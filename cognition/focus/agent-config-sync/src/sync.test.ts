/**
 * Unit tests for buildAgentsList() and syncHeartbeatFiles()
 *
 * TC-244-U-01  NOVA session — self as default, NOVA's subagents only
 * TC-244-U-02  Newhart session — self as default, Newhart's subagents only
 * TC-244-U-03  Mutual exclusion — NOVA and Newhart never see each other
 * TC-244-U-04  Fallback model shape preserved from function rows
 * TC-244-U-05  Row with is_default = null emits no `default` key
 * TC-269-U-01  Heartbeat sync — default agent writes to workspace/ not workspace-nova/
 * TC-269-U-02  Heartbeat sync — subagent writes to workspace-<name>/
 * TC-269-U-03  Heartbeat sync — skip write when content unchanged
 * TC-269-U-04  Heartbeat sync — returns list of updated agent names
 * TC-269-U-05  Heartbeat sync — creates workspace dir if missing
 *
 * Framework: Node built-in test runner (node:test) + tsx for TS execution.
 * Run: npx tsx --test src/sync.test.ts
 */

import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { buildAgentsList, syncHeartbeatFiles } from "./sync.js";
import type { AgentRow, HeartbeatRow } from "./sync.js";

// ── Mock pg.Client helper ───────────────────────────────────────────────────

/**
 * Creates a minimal mock pg.Client whose query() returns fixed HeartbeatRow data.
 * Only the query() method needs to be mocked for syncHeartbeatFiles tests.
 */
function makeMockClient(rows: HeartbeatRow[]): import("pg").Client {
  return {
    query: async () => ({ rows }),
  } as unknown as import("pg").Client;
}

// ── TC-244-U-01: NOVA session ───────────────────────────────────────────────

describe("TC-244-U-01: NOVA session — self as default, NOVA's subagents only", () => {
  const novaRows: AgentRow[] = [
    {
      name: "nova",
      model: "anthropic/claude-opus-4",
      fallback_models: null,
      thinking: "high",
      instance_type: "primary",
      is_default: true,
      allowed_subagents: ["gem", "coder", "scout"],
    },
    {
      name: "coder",
      model: "anthropic/claude-sonnet-4",
      fallback_models: null,
      thinking: "medium",
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
    {
      name: "gem",
      model: "google/gemini-flash",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
    {
      name: "scout",
      model: "google/gemini-flash",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
  ];

  const result = buildAgentsList(novaRows);

  it("nova entry has default: true", () => {
    assert.strictEqual(result.find((e) => e.id === "nova")?.default, true);
  });

  it("coder entry has no default key", () => {
    assert.strictEqual(result.find((e) => e.id === "coder")?.default, undefined);
  });

  it("gem entry has no default key", () => {
    assert.strictEqual(result.find((e) => e.id === "gem")?.default, undefined);
  });

  it("scout entry has no default key", () => {
    assert.strictEqual(result.find((e) => e.id === "scout")?.default, undefined);
  });

  it("all four agents are present", () => {
    assert.deepStrictEqual(
      result.map((e) => e.id).sort(),
      ["coder", "gem", "nova", "scout"],
    );
  });

  it("nova's allowAgents are sorted", () => {
    assert.deepStrictEqual(
      result.find((e) => e.id === "nova")?.subagents?.allowAgents,
      ["coder", "gem", "scout"],
    );
  });

  it("thinking is not emitted for any entry", () => {
    for (const entry of result) {
      assert.ok(
        !Object.prototype.hasOwnProperty.call(entry, "thinking"),
        `Entry '${entry.id}' should not have a thinking property`,
      );
    }
  });
});

// ── TC-244-U-02: Newhart session ────────────────────────────────────────────

describe("TC-244-U-02: Newhart session — self as default, Newhart's subagents only", () => {
  const newhartRows: AgentRow[] = [
    {
      name: "newhart",
      model: "anthropic/claude-opus-4",
      fallback_models: null,
      thinking: "high",
      instance_type: "peer",
      is_default: true,
      allowed_subagents: ["coder", "scout"],
    },
    {
      name: "coder",
      model: "anthropic/claude-sonnet-4",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
    {
      name: "scout",
      model: "google/gemini-flash",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
  ];

  const result = buildAgentsList(newhartRows);

  it("newhart entry has default: true", () => {
    assert.strictEqual(result.find((e) => e.id === "newhart")?.default, true);
  });

  it("coder entry has no default key", () => {
    assert.strictEqual(result.find((e) => e.id === "coder")?.default, undefined);
  });

  it("gem is NOT present (not a Newhart subagent)", () => {
    assert.strictEqual(result.find((e) => e.id === "gem"), undefined);
  });

  it("nova is NOT present", () => {
    assert.strictEqual(result.find((e) => e.id === "nova"), undefined);
  });

  it("exactly three agents are present: newhart, coder, scout", () => {
    assert.deepStrictEqual(
      result.map((e) => e.id).sort(),
      ["coder", "newhart", "scout"],
    );
  });
});

// ── TC-244-U-03: Mutual exclusion ───────────────────────────────────────────

describe("TC-244-U-03: Mutual exclusion — NOVA and Newhart never see each other", () => {
  const novaRows: AgentRow[] = [
    {
      name: "nova",
      model: "anthropic/claude-opus-4",
      fallback_models: null,
      thinking: "high",
      instance_type: "primary",
      is_default: true,
      allowed_subagents: ["gem", "coder", "scout"],
    },
    {
      name: "coder",
      model: "anthropic/claude-sonnet-4",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
    {
      name: "gem",
      model: "google/gemini-flash",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
    {
      name: "scout",
      model: "google/gemini-flash",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
  ];

  const newhartRows: AgentRow[] = [
    {
      name: "newhart",
      model: "anthropic/claude-opus-4",
      fallback_models: null,
      thinking: "high",
      instance_type: "peer",
      is_default: true,
      allowed_subagents: ["coder", "scout"],
    },
    {
      name: "coder",
      model: "anthropic/claude-sonnet-4",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
    {
      name: "scout",
      model: "google/gemini-flash",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
  ];

  const novaResult = buildAgentsList(novaRows);
  const newhartResult = buildAgentsList(newhartRows);

  it("nova's agent list does not include newhart", () => {
    assert.strictEqual(
      novaResult.find((e) => e.id === "newhart"),
      undefined,
    );
  });

  it("newhart's agent list does not include nova", () => {
    assert.strictEqual(
      newhartResult.find((e) => e.id === "nova"),
      undefined,
    );
  });

  it("each list has exactly one entry with default: true", () => {
    const novaDefaults = novaResult.filter((e) => e.default === true);
    const newhartDefaults = newhartResult.filter((e) => e.default === true);
    assert.strictEqual(novaDefaults.length, 1);
    assert.strictEqual(newhartDefaults.length, 1);
  });

  it("nova is default in NOVA's list", () => {
    assert.strictEqual(novaResult.find((e) => e.id === "nova")?.default, true);
  });

  it("newhart is default in Newhart's list", () => {
    assert.strictEqual(
      newhartResult.find((e) => e.id === "newhart")?.default,
      true,
    );
  });
});

// ── TC-244-U-04: Fallback model shape ───────────────────────────────────────

describe("TC-244-U-04: Fallback model shape preserved from function rows", () => {
  const rows: AgentRow[] = [
    {
      name: "coder",
      model: "anthropic/claude-sonnet-4",
      fallback_models: ["openai/gpt-4o", "google/gemini-pro"],
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
    {
      name: "gem",
      model: "google/gemini-flash",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
    {
      name: "scout",
      model: "google/gemini-flash",
      fallback_models: [],
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
  ];

  const result = buildAgentsList(rows);

  it("coder model is object form with primary and fallbacks", () => {
    assert.deepStrictEqual(result.find((e) => e.id === "coder")?.model, {
      primary: "anthropic/claude-sonnet-4",
      fallbacks: ["openai/gpt-4o", "google/gemini-pro"],
    });
  });

  it("fallback order is preserved from DB array", () => {
    const model = result.find((e) => e.id === "coder")?.model;
    assert.ok(typeof model === "object" && "fallbacks" in model);
    assert.deepStrictEqual(model.fallbacks, ["openai/gpt-4o", "google/gemini-pro"]);
  });

  it("gem with null fallback_models uses string model form", () => {
    assert.strictEqual(result.find((e) => e.id === "gem")?.model, "google/gemini-flash");
  });

  it("scout with empty fallback_models array uses string model form", () => {
    assert.strictEqual(
      result.find((e) => e.id === "scout")?.model,
      "google/gemini-flash",
    );
  });
});

// ── TC-244-U-05: is_default = null emits no `default` key ──────────────────

describe("TC-244-U-05: Row with is_default = null emits no `default` key", () => {
  const rows: AgentRow[] = [
    {
      name: "someagent",
      model: "anthropic/claude-sonnet-4",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: null,
      allowed_subagents: null,
    },
    {
      name: "falseagent",
      model: "google/gemini-flash",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    },
  ];

  const result = buildAgentsList(rows);

  it("is_default = null → no default key on entry", () => {
    const entry = result.find((e) => e.id === "someagent");
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "default"),
      "default key must not be present when is_default is null",
    );
    assert.strictEqual(entry.default, undefined);
  });

  it("is_default = false → no default key on entry", () => {
    const entry = result.find((e) => e.id === "falseagent");
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "default"),
      "default key must not be present when is_default is false",
    );
    assert.strictEqual(entry.default, undefined);
  });

  it("only is_default = true produces default: true", () => {
    const trueRow: AgentRow[] = [
      {
        name: "trueagent",
        model: "anthropic/claude-opus-4",
        fallback_models: null,
        thinking: null,
        instance_type: "primary",
        is_default: true,
        allowed_subagents: null,
      },
    ];
    const trueResult = buildAgentsList(trueRow);
    assert.strictEqual(trueResult[0]?.default, true);
    assert.ok(
      Object.prototype.hasOwnProperty.call(trueResult[0], "default"),
      "default key must be present when is_default is true",
    );
  });
});

// ── TC-269-U-01: Default agent writes to workspace/ ─────────────────────────

describe("TC-269-U-01: Heartbeat sync — default agent writes to workspace/ not workspace-nova/", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("nova heartbeat file is written to workspace/HEARTBEAT.md", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "nova", content: "# HEARTBEAT\ntest content\n" },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    const expected = path.join(tmpDir, "workspace", "HEARTBEAT.md");
    assert.ok(fs.existsSync(expected), `Expected file at ${expected}`);
    assert.strictEqual(
      fs.readFileSync(expected, "utf-8"),
      "# HEARTBEAT\ntest content\n",
    );
  });

  it("workspace-nova/ directory is NOT created for default agent", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "nova", content: "# HEARTBEAT\n" },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    const wrongDir = path.join(tmpDir, "workspace-nova");
    assert.ok(
      !fs.existsSync(wrongDir),
      "workspace-nova/ must not be created for the default agent",
    );
  });
});

// ── TC-269-U-02: Subagent writes to workspace-<name>/ ───────────────────────

describe("TC-269-U-02: Heartbeat sync — subagent writes to workspace-<name>/", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("coder heartbeat file is written to workspace-coder/HEARTBEAT.md", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "coder", content: "# CODER HEARTBEAT\n" },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    const expected = path.join(tmpDir, "workspace-coder", "HEARTBEAT.md");
    assert.ok(fs.existsSync(expected), `Expected file at ${expected}`);
    assert.strictEqual(
      fs.readFileSync(expected, "utf-8"),
      "# CODER HEARTBEAT\n",
    );
  });

  it("multiple agents each get their own workspace-<name>/HEARTBEAT.md", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "gem", content: "# GEM\n" },
      { agent_name: "scout", content: "# SCOUT\n" },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    assert.ok(
      fs.existsSync(path.join(tmpDir, "workspace-gem", "HEARTBEAT.md")),
    );
    assert.ok(
      fs.existsSync(path.join(tmpDir, "workspace-scout", "HEARTBEAT.md")),
    );
    assert.strictEqual(
      fs.readFileSync(path.join(tmpDir, "workspace-gem", "HEARTBEAT.md"), "utf-8"),
      "# GEM\n",
    );
  });
});

// ── TC-269-U-03: Skip write when content unchanged ───────────────────────────

describe("TC-269-U-03: Heartbeat sync — skip write when content unchanged", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("returns empty array when content is identical to existing file", async () => {
    const wsDir = path.join(tmpDir, "workspace-coder");
    fs.mkdirSync(wsDir, { recursive: true });
    const filePath = path.join(wsDir, "HEARTBEAT.md");
    fs.writeFileSync(filePath, "unchanged content\n", "utf-8");

    const rows: HeartbeatRow[] = [
      { agent_name: "coder", content: "unchanged content\n" },
    ];
    const client = makeMockClient(rows);
    const updated = await syncHeartbeatFiles(client, tmpDir, "nova");

    assert.deepStrictEqual(updated, []);
  });

  it("returns agent name when content differs from existing file", async () => {
    const wsDir = path.join(tmpDir, "workspace-gem");
    fs.mkdirSync(wsDir, { recursive: true });
    const filePath = path.join(wsDir, "HEARTBEAT.md");
    fs.writeFileSync(filePath, "old content\n", "utf-8");

    const rows: HeartbeatRow[] = [
      { agent_name: "gem", content: "new content\n" },
    ];
    const client = makeMockClient(rows);
    const updated = await syncHeartbeatFiles(client, tmpDir, "nova");

    assert.deepStrictEqual(updated, ["gem"]);
    assert.strictEqual(fs.readFileSync(filePath, "utf-8"), "new content\n");
  });
});

// ── TC-269-U-04: Returns list of updated agent names ─────────────────────────

describe("TC-269-U-04: Heartbeat sync — returns list of updated agent names", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("returns names of all agents whose files changed", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "nova", content: "nova heartbeat\n" },
      { agent_name: "coder", content: "coder heartbeat\n" },
      { agent_name: "gem", content: "gem heartbeat\n" },
    ];
    const client = makeMockClient(rows);
    const updated = await syncHeartbeatFiles(client, tmpDir, "nova");

    // All three are new files → all should be in updated list
    assert.deepStrictEqual(updated.sort(), ["coder", "gem", "nova"]);
  });

  it("returns empty array when no HEARTBEAT rows exist", async () => {
    const client = makeMockClient([]);
    const updated = await syncHeartbeatFiles(client, tmpDir, "nova");
    assert.deepStrictEqual(updated, []);
  });
});

// ── TC-269-U-05: Creates workspace dir if missing ────────────────────────────

describe("TC-269-U-05: Heartbeat sync — creates workspace dir if missing", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("creates workspace/ directory for default agent if it does not exist", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "nova", content: "# HEARTBEAT\n" },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    assert.ok(fs.existsSync(path.join(tmpDir, "workspace")));
  });

  it("creates workspace-<name>/ directory for subagent if it does not exist", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "iris", content: "# HEARTBEAT\n" },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    assert.ok(fs.existsSync(path.join(tmpDir, "workspace-iris")));
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// TC-269-U-06 through TC-269-U-12: Extended HEARTBEAT sync tests (#269)
// ─────────────────────────────────────────────────────────────────────────────

// ── TC-269-U-06: Empty content string is written without skipping ─────────────

describe("TC-269-U-06: Empty content string is written without skipping", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("empty string content creates the file with empty content", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "coder", content: "" },
    ];
    const client = makeMockClient(rows);
    const updated = await syncHeartbeatFiles(client, tmpDir, "nova");

    const filePath = path.join(tmpDir, "workspace-coder", "HEARTBEAT.md");
    assert.ok(fs.existsSync(filePath), `Expected file at ${filePath}`);
    assert.strictEqual(fs.readFileSync(filePath, "utf-8"), "");
    assert.deepStrictEqual(updated, ["coder"]);
  });
});

// ── TC-269-U-07: Very long content (100 KB) is written atomically ─────────────

describe("TC-269-U-07: Very long content (100 KB) is written atomically", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("100KB content is written completely and no .tmp files remain", async () => {
    const bigContent = "x".repeat(100_000);
    const rows: HeartbeatRow[] = [
      { agent_name: "nova", content: bigContent },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    const filePath = path.join(tmpDir, "workspace", "HEARTBEAT.md");
    assert.ok(fs.existsSync(filePath));
    assert.strictEqual(fs.statSync(filePath).size, 100_000);

    // No .tmp files remain
    const entries = fs.readdirSync(path.join(tmpDir, "workspace"));
    const tmpFiles = entries.filter((e) => e.endsWith(".tmp"));
    assert.deepStrictEqual(tmpFiles, [], "No .tmp files should remain after atomic write");
  });
});

// ── TC-269-U-08: Content with special characters ───────────────────────────────

describe("TC-269-U-08: Content with special characters (Unicode, newlines, backticks)", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("special character content is written byte-identical", async () => {
    const specialContent = "# 💎 HEARTBEAT\n\nLine with `backticks` and 中文\n\0null-ish unicode\uFFFD";
    const rows: HeartbeatRow[] = [
      { agent_name: "gem", content: specialContent },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    const filePath = path.join(tmpDir, "workspace-gem", "HEARTBEAT.md");
    assert.ok(fs.existsSync(filePath));
    assert.strictEqual(fs.readFileSync(filePath, "utf-8"), specialContent);
  });
});

// ── TC-269-U-09: Multiple agents — mix of changed and unchanged ────────────────

describe("TC-269-U-09: Multiple agents — mix of changed and unchanged", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
    // Pre-write files for coder (old) and gem (same as incoming)
    fs.mkdirSync(path.join(tmpDir, "workspace-coder"), { recursive: true });
    fs.mkdirSync(path.join(tmpDir, "workspace-gem"), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, "workspace-coder", "HEARTBEAT.md"), "old", "utf-8");
    fs.writeFileSync(path.join(tmpDir, "workspace-gem", "HEARTBEAT.md"), "same", "utf-8");
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("returns only changed agents and skips unchanged ones", async () => {
    const gemMtimeBefore = fs.statSync(path.join(tmpDir, "workspace-gem", "HEARTBEAT.md")).mtimeMs;

    const rows: HeartbeatRow[] = [
      { agent_name: "coder", content: "new" },
      { agent_name: "gem", content: "same" },
      { agent_name: "scout", content: "# SCOUT NEW\n" },
    ];
    const client = makeMockClient(rows);
    const updated = await syncHeartbeatFiles(client, tmpDir, "nova");

    assert.deepStrictEqual(updated.sort(), ["coder", "scout"]);
    assert.strictEqual(fs.readFileSync(path.join(tmpDir, "workspace-coder", "HEARTBEAT.md"), "utf-8"), "new");
    assert.strictEqual(fs.readFileSync(path.join(tmpDir, "workspace-gem", "HEARTBEAT.md"), "utf-8"), "same");

    // gem mtime should be unchanged (file was skipped)
    const gemMtimeAfter = fs.statSync(path.join(tmpDir, "workspace-gem", "HEARTBEAT.md")).mtimeMs;
    assert.strictEqual(gemMtimeBefore, gemMtimeAfter, "gem file mtime should not have changed");
  });
});

// ── TC-269-U-10: Non-default agent named same as some other agent ─────────────

describe("TC-269-U-10: Agent named 'nova' with non-'nova' default agent name", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("nova writes to workspace-nova/ when defaultAgentName is 'newhart'", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "nova", content: "# NOVA HB\n" },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "newhart");

    const correctPath = path.join(tmpDir, "workspace-nova", "HEARTBEAT.md");
    const wrongPath = path.join(tmpDir, "workspace", "HEARTBEAT.md");

    assert.ok(fs.existsSync(correctPath), "workspace-nova/HEARTBEAT.md must exist");
    assert.ok(!fs.existsSync(wrongPath), "workspace/HEARTBEAT.md must NOT exist");
    assert.strictEqual(fs.readFileSync(correctPath, "utf-8"), "# NOVA HB\n");
  });
});

// ── TC-269-U-11: Atomic write — no observable .tmp file after success ──────────

describe("TC-269-U-11: Atomic write — no observable tmp file after success", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("no .tmp files remain after syncHeartbeatFiles resolves", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "nova", content: "# HB\n" },
      { agent_name: "coder", content: "# CODER HB\n" },
    ];
    const client = makeMockClient(rows);
    await syncHeartbeatFiles(client, tmpDir, "nova");

    // Check all workspace dirs for any .tmp files
    const wsDir = path.join(tmpDir, "workspace");
    const wsCoderDir = path.join(tmpDir, "workspace-coder");

    const tmpInWs = fs.existsSync(wsDir)
      ? fs.readdirSync(wsDir).filter((e) => e.endsWith(".tmp"))
      : [];
    const tmpInCoder = fs.existsSync(wsCoderDir)
      ? fs.readdirSync(wsCoderDir).filter((e) => e.endsWith(".tmp"))
      : [];

    assert.deepStrictEqual(tmpInWs, [], "No .tmp files in workspace/");
    assert.deepStrictEqual(tmpInCoder, [], "No .tmp files in workspace-coder/");
  });
});

// ── TC-269-U-12: NULL content — skip write, preserve existing file ─────────────

describe("TC-269-U-12: NULL content in row — skip write, preserve existing file", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "heartbeat-test-"));
    fs.mkdirSync(path.join(tmpDir, "workspace-coder"), { recursive: true });
    fs.writeFileSync(
      path.join(tmpDir, "workspace-coder", "HEARTBEAT.md"),
      "# existing content",
      "utf-8",
    );
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("NULL content: file is preserved unchanged and agent not in updated list", async () => {
    const rows: HeartbeatRow[] = [
      { agent_name: "coder", content: null as unknown as string },
    ];
    const client = makeMockClient(rows);
    const updated = await syncHeartbeatFiles(client, tmpDir, "nova");

    assert.deepStrictEqual(updated, []);
    assert.strictEqual(
      fs.readFileSync(path.join(tmpDir, "workspace-coder", "HEARTBEAT.md"), "utf-8"),
      "# existing content",
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// TC-262-U-01 through TC-262-U-08: Per-agent heartbeat config tests (#262)
// ─────────────────────────────────────────────────────────────────────────────

// Helper: create an AgentRow with heartbeat fields
function makeAgentRow(
  name: string,
  heartbeatEnabled: boolean | null,
  heartbeatEvery: string | null = null,
  heartbeatTarget: string | null = null,
  heartbeatTo: string | null = null,
  isDefault = false,
): AgentRow {
  return {
    name,
    model: "anthropic/claude-sonnet-4",
    fallback_models: null,
    thinking: null,
    instance_type: "subagent",
    is_default: isDefault,
    allowed_subagents: null,
    heartbeat_enabled: heartbeatEnabled,
    heartbeat_every: heartbeatEvery,
    heartbeat_target: heartbeatTarget,
    heartbeat_to: heartbeatTo,
  };
}

// ── TC-262-U-01: heartbeat_enabled=true → emits heartbeat object ──────────────

describe("TC-262-U-01: heartbeat_enabled=true → emits heartbeat object in agents.json", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova", true, "5m", "discord", "channel:1234", true),
  ];
  const result = buildAgentsList(rows);

  it("nova entry has heartbeat object with all four fields", () => {
    const entry = result.find((e) => e.id === "nova");
    assert.ok(entry !== undefined);
    assert.deepStrictEqual(entry.heartbeat, {
      every: "5m",
      target: "discord",
      to: "channel:1234",
    });
  });

  it("heartbeat key is present (not missing)", () => {
    const entry = result.find((e) => e.id === "nova");
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"));
  });
});

// ── TC-262-U-02: heartbeat_enabled=false → emits `"heartbeat": false` ──────────

describe("TC-262-U-02: heartbeat_enabled=false → emits heartbeat: false", () => {
  const rows: AgentRow[] = [
    makeAgentRow("coder", false),
  ];
  const result = buildAgentsList(rows);

  it("coder entry has heartbeat: false (boolean)", () => {
    const entry = result.find((e) => e.id === "coder");
    assert.ok(entry !== undefined);
    assert.strictEqual(entry.heartbeat, false);
    assert.strictEqual(typeof entry.heartbeat, "boolean");
  });
});

// ── TC-262-U-03: heartbeat_enabled=null → emits `"heartbeat": false` ───────────

describe("TC-262-U-03: heartbeat_enabled=null → emits heartbeat: false (defaults to disabled)", () => {
  const rows: AgentRow[] = [
    makeAgentRow("gem", null),
  ];
  const result = buildAgentsList(rows);

  it("gem entry has heartbeat: false when heartbeat_enabled is null", () => {
    const entry = result.find((e) => e.id === "gem");
    assert.ok(entry !== undefined);
    assert.strictEqual(entry.heartbeat, false);
  });
});

// ── TC-262-U-04: ALL agents in list have explicit heartbeat key ────────────────

describe("TC-262-U-04: ALL agents in list have explicit heartbeat key", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova", true, "5m", "discord", "channel:1234", true),
    makeAgentRow("coder", false),
    makeAgentRow("gem", null),
    makeAgentRow("scout", true, "10m", null, null),
  ];
  const result = buildAgentsList(rows);

  it("every entry has a heartbeat property", () => {
    for (const entry of result) {
      assert.ok(
        Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
        `Entry '${entry.id}' must have a heartbeat property`,
      );
    }
  });

  it("no entry has heartbeat=undefined", () => {
    for (const entry of result) {
      assert.notStrictEqual(entry.heartbeat, undefined, `Entry '${entry.id}' heartbeat must not be undefined`);
    }
  });
});

// ── TC-262-U-05: heartbeat_enabled=true with NULL sub-fields → partial object ──

describe("TC-262-U-05: heartbeat_enabled=true with NULL sub-fields → partial object", () => {
  it("only non-NULL fields are serialized into heartbeat object", () => {
    const rows: AgentRow[] = [
      makeAgentRow("coder", true, "5m", null, null),
    ];
    const result = buildAgentsList(rows);
    const entry = result.find((e) => e.id === "coder");
    assert.ok(entry !== undefined);
    assert.deepStrictEqual(entry.heartbeat, { every: "5m" });
  });

  it("all three sub-fields NULL → emit empty object {}", () => {
    const rows: AgentRow[] = [
      makeAgentRow("gem", true, null, null, null),
    ];
    const result = buildAgentsList(rows);
    const entry = result.find((e) => e.id === "gem");
    assert.ok(entry !== undefined);
    assert.deepStrictEqual(entry.heartbeat, {});
  });
});

// ── TC-262-U-06: heartbeat config does not affect agents.json sort order ───────

describe("TC-262-U-06: heartbeat config does not affect sort order", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova", true, "5m", "discord", "channel:1234", true),
    makeAgentRow("coder", false),
    makeAgentRow("gem", null),
  ];
  const result = buildAgentsList(rows);

  it("output is sorted by agent name (id)", () => {
    const ids = result.map((e) => e.id);
    const sorted = [...ids].sort();
    assert.deepStrictEqual(ids, sorted);
  });
});

// ── TC-262-U-07: heartbeat object field order is stable ────────────────────────

describe("TC-262-U-07: heartbeat object field order is stable (every, target, to)", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova", true, "5m", "discord", "channel:1234", true),
  ];
  const result = buildAgentsList(rows);
  const entry = result.find((e) => e.id === "nova");

  it("heartbeat object has keys in order: every, target, to", () => {
    assert.ok(entry !== undefined);
    assert.ok(typeof entry.heartbeat === "object", "heartbeat should be an object");
    const keys = Object.keys(entry.heartbeat as object);
    assert.deepStrictEqual(keys, ["every", "target", "to"]);
  });
});

// ── TC-262-U-08: BVA — heartbeat_every boundary values ────────────────────────

describe("TC-262-U-08: BVA — heartbeat_every boundary values", () => {
  const testValues = ["1s", "30s", "1m", "5m", "1h", "24h", "", "x".repeat(500)];

  for (const val of testValues) {
    it(`heartbeat_every="${val.length > 20 ? val.slice(0, 20) + "..." : val}" is passed through as-is`, () => {
      const rows: AgentRow[] = [makeAgentRow("coder", true, val, null, null)];
      const result = buildAgentsList(rows);
      const entry = result.find((e) => e.id === "coder");
      assert.ok(entry !== undefined);
      assert.ok(typeof entry.heartbeat === "object", "heartbeat should be an object when enabled");
      if (val !== "") {
        assert.strictEqual((entry.heartbeat as { every?: string }).every, val);
      } else {
        // Empty string: val is falsy but not null — our impl checks != null
        // Empty string should be included since it's not null
        assert.strictEqual((entry.heartbeat as { every?: string }).every, "");
      }
    });
  }
});
