import { execFile } from "child_process";
import { existsSync, statSync } from "fs";
import { join } from "path";
import * as os from "os";

const STATE_DIR = process.env.OPENCLAW_STATE_DIR || join(os.homedir(), ".openclaw");
const CONTEXT_FILE = join(STATE_DIR, "SESSION_CONTEXT.md");
const SCRIPTS_DIR = join(STATE_DIR, "scripts");
const CONTEXT_SCRIPT = join(SCRIPTS_DIR, "generate-session-context.sh");
const STALE_MINUTES = 5;

// Track current session participants
let currentParticipantHash = "";

const handler = async (event: any) => {
  if (event.type !== "message" || event.action !== "received") return;

  const ctx = event.context ?? {};
  const senderId = ctx.senderId ?? "";

  // Skip if no sender ID
  if (!senderId) return;

  // For now, just use the sender. In group chats, we'd need all participant IDs.
  // TODO: Get full participant list for groups
  const participants = [senderId];
  const participantHash = participants.sort().join(",");

  // Check if context needs refresh
  let needsRefresh = false;

  if (!existsSync(CONTEXT_FILE)) {
    needsRefresh = true;
  } else {
    // Check staleness
    const stats = statSync(CONTEXT_FILE);
    const ageMinutes = (Date.now() - stats.mtimeMs) / 1000 / 60;
    if (ageMinutes > STALE_MINUTES) {
      needsRefresh = true;
    }

    // Check if participants changed
    if (participantHash !== currentParticipantHash) {
      needsRefresh = true;
    }
  }

  if (!needsRefresh) return;

  // Update participant hash
  currentParticipantHash = participantHash;

  // Generate new context (async to not block message processing)
  const args = [CONTEXT_FILE, ...participants];

  execFile(CONTEXT_SCRIPT, args, (err) => {
    if (err) {
      console.error(`[session-init] Error generating context: ${err.message}`);
    } else {
      console.log(`[session-init] Context refreshed for participants: ${participantHash}`);
    }
  });
};

export default handler;
