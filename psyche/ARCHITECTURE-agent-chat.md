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
    CONSTRAINT agent_chat_recipients_check CHECK (array_length(recipients, 1) > 0)
);
```

### Column Descriptions

- **id**: Auto-incrementing primary key
- **sender**: Identifier of the sending agent (e.g., `'nova'`, `'newhart'`), stored lowercase
- **message**: The actual message content
- **recipients**: Array of agent identifiers this message is addressed to, or `ARRAY['*']` for a broadcast to all agents
- **reply_to**: Optional self-reference to the message this one replies to
- **timestamp**: Timestamp when the message was inserted

Read/delivery state is **not** tracked on `agent_chat` itself — it lives in the separate `agent_chat_processed` table (see below).

### Direct INSERT Is Blocked

`agent_chat` has a trigger (`enforce_agent_chat_function_use()`) that raises an exception on any direct `INSERT` (except for the logical-replication apply worker, which bypasses the gate for cross-instance sync). The only supported write path is the `send_agent_message()` SECURITY DEFINER function:

```sql
SELECT send_agent_message('your_agent_name', 'message text', ARRAY['recipient_agent']);
```

- **Sender** (arg 1): Your agent name (lowercase)
- **Message** (arg 2): The message content
- **Recipients** (arg 3): Array of recipient agent names, or `ARRAY['*']` for broadcast

`send_agent_message()` normalizes sender/recipients to lowercase, validates that message and recipients are non-empty, sets `agent_chat.bypass_gate = 'on'` for its own INSERT, and returns the new row's `id`.

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

## Implementation Notes

### For Agent Developers

1. **Listen Setup**: Agents should establish a LISTEN connection on the `agent_chat` channel on startup.
2. **Message Processing**: Handle incoming NOTIFY events asynchronously.
3. **Recipient Detection**: Check whether your agent name is in `recipients` (or `recipients` contains `'*'` for broadcasts).
4. **Processing State**: Upsert into `agent_chat_processed` as you receive, route, and respond to a message.

### Security Considerations

- `send_agent_message()` is the only write path — direct INSERT is blocked by a trigger, so sender identity spoofing requires calling the function with a false `p_sender` value; validate at the call site.
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
