# Agent Config Sync — DB-to-Config Listener

LISTEN/NOTIFY-driven sync that keeps `~/.openclaw/agents.json` (and, when
enabled, the OpenClaw 2026.11.3+ explicit-ownership include) in sync with the
`agents` table, plus per-agent `HEARTBEAT.md` workspace files in sync with
`agent_bootstrap_context`.

> See `README.md` in this directory for the full field reference, the
> `heartbeatConfigMode` table, and installation procedures. This file covers
> listener internals: the notification flow and the host-version detection
> used for heartbeat compatibility (nova-mind#824).

## How It Works

1. **Startup** — The plugin connects to PostgreSQL, resolves the heartbeat
   compatibility mode (see below), then runs `LISTEN agent_config_changed`
   and `LISTEN heartbeat_content_changed`. It performs an **initial sync** of
   `agents.json`, the explicit-ownership include (only if the operator has
   added the root `$include`), and all agent `HEARTBEAT.md` workspace files.

2. **On `agent_config_changed`** — The trigger fires
   `pg_notify('agent_config_changed', ...)` whenever any column changes on the
   `agents` table. The plugin queries `get_agent_export_rows()`, which scopes
   results to the connecting role (`session_user`) and subagents owning that
   role via `parent_agents` array overlap, and rewrites `agents.json`. It also
   re-syncs the explicit-ownership include and all HEARTBEAT workspace files.
   The function lives in `nova-mind/database/schema.sql` and is owned by
   newhart.

3. **On `heartbeat_content_changed`** — The trigger fires when
   `agent_bootstrap_context` rows with `file_key = 'HEARTBEAT'` are inserted
   or updated. The plugin syncs the affected agent's workspace `HEARTBEAT.md`
   file from the database content.

4. **Atomic writes** — `agents.json`, the explicit-ownership include, and
   HEARTBEAT files are all written to a temp file first, then `rename(2)`-d
   into place to prevent partial reads. `agents.json` and the explicit-ownership
   include are validated BEFORE the rename so an invalid generated file can
   never be promoted where a watcher could pick it up.

5. **Gateway hot-reload** — Because `openclaw.json`'s `agents.entries` uses
   `"$include": "./agents.json"`, the gateway's config file watcher picks up
   the change and hot-reloads the `agents.*` config keys on its next
   observation. **The plugin never signals the gateway process** (no
   `SIGUSR1`, no `process.kill`); HEARTBEAT.md updates likewise need no signal
   since the gateway reads the file fresh on each heartbeat cycle.

## Output Format (`agents.json`)

`agents.json` is a **keyed object** matching the OpenClaw 2026.11.3+
`agents.entries` schema — `{ "<id>": { model, thinkingDefault?, subagents?,
heartbeat? } }` — not a bare array, and there is no `id` field inside each
entry (the object key **is** the id). The legacy `default: true` marker is
never emitted; default-agent ownership is expressed via
`agents.defaults.systemAgent` and `bindings` in the explicit-ownership
include instead. See `README.md`'s "Output Format" section for the full
per-field mapping and an example.

## Heartbeat Compatibility Mode (nova-mind#824)

OpenClaw >= **2026.11.5** removed the `heartbeat` key from the strict agent
schema entirely; writing it is a fatal config-load failure on that host, not
merely an unused key. The plugin resolves a `HeartbeatCompatMode` once per
listener lifetime (a live host upgrade without a full gateway restart is
picked up on the plugin's next start):

- **`legacy`** (host `< 2026.11.5`) — per-agent `heartbeat` and
  `agents.defaults.heartbeat` are emitted exactly as before nova-mind#824.
- **`retired`** (host `>= 2026.11.5`) — neither key is ever emitted.
  `validateExplicitOwnershipConfig()` no longer requires the heartbeat
  sub-keys, and a stale `agents.defaults.heartbeat` left over from a prior
  legacy-mode write is exempted from the hand-authored-ownership-key check
  (it no longer blocks managed explicit-ownership mode).

### Host version detection

`detectHostHeartbeatCompat()` reads the host OpenClaw version from the
package.json of the gateway process that loaded the plugin, starting from
`process.argv[1]`, in two passes:

1. **Pass 1** walks up every ancestor directory looking only for a package
   root literally named `openclaw` (`<dir>/package.json` with
   `name === "openclaw"`); the nearest such root wins. This covers a
   source-checkout host, where the authoritative `package.json` sits at the
   checkout root next to `openclaw.mjs`.
2. **Pass 2** runs only if pass 1 finds nothing, and looks instead for a
   `<dir>/node_modules/openclaw/package.json` dependency copy. This covers a
   global-install host where the gateway binary is a separate package that
   depends on `openclaw`.

Running pass 1 to completion before starting pass 2 prevents a nested
`node_modules/openclaw` copy further down the tree from shadowing the true
package root further up (TC-824-V-22).

Every candidate path — and the plugin's own directory root, resolved via
`fileURLToPath(import.meta.url)` — is `realpathSync`'d before comparison, so
the plugin's own bundled `openclaw` dev/peer dependency (pinned at
`2026.2.9` in `package.json`) is never mistaken for the host version, even
when the plugin directory itself is reached via a symlink (TC-824-V-23).

When no version can be read at all, detection falls back to `retired` with
one WARN line: a false "legacy" write on a retired host is a fatal
gateway-down failure, while a false "retired" omission on an ambiguous host
only degrades (loses heartbeat config; the gateway still starts).

### Operator override

Plugin config `heartbeatConfigMode` (`"auto"` | `"legacy"` | `"retired"`,
enum-enforced by the host at config load via `openclaw.plugin.json`'s
`configSchema`) overrides detection: `"auto"` (default) uses the detected
mode; `"legacy"`/`"retired"` pin it explicitly. If a value outside that enum
somehow reaches the plugin at runtime, `resolveHeartbeatCompatMode()` falls
back to the detected mode and logs one WARN naming the bad value and the
allowed set (TC-824-V-21) — it never throws or silently defaults.

## Output Format (`agents.json`) — DB Columns

```sql
-- Columns on `agents` table (subset relevant to this plugin):
--   name                        VARCHAR
--   model                       VARCHAR
--   fallback_models             TEXT[]
--   thinking                    VARCHAR
--   instance_type               VARCHAR   ('primary' | 'subagent' | 'peer')
--   parent_agents               TEXT[]    (peer agent names that own this subagent)
--   is_default                  BOOLEAN
--   allowed_subagents           TEXT[]
--   heartbeat_enabled           BOOLEAN   (DEFAULT false)
--   heartbeat_every             TEXT      (e.g. '5m', '15m')
--   heartbeat_target            TEXT      (e.g. 'discord')
--   heartbeat_to                TEXT      (e.g. 'channel:1504054635231445112')
--   heartbeat_isolated_session  BOOLEAN   (#714; column may not exist pre-migration-088 — the
--                                          plugin detects this and falls back to a query without it)

-- Triggers:
--   agent_config_changed     -> pg_notify('agent_config_changed', ...)
--   heartbeat_content_changed -> pg_notify('heartbeat_content_changed', ...)
--     (fires on agent_bootstrap_context INSERT/UPDATE WHERE file_key = 'HEARTBEAT')
```

These `heartbeat_*` columns are **unchanged and still read** by
`fetchAgentRows()`/`get_agent_export_rows()` regardless of host version — in
`retired` mode they are simply never written back out to `agents.json` or
the explicit-ownership include. A table-to-Automations-job sync for retired
hosts (where heartbeat cadence instead lives in `openclaw cron list --all`-
visible jobs, which `openclaw doctor` migrates legacy config into) is
deferred to a follow-up issue, not implemented by this plugin.

## Plugin Config

The plugin reads its PostgreSQL connection from its own `config` block in
`openclaw.json`, falling back to the `agent_chat` channel config if omitted:

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
          "password": "",
          "heartbeatConfigMode": "auto"
        }
      }
    }
  }
}
```

## Installation

Handled automatically by `agent-install.sh` (Procedure 1 — zero-edit). See
`README.md`'s "Installation" section for both supported install procedures
and the `heartbeatConfigMode` reference table.
