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
 * Prompt composition order:
 *   prependSystemContext + baseSystemPrompt + appendSystemContext
 *
 *   - prependSystemContext: entity identity + semantic recall memories
 *     (BEFORE base system prompt, so LLM has context before reading instructions)
 *   - appendSystemContext:  per-turn reminders only
 *     (AFTER base system prompt, for proximity to user message)
 *
 * Registers two hooks:
 *   - `message_received`    (observation, fire-and-forget) — caches sender info
 *   - `before_prompt_build` (awaited, returns result)       — injects context
 *
 * Issue: nova-mind #182
 * Closes: nova-openclaw #40, nova-openclaw #41
 */

import { getTurnReminders } from "./turn-reminders.ts";
import { resolveEntityContext, type SenderInfo } from "./entity-resolver.ts";
import { runSemanticRecall, type RecallInput } from "./semantic-recall.ts";

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
  // Remove stale entries
  for (const [key, entry] of senderCache.entries()) {
    if (now - entry.timestamp > CACHE_STALE_MS) {
      senderCache.delete(key);
    }
  }
}

function evictOldestIfFull(): void {
  if (senderCache.size < CACHE_MAX_SIZE) return;

  // Find oldest entry by timestamp and evict it
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

// ── Plugin entry ──────────────────────────────────────────────────────────────

/**
 * Plugin registration function called by the OpenClaw plugin loader.
 * The loader calls module.default(api) to register hooks.
 */
export default function register(api: PluginApi): void {
  // ── Hook 1: message_received (observation, fire-and-forget) ──────────────
  //
  // Caches sender info for use in before_prompt_build.
  // No return value; errors are swallowed (must not block message flow).

  api.on("message_received", async (event: PluginEvent, ctx: PluginContext) => {
    try {
      const sessionKey = ctx.sessionKey;

      if (!sessionKey) return;

      const senderId: string | undefined =
        event.senderId ??
        (event.metadata as any)?.senderId ??
        (event as any).context?.senderId;

      if (!senderId) return;

      // CRITICAL: Cache write MUST be synchronous and FIRST.
      // message_received is fire-and-forget — if an await precedes this,
      // before_prompt_build may fire before the cache is populated.
      // See: nova-mind #182 Step 2 race condition analysis
      evictOldestIfFull();
      evictStaleCacheEntries();

      const senderName: string | undefined =
        event.senderName ??
        (event.metadata as any)?.senderName ??
        (event as any).context?.senderName;

      const provider: string | undefined =
        ctx.messageProvider ??
        (event.metadata as any)?.provider ??
        (event as any).context?.metadata?.provider;

      const senderE164: string | undefined =
        (event.metadata as any)?.senderE164 ??
        (event as any).context?.metadata?.senderE164;

      const content: string | undefined =
        event.content ??
        (event as any).context?.content ??
        (event as any).context?.message;

      senderCache.set(sessionKey, {
        senderId,
        senderName: senderName ?? "",
        provider: provider ?? "",
        senderE164,
        content: content ?? "",
        timestamp: Date.now(),
      });
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
  // Runs three subsystems in parallel, each with independent error handling.
  // Returns prependSystemContext (entity + recall) and appendSystemContext
  // (turn reminders) for injection into the system prompt.
  //
  // Composition: prependSystemContext + baseSystemPrompt + appendSystemContext

  api.on(
    "before_prompt_build",
    async (event: PluginEvent, ctx: PluginContext): Promise<PromptBuildResult | undefined> => {
      const sessionKey = ctx.sessionKey;
      const agentId: string = ctx.agentId ?? "nova";

      // Retrieve cached sender info (may be undefined for first message or
      // if message_received fired from a different process)
      const cached = sessionKey ? senderCache.get(sessionKey) : undefined;

      const senderInfo: SenderInfo = {
        senderId: cached?.senderId,
        senderName: cached?.senderName,
        provider: cached?.provider,
        senderE164: cached?.senderE164,
      };

      const recallInput: RecallInput = {
        content: cached?.content ?? "",
        senderId: cached?.senderId ?? "",
        senderName: cached?.senderName ?? "",
        provider: cached?.provider ?? "",
        conversationId: sessionKey ?? "",
        isGroup: false,
        channelName: "",
        guildId: "",
        messageId: "",
      };

      // ── Run all three subsystems in parallel ────────────────────────────

      const [turnRemindersResult, entityContextResult, recallResult] =
        await Promise.allSettled([
          // 1. Turn reminders (DB-backed, 5-min cache)
          getTurnReminders(agentId).catch((err) => {
            console.error(
              "[turn-context] Turn reminders error:",
              err instanceof Error ? err.message : String(err)
            );
            return null;
          }),

          // 2. Entity resolution (channel-aware, session-cached)
          sessionKey
            ? resolveEntityContext(sessionKey, senderInfo).catch((err) => {
                console.error(
                  "[turn-context] Entity resolution error:",
                  err instanceof Error ? err.message : String(err)
                );
                return null;
              })
            : Promise.resolve(null),

          // 3. Semantic recall (async spawn of proactive-recall.py)
          cached?.content
            ? runSemanticRecall(recallInput).catch((err) => {
                console.error(
                  "[turn-context] Semantic recall error:",
                  err instanceof Error ? err.message : String(err)
                );
                return null;
              })
            : Promise.resolve(null),
        ]);

      // ── Build prependSystemContext: entity identity + recall memories ─────
      // These go BEFORE the base system prompt so the LLM has full context
      // before reading instructions.

      const prependSegments: string[] = [];

      if (
        entityContextResult.status === "fulfilled" &&
        entityContextResult.value
      ) {
        prependSegments.push(entityContextResult.value);
      }

      if (recallResult.status === "fulfilled" && recallResult.value) {
        prependSegments.push(recallResult.value);
      }

      // ── Build appendSystemContext: per-turn reminders ─────────────────────
      // These go AFTER the base system prompt for proximity to the user message.

      const appendSegments: string[] = [];

      if (
        turnRemindersResult.status === "fulfilled" &&
        turnRemindersResult.value
      ) {
        appendSegments.push(turnRemindersResult.value);
      }

      // ── Assemble result ───────────────────────────────────────────────────

      const result: PromptBuildResult = {};
      if (prependSegments.length > 0) {
        result.prependSystemContext = prependSegments.join("\n\n");
      }
      if (appendSegments.length > 0) {
        result.appendSystemContext = appendSegments.join("\n\n");
      }

      // If all subsystems produced nothing, return undefined (no injection)
      if (Object.keys(result).length === 0) return undefined;

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
