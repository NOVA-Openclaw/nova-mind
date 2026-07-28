import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "fs";
import * as os from "os";
import { join } from "path";
import {
  formatEntityContext,
  resolveEntityContext,
  resolveEntityForGuard,
  setEntityResolverPathForTest,
  type SenderInfo,
} from "./entity-resolver.ts";

/**
 * Unit tests for the entity-resolver subsystem in turn-context.
 *
 * Covers Gem's RS-001 through RS-062 design cases for nova-mind #543.
 */

// ── Fixtures ────────────────────────────────────────────────────────────────

const baseEntity = {
  id: 1,
  name: "Tabatha Janell Wilson",
  fullName: "Tabatha Janell Wilson",
  type: "person",
};

const richProfile = {
  facts: { timezone: "America/Chicago" },
  stats: {
    factCount: 48,
    lastMessage: {
      timestamp: "2026-07-27 02:11 UTC",
      ref: "discord:1513392492651872306",
    },
  },
};

// ── Formatting matrix (pure function, no DB) ────────────────────────────────

describe("formatEntityContext", () => {
  it("RS-001: pronouns present → rendered in parenthetical after display name", () => {
    const result = formatEntityContext(
      { ...baseEntity, pronouns: "she/her" },
      { facts: {}, stats: { factCount: 0, lastMessage: null } }
    );
    const lines = result.split("\n");
    assert.equal(lines[0], "👤 **Talking with:** Tabatha Janell Wilson (she/her)");
  });

  it("RS-002: pronouns present + trust_level present → trailing trust suffix", () => {
    const result = formatEntityContext(
      { ...baseEntity, pronouns: "she/her", trustLevel: "friend" },
      { facts: {}, stats: { factCount: 0, lastMessage: null } }
    );
    const lines = result.split("\n");
    assert.equal(
      lines[0],
      "👤 **Talking with:** Tabatha Janell Wilson (she/her) — trust: friend"
    );
  });

  it("RS-003: full stats line renders all data points in documented order", () => {
    const result = formatEntityContext(
      { ...baseEntity, pronouns: "she/her", trustLevel: "friend", createdAt: "2026-01-30" },
      richProfile
    );
    const lines = result.split("\n");
    assert.equal(lines[0], "👤 **Talking with:** Tabatha Janell Wilson (she/her) — trust: friend");
    assert.equal(
      lines[1],
      "📊 Known contact: 48 facts · first seen 2026-01-30 · last message 2026-07-27 02:11 UTC (discord:1513392492651872306)"
    );
  });

  it("RS-004: existing fact-key bullet list still renders below the stats line", () => {
    const result = formatEntityContext(
      { ...baseEntity, createdAt: "2026-01-30" },
      richProfile
    );
    assert.ok(result.includes("📊 Known contact:"));
    assert.ok(result.includes("• **Timezone:** America/Chicago"));
    const statsIdx = result.indexOf("📊 Known contact:");
    const bulletIdx = result.indexOf("• **Timezone:**");
    assert.ok(statsIdx < bulletIdx, "stats line must appear before fact bullets");
  });

  it("RS-010: NULL pronouns → no parenthetical, graceful degradation", () => {
    const result = formatEntityContext(
      baseEntity,
      { facts: {}, stats: { factCount: 0, lastMessage: null } }
    );
    assert.equal(result, "👤 **Talking with:** Tabatha Janell Wilson");
    assert.ok(!result.includes("null"));
    assert.ok(!result.includes("undefined"));
    assert.ok(!result.includes("()"));
  });

  it("RS-011: NULL or 'unknown' trust_level → no trust suffix", () => {
    for (const trustLevel of [null, undefined, "unknown"]) {
      const result = formatEntityContext(
        { ...baseEntity, trustLevel },
        { facts: {}, stats: { factCount: 0, lastMessage: null } }
      );
      assert.ok(!result.includes(" — trust:"), `failed for trustLevel=${String(trustLevel)}`);
      assert.ok(!result.includes("trust: unknown"), `failed for trustLevel=${String(trustLevel)}`);
    }
  });

  it("RS-012: zero entity_facts still renders stats line", () => {
    const result = formatEntityContext(
      { ...baseEntity, createdAt: "2026-01-30" },
      { facts: {}, stats: { factCount: 0, lastMessage: null } }
    );
    assert.ok(result.includes("📊 Known contact:"));
    assert.ok(result.includes("0 facts"));
  });

  it("RS-013: no channel_transcripts rows → last message segment omitted cleanly", () => {
    const result = formatEntityContext(
      { ...baseEntity, createdAt: "2026-01-30" },
      { facts: {}, stats: { factCount: 48, lastMessage: null } }
    );
    assert.ok(result.includes("48 facts"));
    assert.ok(result.includes("first seen 2026-01-30"));
    assert.ok(!result.includes("last message"));
    assert.ok(!result.includes("null"));
    assert.ok(!result.includes("undefined"));
    // No dangling separator after first-seen
    assert.ok(!result.includes("first seen 2026-01-30 ·"));
  });

  it("RS-014: brand-new entity renders sparse/degenerate form without leaked nulls", () => {
    const result = formatEntityContext(
      { id: 2, name: "New User", type: "person", createdAt: "2026-07-28" },
      { facts: {}, stats: { factCount: 0, lastMessage: null } }
    );
    assert.equal(result, "👤 **Talking with:** New User\n📊 Known contact: 0 facts · first seen 2026-07-28");
    assert.ok(!result.includes("null"));
    assert.ok(!result.includes("undefined"));
  });

  it("RS-015: last_seen fallback renders only when no transcript row exists", () => {
    const withLastMessage = formatEntityContext(
      { ...baseEntity, lastSeen: "2026-07-26 08:00 UTC", createdAt: "2026-01-30" },
      { facts: {}, stats: { factCount: 48, lastMessage: richProfile.stats.lastMessage } }
    );
    assert.ok(withLastMessage.includes("last message"));
    assert.ok(!withLastMessage.includes("last seen"));

    const withoutLastMessage = formatEntityContext(
      { ...baseEntity, lastSeen: "2026-07-26 08:00 UTC", createdAt: "2026-01-30" },
      { facts: {}, stats: { factCount: 48, lastMessage: null } }
    );
    assert.ok(!withoutLastMessage.includes("last message"));
    assert.ok(withoutLastMessage.includes("last seen 2026-07-26 08:00 UTC"));
  });

  it("RS-060: exactly 1 fact uses correct singular form", () => {
    const result = formatEntityContext(
      { ...baseEntity, createdAt: "2026-01-30" },
      { facts: {}, stats: { factCount: 1, lastMessage: null } }
    );
    assert.ok(result.includes("1 fact"));
    assert.ok(!result.includes("1 facts"));
  });

  it("RS-061: trust_level renders arbitrary non-empty string; 'unknown' suppressed", () => {
    const values: Array<[string, boolean]> = [
      ["owner", true],
      ["admin", true],
      ["user", true],
      ["unknown", false],
      ["untrusted", true],
      ["friend", true],
    ];
    for (const [trustLevel, shouldRender] of values) {
      const result = formatEntityContext(
        { ...baseEntity, trustLevel },
        { facts: {}, stats: { factCount: 0, lastMessage: null } }
      );
      const rendered = result.includes(` — trust: ${trustLevel}`);
      assert.equal(rendered, shouldRender, `trustLevel=${trustLevel}`);
    }
  });

  it("RS-062: timestamp formatting is stable and explicit (string inputs)", () => {
    const result = formatEntityContext(
      { ...baseEntity, createdAt: "2026-01-30", lastSeen: "2026-07-27 02:11 UTC" },
      {
        facts: {},
        stats: {
          factCount: 1,
          lastMessage: { timestamp: "2026-07-27 02:11 UTC", ref: "discord:1" },
        },
      }
    );
    assert.ok(result.includes("first seen 2026-01-30"));
    assert.ok(result.includes("last message 2026-07-27 02:11 UTC"));
  });
});

// ── Orchestration tests with mocked entity-resolver module ───────────────────

function writeFixture(source: string): { path: string; restore: () => void } {
  const tmpDir = fs.mkdtempSync(join(os.tmpdir(), "turn-context-ertest-"));
  const fixturePath = join(tmpDir, "mock-entity-resolver.ts");
  fs.writeFileSync(fixturePath, source);
  const restorePath = setEntityResolverPathForTest(fixturePath);
  return {
    path: fixturePath,
    restore: () => {
      restorePath();
      try {
        fs.unlinkSync(fixturePath);
        fs.rmdirSync(tmpDir);
      } catch {}
    },
  };
}

const resolvedTabathaFixture = `
export const resolveEntityByIdentifiers = async () => ({
  ok: true,
  entity: {
    id: 42,
    name: "Tabatha Janell Wilson",
    fullName: "Tabatha Janell Wilson",
    type: "person",
    pronouns: "she/her",
    trustLevel: "friend",
    createdAt: "2026-01-30",
  },
  facts: [],
});
export const getCachedEntity = () => null;
export const setCachedEntity = () => {};
`;

const resolvedNewUserFixture = `
export const resolveEntityByIdentifiers = async () => ({
  ok: true,
  entity: {
    id: 99,
    name: "New User",
    type: "person",
    createdAt: "2026-07-28",
  },
  facts: [],
});
export const getCachedEntity = () => null;
export const setCachedEntity = () => {};
`;

describe("resolveEntityContext orchestration", () => {
  it("RS-030: stats query timeout → graceful degradation, pronouns survive", async () => {
    const { restore } = writeFixture(
      resolvedTabathaFixture +
      `export const getEntityProfile = async () => new Promise(() => {});`
    );

    try {
      const result = await resolveEntityContext("session-1", {
        senderId: "123",
        provider: "discord",
      });
      assert.ok(result.text);
      assert.ok(result.text.includes("Tabatha Janell Wilson (she/her)"));
      // Stats degraded to entity-derived first-seen only; no last-message clause
      assert.ok(result.text.includes("📊 Known contact:"));
      assert.ok(result.text.includes("first seen 2026-01-30"));
      assert.ok(!result.text.includes("last message"));
      assert.equal(result.entityId, 42);
    } finally {
      restore();
    }
  });

  it("RS-031: stats query connection error → caught, base info returned", async () => {
    const errors: string[] = [];
    const originalError = console.error;
    console.error = (...args: unknown[]) => {
      errors.push(args.map(String).join(" "));
    };

    const { restore } = writeFixture(
      resolvedTabathaFixture +
      `export const getEntityProfile = async () => { throw new Error("ECONNREFUSED"); };`
    );

    try {
      const result = await resolveEntityContext("session-2", {
        senderId: "123",
        provider: "discord",
      });
      assert.ok(result.text);
      assert.ok(result.text.includes("Tabatha Janell Wilson"));
      assert.ok(errors.some((e) => e.includes("ECONNREFUSED")));
    } finally {
      restore();
      console.error = originalError;
    }
  });

  it("RS-032: stats query SQL error → logged distinctly, graceful degradation", async () => {
    const errors: string[] = [];
    const originalError = console.error;
    console.error = (...args: unknown[]) => {
      errors.push(args.map(String).join(" "));
    };

    const { restore } = writeFixture(
      resolvedTabathaFixture +
      `export const getEntityProfile = async () => { const e = new Error("column lm.timestamp does not exist"); e.code = "42703"; throw e; };`
    );

    try {
      const result = await resolveEntityContext("session-3", {
        senderId: "123",
        provider: "discord",
      });
      assert.ok(result.text);
      assert.ok(result.text.includes("Tabatha Janell Wilson"));
      assert.ok(errors.some((e) => e.includes("42703") || e.includes("column lm.timestamp")));
    } finally {
      restore();
      console.error = originalError;
    }
  });
});

describe("resolveEntityForGuard non-regression", () => {
  it("RS-042: guard path does NOT trigger stats query", async () => {
    let profileCalls = 0;
    const { restore } = writeFixture(
      resolvedNewUserFixture +
      `export const getEntityProfile = async () => { globalThis.__profileCalls = (globalThis.__profileCalls || 0) + 1; return { facts: {}, stats: { factCount: 0, lastMessage: null } }; };`
    );

    try {
      const result = await resolveEntityForGuard("guard-session", {
        senderId: "456",
        provider: "discord",
      });
      assert.equal(result.entityId, 99);
      assert.equal(result.displayName, "New User");
      assert.equal(profileCalls, 0, "getEntityProfile must not be called for guard path");
    } finally {
      restore();
    }
  });
});
