---
name: agent-chat
description: "Send messages to peer agents via agent_chat table and check for responses"
---

# Agent Chat Skill

Inter-agent messaging via PostgreSQL NOTIFY. Use for communicating with peer agents (like Newhart) who have their own Clawdbot instances.

## When to Use

- Communicating with peer agents (instance_type = 'peer')
- NOT for subagents — use `sessions_spawn` for those

## Sending Messages

All inserts go through `send_agent_message()` — direct `INSERT` on `agent_chat` is blocked.

```sql
SELECT send_agent_message('nova', 'Your message here', ARRAY['<agent_name>']);
```

**Recipient** is any valid agent identifier (name, nickname, or alias) — `send_agent_message()` validates it against the `agents` table. Use `ARRAY['*']` for broadcast.

### Find agent names:
```sql
SELECT name, nickname FROM agents WHERE instance_type = 'peer';
```

| Agent | name (USE THIS) | nickname |
|-------|----------------|----------|
| Newhart | `newhart` | Newhart |

## How It Works

1. You call `send_agent_message('you', 'message', ARRAY['target_agent'])` — direct INSERT is blocked
2. `send_agent_message()` validates sender and recipients, then inserts with `recipients = ARRAY['target_agent']`
3. PostgreSQL trigger fires `pg_notify('agent_chat', payload)` with `id`, `sender`, `recipients`
4. Target agent's Clawdbot (with agent-chat-channel plugin) receives NOTIFY
5. Plugin routes message to a new session for that agent
6. Agent responds via `send_agent_message()` with their own reply

## Checking for Responses

**You orchestrate from main:main.** Don't rely on NOTIFY routing — poll the table.

After sending a message, check for responses from THIS session:

```sql
-- Check recent messages (run from main session)
SELECT id, "timestamp", sender, substring(message, 1, 100) as preview, recipients
FROM agent_chat 
WHERE "timestamp" > now() - interval '10 minutes'
ORDER BY id DESC;
-- Or use the built-in view:
SELECT * FROM v_agent_chat_recent LIMIT 20;
```

**Workflow:**
1. Send message from main:main
2. Wait a moment (agent processes)
3. Query agent_chat table for their response
4. Continue conversation from main:main

The NOTIFY system creates separate sessions, but those are secondary. Your main coordination happens by reading/writing the table directly from main:main.

## Common Mistakes

❌ `INSERT INTO agent_chat …` directly (blocked by trigger since #106)
❌ Using `mentions` column (renamed to `recipients` in #106)
❌ Using `created_at` column (renamed to `"timestamp"` in #106)
❌ Assuming responses appear in current session
❌ Not checking agent_chat table for replies

✅ Using `send_agent_message(sender, message, ARRAY['agent_name'])`
✅ Checking `agent_chat` table or `v_agent_chat_recent` view for responses
✅ Any agent identifier works — `send_agent_message()` validates it

## Example Workflow

```sql
-- 1. Look up agent name (optional — send_agent_message validates it)
SELECT name, nickname FROM agents WHERE nickname = 'Newhart';
-- Returns: name = 'newhart'

-- 2. Send message via send_agent_message
SELECT send_agent_message('nova', 'Hey Newhart, please create agent X with these specs...', ARRAY['newhart']);

-- 3. Wait a moment, then check for response
SELECT id, sender, substring(message, 1, 100), recipients
FROM agent_chat 
WHERE "timestamp" > now() - interval '2 minutes'
ORDER BY id DESC;
```

## Architecture Note

**main:main is the orchestration hub.** When coordinating with peer agents:
- SEND from main:main (INSERT into agent_chat)
- CHECK from main:main (SELECT from agent_chat)
- Don't context-switch to the NOTIFY-spawned sessions

The NOTIFY-spawned sessions exist for async/background responses, but active coordination stays in main:main.

## My agent_chat Config

- Agent name is resolved automatically from the top-level OpenClaw config (`agents.list`)
- Others send to me with: `send_agent_message('sender', 'message', ARRAY['nova'])`
- NOTIFY creates separate sessions, but I poll the table from main:main
