/**
 * Entity Resolver subsystem.
 *
 * Resolves the sender's identity via the entity-resolver library and formats
 * their key facts for injection. Results are cached per sessionKey.
 *
 * Ported from ~/.openclaw/hooks/semantic-recall/handler.ts
 * Issue: nova-mind #182
 */

import * as os from "os";
import { join } from "path";

// ── Dynamic import of entity-resolver from installed location ─────────────────

// PG env is already loaded by shared/pg-pool.ts before this module runs,
// but entity-resolver also calls loadPgEnv() internally — that's fine (idempotent).
const entityResolverPath = join(os.homedir(), ".openclaw", "lib", "entity-resolver", "index.ts");
const {
  resolveEntityByIdentifiers,
  getEntityProfile,
  getCachedEntity,
  setCachedEntity,
} = await import(entityResolverPath);

// ── Derived types (can't use static imports from install-time path) ───────────

type Entity = Exclude<Awaited<ReturnType<typeof import(entityResolverPath).resolveEntity>>, null>;
type EntityFacts = Awaited<ReturnType<typeof getEntityProfile>>;

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

// ── Per-session entity cache ──────────────────────────────────────────────────

// The entity-resolver library maintains its own cache (getCachedEntity / setCachedEntity),
// so we delegate to that instead of maintaining a second one here.

// ── Channel-aware identifier mapping ─────────────────────────────────────────

function extractIdentifiers(
  provider: string | undefined,
  senderId: string | undefined,
  senderE164?: string | undefined
): EntityIdentifiers {
  if (!senderId) return {};

  switch (provider) {
    case "discord":
      return { discordId: senderId };
    case "telegram":
      return { telegramId: senderId };
    case "slack":
      return { slackMemberId: senderId };
    case "signal": {
      const ids: EntityIdentifiers = { signalUuid: senderId };
      if (senderE164) ids.phone = senderE164;
      return ids;
    }
    default:
      // Unknown provider — graceful skip; entity resolution will return nothing
      return {};
  }
}

// ── Format helpers ────────────────────────────────────────────────────────────

function formatEntityContext(entity: Entity, facts: EntityFacts): string {
  const displayName = (entity as any).fullName || (entity as any).name;
  let context = `👤 **Talking with:** ${displayName}`;

  const factEntries = Object.entries(facts as Record<string, unknown>);
  if (factEntries.length > 0) {
    context += "\n";
    for (const [key, value] of factEntries) {
      const label = key
        .replace(/_/g, " ")
        .replace(/\b\w/g, (l) => l.toUpperCase());
      context += `\n• **${label}:** ${value}`;
    }
  }

  return context;
}

// ── Public API ────────────────────────────────────────────────────────────────

export interface SenderInfo {
  senderId?: string;
  senderName?: string;
  provider?: string;
  senderE164?: string;
}

/**
 * Resolve the sender entity and return formatted context text, or null if
 * no entity was found or an error occurred.
 *
 * Uses the entity-resolver library's cache keyed by sessionKey.
 */
export async function resolveEntityContext(
  sessionKey: string,
  info: SenderInfo
): Promise<string | null> {
  const { senderId, senderName, provider, senderE164 } = info;

  if (!senderId) return null;

  let entity: Entity | null = null;

  // Check library cache first
  entity = getCachedEntity(sessionKey) as Entity | null;

  if (!entity) {
    const identifiers = extractIdentifiers(provider, senderId, senderE164);
    if (Object.keys(identifiers).length === 0) {
      // Unknown provider — no way to resolve
      console.log(`[turn-context] Unknown provider '${provider}', skipping entity resolution`);
      return null;
    }

    try {
      const resolveResult = await Promise.race([
        resolveEntityByIdentifiers(identifiers),
        new Promise<null>((resolve) => setTimeout(() => resolve(null), 2000)),
      ]);

      if (resolveResult) {
        if ((resolveResult as any).ok) {
          entity = (resolveResult as any).entity as Entity;
        } else {
          // Conflict: multiple entities matched — safer to skip
          console.error(
            `[turn-context] Entity conflict for sender ${senderName || senderId}: ` +
            `${(resolveResult as any).message}`
          );
          return null;
        }
      }

      if (entity) {
        setCachedEntity(sessionKey, entity);
      }
    } catch (err) {
      console.error(
        "[turn-context] Entity resolution error:",
        err instanceof Error ? err.message : String(err)
      );
      return null;
    }
  }

  if (!entity) {
    console.log(
      `[turn-context] No entity found for sender: ${senderName || senderId}`
    );
    return null;
  }

  // Load entity facts with a 1s timeout
  let facts: EntityFacts = {};
  try {
    facts = await Promise.race([
      getEntityProfile((entity as any).id),
      new Promise<EntityFacts>((resolve) => setTimeout(() => resolve({}), 1000)),
    ]);
  } catch (err) {
    console.error(
      "[turn-context] Entity facts loading error:",
      err instanceof Error ? err.message : String(err)
    );
  }

  const result = formatEntityContext(entity, facts);
  console.log(
    `[turn-context] Loaded entity context for: ${(entity as any).name} (${senderId})`
  );
  return result;
}
