/**
 * Unit tests for loadPgEnv() with the `bootstrap` section.
 *
 * Mirrors the agent_chat section-test precedent (TC-23-29) and adds coverage
 * for nova-mind#488: bootstrap section precedence, fallback, and whitespace
 * trimming.
 *
 * Run: npx tsx --test memory/lib/pg-env.test.ts
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

describe("TC-23: bootstrap section present and valid uses section fields", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      database: "newhart_memory",
      user: "flat-user",
      password: "flat-pass",
      bootstrap: {
        database: "nova_memory",
        user: "nova",
        password: "nova-pass",
      },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses bootstrap database/user/password", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.database, "nova_memory");
    assert.strictEqual(cfg.user, "nova");
    assert.strictEqual(cfg.password, "nova-pass");
  });

  it("falls back to flat keys for omitted host/port", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.host, "flat-host");
    assert.strictEqual(cfg.port, 5432);
  });
});

describe("TC-24: bootstrap section absent falls back to flat keys", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      database: "newhart_memory",
      user: "flat-user",
      password: "flat-pass",
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back to flat keys when bootstrap section is missing", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.database, "newhart_memory");
    assert.strictEqual(cfg.user, "flat-user");
    assert.strictEqual(cfg.password, "flat-pass");
    assert.strictEqual(cfg.host, "flat-host");
  });
});

describe("TC-25: partial bootstrap section falls back per field", { concurrency: false }, () => {
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
      database: "newhart_memory",
      user: "flat-user",
      password: "flat-pass",
      bootstrap: {
        database: "nova_memory",
        user: "nova",
      },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses bootstrap fields that are present", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.database, "nova_memory");
    assert.strictEqual(cfg.user, "nova");
  });

  it("falls back to flat keys for omitted fields", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
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
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.host, "localhost");
    assert.strictEqual(cfg.port, 5432);
    assert.strictEqual(cfg.user, os.userInfo().username);
    assert.strictEqual(cfg.database, undefined);
  });
});

describe("TC-27: bootstrap section not an object warns and falls back to flat keys", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      database: "newhart_memory",
      user: "flat-user",
      password: "flat-pass",
      bootstrap: "oops",
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back to flat keys when bootstrap section is not an object", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.database, "newhart_memory");
    assert.strictEqual(cfg.user, "flat-user");
    assert.strictEqual(cfg.host, "flat-host");
  });
});

describe("TC-14/15/16: invalid bootstrap section types fall back to flat keys", { concurrency: false }, () => {
  let tmpDir: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  for (const badValue of [12345, ["nova_memory"], true]) {
    it(`rejects ${JSON.stringify(badValue)} and falls back`, () => {
      const configPath = path.join(tmpDir, "postgres.json");
      writeJson(configPath, {
        host: "flat-host",
        database: "newhart_memory",
        bootstrap: badValue,
      });
      const cfg = loadPgEnv(configPath, "bootstrap");
      assert.strictEqual(cfg.database, "newhart_memory");
      assert.strictEqual(cfg.host, "flat-host");
    });
  }
});

describe("TC-08: whitespace-only values are treated as absent", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      database: "newhart_memory",
      user: "flat-user",
      password: "flat-pass",
      bootstrap: {
        database: "   ",
        user: "",
        host: null,
      },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back per field when bootstrap values are whitespace-only", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.database, "newhart_memory");
    assert.strictEqual(cfg.user, "flat-user");
    assert.strictEqual(cfg.host, "flat-host");
  });
});

describe("TC-06/07: empty string and null treated as absent", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      database: "newhart_memory",
      bootstrap: {
        database: "",
        user: null,
      },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back to flat keys for empty string and null", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.database, "newhart_memory");
    assert.strictEqual(cfg.user, os.userInfo().username);
  });
});

describe("ENV override still wins over bootstrap section", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      database: "newhart_memory",
      bootstrap: { database: "nova_memory" },
    });
    process.env.PGDATABASE = "debug_scratch_db";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses ENV value when present", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.database, "debug_scratch_db");
  });
});

describe("TC-27: bootstrap section does not leak into flat/no-section callers", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      database: "primary_db",
      user: "flat-user",
      password: "flat-pass",
      agent_chat: { database: "agent_chat", user: "chat-user" },
      bootstrap: { database: "nova_memory", user: "nova" },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("loadPgEnv() with no section ignores bootstrap", () => {
    const cfg = loadPgEnv(configPath);
    assert.strictEqual(cfg.database, "primary_db");
    assert.strictEqual(cfg.user, "flat-user");
  });

  it("loadPgEnv(agent_chat) uses agent_chat section, not bootstrap", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "agent_chat");
    assert.strictEqual(cfg.user, "chat-user");
    assert.strictEqual(cfg.host, "flat-host");
  });

  it("loadPgEnv(bootstrap) ignores sibling agent_chat section", () => {
    const cfg = loadPgEnv(configPath, "bootstrap");
    assert.strictEqual(cfg.database, "nova_memory");
    assert.strictEqual(cfg.user, "nova");
    assert.strictEqual(cfg.host, "flat-host");
  });
});
