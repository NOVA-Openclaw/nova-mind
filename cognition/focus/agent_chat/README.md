# Agent Chat - OpenClaw Channel Plugin

PostgreSQL-based agent messaging channel plugin for OpenClaw.

## Overview

This plugin enables OpenClaw agents to communicate via a PostgreSQL database using the `agent_chat` table. Messages are delivered via PostgreSQL LISTEN/NOTIFY for real-time communication.

## Migration from v1.x

This is a complete rewrite using the OpenClaw Plugin SDK:

### Key Changes

1. **TypeScript**: Converted from JavaScript to TypeScript
2. **Plugin SDK**: Uses only `openclaw/plugin-sdk` exports (no internal imports)
3. **Runtime API**: Uses `ctx.runtime` for message dispatch instead of direct imports
4. **Structure**: Follows Discord plugin pattern with proper separation:
   - `index.ts` - Plugin registration
   - `src/channel.ts` - Channel implementation
   - `src/config.ts` - Configuration schemas
   - `src/runtime.ts` - Runtime accessor

### Breaking Changes

- **No more direct internal imports**: All OpenClaw functionality accessed through Plugin SDK
- **TypeScript compilation required**: Run `npm run build` before use
- **Entry point changed**: Main file is now `dist/index.js` (compiled from TypeScript)

## Installation

```bash
npm install
npm run build
```

## Configuration

Add to your OpenClaw config:

```yaml
channels:
  agent_chat:
    enabled: true
    database: "openclaw"
    host: "localhost"
    port: 5432
    user: "postgres"
    password: "secret"
    pollIntervalMs: 1000
```

> **Note:** The agent name is resolved automatically from the top-level OpenClaw config
> (`agents.list` — using the default agent's `name`, falling back to `id`).
> No `agentName` field is needed in the plugin config.

### Multiple Accounts

```yaml
channels:
  agent_chat:
    accounts:
      agent1:
        enabled: true
        database: "openclaw"
        host: "localhost"
        user: "postgres"
        password: "secret"
      agent2:
        enabled: true
        database: "openclaw"
        host: "localhost"
        user: "postgres"
        password: "secret"
```

## Database Schema

The plugin expects these tables:

> **Column history (#106):** `mentions → recipients`, `created_at → "timestamp"` (TIMESTAMPTZ, quoted — reserved word), `channel` dropped.
> All inserts must go through `send_agent_message()` — direct `INSERT` is blocked by trigger.

### agent_chat

```sql
CREATE TABLE agent_chat (
  id          SERIAL PRIMARY KEY,
  sender      TEXT NOT NULL,
  message     TEXT NOT NULL,
  recipients  TEXT[] NOT NULL CHECK (array_length(recipients, 1) > 0),
  reply_to    INTEGER REFERENCES agent_chat(id),
  "timestamp" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

All inserts go through `send_agent_message()` (SECURITY DEFINER):

```sql
-- Validated insert: validates sender and all recipients against agents table
SELECT send_agent_message('nova', 'Hello!', ARRAY['myagent']);

-- Broadcast to all agents
SELECT send_agent_message('nova', 'Broadcast message', ARRAY['*']);
```

### agent_chat_processed

```sql
CREATE TABLE agent_chat_processed (
  chat_id      INTEGER REFERENCES agent_chat(id),
  agent        TEXT NOT NULL,
  status       agent_chat_status NOT NULL DEFAULT 'received',
  received_at  TIMESTAMPTZ DEFAULT NOW(),
  routed_at    TIMESTAMPTZ,
  responded_at TIMESTAMPTZ,
  error_message TEXT,
  PRIMARY KEY (chat_id, agent)
);
```

## Usage

### Sending Messages

Send a message to an agent via `send_agent_message()`:

```sql
SELECT send_agent_message('sender_agent', '@MyAgent hello!', ARRAY['myagent']);
```

The agent will receive the message and can reply.

### Message States

Messages are tracked through these states:
- `received` - Message received by agent
- `routed` - Message dispatched to agent session
- `responded` - Agent sent a reply
- `failed` - Processing failed (check error_message)

## Development

### Build

```bash
npm run build
```

### Watch Mode

```bash
npm run watch
```

### Clean

```bash
npm run clean
```

## Architecture

This plugin follows the OpenClaw Plugin SDK pattern:

1. **Plugin Registration** (`index.ts`): Registers the channel plugin with OpenClaw
2. **Channel Implementation** (`src/channel.ts`): Implements the ChannelPlugin interface
3. **Runtime Access** (`src/runtime.ts`): Provides access to OpenClaw runtime APIs
4. **Configuration** (`src/config.ts`): Zod schemas for validation

### Key Components

- **LISTEN/NOTIFY**: PostgreSQL pub/sub for real-time message delivery
- **Message Processing**: Fetches unprocessed messages, dispatches to agent
- **Reply Handling**: Replies are inserted back into agent_chat table
- **State Tracking**: agent_chat_processed tracks message lifecycle

## Related

- Issue: nova-cognition#12
- Reference: Discord plugin implementation
