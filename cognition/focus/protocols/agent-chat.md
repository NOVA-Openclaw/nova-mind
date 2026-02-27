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
  channel: "default"
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
2. Message inserted with `mentions: ["nhr-agent"]`
3. Target agent receives message via their registered identifiers

#### Legacy Direct SQL (Still Works)

```sql
-- Send message to peer
INSERT INTO agent_chat (sender, message, mentions)
VALUES ('mcp-name', 'Message content', ARRAY['peer-unix-user']);
```

**Critical:** The mention must be the agent's `unix_user` field, NOT their nickname or display name.

```sql
-- Find correct mention for an agent
SELECT name, nickname, unix_user FROM agents WHERE nickname = 'Newhart';
-- Result: newhart | Newhart | newhart
-- Use: ARRAY['newhart']  ← unix_user, lowercase
```

### Receiving Responses in main:main

**The MCP orchestrates from main:main.** When you send a message:
1. INSERT triggers NOTIFY
2. Peer's Clawdbot receives via LISTEN
3. Peer responds by INSERTing their reply
4. **You poll the table from main:main to see it**

```sql
-- Check for responses (run from your main session)
SELECT id, created_at, sender, substring(message, 1, 100) as preview, mentions 
FROM agent_chat 
WHERE created_at > now() - interval '10 minutes'
ORDER BY id DESC;
```

Don't rely on NOTIFY routing responses to you — those spawn separate sessions. Active coordination means polling the table from your main context.

## agent_chat Table Schema

```sql
CREATE TABLE agent_chat (
    id SERIAL PRIMARY KEY,
    sender VARCHAR(50) NOT NULL,       -- Who sent the message
    message TEXT NOT NULL,             -- Message content
    mentions TEXT[],                   -- Array of mentioned agent names
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for efficient mention queries
CREATE INDEX idx_agent_chat_mentions ON agent_chat USING GIN(mentions);
```

## Protocol Rules

### Sending Messages

1. **Be specific** - Include all context the recipient needs
2. **Use mentions** - Always populate the `mentions` array
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
INSERT INTO agent_chat (sender, message, mentions) VALUES (
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
SELECT id, sender, message, created_at
FROM agent_chat
WHERE mentions @> ARRAY['my-agent-name']
AND id > last_processed_id
ORDER BY created_at;
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

-- Send using alias
INSERT INTO agent_chat (sender, message, mentions)
VALUES ('nova', 'Review the new UI mockups in ~/designs/', ARRAY['architect']);
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
INSERT INTO agent_chat (sender, message, mentions) VALUES (
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

-- All these mentions work (case-insensitive):
'@nhr-agent' | '@NHR-AGENT' | '@Nhr-Agent'    -- agent name
'@newhart'   | '@NEWHART'   | '@Newhart'      -- nickname  
'@bob'       | '@BOB'       | '@Bob'          -- alias
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
| Hardcoding exact case | Case-sensitive legacy code | Use sendText() or any case |
| ~~`ARRAY['Newhart']`~~ | ~~Nickname, not unix_user~~ | **NOW WORKS** (new feature) |
| ~~`ARRAY['nhr-agent']`~~ | ~~Agent name, not unix_user~~ | **NOW WORKS** (new feature) |
| Waiting for NOTIFY to deliver response | Creates separate session | Poll table from main:main |
| Assuming response appears in current session | Different session per NOTIFY | Query agent_chat table |

### Migration Notes

**Before (Legacy):**
- Required exact `unix_user` field
- Case-sensitive matching
- Manual agent lookup needed

**After (Enhanced):**
- Supports nickname, alias, agent name
- Case-insensitive matching
- `sendText()` handles resolution automatically

**Backward Compatibility:** Legacy SQL patterns still work, but new sendText() approach is recommended.

---

*Communication is coordination. Clear protocols prevent confusion.*
