/**
 * Test suite for lib/pg-env.ts
 * Run with: npx tsx tests/test-pg-env.ts
 *
 * Tests the updated loadPgEnv() which returns a PgConnectionConfig object
 * instead of Record<string, string>, and does NOT set process.env.
 */

import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir, userInfo } from "os";

// We need to test loadPgEnv with different config paths
// Import dynamically to avoid module caching issues
const libPath = join(__dirname, "..", "lib", "pg-env.ts");

let PASS = 0;
let FAIL = 0;

interface PgConnectionConfig {
  host?: string;
  port?: number;
  database?: string;
  user?: string;
  password?: string;
}

function assertEq<T>(desc: string, expected: T, actual: T) {
  if (expected === actual) {
    console.log(`  PASS: ${desc}`);
    PASS++;
  } else {
    console.log(`  FAIL: ${desc} (expected='${String(expected)}', got='${String(actual)}')`);
    FAIL++;
  }
}

function assertEnvUnset(desc: string, envVar: string) {
  const val = process.env[envVar];
  if (val === undefined) {
    console.log(`  PASS: ${desc} (${envVar} not set)`);
    PASS++;
  } else {
    console.log(`  FAIL: ${desc} — ${envVar} was set to '${val}' (process.env should not be modified)`);
    FAIL++;
  }
}

function clearPgVars() {
  for (const v of ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"]) {
    delete process.env[v];
  }
}

function writeConfig(base: string, data: unknown): string {
  const dir = join(base, ".openclaw");
  mkdirSync(dir, { recursive: true });
  const path = join(dir, "postgres.json");
  const content = typeof data === "string" ? data : JSON.stringify(data);
  writeFileSync(path, content);
  return path;
}

// Dynamic import to get fresh module
async function run() {
  const { loadPgEnv } = await import(libPath);
  const tmp = mkdtempSync(join(tmpdir(), "pg-env-test-"));

  try {
    const currentUser = userInfo().username;

    // TC-1.1
    console.log("TC-1.1: Config with all fields, no ENV");
    clearPgVars();
    const cfg1 = writeConfig(join(tmp, "tc1"), {
      host: "dbhost", port: 5433, database: "testdb",
      user: "testuser", password: "secret123"
    });
    let r: PgConnectionConfig = loadPgEnv(cfg1);
    assertEq("host", "dbhost", r.host);
    assertEq("port (number)", 5433, r.port);
    assertEq("database", "testdb", r.database);
    assertEq("user", "testuser", r.user);
    assertEq("password", "secret123", r.password);
    // Verify process.env was NOT polluted
    assertEnvUnset("process.env.PGHOST not set", "PGHOST");
    assertEnvUnset("process.env.PGDATABASE not set", "PGDATABASE");
    assertEnvUnset("process.env.PGPASSWORD not set", "PGPASSWORD");

    // TC-1.2
    console.log("TC-1.2: All ENV set — ENV takes priority");
    clearPgVars();
    Object.assign(process.env, {
      PGHOST: "envhost", PGPORT: "9999", PGDATABASE: "envdb",
      PGUSER: "envuser", PGPASSWORD: "envpass"
    });
    r = loadPgEnv(cfg1);
    assertEq("host from ENV", "envhost", r.host);
    assertEq("port from ENV (number)", 9999, r.port);
    assertEq("database from ENV", "envdb", r.database);
    assertEq("user from ENV", "envuser", r.user);
    assertEq("password from ENV", "envpass", r.password);

    // TC-1.4
    console.log("TC-1.4: Mixed ENV + config");
    clearPgVars();
    process.env.PGHOST = "remotehost";
    process.env.PGPORT = "9999";
    r = loadPgEnv(cfg1);
    assertEq("host from ENV", "remotehost", r.host);
    assertEq("port from ENV (number)", 9999, r.port);
    assertEq("database from config", "testdb", r.database);
    assertEq("user from config", "testuser", r.user);

    // TC-2.1: No ENV, no config
    console.log("TC-2.1: No ENV, no config — defaults");
    clearPgVars();
    r = loadPgEnv("/nonexistent/path/postgres.json");
    assertEq("host default", "localhost", r.host);
    assertEq("port default (number)", 5432, r.port);
    assertEq("user default", currentUser, r.user);
    assertEq("database unset", undefined, r.database);
    assertEq("password unset", undefined, r.password);
    // Verify process.env still unset
    assertEnvUnset("process.env.PGHOST not set after defaults", "PGHOST");

    // TC-2.3: Empty strings
    console.log("TC-2.3: Config with empty strings");
    clearPgVars();
    const cfg23 = writeConfig(join(tmp, "tc2_3"), { host: "", port: 5432, user: "" });
    r = loadPgEnv(cfg23);
    assertEq("host empty->default", "localhost", r.host);
    assertEq("user empty->default", currentUser, r.user);

    // TC-3.4: Null values
    console.log("TC-3.4: Null values in JSON");
    clearPgVars();
    const cfg34 = writeConfig(join(tmp, "tc3_4"), { host: null, port: 5432 });
    r = loadPgEnv(cfg34);
    assertEq("host null->default", "localhost", r.host);
    assertEq("port (number)", 5432, r.port);

    // TC-3.5: Empty ENV string
    console.log("TC-3.5: ENV set to empty string");
    clearPgVars();
    process.env.PGHOST = "";
    r = loadPgEnv(cfg1);
    assertEq("host empty ENV->config", "dbhost", r.host);

    // TC-4.1: Malformed JSON
    console.log("TC-4.1: Malformed JSON");
    clearPgVars();
    const cfgBad = writeConfig(join(tmp, "tc4_1"), "{invalid json");
    r = loadPgEnv(cfgBad);
    assertEq("host malformed->default", "localhost", r.host);

    // TC-3.2: Port as string in config
    console.log("TC-3.2: Port as string in config");
    clearPgVars();
    const cfg32 = writeConfig(join(tmp, "tc3_2"), { port: "5433" });
    r = loadPgEnv(cfg32);
    assertEq("port string->number", 5433, r.port);

    // TC-3.3: Port as integer in config
    console.log("TC-3.3: Port as integer in config");
    clearPgVars();
    const cfg33 = writeConfig(join(tmp, "tc3_3"), { port: 5433 });
    r = loadPgEnv(cfg33);
    assertEq("port int->number", 5433, r.port);

    // TC-5.1: Verify no process.env mutation throughout (post-test check)
    console.log("TC-5.1: Final check — process.env.PG* all unset after clearPgVars");
    clearPgVars();
    r = loadPgEnv(cfg1);
    // After loading from config, env should still be clean
    assertEnvUnset("PGHOST unset after config load", "PGHOST");
    assertEnvUnset("PGPORT unset after config load", "PGPORT");
    assertEnvUnset("PGDATABASE unset after config load", "PGDATABASE");
    assertEnvUnset("PGUSER unset after config load", "PGUSER");
    assertEnvUnset("PGPASSWORD unset after config load", "PGPASSWORD");

  } finally {
    clearPgVars();
    rmSync(tmp, { recursive: true, force: true });
  }

  console.log();
  console.log("═══════════════════════════════════════════");
  console.log(`  TypeScript tests: ${PASS} passed, ${FAIL} failed`);
  console.log("═══════════════════════════════════════════");
  process.exit(FAIL === 0 ? 0 : 1);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
