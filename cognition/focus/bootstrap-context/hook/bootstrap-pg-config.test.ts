/**
 * Unit tests for bootstrap override detection and warning helpers.
 *
 * Covers nova-mind#488 handler-side validation that loadPgEnv does not
 * provide: unknown-key warnings and the distinct pg-env-unavailable warning.
 *
 * Run: npx tsx --test cognition/focus/bootstrap-context/hook/bootstrap-pg-config.test.ts
 */

import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  detectBootstrapOverride,
  pgEnvUnavailableWarning,
} from "./bootstrap-pg-config.ts";

function writeJson(filePath: string, data: unknown) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(data), "utf-8");
}

describe("detectBootstrapOverride", { concurrency: false }, () => {
  let tmpDir: string;
  let homeDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "bootstrap-cfg-test-"));
    homeDir = path.join(tmpDir, "home");
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("reports not configured when postgres.json is missing", () => {
    const result = detectBootstrapOverride(homeDir);
    assert.strictEqual(result.configured, false);
    assert.deepStrictEqual(result.unknownKeys, []);
  });

  it("reports not configured when bootstrap section is absent", () => {
    writeJson(path.join(homeDir, ".openclaw", "postgres.json"), {
      database: "newhart_memory",
    });
    const result = detectBootstrapOverride(homeDir);
    assert.strictEqual(result.configured, false);
    assert.deepStrictEqual(result.unknownKeys, []);
  });

  it("reports configured with no unknown keys for valid section", () => {
    writeJson(path.join(homeDir, ".openclaw", "postgres.json"), {
      database: "newhart_memory",
      bootstrap: { database: "nova_memory" },
    });
    const result = detectBootstrapOverride(homeDir);
    assert.strictEqual(result.configured, true);
    assert.deepStrictEqual(result.unknownKeys, []);
  });

  it("reports unknown keys but still configured", () => {
    writeJson(path.join(homeDir, ".openclaw", "postgres.json"), {
      database: "newhart_memory",
      bootstrap: { database: "nova_memory", datbase: "typo", host: "localhost" },
    });
    const result = detectBootstrapOverride(homeDir);
    assert.strictEqual(result.configured, true);
    assert.deepStrictEqual(result.unknownKeys, ["datbase"]);
  });

  it("reports not configured for non-object section", () => {
    writeJson(path.join(homeDir, ".openclaw", "postgres.json"), {
      database: "newhart_memory",
      bootstrap: 12345,
    });
    const result = detectBootstrapOverride(homeDir);
    assert.strictEqual(result.configured, false);
    assert.deepStrictEqual(result.unknownKeys, []);
  });

  it("reports not configured for null section", () => {
    writeJson(path.join(homeDir, ".openclaw", "postgres.json"), {
      database: "newhart_memory",
      bootstrap: null,
    });
    const result = detectBootstrapOverride(homeDir);
    assert.strictEqual(result.configured, false);
    assert.deepStrictEqual(result.unknownKeys, []);
  });

  it("reports not configured for malformed JSON", () => {
    fs.mkdirSync(path.join(homeDir, ".openclaw"), { recursive: true });
    fs.writeFileSync(
      path.join(homeDir, ".openclaw", "postgres.json"),
      "{not valid",
      "utf-8",
    );
    const result = detectBootstrapOverride(homeDir);
    assert.strictEqual(result.configured, false);
    assert.deepStrictEqual(result.unknownKeys, []);
  });
});

describe("pgEnvUnavailableWarning", () => {
  it("returns plain warning when no override is configured", () => {
    const msg = pgEnvUnavailableWarning(false, new Error("ENOENT"));
    assert.strictEqual(
      msg,
      "[bootstrap-context] Could not load pg-env.ts: ENOENT",
    );
  });

  it("returns distinct warning when override is configured", () => {
    const msg = pgEnvUnavailableWarning(true, new Error("ENOENT"));
    assert.match(
      msg,
      /bootstrap override cannot be applied/,
    );
    assert.match(msg, /ENOENT/);
  });
});
