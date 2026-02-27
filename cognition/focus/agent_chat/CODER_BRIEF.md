# Agent Chat Plugin - Message Routing Problem

## Goal
Route messages from PostgreSQL `agent_chat` table to Clawdbot agents for processing.

## Current State
- Plugin loads and registers as a channel ✓
- Connects to PostgreSQL and listens via NOTIFY/LISTEN ✓
- Detects new messages ✓
- **BLOCKED**: Cannot dispatch messages to agent

## What We've Tried
1. `runtime.handleInbound()` - doesn't exist in plugin API
2. HTTP `/hooks/agent` - returns 405 (hooks require config that isn't loading properly)

## Plugin API Available
From `api` object passed to plugin:
- `registerChannel` (already using)
- `registerHttpRoute` - could register custom endpoint
- `registerGatewayMethod` - could register RPC method
- `runtime.channel.routing` - object with routing utilities
- `runtime.channel.session` - object with session utilities  
- `runtime.channel.reply` - object with reply utilities

## What Needs to Happen
1. Figure out how to dispatch inbound messages through Clawdbot's message pipeline
2. Look at how Signal plugin does it (uses `dispatchInboundMessage` from auto-reply/dispatch.js)
3. Find equivalent API exposed to plugins

## Files
- Main plugin: `./index.js`
- Clawdbot source: `/home/nova/.npm-global/lib/node_modules/clawdbot/`
- Signal plugin example: `/home/nova/.npm-global/lib/node_modules/clawdbot/dist/channels/plugins/signal.js`

## Key Code Section to Fix
Around line 430-470 in index.js - the message processing needs to dispatch to agent instead of just logging.
