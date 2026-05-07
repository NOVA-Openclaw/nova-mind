import { spawnSync } from "child_process";
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

// Dynamic import of entity-resolver from installed location ($HOME/.openclaw/lib/)
// This path works both from the repo AND from the installed hook location.
const entityResolverPath = join(os.homedir(), ".openclaw", "lib", "entity-resolver", "index.ts");
const {
  resolveEntity,
  resolveEntityByIdentifiers,
  getEntityProfile,
  getCachedEntity,
  setCachedEntity,
} = await import(entityResolverPath);

// Types derived from resolver return types (can't use static type imports
// from a path that only exists at install time)
type Entity = Exclude<Awaited<ReturnType<typeof resolveEntity>>, null>;
type EntityFacts = Awaited<ReturnType<typeof getEntityProfile>>;

// EntityIdentifiers: mirrors relationships/lib/entity-resolver/types.ts
// Defined inline because the source path is not available at install time.
interface EntityIdentifiers {
  phone?: string;
  uuid?: string;
  certCN?: string;
  email?: string;
  discordId?: string;
  telegramId?: string;
  slackMemberId?: string;
  signalUuid?: string;
  signalUsername?: string;
}

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

/**
 * Extract channel-aware identifiers from event metadata.
 * Maps provider-specific sender IDs to the correct EntityIdentifiers fields.
 */
function extractIdentifiers(
  provider: string | undefined,
  senderId: string | undefined,
  senderE164?: string | undefined,
): EntityIdentifiers {
  if (!senderId) return {};

  switch (provider) {
    case 'discord':
      return { discordId: senderId };
    case 'telegram':
      return { telegramId: senderId };
    case 'slack':
      return { slackMemberId: senderId };
    case 'signal': {
      const ids: EntityIdentifiers = { signalUuid: senderId };
      if (senderE164) {
        ids.phone = senderE164;
      }
      return ids;
    }
    default:
      // Unknown provider — graceful skip, fall back to legacy uuid/phone path
      return {};
  }
}

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
  // Only handle message:received events
  if (event.type !== "message" || event.action !== "received") {
    return;
  }

  // Use correct field path: event.context.content (not .message)
  const message: string | undefined = (event.context as any)?.content
    ?? (event.context as any)?.message;  // fallback for legacy callers
  if (!message || message.length < 10) {
    // Skip very short messages (commands, reactions, etc.)
    return;
  }

  // Skip if message looks like a command
  if (message.startsWith("/") || message.startsWith("!")) {
    return;
  }

  // Extract sender info from event.context.metadata (correct path)
  const metadata = (event.context as any)?.metadata;
  const senderId: string | undefined = metadata?.senderId
    ?? (event.context as any)?.senderId;  // fallback for legacy callers
  const senderName: string | undefined = metadata?.senderName
    ?? (event.context as any)?.senderName;
  const provider: string | undefined = metadata?.provider;
  const senderE164: string | undefined = metadata?.senderE164;
  const sessionId: string = (event.context as any)?.sessionId || `session:${senderId || 'unknown'}`;

  // Build channel-aware identifiers
  const platformIdentifiers = extractIdentifiers(provider, senderId, senderE164);

  // Try to resolve entity context (with caching)
  let entity: Entity | null = null;
  if (senderId) {
    // Check cache first
    entity = getCachedEntity(sessionId);
    
    if (!entity) {
      // Resolve from database using platform-aware identifiers
      try {
        // Merge platform identifiers with legacy fallback (uuid/phone)
        const identifiers: EntityIdentifiers = Object.keys(platformIdentifiers).length > 0
          ? platformIdentifiers
          : { uuid: senderId, phone: senderId };

        // Use resolveEntityByIdentifiers for conflict detection
        const resolveResult = await Promise.race([
          resolveEntityByIdentifiers(identifiers),
          new Promise<null>((resolve) => setTimeout(() => resolve(null), 2000)),
        ]);

        if (resolveResult) {
          if (resolveResult.ok) {
            entity = resolveResult.entity;
          } else {
            // Conflict: multiple entities matched — log as data integrity issue, do NOT pick a winner
            console.error(
              `[semantic-recall] CONFLICT: ${resolveResult.message}`,
            );
            // Don't resolve entity — safer to inject no entity context than the wrong one
          }
        }
        
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
    const truncatedMessage = message.substring(0, 500);
    const result = spawnSync(PYTHON_VENV, [
      RECALL_SCRIPT, '--stdin',
      '--max-tokens', String(TOKEN_BUDGET),
      '--high-confidence', String(HIGH_CONFIDENCE_THRESHOLD)
    ], {
      input: truncatedMessage,
      encoding: 'utf-8',
      timeout: 5000,  // 5 second timeout
      env: { ...process.env }
    });
    if (result.status === 0 && result.stdout) {
      recallResult = JSON.parse(result.stdout);
    } else {
      throw new Error(result.stderr || `Exit code: ${result.status}`);
    }
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
