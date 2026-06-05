/**
 * Turn Context Plugin — index.ts
 *
 * Consolidates the broken `semantic-recall` and `agent-turn-context` internal
 * hooks into a single Plugin SDK plugin that correctly injects context via
 * `before_prompt_build` (awaited, returns { prependSystemContext, appendSystemContext }).
 *
 * Root causes fixed:
 *   1. Old hooks used `event.messages.push()` on fire-and-forget events —
 *      context never reached the LLM prompt.
 *   2. Old semantic-recall hook used spawnSync, blocking the event loop.
 *
 * Classifier-First Dispatch (issue #150):
 *   Messages are classified before subsystems run. The prompt_helper_config
 *   table gates which subsystems are enabled per message type. Turn reminders
 *   always fire regardless of classification.
 *
 * Prompt composition order:
 *   prependSystemContext + baseSystemPrompt + appendSystemContext
 *
 *   - prependSystemContext: entity identity + domain routing + semantic recall
 *     (BEFORE base system prompt, so LLM has context before reading instructions)
 *   - appendSystemContext:  per-turn reminders only
 *     (AFTER base system prompt, for proximity to user message)
 *
 * Registers two hooks:
 *   - `message_received`    (observation, fire-and-forget) — caches sender info
 *   - `before_prompt_build` (awaited, returns result)       — injects context
 *
 * Issue: nova-mind #182, #150, #140, #168
 * Closes: nova-openclaw #40, nova-openclaw #41
 */

import { getTurnReminders } from "./turn-reminders.ts";
import { resolveEntityContext, type SenderInfo } from "./entity-resolver.ts";
import { runSemanticRecall, type RecallInput } from "./semantic-recall.ts";
import { classifyMessage, type ClassifierResult, type MessageType } from "./classifier.ts";
import { identifyDomain, formatDomainContext, type DomainResult } from "./domain-identifier.ts";
import { getPool } from "./shared/pg-pool.ts";

// ── Sender info cache (message_received → before_prompt_build) ───────────────

interface SenderCache {
  senderId: string;
  senderName: string;
  provider: string;
  senderE164?: string;
  content: string;
  timestamp: number;
}

const CACHE_MAX_SIZE = 1000;
const CACHE_STALE_MS = 30 * 60 * 1000; // 30 minutes

const senderCache = new Map<string, SenderCache>();

function evictStaleCacheEntries(): void {
  const now = Date.now();
  for (const [key, entry] of senderCache.entries()) {
    if (now - entry.timestamp > CACHE_STALE_MS) {
      senderCache.delete(key);
    }
  }
}

function evictOldestIfFull(): void {
  if (senderCache.size < CACHE_MAX_SIZE) return;

  let oldestKey: string | null = null;
  let oldestTime = Infinity;
  for (const [key, entry] of senderCache.entries()) {
    if (entry.timestamp < oldestTime) {
      oldestTime = entry.timestamp;
      oldestKey = key;
    }
  }
  if (oldestKey) senderCache.delete(oldestKey);
}

// ── Prompt Helper Config cache ────────────────────────────────────────────────

interface HelperConfig {
  entity_resolver: boolean;
  semantic_recall: boolean;
  domain_identifier: boolean;
}

interface HelperConfigCacheEntry {
  config: HelperConfig;
  timestamp: number;
}

const HELPER_CONFIG_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes
const helperConfigCache = new Map<string, HelperConfigCacheEntry>();

/**
 * Query prompt_helper_config for the given agent and message type.
 * Agent-specific rows take precedence over default (agent_name IS NULL) rows.
 * Results are cached for 5 minutes to avoid DB round-trips per message.
 */
async function getHelperConfig(agentId: string, messageType: MessageType): Promise<HelperConfig> {
  const cacheKey = `${agentId}:${messageType}`;
  const cached = helperConfigCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < HELPER_CONFIG_CACHE_TTL_MS) {
    return cached.config;
  }

  // Safe defaults — all subsystems enabled if config table is unavailable
  const defaults: HelperConfig = {
    entity_resolver: true,
    semantic_recall: true,
    domain_identifier: true,
  };

  try {
    const pool = getPool();
    const client = await pool.connect();
    try {
      // DISTINCT ON ensures agent-specific config (agent_name IS NOT NULL) takes
      // precedence over default (agent_name IS NULL) when both exist for the same helper.
      const result = await client.query<{ helper_name: string; enabled: boolean }>(
        `SELECT DISTINCT ON (helper_name) helper_name, enabled
         FROM prompt_helper_config
         WHERE message_type = $1
           AND (agent_name = $2 OR agent_name IS NULL)
         ORDER BY helper_name, agent_name NULLS LAST`,
        [messageType, agentId]
      );

      const config: HelperConfig = { ...defaults };
      for (const row of result.rows) {
        if (row.helper_name === "entity_resolver") {
          config.entity_resolver = row.enabled;
        } else if (row.helper_name === "semantic_recall") {
          config.semantic_recall = row.enabled;
        } else if (row.helper_name === "domain_identifier") {
          config.domain_identifier = row.enabled;
        }
      }

      helperConfigCache.set(cacheKey, { config, timestamp: Date.now() });
      return config;
    } finally {
      client.release();
    }
  } catch (err) {
    // Table may not exist yet — use defaults gracefully
    console.warn(
      "[turn-context] prompt_helper_config query failed (using defaults):",
      err instanceof Error ? err.message : String(err)
    );
    return defaults;
  }
}

/**
 * Determine whether a session key represents a group/channel context.
 * Group channels share a session key across multiple senders.
 */
function isGroupSession(sessionKey: string | undefined): boolean {
  if (!sessionKey) return false;
  return sessionKey.includes(":channel:") || sessionKey.includes(":group:");
}

// ── Plugin entry ──────────────────────────────────────────────────────────────

/**
 * Plugin registration function called by the OpenClaw plugin loader.
 * The loader calls module.default(api) to register hooks.
 */
export default function register(api: PluginApi): void {
  console.info("[turn-context] Plugin registered — hooks: message_received, before_prompt_build");

  // ── Hook 1: message_received (observation, fire-and-forget) ──────────────
  //
  // Caches sender info for use in before_prompt_build.
  // No return value; errors are swallowed (must not block message flow).

  api.on("message_received", async (event: PluginEvent, ctx: PluginContext) => {
    try {
      const sessionKey = ctx.sessionKey;
      if (!sessionKey) return;

      // ── Extract all fields synchronously ──────────────────────────────
      const senderId: string | undefined =
        event.senderId ??
        (event.metadata as any)?.senderId;

      const senderName: string | undefined =
        event.senderName ??
        (event.metadata as any)?.senderName;

      const provider: string | undefined =
        ctx.messageProvider ??
        (event.metadata as any)?.provider;

      const senderE164: string | undefined =
        (event.metadata as any)?.senderE164;

      const content: string | undefined =
        event.content ??
        (event as any).context?.content;

      // CRITICAL: Cache write MUST happen before any await or async work.
      // message_received is fire-and-forget — before_prompt_build may fire
      // before this handler's Promise settles.
      // See: nova-mind #182 Step 2 race condition analysis
      senderCache.set(sessionKey, {
        senderId: senderId ?? "",
        senderName: senderName ?? "",
        provider: provider ?? "",
        senderE164,
        content: content ?? "",
        timestamp: Date.now(),
      });

      // Eviction runs AFTER cache write — safe to defer
      evictOldestIfFull();
      evictStaleCacheEntries();
    } catch (err) {
      // Observation-mode hook: swallow all errors
      console.error(
        "[turn-context] message_received cache error:",
        err instanceof Error ? err.message : String(err)
      );
    }
  });

  // ── Hook 2: before_prompt_build (awaited, returns context segments) ────────
  //
  // Classifier-first dispatch:
  //   1. Classify message type (rule-based, ~0ms; Ollama fallback, <2s)
  //   2. Load prompt_helper_config gating from DB (5-min cached)
  //   3. Turn reminders ALWAYS fire (not gated by message type)
  //   4. Run enabled subsystems in parallel (Promise.allSettled)
  //   5. Assemble prependSystemContext + appendSystemContext
  //
  // Subsystem gating:
  //   - entity_resolver:   gated by prompt_helper_config
  //   - domain_identifier: gated by prompt_helper_config
  //   - semantic_recall:   gated by prompt_helper_config
  //   - turn_reminders:    ALWAYS fires regardless of message type
  //
  // Returns prependSystemContext (entity + domain + recall) and
  // appendSystemContext (turn reminders) for injection into the system prompt.
  //
  // Composition: prependSystemContext + baseSystemPrompt + appendSystemContext

  api.on(
    "before_prompt_build",
    async (event: PluginEvent, ctx: PluginContext): Promise<PromptBuildResult | undefined> => {
      const hookStart = Date.now();
      const sessionKey = ctx.sessionKey;
      const agentId: string = ctx.agentId ?? "nova";

      console.info(
        `[turn-context] before_prompt_build START agent=${agentId} session=${sessionKey ?? "none"}`
      );

      // Retrieve cached sender info (may be undefined for first message or
      // if message_received fired from a different process).
      // Check staleness: entries older than CACHE_STALE_MS are treated as expired on read.
      const raw = sessionKey ? senderCache.get(sessionKey) : undefined;
      const cached =
        raw && Date.now() - raw.timestamp < CACHE_STALE_MS ? raw : undefined;

      console.info(
        `[turn-context] Sender cache ${
          cached
            ? `HIT sender=${cached.senderName} content=${cached.content.length}chars`
            : "MISS (no cached sender info)"
        }`
      );

      const isGroup = isGroupSession(sessionKey);

      const senderInfo: SenderInfo = {
        senderId: cached?.senderId,
        senderName: cached?.senderName,
        provider: cached?.provider,
        senderE164: cached?.senderE164,
      };

      // ── Step 1: Classify message type ──────────────────────────────────────
      // Rule-based classification handles ~60-70% of cases without LLM overhead.
      // Ambiguous messages fall back to Ollama (2000ms timeout).
      // On any failure, defaults to 'info_request' so all subsystems fire —
      // better to over-recall than silently suppress recall on classifier error.

      const classifyStart = Date.now();
      let classification: ClassifierResult = { type: "info_request", method: "default" };
      if (cached?.content) {
        try {
          classification = await classifyMessage(cached.content);
        } catch (err) {
          console.warn(
            "[turn-context] Classifier error (defaulting to info_request for safe full recall):",
            err instanceof Error ? err.message : String(err)
          );
        }
      }
      const classifyMs = Date.now() - classifyStart;
      console.info(
        `[turn-context] classifier: type=${classification.type} method=${
          classification.method ?? "?"
        } domainHints=${JSON.stringify(classification.domainHints ?? [])} elapsed=${classifyMs}ms`
      );

      // ── Step 2: Load prompt_helper_config ──────────────────────────────────
      // Determines which subsystems are enabled for this message type.
      // 5-minute cache; falls back to enabling all on query failure.

      let helperConfig: HelperConfig = {
        entity_resolver: true,
        semantic_recall: true,
        domain_identifier: true,
      };
      try {
        helperConfig = await getHelperConfig(agentId, classification.type);
      } catch (err) {
        console.warn(
          "[turn-context] prompt_helper_config load failed (using defaults):",
          err instanceof Error ? err.message : String(err)
        );
      }
      console.info(
        `[turn-context] helper_config: type=${classification.type} ` +
        `entity_resolver=${helperConfig.entity_resolver} ` +
        `semantic_recall=${helperConfig.semantic_recall} ` +
        `domain_identifier=${helperConfig.domain_identifier}`
      );

      // ── Step 2.5: Resolve entity first to get entityId for recall input (#075) ───
      // Entity resolution runs sequentially before recall so the resolved entityId
      // can be threaded into the recall input for visibility-based filtering.
      const entityResolveStart = Date.now();
      let entityContextText: string | null = null;
      let resolvedEntityId: number | null = null;

      if (helperConfig.entity_resolver && sessionKey) {
        try {
          const entityResult = await resolveEntityContext(sessionKey, senderInfo);
          entityContextText = entityResult.text;
          resolvedEntityId = entityResult.entityId;
        } catch (err) {
          console.error(
            "[turn-context] Entity resolution error:",
            err instanceof Error ? err.message : String(err)
          );
        }
      }
      console.info(
        `[turn-context] entity-resolver: ` +
        `${resolvedEntityId != null ? `entityId=${resolvedEntityId}` : "no entity"} ` +
        `elapsed=${Date.now() - entityResolveStart}ms`
      );

      // Build recall input: pass classifier domain hints, resolved entityId, + visibility info
      const recallInput: RecallInput = {
        content: cached?.content ?? "",
        senderId: cached?.senderId ?? "",
        senderName: cached?.senderName ?? "",
        provider: cached?.provider ?? "",
        conversationId: sessionKey ?? "",
        isGroup,
        channelName: "",
        guildId: "",
        messageId: "",
        domainHints: classification.domainHints,
        entityId: resolvedEntityId ?? undefined,  // Now correctly wired (#075)
      };

      // ── Step 3: Run remaining subsystems in parallel ─────────────────────────
      // (Entity resolution ran above to supply entityId to recallInput.)
      // Turn reminders always fire (not gated by helperConfig).
      // Other subsystems are gated by their helperConfig flag.
      //
      // All run via Promise.allSettled so one failure never blocks others.

      console.info(
        `[turn-context] Starting parallel subsystems:` +
        ` turn-reminders=always` +
        ` domain-identifier=${helperConfig.domain_identifier}` +
        ` semantic-recall=${helperConfig.semantic_recall}`
      );
      const subsystemStart = Date.now();

      const [turnRemindersResult, domainIdentifierResult, recallResult] =
        await Promise.allSettled<[
          Promise<string | null>,
          Promise<DomainResult | null>,
          Promise<string | null>,
        ]>([
          // 1. Turn reminders — ALWAYS fires, never gated
          getTurnReminders(agentId).catch((err) => {
            console.error(
              "[turn-context] Turn reminders error:",
              err instanceof Error ? err.message : String(err)
            );
            return null;
          }),

          // 2. Domain identifier — gated by helperConfig
          helperConfig.domain_identifier && cached?.content
            ? identifyDomain(cached.content, classification.domainHints).catch((err) => {
                console.error(
                  "[turn-context] Domain identification error:",
                  err instanceof Error ? err.message : String(err)
                );
                return null as DomainResult | null;
              })
            : Promise.resolve(null as DomainResult | null),

          // 3. Semantic recall — gated by helperConfig
          // Uses classifier domain hints and resolved entityId for domain-scoped
          // and visibility-gated recall (#150, #075)
          helperConfig.semantic_recall && cached?.content
            ? runSemanticRecall(recallInput).catch((err) => {
                console.error(
                  "[turn-context] Semantic recall error:",
                  err instanceof Error ? err.message : String(err)
                );
                return null;
              })
            : Promise.resolve(null),
        ]);

      const subsystemMs = Date.now() - subsystemStart;

      // Resolve settled results
      const remindersOk =
        turnRemindersResult.status === "fulfilled" && turnRemindersResult.value != null;
      const entityOk = entityContextText != null;
      const domainOk =
        domainIdentifierResult.status === "fulfilled" && domainIdentifierResult.value != null;
      const recallOk =
        recallResult.status === "fulfilled" && recallResult.value != null;

      // Structured observability log: per-subsystem timing + tier info
      console.info(
        `[turn-context] Subsystems completed in ${subsystemMs}ms:` +
        ` reminders=${turnRemindersResult.status}` +
        `${remindersOk ? `(${(turnRemindersResult as PromiseFulfilledResult<string>).value!.length}chars)` : ""}` +
        ` entity=${helperConfig.entity_resolver ? (entityOk ? "fulfilled" : "no-entity") : "skipped"}` +
        `${entityOk ? `(${entityContextText!.length}chars entityId=${resolvedEntityId})` : ""}` +
        ` domain=${helperConfig.domain_identifier ? domainIdentifierResult.status : "skipped"}` +
        `${domainOk ? `(${(domainIdentifierResult as PromiseFulfilledResult<DomainResult>).value!.domains.length}matches)` : ""}` +
        ` recall=${helperConfig.semantic_recall ? recallResult.status : "skipped"}` +
        `${recallOk ? `(${(recallResult as PromiseFulfilledResult<string>).value!.length}chars)` : cached?.content ? "(no results)" : "(skipped, no content)"}`
      );
      );

      // ── Build prependSystemContext: entity + domain + recall ──────────────
      // These go BEFORE the base system prompt so the LLM has full context
      // before reading instructions.

      const prependSegments: string[] = [];

      // Entity identity (who is the sender)
      if (entityOk) {
        prependSegments.push(entityContextText!);
      }

      // Domain routing results
      if (domainOk) {
        const domainResultValue = (domainIdentifierResult as PromiseFulfilledResult<DomainResult>).value!;
        const domainContextStr = formatDomainContext(domainResultValue);
        if (domainContextStr) {
          prependSegments.push(domainContextStr);
        } else {
          // Explicitly surface "no domain identified" so agents know routing was attempted
          prependSegments.push("🏷️ Domain: NO DOMAIN IDENTIFIED");
        }
      }

      // Semantic recall memories
      if (recallOk) {
        prependSegments.push((recallResult as PromiseFulfilledResult<string>).value!);
      }

      // ── Build appendSystemContext: per-turn reminders ─────────────────────
      // These go AFTER the base system prompt for proximity to the user message.

      const appendSegments: string[] = [];

      if (remindersOk) {
        appendSegments.push((turnRemindersResult as PromiseFulfilledResult<string>).value!);
      }

      // ── Assemble result ───────────────────────────────────────────────────

      const result: PromptBuildResult = {};
      if (prependSegments.length > 0) {
        result.prependSystemContext = prependSegments.join("\n\n");
      }
      if (appendSegments.length > 0) {
        result.appendSystemContext = appendSegments.join("\n\n");
      }

      const totalMs = Date.now() - hookStart;

      // If all subsystems produced nothing, return undefined (no injection)
      if (Object.keys(result).length === 0) {
        console.info(
          `[turn-context] before_prompt_build DONE in ${totalMs}ms — no context to inject` +
          ` (classifier=${classification.type}/${classification.method})`
        );
        return undefined;
      }

      const prependLen = result.prependSystemContext?.length ?? 0;
      const appendLen = result.appendSystemContext?.length ?? 0;
      console.info(
        `[turn-context] before_prompt_build DONE in ${totalMs}ms —` +
        ` injecting prepend=${prependLen}chars append=${appendLen}chars` +
        ` classifier=${classification.type}/${classification.method}` +
        ` tier=${classification.domainHints?.length ? "domain" : "full_nodomain"}` +
        ` isGroup=${isGroup}`
      );

      return result;
    },
    { timeoutMs: 8000 }
  );
}

// ── Plugin API type stubs ─────────────────────────────────────────────────────
// Minimal type declarations for the Plugin SDK surface we use.
// The actual types come from the OpenClaw plugin loader at runtime.

interface PluginApi {
  on(
    hook: string,
    handler: (event: PluginEvent, ctx: PluginContext) => Promise<void | PromptBuildResult | undefined>,
    options?: { timeoutMs?: number }
  ): void;
}

interface PluginEvent {
  senderId?: string;
  senderName?: string;
  content?: string;
  metadata?: Record<string, unknown>;
  [key: string]: unknown;
}

interface PluginContext {
  sessionKey?: string;
  agentId?: string;
  messageProvider?: string;
  [key: string]: unknown;
}

interface PromptBuildResult {
  prependSystemContext?: string;
  appendSystemContext?: string;
}
