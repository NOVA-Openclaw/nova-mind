import { execSync } from "child_process";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import * as os from "os";

// Load PG env vars from postgres.json BEFORE importing entity-resolver,
// which creates a pg.Pool at module scope. Without this, PGPASSWORD may be
// unset and node-pg falls back to ~/.pgpass (which can have stale creds).
// See: https://github.com/NOVA-Openclaw/nova-memory/issues/136
const pgEnvPath = join(os.homedir(), ".openclaw", "lib", "pg-env.ts");
const { loadPgEnv } = await import(pgEnvPath);
loadPgEnv();

import {
  resolveEntity,
  getEntityProfile,
  getCachedEntity,
  setCachedEntity,
  type Entity,
  type EntityFacts,
} from "../../../nova-relationships/lib/entity-resolver/index.ts";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const RECALL_SCRIPT = join(__dirname, '../../scripts/proactive-recall.py');
const WORKSPACE = process.env.OPENCLAW_WORKSPACE || join(process.env.HOME || os.homedir(), '.openclaw');

// Standard venv location (installed by nova-memory installer)
const STANDARD_VENV = join(process.env.HOME || os.homedir(), '.local/share', os.userInfo().username, 'venv/bin/python');
// Fallback to workspace venv for backward compatibility
const WORKSPACE_VENV = join(WORKSPACE, 'scripts/tts-venv/bin/python');

// Use standard venv if it exists, otherwise fall back to workspace venv
import { existsSync } from 'fs';
const PYTHON_VENV = existsSync(STANDARD_VENV) ? STANDARD_VENV : WORKSPACE_VENV;

// Configurable via environment variables
const TOKEN_BUDGET = parseInt(process.env.SEMANTIC_RECALL_TOKEN_BUDGET || "1000", 10);
const HIGH_CONFIDENCE_THRESHOLD = parseFloat(process.env.SEMANTIC_RECALL_HIGH_CONFIDENCE || "0.7");

function formatEntityContext(entity: Entity, facts: EntityFacts): string {
  const displayName = entity.fullName || entity.name;
  let context = `👤 **Talking with:** ${displayName}`;
  
  const factEntries = Object.entries(facts);
  if (factEntries.length > 0) {
    context += "\n";
    for (const [key, value] of factEntries) {
      const label = key.replace(/_/g, " ").replace(/\b\w/g, (l) => l.toUpperCase());
      context += `\n• **${label}:** ${value}`;
    }
  }
  
  return context;
}

const handler = async (event) => {
  // Check if OPENAI_API_KEY is set before executing
  if (!process.env.OPENAI_API_KEY) {
    console.error("[semantic-recall] ERROR: OPENAI_API_KEY not set - semantic recall disabled");
    return;
  }

  // Only handle message:received events
  if (event.type !== "message" || event.action !== "received") {
    return;
  }

  const message = (event.context as { message?: string })?.message;
  if (!message || message.length < 10) {
    // Skip very short messages (commands, reactions, etc.)
    return;
  }

  // Skip if message looks like a command
  if (message.startsWith("/") || message.startsWith("!")) {
    return;
  }

  // Extract sender identifier from event context
  const senderId = (event.context as { senderId?: string })?.senderId;
  const senderName = (event.context as { senderName?: string })?.senderName;
  const sessionId = (event.context as { sessionId?: string })?.sessionId || `session:${senderId || 'unknown'}`;

  // Try to resolve entity context (with caching)
  let entity: Entity | null = null;
  if (senderId) {
    // Check cache first
    entity = getCachedEntity(sessionId);
    
    if (!entity) {
      // Resolve from database
      try {
        entity = await Promise.race([
          resolveEntity({ uuid: senderId, phone: senderId }),
          new Promise<null>((resolve) => setTimeout(() => resolve(null), 2000))
        ]);
        
        // Cache the result if found
        if (entity) {
          setCachedEntity(sessionId, entity);
        }
      } catch (err) {
        console.error("[semantic-recall] Entity resolution error:", err instanceof Error ? err.message : String(err));
      }
    } else {
      console.log(`[semantic-recall] Using cached entity for session: ${sessionId}`);
    }
  }

  // Run semantic recall (parallel with entity profile loading if needed)
  let recallResult: { 
    memories?: Array<{ source: string; content: string; similarity: number; full?: boolean }>;
    tokens_used?: number;
    token_budget?: number;
  } | null = null;
  try {
    const escapedMessage = message.replace(/"/g, '\\"').replace(/\$/g, '\\$').substring(0, 500);
    const result = execSync(
      `${PYTHON_VENV} ${RECALL_SCRIPT} "${escapedMessage}" --max-tokens ${TOKEN_BUDGET} --high-confidence ${HIGH_CONFIDENCE_THRESHOLD}`,
      { 
        encoding: "utf-8",
        timeout: 5000,  // 5 second timeout
        env: { ...process.env }
      }
    );
    recallResult = JSON.parse(result);
  } catch (err) {
    // Fail silently - don't block message processing
    console.error("[semantic-recall] Recall error:", err instanceof Error ? err.message : String(err));
  }

  // Load entity facts if entity found
  let entityFacts: EntityFacts = {};
  if (entity) {
    try {
      entityFacts = await Promise.race([
        getEntityProfile(entity.id),
        new Promise<EntityFacts>((resolve) => setTimeout(() => resolve({}), 1000))
      ]);
    } catch (err) {
      console.error("[semantic-recall] Entity facts loading error:", err instanceof Error ? err.message : String(err));
    }
  }

  // Inject entity context
  if (entity) {
    const entityContext = formatEntityContext(entity, entityFacts);
    event.messages.push(entityContext);
    console.log(`[semantic-recall] Loaded entity context for: ${entity.name} (${senderId})`);
  } else if (senderId) {
    console.log(`[semantic-recall] No entity found for sender: ${senderName || senderId}`);
  }

  // Inject semantic recall memories
  if (recallResult?.memories && recallResult.memories.length > 0) {
    // Format memories for injection with tiered indicators
    const memoryText = recallResult.memories
      .map((m) => {
        const confidence = m.full ? "🎯" : "📝";  // Full content vs summary
        return `${confidence} [${m.source}] (${(m.similarity * 100).toFixed(0)}%): ${m.content}`;
      })
      .join("\n\n");

    // Add to event messages (will be shown to agent)
    event.messages.push(`🧠 **Relevant Context:**\n${memoryText}`);
    
    const tokensInfo = recallResult.tokens_used ? ` (~${recallResult.tokens_used}/${recallResult.token_budget} tokens)` : "";
    console.log(`[semantic-recall] Found ${recallResult.memories.length} relevant memories${tokensInfo}`);
  }
};

export default handler;
