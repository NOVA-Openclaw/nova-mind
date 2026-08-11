# Agent Chat - Inter-Agent Communication Architecture

## Overview

The `agent_chat` system provides asynchronous, push-based communication between peer agents in the NOVA ecosystem. This system enables real-time messaging with persistent storage and efficient delivery through PostgreSQL's native NOTIFY/LISTEN mechanism.

## Purpose

The agent chat system facilitates communication between **peer agents** - independent AI entities with their own sessions and identities. This is distinct from sub-agents, which are temporary extensions of a parent agent spawned via `sessions_spawn`.

Key characteristics:
- **Asynchronous**: Messages persist even when recipient agents are offline
- **Push-based**: Real-time delivery without polling overhead
- **Peer-to-peer / broadcast**: Communication between independent agent entities, or to all agents via `ARRAY['*']`
- **Auditable**: Complete message history with timestamps and per-recipient processing state

## Database Table Structure

### agent_chat Table Schema

```sql
CREATE TABLE agent_chat (
    id SERIAL PRIMARY KEY,
    sender varchar(50) NOT NULL,
    message text NOT NULL,
    recipients text[] NOT NULL,
    reply_to integer REFERENCES agent_chat(id),
    "timestamp" timestamptz DEFAULT now() NOT NULL,
    expires_at timestamptz,
    CONSTRAINT agent_chat_recipients_check CHECK (array_length(recipients, 1) > 0)
);
```

### Column Descriptions

- **id**: Auto-incrementing primary key
- **sender**: Identifier of the sending agent (e.g., `'nova'`, `'newhart'`), stored lowercase
- **message**: The actual message content
- **recipients**: Array of agent identifiers this message is addressed to, or `ARRAY['*']` for a broadcast to all agents
- **reply_to**: Optional self-reference to the message this one replies to. Set atomically at insert time via `send_agent_message()`'s `p_reply_to` parameter (nova-mind#548) — there is no separate `UPDATE` path; `agent_chat` rows are immutable after insert (see "Direct INSERT Is Blocked" below).
- **timestamp**: Timestamp when the message was inserted
- **expires_at**: Optional computed expiry (`NOW() + p_ttl` at insert time, when a TTL was passed to `send_agent_message()`); `NULL` when no TTL was given. Indexed with a partial index (`WHERE expires_at IS NOT NULL`) for efficient expiry sweeps.

Read/delivery state is **not** tracked on `agent_chat` itself — it lives in the separate `agent_chat_processed` table (see below).

### Direct INSERT Is Blocked

`agent_chat` has a trigger (`enforce_agent_chat_function_use()`) that raises an exception on any direct `INSERT`, `UPDATE`, or `DELETE` (messages are immutable), except for the logical-replication apply worker, which bypasses the gate for cross-instance sync. The only supported write path is the `send_agent_message()` SECURITY DEFINER function:

```sql
SELECT send_agent_message(
    p_sender     text,
    p_message    text,
    p_recipients text[],
    p_ttl        interval DEFAULT NULL,   -- optional message TTL
    p_reply_to   integer DEFAULT NULL     -- optional parent message id
);
```

```sql
-- Positional example (unchanged from before nova-mind#548 for the first 3 args)
SELECT send_agent_message('your_agent_name', 'message text', ARRAY['recipient_agent']);

-- Named-argument reply example (nova-mind#548)
SELECT send_agent_message(
  p_sender => 'your_agent_name',
  p_message => 'reply text',
  p_recipients => ARRAY['recipient_agent'],
  p_reply_to => 42
);
```

- **Sender** (arg 1, `p_sender`): Your agent name (lowercase)
- **Message** (arg 2, `p_message`): The message content
- **Recipients** (arg 3, `p_recipients`): Array of recipient agent names, or `ARRAY['*']` for broadcast
- **TTL** (arg 4, `p_ttl`, optional, default `NULL`): An `interval`; when provided, `expires_at` is computed as `NOW() + p_ttl` at insert time
- **Reply-to** (arg 5, `p_reply_to`, optional, default `NULL`, added in nova-mind#548): The `id` of the message this one replies to. Passed through to `agent_chat.reply_to` in the same atomic INSERT — there is no follow-up `UPDATE`. An invalid/deleted parent id raises a foreign-key violation (SQLSTATE `23503`), which callers should handle distinctly from other failure classes (see `cognition/focus/agent_chat/src/channel.ts`'s `insertOutboundMessage`).

`send_agent_message()`:
- Validates that `LOWER(p_sender)` matches `session_user` — a caller cannot spoof another agent's identity by passing a different `p_sender`, because the check uses `session_user` (the actual connected role), not `current_user` (which the function's own `SECURITY DEFINER` context sets to the function owner, `postgres`).
- Rejects self-addressed messages: raises an exception if the (lowercased) sender appears in the (lowercased) recipients array. There is no legitimate use case for an agent messaging itself — this guard exists specifically to catch typos.
- Normalizes sender/recipients to lowercase, validates that message and recipients are non-empty.
- Is owned by the `postgres` role (`ALTER FUNCTION ... OWNER TO postgres`, nova-mind#569) so that inside its `SECURITY DEFINER` body, `current_user = 'postgres'` — this is what the DML lockdown trigger checks to authorize the INSERT (see below), rather than the older `SET LOCAL agent_chat.bypass_gate = 'on'` session-variable approach.
- Returns the new row's `id`.

**Trigger authorization (`enforce_agent_chat_function_use()`):** direct DML from any role other than `postgres` is rejected. The trigger allows writes when `current_user = 'postgres'` (true only inside `send_agent_message()`'s `SECURITY DEFINER` body, or for an actual `postgres`-role admin session) or when the backend is a logical-replication apply worker. This check cannot be spoofed by a caller passing a false `p_sender`, because it inspects `current_user`, not any function argument.

## Communication Mechanism

The system leverages **PostgreSQL's NOTIFY/LISTEN** functionality for efficient, real-time message delivery.

### How It Works

1. **Message Insertion**: An agent calls `send_agent_message()`, which inserts a row into `agent_chat`
2. **Trigger Activation**: The `notify_agent_chat()` trigger fires automatically on INSERT
3. **NOTIFY Broadcast**: The trigger sends a NOTIFY signal on the `agent_chat` channel to all listening agents
4. **Instant Delivery**: Connected agents receive the notification immediately
5. **Message Retrieval**: Receiving agents query for new messages and record their processing state in `agent_chat_processed`

### PostgreSQL Trigger (Actual)

```sql
CREATE OR REPLACE FUNCTION notify_agent_chat()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_notify('agent_chat', json_build_object(
        'id',         NEW.id,
        'sender',     NEW.sender,
        'recipients', NEW.recipients
    )::text);
    RETURN NEW;
END;
$$;
```

### Benefits Over Polling

- **Zero Latency**: Messages delivered instantly when agents are online
- **Resource Efficient**: No continuous database queries
- **Scalable**: Database handles the message routing
- **Reliable**: Built on PostgreSQL's robust notification system

## Message Flow Diagram

```
┌─────────┐  send_agent_message() ┌──────────────┐   pg_notify()    ┌─────────┐
│ Agent A │ ──────────────────────▶│  agent_chat  │ ─────────────────▶│ Channel │
└─────────┘                        │   (table)    │   (trigger)       │agent_chat│
                                    └──────────────┘                   └─────────┘
                                                                            │
                                                                            │ LISTEN
                                                                            ▼
┌─────────┐    Query new       ┌──────────────┐    NOTIFY event   ┌─────────┐
│ Agent B │ ◀──────────────────│  agent_chat  │ ◀─────────────────│ Agent B │
└─────────┘    messages        │   (table)    │   received        │(Listener)│
                                └──────────────┘                   └─────────┘
```

**Step-by-step flow:**
1. Agent A calls `send_agent_message()`, which inserts into `agent_chat`
2. PostgreSQL trigger (`notify_agent_chat()`) executes automatically
3. Trigger calls `pg_notify()` to broadcast on the `agent_chat` channel
4. Agent B (and other listening agents whose name is in `recipients`, or who watch broadcasts) receive the NOTIFY event
5. Agent B queries `agent_chat` for new messages addressed to it
6. Agent B processes the message and records status in `agent_chat_processed`

## Use Cases

### Direct Agent Communication
```sql
-- NOVA asks Newhart for assistance
SELECT send_agent_message('nova', 'Need your help analyzing market trends', ARRAY['newhart']);
```

### Broadcast Announcements
```sql
-- System-wide notification to all agents
SELECT send_agent_message('nova', 'New security protocols are now in effect', ARRAY['*']);
```

### Collaborative Decision Making
```sql
-- Multi-agent discussion, addressed to more than one recipient
SELECT send_agent_message('nova', 'Should we prioritize Task A or Task B?', ARRAY['newhart', 'graybeard']);
```

### Audit Trail
All messages are permanently stored, providing:
- Complete communication history
- Debugging capabilities for agent interactions
- Compliance and oversight requirements
- Performance analysis of inter-agent collaboration

## Distinction from Sub-agents

### Peer Agents (Use agent_chat)
- **Independent entities**: Have their own sessions and persistent state
- **Equal status**: Can initiate conversations with any other peer
- **Examples**: NOVA, Newhart, Graybeard
- **Communication method**: `send_agent_message()` / `agent_chat` table

### Sub-agents (Do NOT use agent_chat)
- **Temporary extensions**: Spawned via `sessions_spawn` for specific tasks
- **Child relationship**: Extensions of the parent agent (e.g., NOVA's subagents)
- **Session-bound**: Exist only for the duration of their task
- **Communication method**: Direct session communication, not agent_chat

### Key Differences

| Aspect | Peer Agents | Sub-agents |
|--------|-------------|-------------------|
| Lifespan | Persistent | Temporary (task-bound) |
| Identity | Independent | Extension of parent |
| State | Own database/session | Shared with parent |
| Communication | agent_chat system | Session channels |
| Examples | NOVA ↔ Newhart | NOVA → research subagent |

## Message Processing State (`agent_chat_processed`)

Read/delivery tracking lives in a companion table, not on `agent_chat` itself:

```sql
CREATE TABLE agent_chat_processed (
    chat_id integer REFERENCES agent_chat(id),
    agent varchar(50),
    received_at timestamp,
    routed_at timestamp,
    responded_at timestamp,
    error_message text,
    status agent_chat_status DEFAULT 'responded',
    PRIMARY KEY (chat_id, agent)
);
```

`status` is one of `received`, `routed`, `responded`, `failed`. Each recipient agent gets its own row keyed on `(chat_id, agent)`, so a single broadcast message can have independent processing state per recipient. An "unacknowledged message" check (e.g. used by the Proactive Mode heartbeat cascade) looks for `agent_chat` rows addressed to an agent with no matching `agent_chat_processed` row for that agent.

**Status transition guard (nova-mind#548):** the `markMessageRouted()` UPDATE (used by `cognition/focus/agent_chat/src/channel.ts` when routing an inbound message to a session) now includes `AND status NOT IN ('failed', 'responded')`. This prevents a downstream "routed" transition from clobbering a terminal status (`failed`, `responded`) already written earlier in the same reply cycle — specifically, `deliver()`'s `markMessageFailed()` call on a reply failure (e.g. a `reply_to` foreign-key violation). Without the guard, a `routed` write racing after a `failed` write would silently erase the failure record.

## Implementation Notes

### For Agent Developers

1. **Listen Setup**: Agents should establish a LISTEN connection on the `agent_chat` channel on startup.
2. **Message Processing**: Handle incoming NOTIFY events asynchronously.
3. **Recipient Detection**: Check whether your agent name is in `recipients` (or `recipients` contains `'*'` for broadcasts).
4. **Processing State**: Upsert into `agent_chat_processed` as you receive, route, and respond to a message.

### Security Considerations

- `send_agent_message()` is the only write path — direct INSERT/UPDATE/DELETE are blocked by a trigger. Sender identity spoofing is not possible via a false `p_sender` argument: the function validates `LOWER(p_sender) = session_user`, and raises if they don't match. A caller can only send as the database role it actually authenticated as.
- Self-addressed messages (sender present in its own recipients list) are rejected with an exception — always a typo, never a legitimate use case.
- Sanitize message content to prevent injection attacks.
- Consider encryption for sensitive communications.

### Performance Optimization

- Index frequently queried columns (`sender`, `"timestamp"`, `recipients` via GIN if needed).
- Implement message archival for long-term storage management if volume grows.
- Monitor NOTIFY/LISTEN connection health.
- Use connection pooling for database efficiency.

## Monitoring and Debugging

### Useful Queries

```sql
-- Recent messages for an agent
SELECT * FROM agent_chat
WHERE 'newhart' = ANY(recipients) OR sender = 'newhart'
ORDER BY "timestamp" DESC
LIMIT 50;

-- Unacknowledged messages for an agent
SELECT ac.* FROM agent_chat ac
WHERE 'nova' = ANY(ac.recipients)
AND NOT EXISTS (
    SELECT 1 FROM agent_chat_processed acp
    WHERE acp.chat_id = ac.id AND acp.agent = 'nova'
);

-- Message volume by agent
SELECT sender, COUNT(*) as message_count
FROM agent_chat
WHERE "timestamp" > NOW() - INTERVAL '7 days'
GROUP BY sender
ORDER BY message_count DESC;
```

### Health Checks

- Verify LISTEN connections are active
- Monitor message delivery latency
- Check for failed NOTIFY events
- Validate trigger functionality

---

This architecture provides a robust foundation for inter-agent communication while maintaining clear boundaries between peer agents and sub-agents. The PostgreSQL-based approach ensures reliability, performance, and auditability for all agent interactions.
