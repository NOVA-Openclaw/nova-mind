import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildPromptResult, resolvePlacement } from "./index.ts";

/**
 * Unit tests for the placement-aware prompt assembly in turn-context.
 *
 * These tests cover nova-mind #439: the dynamic entity/domain/recall block
 * must land under a different return key depending on the configured
 * placement, while turn reminders + honorific guard remain in
 * appendSystemContext.
 */

describe("buildPromptResult", () => {
  const dynamicSegments = [
    "👤 **Talking with:** Zonk",
    "🏷️ Domain: coding → coder (keyword, 75%)",
    "🧠 **Relevant Context:**\n📝 [memory] (65%): likes typescript",
  ];

  const appendSegments = [
    "📌 **Per-Turn Reminders:**\nBe concise.",
    'Do not use "Sir", "Ma\'am", or other formal honorifics — address Zonk by name or with normal conversational pronouns.',
  ];

  it("TC-439-001: default system-prepend places dynamic block in prependSystemContext", () => {
    const result = buildPromptResult("system-prepend", dynamicSegments, appendSegments);

    assert.ok(result.prependSystemContext, "expected prependSystemContext to be set");
    assert.equal(result.prependSystemContext, dynamicSegments.join("\n\n"));
    assert.ok(result.appendSystemContext, "expected appendSystemContext to be set");
    assert.equal(result.appendSystemContext, appendSegments.join("\n\n"));
    assert.equal(result.prependContext, undefined);
    assert.equal(result.appendContext, undefined);
  });

  it("TC-439-002: turn-prepend places dynamic block in prependContext", () => {
    const result = buildPromptResult("turn-prepend", dynamicSegments, appendSegments);

    assert.ok(result.prependContext, "expected prependContext to be set");
    assert.equal(result.prependContext, dynamicSegments.join("\n\n"));
    assert.ok(result.appendSystemContext, "expected appendSystemContext to be set");
    assert.equal(result.appendSystemContext, appendSegments.join("\n\n"));
    assert.equal(result.prependSystemContext, undefined);
    assert.equal(result.appendContext, undefined);
  });

  it("TC-439-003: turn-prepend keeps appendSystemContext unchanged (reminders + guard)", () => {
    const result = buildPromptResult("turn-prepend", dynamicSegments, appendSegments);

    assert.ok(result.appendSystemContext?.includes("Per-Turn Reminders"));
    assert.ok(result.appendSystemContext?.includes('Do not use "Sir"'));
  });

  it("TC-439-004: empty dynamic segments omit the prepend key entirely", () => {
    const result = buildPromptResult("turn-prepend", [], appendSegments);

    assert.equal(result.prependContext, undefined);
    assert.equal(result.prependSystemContext, undefined);
    assert.ok(result.appendSystemContext);
  });

  it("TC-439-005: empty append segments omit appendSystemContext", () => {
    const result = buildPromptResult("system-prepend", dynamicSegments, []);

    assert.ok(result.prependSystemContext);
    assert.equal(result.appendSystemContext, undefined);
  });

  it("TC-439-006: both empty returns empty result", () => {
    const result = buildPromptResult("turn-prepend", [], []);

    assert.deepEqual(result, {});
  });
});

describe("resolvePlacement", () => {
  it("TC-439-007: undefined config defaults to system-prepend", () => {
    assert.equal(resolvePlacement(undefined), "system-prepend");
  });

  it("TC-439-008: empty object defaults to system-prepend", () => {
    assert.equal(resolvePlacement({}), "system-prepend");
  });

  it("TC-439-009: bogus placement string falls back to system-prepend", () => {
    assert.equal(resolvePlacement({ placement: "bogus" }), "system-prepend");
  });

  it("TC-439-010: non-string placement (number) falls back to system-prepend", () => {
    assert.equal(resolvePlacement({ placement: 123 }), "system-prepend");
  });

  it("TC-439-011: explicit turn-prepend is accepted", () => {
    assert.equal(resolvePlacement({ placement: "turn-prepend" }), "turn-prepend");
  });

  it("TC-439-012: explicit system-prepend is accepted", () => {
    assert.equal(resolvePlacement({ placement: "system-prepend" }), "system-prepend");
  });
});
