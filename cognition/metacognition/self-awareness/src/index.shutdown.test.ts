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

  it("aborts a pending embedding fetch and lets gateway_stop close the pool quickly", async (t) => {
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

    // Avoid leaving the hanging fetch promise unhandled.
    fetchResolve();
    await runPromise;
  });

  it("returns promptly when the hook abort signal is already aborted", async (t) => {
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
