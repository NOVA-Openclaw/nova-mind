/**
 * Unit tests for buildAgentsList() and syncHeartbeatFiles()
 *
 * Updated for nova-mind#707: buildAgentsList() now returns a keyed object
 * (`{ "<id>": {...} }`) matching OpenClaw 2026.9.x agents.entries schema.
 * Existing TC-244/262/269/273/660 assertions were adapted from array to object shape.
 *
 * TC-244-U-01  NOVA session — self as default, NOVA's subagents only
 * TC-244-U-02  Newhart session — self as default, Newhart's subagents only
 * TC-244-U-03  Mutual exclusion — NOVA and Newhart never see each other
 * TC-244-U-04  Fallback model shape preserved from function rows
 * TC-244-U-05  Row with is_default = null emits no `default` key
 * TC-262-U-01  heartbeat_enabled=true → emits heartbeat object
 * TC-262-U-02  heartbeat_enabled=false → heartbeat key ABSENT (updated #273)
 * TC-262-U-03  heartbeat_enabled=null → heartbeat key ABSENT (updated #273)
 * TC-262-U-04  heartbeat key present IFF enabled; absent when disabled (updated #273)
 * TC-262-U-05  heartbeat_enabled=true with NULL sub-fields → partial object
 * TC-262-U-06  heartbeat config does not affect sort order
 * TC-262-U-07  heartbeat object field order is stable
 * TC-262-U-08  BVA — heartbeat_every boundary values
 * TC-269-U-01  Heartbeat sync — default agent writes to workspace/ not workspace-nova/
 * TC-269-U-02  Heartbeat sync — subagent writes to workspace-<name>/
 * TC-269-U-03  Heartbeat sync — skip write when content unchanged
 * TC-269-U-04  Heartbeat sync — returns list of updated agent names
 * TC-269-U-05  Heartbeat sync — creates workspace dir if missing
 * TC-273-U-01  Boolean guard — no typeof heartbeat === "boolean" ever
 * TC-273-U-02  Schema compliance — objects or undefined, exhaustive partitions
 * TC-273-U-03  Mixed scenario — primary regression test for #273
 * TC-273-U-04  JSON serialization guard — no "heartbeat":false in output
 * TC-273-U-05  TypeScript type guard — heartbeat is HeartbeatConfig?
 * TC-273-U-06  Edge: empty input → empty output
 * TC-273-U-07  Edge: heartbeat_enabled field entirely absent (pre-migration row)
 * TC-273-U-08  Scenario: all agents disabled → zero heartbeat keys
 * TC-273-U-09  Scenario: all agents enabled → all have heartbeat objects
 * TC-273-U-10  BVA: partial heartbeat objects (each sub-field in isolation)
 *
 * Framework: Node built-in test runner (node:test) + tsx for TS execution.
 * Run: npx tsx --test src/sync.test.ts
 */

import { describe, it, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { buildAgentsList, resetProviderPrefixWarnings, syncHeartbeatFiles, validateAgentsEntries, writeAgentsJsonAtomically } from "./sync.js";
import type { AgentRow, HeartbeatRow, AgentEntryConfig } from "./sync.js";

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

  const { entries: result } = buildAgentsList(novaRows);

  it("nova entry has no default key", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(result["nova"], "default"),
      "default key must not be emitted under ownership=explicit",
    );
  });

  it("coder entry has no default key", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(result["coder"], "default"),
      "default key must not be emitted under ownership=explicit",
    );
  });

  it("gem entry has no default key", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(result["gem"], "default"),
      "default key must not be emitted under ownership=explicit",
    );
  });

  it("scout entry has no default key", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(result["scout"], "default"),
      "default key must not be emitted under ownership=explicit",
    );
  });

  it("all four agents are present", () => {
    assert.deepStrictEqual(
      Object.keys(result).sort(),
      ["coder", "gem", "nova", "scout"],
    );
  });

  it("nova's allowAgents are sorted", () => {
    assert.deepStrictEqual(
      result["nova"]?.subagents?.allowAgents,
      ["coder", "gem", "scout"],
    );
  });

  it("thinkingDefault is emitted for agents with a valid thinking value", () => {
    const novaEntry = result["nova"];
    const coderEntry = result["coder"];
    assert.ok(novaEntry !== undefined);
    assert.ok(coderEntry !== undefined);
    assert.strictEqual(novaEntry.thinkingDefault, "high");
    assert.strictEqual(coderEntry.thinkingDefault, "medium");
  });

  it("thinkingDefault is omitted for agents with thinking = null", () => {
    for (const [id, entry] of Object.entries(result)) {
      if (id === "gem" || id === "scout") {
        assert.ok(
          !Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
          `Entry '${id}' should not have a thinkingDefault property`,
        );
      }
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

  const { entries: result } = buildAgentsList(newhartRows);

  it("newhart entry has no default key", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(result["newhart"], "default"),
      "default key must not be emitted under ownership=explicit",
    );
  });

  it("coder entry has no default key", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(result["coder"], "default"),
      "default key must not be emitted under ownership=explicit",
    );
  });

  it("gem is NOT present (not a Newhart subagent)", () => {
    assert.strictEqual(result["gem"], undefined);
  });

  it("nova is NOT present", () => {
    assert.strictEqual(result["nova"], undefined);
  });

  it("exactly three agents are present: newhart, coder, scout", () => {
    assert.deepStrictEqual(
      Object.keys(result).sort(),
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

  const { entries: novaResult } = buildAgentsList(novaRows);
  const { entries: newhartResult } = buildAgentsList(newhartRows);

  it("nova's agent list does not include newhart", () => {
    assert.strictEqual(
      novaResult["newhart"],
      undefined,
    );
  });

  it("newhart's agent list does not include nova", () => {
    assert.strictEqual(
      newhartResult["nova"],
      undefined,
    );
  });

  it("no list contains any entry with a default key", () => {
    const novaDefaults = Object.values(novaResult).filter((e) =>
      Object.prototype.hasOwnProperty.call(e, "default"),
    );
    const newhartDefaults = Object.values(newhartResult).filter((e) =>
      Object.prototype.hasOwnProperty.call(e, "default"),
    );
    assert.strictEqual(novaDefaults.length, 0);
    assert.strictEqual(newhartDefaults.length, 0);
  });

  it("nova entry has no default key in NOVA's list", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(novaResult["nova"], "default"),
      "default key must not be emitted under ownership=explicit",
    );
  });

  it("newhart entry has no default key in Newhart's list", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(newhartResult["newhart"], "default"),
      "default key must not be emitted under ownership=explicit",
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

  const { entries: result } = buildAgentsList(rows);

  it("coder model is object form with primary and fallbacks", () => {
    assert.deepStrictEqual(result["coder"]?.model, {
      primary: "anthropic/claude-sonnet-4",
      fallbacks: ["openai/gpt-4o", "google/gemini-pro"],
    });
  });

  it("fallback order is preserved from DB array", () => {
    const model = result["coder"]?.model;
    assert.ok(typeof model === "object" && "fallbacks" in model);
    assert.deepStrictEqual(model.fallbacks, ["openai/gpt-4o", "google/gemini-pro"]);
  });

  it("gem with null fallback_models uses string model form", () => {
    assert.strictEqual(result["gem"]?.model, "google/gemini-flash");
  });

  it("scout with empty fallback_models array uses string model form", () => {
    assert.strictEqual(
      result["scout"]?.model,
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

  const { entries: result } = buildAgentsList(rows);

  it("is_default = null → no default key on entry", () => {
    const entry = result["someagent"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "default"),
      "default key must not be present when is_default is null",
    );
  });

  it("is_default = false → no default key on entry", () => {
    const entry = result["falseagent"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "default"),
      "default key must not be present when is_default is false",
    );
  });

  it("is_default = true also emits no default key", () => {
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
    const { entries: trueResult } = buildAgentsList(trueRow);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(trueResult["trueagent"], "default"),
      "default key must not be emitted even when is_default is true",
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
  const { entries: result } = buildAgentsList(rows);

  it("nova entry has heartbeat object with all four fields", () => {
    const entry = result["nova"];
    assert.ok(entry !== undefined);
    assert.deepStrictEqual(entry.heartbeat, {
      every: "5m",
      target: "discord",
      to: "channel:1234",
    });
  });

  it("heartbeat key is present (not missing)", () => {
    const entry = result["nova"];
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"));
  });
});

// ── TC-262-U-02: heartbeat_enabled=false → heartbeat key is ABSENT ──────────

describe("TC-262-U-02: heartbeat_enabled=false → heartbeat key is ABSENT from entry", () => {
  const rows: AgentRow[] = [
    makeAgentRow("coder", false),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("coder entry has heartbeat: undefined (key absent)", () => {
    const entry = result["coder"];
    assert.ok(entry !== undefined);
    assert.strictEqual(entry.heartbeat, undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
      "heartbeat key must not be present when disabled",
    );
    assert.ok(typeof entry.heartbeat !== "boolean", "heartbeat must never be a boolean");
  });
});

// ── TC-262-U-03: heartbeat_enabled=null → heartbeat key is ABSENT ───────────

describe("TC-262-U-03: heartbeat_enabled=null → heartbeat key is ABSENT from entry", () => {
  const rows: AgentRow[] = [
    makeAgentRow("gem", null),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("gem entry has heartbeat: undefined (key absent) when heartbeat_enabled is null", () => {
    const entry = result["gem"];
    assert.ok(entry !== undefined);
    assert.strictEqual(entry.heartbeat, undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
      "heartbeat key must not be present when heartbeat_enabled is null",
    );
    assert.ok(typeof entry.heartbeat !== "boolean", "heartbeat must never be a boolean");
  });
});

// ── TC-262-U-04: heartbeat key present IFF enabled; absent when disabled or null ──

describe("TC-262-U-04: heartbeat key present IFF enabled; absent when disabled or null", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova", true, "5m", "discord", "channel:1234", true),
    makeAgentRow("coder", false),
    makeAgentRow("gem", null),
    makeAgentRow("scout", true, "10m", null, null),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("nova entry (enabled) has a heartbeat property", () => {
    const entry = result["nova"];
    assert.ok(entry !== undefined);
    assert.ok(
      Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
      "nova: enabled agent must have heartbeat property",
    );
    assert.ok(typeof entry.heartbeat === "object", "nova: heartbeat must be an object (not boolean)");
  });

  it("scout entry (enabled) has a heartbeat property", () => {
    const entry = result["scout"];
    assert.ok(entry !== undefined);
    assert.ok(
      Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
      "scout: enabled agent must have heartbeat property",
    );
    assert.ok(typeof entry.heartbeat === "object", "scout: heartbeat must be an object (not boolean)");
  });

  it("coder entry (disabled) has heartbeat key ABSENT", () => {
    const entry = result["coder"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
      "coder: disabled agent must NOT have heartbeat property",
    );
    assert.strictEqual(entry.heartbeat, undefined);
  });

  it("gem entry (null) has heartbeat key ABSENT", () => {
    const entry = result["gem"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
      "gem: null-disabled agent must NOT have heartbeat property",
    );
    assert.strictEqual(entry.heartbeat, undefined);
  });
});

// ── TC-262-U-05: heartbeat_enabled=true with NULL sub-fields → partial object ──

describe("TC-262-U-05: heartbeat_enabled=true with NULL sub-fields → partial object", () => {
  it("only non-NULL fields are serialized into heartbeat object", () => {
    const rows: AgentRow[] = [
      makeAgentRow("coder", true, "5m", null, null),
    ];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["coder"];
    assert.ok(entry !== undefined);
    assert.deepStrictEqual(entry.heartbeat, { every: "5m" });
  });

  it("all three sub-fields NULL → emit empty object {}", () => {
    const rows: AgentRow[] = [
      makeAgentRow("gem", true, null, null, null),
    ];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["gem"];
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
  const { entries: result } = buildAgentsList(rows);

  it("output is sorted by agent name (id)", () => {
    const ids = Object.keys(result);
    const sorted = [...ids].sort();
    assert.deepStrictEqual(ids, sorted);
  });
});

// ── TC-262-U-07: heartbeat object field order is stable ────────────────────────

describe("TC-262-U-07: heartbeat object field order is stable (every, target, to)", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova", true, "5m", "discord", "channel:1234", true),
  ];
  const { entries: result } = buildAgentsList(rows);
  const entry = result["nova"];

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
      const { entries: result } = buildAgentsList(rows);
      const entry = result["coder"];
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

// ─────────────────────────────────────────────────────────────────────────────
// TC-273-U-01 through TC-273-U-10: Heartbeat schema fix tests (#273)
// ─────────────────────────────────────────────────────────────────────────────

// ── TC-273-U-01: Boolean guard — no agent entry ever has typeof heartbeat === "boolean" ──

describe("TC-273-U-01: Boolean guard — no agent entry ever has typeof heartbeat === \"boolean\"", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova",  true,  "5m", "discord", "channel:1234", true),
    makeAgentRow("coder", false),
    makeAgentRow("gem",   null),
    {
      name: "iris",
      model: "anthropic/claude-sonnet-4",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
      // heartbeat_enabled field entirely absent (undefined)
    },
  ];
  const { entries: result } = buildAgentsList(rows);

  it("returns 4 entries", () => {
    assert.strictEqual(Object.keys(result).length, 4);
  });

  it("no entry has typeof heartbeat === \"boolean\"", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        typeof entry.heartbeat !== "boolean",
        `Entry '${id}' must not have a boolean heartbeat (got ${typeof entry.heartbeat})`,
      );
    }
  });

  it("no entry has heartbeat === false", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.notStrictEqual(entry.heartbeat, false, `Entry '${id}' heartbeat must not be false`);
    }
  });

  it("no entry has heartbeat === true", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.notStrictEqual(entry.heartbeat, true, `Entry '${id}' heartbeat must not be true`);
    }
  });
});

// ── TC-273-U-02: Schema compliance — heartbeat values are objects or undefined ──

describe("TC-273-U-02: Schema compliance — heartbeat values are objects or undefined, never false/null/true", () => {
  const rows: AgentRow[] = [
    makeAgentRow("agent-enabled",  true,  "5m", "discord", "ch:123"),
    makeAgentRow("agent-partial",  true,  "1m", null, null),
    makeAgentRow("agent-min",      true,  null, null, null),
    makeAgentRow("agent-false",    false),
    makeAgentRow("agent-null",     null),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("agent-enabled: heartbeat key present, value is object with all sub-fields", () => {
    const entry = result["agent-enabled"];
    assert.ok(entry !== undefined);
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "agent-enabled must have heartbeat key");
    assert.ok(typeof entry.heartbeat === "object" && entry.heartbeat !== null, "heartbeat must be object");
    assert.deepStrictEqual(entry.heartbeat, { every: "5m", target: "discord", to: "ch:123" });
  });

  it("agent-partial: heartbeat key present, value is object with only 'every' field", () => {
    const entry = result["agent-partial"];
    assert.ok(entry !== undefined);
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "agent-partial must have heartbeat key");
    assert.ok(typeof entry.heartbeat === "object" && entry.heartbeat !== null, "heartbeat must be object");
    assert.deepStrictEqual(entry.heartbeat, { every: "1m" });
  });

  it("agent-min: heartbeat key present, value is empty object {}", () => {
    const entry = result["agent-min"];
    assert.ok(entry !== undefined);
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "agent-min must have heartbeat key");
    assert.deepStrictEqual(entry.heartbeat, {});
  });

  it("agent-false: heartbeat key ABSENT, value is undefined", () => {
    const entry = result["agent-false"];
    assert.ok(entry !== undefined);
    assert.ok(!Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "agent-false must NOT have heartbeat key");
    assert.strictEqual(entry.heartbeat, undefined);
  });

  it("agent-null: heartbeat key ABSENT, value is undefined", () => {
    const entry = result["agent-null"];
    assert.ok(entry !== undefined);
    assert.ok(!Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "agent-null must NOT have heartbeat key");
    assert.strictEqual(entry.heartbeat, undefined);
  });
});

// ── TC-273-U-03: Mixed scenario — enabled agents get objects, disabled/null omit key ──

describe("TC-273-U-03: Mixed scenario — primary regression test for #273", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova",  true,  "5m",  "discord", "channel:1234", true),
    makeAgentRow("coder", true,  "10m", "slack",   "channel:5678"),
    makeAgentRow("gem",   false),
    makeAgentRow("scout", null),
    makeAgentRow("iris",  true,  null,  null,      null),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("nova: heartbeat present with correct value", () => {
    const entry = result["nova"];
    assert.ok(entry !== undefined);
    assert.deepStrictEqual(entry.heartbeat, { every: "5m", target: "discord", to: "channel:1234" });
  });

  it("coder: heartbeat present with correct value", () => {
    const entry = result["coder"];
    assert.ok(entry !== undefined);
    assert.deepStrictEqual(entry.heartbeat, { every: "10m", target: "slack", to: "channel:5678" });
  });

  it("gem: heartbeat key ABSENT", () => {
    const entry = result["gem"];
    assert.ok(entry !== undefined);
    assert.ok(!Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "gem must not have heartbeat key");
    assert.strictEqual(entry.heartbeat, undefined);
  });

  it("scout: heartbeat key ABSENT", () => {
    const entry = result["scout"];
    assert.ok(entry !== undefined);
    assert.ok(!Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "scout must not have heartbeat key");
    assert.strictEqual(entry.heartbeat, undefined);
  });

  it("iris: heartbeat present with empty object (enabled, no sub-fields)", () => {
    const entry = result["iris"];
    assert.ok(entry !== undefined);
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "iris must have heartbeat key");
    assert.deepStrictEqual(entry.heartbeat, {});
  });

  it("all enabled agents have object heartbeat (never boolean)", () => {
    for (const id of ["nova", "coder", "iris"]) {
      const entry = result[id];
      assert.ok(entry !== undefined);
      assert.ok(typeof entry.heartbeat === "object" && entry.heartbeat !== null,
        `${id}: heartbeat must be an object`);
    }
  });

  it("all disabled agents have heartbeat === undefined", () => {
    for (const id of ["gem", "scout"]) {
      const entry = result[id];
      assert.ok(entry !== undefined);
      assert.strictEqual(entry.heartbeat, undefined, `${id}: heartbeat must be undefined`);
    }
  });

  it("count of entries with heartbeat key is 3 (nova, coder, iris)", () => {
    const withHeartbeat = Object.values(result).filter((e) => Object.prototype.hasOwnProperty.call(e, "heartbeat"));
    assert.strictEqual(withHeartbeat.length, 3);
  });

  it("count of entries without heartbeat key is 2 (gem, scout)", () => {
    const withoutHeartbeat = Object.values(result).filter((e) => !Object.prototype.hasOwnProperty.call(e, "heartbeat"));
    assert.strictEqual(withoutHeartbeat.length, 2);
  });
});

// ── TC-273-U-04: JSON serialization guard — output never contains "heartbeat":false ──

describe("TC-273-U-04: JSON serialization guard — JSON output never contains \"heartbeat\":false", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova",  true,  "5m", "discord", "channel:1234", true),
    makeAgentRow("coder", false),
    makeAgentRow("gem",   null),
  ];
  const { entries: result } = buildAgentsList(rows);
  const jsonStr = JSON.stringify(result);

  it("JSON output does not contain '\"heartbeat\":false'", () => {
    assert.ok(!jsonStr.includes('"heartbeat":false'), `JSON must not contain "heartbeat":false`);
  });

  it("JSON output does not contain '\"heartbeat\": false'", () => {
    assert.ok(!jsonStr.includes('"heartbeat": false'), `JSON must not contain "heartbeat": false`);
  });

  it("JSON output contains exactly one 'heartbeat' key (nova's enabled entry)", () => {
    const matches = jsonStr.match(/"heartbeat"/g) || [];
    assert.strictEqual(matches.length, 1, `Expected exactly 1 heartbeat key in JSON, got ${matches.length}`);
  });

  it("the heartbeat key in JSON is followed by '{' (an object), not 'false'", () => {
    const hbIdx = jsonStr.indexOf('"heartbeat"');
    assert.ok(hbIdx !== -1, "heartbeat key must exist in JSON");
    // Find the character after the colon
    const afterColon = jsonStr.slice(hbIdx + '"heartbeat":'.length).trimStart();
    assert.ok(
      afterColon.startsWith("{"),
      `heartbeat value in JSON must start with '{', got: ${afterColon.slice(0, 10)}`,
    );
  });
});

// ── TC-273-U-05: TypeScript type guard — heartbeat is HeartbeatConfig | undefined ──

describe("TC-273-U-05: TypeScript type guard — heartbeat is HeartbeatConfig | undefined, not | false", () => {
  const rows: AgentRow[] = [
    makeAgentRow("coder", false),
    makeAgentRow("gem",   null),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("coder: heartbeat is undefined, not false", () => {
    const entry = result["coder"];
    assert.ok(entry !== undefined);
    assert.strictEqual(entry.heartbeat, undefined);
    assert.ok(typeof entry.heartbeat !== "boolean", "heartbeat must not be the boolean false");
  });

  it("gem: heartbeat is undefined, not false", () => {
    const entry = result["gem"];
    assert.ok(entry !== undefined);
    assert.strictEqual(entry.heartbeat, undefined);
    assert.ok(typeof entry.heartbeat !== "boolean", "heartbeat must not be the boolean false");
  });

  it("no disabled agent's heartbeat is strictly false (boolean)", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(typeof entry.heartbeat !== "boolean", `Entry '${id}' must not have heartbeat === false`);
    }
  });
});

// ── TC-273-U-06: Edge case — empty rows input produces empty output ────────────

describe("TC-273-U-06: Edge case — empty rows input produces empty output", () => {
  it("buildAgentsList([]) returns an empty array", () => {
    const { entries: result } = buildAgentsList([]);
    assert.ok(typeof result === "object" && result !== null && !Array.isArray(result), "result must be an object");
    assert.strictEqual(Object.keys(result).length, 0);
  });
});

// ── TC-273-U-07: Edge case — heartbeat_enabled field entirely absent (undefined) ──

describe("TC-273-U-07: Edge case — heartbeat_enabled field entirely absent (pre-migration row)", () => {
  const row: AgentRow = {
    name: "legacy-agent",
    model: "anthropic/claude-sonnet-4",
    fallback_models: null,
    thinking: null,
    instance_type: "subagent",
    is_default: false,
    allowed_subagents: null,
    // heartbeat_enabled, heartbeat_every, etc. all absent (undefined)
  };
  const { entries: result } = buildAgentsList([row]);

  it("returns 1 entry", () => {
    assert.strictEqual(Object.keys(result).length, 1);
  });

  it("entry id is 'legacy-agent'", () => {
    assert.strictEqual(Object.keys(result)[0], "legacy-agent");
  });

  it("heartbeat key is ABSENT from legacy-agent entry", () => {
    assert.ok(
      !Object.prototype.hasOwnProperty.call(Object.values(result)[0], "heartbeat"),
      "heartbeat key must not be present for pre-migration row",
    );
  });

  it("legacy-agent heartbeat is undefined", () => {
    assert.strictEqual(Object.values(result)[0]!.heartbeat, undefined);
  });

  it("typeof legacy-agent heartbeat is not boolean", () => {
    assert.ok(typeof Object.values(result)[0]!.heartbeat !== "boolean", "heartbeat must never be a boolean");
  });
});

// ── TC-273-U-08: All-disabled scenario — zero agents have heartbeat key ─────────

describe("TC-273-U-08: All-disabled scenario — zero agents have heartbeat key", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova",   false, null, null, null, true),
    makeAgentRow("coder",  false),
    makeAgentRow("gem",    null),
    makeAgentRow("scout",  null),
    makeAgentRow("iris",   false),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("returns 5 entries", () => {
    assert.strictEqual(Object.keys(result).length, 5);
  });

  it("not a single entry has a heartbeat property", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        !Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
        `Entry '${id}' must NOT have a heartbeat property`,
      );
    }
  });

  it("every entry has heartbeat === undefined", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.strictEqual(entry.heartbeat, undefined, `Entry '${id}' heartbeat must be undefined`);
    }
  });

  it("JSON.stringify output does not contain 'heartbeat' at all", () => {
    const jsonStr = JSON.stringify(result);
    assert.ok(!jsonStr.includes('"heartbeat"'), "serialized JSON must not contain any heartbeat key");
  });
});

// ── TC-273-U-09: All-enabled scenario — every agent has heartbeat object ─────────

describe("TC-273-U-09: All-enabled scenario — every agent has heartbeat object", () => {
  const rows: AgentRow[] = [
    makeAgentRow("nova",  true, "5m",  "discord", "ch:1", true),
    makeAgentRow("coder", true, "10m", "slack",   "ch:2"),
    makeAgentRow("gem",   true, null,  null,      null),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("returns 3 entries", () => {
    assert.strictEqual(Object.keys(result).length, 3);
  });

  it("every entry has a heartbeat property", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        Object.prototype.hasOwnProperty.call(entry, "heartbeat"),
        `Entry '${id}' must have a heartbeat property`,
      );
    }
  });

  it("every entry heartbeat is typeof 'object'", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        typeof entry.heartbeat === "object",
        `Entry '${id}' heartbeat must be an object`,
      );
    }
  });

  it("no entry heartbeat is null", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(entry.heartbeat !== null, `Entry '${id}' heartbeat must not be null`);
    }
  });

  it("no entry heartbeat is a boolean (false or true)", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(typeof entry.heartbeat !== "boolean", `Entry '${id}' heartbeat must not be false`);
      assert.ok(typeof entry.heartbeat !== "boolean", `Entry '${id}' heartbeat must not be true`);
    }
  });
});

// ── TC-273-U-10: BVA — partial heartbeat objects (each sub-field in isolation) ──

describe("TC-273-U-10: BVA — partial heartbeat objects (each sub-field in isolation)", () => {
  it("Sub-test A: only 'every' set → heartbeat = {every: '5m'}", () => {
    const rows: AgentRow[] = [makeAgentRow("a1", true, "5m", null, null)];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["a1"];
    assert.ok(entry !== undefined);
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "a1 must have heartbeat key");
    assert.deepStrictEqual(entry.heartbeat, { every: "5m" });
    // 'target' and 'to' must not be present in the object
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry.heartbeat, "target"),
      "heartbeat must not have 'target' key when null",
    );
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry.heartbeat, "to"),
      "heartbeat must not have 'to' key when null",
    );
  });

  it("Sub-test B: only 'target' set → heartbeat = {target: 'discord'}", () => {
    const rows: AgentRow[] = [makeAgentRow("a2", true, null, "discord", null)];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["a2"];
    assert.ok(entry !== undefined);
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "a2 must have heartbeat key");
    assert.deepStrictEqual(entry.heartbeat, { target: "discord" });
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry.heartbeat, "every"),
      "heartbeat must not have 'every' key when null",
    );
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry.heartbeat, "to"),
      "heartbeat must not have 'to' key when null",
    );
  });

  it("Sub-test C: only 'to' set → heartbeat = {to: 'channel:1234'}", () => {
    const rows: AgentRow[] = [makeAgentRow("a3", true, null, null, "channel:1234")];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["a3"];
    assert.ok(entry !== undefined);
    assert.ok(Object.prototype.hasOwnProperty.call(entry, "heartbeat"), "a3 must have heartbeat key");
    assert.deepStrictEqual(entry.heartbeat, { to: "channel:1234" });
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry.heartbeat, "every"),
      "heartbeat must not have 'every' key when null",
    );
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry.heartbeat, "target"),
      "heartbeat must not have 'target' key when null",
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// TC-714-U-01..04: Per-agent isolatedSession propagation and pre-088 tolerance
// ─────────────────────────────────────────────────────────────────────────────

function makeAgentRowWithHeartbeat(
  name: string,
  heartbeatEnabled: boolean,
  extras?: Partial<AgentRow>,
): AgentRow {
  return {
    name,
    model: "anthropic/claude-sonnet-4",
    fallback_models: null,
    thinking: null,
    instance_type: "subagent",
    is_default: false,
    allowed_subagents: null,
    heartbeat_enabled: heartbeatEnabled,
    heartbeat_every: "30m",
    heartbeat_target: "discord",
    heartbeat_to: "channel:1504054635231445112",
    ...extras,
  };
}

describe("TC-714-U-01: heartbeat_isolated_session=true → isolatedSession: true", () => {
  const rows: AgentRow[] = [
    makeAgentRowWithHeartbeat("nova", true, { heartbeat_isolated_session: true }),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("emits isolatedSession: true", () => {
    assert.strictEqual(result["nova"]?.heartbeat?.isolatedSession, true);
  });
});

describe("TC-714-U-02: heartbeat_isolated_session=false → isolatedSession: false", () => {
  const rows: AgentRow[] = [
    makeAgentRowWithHeartbeat("nova", true, { heartbeat_isolated_session: false }),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("emits isolatedSession: false", () => {
    assert.strictEqual(result["nova"]?.heartbeat?.isolatedSession, false);
  });
});

describe("TC-714-U-03: heartbeat_isolated_session=null → isolatedSession omitted", () => {
  const rows: AgentRow[] = [
    makeAgentRowWithHeartbeat("nova", true, { heartbeat_isolated_session: null }),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("omits isolatedSession key", () => {
    const hb = result["nova"]?.heartbeat;
    assert.ok(hb !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(hb, "isolatedSession"),
      "isolatedSession must be absent when the DB row is null",
    );
  });
});

describe("TC-714-U-04: fetchAgentRows tolerates missing heartbeat_isolated_session column (pre-088)", () => {
  it("falls back to the query without the column when information_schema reports it missing", async () => {
    let executedQuery = "";
    const mockClient = {
      query: async (sql: string | { text: string }) => {
        const sqlText = typeof sql === "string" ? sql : sql.text;
        if (sqlText.includes("information_schema.columns")) {
          return { rows: [{ exists: false }] };
        }
        executedQuery = sqlText;
        return { rows: [] };
      },
    } as unknown as import("pg").Client;

    const rows = await (async () => {
      const { fetchAgentRows } = await import("./sync.js");
      return fetchAgentRows(mockClient);
    })();

    assert.strictEqual(rows.length, 0);
    assert.ok(
      !executedQuery.includes("heartbeat_isolated_session"),
      "fallback query must not reference heartbeat_isolated_session",
    );
    assert.ok(
      executedQuery.includes("FROM get_agent_export_rows()"),
      "fallback query must still use role-scoped function",
    );
  });

  it("uses the full query when the column exists", async () => {
    let executedQuery = "";
    const mockClient = {
      query: async (sql: string | { text: string }) => {
        const sqlText = typeof sql === "string" ? sql : sql.text;
        if (sqlText.includes("information_schema.columns")) {
          return { rows: [{ exists: true }] };
        }
        executedQuery = sqlText;
        return { rows: [] };
      },
    } as unknown as import("pg").Client;

    const rows = await (async () => {
      const { fetchAgentRows } = await import("./sync.js");
      return fetchAgentRows(mockClient);
    })();

    assert.strictEqual(rows.length, 0);
    assert.ok(
      executedQuery.includes("heartbeat_isolated_session"),
      "full query must select heartbeat_isolated_session",
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// TC-660-U-01..18: thinking → thinkingDefault mapping (#660)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Helper to build a minimal AgentRow with a configurable thinking value.
 */
function makeThinkingRow(
  name: string,
  thinking: string | null | undefined,
  extras?: Partial<AgentRow>,
): AgentRow {
  return {
    name,
    model: "anthropic/claude-sonnet-4",
    fallback_models: null,
    thinking: thinking as string | null,
    instance_type: "subagent",
    is_default: false,
    allowed_subagents: null,
    ...extras,
  };
}

// ── TC-660-U-01: Regression guard — non-default `off` maps through ───────────

describe("TC-660-U-01: Regression guard — thinking='off' maps to thinkingDefault='off'", () => {
  const rows: AgentRow[] = [makeThinkingRow("bastion", "off")];
  const { entries: result } = buildAgentsList(rows);

  it("emits thinkingDefault: 'off'", () => {
    const entry = result["bastion"];
    assert.ok(entry !== undefined);
    assert.ok(
      Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
      "entry must have own thinkingDefault property",
    );
    assert.strictEqual(entry.thinkingDefault, "off");
  });
});

// ── TC-660-U-02: Non-default `high` maps through ─────────────────────────────

describe("TC-660-U-02: thinking='high' maps to thinkingDefault='high'", () => {
  const rows: AgentRow[] = [makeThinkingRow("newhart", "high")];
  const { entries: result } = buildAgentsList(rows);

  it("emits thinkingDefault: 'high' even when it matches a typical global default", () => {
    const entry = result["newhart"];
    assert.ok(entry !== undefined);
    assert.strictEqual(entry.thinkingDefault, "high");
  });
});

// ── TC-660-U-03: All 7 DB-legal values map 1:1 ───────────────────────────────

describe("TC-660-U-03: All 7 DB-legal thinking values map 1:1", () => {
  const values = ["off", "minimal", "low", "medium", "high", "xhigh", "adaptive"] as const;

  for (const value of values) {
    it(`thinking='${value}' → thinkingDefault='${value}'`, () => {
      const rows: AgentRow[] = [makeThinkingRow(`agent-${value}`, value)];
      const { entries: result } = buildAgentsList(rows);
      const entry = result[`agent-${value}`];
      assert.ok(entry !== undefined);
      assert.strictEqual(entry.thinkingDefault, value);
    });
  }
});

// ── TC-660-U-04: Existing fields unaffected by the fix ───────────────────────

describe("TC-660-U-04: Existing fields unaffected by thinkingDefault mapping", () => {
  const rowWithThinking: AgentRow = {
    name: "combo",
    model: "anthropic/claude-opus-4",
    fallback_models: ["openai/gpt-4o", "google/gemini-pro"],
    thinking: "low",
    instance_type: "subagent",
    is_default: true,
    allowed_subagents: ["gem", "coder"],
    heartbeat_enabled: true,
    heartbeat_every: "5m",
    heartbeat_target: "discord",
    heartbeat_to: "channel:1234",
  };
  const rowWithoutThinking: AgentRow = { ...rowWithThinking, thinking: null };

  const { entries: resultWith } = buildAgentsList([rowWithThinking]);
  const { entries: resultWithout } = buildAgentsList([rowWithoutThinking]);

  it("only difference is the added thinkingDefault key", () => {
    assert.strictEqual(Object.keys(resultWith).length, 1);
    assert.strictEqual(Object.keys(resultWithout).length, 1);

    const withEntry = Object.values(resultWith)[0];
    const withoutEntry = Object.values(resultWithout)[0];

    assert.strictEqual(withEntry.thinkingDefault, "low");
    assert.ok(
      !Object.prototype.hasOwnProperty.call(withoutEntry, "thinkingDefault"),
    );

    // Compare every other key
    const { thinkingDefault: _, ...withRest } = withEntry;
    assert.deepStrictEqual(withRest, withoutEntry);
  });
});

// ── TC-660-U-05..06: Null / empty string → omitted ───────────────────────────

describe("TC-660-U-05..06: Null and empty string thinking values are omitted", () => {
  it("TC-660-U-05: thinking = null → key omitted", () => {
    const rows: AgentRow[] = [makeThinkingRow("nullagent", null)];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["nullagent"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
      "thinkingDefault must be absent when thinking is null",
    );
    assert.strictEqual(entry.thinkingDefault, undefined);
  });

  it("TC-660-U-06: thinking = '' → key omitted", () => {
    const rows: AgentRow[] = [makeThinkingRow("emptyagent", "")];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["emptyagent"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
      "thinkingDefault must be absent when thinking is empty string",
    );
  });
});

// ── TC-660-U-07: Schema-valid but DB-illegal values (`max`, `ultra`) pass through
describe("TC-660-U-07: Schema-valid but DB-illegal values 'max' and 'ultra' pass through", () => {
  it("thinking='max' → thinkingDefault='max'", () => {
    const rows: AgentRow[] = [makeThinkingRow("maxagent", "max")];
    const { entries: result } = buildAgentsList(rows);
    assert.strictEqual(Object.values(result)[0]?.thinkingDefault, "max");
  });

  it("thinking='ultra' → thinkingDefault='ultra'", () => {
    const rows: AgentRow[] = [makeThinkingRow("ultraagent", "ultra")];
    const { entries: result } = buildAgentsList(rows);
    assert.strictEqual(Object.values(result)[0]?.thinkingDefault, "ultra");
  });
});

// ── TC-660-U-08: Genuinely unknown tier → omitted, no crash ──────────────────

describe("TC-660-U-08: Unknown thinking tier is omitted without crashing", () => {
  const rows: AgentRow[] = [
    makeThinkingRow("good", "low"),
    makeThinkingRow("bad", "notarealvalue"),
    makeThinkingRow("good2", "medium"),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("omits thinkingDefault for the unknown value", () => {
    const badEntry = result["bad"];
    assert.ok(badEntry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(badEntry, "thinkingDefault"),
    );
  });

  it("still emits thinkingDefault for valid sibling rows", () => {
    assert.strictEqual(result["good"]?.thinkingDefault, "low");
    assert.strictEqual(result["good2"]?.thinkingDefault, "medium");
  });
});

// ── TC-660-U-09..10: Wrong JS type → omitted, no throw ───────────────────────

describe("TC-660-U-09..10: Wrong-type thinking values are omitted without throwing", () => {
  it("TC-660-U-09: thinking is a number → omitted", () => {
    const rows: AgentRow[] = [
      makeThinkingRow("numagent", 5 as unknown as string),
    ];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["numagent"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
    );
  });

  it("TC-660-U-10: thinking is a boolean → omitted", () => {
    const rows: AgentRow[] = [
      makeThinkingRow("boolagent", true as unknown as string),
    ];
    const { entries: result } = buildAgentsList(rows);
    const entry = result["boolagent"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
    );
  });
});

// ── TC-660-U-11: Mixed-case values are strict-rejected ───────────────────────

describe("TC-660-U-11: Mixed-case thinking values are omitted (strict membership)", () => {
  const rows: AgentRow[] = [
    makeThinkingRow("h1", "High"),
    makeThinkingRow("h2", "OFF"),
    makeThinkingRow("h3", "AdAptive"),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("omits thinkingDefault for every mixed-case variant", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        !Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
        `Entry '${id}' must not have thinkingDefault for mixed-case input`,
      );
    }
  });
});

// ── TC-660-U-12: Whitespace-padded values are strict-rejected ────────────────

describe("TC-660-U-12: Whitespace-padded thinking values are omitted (strict membership)", () => {
  const rows: AgentRow[] = [
    makeThinkingRow("w1", " off"),
    makeThinkingRow("w2", "high "),
    makeThinkingRow("w3", " low "),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("omits thinkingDefault for every whitespace-padded variant", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        !Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
        `Entry '${id}' must not have thinkingDefault for whitespace-padded input`,
      );
    }
  });
});

// ── TC-660-U-13: Empty agent list ────────────────────────────────────────────

describe("TC-660-U-13: Empty agent list", () => {
  it("returns an empty array", () => {
    const { entries: result } = buildAgentsList([]);
    assert.deepStrictEqual(result, {});
  });
});

// ── TC-660-U-14: Single agent with thinking set ──────────────────────────────

describe("TC-660-U-14: Single agent with thinking set", () => {
  const rows: AgentRow[] = [makeThinkingRow("solo", "medium")];
  const { entries: result } = buildAgentsList(rows);

  it("returns one entry with thinkingDefault matching the input", () => {
    assert.strictEqual(Object.keys(result).length, 1);
    assert.strictEqual(Object.keys(result)[0], "solo");
    assert.strictEqual(Object.values(result)[0]?.thinkingDefault, "medium");
  });
});

// ── TC-660-U-15: Large fleet with mixed thinking values ──────────────────────

describe("TC-660-U-15: Large fleet with mixed thinking values", () => {
  const values = ["off", "minimal", "low", "medium", "high", "xhigh", "adaptive"];
  const rows: AgentRow[] = [];
  for (let i = 0; i < 30; i++) {
    rows.push(
      makeThinkingRow(
        `agent-${String(i).padStart(2, "0")}`,
        i % 6 === 0 ? null : values[i % values.length],
      ),
    );
  }
  const { entries: result } = buildAgentsList(rows);

  it("emits thinkingDefault for exactly the 25 non-null rows", () => {
    const withKey = Object.values(result).filter((e) =>
      Object.prototype.hasOwnProperty.call(e, "thinkingDefault"),
    );
    assert.strictEqual(withKey.length, 25);
  });

  it("omits thinkingDefault for exactly the 5 null rows", () => {
    const withoutKey = Object.values(result).filter(
      (e) => !Object.prototype.hasOwnProperty.call(e, "thinkingDefault"),
    );
    assert.strictEqual(withoutKey.length, 5);
  });

  it("sort order is unaffected by the new field", () => {
    const ids = Object.keys(result);
    assert.deepStrictEqual(ids, [...ids].sort((a, b) => a.localeCompare(b)));
  });

  it("spot-checks preserve correct per-row values", () => {
    assert.strictEqual(result["agent-01"]?.thinkingDefault, "minimal");
    assert.strictEqual(result["agent-07"]?.thinkingDefault, "off");
    assert.strictEqual(result["agent-11"]?.thinkingDefault, "high");
  });
});

// ── TC-660-U-16: `thinking` property absent from row object ──────────────────

describe("TC-660-U-16: thinking property absent from row object", () => {
  it("omits thinkingDefault when the property is missing", () => {
    const row = {
      name: "legacy",
      model: "anthropic/claude-sonnet-4",
      fallback_models: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
    } as unknown as AgentRow;
    const { entries: result } = buildAgentsList([row]);
    const entry = result["legacy"];
    assert.ok(entry !== undefined);
    assert.ok(
      !Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
    );
  });
});

// ── TC-660-U-17: Explicit value equal to hypothetical global default is emitted
describe("TC-660-U-17: Explicit value equal to a hypothetical global default is still emitted", () => {
  const rows: AgentRow[] = [makeThinkingRow("explicit-high", "high")];
  const { entries: result } = buildAgentsList(rows);

  it("emits explicit thinkingDefault: 'high'", () => {
    const entry = result["explicit-high"];
    assert.ok(entry !== undefined);
    assert.ok(
      Object.prototype.hasOwnProperty.call(entry, "thinkingDefault"),
    );
    assert.strictEqual(entry.thinkingDefault, "high");
  });
});

// ── TC-660-U-18: Fleet-shape regression test ─────────────────────────────────

describe("TC-660-U-18: Fleet-shape regression — issue-cited agents get expected thinkingDefault", () => {
  const rows: AgentRow[] = [
    makeThinkingRow("bastion", "off"),
    makeThinkingRow("ember", "off"),
    makeThinkingRow("flicker", "off"),
    makeThinkingRow("flint", "off"),
    makeThinkingRow("gallan", "off"),
    makeThinkingRow("gidget", "off"),
    makeThinkingRow("grain", "off"),
    makeThinkingRow("hermes", "off"),
    makeThinkingRow("newhart", "high"),
    makeThinkingRow("scout", "low"),
    makeThinkingRow("gem", "adaptive"),
    makeThinkingRow("coder", "medium"),
  ];
  const { entries: result } = buildAgentsList(rows);

  it("every 'off'-configured agent gets thinkingDefault: 'off'", () => {
    for (const name of ["bastion", "ember", "flicker", "flint", "gallan", "gidget", "grain", "hermes"]) {
      const entry = result[name];
      assert.ok(entry !== undefined, `entry for ${name} must exist`);
      assert.strictEqual(entry.thinkingDefault, "off", `${name} must have thinkingDefault: off`);
    }
  });

  it("newhart gets thinkingDefault: 'high'", () => {
    assert.strictEqual(result["newhart"]?.thinkingDefault, "high");
  });

  it("other tiered agents keep their explicit values", () => {
    assert.strictEqual(result["scout"]?.thinkingDefault, "low");
    assert.strictEqual(result["gem"]?.thinkingDefault, "adaptive");
    assert.strictEqual(result["coder"]?.thinkingDefault, "medium");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// TC-707-U-001..011: agents.entries keyed-object shape, validation, adversarial
// rows (#707)
// ─────────────────────────────────────────────────────────────────────────────

// ── TC-707-001: buildAgentsList output changes from bare array to keyed object

describe("TC-707-001: buildAgentsList emits keyed-object agents.entries shape", () => {
  const rows: AgentRow[] = [
    {
      name: "alpha",
      model: "anthropic/claude-sonnet-4",
      fallback_models: null,
      thinking: "low",
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
      status: "active",
    },
    {
      name: "beta",
      model: "google/gemini-flash",
      fallback_models: ["openai/gpt-4o"],
      thinking: null,
      instance_type: "subagent",
      is_default: true,
      allowed_subagents: ["alpha"],
      status: "active",
    },
  ];
  const { entries: result } = buildAgentsList(rows);

  it("output is a plain object, not an array", () => {
    assert.ok(typeof result === "object" && result !== null && !Array.isArray(result));
  });

  it("keys are agent ids", () => {
    assert.deepStrictEqual(Object.keys(result).sort(), ["alpha", "beta"]);
  });

  it("each value does NOT contain an id field", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        !Object.prototype.hasOwnProperty.call(entry, "id"),
        `entry ${id} must not have an id field`,
      );
    }
  });

  it("no default marker is emitted on any keyed value", () => {
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        !Object.prototype.hasOwnProperty.call(entry, "default"),
        `entry ${id} must not have a default field`,
      );
    }
  });

  it("model object shape is preserved", () => {
    assert.deepStrictEqual(result["beta"]?.model, {
      primary: "google/gemini-flash",
      fallbacks: ["openai/gpt-4o"],
    });
  });

  it("output passes validateAgentsEntries", () => {
    assert.doesNotThrow(() => validateAgentsEntries(result));
  });
});

// ── TC-707-004: validation BEFORE atomic write ───────────────────────────────

describe("TC-707-004: validation happens before atomic write", () => {
  let tmpDir: string;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-write-test-"));
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("writes a valid keyed object and leaves no tmp file", async () => {
    const filePath = path.join(tmpDir, "agents.json");
    const entries: Record<string, AgentEntryConfig> = {
      nova: { model: "anthropic/claude-opus-4" },
    };
    await writeAgentsJsonAtomically(filePath, entries);

    assert.ok(fs.existsSync(filePath));
    const parsed = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    assert.strictEqual(parsed.nova.model, "anthropic/claude-opus-4");
    assert.ok(!Object.prototype.hasOwnProperty.call(parsed.nova, "id"));

    const tmpFiles = fs.readdirSync(tmpDir).filter((f) => f.endsWith(".tmp"));
    assert.deepStrictEqual(tmpFiles, []);
  });

  it("aborts write and leaves live file untouched when validation fails", async () => {
    const filePath = path.join(tmpDir, "agents-invalid.json");
    fs.writeFileSync(filePath, "{\"nova\":{\"model\":\"good\"}}\n", "utf-8");
    const originalContent = fs.readFileSync(filePath, "utf-8");

    // Invalid: contains an id field inside the value
    const invalidEntries: Record<string, AgentEntryConfig> = {
      nova: { id: "nova", model: "anthropic/claude-opus-4" } as unknown as AgentEntryConfig,
    };

    await assert.rejects(
      async () => writeAgentsJsonAtomically(filePath, invalidEntries),
      /must not contain an "id" field/,
    );

    const afterContent = fs.readFileSync(filePath, "utf-8");
    assert.strictEqual(afterContent, originalContent, "live file must be untouched");

    const tmpFiles = fs.readdirSync(tmpDir).filter((f) => f.endsWith(".tmp"));
    assert.deepStrictEqual(tmpFiles, [], "no tmp file should remain after aborted write");
  });

  it("rejects empty entries object before writing", async () => {
    const filePath = path.join(tmpDir, "agents-empty.json");
    await assert.rejects(
      async () => writeAgentsJsonAtomically(filePath, {}),
      /must contain at least one configured agent/,
    );
    assert.ok(!fs.existsSync(filePath));
  });
});

// ── TC-707-005: only status='active' rows are included ───────────────────────

describe("TC-707-005: only status='active' rows are included", () => {
  it("includes active rows", () => {
    const rows: AgentRow[] = [
      { name: "active1", model: "m1", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
      { name: "active2", model: "m2", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    const { entries: result } = buildAgentsList(rows);
    assert.deepStrictEqual(Object.keys(result).sort(), ["active1", "active2"]);
  });

  it("excludes retired/archived/non-active rows even with real content", () => {
    const rows: AgentRow[] = [
      { name: "active", model: "anthropic/claude-opus-4", fallback_models: ["openai/gpt-4o"], thinking: "high", instance_type: "primary", is_default: true, allowed_subagents: ["retired", "shared"], status: "active" },
      {
        name: "retired",
        model: "google/gemini-flash",
        fallback_models: ["anthropic/claude-sonnet-4"],
        thinking: "xhigh",
        instance_type: "subagent",
        is_default: false,
        allowed_subagents: ["*"],
        status: "retired",
      },
    ];
    const { entries: result, skipped } = buildAgentsList(rows);
    assert.strictEqual(Object.keys(result).length, 1);
    assert.ok(result["active"]);
    assert.strictEqual(result["retired"], undefined);
    assert.ok(skipped.some((s) => s.name === "retired" && s.reason.includes("retired")));
  });
});

// ── TC-707-008: adversarial wrong-type fallback_models ───────────────────────

describe("TC-707-008: wrong-type fallback_models is handled without breaking file", () => {
  it("normalizes a scalar string fallback_models to a single-element array", () => {
    const rows: AgentRow[] = [
      { name: "scalar", model: "primary", fallback_models: "fallback-model", thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    const { entries: result, skipped } = buildAgentsList(rows);
    assert.deepStrictEqual(result["scalar"]?.model, {
      primary: "primary",
      fallbacks: ["fallback-model"],
    });
    assert.ok(skipped.some((s) => s.name === "scalar" && s.reason.includes("scalar string")));
    assert.doesNotThrow(() => validateAgentsEntries(result));
  });

  it("skips rows with unsupported fallback_models type", () => {
    const rows: AgentRow[] = [
      { name: "good", model: "m1", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
      { name: "bad", model: "m2", fallback_models: 123, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    const { entries: result, skipped } = buildAgentsList(rows);
    assert.strictEqual(Object.keys(result).length, 1);
    assert.ok(result["good"]);
    assert.strictEqual(result["bad"], undefined);
    assert.ok(skipped.some((s) => s.name === "bad" && s.reason.includes("unsupported type")));
    assert.doesNotThrow(() => validateAgentsEntries(result));
  });
});

// ── TC-707-009: NULL model on an active row ──────────────────────────────────

describe("TC-707-009: NULL model on active row is skipped, never emits model:null", () => {
  it("omits rows with null model and reports the skip", () => {
    const rows: AgentRow[] = [
      { name: "good", model: "anthropic/claude-opus-4", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
      { name: "nullmodel", model: null, fallback_models: null, thinking: "high", instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    const { entries: result, skipped } = buildAgentsList(rows);
    assert.strictEqual(Object.keys(result).length, 1);
    assert.ok(result["good"]);
    assert.strictEqual(result["nullmodel"], undefined);
    assert.ok(skipped.some((s) => s.name === "nullmodel" && s.reason.includes("model is null")));
  });

  it("serialized output never contains a literal null model", () => {
    const rows: AgentRow[] = [
      { name: "good", model: "m", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    const { entries: result } = buildAgentsList(rows);
    const json = JSON.stringify(result);
    assert.ok(!json.includes('"model":null'));
    assert.ok(!json.includes('"model":"null"'));
  });
});

// ── TC-707-010: unknown/malformed provider prefix ────────────────────────────

describe("TC-707-010: unknown provider prefix does not crash the generator", () => {
  beforeEach(() => resetProviderPrefixWarnings());

  it("passes through an unrecognized provider prefix", () => {
    const rows: AgentRow[] = [
      { name: "weird", model: "totally-unknown-provider/some-model", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
      { name: "bare", model: "some-model-name", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    const { entries: result } = buildAgentsList(rows);
    assert.strictEqual(result["weird"]?.model, "totally-unknown-provider/some-model");
    assert.strictEqual(result["bare"]?.model, "some-model-name");
    assert.doesNotThrow(() => validateAgentsEntries(result));
  });

  it("logs exactly one warning for an unknown provider prefix and emits the entry unchanged", () => {
    const warnings: string[] = [];
    const logger = { warn: (msg: string) => warnings.push(msg) };
    const rows: AgentRow[] = [
      { name: "known", model: "anthropic/claude-sonnet-4", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
      { name: "weird", model: "totally-unknown-provider/some-model", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    const { entries: result } = buildAgentsList(rows, logger);
    assert.strictEqual(result["weird"]?.model, "totally-unknown-provider/some-model");
    assert.strictEqual(warnings.length, 1);
    assert.ok(warnings[0]?.includes("weird"));
    assert.ok(warnings[0]?.includes("totally-unknown-provider"));
  });

  it("warns for a bare model name with no provider prefix", () => {
    const warnings: string[] = [];
    const logger = { warn: (msg: string) => warnings.push(msg) };
    const rows: AgentRow[] = [
      { name: "bare", model: "some-model-name", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    const { entries: result } = buildAgentsList(rows, logger);
    assert.strictEqual(result["bare"]?.model, "some-model-name");
    assert.strictEqual(warnings.length, 1);
    assert.ok(warnings[0]?.includes("bare"));
    assert.ok(warnings[0]?.includes("no provider prefix"));
  });

  it("warns for unknown prefixes in fallback models", () => {
    const warnings: string[] = [];
    const logger = { warn: (msg: string) => warnings.push(msg) };
    const rows: AgentRow[] = [
      {
        name: "multi",
        model: "anthropic/claude-sonnet-4",
        fallback_models: ["unknown-provider/fallback", "google/gemini-flash"],
        thinking: null,
        instance_type: "subagent",
        is_default: false,
        allowed_subagents: null,
        status: "active",
      },
    ];
    const { entries: result } = buildAgentsList(rows, logger);
    const model = result["multi"]?.model;
    assert.ok(typeof model === "object" && "fallbacks" in model);
    assert.deepStrictEqual(model.fallbacks, ["unknown-provider/fallback", "google/gemini-flash"]);
    assert.strictEqual(warnings.length, 1);
    assert.ok(warnings[0]?.includes("unknown-provider"));
  });

  it("warns only once per (agent, prefix) across consecutive buildAgentsList calls", () => {
    resetProviderPrefixWarnings();
    const warnings: string[] = [];
    const logger = { warn: (msg: string) => warnings.push(msg) };
    const rowA: AgentRow = {
      name: "dedup-a",
      model: "unknown-dedup-provider/model-a",
      fallback_models: null,
      thinking: null,
      instance_type: "subagent",
      is_default: false,
      allowed_subagents: null,
      status: "active",
    };

    buildAgentsList([rowA], logger);
    assert.strictEqual(warnings.length, 1);

    // Same agent, same unknown prefix -> no new warning.
    buildAgentsList([rowA], logger);
    assert.strictEqual(warnings.length, 1);

    // Different agent, same unknown prefix -> one more warning.
    const rowB: AgentRow = { ...rowA, name: "dedup-b" };
    buildAgentsList([rowB], logger);
    assert.strictEqual(warnings.length, 2);
  });
});

// ── TC-707-014: duplicate raw agent names are a hard error ───────────────────

describe("TC-707-014: duplicate raw agent names block the build", () => {
  it("throws when two raw rows share the same name", () => {
    const rows: AgentRow[] = [
      { name: "dupe", model: "anthropic/claude-sonnet-4", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
      { name: "dupe", model: "google/gemini-flash", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    assert.throws(
      () => buildAgentsList(rows),
      /Duplicate agent name 'dupe'/,
    );
  });

  it("throws even when the duplicate would otherwise be skipped", () => {
    const rows: AgentRow[] = [
      { name: "dupe", model: "anthropic/claude-sonnet-4", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
      { name: "dupe", model: "google/gemini-flash", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "retired" },
    ];
    assert.throws(
      () => buildAgentsList(rows),
      /Duplicate agent name 'dupe'/,
    );
  });

  it("does not throw when names are distinct", () => {
    const rows: AgentRow[] = [
      { name: "alpha", model: "anthropic/claude-sonnet-4", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
      { name: "beta", model: "google/gemini-flash", fallback_models: null, thinking: null, instance_type: "subagent", is_default: false, allowed_subagents: null, status: "active" },
    ];
    assert.doesNotThrow(() => buildAgentsList(rows));
  });
});

// ── TC-707-011: non-active fixture rows use real, distinguishable content ────

describe("TC-707-011: non-active rows with distinctive real content are filtered", () => {
  it("a retired row with full config is excluded from output", () => {
    const rows: AgentRow[] = [
      { name: "nova", model: "anthropic/claude-opus-4", fallback_models: null, thinking: "high", instance_type: "primary", is_default: true, allowed_subagents: ["gem", "coder"], status: "active" },
      {
        name: "retired-shadow",
        model: "openrouter/anthropic/claude-opus-5.5",
        fallback_models: ["anthropic/claude-opus-4-8", "openai/gpt-5.4"],
        thinking: "ultra",
        instance_type: "subagent",
        is_default: false,
        allowed_subagents: ["nova", "gem", "coder", "scout"],
        status: "retired",
      },
    ];
    const { entries: result } = buildAgentsList(rows);
    assert.strictEqual(Object.keys(result).length, 1);
    assert.ok(result["nova"]);
    assert.strictEqual(result["retired-shadow"], undefined);
  });
});

// ── TC-707-013: cutover drift report (fixture-based diff logic) ──────────────

describe("TC-707-013: cutover drift report detects model drift and new agents", () => {
  it("reports model drift for a shared agent and lists DB-only agents", () => {
    // Simulated inline agents.entries (the currently-running config).
    const inline: Record<string, AgentEntryConfig> = {
      nova: {
        model: {
          primary: "openrouter/anthropic/claude-opus-5.5",
          fallbacks: ["anthropic/claude-opus-4-8"],
        },
        thinkingDefault: "high",
      },
      gem: { model: "google/gemini-flash" },
    };

    // Simulated generated roster from the DB.
    const generated: Record<string, AgentEntryConfig> = {
      nova: {
        model: "anthropic/claude-opus-4-8", // DB has live fallback as primary
        thinkingDefault: "high",
      },
      gem: { model: "google/gemini-flash" },
      coder: { model: "anthropic/claude-sonnet-4" },
      scout: { model: "google/gemini-flash" },
    };

    const inlineIds = Object.keys(inline);
    const generatedIds = Object.keys(generated);
    const commonIds = inlineIds.filter((id) => generatedIds.includes(id));
    const dbOnlyIds = generatedIds.filter((id) => !inlineIds.includes(id));

    // Drift: nova's model differs.
    const novaDrift = !(
      JSON.stringify(generated["nova"]?.model) === JSON.stringify(inline["nova"]?.model)
    );
    assert.strictEqual(novaDrift, true, "nova model drift must be detected");

    // New agents that a naive cutover would add.
    assert.deepStrictEqual(dbOnlyIds.sort(), ["coder", "scout"]);

    // Shared agent with no drift.
    assert.strictEqual(
      JSON.stringify(generated["gem"]),
      JSON.stringify(inline["gem"]),
    );

    // Report line as the real tool would emit.
    const reportLines: string[] = [];
    for (const id of commonIds) {
      if (JSON.stringify(generated[id]) !== JSON.stringify(inline[id])) {
        reportLines.push(
          `${id}: model differs — generated=${JSON.stringify(generated[id]!.model)} inline=${JSON.stringify(inline[id]!.model)}`,
        );
      }
    }
    assert.ok(
      reportLines.some((line) => line.includes("nova") && line.includes("openrouter")),
      "report must surface nova's model drift",
    );
  });
});

// ── TC-770-U-01: Regression — generated agents.json must never contain a default key ──

describe("TC-770-U-01: generated agents.json must never contain a legacy default key", () => {
  it("single default-marked row produces JSON with no 'default' key", () => {
    const rows: AgentRow[] = [
      {
        name: "nova",
        model: "anthropic/claude-opus-4",
        fallback_models: null,
        thinking: "high",
        instance_type: "primary",
        is_default: true,
        allowed_subagents: ["gem", "coder"],
      },
    ];
    const { entries: result } = buildAgentsList(rows);
    const jsonStr = JSON.stringify(result, null, 2);

    assert.ok(
      !jsonStr.includes('"default"'),
      `serialized agents.json must not contain a "default" key; got: ${jsonStr}`,
    );
    assert.doesNotThrow(() => validateAgentsEntries(result));
  });

  it("mixed fleet with one is_default=true produces no default key anywhere", () => {
    const rows: AgentRow[] = [
      {
        name: "nova",
        model: "anthropic/claude-opus-4",
        fallback_models: null,
        thinking: "high",
        instance_type: "primary",
        is_default: true,
        allowed_subagents: ["gem", "coder"],
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
    ];
    const { entries: result } = buildAgentsList(rows);
    const jsonStr = JSON.stringify(result, null, 2);

    assert.ok(
      !jsonStr.includes('"default"'),
      `serialized agents.json must not contain a "default" key; got: ${jsonStr}`,
    );
    for (const [id, entry] of Object.entries(result)) {
      assert.ok(
        !Object.prototype.hasOwnProperty.call(entry, "default"),
        `entry '${id}' must not have a default field`,
      );
    }
    assert.doesNotThrow(() => validateAgentsEntries(result));
  });

  it("atomic write of generated entries produces a file with no default key", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "sync-770-test-"));
    try {
      const filePath = path.join(tmpDir, "agents.json");
      const rows: AgentRow[] = [
        {
          name: "nova",
          model: "anthropic/claude-opus-4",
          fallback_models: null,
          thinking: "high",
          instance_type: "primary",
          is_default: true,
          allowed_subagents: ["gem"],
        },
      ];
      const { entries } = buildAgentsList(rows);
      await writeAgentsJsonAtomically(filePath, entries);

      const written = fs.readFileSync(filePath, "utf-8");
      assert.ok(
        !written.includes('"default"'),
        `written agents.json must not contain a "default" key; got: ${written}`,
      );
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
