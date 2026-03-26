import { execFileSync } from "child_process";
import { existsSync } from "fs";
import { join } from "path";
import * as os from "os";

const STATE_DIR = process.env.OPENCLAW_STATE_DIR || join(os.homedir(), ".openclaw");
const SCRIPTS_DIR = join(STATE_DIR, "scripts");
const LIB_DIR = join(STATE_DIR, "lib");

// Load PG env vars from postgres.json BEFORE importing entity-resolver,
// which creates a pg.Pool at module scope. Without this, PGPASSWORD may be
// unset and node-pg falls back to ~/.pgpass (which can have stale creds).
// See: https://github.com/NOVA-Openclaw/nova-memory/issues/136
const pgEnvPath = join(LIB_DIR, "pg-env.ts");
try {
  const { loadPgEnv } = await import(pgEnvPath);
  loadPgEnv();
} catch (err) {
  console.error(
    "[semantic-recall] Failed to load pg-env:",
    err instanceof Error ? err.message : String(err),
  );
}

interface Entity {
  id: number;
  name: string;
  fullName?: string;
  type?: string;
}

interface EntityFacts {
  [key: string]: string;
}

type EntityResolverModule = {
  resolveEntity: (identifiers: { uuid?: string; phone?: string }) => Promise<Entity | null>;
  getEntityProfile: (entityId: number) => Promise<EntityFacts>;
  getCachedEntity: (sessionId: string) => Entity | null;
  setCachedEntity: (sessionId: string, entity: Entity) => void;
};

const entityResolverPath = join(LIB_DIR, "entity-resolver", "index.ts");
let entityResolver: EntityResolverModule | null = null;

try {
  entityResolver = (await import(entityResolverPath)) as EntityResolverModule;
} catch (err) {
  console.error(
    `[semantic-recall] Entity resolver unavailable at ${entityResolverPath}:`,
    err instanceof Error ? err.message : String(err),
  );
}

const RECALL_SCRIPT = join(SCRIPTS_DIR, "proactive-recall.py");
const STANDARD_VENV = join(
  os.homedir(),
  ".local",
  "share",
  os.userInfo().username,
  "venv",
  "bin",
  "python",
);
const FALLBACK_VENV = join(SCRIPTS_DIR, "tts-venv", "bin", "python");
const PYTHON_VENV = existsSync(STANDARD_VENV) ? STANDARD_VENV : FALLBACK_VENV;

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

const handler = async (event: any) => {
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
  const sessionId = (event.context as { sessionId?: string })?.sessionId || `session:${senderId || "unknown"}`;

  // Try to resolve entity context (with caching)
  let entity: Entity | null = null;
  if (senderId && entityResolver) {
    // Check cache first
    entity = entityResolver.getCachedEntity(sessionId);

    if (!entity) {
      // Resolve from database
      try {
        entity = await Promise.race([
          entityResolver.resolveEntity({ uuid: senderId, phone: senderId }),
          new Promise<null>((resolve) => setTimeout(() => resolve(null), 2000)),
        ]);

        // Cache the result if found
        if (entity) {
          entityResolver.setCachedEntity(sessionId, entity);
        }
      } catch (err) {
        console.error("[semantic-recall] Entity resolution error:", err instanceof Error ? err.message : String(err));
      }
    } else {
      console.log(`[semantic-recall] Using cached entity for session: ${sessionId}`);
    }
  } else if (senderId && !entityResolver) {
    console.error("[semantic-recall] Skipping entity enrichment because entity-resolver is unavailable");
  }

  // Run semantic recall (parallel with entity profile loading if needed)
  let recallResult: {
    memories?: Array<{ source: string; content: string; similarity: number; full?: boolean }>;
    tokens_used?: number;
    token_budget?: number;
  } | null = null;

  if (!existsSync(PYTHON_VENV)) {
    console.error(
      `[semantic-recall] Python venv not found. Tried ${STANDARD_VENV} and ${FALLBACK_VENV}`,
    );
  } else {
    try {
      const result = execFileSync(
        PYTHON_VENV,
        [
          RECALL_SCRIPT,
          message.substring(0, 500),
          "--max-tokens",
          TOKEN_BUDGET.toString(),
          "--high-confidence",
          HIGH_CONFIDENCE_THRESHOLD.toString(),
        ],
        {
          encoding: "utf-8",
          timeout: 5000,
          env: { ...process.env },
        },
      );
      recallResult = JSON.parse(result);
    } catch (err) {
      // Fail silently - don't block message processing
      console.error("[semantic-recall] Recall error:", err instanceof Error ? err.message : String(err));
    }
  }

  // Load entity facts if entity found
  let entityFacts: EntityFacts = {};
  if (entity && entityResolver) {
    try {
      entityFacts = await Promise.race([
        entityResolver.getEntityProfile(entity.id),
        new Promise<EntityFacts>((resolve) => setTimeout(() => resolve({}), 1000)),
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
        const confidence = m.full ? "🎯" : "📝"; // Full content vs summary
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
