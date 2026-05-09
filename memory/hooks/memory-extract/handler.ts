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

const handler = async (event) => {
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
  
  // Get sender info for attribution
  const senderName = ctx.senderName ?? "unknown";
  const senderId = ctx.senderId ?? "";  // Phone number or UUID for unique matching
  const isGroup = ctx.isGroup ?? false;
  
  console.info('[memory-extract] Processing message', {
    sender: senderName,
    senderId: senderId ? senderId.substring(0, 8) + '...' : 'none',
    isGroup,
    messageLength: rawBody.length,
    messagePreview: rawBody.substring(0, 80) + (rawBody.length > 80 ? '...' : '')
  });
  
  // Run extraction via stdin pipe — never pass untrusted message text as shell args (#155)
  // LLM extracts every message directly via process-input.sh (#165)
  const scriptPath = join(os.homedir(), '.openclaw', 'scripts', 'process-input.sh');

  // Store the full sessionKey as the source identifier — it's the canonical session reference
  // When chat logs move to DB (#170), this maps directly to the session record
  const sessionId = event.sessionKey ?? '';
  const messageTimestamp = new Date().toISOString();  // Current time as extraction timestamp

  // Resolve DB-level channel transcript / session FK ids (C1 fix — #170).
  // OpenClaw may populate these in ctx when the channel plugin has already persisted
  // the message. When they are absent (real-time path before batch ingest), we do a
  // lightweight upsert here so entity_facts always has valid FK pointers.
  let channelTranscriptId = String(ctx.channelTranscriptId ?? ctx.channel_transcript_id ?? '');
  let channelSessionId = String(ctx.channelSessionId ?? ctx.channel_session_id ?? '');

  if (!channelTranscriptId || channelTranscriptId === '0') {
    try {
      // Derive provider from chat_id format
      const chatId = String(ctx.conversationId ?? ctx.chatId ?? ctx.chat_id ?? '');
      let provider = String(ctx.provider ?? ctx.channelId ?? 'openclaw');
      if (provider === 'openclaw') {
        // Derive provider from chat_id format when ctx.provider is not set
        if (chatId.startsWith('channel:')) provider = 'discord';
        else if (chatId.startsWith('group:') || chatId.startsWith('+')) provider = 'signal';
      }

      const externalChatId = chatId || sessionId || 'unknown';
      const externalMessageId = String(ctx.messageId ?? ctx.message_id ?? '');
      const isGroupBool = Boolean(ctx.isGroup ?? false);
      const chatType = isGroupBool ? 'group' : 'direct';
      const groupSubject = String(ctx.channelName ?? ctx.groupSubject ?? ctx.group_subject ?? '');
      const groupSpace = String(ctx.guildId ?? ctx.groupSpace ?? ctx.group_space ?? '');
      const senderTag = String(ctx.senderTag ?? ctx.sender_tag ?? '');

      // Only attempt upsert when psql is available and we have minimal identifying info
      if (externalMessageId || rawBody.length > 0) {
        // Upsert session row
        const sessArgs = [
          'nova_memory', '-t', '-A', '-c',
          `INSERT INTO channel_sessions (session_key, agent_id, provider, external_chat_id, chat_type` +
          (groupSubject ? ', group_subject, title' : '') +
          (groupSpace ? ', group_space_id' : '') +
          `) VALUES (` +
          `'${sessionId.replace(/'/g, "''")}', 'main', ` +
          `'${provider.replace(/'/g, "''")}', ` +
          `'${externalChatId.replace(/'/g, "''")}', ` +
          `'${chatType}'` +
          (groupSubject ? `, '${groupSubject.replace(/'/g, "''")}', '${groupSubject.replace(/'/g, "''")}' ` : '') +
          (groupSpace ? `, '${groupSpace.replace(/'/g, "''")}' ` : '') +
          `) ON CONFLICT (provider, external_chat_id, COALESCE(external_thread_id, '')) DO UPDATE SET updated_at = NOW() RETURNING id;`
        ];

        const { stdout: sessOut } = await execFileAsync('psql', sessArgs).catch(() => ({ stdout: '' }));
        const resolvedSessionId = sessOut.trim();
        if (resolvedSessionId && /^\d+$/.test(resolvedSessionId)) {
          channelSessionId = resolvedSessionId;
        }

        // Upsert transcript row when we have a session and a message id or can derive one
        if (channelSessionId) {
          const msgId = externalMessageId || `${messageTimestamp}_rt`;
          const contentSnippet = rawBody.substring(0, 65535).replace(/'/g, "''");
          const senderNameEsc = senderName.replace(/'/g, "''");
          const senderIdEsc = senderId.replace(/'/g, "''");
          const senderTagEsc = senderTag.replace(/'/g, "''");

          const txArgs = [
            'nova_memory', '-t', '-A', '-c',
            `INSERT INTO channel_transcripts (session_id, external_message_id, timestamp, role, content` +
            (senderId ? ', sender_id' : '') +
            (senderName && senderName !== 'unknown' ? ', sender_name' : '') +
            (senderTag ? ', sender_tag' : '') +
            `) VALUES (` +
            `${channelSessionId}, '${msgId.replace(/'/g, "''")}', ` +
            `'${messageTimestamp}', 'user', '${contentSnippet}'` +
            (senderId ? `, '${senderIdEsc}'` : '') +
            (senderName && senderName !== 'unknown' ? `, '${senderNameEsc}'` : '') +
            (senderTag ? `, '${senderTagEsc}'` : '') +
            `) ON CONFLICT (session_id, external_message_id) DO NOTHING RETURNING id;`
          ];

          const { stdout: txOut } = await execFileAsync('psql', txArgs).catch(() => ({ stdout: '' }));
          const resolvedTranscriptId = txOut.trim();
          if (resolvedTranscriptId && /^\d+$/.test(resolvedTranscriptId)) {
            channelTranscriptId = resolvedTranscriptId;
          }
        }
      }
    } catch (err) {
      console.warn('[memory-extract] Could not upsert channel_transcripts for FK wiring', {
        error: (err as Error).message
      });
    }
  }

  const child = spawn(scriptPath, [], {
    stdio: ['pipe', 'pipe', 'pipe'],
    env: {
      ...process.env,
      SENDER_NAME: senderName,
      SENDER_ID: senderId,
      IS_GROUP: String(isGroup),
      SOURCE_SESSION_ID: sessionId,
      SOURCE_TIMESTAMP: messageTimestamp,
      // DB-level source pointers for entity_facts FK columns (may be empty string when not yet ingested)
      SOURCE_CHANNEL_TRANSCRIPT_ID: channelTranscriptId,
      SOURCE_CHANNEL_SESSION_ID: channelSessionId
    }
  });

  child.stdin.write(rawBody);
  child.stdin.end();

  child.on('close', (code) => {
    if (code !== 0) {
      console.error('[memory-extract] Extraction failed', {
        sender: senderName,
        exitCode: code
      });
    } else {
      console.info('[memory-extract] Extraction complete', {
        sender: senderName
      });
    }
  });

  child.on('error', (err) => {
    console.error('[memory-extract] Spawn error', {
      sender: senderName,
      error: err.message
    });
  });
};

export default handler;
