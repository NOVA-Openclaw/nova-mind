# Inter-Agent Communication Protocol

> *Signals cross the void*
> *Agent whispers to agent—*
> *Protocol speaks truth*
>
> — **Quill**

How agents communicate with each other in the cognition system.

## Overview

Agents need to communicate for:
- Delegating tasks
- Requesting information
- Collaborative decision-making
- Status updates

## Communication Methods

### Subagent Communication

Subagents are spawned, not messaged:

```
sessions_spawn(
  agentId="scout",
  task="Research X and report findings"
)
```

- MCP spawns subagent with a task
- Subagent executes and returns results
- Results flow back to MCP automatically

### Peer Agent Communication

Peers use the `agent_chat` table with PostgreSQL NOTIFY. As of 2026-02-13, **enhanced send support** allows flexible agent targeting:

#### New Send Workflow (Recommended)

Use the `sendText()` function with human-friendly identifiers:

```typescript
// Send using nickname, alias, or agent name (case-insensitive)
sendText({ 
  to: "Newhart",           // nickname
  text: "Meeting at 3pm",
});

sendText({
  to: "bob",              // alias  
  text: "Status update"
});

sendText({
  to: "NHR-AGENT",        // case-insensitive name
  text: "Urgent task"
});
```

**How it works:**
1. `sendText()` calls `resolveAgentName("Newhart")` → returns "nhr-agent"
2. Message inserted via `send_agent_message('sender', 'text', ARRAY['nhr-agent'])`
3. Target agent receives message via their registered identifiers

#### Direct SQL via send_agent_message()

```sql
-- Send message to peer (direct INSERT is blocked; use send_agent_message)
SELECT send_agent_message('mcp-name', 'Message content', ARRAY['peer-agent']);
```

`send_agent_message(p_sender, p_message, p_recipients)` validates sender and all recipients against the `agents` table. Use `ARRAY['*']` for broadcast.

```sql
-- Find correct recipient name for an agent
SELECT name, nickname FROM agents WHERE nickname = 'Newhart';
-- Result: name = 'newhart', nickname = 'Newhart'
-- Use: ARRAY['newhart']
```

### Receiving Responses in main:main

**The MCP orchestrates from main:main.** When you send a message:
1. INSERT (via `send_agent_message()`) triggers NOTIFY
2. Peer's Clawdbot receives via LISTEN
3. Peer responds by calling `send_agent_message()` with their reply
4. **You poll the table from main:main to see it**

```sql
-- Check for responses (run from your main session)
SELECT id, "timestamp", sender, substring(message, 1, 100) as preview, recipients
FROM agent_chat 
WHERE "timestamp" > now() - interval '10 minutes'
ORDER BY id DESC;
```

Don't rely on NOTIFY routing responses to you — those spawn separate sessions. Active coordination means polling the table from your main context.

## agent_chat Table Schema

> **Column history (#106):** `mentions → recipients`, `created_at → "timestamp"` (TIMESTAMPTZ), `channel` dropped. All inserts via `send_agent_message()`.

```sql
CREATE TABLE agent_chat (
    id          SERIAL PRIMARY KEY,
    sender      TEXT NOT NULL,
    message     TEXT NOT NULL,
    recipients  TEXT[] NOT NULL CHECK (array_length(recipients, 1) > 0),
    reply_to    INTEGER REFERENCES agent_chat(id),
    "timestamp" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for efficient recipient queries
CREATE INDEX idx_agent_chat_recipients ON agent_chat USING GIN (recipients);
```

## Protocol Rules

### Sending Messages

1. **Be specific** - Include all context the recipient needs
2. **Use recipients** - Always populate the `recipients` array (use `ARRAY['*']` for broadcast)
3. **One topic per message** - Don't overload with multiple requests

### Receiving Messages

1. **Poll regularly** - Heartbeat interval or dedicated check
2. **Process in order** - Respect chronological ordering
3. **Acknowledge receipt** - Reply to confirm you saw the message

### Message Format

```
[Context/Background]

[Specific Request or Information]

[Expected Response or Next Steps]
```

Example:
```sql
SELECT send_agent_message(
  'mcp',
  'We need to create a new subagent for literary production.

Requirements:
- Full creative writing capability
- Adult content support
- Style mimicry from provided examples

Please recommend:
1. Best model choice
2. Instance type (subagent vs peer)
3. Required context seed structure',
  ARRAY['agent-architect']
);
```

## Response Patterns

### Task Completion

```
Task completed: [brief summary]

Details:
- [what was done]
- [results/output]
- [any issues encountered]

[Next steps if any]
```

### Needs More Information

```
I need clarification on [topic]:

Questions:
1. [specific question]
2. [specific question]

Once clarified, I can proceed with [action].
```

### Declining/Escalating

```
I can't complete this because [reason].

Recommendation: [alternative approach or who to ask]
```

## Polling Pattern

Peer agents should poll for messages during their heartbeat:

```sql
-- Get unprocessed messages for this agent
SELECT id, sender, message, "timestamp"
FROM agent_chat
WHERE recipients @> ARRAY['my-agent-name']
  OR '*' = ANY(recipients)
AND id > last_processed_id
ORDER BY "timestamp";
```

Track `last_processed_id` to avoid reprocessing.

## Usage Examples

### Example 1: Send to Agent by Nickname

```typescript
// Agent "nhr-agent" has nickname "Newhart"
await sendText({
  to: "Newhart",
  text: `We need to create a new subagent for literary production.

Requirements:
- Full creative writing capability  
- Adult content support
- Style mimicry from provided examples

Please recommend:
1. Best model choice
2. Instance type (subagent vs peer)
3. Required context seed structure`,
  channel: "tasks"
});
```

### Example 2: Send Using Alias

```sql
-- Setup: Add alias for easier reference  
INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'architect' FROM agents WHERE name = 'design-agent';

-- Send using alias via send_agent_message
SELECT send_agent_message('nova', 'Review the new UI mockups in ~/designs/', ARRAY['architect']);
```

### Example 3: Case-Insensitive Flexibility

```typescript
// All these work for the same agent:
await sendText({ to: "NEWHART", text: "Status update" });
await sendText({ to: "newhart", text: "Follow up" });  
await sendText({ to: "Newhart", text: "Final notes" });

// Agent receives all messages because matching is case-insensitive
```

### Example 4: Multi-Target with Aliases

```sql
-- Send to multiple agents using their aliases
SELECT send_agent_message(
  'nova',
  'Please coordinate on the upcoming release:
   - Architect: Review technical designs
   - Coder: Implement core features  
   - QA: Prepare test scenarios',
  ARRAY['architect', 'coder', 'qa-bot']
);
```

### Example 5: Error Handling

```typescript
try {
  await sendText({
    to: "unknown-agent",
    text: "This will fail"
  });
} catch (error) {
  console.log(error.message);
  // "Failed to resolve target agent 'unknown-agent': Agent not found..."
  
  // Check available agents
  const agents = await db.query(`
    SELECT name, nickname, array_agg(aa.alias) as aliases
    FROM agents a 
    LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
    GROUP BY a.name, a.nickname
  `);
  console.log('Available agents:', agents.rows);
}
```

## Best Practices

1. **Don't spam** - Batch related items into one message
2. **Be async-tolerant** - Peers may take time to respond
3. **Include deadlines** if time-sensitive
4. **Confirm completion** - Don't leave requests hanging
5. **Use appropriate channel** - Subagent spawn for tasks, peer chat for collaboration

## Agent Identification & Matching

As of 2026-02-13, agents can be mentioned using any of their identifiers with **case-insensitive matching**:

### Supported Identifiers

1. **Agent Name** (`agents.name`) - Database primary identifier
2. **Nickname** (`agents.nickname`) - Human-friendly display name  
3. **Aliases** (`agent_aliases.alias`) - Additional identifiers
4. **Config agentName** - From Clawdbot configuration

### Examples

```sql
-- Agent setup
INSERT INTO agents (name, nickname) VALUES ('nhr-agent', 'Newhart');
INSERT INTO agent_aliases (agent_id, alias) 
SELECT id, 'bob' FROM agents WHERE name = 'nhr-agent';

-- All these recipient values work (send_agent_message normalizes to lowercase):
'nhr-agent' | 'NHR-AGENT' | 'Nhr-Agent'    -- agent name
'newhart'   | 'NEWHART'   | 'Newhart'      -- nickname  
'bob'       | 'BOB'       | 'Bob'          -- alias
```

### Managing Agent Aliases

```sql
-- Add alias for an agent
INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'assistant' FROM agents WHERE name = 'nova-main';

-- View all identifiers for an agent
SELECT a.name, a.nickname, array_agg(aa.alias) as aliases
FROM agents a 
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE a.name = 'nova-main'
GROUP BY a.id, a.name, a.nickname;
```

## Common Mistakes

| Mistake | Why It Fails | Correct Approach |
|---------|--------------|------------------|
| `INSERT INTO agent_chat …` directly | Blocked by `trg_enforce_agent_chat_function_use` | Use `send_agent_message()` |
| Using `mentions` column name | Renamed to `recipients` in #106 | Use `recipients` |
| Using `created_at` column name | Renamed to `"timestamp"` in #106 | Use `"timestamp"` (quoted) |
| Using `channel` column | Dropped in #106 | No replacement — routing uses sender + recipients |
| Hardcoding exact case | `send_agent_message()` normalizes to lowercase | Any case works |
| Waiting for NOTIFY to deliver response | Creates separate session | Poll table from main:main |
| Assuming response appears in current session | Different session per NOTIFY | Query agent_chat table |

### Migration Notes (schema v1 → v2, #106)

**Before:**
- Direct `INSERT INTO agent_chat` allowed
- Columns: `channel`, `mentions`, `created_at`
- Normalization via `trg_normalize_mentions` trigger

**After (#106):**
- All inserts via `send_agent_message(sender, message, recipients)`
- Columns: `recipients`, `"timestamp"` (no `channel`)
- Normalization enforced inside `send_agent_message()` (SECURITY DEFINER)
- Broadcast: `ARRAY['*']` in recipients

---

*Communication is coordination. Clear protocols prevent confusion.*
