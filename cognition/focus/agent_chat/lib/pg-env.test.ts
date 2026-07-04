/**
 * Unit tests for loadPgEnv() section-key fallback.
 *
 * TC-23  Section present and valid → uses section fields
 * TC-24  Section absent → falls back to flat keys
 * TC-25  Section partial → per-field fallback to flat keys / defaults
 * TC-26  Malformed JSON file → warn and fall through to defaults
 * TC-27  Section present but not an object → warn and fall back to flat keys
 * TC-28  Python-only env overwrite semantics (see memory/tests/test_pg_env.py)
 * TC-29  Section absent fallback (covered by TC-24)
 *
 * Framework: Node built-in test runner + tsx.
 * Run: npx tsx --test lib/pg-env.test.ts
 */

import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { loadPgEnv } from "./pg-env.js";

const PG_VARS = ["PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"] as const;

function writeJson(filePath: string, data: unknown) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(data), "utf-8");
}

function clearPgEnv(): Record<string, string | undefined> {
  const saved: Record<string, string | undefined> = {};
  for (const v of PG_VARS) {
    saved[v] = process.env[v];
    delete process.env[v];
  }
  return saved;
}

function restorePgEnv(saved: Record<string, string | undefined>) {
  for (const v of PG_VARS) {
    if (saved[v] === undefined) {
      delete process.env[v];
    } else {
      process.env[v] = saved[v];
    }
  }
}

// Run all describes sequentially and isolate env within each describe.
describe("TC-23: section present and valid uses section fields", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      database: "nova_memory",
      user: "flat-user",
      password: "flat-pass",
      agent_chat: {
        database: "agent_chat",
        user: "chat-user",
        password: "chat-pass",
      },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses section database/user/password", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "agent_chat");
    assert.strictEqual(cfg.user, "chat-user");
    assert.strictEqual(cfg.password, "chat-pass");
  });

  it("falls back to flat keys for omitted host/port", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.host, "flat-host");
    assert.strictEqual(cfg.port, 5432);
  });
});

describe("TC-24: section absent falls back to flat keys", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      database: "nova_memory",
      user: "flat-user",
      password: "flat-pass",
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back to flat keys when section is missing", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "nova_memory");
    assert.strictEqual(cfg.user, "flat-user");
    assert.strictEqual(cfg.password, "flat-pass");
    assert.strictEqual(cfg.host, "flat-host");
  });
});

describe("TC-25: partial section falls back per field", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      port: 5433,
      database: "nova_memory",
      user: "flat-user",
      password: "flat-pass",
      agent_chat: {
        database: "agent_chat",
        user: "chat-user",
      },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses section fields that are present", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "agent_chat");
    assert.strictEqual(cfg.user, "chat-user");
  });

  it("falls back to flat keys for omitted fields", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.host, "flat-host");
    assert.strictEqual(cfg.port, 5433);
    assert.strictEqual(cfg.password, "flat-pass");
  });
});

describe("TC-26: malformed JSON falls through to defaults", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    fs.writeFileSync(configPath, "{not valid json", "utf-8");
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("returns defaults without throwing", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.host, "localhost");
    assert.strictEqual(cfg.port, 5432);
    assert.strictEqual(cfg.user, os.userInfo().username);
    assert.strictEqual(cfg.database, undefined);
  });
});

describe("TC-27: section not an object warns and falls back to flat keys", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      database: "nova_memory",
      user: "flat-user",
      password: "flat-pass",
      agent_chat: "oops",
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back to flat keys when section is not an object", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "nova_memory");
    assert.strictEqual(cfg.user, "flat-user");
    assert.strictEqual(cfg.host, "flat-host");
  });
});

describe("ENV override still wins over section", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      database: "nova_memory",
      agent_chat: { database: "agent_chat" },
    });
    process.env.PGDATABASE = "env_db";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses ENV value when present", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "env_db");
  });
});
