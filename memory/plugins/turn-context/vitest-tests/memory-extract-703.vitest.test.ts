import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import handler from "../../../hooks/memory-extract/handler.ts";

/**
 * Unit tests for #703: memory-extract handler must fail loudly when the peer
 * memory database cannot be resolved, instead of falling back to nova_memory.
 *
 * Fixture-value derivations:
 * - graybeard/newhart/victoria are the three real peer agents identified in
 *   tests/TEST-CASES-ISSUE-708.md §1b.
 * - athena is NOVA's subagent and therefore maps to nova_memory, per the same
 *   design section.
 * - "totallymadeuppeer" and "agent:badprefix" are the malformed/unknown inputs
 *   from TC-703-009.
 * - Mocked psql stdout "42" / "99" are arbitrary synthetic ids returned by the
 *   session and transcript upserts so the handler reaches the extraction spawn.
 */

vi.mock("child_process", () => ({
  spawn: vi.fn(),
  execFile: vi.fn(),
}));

import { spawn, execFile } from "child_process";

describe("memory-extract handler DB resolution (#703)", () => {
  let originalPgDatabase: string | undefined;
  const errors: string[] = [];
  const originalError = console.error;

  beforeEach(() => {
    originalPgDatabase = process.env.PGDATABASE;
    errors.length = 0;
    console.error = (...args: unknown[]) => {
      errors.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
      originalError.apply(console, args);
    };
    vi.mocked(spawn).mockReset();
    vi.mocked(execFile).mockReset();
  });

  afterEach(() => {
    if (originalPgDatabase === undefined) {
      delete process.env.PGDATABASE;
    } else {
      process.env.PGDATABASE = originalPgDatabase;
    }
    console.error = originalError;
  });

  function makeEvent(overrides: Record<string, unknown> = {}): any {
    return {
      type: "message",
      action: "received",
      sessionKey: "agent:nova:discord:channel:123",
      context: {
        content: "This is a reasonably long test message for extraction.",
        metadata: {},
      },
      ...overrides,
    };
  }

  function mockPsqlForHappyPath(): void {
    vi.mocked(execFile).mockImplementation((_cmd: any, args: any, cb: any) => {
      if (Array.isArray(args) && args.includes("INSERT INTO channel_sessions")) {
        cb(null, "42\n", "");
      } else if (Array.isArray(args) && args.includes("INSERT INTO channel_transcripts")) {
        cb(null, "99\n", "");
      } else {
        cb(null, "", "");
      }
      return {} as any;
    });
  }

  it("TC-703-007: PGDATABASE unset fails loudly and does not write to nova_memory", async () => {
    delete process.env.PGDATABASE;

    await handler(makeEvent());

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(true);
    expect(errors.some((e) => e.includes("PGDATABASE is not set"))).toBe(true);
    expect(vi.mocked(execFile)).not.toHaveBeenCalled();
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("TC-703-008: PGDATABASE set to nonexistent DB still fails loudly (no fallback)", async () => {
    // Use a name that survives the `_memory` suffix sanity check but does not
    // match the session's expected peer database, so resolution fails before
    // any connection is attempted.
    process.env.PGDATABASE = "nonexistentpeer_memory";

    await handler(makeEvent({ sessionKey: "agent:newhart:agent_chat" }));

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(true);
    expect(errors.some((e) => e.includes("PGDATABASE mismatch"))).toBe(true);
    expect(vi.mocked(execFile)).not.toHaveBeenCalled();
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("TC-703-002: resolvable peer DB passes resolution and uses it for psql", async () => {
    process.env.PGDATABASE = "newhart_memory";
    mockPsqlForHappyPath();

    await handler(makeEvent({ sessionKey: "agent:newhart:agent_chat" }));

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(false);
    const psqlCalls = vi.mocked(execFile).mock.calls.filter((c) => c[0] === "psql");
    expect(psqlCalls.length).toBeGreaterThan(0);
    for (const call of psqlCalls) {
      const dbArg = (call[1] as string[])[0];
      expect(dbArg).toBe("newhart_memory");
      expect(dbArg).not.toBe("nova_memory");
    }
  });

  it("TC-703-009a: session_key/env mismatch fails loudly", async () => {
    process.env.PGDATABASE = "newhart_memory";

    await handler(makeEvent({ sessionKey: "agent:nova:agent_chat" }));

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(true);
    expect(errors.some((e) => e.includes("PGDATABASE mismatch"))).toBe(true);
    expect(vi.mocked(execFile)).not.toHaveBeenCalled();
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("TC-703-009b: unknown peer segment fails loudly", async () => {
    process.env.PGDATABASE = "totallymadeuppeer_memory";

    await handler(makeEvent({ sessionKey: "agent:totallymadeuppeer:x" }));

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(true);
    expect(errors.some((e) => e.includes("Unknown agent"))).toBe(true);
    expect(vi.mocked(execFile)).not.toHaveBeenCalled();
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("TC-703-009c: session_key missing agent prefix fails loudly", async () => {
    process.env.PGDATABASE = "nova_memory";

    await handler(makeEvent({ sessionKey: "discord:channel:123" }));

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(true);
    expect(errors.some((e) => e.includes("Cannot derive agent"))).toBe(true);
    expect(vi.mocked(execFile)).not.toHaveBeenCalled();
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("athena maps to nova_memory as a NOVA subagent", async () => {
    process.env.PGDATABASE = "nova_memory";
    mockPsqlForHappyPath();

    await handler(makeEvent({ sessionKey: "agent:athena:agent_chat" }));

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(false);
    const psqlCalls = vi.mocked(execFile).mock.calls.filter((c) => c[0] === "psql");
    expect(psqlCalls.length).toBeGreaterThan(0);
    for (const call of psqlCalls) {
      expect((call[1] as string[])[0]).toBe("nova_memory");
    }
  });
});
