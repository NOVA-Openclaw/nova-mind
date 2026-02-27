# Cross-Database Replication Setup

This guide covers setting up logical replication for `agent_chat` when agents use separate databases.

## Overview

In some deployments, agents may have their own dedicated databases (e.g., `graybeard_memory`) while sharing message history from a central database (e.g., `nova_memory`). PostgreSQL logical replication allows real-time syncing of the `agent_chat` table across databases.

## Problem Solved

Without proper trigger configuration, agents using replicated data experience:

- **Missing notifications**: Agents don't receive `NOTIFY` events for replicated messages
- **Embedding conflicts**: Duplicate key violations when embedding triggers fire on replicated data

## Architecture Example

```
┌─────────────────┐     Logical Replication    ┌─────────────────┐
│   nova_memory   │ ─────────────────────────→ │ graybeard_memory │
│                 │                            │                 │
│  agent_chat     │                            │   agent_chat    │
│  (source)       │                            │   (replica)     │
└─────────────────┘                            └─────────────────┘
        ↑                                              ↑
        │                                              │
   All agents can                                 Graybeard agent
   write messages                                 receives replicated
                                                  messages + notifications
```

## Setup Steps

### 1. Create Publication (Source Database)

On the source database (e.g., `nova_memory`):

```sql
-- Create publication for agent_chat table
CREATE PUBLICATION agent_chat_pub FOR TABLE agent_chat;

-- Verify publication
SELECT * FROM pg_publication_tables WHERE pubname = 'agent_chat_pub';
```

### 2. Create Subscription (Target Database)  

On the target database (e.g., `graybeard_memory`):

```sql
-- Create subscription to replicate agent_chat
CREATE SUBSCRIPTION agent_chat_from_nova
CONNECTION 'host=localhost port=5432 dbname=nova_memory user=replication_user'
PUBLICATION agent_chat_pub;

-- Verify subscription
SELECT * FROM pg_subscription WHERE subname = 'agent_chat_from_nova';
```

### 3. Configure Triggers (Automatic)

The `agent-install.sh` script automatically detects logical replication subscriptions and configures triggers appropriately:

```bash
./agent-install.sh --database graybeard_memory
```

This will:
- Detect `agent_chat` subscriptions  
- Configure notification trigger: `ENABLE ALWAYS TRIGGER`
- Configure embedding trigger: `ENABLE REPLICA TRIGGER`

### 4. Manual Trigger Configuration

If needed, you can manually configure triggers:

```sql
-- Notification trigger: fire ALWAYS (including replicated rows)
ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;

-- Embedding trigger: fire REPLICA only (skip replicated rows)  
ALTER TABLE agent_chat ENABLE REPLICA TRIGGER trg_embed_chat_message;
```

## Verification

### Check Trigger Status

```sql
SELECT 
    schemaname, 
    tablename, 
    triggername, 
    CASE tgenabled
        WHEN 'O' THEN 'ORIGIN'
        WHEN 'D' THEN 'DISABLED' 
        WHEN 'R' THEN 'REPLICA'
        WHEN 'A' THEN 'ALWAYS'
        ELSE 'UNKNOWN'
    END as trigger_mode
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid  
WHERE c.relname = 'agent_chat' 
  AND NOT t.tgisinternal
ORDER BY triggername;
```

Expected output:
```
 schemaname | tablename  |      triggername       | trigger_mode
------------+------------+------------------------+--------------
 public     | agent_chat | trg_embed_chat_message | REPLICA
 public     | agent_chat | trg_notify_agent_chat  | ALWAYS
```

### Test Replication

1. Insert a message on source database:
```sql
-- On nova_memory
INSERT INTO agent_chat (channel, sender, message, mentions) 
VALUES ('test', 'system', 'Test replication message', ARRAY['graybeard']);
```

2. Verify on target database:
```sql  
-- On graybeard_memory
SELECT * FROM agent_chat ORDER BY id DESC LIMIT 1;
```

3. Check that Graybeard agent receives `NOTIFY agent_chat` event

## Troubleshooting

### Notifications Not Received

**Symptom**: Agent doesn't receive notifications for replicated messages
**Solution**: Ensure notification trigger is set to ALWAYS:

```sql
ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;
```

### Duplicate Key Violations  

**Symptom**: `duplicate key value violates unique constraint "memory_embeddings_pkey"`
**Solution**: Ensure embedding trigger only fires on REPLICA:

```sql
ALTER TABLE agent_chat ENABLE REPLICA TRIGGER trg_embed_chat_message;
```

### Subscription Issues

Check subscription status:
```sql
SELECT 
    subname,
    subenabled, 
    subslotname,
    subpublications
FROM pg_subscription;
```

Check replication lag:
```sql
SELECT * FROM pg_stat_subscription;
```

## Security Notes

- Use dedicated replication user with minimal privileges
- Consider SSL for cross-network replication
- Monitor replication lag and disk usage
- Set up proper backup/recovery for both databases

## Related Files

- `focus/agent_chat/schema.sql` - Contains trigger definitions and replication comments
- `agent-install.sh` - Automatic replication detection and configuration
- Database migration scripts in `migrations/`