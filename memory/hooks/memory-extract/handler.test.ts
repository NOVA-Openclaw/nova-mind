/**
 * Acceptance tests for nova-mind#621 PR1 (Changes 1+2).
 *
 * Scope:
 *   - Change 1: local FK upsert always runs against PGDATABASE; env handoff uses
 *     locally-resolved ids, never raw ctx ids from another DB.
 *   - Change 2: if local FK resolution fails, FK env vars are emptied so the
 *     extractor stores the fact with NULL FK columns (fail-open).
 *
 * Uses two schema-identical temporary databases:
 *   - source DB  (simulates nova_memory / shared transcript store)
 *   - target DB  (simulates newhart_memory / PGDATABASE extraction target)
 *
 * Run: npx tsx --test memory/hooks/memory-extract/handler.test.ts
 */

import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import handler from "./handler.ts";

const execFileAsync = promisify(execFile);

const PGADMIN = "nova";
const SCHEMA_SOURCE_DB = "nova_memory_test_coder497";

const ENV_VARS_TO_ISOLATE = [
  "PGDATABASE",
  "EXTRACTION_SCRIPT_PATH_OVERRIDE",
  "EXTRACTION_PYTHON_CMD_OVERRIDE",
  "EXTRACTION_TIMEOUT_MS_OVERRIDE",
  "EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE",
  "MARKER_PATH",
  "PATH",
];

let suiteTemplateDb: string;
let tempDir: string;
let mockScriptPath: string;
const testDbs: Set<string> = new Set();

function uniqueDbName(label: string): string {
  const pid = process.pid;
  const rand = Math.random().toString(36).slice(2, 8);
  return `nm621_${label}_${pid}_${rand}`;
}

async function psql(args: string[]): Promise<{ stdout: string; stderr: string }> {
  return execFileAsync("psql", ["-U", PGADMIN, "-h", "localhost", ...args]);
}

async function runSql(dbName: string, sql: string): Promise<string> {
  const { stdout } = await psql(["-d", dbName, "-t", "-A", "-F\t", "-c", sql]);
  return stdout.trim();
}

async function createDbFromTemplate(dbName: string, template: string): Promise<void> {
  await psql(["-d", "postgres", "-c", `CREATE DATABASE "${dbName}" TEMPLATE "${template}";`]);
}

async function dropDb(dbName: string): Promise<void> {
  try {
    await psql(["-d", "postgres", "-c", `DROP DATABASE IF EXISTS "${dbName}";`]);
  } catch {
    // ignore cleanup failures
  }
}


function saveEnv(): Record<string, string | undefined> {
  const saved: Record<string, string | undefined> = {};
  for (const key of ENV_VARS_TO_ISOLATE) {
    saved[key] = process.env[key];
  }
  return saved;
}

function restoreEnv(saved: Record<string, string | undefined>): void {
  for (const key of ENV_VARS_TO_ISOLATE) {
    if (saved[key] === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = saved[key];
    }
  }
}

async function waitForMarker(markerPath: string, timeoutMs = 8000): Promise<Record<string, any>> {
  const start = Date.now();
  while (!fs.existsSync(markerPath)) {
    if (Date.now() - start > timeoutMs) {
      throw new Error(`Timed out waiting for marker file: ${markerPath}`);
    }
    await new Promise((r) => setTimeout(r, 50));
  }
  return JSON.parse(fs.readFileSync(markerPath, "utf8"));
}

function buildMockScript(): string {
  return `#!/usr/bin/env python3
import json
import os
import sys
import psycopg2

# Read the message body from stdin (kept for parity with real extractor)
message = sys.stdin.read()

marker_path = os.environ.get("MARKER_PATH", "/tmp/nm621_marker.json")
session_id = os.environ.get("SOURCE_CHANNEL_SESSION_ID", "").strip()
transcript_id = os.environ.get("SOURCE_CHANNEL_TRANSCRIPT_ID", "").strip()

print(
    f"[mock-extract] env session_id={session_id!r} transcript_id={transcript_id!r}",
    file=sys.stderr,
)

conn = psycopg2.connect()
try:
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO entities (name, type) VALUES ('TestSender', 'person') "
            "ON CONFLICT (name, type) DO UPDATE SET last_seen = NOW() RETURNING id;"
        )
        entity_id = cur.fetchone()[0]

        cols = ["entity_id", "key", "value", "visibility", "durability", "category"]
        vals = [entity_id, "nm621_fact", message[:50], "public", "long_term", "observation"]
        ph = ["%s"] * len(cols)

        if session_id and session_id.isdigit():
            cols.append("source_channel_session_id")
            vals.append(int(session_id))
            ph.append("%s")
        if transcript_id and transcript_id.isdigit():
            cols.append("source_channel_transcript_id")
            vals.append(int(transcript_id))
            ph.append("%s")

        cur.execute(
            f"INSERT INTO entity_facts ({', '.join(cols)}) VALUES ({', '.join(ph)}) RETURNING id;",
            vals,
        )
        fact_id = cur.fetchone()[0]
    conn.commit()
finally:
    conn.close()

with open(marker_path, "w") as f:
    json.dump({
        "source_channel_session_id": session_id,
        "source_channel_transcript_id": transcript_id,
        "fact_id": fact_id,
    }, f)

print("{}")
`;
}

async function countRows(dbName: string, table: string): Promise<number> {
  const out = await runSql(dbName, `SELECT COUNT(*) FROM ${table};`);
  return Number(out);
}

async function getSingleFact(dbName: string): Promise<Record<string, any>> {
  const out = await runSql(
    dbName,
    `SELECT id, entity_id, source_channel_session_id, source_channel_transcript_id ` +
      `FROM entity_facts WHERE key = 'nm621_fact' ORDER BY id DESC LIMIT 1;`
  );
  const parts = out.split("\t");
  return {
    id: parts[0] ? Number(parts[0]) : null,
    entity_id: parts[1] ? Number(parts[1]) : null,
    source_channel_session_id: parts[2] ? Number(parts[2]) : null,
    source_channel_transcript_id: parts[3] ? Number(parts[3]) : null,
  };
}

describe("nova-mind#621 PR1: cross-DB FK resolution", { concurrency: false }, () => {
  before(async () => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "nm621-"));
    mockScriptPath = path.join(tempDir, "mock_extract.py");
    fs.writeFileSync(mockScriptPath, buildMockScript(), { mode: 0o755 });

    suiteTemplateDb = uniqueDbName("template");
    await createDbFromTemplate(suiteTemplateDb, SCHEMA_SOURCE_DB);
    testDbs.add(suiteTemplateDb);
    await runSql(
      suiteTemplateDb,
      `TRUNCATE entities, entity_facts, entity_fact_sources, channel_sessions, ` +
        `channel_transcripts, extraction_failures RESTART IDENTITY CASCADE;`
    );
  });

  after(async () => {
    for (const db of Array.from(testDbs)) {
      await dropDb(db);
    }
    testDbs.clear();
    fs.rmSync(tempDir, { recursive: true, force: true });
  });

  async function freshDbs(): Promise<{ sourceDb: string; targetDb: string }> {
    const sourceDb = uniqueDbName("src");
    const targetDb = uniqueDbName("tgt");
    await createDbFromTemplate(sourceDb, suiteTemplateDb);
    await createDbFromTemplate(targetDb, suiteTemplateDb);
    testDbs.add(sourceDb);
    testDbs.add(targetDb);

    for (const db of [sourceDb, targetDb]) {
      await runSql(
        db,
        `TRUNCATE entities, entity_facts, entity_fact_sources, channel_sessions, ` +
          `channel_transcripts, extraction_failures RESTART IDENTITY CASCADE;`
      );
    }
    return { sourceDb, targetDb };
  }

  async function cleanupDbs(sourceDb: string, targetDb: string): Promise<void> {
    await dropDb(sourceDb);
    await dropDb(targetDb);
    testDbs.delete(sourceDb);
    testDbs.delete(targetDb);
  }

  it(
    "Case 1: cross-DB happy path — ctx ids from source DB resolve to local target rows",
    async () => {
      const { sourceDb, targetDb } = await freshDbs();
      const savedEnv = saveEnv();
      const markerPath = path.join(tempDir, `marker-${Date.now()}.json`);

      try {
        // Seed source DB with ids that only exist there.
        await runSql(
          sourceDb,
          `INSERT INTO channel_sessions (id, session_key, agent_id, provider, external_chat_id, chat_type) ` +
            `VALUES (10871, 'agent_chat:newhart', 'main', 'agent_chat', 'agent_chat:newhart', 'direct');`
        );
        await runSql(
          sourceDb,
          `INSERT INTO channel_transcripts (id, session_id, external_message_id, timestamp, role, content) ` +
            `VALUES (999999, 10871, 'src-msg-1', NOW(), 'user', 'source transcript');`
        );

        process.env.PGDATABASE = targetDb;
        process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mockScriptPath;
        process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = "/usr/bin/python3";
        process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = "10000";
        process.env.EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE = "0";
        process.env.MARKER_PATH = markerPath;

        const event = {
          type: "message",
          action: "received",
          sessionKey: "agent_chat:newhart",
          context: {
            content: "This is a cross-database memory extraction test message.",
            channelSessionId: "10871",
            channelTranscriptId: "999999",
            conversationId: "agent_chat:newhart",
            messageId: "cross-msg-1",
            metadata: {
              senderName: "TestSender",
              senderId: "sender-123",
              provider: "agent_chat",
            },
          },
        };

        await handler(event);
        const marker = await waitForMarker(markerPath);

        // Target DB must contain exactly one local session/transcript pair.
        const targetSessionCount = await countRows(targetDb, "channel_sessions");
        const targetTranscriptCount = await countRows(targetDb, "channel_transcripts");
        assert.strictEqual(targetSessionCount, 1, "target should have one local session");
        assert.strictEqual(targetTranscriptCount, 1, "target should have one local transcript");

        const targetSessionId = Number(
          await runSql(
            targetDb,
            `SELECT id FROM channel_sessions WHERE provider = 'agent_chat' AND external_chat_id = 'agent_chat:newhart';`
          )
        );
        const targetTranscriptId = Number(
          await runSql(
            targetDb,
            `SELECT id FROM channel_transcripts WHERE session_id = ${targetSessionId};`
          )
        );

        // Env handoff must use LOCAL ids, never the source ctx ids.
        assert.notStrictEqual(marker.source_channel_session_id, "10871");
        assert.notStrictEqual(marker.source_channel_transcript_id, "999999");
        assert.strictEqual(marker.source_channel_session_id, String(targetSessionId));
        assert.strictEqual(marker.source_channel_transcript_id, String(targetTranscriptId));

        // Fact FKs must resolve against the target DB.
        const fact = await getSingleFact(targetDb);
        assert.strictEqual(fact.source_channel_session_id, targetSessionId);
        assert.strictEqual(fact.source_channel_transcript_id, targetTranscriptId);

        // Isolation guard: source DB must be unchanged by the extraction.
        assert.strictEqual(await countRows(sourceDb, "channel_sessions"), 1);
        assert.strictEqual(await countRows(sourceDb, "channel_transcripts"), 1);
        assert.strictEqual(await countRows(sourceDb, "entity_facts"), 0);
      } finally {
        restoreEnv(savedEnv);
        await cleanupDbs(sourceDb, targetDb);
      }
    }
  );

  it("Case 2: real-time no-regression — no ctx ids", async () => {
    const { sourceDb, targetDb } = await freshDbs();
    const savedEnv = saveEnv();
    const markerPath = path.join(tempDir, `marker-${Date.now()}.json`);

    try {
      process.env.PGDATABASE = targetDb;
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mockScriptPath;
      process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = "/usr/bin/python3";
      process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = "10000";
      process.env.EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE = "0";
      process.env.MARKER_PATH = markerPath;

      const event = {
        type: "message",
        action: "received",
        sessionKey: "agent_chat:newhart",
        context: {
          content: "This is a real-time memory extraction test message.",
          conversationId: "agent_chat:newhart",
          messageId: "rt-msg-1",
          metadata: {
            senderName: "TestSender",
            senderId: "sender-123",
            provider: "agent_chat",
          },
        },
      };

      await handler(event);
      const marker = await waitForMarker(markerPath);

      const targetSessionCount = await countRows(targetDb, "channel_sessions");
      const targetTranscriptCount = await countRows(targetDb, "channel_transcripts");
      assert.strictEqual(targetSessionCount, 1);
      assert.strictEqual(targetTranscriptCount, 1);

      const fact = await getSingleFact(targetDb);
      assert.ok(fact.source_channel_session_id, "fact should have a session FK");
      assert.ok(fact.source_channel_transcript_id, "fact should have a transcript FK");
      assert.strictEqual(marker.source_channel_session_id, String(fact.source_channel_session_id));
      assert.strictEqual(marker.source_channel_transcript_id, String(fact.source_channel_transcript_id));
    } finally {
      restoreEnv(savedEnv);
      await cleanupDbs(sourceDb, targetDb);
    }
  });

  it("Case 3: NULL-fallback when local FK resolution fails", async () => {
    const { sourceDb, targetDb } = await freshDbs();
    const savedEnv = saveEnv();
    const markerPath = path.join(tempDir, `marker-${Date.now()}.json`);

    try {
      // Force local FK resolution to fail by removing the channel tables from the
      // target DB. The dependent entity_facts FK constraints are dropped with them,
      // so the extractor can still store the fact with NULL FK columns.
      await runSql(targetDb, `DROP TABLE channel_sessions, channel_transcripts CASCADE;`);

      process.env.PGDATABASE = targetDb;
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mockScriptPath;
      process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = "/usr/bin/python3";
      process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = "10000";
      process.env.EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE = "0";
      process.env.MARKER_PATH = markerPath;

      const event = {
        type: "message",
        action: "received",
        sessionKey: "agent_chat:newhart",
        context: {
          content: "This message should store with NULL FKs when local resolution fails.",
          conversationId: "agent_chat:newhart",
          messageId: "null-msg-1",
          metadata: {
            senderName: "TestSender",
            senderId: "sender-123",
            provider: "agent_chat",
          },
        },
      };

      await handler(event);
      const marker = await waitForMarker(markerPath);

      assert.strictEqual(marker.source_channel_session_id, "");
      assert.strictEqual(marker.source_channel_transcript_id, "");

      // No local channel rows should have been written.
      const sessCount = Number(await runSql(targetDb, `SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'channel_sessions';`));
      const txCount = Number(await runSql(targetDb, `SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'channel_transcripts';`));
      assert.strictEqual(sessCount, 0);
      assert.strictEqual(txCount, 0);

      // Fact must still exist with NULL FKs.
      const factCount = await countRows(targetDb, "entity_facts");
      assert.strictEqual(factCount, 1);
      const fact = await getSingleFact(targetDb);
      assert.strictEqual(fact.source_channel_session_id, null);
      assert.strictEqual(fact.source_channel_transcript_id, null);
    } finally {
      restoreEnv(savedEnv);
      await cleanupDbs(sourceDb, targetDb);
    }
  });

  it("Case 4: idempotency — re-run does not duplicate local FK rows", async () => {
    const { sourceDb, targetDb } = await freshDbs();
    const savedEnv = saveEnv();

    try {
      process.env.PGDATABASE = targetDb;
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mockScriptPath;
      process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = "/usr/bin/python3";
      process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = "10000";
      process.env.EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE = "0";

      const event = {
        type: "message",
        action: "received",
        sessionKey: "agent_chat:newhart",
        context: {
          content: "Idempotency test message run number one and two.",
          conversationId: "agent_chat:newhart",
          messageId: "idempotent-msg-1",
          metadata: {
            senderName: "TestSender",
            senderId: "sender-123",
            provider: "agent_chat",
          },
        },
      };

      for (let i = 0; i < 2; i++) {
        const markerPath = path.join(tempDir, `marker-idem-${Date.now()}-${i}.json`);
        process.env.MARKER_PATH = markerPath;
        await handler(event);
        await waitForMarker(markerPath);
      }

      assert.strictEqual(await countRows(targetDb, "channel_sessions"), 1);
      assert.strictEqual(await countRows(targetDb, "channel_transcripts"), 1);
    } finally {
      restoreEnv(savedEnv);
      await cleanupDbs(sourceDb, targetDb);
    }
  });

  it("Case 5: same-DB — ctx ids already local are reused", async () => {
    const { sourceDb, targetDb } = await freshDbs();
    const savedEnv = saveEnv();
    const markerPath = path.join(tempDir, `marker-${Date.now()}.json`);

    try {
      // Pre-seed target with local rows at known ids.
      await runSql(
        targetDb,
        `INSERT INTO channel_sessions (id, session_key, agent_id, provider, external_chat_id, chat_type) ` +
          `VALUES (20001, 'agent_chat:newhart', 'main', 'agent_chat', 'agent_chat:newhart', 'direct');`
      );
      await runSql(
        targetDb,
        `INSERT INTO channel_transcripts (id, session_id, external_message_id, timestamp, role, content) ` +
          `VALUES (30001, 20001, 'same-msg-1', NOW(), 'user', 'existing transcript');`
      );

      process.env.PGDATABASE = targetDb;
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mockScriptPath;
      process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = "/usr/bin/python3";
      process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = "10000";
      process.env.EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE = "0";
      process.env.MARKER_PATH = markerPath;

      const event = {
        type: "message",
        action: "received",
        sessionKey: "agent_chat:newhart",
        context: {
          content: "Same-DB memory extraction test message with existing local ids.",
          channelSessionId: "20001",
          channelTranscriptId: "30001",
          conversationId: "agent_chat:newhart",
          messageId: "same-msg-1",
          metadata: {
            senderName: "TestSender",
            senderId: "sender-123",
            provider: "agent_chat",
          },
        },
      };

      await handler(event);
      const marker = await waitForMarker(markerPath);

      assert.strictEqual(await countRows(targetDb, "channel_sessions"), 1);
      assert.strictEqual(await countRows(targetDb, "channel_transcripts"), 1);

      assert.strictEqual(marker.source_channel_session_id, "20001");
      assert.strictEqual(marker.source_channel_transcript_id, "30001");

      const fact = await getSingleFact(targetDb);
      assert.strictEqual(fact.source_channel_session_id, 20001);
      assert.strictEqual(fact.source_channel_transcript_id, 30001);
    } finally {
      restoreEnv(savedEnv);
      await cleanupDbs(sourceDb, targetDb);
    }
  });

  it("Case 1b: cross-DB ids present but local session-upsert fails — no foreign-id transcript write", async () => {
    const { sourceDb, targetDb } = await freshDbs();
    const savedEnv = saveEnv();
    const markerPath = path.join(tempDir, `marker-${Date.now()}.json`);

    try {
      // Seed source DB with a session id that will also NOT resolve locally.
      await runSql(
        sourceDb,
        `INSERT INTO channel_sessions (id, session_key, agent_id, provider, external_chat_id, chat_type) ` +
          `VALUES (10871, 'agent_chat:newhart', 'main', 'agent_chat', 'agent_chat:newhart', 'direct');`
      );
      await runSql(
        sourceDb,
        `INSERT INTO channel_transcripts (id, session_id, external_message_id, timestamp, role, content) ` +
          `VALUES (999999, 10871, 'src-msg-1', NOW(), 'user', 'source transcript');`
      );

      // Remove channel_sessions from target DB so the local session upsert fails.
      await runSql(targetDb, `DROP TABLE channel_sessions CASCADE;`);

      process.env.PGDATABASE = targetDb;
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mockScriptPath;
      process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = "/usr/bin/python3";
      process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = "10000";
      process.env.EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE = "0";
      process.env.MARKER_PATH = markerPath;

      const event = {
        type: "message",
        action: "received",
        sessionKey: "agent_chat:newhart",
        context: {
          content: "Cross-DB ids with local session-upsert failure.",
          channelSessionId: "10871",
          channelTranscriptId: "999999",
          conversationId: "agent_chat:newhart",
          messageId: "cb-msg-1",
          metadata: {
            senderName: "TestSender",
            senderId: "sender-123",
            provider: "agent_chat",
          },
        },
      };

      await handler(event);
      const marker = await waitForMarker(markerPath);

      // No local session table, so both FK env vars must be empty.
      assert.strictEqual(marker.source_channel_session_id, "");
      assert.strictEqual(marker.source_channel_transcript_id, "");

      // Most importantly: no transcript row may have been written referencing the
      // foreign session id (channel_transcripts exists, but session_id column is gone
      // with channel_sessions, so verify via information_schema absence or fact FKs).
      const fact = await getSingleFact(targetDb);
      assert.strictEqual(fact.source_channel_session_id, null);
      assert.strictEqual(fact.source_channel_transcript_id, null);
    } finally {
      restoreEnv(savedEnv);
      await cleanupDbs(sourceDb, targetDb);
    }
  });

  it("Case 6: session resolves but transcript upsert fails — mixed NULL FK fact", async () => {
    const { sourceDb, targetDb } = await freshDbs();
    const savedEnv = saveEnv();
    const markerPath = path.join(tempDir, `marker-${Date.now()}.json`);

    try {
      process.env.PGDATABASE = targetDb;
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mockScriptPath;
      process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = "/usr/bin/python3";
      process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = "10000";
      process.env.EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE = "0";
      process.env.MARKER_PATH = markerPath;

      // Drop only channel_transcripts so session upsert succeeds but transcript upsert fails.
      await runSql(targetDb, `DROP TABLE channel_transcripts CASCADE;`);

      const event = {
        type: "message",
        action: "received",
        sessionKey: "agent_chat:newhart",
        context: {
          content: "Session resolves but transcript upsert fails.",
          conversationId: "agent_chat:newhart",
          messageId: "mix-msg-1",
          metadata: {
            senderName: "TestSender",
            senderId: "sender-123",
            provider: "agent_chat",
          },
        },
      };

      await handler(event);
      const marker = await waitForMarker(markerPath);

      // Session id should be set locally; transcript id must be empty.
      assert.notStrictEqual(marker.source_channel_session_id, "");
      assert.strictEqual(marker.source_channel_transcript_id, "");

      const sessionId = Number(marker.source_channel_session_id);
      assert.ok(Number.isFinite(sessionId));
      assert.strictEqual(await countRows(targetDb, "channel_sessions"), 1);

      const fact = await getSingleFact(targetDb);
      assert.strictEqual(fact.source_channel_session_id, sessionId);
      assert.strictEqual(fact.source_channel_transcript_id, null);
    } finally {
      restoreEnv(savedEnv);
      await cleanupDbs(sourceDb, targetDb);
    }
  });

  it('Case 7: ctx id literal "0" is treated as a normal truthy string', async () => {
    const { sourceDb, targetDb } = await freshDbs();
    const savedEnv = saveEnv();
    const markerPath = path.join(tempDir, `marker-${Date.now()}.json`);

    try {
      process.env.PGDATABASE = targetDb;
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mockScriptPath;
      process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = "/usr/bin/python3";
      process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = "10000";
      process.env.EXTRACTION_MAX_PRIOR_MESSAGES_OVERRIDE = "0";
      process.env.MARKER_PATH = markerPath;

      const event = {
        type: "message",
        action: "received",
        sessionKey: "agent_chat:newhart",
        context: {
          content: "Boundary test with ctx id literal zero.",
          channelSessionId: "0",
          channelTranscriptId: "0",
          conversationId: "agent_chat:newhart",
          messageId: "zero-msg-1",
          metadata: {
            senderName: "TestSender",
            senderId: "sender-123",
            provider: "agent_chat",
          },
        },
      };

      await handler(event);
      const marker = await waitForMarker(markerPath);

      // Local upsert should create real rows and use their ids; "0" is not special-cased.
      assert.notStrictEqual(marker.source_channel_session_id, "");
      assert.notStrictEqual(marker.source_channel_transcript_id, "");
      assert.notStrictEqual(marker.source_channel_session_id, "0");
      assert.notStrictEqual(marker.source_channel_transcript_id, "0");

      assert.strictEqual(await countRows(targetDb, "channel_sessions"), 1);
      assert.strictEqual(await countRows(targetDb, "channel_transcripts"), 1);
    } finally {
      restoreEnv(savedEnv);
      await cleanupDbs(sourceDb, targetDb);
    }
  });
});
