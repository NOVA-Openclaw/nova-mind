/**
 * Agent Config Sync — OpenClaw Extension Plugin
 *
 * Listens to PostgreSQL NOTIFY events on `agent_config_changed` and writes
 * ~/.openclaw/agents.json whenever agent model configuration changes in the DB.
 *
 * On OpenClaw 2026.11.3+ (agents.ownership = "explicit"), also writes a
 * managed explicit-ownership include file and ensures openclaw.json loads it.
 *
 * Issue #146 — DB-to-Config Sync for Agent Model Configuration
 * Issue #819 — OpenClaw 2026.11.3 explicit ownership compatibility
 */

import type {
  OpenClawPluginApi,
  OpenClawPluginServiceContext,
} from "openclaw/plugin-sdk";
import { createRequire } from "node:module";
import {
  syncAgentsConfig,
  syncHeartbeatFiles,
  fetchAgentRows,
  syncExplicitOwnershipConfig,
  type OwnershipMode,
} from "./src/sync.js";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

type Logger = OpenClawPluginServiceContext["logger"];

// ── Defaults ────────────────────────────────────────────────────────────────

const DEFAULT_OUTPUT_PATH = path.join(os.homedir(), ".openclaw", "agents.json");
const DEFAULT_OPENCLAW_CONFIG_PATH = path.join(os.homedir(), ".openclaw", "openclaw.json");
const DEFAULT_EXPLICIT_CONFIG_PATH = path.join(
  os.homedir(),
  ".openclaw",
  "agents-explicit.json",
);
const STATE_DIR = path.join(os.homedir(), ".openclaw");
const KEEPALIVE_INTERVAL_MS = 30_000;
const NOTIFY_CHANNEL = "agent_config_changed";
const HEARTBEAT_NOTIFY_CHANNEL = "heartbeat_content_changed";
const RECONNECT_DELAY_MS = 5_000;
const MAX_RECONNECT_DELAY_MS = 60_000;

// ── Helpers ─────────────────────────────────────────────────────────────────

function resolveDbConfig(
  pluginConfig: Record<string, unknown> | undefined,
  fullConfig: Record<string, unknown>,
): { host: string; port: number; database: string; user: string; password: string; query_timeout: number; statement_timeout: number } | null {
  // 1. Try dedicated plugin config
  if (pluginConfig?.database && pluginConfig?.host && pluginConfig?.user) {
    return {
      host: String(pluginConfig.host),
      port: Number(pluginConfig.port ?? 5432),
      database: String(pluginConfig.database),
      user: String(pluginConfig.user),
      password: String(pluginConfig.password ?? ""),
      // Client-side (8s) and server-side (10s) query ceilings. Both are well
      // above the 3s service shutdown deadline, so they never fire during
      // normal operation, but they prevent a hung Postgres/network from
      // blocking a client forever.
      query_timeout: 8000,
      statement_timeout: 10000,
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
      query_timeout: 8000,
      statement_timeout: 10000,
    };
  }

  return null;
}

// ── Ownership mode resolution ───────────────────────────────────────────────

/**
 * Detect the running gateway version from the host.
 *
 * Sources are tried in order:
 * 1. `api.runtime.version` — exposed by OpenClaw 2026.9.6+ to every plugin.
 * 2. `process.env.OPENCLAW_VERSION` — operator override.
 * 3. The `package.json` of the host `openclaw` package resolved from the
 *    gateway entry script (`process.argv[1]`).
 * 4. The `openclaw` package resolved from this plugin's own loader graph.
 *
 * Returns `undefined` when no source can provide a usable version string.
 */
function detectRunningGatewayVersion(api: OpenClawPluginApi): string | undefined {
  // 1. The host gateway exposes its version on api.runtime.version.
  const runtimeVersion = api.runtime?.version;
  if (typeof runtimeVersion === "string" && runtimeVersion.trim().length > 0) {
    return runtimeVersion.trim();
  }

  // 2. Environment override.
  const envVersion = process.env.OPENCLAW_VERSION;
  if (typeof envVersion === "string" && envVersion.trim().length > 0) {
    return envVersion.trim();
  }

  // 3. Resolve the host openclaw package.json from the gateway entry script.
  try {
    const require = createRequire(import.meta.url);
    const gatewayEntry = process.argv[1];
    if (gatewayEntry) {
      const candidate = path.resolve(
        path.dirname(gatewayEntry),
        "node_modules",
        "openclaw",
        "package.json",
      );
      if (fs.existsSync(candidate)) {
        const pkg = JSON.parse(fs.readFileSync(candidate, "utf-8")) as {
          version?: string;
        };
        if (typeof pkg.version === "string" && pkg.version.trim().length > 0) {
          return pkg.version.trim();
        }
      }
    }

    // 4. Fallback: resolve openclaw from this module's loader graph.
    const resolved = require.resolve("openclaw/package.json");
    if (resolved) {
      const pkg = JSON.parse(fs.readFileSync(resolved, "utf-8")) as {
        version?: string;
      };
      if (typeof pkg.version === "string" && pkg.version.trim().length > 0) {
        return pkg.version.trim();
      }
    }
  } catch {
    // Ignore resolution failures; the plugin will fall back to legacy mode.
  }

  return undefined;
}

/**
 * Parse a dotted OpenClaw version string (e.g. "2026.11.3") into numeric
 * [major, minor, patch] components, or null when unparseable.
 */
/** @internal exported for unit tests */
export function parseOpenClawVersion(raw: string | undefined | null): [number, number, number] | null {
  if (typeof raw !== "string" || !raw.trim()) return null;
  // Tolerate legacy dot-beta suffixes like "2026.11.3-beta.1".
  const normalized = raw.trim().replace(/-.*/, "");
  const parts = normalized.split(".").map((p) => Number.parseInt(p, 10));
  if (parts.length < 3 || parts.some((n) => Number.isNaN(n))) return null;
  return [parts[0]!, parts[1]!, parts[2]!];
}

/** @internal exported for unit tests */
export function isOpenClawVersionAtLeast(
  raw: string | undefined | null,
  major: number,
  minor: number,
  patch: number,
): boolean {
  const parsed = parseOpenClawVersion(raw);
  if (!parsed) return false;
  const [vMajor, vMinor, vPatch] = parsed;
  if (vMajor !== major) return vMajor > major;
  if (vMinor !== minor) return vMinor > minor;
  return vPatch >= patch;
}

/**
 * Determine how agents.default should be expressed.
 *
 * The mode is chosen from the VERSION OF THE RUNNING GATEWAY, not from config
 * content (which may have been written by an earlier build):
 *
 * - "explicit" when `agents.ownership` is "explicit".
 * - "explicit" when the running gateway reports a version >= 2026.11.0.
 * - "legacy" when the running gateway reports a version < 2026.11.0.
 * - "legacy" when the version cannot be determined AND agents.ownership is
 *   not "explicit". A loud warning is logged because this emits the
 *   default:true marker; operators on 2026.11.0+ should never see this path
 *   unless the gateway failed to report its version.
 */
/** @internal exported for unit tests */
export function resolveOwnershipMode(
  config: Record<string, unknown>,
  runningVersion: string | undefined,
  log: Logger,
): OwnershipMode {
  const agents = config.agents as Record<string, unknown> | undefined;
  if (agents?.ownership === "explicit") {
    return "explicit";
  }

  if (runningVersion) {
    const parsed = parseOpenClawVersion(runningVersion);
    if (parsed) {
      if (isOpenClawVersionAtLeast(runningVersion, 2026, 11, 0)) {
        return "explicit";
      }
      return "legacy";
    }
    // Version string was provided but unparseable; treat as unknown and warn.
  }

  // Version unknown or unparseable: keep legacy behaviour but warn loudly.
  // Explicit ownership was already handled above, so we never reach here when
  // ownership=explicit.
  log.warn(
    "agent_config_sync: Could not determine running gateway version. " +
      "Assuming legacy mode and emitting the default:true marker for the default agent. " +
      "Set agents.ownership='explicit' to suppress the marker, or run on OpenClaw 2026.11.0+ " +
      "so the gateway can report its version to the plugin.",
  );
  return "legacy";
}

// ── Service ─────────────────────────────────────────────────────────────────

function createConfigSyncService(api: OpenClawPluginApi) {
  let pgClient: import("pg").Client | null = null;
  let keepAliveTimer: ReturnType<typeof setInterval> | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;
  let reconnectDelay = RECONNECT_DELAY_MS;
  const activeWork = new Map<Promise<unknown>, string>();

  function track<T>(promise: Promise<T>, description = "unnamed work"): Promise<T> {
    activeWork.set(promise, description);
    promise.finally(() => activeWork.delete(promise));
    return promise;
  }

  const outputPath =
    (api.pluginConfig?.outputPath as string | undefined) ?? DEFAULT_OUTPUT_PATH;
  const openclawConfigPath =
    (api.pluginConfig?.openclawConfigPath as string | undefined) ??
    DEFAULT_OPENCLAW_CONFIG_PATH;
  const explicitConfigPath =
    (api.pluginConfig?.explicitConfigPath as string | undefined) ??
    DEFAULT_EXPLICIT_CONFIG_PATH;

  async function startListener(log: Logger): Promise<void> {
    const fullConfig = api.config as unknown as Record<string, unknown>;
    const dbConfig = resolveDbConfig(
      api.pluginConfig as Record<string, unknown> | undefined,
      fullConfig,
    );

    if (!dbConfig) {
      log.error(
        "agent_config_sync: No database config found. " +
          "Configure plugins.entries.agent_config_sync.config or channels.agent_chat.",
      );
      return;
    }

    const runningVersion = detectRunningGatewayVersion(api);
    if (!runningVersion) {
      log.warn(
        "agent_config_sync: Unable to determine running gateway version from " +
          "api.runtime.version, OPENCLAW_VERSION, or the host openclaw package.json. " +
          "Falling back to legacy-mode detection.",
      );
    }

    const ownershipMode = resolveOwnershipMode(fullConfig, runningVersion, log);
    log.info(
      `agent_config_sync: Detected ownership mode: '${ownershipMode}' ` +
        `(gateway version: ${runningVersion ?? "unknown"})`,
    );

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

      // Determine default agent name for heartbeat workspace routing and
      // explicit-ownership bindings. This is stable for the lifetime of the
      // listener; a NOTIFY-driven change that would alter it will be picked
      // up on the next gateway restart.
      const agentRows = await fetchAgentRows(client);
      const defaultAgentName =
        agentRows.find((r) => r.is_default === true)?.name ?? "nova";
      log.info(
        `agent_config_sync: Default agent for heartbeat routing: '${defaultAgentName}'`,
      );

      // Initial agents.json sync on startup
      const changed = await syncAgentsConfig(client, outputPath, {
        ownershipMode,
        logger: log,
      });
      if (changed) {
        log.info(`agent_config_sync: Initial sync wrote ${outputPath}`);
        log.info(
          "agent_config_sync: Config file written; gateway watcher will reload on next observation",
        );
      } else {
        log.info(`agent_config_sync: Initial sync — config already up to date`);
      }

      // On OpenClaw 2026.11.3+ with explicit ownership, also write the
      // managed ownership/bindings include and ensure openclaw.json loads it.
      if (ownershipMode === "explicit") {
        try {
          const { explicitChanged, openclawChanged } = await syncExplicitOwnershipConfig(
            client,
            openclawConfigPath,
            explicitConfigPath,
            fullConfig,
            log,
          );
          if (explicitChanged) {
            log.info(
              `agent_config_sync: Explicit ownership config written → ${explicitConfigPath}`,
            );
            log.info(
              "agent_config_sync: Include file written; gateway watcher will reload on next observation",
            );
          }
          if (openclawChanged) {
            log.info(
              `agent_config_sync: openclaw.json updated to include ${explicitConfigPath}`,
            );
          }
          if (!explicitChanged && !openclawChanged) {
            log.info(
              "agent_config_sync: Explicit ownership config already up to date",
            );
          }
        } catch (err) {
          log.error(
            `agent_config_sync: Explicit ownership sync failed: ${err}`,
          );
        }
      }

      // Initial heartbeat sync on startup
      const heartbeatUpdated = await syncHeartbeatFiles(
        client,
        STATE_DIR,
        defaultAgentName,
      );
      if (heartbeatUpdated.length > 0) {
        log.info(
          `agent_config_sync: Initial heartbeat sync updated files for: ${heartbeatUpdated.join(", ")}`,
        );
      } else {
        log.info(
          "agent_config_sync: Initial heartbeat sync — all files up to date",
        );
      }

      // Start LISTEN on agents config channel
      await client.query(`LISTEN ${NOTIFY_CHANNEL}`);
      log.info(`agent_config_sync: Listening on channel '${NOTIFY_CHANNEL}'`);

      // Start LISTEN on heartbeat content channel
      await client.query(`LISTEN ${HEARTBEAT_NOTIFY_CHANNEL}`);
      log.info(
        `agent_config_sync: Listening on channel '${HEARTBEAT_NOTIFY_CHANNEL}'`,
      );

      // Handle notifications
      async function handleNotification(msg: { channel: string; payload?: string }) {
        if (stopped) return;

        if (msg.channel === NOTIFY_CHANNEL) {
          log.info("agent_config_sync: Received agent config change notification");

          try {
            const changed = await syncAgentsConfig(client, outputPath, {
              ownershipMode,
              logger: log,
            });
            if (changed) {
              log.info(`agent_config_sync: Config updated → ${outputPath}`);
              log.info(
                "agent_config_sync: Config file written; gateway watcher will reload on next observation",
              );
            } else {
              log.info("agent_config_sync: Config unchanged after notification");
            }
          } catch (err) {
            log.error(`agent_config_sync: Agents sync failed: ${err}`);
          }

          // #269 — agent_config_changed also triggers HEARTBEAT sync
          // (agents table heartbeat columns may have changed, or content may have updated)
          try {
            const updated = await syncHeartbeatFiles(
              client,
              STATE_DIR,
              defaultAgentName,
            );
            if (updated.length > 0) {
              log.info(
                `agent_config_sync: Heartbeat files updated (via agent_config_changed) for: ${updated.join(", ")}`,
              );
            }
          } catch (err) {
            log.error(`agent_config_sync: Heartbeat sync failed (via agent_config_changed): ${err}`);
          }

          // Re-sync explicit ownership config on agent changes as well.
          if (ownershipMode === "explicit") {
            try {
              const { explicitChanged, openclawChanged } =
                await syncExplicitOwnershipConfig(
                  client,
                  openclawConfigPath,
                  explicitConfigPath,
                  fullConfig,
                  log,
                );
              if (explicitChanged || openclawChanged) {
                log.info(
                  explicitChanged
                    ? `agent_config_sync: Explicit ownership config updated → ${explicitConfigPath}`
                    : "agent_config_sync: Explicit ownership config unchanged",
                );
                if (explicitChanged) {
                  log.info(
                    "agent_config_sync: Include file written; gateway watcher will reload on next observation",
                  );
                }
              }
            } catch (err) {
              log.error(
                `agent_config_sync: Explicit ownership sync failed (via agent_config_changed): ${err}`,
              );
            }
          }
        } else if (msg.channel === HEARTBEAT_NOTIFY_CHANNEL) {
          log.info(
            "agent_config_sync: Received heartbeat content change notification",
          );

          try {
            const updated = await syncHeartbeatFiles(
              client,
              STATE_DIR,
              defaultAgentName,
            );
            if (updated.length > 0) {
              log.info(
                `agent_config_sync: Heartbeat files updated for: ${updated.join(", ")}`,
              );
            } else {
              log.info(
                "agent_config_sync: Heartbeat files unchanged after notification",
              );
            }
          } catch (err) {
            log.error(`agent_config_sync: Heartbeat sync failed: ${err}`);
          }
        }
      }

      client.on("notification", (msg) => {
        return track(
          handleNotification(msg as { channel: string; payload?: string }),
          `${msg.channel} notification handler`,
        );
      });

      // Handle connection errors → reconnect
      client.on("error", (err) => {
        log.error(`agent_config_sync: Connection error: ${err.message}`);
        cleanup().catch(() => {});
        scheduleReconnect(log);
      });

      // Keep-alive heartbeat
      keepAliveTimer = setInterval(() => {
        if (stopped) return;
        track(
          client.query("SELECT 1").catch((err) => {
            log.error(`agent_config_sync: Keep-alive failed: ${err.message}`);
            cleanup().catch(() => {});
            scheduleReconnect(log);
          }),
          "keepalive query",
        );
      }, KEEPALIVE_INTERVAL_MS);
    } catch (err) {
      log.error(`agent_config_sync: Failed to start: ${err}`);
      await cleanup();
      scheduleReconnect(log);
    }
  }

  async function cleanup(): Promise<void> {
    if (keepAliveTimer) {
      clearInterval(keepAliveTimer);
      keepAliveTimer = null;
    }
    if (pgClient) {
      const client = pgClient;
      pgClient = null;
      try {
        await client.end();
      } catch {
        // Ignore close errors during shutdown.
      }
    }
  }

  function forceCloseClient(
    connectionClient: import("pg").Client | null,
    log?: Logger,
  ): void {
    if (!connectionClient) return;
    try {
      const stream = (
        connectionClient as unknown as {
          connection?: { stream?: { destroy?: () => void } };
        }
      ).connection?.stream;
      if (typeof stream?.destroy === "function") {
        stream.destroy();
        log?.info?.("agent_config_sync: Forced PostgreSQL connection closed");
      }
    } catch (error) {
      log?.error?.(`agent_config_sync: Error force-closing connection: ${error}`);
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
        startListener(log).catch(async (err) => {
          log.error(`agent_config_sync: Reconnect failed: ${err}`);
          await cleanup();
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
      if (keepAliveTimer) {
        clearInterval(keepAliveTimer);
        keepAliveTimer = null;
      }

      const SHUTDOWN_DEADLINE_MS = 3000;
      const WORK_BUDGET_MS = 1500;
      const deadline = Date.now() + SHUTDOWN_DEADLINE_MS;

      // Drain in-flight handlers/keepalive queries with a bounded budget. A
      // handler mid-sync can take minutes, so we cap the wait and abandon
      // stragglers. Core forces retirement after 5s; we stay well under it.
      const snapshot = Array.from(activeWork.entries());
      if (snapshot.length > 0) {
        let workTimer: ReturnType<typeof setTimeout> | undefined;
        const workResult = await Promise.race([
          Promise.allSettled(snapshot.map(([promise]) => promise)),
          new Promise<"work-timeout">((resolve) => {
            workTimer = setTimeout(resolve, WORK_BUDGET_MS, "work-timeout");
          }),
        ]);
        if (workTimer) {
          clearTimeout(workTimer);
        }
        if (workResult === "work-timeout") {
          const abandoned = Array.from(activeWork.values());
          ctx.logger.error(
            `agent_config_sync: Shutdown timeout waiting for in-flight work; abandoning ${abandoned.length} pending task(s): ${abandoned.join(", ")}`,
          );
        }
      }

      // Close the client with whatever budget remains. If client.end() hangs
      // on a dead connection, force-close the underlying stream so the call
      // returns instead of waiting for core's forced retirement.
      const clientToClose = pgClient;
      if (clientToClose) {
        pgClient = null;
      }
      const remainingMs = deadline - Date.now();
      if (remainingMs <= 0) {
        ctx.logger.error("agent_config_sync: Shutdown budget exhausted; force-closing connection");
        forceCloseClient(clientToClose, ctx.logger);
      } else {
        let closeTimer: ReturnType<typeof setTimeout> | undefined;
        try {
          const closeResult = await Promise.race([
            (async () => {
              await clientToClose!.query(`UNLISTEN ${NOTIFY_CHANNEL}`);
              await clientToClose!.query(`UNLISTEN ${HEARTBEAT_NOTIFY_CHANNEL}`);
              await clientToClose!.end();
            })(),
            new Promise<"close-timeout">((resolve) => {
              closeTimer = setTimeout(resolve, remainingMs, "close-timeout");
            }),
          ]);
          if (closeTimer) {
            clearTimeout(closeTimer);
          }
          if (closeResult === "close-timeout") {
            ctx.logger.error("agent_config_sync: Shutdown timeout waiting for client.end(); force-closing connection");
            forceCloseClient(clientToClose, ctx.logger);
          }
        } catch (error) {
          ctx.logger.error(`agent_config_sync: Error during shutdown: ${error}`);
          forceCloseClient(clientToClose, ctx.logger);
          if (closeTimer) {
            clearTimeout(closeTimer);
          }
        }
      }

      // After closing the connection, give handler continuations a brief
      // bounded window to settle. Real pg.Client.end() rejects in-flight
      // queries, so handlers should resolve quickly; this prevents the call
      // from leaking unfinished promises.
      if (activeWork.size > 0) {
        await Promise.race([
          Promise.allSettled(Array.from(activeWork.values())),
          new Promise<void>((resolve) => {
            setTimeout(resolve, 500);
          }),
        ]);
      }

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
