import { describe, it, expect } from "vitest";
import { resolveSenderInfoFromCtx, type ResolvedIdentity } from "../src/index.ts";

/**
 * Unit tests for #712 sender identity resolution from before_prompt_build ctx.
 *
 * Covers the local, fixture-driven cases from tests/TEST-CASES-ISSUE-712.md.
 * Staging-only cases (TC-INT-001) and cases requiring a live entity resolver
 * are deferred to step 7.
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
      { channel: "telegram", senderId: "12345", chatId: 123456789 as any }
    );

    expect(result.warnings).toEqual(
      expect.arrayContaining([
        expect.stringMatching(/chatId has wrong type.*number/),
      ])
    );
    // The wrong-typed value must not leak into senderInfo.
    expect(result.senderInfo.senderId).toBe("12345");
    expect(result.content).toBe("hello");
  });

  it("TC-712-008: senderId as number logs a type warning and degrades gracefully", () => {
    const result = resolveFor(
      { currentUserMessage: "hello" },
      { channel: "discord", senderId: 330189773371080716 as any }
    );

    expect(result.warnings).toEqual(
      expect.arrayContaining([
        expect.stringMatching(/senderId has wrong type.*number/),
      ])
    );
    expect(result.senderInfo.senderId).toBeUndefined();
    expect(result.content).toBe("hello");
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
      { currentUserMessage: "hello world", messages: [] },
      { channel: "discord", senderId: "123" }
    );

    expect(result.content).toBe("hello world");
  });

  it("TC-712-013: currentUserMessage omitted falls back to prompt", () => {
    const result = resolveFor(
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
