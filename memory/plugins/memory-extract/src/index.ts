/**
 * Memory Extract — OpenClaw plugin entry point.
 *
 * Migrates the legacy internal `memory-extract` hook into a proper
 * nova-mind plugin (#726).  The plugin:
 *   * captures `api.logger` at registration time (#716)
 *   * subscribes to `message_received` and maps sender fields from the
 *     host-provided event/context (#708)
 *   * emits the #716 startup/shutdown lifecycle lines from
 *     `gateway_start`/`gateway_stop`
 *
 * The extraction implementation lives in `./extraction.ts` and is shared
 * with the legacy-hook wrapper so #703/#708/#716 behaviour is unchanged.
 */

import {
  handleMessageReceived,
  setModuleLogger,
  emitShutdown,
  emitStartupInfo,
  createDefaultLogger,
  type PluginLogger,
} from "./extraction.ts";

// ── Host-contract types (read-only references) ─────────────────────────────
//
// Cited from /home/nova/nova-openclaw-production (2026.9.x):
//   * PluginLogger          — src/plugins/logger-types.ts:1-7
//   * message_received      — src/plugins/hook-types.ts:1126-1129
//     event: PluginHookMessageReceivedEvent
//     ctx:   PluginHookMessageContext
//   * gateway_start/stop    — src/plugins/hook-types.ts:1182-1186
//     event shapes          — src/plugins/hook-gateway.types.ts:18-22
//
// The host shapes are reproduced here as minimal stubs so the plugin builds
// without depending on the private fork source tree.

interface PluginMessageReceivedEvent {
  /** Event.from is the sender display name on the plugin contract. */
  from?: string;
  content: string;
  threadId?: string | number;
  messageId?: string;
  senderId?: string;
  sessionKey?: string;
  metadata?: Record<string, unknown>;
}

interface PluginMessageContext {
  channelId?: string;
  accountId?: string;
  conversationId?: string;
  sessionKey?: string;
  messageId?: string;
  senderId?: string;
}

interface PluginGatewayStartEvent {
  port: number;
}

interface PluginGatewayStopEvent {
  reason?: string;
}

interface PluginApi {
  logger: PluginLogger;
  pluginConfig?: Record<string, unknown>;
  on(
    hook: "message_received",
    handler: (event: PluginMessageReceivedEvent, ctx: PluginMessageContext) => Promise<void> | void
  ): void;
  on(
    hook: "gateway_start",
    handler: (event: PluginGatewayStartEvent) => Promise<void> | void
  ): void;
  on(
    hook: "gateway_stop",
    handler: (event: PluginGatewayStopEvent) => Promise<void> | void
  ): void;
}

/**
 * Convert the plugin `message_received` event/context into the legacy
 * event shape expected by the shared extraction core.  This keeps the
 * mapping table explicit and testable.
 */
export function buildLegacyEvent(
  event: PluginMessageReceivedEvent,
  ctx: PluginMessageContext
): any {
  const meta = (event.metadata ?? {}) as Record<string, unknown>;

  return {
    type: "message",
    action: "received",
    sessionKey: ctx.sessionKey ?? event.sessionKey ?? "",
    threadId: event.threadId ?? meta.threadId ?? undefined,
    context: {
      content: event.content,
      metadata: {
        senderName: meta.senderName ?? event.from ?? "unknown",
        senderId: meta.senderId ?? ctx.senderId ?? event.senderId ?? "",
        isGroup: meta.isGroup ?? false,
        senderUsername: meta.senderUsername ?? "",
        senderTag: meta.senderTag ?? "",
        provider: meta.provider ?? ctx.channelId ?? "openclaw",
        channelName: meta.channelName ?? "",
        guildId: meta.guildId ?? "",
        conversationId: ctx.conversationId ?? meta.conversationId ?? "",
        messageId: event.messageId ?? meta.messageId ?? "",
        accountId: ctx.accountId ?? meta.accountId ?? "",
      },
    },
  };
}

function resolveConfigFromApi(pluginConfig: Record<string, unknown> | undefined): {
  summaryIntervalMs?: number;
  stallThresholdMs?: number;
  stallRepeatIntervalMs?: number;
  stallCheckIntervalMs?: number;
  dbUnresolvedRateLimitMs?: number;
} {
  if (!pluginConfig) return {};
  const pick = (key: string): number | undefined => {
    const value = pluginConfig[key];
    if (typeof value === "number" && Number.isFinite(value) && value > 0) {
      return value;
    }
    return undefined;
  };
  return {
    summaryIntervalMs: pick("summaryIntervalMs"),
    stallThresholdMs: pick("stallThresholdMs"),
    stallRepeatIntervalMs: pick("stallRepeatIntervalMs"),
    stallCheckIntervalMs: pick("stallCheckIntervalMs"),
    dbUnresolvedRateLimitMs: pick("dbUnresolvedRateLimitMs"),
  };
}

export default function register(api: PluginApi): void {
  // Capture the logger handed to us by the host at registration time.
  // The host contract (plugin-api.types.ts:202) places logger on the
  // registration API, not on hook contexts, so we must store it now.
  const configOverride = resolveConfigFromApi(api.pluginConfig);
  setModuleLogger(api.logger, configOverride);

  // Subscribe to inbound messages.
  api.on("message_received", async (event, ctx) => {
    const legacyEvent = buildLegacyEvent(event, ctx);
    await handleMessageReceived(legacyEvent);
  });

  // Startup line: idempotent guard inside emitStartupInfo() ensures it
  // fires exactly once even if both register() and gateway_start run.
  api.on("gateway_start", async () => {
    emitStartupInfo();
  });

  // Shutdown line with session totals.
  api.on("gateway_stop", async () => {
    emitShutdown();
  });
}

// Re-export the shared core so the legacy wrapper and tests can import
// from one canonical location.
export {
  handleMessageReceived,
  resolveMemoryDatabase,
  peerDbCache,
  resetForTests,
  setModuleLogger,
  emitShutdown,
  getSessionCounters,
  getSummaryCounters,
  getLastSuccessfulStoreAt,
  createDefaultLogger,
} from "./extraction.ts";
