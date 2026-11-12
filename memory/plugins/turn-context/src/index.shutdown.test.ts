/**
 * Shutdown contract tests for the turn-context plugin.
 *
 * Verifies that before_prompt_build returns promptly when aborted, that the
 * proactive-recall.py child is killed on abort, and that gateway_stop closes
 * the shared pg.Pool.
 *
 * Issue: nova-openclaw #239 / SE #1475
 */

import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { setEntityResolverPathForTest } from "./entity-resolver.ts";

const SHUTDOWN_BUDGET_MS = 500; // must stay well under core's 5000ms drain

describe("turn-context shutdown contract", () => {
  let restoreEntityResolverPath: () => void;

  before(() => {
    // Disable the real entity-resolver dynamic import so it does not pull in
    // additional PG pools or side effects during shutdown tests.
    restoreEntityResolverPath = setEntityResolverPathForTest(
      "/nonexistent/entity-resolver-for-shutdown-test.ts"
    );
  });

  after(() => {
    restoreEntityResolverPath();
  });

  it("kills the semantic-recall child and returns promptly when aborted", { timeout: 5000 }, async (t) => {
    const ends: Array<{ calls: number }> = [];
    const spawnCalls: Array<{ args: any[]; child: MockChild }> = [];

    class MockClient {
      async query(text: string) {
        if (text.includes("prompt_helper_config")) {
          return { rows: [] };
        }
        if (text.includes("get_agent_turn_context")) {
          return { rows: [{ content: "", truncated: false, records_skipped: 0, total_chars: 0 }] };
        }
        if (text.includes("information_schema.columns")) {
          return { rows: [{ exists: false }] };
        }
        if (text.includes("agent_domains")) {
          return { rows: [] };
        }
        return { rows: [] };
      }
      release() {}
    }

    class MockPool {
      endCalls = 0;
      async connect() {
        return new MockClient();
      }
      async query() {
        return { rows: [] };
      }
      on() {}
      async end() {
        this.endCalls++;
        ends.push({ calls: this.endCalls });
      }
    }

    const MockPoolCtor = function () {
      return new MockPool();
    } as unknown as typeof import("pg").Pool;

    (t as any).mock.module("pg", {
      exports: { default: { Pool: MockPoolCtor }, Pool: MockPoolCtor },
    });

    class MockChild extends EventEmitter {
      stdin = {
        write: () => {},
        end: () => {},
      };
      stdout = new EventEmitter();
      stderr = new EventEmitter();
      killedWith: string | null = null;
      kill(signal?: string) {
        this.killedWith = signal ?? "SIGTERM";
        // Defer close so the abort path (not the timeout) is exercised.
        setTimeout(() => this.emit("close", 1), 5);
      }
    }

    function mockSpawn(command: string, args: string[]) {
      const child = new MockChild();
      spawnCalls.push({ args: [command, args], child });
      return child;
    }

    (t as any).mock.module("child_process", {
      exports: { spawn: mockSpawn },
    });

    const handlers: Record<string, (...args: any[]) => any> = {};
    const api = {
      pluginConfig: {},
      on: (hook: string, handler: (...args: any[]) => any) => {
        handlers[hook] = handler;
      },
    };

    const { default: register } = await import("./index.ts");
    register(api);

    const controller = new AbortController();
    const hookPromise = handlers.before_prompt_build(
      { currentUserMessage: "hello world" },
      {
        agentId: "nova",
        sessionKey: "test:discord:channel:1",
        abortSignal: controller.signal,
      }
    );

    await waitFor(() => spawnCalls.length > 0, { timeoutMs: 1000 });

    const stopStart = Date.now();
    controller.abort();
    const result = await hookPromise;
    const elapsed = Date.now() - stopStart;

    assert.ok(
      elapsed < SHUTDOWN_BUDGET_MS,
      `before_prompt_build took ${elapsed}ms after abort, expected < ${SHUTDOWN_BUDGET_MS}ms`
    );
    assert.equal(
      result,
      undefined,
      "aborted hook should return undefined"
    );
    assert.equal(spawnCalls.length, 1, "expected exactly one recall spawn");
    assert.equal(
      spawnCalls[0].child.killedWith,
      "SIGTERM",
      "proactive-recall.py should be killed on abort"
    );

    await handlers.gateway_stop();
    assert.ok(
      ends.length > 0 && ends[ends.length - 1].calls > 0,
      "pool.end() was not called by gateway_stop"
    );
  });

  it("returns undefined immediately when already aborted", { timeout: 5000 }, async (t) => {
    const spawnCalls: Array<{ args: any[]; child: MockChild }> = [];

    class MockPool {
      async connect() {
        return {
          query: async () => ({ rows: [] }),
          release: () => {},
        };
      }
      async query() {
        return { rows: [] };
      }
      on() {}
      async end() {}
    }
    const MockPoolCtor = function () {
      return new MockPool();
    } as unknown as typeof import("pg").Pool;

    (t as any).mock.module("pg", {
      exports: { default: { Pool: MockPoolCtor }, Pool: MockPoolCtor },
    });

    class MockChild extends EventEmitter {
      stdin = { write: () => {}, end: () => {} };
      stdout = new EventEmitter();
      stderr = new EventEmitter();
      kill() {}
    }
    function mockSpawn(command: string, args: string[]) {
      const child = new MockChild();
      spawnCalls.push({ args: [command, args], child });
      return child;
    }
    (t as any).mock.module("child_process", {
      exports: { spawn: mockSpawn },
    });

    const handlers: Record<string, (...args: any[]) => any> = {};
    const api = {
      pluginConfig: {},
      on: (hook: string, handler: (...args: any[]) => any) => {
        handlers[hook] = handler;
      },
    };

    const { default: register } = await import("./index.ts");
    register(api);

    const controller = new AbortController();
    controller.abort();

    const start = Date.now();
    const result = await handlers.before_prompt_build(
      { currentUserMessage: "hello world" },
      {
        agentId: "nova",
        sessionKey: "test:discord:channel:1",
        abortSignal: controller.signal,
      }
    );
    const elapsed = Date.now() - start;

    assert.ok(
      elapsed < SHUTDOWN_BUDGET_MS,
      `already-aborted hook took ${elapsed}ms, expected < ${SHUTDOWN_BUDGET_MS}ms`
    );
    assert.equal(result, undefined);
    assert.equal(spawnCalls.length, 0, "no child should be spawned when already aborted");
  });

  it("returns within 4s when pool.end() hangs and force-closes connections", { timeout: 6000 }, async (t) => {
    let endCalled = false;
    let destroyed = false;

    class MockPool {
      connection = {
        stream: {
          destroy: () => {
            destroyed = true;
          },
        },
      };
      _clients = [this];

      async connect() {
        return {
          query: async () => ({ rows: [] }),
          release: () => {},
        };
      }
      async query() {
        return { rows: [] };
      }
      on() {}
      async end() {
        endCalled = true;
        // Simulate a hung pool.end() that never resolves.
        return new Promise<void>(() => {});
      }
    }

    const MockPoolCtor = function () {
      return new MockPool();
    } as unknown as typeof import("pg").Pool;

    (t as any).mock.module("pg", {
      exports: { default: { Pool: MockPoolCtor }, Pool: MockPoolCtor },
    });

    const handlers: Record<string, (...args: any[]) => any> = {};
    const api = {
      pluginConfig: {},
      on: (hook: string, handler: (...args: any[]) => any) => {
        handlers[hook] = handler;
      },
    };

    const { getPool } = await import("./shared/pg-pool.ts");
    await getPool();

    const { default: register } = await import("./index.ts");
    register(api);

    const stopStart = Date.now();
    await handlers.gateway_stop();
    const elapsed = Date.now() - stopStart;

    assert.ok(
      elapsed < 4000,
      `gateway_stop took ${elapsed}ms, expected < 4000ms`
    );
    assert.ok(endCalled, "pool.end() was not called by gateway_stop");
    assert.ok(
      destroyed,
      "connection stream was not force-destroyed when pool.end() hung"
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
