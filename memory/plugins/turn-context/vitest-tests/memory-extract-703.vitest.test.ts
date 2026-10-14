import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import register, {
  handleMessageReceived,
  resolveMemoryDatabase,
  peerDbCache,
  resetForTests,
} from "../../../hooks/memory-extract/handler.ts";

/**
 * Unit tests for #703: memory-extract handler must resolve the current
 * gateway's own memory database (PGDATABASE or ~/.openclaw/postgres.json),
 * never fall back to a hardcoded nova_memory literal.
 *
 * Fixture-value derivations:
 * - Tests set $HOME to a temp directory so production code's os.homedir() reads
 *   a hermetic ~/.openclaw/postgres.json instead of the real one.
 * - "lex" is one of NOVA's 27 subagents listed in the orchestrator review.
 * - "newhart" is one of the three real peer agents; its DB name follows the
 *   <peer>_memory pattern.
 * - "graybeard_memory" is used for the cross-peer guard: a newhart-prefixed
 *   session must not write into graybeard's DB.
 * - "bastion" is a synthetic peer subagent; bastion_memory does not exist, so
 *   a bastion-prefixed session on victoria_memory is allowed.
 * - "nonexistent_peer_memory" is a synthetic PGDATABASE value ending in
 *   _memory that the mocked DB layer reports as not existing (TC-703-008).
 * - Mocked psql stdout "42" / "99" are arbitrary synthetic ids.
 */

vi.mock("child_process", () => ({
  spawn: vi.fn(),
  execFile: vi.fn(),
}));

import { spawn, execFile } from "child_process";

function makeHomeDir(): string {
  return mkdtempSync(join(tmpdir(), "memory-extract-703-"));
}

function makePostgresConfig(homeDir: string, database: string): void {
  const dir = join(homeDir, ".openclaw");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "postgres.json"), JSON.stringify({ database }));
}

function cleanupHomeDir(homeDir: string): void {
  try {
    rmSync(homeDir, { recursive: true, force: true });
  } catch {}
}

/**
 * Return a mock Python child that exits successfully. Used as the default
 * spawn implementation so tests that do reach extraction don't crash on
 * undefined streams.
 */
function makeSuccessfulChild(): any {
  return {
    stdin: { write: vi.fn(), end: vi.fn() },
    stdout: { on: vi.fn() },
    stderr: { on: vi.fn() },
    kill: vi.fn(),
    killed: false,
    on: vi.fn((event: string, handler: any) => {
      if (event === "close") handler(0, null);
    }),
  };
}

/**
 * Configure the mocked execFile so psql calls return sensible results:
 * - SELECT 1 FROM pg_database WHERE datname = '<agent>_memory' returns "1\n"
 *   when agent is in existsFor, otherwise "".
 * - INSERT INTO channel_sessions returns "42\n".
 * - INSERT INTO channel_transcripts returns "99\n".
 * - Everything else returns "".
 *
 * Callbacks receive (error, stdout, stderr) as strings; this matches both the
 * module-level promisified wrapper and the direct Promise wrapper used by the
 * peer-DB guard.
 */
function mockPsql(existsFor: Set<string> = new Set()): void {
  vi.mocked(execFile).mockImplementation((_cmd: any, args: any, cb: any) => {
    if (!Array.isArray(args)) {
      cb(null, "", "");
      return {} as any;
    }
    const sql = args.find((a: any) => typeof a === "string" && a.includes("SELECT 1 FROM pg_database"));
    if (sql) {
      const match = sql.match(/datname = '([^']+)'/);
      const dbName = match ? match[1] : "";
      const owner = dbName.replace(/_memory$/, "");
      cb(null, existsFor.has(owner) ? "1\n" : "", "");
      return {} as any;
    }
    if (args.includes("INSERT INTO channel_sessions")) {
      cb(null, "42\n", "");
    } else if (args.includes("INSERT INTO channel_transcripts")) {
      cb(null, "99\n", "");
    } else {
      cb(null, "", "");
    }
    return {} as any;
  });
}

describe("resolveMemoryDatabase (#703)", () => {
  let originalPgDatabase: string | undefined;
  let originalHome: string | undefined;
  let homeDir: string;

  beforeEach(() => {
    originalPgDatabase = process.env.PGDATABASE;
    originalHome = process.env.HOME;
    homeDir = makeHomeDir();
    process.env.HOME = homeDir;
    delete process.env.PGDATABASE;
    vi.mocked(execFile).mockReset();
    peerDbCache.clear();
  });

  afterEach(() => {
    if (originalPgDatabase === undefined) delete process.env.PGDATABASE;
    else process.env.PGDATABASE = originalPgDatabase;
    if (originalHome === undefined) delete process.env.HOME;
    else process.env.HOME = originalHome;
    cleanupHomeDir(homeDir);
  });

  it("resolves from ~/.openclaw/postgres.json when PGDATABASE is unset", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    await expect(resolveMemoryDatabase("agent:nova:discord:channel:123")).resolves.toBe("nova_memory");
  });

  it("PGDATABASE overrides postgres.json", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    process.env.PGDATABASE = "newhart_memory";
    await expect(resolveMemoryDatabase("agent:newhart:agent_chat")).resolves.toBe("newhart_memory");
  });

  it("fails loudly when neither PGDATABASE nor postgres.json provides a DB", async () => {
    await expect(resolveMemoryDatabase("agent:nova:discord:channel:123")).rejects.toThrow(
      /Could not resolve memory database/
    );
  });

  it("fails loudly when resolved DB name does not end with _memory", async () => {
    makePostgresConfig(homeDir, "not_a_memory_db");
    await expect(resolveMemoryDatabase("agent:nova:discord:channel:123")).rejects.toThrow(
      /does not look like a memory database/
    );
  });

  it("allows NOVA subagent 'lex' against nova_memory", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();
    await expect(resolveMemoryDatabase("agent:lex:agent_chat")).resolves.toBe("nova_memory");
  });

  it("allows an arbitrary new subagent name against nova_memory", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();
    await expect(resolveMemoryDatabase("agent:futurebot:agent_chat")).resolves.toBe("nova_memory");
  });

  it("allows a peer's subagent 'bastion' on victoria_memory when bastion_memory does not exist", async () => {
    process.env.PGDATABASE = "victoria_memory";
    mockPsql(new Set(["victoria"]));
    await expect(resolveMemoryDatabase("agent:bastion:agent_chat")).resolves.toBe("victoria_memory");
  });

  it("cross-peer guard rejects newhart session against graybeard_memory when graybeard_memory exists", async () => {
    process.env.PGDATABASE = "graybeard_memory";
    mockPsql(new Set(["graybeard", "newhart"]));
    await expect(resolveMemoryDatabase("agent:newhart:agent_chat")).rejects.toThrow(
      /Cross-peer guard/
    );
  });

  it("cross-peer guard rejects graybeard session against newhart_memory when graybeard_memory exists", async () => {
    process.env.PGDATABASE = "newhart_memory";
    mockPsql(new Set(["graybeard", "newhart"]));
    await expect(resolveMemoryDatabase("agent:graybeard:agent_chat")).rejects.toThrow(
      /Cross-peer guard/
    );
  });

  it("no sessionKey resolves from env and skips the cross-peer guard", async () => {
    process.env.PGDATABASE = "nova_memory";
    mockPsql();
    await expect(resolveMemoryDatabase("")).resolves.toBe("nova_memory");
  });

  it("no sessionKey throws when the database cannot be resolved", async () => {
    await expect(resolveMemoryDatabase("")).rejects.toThrow(
      /Could not resolve memory database/
    );
  });
});

describe("memory-extract handler DB resolution (#703 integration)", () => {
  let originalPgDatabase: string | undefined;
  let originalHome: string | undefined;
  let homeDir: string;
  let errors: string[] = [];
  let logger: { debug: any; info: any; warn: any; error: any };
  let api: { logger: typeof logger; pluginConfig: Record<string, unknown>; on: any; handlers: Record<string, any> };

  function makeApiForTest(): typeof api {
    logger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn((msg: string) => errors.push(msg)),
    };
    return {
      logger,
      pluginConfig: {},
      on: vi.fn((hook: string, handler: unknown) => {
        (api as any).handlers[hook] = handler;
      }),
      handlers: {},
    } as any;
  }

  beforeEach(() => {
    originalPgDatabase = process.env.PGDATABASE;
    originalHome = process.env.HOME;
    homeDir = makeHomeDir();
    process.env.HOME = homeDir;
    // Give register() a resolvable DB so its startup INFO line fires, then
    // clear the captured log so each test only sees errors from the message
    // handler. Tests that specifically need unresolved DB delete this below.
    process.env.PGDATABASE = "nova_memory";
    errors = [];
    api = makeApiForTest();
    resetForTests();
    register(api);
    errors.length = 0;
    vi.mocked(spawn).mockImplementation(() => makeSuccessfulChild() as any);
    vi.mocked(execFile).mockReset();
    peerDbCache.clear();
  });

  afterEach(() => {
    if (originalPgDatabase === undefined) delete process.env.PGDATABASE;
    else process.env.PGDATABASE = originalPgDatabase;
    if (originalHome === undefined) delete process.env.HOME;
    else process.env.HOME = originalHome;
    cleanupHomeDir(homeDir);
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

  async function triggerHandler(event: any): Promise<void> {
    await handleMessageReceived(event);
  }

  it("TC-703-007: no PGDATABASE and no postgres.json fails loudly", async () => {
    delete process.env.PGDATABASE;

    await triggerHandler(makeEvent());

    expect(errors.some((e) => e.includes("reason=db_unresolved"))).toBe(true);
    expect(vi.mocked(execFile)).not.toHaveBeenCalled();
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("TC-703-008: PGDATABASE set to a nonexistent DB fails loudly without fallback or Python spawn", async () => {
    process.env.PGDATABASE = "nonexistent_peer_memory";
    vi.mocked(execFile).mockImplementation((_cmd: any, args: any, cb: any) => {
      if (Array.isArray(args) && args[0] === "nonexistent_peer_memory") {
        cb(
          new Error('FATAL: database "nonexistent_peer_memory" does not exist'),
          "",
          ""
        );
        return {} as any;
      }
      cb(null, "", "");
      return {} as any;
    });

    await triggerHandler(makeEvent({ sessionKey: "agent:nova:discord:channel:123" }));

    expect(errors.some((e) => e.includes("reason=db_unreachable"))).toBe(true);
    expect(errors.some((e) => e.includes("db=nonexistent_peer_memory"))).toBe(true);
    expect(errors.some((e) => e.includes("nova_memory"))).toBe(false);
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("TC-703-002: resolvable peer DB passes resolution and uses it for psql", async () => {
    process.env.PGDATABASE = "newhart_memory";
    mockPsql(new Set(["newhart"]));

    await triggerHandler(makeEvent({ sessionKey: "agent:newhart:agent_chat" }));

    expect(errors.some((e) => e.includes("reason=db_unresolved"))).toBe(false);
    expect(errors.some((e) => e.includes("reason=db_unreachable"))).toBe(false);
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
    mockPsql(new Set(["graybeard", "newhart"]));

    await triggerHandler(makeEvent({ sessionKey: "agent:newhart:agent_chat" }));

    expect(errors.some((e) => e.includes("reason=peer_guard_refused"))).toBe(true);
    // The guard itself performs one catalog lookup; no data writes or Python
    // extraction should be attempted.
    const psqlCalls = vi.mocked(execFile).mock.calls.filter((c) => c[0] === "psql");
    expect(psqlCalls.length).toBe(1);
    expect((psqlCalls[0][1] as string[]).join(" ")).toContain("pg_database");
    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
  });

  it("TC-703-009c: session_key missing agent prefix still resolves to a valid DB", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await triggerHandler(makeEvent({ sessionKey: "discord:channel:123" }));

    // No agent prefix means the cross-peer guard is not applicable; the DB
    // still resolves from config and processing continues.
    expect(errors.some((e) => e.includes("reason=db_unresolved"))).toBe(false);
    expect(errors.some((e) => e.includes("reason=db_unreachable"))).toBe(false);
    const psqlCalls = vi.mocked(execFile).mock.calls.filter((c) => c[0] === "psql");
    expect(psqlCalls.length).toBeGreaterThan(0);
  });

  it("passes resolved PGDATABASE to the Python child explicitly", async () => {
    delete process.env.PGDATABASE;
    makePostgresConfig(homeDir, "newhart_memory");
    mockPsql();

    await triggerHandler(makeEvent({ sessionKey: "agent:newhart:agent_chat" }));

    expect(vi.mocked(spawn)).toHaveBeenCalled();
    const spawnEnv = vi.mocked(spawn).mock.calls[0][2]?.env as Record<string, string> | undefined;
    expect(spawnEnv?.PGDATABASE).toBe("newhart_memory");
  });
});
