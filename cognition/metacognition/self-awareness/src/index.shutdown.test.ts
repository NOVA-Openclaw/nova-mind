/**
 * Shutdown contract tests for the self-awareness plugin.
 *
 * Verifies that the message_sent hook honours its abort signal and that
 * gateway_stop waits for in-flight work and closes the shared pg.Pool.
 *
 * Issue: nova-openclaw #239 / SE #1475
 */

import { afterEach, beforeEach, describe, it } from "node:test";
import assert from "node:assert/strict";

const SHUTDOWN_BUDGET_MS = 500; // must stay well under core's 5000ms drain

describe("self-awareness shutdown contract", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("aborts a pending embedding fetch and lets gateway_stop close the pool quickly", { timeout: 5000 }, async (t) => {
    const ends: Array<{ calls: number }> = [];
    const queries: string[] = [];
    const fetchCalls: Array<{ url: string; init?: RequestInit }> = [];

    class MockPool {
      endCalls = 0;
      async query(text: string) {
        queries.push(text);
        if (text.includes("self_awareness_triggers")) {
          return {
            rows: [
              {
                id: 1,
                name: "test-trigger",
                category: "test",
                keyphrases: ["foo"],
                keyphrase_embeddings: [[1, 0, 0]],
                similarity_threshold: 1.0,
                action: "log_only",
                action_config: null,
                cooldown_minutes: 0,
                last_triggered_at: null,
                times_triggered: 0,
              },
            ],
          };
        }
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

    let fetchResolve: (value?: any) => void = () => {};
    let fetchReject: (reason?: any) => void = () => {};
    globalThis.fetch = async (url: any, init?: RequestInit): Promise<any> => {
      fetchCalls.push({ url: String(url), init });
      return new Promise((resolve, reject) => {
        fetchResolve = resolve;
        fetchReject = reject;
        const signal = init?.signal as AbortSignal | undefined;
        if (signal) {
          const onAbort = () => {
            signal.removeEventListener("abort", onAbort);
            reject(new Error("AbortError"));
          };
          if (signal.aborted) {
            onAbort();
            return;
          }
          signal.addEventListener("abort", onAbort);
        }
      }) as any;
    };

    const handlers: Record<string, (...args: any[]) => any> = {};
    const api = {
      on: (hook: string, handler: (...args: any[]) => any) => {
        handlers[hook] = handler;
      },
    };

    const { default: register } = await import("./index.ts");
    register(api);

    const controller = new AbortController();
    const runPromise = handlers.message_sent(
      { content: "hello world" },
      { agentId: "nova", abortSignal: controller.signal }
    );

    // The handler itself returns immediately (fire-and-forget). Wait for the
    // background run to reach the embedding fetch.
    await waitFor(() => fetchCalls.length > 0, { timeoutMs: 1000 });

    const stopStart = Date.now();
    controller.abort();
    await handlers.gateway_stop();
    const elapsed = Date.now() - stopStart;

    assert.ok(
      elapsed < SHUTDOWN_BUDGET_MS,
      `gateway_stop took ${elapsed}ms, expected < ${SHUTDOWN_BUDGET_MS}ms`
    );
    assert.ok(
      ends.length > 0 && ends[ends.length - 1].calls > 0,
      "pool.end() was not called by gateway_stop"
    );
    assert.ok(
      fetchCalls.length === 1,
      `expected exactly one embedding fetch, got ${fetchCalls.length}`
    );

    // The embedding fetch must receive the abort signal so that stripping it
    // causes a regression instead of a silent hang.
    assert.ok(
      fetchCalls[0].init?.signal instanceof AbortSignal,
      "embedding fetch should be passed ctx.abortSignal"
    );

    // Avoid leaving the hanging fetch promise unhandled.
    fetchResolve();
    await runPromise;
  });

  it("returns promptly when the hook abort signal is already aborted", { timeout: 5000 }, async (t) => {
    const queries: string[] = [];
    class MockPool {
      async query(text: string) {
        queries.push(text);
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

    globalThis.fetch = async (): Promise<any> => new Promise(() => {}) as any;

    const handlers: Record<string, (...args: any[]) => any> = {};
    const api = {
      on: (hook: string, handler: (...args: any[]) => any) => {
        handlers[hook] = handler;
      },
    };

    const { default: register } = await import("./index.ts");
    register(api);

    const controller = new AbortController();
    controller.abort();

    const start = Date.now();
    const runPromise = handlers.message_sent(
      { content: "hello world" },
      { agentId: "nova", abortSignal: controller.signal }
    );
    await runPromise;
    const elapsed = Date.now() - start;

    assert.ok(
      elapsed < SHUTDOWN_BUDGET_MS,
      `aborted handler took ${elapsed}ms, expected < ${SHUTDOWN_BUDGET_MS}ms`
    );
    assert.equal(
      queries.filter((q) => q.includes("self_awareness_triggers")).length,
      0,
      "DB query should be skipped when already aborted"
    );
  });

  it("waits for an in-flight run to finish before closing the pool", { timeout: 5000 }, async (t) => {
    const queries: string[] = [];
    const ends: number[] = [];
    const fetchCalls: Array<{ url: string; init?: RequestInit }> = [];

    class MockPool {
      async query(text: string) {
        queries.push(text);
        if (text.includes("self_awareness_triggers")) {
          return {
            rows: [
              {
                id: 1,
                name: "test-trigger",
                category: "test",
                keyphrases: ["foo"],
                keyphrase_embeddings: [[1, 0, 0]],
                similarity_threshold: 1.0,
                action: "log_only",
                action_config: null,
                cooldown_minutes: 0,
                last_triggered_at: null,
                times_triggered: 0,
              },
            ],
          };
        }
        return { rows: [] };
      }
      on() {}
      async end() {
        ends.push(1);
      }
    }

    const MockPoolCtor = function () {
      return new MockPool();
    } as unknown as typeof import("pg").Pool;

    (t as any).mock.module("pg", {
      exports: { default: { Pool: MockPoolCtor }, Pool: MockPoolCtor },
    });

    globalThis.fetch = async (url: any, init?: RequestInit): Promise<any> => {
      fetchCalls.push({ url: String(url), init });
      // Delay long enough that gateway_stop is called while the run is still
      // in flight, but short enough to stay well under the work budget.
      await new Promise((resolve) => setTimeout(resolve, 200));
      return { ok: true, json: async () => ({ embedding: [1, 0, 0] }) };
    };

    const handlers: Record<string, (...args: any[]) => any> = {};
    const api = {
      on: (hook: string, handler: (...args: any[]) => any) => {
        handlers[hook] = handler;
      },
    };

    const { default: register } = await import("./index.ts");
    register(api);

    const runPromise = handlers.message_sent(
      { content: "hello world" },
      { agentId: "nova", abortSignal: new AbortController().signal }
    );

    // Let the background run reach the embedding fetch before stopping.
    await waitFor(() => fetchCalls.length > 0, { timeoutMs: 1000 });

    const stopStart = Date.now();
    await handlers.gateway_stop();
    const elapsed = Date.now() - stopStart;

    assert.ok(
      elapsed >= 150,
      `gateway_stop should wait for the in-flight run, but took only ${elapsed}ms`
    );
    assert.ok(
      elapsed < 3000,
      `gateway_stop took ${elapsed}ms, expected < 3000ms`
    );
    assert.ok(
      ends.length > 0,
      "pool.end() was not called by gateway_stop"
    );

    await runPromise;
  });

  it("returns within 4s when pool.end() hangs and force-closes connections", { timeout: 6000 }, async (t) => {
    let endCalled = false;
    let destroyed = false;
    const fetchCalls: Array<{ url: string; init?: RequestInit }> = [];

    class MockPool {
      connection = {
        stream: {
          destroy: () => {
            destroyed = true;
          },
        },
      };
      _clients = [this];

      async query(text: string) {
        if (text.includes("self_awareness_triggers")) {
          return {
            rows: [
              {
                id: 1,
                name: "test-trigger",
                category: "test",
                keyphrases: ["foo"],
                keyphrase_embeddings: [[1, 0, 0]],
                similarity_threshold: 1.0,
                action: "log_only",
                action_config: null,
                cooldown_minutes: 0,
                last_triggered_at: null,
                times_triggered: 0,
              },
            ],
          };
        }
        return { rows: [] };
      }
      on() {}
      async end() {
        endCalled = true;
        // Simulate a pool.end() that never resolves because a checked-out
        // client is stuck on a dead socket.
        return new Promise<void>(() => {});
      }
    }

    const MockPoolCtor = function () {
      return new MockPool();
    } as unknown as typeof import("pg").Pool;

    (t as any).mock.module("pg", {
      exports: { default: { Pool: MockPoolCtor }, Pool: MockPoolCtor },
    });

    globalThis.fetch = async (url: any, init?: RequestInit): Promise<any> => {
      fetchCalls.push({ url: String(url), init });
      return { ok: true, json: async () => ({ embedding: [1, 0, 0] }) };
    };

    const handlers: Record<string, (...args: any[]) => any> = {};
    const api = {
      on: (hook: string, handler: (...args: any[]) => any) => {
        handlers[hook] = handler;
      },
    };

    const { default: register } = await import("./index.ts");
    register(api);

    // Create a pool by running the handler once; let it finish so activeRuns
    // is empty when gateway_stop is called.
    await handlers.message_sent(
      { content: "hello world" },
      { agentId: "nova", abortSignal: new AbortController().signal }
    );
    assert.ok(endCalled === false, "pool.end() should not have been called yet");

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
