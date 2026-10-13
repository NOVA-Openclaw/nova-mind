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
 * Registers one hook:
 *   - `before_prompt_build` (awaited, returns result) — injects context
 *
 * Issue: nova-mind #182, #150, #140, #168
 * Closes: nova-openclaw #40, nova-openclaw #41
 */

import { getTurnReminders } from "./turn-reminders.ts";
import { resolveEntityContext, resolveEntityForGuard, type SenderInfo } from "./entity-resolver.ts";
import { buildHonorificGuard } from "./honorific-guard.ts";
import { runSemanticRecall, type RecallInput } from "./semantic-recall.ts";
import { classifyMessage, type ClassifierResult, type MessageType } from "./classifier.ts";
import { identifyDomain, formatDomainContext, type DomainResult } from "./domain-identifier.ts";
import { getPool } from "./shared/pg-pool.ts";

// ── Sender identity from host context (#712) ─────────────────────────────────

interface ChannelContextSender {
  id?: string;
  name?: string;
  displayName?: string;
}
interface ChannelContextChat {
  id?: string;
}

interface ChannelContextShape {
  sender?: ChannelContextSender;
  chat?: ChannelContextChat;
}

export interface ResolvedIdentity {
  senderInfo: SenderInfo;
  content: string;
  warnings: string[];
}

function normalizeStringField(value: unknown, fieldName: string): { value?: string; warning?: string } {
  if (value === undefined || value === null) {
    return {};
  }
  if (typeof value !== "string") {
    return { warning: `${fieldName} has wrong type (expected string, got ${typeof value})` };
  }
  if (value === "") {
    return { warning: `${fieldName} is empty` };
  }
  return { value };
}

/**
 * Resolve sender identity and current-turn content directly from the host
 * context provided to before_prompt_build. The old message_received cache is
 * removed (#712); ctx carries senderId/channel/chatId on OpenClaw 2026.9.x.
 *
 * Defensive: every malformed/absent field produces a warning and degrades
 * gracefully; the function never throws and never returns silently.
 */
export function resolveSenderInfoFromCtx(
  event: PluginEvent,
  ctx: PluginContext,
  api: PluginApi
): ResolvedIdentity {
  const warnings: string[] = [];

  const senderIdResult = normalizeStringField(ctx.senderId, "senderId");
  if (senderIdResult.warning) warnings.push(senderIdResult.warning);

  const chatIdResult = normalizeStringField(ctx.chatId, "chatId");
  if (chatIdResult.warning) warnings.push(chatIdResult.warning);

  const channelResult = normalizeStringField(ctx.channel, "channel");
  if (channelResult.warning) warnings.push(channelResult.warning);

  // Explicitly warn about a missing senderId when the turn is otherwise
  // channel-originated, so operators see why entity resolution is skipped.
  if (!senderIdResult.value && (chatIdResult.value || channelResult.value || ctx.messageProvider)) {
    warnings.push("senderId is missing");
  }

  // Provider: prefer the explicit channel field, fall back to messageProvider.
  const provider = channelResult.value ?? ctx.messageProvider;

  // Sender name from channelContext (rich) or event metadata.
  const channelCtx = ctx.channelContext as ChannelContextShape | undefined;
  let senderName: string | undefined =
    channelCtx?.sender?.name ?? channelCtx?.sender?.displayName;
  if (typeof event.senderName === "string" && event.senderName) {
    senderName = senderName ?? event.senderName;
  }

  // Content for classification/recall: currentUserMessage first, then prompt.
  let content = "";
  if (typeof event.currentUserMessage === "string") {
    content = event.currentUserMessage;
  } else if (typeof event.prompt === "string") {
    content = event.prompt;
  }

  // If we have no identity sources at all, warn once (e.g. cron/heartbeat).
  if (!senderIdResult.value && !chatIdResult.value && !provider) {
    warnings.push("No channel identity available (senderId, channel, chatId all absent)");
  }

  return {
    senderInfo: {
      senderId: senderIdResult.value,
      senderName,
      provider,
      senderE164: (event.metadata as any)?.senderE164,
      accountId: ctx.accountId,
      host:
        (event.metadata as any)?.host ?? (event.metadata as any)?.senderHost,
      config: (api as any).config ?? undefined,
    },
    content,
    warnings,
  };
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
  const placement = resolvePlacement(api.pluginConfig as Record<string, unknown> | undefined);
  console.info(
    `[turn-context] Plugin registered — hooks: before_prompt_build, placement=${placement}`
  );

  // ── Hook: before_prompt_build (awaited, returns context segments) ──────────
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
      const rawAgentId = ctx.agentId;
      const agentId: string = rawAgentId ?? "nova";

      console.info(
        `[turn-context] before_prompt_build START agent=${agentId} session=${sessionKey ?? "none"}`
      );

      const { senderInfo, content, warnings } = resolveSenderInfoFromCtx(event, ctx, api);
      for (const warning of warnings) {
        console.warn(`[turn-context] Identity warning: ${warning}`);
      }

      console.info(
        `[turn-context] Identity resolved senderId=${senderInfo.senderId ?? "none"} ` +
        `provider=${senderInfo.provider ?? "none"} chatId=${ctx.chatId ?? "none"} ` +
        `content=${content.length}chars`
      );

      const isGroup = isGroupSession(sessionKey);

      // ── Step 1: Classify message type ──────────────────────────────────────
      // Rule-based classification handles ~60-70% of cases without LLM overhead.
      // Ambiguous messages fall back to Ollama (2000ms timeout).
      // On any failure, defaults to 'info_request' so all subsystems fire —
      // better to over-recall than silently suppress recall on classifier error.

      const classifyStart = Date.now();
      let classification: ClassifierResult = { type: "info_request", method: "default" };
      if (content) {
        try {
          classification = await classifyMessage(content);
        } catch (err) {
          console.warn(
            "[turn-context] Classifier error (defaulting to conversation for safe recall):",
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
      let resolvedDisplayName: string | null = null;

      if (helperConfig.entity_resolver && sessionKey) {
        try {
          const entityResult = await resolveEntityContext(sessionKey, senderInfo);
          entityContextText = entityResult.text;
          resolvedEntityId = entityResult.entityId;
          resolvedDisplayName = entityResult.displayName;
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

      // ── Step 2.6: Always-on honorific guard (#421) ───────────────────────────
      // Reuses the Step 2.5 result when entity_resolver is enabled (zero extra
      // calls). When entity_resolver is gated OFF, performs its own lightweight
      // resolution so the guard is never skipped. This avoids timeout stacking
      // because only one resolution path runs per turn.
      let guardEntityId: number | null = null;
      let guardDisplayName: string | null = null;

      if (helperConfig.entity_resolver) {
        guardEntityId = resolvedEntityId;
        guardDisplayName = resolvedDisplayName;
      } else if (sessionKey) {
        try {
          const guardResult = await resolveEntityForGuard(sessionKey, senderInfo);
          guardEntityId = guardResult.entityId;
          guardDisplayName = guardResult.displayName;
        } catch (err) {
          console.error(
            "[turn-context] Honorific guard entity resolution error:",
            err instanceof Error ? err.message : String(err)
          );
        }
      }

      if (rawAgentId == null) {
        console.warn(
          "[turn-context] ctx.agentId missing for honorific guard — treating as non-NOVA (fail closed)"
        );
      }

      const honorificGuardText = buildHonorificGuard(
        guardEntityId,
        rawAgentId,
        guardDisplayName ?? undefined
      );

      // Build recall input: pass classifier domain hints, resolved entityId, + visibility info
      const recallInput: RecallInput = {
        content,
        senderId: senderInfo.senderId ?? "",
        senderName: senderInfo.senderName ?? "",
        provider: senderInfo.provider ?? "",
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
          helperConfig.domain_identifier && content
            ? identifyDomain(content, classification.domainHints).catch((err) => {
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
          helperConfig.semantic_recall && content
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
        `${recallOk ? `(${(recallResult as PromiseFulfilledResult<string>).value!.length}chars)` : content ? "(no results)" : "(skipped, no content)"}`
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

      if (honorificGuardText) {
        appendSegments.push(honorificGuardText);
      }

      // ── Assemble result ───────────────────────────────────────────────────

      const result = buildPromptResult(placement, prependSegments, appendSegments);

      const totalMs = Date.now() - hookStart;

      // If all subsystems produced nothing, return undefined (no injection)
      if (Object.keys(result).length === 0) {
        console.info(
          `[turn-context] before_prompt_build DONE in ${totalMs}ms — no context to inject` +
          ` (classifier=${classification.type}/${classification.method})`
        );
        return undefined;
      }

      const prependLen =
        (result.prependSystemContext?.length ?? 0) || (result.prependContext?.length ?? 0);
      const appendLen = result.appendSystemContext?.length ?? 0;
      console.info(
        `[turn-context] before_prompt_build DONE in ${totalMs}ms —` +
        ` placement=${placement} injecting prepend=${prependLen}chars append=${appendLen}chars` +
        ` classifier=${classification.type}/${classification.method}` +
        ` tier=${classification.domainHints?.length ? "domain" : "full_nodomain"}` +
        ` isGroup=${isGroup}`
      );

      return result;
    },
    { timeoutMs: 8000 }
  );
}


// ── Placement helpers ───────────────────────────────────────────────────────

/** Valid placements for the dynamic context block. */
type Placement = "system-prepend" | "turn-prepend";

/**
 * Resolve the configured placement value.
 * Defaults to "system-prepend". Unknown values fall back to the default
 * rather than failing, so a misconfigured plugin never breaks prompts.
 */
export function resolvePlacement(config: Record<string, unknown> | undefined): Placement {
  const raw = config?.placement;
  if (raw === "turn-prepend") return "turn-prepend";
  return "system-prepend";
}

/**
 * Assemble the before_prompt_build return object based on placement.
 *
 * - system-prepend: dynamic entity/domain/recall block -> prependSystemContext
 * - turn-prepend:   dynamic block -> prependContext
 * In both cases turn reminders + honorific guard -> appendSystemContext.
 */
export function buildPromptResult(
  placement: Placement,
  prependSegments: string[],
  appendSegments: string[]
): PromptBuildResult {
  const result: PromptBuildResult = {};

  if (prependSegments.length > 0) {
    const joined = prependSegments.join("\n\n");
    if (placement === "turn-prepend") {
      result.prependContext = joined;
    } else {
      result.prependSystemContext = joined;
    }
  }

  if (appendSegments.length > 0) {
    result.appendSystemContext = appendSegments.join("\n\n");
  }

  return result;
}

// ── Plugin API type stubs ─────────────────────────────────────────────────────
// Minimal type declarations for the Plugin SDK surface we use.
// The actual types come from the OpenClaw plugin loader at runtime.

interface PluginApi {
  pluginConfig?: Record<string, unknown>;
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
  /** Current request before projection (OpenClaw 2026.9.x). */
  currentUserMessage?: string;
  /** Legacy prompt field when currentUserMessage is omitted. */
  prompt?: string;
  [key: string]: unknown;
}

interface PluginContext {
  sessionKey?: string;
  agentId?: string;
  /** Channel/plugin id for channel-originated runs, e.g. `discord`. */
  channel?: string;
  /** Conversation target id for channel-originated runs. */
  chatId?: string;
  /** Sender identity for channel-originated runs when available. */
  senderId?: string;
  messageProvider?: string;
  accountId?: string;
  config?: Record<string, unknown>;
  /** Channel-owned sender/chat details. */
  channelContext?: ChannelContextShape;
  [key: string]: unknown;
}

interface PromptBuildResult {
  prependSystemContext?: string;
  appendSystemContext?: string;
  prependContext?: string;
  appendContext?: string;
}
