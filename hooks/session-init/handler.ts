import { execSync, exec } from "child_process";
import { existsSync, statSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import * as os from "os";

const WORKSPACE = process.env.OPENCLAW_WORKSPACE || join(process.env.HOME || os.homedir(), '.openclaw');
const CONTEXT_FILE = join(WORKSPACE, 'SESSION_CONTEXT.md');
const STALE_MINUTES = 5;

// Track current session participants
let currentParticipantHash = "";

const handler = async (event) => {
  if (event.type !== "message" || event.action !== "received") return;

  const ctx = event.context ?? {};
  const senderId = ctx.senderId ?? "";
  const isGroup = ctx.isGroup ?? false;
  
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
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = dirname(__filename);
  const scriptPath = join(__dirname, '../../scripts/generate-session-context.sh');
  const args = participants.map(p => `"${p}"`).join(" ");
  
  exec(`"${scriptPath}" "${CONTEXT_FILE}" ${args}`, (err) => {
    if (err) {
      console.error(`[session-init] Error generating context: ${err.message}`);
    } else {
      console.log(`[session-init] Context refreshed for participants: ${participantHash}`);
    }
  });
};

export default handler;
