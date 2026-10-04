/**
 * Tests for nova-mind #701 (provider-key restore) + #621 (single-DB resolution).
 *
 * No real secret values: dummy placeholders only; the child is probed for SET/UNSET
 * only (never a value or length). All fixtures are temp files (hermetic).
 *
 * Run: npx tsx --test memory/hooks/memory-extract/handler.test.ts
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { loadSecretsEnv, fillMissingEnv, buildChildEnv, resolveMemoryDb } from "./handler.js";

const KEY = "OPENROUTER_API_KEY";

describe("memory-extract #701 provider-key restore", () => {
  let tmpDir: string;
  let secretsPath: string;
  let pgJson: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "me701-"));
    secretsPath = path.join(tmpDir, "secrets.env");
    fs.writeFileSync(
      secretsPath,
      ["# comment line", "", "OPENROUTER_API_KEY=router-dummy", 'QUOTED_KEY="quoted-dummy"', "not a valid line", "123BAD=skipme"].join("\n"),
      "utf-8"
    );
    pgJson = path.join(tmpDir, "postgres.json");
    fs.writeFileSync(pgJson, JSON.stringify({ database: "file_db" }), "utf-8");
  });

  after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));

  it("loadSecretsEnv parses secrets.env (skips comments/blanks, strips quotes, ignores invalid keys)", () => {
    const parsed = loadSecretsEnv(secretsPath);
    assert.equal(parsed[KEY], "router-dummy");
    assert.equal(parsed.QUOTED_KEY, "quoted-dummy");
    assert.ok(!("123BAD" in parsed));
  });

  it("#701 regression guard: child env gets the provider key even though process.env does NOT have it", () => {
    const saved = process.env[KEY];
    delete process.env[KEY];
    try {
      assert.ok(!(KEY in process.env), "precondition: process.env must not carry the key");
      const childEnv = buildChildEnv({ ...process.env, PGDATABASE: "test_db" }, secretsPath, pgJson);
      assert.ok(childEnv[KEY], "child env must carry the restored key (fails if the #701 bug returns)");
      const seen = execFileSync(process.execPath, ["-e", "process.stdout.write(process.env.OPENROUTER_API_KEY ? 'SET' : 'UNSET')"], { env: childEnv, encoding: "utf-8" });
      assert.equal(seen, "SET");
    } finally {
      if (saved === undefined) delete process.env[KEY]; else process.env[KEY] = saved;
    }
  });

  it("buildChildEnv restores a provider key only when absent (never overwrites a set one)", () => {
    const env1 = buildChildEnv({ PGDATABASE: "test_db" }, secretsPath, pgJson);
    assert.equal(env1[KEY], "router-dummy");
    const env2 = buildChildEnv({ PGDATABASE: "test_db", [KEY]: "preset-dummy" }, secretsPath, pgJson);
    assert.equal(env2[KEY], "preset-dummy");
  });

  it("missing secrets.env is a no-op for provider keys, not a throw", () => {
    const missing = path.join(tmpDir, "nope.env");
    assert.doesNotThrow(() => buildChildEnv({ PGDATABASE: "test_db", FOO: "bar" }, missing, pgJson));
    const env = buildChildEnv({ PGDATABASE: "test_db", FOO: "bar" }, missing, pgJson);
    assert.equal(env.FOO, "bar");
    assert.ok(!(KEY in env));
  });
});

describe("memory-extract #621 single-DB resolution (split-brain fix)", () => {
  let tmpDir: string;
  let pgJson: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "me621-"));
    pgJson = path.join(tmpDir, "postgres.json");
    fs.writeFileSync(pgJson, JSON.stringify({ database: "file_db" }), "utf-8");
  });

  after(() => fs.rmSync(tmpDir, { recursive: true, force: true }));

  it("env PGDATABASE wins over postgres.json .database", () => {
    assert.equal(resolveMemoryDb({ PGDATABASE: "env_db" }, pgJson), "env_db");
  });

  it("postgres.json .database is used when PGDATABASE is unset", () => {
    assert.equal(resolveMemoryDb({}, pgJson), "file_db");
  });

  it("neither present -> throws (handler try/catch then skips the extraction, no crash)", () => {
    const missing = path.join(tmpDir, "none.json");
    assert.throws(() => resolveMemoryDb({}, missing), /No database resolved/);
  });

  it("buildChildEnv pins the resolved DB into the child so python libpq matches handler psql", () => {
    const fromEnv = buildChildEnv({ PGDATABASE: "env_db" }, path.join(tmpDir, "nope.env"), pgJson);
    assert.equal(fromEnv.PGDATABASE, "env_db");
    const fromFile = buildChildEnv({}, path.join(tmpDir, "nope.env"), pgJson);
    assert.equal(fromFile.PGDATABASE, "file_db");
  });

  it("buildChildEnv throws when no DB resolves (hook skips the extraction instead of crashing)", () => {
    assert.throws(() => buildChildEnv({}, path.join(tmpDir, "nope.env"), path.join(tmpDir, "none.json")), /No database resolved/);
  });
});
