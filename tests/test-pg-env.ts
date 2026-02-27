/**
 * Test suite for lib/pg-env.ts
 * Run with: npx tsx tests/test-pg-env.ts
 */

import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir, userInfo } from "os";

// We need to test loadPgEnv with different config paths
// Import dynamically to avoid module caching issues
const libPath = join(__dirname, "..", "lib", "pg-env.ts");

let PASS = 0;
let FAIL = 0;

function assertEq(desc: string, expected: string | undefined, actual: string | undefined) {
  if (expected === actual) {
    console.log(`  PASS: ${desc}`);
    PASS++;
  } else {
    console.log(`  FAIL: ${desc} (expected='${expected}', got='${actual}')`);
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
    let r = loadPgEnv(cfg1);
    assertEq("PGHOST", "dbhost", r.PGHOST);
    assertEq("PGPORT", "5433", r.PGPORT);
    assertEq("PGDATABASE", "testdb", r.PGDATABASE);
    assertEq("PGUSER", "testuser", r.PGUSER);
    assertEq("PGPASSWORD", "secret123", r.PGPASSWORD);

    // TC-1.2
    console.log("TC-1.2: All ENV set");
    clearPgVars();
    Object.assign(process.env, {
      PGHOST: "envhost", PGPORT: "9999", PGDATABASE: "envdb",
      PGUSER: "envuser", PGPASSWORD: "envpass"
    });
    r = loadPgEnv(cfg1);
    assertEq("PGHOST", "envhost", r.PGHOST);
    assertEq("PGPORT", "9999", r.PGPORT);
    assertEq("PGDATABASE", "envdb", r.PGDATABASE);

    // TC-1.4
    console.log("TC-1.4: Mixed ENV + config");
    clearPgVars();
    process.env.PGHOST = "remotehost";
    process.env.PGPORT = "9999";
    r = loadPgEnv(cfg1);
    assertEq("PGHOST", "remotehost", r.PGHOST);
    assertEq("PGPORT", "9999", r.PGPORT);
    assertEq("PGDATABASE", "testdb", r.PGDATABASE);
    assertEq("PGUSER", "testuser", r.PGUSER);

    // TC-2.1: No ENV, no config
    console.log("TC-2.1: No ENV, no config — defaults");
    clearPgVars();
    r = loadPgEnv("/nonexistent/path/postgres.json");
    assertEq("PGHOST", "localhost", r.PGHOST);
    assertEq("PGPORT", "5432", r.PGPORT);
    assertEq("PGUSER", currentUser, r.PGUSER);
    assertEq("PGDATABASE unset", undefined, r.PGDATABASE);
    assertEq("PGPASSWORD unset", undefined, r.PGPASSWORD);

    // TC-2.3: Empty strings
    console.log("TC-2.3: Config with empty strings");
    clearPgVars();
    const cfg23 = writeConfig(join(tmp, "tc2_3"), { host: "", port: 5432, user: "" });
    r = loadPgEnv(cfg23);
    assertEq("PGHOST defaults", "localhost", r.PGHOST);
    assertEq("PGUSER defaults", currentUser, r.PGUSER);

    // TC-3.4: Null values
    console.log("TC-3.4: Null values in JSON");
    clearPgVars();
    const cfg34 = writeConfig(join(tmp, "tc3_4"), { host: null, port: 5432 });
    r = loadPgEnv(cfg34);
    assertEq("PGHOST null->default", "localhost", r.PGHOST);
    assertEq("PGPORT", "5432", r.PGPORT);

    // TC-3.5: Empty ENV string
    console.log("TC-3.5: ENV set to empty string");
    clearPgVars();
    process.env.PGHOST = "";
    r = loadPgEnv(cfg1);
    assertEq("PGHOST empty->config", "dbhost", r.PGHOST);

    // TC-4.1: Malformed JSON
    console.log("TC-4.1: Malformed JSON");
    clearPgVars();
    const cfgBad = writeConfig(join(tmp, "tc4_1"), "{invalid json");
    r = loadPgEnv(cfgBad);
    assertEq("PGHOST malformed->default", "localhost", r.PGHOST);

    // TC-3.2: Port as string
    console.log("TC-3.2: Port as string");
    clearPgVars();
    const cfg32 = writeConfig(join(tmp, "tc3_2"), { port: "5433" });
    r = loadPgEnv(cfg32);
    assertEq("PGPORT string", "5433", r.PGPORT);

    // TC-3.3: Port as integer
    console.log("TC-3.3: Port as integer");
    clearPgVars();
    const cfg33 = writeConfig(join(tmp, "tc3_3"), { port: 5433 });
    r = loadPgEnv(cfg33);
    assertEq("PGPORT int", "5433", r.PGPORT);

  } finally {
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
