import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { buildPromptResult, resolvePlacement } from "./index.ts";
import {
  extractIdentifiers,
  resolveIrcHostFromConfig,
  setIrcConfigPathForTest,
} from "./entity-resolver.ts";
import * as fs from "fs";
import * as os from "os";
import { join } from "path";

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

describe("extractIdentifiers (IRC support #522)", () => {
  it("TC-522-014: bare nick + host with irc. prefix → composite identifier", () => {
    assert.deepEqual(
      extractIdentifiers("irc", "Druidian", undefined, { host: "irc.late.sh" }),
      { ircUsername: "late.sh/druidian" }
    );
  });

  it("TC-522-015: nick!user@host senderId form extracts nick correctly", () => {
    assert.deepEqual(
      extractIdentifiers("irc", "Druidian!~user@example.com", undefined, { host: "irc.late.sh" }),
      { ircUsername: "late.sh/druidian" }
    );
  });

  it("TC-522-016: missing host and no config match → graceful skip, not crash", () => {
    const configPath = join(os.tmpdir(), `turn-context-test-empty-${Date.now()}.json`);
    const restore = setIrcConfigPathForTest(configPath);
    fs.writeFileSync(configPath, JSON.stringify({ channels: {} }));
    try {
      assert.deepEqual(extractIdentifiers("irc", "Druidian"), {});
      assert.deepEqual(extractIdentifiers("irc", "Druidian", undefined, { host: undefined }), {});
    } finally {
      restore();
      fs.unlinkSync(configPath);
    }
  });

  it("TC-522-017: empty/whitespace nick after parsing → skip", () => {
    assert.deepEqual(
      extractIdentifiers("irc", "!user@host", undefined, { host: "irc.late.sh" }),
      {}
    );
  });

  it("TC-522-018: nick with IRC-legal special chars round-trips lowercased", () => {
    assert.deepEqual(
      extractIdentifiers("irc", "Dru-idian[bot]", undefined, { host: "irc.late.sh" }),
      { ircUsername: "late.sh/dru-idian[bot]" }
    );
  });

  it("TC-522-032: network derivation lowercases host before stripping irc. prefix", () => {
    assert.deepEqual(
      extractIdentifiers("irc", "Druidian", undefined, { host: "IRC.Late.SH" }),
      { ircUsername: "late.sh/druidian" }
    );
  });

  it("TC-522-033: network derivation strips irc- (hyphen) prefix", () => {
    assert.deepEqual(
      extractIdentifiers("irc", "Druidian", undefined, { host: "irc-late.sh" }),
      { ircUsername: "late.sh/druidian" }
    );
  });

  it("TC-522-034: network derivation falls back to full lowercased host", () => {
    assert.deepEqual(
      extractIdentifiers("irc", "Druidian", undefined, { host: "chat.freenode.net" }),
      { ircUsername: "chat.freenode.net/druidian" }
    );
  });

  it("TC-522-035: prefix-only host yields empty network → graceful skip", () => {
    assert.deepEqual(
      extractIdentifiers("irc", "Druidian", undefined, { host: "irc." }),
      {}
    );
  });

  it("TC-522-019: regression — discord path unchanged", () => {
    assert.deepEqual(extractIdentifiers("discord", "123456789"), { discordId: "123456789" });
  });

  it("TC-522-020: regression — telegram path unchanged", () => {
    assert.deepEqual(extractIdentifiers("telegram", "987654"), { telegramId: "987654" });
  });

  it("TC-522-021: regression — slack path unchanged", () => {
    assert.deepEqual(extractIdentifiers("slack", "U183XNADU"), { slackMemberId: "U183XNADU" });
  });

  it("TC-522-022: regression — signal path unchanged (uuid + optional e164)", () => {
    assert.deepEqual(
      extractIdentifiers("signal", "uuid-1234", "+15551234567"),
      { signalUuid: "uuid-1234", phone: "+15551234567" }
    );
  });

  it("TC-522-023: regression — unknown provider still returns {}", () => {
    assert.deepEqual(extractIdentifiers("mattermost", "someid"), {});
  });

  it("TC-522-024: regression note — device provider gap remains out of scope", () => {
    // deviceId exists in EntityIdentifiers/IDENTIFIER_TO_DB_KEY but has no
    // extractIdentifiers case today. #522 must not widen the default match.
    assert.deepEqual(extractIdentifiers("device", "some-device-id"), {});
  });

  it("TC-522-036: host resolved from OpenClaw config when accountId provided and metadata host absent", () => {
    const configPath = join(os.tmpdir(), `turn-context-test-openclaw-${Date.now()}.json`);
    const originalPath = join(os.homedir(), ".openclaw", "openclaw.json");

    const testConfig = {
      channels: {
        irc: {
          host: "irc.late.sh",
          accounts: {
            default: { host: "irc.late.sh" },
            secondary: { host: "irc.libera.chat" },
          },
        },
      },
    };

    // Point resolver at temp config
    fs.writeFileSync(configPath, JSON.stringify(testConfig));
    const restore = setIrcConfigPathForTest(configPath);

    try {
      // default account -> top-level host
      assert.deepEqual(
        extractIdentifiers("irc", "Druidian", undefined, { accountId: "default" }),
        { ircUsername: "late.sh/druidian" }
      );

      // secondary account -> account-specific host
      assert.deepEqual(
        extractIdentifiers("irc", "Druidian", undefined, { accountId: "secondary" }),
        { ircUsername: "libera.chat/druidian" }
      );
    } finally {
      restore();
      fs.unlinkSync(configPath);
    }
  });
});
