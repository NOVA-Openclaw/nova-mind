import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildHonorificGuard } from "./honorific-guard.ts";

/**
 * Unit tests for buildHonorificGuard.
 *
 * Covers Gem's HG-001 through HG-027 design cases for nova-mind #421.
 */

describe("buildHonorificGuard", () => {
  // ── HG-001 to HG-006: core four states ───────────────────────────────────

  it("HG-001: non-I)ruid sender + nova → prohibition line with preferred name", () => {
    const result = buildHonorificGuard(7, "nova", "Zonk");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes('Do not use "Sir"'));
    assert.ok(result!.includes("Zonk"));
  });

  it("HG-002: non-I)ruid sender + non-nova → prohibition line regardless of agent", () => {
    const result = buildHonorificGuard(7, "graybeard", "Zonk");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes('Do not use "Sir"'));
    assert.ok(result!.includes("Zonk"));
    assert.ok(!result!.includes("NOVA"));
  });

  it("HG-003: I)ruid sender + non-nova → NOVA-exclusivity line", () => {
    const result = buildHonorificGuard(2, "graybeard", "I)ruid");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes("I)ruid"));
    assert.ok(result!.includes("NOVA"));
    assert.ok(result!.includes('"Sir"'));
    assert.ok(!result!.includes('Do not use "Sir"'));
  });

  it("HG-004: I)ruid sender + nova → no guard", () => {
    const result = buildHonorificGuard(2, "nova", "I)ruid");
    assert.equal(result, null);
  });

  it("HG-005: unresolved sender (null) + nova → prohibition fail-safe", () => {
    const result = buildHonorificGuard(null, "nova");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes('Do not use "Sir"'));
  });

  it("HG-006: unresolved sender (undefined) + nova → prohibition fail-safe", () => {
    const result = buildHonorificGuard(undefined, "nova");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes('Do not use "Sir"'));
  });

  // ── HG-007 to HG-010: missing/invalid agentId fail-closed ────────────────

  it("HG-007: I)ruid sender + undefined agentId → exclusivity line (fail closed)", () => {
    const result = buildHonorificGuard(2, undefined, "I)ruid");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes("I)ruid"));
    assert.ok(result!.includes("NOVA"));
  });

  it("HG-008: I)ruid sender + null agentId → exclusivity line (fail closed)", () => {
    const result = buildHonorificGuard(2, null, "I)ruid");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes("I)ruid"));
    assert.ok(result!.includes("NOVA"));
  });

  it("HG-009: I)ruid sender + empty agentId → exclusivity line (fail closed)", () => {
    const result = buildHonorificGuard(2, "", "I)ruid");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes("I)ruid"));
    assert.ok(result!.includes("NOVA"));
  });

  it("HG-010: non-I)ruid sender + undefined agentId → prohibition line", () => {
    const result = buildHonorificGuard(7, undefined, "Zonk");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes('Do not use "Sir"'));
    assert.ok(result!.includes("Zonk"));
  });

  // ── HG-011 to HG-013: case/whitespace exact-match boundaries ─────────────

  it("HG-011: agentId 'Nova' is treated as NOT nova (case-sensitive)", () => {
    const result = buildHonorificGuard(2, "Nova", "I)ruid");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes("NOVA"));
  });

  it("HG-012: agentId ' nova ' is treated as NOT nova (no trim)", () => {
    const result = buildHonorificGuard(2, " nova ", "I)ruid");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes("NOVA"));
  });

  it("HG-013: agentId exact lowercase 'nova' + entity 2 → no guard", () => {
    const result = buildHonorificGuard(2, "nova", "I)ruid");
    assert.equal(result, null);
  });

  // ── HG-014 to HG-019: preferredName variations ───────────────────────────

  it("HG-014: provided preferredName is referenced in prohibition line", () => {
    const result = buildHonorificGuard(7, "nova", "Edmund");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes("Edmund"));
  });

  it("HG-015: omitted preferredName falls back to pronoun language", () => {
    const result = buildHonorificGuard(7, "nova");
    assert.equal(typeof result, "string");
    assert.ok(!result!.includes("undefined"));
    assert.ok(!result!.includes("null"));
    assert.ok(result!.includes("this sender"));
  });

  it("HG-016: empty preferredName falls back to pronoun language", () => {
    const result = buildHonorificGuard(7, "nova", "");
    assert.equal(typeof result, "string");
    assert.ok(!result!.includes("undefined"));
    assert.ok(!result!.includes("null"));
    assert.ok(result!.includes("this sender"));
  });

  it("HG-017: preferredName does not cause emission for no-guard case", () => {
    const result = buildHonorificGuard(2, "nova", "I)ruid");
    assert.equal(result, null);
  });

  it("HG-018: exclusivity line refers to I)ruid literally, no preferredName interpolation", () => {
    const result = buildHonorificGuard(2, "graybeard", "I)ruid");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes("I)ruid"));
    assert.ok(!result!.includes("{{")); // sanity: no template artifacts
  });

  it("HG-019: preferredName with markdown-special characters does not throw", () => {
    assert.doesNotThrow(() => {
      const result = buildHonorificGuard(7, "nova", "Zo`nk*\n");
      assert.equal(typeof result, "string");
    });
  });

  // ── HG-020 to HG-023: entityId boundary values ───────────────────────────

  it("HG-020: entityId 0 is treated as non-I)ruid (prohibition)", () => {
    const result = buildHonorificGuard(0, "nova", "X");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes('Do not use "Sir"'));
  });

  it("HG-021: negative entityId is treated as non-I)ruid (prohibition)", () => {
    const result = buildHonorificGuard(-1, "nova", "X");
    assert.equal(typeof result, "string");
    assert.ok(result!.includes('Do not use "Sir"'));
  });

  it("HG-022: entityId 2.0 matches I)ruid (no guard with nova)", () => {
    const result = buildHonorificGuard(2.0, "nova", "I)ruid");
    assert.equal(result, null);
  });

  it("HG-023: entityId NaN is treated as non-I)ruid without throwing", () => {
    assert.doesNotThrow(() => {
      const result = buildHonorificGuard(NaN, "nova", "X");
      assert.equal(typeof result, "string");
      assert.ok(result!.includes('Do not use "Sir"'));
    });
  });

  // ── HG-024 to HG-027: contract / purity tests ────────────────────────────

  it("HG-024: guard-emitting paths return a string", () => {
    const cases = [
      buildHonorificGuard(7, "nova", "Zonk"),
      buildHonorificGuard(7, "graybeard", "Zonk"),
      buildHonorificGuard(2, "graybeard", "I)ruid"),
      buildHonorificGuard(null, "nova"),
    ];
    for (const r of cases) {
      assert.equal(typeof r, "string");
    }
  });

  it("HG-025: no-guard path returns strict null", () => {
    assert.equal(buildHonorificGuard(2, "nova"), null);
    assert.equal(buildHonorificGuard(2, "nova", "I)ruid"), null);
    assert.equal(buildHonorificGuard(2.0, "nova", "I)ruid"), null);
  });

  it("HG-026: emitted guard text is non-empty and trimmed", () => {
    const result = buildHonorificGuard(7, "nova", "Zonk");
    assert.ok(result != null);
    assert.ok(result!.trim().length > 0);
    assert.equal(result, result!.trim());
  });

  it("HG-027: function is pure — repeated calls with same inputs are identical", () => {
    const inputs: [number | null | undefined, string | null | undefined, string | undefined] = [
      7,
      "nova",
      "Zonk",
    ];
    const a = buildHonorificGuard(...inputs);
    const b = buildHonorificGuard(...inputs);
    assert.equal(a, b);
  });
});
