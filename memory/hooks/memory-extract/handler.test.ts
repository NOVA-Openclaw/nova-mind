/**
 * Tests for the nova-mind#701 fix: the memory-extract hook must pass provider
 * API keys to the spawned extraction child even though OpenClaw scrubs them from
 * the live process.env (zero-env hardening, cf. nova-mind#408).
 *
 * No real secret values appear here: dummy placeholders only, and the child is
 * probed for SET/UNSET only (never a value or length).
 *
 * Run: npx tsx --test memory/hooks/memory-extract/handler.test.ts
 */
import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { loadSecretsEnv, fillMissingEnv, buildChildEnv } from "./handler.js";

const KEY = "OPENROUTER_API_KEY";

describe("memory-extract #701 provider-key restore", () => {
  let tmpDir: string;
  let secretsPath: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "me701-"));
    secretsPath = path.join(tmpDir, "secrets.env");
    fs.writeFileSync(
      secretsPath,
      [
        "# comment line",
        "",
        "OPENROUTER_API_KEY=router-dummy",
        "QUOTED_KEY=\"quoted-dummy\"",
        "not a valid line",
        "123BAD=skipme",
      ].join("\n"),
      "utf-8"
    );
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("loadSecretsEnv parses secrets.env (skips comments/blanks, strips quotes, ignores invalid keys)", () => {
    const parsed = loadSecretsEnv(secretsPath);
    assert.ok(parsed[KEY], "provider key should be parsed");
    assert.equal(parsed.QUOTED_KEY, "quoted-dummy");
    assert.ok(!("123BAD" in parsed));
  });

  it("#701 regression guard: child env gets the key even though process.env does NOT have it", () => {
    const saved = process.env[KEY];
    delete process.env[KEY];
    try {
      assert.ok(!(KEY in process.env), "precondition: process.env must not carry the key");
      const childEnv = buildChildEnv({ ...process.env }, secretsPath);
      assert.ok(childEnv[KEY], "child env must carry the restored key (fails if the #701 bug returns)");
      const seen = execFileSync(
        process.execPath,
        ["-e", "process.stdout.write(process.env.OPENROUTER_API_KEY ? 'SET' : 'UNSET')"],
        { env: childEnv, encoding: "utf-8" }
      );
      assert.equal(seen, "SET");
    } finally {
      if (saved === undefined) delete process.env[KEY];
      else process.env[KEY] = saved;
    }
  });

  it("missing secrets.env is a no-op, not a throw", () => {
    const missing = path.join(tmpDir, "does-not-exist.env");
    assert.doesNotThrow(() => buildChildEnv({ FOO: "bar" }, missing));
    assert.deepEqual(buildChildEnv({ FOO: "bar" }, missing), { FOO: "bar" });
  });

  it("a key already present in the env is never overwritten", () => {
    const env = buildChildEnv({ [KEY]: "preset-dummy", OTHER: "x" }, secretsPath);
    assert.equal(env[KEY], "preset-dummy");
    const t: NodeJS.ProcessEnv = { ALREADY: "keep-me" };
    fillMissingEnv(t, { ALREADY: "DO-NOT-USE", NEWKEY: "added" });
    assert.equal(t.ALREADY, "keep-me");
    assert.equal(t.NEWKEY, "added");
  });
});
