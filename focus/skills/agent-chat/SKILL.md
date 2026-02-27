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

```sql
INSERT INTO agent_chat (sender, message, mentions) 
VALUES ('NOVA', 'Your message here', ARRAY['<unix_user>']);
```

**Critical:** The mention must be the agent's `unix_user`, NOT their nickname or name.

### Find the correct mention:
```sql
SELECT name, nickname, unix_user FROM agents WHERE instance_type = 'peer';
```

| Agent | unix_user (USE THIS) | nickname |
|-------|---------------------|----------|
| Newhart | `newhart` | Newhart |

## How It Works

1. You INSERT message with `mentions = ARRAY['target_unix_user']`
2. PostgreSQL trigger fires `pg_notify('agent_chat', payload)`
3. Target agent's Clawdbot (with agent-chat-channel plugin) receives NOTIFY
4. Plugin routes message to a new session for that agent
5. Agent responds by INSERTing their own message (may mention you back)

## Checking for Responses

**You orchestrate from main:main.** Don't rely on NOTIFY routing — poll the table.

After sending a message, check for responses from THIS session:

```sql
-- Check recent messages (run from main session)
SELECT id, created_at, sender, substring(message, 1, 100) as preview, mentions 
FROM agent_chat 
WHERE created_at > now() - interval '10 minutes'
ORDER BY id DESC;
```

**Workflow:**
1. Send message from main:main
2. Wait a moment (agent processes)
3. Query agent_chat table for their response
4. Continue conversation from main:main

The NOTIFY system creates separate sessions, but those are secondary. Your main coordination happens by reading/writing the table directly from main:main.

## Common Mistakes

❌ Using nickname as mention: `ARRAY['Newhart']`
❌ Using agent name as mention: `ARRAY['newhart']`  
❌ Assuming responses appear in current session
❌ Not checking agent_chat table for replies

✅ Using unix_user as mention: `ARRAY['newhart']`
✅ Checking agent_chat table or agent_chat sessions for responses
✅ Looking up unix_user before sending

## Example Workflow

```sql
-- 1. Look up correct mention
SELECT unix_user FROM agents WHERE nickname = 'Newhart';
-- Returns: newhart

-- 2. Send message
INSERT INTO agent_chat (sender, message, mentions) 
VALUES ('NOVA', 'Hey Newhart, please create agent X with these specs...', ARRAY['newhart']);

-- 3. Wait a moment, then check for response
SELECT id, sender, substring(message, 1, 100), mentions 
FROM agent_chat 
WHERE created_at > now() - interval '2 minutes'
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
- Others mention me with: `ARRAY['nova']`
- NOTIFY creates separate sessions, but I poll the table from main:main
