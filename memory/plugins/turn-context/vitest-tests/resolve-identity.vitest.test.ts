import { describe, it, expect } from "vitest";
import * as fs from "fs";
import * as os from "os";
import { join } from "path";
import { resolveSenderInfoFromCtx, type ResolvedIdentity } from "../src/index.ts";
import { resolveEntityContext, setEntityResolverPathForTest } from "../src/entity-resolver.ts";

/**
 * Unit tests for #712 sender identity resolution from before_prompt_build ctx.
 *
 * Covers the local, fixture-driven cases from tests/TEST-CASES-ISSUE-712.md.
 * Staging-only cases (TC-INT-001) and cases requiring a live entity resolver
 * are deferred to step 7.
 *
 * Fixture-value derivations:
 * - channel values "discord"/"telegram" are canonical providers used by
 *   extractIdentifiers() (entity-resolver.ts switch statement).
 * - chatId 123456789 is the numeric-typed example from TC-712-007.
 * - senderId 330189773371080716 is the numeric Discord snowflake example from
 *   TC-712-008 and the known Discord id from TC-712-003 (mapped to entity_id 2
 *   by the mocked entity-resolver library below).
 * - currentUserMessage / prompt are the documented fields of
 *   PluginHookBeforePromptBuildEvent in the OpenClaw 2026.9.6 host contract.
 */

function makeApi(): any {
  return { pluginConfig: {}, config: {} };
}

function resolveFor(
  event: Record<string, unknown>,
  ctx: Record<string, unknown>
): ResolvedIdentity {
  return resolveSenderInfoFromCtx(event as any, ctx as any, makeApi());
}

/**
 * Write a mock entity-resolver module to disk and point the test seam at it.
 * Returns the fixture path and a restore function.
 */
function writeFixture(source: string): { path: string; restore: () => void } {
  const tmpDir = fs.mkdtempSync(join(os.tmpdir(), "turn-context-712-003-"));
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

const discordIdentifierFixture = `
export const resolveEntityByIdentifiers = async (identifiers) => {
  if (identifiers.discordId === "330189773371080716") {
    return {
      ok: true,
      entity: {
        id: 2,
        name: "I)ruid",
        fullName: "I)ruid",
        type: "person",
      },
    };
  }
  return { ok: true, entity: null };
};
export const getCachedEntity = () => null;
export const setCachedEntity = () => {};
export const getEntityProfile = async () => ({ facts: {}, stats: { factCount: 0, lastMessage: null } });
`;

describe("resolveSenderInfoFromCtx (#712)", () => {
  it("TC-712-006: senderId undefined warns but returns identity and content", () => {
    const result = resolveFor(
      { currentUserMessage: "hello" },
      { channel: "discord", chatId: "1513392492651872306" }
    );

    expect(result.warnings).toEqual(
      expect.arrayContaining([
        expect.stringContaining("senderId"),
      ])
    );
    expect(result.senderInfo.provider).toBe("discord");
    expect(result.senderInfo.senderId).toBeUndefined();
    expect(result.content).toBe("hello");
  });

  it("TC-712-007: chatId as number logs a type warning and is not used as a key", () => {
    const result = resolveFor(
      { currentUserMessage: "hello" },
      {
        channel: "telegram",
        senderId: "12345",
        // Numeric chatId is the wrong-type fixture required by TC-712-007.
        chatId: 123456789 as any,
      }
    );

    expect(result.warnings).toEqual(
      expect.arrayContaining([
        expect.stringMatching(/chatId has wrong type.*number/),
      ])
    );

    expect(result.senderInfo.senderId).toBe("12345");
    expect(result.content).toBe("hello");
  });

  it("TC-712-008: senderId as number logs a type warning and degrades gracefully", () => {
    const result = resolveFor(
      { currentUserMessage: "hello" },
      {
        channel: "discord",
        // Numeric Discord snowflake is the wrong-type fixture required by TC-712-008.
        senderId: 330189773371080716 as any,
      }
    );

    expect(result.warnings).toEqual(
      expect.arrayContaining([
        expect.stringMatching(/senderId has wrong type.*number/),
      ])
    );
    expect(result.senderInfo.senderId).toBeUndefined();
    expect(result.content).toBe("hello");
  });

  it("TC-712-003: Discord sender_id 330189773371080716 resolves to entity_id 2", async () => {
    const { restore } = writeFixture(discordIdentifierFixture);
    try {
      const result = await resolveEntityContext("session-712-003", {
        senderId: "330189773371080716",
        provider: "discord",
      });

      expect(result.entityId).toBe(2);
      expect(result.text).toContain("I)ruid");
    } finally {
      restore();
    }
  });

  it("TC-712-003 inverse: same numeric string on a non-Discord provider does not resolve to entity 2", async () => {
    const { restore } = writeFixture(discordIdentifierFixture);
    try {
      const result = await resolveEntityContext("session-712-003-inv", {
        senderId: "330189773371080716",
        provider: "telegram",
      });

      expect(result.entityId).toBeNull();
      expect(result.text).toBeNull();
    } finally {
      restore();
    }
  });

  it("TC-712-009: empty-string chatId is treated as absent with a warning", () => {
    const result = resolveFor(
      { currentUserMessage: "hello" },
      { channel: "discord", senderId: "330189773371080716", chatId: "" }
    );

    expect(result.warnings).toEqual(
      expect.arrayContaining([expect.stringContaining("chatId is empty")])
    );
    expect(result.senderInfo.senderId).toBe("330189773371080716");
    expect(result.content).toBe("hello");
  });

  it("TC-712-010: all identity fields absent produces one consolidated warning", () => {
    const result = resolveFor({ currentUserMessage: "heartbeat" }, {});

    // Exactly one warning for the fully absent-identity case, not three.
    expect(result.warnings).toEqual([
      "No channel identity available (senderId, channel, chatId all absent)",
    ]);
    expect(result.content).toBe("heartbeat");
  });

  it("TC-712-011: malformed ctx never returns silently — always warns and returns identity", () => {
    const malformedCases = [
      { ctx: { senderId: undefined }, label: "missing senderId" },
      { ctx: { chatId: 123 as any, channel: "telegram" }, label: "chatId number" },
      { ctx: { senderId: 1 as any, channel: "discord" }, label: "senderId number" },
      { ctx: { chatId: "", channel: "discord" }, label: "empty chatId" },
      { ctx: {}, label: "all absent" },
    ];


    for (const { ctx, label } of malformedCases) {
      const result = resolveFor({ currentUserMessage: "x" }, ctx);
      expect(result.warnings.length, `expected warning for ${label}`).toBeGreaterThan(0);
      expect(result, `expected defined identity object for ${label}`).toBeDefined();
    }
  });

  it("TC-712-012: empty messages array but currentUserMessage populated uses currentUserMessage", () => {
    const result = resolveFor(
      // event.messages is the historical-session array; currentUserMessage is
      // the current turn's text per the 2026.9.6 host contract.
      { currentUserMessage: "hello world", messages: [] },
      { channel: "discord", senderId: "123" }
    );

    expect(result.content).toBe("hello world");
  });

  it("TC-712-013: currentUserMessage omitted falls back to prompt", () => {
    const result = resolveFor(
      // prompt is the legacy fallback documented for older hosts.
      { prompt: "legacy prompt text" },
      { channel: "discord", senderId: "123" }
    );

    expect(result.content).toBe("legacy prompt text");
  });

  it("TC-712-012/013: currentUserMessage takes precedence over prompt", () => {
    const result = resolveFor(
      { currentUserMessage: "current", prompt: "legacy" },
      { channel: "discord", senderId: "123" }
    );

    expect(result.content).toBe("current");
  });

  it("Identity resolves provider from ctx.channel, overriding messageProvider", () => {
    const result = resolveFor(
      { currentUserMessage: "hi" },
      { channel: "discord", messageProvider: "slack", senderId: "123" }
    );

    // channel is the authoritative provider for identity matching.
    expect(result.senderInfo.provider).toBe("discord");
  });

  it("Sender name is read from channelContext.sender when available", () => {
    const result = resolveFor(
      { currentUserMessage: "hi" },
      {
        channel: "discord",
        senderId: "123",
        channelContext: { sender: { name: "Zonk", displayName: "ZonkDisplay" } },
      }
    );

    expect(result.senderInfo.senderName).toBe("Zonk");
  });

  it("Sender name falls back to event.senderName when channelContext lacks it", () => {
    const result = resolveFor(
      { currentUserMessage: "hi", senderName: "EventName" },
      { channel: "discord", senderId: "123" }
    );

    expect(result.senderInfo.senderName).toBe("EventName");
  });
});
