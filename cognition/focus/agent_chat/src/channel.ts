import pg from "pg";
import type {
  ChannelPlugin,
  OpenClawConfig,
  ChannelGatewayContext,
  ChannelMeta,
} from "openclaw/plugin-sdk";
import { getAgentChatRuntime } from "./runtime.js";
import { AgentChatConfigSchema, type ResolvedAgentChatAccount } from "./config.js";

const { Client } = pg;

const PLUGIN_ID = "agent_chat";

/**
 * Resolve the agent name from the top-level OpenClaw config.
 * Uses agents.list to find the default agent, then falls back to id.
 */
function resolveAgentName(cfg: OpenClawConfig): string {
  const agents = cfg.agents?.list ?? [];
  const defaultAgent = agents.find((a) => a.default) ?? agents[0];
  return defaultAgent?.id ?? defaultAgent?.name ?? "main";
}

// Manual meta definition since "agent_chat" is not in the core channel allowlist
const meta: Omit<ChannelMeta, "id"> = {
  label: "Agent Chat",
  selectionLabel: "Agent Chat",
  docsPath: "/channels/agent_chat",
  blurb: "PostgreSQL-based agent messaging via agent_chat table",
  order: 999,
};

/**
 * Create PostgreSQL client from config
 */
function createPgClient(config: {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
}) {
  return new Client({
    host: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    password: config.password,
  });
}

/**
 * Fetch unprocessed messages for this agent from agent_chat table
 */
async function fetchUnprocessedMessages(client: pg.Client, agentName: string) {
  const query = `
    SELECT ac.id, ac.sender, ac.message, ac.recipients, ac.reply_to, ac."timestamp"
    FROM agent_chat ac
    LEFT JOIN agent_chat_processed acp ON ac.id = acp.chat_id AND LOWER(acp.agent) = LOWER($1)
    WHERE (LOWER($1) = ANY(SELECT LOWER(unnest(ac.recipients)))
        OR '*' = ANY(ac.recipients))
      AND acp.chat_id IS NULL
    ORDER BY ac."timestamp" ASC
  `;

  const result = await client.query(query, [agentName]);
  return result.rows;
}

/**
 * Mark message as received (initial state)
 */
async function markMessageReceived(client: pg.Client, chatId: number, agentName: string) {
  const query = `
    INSERT INTO agent_chat_processed (chat_id, agent, status, received_at)
    VALUES ($1, LOWER($2), 'received', NOW())
    ON CONFLICT (chat_id, agent) DO UPDATE
    SET received_at = COALESCE(agent_chat_processed.received_at, NOW())
  `;

  await client.query(query, [chatId, agentName]);
}

/**
 * Mark message as routed (passed to agent session)
 */
async function markMessageRouted(client: pg.Client, chatId: number, agentName: string) {
  const query = `
    UPDATE agent_chat_processed
    SET status = 'routed', routed_at = NOW()
    WHERE chat_id = $1 AND LOWER(agent) = LOWER($2)
  `;

  await client.query(query, [chatId, agentName]);
}

/**
 * Mark message as responded (agent replied)
 */
async function markMessageResponded(client: pg.Client, chatId: number, agentName: string) {
  const query = `
    UPDATE agent_chat_processed
    SET status = 'responded', responded_at = NOW()
    WHERE chat_id = $1 AND LOWER(agent) = LOWER($2)
  `;

  await client.query(query, [chatId, agentName]);
}

/**
 * Mark message as failed with error
 */
async function markMessageFailed(
  client: pg.Client,
  chatId: number,
  agentName: string,
  errorMsg: string,
) {
  const query = `
    UPDATE agent_chat_processed
    SET status = 'failed', error_message = $3
    WHERE chat_id = $1 AND LOWER(agent) = LOWER($2)
  `;

  await client.query(query, [chatId, agentName, errorMsg]);
}

/**
 * Insert outbound message into agent_chat via send_agent_message()
 */
async function insertOutboundMessage(
  client: pg.Client,
  {
    sender,
    message,
    recipients,
    replyTo,
  }: {
    sender: string;
    message: string;
    recipients: string[];
    replyTo: number | null;
  },
) {
  // All inserts must go through send_agent_message() — direct INSERT is blocked.
  // reply_to is set separately after insert since send_agent_message doesn't accept it.
  const result = await client.query(
    `SELECT send_agent_message($1, $2, $3) AS id`,
    [sender, message, recipients],
  );

  const newId: number = result.rows[0].id;

  if (replyTo !== null) {
    await client.query(
      `UPDATE agent_chat SET reply_to = $1 WHERE id = $2`,
      [replyTo, newId],
    );
  }

  return { id: newId };
}

/**
 * Build session label for agent_chat message
 */
function buildSessionLabel({ agentName }: { agentName: string }) {
  return `agent:${agentName}:agent_chat`;
}

/**
 * Process a single message from agent_chat
 */
async function processAgentChatMessage({
  message,
  client,
  agentName,
  cfg,
  ctx,
}: {
  message: {
    id: number;
    sender: string;
    message: string;
    recipients: string[];
    reply_to: number | null;
    timestamp: Date;
  };
  client: pg.Client;
  agentName: string;
  cfg: OpenClawConfig;
  ctx: ChannelGatewayContext<ResolvedAgentChatAccount>;
}) {
  const log = ctx.log;
  const runtime = getAgentChatRuntime();

  log?.info?.(`Processing message ${message.id} from ${message.sender}`);

  // Self-mention guard: prevent infinite loops
  if (message.sender.toLowerCase() === agentName.toLowerCase()) {
    log?.debug?.(`Skipping self-mention from ${message.sender}`);
    await markMessageReceived(client, message.id, agentName);
    return;
  }

  try {
    // Mark as received first
    await markMessageReceived(client, message.id, agentName);
    log?.debug?.(`Marked message ${message.id} as received`);

    // Build session label
    const sessionLabel = buildSessionLabel({ agentName });

    // Format the inbound message envelope
    const envelopeOptions = runtime.channel.reply.resolveEnvelopeFormatOptions(cfg);
    const fromLabel = `${message.sender}`;
    const body = runtime.channel.reply.formatInboundEnvelope({
      channel: "AgentChat",
      from: fromLabel,
      timestamp: message.timestamp ? new Date(message.timestamp).getTime() : undefined,
      body: message.message,
      chatType: "direct",
      sender: { name: message.sender, id: message.sender },
      envelope: envelopeOptions,
    });

    // Build the inbound context
    const agentChatTo = `agent_chat:${agentName}`;
    const ctxPayload = runtime.channel.reply.finalizeInboundContext({
      Body: body,
      RawBody: message.message,
      CommandBody: message.message,
      From: `agent_chat:${message.sender}`,
      To: agentChatTo,
      SessionKey: sessionLabel,
      ChatType: "direct",
      ConversationLabel: fromLabel,
      SenderName: message.sender,
      SenderId: message.sender,
      Provider: "agent_chat",
      Surface: "agent_chat",
      MessageSid: String(message.id),
      Timestamp: message.timestamp ? new Date(message.timestamp).getTime() : undefined,
      OriginatingChannel: "agent_chat",
      OriginatingTo: agentChatTo,
    });

    // Create reply dispatcher that sends replies back to agent_chat table
    const { dispatcher, replyOptions, markDispatchIdle } =
      runtime.channel.reply.createReplyDispatcherWithTyping({
        deliver: async (payload, info) => {
          try {
            await insertOutboundMessage(client, {
              sender: agentName,
              message: payload.text || "",
              recipients: [message.sender],
              replyTo: message.id,
            });

            // Mark as responded
            await markMessageResponded(client, message.id, agentName);
            log?.info?.(`Sent reply for message ${message.id}`);
          } catch (err) {
            log?.error?.(`Failed to send reply for message ${message.id}: ${err}`);
            throw err;
          }
        },
        onError: (err, info) => {
          log?.error?.(`${info.kind} reply failed: ${err}`);
        },
      });

    // Dispatch the message to the agent using dispatchReplyFromConfig
    log?.info?.(`🚀 Dispatching message ${message.id} to agent...`);

    try {
      await runtime.channel.reply.dispatchReplyFromConfig({
        ctx: ctxPayload,
        cfg,
        dispatcher,
        replyOptions,
      });

      markDispatchIdle();

      log?.info?.(`✅ Successfully dispatched message ${message.id}`);
      await markMessageRouted(client, message.id, agentName);
    } catch (dispatchError) {
      log?.error?.(`❌ Dispatch error for message ${message.id}: ${dispatchError}`);
      await markMessageFailed(
        client,
        message.id,
        agentName,
        (dispatchError as Error).message,
      );
    }
  } catch (error) {
    // Mark as failed if routing fails
    await markMessageFailed(client, message.id, agentName, (error as Error).message);
    log?.error?.(`Failed to route message ${message.id}: ${error}`);
  }
}

/**
 * Start monitoring agent_chat for this account
 */
async function startAgentChatMonitor(
  ctx: ChannelGatewayContext<ResolvedAgentChatAccount>,
): Promise<void> {
  const { pollIntervalMs } = ctx.account.config;
  const agentName = resolveAgentName(ctx.cfg);
  const log = ctx.log;

  if (!agentName) {
    log?.error?.(
      `agent_chat: cannot start monitor — no agent name found in top-level config (agents.list). ` +
      `Please configure agents.list with at least one agent entry that has an id or name.`,
    );
    return;
  }

  log?.info?.(
    `Starting monitor for agent: ${agentName} @ ${ctx.account.config.host}:${ctx.account.config.port}/${ctx.account.config.database}`,
  );

  const client = createPgClient(ctx.account.config);

  try {
    await client.connect();
    log?.info?.(`Connected to PostgreSQL`);

    // Listen to agent_chat channel
    await client.query("LISTEN agent_chat");
    log?.info?.(`Listening on channel 'agent_chat'`);

    // Handle notifications
    client.on("notification", async (msg) => {
      if (msg.channel === "agent_chat") {
        log?.debug?.(`Received notification`);

        try {
          const messages = await fetchUnprocessedMessages(client, agentName);

          for (const message of messages) {
            await processAgentChatMessage({
              message,
              client,
              agentName,
              cfg: ctx.cfg,
              ctx,
            });
          }
        } catch (error) {
          log?.error?.(`Error processing notification: ${error}`);
        }
      }
    });

    // Initial check for existing unprocessed messages
    const initialMessages = await fetchUnprocessedMessages(client, agentName);
    log?.info?.(`Found ${initialMessages.length} unprocessed messages on startup`);

    for (const message of initialMessages) {
      await processAgentChatMessage({
        message,
        client,
        agentName,
        cfg: ctx.cfg,
        ctx,
      });
    }

    // Keep connection alive
    const keepAliveInterval = setInterval(() => {
      if (!ctx.abortSignal?.aborted) {
        client.query("SELECT 1").catch((err) => {
          log?.error?.(`Keep-alive failed: ${err}`);
        });
      }
    }, pollIntervalMs);

    // Handle abort signal
    if (ctx.abortSignal) {
      ctx.abortSignal.addEventListener("abort", async () => {
        log?.info?.(`Received abort signal`);
        clearInterval(keepAliveInterval);
        try {
          await client.query("UNLISTEN agent_chat");
          await client.end();
          log?.info?.(`Disconnected from PostgreSQL`);
        } catch (error) {
          log?.error?.(`Error during shutdown: ${error}`);
        }
      });
    }

    // Wait for abort
    return new Promise<void>((resolve) => {
      if (ctx.abortSignal) {
        ctx.abortSignal.addEventListener("abort", () => resolve());
      }
    });
  } catch (error) {
    log?.error?.(`Fatal error: ${error}`);
    try {
      await client.end();
    } catch (cleanupError) {
      // Ignore cleanup errors
    }
    throw error;
  }
}

/**
 * Normalize agent_chat messaging target
 */
function normalizeAgentChatMessagingTarget(raw: string): string | undefined {
  const trimmed = raw.trim();
  if (!trimmed) return undefined;

  let normalized = trimmed;

  // Strip 'agent_chat:' prefix (case-insensitive)
  if (normalized.toLowerCase().startsWith("agent_chat:")) {
    normalized = normalized.slice("agent_chat:".length).trim();
  }
  // Strip 'agent:' prefix (case-insensitive)
  else if (normalized.toLowerCase().startsWith("agent:")) {
    normalized = normalized.slice("agent:".length).trim();
  }

  if (!normalized) return undefined;

  return normalized;
}

/**
 * Check if raw string looks like an agent_chat target ID
 */
function looksLikeAgentChatTargetId(raw: string): boolean {
  const trimmed = raw.trim();
  if (!trimmed) return false;

  // Accept 'agent:' or 'agent_chat:' prefixes
  if (/^(agent_chat:|agent:)/i.test(trimmed)) return true;

  // Accept bare agent names (alphanumeric, underscore, hyphen)
  return /^[a-zA-Z0-9_-]+$/.test(trimmed);
}

/**
 * Agent Chat Channel Plugin
 */
export const agentChatPlugin: ChannelPlugin<ResolvedAgentChatAccount> = {
  id: PLUGIN_ID,

  meta: {
    id: PLUGIN_ID,
    ...meta,
  },

  capabilities: {
    chatTypes: ["direct", "group"],
    media: false,
    reactions: false,
    threads: false,
  },

  reload: {
    configPrefixes: ["channels.agent_chat"],
  },

  configSchema: AgentChatConfigSchema,

  messaging: {
    normalizeTarget: normalizeAgentChatMessagingTarget,
    targetResolver: {
      looksLikeId: looksLikeAgentChatTargetId,
      hint: "<AgentName|agent:AgentName|agent_chat:AgentName>",
    },
  },

  config: {
    listAccountIds: (cfg) => {
      const channelConfig = cfg.channels?.agent_chat;
      if (!channelConfig) return [];

      const accounts = ["default"];
      if (channelConfig.accounts) {
        accounts.push(...Object.keys(channelConfig.accounts));
      }
      return accounts;
    },

    resolveAccount: (cfg, accountId) => {
      const channelConfig = cfg.channels?.agent_chat;

      if (!channelConfig) {
        return {
          accountId: accountId || "default",
          name: accountId || "default",
          enabled: false,
          config: {
            database: "",
            host: "",
            port: 5432,
            user: "",
            password: "",
            pollIntervalMs: 1000,
          },
        } as ResolvedAgentChatAccount;
      }

      const normalizedAccountId = accountId || "default";
      const config =
        normalizedAccountId === "default"
          ? channelConfig
          : channelConfig.accounts?.[normalizedAccountId] || {};

      return {
        accountId: normalizedAccountId,
        name: config.name || normalizedAccountId,
        enabled: config.enabled !== false,
        config: {
          database: config.database || "",
          host: config.host || "",
          port: config.port || 5432,
          user: config.user || "",
          password: config.password || "",
          pollIntervalMs: config.pollIntervalMs || 1000,
        },
      } as ResolvedAgentChatAccount;
    },

    defaultAccountId: () => "default",

    isConfigured: (account, cfg) =>
      Boolean(
        resolveAgentName(cfg) &&
          account.config.database &&
          account.config.host &&
          account.config.user &&
          account.config.password,
      ),

    describeAccount: (account, cfg) => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: Boolean(
        resolveAgentName(cfg) &&
          account.config.database &&
          account.config.host &&
          account.config.user &&
          account.config.password,
      ),
      agentName: resolveAgentName(cfg),
      database: account.config.database,
      host: account.config.host,
    }),
  },

  outbound: {
    deliveryMode: "direct",
    textChunkLimit: 4000, // PostgreSQL text field - generous limit

    sendText: async ({ cfg, to, text, accountId }) => {
      const account = agentChatPlugin.config!.resolveAccount(cfg, accountId);

      if (!agentChatPlugin.config!.isConfigured?.(account, cfg)) {
        throw new Error(`agent_chat account ${accountId} not configured`);
      }

      const client = createPgClient(account.config);

      try {
        await client.connect();

        const agentName = resolveAgentName(cfg);
        if (!agentName) {
          throw new Error(
            `agent_chat: cannot send — no agent name found in top-level config (agents.list)`,
          );
        }

        // 'to' is the recipient agent name (format: "agent_chat:AgentName", "agent:AgentName", or bare "AgentName")
        const recipientName = normalizeAgentChatMessagingTarget(to) || to;

        const result = await insertOutboundMessage(client, {
          sender: agentName,
          message: text,
          recipients: [recipientName],
          replyTo: null,
        });

        return {
          channel: PLUGIN_ID,
          messageId: String(result.id),
          success: true,
        };
      } finally {
        await client.end();
      }
    },
  },

  gateway: {
    startAccount: async (ctx) => {
      return await startAgentChatMonitor(ctx);
    },
  },

  status: {
    defaultRuntime: {
      accountId: "default",
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
    },

    buildChannelSummary: ({ snapshot }) => ({
      configured: snapshot.configured ?? false,
      running: snapshot.running ?? false,
      // agentName and database stored in probe for custom display
      agentName: (snapshot.probe as { agentName?: string })?.agentName ?? null,
      database: (snapshot.probe as { database?: string })?.database ?? null,
    }),

    buildAccountSnapshot: ({ account, runtime, cfg }) => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: Boolean(
        resolveAgentName(cfg) &&
          account.config.database &&
          account.config.host &&
          account.config.user &&
          account.config.password,
      ),
      running: runtime?.running ?? false,
      lastStartAt: runtime?.lastStartAt ?? null,
      lastStopAt: runtime?.lastStopAt ?? null,
      lastError: runtime?.lastError ?? null,
      // Store custom info in probe
      probe: {
        agentName: resolveAgentName(cfg),
        database: account.config.database,
      },
    }),
  },
};
