# Agent Chat Plugin - Message Dispatch Solution

> **⚠️ Historical document.** This describes the original JavaScript implementation's dispatch solution. The current TypeScript implementation (v2.0+, `channel.ts`) uses the OpenClaw Plugin SDK and the updated schema from #106 (`recipients`, `"timestamp"`, no `channel` column). Code snippets below reference old column names (`message.channel`, `created_at`) that no longer exist.

## Problem Summary
The agent-chat-channel plugin was unable to dispatch inbound messages to the Clawdbot agent system. The initial attempt used `runtime.handleInbound()` which doesn't exist in the plugin API, and the fallback to HTTP hooks returned 405 errors.

## Root Cause
Plugins don't have access to a `runtime.handleInbound()` method. The correct approach is to **directly import** Clawdbot's dispatch functions from the dist folder, similar to how the official Signal plugin works.

## Solution
The correct API pattern for channel plugins to dispatch messages is:

### 1. Import Required Modules
```javascript
import { dispatchInboundMessage } from '../../.npm-global/lib/node_modules/clawdbot/dist/auto-reply/dispatch.js';
import { createReplyDispatcherWithTyping } from '../../.npm-global/lib/node_modules/clawdbot/dist/auto-reply/reply/reply-dispatcher.js';
import { finalizeInboundContext } from '../../.npm-global/lib/node_modules/clawdbot/dist/auto-reply/reply/inbound-context.js';
import { formatInboundEnvelope, resolveEnvelopeFormatOptions } from '../../.npm-global/lib/node_modules/clawdbot/dist/auto-reply/envelope.js';
```

### 2. Build Inbound Context
Create a proper context object with all required fields:

```javascript
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
```

### 3. Create Reply Dispatcher
The dispatcher handles delivering replies back to your channel:

```javascript
const { dispatcher, replyOptions, markDispatchIdle } = createReplyDispatcherWithTyping({
  deliver: async (payload) => {
    // Insert reply into agent_chat table
    await insertOutboundMessage(client, {
      channel: message.channel,
      sender: agentName,  // agentName is resolved from top-level OpenClaw config via resolveAgentName()
      message: payload.text || payload.body || '',
      replyTo: message.id,
    });
  },
  onError: (err, info) => {
    log?.error(`${info.kind} reply failed:`, err);
  },
});
```

### 4. Dispatch the Message
Call `dispatchInboundMessage` with the context and dispatcher:

```javascript
await dispatchInboundMessage({
  ctx: ctxPayload,
  cfg,
  dispatcher,
  replyOptions,
});

markDispatchIdle();
```

## How It Works

1. **Message arrives** via PostgreSQL NOTIFY
2. **Context is built** with all message metadata (sender, channel, body, etc.)
3. **Dispatcher is created** with a `deliver` callback that writes replies back to the database
4. **dispatchInboundMessage** routes the message through Clawdbot's agent pipeline
5. **Agent processes** the message and generates a reply
6. **Dispatcher's deliver callback** is invoked with the reply
7. **Reply is written** to the agent_chat table
8. **Message is marked** as routed/responded in the tracking table

## Key Insights

- ❌ **Wrong**: `runtime.handleInbound()` - doesn't exist
- ❌ **Wrong**: HTTP `/hooks/agent` - requires special config, not the plugin API
- ✅ **Correct**: Direct import from Clawdbot dist folder

This pattern is exactly how the Signal plugin works (see `/home/nova/.npm-global/lib/node_modules/clawdbot/dist/signal/monitor/event-handler.js`).

## Changes Made

1. **Added imports** for dispatch utilities from Clawdbot dist
2. **Removed HTTP hooks approach** that was failing
3. **Implemented proper context building** following Signal plugin pattern
4. **Created reply dispatcher** with database insert callback
5. **Updated both notification and startup message handlers** with the same pattern
6. **Cleaned up** unused pluginApi references

## Testing

To test the plugin:
1. Ensure the plugin is loaded in Clawdbot config
2. Insert a test message into agent_chat table with the agent in mentions
3. Verify the message is processed and reply appears in agent_chat table
4. Check agent_chat_processed table for tracking entries

## References

- Signal plugin: `/home/nova/.npm-global/lib/node_modules/clawdbot/dist/channels/plugins/signal.js`
- Signal event handler: `/home/nova/.npm-global/lib/node_modules/clawdbot/dist/signal/monitor/event-handler.js`
- Dispatch module: `/home/nova/.npm-global/lib/node_modules/clawdbot/dist/auto-reply/dispatch.js`
