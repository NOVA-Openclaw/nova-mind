# Agent Config Sync — DB-to-Config Listener

Replaces the old `agent-config-db` pre-spawn/pre-run hook with a
LISTEN/NOTIFY-driven sync that writes `~/.openclaw/agents.json`.

## How It Works

1. **Startup** — The plugin connects to PostgreSQL and runs
   `LISTEN agent_config_changed`.  It also performs an **initial sync** so the
   config file reflects current DB state on gateway start.

2. **On notification** — The `agents_config_changed` trigger fires
   `pg_notify('agent_config_changed', ...)` whenever `model`,
   `fallback_models`, `thinking`, or `instance_type` change on the `agents`
   table.  The plugin queries the table and rewrites `agents.json`.

3. **Atomic writes** — The JSON is written to a temp file first, then
   `rename(2)`-d into place to prevent partial reads by the gateway.

4. **Gateway hot-reload** — Because `openclaw.json` uses
   `"$include": "./agents.json"`, the gateway's config file watcher picks up
   the change and hot-reloads the `agents.*` config keys (which are classified
   as `"none"` / no-restart in the reload rules).

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
- Peer agents (`instance_type = 'peer'`) are **excluded**.
- Fallback order is preserved from the DB array.

## DB Schema Requirements

```sql
-- Columns on `agents` table:
--   name            VARCHAR
--   model           VARCHAR
--   fallback_models TEXT[]
--   thinking        VARCHAR
--   instance_type   VARCHAR   ('primary' | 'subagent' | 'peer')

-- Trigger (already in place):
--   agents_config_changed → pg_notify('agent_config_changed', ...)
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
4. Runs an initial sync to generate `agents.json`
