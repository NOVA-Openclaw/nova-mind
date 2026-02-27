# Issue #146: DB-to-Config Sync for Agent Model Configuration

## Context

The `agents` table in `nova_memory` is the single source of truth for agent configurations (primary model, fallback models, thinking mode, etc.). OpenClaw reads agent configs from `openclaw.json` at runtime. Currently these are manually kept in sync — when Newhart updates an agent's model in the DB, someone has to manually update the JSON config's `agents.defaults.models` allow-list and `agents.list` entries.

Previously, a `session:pre-spawn` hook (`agent-config-db`) attempted to bridge this gap by dynamically injecting DB config at spawn time. This approach broke when `fallbackModel` was removed upstream (#145 hotfix). Rather than fixing the hook, we're replacing the entire approach with a config sync that keeps `openclaw.json` up to date with the DB at all times.

## Solution

### Part 1: Remove the `agent-config-db` hook entirely

Delete the entire `focus/agent-config-db/` directory from nova-cognition. This hook is no longer used. The `session:pre-spawn` hook event still exists in nova-openclaw for other users — we're just not consuming it anymore.

**Files to delete:**
- `focus/agent-config-db/handler.ts`
- `focus/agent-config-db/HOOK.md`
- Any references in `agent-install.sh` that install this hook

### Part 2: Implement DB-to-Config sync

Create a sync mechanism that:
1. Reads agent configs from the `agents` table (model, fallbacks, thinking)
2. Writes them to the appropriate sections of `openclaw.json`:
   - `agents.defaults.models` — the allow-list of models (populated from all unique models across agents)
   - `agents.list` — per-agent config entries with primary model and fallbacks
3. Triggers on DB changes so the config stays current

The sync leverages OpenClaw's hot-reload (`gateway.reload.mode: "hot"`) so changes take effect without gateway restart.

### Part 3: Installer sets hot-reload as default

`agent-install.sh` should ensure `gateway.reload.mode: "hot"` is set in the OpenClaw config during installation. This is a prerequisite for the sync to work — without hot-reload, config file changes require a manual gateway restart.

**File:** `agent-install.sh` — add config setup step that sets hot-reload mode if not already configured.

## Design Decisions (Resolved)

### Sync trigger: PostgreSQL LISTEN/NOTIFY
Consistent with existing pattern (agent_chat uses the same). A trigger on the `agents` table fires `pg_notify('agent_config_changed', ...)` when model/fallback/thinking columns are updated. A listener catches the notification and writes the updated config.

### Config file: Separate `agents-db.json` via `$include`
OpenClaw natively supports `$include` directives in config files (see `src/config/includes.ts`). Deep merge, JSON5 support, security-scoped to the config directory, and compatible with hot-reload file watching.

- Sync writes to `~/.openclaw/agents.json`
- `openclaw.json` includes it: `"$include": "./agents.json"`
- `agent-install.sh` adds the `$include` directive to `openclaw.json` during installation
- Hot-reload detects the file change and picks up new config
- Main config stays clean — auto-generated agent config is fully separate

### Which agents: Primary + subagents only (NOT peers)
- **primary** (`instance_type = 'primary'`, i.e. nova/main) — our own model config
- **subagents** (`instance_type = 'subagent'`) — agents we spawn (coder, gem, gidget, hermes, etc.)
- **NOT peers** (`instance_type = 'peer'`, i.e. graybeard, newhart) — they have their own gateways and manage their own configs

Peer agents must NOT appear in `agents.list`. Attempting to spawn a peer agent by name should fail — they are reachable via agent_chat, not spawn.

## Prerequisites (DB schema changes — Newhart)

1. **Replace `fallback_model` (VARCHAR) with `fallback_models` (TEXT[])** — supports multiple ordered fallback models matching OpenClaw's `model.fallbacks: string[]`
2. **Create `notify_agent_config_changed()` trigger** — fires `pg_notify('agent_config_changed', ...)` on UPDATE to `model`, `fallback_models`, or `thinking` columns. Does NOT fire on unrelated column changes.
3. **Migrate existing data** — existing `fallback_model` values become single-element arrays in `fallback_models`

## Acceptance Criteria

- [ ] `focus/agent-config-db/` directory completely removed from nova-cognition
- [ ] `agent-install.sh` no longer installs the `agent-config-db` hook
- [ ] Sync mechanism reads agent configs from DB and writes to OpenClaw JSON config
- [ ] `agents.defaults.models` allow-list auto-populated from DB
- [ ] `agents.list` entries auto-populated with per-agent model/fallback/thinking config
- [ ] Hot-reload picks up config changes without gateway restart
- [ ] Manual allow-list maintenance is no longer needed
- [ ] Sync handles: new agents added, existing agents updated, models changed
