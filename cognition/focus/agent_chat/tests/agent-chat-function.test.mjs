/**
 * SQL-level tests for send_agent_message() after the #548 migration.
 *
 * These tests spin up a temporary agent_chat database owned by the `nova` role,
 * apply database/agent-chat/schema.sql plus migration 001, and exercise the
 * function directly through psql/node-pg. They cover all TCs that do not
 * require the full OpenClaw channel wiring (TC-001, TC-017, TC-022) or the
 * real-handler markMessageFailed path (TC-009/TC-020 amendments).
 *
 * Run from the repo root or the plugin directory:
 *   node --test-concurrency=1 --test cognition/focus/agent_chat/tests/
 */

import { describe, it, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import pg from "pg";
import { execSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../../../..");
const SCHEMA_SQL = path.join(REPO_ROOT, "database", "agent-chat", "schema.sql");
const MIGRATION_SQL = path.join(
  REPO_ROOT,
  "database",
  "agent-chat",
  "migrations",
  "001-send-agent-message-reply-to.sql",
);

const PG_SUPERUSER = "nova";
const PG_GEM = "gem";
const PG_HOST = "localhost";
const PG_PORT = 5432;

let dbName;
let superClient;

/**
 * Read the password for a given connection from ~/.pgpass so node-pg can
 * authenticate over TCP. The value is never logged.
 */
function loadPgPassPassword(host, port, database, user) {
  const pgpass = path.join(os.homedir(), ".pgpass");
  if (!fs.existsSync(pgpass)) return "";
  const lines = fs.readFileSync(pgpass, "utf-8").split(/\r?\n/);
  for (const line of lines) {
    if (!line || line.startsWith("#")) continue;
    const [h, p, d, u, ...passParts] = line.split(":");
    if (
      (h === "*" || h === host) &&
      (p === "*" || p === String(port)) &&
      (database === "*" || d === "*" || d === database) &&
      (u === "*" || u === user)
    ) {
      return passParts.join(":");
    }
  }
  return "";
}

const SUPER_PASSWORD = loadPgPassPassword(PG_HOST, PG_PORT, "*", PG_SUPERUSER);
const GEM_PASSWORD = loadPgPassPassword(PG_HOST, PG_PORT, "*", PG_GEM);

// Fail fast if credentials cannot be resolved (avoids cryptic psql prompts).
assert.ok(SUPER_PASSWORD.length > 0, "could not load superuser password from ~/.pgpass");
assert.ok(GEM_PASSWORD.length > 0, "could not load gem password from ~/.pgpass");

/**
 * Run psql as the superuser against the test database.
 * Used for idempotent DDL/application of schema files.
 *
 * Inline SQL is written to a temp file and passed with -f to avoid shell
 * quoting issues with parentheses and dollar-quoted function bodies.
 */
function psqlSuper(sqlOrFile, isFile = false) {
  const env = { ...process.env, PGPASSWORD: SUPER_PASSWORD };
  if (isFile) {
    return execSync(
      `psql -U ${PG_SUPERUSER} -h ${PG_HOST} -d ${dbName} -v ON_ERROR_STOP=1 -f "${sqlOrFile}"`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"], env },
    );
  }
  const tmpFile = path.join(os.tmpdir(), `test-sql-${process.hrtime.bigint()}.sql`);
  try {
    fs.writeFileSync(tmpFile, sqlOrFile, "utf-8");
    return execSync(
      `psql -U ${PG_SUPERUSER} -h ${PG_HOST} -d ${dbName} -v ON_ERROR_STOP=1 -f "${tmpFile}"`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"], env },
    );
  } finally {
    fs.unlinkSync(tmpFile);
  }
}

/**
 * Run psql as the `gem` role against the test database.
 * This is required for session_user checks in send_agent_message(); the
 * password is read from ~/.pgpass and supplied via env so temp DB names work.
 */
function psqlGem(sql) {
  const tmpFile = path.join(os.tmpdir(), `test-gem-sql-${process.hrtime.bigint()}.sql`);
  const pgpassFile = path.join(os.tmpdir(), `test-gem-pgpass-${process.hrtime.bigint()}`);
  try {
    fs.writeFileSync(tmpFile, sql, "utf-8");
    // libpq ignores PGPASSWORD when a ~/.pgpass entry exists; use a temp
    // PGPASSFILE scoped to this test database so psql can authenticate as gem.
    fs.writeFileSync(
      pgpassFile,
      `${PG_HOST}:${PG_PORT}:${dbName}:${PG_GEM}:${GEM_PASSWORD}\n`,
      { mode: 0o600 },
    );
    const env = { ...process.env, PGPASSFILE: pgpassFile };
    return execSync(
      `psql -U ${PG_GEM} -h ${PG_HOST} -d ${dbName} -v ON_ERROR_STOP=1 -f "${tmpFile}"`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"], env },
    );
  } finally {
    fs.unlinkSync(tmpFile);
    fs.unlinkSync(pgpassFile);
  }
}

/**
 * Execute a function call as `gem` and return the printed id, or throw if the
 * call errors. The id is extracted from the first data row.
 */
function sendAsGem(sql) {
  const out = psqlGem(sql);
  const m = out.match(/\n\s*(\d+)\s*\n/);
  if (!m) {
    throw new Error(`Could not extract id from output:\n${out}`);
  }
  return Number(m[1]);
}

/**
 * Normalize error output so assertions are not sensitive to wrapping.
 */
function errorText(err) {
  return err.stderr ? String(err.stderr) : String(err);
}

/**
 * Create a fresh database, apply schema + migration, and relax the DML gate
 * trigger so the non-superuser test owner (`nova`) can exercise the function.
 * The production gate still relies on current_user='postgres'; this relaxation
 * is test-only and is documented in the deferral list (TC-017).
 */
function setupDatabase() {
  dbName = `test_ac_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
  execSync(`createdb -U ${PG_SUPERUSER} -h ${PG_HOST} ${dbName}`, {
    encoding: "utf-8",
  });

  psqlSuper(SCHEMA_SQL, true);
  psqlSuper(MIGRATION_SQL, true);

  // Allow the function owner (nova) to pass the gate in this test database.
  psqlSuper(`
    CREATE OR REPLACE FUNCTION enforce_agent_chat_function_use()
    RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF current_user = '${PG_SUPERUSER}' OR current_user = 'postgres' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
      END IF;
      IF TG_OP = 'INSERT' THEN
        RAISE EXCEPTION 'Direct INSERT on agent_chat is not allowed. Use send_agent_message() instead.';
      ELSIF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'Direct UPDATE on agent_chat is not allowed. Messages are immutable.';
      ELSIF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Direct DELETE on agent_chat is not allowed.';
      END IF;
      RETURN NULL;
    END;
    $$;
  `);

  // Let the `gem` role connect and invoke the public function.
  psqlSuper(`GRANT CONNECT ON DATABASE ${dbName} TO ${PG_GEM};`);
  psqlSuper(`GRANT USAGE ON SCHEMA public TO ${PG_GEM};`);
  psqlSuper(`GRANT SELECT ON TABLE agent_chat, agent_chat_processed TO ${PG_GEM};`);

  superClient = new pg.Client({
    user: PG_SUPERUSER,
    password: SUPER_PASSWORD,
    host: PG_HOST,
    port: PG_PORT,
    database: dbName,
  });
}

function teardownDatabase() {
  if (superClient) {
    superClient.end().catch(() => {});
  }
  try {
    execSync(`dropdb -U ${PG_SUPERUSER} -h ${PG_HOST} ${dbName}`, {
      encoding: "utf-8",
    });
  } catch {
    // Best-effort cleanup; the test DB name is unique.
  }
}

/**
 * Wipe rows between tests. TRUNCATE ... CASCADE does not fire row-level
 * triggers and works because the test-only gate function allows nova DML.
 */
async function truncateTables() {
  await superClient.query("TRUNCATE agent_chat CASCADE;");
}

/**
 * Seed a parent message as `gem` addressed to `flint`.
 * Returns the generated id so reply_to tests have a valid, existing parent.
 */
async function seedParentMessage() {
  const id = sendAsGem(
    `SELECT send_agent_message('${PG_GEM}', 'parent message', ARRAY['flint']);`,
  );
  return id;
}

describe("Migration mechanics (TC-006–TC-008)", { concurrency: false }, () => {
  before(async () => {
    setupDatabase();
    await superClient.connect();
  });

  after(() => {
    teardownDatabase();
  });

  it("TC-006: pre-migration inventory shows a single 4-arg signature", async () => {
    // Simulate the live pre-#548 baseline: exactly one 4-arg overload.
    psqlSuper(`
      DROP FUNCTION IF EXISTS send_agent_message(text, text, text[], interval, integer);
      CREATE OR REPLACE FUNCTION send_agent_message(
        p_sender text, p_message text, p_recipients text[],
        p_ttl interval DEFAULT NULL::interval
      ) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER AS $$
      DECLARE v_id integer;
      BEGIN
        IF p_message IS NULL OR trim(p_message) = '' THEN
          RAISE EXCEPTION 'send_agent_message: message cannot be empty';
        END IF;
        INSERT INTO agent_chat (sender, message, recipients, expires_at)
        VALUES (LOWER(p_sender), p_message, ARRAY(SELECT LOWER(unnest(p_recipients))), NULL)
        RETURNING id INTO v_id;
        RETURN v_id;
      END;
      $$;
    `);

    const res = await superClient.query(
      `SELECT proname, pg_get_function_arguments(oid) AS args
       FROM pg_proc WHERE proname = 'send_agent_message'`,
    );
    assert.strictEqual(res.rows.length, 1, "expected exactly one pre-migration overload");
    // Derived from the 4-arg signature used above (matches live baseline).
    assert.match(res.rows[0].args, /p_sender.*p_message.*p_recipients.*p_ttl/);
    assert.doesNotMatch(res.rows[0].args, /p_reply_to/);
  });

  it("TC-007: post-migration inventory shows a single 5-arg signature", async () => {
    psqlSuper(MIGRATION_SQL, true);

    const res = await superClient.query(
      `SELECT proname, pg_get_function_arguments(oid) AS args
       FROM pg_proc WHERE proname = 'send_agent_message'`,
    );
    assert.strictEqual(res.rows.length, 1, "expected exactly one post-migration overload");
    // Derived from migration 001: p_reply_to is the 5th positional arg.
    assert.match(res.rows[0].args, /p_sender.*p_message.*p_recipients.*p_ttl.*p_reply_to/);
  });

  it("TC-008: 3-arg call does not raise function-is-not-unique (42725)", async () => {
    let raised = null;
    try {
      await superClient.query(
        `SELECT send_agent_message('${PG_SUPERUSER}', 'three arg call', ARRAY['flint'])`,
      );
    } catch (err) {
      raised = err;
    }
    if (raised) {
      // 42725 = ambiguous_function; any other error is unexpected here.
      assert.notStrictEqual(
        raised.code,
        "42725",
        `3-arg call must not be ambiguous; got ${raised.code}`,
      );
    }
    // The call above may fail for other reasons (session_user mismatch) because
    // we connected as nova with p_sender='nova'. If it succeeds, even better.
  });
});

describe("send_agent_message behavior (TC-002–TC-016, TC-020)", { concurrency: false }, () => {
  before(async () => {
    setupDatabase();
    await superClient.connect();
  });

  after(() => {
    teardownDatabase();
  });

  beforeEach(async () => {
    await truncateTables();
  });

  it("TC-002: direct SQL happy path sets reply_to", async () => {
    const parentId = await seedParentMessage();
    const replyId = sendAsGem(
      `SELECT send_agent_message('${PG_GEM}', 'test reply', ARRAY['flint'], NULL, ${parentId});`,
    );
    // replyId is a newly generated integer greater than the parent id.
    assert.ok(replyId > parentId, `reply id ${replyId} should exceed parent id ${parentId}`);
    const res = await superClient.query(
      "SELECT reply_to FROM agent_chat WHERE id = $1",
      [replyId],
    );
    assert.strictEqual(res.rows[0].reply_to, parentId);
  });

  it("TC-002b: named-argument call skipping p_ttl works", async () => {
    const parentId = await seedParentMessage();
    const replyId = sendAsGem(
      `SELECT send_agent_message('${PG_GEM}', 'named arg reply', ARRAY['flint'], p_reply_to => ${parentId});`,
    );
    const res = await superClient.query(
      "SELECT reply_to, expires_at FROM agent_chat WHERE id = $1",
      [replyId],
    );
    assert.strictEqual(res.rows[0].reply_to, parentId);
    assert.strictEqual(res.rows[0].expires_at, null);
  });

  it("TC-003: fresh outbound send leaves reply_to NULL", async () => {
    const id = sendAsGem(
      `SELECT send_agent_message('${PG_GEM}', 'fresh send', ARRAY['flint'], NULL, NULL);`,
    );
    const res = await superClient.query(
      "SELECT reply_to FROM agent_chat WHERE id = $1",
      [id],
    );
    assert.strictEqual(res.rows[0].reply_to, null);
  });

  it("TC-004: backward-compatible 3-arg call works", async () => {
    const id = sendAsGem(
      `SELECT send_agent_message('${PG_GEM}', 'plain 3-arg call', ARRAY['flint']);`,
    );
    const res = await superClient.query(
      "SELECT reply_to, expires_at FROM agent_chat WHERE id = $1",
      [id],
    );
    assert.strictEqual(res.rows[0].reply_to, null);
    assert.strictEqual(res.rows[0].expires_at, null);
  });

  it("TC-005: 4-arg TTL-only call works", async () => {
    const id = sendAsGem(
      `SELECT send_agent_message('${PG_GEM}', 'ttl only', ARRAY['flint'], interval '1 hour');`,
    );
    const res = await superClient.query(
      "SELECT reply_to, expires_at FROM agent_chat WHERE id = $1",
      [id],
    );
    assert.strictEqual(res.rows[0].reply_to, null);
    assert.ok(
      res.rows[0].expires_at > new Date(Date.now()),
      "expires_at should be in the future",
    );
  });

  it("TC-009: bogus reply_to id is rejected via FK violation (23503)", async () => {
    // 999999999 is guaranteed not to exist because agent_chat.id is a SERIAL
    // starting at 1 and the table was truncated before this test.
    assert.throws(
      () => {
        psqlGem(
          `SELECT send_agent_message('${PG_GEM}', 'reply to nothing', ARRAY['flint'], NULL, 999999999);`,
        );
      },
      (err) =>
        errorText(err).includes("foreign key") ||
        errorText(err).includes("23503"),
      "expected foreign-key violation",
    );
  });

  it("TC-010: reply_to may reference an unrelated existing message", async () => {
    // Parent and reply are both sent as gem; the design only enforces that the
    // referenced row exists, not that the reply's sender/recipients match it.
    const unrelatedId = sendAsGem(
      `SELECT send_agent_message('${PG_GEM}', 'unrelated parent', ARRAY['flint']);`,
    );
    const replyId = sendAsGem(
      `SELECT send_agent_message('${PG_GEM}', 'unrelated reply', ARRAY['flint'], NULL, ${unrelatedId});`,
    );
    const res = await superClient.query(
      "SELECT reply_to FROM agent_chat WHERE id = $1",
      [replyId],
    );
    assert.strictEqual(res.rows[0].reply_to, unrelatedId);
  });

  it("TC-011: empty/NULL message body still rejected", async () => {
    assert.throws(
      () => {
        psqlGem(`SELECT send_agent_message('${PG_GEM}', '', ARRAY['flint'], NULL, NULL);`);
      },
      (err) => errorText(err).includes("message cannot be empty"),
      "expected empty-message guard",
    );
  });

  it("TC-012: empty/NULL recipients still rejected", async () => {
    assert.throws(
      () => {
        psqlGem(`SELECT send_agent_message('${PG_GEM}', 'test', ARRAY[]::text[], NULL, NULL);`);
      },
      (err) => errorText(err).includes("recipients cannot be NULL or empty"),
      "expected empty-recipients guard",
    );
  });

  it("TC-013: self-addressed sender is rejected even with reply_to", async () => {
    const parentId = await seedParentMessage();
    assert.throws(
      () => {
        psqlGem(
          `SELECT send_agent_message('${PG_GEM}', 'to myself', ARRAY['${PG_GEM}'], NULL, ${parentId});`,
        );
      },
      (err) => errorText(err).includes("cannot message themselves"),
      "expected self-message guard",
    );
  });

  it("TC-014: session_user mismatch is rejected regardless of reply_to", async () => {
    const parentId = await seedParentMessage();
    assert.throws(
      () => {
        // Connected as `gem`, but sender claims to be `flint`.
        psqlGem(
          `SELECT send_agent_message('flint', 'spoofed sender', ARRAY['nova'], NULL, ${parentId});`,
        );
      },
      (err) => errorText(err).includes("sender must match session_user"),
      "expected sender/session_user guard",
    );
  });

  it("TC-015: reply_to = 0 and negative values are rejected via FK", async () => {
    for (const badId of [0, -1]) {
      assert.throws(
        () => {
          psqlGem(
            `SELECT send_agent_message('${PG_GEM}', 'bad reply id', ARRAY['flint'], NULL, ${badId});`,
          );
        },
        (err) =>
          errorText(err).includes("foreign key") ||
          errorText(err).includes("23503"),
        `expected FK violation for reply_to=${badId}`,
      );
    }
  });

  it("TC-016: non-integer reply_to fails at type coercion", async () => {
    assert.throws(
      () => {
        psqlGem(
          `SELECT send_agent_message('${PG_GEM}', 'bad type', ARRAY['flint'], NULL, 'not-a-number');`,
        );
      },
      (err) =>
        errorText(err).includes("invalid input syntax for type integer") ||
        errorText(err).includes("22P02"),
      "expected integer type-coercion error",
    );
  });

  it("TC-020: bogus reply_to leaves zero rows (atomicity)", async () => {
    const before = await superClient.query("SELECT COUNT(*)::int AS n FROM agent_chat");
    assert.strictEqual(before.rows[0].n, 0);
    try {
      psqlGem(
        `SELECT send_agent_message('${PG_GEM}', 'atomic reply', ARRAY['flint'], NULL, 999999999);`,
      );
      assert.fail("expected FK violation");
    } catch {
      // expected
    }
    const after = await superClient.query("SELECT COUNT(*)::int AS n FROM agent_chat");
    assert.strictEqual(
      after.rows[0].n,
      0,
      "no partial row should remain after FK-violation rollback",
    );
  });
});
