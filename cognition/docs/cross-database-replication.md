# Cross-Database Replication Setup

This guide covers setting up **bidirectional** logical replication for `agent_chat` when agents use
separate databases. The production configuration (nova_memory ↔ graybeard_memory) is bidirectional
so each agent sees messages the other sends in real time.

> **TL;DR for the most critical setting:** Always use `origin = 'none'` on both subscriptions.
> Without it, a replication loop forms that kills the apply worker within minutes.

## Overview

In some deployments, agents have their own dedicated databases (e.g., `graybeard_memory`) alongside
a central database (e.g., `nova_memory`). PostgreSQL logical replication allows real-time syncing
of the `agent_chat` table across databases in both directions.

## Problem Solved

Without proper trigger and subscription configuration, agents using replicated data experience:

- **Missing notifications**: Agents don't receive `NOTIFY` events for replicated messages
- **Replication failures**: Embedding triggers that reference columns not present on the subscriber
  crash the apply worker
- **Replication loops**: When `origin = 'none'` is omitted, changes bounce back and forth until PK
  conflicts kill the apply worker

## Architecture: Bidirectional (Production)

Both databases publish **and** subscribe to each other's `agent_chat` table:

```
┌─────────────────┐   agent_chat_from_nova    ┌──────────────────┐
│   nova_memory   │ ────────────────────────→ │ graybeard_memory │
│                 │                           │                  │
│ agent_chat_pub  │ ←──────────────────────── │ agent_chat_pub   │
│ (publication)   │  agent_chat_from_graybeard│ (publication)    │
└─────────────────┘                           └──────────────────┘
```

Each database:
- Has a **publication** (`agent_chat_pub`) that exports locally-originated changes
- Has a **subscription** that imports changes from the other database

ID ranges are separated to prevent PK conflicts:
- `nova_memory`: sequential IDs starting from 1 (currently ~2500s)
- `graybeard_memory`: IDs starting from 1,000,000 (currently ~1,000,112)

## Architecture: Unidirectional (Simpler Alternative)

For deployments where only one agent needs to see the other's messages without writing back:

```
┌─────────────────┐     Logical Replication    ┌─────────────────┐
│   nova_memory   │ ─────────────────────────→ │ graybeard_memory │
│                 │                            │                 │
│  agent_chat     │                            │   agent_chat    │
│  (source)       │                            │   (replica)     │
└─────────────────┘                            └─────────────────┘
```

Setup is the same as bidirectional but with only one subscription. Skip the second subscription and
slot creation steps below.

---

## Critical Settings

### `origin = 'none'` — The Most Important Setting

> ⚠️ **This is the single most important subscription parameter for bidirectional replication.**

When `origin = 'none'` is set on a subscription, PostgreSQL only replicates rows whose origin is
the publisher itself — not rows that arrived on the publisher via its own subscriptions. This breaks
the replication loop:

- **With `origin = 'any'` (the default):** nova → graybeard → nova → graybeard → PK conflict →
  apply worker death. The loop forms because graybeard's subscription re-exports nova's changes
  back to nova.
- **With `origin = 'none'`:** nova → graybeard (stops here). Graybeard only sends changes that
  originated locally on graybeard back to nova. The loop cannot form.

**Always use `origin = 'none'` on both subscriptions in a bidirectional setup.**

### `copy_data = false`

No initial table sync. Use this when the tables already exist and are populated (or will be seeded
separately). Avoids duplicate key conflicts from copying rows that already exist on the target.

### `create_slot = false`

Slots are pre-created manually at a specific LSN position. This gives precise control over where
replication begins, which is essential during a clean rebuild to avoid replaying stale WAL.

---

## Setup: Bidirectional Replication

### Step 1. Create Publications (Both Databases)

On **each** database, create a column-restricted publication. Only the columns that exist on both
sides are published — this prevents the apply worker from failing if the schemas diverge slightly.

```sql
-- On BOTH nova_memory and graybeard_memory
CREATE PUBLICATION agent_chat_pub
FOR TABLE agent_chat (id, sender, message, recipients, reply_to, timestamp);

-- Verify
SELECT * FROM pg_publication_tables WHERE pubname = 'agent_chat_pub';
```

### Step 2. Create Replication Slots (On the Publisher for Each Subscription)

Slots must be created on the **publisher** side before creating the subscription. Use
`create_slot = false` in the subscription so the slot is not re-created at subscription time.

```sql
-- On graybeard_memory: create the slot that nova_memory's subscription will consume
SELECT pg_create_logical_replication_slot('agent_chat_from_graybeard', 'pgoutput');

-- On nova_memory: create the slot that graybeard_memory's subscription will consume
SELECT pg_create_logical_replication_slot('agent_chat_from_nova', 'pgoutput');
```

Verify slots exist:
```sql
SELECT slot_name, plugin, active FROM pg_replication_slots;
```

### Step 3. Create Subscriptions (On Each Subscriber)

> ⚠️ Note the `host=/var/run/postgresql` (Unix socket) instead of `host=localhost`. Same-host
> replication should use Unix sockets. Password auth is still required despite using sockets.

**On nova_memory** (subscribing to graybeard's changes):
```sql
CREATE SUBSCRIPTION agent_chat_from_graybeard
CONNECTION 'host=/var/run/postgresql dbname=graybeard_memory user=postgres password=<password>'
PUBLICATION agent_chat_pub
WITH (
    copy_data    = false,
    create_slot  = false,
    slot_name    = 'agent_chat_from_graybeard',
    enabled      = true,
    origin       = 'none'   -- CRITICAL: prevents replication loop
);
```

**On graybeard_memory** (subscribing to nova's changes):
```sql
CREATE SUBSCRIPTION agent_chat_from_nova
CONNECTION 'host=/var/run/postgresql dbname=nova_memory user=postgres password=<password>'
PUBLICATION agent_chat_pub
WITH (
    copy_data    = false,
    create_slot  = false,
    slot_name    = 'agent_chat_from_nova',
    enabled      = true,
    origin       = 'none'   -- CRITICAL: prevents replication loop
);
```

### Step 4. Configure Triggers (Both Databases)

Trigger configuration differs slightly between the two databases. See the table below. The key
rules:

- `trg_notify_agent_chat`: must be **ALWAYS** on both sides so agents receive NOTIFY for replicated
  messages
- `trg_embed_chat_message`: must be **DISABLED** — embeddings are generated at source only

> ⚠️ **Critical — `ENABLE REPLICA TRIGGER` is backwards and dangerous.** The name implies
> "enable this trigger during replication" but it actually sets mode `R` (REPLICA), which means
> the trigger fires *only* during replication and *not* during normal writes — the exact opposite
> of what you want for `trg_embed_chat_message`. With mode `R`, the apply worker calls
> `embed_chat_message()` on the subscriber, which fails because the `content_hash` column doesn't
> exist in `memory_embeddings` on the subscriber. The `apply_error_count` increments silently and
> eventually the apply worker dies. **Always use `DISABLE TRIGGER`** (mode `D`) for embedding
> triggers on subscribers. See issue #130.

#### nova_memory trigger configuration

```sql
-- ALWAYS: nova agent needs NOTIFY for messages replicated from graybeard
ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;

-- DISABLED: embeddings generated at source only; do NOT use ENABLE REPLICA (see warning above)
ALTER TABLE agent_chat DISABLE TRIGGER trg_embed_chat_message;

-- ORIGIN (default): enforcement skipped during replication (no action needed)
-- ALTER TABLE agent_chat ENABLE TRIGGER trg_enforce_agent_chat_function_use;  -- already ORIGIN
-- ALTER TABLE agent_chat ENABLE TRIGGER trg_enforce_function_use;             -- already ORIGIN
```

#### graybeard_memory trigger configuration

```sql
-- ALWAYS: graybeard agent needs NOTIFY for messages replicated from nova
ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;

-- DISABLED: no embeddings on subscriber; do NOT use ENABLE REPLICA (see warning above)
ALTER TABLE agent_chat DISABLE TRIGGER trg_embed_chat_message;

-- DISABLED: no enforcement on subscriber
ALTER TABLE agent_chat DISABLE TRIGGER trg_enforce_function_use;
```

#### Trigger Configuration Summary (Both Databases)

| Database | Trigger | Mode | Reason |
|---|---|---|---|
| nova_memory | `trg_notify_agent_chat` | `A` (ALWAYS) | Agent needs NOTIFY for replicated messages |
| nova_memory | `trg_embed_chat_message` | `D` (DISABLED) | Embeddings at source only |
| nova_memory | `trg_enforce_agent_chat_function_use` | `O` (ORIGIN) | Skipped during replication |
| nova_memory | `trg_enforce_function_use` | `O` (ORIGIN) | Skipped during replication |
| graybeard_memory | `trg_notify_agent_chat` | `A` (ALWAYS) | Agent needs NOTIFY |
| graybeard_memory | `trg_embed_chat_message` | `D` (DISABLED) | No embeddings on subscriber |
| graybeard_memory | `trg_enforce_function_use` | `D` (DISABLED) | No enforcement on subscriber |

The `agent-install.sh` script automatically detects logical replication subscriptions and
configures these triggers:

```bash
./agent-install.sh --database graybeard_memory
```

---

## Nuclear Rebuild Procedure

Use this when replication breaks badly (apply workers died, stale slots, repeated errors):

1. **Disable and drop all `agent_chat` subscriptions on BOTH databases:**

   ```sql
   -- On nova_memory
   ALTER SUBSCRIPTION agent_chat_from_graybeard DISABLE;
   ALTER SUBSCRIPTION agent_chat_from_graybeard SET (slot_name = NONE);
   DROP SUBSCRIPTION agent_chat_from_graybeard;

   -- On graybeard_memory
   ALTER SUBSCRIPTION agent_chat_from_nova DISABLE;
   ALTER SUBSCRIPTION agent_chat_from_nova SET (slot_name = NONE);
   DROP SUBSCRIPTION agent_chat_from_nova;
   ```

   > Set `slot_name = NONE` before dropping so PostgreSQL doesn't try to drop the slot (which
   > may already be gone or on the other host).

2. **Drop all `agent_chat` replication slots on BOTH databases:**

   ```sql
   -- On nova_memory (drops the slot graybeard_memory was reading)
   SELECT pg_drop_replication_slot('agent_chat_from_nova');

   -- On graybeard_memory (drops the slot nova_memory was reading)
   SELECT pg_drop_replication_slot('agent_chat_from_graybeard');
   ```

   Terminate active walsenders first if needed:
   ```sql
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE application_name IN ('agent_chat_from_nova', 'agent_chat_from_graybeard');
   ```

3. **Create fresh slots at current WAL position on BOTH databases:**

   ```sql
   -- On graybeard_memory (for nova_memory's subscription)
   SELECT pg_create_logical_replication_slot('agent_chat_from_graybeard', 'pgoutput');

   -- On nova_memory (for graybeard_memory's subscription)
   SELECT pg_create_logical_replication_slot('agent_chat_from_nova', 'pgoutput');
   ```

4. **Re-create subscriptions with `origin = 'none'`** — see Step 3 above.

5. **Verify both workers have PIDs and zero apply_error_count:**

   ```sql
   -- Should show pid IS NOT NULL and apply_error_count = 0 on both databases
   SELECT s.subname, st.apply_error_count, w.pid
   FROM pg_subscription s
   JOIN pg_stat_subscription_stats st ON st.subid = s.oid
   LEFT JOIN pg_stat_subscription w ON w.subid = s.oid
   WHERE s.subname LIKE 'agent_chat_%';
   ```

---

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

Expected output on **nova_memory**:
```
 schemaname | tablename  |              triggername               | trigger_mode
------------+------------+----------------------------------------+--------------
 public     | agent_chat | trg_embed_chat_message                 | DISABLED
 public     | agent_chat | trg_enforce_agent_chat_function_use    | ORIGIN
 public     | agent_chat | trg_enforce_function_use               | ORIGIN
 public     | agent_chat | trg_notify_agent_chat                  | ALWAYS
```

Expected output on **graybeard_memory**:
```
 schemaname | tablename  |         triggername          | trigger_mode
------------+------------+------------------------------+--------------
 public     | agent_chat | trg_embed_chat_message       | DISABLED
 public     | agent_chat | trg_enforce_function_use     | DISABLED
 public     | agent_chat | trg_notify_agent_chat        | ALWAYS
```

### Test Replication

1. Insert a message on nova_memory:
```sql
-- On nova_memory (use send_agent_message — direct INSERT is blocked)
SELECT send_agent_message('nova', 'Test replication message', ARRAY['graybeard']);
```

2. Verify it arrives on graybeard_memory:
```sql  
-- On graybeard_memory
SELECT * FROM agent_chat ORDER BY id DESC LIMIT 1;
```

3. Insert a message on graybeard_memory and verify it arrives on nova_memory:
```sql
-- On graybeard_memory (note: graybeard IDs start at 1,000,000)
SELECT send_agent_message('graybeard', 'Test reverse replication', ARRAY['nova']);

-- On nova_memory
SELECT * FROM agent_chat WHERE id >= 1000000 ORDER BY id DESC LIMIT 1;
```

4. Confirm both agents receive `NOTIFY agent_chat` events for both directions

---

## Monitoring

### Check for Silent Replication Failures

```sql
-- On each database — non-zero apply_error_count means the apply worker is crashing
SELECT 
    subname,
    apply_error_count,
    sync_error_count
FROM pg_stat_subscription_stats;
```

### Check Apply Worker Status

```sql
-- On each database
SELECT 
    subname,
    pid,
    received_lsn,
    latest_end_lsn,
    latest_end_time,
    worker_type
FROM pg_stat_subscription;
```

A healthy bidirectional setup shows two rows on each database (one per subscription direction),
each with a non-null `pid`.

### Check Replication Slots

```sql
-- On each database — check that slots are active and not retaining excessive WAL
SELECT 
    slot_name,
    active,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots
WHERE slot_name LIKE 'agent_chat_%';
```

---

## Troubleshooting

### Replication Loop (The #1 Killer)

**Symptom**: `apply_error_count` rapidly increasing on both databases. Duplicate key violations in
PostgreSQL logs. Apply worker accumulates errors and eventually dies.

**Cause**: `origin = 'none'` was not set on one or both subscriptions. With the default
`origin = 'any'`, changes loop: nova → graybeard → nova → PK conflict.

**Fix**: Drop and recreate the subscription(s) with `origin = 'none'`. Use the Nuclear Rebuild
Procedure above to ensure a clean state.

### Notifications Not Received

**Symptom**: Agent doesn't receive notifications for replicated messages
**Solution**: Ensure notification trigger is set to ALWAYS on the subscriber:

```sql
ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;
```

### Apply Worker Crashes / Replication Stalls

**Symptom**: `apply_error_count` incrementing in `pg_stat_subscription_stats`; replication appears
connected but rows stop flowing

**Common cause #1**: `trg_embed_chat_message` is set to REPLICA (`R`) instead of DISABLED (`D`)

> ⚠️ **`ENABLE REPLICA TRIGGER` is backwards.** The command name implies "enable this trigger
> during replication" but it actually sets mode `R`, which means the trigger fires *only* during
> replication. This is the worst possible mode for `trg_embed_chat_message` on a subscriber:
> it calls `embed_chat_message()` for every replicated row, which fails because the
> `content_hash` column doesn't exist on the subscriber. See issue #130.

**Fix for cause #1**:
```sql
-- Check current trigger mode
SELECT triggername, tgenabled FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'agent_chat' AND NOT t.tgisinternal;

-- Fix: disable the embedding trigger (mode D, not mode R)
ALTER TABLE agent_chat DISABLE TRIGGER trg_embed_chat_message;
```

**Common cause #2**: Stale slot position. After many apply errors, the slot's `confirmed_flush_lsn`
can get stuck, causing old WAL entries to be replayed repeatedly.

**Fix for cause #2**: Use the Nuclear Rebuild Procedure to drop and recreate the slot at the
current WAL position.

### No Data Flowing (Worker Appears Connected)

**Symptom**: `pg_stat_subscription` shows a connected worker, but no rows replicate

**Cause A**: Subscription was created with `connect = false` but `REFRESH PUBLICATION` was never
run.

```sql
ALTER SUBSCRIPTION agent_chat_from_nova REFRESH PUBLICATION WITH (copy_data = false);
```

**Cause B**: The publication on the publisher has an explicit column list that doesn't match the
current schema (e.g., after column renames).

```sql
-- On the publisher: verify and recreate publication if needed
SELECT pubname, puballtables FROM pg_publication WHERE pubname = 'agent_chat_pub';
DROP PUBLICATION IF EXISTS agent_chat_pub;
CREATE PUBLICATION agent_chat_pub
FOR TABLE agent_chat (id, sender, message, recipients, reply_to, timestamp);
```

### Duplicate Key Violations During Initial Sync

**Symptom**: `duplicate key value violates unique constraint` during subscription creation
**Solution**: Use `copy_data = false` when recreating a subscription for a table that already has
data.

### Orphaned Replication Slot

**Symptom**: `CREATE SUBSCRIPTION` fails because a slot with the same name already exists, or disk
space is filling up from retained WAL

**Solution**: Drop the orphaned slot on the publisher:

```sql
-- Terminate active walsender first if needed
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE application_name = 'agent_chat_from_nova';

-- Drop the slot
SELECT pg_drop_replication_slot('agent_chat_from_nova');

-- Verify
SELECT slot_name, active FROM pg_replication_slots;
```

### Subscription Issues

```sql
-- Check subscription status
SELECT 
    subname,
    subenabled, 
    subslotname,
    subpublications,
    suborigin
FROM pg_subscription;
```

Verify `suborigin = 'none'` for both subscriptions. If it shows `any`, recreate the subscriptions
with `origin = 'none'`.

---

## Security Notes

- Use a dedicated replication user with minimal privileges in production if not using the postgres
  superuser
- Consider SSL for cross-network replication (same-host Unix socket connections are inherently
  local)
- Monitor replication lag and disk usage from retained WAL slots
- Set up proper backup/recovery for both databases

---

## Migrating an Existing Replication Setup After #106 Column Renames

If you have a running publication/subscription before the `agent_chat` column renames in #106,
follow these steps. The renames touch `mentions → recipients`, `created_at → "timestamp"`, and
drop `channel`.

> **Why this matters:** PostgreSQL logical replication publications that list columns explicitly
> break when the underlying column names change. Even publications that do not list columns
> explicitly need both sides (publisher and subscriber) to have matching column names before
> replication can resume.

### Step-by-step migration

#### 1. Pause all subscribers

On **each** subscriber database, temporarily disable subscriptions:

```sql
-- On graybeard_memory
ALTER SUBSCRIPTION agent_chat_from_nova DISABLE;

-- On nova_memory (if bidirectional)
ALTER SUBSCRIPTION agent_chat_from_graybeard DISABLE;
```

#### 2. Apply column renames on both databases

On **each** database, run the installer to apply Step 1.5 renames:

```bash
./agent-install.sh --database <dbname>
```

Or apply manually:

```sql
ALTER TABLE agent_chat RENAME COLUMN mentions TO recipients;
ALTER TABLE agent_chat RENAME COLUMN created_at TO "timestamp";
ALTER TABLE agent_chat DROP COLUMN IF EXISTS channel;
```

#### 3. Recreate publications with explicit column list

On **each** database:

```sql
DROP PUBLICATION IF EXISTS agent_chat_pub;
CREATE PUBLICATION agent_chat_pub
FOR TABLE agent_chat (id, sender, message, recipients, reply_to, timestamp);
```

#### 4. Re-enable subscriptions

On **each** subscriber:

```sql
ALTER SUBSCRIPTION agent_chat_from_nova ENABLE;
-- (and agent_chat_from_graybeard on nova_memory if bidirectional)
```

#### 5. Verify replication is healthy

```sql
-- On each database
SELECT subname, subenabled, suborigin FROM pg_subscription;
SELECT subname, apply_error_count FROM pg_stat_subscription_stats;
SELECT * FROM pg_stat_subscription;
```

#### 6. Verify trigger configuration

After re-enabling, confirm triggers are set correctly per the Trigger Configuration Summary table
above.

---

## Related Files

- `focus/agent_chat/schema.sql` - Contains trigger definitions and replication comments
- `agent-install.sh` - Automatic replication detection and configuration
- `memory/database/renames.json` - Declarative rename manifest applied by Step 1.5
- Database migration scripts in `migrations/`
- GitHub issue #130 — `ENABLE REPLICA TRIGGER` sets mode R, not ALWAYS
