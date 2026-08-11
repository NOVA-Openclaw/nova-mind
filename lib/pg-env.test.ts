/**
 * Unit tests for loadPgEnv() section-key precedence.
 *
 * Mirrors the Python coverage TC-23 through TC-43 from lib/tests/test_pg_env.py
 * for the TypeScript loader in lib/pg-env.ts.
 *
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

describe("TC-30: section field present + ENV set for same field -> section wins", { concurrency: false }, () => {
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

  it("uses section value when both section and ENV define the field", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "agent_chat");
  });
});

describe("TC-31: section field present + ENV unset -> section wins", { concurrency: false }, () => {
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
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses section value when ENV is unset", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "agent_chat");
  });
});

describe("TC-32: section=None + ENV set -> ENV wins (legacy behavior)", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      database: "nova_memory",
    });
    process.env.PGDATABASE = "env_db";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses ENV value when no section is provided", () => {
    const cfg = loadPgEnv(configPath);
    assert.strictEqual(cfg.database, "env_db");
  });
});

describe("TC-33: ENV wins for fields omitted from section", { concurrency: false }, () => {
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
    process.env.PGUSER = "env_user";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses section for defined field and ENV for omitted field", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "agent_chat");
    assert.strictEqual(cfg.user, "env_user");
  });
});

describe("TC-34: empty-string section value falls back to ENV", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      database: "nova_memory",
      agent_chat: { database: "" },
    });
    process.env.PGDATABASE = "env_db";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back to ENV when section value is empty", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "env_db");
  });
});

describe("TC-35: empty-string ENV treated as unset, section wins", { concurrency: false }, () => {
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
    process.env.PGDATABASE = "";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses section value when ENV is empty", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "agent_chat");
  });
});

describe("TC-36: missing section name falls through to ENV/flat/default chain", { concurrency: false }, () => {
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
    process.env.PGDATABASE = "env_db";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses ENV when requested section does not exist", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "env_db");
  });
});

describe("TC-37: section defines DB but not host; ENV defines host", { concurrency: false }, () => {
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
      agent_chat: { database: "agent_chat" },
    });
    process.env.PGHOST = "env-host";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses ENV for host and section for database", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.host, "env-host");
    assert.strictEqual(cfg.database, "agent_chat");
  });
});

describe("TC-38: section silent on password preserves flat-config behavior", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      database: "nova_memory",
      user: "flat-user",
      password: "flat-pass",
      agent_chat: { database: "agent_chat", user: "chat-user" },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back to flat password when section omits it", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.password, "flat-pass");
  });
});

describe("TC-39: section password wins over ENV", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      database: "nova_memory",
      password: "flat-pass",
      agent_chat: { password: "chat-pass" },
    });
    process.env.PGPASSWORD = "env-pass";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses section password when both section and ENV define it", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.password, "chat-pass");
  });
});

describe("TC-40: all 5 fields in section, all 5 in ENV -> section wins all", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      port: 5432,
      database: "nova_memory",
      user: "flat-user",
      password: "flat-pass",
      agent_chat: {
        host: "sect-host",
        port: 5433,
        database: "agent_chat",
        user: "sect-user",
        password: "sect-pass",
      },
    });
    Object.assign(process.env, {
      PGHOST: "env-host",
      PGPORT: "9999",
      PGDATABASE: "env_db",
      PGUSER: "env_user",
      PGPASSWORD: "env-pass",
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses section values for every field", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.host, "sect-host");
    assert.strictEqual(cfg.port, 5433);
    assert.strictEqual(cfg.database, "agent_chat");
    assert.strictEqual(cfg.user, "sect-user");
    assert.strictEqual(cfg.password, "sect-pass");
  });
});

describe("TC-41: all 5 fields in section, ENV unset -> section wins all", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      port: 5432,
      database: "nova_memory",
      user: "flat-user",
      password: "flat-pass",
      agent_chat: {
        host: "sect-host",
        port: 5433,
        database: "agent_chat",
        user: "sect-user",
        password: "sect-pass",
      },
    });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses section values for every field when ENV is unset", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.host, "sect-host");
    assert.strictEqual(cfg.port, 5433);
    assert.strictEqual(cfg.database, "agent_chat");
    assert.strictEqual(cfg.user, "sect-user");
    assert.strictEqual(cfg.password, "sect-pass");
  });
});

describe("TC-42: empty section dict behaves like no section", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      host: "flat-host",
      port: 5432,
      database: "nova_memory",
      user: "flat-user",
      password: "flat-pass",
      agent_chat: {},
    });
    process.env.PGDATABASE = "env_db";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("falls back to ENV and flat keys when section is empty", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "env_db");
    assert.strictEqual(cfg.host, "flat-host");
    assert.strictEqual(cfg.user, "flat-user");
    assert.strictEqual(cfg.password, "flat-pass");
  });
});

describe("TC-43: per-field independence", { concurrency: false }, () => {
  const fieldSpecs: Array<[string, string, string, string | number]> = [
    ["host", "PGHOST", "env-host", "sect-host"],
    ["port", "PGPORT", "9999", 5433],
    ["database", "PGDATABASE", "env_db", "agent_chat"],
    ["user", "PGUSER", "env_user", "sect-user"],
    ["password", "PGPASSWORD", "env_pass", "sect-pass"],
  ];

  for (const [jsonKey, envVar, envVal, sectVal] of fieldSpecs) {
    describe(`field ${jsonKey}`, () => {
      let tmpDir: string;
      let configPath: string;
      let savedEnv: Record<string, string | undefined>;

      before(() => {
        savedEnv = clearPgEnv();
        tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
        configPath = path.join(tmpDir, "postgres.json");
        writeJson(configPath, {
          [jsonKey]: "flat-val",
          agent_chat: { [jsonKey]: sectVal },
        });
        process.env[envVar] = envVal;
      });

      after(() => {
        fs.rmSync(tmpDir, { recursive: true, force: true });
        restorePgEnv(savedEnv);
      });

      it("section value wins for this field", () => {
        const cfg = loadPgEnv(configPath, "agent_chat");
        assert.strictEqual(cfg[jsonKey as keyof typeof cfg], sectVal);
      });
    });
  }
});

describe("Regression: agent_chat database wins over gateway PGDATABASE", { concurrency: false }, () => {
  let tmpDir: string;
  let configPath: string;
  let savedEnv: Record<string, string | undefined>;

  before(() => {
    savedEnv = clearPgEnv();
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pg-env-test-"));
    configPath = path.join(tmpDir, "postgres.json");
    writeJson(configPath, {
      database: "nova_memory",
      agent_chat: { database: "agent_chat_staging" },
    });
    process.env.PGDATABASE = "nova_staging_memory";
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
    restorePgEnv(savedEnv);
  });

  it("uses agent_chat section database instead of process.env.PGDATABASE", () => {
    const cfg = loadPgEnv(configPath, "agent_chat");
    assert.strictEqual(cfg.database, "agent_chat_staging");
  });
});
