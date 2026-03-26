import { execFile } from "child_process";
import { join } from "path";
import * as os from "os";

const STATE_DIR = process.env.OPENCLAW_STATE_DIR || join(os.homedir(), ".openclaw");
const SCRIPTS_DIR = join(STATE_DIR, "scripts");
const EXTRACTION_SCRIPT = join(SCRIPTS_DIR, "process-input-with-grammar.sh");

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

const handler = async (event: any) => {
  console.info('[memory-extract] Hook triggered', {
    eventType: event.type,
    eventAction: event.action
  });

  // Track activity for cost/hour calculations
  if (event.type === "message") {
    const ctx = event.context ?? {};
    const rawBody = ctx.rawBody ?? ctx.message ?? "";
    const isHeartbeat = rawBody.includes("HEARTBEAT") || rawBody.includes("DASHBOARD UPDATE") || rawBody.startsWith("System: [");
    logActivity(!isHeartbeat);
  }

  if (event.type !== "message" || event.action !== "received") {
    console.debug('[memory-extract] Skipping non-received message event');
    return;
  }

  const ctx = event.context ?? {};
  const rawBody = ctx.rawBody ?? ctx.message ?? "";

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

  // Run extraction with attribution env vars (include senderId for unique matching)
  execFile(
    EXTRACTION_SCRIPT,
    [rawBody],
    {
      env: {
        ...process.env,
        SENDER_NAME: senderName,
        SENDER_ID: senderId,
        IS_GROUP: String(isGroup),
      },
    },
    (err) => {
      if (err) {
        console.error('[memory-extract] Extraction failed', {
          sender: senderName,
          error: err.message,
          code: err.code
        });
      } else {
        console.info('[memory-extract] Extraction complete', {
          sender: senderName
        });
      }
    }
  );
};

export default handler;
