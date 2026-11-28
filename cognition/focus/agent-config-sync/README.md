# agent-config-sync

An OpenClaw extension plugin that keeps `~/.openclaw/agents.json` in sync with your PostgreSQL database — automatically and in real time.

> **Requirement:** This plugin requires **OpenClaw >= 2026.11.3** and is shipped together with the fork upgrade. It does not support OpenClaw 2026.9.x or earlier.

> **Heartbeat config:** On OpenClaw **>= 2026.11.5** the strict agent schema rejects the `heartbeat` key, so the plugin automatically stops emitting per-agent `heartbeat` and `agents.defaults.heartbeat`. On OpenClaw **< 2026.11.5** the legacy behaviour is preserved byte-for-byte. See `heartbeatConfigMode` below to override auto-detection.

It watches the `agents` DB table:

- **`agents`** — agent definitions (model, fallback models, allowed subagents, default flag)

When the table changes, the plugin receives a PostgreSQL `NOTIFY` event, rebuilds `agents.json` as a **keyed object**, writes it atomically, and lets the gateway's config file watcher reload it. **The plugin never signals the gateway process.**

> **Note:** The `agent_system_config` table still exists and is used by the gateway, but its values (e.g. `maxSpawnDepth`) are stored directly in `openclaw.json` — they are **not** written to `agents.json`.

> **OpenClaw 2026.11.3:** This plugin always runs in explicit-ownership mode. It writes a managed `agents-explicit.json` include file when enabled. It does **not** edit `openclaw.json` automatically; the operator must add `"$include": "./agents-explicit.json"` to enable managed explicit ownership bindings.

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

`agents.json` is a **keyed object** of agent entries matching the OpenClaw 2026.11.3+ `agents.entries` schema. The object key is the agent id; there is no `id` field inside each entry.

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
| `default` | `agents.is_default` | **Never emitted.** OpenClaw 2026.11.3+ uses explicit ownership (`agents.defaults.systemAgent` and `bindings`) instead of the legacy `default:true` marker. |
| `model` | `agents.model` + `agents.fallback_models` | String when no fallbacks; object `{ primary, fallbacks }` when fallbacks present |
| `thinkingDefault` | `agents.thinking` | Included only when `thinking` is a non-empty string matching the config schema's 9-value enum (`off`/`minimal`/`low`/`medium`/`high`/`xhigh`/`adaptive`/`max`/`ultra`, nova-mind#660). `NULL`, empty string, unknown tiers, wrong JS type, mixed case, and whitespace-padded values are all silently omitted — the row degrades gracefully rather than crashing or emitting a bad value. |
| `subagents.allowAgents` | `agents.allowed_subagents` | Included when non-empty, sorted alphabetically |
| `heartbeat` | `agents.heartbeat_enabled`, `heartbeat_every`, `heartbeat_target`, `heartbeat_to` | Object `{ every, target, to }` (non-NULL fields only) when `heartbeat_enabled = true` **and** the plugin is in `legacy` mode. **Key is omitted entirely** when `heartbeat_enabled` is `false` or `NULL`, and also omitted in `retired` mode regardless of the DB flag (nova-mind#824 — OpenClaw >= 2026.11.5 rejects the key). |

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

## OpenClaw 2026.11.3 Explicit Ownership

The plugin always writes the managed include file when enabled — by default `~/.openclaw/agents-explicit.json` — containing:

- `agents.ownership = "explicit"`
- `agents.defaults.heartbeat` (direct policy / target / agent id) — **omitted on OpenClaw >= 2026.11.5** because the strict agent schema rejects this key
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

There are two supported install paths. Choose the one that matches your peer.

### Procedure 1 — Zero-edit (peers that already own their routing)

Use this for a peer such as **Newhart** whose `openclaw.json` already contains
hand-authored explicit-ownership keys (`agents.ownership`,
`agents.defaults.systemAgent`, `agents.defaults.heartbeat`, root `bindings[]`)
or a hand-written default-agent heartbeat policy. The plugin detects those
surfaces and does not manage them, so your hand-authored routing stays in control.

1. Make sure the plugin is enabled in `openclaw.json`:
   ```json
   {
     "plugins": {
       "entries": {
         "agent_config_sync": {
           "enabled": true
         }
       }
     }
   }
   ```
   A bare `{}` merge leaves `enabled: false`; you must set `enabled: true` explicitly.
2. Verify `agents.entries` loads the generated file:
   ```json
   {
     "agents": {
       "entries": { "$include": "./agents.json" }
     }
   }
   ```
3. Restart the gateway.
4. Validate the config: `openclaw config validate`.

The plugin writes `agents.json` only. It does not manage ownership, systemAgent,
bindings, or heartbeat defaults; your hand-authored routing stays in control.
No `$include` for `agents-explicit.json` is needed for this procedure.

### Procedure 2 — Move routing to the managed include

Use this if you want the plugin to own `agents.ownership`,
`agents.defaults.heartbeat`, `agents.defaults.systemAgent`, and managed
`bindings[]`. Because 11.3 fails to **load** (exit 1, no `doctor` offer) when a
root `$include` points to a missing file, you must create the include file and
add the `$include` directive in **one edit**, then validate, then restart.
Never add the `$include` across a restart.

1. Stop the gateway.
2. Back up `~/.openclaw/openclaw.json`.
3. Create `~/.openclaw/agents-explicit.json` with the keys you are moving. For
   example, if `newhart` is the default peer:
   ```json
   {
     "agents": {
       "ownership": "explicit",
       "defaults": {
         "heartbeat": {
           "directPolicy": "block",
           "target": "none",
           "agentId": "newhart"
         },
         "systemAgent": {
           "agentId": "newhart"
         }
       }
     },
     "bindings": []
   }
   ```
4. In the **same edit**, add the root `$include` to `openclaw.json` and remove
   the keys you just moved so they are not duplicated:
   ```json
   {
     "$include": "./agents-explicit.json",
     "agents": {
       "entries": { "$include": "./agents.json" }
     }
   }
   ```
5. Run `openclaw config validate`. If validation fails, fix the config before
   restarting; do not start the gateway with a missing include target.
6. Start the gateway. The plugin will keep `agents-explicit.json` in sync.
7. If you want to keep some hand-written bindings, leave them as sibling keys in
   `openclaw.json`; the plugin will skip generating duplicate matches.

### Installer

`agent-install.sh` automates Procedure 1 on fresh peers. To run it manually:

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
          "outputPath": "/home/nova/.openclaw/agents.json",
          "heartbeatConfigMode": "auto"
        }
      }
    }
  }
}
```

If `config` is omitted, the plugin falls back to `channels.agent_chat` DB credentials.

### `heartbeatConfigMode`

| Value | Behaviour |
|---|---|
| `auto` (default) | Detect the host OpenClaw version from the gateway executable's `package.json`. Use `legacy` mode for versions `< 2026.11.5` and `retired` mode for versions `>= 2026.11.5`. If detection fails, the plugin falls back to `retired` (safe default) and logs one WARN line. |
| `legacy` | Always emit per-agent `heartbeat` and `agents.defaults.heartbeat` as on pre-fix OpenClaw < 2026.11.5. Use this to pin behaviour on a fleet whose auto-detection is unreliable. |
| `retired` | Never emit heartbeat config. Use this on OpenClaw >= 2026.11.5 or when you want to guarantee no `heartbeat` key is written. |

The boundary is **inclusive** at `2026.11.5`. Prerelease and fork suffixes (e.g. `2026.11.10-nova`) are classified by their numeric core version, so a fork-tagged 11.10 host is treated the same as a clean 11.10 host.

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
