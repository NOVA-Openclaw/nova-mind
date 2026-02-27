/**
 * Agent Config Sync — OpenClaw Extension Plugin
 *
 * Listens to PostgreSQL NOTIFY events on `agent_config_changed` and writes
 * ~/.openclaw/agents.json whenever agent model configuration changes in the DB.
 *
 * Issue #146 — DB-to-Config Sync for Agent Model Configuration
 */

import type {
  OpenClawPluginApi,
  OpenClawPluginServiceContext,
} from "openclaw/plugin-sdk";
import { createRequire } from "node:module";
import { syncAgentsConfig } from "./src/sync.js";
import path from "node:path";
import os from "node:os";

type Logger = OpenClawPluginServiceContext["logger"];

// ── Defaults ────────────────────────────────────────────────────────────────

const DEFAULT_OUTPUT_PATH = path.join(os.homedir(), ".openclaw", "agents.json");
const KEEPALIVE_INTERVAL_MS = 30_000;
const NOTIFY_CHANNEL = "agent_config_changed";
const RECONNECT_DELAY_MS = 5_000;
const MAX_RECONNECT_DELAY_MS = 60_000;

// ── Helpers ─────────────────────────────────────────────────────────────────

function resolveDbConfig(
  pluginConfig: Record<string, unknown> | undefined,
  fullConfig: Record<string, unknown>,
): { host: string; port: number; database: string; user: string; password: string } | null {
  // 1. Try dedicated plugin config
  if (pluginConfig?.database && pluginConfig?.host && pluginConfig?.user) {
    return {
      host: String(pluginConfig.host),
      port: Number(pluginConfig.port ?? 5432),
      database: String(pluginConfig.database),
      user: String(pluginConfig.user),
      password: String(pluginConfig.password ?? ""),
    };
  }

  // 2. Fall back to agent_chat channel config
  const channels = fullConfig.channels as Record<string, unknown> | undefined;
  const agentChat = channels?.agent_chat as Record<string, unknown> | undefined;
  if (agentChat?.database && agentChat?.host && agentChat?.user) {
    return {
      host: String(agentChat.host),
      port: Number(agentChat.port ?? 5432),
      database: String(agentChat.database),
      user: String(agentChat.user),
      password: String(agentChat.password ?? ""),
    };
  }

  return null;
}

// ── Service ─────────────────────────────────────────────────────────────────

function createConfigSyncService(api: OpenClawPluginApi) {
  let pgClient: import("pg").Client | null = null;
  let keepAliveTimer: ReturnType<typeof setInterval> | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;
  let reconnectDelay = RECONNECT_DELAY_MS;

  const outputPath =
    (api.pluginConfig?.outputPath as string | undefined) ?? DEFAULT_OUTPUT_PATH;

  async function startListener(log: Logger): Promise<void> {
    const dbConfig = resolveDbConfig(
      api.pluginConfig as Record<string, unknown> | undefined,
      api.config as unknown as Record<string, unknown>,
    );

    if (!dbConfig) {
      log.error(
        "agent_config_sync: No database config found. " +
          "Configure plugins.entries.agent_config_sync.config or channels.agent_chat.",
      );
      return;
    }

    // Dynamic import to match agent_chat pattern (pg may not be available)
    const pg = await import("pg");
    const client = new pg.default.Client(dbConfig);
    pgClient = client;

    try {
      await client.connect();
      log.info(
        `agent_config_sync: Connected to ${dbConfig.host}:${dbConfig.port}/${dbConfig.database}`,
      );

      // Reset reconnect delay on successful connection
      reconnectDelay = RECONNECT_DELAY_MS;

      // Initial sync on startup
      const changed = await syncAgentsConfig(client, outputPath);
      if (changed) {
        log.info(`agent_config_sync: Initial sync wrote ${outputPath}`);
        log.info("agent_config_sync: Signaling gateway to reload config (SIGUSR1)");
        process.kill(process.pid, "SIGUSR1");
      } else {
        log.info(`agent_config_sync: Initial sync — config already up to date`);
      }

      // Start LISTEN
      await client.query(`LISTEN ${NOTIFY_CHANNEL}`);
      log.info(`agent_config_sync: Listening on channel '${NOTIFY_CHANNEL}'`);

      // Handle notifications
      client.on("notification", async (msg) => {
        if (msg.channel !== NOTIFY_CHANNEL) return;

        log.info("agent_config_sync: Received config change notification");

        try {
          const changed = await syncAgentsConfig(client, outputPath);
          if (changed) {
            log.info(`agent_config_sync: Config updated → ${outputPath}`);
            log.info("agent_config_sync: Signaling gateway to reload config (SIGUSR1)");
            process.kill(process.pid, "SIGUSR1");
          } else {
            log.info("agent_config_sync: Config unchanged after notification");
          }
        } catch (err) {
          log.error(`agent_config_sync: Sync failed: ${err}`);
        }
      });

      // Handle connection errors → reconnect
      client.on("error", (err) => {
        log.error(`agent_config_sync: Connection error: ${err.message}`);
        cleanup();
        scheduleReconnect(log);
      });

      // Keep-alive heartbeat
      keepAliveTimer = setInterval(() => {
        client.query("SELECT 1").catch((err) => {
          log.error(`agent_config_sync: Keep-alive failed: ${err.message}`);
          cleanup();
          scheduleReconnect(log);
        });
      }, KEEPALIVE_INTERVAL_MS);
    } catch (err) {
      log.error(`agent_config_sync: Failed to start: ${err}`);
      cleanup();
      scheduleReconnect(log);
    }
  }

  function cleanup(): void {
    if (keepAliveTimer) {
      clearInterval(keepAliveTimer);
      keepAliveTimer = null;
    }
    if (pgClient) {
      pgClient.end().catch(() => {});
      pgClient = null;
    }
  }

  function scheduleReconnect(log: Logger): void {
    if (stopped) return;
    log.info(
      `agent_config_sync: Reconnecting in ${reconnectDelay / 1000}s...`,
    );
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      if (!stopped) {
        startListener(log).catch((err) => {
          log.error(`agent_config_sync: Reconnect failed: ${err}`);
          // Exponential backoff
          reconnectDelay = Math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY_MS);
          scheduleReconnect(log);
        });
      }
    }, reconnectDelay);
    // Exponential backoff for next attempt
    reconnectDelay = Math.min(reconnectDelay * 2, MAX_RECONNECT_DELAY_MS);
  }

  return {
    id: "agent_config_sync",
    start: async (ctx: OpenClawPluginServiceContext) => {
      stopped = false;
      ctx.logger.info("agent_config_sync: Service starting...");
      await startListener(ctx.logger);
    },
    stop: async (ctx: OpenClawPluginServiceContext) => {
      stopped = true;
      ctx.logger.info("agent_config_sync: Service stopping...");
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
      cleanup();
      ctx.logger.info("agent_config_sync: Service stopped");
    },
  };
}

// ── Plugin Definition ───────────────────────────────────────────────────────

const plugin = {
  id: "agent_config_sync",
  name: "Agent Config Sync",
  description:
    "Syncs agent model configuration from PostgreSQL to ~/.openclaw/agents.json via LISTEN/NOTIFY",

  register(api: OpenClawPluginApi) {
    const log = api.logger;

    // Verify pg is available (use createRequire for ESM compatibility)
    try {
      const require = createRequire(import.meta.url);
      require.resolve("pg");
      log.debug?.("agent_config_sync: pg dependency resolved");
    } catch {
      log.error(
        "agent_config_sync: FATAL — 'pg' module not found. " +
          "Install it with: npm install pg. Plugin will NOT function.",
      );
      return;
    }

    // Register as a gateway service (starts/stops with gateway)
    api.registerService(createConfigSyncService(api));

    log.info("agent_config_sync: Registered ✅");
  },
};

export default plugin;
