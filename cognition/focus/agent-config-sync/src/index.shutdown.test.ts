/**
 * Shutdown contract tests for the agent_config_sync extension.
 *
 * Verifies that service stop() awaits in-flight NOTIFY handlers and pgClient.end()
 * before logging "Service stopped", and that the whole stop settles well under
 * the gateway's 5000ms disposal budget.
 *
 * Issue: nova-openclaw #239 / SE #1475
 */

import { afterEach, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { EventEmitter } from "node:events";

const SHUTDOWN_BUDGET_MS = 500; // must stay well under core's 5000ms drain
const SHUTDOWN_BUDGET_WITH_WORK_MS = 2500; // allows the 1.5s in-flight work budget to fire

function makeDbPluginConfig(outputPath: string) {
  return {
    outputPath,
    host: "localhost",
    port: 5432,
    database: "test_db",
    user: "test_user",
    password: "test_pass",
  };
}

describe("agent_config_sync shutdown contract", () => {
  let tmpDir: string;
  let outputPath: string;

  beforeEach(async () => {
    tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "acs-shutdown-"));
    outputPath = path.join(tmpDir, "agents.json");
    // Seed the output with the same content the initial sync would produce so
    // syncAgentsConfig returns changed=false and does not SIGUSR1 the test process.
    await fs.promises.writeFile(
      outputPath,
      JSON.stringify({ nova: { model: "ollama/llama3" } }, null, 2) + "\n",
      "utf-8"
    );
  });

  afterEach(async () => {
    await fs.promises.rm(tmpDir, { recursive: true, force: true });
  });

  it("awaits a pending NOTIFY handler and client.end() before returning from stop()", { timeout: 5000 }, async (t) => {
    const logLines: string[] = [];
    const logger = {
      info: (msg: string) => logLines.push(`INFO ${msg}`),
      error: (msg: string) => logLines.push(`ERROR ${msg}`),
      debug: (msg: string) => logLines.push(`DEBUG ${msg}`),
    };

    type PendingQuery = { resolve: (value: any) => void; reject: (reason?: any) => void };
    let pendingQuery: PendingQuery | null = null;
    let endCalled = false;
    let endResolved = false;
    let notifySettled = false;
    let notificationHandler: ((msg: any) => void) | null = null;
    let blockQueries = false;

    class MockClient extends EventEmitter {
      async connect() {}
      async end() {
        endCalled = true;
        // Simulate a real pg.Client.end() that takes nonzero time and aborts
        // in-flight queries when it settles.
        return new Promise<void>((resolve) => {
          setTimeout(() => {
            if (pendingQuery) {
              pendingQuery.reject(new Error("connection closed"));
              pendingQuery = null;
            }
            endResolved = true;
            resolve();
          }, 100);
        });
      }
      async query(text: string) {
        if (endResolved) {
          throw new Error("connection closed");
        }
        if (text.includes("information_schema.columns")) {
          return { rows: [{ exists: true }] };
        }
        if (text.includes("agent_bootstrap_context")) {
          return { rows: [] };
        }
        if (text.includes("get_agent_export_rows()")) {
          if (!blockQueries) {
            return {
              rows: [
                {
                  name: "nova",
                  model: "ollama/llama3",
                  fallback_models: null,
                  thinking: null,
                  instance_type: "primary",
                  is_default: true,
                  allowed_subagents: null,
                  heartbeat_enabled: false,
                },
              ],
            };
          }
          if (pendingQuery) {
            pendingQuery.reject(new Error("superseded"));
          }
          return new Promise((resolve, reject) => {
            pendingQuery = { resolve, reject };
          });
        }
        return { rows: [] };
      }
      on(event: string, handler: (...args: any[]) => void) {
        super.on(event, handler);
        if (event === "notification") {
          notificationHandler = handler;
        }
      }
    }

    const mockPg = {
      default: { Client: MockClient },
      Client: MockClient,
    };

    (t as any).mock.module("pg", {
      exports: { default: mockPg.default, Client: MockClient },
    });

    let service: any;
    const api = {
      pluginConfig: makeDbPluginConfig(outputPath),
      config: {},
      logger,
      registerService: (svc: any) => {
        service = svc;
      },
    };

    const { default: plugin } = await import("../index.ts");
    plugin.register(api);

    await service.start({ logger });

    // Now block get_agent_export_rows queries so the notification handler hangs.
    blockQueries = true;

    // Trigger a notification whose handler will hang on the get_agent_export_rows
    // query until stop() ends the client.
    assert.ok(notificationHandler, "notification handler was not registered");
    const notifyPromise = notificationHandler!({ channel: "agent_config_changed", payload: "" });
    notifyPromise.finally(() => {
      notifySettled = true;
    });

    // Wait until the handler has reached the hanging query so we exercise
    // stop() waiting for in-flight work.
    await waitFor(() => pendingQuery !== null, { timeoutMs: 1000 });

    const stopStart = Date.now();
    await service.stop({ logger });
    const elapsed = Date.now() - stopStart;

    assert.ok(
      elapsed < SHUTDOWN_BUDGET_WITH_WORK_MS,
      `stop() took ${elapsed}ms, expected < ${SHUTDOWN_BUDGET_WITH_WORK_MS}ms`
    );
    assert.ok(endCalled, "pgClient.end() was not called by stop()");
    assert.ok(endResolved, "pgClient.end() was not awaited to completion by stop()");
    assert.ok(notifySettled, "in-flight NOTIFY handler was not awaited by stop()");

    const stoppedIndex = logLines.findIndex((l) => l.includes("Service stopped"));
    const stoppingIndex = logLines.findIndex((l) => l.includes("Service stopping"));
    assert.ok(stoppingIndex >= 0, "missing 'Service stopping' log");
    assert.ok(stoppedIndex > stoppingIndex, "'Service stopped' must be logged after 'Service stopping'");
  });

  it("returns quickly when there is no in-flight work", { timeout: 5000 }, async (t) => {
    const logLines: string[] = [];
    const logger = {
      info: (msg: string) => logLines.push(`INFO ${msg}`),
      error: (msg: string) => logLines.push(`ERROR ${msg}`),
      debug: (msg: string) => logLines.push(`DEBUG ${msg}`),
    };

    class MockClient extends EventEmitter {
      async connect() {}
      async end() {
        return new Promise<void>((resolve) => {
          setTimeout(() => {
            resolve();
          }, 50);
        });
      }
      async query(text: string) {
        if (text.includes("information_schema.columns")) {
          return { rows: [{ exists: true }] };
        }
        if (text.includes("get_agent_export_rows()")) {
          return {
            rows: [
              {
                name: "nova",
                model: "ollama/llama3",
                fallback_models: null,
                thinking: null,
                instance_type: "primary",
                is_default: true,
                allowed_subagents: null,
                heartbeat_enabled: false,
              },
            ],
          };
        }
        return { rows: [] };
      }
    }

    const mockPg = {
      default: { Client: MockClient },
      Client: MockClient,
    };

    (t as any).mock.module("pg", {
      exports: { default: mockPg.default, Client: MockClient },
    });

    let service: any;
    const api = {
      pluginConfig: makeDbPluginConfig(outputPath),
      config: {},
      logger,
      registerService: (svc: any) => {
        service = svc;
      },
    };

    const { default: plugin } = await import("../index.ts");
    plugin.register(api);

    await service.start({ logger });

    const stopStart = Date.now();
    await service.stop({ logger });
    const elapsed = Date.now() - stopStart;

    assert.ok(
      elapsed < SHUTDOWN_BUDGET_MS,
      `stop() took ${elapsed}ms, expected < ${SHUTDOWN_BUDGET_MS}ms`
    );
    assert.ok(
      logLines.some((l) => l.includes("Service stopped")),
      "missing 'Service stopped' log"
    );
  });

  it("returns within 4s when client.end() hangs and destroys the connection", { timeout: 6000 }, async (t) => {
    const logLines: string[] = [];
    const logger = {
      info: (msg: string) => logLines.push(`INFO ${msg}`),
      error: (msg: string) => logLines.push(`ERROR ${msg}`),
      debug: (msg: string) => logLines.push(`DEBUG ${msg}`),
    };

    let clientInstance: MockClient | null = null;

    class MockClient extends EventEmitter {
      ended = false;
      destroyed = false;
      connection = {
        stream: {
          destroy: () => {
            this.destroyed = true;
            this.ended = true;
          },
        },
      };

      constructor(...args: any[]) {
        super(...args);
        clientInstance = this;
      }

      async connect() {}
      async end() {
        this.ended = true;
        // Simulate a client.end() that never resolves.
        return new Promise<void>(() => {});
      }
      async query(text: string) {
        if (text.includes("information_schema.columns")) {
          return { rows: [{ exists: true }] };
        }
        if (text.includes("get_agent_export_rows()")) {
          return {
            rows: [
              {
                name: "nova",
                model: "ollama/llama3",
                fallback_models: null,
                thinking: null,
                instance_type: "primary",
                is_default: true,
                allowed_subagents: null,
                heartbeat_enabled: false,
              },
            ],
          };
        }
        return { rows: [] };
      }
    }

    const mockPg = {
      default: { Client: MockClient },
      Client: MockClient,
    };

    (t as any).mock.module("pg", {
      exports: { default: mockPg.default, Client: MockClient },
    });

    let service: any;
    const api = {
      pluginConfig: makeDbPluginConfig(outputPath),
      config: {},
      logger,
      registerService: (svc: any) => {
        service = svc;
      },
    };

    const { default: plugin } = await import("../index.ts");
    plugin.register(api);

    await service.start({ logger });

    const stopStart = Date.now();
    await service.stop({ logger });
    const elapsed = Date.now() - stopStart;

    assert.ok(
      elapsed < 4000,
      `stop() took ${elapsed}ms, expected < 4000ms`
    );
    assert.ok(
      logLines.some((l) => l.includes("force-closing connection")),
      "expected force-close log when client.end() hangs"
    );
    assert.ok(
      clientInstance?.destroyed,
      "connection stream was not destroyed when client.end() hung"
    );
  });
});

async function waitFor(
  predicate: () => boolean,
  { timeoutMs = 1000, intervalMs = 5 } = {}
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve, reject) => {
    const check = () => {
      if (predicate()) return resolve();
      if (Date.now() > deadline) {
        return reject(new Error("waitFor timed out"));
      }
      setTimeout(check, intervalMs);
    };
    check();
  });
}
