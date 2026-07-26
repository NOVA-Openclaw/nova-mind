/**
 * Entity Resolver subsystem.
 *
 * Resolves the sender's identity via the entity-resolver library and formats
 * their key facts for injection. Results are cached per sessionKey.
 *
 * Ported from ~/.openclaw/hooks/semantic-recall/handler.ts
 * Issue: nova-mind #182
 */

import * as fs from "fs";
import * as os from "os";
import { join } from "path";

// ── Dynamic import of entity-resolver from installed location ─────────────────

// Entity type from dynamic import — use any with runtime property checks
type Entity = any;
type EntityFacts = Record<string, unknown>;

let resolveEntityByIdentifiers: any;
let getEntityProfile: any;
let getCachedEntity: any;
let setCachedEntity: any;
let entityResolverLoaded = false;

async function ensureEntityResolver(): Promise<boolean> {
  if (entityResolverLoaded) return !!resolveEntityByIdentifiers;
  entityResolverLoaded = true;
  try {
    const entityResolverPath = join(os.homedir(), ".openclaw", "lib", "entity-resolver", "index.ts");
    const mod = await import(entityResolverPath);
    resolveEntityByIdentifiers = mod.resolveEntityByIdentifiers;
    getEntityProfile = mod.getEntityProfile;
    getCachedEntity = mod.getCachedEntity;
    setCachedEntity = mod.setCachedEntity;
    return true;
  } catch (err) {
    console.warn("[turn-context] Entity resolver not available:", (err as Error).message);
    // All four functions remain undefined — resolveEntityContext will return null gracefully
    return false;
  }
}

// ── IRC host resolution from OpenClaw config ─────────────────────────────────

interface IrcConfig {
  host?: string;
  defaultAccount?: string;
  accounts?: Record<string, { host?: string }>;
}

interface ChannelsConfig {
  irc?: IrcConfig;
}

interface OpenClawConfigShape {
  channels?: ChannelsConfig;
}

let cachedOpenClawConfig: OpenClawConfigShape | null | undefined;
let openClawConfigPath: string | undefined;

function resolveOpenClawConfigPath(): string {
  if (openClawConfigPath) return openClawConfigPath;
  openClawConfigPath = join(os.homedir(), ".openclaw", "openclaw.json");
  return openClawConfigPath;
}

/** Test seam: override the config path and clear the cache. Returns a restore fn. */
export function setIrcConfigPathForTest(path: string): () => void {
  const previousPath = openClawConfigPath;
  const previousCache = cachedOpenClawConfig;
  openClawConfigPath = path;
  cachedOpenClawConfig = undefined;
  return () => {
    openClawConfigPath = previousPath;
    cachedOpenClawConfig = previousCache;
  };
}

function readOpenClawConfig(): OpenClawConfigShape | null {
  if (cachedOpenClawConfig !== undefined) return cachedOpenClawConfig;
  try {
    const raw = fs.readFileSync(resolveOpenClawConfigPath(), "utf-8");
    cachedOpenClawConfig = JSON.parse(raw) as OpenClawConfigShape;
    return cachedOpenClawConfig;
  } catch (err) {
    console.warn(
      "[turn-context] Could not read openclaw.json:",
      err instanceof Error ? err.message : String(err)
    );
    cachedOpenClawConfig = null;
    return null;
  }
}

/**
 * Determine the IRC server host for a given accountId from OpenClaw config.
 * Falls back from account-specific config to top-level channel config.
 * Returns undefined if no host can be determined.
 *
 * Defensive: config may come from disk and contain unexpected shapes; any
 * read/parse/type error must degrade to undefined so the shared turn-context
 * hook path does not throw synchronously for IRC messages. See nova-mind#522.
 */
export function resolveIrcHostFromConfig(accountId?: string, config?: Record<string, unknown>): string | undefined {
  try {
    const cfg = (config ?? readOpenClawConfig()) as OpenClawConfigShape | null | undefined;
    const irc = cfg?.channels?.irc;
    if (!irc || typeof irc !== "object" || Array.isArray(irc)) return undefined;

    // If an explicit account id is provided, prefer its host, then fall back to top-level.
    if (accountId && accountId !== irc.defaultAccount) {
      const accountHost = irc.accounts?.[accountId]?.host;
      if (typeof accountHost === "string") {
        const trimmed = accountHost.trim();
        if (trimmed) return trimmed;
      }
    }

    const topHost = irc.host;
    if (typeof topHost === "string") {
      const trimmed = topHost.trim();
      if (trimmed) return trimmed;
    }
    return undefined;
  } catch (err) {
    console.warn(
      "[turn-context] IRC host resolution error:",
      err instanceof Error ? err.message : String(err)
    );
    return undefined;
  }
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
  ircUsername?: string;
}

/**
 * Derive an IRC network identifier from a server host.
 * - Lowercases the full host first.
 * - Strips a leading "irc." or "irc-" prefix if present.
 * - Falls back to the full lowercased host when no prefix is present.
 * - Returns null when the host is missing or the stripped result is empty.
 */
export function deriveIrcNetwork(host: string | undefined): string | null {
  if (!host || typeof host !== "string") return null;
  const lower = host.trim().toLowerCase();
  if (!lower) return null;

  let network = lower;
  if (network.startsWith("irc.")) {
    network = network.slice(4);
  } else if (network.startsWith("irc-")) {
    network = network.slice(4);
  }

  if (!network) return null;
  return network;
}

/**
 * Parse the nick portion from an IRC sender identifier.
 * IRC sender ids may be bare nicks or `nick!user@host` masks.
 */
export function parseIrcNick(senderId: string): string | null {
  const trimmed = senderId.trim();
  if (!trimmed) return null;
  const bangIdx = trimmed.indexOf("!");
  const nick = bangIdx >= 0 ? trimmed.slice(0, bangIdx) : trimmed;
  return nick || null;
}

export function extractIdentifiers(
  provider: string | undefined,
  senderId: string | undefined,
  senderE164?: string | undefined,
  options?: { accountId?: string; host?: string; config?: Record<string, unknown> }
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
    case "irc": {
      const host = options?.host ?? resolveIrcHostFromConfig(options?.accountId, options?.config);
      const network = deriveIrcNetwork(host);
      if (!network) return {};

      const nick = parseIrcNick(senderId);
      if (!nick) return {};

      return { ircUsername: `${network}/${nick.toLowerCase()}` };
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
  accountId?: string;
  host?: string;
  config?: Record<string, unknown>;
}

/**
 * Resolve the sender entity and return formatted context text, or null if
 * no entity was found or an error occurred.
 *
 * Cache key is `sessionKey:senderId` to prevent cross-user cache collisions
 * in group channels where multiple senders share a sessionKey.
 *
 * Bugfix: was keyed by sessionKey alone, causing User B to receive User A's
 * cached entity in group channels. See nova-mind #150.
 */
export async function resolveEntityContext(
  sessionKey: string,
  info: SenderInfo
): Promise<{ text: string | null; entityId: number | null; displayName: string | null }> {
  const entity = await resolveEntityOnly(sessionKey, info);

  if (!entity) {
    return { text: null, entityId: null, displayName: null };
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

  const displayName = entity.fullName || entity.name;
  const result = formatEntityContext(entity, facts);
  console.log(
    `[turn-context] Loaded entity context for: ${entity.name} (entityId=${entity.id}) (${info.senderId})`
  );
  return { text: result, entityId: entity.id as number, displayName };
}

/**
 * Lightweight entity resolution for the honorific guard.
 *
 * Returns only the entity id and display name, skipping the entity-facts
 * lookup and text formatting. Uses the same cache key as resolveEntityContext
 * so warm paths hit the same cached entity.
 *
 * Issue: nova-mind #421
 */
export async function resolveEntityForGuard(
  sessionKey: string,
  info: SenderInfo
): Promise<{ entityId: number | null; displayName: string | null }> {
  const entity = await resolveEntityOnly(sessionKey, info);

  if (!entity) {
    return { entityId: null, displayName: null };
  }

  const displayName = entity.fullName || entity.name;
  return { entityId: entity.id as number, displayName };
}

/**
 * Shared entity resolution logic used by resolveEntityContext and
 * resolveEntityForGuard. Handles cache lookup, identifier extraction,
 * database resolution, and caching.
 */
async function resolveEntityOnly(
  sessionKey: string,
  info: SenderInfo
): Promise<Entity | null> {
  // Lazy-load entity resolver — graceful degradation if not installed
  if (!(await ensureEntityResolver())) return null;

  const { senderId, senderName, provider, senderE164, accountId, host, config } = info;

  if (!senderId) return null;

  // Cache key includes both sessionKey AND senderId to prevent cross-user collisions
  // in group channels where sessionKey is shared across all participants.
  const cacheKey = `${sessionKey}:${senderId}`;

  let entity: Entity | null = null;

  // Check library cache first (keyed by sessionKey:senderId)
  if (getCachedEntity) {
    entity = getCachedEntity(cacheKey) as Entity | null;
  }

  if (!entity) {
    const identifiers = extractIdentifiers(provider, senderId, senderE164, { accountId, host, config });
    if (Object.keys(identifiers).length === 0) {
      // Network/host unavailable or unknown provider — no way to resolve
      if (provider === "irc") {
        console.log(`[turn-context] IRC network derivation failed for sender ${senderName || senderId}, skipping entity resolution`);
      } else {
        console.log(`[turn-context] Unknown provider '${provider}', skipping entity resolution`);
      }
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
        setCachedEntity(cacheKey, entity);
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

  return entity;
}
