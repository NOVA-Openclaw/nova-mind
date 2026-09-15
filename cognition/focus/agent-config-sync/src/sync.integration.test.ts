/**
 * Integration tests for the config→runtime consumer seam of nova-mind#660.
 *
 * TC-660-I-01  Generated thinkingDefault survives AgentEntrySchema validation (not available in runtime build)
 * TC-660-I-02  Per-agent thinkingDefault overrides global default at resolution seam
 * TC-660-I-03  Null/absent thinking row still inherits global default
 * TC-660-I-04  Multi-agent fleet: distinct per-agent tiers, neither contaminated by global
 *
 * These tests exercise the actual nova-openclaw resolution seam:
 *   - resolveAgentConfig()   from /home/nova/nova-openclaw-production/dist/agent-scope-config-BxAUeF6t.js
 *   - normalizeThinkLevel()  from /home/nova/nova-openclaw-production/dist/thinking.shared-BWnbgBUO.js
 *
 * The import paths are the hashed dist chunk names because the package does not
 * export these internal modules through package.json "exports". The modules are
 * loaded directly from the checked-in production build on the host.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { buildAgentsList } from "./sync.js";
import type { AgentRow } from "./sync.js";

// ── Direct imports from the nova-openclaw production build ──────────────────

import {
  r as resolveAgentConfig,
  t as listAgentEntries,
} from "/home/nova/nova-openclaw-production/dist/agent-scope-config-BxAUeF6t.js";
import { s as normalizeThinkLevel } from "/home/nova/nova-openclaw-production/dist/thinking.shared-BWnbgBUO.js";

// ── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Resolve the effective thinking level for an agent id through the real
 * consumer seam used at get-reply-directives.ts:450-451:
 *   normalizeThinkLevel(agentEntry?.thinkingDefault) ?? normalizeThinkLevel(agentCfg?.thinkingDefault)
 */
function resolveEffectiveThinking(
  cfg: { agents?: { defaults?: { thinkingDefault?: string }; list?: unknown[] } },
  agentId: string,
): string | undefined {
  const agentEntry = resolveAgentConfig(cfg as never, agentId);
  const agentCfg = cfg.agents?.defaults;
  return (
    normalizeThinkLevel(agentEntry?.thinkingDefault) ??
    normalizeThinkLevel(agentCfg?.thinkingDefault)
  );
}

function makeAgentRow(name: string, thinking: string | null): AgentRow {
  return {
    name,
    model: "anthropic/claude-sonnet-4",
    fallback_models: null,
    thinking,
    instance_type: "subagent",
    is_default: false,
    allowed_subagents: null,
  };
}

function buildConfig(rows: AgentRow[], globalDefault?: string) {
  const list = buildAgentsList(rows);
  return {
    agents: {
      defaults: globalDefault ? { thinkingDefault: globalDefault } : {},
      list,
    },
  };
}

// ── TC-660-I-02: Per-agent thinkingDefault overrides global default ─────────

describe("TC-660-I-02: Per-agent thinkingDefault overrides global default at runtime seam", () => {
  it("agent with thinking='off' resolves to 'off' even when global default is 'high'", () => {
    const cfg = buildConfig([makeAgentRow("bastion", "off")], "high");
    assert.strictEqual(resolveEffectiveThinking(cfg, "bastion"), "off");
  });

  it("agent with thinking='xhigh' resolves to 'xhigh' even when global default is 'medium'", () => {
    const cfg = buildConfig([makeAgentRow("ember", "xhigh")], "medium");
    assert.strictEqual(resolveEffectiveThinking(cfg, "ember"), "xhigh");
  });
});

// ── TC-660-I-03: Null/absent thinking still inherits global default ─────────

describe("TC-660-I-03: Null/absent thinking row inherits global default", () => {
  it("agent with thinking=null inherits global 'high'", () => {
    const cfg = buildConfig([makeAgentRow("scout", null)], "high");
    assert.strictEqual(resolveEffectiveThinking(cfg, "scout"), "high");
  });

  it("agent with thinking=null inherits global 'off'", () => {
    const cfg = buildConfig([makeAgentRow("gem", null)], "off");
    assert.strictEqual(resolveEffectiveThinking(cfg, "gem"), "off");
  });
});

// ── TC-660-I-04: Multi-agent fleet with distinct per-agent tiers ────────────

describe("TC-660-I-04: Multi-agent fleet with distinct per-agent tiers", () => {
  const cfg = buildConfig(
    [
      makeAgentRow("agentA", "low"),
      makeAgentRow("agentB", "xhigh"),
      makeAgentRow("agentC", null),
    ],
    "medium",
  );

  it("agentA resolves to its own 'low'", () => {
    assert.strictEqual(resolveEffectiveThinking(cfg, "agentA"), "low");
  });

  it("agentB resolves to its own 'xhigh'", () => {
    assert.strictEqual(resolveEffectiveThinking(cfg, "agentB"), "xhigh");
  });

  it("agentC inherits the global 'medium'", () => {
    assert.strictEqual(resolveEffectiveThinking(cfg, "agentC"), "medium");
  });
});

// ── TC-660-I-01: Generated output is consumable by listAgentEntries ─────────

describe("TC-660-I-01: Generated thinkingDefault entry survives listAgentEntries / resolveAgentConfig", () => {
  it("post-fix buildAgentsList output yields an entry with thinkingDefault='off' via resolveAgentConfig", () => {
    const cfg = buildConfig([makeAgentRow("bastion", "off")], "high");
    const entries = listAgentEntries(cfg as never);
    const entry = entries.find((e) => e.id === "bastion");
    assert.ok(entry !== undefined, "bastion must be listed");
    assert.strictEqual(entry.thinkingDefault, "off");
  });

  it("resolveAgentConfig surfaces the generated thinkingDefault", () => {
    const cfg = buildConfig([makeAgentRow("newhart", "high")], "medium");
    const resolved = resolveAgentConfig(cfg as never, "newhart");
    assert.ok(resolved !== undefined);
    assert.strictEqual(resolved.thinkingDefault, "high");
  });
});
