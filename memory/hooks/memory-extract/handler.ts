import { spawn, execFile } from "child_process";
import { join } from "path";
import { promisify } from "util";
import * as os from "os";

const execFileAsync = promisify(execFile);

interface ActivityState {
  activeMinutesToday: number;
  lastActiveAt: number | null;
  todayDate: string | null;
  userMessages: number;
  heartbeats: number;
}

// In-memory activity tracking (no longer persisted to file)
let activityState: ActivityState = {
  activeMinutesToday: 0,
  lastActiveAt: null,
  todayDate: null,
  userMessages: 0,
  heartbeats: 0
};

function logActivity(isUserMessage: boolean) {
  const today = new Date().toISOString().split('T')[0];
  const now = Date.now();

  // Reset if new day
  if (activityState.todayDate !== today) {
    console.info('[memory-extract] New day detected, resetting activity counters', {
      previousDate: activityState.todayDate,
      newDate: today,
      previousUserMessages: activityState.userMessages,
      previousHeartbeats: activityState.heartbeats,
      previousActiveMinutes: activityState.activeMinutesToday
    });
    activityState = {
      activeMinutesToday: 0,
      lastActiveAt: null,
      todayDate: today,
      userMessages: 0,
      heartbeats: 0
    };
  }

  if (isUserMessage) {
    activityState.userMessages++;
    if (activityState.lastActiveAt) {
      const gap = (now - activityState.lastActiveAt) / 60000;
      if (gap <= 5) {
        activityState.activeMinutesToday += gap;
      }
    }
    activityState.lastActiveAt = now;
  } else {
    activityState.heartbeats++;
  }

  console.debug('[memory-extract] Activity update', {
    isUserMessage,
    activeMinutesToday: activityState.activeMinutesToday.toFixed(2),
    userMessages: activityState.userMessages,
    heartbeats: activityState.heartbeats,
    date: activityState.todayDate
  });
}

// ---------------------------------------------------------------------------
// Issue #485 constants
// ---------------------------------------------------------------------------
const EXTRACTION_TIMEOUT_MS = 30000;
const KILL_GRACE_MS = 5000;
const PIPE_TAIL_CAP_BYTES = 16384;

// ---------------------------------------------------------------------------
// Issue #485 helpers
// ---------------------------------------------------------------------------

/**
 * Attach a data handler to a child-process stream that retains only the last
 * `cap` bytes. Reading continuously prevents pipe stalls when the child writes
 * more than the OS pipe buffer can hold.
 */
function attachTailBuffer(stream: any, cap: number): () => Buffer {
  const chunks: Buffer[] = [];
  let total = 0;

  stream.on('data', (chunk: Buffer) => {
    chunks.push(chunk);
    total += chunk.length;
    while (total > cap && chunks.length > 0) {
      const first = chunks[0];
      const over = total - cap;
      if (over >= first.length) {
        chunks.shift();
        total -= first.length;
      } else {
        chunks[0] = first.subarray(over);
        total -= over;
      }
    }
  });

  return () => {
    if (chunks.length === 0) {
      return Buffer.alloc(0);
    }
    const tail = Buffer.concat(chunks);
    return tail.length > cap ? tail.subarray(-cap) : tail;
  };
}

function tailToString(tail: Buffer): string {
  // Node's utf8 decoder replaces incomplete sequences with U+FFFD automatically.
  return tail.toString('utf8');
}

function truncateSenderId(senderId: string): string {
  if (!senderId) return 'none';
  return senderId.substring(0, 8) + '...';
}

/**
 * Log a psql failure without leaking connection secrets. The error object from
 * execFile may contain the full command line, so we only log `.message`.
 */
function logPsqlError(site: string, err: any): { stdout: string } {
  const message = err?.message ?? String(err);
  console.error('[memory-extract] psql upsert failed', {
    site,
    error: message
  });
  return { stdout: '' };
}

/**
 * Insert a dead-letter row for a failed extraction. If a channel transcript FK
 * is available, store that and leave `content` NULL. Otherwise fall back to
 * storing the raw message body so the failure is still replayable.
 */
async function insertExtractionFailure(args: {
  channelTranscriptId: string;
  sessionKey: string;
  senderName: string;
  senderId: string;
  content: string;
  stderrTail: string;
  stdoutTail: string;
  exitCode: number | null;
  failureReason: string;
}) {
  const txId = args.channelTranscriptId && args.channelTranscriptId !== '0'
    ? args.channelTranscriptId
    : '';

  // If we have a transcript FK, do not duplicate the body; rely on the FK.
  // If not, store the body as a fallback (same 65535 cap used by the
  // channel_transcripts upsert path).
  const bodyForFallback = txId ? '' : args.content.substring(0, 65535);

  const sessionKeyEsc = args.sessionKey.replace(/'/g, "''");
  const senderNameEsc = args.senderName.replace(/'/g, "''");
  const senderIdEsc = args.senderId.replace(/'/g, "''");
  const stderrEsc = args.stderrTail.replace(/'/g, "''");
  const stdoutEsc = args.stdoutTail.replace(/'/g, "''");
  const reasonEsc = args.failureReason.replace(/'/g, "''");
  const bodyEsc = bodyForFallback.replace(/'/g, "''");

  const txIdVal = txId ? txId : 'NULL';
  const bodyVal = bodyForFallback ? `'${bodyEsc}'` : 'NULL';
  const exitCodeVal = args.exitCode === null ? 'NULL' : String(args.exitCode);

  const sql = `
    INSERT INTO extraction_failures (
      channel_transcript_id, session_key, sender_name, sender_id,
      content, stderr_tail, stdout_tail, exit_code, failure_reason
    ) VALUES (
      ${txIdVal}, '${sessionKeyEsc}', '${senderNameEsc}', '${senderIdEsc}',
      ${bodyVal}, '${stderrEsc}', '${stdoutEsc}', ${exitCodeVal}, '${reasonEsc}'
    );
  `;

  try {
    await execFileAsync('psql', ['nova_memory', '-t', '-A', '-c', sql]);
  } catch (err) {
    console.error('[memory-extract] Failed to insert extraction_failure', {
      error: (err as Error).message,
      failureReason: args.failureReason
    });
  }
}

const handler = async (event: any) => {
  try {
    console.info('[memory-extract] Hook triggered', {
      eventType: event.type,
      eventAction: event.action
    });

    // Track activity for cost/hour calculations
    if (event.type === "message") {
      const ctx = event.context ?? {};
      const rawBody = ctx.content ?? ctx.rawBody ?? ctx.RawBody ?? ctx.message ?? ctx.Body ?? "";
      const isHeartbeat = rawBody.includes("HEARTBEAT") || rawBody.includes("DASHBOARD UPDATE") || rawBody.startsWith("System: [");
      logActivity(!isHeartbeat);
    }

    if (event.type !== "message" || event.action !== "received") {
      console.debug('[memory-extract] Skipping non-received message event');
      return;
    }

    const ctx = event.context ?? {};
    const rawBody = ctx.content ?? ctx.rawBody ?? ctx.RawBody ?? ctx.message ?? ctx.Body ?? "";

    if (!rawBody || rawBody.trim().length < 10) {
      console.debug('[memory-extract] Skipping short or empty message');
      return;
    }

    // Skip commands
    if (rawBody.startsWith("/")) {
      console.debug('[memory-extract] Skipping command message');
      return;
    }

    // Get sender info for attribution — canonical location is ctx.metadata
    const meta = (ctx.metadata ?? {}) as Record<string, any>;
    // Canonical field paths per MessageReceivedHookContext spec (#184)
    const senderName = meta.senderName ?? ctx.from ?? "unknown";
    const senderId = meta.senderId ?? "";  // Phone number or UUID for unique matching
    const isGroup = meta.isGroup ?? ctx.isGroup ?? false;

    console.info('[memory-extract] Processing message', {
      sender: senderName,
      senderId: senderId ? senderId.substring(0, 8) + '...' : 'none',
      isGroup,
      messageLength: rawBody.length,
      messagePreview: rawBody.substring(0, 80) + (rawBody.length > 80 ? '...' : '')
    });

    // Run extraction via stdin pipe — never pass untrusted message text as shell args (#155)
    // LLM extracts every message directly via process-input.sh (#165)
    // Updated to call Python extraction pipeline (#112)
    // Env override allows tests to point at a mock script without touching prod path.
    const scriptPath = process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE
      || join(os.homedir(), '.openclaw', 'scripts', 'extract_memories.py');

    // Store the full sessionKey as the source identifier — it's the canonical session reference
    // When chat logs move to DB (#170), this maps directly to the session record
    const sessionKey = event.sessionKey ?? '';
    const messageTimestamp = new Date().toISOString();  // Current time as extraction timestamp

    // Resolve DB-level channel transcript / session FK ids (C1 fix — #170).
    // OpenClaw may populate these in ctx when the channel plugin has already persisted
    // the message. When they are absent (real-time path before batch ingest), we do a
    // lightweight upsert here so entity_facts always has valid FK pointers.
    let channelTranscriptId = String(ctx.channelTranscriptId ?? ctx.channel_transcript_id ?? '');
    let channelSessionId = String(ctx.channelSessionId ?? ctx.channel_session_id ?? '');

    // These identifiers are needed for FK recovery if the transcript upsert returns empty
    // because the row already exists (ON CONFLICT DO NOTHING).
    let externalMessageId = '';
    let derivedMessageId = '';

    if (!channelTranscriptId || channelTranscriptId === '0') {
      try {
        // Derive provider from chat_id format — read from metadata first
        const chatId = String(ctx.conversationId ?? meta.conversationId ?? ctx.chatId ?? ctx.chat_id ?? '');
        let provider = String(meta.provider ?? ctx.provider ?? ctx.channelId ?? 'openclaw');
        if (provider === 'openclaw') {
          // Derive provider from chat_id format when ctx.provider is not set
          if (chatId.startsWith('channel:')) provider = 'discord';
          else if (chatId.startsWith('group:') || chatId.startsWith('+')) provider = 'signal';
        }

        const externalChatId = chatId || sessionKey || 'unknown';
        externalMessageId = String(ctx.messageId ?? meta.messageId ?? ctx.message_id ?? '');
        const isGroupBool = Boolean(meta.isGroup ?? ctx.isGroup ?? false);
        const chatType = isGroupBool ? 'group' : 'direct';
        const groupSubject = String(meta.channelName ?? ctx.channelName ?? ctx.groupSubject ?? ctx.group_subject ?? '');
        const groupSpace = String(meta.guildId ?? ctx.guildId ?? ctx.groupSpace ?? ctx.group_space ?? '');
        const senderTag = String(meta.senderTag ?? ctx.senderTag ?? ctx.sender_tag ?? '');
        const senderUsername = String(meta.senderUsername ?? ctx.senderUsername ?? '');

        // Only attempt upsert when psql is available and we have minimal identifying info
        if (externalMessageId || rawBody.length > 0) {
          // Upsert session row
          const sessArgs = [
            'nova_memory', '-t', '-A', '-c',
            `INSERT INTO channel_sessions (session_key, agent_id, provider, external_chat_id, chat_type` +
            (groupSubject ? ', group_subject, title' : '') +
            (groupSpace ? ', group_space_id' : '') +
            `) VALUES (` +
            `'${sessionKey.replace(/'/g, "''")}', 'main', ` +
            `'${provider.replace(/'/g, "''")}', ` +
            `'${externalChatId.replace(/'/g, "''")}', ` +
            `'${chatType}'` +
            (groupSubject ? `, '${groupSubject.replace(/'/g, "''")}', '${groupSubject.replace(/'/g, "''")}' ` : '') +
            (groupSpace ? `, '${groupSpace.replace(/'/g, "''")}' ` : '') +
            `) ON CONFLICT (provider, external_chat_id, COALESCE(external_thread_id, '')) DO UPDATE SET updated_at = NOW() RETURNING id;`
          ];

          const { stdout: sessOut } = await execFileAsync('psql', sessArgs)
            .catch((err) => logPsqlError('session-upsert', err));
          // psql -t -A may include 'INSERT 0 1' status line — extract first numeric line
          const resolvedSessionId = (sessOut.match(/^(\d+)/m) ?? [])[1] ?? '';
          if (resolvedSessionId) {
            channelSessionId = resolvedSessionId;
          }

          // Upsert transcript row when we have a session and a message id or can derive one
          if (channelSessionId) {
            derivedMessageId = externalMessageId || `${messageTimestamp}_rt`;
            const contentSnippet = rawBody.substring(0, 65535).replace(/'/g, "''");
            const senderNameEsc = senderName.replace(/'/g, "''");
            const senderIdEsc = senderId.replace(/'/g, "''");
            const senderTagEsc = senderTag.replace(/'/g, "''");
            const senderUsernameEsc = senderUsername.replace(/'/g, "''");

            const txArgs = [
              'nova_memory', '-t', '-A', '-c',
              `INSERT INTO channel_transcripts (session_id, external_message_id, timestamp, role, content` +
              (senderId ? ', sender_id' : '') +
              (senderName && senderName !== 'unknown' ? ', sender_name' : '') +
              (senderTag ? ', sender_tag' : '') +
              (senderUsername ? ', sender_username' : '') +
              `) VALUES (` +
              `${channelSessionId}, '${derivedMessageId.replace(/'/g, "''")}', ` +
              `'${messageTimestamp}', 'user', '${contentSnippet}'` +
              (senderId ? `, '${senderIdEsc}'` : '') +
              (senderName && senderName !== 'unknown' ? `, '${senderNameEsc}'` : '') +
              (senderTag ? `, '${senderTagEsc}'` : '') +
              (senderUsername ? `, '${senderUsernameEsc}'` : '') +
              `) ON CONFLICT (session_id, external_message_id) DO NOTHING RETURNING id;`
            ];

            const { stdout: txOut } = await execFileAsync('psql', txArgs)
              .catch((err) => logPsqlError('transcript-upsert', err));
            // psql -t -A may include 'INSERT 0 1' status line — extract first numeric line
            const resolvedTranscriptId = (txOut.match(/^(\d+)/m) ?? [])[1] ?? '';
            if (resolvedTranscriptId) {
              channelTranscriptId = resolvedTranscriptId;
            }

            // C1 recovery: ON CONFLICT DO NOTHING returns no id when the row already
            // exists. Recover the real transcript id with a follow-up SELECT before
            // falling back to body storage.
            if (!channelTranscriptId && channelSessionId && derivedMessageId) {
              const lookupArgs = [
                'nova_memory', '-t', '-A', '-c',
                `SELECT id FROM channel_transcripts WHERE session_id = ${channelSessionId} AND external_message_id = '${derivedMessageId.replace(/'/g, "''")}' LIMIT 1;`
              ];
              const { stdout: lookupOut } = await execFileAsync('psql', lookupArgs)
                .catch((err) => logPsqlError('transcript-lookup', err));
              const foundId = (lookupOut.match(/^(\d+)/m) ?? [])[1] ?? '';
              if (foundId) {
                channelTranscriptId = foundId;
              }
            }
          }
        }
      } catch (err) {
        console.warn('[memory-extract] Could not upsert channel_transcripts for FK wiring', {
          error: (err as Error).message
        });
      }
    }

    // Allow tests to override the python interpreter and timeout without
    // modifying production defaults or requiring module reload.
    const pythonCmd = process.env.EXTRACTION_PYTHON_CMD_OVERRIDE || 'python3';
    const timeoutMs = (() => {
      const raw = process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
      if (!raw) return EXTRACTION_TIMEOUT_MS;
      const n = Number(raw);
      return Number.isFinite(n) && n > 0 ? n : EXTRACTION_TIMEOUT_MS;
    })();

    const child = spawn(pythonCmd, [scriptPath], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: {
        ...process.env,
        SENDER_NAME: senderName,
        SENDER_ID: senderId,
        IS_GROUP: String(isGroup),
        SOURCE_SESSION_ID: sessionKey,
        SOURCE_TIMESTAMP: messageTimestamp,
        // DB-level source pointers for entity_facts FK columns (may be empty string when not yet ingested)
        SOURCE_CHANNEL_TRANSCRIPT_ID: channelTranscriptId,
        SOURCE_CHANNEL_SESSION_ID: channelSessionId
      }
    });

    const getStderrTail = attachTailBuffer(child.stderr, PIPE_TAIL_CAP_BYTES);
    const getStdoutTail = attachTailBuffer(child.stdout, PIPE_TAIL_CAP_BYTES);

    child.stdin.write(rawBody);
    child.stdin.end();

    let timeoutHandle: any = null;
    let didTimeout = false;
    let failureRecorded = false;

    const recordFailure = async (reason: string, exitCode: number | null) => {
      if (failureRecorded) return;
      failureRecorded = true;
      await insertExtractionFailure({
        channelTranscriptId,
        sessionKey,
        senderName,
        senderId,
        content: rawBody,
        stderrTail: tailToString(getStderrTail()),
        stdoutTail: tailToString(getStdoutTail()),
        exitCode,
        failureReason: reason
      });
    };

    timeoutHandle = setTimeout(() => {
      didTimeout = true;
      console.error('[memory-extract] Extraction timed out, terminating child', {
        sender: senderName,
        senderId: truncateSenderId(senderId)
      });
      child.kill('SIGTERM');
      setTimeout(() => {
        if (!child.killed) {
          console.error('[memory-extract] Extraction child did not terminate gracefully, forcing SIGKILL', {
            sender: senderName,
            senderId: truncateSenderId(senderId)
          });
          child.kill('SIGKILL');
        }
      }, KILL_GRACE_MS);
    }, timeoutMs);

    child.on('close', async (code, signal) => {
      if (timeoutHandle) {
        clearTimeout(timeoutHandle);
        timeoutHandle = null;
      }

      if (didTimeout) {
        console.error('[memory-extract] Extraction failed', {
          sender: senderName,
          senderId: truncateSenderId(senderId),
          exitCode: code,
          signal,
          failureReason: 'timeout',
          stderrTail: tailToString(getStderrTail())
        });
        await recordFailure('timeout', null);
      } else if (code !== 0) {
        console.error('[memory-extract] Extraction failed', {
          sender: senderName,
          senderId: truncateSenderId(senderId),
          exitCode: code,
          signal,
          failureReason: 'nonzero_exit',
          stderrTail: tailToString(getStderrTail())
        });
        await recordFailure('nonzero_exit', code);
      } else {
        console.info('[memory-extract] Extraction complete', {
          sender: senderName,
          senderId: truncateSenderId(senderId)
        });
      }
    });

    child.on('error', async (err) => {
      if (timeoutHandle) {
        clearTimeout(timeoutHandle);
        timeoutHandle = null;
      }
      console.error('[memory-extract] Spawn error', {
        sender: senderName,
        senderId: truncateSenderId(senderId),
        failureReason: 'spawn_error',
        error: err.message
      });
      await recordFailure('spawn_error', null);
    });
  } catch (handlerErr) {
    // Hook contract: handlers must not throw. Log and swallow so other handlers run.
    console.error('[memory-extract] Unexpected handler error', {
      error: (handlerErr as Error).message
    });
  }
};

export default handler;
