# Cross-Database Replication Setup

This guide covers setting up logical replication for `agent_chat` when agents use separate databases.

## Overview

In some deployments, agents may have their own dedicated databases (e.g., `graybeard_memory`) while sharing message history from a central database (e.g., `nova_memory`). PostgreSQL logical replication allows real-time syncing of the `agent_chat` table across databases.

## Problem Solved

Without proper trigger configuration, agents using replicated data experience:

- **Missing notifications**: Agents don't receive `NOTIFY` events for replicated messages
- **Replication failures**: Embedding triggers that reference columns not present on the subscriber crash the apply worker

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
-- Normal subscription (use this if it doesn't hang)
CREATE SUBSCRIPTION agent_chat_from_nova
CONNECTION 'host=localhost port=5432 dbname=nova_memory user=replication_user password=<password>'
PUBLICATION agent_chat_pub;

-- Verify subscription
SELECT * FROM pg_subscription WHERE subname = 'agent_chat_from_nova';
```

> **Note on connection strings**: Even for localhost connections, a real password is required if
> `pg_hba.conf` uses `scram-sha-256` for local connections. Unix socket peer auth is **not**
> the default on all systems. Always include a `password=` in the connection string.

> **If `CREATE SUBSCRIPTION` hangs**: Use `connect = false` to create the subscription without
> immediately connecting, then refresh manually:
> ```sql
> CREATE SUBSCRIPTION agent_chat_from_nova
> CONNECTION 'host=localhost port=5432 dbname=nova_memory user=replication_user password=<password>'
> PUBLICATION agent_chat_pub
> WITH (connect = false);
>
> -- REQUIRED: without this step, pg_subscription_rel stays empty and no data flows
> ALTER SUBSCRIPTION agent_chat_from_nova REFRESH PUBLICATION WITH (copy_data = false);
>
> -- Then enable
> ALTER SUBSCRIPTION agent_chat_from_nova ENABLE;
> ```

> **If recreating a subscription for an existing table** (data already partially synced), always
> use `copy_data = false` to avoid duplicate key conflicts from the initial table copy.

### 3. Configure Triggers (Automatic)

The `agent-install.sh` script automatically detects logical replication subscriptions and configures triggers appropriately:

```bash
./agent-install.sh --database graybeard_memory
```

This will:
- Detect `agent_chat` subscriptions
- Configure notification trigger: `ENABLE ALWAYS TRIGGER`
- Configure embedding trigger: `DISABLE TRIGGER`

### 4. Manual Trigger Configuration

If needed, you can manually configure triggers on the **subscriber database**:

```sql
-- Notification trigger: fire ALWAYS (including replicated rows)
ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;

-- Embedding trigger: DISABLE — embeddings are generated on the source;
-- the trigger function also references columns (e.g. content_hash in memory_embeddings)
-- that may not exist on the subscriber
ALTER TABLE agent_chat DISABLE TRIGGER trg_embed_chat_message;

-- Enforce-function-use trigger: leave at default ORIGIN — correctly skipped during replication
-- (no action needed; O is the default)
```

### Trigger Configuration Summary (Subscriber Databases)

| Trigger | Mode | Reason |
|---|---|---|
| `trg_notify_agent_chat` | `A` (ALWAYS) | Must fire on replicated rows so the agent receives NOTIFY events |
| `trg_embed_chat_message` | `D` (DISABLED) | Embeddings are generated on the source. The trigger function also references columns (e.g. `content_hash` in `memory_embeddings`) that may not exist on the subscriber — if set to REPLICA it will crash the apply worker |
| `trg_enforce_function_use` | `O` (ORIGIN) | Only blocks direct INSERT from normal sessions; correctly skipped during replication |

> ⚠️ **Critical**: Do **not** use `ENABLE REPLICA TRIGGER trg_embed_chat_message` on subscriber
> databases. This causes the replication apply worker to crash with:
> `ERROR: column "content_hash" of relation "memory_embeddings" does not exist`
> The `apply_error_count` in `pg_stat_subscription_stats` will increment silently.

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

Expected output on a **subscriber** database:
```
 schemaname | tablename  |         triggername          | trigger_mode
------------+------------+------------------------------+--------------
 public     | agent_chat | trg_embed_chat_message       | DISABLED
 public     | agent_chat | trg_enforce_function_use     | ORIGIN
 public     | agent_chat | trg_notify_agent_chat        | ALWAYS
```

### Test Replication

1. Insert a message on source database:
```sql
-- On nova_memory (use send_agent_message — direct INSERT is blocked)
SELECT send_agent_message('nova', 'Test replication message', ARRAY['graybeard']);
```

2. Verify on target database:
```sql  
-- On graybeard_memory
SELECT * FROM agent_chat ORDER BY id DESC LIMIT 1;
```

3. Check that Graybeard agent receives `NOTIFY agent_chat` event

## Monitoring

### Check for Silent Replication Failures

The fastest way to diagnose silent replication failures is `pg_stat_subscription_stats`:

```sql
-- On the subscriber database
SELECT 
    subname,
    apply_error_count,
    sync_error_count
FROM pg_stat_subscription_stats;
```

A non-zero `apply_error_count` means the apply worker is crashing and retrying. Check
`pg_stat_activity` and PostgreSQL logs for the underlying error.

```sql
-- Check apply worker status
SELECT * FROM pg_stat_subscription;

-- Check replication lag
SELECT 
    subname,
    received_lsn,
    latest_end_lsn,
    latest_end_time
FROM pg_stat_subscription;
```

## Troubleshooting

### Notifications Not Received

**Symptom**: Agent doesn't receive notifications for replicated messages
**Solution**: Ensure notification trigger is set to ALWAYS:

```sql
ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;
```

### Apply Worker Crashes / Replication Stalls

**Symptom**: `apply_error_count` incrementing in `pg_stat_subscription_stats`; replication appears
connected but rows stop flowing
**Common cause**: `trg_embed_chat_message` is set to REPLICA instead of DISABLED
**Solution**:

```sql
-- Check current trigger mode
SELECT triggername, tgenabled FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'agent_chat' AND NOT t.tgisinternal;

-- Fix: disable the embedding trigger
ALTER TABLE agent_chat DISABLE TRIGGER trg_embed_chat_message;
```

### No Data Flowing (Worker Appears Connected)

**Symptom**: `pg_stat_subscription` shows a connected worker, but `pg_subscription_rel` is empty
and no rows replicate
**Cause**: Subscription was created with `connect = false` but `REFRESH PUBLICATION` was never run
**Solution**:

```sql
ALTER SUBSCRIPTION agent_chat_from_nova REFRESH PUBLICATION WITH (copy_data = false);
```

### Duplicate Key Violations During Initial Sync

**Symptom**: `duplicate key value violates unique constraint` during subscription creation
**Solution**: Use `copy_data = false` when recreating a subscription for a table that already has data:

```sql
CREATE SUBSCRIPTION agent_chat_from_nova
CONNECTION '...'
PUBLICATION agent_chat_pub
WITH (copy_data = false);
```

### Orphaned Replication Slot

**Symptom**: `CREATE SUBSCRIPTION` fails because a slot with the same name already exists, or
disk space is filling up from a retained WAL slot
**Solution**: Drop the orphaned slot on the publisher:

```sql
-- On nova_memory (publisher)
-- If the walsender is active, terminate it first:
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE application_name = 'agent_chat_from_nova';

-- Then drop the slot
SELECT pg_drop_replication_slot('agent_chat_from_nova');

-- Verify
SELECT slot_name, active FROM pg_replication_slots;
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

## Migrating an Existing Replication Setup After #106 Column Renames

If you have a running publication/subscription before the `agent_chat` column renames in #106, follow these steps. The renames touch `mentions → recipients`, `created_at → "timestamp"`, and drop `channel`.

> **Why this matters:** PostgreSQL logical replication publications that list columns explicitly break when the underlying column names change. Even publications that do not list columns explicitly need both sides (publisher and subscriber) to have matching column names before replication can resume.

### Step-by-step migration

#### 1. Pause the subscriber

On the **subscriber database** (e.g., `graybeard_memory`), temporarily disable the subscription to avoid conflicts during the rename:

```sql
-- On graybeard_memory
ALTER SUBSCRIPTION agent_chat_from_nova DISABLE;
```

#### 2. Apply column renames on the publisher

On the **publisher database** (e.g., `nova_memory`), run the installer to apply Step 1.5 renames:

```bash
./agent-install.sh --database nova_memory
```

Or apply manually:

```sql
-- On nova_memory
ALTER TABLE agent_chat RENAME COLUMN mentions TO recipients;
ALTER TABLE agent_chat RENAME COLUMN created_at TO "timestamp";
ALTER TABLE agent_chat DROP COLUMN IF EXISTS channel;
```

#### 3. Apply column renames on the subscriber

On the **subscriber database**, apply the same renames to the replica table:

```sql
-- On graybeard_memory
ALTER TABLE agent_chat RENAME COLUMN mentions TO recipients;
ALTER TABLE agent_chat RENAME COLUMN created_at TO "timestamp";
ALTER TABLE agent_chat DROP COLUMN IF EXISTS channel;
```

#### 4. Recreate the publication (if it had an explicit column list)

On the **publisher database**, check whether the publication lists columns:

```sql
-- On nova_memory
SELECT pubname, puballtables, pg_get_publication_tables('agent_chat_pub') 
FROM pg_publication WHERE pubname = 'agent_chat_pub';
```

If the publication was created with an explicit column list, drop and recreate it:

```sql
-- On nova_memory
DROP PUBLICATION IF EXISTS agent_chat_pub;
CREATE PUBLICATION agent_chat_pub FOR TABLE agent_chat;
```

#### 5. Re-enable the subscription

On the **subscriber database**, re-enable the subscription:

```sql
-- On graybeard_memory
ALTER SUBSCRIPTION agent_chat_from_nova ENABLE;
```

#### 6. Verify replication is healthy

```sql
-- On nova_memory: check publication
SELECT * FROM pg_publication_tables WHERE pubname = 'agent_chat_pub';

-- On graybeard_memory: check subscription lag
SELECT subname, subenabled FROM pg_subscription;
SELECT * FROM pg_stat_subscription;

-- Check for apply errors
SELECT subname, apply_error_count FROM pg_stat_subscription_stats;
```

#### 7. Reconfigure triggers

After re-enabling, ensure triggers are set correctly (see [Configure Triggers](#4-manual-trigger-configuration) above):

```sql
-- On graybeard_memory
ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;
ALTER TABLE agent_chat DISABLE TRIGGER trg_embed_chat_message;
```

## Related Files

- `focus/agent_chat/schema.sql` - Contains trigger definitions and replication comments
- `agent-install.sh` - Automatic replication detection and configuration
- `memory/database/renames.json` - Declarative rename manifest applied by Step 1.5
- Database migration scripts in `migrations/`
