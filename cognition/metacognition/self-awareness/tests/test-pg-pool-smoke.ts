/**
 * Smoke test for self-awareness's pg-pool.ts (nova-mind #408).
 *
 * Confirms the ported #330 fix pattern: self-awareness's pg-pool module
 * calls the shared lib/pg-env.ts loadPgEnv() loader correctly (Path A —
 * see se-runs/375-step3-test-design.md §3), preserves plugin-specific
 * config (pool max=3, "[self-awareness]" log prefixes, "nova" default
 * user), and never mutates process.env.PG* at any point.
 *
 * This does not duplicate memory/tests/test-pg-env.ts's full TC-1.1
 * through TC-5.1 matrix against the shared loader itself (that coverage
 * already exists there) — it verifies self-awareness's *consumption* of
 * that loader is correct and side-effect free.
 *
 * Run with: npx tsx tests/test-pg-pool-smoke.ts
 */

import { mkdtempSync, mkdirSync, writeFileSync, rmSync, cpSync } from "fs";
import { join, dirname } from "path";
import { tmpdir } from "os";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

let PASS = 0;
let FAIL = 0;

function assertEq<T>(desc: string, expected: T, actual: T) {
  if (expected === actual) {
    console.log(`  PASS: ${desc}`);
    PASS++;
  } else {
    console.log(`  FAIL: ${desc} (expected='${String(expected)}', got='${String(actual)}')`);
    FAIL++;
  }
}

function assertTrue(desc: string, cond: boolean) {
  if (cond) {
    console.log(`  PASS: ${desc}`);
    PASS++;
  } else {
    console.log(`  FAIL: ${desc}`);
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

async function run() {
  const realHome = process.env.HOME as string;
  // The real deployed lib/pg-env.ts on this host — used to build scratch
  // fake-HOME trees that carry a real, working loader (not a stub), so we
  // exercise the actual consumption path, not a mock.
  const realPgEnvPath = join(realHome, ".openclaw", "lib", "pg-env.ts");

  const scratchRoot = mkdtempSync(join(tmpdir(), "self-awareness-pgpool-test-"));

  function makeFakeHome(name: string): string {
    const home = join(scratchRoot, name);
    const libDir = join(home, ".openclaw", "lib");
    mkdirSync(libDir, { recursive: true });
    cpSync(realPgEnvPath, join(libDir, "pg-env.ts"));
    return home;
  }

  function writePostgresJson(home: string, data: unknown): void {
    const path = join(home, ".openclaw", "postgres.json");
    const content = typeof data === "string" ? data : JSON.stringify(data);
    writeFileSync(path, content);
  }

  // Import the module under test fresh (avoid caching across scenarios that
  // rely on distinct HOME values feeding through to loadPgConfig()).
  const pgPoolPath = join(__dirname, "..", "src", "shared", "pg-pool.ts");

  try {
    // ── Scenario 1: full config file, no ENV — values loaded via shared loader ──
    console.log("Scenario 1: Config file with all fields, no ENV set");
    clearPgVars();
    const home1 = makeFakeHome("s1");
    writePostgresJson(home1, {
      host: "dbhost1", port: 5433, database: "testdb1",
      user: "testuser1", password: "secret1",
    });
    process.env.HOME = home1;
    const { loadPgConfig: loadPgConfig1 } = await import(pgPoolPath);
    const cfg1 = await loadPgConfig1();
    assertEq("host from config via shared loader", "dbhost1", cfg1.host);
    assertEq("port from config via shared loader (number)", 5433, cfg1.port);
    assertEq("database from config via shared loader", "testdb1", cfg1.database);
    assertEq("user from config via shared loader", "testuser1", cfg1.user);
    assertEq("password from config via shared loader", "secret1", cfg1.password);
    assertEnvUnset("PGHOST not set after loadPgConfig()", "PGHOST");
    assertEnvUnset("PGPORT not set after loadPgConfig()", "PGPORT");
    assertEnvUnset("PGDATABASE not set after loadPgConfig()", "PGDATABASE");
    assertEnvUnset("PGUSER not set after loadPgConfig()", "PGUSER");
    assertEnvUnset("PGPASSWORD not set after loadPgConfig()", "PGPASSWORD");

    // ── Scenario 2: ENV takes priority over config file (loader precedence) ──
    console.log("Scenario 2: ENV set — takes priority over config file (return value only)");
    clearPgVars();
    process.env.HOME = home1; // reuse s1's config file
    Object.assign(process.env, {
      PGHOST: "envhost", PGPORT: "9999", PGDATABASE: "envdb",
      PGUSER: "envuser", PGPASSWORD: "envpass",
    });
    const cfg2 = await loadPgConfig1();
    assertEq("host from ENV wins", "envhost", cfg2.host);
    assertEq("port from ENV wins (number)", 9999, cfg2.port);
    assertEq("database from ENV wins", "envdb", cfg2.database);
    assertEq("user from ENV wins", "envuser", cfg2.user);
    assertEq("password from ENV wins", "envpass", cfg2.password);
    clearPgVars();

    // ── Scenario 3: postgres.json absent entirely — falls back to plugin defaults ──
    console.log("Scenario 3: postgres.json absent — self-awareness defaults preserved");
    clearPgVars();
    const home3 = makeFakeHome("s3"); // has lib/pg-env.ts but no postgres.json
    process.env.HOME = home3;
    const cfg3 = await loadPgConfig1();
    assertEq("host default preserved", "localhost", cfg3.host);
    assertEq("port default preserved (number)", 5432, cfg3.port);
    assertEq("database default preserved (self-awareness-specific: nova_memory)", "nova_memory", cfg3.database);
    assertEq("user default preserved (self-awareness-specific: nova)", "nova", cfg3.user);
    assertEq("password default preserved (undefined)", undefined, cfg3.password);
    assertEnvUnset("PGHOST still unset after default fallback", "PGHOST");
    assertEnvUnset("PGPASSWORD still unset after default fallback", "PGPASSWORD");

    // ── Scenario 4: postgres.json with empty strings — treated as absent ──
    console.log("Scenario 4: postgres.json with empty strings — treated as absent");
    clearPgVars();
    const home4 = makeFakeHome("s4");
    writePostgresJson(home4, { host: "", port: 5432, user: "" });
    process.env.HOME = home4;
    const cfg4 = await loadPgConfig1();
    assertEq("host empty->default", "localhost", cfg4.host);
    assertEq("user empty->default (self-awareness default)", "nova", cfg4.user);

    // ── Scenario 5: postgres.json with null values — treated as absent ──
    console.log("Scenario 5: postgres.json with null values — treated as absent");
    clearPgVars();
    const home5 = makeFakeHome("s5");
    writePostgresJson(home5, { host: null, port: 5432 });
    process.env.HOME = home5;
    const cfg5 = await loadPgConfig1();
    assertEq("host null->default", "localhost", cfg5.host);
    assertEq("port (number)", 5432, cfg5.port);

    // ── Scenario 6: malformed JSON — falls back to defaults, no crash ──
    console.log("Scenario 6: malformed JSON — falls back to defaults, no exception");
    clearPgVars();
    const home6 = makeFakeHome("s6");
    writePostgresJson(home6, "{invalid json");
    process.env.HOME = home6;
    const cfg6 = await loadPgConfig1();
    assertEq("host malformed->default", "localhost", cfg6.host);
    assertEq("database malformed->default (self-awareness-specific)", "nova_memory", cfg6.database);

    // ── Scenario 7: shared loader unreachable (missing ~/.openclaw/lib/pg-env.ts) ──
    console.log("Scenario 7: shared loader unreachable — falls back to hardcoded defaults gracefully");
    clearPgVars();
    const home7 = join(scratchRoot, "s7"); // deliberately no lib/pg-env.ts
    mkdirSync(home7, { recursive: true });
    process.env.HOME = home7;
    const cfg7 = await loadPgConfig1();
    assertEq("host falls back when loader missing", "localhost", cfg7.host);
    assertEq("database falls back when loader missing", "nova_memory", cfg7.database);
    assertEq("user falls back when loader missing", "nova", cfg7.user);
    assertEnvUnset("PGHOST unset even on loader-missing fallback path", "PGHOST");

    // ── Scenario 8: getPool() constructs Pool with explicit config incl. max=3 ──
    console.log("Scenario 8: getPool() — Pool receives explicit config object, max=3 preserved");
    clearPgVars();
    process.env.HOME = home1;
    const { getPool } = await import(pgPoolPath);
    const pool = await getPool();
    assertTrue("getPool() returns a Pool instance", pool != null && typeof pool.query === "function");
    assertTrue("Pool options.max === 3 (self-awareness-specific pool size)", pool.options.max === 3);
    assertEq("Pool options.host from explicit config (not process.env)", "dbhost1", pool.options.host);
    assertEq("Pool options.database from explicit config", "testdb1", pool.options.database);
    assertEnvUnset("PGHOST still unset after getPool()", "PGHOST");
    assertEnvUnset("PGPASSWORD still unset after getPool()", "PGPASSWORD");
    await pool.end().catch(() => {});

  } finally {
    process.env.HOME = realHome;
    clearPgVars();
    rmSync(scratchRoot, { recursive: true, force: true });
  }

  console.log();
  console.log("═══════════════════════════════════════════");
  console.log(`  self-awareness pg-pool smoke tests: ${PASS} passed, ${FAIL} failed`);
  console.log("═══════════════════════════════════════════");
  process.exit(FAIL === 0 ? 0 : 1);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
