/**
 * Integration tests for the config→runtime consumer seam of nova-mind#660.
 *
 * TC-660-I-01  Generated thinkingDefault survives listAgentEntries / resolveAgentConfig
 * TC-660-I-02  Per-agent thinkingDefault overrides global default at resolution seam
 * TC-660-I-03  Null/absent thinking row still inherits global default
 * TC-660-I-04  Multi-agent fleet: distinct per-agent tiers, neither contaminated by global
 *
 * These tests exercise the actual nova-openclaw resolution seam when the
 * nova-openclaw dist is available on the runner:
 *   - resolveAgentConfig()  from dist/agent-scope-config-<hash>.js
 *   - normalizeThinkLevel() from dist/thinking.shared-<hash>.js
 *   - listAgentEntries()    from dist/agent-scope-config-<hash>.js
 *
 * Import path portability (nova-mind#669):
 *   - Base directory is set via NOVA_OPENCLAW_DIST env var, falling back to
 *     /home/nova/nova-openclaw-production/dist if present, then /opt/openclaw/dist.
 *   - Hashed chunk filenames are resolved at runtime by globbing dist/.
 *   - If the seam cannot be loaded, the integration suite SKIPS with a clear
 *     message instead of failing or silently passing.
 */

import { describe, it, skip } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

import { buildAgentsList } from "./sync.js";
import type { AgentRow } from "./sync.js";

// ── Discover the nova-openclaw dist seam at runtime ─────────────────────────

function findOpenClawDist(): string | undefined {
  const envPath = process.env.NOVA_OPENCLAW_DIST;
  if (envPath && fs.existsSync(envPath)) return envPath;

  const candidates = [
    "/home/nova/nova-openclaw-production/dist",
    "/opt/openclaw/dist",
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return undefined;
}

function globChunk(distDir: string, prefix: string): string | undefined {
  try {
    const entries = fs.readdirSync(distDir);
    const match = entries.find(
      (e) => e.startsWith(prefix) && e.endsWith(".js"),
    );
    return match ? path.join(distDir, match) : undefined;
  } catch {
    return undefined;
  }
}

const distDir = findOpenClawDist();
const agentScopePath = distDir
  ? globChunk(distDir, "agent-scope-config-")
  : undefined;
const thinkingSharedPath = distDir
  ? globChunk(distDir, "thinking.shared-")
  : undefined;

let seamAvailable = false;
let resolveAgentConfig: (cfg: unknown, agentId: string) => { thinkingDefault?: string } | undefined;
let listAgentEntries: (cfg: unknown) => Array<{ id: string; thinkingDefault?: string }>;
let normalizeThinkLevel: (raw?: string | null) => string | undefined;

try {
  if (!agentScopePath || !thinkingSharedPath) {
    throw new Error(
      `nova-openclaw dist seam not found in ${distDir ?? "any candidate path"}`,
    );
  }

  const agentScope = await import(agentScopePath);
  const thinkingShared = await import(thinkingSharedPath);

  resolveAgentConfig = agentScope.r;
  listAgentEntries = agentScope.t;
  normalizeThinkLevel = thinkingShared.s;

  if (
    typeof resolveAgentConfig !== "function" ||
    typeof listAgentEntries !== "function" ||
    typeof normalizeThinkLevel !== "function"
  ) {
    throw new Error("loaded seam modules but expected exports are missing");
  }

  seamAvailable = true;
} catch (err) {
  const reason = err instanceof Error ? err.message : String(err);
  console.log(
    `[TC-660-I SKIP] Cannot load nova-openclaw runtime seam: ${reason}`,
  );
}

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

// ── Conditional describe helper ─────────────────────────────────────────────

function describeIfSeam(label: string, fn: () => void) {
  if (!seamAvailable) {
    describe(`${label} [SKIP: nova-openclaw seam unavailable]`, () => {
      it("skipped — nova-openclaw runtime seam is not available", () => {
        skip("nova-openclaw runtime seam unavailable on this runner");
      });
    });
    return;
  }
  describe(label, fn);
}

// ── TC-660-I-02: Per-agent thinkingDefault overrides global default ─────────

describeIfSeam(
  "TC-660-I-02: Per-agent thinkingDefault overrides global default at runtime seam",
  () => {
    it("agent with thinking='off' resolves to 'off' even when global default is 'high'", () => {
      const cfg = buildConfig([makeAgentRow("bastion", "off")], "high");
      assert.strictEqual(resolveEffectiveThinking(cfg, "bastion"), "off");
    });

    it("agent with thinking='xhigh' resolves to 'xhigh' even when global default is 'medium'", () => {
      const cfg = buildConfig([makeAgentRow("ember", "xhigh")], "medium");
      assert.strictEqual(resolveEffectiveThinking(cfg, "ember"), "xhigh");
    });
  },
);

// ── TC-660-I-03: Null/absent thinking still inherits global default ─────────

describeIfSeam(
  "TC-660-I-03: Null/absent thinking row inherits global default",
  () => {
    it("agent with thinking=null inherits global 'high'", () => {
      const cfg = buildConfig([makeAgentRow("scout", null)], "high");
      assert.strictEqual(resolveEffectiveThinking(cfg, "scout"), "high");
    });

    it("agent with thinking=null inherits global 'off'", () => {
      const cfg = buildConfig([makeAgentRow("gem", null)], "off");
      assert.strictEqual(resolveEffectiveThinking(cfg, "gem"), "off");
    });
  },
);

// ── TC-660-I-04: Multi-agent fleet with distinct per-agent tiers ────────────

describeIfSeam(
  "TC-660-I-04: Multi-agent fleet with distinct per-agent tiers",
  () => {
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
  },
);

// ── TC-660-I-01: Generated output is consumable by listAgentEntries ─────────

describeIfSeam(
  "TC-660-I-01: Generated thinkingDefault entry survives listAgentEntries / resolveAgentConfig",
  () => {
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
  },
);
