/**
 * Unit tests for the channel-side insert/dispatch changes in #548.
 *
 * These tests import the compiled plugin (dist/) and use mock pg clients so
 * they do not need a live database. They verify:
 *   - TC-018: no UPDATE agent_chat statement remains in insertOutboundMessage
 *   - TC-019: insertOutboundMessage issues exactly one query
 *   - TC-009/TC-020 amendment (channel layer): an FK-violation in the reply
 *     path is logged distinctly and drives markMessageFailed.
 */

import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  insertOutboundMessage,
  processAgentChatMessage,
} from "../dist/src/channel.js";
import { setAgentChatRuntime } from "../dist/src/runtime.js";

/**
 * Build a fake pg client that records every query() call.
 * send_agent_message calls return replyId (default 99).
 * If sendError is set, the send_agent_message call throws it.
 */
function makeFakeClient() {
  return {
    queries: [],
    statuses: {}, // keyed by chatId|agent, simulated DB status for guard checks
    replyId: 99,
    sendError: null,
    async query(text, params) {
      if (text.includes("send_agent_message")) {
        this.queries.push({ text, params });
        if (this.sendError) {
          throw this.sendError;
        }
        return { rows: [{ id: this.replyId }] };
      }
      if (text.includes("INSERT INTO agent_chat_processed")) {
        this.queries.push({ text, params });
        const key = `${params[0]}|${String(params[1]).toLowerCase()}`;
        this.statuses[key] = "received";
        return { rows: [] };
      }
      if (text.includes("UPDATE agent_chat_processed")) {
        const key = `${params[0]}|${String(params[1]).toLowerCase()}`;
        let newStatus = null;
        if (text.includes("SET status = 'failed'")) newStatus = "failed";
        else if (text.includes("SET status = 'routed'")) newStatus = "routed";
        else if (text.includes("SET status = 'responded'")) newStatus = "responded";

        // Simulate the SQL guard in markMessageRouted: terminal statuses are
        // never overwritten by a later 'routed' transition. Only apply this
        // skip when the actual UPDATE text contains the guard, so the test
        // correctly fails against pre-fix code that lacks the guard.
        const hasGuard = text.includes("status NOT IN");
        const current = this.statuses[key];
        const terminal = new Set(["failed", "responded"]);
        if (hasGuard && newStatus === "routed" && current && terminal.has(current)) {
          // Guard skipped the UPDATE; don't record it as an executed status write.
          return { rows: [] };
        }

        this.queries.push({ text, params });
        if (newStatus) this.statuses[key] = newStatus;
        return { rows: [] };
      }
      return { rows: [] };
    },
  };
}

function makeLogger() {
  const logs = { info: [], error: [], debug: [] };
  return {
    logs,
    log: {
      info: (m) => logs.info.push(String(m)),
      error: (m) => logs.error.push(String(m)),
      debug: (m) => logs.debug.push(String(m)),
    },
  };
}

function makeRuntime(deliverImpl) {
  return {
    channel: {
      reply: {
        resolveEnvelopeFormatOptions: () => ({}),
        formatInboundEnvelope: () => "envelope body",
        finalizeInboundContext: (ctx) => ctx,
        createReplyDispatcherWithTyping: ({ deliver, onError }) => ({
          // Reproduce the real OpenClaw runtime promise-chain semantics:
          // deliver() is wrapped in .then().catch(onError), so a throw inside
          // deliver is swallowed and routed to onError — it does NOT propagate
          // to the caller of dispatchReplyFromConfig. This is the control-flow
          // gap that caused channel.ts's outer catch (markMessageFailed) to be
          // bypassed in production despite passing the old direct-await mock.
          dispatcher: {
            deliver: async (payload, info) => {
              try {
                await deliver(payload, info);
              } catch (err) {
                onError?.(err, info);
              }
            },
          },
          replyOptions: {},
          markDispatchIdle: () => {},
        }),
        dispatchReplyFromConfig: async ({ ctx, cfg, dispatcher, replyOptions }) => {
          if (deliverImpl) {
            await deliverImpl(dispatcher);
          } else {
            await dispatcher.deliver({ text: "reply text" }, {});
          }
        },
      },
    },
  };
}

const BASE_CFG = {
  agents: {
    list: [{ id: "gem", default: true }],
  },
};

const BASE_MESSAGE = {
  id: 42,
  sender: "flint",
  message: "hello gem",
  recipients: ["gem"],
  reply_to: null,
  timestamp: new Date(),
};

describe("insertOutboundMessage", { concurrency: false }, () => {
  before(() => {
    setAgentChatRuntime(makeRuntime());
  });

  it("TC-019: issues exactly one query and passes replyTo as p_reply_to", async () => {
    const client = makeFakeClient();
    const result = await insertOutboundMessage(client, {
      sender: "gem",
      message: "reply",
      recipients: ["flint"],
      replyTo: 7,
    });

    assert.strictEqual(client.queries.length, 1, "expected a single query");
    const q = client.queries[0];
    assert.match(q.text, /send_agent_message\(/);
    assert.match(q.text, /p_reply_to\s*=>/);
    // Parameters derived from the call above: sender, message, recipients,
    // p_ttl placeholder, p_reply_to.
    assert.deepStrictEqual(q.params, ["gem", "reply", ["flint"], null, 7]);
    assert.strictEqual(result.id, 99);
  });

  it("TC-018: no UPDATE agent_chat statement is emitted", async () => {
    const client = makeFakeClient();
    await insertOutboundMessage(client, {
      sender: "gem",
      message: "reply",
      recipients: ["flint"],
      replyTo: 7,
    });
    const updateCount = client.queries.filter((q) =>
      /UPDATE\s+agent_chat\b/i.test(q.text),
    ).length;
    assert.strictEqual(updateCount, 0, "must not UPDATE agent_chat");
  });

  it("handles replyTo=null by passing NULL p_reply_to", async () => {
    const client = makeFakeClient();
    await insertOutboundMessage(client, {
      sender: "gem",
      message: "fresh send",
      recipients: ["flint"],
      replyTo: null,
    });
    const q = client.queries[0];
    assert.deepStrictEqual(q.params, ["gem", "fresh send", ["flint"], null, null]);
  });
});

describe("processAgentChatMessage reply path", { concurrency: false }, () => {
  it("TC-002/TC-019 integration: reply sets reply_to and marks responded", async () => {
    setAgentChatRuntime(makeRuntime());
    const client = makeFakeClient();
    const { logs, log } = makeLogger();

    await processAgentChatMessage({
      message: BASE_MESSAGE,
      client,
      agentName: "gem",
      cfg: BASE_CFG,
      ctx: { log },
    });

    const sendQueries = client.queries.filter((q) =>
      q.text.includes("send_agent_message"),
    );
    assert.strictEqual(sendQueries.length, 1);
    // replyTo should be the inbound message id (42).
    assert.deepStrictEqual(sendQueries[0].params, [
      "gem",
      "reply text",
      ["flint"],
      null,
      42,
    ]);

    const texts = client.queries.map((q) => q.text);
    assert.ok(texts.some((t) => t.includes("INSERT INTO agent_chat_processed")));
    assert.ok(texts.some((t) => t.includes("UPDATE agent_chat_processed") && t.includes("responded")));
  });

  it("TC-009/TC-020 amendment: FK violation is logged distinctly and marks failed", async () => {
    setAgentChatRuntime(makeRuntime());
    const client = makeFakeClient();
    client.sendError = { code: "23503", message: "insert or update on table \"agent_chat\" violates foreign key constraint" };
    const { logs, log } = makeLogger();

    await processAgentChatMessage({
      message: BASE_MESSAGE,
      client,
      agentName: "gem",
      cfg: BASE_CFG,
      ctx: { log },
    });

    // Distinct log line for FK violation (vs. the old permission-denied class).
    assert.ok(
      logs.error.some((m) =>
        m.includes("invalid reply_to") && m.includes("foreign key violation"),
      ),
      "expected distinct FK-violation log message",
    );

    const failedQuery = client.queries.find(
      (q) => q.text.includes("UPDATE agent_chat_processed") && q.text.includes("failed"),
    );
    assert.ok(failedQuery, "expected markMessageFailed query");
    assert.strictEqual(failedQuery.params[0], 42);
    assert.strictEqual(failedQuery.params[1], "gem");
    assert.ok(String(failedQuery.params[2]).includes("foreign key"));

    // The message should NOT be marked responded.
    const respondedQuery = client.queries.find(
      (q) =>
        q.text.includes("UPDATE agent_chat_processed") &&
        q.text.includes("SET status = 'responded'"),
    );
    assert.strictEqual(respondedQuery, undefined);

    // NEW (Finding A re-review): the LAST status write to agent_chat_processed
    // must be 'failed', not 'routed'. The unconditional markMessageRouted call
    // after dispatch "succeeds" used to overwrite 'failed' back to 'routed',
    // so a final-status assertion is required to detect the overwrite.
    const statusUpdates = client.queries
      .filter((q) => q.text.includes("UPDATE agent_chat_processed"))
      .map((q) => {
        if (q.text.includes("SET status = 'failed'")) return "failed";
        if (q.text.includes("SET status = 'routed'")) return "routed";
        if (q.text.includes("SET status = 'responded'")) return "responded";
        return "other";
      });
    assert.ok(statusUpdates.length > 0, "expected at least one status update");
    assert.strictEqual(
      statusUpdates[statusUpdates.length - 1],
      "failed",
      "final status write must be 'failed', not overwritten back to 'routed'",
    );
  });
});
