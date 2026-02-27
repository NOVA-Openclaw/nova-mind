# agent-config-sync

An OpenClaw extension plugin that keeps `~/.openclaw/agents.json` in sync with your PostgreSQL database — automatically and in real time.

It watches the `agents` DB table:

- **`agents`** — agent definitions (model, fallback models, allowed subagents, default flag)

When the table changes, the plugin receives a PostgreSQL `NOTIFY` event, rebuilds `agents.json` as a **bare JSON array**, writes it atomically, and signals the gateway to reload (`SIGUSR1`).

> **Note:** The `agent_system_config` table still exists and is used by the gateway, but its values (e.g. `maxSpawnDepth`) are stored directly in `openclaw.json` — they are **not** written to `agents.json`.

---

## What It Does

```
DB change
  └─► trigger fires pg_notify('agent_config_changed')
        └─► plugin receives notification (LISTEN)
              └─► queries agents WHERE instance_type != 'peer'
                    └─► builds bare JSON array
                          └─► atomic write (tmp + rename) → agents.json
                                └─► SIGUSR1 → gateway hot-reload
```

On startup the plugin performs an **initial sync** so `agents.json` is always fresh, even before any DB change occurs.

---

## Output Format

`agents.json` is a **bare JSON array** of agent entries. There is no wrapping object.

### Example output

```json
[
  {
    "id": "main",
    "default": true,
    "model": {
      "primary": "openrouter/anthropic/claude-opus-4-6",
      "fallbacks": [
        "openrouter/anthropic/claude-sonnet-4-6"
      ]
    },
    "subagents": {
      "allowAgents": ["coder", "researcher"]
    }
  },
  {
    "id": "coder",
    "model": "openrouter/anthropic/claude-sonnet-4-6"
  },
  {
    "id": "researcher",
    "model": "openrouter/anthropic/claude-sonnet-4-6"
  }
]
```

### Entry fields

| Field | Source | Notes |
|---|---|---|
| `id` | `agents.name` | Always present |
| `default` | `agents.is_default` | `true` only when `is_default = true`; key **omitted** otherwise |
| `model` | `agents.model` + `agents.fallback_models` | String when no fallbacks; object `{ primary, fallbacks }` when fallbacks present |
| `subagents.allowAgents` | `agents.allowed_subagents` | Included when non-empty, sorted alphabetically |

**Not included in output:**
- Models allowlist (`agents.defaults.models`) — stays in `openclaw.json`
- System defaults (`agents.defaults.subagents`) — stays in `openclaw.json`

---

## How agents.json Is Loaded

`openclaw.json` uses `$include` at the **`agents.list`** level to load the array:

```json
{
  "agents": {
    "list": { "$include": "./agents.json" },
    "defaults": {
      "subagents": {
        "maxSpawnDepth": 3
      }
    }
  }
}
```

The `$include` directive splices the bare array directly into `agents.list`. All other `agents.*` keys (defaults, etc.) remain in `openclaw.json` and are unaffected by syncs.

---

## DB Filter

Only non-peer agents are synced:

```sql
WHERE instance_type != 'peer'
  AND model IS NOT NULL
```

Peer agents (connected remote instances) are excluded — they are managed dynamically by the gateway, not via `agents.json`.

---

## agent_system_config Table

This table exists and stores system-wide configuration, but its values are **not synced to `agents.json`**. They are applied directly to `openclaw.json` at install time and managed there.

### Schema

```sql
CREATE TABLE agent_system_config (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    value_type TEXT NOT NULL DEFAULT 'text',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### Supported Keys

| DB key | JSON path | value_type | Notes |
|---|---|---|---|
| `max_spawn_depth` | `agents.defaults.subagents.maxSpawnDepth` | `integer` | Set in `openclaw.json`, not in `agents.json` |
| `max_concurrent_subagents` | `agents.defaults.subagents.maxConcurrent` | `integer` | Reserved for future use |

---

## Notification Flow

The `agents` table has an unconditional trigger that fires on **any row change** (INSERT, UPDATE, or DELETE on any column):

```
DB INSERT / UPDATE / DELETE on agents
  │
  └─► trigger: notify_agent_config_changed()
        │
        └─► pg_notify('agent_config_changed', '{"agent_id":..., "operation":"UPDATE"}')
              │
              └─► plugin receives notification
                    │
                    └─► syncAgentsConfig()
                          │
                          ├─► SELECT WHERE instance_type != 'peer'
                          │
                          └─► atomic write → agents.json
                                │
                                └─► SIGUSR1 → gateway hot-reload
```

### SQL Trigger

The trigger is unconditional — it fires on any change to any column:

```sql
CREATE OR REPLACE FUNCTION notify_agent_config_changed()
RETURNS trigger AS $$
BEGIN
    PERFORM pg_notify('agent_config_changed', json_build_object(
        'agent_id', COALESCE(NEW.id, OLD.id),
        'agent_name', COALESCE(NEW.name, OLD.name),
        'operation', TG_OP
    )::text);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS agent_config_changed ON agents;
CREATE TRIGGER agent_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agents
    FOR EACH ROW EXECUTE FUNCTION notify_agent_config_changed();
```

> **Why unconditional?** Previously the trigger only fired when specific columns changed (model, fallback_models, etc.). Now that `is_default` and `allowed_subagents` are also synced, the trigger fires on any change and lets the plugin decide what to write. This avoids missed updates when new columns are added.

---

## Installation

The installer (`agent-install.sh`) handles everything automatically:

1. Installs and builds the `agent_config_sync` extension plugin
2. Sets `agents.list = { "$include": "./agents.json" }` in `openclaw.json`
3. Installs the `notify_agent_config_changed()` trigger on the `agents` table
4. Generates the initial `agents.json` from current DB state

To run manually:

```bash
./agent-install.sh
```

---

## Plugin Configuration

Configure in `openclaw.json` under `plugins.entries.agent_config_sync.config`:

```json
{
  "plugins": {
    "entries": {
      "agent_config_sync": {
        "config": {
          "host": "localhost",
          "port": 5432,
          "database": "nova",
          "user": "nova",
          "password": "...",
          "outputPath": "/home/nova/.openclaw/agents.json"
        }
      }
    }
  }
}
```

If `config` is omitted, the plugin falls back to `channels.agent_chat` DB credentials.

---

## File Structure

```
focus/agent-config-sync/
├── index.ts          # Plugin entrypoint: LISTEN loop, reconnection, SIGUSR1 reload
├── src/
│   └── sync.ts       # Core logic: query, build, write agents.json
├── package.json
├── tsconfig.json
└── openclaw.plugin.json
```

---

## Key Behaviours

- **Bare array output**: `agents.json` is a plain JSON array, not a wrapped object
- **Atomic writes**: Uses a tmp file + rename to prevent partial reads during write
- **Idempotent sync**: Compares new content to existing file — skips write if identical
- **Graceful error handling**: Invalid DB values are warned about and skipped, never crash
- **Reconnection**: Exponential backoff (5s → 60s) on connection loss
- **Keep-alive**: 30s heartbeat query to detect stale connections early
- **Hot reload**: Sends `SIGUSR1` to gateway process after every successful write
