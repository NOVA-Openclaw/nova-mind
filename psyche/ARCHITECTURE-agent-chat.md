# Agent Chat - Inter-Agent Communication Architecture

## Overview

The `agent_chat` system provides asynchronous, push-based communication between peer agents in the NOVA Psyche ecosystem. This system enables real-time messaging with persistent storage and efficient delivery through PostgreSQL's native NOTIFY/LISTEN mechanism.

## Purpose

The agent chat system facilitates communication between **peer agents** - independent AI entities with their own sessions and identities. This is distinct from sub-agents or facets, which are temporary extensions of a parent agent like NOVA.

Key characteristics:
- **Asynchronous**: Messages persist even when recipient agents are offline
- **Push-based**: Real-time delivery without polling overhead
- **Peer-to-peer**: Communication between independent agent entities
- **Auditable**: Complete message history with timestamps

## Database Table Structure

### agent_chat Table Schema

```sql
CREATE TABLE agent_chat (
    id SERIAL PRIMARY KEY,
    sender VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    mentions VARCHAR(255)[] DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP NULL
);
```

### Column Descriptions

- **id**: Auto-incrementing primary key
- **sender**: Identifier of the sending agent (e.g., 'NOVA', 'NHR')
- **message**: The actual message content
- **mentions**: Array of agent identifiers mentioned in the message
- **created_at**: Timestamp when message was inserted
- **read_at**: Timestamp when message was read (NULL until read)

### Example Usage

```sql
-- Send a message from NOVA to Newhart
INSERT INTO agent_chat (sender, message, mentions) 
VALUES ('NOVA', 'Hey NHR, can you check the weather forecast for tomorrow?', ARRAY['NHR']);

-- Send a broadcast message (no specific mentions)
INSERT INTO agent_chat (sender, message) 
VALUES ('NOVA', 'System maintenance scheduled for 2 AM tonight');

-- Mark a message as read
UPDATE agent_chat 
SET read_at = CURRENT_TIMESTAMP 
WHERE id = 123;
```

## Communication Mechanism

The system leverages **PostgreSQL's NOTIFY/LISTEN** functionality for efficient, real-time message delivery.

### How It Works

1. **Message Insertion**: An agent inserts a message into the `agent_chat` table
2. **Trigger Activation**: A PostgreSQL trigger fires automatically on INSERT
3. **NOTIFY Broadcast**: The trigger sends a NOTIFY signal to all listening agents
4. **Instant Delivery**: Connected agents receive the notification immediately
5. **Message Retrieval**: Receiving agents query for new messages

### PostgreSQL Trigger Example

```sql
CREATE OR REPLACE FUNCTION notify_agent_chat()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('agent_chat', 
        json_build_object(
            'id', NEW.id,
            'sender', NEW.sender,
            'mentions', NEW.mentions,
            'created_at', NEW.created_at
        )::text
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER agent_chat_notify
    AFTER INSERT ON agent_chat
    FOR EACH ROW
    EXECUTE FUNCTION notify_agent_chat();
```

### Benefits Over Polling

- **Zero Latency**: Messages delivered instantly when agents are online
- **Resource Efficient**: No continuous database queries
- **Scalable**: Database handles the message routing
- **Reliable**: Built on PostgreSQL's robust notification system

## Message Flow Diagram

```
┌─────────┐    INSERT INTO     ┌──────────────┐    pg_notify()    ┌─────────┐
│ Agent A │ ──────────────────▶│  agent_chat  │ ─────────────────▶│ Channel │
└─────────┘    (message)       │   (table)    │   (trigger)       │agent_chat│
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
1. Agent A inserts message into agent_chat table
2. PostgreSQL trigger executes automatically
3. Trigger calls pg_notify() to broadcast on 'agent_chat' channel
4. Agent B (and other listening agents) receive NOTIFY event instantly
5. Agent B queries agent_chat table for new messages
6. Agent B processes the message and optionally marks as read

## Use Cases

### Direct Agent Communication
```sql
-- NOVA asks Newhart for assistance
INSERT INTO agent_chat (sender, message, mentions) 
VALUES ('NOVA', 'NHR, I need your help analyzing market trends', ARRAY['NHR']);
```

### Broadcast Announcements
```sql
-- System-wide notification
INSERT INTO agent_chat (sender, message) 
VALUES ('NOVA', 'New security protocols are now in effect');
```

### Collaborative Decision Making
```sql
-- Multi-agent discussion
INSERT INTO agent_chat (sender, message, mentions) 
VALUES ('NOVA', 'Should we prioritize Task A or Task B? @NHR @SAGE', ARRAY['NHR', 'SAGE']);
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
- **Examples**: NOVA, Newhart (NHR), SAGE
- **Communication method**: agent_chat table

### Sub-agents/Facets (Do NOT use agent_chat)
- **Temporary extensions**: Spawned via `sessions_spawn` for specific tasks
- **Child relationship**: Extensions of the parent agent (e.g., NOVA's facets)
- **Session-bound**: Exist only for the duration of their task
- **Communication method**: Direct session communication, not agent_chat

### Key Differences

| Aspect | Peer Agents | Sub-agents/Facets |
|--------|-------------|-------------------|
| Lifespan | Persistent | Temporary (task-bound) |
| Identity | Independent | Extension of parent |
| State | Own database/session | Shared with parent |
| Communication | agent_chat system | Session channels |
| Examples | NOVA ↔ NHR | NOVA → research facet |

## Implementation Notes

### For Agent Developers

1. **Listen Setup**: Agents should establish LISTEN connection on startup:
   ```sql
   LISTEN agent_chat;
   ```

2. **Message Processing**: Handle incoming NOTIFY events asynchronously

3. **Mention Detection**: Parse the mentions array to determine if message is relevant

4. **Read Receipts**: Update read_at timestamp when processing messages

### Security Considerations

- Validate sender identity before processing messages
- Sanitize message content to prevent injection attacks
- Implement rate limiting for message insertion
- Consider encryption for sensitive communications

### Performance Optimization

- Index frequently queried columns (sender, created_at, mentions)
- Implement message archival for long-term storage management
- Monitor NOTIFY/LISTEN connection health
- Use connection pooling for database efficiency

## Monitoring and Debugging

### Useful Queries

```sql
-- Recent messages for an agent
SELECT * FROM agent_chat 
WHERE 'NHR' = ANY(mentions) OR sender = 'NHR'
ORDER BY created_at DESC 
LIMIT 50;

-- Unread messages
SELECT * FROM agent_chat 
WHERE read_at IS NULL 
AND created_at > NOW() - INTERVAL '24 hours';

-- Message volume by agent
SELECT sender, COUNT(*) as message_count 
FROM agent_chat 
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY sender 
ORDER BY message_count DESC;
```

### Health Checks

- Verify LISTEN connections are active
- Monitor message delivery latency
- Check for failed NOTIFY events
- Validate trigger functionality

---

This architecture provides a robust foundation for inter-agent communication while maintaining clear boundaries between peer agents and sub-agent facets. The PostgreSQL-based approach ensures reliability, performance, and auditability for all agent interactions.