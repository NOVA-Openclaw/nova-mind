import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import register from "../src/index.ts";

/**
 * Integration tests for the before_prompt_build hook covering the end-to-end
 * cases in tests/TEST-CASES-ISSUE-712.md that can run without a live staging
 * gateway or live entity DB.
 *
 * Fixture-value derivations:
 * - "discord" is the channel provider used by extractIdentifiers in
 *   entity-resolver.ts for the discordId identifier case.
 * - session keys "sess:A" / "sess:B" and sender ids "123" / "456" are
 *   arbitrary non-empty strings chosen to keep A and B distinct.
 * - "👤 **Talking with:** Alice" and "🧠 **Relevant Context:**..." are the
 *   exact formatted blocks produced by entity-resolver.ts and
 *   semantic-recall.ts respectively (verified by existing node:test suites).
 */

// Capture the handler registered by the plugin.
function makeApi(): {
  pluginConfig: Record<string, unknown>;
  on: (hook: string, handler: unknown, opts?: unknown) => void;
  handler?: (event: unknown, ctx: unknown) => Promise<unknown>;
} {
  const api = {
    pluginConfig: {},
    on: (hook: string, handler: unknown) => {
      if (hook === "before_prompt_build") {
        (api as any).handler = handler;
      }
    },
  };
  return api;
}

// Mocks are hoisted by vitest; keep module shape stable.
vi.mock("../src/shared/pg-pool.ts", () => ({
  getPool: vi.fn(() => ({
    connect: vi.fn(async () => ({
      query: vi.fn(async () => ({ rows: [] })),
      release: vi.fn(),
    })),
  })),
}));

vi.mock("../src/entity-resolver.ts", async () => {
  const actual = await import("../src/entity-resolver.ts");
  return {
    ...actual,
    resolveEntityContext: vi.fn(),
    resolveEntityForGuard: vi.fn(),
  };
});

vi.mock("../src/semantic-recall.ts", () => ({
  runSemanticRecall: vi.fn(),
}));

vi.mock("../src/domain-identifier.ts", () => ({
  identifyDomain: vi.fn(),
  formatDomainContext: vi.fn(() => ""),
}));

vi.mock("../src/turn-reminders.ts", () => ({
  getTurnReminders: vi.fn(),
}));

import { resolveEntityContext, resolveEntityForGuard } from "../src/entity-resolver.ts";
import { runSemanticRecall } from "../src/semantic-recall.ts";
import { identifyDomain, formatDomainContext } from "../src/domain-identifier.ts";
import { getTurnReminders } from "../src/turn-reminders.ts";

describe("before_prompt_build hook (#712 integration)", () => {
  let logs: string[] = [];
  const originalInfo = console.info;
  const originalWarn = console.warn;
  const originalError = console.error;

  beforeEach(() => {
    logs = [];
    console.info = (...args: unknown[]) => {
      logs.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
      originalInfo.apply(console, args);
    };
    console.warn = (...args: unknown[]) => {
      logs.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
      originalWarn.apply(console, args);
    };
    console.error = (...args: unknown[]) => {
      logs.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
      originalError.apply(console, args);
    };

    vi.mocked(resolveEntityContext).mockReset().mockResolvedValue(null as any);
    vi.mocked(resolveEntityForGuard).mockReset().mockResolvedValue({ entityId: null, displayName: null });
    vi.mocked(runSemanticRecall).mockReset().mockResolvedValue(null);
    vi.mocked(identifyDomain).mockReset().mockResolvedValue(null);
    vi.mocked(formatDomainContext).mockReset().mockReturnValue("");
    vi.mocked(getTurnReminders).mockReset().mockResolvedValue(null);
  });

  afterEach(() => {
    console.info = originalInfo;
    console.warn = originalWarn;
    console.error = originalError;
  });

  function baseCtx(overrides: Record<string, unknown> = {}) {
    return {
      sessionKey: "sess:A",
      agentId: "nova",
      channel: "discord",
      senderId: "123",
      chatId: "456",
      ...overrides,
    };
  }

  it("TC-712-001: no 'Sender cache MISS' log is a precondition for success", async () => {
    const api = makeApi();
    register(api);
    vi.mocked(resolveEntityContext).mockResolvedValue({
      text: "👤 **Talking with:** Alice",
      entityId: 1,
      displayName: "Alice",
    });
    vi.mocked(runSemanticRecall).mockResolvedValue(null);
    vi.mocked(getTurnReminders).mockResolvedValue(null);

    await (api.handler as any)(
      { currentUserMessage: "hello" },
      baseCtx()
    );

    expect(logs.some((l) => l.includes("Sender cache"))).toBe(false);
  });

  it("TC-712-002: entity resolves on the first turn of a new session", async () => {
    const api = makeApi();
    register(api);
    vi.mocked(resolveEntityContext).mockResolvedValue({
      text: "👤 **Talking with:** Alice",
      entityId: 1,
      displayName: "Alice",
    });
    vi.mocked(runSemanticRecall).mockResolvedValue(null);
    vi.mocked(getTurnReminders).mockResolvedValue(null);

    const result = await (api.handler as any)(
      { currentUserMessage: "hello" },
      baseCtx()
    );

    expect(result).toBeDefined();
    expect(result.prependSystemContext).toContain("👤 **Talking with:** Alice");
  });

  it("TC-712-004: semantic recall runs for a content-bearing message", async () => {
    const api = makeApi();
    register(api);
    vi.mocked(resolveEntityContext).mockResolvedValue({
      text: "👤 **Talking with:** Alice",
      entityId: 1,
      displayName: "Alice",
    });
    vi.mocked(runSemanticRecall).mockResolvedValue(
      "🧠 **Relevant Context:**\n📝 [memory] (65%): likes typescript"
    );
    vi.mocked(getTurnReminders).mockResolvedValue(null);

    const result = await (api.handler as any)(
      { currentUserMessage: "what do I like?" },
      baseCtx()
    );

    expect(vi.mocked(runSemanticRecall)).toHaveBeenCalled();
    expect(logs.some((l) => l.includes("recall=fulfilled"))).toBe(true);
    expect(result.prependSystemContext).toContain("🧠 **Relevant Context:**");
  });

  it("TC-712-005: recall results are injected into prependSystemContext", async () => {
    const api = makeApi();
    register(api);
    vi.mocked(resolveEntityContext).mockResolvedValue({
      text: "👤 **Talking with:** Alice",
      entityId: 1,
      displayName: "Alice",
    });
    vi.mocked(runSemanticRecall).mockResolvedValue(
      "🧠 **Relevant Context:**\n📝 [memory] (65%): likes typescript"
    );
    vi.mocked(getTurnReminders).mockResolvedValue(null);

    const result = await (api.handler as any)(
      { currentUserMessage: "what do I like?" },
      baseCtx()
    );

    expect(result.prependSystemContext).toContain("likes typescript");
    expect(result.prependSystemContext).toContain("👤 **Talking with:** Alice");
  });

  it("TC-712-015: two interleaved sessions never cross-attribute identity", async () => {
    const api = makeApi();
    register(api);

    vi.mocked(resolveEntityContext).mockImplementation(async (_sessionKey: string, info: any) => {
      // Delay so the two calls overlap in real time.
      await new Promise((r) => setTimeout(r, 50));
      if (info.senderId === "123") {
        return { text: "👤 **Talking with:** Alice", entityId: 1, displayName: "Alice" };
      }
      return { text: "👤 **Talking with:** Bob", entityId: 2, displayName: "Bob" };
    });
    vi.mocked(runSemanticRecall).mockImplementation(async (input: any) => {
      await new Promise((r) => setTimeout(r, 30));
      return `🧠 **Relevant Context:**\n📝 [memory] (${input.senderId}): data`;
    });
    vi.mocked(getTurnReminders).mockResolvedValue(null);

    const [resultA, resultB] = await Promise.all([
      (api.handler as any)(
        { currentUserMessage: "hi" },
        baseCtx({ sessionKey: "sess:A", senderId: "123" })
      ),
      (api.handler as any)(
        { currentUserMessage: "hi" },
        baseCtx({ sessionKey: "sess:B", senderId: "456" })
      ),
    ]);

    expect(resultA.prependSystemContext).toContain("Alice");
    expect(resultA.prependSystemContext).toContain("(123): data");
    expect(resultB.prependSystemContext).toContain("Bob");
    expect(resultB.prependSystemContext).toContain("(456): data");
    // Negative-space: ensure A does not contain B's content and vice versa.
    expect(resultA.prependSystemContext).not.toContain("Bob");
    expect(resultA.prependSystemContext).not.toContain("(456): data");
    expect(resultB.prependSystemContext).not.toContain("Alice");
    expect(resultB.prependSystemContext).not.toContain("(123): data");
  });

  it("TC-712-016: group channel shared by two senders attributes correctly within one sessionKey", async () => {
    const api = makeApi();
    register(api);

    vi.mocked(resolveEntityContext).mockImplementation(async (_sessionKey: string, info: any) => {
      if (info.senderId === "123") {
        return { text: "👤 **Talking with:** Alice", entityId: 1, displayName: "Alice" };
      }
      return { text: "👤 **Talking with:** Bob", entityId: 2, displayName: "Bob" };
    });
    vi.mocked(runSemanticRecall).mockImplementation(async (input: any) => {
      return `🧠 **Relevant Context:**\n📝 [memory] (${input.senderId}): data`;
    });
    vi.mocked(getTurnReminders).mockResolvedValue(null);

    // Both turns share the same sessionKey (group channel).
    const resultA = await (api.handler as any)(
      { currentUserMessage: "hi" },
      baseCtx({ sessionKey: "discord:channel:shared", senderId: "123" })
    );
    const resultB = await (api.handler as any)(
      { currentUserMessage: "hi" },
      baseCtx({ sessionKey: "discord:channel:shared", senderId: "456" })
    );

    expect(resultA.prependSystemContext).toContain("Alice");
    expect(resultB.prependSystemContext).toContain("Bob");
    expect(resultA.prependSystemContext).not.toContain("Bob");
    expect(resultB.prependSystemContext).not.toContain("Alice");
  });
});
