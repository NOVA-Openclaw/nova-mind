import pg from 'pg';
import { z } from 'zod';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { homedir } from 'os';
import { execSync } from 'child_process';

const { Client } = pg;

// Dispatch utilities will be loaded lazily
let dispatchInboundMessage = null;
let createReplyDispatcherWithTyping = null;
let finalizeInboundContext = null;
let formatInboundEnvelope = null;
let resolveEnvelopeFormatOptions = null;
let dispatchModulesLoaded = false;

// Load dispatch modules lazily when first needed
async function loadDispatchModules() {
  if (dispatchModulesLoaded) {
    console.log('[agent_chat] Dispatch modules already loaded');
    return true;
  }
  
  try {
    // Find the GLOBAL openclaw installation (the one running the gateway)
    // The local node_modules copy doesn't have all the templates we need
    
    // Get npm global prefix dynamically
    let npmPrefix = process.env.npm_config_prefix;
    if (!npmPrefix) {
      try {
        npmPrefix = execSync('npm config get prefix', { encoding: 'utf8' }).trim();
      } catch (err) {
        console.log('[agent_chat] Could not get npm prefix:', err.message);
        npmPrefix = '/usr/local'; // fallback
      }
    }
    
    const globalPaths = [
      process.env.OPENCLAW_PATH,  // Explicit override via environment variable
      join(homedir(), '.npm-global/lib/node_modules/openclaw'),  // User's npm global
      join(npmPrefix, 'lib/node_modules/openclaw'),  // System npm global prefix
      '/usr/local/lib/node_modules/openclaw',  // System fallback
    ].filter(Boolean);  // Remove undefined/null entries
    
    let openclawPath = null;
    for (const p of globalPaths) {
      try {
        const { existsSync } = await import('fs');
        const testPath = join(p, 'dist/auto-reply/dispatch.js');
        console.log(`[agent_chat] Checking for dispatch modules at: ${testPath}`);
        if (existsSync(testPath)) {
          openclawPath = p;
          console.log(`[agent_chat] Found openclaw at: ${openclawPath}`);
          break;
        }
      } catch (err) {
        console.log(`[agent_chat] Error checking path ${p}:`, err.message);
      }
    }
    
    // Fallback to module resolution if global paths fail
    if (!openclawPath) {
      console.log('[agent_chat] Global paths failed, trying module resolution...');
      try {
        const openclawMainPath = fileURLToPath(import.meta.resolve('openclaw'));
        openclawPath = dirname(dirname(openclawMainPath));
        console.log(`[agent_chat] Resolved openclaw via import.meta.resolve: ${openclawPath}`);
      } catch (err) {
        console.error('[agent_chat] Module resolution failed:', err.message);
        throw new Error('Cannot locate openclaw installation');
      }
    }
    
    console.log('[agent_chat] Loading dispatch modules from:', openclawPath);
    
    // Load dispatch module
    const dispatchPath = join(openclawPath, 'dist/auto-reply/dispatch.js');
    console.log(`[agent_chat] Loading: ${dispatchPath}`);
    const dispatchMod = await import(dispatchPath);
    dispatchInboundMessage = dispatchMod.dispatchInboundMessage;
    if (!dispatchInboundMessage) {
      throw new Error('dispatchInboundMessage is undefined after import');
    }
    console.log('[agent_chat] ✓ dispatchInboundMessage loaded');
    
    // Load reply dispatcher module
    const replyPath = join(openclawPath, 'dist/auto-reply/reply/reply-dispatcher.js');
    console.log(`[agent_chat] Loading: ${replyPath}`);
    const replyMod = await import(replyPath);
    createReplyDispatcherWithTyping = replyMod.createReplyDispatcherWithTyping;
    if (!createReplyDispatcherWithTyping) {
      throw new Error('createReplyDispatcherWithTyping is undefined after import');
    }
    console.log('[agent_chat] ✓ createReplyDispatcherWithTyping loaded');
    
    // Load inbound context module
    const contextPath = join(openclawPath, 'dist/auto-reply/reply/inbound-context.js');
    console.log(`[agent_chat] Loading: ${contextPath}`);
    const contextMod = await import(contextPath);
    finalizeInboundContext = contextMod.finalizeInboundContext;
    if (!finalizeInboundContext) {
      throw new Error('finalizeInboundContext is undefined after import');
    }
    console.log('[agent_chat] ✓ finalizeInboundContext loaded');
    
    // Load envelope module
    const envelopePath = join(openclawPath, 'dist/auto-reply/envelope.js');
    console.log(`[agent_chat] Loading: ${envelopePath}`);
    const envelopeMod = await import(envelopePath);
    formatInboundEnvelope = envelopeMod.formatInboundEnvelope;
    resolveEnvelopeFormatOptions = envelopeMod.resolveEnvelopeFormatOptions;
    if (!formatInboundEnvelope || !resolveEnvelopeFormatOptions) {
      throw new Error('Envelope functions are undefined after import');
    }
    console.log('[agent_chat] ✓ formatInboundEnvelope and resolveEnvelopeFormatOptions loaded');
    
    dispatchModulesLoaded = true;
    console.log('[agent_chat] ✅ All dispatch modules loaded successfully!');
    return true;
  } catch (err) {
    console.error('[agent_chat] ❌ Failed to load dispatch modules:', err);
    console.error('[agent_chat] Stack trace:', err.stack);
    return false;
  }
}

/**
 * Agent Chat Channel Plugin for OpenClaw
 * 
 * Listens to PostgreSQL NOTIFY on 'agent_chat' channel and routes messages
 * to the agent when mentioned. Marks processed messages in agent_chat_processed.
 */

const PLUGIN_ID = 'agent_chat';

/**
 * Zod schema for agent_chat configuration
 */
const AgentChatAccountSchemaBase = z
  .object({
    name: z.string().optional(),
    enabled: z.boolean().optional(),
    agentName: z.string(),
    database: z.string(),
    host: z.string(),
    port: z.number().int().positive().optional().default(5432),
    user: z.string(),
    password: z.string(),
    pollIntervalMs: z.number().int().positive().optional().default(1000),
  })
  .strict();

const AgentChatAccountSchema = AgentChatAccountSchemaBase;

const AgentChatConfigSchema = AgentChatAccountSchemaBase.extend({
  accounts: z.record(z.string(), AgentChatAccountSchema.optional()).optional(),
});

/**
 * Resolve agent_chat account config from OpenClaw config
 */
function resolveAgentChatAccount({ cfg, accountId = 'default' }) {
  const channelConfig = cfg.channels?.agent_chat;
  
  if (!channelConfig) {
    return {
      accountId,
      enabled: false,
      configured: false,
      config: {},
    };
  }

  const config = accountId === 'default' 
    ? channelConfig 
    : channelConfig.accounts?.[accountId] || {};

  return {
    accountId,
    name: config.name || accountId,
    enabled: config.enabled !== false,
    configured: Boolean(
      config.agentName &&
      config.database &&
      config.host &&
      config.user &&
      config.password
    ),
    config: {
      agentName: config.agentName,
      database: config.database,
      host: config.host,
      port: config.port || 5432,
      user: config.user,
      password: config.password,
      pollIntervalMs: config.pollIntervalMs || 1000,
    },
  };
}

/**
 * Create PostgreSQL client from config
 */
function createPgClient(config) {
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
async function fetchUnprocessedMessages(client, agentName) {
  // Case-insensitive matching for agent mentions
  const query = `
    SELECT ac.id, ac.channel, ac.sender, ac.message, ac.mentions, ac.reply_to, ac.created_at
    FROM agent_chat ac
    LEFT JOIN agent_chat_processed acp ON ac.id = acp.chat_id AND LOWER(acp.agent) = LOWER($1)
    WHERE LOWER($1) = ANY(SELECT LOWER(unnest(ac.mentions)))
      AND acp.chat_id IS NULL
    ORDER BY ac.created_at ASC
  `;
  
  const result = await client.query(query, [agentName]);
  return result.rows;
}

/**
 * Mark message as received (initial state)
 */
async function markMessageReceived(client, chatId, agentName) {
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
async function markMessageRouted(client, chatId, agentName) {
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
async function markMessageResponded(client, chatId, agentName) {
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
async function markMessageFailed(client, chatId, agentName, errorMsg) {
  const query = `
    UPDATE agent_chat_processed
    SET status = 'failed', error_message = $3
    WHERE chat_id = $1 AND LOWER(agent) = LOWER($2)
  `;
  
  await client.query(query, [chatId, agentName, errorMsg]);
}

/**
 * Insert outbound message into agent_chat
 */
async function insertOutboundMessage(client, { channel, sender, message, replyTo }) {
  const query = `
    INSERT INTO agent_chat (channel, sender, message, mentions, reply_to, created_at)
    VALUES ($1, $2, $3, $4, $5, NOW())
    RETURNING id
  `;
  
  const result = await client.query(query, [
    channel,
    sender,
    message,
    [], // mentions - empty for now, could be parsed from message
    replyTo || null,
  ]);
  
  return result.rows[0];
}

/**
 * Build session label for agent_chat message
 */
function buildSessionLabel({ channel, sender, chatId }) {
  return `${PLUGIN_ID}:${channel}:${sender}:${chatId}`;
}

/**
 * Start monitoring agent_chat for this account
 */
async function startAgentChatMonitor({ account, cfg, runtime, abortSignal, log }) {
  const { agentName, database, host, port, user, password, pollIntervalMs } = account.config;
  
  log?.info(`[agent_chat:${account.accountId}] Starting monitor for agent: ${agentName} @ ${host}:${port}/${database}`);
  
  const client = createPgClient(account.config);
  
  try {
    await client.connect();
    log?.info(`[agent_chat:${account.accountId}] Connected to PostgreSQL`);
    
    // Listen to agent_chat channel
    await client.query('LISTEN agent_chat');
    log?.info(`[agent_chat:${account.accountId}] Listening on channel 'agent_chat'`);
    
    // Handle notifications
    client.on('notification', async (msg) => {
      if (msg.channel === 'agent_chat') {
        log?.debug(`[agent_chat:${account.accountId}] Received notification`);
        
        try {
          const messages = await fetchUnprocessedMessages(client, agentName);
          
          for (const message of messages) {
            log?.info(`[agent_chat:${account.accountId}] Processing message ${message.id} from ${message.sender}`);
            
            try {
              // Mark as received first
              await markMessageReceived(client, message.id, agentName);
              log?.info(`[agent_chat:${account.accountId}] Marked message ${message.id} as received`);
              
              // Build session label
              const sessionLabel = buildSessionLabel({
                channel: message.channel,
                sender: message.sender,
                chatId: message.id,
              });
              
              // Verify dispatch modules are loaded
              if (!dispatchModulesLoaded || !formatInboundEnvelope || !resolveEnvelopeFormatOptions || !finalizeInboundContext || !createReplyDispatcherWithTyping || !dispatchInboundMessage) {
                throw new Error('Dispatch modules not loaded. Cannot process message.');
              }
              
              // Format the inbound message envelope
              log?.debug(`[agent_chat:${account.accountId}] Formatting envelope for message ${message.id}`);
              const envelopeOptions = resolveEnvelopeFormatOptions(cfg);
              const fromLabel = `${message.sender} (${message.channel})`;
              const body = formatInboundEnvelope({
                channel: 'AgentChat',
                from: fromLabel,
                timestamp: message.created_at ? new Date(message.created_at).getTime() : undefined,
                body: message.message,
                chatType: 'direct',
                sender: { name: message.sender, id: message.sender },
                envelope: envelopeOptions,
              });
              log?.debug(`[agent_chat:${account.accountId}] Envelope formatted for message ${message.id}`);
              
              // Build the inbound context (follows Signal plugin pattern)
              log?.debug(`[agent_chat:${account.accountId}] Building inbound context for message ${message.id}`);
              const agentChatTo = `agent_chat:${message.channel}`;
              const ctxPayload = finalizeInboundContext({
                Body: body,
                RawBody: message.message,
                CommandBody: message.message,
                From: `agent_chat:${message.sender}`,
                To: agentChatTo,
                SessionKey: sessionLabel,
                ChatType: 'direct',
                ConversationLabel: fromLabel,
                SenderName: message.sender,
                SenderId: message.sender,
                Provider: 'agent_chat',
                Surface: 'agent_chat',
                MessageSid: String(message.id),
                Timestamp: message.created_at ? new Date(message.created_at).getTime() : undefined,
                OriginatingChannel: 'agent_chat',
                OriginatingTo: agentChatTo,
              });
              log?.debug(`[agent_chat:${account.accountId}] Context built for message ${message.id}`);
              
              // Create reply dispatcher that sends replies back to agent_chat table
              log?.debug(`[agent_chat:${account.accountId}] Creating reply dispatcher for message ${message.id}`);
              const { dispatcher, replyOptions, markDispatchIdle } = createReplyDispatcherWithTyping({
                deliver: async (payload) => {
                  // Insert reply into agent_chat table
                  try {
                    await insertOutboundMessage(client, {
                      channel: message.channel,
                      sender: agentName,
                      message: payload.text || payload.body || '',
                      replyTo: message.id,
                    });
                    
                    log?.info(`[agent_chat:${account.accountId}] Sent reply for message ${message.id}`);
                  } catch (err) {
                    log?.error(`[agent_chat:${account.accountId}] Failed to send reply for message ${message.id}:`, err);
                    throw err;
                  }
                },
                onError: (err, info) => {
                  log?.error(`[agent_chat:${account.accountId}] ${info.kind} reply failed:`, err);
                },
              });
              log?.debug(`[agent_chat:${account.accountId}] Reply dispatcher created for message ${message.id}`);
              
              // Dispatch the message to the agent
              log?.info(`[agent_chat:${account.accountId}] 🚀 Dispatching message ${message.id} to agent...`);
              log?.debug(`[agent_chat:${account.accountId}] Dispatch context: SessionKey=${ctxPayload.SessionKey}, From=${ctxPayload.From}, To=${ctxPayload.To}`);
              
              try {
                log?.debug(`[agent_chat:${account.accountId}] Calling dispatchInboundMessage for message ${message.id}...`);
                await dispatchInboundMessage({
                  ctx: ctxPayload,
                  cfg,
                  dispatcher,
                  replyOptions,
                });
                
                log?.debug(`[agent_chat:${account.accountId}] dispatchInboundMessage completed for message ${message.id}`);
                markDispatchIdle();
                
                log?.info(`[agent_chat:${account.accountId}] ✅ Successfully dispatched message ${message.id}`);
                await markMessageRouted(client, message.id, agentName);
                log?.info(`[agent_chat:${account.accountId}] Marked message ${message.id} as routed`);
              } catch (dispatchError) {
                log?.error(`[agent_chat:${account.accountId}] ❌ Dispatch error for message ${message.id}:`, dispatchError);
                log?.error(`[agent_chat:${account.accountId}] Error stack:`, dispatchError.stack);
                await markMessageFailed(client, message.id, agentName, dispatchError.message);
              }
            } catch (error) {
              // Mark as failed if routing fails
              await markMessageFailed(client, message.id, agentName, error.message);
              log?.error(`[agent_chat:${account.accountId}] Failed to route message ${message.id}:`, error);
            }
          }
        } catch (error) {
          log?.error(`[agent_chat:${account.accountId}] Error processing notification:`, error);
        }
      }
    });
    
    // Initial check for existing unprocessed messages
    const initialMessages = await fetchUnprocessedMessages(client, agentName);
    log?.info(`[agent_chat:${account.accountId}] Found ${initialMessages.length} unprocessed messages on startup`);
    
    for (const message of initialMessages) {
      try {
        log?.info(`[agent_chat:${account.accountId}] Processing startup message ${message.id} from ${message.sender}`);
        
        // Mark as received first
        await markMessageReceived(client, message.id, agentName);
        log?.info(`[agent_chat:${account.accountId}] Marked startup message ${message.id} as received`);
        
        // Verify dispatch modules are loaded
        if (!dispatchModulesLoaded || !formatInboundEnvelope || !resolveEnvelopeFormatOptions || !finalizeInboundContext || !createReplyDispatcherWithTyping || !dispatchInboundMessage) {
          throw new Error('Dispatch modules not loaded. Cannot process startup message.');
        }
        
        const sessionLabel = buildSessionLabel({
          channel: message.channel,
          sender: message.sender,
          chatId: message.id,
        });
        
        // Format the inbound message envelope
        log?.debug(`[agent_chat:${account.accountId}] Formatting envelope for startup message ${message.id}`);
        const envelopeOptions = resolveEnvelopeFormatOptions(cfg);
        const fromLabel = `${message.sender} (${message.channel})`;
        const body = formatInboundEnvelope({
          channel: 'AgentChat',
          from: fromLabel,
          timestamp: message.created_at ? new Date(message.created_at).getTime() : undefined,
          body: message.message,
          chatType: 'direct',
          sender: { name: message.sender, id: message.sender },
          envelope: envelopeOptions,
        });
        
        // Build the inbound context
        const agentChatTo = `agent_chat:${message.channel}`;
        const ctxPayload = finalizeInboundContext({
          Body: body,
          RawBody: message.message,
          CommandBody: message.message,
          From: `agent_chat:${message.sender}`,
          To: agentChatTo,
          SessionKey: sessionLabel,
          ChatType: 'direct',
          ConversationLabel: fromLabel,
          SenderName: message.sender,
          SenderId: message.sender,
          Provider: 'agent_chat',
          Surface: 'agent_chat',
          MessageSid: String(message.id),
          Timestamp: message.created_at ? new Date(message.created_at).getTime() : undefined,
          OriginatingChannel: 'agent_chat',
          OriginatingTo: agentChatTo,
        });
        
        // Create reply dispatcher
        const { dispatcher, replyOptions, markDispatchIdle } = createReplyDispatcherWithTyping({
          deliver: async (payload) => {
            try {
              await insertOutboundMessage(client, {
                channel: message.channel,
                sender: agentName,
                message: payload.text || payload.body || '',
                replyTo: message.id,
              });
              
              log?.info(`[agent_chat:${account.accountId}] Sent reply for startup message ${message.id}`);
            } catch (err) {
              log?.error(`[agent_chat:${account.accountId}] Failed to send reply for startup message ${message.id}:`, err);
              throw err;
            }
          },
          onError: (err, info) => {
            log?.error(`[agent_chat:${account.accountId}] ${info.kind} reply failed:`, err);
          },
        });
        
        // Dispatch the message
        log?.info(`[agent_chat:${account.accountId}] 🚀 Dispatching startup message ${message.id} to agent...`);
        log?.debug(`[agent_chat:${account.accountId}] Dispatch context: SessionKey=${ctxPayload.SessionKey}, From=${ctxPayload.From}, To=${ctxPayload.To}`);
        
        try {
          log?.debug(`[agent_chat:${account.accountId}] Calling dispatchInboundMessage for startup message ${message.id}...`);
          await dispatchInboundMessage({
            ctx: ctxPayload,
            cfg,
            dispatcher,
            replyOptions,
          });
          
          log?.debug(`[agent_chat:${account.accountId}] dispatchInboundMessage completed for startup message ${message.id}`);
          markDispatchIdle();
          
          log?.info(`[agent_chat:${account.accountId}] ✅ Successfully dispatched startup message ${message.id}`);
          await markMessageRouted(client, message.id, agentName);
          log?.info(`[agent_chat:${account.accountId}] Marked startup message ${message.id} as routed`);
        } catch (dispatchError) {
          log?.error(`[agent_chat:${account.accountId}] ❌ Dispatch error for startup message ${message.id}:`, dispatchError);
          log?.error(`[agent_chat:${account.accountId}] Error stack:`, dispatchError.stack);
          await markMessageFailed(client, message.id, agentName, dispatchError.message);
        }
      } catch (error) {
        // Mark as failed if routing fails
        await markMessageFailed(client, message.id, agentName, error.message);
        log?.error(`[agent_chat:${account.accountId}] Failed to route message ${message.id}:`, error);
      }
    }
    
    // Keep connection alive
    const keepAliveInterval = setInterval(() => {
      if (!abortSignal?.aborted) {
        client.query('SELECT 1').catch((err) => {
          log?.error(`[agent_chat:${account.accountId}] Keep-alive failed:`, err);
        });
      }
    }, pollIntervalMs);
    
    // Handle abort signal
    if (abortSignal) {
      abortSignal.addEventListener('abort', async () => {
        log?.info(`[agent_chat:${account.accountId}] Received abort signal`);
        clearInterval(keepAliveInterval);
        try {
          await client.query('UNLISTEN agent_chat');
          await client.end();
          log?.info(`[agent_chat:${account.accountId}] Disconnected from PostgreSQL`);
        } catch (error) {
          log?.error(`[agent_chat:${account.accountId}] Error during shutdown:`, error);
        }
      });
    }
    
    // Wait for abort
    return new Promise((resolve) => {
      if (abortSignal) {
        abortSignal.addEventListener('abort', () => resolve());
      }
    });
    
  } catch (error) {
    log?.error(`[agent_chat:${account.accountId}] Fatal error:`, error);
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
 * Accepts: 'agent:NAME', 'agent_chat:NAME', or just 'NAME'
 * Returns: 'NAME' (stripped of prefix)
 */
function normalizeAgentChatMessagingTarget(raw) {
  const trimmed = raw.trim();
  if (!trimmed) return undefined;

  let normalized = trimmed;

  // Strip 'agent_chat:' prefix (case-insensitive)
  if (normalized.toLowerCase().startsWith('agent_chat:')) {
    normalized = normalized.slice('agent_chat:'.length).trim();
  }
  // Strip 'agent:' prefix (case-insensitive)
  else if (normalized.toLowerCase().startsWith('agent:')) {
    normalized = normalized.slice('agent:'.length).trim();
  }

  if (!normalized) return undefined;

  return normalized;
}

/**
 * Check if raw string looks like an agent_chat target ID
 */
function looksLikeAgentChatTargetId(raw) {
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
export const agentChatPlugin = {
  id: PLUGIN_ID,
  
  meta: {
    name: 'Agent Chat',
    description: 'PostgreSQL-based agent messaging via agent_chat table',
    order: 999, // Low priority in channel list
  },
  
  capabilities: {
    chatTypes: ['direct', 'group'],
    media: false,
    reactions: false,
    threads: false,
  },
  
  reload: {
    configPrefixes: ['channels.agent_chat'],
  },

  configSchema: AgentChatConfigSchema,

  messaging: {
    normalizeTarget: normalizeAgentChatMessagingTarget,
    targetResolver: {
      looksLikeId: looksLikeAgentChatTargetId,
      hint: '<AgentName|agent:AgentName|agent_chat:AgentName>',
    },
  },

  config: {
    listAccountIds: (cfg) => {
      const channelConfig = cfg.channels?.agent_chat;
      if (!channelConfig) return [];
      
      const accounts = ['default'];
      if (channelConfig.accounts) {
        accounts.push(...Object.keys(channelConfig.accounts));
      }
      return accounts;
    },
    
    resolveAccount: (cfg, accountId) => resolveAgentChatAccount({ cfg, accountId }),
    
    defaultAccountId: () => 'default',
    
    isConfigured: (account) => account.configured,
    
    describeAccount: (account) => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: account.configured,
      agentName: account.config.agentName,
      database: account.config.database,
      host: account.config.host,
    }),
  },
  
  outbound: {
    deliveryMode: 'direct',
    
    sendText: async ({ cfg, to, text, accountId, metadata }) => {
      const account = resolveAgentChatAccount({ cfg, accountId });
      
      if (!account.configured) {
        throw new Error(`agent_chat account ${accountId} not configured`);
      }
      
      const client = createPgClient(account.config);
      
      try {
        await client.connect();
        
        // Extract channel and reply_to from metadata or 'to' parameter
        const channel = metadata?.channel || 'default';
        const replyTo = metadata?.replyTo || null;
        
        const result = await insertOutboundMessage(client, {
          channel,
          sender: account.config.agentName,
          message: text,
          replyTo,
        });
        
        // If this is a reply to a message, mark the original message as responded
        if (replyTo) {
          await markMessageResponded(client, replyTo, account.config.agentName);
        }
        // Also check if there's a dbId in metadata (from inbound message routing)
        else if (metadata?.dbId) {
          await markMessageResponded(client, metadata.dbId, account.config.agentName);
        }
        
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
      const account = ctx.account;
      
      // Load dispatch modules before starting monitor
      const loaded = await loadDispatchModules();
      if (!loaded) {
        ctx.log?.error(`[agent_chat:${account.accountId}] Cannot start - dispatch modules failed to load`);
        return null;
      }
      
      return await startAgentChatMonitor({
        account,
        cfg: ctx.cfg,
        runtime: ctx.runtime,
        abortSignal: ctx.abortSignal,
        log: ctx.log,
      });
    },
  },
  
  status: {
    defaultRuntime: {
      accountId: 'default',
      running: false,
      lastStartAt: null,
      lastStopAt: null,
      lastError: null,
    },
    
    buildChannelSummary: ({ snapshot }) => ({
      configured: snapshot.configured ?? false,
      running: snapshot.running ?? false,
      agentName: snapshot.agentName ?? null,
      database: snapshot.database ?? null,
    }),
    
    buildAccountSnapshot: ({ account, runtime }) => ({
      accountId: account.accountId,
      name: account.name,
      enabled: account.enabled,
      configured: account.configured,
      agentName: account.config.agentName,
      database: account.config.database,
      running: runtime?.running ?? false,
      lastStartAt: runtime?.lastStartAt ?? null,
      lastStopAt: runtime?.lastStopAt ?? null,
      lastError: runtime?.lastError ?? null,
    }),
  },
};

// Register function for OpenClaw extension loader
export function register(api) {
  api.registerChannel({ plugin: agentChatPlugin });
}

// Default export for plugin loader (function form)
export default function(api) {
  // Dispatch modules will be loaded lazily in startAccount
  api.registerChannel({ plugin: agentChatPlugin });
}
