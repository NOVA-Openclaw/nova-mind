import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

/**
 * Unit tests for nova-mind#309: SecretRef migration for the memory-extract
 * plugin and extraction child environment.
 */

vi.mock("child_process", () => ({
  spawn: vi.fn(),
  execFile: vi.fn(),
}));

import { spawn, execFile } from "child_process";
import {
  handleMessageReceived,
  resetForTests,
  setModuleLogger,
  getExtractionApiKey,
  setExtractionApiKey,
} from "../src/extraction.ts";

function makeHomeDir(): string {
  return mkdtempSync(join(tmpdir(), "memory-extract-309-"));
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

function mockPsql(): void {
  vi.mocked(execFile).mockImplementation((_cmd: any, args: any, cb: any) => {
    if (!Array.isArray(args)) {
      cb(null, "", "");
      return {} as any;
    }
    const sql = args.find(
      (a: any) => typeof a === "string" && a.includes("SELECT 1 FROM pg_database")
    );
    if (sql) {
      cb(null, "", "");
      return {} as any;
    }
    const sqlArg = args.find((a: any) => typeof a === "string" && a.includes("INSERT INTO"));
    if (sqlArg && sqlArg.includes("INSERT INTO channel_sessions")) {
      cb(null, "42\n", "");
    } else if (sqlArg && sqlArg.includes("INSERT INTO channel_transcripts")) {
      cb(null, "99\n", "");
    } else {
      cb(null, "", "");
    }
    return {} as any;
  });
}

function makeMockLogger(): {
  debug: ReturnType<typeof vi.fn>;
  info: ReturnType<typeof vi.fn>;
  warn: ReturnType<typeof vi.fn>;
  error: ReturnType<typeof vi.fn>;
} {
  return {
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  };
}

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

function captureSpawnEnv(): Record<string, string | undefined> | undefined {
  const calls = vi.mocked(spawn).mock.calls;
  const last = calls[calls.length - 1];
  if (!last) return undefined;
  const opts = last[2] as any;
  return opts?.env;
}

describe("#309 SecretRef extraction environment", () => {
  let originalPgDatabase: string | undefined;
  let originalHome: string | undefined;
  let originalOpenRouterKey: string | undefined;
  let homeDir: string;

  beforeEach(() => {
    originalPgDatabase = process.env.PGDATABASE;
    originalHome = process.env.HOME;
    originalOpenRouterKey = process.env.OPENROUTER_API_KEY;
    homeDir = makeHomeDir();
    process.env.HOME = homeDir;
    delete process.env.PGDATABASE;
    delete process.env.OPENROUTER_API_KEY;

    vi.useRealTimers();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-11-20T00:00:00.000Z"));

    vi.mocked(spawn).mockReset();
    vi.mocked(execFile).mockReset();
    resetForTests();
  });

  afterEach(() => {
    if (originalPgDatabase === undefined) delete process.env.PGDATABASE;
    else process.env.PGDATABASE = originalPgDatabase;
    if (originalHome === undefined) delete process.env.HOME;
    else process.env.HOME = originalHome;
    if (originalOpenRouterKey === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = originalOpenRouterKey;

    cleanupHomeDir(homeDir);
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  // ── MIND-01: resolved key from plugin config is injected into child env ──
  it("MIND-01: injects resolved OPENROUTER_API_KEY from plugin config into child env", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();
    const resolvedKey = "sk-test-resolved-from-secretref";

    const logger = makeMockLogger();
    setModuleLogger(logger, { extraction: { apiKey: resolvedKey } });

    vi.mocked(spawn).mockImplementation(() => makeSuccessfulChild() as any);
    await handleMessageReceived(makeEvent());

    const env = captureSpawnEnv();
    expect(env).toBeDefined();
    expect(env?.OPENROUTER_API_KEY).toBe(resolvedKey);
    expect(process.env.OPENROUTER_API_KEY).toBeUndefined();
  });

  // ── MIND-02: unresolved key fails cold, no fallback to process.env ──
  it("MIND-02: fails cold when apiKey is unresolved and does not fall back to process.env", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();
    process.env.OPENROUTER_API_KEY = "sk-leftover-in-process-env";

    const logger = makeMockLogger();
    setModuleLogger(logger);

    vi.mocked(spawn).mockImplementation(() => makeSuccessfulChild() as any);
    await handleMessageReceived(makeEvent());

    expect(vi.mocked(spawn)).not.toHaveBeenCalled();
    const errorMsg = logger.error.mock.calls.find((c: any) =>
      (c[0] as string).includes("extraction apiKey unresolved")
    )?.[0] as string;
    expect(errorMsg).toBeDefined();
    expect(errorMsg).not.toContain("sk-leftover-in-process-env");
  });

  // ── MIND-04 / manifest: plugin config accepts SecretRef-shaped value ──
  it("MIND-04: setModuleLogger accepts extraction.apiKey as a plain resolved string", () => {
    const logger = makeMockLogger();
    setModuleLogger(logger, { extraction: { apiKey: "sk-resolved" } });
    expect(getExtractionApiKey()).toBe("sk-resolved");
  });

  it("MIND-04: setExtractionApiKey accepts a structured SecretRef source object gracefully", () => {
    // Although runtime resolution turns SecretRefs into plain strings, the
    // test harness may pass the source object. The setter must not crash and
    // should treat non-string values as unresolved.
    const logger = makeMockLogger();
    setModuleLogger(logger);
    setExtractionApiKey({ source: "env", provider: "default", id: "OPENROUTER_API_KEY" } as any);
    expect(getExtractionApiKey()).toBeNull();
  });

  // ── MIND-06: secrets hygiene — no env dump, no key in logs ──
  it("MIND-06: never logs the resolved API key value", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();
    const resolvedKey = "sk-super-secret-key-mind06";

    const logger = makeMockLogger();
    setModuleLogger(logger, { extraction: { apiKey: resolvedKey } });

    vi.mocked(spawn).mockImplementation(() => makeSuccessfulChild() as any);
    await handleMessageReceived(makeEvent());

    const allMessages = [
      ...logger.debug.mock.calls,
      ...logger.info.mock.calls,
      ...logger.warn.mock.calls,
      ...logger.error.mock.calls,
    ].map((c: any) => c[0] as string);

    for (const msg of allMessages) {
      expect(msg).not.toContain(resolvedKey);
    }
  });

  // ── MIND-07 regression: other child env vars are still present ──
  it("MIND-07: child env still contains PGDATABASE, SENDER_NAME, SOURCE_SESSION_ID, etc.", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();
    process.env.PGHOST = "pg.example.com";
    process.env.PGPORT = "5433";

    const logger = makeMockLogger();
    setModuleLogger(logger, { extraction: { apiKey: "sk-test" } });

    vi.mocked(spawn).mockImplementation(() => makeSuccessfulChild() as any);
    await handleMessageReceived(makeEvent());

    const env = captureSpawnEnv();
    expect(env?.PGDATABASE).toBe("nova_memory");
    expect(env?.SENDER_NAME).toBe("unknown");
    expect(env?.SOURCE_SESSION_ID).toBe("agent:nova:discord:channel:123");
    expect(env?.PGHOST).toBe("pg.example.com");
    expect(env?.PGPORT).toBe("5433");
  });

  // ── MIND-06: no process.env spread ──
  it("MIND-06: child env does not inherit arbitrary process.env variables", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();
    process.env.ARBITRARY_GATEWAY_SECRET = "should-not-appear";

    const logger = makeMockLogger();
    setModuleLogger(logger, { extraction: { apiKey: "sk-test" } });

    vi.mocked(spawn).mockImplementation(() => makeSuccessfulChild() as any);
    await handleMessageReceived(makeEvent());

    const env = captureSpawnEnv();
    expect(env?.ARBITRARY_GATEWAY_SECRET).toBeUndefined();
    delete process.env.ARBITRARY_GATEWAY_SECRET;
  });
});
