import { exec } from "child_process";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

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
  const escaped = rawBody.replace(/'/g, "'\\''");
  const envVars = `SENDER_NAME='${senderName}' SENDER_ID='${senderId}' IS_GROUP='${isGroup}'`;
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  // Use grammar-enhanced extraction (issue #22)
  const scriptPath = join(__dirname, '../../scripts/process-input-with-grammar.sh');
  
  exec(`${envVars} ${scriptPath} '${escaped}'`, (err) => {
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
  });
};

export default handler;
