/**
 * Unit tests for buildAgentsList()
 *
 * TC-244-U-01  NOVA session — self as default, NOVA's subagents only
 * TC-244-U-02  Newhart session — self as default, Newhart's subagents only
 * TC-244-U-03  Mutual exclusion — NOVA and Newhart never see each other
 * TC-244-U-04  Fallback model shape preserved from function rows
 * TC-244-U-05  Row with is_default = null emits no `default` key
 *
 * Framework: Node built-in test runner (node:test) + tsx for TS execution.
 * Run: npx tsx --test src/sync.test.ts
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildAgentsList } from "./sync.js";
import type { AgentRow } from "./sync.js";

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
