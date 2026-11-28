/**
 * Heartbeat compatibility tests for nova-mind#824.
 *
 * Covers the version gate and heartbeat-config emission behaviour for
 * OpenClaw >= 2026.11.5 ("retired") versus < 2026.11.5 ("legacy").
 *
 * Section 4  — TC-824-V-*  detection / classification
 * Section 5  — TC-824-E-*  per-agent + defaults.heartbeat emission gating
 * Section 6  — TC-824-R-*  stale-content removal
 * Section 7  — TC-824-M-*  managed-mode / hand-authored-key exemption
 * Section 9  — TC-824-I-*  idempotence
 * Section 10 — TC-824-D-*  #819 no-default-marker interaction
 *
 * Framework: Node built-in test runner + tsx.
 */

import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  buildAgentsList,
  buildExplicitOwnershipConfig,
  classifyHeartbeatCompat,
  detectHostHeartbeatCompat,
  resolveHeartbeatCompatMode,
  resetExplicitOwnershipInstructions,
  syncAgentsConfig,
  syncExplicitOwnershipConfig,
  validateExplicitOwnershipConfig,
} from "./sync.js";
import type { AgentRow, HeartbeatCompatMode } from "./sync.js";

// ── Helpers ─────────────────────────────────────────────────────────────────

function makeHeartbeatRow(enabled: boolean, overrides: Partial<AgentRow> = {}): AgentRow {
  return {
    name: "newhart",
    model: "anthropic/claude-opus-4",
    fallback_models: null,
    thinking: null,
    instance_type: "peer",
    is_default: true,
    allowed_subagents: null,
    heartbeat_enabled: enabled,
    heartbeat_every: "30m",
    heartbeat_target: "channel",
    heartbeat_to: "heartbeat-room",
    heartbeat_isolated_session: true,
    ...overrides,
  };
}

function makeMockClient(rows: AgentRow[]): import("pg").Client {
  return {
    query: async (sql: string) => {
      if (typeof sql === "string" && sql.includes("information_schema.columns")) {
        return { rows: [{ exists: true }] };
      }
      return { rows };
    },
  } as unknown as import("pg").Client;
}

/**
 * Create a fake host gateway tree with an openclaw package.json at the given
 * version. Returns the path to a fake gateway entry script.
 */
function makeFakeHostTree(version: string): { entryPath: string; cleanup: () => void } {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-host-"));
  const binDir = path.join(tmpDir, "bin");
  const openclawDir = path.join(tmpDir, "node_modules", "openclaw");
  fs.mkdirSync(binDir, { recursive: true });
  fs.mkdirSync(openclawDir, { recursive: true });
  const entryPath = path.join(binDir, "openclaw.js");
  fs.writeFileSync(entryPath, "#!/usr/bin/env node\n", "utf-8");
  fs.writeFileSync(
    path.join(openclawDir, "package.json"),
    JSON.stringify({ name: "openclaw", version }),
    "utf-8",
  );
  return {
    entryPath,
    cleanup: () => fs.rmSync(tmpDir, { recursive: true, force: true }),
  };
}

// ── Section 4: Detection / classification ───────────────────────────────────

describe("TC-824-V-01..V-07: numeric version boundary", () => {
  const cases: Array<[string, HeartbeatCompatMode]> = [
    ["2026.11.3", "legacy"],
    ["2026.11.4", "legacy"],
    ["2026.11.5", "retired"],
    ["2026.11.10", "retired"],
    ["2026.11.100", "retired"],
    ["2026.9.6", "legacy"],
    ["2027.1.1", "retired"],
  ];

  for (const [input, expected] of cases) {
    it(`classifies ${input} as ${expected}`, () => {
      const result = classifyHeartbeatCompat(input);
      assert.strictEqual(result.mode, expected);
      assert.ok(result.reason.includes("version-parsed"));
    });
  }
});

describe("TC-824-V-08..V-10: safe default on unparseable input", () => {
  const cases = ["", undefined, "banana"];

  for (const input of cases) {
    it(`classifies ${JSON.stringify(input)} as retired via safe default`, () => {
      const result = classifyHeartbeatCompat(input);
      assert.strictEqual(result.mode, "retired");
      assert.strictEqual(result.reason, "detection-failed-safe-default");
    });
  }
});

describe("TC-824-V-11..V-14: prerelease / suffix / metadata handling", () => {
  const cases: Array<[string, HeartbeatCompatMode]> = [
    ["2026.11.10-beta.1", "retired"],
    ["2026.11.10-nova", "retired"],
    ["2026.11.10-nova.2", "retired"],
    ["2026.11.10+build.5", "retired"],
    [" 2026.11.10 ", "retired"],
    ["v2026.11.10", "retired"],
  ];

  for (const [input, expected] of cases) {
    it(`classifies ${JSON.stringify(input)} as ${expected}`, () => {
      const result = classifyHeartbeatCompat(input);
      assert.strictEqual(result.mode, expected);
    });
  }
});

describe("TC-824-V-20: wrong-copy guard", () => {
  it("reads the host gateway's openclaw version, not the plugin-local copy", () => {
    const host = makeFakeHostTree("2026.11.10");
    try {
      // Place a plugin-local copy with an older version in a sibling directory.
      // The detector must still use the host entry path we supply.
      const pluginLocal = path.join(path.dirname(host.entryPath), "..", "plugin-local");
      fs.mkdirSync(path.join(pluginLocal, "node_modules", "openclaw"), { recursive: true });
      fs.writeFileSync(
        path.join(pluginLocal, "node_modules", "openclaw", "package.json"),
        JSON.stringify({ name: "openclaw", version: "2026.11.3" }),
        "utf-8",
      );

      const result = detectHostHeartbeatCompat({ hostEntryPath: host.entryPath });
      assert.strictEqual(result.mode, "retired");
      assert.strictEqual(result.version, "2026.11.10");
      assert.ok(result.reason.includes("version-parsed"));
    } finally {
      host.cleanup();
    }
  });
});

describe("TC-824-V-21: operator override via resolveHeartbeatCompatMode", () => {
  it("overrides detection with 'legacy'", () => {
    const result = resolveHeartbeatCompatMode("legacy", { mode: "retired", reason: "x" });
    assert.strictEqual(result.mode, "legacy");
    assert.strictEqual(result.reason, "config-override");
  });

  it("overrides detection with 'retired'", () => {
    const result = resolveHeartbeatCompatMode("retired", { mode: "legacy", reason: "x" });
    assert.strictEqual(result.mode, "retired");
    assert.strictEqual(result.reason, "config-override");
  });

  it("falls back to detected mode for 'auto'", () => {
    const result = resolveHeartbeatCompatMode("auto", { mode: "retired", reason: "detected" });
    assert.strictEqual(result.mode, "retired");
    assert.strictEqual(result.reason, "detected");
  });

  it("falls back to detected mode for unknown values", () => {
    const result = resolveHeartbeatCompatMode("banana", { mode: "legacy", reason: "detected" });
    assert.strictEqual(result.mode, "legacy");
    assert.strictEqual(result.reason, "detected");
  });
});

// ── Section 5: Per-agent + defaults.heartbeat emission gating ───────────────

describe("TC-824-E-01: retired mode omits per-agent heartbeat", () => {
  const row = makeHeartbeatRow(true);
  const { entries } = buildAgentsList([row], { heartbeatCompatMode: "retired" });

  it("does not emit a heartbeat key", () => {
    assert.ok(!Object.prototype.hasOwnProperty.call(entries["newhart"], "heartbeat"));
  });
});

describe("TC-824-E-02: legacy mode preserves per-agent heartbeat byte-identical", () => {
  const row = makeHeartbeatRow(true);
  const { entries } = buildAgentsList([row], { heartbeatCompatMode: "legacy" });

  it("emits the expected heartbeat object", () => {
    assert.deepStrictEqual(entries["newhart"].heartbeat, {
      every: "30m",
      target: "channel",
      to: "heartbeat-room",
      isolatedSession: true,
    });
  });
});

describe("TC-824-E-03: retired mode omits heartbeat regardless of per-row flag", () => {
  const rows: AgentRow[] = [
    makeHeartbeatRow(true, { name: "enabled", is_default: false }),
    makeHeartbeatRow(false, { name: "disabled", is_default: false }),
    makeHeartbeatRow(true, { name: "nullish", is_default: false, heartbeat_enabled: null }),
  ];
  const { entries } = buildAgentsList(rows, { heartbeatCompatMode: "retired" });

  it("zero entries have a heartbeat key", () => {
    for (const id of Object.keys(entries)) {
      assert.ok(!Object.prototype.hasOwnProperty.call(entries[id], "heartbeat"));
    }
  });
});

describe("TC-824-E-04: retired mode omits agents.defaults.heartbeat", () => {
  const config = buildExplicitOwnershipConfig("newhart", [], undefined, "retired");

  it("does not emit defaults.heartbeat", () => {
    assert.ok(!Object.prototype.hasOwnProperty.call(config.agents.defaults, "heartbeat"));
  });

  it("still emits systemAgent", () => {
    assert.strictEqual(config.agents.defaults.systemAgent.agentId, "newhart");
  });
});

describe("TC-824-E-05: legacy mode emits agents.defaults.heartbeat byte-identical", () => {
  const config = buildExplicitOwnershipConfig("newhart", [], undefined, "legacy");

  it("emits the expected heartbeat block", () => {
    assert.deepStrictEqual(config.agents.defaults.heartbeat, {
      directPolicy: "block",
      target: "none",
      agentId: "newhart",
    });
  });
});

describe("TC-824-E-06: retired mode explicit-ownership validator does not require heartbeat", () => {
  const config = buildExplicitOwnershipConfig("newhart", [], undefined, "retired");

  it("does not throw", () => {
    assert.doesNotThrow(() => validateExplicitOwnershipConfig(config, "retired"));
  });
});

describe("TC-824-E-07: legacy mode validator still requires heartbeat", () => {
  const config = buildExplicitOwnershipConfig("newhart", [], undefined, "legacy");

  it("does not throw on the non-mutated legacy object", () => {
    assert.doesNotThrow(() => validateExplicitOwnershipConfig(config, "legacy"));
  });

  it("throws when heartbeat is deleted", () => {
    const mutated = JSON.parse(JSON.stringify(config)) as typeof config;
    delete mutated.agents.defaults.heartbeat;
    assert.throws(() => validateExplicitOwnershipConfig(mutated, "legacy"));
  });
});

// ── Section 6: Stale-content removal ────────────────────────────────────────

describe("TC-824-R-01: retired mode removes stale per-agent heartbeat from agents.json", () => {
  it("writes a file without heartbeat and reports changed=true", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-r01-"));
    try {
      const outputPath = path.join(tmpDir, "agents.json");
      fs.writeFileSync(
        outputPath,
        JSON.stringify(
          {
            newhart: {
              model: "anthropic/claude-opus-4",
              heartbeat: { every: "30m", target: "channel" },
            },
          },
          null,
          2,
        ) + "\n",
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const changed = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "retired",
      });
      assert.strictEqual(changed, true);

      const written = JSON.parse(fs.readFileSync(outputPath, "utf-8")) as Record<string, unknown>;
      assert.ok(!Object.prototype.hasOwnProperty.call(written["newhart"], "heartbeat"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

describe("TC-824-R-02: retired mode removes stale agents.defaults.heartbeat", () => {
  it("writes a file without defaults.heartbeat and reports changed=true", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-r02-"));
    try {
      const openclawPath = path.join(tmpDir, "openclaw.json");
      const explicitPath = path.join(tmpDir, "agents-explicit.json");
      fs.writeFileSync(
        openclawPath,
        JSON.stringify({ "$include": "./agents-explicit.json" }),
        "utf-8",
      );
      fs.writeFileSync(
        explicitPath,
        JSON.stringify(
          {
            agents: {
              ownership: "explicit",
              defaults: {
                heartbeat: { directPolicy: "block", target: "none", agentId: "newhart" },
                systemAgent: { agentId: "newhart" },
              },
            },
            bindings: [],
          },
          null,
          2,
        ) + "\n",
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const result = await syncExplicitOwnershipConfig(
        client,
        openclawPath,
        explicitPath,
        { channels: {} },
        undefined,
        "retired",
      );
      assert.strictEqual(result.explicitChanged, true);

      const written = JSON.parse(fs.readFileSync(explicitPath, "utf-8")) as Record<string, unknown>;
      const defaults = (written.agents as Record<string, unknown>).defaults as Record<string, unknown>;
      assert.ok(!Object.prototype.hasOwnProperty.call(defaults, "heartbeat"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

describe("TC-824-R-03: removal converges to a stable steady state", () => {
  it("second sync returns changed=false", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-r03-"));
    try {
      const outputPath = path.join(tmpDir, "agents.json");
      fs.writeFileSync(
        outputPath,
        JSON.stringify(
          {
            newhart: {
              model: "anthropic/claude-opus-4",
              heartbeat: { every: "30m" },
            },
          },
          null,
          2,
        ) + "\n",
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const first = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "retired",
      });
      assert.strictEqual(first, true);

      const second = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "retired",
      });
      assert.strictEqual(second, false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

// ── Section 7: Managed-mode / hand-authored-key exemption ───────────────────

describe("TC-824-M-01..M-04: hand-authored predicate with heartbeat exemption", () => {
  beforeEach(() => {
    resetExplicitOwnershipInstructions();
  });

  it("M-01: retired mode treats heartbeat alone as not hand-authored", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-m01-"));
    try {
      const openclawPath = path.join(tmpDir, "openclaw.json");
      const explicitPath = path.join(tmpDir, "agents-explicit.json");
      fs.writeFileSync(
        openclawPath,
        JSON.stringify({ agents: { defaults: { heartbeat: { agentId: "newhart" } } } }),
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const result = await syncExplicitOwnershipConfig(
        client,
        openclawPath,
        explicitPath,
        { channels: { discord: { enabled: true } } },
        undefined,
        "retired",
      );
      // The include is missing, so the function logs the missing-include
      // instruction and returns false; the important part is that it did NOT
      // treat the stale heartbeat key as hand-authored and disable managed mode.
      assert.strictEqual(result.explicitChanged, false);
      assert.strictEqual(result.openclawChanged, false);
      assert.ok(!fs.existsSync(explicitPath), "explicit file must not be written when include is missing");
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("M-02: legacy mode treats heartbeat alone as hand-authored", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-m02-"));
    try {
      const openclawPath = path.join(tmpDir, "openclaw.json");
      const explicitPath = path.join(tmpDir, "agents-explicit.json");
      fs.writeFileSync(
        openclawPath,
        JSON.stringify({ agents: { defaults: { heartbeat: { agentId: "newhart" } } } }),
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const result = await syncExplicitOwnershipConfig(
        client,
        openclawPath,
        explicitPath,
        { channels: { discord: { enabled: true } } },
        undefined,
        "legacy",
      );
      assert.strictEqual(result.explicitChanged, false);
      assert.ok(!fs.existsSync(explicitPath));
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("M-03: retired mode still treats agents.ownership as hand-authored", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-m03-"));
    try {
      const openclawPath = path.join(tmpDir, "openclaw.json");
      const explicitPath = path.join(tmpDir, "agents-explicit.json");
      fs.writeFileSync(
        openclawPath,
        JSON.stringify({ agents: { ownership: "explicit" } }),
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const result = await syncExplicitOwnershipConfig(
        client,
        openclawPath,
        explicitPath,
        { channels: { discord: { enabled: true } } },
        undefined,
        "retired",
      );
      assert.strictEqual(result.explicitChanged, false);
      assert.ok(!fs.existsSync(explicitPath));
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("M-04: retired mode still treats systemAgent as hand-authored", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-m04-"));
    try {
      const openclawPath = path.join(tmpDir, "openclaw.json");
      const explicitPath = path.join(tmpDir, "agents-explicit.json");
      fs.writeFileSync(
        openclawPath,
        JSON.stringify({ agents: { defaults: { systemAgent: { agentId: "newhart" } } } }),
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const result = await syncExplicitOwnershipConfig(
        client,
        openclawPath,
        explicitPath,
        { channels: { discord: { enabled: true } } },
        undefined,
        "retired",
      );
      assert.strictEqual(result.explicitChanged, false);
      assert.ok(!fs.existsSync(explicitPath));
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

describe("TC-824-M-05..M-06: retired mode proceeds to manage when only heartbeat is hand-authored", () => {
  beforeEach(() => {
    resetExplicitOwnershipInstructions();
  });

  it("M-05: writes managed explicit file when heartbeat is the only stale key", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-m05-"));
    try {
      const openclawPath = path.join(tmpDir, "openclaw.json");
      const explicitPath = path.join(tmpDir, "agents-explicit.json");
      fs.writeFileSync(
        openclawPath,
        JSON.stringify({
          "$include": "./agents-explicit.json",
          agents: { defaults: { heartbeat: { agentId: "newhart" } } },
        }),
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const result = await syncExplicitOwnershipConfig(
        client,
        openclawPath,
        explicitPath,
        { channels: { discord: { enabled: true } } },
        undefined,
        "retired",
      );
      assert.strictEqual(result.explicitChanged, true);
      assert.ok(fs.existsSync(explicitPath));
      const written = JSON.parse(fs.readFileSync(explicitPath, "utf-8")) as Record<string, unknown>;
      const defaults = (written.agents as Record<string, unknown>).defaults as Record<string, unknown>;
      assert.ok(!Object.prototype.hasOwnProperty.call(defaults, "heartbeat"));
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

// ── Section 9: Idempotence ──────────────────────────────────────────────────

describe("TC-824-I-01..I-02: retired mode idempotence", () => {
  it("syncAgentsConfig is idempotent in retired mode", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-i01-"));
    try {
      const outputPath = path.join(tmpDir, "agents.json");
      const client = makeMockClient([makeHeartbeatRow(true)]);
      const first = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "retired",
      });
      assert.strictEqual(first, true);

      const second = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "retired",
      });
      assert.strictEqual(second, false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it("syncExplicitOwnershipConfig is idempotent in retired mode", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-i02-"));
    try {
      const openclawPath = path.join(tmpDir, "openclaw.json");
      const explicitPath = path.join(tmpDir, "agents-explicit.json");
      fs.writeFileSync(
        openclawPath,
        JSON.stringify({ "$include": "./agents-explicit.json" }),
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const first = await syncExplicitOwnershipConfig(
        client,
        openclawPath,
        explicitPath,
        { channels: { discord: { enabled: true } } },
        undefined,
        "retired",
      );
      assert.strictEqual(first.explicitChanged, true);
      assert.strictEqual(first.openclawChanged, false);

      const second = await syncExplicitOwnershipConfig(
        client,
        openclawPath,
        explicitPath,
        { channels: { discord: { enabled: true } } },
        undefined,
        "retired",
      );
      assert.strictEqual(second.explicitChanged, false);
      assert.strictEqual(second.openclawChanged, false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

describe("TC-824-I-03: legacy mode idempotence is preserved", () => {
  it("syncAgentsConfig is idempotent in legacy mode", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-i03-"));
    try {
      const outputPath = path.join(tmpDir, "agents.json");
      const client = makeMockClient([makeHeartbeatRow(true)]);
      const first = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "legacy",
      });
      assert.strictEqual(first, true);

      const second = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "legacy",
      });
      assert.strictEqual(second, false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

describe("TC-824-I-04: removal then steady state", () => {
  it("returns true on stale-file removal then false", async () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "acs-i04-"));
    try {
      const outputPath = path.join(tmpDir, "agents.json");
      fs.writeFileSync(
        outputPath,
        JSON.stringify(
          {
            newhart: {
              model: "anthropic/claude-opus-4",
              heartbeat: { every: "30m" },
            },
          },
          null,
          2,
        ) + "\n",
        "utf-8",
      );

      const client = makeMockClient([makeHeartbeatRow(true)]);
      const first = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "retired",
      });
      assert.strictEqual(first, true);

      const second = await syncAgentsConfig(client, outputPath, {
        heartbeatCompatMode: "retired",
      });
      assert.strictEqual(second, false);
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

// ── Section 10: #819 no-default-marker interaction ──────────────────────────

describe("TC-824-D-01: retired mode composes with #819 no-default marker", () => {
  const row: AgentRow = {
    name: "newhart",
    model: "anthropic/claude-opus-4",
    fallback_models: null,
    thinking: null,
    instance_type: "peer",
    is_default: true,
    allowed_subagents: null,
    heartbeat_enabled: true,
    heartbeat_every: "30m",
    heartbeat_target: null,
    heartbeat_to: null,
    heartbeat_isolated_session: null,
  };
  const { entries } = buildAgentsList([row], { heartbeatCompatMode: "retired" });

  it("has no default key", () => {
    assert.ok(!Object.prototype.hasOwnProperty.call(entries["newhart"], "default"));
  });

  it("has no heartbeat key", () => {
    assert.ok(!Object.prototype.hasOwnProperty.call(entries["newhart"], "heartbeat"));
  });
});

describe("TC-824-D-02: retired mode keeps the rest of explicit ownership intact", () => {
  const config = buildExplicitOwnershipConfig(
    "newhart",
    [{ channel: "discord", accountId: "default" }],
    undefined,
    "retired",
  );

  it("keeps ownership and systemAgent", () => {
    assert.strictEqual(config.agents.ownership, "explicit");
    assert.strictEqual(config.agents.defaults.systemAgent.agentId, "newhart");
  });

  it("still emits bindings", () => {
    assert.strictEqual(config.bindings.length, 1);
    assert.strictEqual(config.bindings[0].agentId, "newhart");
  });

  it("omits heartbeat", () => {
    assert.ok(!Object.prototype.hasOwnProperty.call(config.agents.defaults, "heartbeat"));
  });
});
