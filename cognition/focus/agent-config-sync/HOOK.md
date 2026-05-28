# Agent Config Sync — DB-to-Config Listener

Replaces the old `agent-config-db` pre-spawn/pre-run hook with a
LISTEN/NOTIFY-driven sync that writes `~/.openclaw/agents.json`.

## How It Works

1. **Startup** — The plugin connects to PostgreSQL and runs
   `LISTEN agent_config_changed` and `LISTEN heartbeat_content_changed`.
   It performs an **initial sync** of both `agents.json` and all agent
   `HEARTBEAT.md` workspace files.

2. **On `agent_config_changed`** — The trigger fires
   `pg_notify('agent_config_changed', ...)` whenever any column changes on the
   `agents` table. The plugin queries `get_agent_export_rows()`, which scopes
   results to the connecting role (session_user) and subagents owning that role
   via `parent_agents` array overlap, and rewrites `agents.json`. It also
   syncs all HEARTBEAT workspace files. The function lives in
   nova-mind/database/schema.sql and is owned by newhart.

3. **On `heartbeat_content_changed`** — The trigger fires when
   `agent_bootstrap_context` rows with `file_key = 'HEARTBEAT'` are inserted
   or updated. The plugin syncs the affected agent's workspace `HEARTBEAT.md`
   file from the database content.

4. **Atomic writes** — Both JSON and HEARTBEAT files are written to a temp
   file first, then `rename(2)`-d into place to prevent partial reads.

5. **Gateway hot-reload** — Because `openclaw.json` uses
   `"$include": "./agents.json"`, the gateway's config file watcher picks up
   the change and hot-reloads the `agents.*` config keys. SIGUSR1 is sent
   after agents.json updates. HEARTBEAT file updates do not require SIGUSR1
   (the gateway reads the file on each heartbeat cycle).

## Output Format (`agents.json`)

```json
{
  "agents": {
    "defaults": {
      "models": {
        "openrouter/anthropic/claude-opus-4.6": {},
        "openrouter/google/gemini-3-flash-preview": {}
      }
    },
    "list": [
      {
        "id": "coder",
        "model": {
          "primary": "openrouter/anthropic/claude-sonnet-4.6",
          "fallbacks": ["openrouter/openai/gpt-5.2-codex"]
        }
      },
      {
        "id": "gem",
        "model": "openrouter/google/gemini-3-flash-preview"
      }
    ]
  }
}
```

### Rules

| Condition | `model` value |
|-----------|--------------|
| No fallbacks (NULL or `{}`) | Plain string: `"openrouter/..."` |
| Has fallbacks | Object: `{ "primary": "...", "fallbacks": ["..."] }` |

- `agents.defaults.models` is an allow-list of **all** unique models
  (primaries + every fallback).
- Results are scoped per-gateway: `get_agent_export_rows()` returns the connecting
  peer's own row (as `is_default = TRUE`) plus subagents linked to that peer via
  `parent_agents` array overlap. Peers and their own subagents both appear in their
  respective agents.json.
- Fallback order is preserved from the DB array.

## DB Schema Requirements

```sql
-- Columns on `agents` table:
--   name               VARCHAR
--   model              VARCHAR
--   fallback_models    TEXT[]
--   thinking           VARCHAR
--   instance_type      VARCHAR   ('primary' | 'subagent' | 'peer')
--   parent_agents      TEXT[]    (peer agent names that own this subagent)
--   heartbeat_enabled  BOOLEAN   (DEFAULT false)
--   heartbeat_every    TEXT      (e.g. '5m', '15m')
--   heartbeat_target   TEXT      (e.g. 'discord')
--   heartbeat_to       TEXT      (e.g. 'channel:1504054635231445112')

-- Triggers:
--   agent_config_changed → pg_notify('agent_config_changed', ...)
--   heartbeat_content_changed → pg_notify('heartbeat_content_changed', ...)
--     (fires on agent_bootstrap_context INSERT/UPDATE WHERE file_key = 'HEARTBEAT')
```

## Plugin Config

The plugin reads its PostgreSQL connection from the **agent_chat** plugin
config in `openclaw.json`:

```jsonc
{
  "plugins": {
    "entries": {
      "agent_config_sync": {
        "enabled": true,
        "config": {
          "database": "nova_memory",
          "host": "localhost",
          "port": 5432,
          "user": "nova",
          "password": ""
        }
      }
    }
  }
}
```

If no dedicated config is provided, it falls back to `channels.agent_chat`
connection settings.

## Installation

Handled automatically by `agent-install.sh`.  The installer:

1. Copies the plugin source to `~/.openclaw/extensions/agent_config_sync/`
2. Builds TypeScript
3. Adds `"$include": "./agents.json"` to `openclaw.json`
4. Generates `agents.json` only if the file does not already exist
   (use `--regenerate-agents-json` to force regeneration with backup)
5. The plugin handles ongoing sync via LISTEN/NOTIFY at runtime
