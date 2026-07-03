# agent_chat Database Migration Runbook

Issue: [NOVA-Openclaw/nova-mind#320](https://github.com/NOVA-Openclaw/nova-mind/issues/320)

Move the `agent_chat` messaging bus from `nova_memory` into a dedicated
`agent_chat` database on the same PostgreSQL instance. This runbook covers the
SQL/migration tooling (Chunk A). Plugin, Python consumer, and installer changes
are handled in Chunks B and C.

## Audience

Database/operators — the human running the cutover. All commands assume a
PostgreSQL superuser connection via `.pgpass` or environment variables.

## Prerequisites

* PostgreSQL 16+ superuser access (for `CREATE DATABASE`, `--disable-triggers`).
* All nova-ecosystem, Victoria, and peer agent DB roles already exist.
* `psql`, `pg_dump`, Python 3, and `psycopg2` are installed.
* Source database is `nova_memory`; target database will be `agent_chat`.
* A maintenance window where `agent_chat` table drops are acceptable.

## Files

| File | Purpose |
|------|---------|
| `database/agent-chat/schema.sql` | Full schema for the new `agent_chat` database |
| `scripts/agent-chat-migration/migrate.sh` | One-shot migration: create DB, apply schema, copy data, verify |
| `scripts/agent-chat-migration/delta_check_and_migrate.py` | Repeated delta detection/migration after rollout |
| `scripts/agent-chat-migration/pre_drop_gate_check.sh` | Six-gate checklist before dropping old objects |
| `scripts/agent-chat-migration/decommission.sh` | Drop objects from `nova_memory` |
| `scripts/agent-chat-migration/README.md` | This runbook |

## Strict Operator Sequence

The migration must be performed in this order. Skipping steps risks data loss
or a broken bus.

### 1. Pre-migration checks

Record baseline counts and max ids:

```bash
psql -U postgres -d nova_memory -c "SELECT count(*) FROM agent_chat;"
psql -U postgres -d nova_memory -c "SELECT count(*) FROM agent_chat_processed;"
psql -U postgres -d nova_memory -c "SELECT max(id) FROM agent_chat;"
psql -U postgres -d nova_memory -c "SELECT last_value, is_called FROM agent_chat_id_seq;"
```

### 2. Migrate schema and data

Run the migration script. It is idempotent: re-running after a successful
migration skips the data copy and reapplies schema safely.

```bash
./scripts/agent-chat-migration/migrate.sh \
  --source-db nova_memory \
  --target-db agent_chat \
  --host localhost \
  --port 5432 \
  --superuser postgres
```

Expected output:

* `agent_chat` database created (if not present).
* Schema applied.
* Data copied with `--disable-triggers` (notify/enforce triggers do not fire).
* `agent_chat_id_seq` set to `max(id)` with `is_called = true`.
* Verification reports row-count parity, sequence alignment, and zero orphans.

Do **not** point live agents at the new DB until the verification passes.

### 3. Verify the new bus directly

```bash
psql -U nova -d agent_chat -c "SELECT send_agent_message('nova', 'round-trip test', ARRAY['newhart']);"
```

Confirm a LISTEN client on `agent_chat` receives the NOTIFY payload.

### 4. Roll out agent configs (Chunk B/C pointer)

Update every agent's `~/.openclaw/postgres.json` to include the nested
`agent_chat` section:

```json
{
  "host": "localhost",
  "database": "nova_memory",
  "user": "<agent>",
  "password": "...",
  "agent_chat": {
    "database": "agent_chat",
    "user": "<agent>",
    "password": "..."
  }
}
```

Covered in Chunk B:

* `loadPgEnv()` / `load_pg_env()` section-key support.
* `agent_chat` plugin reads the nested section with fallback to flat keys.
* `pg-notify-listener.py` repointed.
* `proactive-gate-check.py` hardcoded DSN fixed.
* `agent_config_sync` pinned to `nova_memory` with explicit config.

Covered in Chunk C:

* `agent-install.sh` writes `.pgpass` entries for memory + messaging DBs.
* `agent-install.sh` removes dead `channels.agent_chat` connection keys.
* Installer verification arrays are two-DB aware.

### 5. Interim delta check / migrate

After all agents are verified on the new DB, check for any rows written to
`nova_memory` during the rollout window and migrate them:

```bash
# Report-only
./scripts/agent-chat-migration/delta_check_and_migrate.py \
  --source-db nova_memory \
  --target-db agent_chat \
  --user postgres

# Apply
./scripts/agent-chat-migration/delta_check_and_migrate.py \
  --source-db nova_memory \
  --target-db agent_chat \
  --user postgres \
  --migrate
```

Repeat until the report shows zero delta rows. The script aborts if it detects
an id-space collision where the same id has different content in the two DBs.

### 6. Pre-DROP gate check

Run the six-gate checklist. Two gates require operator attestations because
they cannot be verified automatically by SQL alone.

```bash
# Create attestation files first:
cat > /tmp/agent_chat_roundtrips.log <<EOF
2026-07-03T12:00:00Z nova peer round-trip passed
2026-07-03T12:01:00Z newhart peer round-trip passed
2026-07-03T12:02:00Z graybeard peer round-trip passed
2026-07-03T12:03:00Z subagent (gem) round-trip passed
2026-07-03T12:04:00Z victoria cross-ecosystem round-trip passed
EOF

cat > /tmp/agent_chat_consumers.log <<EOF
2026-07-03T12:05:00Z proactive-gate-check.py repointed and smoke-tested
2026-07-03T12:06:00Z pg-notify-listener.py repointed and smoke-tested
2026-07-03T12:07:00Z agent_chat plugin configs rolled out fleet-wide
EOF

./scripts/agent-chat-migration/pre_drop_gate_check.sh \
  --source-db nova_memory \
  --target-db agent_chat \
  --user postgres \
  --round-trip-log /tmp/agent_chat_roundtrips.log \
  --consumer-attestation /tmp/agent_chat_consumers.log \
  --gate-pass-marker /run/agent_chat_gate_pass.timestamp
```

Gates:

1. **Row count match** — `agent_chat` and `agent_chat_processed` counts match.
2. **Sequence alignment** — `last_value >= max(id)` and `is_called = true`.
3. **Round-trip freshness** — attestation that all required peers/subagents/Victoria have fresh round-trips.
4. **Zero delta rows** — no unresolved rows in `nova_memory` after the cutoff.
5. **Dependent-object resolution** — `pg_depend` shows only objects in the planned drop list.
6. **Consumer scripts repointed** — attestation that all consumers are on the new DB.

### 7. Decommission old objects in nova_memory

Only after gate check passes:

```bash
./scripts/agent-chat-migration/decommission.sh \
  --source-db nova_memory \
  --target-db agent_chat \
  --user postgres \
  --gate-pass-marker /run/agent_chat_gate_pass.timestamp \
  --i-understand-the-risk
```

The script drops, in order:

1. `job_messages.message_id_fkey`
2. Triggers: `trg_embed_chat_message`, `trg_enforce_agent_chat_function_use`, `trg_enforce_function_use`, `trg_notify_agent_chat`
3. Views: `v_agent_chat_recent`, `v_agent_chat_stats`
4. Functions: `send_agent_message`, `notify_agent_chat`, `enforce_agent_chat_function_use`, `expire_old_chat`, `chat`, `embed_chat_message`
5. Tables: `agent_chat_processed`, `agent_chat`
6. Sequence: `agent_chat_id_seq`
7. Type: `agent_chat_status`

No `CASCADE` is used. If any unexpected dependency remains, the script fails
before dropping tables.

### 8. Post-DROP smoke test

```bash
psql -U nova -d agent_chat -c "SELECT send_agent_message('nova', 'post-DROP smoke test', ARRAY['newhart']);"
psql -U postgres -d nova_memory -c "SELECT count(*) FROM agent_chat;"  # should fail with "relation does not exist"
```

## Rollout-status audit

`scripts/agent-chat-migration/audit_rollout.py` reads each candidate
`~/.openclaw/postgres.json` and resolves which database `agent_chat` would
connect to, using the same nested-section → flat-key fallback as the
plugin and consumer scripts.

```bash
./scripts/agent-chat-migration/audit_rollout.py
```

Sample output:

```
Agent        Status       Database             User            Path
------------------------------------------------------------------------------------------
nova         migrated     agent_chat           nova            /home/nova/.openclaw/postgres.json
newhart      unreadable   None                 None            /home/newhart/.openclaw/postgres.json
             error: [Errno 13] Permission denied: '/home/newhart/.openclaw/postgres.json'
graybeard    unreadable   None                 None            /home/graybeard/.openclaw/postgres.json
             error: [Errno 13] Permission denied: '/home/graybeard/.openclaw/postgres.json'

Summary: 1 migrated, 0 unmigrated, 2 unreadable/missing (of 3 candidates)
```

Peer agents (`newhart`, `graybeard`) run as separate unix users, so a
non-root audit will see permission-denied for their home directories. Run
the audit as root, or run it once per peer as that peer's unix user, to
verify those configs. The script exits non-zero until every candidate is
readable and resolves to the `agent_chat` database.

### Required postgres.json snippet per agent

Every agent must add the nested `agent_chat` section to its
`~/.openclaw/postgres.json`:

```json
{
  "host": "localhost",
  "port": 5432,
  "database": "nova_memory",
  "user": "<agent>",
  "password": "<password>",
  "agent_chat": {
    "database": "agent_chat",
    "user": "<agent>",
    "password": "<password>"
  }
}
```

Only `database`, `user`, and `password` are required inside `agent_chat`;
`host` and `port` fall back to the flat keys (or their defaults) if omitted.

## Rollback notes

Before Step 7, the original `nova_memory` tables still contain all data.
If the migration must be abandoned before decommission:

1. Stop agents from writing to `agent_chat`.
2. Truncate the target tables and rerun `migrate.sh`, or drop the entire
   `agent_chat` database with `DROP DATABASE agent_chat;`.
3. Revert agent configs to remove the `agent_chat` nested section.

After Step 7, rollback requires restoring from backup.

## Design decisions (authoritative)

* New DB name: `agent_chat`.
* Migrated objects: type, both tables, non-duplicate indexes, `agent_chat_id_seq`,
  `send_agent_message`, `notify_agent_chat`, `enforce_agent_chat_function_use`,
  `expire_old_chat`, one enforce trigger, `trg_notify_agent_chat` (ENABLE ALWAYS),
  both views, comments.
* Dropped from `nova_memory` (not migrated): `embed_chat_message()` and
  `trg_embed_chat_message`, `chat()` helper, duplicate index
  `idx_chat_processed_agent`, duplicate trigger `trg_enforce_function_use`,
  `openproject_user` grants.
* Grants: 18 nova-ecosystem roles plus `victoria` (send+receive) and
  `nova-staging` (SEND capability via `send_agent_message` + SELECT).
* `send_agent_message` retains `SECURITY DEFINER`; its owner must have INSERT on
  `agent_chat` in the new DB.
