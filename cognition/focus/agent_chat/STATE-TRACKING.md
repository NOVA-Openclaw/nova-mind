# Message State Tracking

The agent-chat-channel plugin now tracks messages through a complete processing pipeline with granular states.

## Overview

Previously, messages were simply marked as "processed" when received. This didn't distinguish between:
- Plugin received the notification
- Message was routed to agent session
- Agent actually responded

Now messages track through distinct states: `received` → `routed` → `responded` (or `failed`)

## State Definitions

| State | Meaning | Timestamp Field |
|-------|---------|----------------|
| **received** | Plugin got the NOTIFY and saw the message | `received_at` |
| **routed** | Message passed to agent session (handleInbound called) | `routed_at` |
| **responded** | Agent sent a reply | `responded_at` |
| **failed** | Error occurred during routing | `error_message` populated |

## Schema Changes

### New Table Structure

```sql
CREATE TABLE agent_chat_processed (
    chat_id INTEGER REFERENCES agent_chat(id) ON DELETE CASCADE,
    agent TEXT NOT NULL,
    status agent_chat_status NOT NULL DEFAULT 'received',
    received_at TIMESTAMP DEFAULT NOW(),
    routed_at TIMESTAMP,
    responded_at TIMESTAMP,
    error_message TEXT,
    PRIMARY KEY (chat_id, agent)
);
```

### Migration

If you have an existing deployment:

```bash
# Backup first!
pg_dump -d your_database > backup.sql

# Run migration
psql -d your_database -f migration.sql
```

The migration script will:
1. Add new columns
2. Set existing records to 'responded' state (conservative assumption)
3. Remove old `processed_at` column
4. Create performance indexes

## Monitoring

### Find Stuck Messages

Messages that were routed but never got responses:

```sql
SELECT 
  ac.id,
  ac.sender,
  ac.message,
  acp.routed_at,
  NOW() - acp.routed_at AS time_since_routed
FROM agent_chat ac
JOIN agent_chat_processed acp ON ac.id = acp.chat_id
WHERE acp.status = 'routed'
  AND acp.routed_at < NOW() - INTERVAL '5 minutes'
ORDER BY acp.routed_at DESC;
```

### Response Time Stats

```sql
SELECT 
  agent,
  COUNT(*) as total_responses,
  AVG(EXTRACT(EPOCH FROM (responded_at - received_at))) as avg_response_seconds
FROM agent_chat_processed
WHERE status = 'responded'
GROUP BY agent;
```

### Activity Dashboard

```sql
SELECT 
  agent,
  COUNT(*) as total,
  SUM(CASE WHEN status = 'responded' THEN 1 ELSE 0 END) as responded,
  ROUND(100.0 * SUM(CASE WHEN status = 'responded' THEN 1 ELSE 0 END) / COUNT(*), 1) as response_rate
FROM agent_chat_processed
WHERE received_at > NOW() - INTERVAL '24 hours'
GROUP BY agent;
```

See `monitoring-queries.sql` for more examples.

## Plugin Behavior

### Inbound Flow

1. **Notification arrives** → Mark as `received`
2. **Call handleInbound** → If success, mark as `routed`; if failure, mark as `failed`
3. **Agent replies** → Mark original message as `responded`

### Outbound Flow

When the agent sends a message:
- If it's a reply (`replyTo` in metadata) → mark original as `responded`
- If metadata includes `dbId` → mark that message as `responded`

### Error Handling

If routing fails:
- Status set to `failed`
- Error message stored in `error_message` column
- Message won't be reprocessed

## Use Cases

### Finding Ignored Messages

The most common use case: "Agent received 24 messages but only replied to 1"

```sql
SELECT ac.id, ac.sender, ac.message
FROM agent_chat ac
JOIN agent_chat_processed acp ON ac.id = acp.chat_id
WHERE acp.responded_at IS NULL
  AND acp.received_at < NOW() - INTERVAL '1 hour'
ORDER BY acp.received_at DESC;
```

### Debugging Slow Responses

Find messages with high routing latency:

```sql
SELECT 
  ac.id,
  ac.sender,
  EXTRACT(EPOCH FROM (acp.routed_at - acp.received_at)) as routing_seconds,
  EXTRACT(EPOCH FROM (acp.responded_at - acp.routed_at)) as response_seconds
FROM agent_chat ac
JOIN agent_chat_processed acp ON ac.id = acp.chat_id
WHERE acp.status = 'responded'
  AND acp.responded_at > NOW() - INTERVAL '24 hours'
ORDER BY routing_seconds DESC
LIMIT 10;
```

### Identifying Failure Patterns

```sql
SELECT 
  error_message,
  COUNT(*) as occurrences
FROM agent_chat_processed
WHERE status = 'failed'
  AND received_at > NOW() - INTERVAL '7 days'
GROUP BY error_message
ORDER BY occurrences DESC;
```

## Files

- `schema.sql` - Full database schema with state tracking
- `migration.sql` - Migrate existing deployment to new schema
- `monitoring-queries.sql` - Helpful queries for monitoring message states
- `index.js` - Plugin code with state tracking implementation

## Testing

After deploying:

1. Send a test message mentioning your agent
2. Check the state progression:

```sql
SELECT * FROM agent_chat_processed WHERE chat_id = <your_message_id>;
```

You should see:
- `status = 'received'` immediately
- `status = 'routed'` after handleInbound
- `status = 'responded'` after agent replies

## Troubleshooting

### Messages stuck in 'received'

- Check if handleInbound is being called
- Look for errors in plugin logs

### Messages stuck in 'routed'

- Agent received but chose not to respond
- Check agent session logs
- Verify agent logic for handling messages

### High failure rate

- Check `error_message` field for patterns
- Verify database connectivity
- Check plugin configuration
