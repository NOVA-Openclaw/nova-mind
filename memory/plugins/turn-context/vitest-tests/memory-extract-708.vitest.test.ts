import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { handleMessageReceived, resolveMemoryDatabase, peerDbCache } from "../../../hooks/memory-extract/handler.ts";

/**
 * Unit tests for #708: memory-extract session upsert must populate
 * external_thread_id from the host-provided threadId and set last_message_at
 * on both INSERT and ON CONFLICT UPDATE.
 *
 * Fixture-value derivations:
 * - Tests set $HOME to a temp directory so production code reads a hermetic
 *   ~/.openclaw/postgres.json instead of the real one.
 * - "discord:channel:123" and "discord:channel:124" are synthetic external
 *   chat ids; "threadA" / "threadB" are synthetic distinct non-empty thread
 *   ids for the two-threads-same-chat case (TC-708-003).
 * - 123456789 is the numeric thread id used in TC-708-005; "123456789" is
 *   its string form. Both must normalize to the same external_thread_id.
 * - The mocked psql stdout "42" is an arbitrary synthetic session id.
 */

vi.mock("child_process", () => ({
  spawn: vi.fn(),
  execFile: vi.fn(),
}));

import { spawn, execFile } from "child_process";

function makeHomeDir(): string {
  return mkdtempSync(join(tmpdir(), "memory-extract-708-"));
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
 * Mock execFile so psql calls succeed with a synthetic session id.
 */
function mockPsql(): void {
  vi.mocked(execFile).mockImplementation((_cmd: any, args: any, cb: any) => {
    if (!Array.isArray(args)) {
      cb(null, "", "");
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

/**
 * Return every psql call SQL string captured by the mock.
 */
function capturedPsqlSql(): string[] {
  return vi.mocked(execFile).mock.calls
    .filter((c) => c[0] === "psql")
    .map((c) => {
      const args = c[1] as string[];
      const sql = args.find((a) => typeof a === "string" && a.includes("INSERT INTO"));
      return sql || "";
    });
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

describe("memory-extract handler session upsert (#708)", () => {
  let originalPgDatabase: string | undefined;
  let originalHome: string | undefined;
  let homeDir: string;

  beforeEach(() => {
    originalPgDatabase = process.env.PGDATABASE;
    originalHome = process.env.HOME;
    homeDir = makeHomeDir();
    process.env.HOME = homeDir;
    delete process.env.PGDATABASE;
    vi.mocked(spawn).mockReset();
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

  it("TC-708-001: session INSERT includes external_thread_id when event.threadId is present", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await handleMessageReceived(makeEvent({ threadId: "threadA" }));

    const sql = capturedPsqlSql().find((s) => s.includes("INSERT INTO channel_sessions"));
    expect(sql).toBeDefined();
    expect(sql).toContain("external_thread_id");
    expect(sql).toContain("'threadA'");
  });

  it("TC-708-002: session INSERT and UPDATE both set last_message_at", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await handleMessageReceived(makeEvent());

    const sql = capturedPsqlSql().find((s) => s.includes("INSERT INTO channel_sessions"));
    expect(sql).toBeDefined();
    expect(sql).toContain("last_message_at");
    expect(sql).toMatch(/last_message_at\) VALUES \([^)]+'/); // INSERT column and value
    expect(sql).toContain("DO UPDATE SET");
    expect(sql).toMatch(/last_message_at\s*=\s*'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z'/);
  });

  it("TC-708-003: two threads in the same chat get distinct session rows", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await handleMessageReceived(makeEvent({ threadId: "threadA" }));
    await handleMessageReceived(makeEvent({ threadId: "threadB" }));

    const sessionSqls = capturedPsqlSql().filter((s) => s.includes("INSERT INTO channel_sessions"));
    expect(sessionSqls.length).toBe(2);
    expect(sessionSqls[0]).toContain("'threadA'");
    expect(sessionSqls[1]).toContain("'threadB'");
    // Both statements must target the same unique index so PostgreSQL can
    // distinguish the two threads instead of collapsing them.
    for (const sql of sessionSqls) {
      expect(sql).toContain("ON CONFLICT (provider, external_chat_id, COALESCE(external_thread_id, ''))");
    }
  });

  it("TC-708-004: missing threadId omits external_thread_id and stores NULL semantics", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await handleMessageReceived(makeEvent());

    const sql = capturedPsqlSql().find((s) => s.includes("INSERT INTO channel_sessions"));
    expect(sql).toBeDefined();
    // The INSERT column list must not include external_thread_id; the ON
    // CONFLICT target still references the unique index expression.
    const insertCols = sql.match(/INSERT INTO channel_sessions \(([^)]+)\)/)?.[1] ?? "";
    expect(insertCols).not.toContain("external_thread_id");
    expect(sql).toContain("ON CONFLICT (provider, external_chat_id, COALESCE(external_thread_id, ''))");
  });

  it("TC-708-005: numeric and string threadId forms normalize to the same text", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await handleMessageReceived(makeEvent({ threadId: 123456789 }));
    await handleMessageReceived(makeEvent({ threadId: "123456789" }));

    const sessionSqls = capturedPsqlSql().filter((s) => s.includes("INSERT INTO channel_sessions"));
    expect(sessionSqls.length).toBe(2);
    expect(sessionSqls[0]).toContain("'123456789'");
    expect(sessionSqls[1]).toContain("'123456789'");
  });

  it("TC-708-006: empty string threadId normalizes to NULL (omitted from INSERT)", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await handleMessageReceived(makeEvent({ threadId: "" }));

    const sql = capturedPsqlSql().find((s) => s.includes("INSERT INTO channel_sessions"));
    expect(sql).toBeDefined();
    // Empty string must normalize to NULL, so the column is omitted from the
    // INSERT list just like an absent threadId (TC-708-004).
    const insertCols = sql.match(/INSERT INTO channel_sessions \(([^)]+)\)/)?.[1] ?? "";
    expect(insertCols).not.toContain("external_thread_id");
  });

  it("TC-708-007: the unique index expression is the ON CONFLICT target", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await handleMessageReceived(makeEvent({ threadId: "threadA" }));

    const sql = capturedPsqlSql().find((s) => s.includes("INSERT INTO channel_sessions"));
    expect(sql).toBeDefined();
    expect(sql).toContain("ON CONFLICT (provider, external_chat_id, COALESCE(external_thread_id, ''))");
  });

  it("TC-708-008: last_message_at uses the message timestamp monotonically", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    mockPsql();

    await handleMessageReceived(makeEvent());
    // Small delay to ensure the second message has a strictly later timestamp.
    await new Promise((resolve) => setTimeout(resolve, 10));
    await handleMessageReceived(makeEvent());

    const sessionSqls = capturedPsqlSql().filter((s) => s.includes("INSERT INTO channel_sessions"));
    expect(sessionSqls.length).toBe(2);

    const timestamps = sessionSqls.map((sql) => {
      const match = sql.match(/last_message_at\s*=\s*'([^']+)'/);
      return match ? new Date(match[1]).getTime() : 0;
    });
    expect(timestamps[1]).toBeGreaterThanOrEqual(timestamps[0]);
  });
});
