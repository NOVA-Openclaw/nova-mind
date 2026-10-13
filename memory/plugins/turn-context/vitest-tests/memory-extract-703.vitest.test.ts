import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, writeFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import handler, { resolveMemoryDatabase } from "../../../hooks/memory-extract/handler.ts";

/**
 * Unit tests for #703: memory-extract handler must resolve the current
 * gateway's own memory database (PGDATABASE or ~/.openclaw/postgres.json),
 * never fall back to a hardcoded nova_memory literal.
 *
 * Fixture-value derivations:
 * - Tests point at a temp postgres.json via OPENCLAW_POSTGRES_CONFIG_OVERRIDE
 *   so they never read the real ~/.openclaw/postgres.json.
 * - "lex" is one of NOVA's 27 subagents listed in the orchestrator review.
 * - "newhart" is one of the three real peer agents; its DB name follows the
 *   <peer>_memory pattern.
 * - "graybeard_memory" is used for the cross-peer guard: a newhart-prefixed
 *   session must not write into graybeard's DB.
 * - Mocked psql stdout "42" / "99" are arbitrary synthetic ids.
 */

vi.mock("child_process", () => ({
  spawn: vi.fn(),
  execFile: vi.fn(),
}));

import { spawn, execFile } from "child_process";

function makePostgresConfig(database: string): string {
  const dir = mkdtempSync(join(tmpdir(), "memory-extract-703-"));
  const path = join(dir, "postgres.json");
  writeFileSync(path, JSON.stringify({ database }));
  return path;
}

function cleanupPostgresConfig(path: string): void {
  try {
    rmSync(join(path, ".."), { recursive: true, force: true });
  } catch {}
}

describe("resolveMemoryDatabase (#703)", () => {
  let originalPgDatabase: string | undefined;
  let originalOverride: string | undefined;

  beforeEach(() => {
    originalPgDatabase = process.env.PGDATABASE;
    originalOverride = process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE;
    delete process.env.PGDATABASE;
    // Point away from the real ~/.openclaw/postgres.json so tests are hermetic.
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = join(tmpdir(), "memory-extract-703-missing-postgres.json");
  });

  afterEach(() => {
    if (originalPgDatabase === undefined) delete process.env.PGDATABASE;
    else process.env.PGDATABASE = originalPgDatabase;
    if (originalOverride === undefined) delete process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE;
    else process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = originalOverride;
  });

  it("resolves from OPENCLAW_POSTGRES_CONFIG_OVERRIDE when PGDATABASE is unset", () => {
    const configPath = makePostgresConfig("nova_memory");
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = configPath;
    try {
      expect(resolveMemoryDatabase("agent:nova:discord:channel:123")).toBe("nova_memory");
    } finally {
      cleanupPostgresConfig(configPath);
    }
  });

  it("PGDATABASE overrides postgres.json", () => {
    const configPath = makePostgresConfig("nova_memory");
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = configPath;
    process.env.PGDATABASE = "newhart_memory";
    try {
      expect(resolveMemoryDatabase("agent:newhart:agent_chat")).toBe("newhart_memory");
    } finally {
      cleanupPostgresConfig(configPath);
    }
  });

  it("fails loudly when neither PGDATABASE nor postgres.json provides a DB", () => {
    expect(() => resolveMemoryDatabase("agent:nova:discord:channel:123")).toThrow(
      /Could not resolve memory database/
    );
  });

  it("fails loudly when resolved DB name does not end with _memory", () => {
    const configPath = makePostgresConfig("not_a_memory_db");
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = configPath;
    try {
      expect(() => resolveMemoryDatabase("agent:nova:discord:channel:123")).toThrow(
        /does not look like a memory database/
      );
    } finally {
      cleanupPostgresConfig(configPath);
    }
  });

  it("allows NOVA subagent 'lex' against nova_memory", () => {
    const configPath = makePostgresConfig("nova_memory");
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = configPath;
    try {
      expect(resolveMemoryDatabase("agent:lex:agent_chat")).toBe("nova_memory");
    } finally {
      cleanupPostgresConfig(configPath);
    }
  });

  it("allows an arbitrary new subagent name against nova_memory", () => {
    const configPath = makePostgresConfig("nova_memory");
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = configPath;
    try {
      expect(resolveMemoryDatabase("agent:futurebot:agent_chat")).toBe("nova_memory");
    } finally {
      cleanupPostgresConfig(configPath);
    }
  });

  it("cross-peer guard rejects newhart session against graybeard_memory", () => {
    process.env.PGDATABASE = "graybeard_memory";
    expect(() => resolveMemoryDatabase("agent:newhart:agent_chat")).toThrow(
      /Cross-peer guard/
    );
  });
});

describe("memory-extract handler DB resolution (#703 integration)", () => {
  let originalPgDatabase: string | undefined;
  let originalOverride: string | undefined;
  const errors: string[] = [];
  const originalError = console.error;

  beforeEach(() => {
    originalPgDatabase = process.env.PGDATABASE;
    originalOverride = process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE;
    delete process.env.PGDATABASE;
    // Point away from the real ~/.openclaw/postgres.json so tests are hermetic.
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = join(tmpdir(), "memory-extract-703-missing-postgres.json");
    errors.length = 0;
    console.error = (...args: unknown[]) => {
      errors.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
      originalError.apply(console, args);
    };
    vi.mocked(spawn).mockReset();
    vi.mocked(execFile).mockReset();
  });

  afterEach(() => {
    if (originalPgDatabase === undefined) delete process.env.PGDATABASE;
    else process.env.PGDATABASE = originalPgDatabase;
    if (originalOverride === undefined) delete process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE;
    else process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = originalOverride;
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

  it("TC-703-007: no PGDATABASE and no postgres.json fails loudly", async () => {
    await handler(makeEvent());

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(true);
    expect(errors.some((e) => e.includes("Could not resolve memory database"))).toBe(true);
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

  it("TC-703-009a: session_key/env mismatch triggers cross-peer guard", async () => {
    process.env.PGDATABASE = "graybeard_memory";

    await handler(makeEvent({ sessionKey: "agent:newhart:agent_chat" }));

    expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(true);
    expect(errors.some((e) => e.includes("Cross-peer guard"))).toBe(true);
    expect(vi.mocked(execFile)).not.toHaveBeenCalled();
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("TC-703-009c: session_key missing agent prefix still resolves to a valid DB", async () => {
    const configPath = makePostgresConfig("nova_memory");
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = configPath;
    mockPsqlForHappyPath();

    try {
      await handler(makeEvent({ sessionKey: "discord:channel:123" }));

      // No agent prefix means the cross-peer guard is not applicable; the DB
      // still resolves from config and processing continues.
      expect(errors.some((e) => e.includes("Database resolution failed"))).toBe(false);
      const psqlCalls = vi.mocked(execFile).mock.calls.filter((c) => c[0] === "psql");
      expect(psqlCalls.length).toBeGreaterThan(0);
    } finally {
      cleanupPostgresConfig(configPath);
    }
  });

  it("passes resolved PGDATABASE to the Python child explicitly", async () => {
    const configPath = makePostgresConfig("newhart_memory");
    process.env.OPENCLAW_POSTGRES_CONFIG_OVERRIDE = configPath;
    mockPsqlForHappyPath();

    try {
      await handler(makeEvent({ sessionKey: "agent:newhart:agent_chat" }));

      expect(vi.mocked(spawn)).toHaveBeenCalled();
      const spawnEnv = vi.mocked(spawn).mock.calls[0][2]?.env as Record<string, string> | undefined;
      expect(spawnEnv?.PGDATABASE).toBe("newhart_memory");
    } finally {
      cleanupPostgresConfig(configPath);
    }
  });
});
