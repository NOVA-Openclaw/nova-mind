# agent-config-sync

An OpenClaw extension plugin that keeps `~/.openclaw/agents.json` in sync with your PostgreSQL database — automatically and in real time.

It watches the `agents` DB table:

- **`agents`** — agent definitions (model, fallback models, allowed subagents, default flag)

When the table changes, the plugin receives a PostgreSQL `NOTIFY` event, rebuilds `agents.json` as a **keyed object**, writes it atomically, and lets the gateway's config file watcher reload it. **The plugin never signals the gateway process.**

> **Note:** The `agent_system_config` table still exists and is used by the gateway, but its values (e.g. `maxSpawnDepth`) are stored directly in `openclaw.json` — they are **not** written to `agents.json`.

> **OpenClaw 2026.11.3+:** When the resolved config uses `agents.ownership = "explicit"`, the plugin writes a managed `agents-explicit.json` include file. It does **not** edit `openclaw.json` automatically; the operator must add `"$include": "./agents-explicit.json"` to enable managed explicit ownership bindings.

---

## What It Does

This plugin keeps `~/.openclaw/agents.json` and agent-specific `HEARTBEAT.md` files in sync with your PostgreSQL database in real time. It reacts to changes in both agent configuration and heartbeat content.

```
DB change (agents, agent_bootstrap_context for HEARTBEAT)
  ├─► trigger fires pg_notify('agent_config_changed')
  │       └─► plugin receives notification (LISTEN)
  │             └─► queries get_agent_export_rows() (session_user-scoped)
  │                   └─► builds keyed entries object (including heartbeat config)
  │                         └─► atomic write (tmp + rename) → agents.json
  │                               └─► gateway config watcher reloads on next observation
  │
  └─► trigger fires pg_notify('heartbeat_content_changed')
          └─► plugin receives notification (LISTEN)
                └─► reads HEARTBEAT content from agent_bootstrap_context
                      └─► writes/updates agent's HEARTBEAT.md file
```

On startup, the plugin performs an **initial sync** for both `agents.json` and all active `HEARTBEAT.md` files, ensuring all configurations are fresh.

---

## Output Format

`agents.json` is a **keyed object** of agent entries matching the OpenClaw 2026.9.x+ `agents.entries` schema. The object key is the agent id; there is no `id` field inside each entry.

### Example output

```json
{
  "main": {
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
  "coder": {
    "model": "openrouter/anthropic/claude-sonnet-4-6"
  },
  "researcher": {
    "model": "openrouter/anthropic/claude-sonnet-4-6"
  }
}
```

### Entry fields

| Field | Source | Notes |
|---|---|---|
| `id` | `agents.name` | Always present |
| `default` | `agents.is_default` | `true` only when `is_default = true`; key **omitted** otherwise |
| `model` | `agents.model` + `agents.fallback_models` | String when no fallbacks; object `{ primary, fallbacks }` when fallbacks present |
| `thinkingDefault` | `agents.thinking` | Included only when `thinking` is a non-empty string matching the config schema's 9-value enum (`off`/`minimal`/`low`/`medium`/`high`/`xhigh`/`adaptive`/`max`/`ultra`, nova-mind#660). `NULL`, empty string, unknown tiers, wrong JS type, mixed case, and whitespace-padded values are all silently omitted — the row degrades gracefully rather than crashing or emitting a bad value. |
| `subagents.allowAgents` | `agents.allowed_subagents` | Included when non-empty, sorted alphabetically |
| `heartbeat` | `agents.heartbeat_enabled`, `heartbeat_every`, `heartbeat_target`, `heartbeat_to` | Object `{ every, target, to }` (non-NULL fields only) when `heartbeat_enabled = true`. **Key is omitted entirely** when `heartbeat_enabled` is `false` or `NULL` (fixed in #273 — OpenClaw's schema requires an object or no key at all, never a boolean `false`). |

**Not included in output:**
- Models allowlist (`agents.defaults.models`) — stays in `openclaw.json`
- System defaults (`agents.defaults.subagents`) — stays in `openclaw.json`

---

## How agents.json Is Loaded

`openclaw.json` uses `$include` at the **`agents.entries`** level to load the generated object:

```json
{
  "agents": {
    "entries": { "$include": "./agents.json" },
    "defaults": {
      "subagents": {
        "maxSpawnDepth": 3
      }
    }
  }
}
```

The `$include` directive merges the keyed object into `agents.entries`. All other `agents.*` keys (defaults, etc.) remain in `openclaw.json` and are unaffected by syncs.

## OpenClaw 2026.11.3+ Explicit Ownership

When the resolved config already uses `agents.ownership = "explicit"`, the plugin writes a managed include file — by default `~/.openclaw/agents-explicit.json` — containing:

- `agents.ownership = "explicit"`
- `agents.defaults.heartbeat` (direct policy / target / agent id)
- `agents.defaults.systemAgent.agentId`
- Top-level `bindings[]` routing every configured channel account to the default peer agent

**Important:** the plugin never edits `openclaw.json` automatically. To enable managed explicit ownership, add the root include directive yourself:

```json
{
  "$include": "./agents-explicit.json",
  "agents": {
    "entries": { "$include": "./agents.json" }
  }
}
```

If `openclaw.json` already contains hand-authored explicit-ownership keys (`agents.ownership`, `agents.defaults.heartbeat`, `agents.defaults.systemAgent`, or `bindings[]`), the plugin logs a one-time instruction and does not manage them, so your hand-written routing is preserved.

A channel that is added by editing `openclaw.json` will get a managed binding only on the next sync — either at the next gateway start or when the plugin receives an `agent_config_changed` NOTIFY.

---

## DB Filter

Agents are scoped per-gateway via `get_agent_export_rows()`:

```sql
SELECT name, model, fallback_models, thinking, instance_type, is_default, allowed_subagents
FROM get_agent_export_rows();
```

The function (defined in nova-mind/database/schema.sql, owned by newhart) uses `session_user`
to scope results: it returns the connecting peer's own row (as `is_default = TRUE`) plus every
subagent where `session_user = ANY(parent_agents)` (as `is_default = FALSE`). This ensures
each peer gateway receives only its own agent set.

The `thinking` column returned here is what `buildAgentsList()` validates and maps to
`thinkingDefault` (nova-mind#660) — see the Entry fields table above.

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
                          ├─► SELECT FROM get_agent_export_rows() (session_user-scoped)
                          │
                          └─► atomic write → agents.json
                                │
                                └─► gateway config watcher reloads on next observation
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
2. Sets `agents.entries = { "$include": "./agents.json" }` in `openclaw.json`
3. Installs the `notify_agent_config_changed()` trigger on the `agents` table
4. Generates the initial `agents.json` from current DB state

To run manually:

```bash
./agent-install.sh
```

### Install steps for Newhart (hand-written ownership / bindings / heartbeat / systemAgent)

If `openclaw.json` already has hand-authored explicit-ownership keys, the plugin will not fight them. To switch to the managed include:

1. Stop the gateway.
2. Back up `~/.openclaw/openclaw.json`.
3. Remove the hand-authored keys you want managed:
   - `agents.ownership`
   - `agents.defaults.heartbeat`
   - `agents.defaults.systemAgent`
   - `bindings[]`
4. Add the root include directive at the top of `openclaw.json`:
   ```json
   {
     "$include": "./agents-explicit.json",
     "agents": {
       "entries": { "$include": "./agents.json" }
     }
   }
   ```
5. Start the gateway. The plugin will write `agents-explicit.json` on startup.
6. Validate the config: `openclaw config validate`.
7. If you want to keep some hand-written bindings, leave them in `openclaw.json` as sibling keys; the plugin will skip generating duplicate matches.

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

## Doctor `--fix` Interactions

When managed explicit ownership is enabled (`"$include": "./agents-explicit.json"` at the root of `openclaw.json`), the keys inside that include are owned by the include file. `openclaw doctor --fix` will refuse to flatten those `$include`-owned values into `openclaw.json`. The affected automatic repairs are:

| Doctor fix | Managed path it touches | How to apply it manually |
|---|---|---|
| Legacy system-agent / ambient-owner migration | `agents.defaults.systemAgent.agentId`, `agents.defaults.heartbeat.agentId` | Edit `agents-explicit.json` (or remove the `$include` and manage these keys by hand). |
| Heartbeat defaults repair | `agents.defaults.heartbeat.*` (e.g. `every`, `directPolicy`, `target`) | Edit `agents-explicit.json`. |
| Ownership mode migration | `agents.ownership` | Edit `agents-explicit.json` or remove the `$include`. |
| Binding repairs (remove missing-agent bindings, `dm`→`direct` peer migration, add default-account bindings) | `bindings[]` | Edit `agents-explicit.json` directly, or keep hand-written bindings as sibling keys in `openclaw.json`. |

The plugin intentionally keeps the managed surface minimal (`agents.ownership`, `agents.defaults.heartbeat`, `agents.defaults.systemAgent`, and `bindings[]`) so everything else in `openclaw.json` remains editable by `openclaw doctor --fix`.

## File Structure

```
focus/agent-config-sync/
├── index.ts          # Plugin entrypoint: LISTEN loop, reconnection, file-watcher reload
├── src/
│   └── sync.ts       # Core logic: query, build, write agents.json / agents-explicit.json
├── scripts/
│   └── report-cutover-drift.ts   # Read-only drift report for cutover planning
├── package.json
├── tsconfig.json
└── openclaw.plugin.json
```

---

## Key Behaviours

- **Keyed object output**: `agents.json` is a keyed object matching `agents.entries`, not a bare array
- **No gateway signals**: The plugin never calls `process.kill(..., "SIGUSR1")`; OpenClaw 2026.11.3's config file watcher reloads after file changes
- **Hands off hand-written config**: If `openclaw.json` already has `agents.ownership`, `agents.defaults.heartbeat`, `agents.defaults.systemAgent`, or `bindings[]`, the plugin leaves them alone
- **Managed explicit ownership via include**: Writes `agents-explicit.json` only when the operator has added `"$include": "./agents-explicit.json"` to `openclaw.json`
- **Atomic writes**: Uses a tmp file + rename to prevent partial reads during write
- **Idempotent sync**: Compares new content to existing file — skips write if identical
- **Graceful error handling**: Invalid DB values are warned about and skipped, never crash
- **Reconnection**: Exponential backoff (5s → 60s) on connection loss
- **Keep-alive**: 30s heartbeat query to detect stale connections early
- **Hot reload**: Gateway config watcher reloads on next observation after every successful write
