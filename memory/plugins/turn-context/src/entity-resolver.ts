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
// Wrapped in try/catch for graceful degradation if the library is not installed.

// Entity type from dynamic import — use any with runtime property checks
type Entity = any;
type EntityFacts = Record<string, unknown>;

let resolveEntityByIdentifiers: any;
let getEntityProfile: any;
let getCachedEntity: any;
let setCachedEntity: any;

try {
  const entityResolverPath = join(os.homedir(), ".openclaw", "lib", "entity-resolver", "index.ts");
  const mod = await import(entityResolverPath);
  resolveEntityByIdentifiers = mod.resolveEntityByIdentifiers;
  getEntityProfile = mod.getEntityProfile;
  getCachedEntity = mod.getCachedEntity;
  setCachedEntity = mod.setCachedEntity;
} catch (err) {
  console.warn("[turn-context] Entity resolver not available:", (err as Error).message);
  // All four functions remain undefined — resolveEntityContext will return null gracefully
}

// ── Channel-aware identifier mapping ─────────────────────────────────────────

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
  const displayName = entity.fullName || entity.name;
  let context = `👤 **Talking with:** ${displayName}`;

  const factEntries = Object.entries(facts);
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
  // Graceful degradation if entity-resolver library is not installed
  if (!resolveEntityByIdentifiers) return null;

  const { senderId, senderName, provider, senderE164 } = info;

  if (!senderId) return null;

  let entity: Entity | null = null;

  // Check library cache first
  if (getCachedEntity) {
    entity = getCachedEntity(sessionKey) as Entity | null;
  }

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
        if (resolveResult.ok) {
          entity = resolveResult.entity as Entity;
        } else {
          // Conflict: multiple entities matched — safer to skip
          console.error(
            `[turn-context] Entity conflict for sender ${senderName || senderId}: ` +
            `${resolveResult.message}`
          );
          return null;
        }
      }

      if (entity && setCachedEntity) {
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
  if (getEntityProfile) {
    try {
      facts = await Promise.race([
        getEntityProfile(entity.id),
        new Promise<EntityFacts>((resolve) => setTimeout(() => resolve({}), 1000)),
      ]);
    } catch (err) {
      console.error(
        "[turn-context] Entity facts loading error:",
        err instanceof Error ? err.message : String(err)
      );
    }
  }

  const result = formatEntityContext(entity, facts);
  console.log(
    `[turn-context] Loaded entity context for: ${entity.name} (${senderId})`
  );
  return result;
}
