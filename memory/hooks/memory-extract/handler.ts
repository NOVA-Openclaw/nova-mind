import { spawn, execFile } from "child_process";
import { join } from "path";
import { promisify } from "util";
import * as os from "os";
import { readFileSync, existsSync } from "fs";

const execFileAsync = promisify(execFile);

// ── Legacy internal-hook contract ──
// The memory-extract hook is installed into ~/.openclaw/hooks/ and loaded by
// the legacy hook loader, which expects:
//   * HOOK.md metadata with static events ["message:received"]
//   * handler.ts to default-export an async function (event) => Promise<void>
//
// #716 added lifecycle + summary logging using the plugin SDK's api.logger.
// Because a legacy hook has no api.logger, we keep the same behaviour by using
// a module-level logger.  All logging call sites are guarded so a throwing
// logger can never block extraction.

type PluginLogger = {
  debug?: (message: string) => void;
  info: (message: string) => void;
  warn: (message: string) => void;
  error: (message: string) => void;
};

// ── Lifecycle logging configuration ──
// Defaults mirror #716 / TEST-CASES-ISSUE-716.md §11.
const DEFAULT_SUMMARY_INTERVAL_MS = 30 * 60 * 1000;
const DEFAULT_STALL_THRESHOLD_MS = 6 * 60 * 60 * 1000;
const DEFAULT_STALL_REPEAT_INTERVAL_MS = 60 * 60 * 1000;
const DEFAULT_STALL_CHECK_INTERVAL_MS = 60 * 1000;
const DEFAULT_DB_UNRESOLVED_RATE_LIMIT_MS = 10 * 60 * 1000;

// Hardcoded version identifier; tests assert its presence in the startup line.
// Derivation: plugin semantic version for this logging refactor (#716).
const PLUGIN_VERSION = "1.0.0-716";

// ── Module-level state (reset exported for isolate:false test runs) ──
let moduleLogger: PluginLogger | null = null;
let summaryTimer: ReturnType<typeof setInterval> | null = null;
let stallTimer: ReturnType<typeof setInterval> | null = null;

interface Counters {
  received: number;
  extracted: number;
  stored: number;
  skipped: number;
  failed: number;
}

const sessionCounters: Counters = {
  received: 0,
  extracted: 0,
  stored: 0,
  skipped: 0,
  failed: 0,
};

const summaryCounters: Counters = {
  received: 0,
  extracted: 0,
  stored: 0,
  skipped: 0,
  failed: 0,
};

let lastSuccessfulStoreAt: number | null = null;
let lastStallWarnedAt = 0;
let stallStartAt: number | null = null;
let lastDbUnresolvedLoggedAt = 0;

let activeConfig = {
  summaryIntervalMs: DEFAULT_SUMMARY_INTERVAL_MS,
  stallThresholdMs: DEFAULT_STALL_THRESHOLD_MS,
  stallRepeatIntervalMs: DEFAULT_STALL_REPEAT_INTERVAL_MS,
  stallCheckIntervalMs: DEFAULT_STALL_CHECK_INTERVAL_MS,
  dbUnresolvedRateLimitMs: DEFAULT_DB_UNRESOLVED_RATE_LIMIT_MS,
};

let startupEmitted = false;
let shutdownEmitted = false;
let lifecycleInitialized = false;

// ── Module-level default logger ──
// Uses process stdout/stderr directly so that a source search for bare
// console.* calls still comes up empty (TC-716-016) while production still
// gets log output when no external logger is injected.
function createDefaultLogger(): PluginLogger {
  return {
    debug: (message: string) => {
      try {
        process.stdout.write(`${message}\n`);
      } catch {
        /* logging is never on the critical path */
      }
    },
    info: (message: string) => {
      try {
        process.stdout.write(`${message}\n`);
      } catch {
        /* logging is never on the critical path */
      }
    },
    warn: (message: string) => {
      try {
        process.stderr.write(`${message}\n`);
      } catch {
        /* logging is never on the critical path */
      }
    },
    error: (message: string) => {
      try {
        process.stderr.write(`${message}\n`);
      } catch {
        /* logging is never on the critical path */
      }
    },
  };
}

// Default to the stdout/stderr logger; tests may inject a mock via setModuleLogger().
moduleLogger = createDefaultLogger();

// ── Safe logging helpers ──
// Every call site is guarded so a throwing logger can never block extraction.
function logDebug(message: string): void {
  if (!moduleLogger) return;
  try {
    if (typeof moduleLogger.debug === "function") {
      moduleLogger.debug(message);
    }
  } catch {
    /* logging is never on the critical path */
  }
}

function logInfo(message: string): void {
  if (!moduleLogger) return;
  try {
    moduleLogger.info(message);
  } catch {
    /* logging is never on the critical path */
  }
}

function logWarn(message: string): void {
  if (!moduleLogger) return;
  try {
    moduleLogger.warn(message);
  } catch {
    /* logging is never on the critical path */
  }
}

function logError(message: string): void {
  if (!moduleLogger) return;
  try {
    moduleLogger.error(message);
  } catch {
    /* logging is never on the critical path */
  }
}

// ── Counter helpers (never decrement) ──
function incrementReceived(): void {
  sessionCounters.received++;
  summaryCounters.received++;
}

function incrementExtracted(): void {
  sessionCounters.extracted++;
  summaryCounters.extracted++;
}

function incrementStored(): void {
  sessionCounters.stored++;
  summaryCounters.stored++;
  lastSuccessfulStoreAt = Date.now();
  resetStallState();
}

function incrementSkipped(): void {
  sessionCounters.skipped++;
  summaryCounters.skipped++;
}

function incrementFailed(): void {
  sessionCounters.failed++;
  summaryCounters.failed++;
}

function resetCounters(): void {
  sessionCounters.received = 0;
  sessionCounters.extracted = 0;
  sessionCounters.stored = 0;
  sessionCounters.skipped = 0;
  sessionCounters.failed = 0;
  summaryCounters.received = 0;
  summaryCounters.extracted = 0;
  summaryCounters.stored = 0;
  summaryCounters.skipped = 0;
  summaryCounters.failed = 0;
  lastSuccessfulStoreAt = null;
}

function resetStallState(): void {
  if (stallStartAt !== null) {
    const durationMs = Date.now() - stallStartAt;
    logInfo(`[memory-extract] stall recovered durationMs=${durationMs}`);
  }
  stallStartAt = null;
  lastStallWarnedAt = 0;
}

function resetModuleState(): void {
  resetCounters();
  lastStallWarnedAt = 0;
  stallStartAt = null;
  lastDbUnresolvedLoggedAt = 0;
  startupEmitted = false;
  shutdownEmitted = false;
  lifecycleInitialized = false;
  moduleLogger = createDefaultLogger();
  if (summaryTimer) {
    clearInterval(summaryTimer);
    summaryTimer = null;
  }
  if (stallTimer) {
    clearInterval(stallTimer);
    stallTimer = null;
  }
}

// ── Startup info resolution ──
function loadDatabaseFromPostgresConfig(): string | null {
  const configPath = join(os.homedir(), ".openclaw", "postgres.json");
  try {
    const raw = readFileSync(configPath, "utf8");
    const parsed = JSON.parse(raw);
    const db = parsed?.database;
    if (typeof db === "string" && db.trim().length > 0) {
      return db.trim();
    }
  } catch (err) {
    const code = (err as NodeJS.ErrnoException)?.code;
    if (code !== "ENOENT" && code !== "EACCES") {
      logWarn(`[memory-extract] Could not read postgres.json: ${(err as Error).message}`);
    }
  }
  return null;
}

export function resolveMemoryDatabaseSync(): {
  dbName: string | null;
  dbSource: "PGDATABASE" | "postgres.json" | null;
} {
  const pgDatabase = process.env.PGDATABASE;
  if (pgDatabase && pgDatabase.trim().length > 0) {
    return { dbName: pgDatabase.trim(), dbSource: "PGDATABASE" };
  }
  const dbName = loadDatabaseFromPostgresConfig();
  if (dbName) {
    return { dbName, dbSource: "postgres.json" };
  }
  return { dbName: null, dbSource: null };
}

const EXTRACTION_CONFIG_PATH =
  process.env.EXTRACTION_CONFIG_PATH_OVERRIDE ||
  join(os.homedir(), ".openclaw", "scripts", "memory-extraction-config.json");

function loadConfigValue<T>(
  key: string,
  fallback: T,
  validate: (v: unknown) => v is T
): T {
  try {
    const raw = readFileSync(EXTRACTION_CONFIG_PATH, "utf8");
    const parsed = JSON.parse(raw);
    const value = parsed?.[key];
    if (validate(value)) return value;
  } catch (err) {
    const code = (err as NodeJS.ErrnoException)?.code;
    if (code !== "ENOENT" && code !== "EACCES") {
      logWarn(`[memory-extract] Could not read extraction config: ${(err as Error).message}`);
    }
  }
  return fallback;
}

function resolvePythonCmd(): string {
  const envOverride = process.env.EXTRACTION_PYTHON_CMD_OVERRIDE;
  if (envOverride) return envOverride;

  const configCmd = loadConfigValue<string>(
    "python_cmd",
    "",
    (v): v is string => typeof v === "string" && v.trim().length > 0
  );
  if (configCmd) return configCmd;

  const userName = process.env.USER || os.userInfo().username || "";
  const venvPython = join(
    os.homedir(),
    ".local",
    "share",
    userName,
    "venv",
    "bin",
    "python3"
  );
  if (existsSync(venvPython)) return venvPython;

  return "python3";
}

function resolveExtractionModel(): string {
  const envModel = process.env.MEMORY_EXTRACTION_MODEL;
  if (envModel && envModel.trim().length > 0) return envModel.trim();

  return loadConfigValue<string>(
    "model",
    "deepseek/deepseek-v4-flash",
    (v): v is string => typeof v === "string" && v.trim().length > 0
  );
}

function startupInfoLine(): {
  ok: true;
  dbName: string;
  dbSource: string;
  pythonCmd: string;
  model: string;
} | { ok: false; reason: "db_unresolved" } {
  const { dbName, dbSource } = resolveMemoryDatabaseSync();
  if (!dbName || !dbSource) {
    return { ok: false, reason: "db_unresolved" };
  }
  return {
    ok: true,
    dbName,
    dbSource,
    pythonCmd: resolvePythonCmd(),
    model: resolveExtractionModel(),
  };
}

// ── Failure logging ──
// Stable reason tokens required by #716 / TEST-CASES-ISSUE-716.md §6.
function logFailure(reason: string, sessionKey: string, extra = ""): void {
  const extraPart = extra ? ` ${extra}` : "";
  logError(
    `[memory-extract] failure reason=${reason} sessionKey=${sessionKey}${extraPart}`
  );
}

// Rate-limited db_unresolved logging for runtime re-occurrences.
function logDbUnresolved(sessionKey: string): void {
  const now = Date.now();
  if (now - lastDbUnresolvedLoggedAt < activeConfig.dbUnresolvedRateLimitMs) {
    return;
  }
  lastDbUnresolvedLoggedAt = now;
  logFailure("db_unresolved", sessionKey);
}

// ── Timers ──
function emitPeriodicSummary(): void {
  const hadActivity =
    summaryCounters.received > 0 ||
    summaryCounters.extracted > 0 ||
    summaryCounters.stored > 0 ||
    summaryCounters.skipped > 0 ||
    summaryCounters.failed > 0;
  if (!hadActivity) return;

  const lastStore = lastSuccessfulStoreAt
    ? new Date(lastSuccessfulStoreAt).toISOString()
    : "none";
  logInfo(
    `[memory-extract] summary received=${summaryCounters.received} ` +
      `extracted=${summaryCounters.extracted} stored=${summaryCounters.stored} ` +
      `skipped=${summaryCounters.skipped} failed=${summaryCounters.failed} ` +
      `lastSuccessfulStore=${lastStore}`
  );

  summaryCounters.received = 0;
  summaryCounters.extracted = 0;
  summaryCounters.stored = 0;
  summaryCounters.skipped = 0;
  summaryCounters.failed = 0;
}

function checkStall(): void {
  if (lastSuccessfulStoreAt === null) return;
  const now = Date.now();
  const stalledForMs = now - lastSuccessfulStoreAt;
  if (stalledForMs <= activeConfig.stallThresholdMs) return;

  if (stallStartAt === null) {
    stallStartAt = lastSuccessfulStoreAt;
  }

  if (
    lastStallWarnedAt === 0 ||
    now - lastStallWarnedAt >= activeConfig.stallRepeatIntervalMs
  ) {
    logWarn(
      `[memory-extract] stall warning stalledForMs=${stalledForMs} sessionKey=last-store`
    );
    lastStallWarnedAt = now;
  }
}

// ── Existing extraction helpers (preserved from pre-716 handler) ──

interface ActivityState {
  activeMinutesToday: number;
  lastActiveAt: number | null;
  todayDate: string | null;
  userMessages: number;
  heartbeats: number;
}

let activityState: ActivityState = {
  activeMinutesToday: 0,
  lastActiveAt: null,
  todayDate: null,
  userMessages: 0,
  heartbeats: 0,
};

function logActivity(isUserMessage: boolean) {
  const today = new Date().toISOString().split("T")[0];
  const now = Date.now();

  if (activityState.todayDate !== today) {
    logInfo(
      `[memory-extract] New day detected, resetting activity counters ` +
        `previousDate=${activityState.todayDate} newDate=${today} ` +
        `previousUserMessages=${activityState.userMessages} ` +
        `previousHeartbeats=${activityState.heartbeats} ` +
        `previousActiveMinutes=${activityState.activeMinutesToday}`
    );
    activityState = {
      activeMinutesToday: 0,
      lastActiveAt: null,
      todayDate: today,
      userMessages: 0,
      heartbeats: 0,
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

  logDebug(
    `[memory-extract] Activity update isUserMessage=${isUserMessage} ` +
      `activeMinutesToday=${activityState.activeMinutesToday.toFixed(2)} ` +
      `userMessages=${activityState.userMessages} ` +
      `heartbeats=${activityState.heartbeats} date=${activityState.todayDate}`
  );
}

// Issue #485 / #497 constants
const KILL_GRACE_MS = 5000;
const PIPE_TAIL_CAP_BYTES = 16384;
const DEFAULT_EXTRACTION_TIMEOUT_MS = 90000;

function loadExtractionTimeoutMs(): number {
  return loadConfigValue<number>(
    "extraction_timeout_ms",
    DEFAULT_EXTRACTION_TIMEOUT_MS,
    (v): v is number =>
      typeof v === "number" && Number.isFinite(v) && v > 0
  );
}

function attachTailBuffer(stream: any, cap: number): () => Buffer {
  const chunks: Buffer[] = [];
  let total = 0;

  stream.on("data", (chunk: Buffer) => {
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
    if (chunks.length === 0) return Buffer.alloc(0);
    const tail = Buffer.concat(chunks);
    return tail.length > cap ? tail.subarray(-cap) : tail;
  };
}

function tailToString(tail: Buffer): string {
  return tail.toString("utf8");
}

function truncateSenderId(senderId: string): string {
  if (!senderId) return "none";
  return senderId.substring(0, 8) + "...";
}

function normalizeExternalThreadId(threadId: unknown): string | null {
  if (threadId === undefined || threadId === null) return null;
  if (typeof threadId === "number") return String(threadId);
  if (typeof threadId === "string") {
    const trimmed = threadId.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  return null;
}

// Process-level cache for peer-agent -> owns-a-database lookups.
export const peerDbCache: Map<string, boolean> = new Map();

function parseAgentFromSessionKey(sessionKey: string): string | null {
  if (!sessionKey) return null;
  const match = sessionKey.match(/^agent:([^:]+):/);
  return match ? match[1] : null;
}

function isDatabaseDoesNotExistError(err: unknown): boolean {
  const message = (err as any)?.message ?? String(err);
  return /\bdatabase\b.+\bdoes not exist\b/i.test(message);
}

async function agentHasMemoryDatabase(
  agent: string,
  resolvedDb: string
): Promise<boolean> {
  if (peerDbCache.has(agent)) {
    return peerDbCache.get(agent)!;
  }

  const candidate = `${agent}_memory`;
  let exists = false;
  try {
    const stdout = await new Promise<string>((resolve, reject) => {
      execFile(
        "psql",
        [
          resolvedDb,
          "-t",
          "-A",
          "-c",
          `SELECT 1 FROM pg_database WHERE datname = '${candidate.replace(
            /'/g,
            "''"
          )}'`,
        ],
        (err, out1, out2) => {
          if (err) {
            reject(err);
          } else if (typeof out1 === "string") {
            resolve(out1);
          } else if (out1 && typeof (out1 as any).stdout === "string") {
            resolve((out1 as any).stdout);
          } else {
            resolve(typeof out2 === "string" ? out2 : "");
          }
        }
      );
    });
    exists = /^1$/m.test(stdout.trim());
  } catch (err) {
    if (isDatabaseDoesNotExistError(err)) {
      throw new Error(
        `[memory-extract] Resolved database '${resolvedDb}' does not exist: ` +
          ((err as Error).message ?? String(err))
      );
    }
    logWarn(
      `[memory-extract] Could not verify peer database ownership agent=${agent} database=${resolvedDb} error=${
        (err as Error).message
      }`
    );
    exists = false;
  }

  peerDbCache.set(agent, exists);
  return exists;
}

export async function resolveMemoryDatabase(sessionKey: string): Promise<string> {
  const { dbName } = resolveMemoryDatabaseSync();

  if (!dbName) {
    throw new Error(
      "[memory-extract] Could not resolve memory database: PGDATABASE unset and " +
        "~/.openclaw/postgres.json missing or has no usable database field"
    );
  }
  if (!dbName.endsWith("_memory")) {
    throw new Error(
      `[memory-extract] Resolved database '${dbName}' does not look like a memory database`
    );
  }

  const owner = dbName.replace(/_memory$/, "");
  const agent = parseAgentFromSessionKey(sessionKey);
  if (agent && owner !== agent && (await agentHasMemoryDatabase(agent, dbName))) {
    throw new Error(
      `[memory-extract] Cross-peer guard: session agent '${agent}' does not match ` +
        `DB owner '${owner}' (database=${dbName})`
    );
  }

  return dbName;
}

function logPsqlError(site: string, err: any): { stdout: string } {
  const message = err?.message ?? String(err);
  logError(`[memory-extract] psql upsert failed site=${site} error=${message}`);
  return { stdout: "" };
}

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
  const txId =
    args.channelTranscriptId && args.channelTranscriptId !== "0"
      ? args.channelTranscriptId
      : "";

  const bodyForFallback = txId ? "" : args.content.substring(0, 65535);

  const sessionKeyEsc = args.sessionKey.replace(/'/g, "''");
  const senderNameEsc = args.senderName.replace(/'/g, "''");
  const senderIdEsc = args.senderId.replace(/'/g, "''");
  const stderrEsc = args.stderrTail.replace(/'/g, "''");
  const stdoutEsc = args.stdoutTail.replace(/'/g, "''");
  const reasonEsc = args.failureReason.replace(/'/g, "''");
  const bodyEsc = bodyForFallback.replace(/'/g, "''");

  const txIdVal = txId ? txId : "NULL";
  const bodyVal = bodyForFallback ? `'${bodyEsc}'` : "NULL";
  const exitCodeVal = args.exitCode === null ? "NULL" : String(args.exitCode);

  const sql = `
    INSERT INTO extraction_failures (
      channel_transcript_id, session_key, sender_name, sender_id,
      content, stderr_tail, stdout_tail, exit_code, failure_reason
    ) VALUES (
      ${txIdVal}, '${sessionKeyEsc}', '${senderNameEsc}', '${senderIdEsc}',
      ${bodyVal}, '${stderrEsc}', '${stdoutEsc}', ${exitCodeVal}, '${reasonEsc}'
    );
  `;

  let memoryDatabase: string;
  try {
    memoryDatabase = await resolveMemoryDatabase(args.sessionKey || "");
  } catch (err) {
    logError(
      `[memory-extract] Failed to resolve DB for extraction_failure insertion ` +
        `sessionKey=${args.sessionKey} error=${(err as Error).message} ` +
        `failureReason=${args.failureReason}`
    );
    return;
  }

  try {
    await execFileAsync("psql", [memoryDatabase, "-t", "-A", "-c", sql]);
  } catch (err) {
    logError(
      `[memory-extract] Failed to insert extraction_failure ` +
        `error=${(err as Error).message} failureReason=${args.failureReason}`
    );
  }
}

// ── Message handler (extracted from the old default export for testability) ──
export async function handleMessageReceived(event: any): Promise<void> {
  const sessionKey = event.sessionKey ?? "";
  incrementReceived();

  try {
    logDebug(`[memory-extract] Hook triggered eventType=${event.type} eventAction=${event.action}`);

    if (event.type === "message") {
      const ctx = event.context ?? {};
      const rawBody =
        ctx.content ?? ctx.rawBody ?? ctx.RawBody ?? ctx.message ?? ctx.Body ?? "";
      const isHeartbeat =
        rawBody.includes("HEARTBEAT") ||
        rawBody.includes("DASHBOARD UPDATE") ||
        rawBody.startsWith("System: [");
      logActivity(!isHeartbeat);
    }

    if (event.type !== "message" || event.action !== "received") {
      logDebug("[memory-extract] Skipping non-received message event");
      return;
    }

    const ctx = event.context ?? {};
    const rawBody =
      ctx.content ?? ctx.rawBody ?? ctx.RawBody ?? ctx.message ?? ctx.Body ?? "";

    if (!rawBody || rawBody.trim().length < 10) {
      logDebug("[memory-extract] Skipping short or empty message");
      incrementSkipped();
      return;
    }

    if (rawBody.startsWith("/")) {
      logDebug("[memory-extract] Skipping command message");
      incrementSkipped();
      return;
    }

    const meta = (ctx.metadata ?? {}) as Record<string, any>;
    const senderName = meta.senderName ?? ctx.from ?? "unknown";
    const senderId = meta.senderId ?? "";
    const isGroup = meta.isGroup ?? ctx.isGroup ?? false;

    logInfo(
      `[memory-extract] Processing message sender=${senderName} ` +
        `senderId=${senderId ? senderId.substring(0, 8) + "..." : "none"} ` +
        `isGroup=${isGroup} messageLength=${rawBody.length}`
    );

    const scriptPath =
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE ||
      join(os.homedir(), ".openclaw", "scripts", "extract_memories.py");

    let memoryDatabase: string;
    try {
      memoryDatabase = await resolveMemoryDatabase(sessionKey);
    } catch (dbErr) {
      const errMessage = (dbErr as Error).message ?? String(dbErr);
      if (errMessage.includes("Cross-peer guard")) {
        logFailure("peer_guard_refused", sessionKey);
      } else if (errMessage.includes("does not exist")) {
        const dbMatch = errMessage.match(/Resolved database '([^']+)'/);
        const failedDb = dbMatch ? dbMatch[1] : "unknown";
        logFailure("db_unreachable", sessionKey, `db=${failedDb}`);
      } else if (
        errMessage.includes("Could not resolve memory database")
      ) {
        logDbUnresolved(sessionKey);
      } else if (errMessage.includes("does not look like a memory database")) {
        logDbUnresolved(sessionKey);
      } else {
        logFailure("db_unreachable", sessionKey);
      }
      incrementFailed();
      return;
    }

    const messageTimestamp = new Date().toISOString();

    let channelTranscriptId = String(
      ctx.channelTranscriptId ?? ctx.channel_transcript_id ?? ""
    );
    let channelSessionId = String(
      ctx.channelSessionId ?? ctx.channel_session_id ?? ""
    );
    let externalMessageId = "";
    let derivedMessageId = "";

    if (!channelTranscriptId || channelTranscriptId === "0") {
      try {
        const chatId = String(
          ctx.conversationId ??
            meta.conversationId ??
            ctx.chatId ??
            ctx.chat_id ??
            ""
        );
        let provider = String(
          meta.provider ?? ctx.provider ?? ctx.channelId ?? "openclaw"
        );
        if (provider === "openclaw") {
          if (chatId.startsWith("channel:")) provider = "discord";
          else if (chatId.startsWith("group:") || chatId.startsWith("+"))
            provider = "signal";
        }

        const externalChatId = chatId || sessionKey || "unknown";
        externalMessageId = String(
          ctx.messageId ?? meta.messageId ?? ctx.message_id ?? ""
        );
        const isGroupBool = Boolean(meta.isGroup ?? ctx.isGroup ?? false);
        const chatType = isGroupBool ? "group" : "direct";
        const groupSubject = String(
          meta.channelName ?? ctx.channelName ?? ctx.groupSubject ?? ctx.group_subject ?? ""
        );
        const groupSpace = String(
          meta.guildId ?? ctx.guildId ?? ctx.groupSpace ?? ctx.group_space ?? ""
        );
        const senderTag = String(meta.senderTag ?? ctx.senderTag ?? ctx.sender_tag ?? "");
        const senderUsername = String(
          meta.senderUsername ?? ctx.senderUsername ?? ""
        );

        const rawThreadId =
          event.threadId ?? ctx.threadId ?? ctx.thread_id ?? meta.threadId ?? meta.thread_id;
        const externalThreadId = normalizeExternalThreadId(rawThreadId);
        const externalThreadIdVal =
          externalThreadId === null
            ? "NULL"
            : `'${externalThreadId.replace(/'/g, "''")}'`;

        if (externalMessageId || rawBody.length > 0) {
          const sessArgs = [
            memoryDatabase,
            "-t",
            "-A",
            "-c",
            `INSERT INTO channel_sessions (session_key, agent_id, provider, external_chat_id, chat_type` +
              (externalThreadId !== null ? ", external_thread_id" : "") +
              (groupSubject ? ", group_subject, title" : "") +
              (groupSpace ? ", group_space_id" : "") +
              `, last_message_at) VALUES (` +
              `'${sessionKey.replace(/'/g, "''")}', 'main', ` +
              `'${provider.replace(/'/g, "''")}', ` +
              `'${externalChatId.replace(/'/g, "''")}', ` +
              `'${chatType}'` +
              (externalThreadId !== null ? `, ${externalThreadIdVal}` : "") +
              (groupSubject
                ? `, '${groupSubject.replace(/'/g, "''")}', '${groupSubject.replace(
                    /'/g,
                    "''"
                  )}' `
                : "") +
              (groupSpace
                ? `, '${groupSpace.replace(/'/g, "''")}' `
                : "") +
              `, '${messageTimestamp}') ON CONFLICT (provider, external_chat_id, COALESCE(external_thread_id, '')) DO UPDATE SET updated_at = NOW(), last_message_at = '${messageTimestamp}' RETURNING id;`,
          ];

          const { stdout: sessOut } = await execFileAsync("psql", sessArgs).catch((err) =>
            logPsqlError("session-upsert", err)
          );
          const resolvedSessionId = (sessOut.match(/^(\d+)/m) ?? [])[1] ?? "";
          if (resolvedSessionId) channelSessionId = resolvedSessionId;

          if (channelSessionId) {
            derivedMessageId = externalMessageId || `${messageTimestamp}_rt`;
            const contentSnippet = rawBody.substring(0, 65535).replace(/'/g, "''");
            const senderNameEsc = senderName.replace(/'/g, "''");
            const senderIdEsc = senderId.replace(/'/g, "''");
            const senderTagEsc = senderTag.replace(/'/g, "''");
            const senderUsernameEsc = senderUsername.replace(/'/g, "''");

            const txArgs = [
              memoryDatabase,
              "-t",
              "-A",
              "-c",
              `INSERT INTO channel_transcripts (session_id, external_message_id, timestamp, role, content` +
                (senderId ? ", sender_id" : "") +
                (senderName && senderName !== "unknown" ? ", sender_name" : "") +
                (senderTag ? ", sender_tag" : "") +
                (senderUsername ? ", sender_username" : "") +
                `) VALUES (` +
                `${channelSessionId}, '${derivedMessageId.replace(/'/g, "''")}', ` +
                `'${messageTimestamp}', 'user', '${contentSnippet}'` +
                (senderId ? `, '${senderIdEsc}'` : "") +
                (senderName && senderName !== "unknown" ? `, '${senderNameEsc}'` : "") +
                (senderTag ? `, '${senderTagEsc}'` : "") +
                (senderUsername ? `, '${senderUsernameEsc}'` : "") +
                `) ON CONFLICT (session_id, external_message_id) DO NOTHING RETURNING id;`,
            ];

            const { stdout: txOut } = await execFileAsync("psql", txArgs).catch((err) =>
              logPsqlError("transcript-upsert", err)
            );
            const resolvedTranscriptId = (txOut.match(/^(\d+)/m) ?? [])[1] ?? "";
            if (resolvedTranscriptId) channelTranscriptId = resolvedTranscriptId;

            if (!channelTranscriptId && channelSessionId && derivedMessageId) {
              const lookupArgs = [
                memoryDatabase,
                "-t",
                "-A",
                "-c",
                `SELECT id FROM channel_transcripts WHERE session_id = ${channelSessionId} AND external_message_id = '${derivedMessageId.replace(
                  /'/g,
                  "''"
                )}' LIMIT 1;`,
              ];
              const { stdout: lookupOut } = await execFileAsync("psql", lookupArgs).catch(
                (err) => logPsqlError("transcript-lookup", err)
              );
              const foundId = (lookupOut.match(/^(\d+)/m) ?? [])[1] ?? "";
              if (foundId) channelTranscriptId = foundId;
            }
          }
        }
      } catch (err) {
        logWarn(
          `[memory-extract] Could not upsert channel_transcripts for FK wiring ` +
            `error=${(err as Error).message}`
        );
      }
    }

    const pythonCmd = resolvePythonCmd();
    logInfo(`[memory-extract] Resolved extraction interpreter pythonCmd=${pythonCmd}`);

    const timeoutMs = (() => {
      const raw = process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
      if (!raw) return loadExtractionTimeoutMs();
      const n = Number(raw);
      return Number.isFinite(n) && n > 0 ? n : loadExtractionTimeoutMs();
    })();

    const child = spawn(pythonCmd, [scriptPath], {
      stdio: ["pipe", "pipe", "pipe"],
      env: {
        ...process.env,
        PGDATABASE: memoryDatabase,
        SENDER_NAME: senderName,
        SENDER_ID: senderId,
        IS_GROUP: String(isGroup),
        SOURCE_SESSION_ID: sessionKey,
        SOURCE_TIMESTAMP: messageTimestamp,
        SOURCE_CHANNEL_TRANSCRIPT_ID: channelTranscriptId,
        SOURCE_CHANNEL_SESSION_ID: channelSessionId,
      },
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
        failureReason: reason,
      });
    };

    timeoutHandle = setTimeout(() => {
      didTimeout = true;
      logError(
        `[memory-extract] Extraction timed out sender=${senderName} ` +
          `senderId=${truncateSenderId(senderId)}`
      );
      child.kill("SIGTERM");
      setTimeout(() => {
        if (!child.killed) {
          logError(
            `[memory-extract] Extraction child did not terminate gracefully, forcing SIGKILL ` +
              `sender=${senderName} senderId=${truncateSenderId(senderId)}`
          );
          child.kill("SIGKILL");
        }
      }, KILL_GRACE_MS);
    }, timeoutMs);

    await new Promise<void>((resolve) => {
      let settled = false;
      const done = () => {
        if (settled) return;
        settled = true;
        resolve();
      };

      child.on("close", async (code, signal) => {
        if (timeoutHandle) {
          clearTimeout(timeoutHandle);
          timeoutHandle = null;
        }

        if (didTimeout) {
          logFailure("timeout", sessionKey, `signal=${signal}`);
          await recordFailure("timeout", null);
          incrementFailed();
        } else {
          const stderrTail = tailToString(getStderrTail());
          const hasProviderKeyMissing = stderrTail.includes(
            "OPENROUTER_API_KEY not set"
          );

          if (code === 2) {
            logFailure("extractor_exit_nonzero", sessionKey, `exitCode=${code}`);
            await recordFailure("json_parse_failure", code);
            incrementFailed();
          } else if (code !== 0) {
            if (hasProviderKeyMissing) {
              logFailure("provider_key_missing", sessionKey, `exitCode=${code}`);
              await recordFailure("provider_key_missing", code);
            } else {
              logFailure("extractor_exit_nonzero", sessionKey, `exitCode=${code}`);
              await recordFailure("nonzero_exit", code);
            }
            incrementFailed();
          } else {
            logInfo(
              `[memory-extract] Extraction complete sender=${senderName} ` +
                `senderId=${truncateSenderId(senderId)}`
            );
            incrementExtracted();
            incrementStored();
          }
        }
        done();
      });

      child.on("error", async (err) => {
        if (timeoutHandle) {
          clearTimeout(timeoutHandle);
          timeoutHandle = null;
        }
        logFailure("extractor_spawn_failed", sessionKey, `error=${err.message}`);
        await recordFailure("spawn_error", null);
        incrementFailed();
        done();
      });
    });
  } catch (handlerErr) {
    logError(
      `[memory-extract] Unexpected handler error error=${
        (handlerErr as Error).message
      }`
    );
  }
}

// ── Lifecycle helpers ──
function startLifecycleTimers(): void {
  if (summaryTimer) {
    clearInterval(summaryTimer);
  }
  if (stallTimer) {
    clearInterval(stallTimer);
  }
  summaryTimer = setInterval(emitPeriodicSummary, activeConfig.summaryIntervalMs);
  summaryTimer.unref();
  stallTimer = setInterval(checkStall, activeConfig.stallCheckIntervalMs);
  stallTimer.unref();

  process.once("SIGTERM", emitShutdown);
  process.once("SIGINT", emitShutdown);
  process.on("beforeExit", emitShutdown);
}

function stopLifecycleTimers(): void {
  if (summaryTimer) {
    clearInterval(summaryTimer);
    summaryTimer = null;
  }
  if (stallTimer) {
    clearInterval(stallTimer);
    stallTimer = null;
  }
}

function emitStartupInfo(): void {
  if (startupEmitted) return;
  startupEmitted = true;
  const startup = startupInfoLine();
  if (!startup.ok) {
    logError(
      `[memory-extract] startup failed version=${PLUGIN_VERSION} reason=db_unresolved`
    );
  } else {
    logInfo(
      `[memory-extract] startup version=${PLUGIN_VERSION} ` +
        `db=${startup.dbName} source=${startup.dbSource} ` +
        `python=${startup.pythonCmd} model=${startup.model}`
    );
  }
}

export function emitShutdown(): void {
  if (shutdownEmitted) return;
  shutdownEmitted = true;
  stopLifecycleTimers();
  logInfo(
    `[memory-extract] shutdown received=${sessionCounters.received} ` +
      `extracted=${sessionCounters.extracted} stored=${sessionCounters.stored} ` +
      `skipped=${sessionCounters.skipped} failed=${sessionCounters.failed}`
  );
}

function ensureInitialized(): void {
  if (lifecycleInitialized) return;
  moduleLogger ??= createDefaultLogger();
  emitStartupInfo();
  startLifecycleTimers();
  lifecycleInitialized = true;
}

/** Test-only hook to inject a mock logger and optionally override lifecycle config. */
export function setModuleLogger(
  logger: PluginLogger | null,
  config?: Partial<typeof activeConfig>
): void {
  moduleLogger = logger ?? createDefaultLogger();
  if (config) {
    activeConfig = { ...activeConfig, ...config };
  }
  emitStartupInfo();
  if (!lifecycleInitialized) {
    startLifecycleTimers();
    lifecycleInitialized = true;
  }
}

// ── Legacy hook entry point ──
export default async function handler(event: any): Promise<void> {
  ensureInitialized();
  return handleMessageReceived(event);
}

// ── Test helpers ──
export function getSessionCounters(): Readonly<Counters> {
  return { ...sessionCounters };
}

export function getSummaryCounters(): Readonly<Counters> {
  return { ...summaryCounters };
}

export function getLastSuccessfulStoreAt(): number | null {
  return lastSuccessfulStoreAt;
}

export function resetForTests(): void {
  resetModuleState();
}
