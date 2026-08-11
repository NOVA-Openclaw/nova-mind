# Database Configuration

## Overview

nova-memory uses a centralized configuration file (`~/.openclaw/postgres.json`) so that all components — shell scripts, Python hooks, TypeScript extensions — share the same database credentials without hardcoding.

## Config File

**Location:** `~/.openclaw/postgres.json`

```json
{
  "host": "localhost",
  "port": 5432,
  "database": "nova_memory",
  "user": "nova",
  "password": "secret"
}
```

All fields are optional. Missing fields fall through to environment variables or built-in defaults.

## Nested Sections (Multiple Databases)

Since nova-mind#330/#320, `postgres.json` can carry additional named, nested
objects alongside the flat top-level keys — one per additional database a
component needs to reach. Inside nova-mind the primary consumer is
**`bootstrap`** (#488: lets the db-bootstrap-context hook query a different
database than an agent's primary DB, so a split agent like `newhart` — whose
primary DB is `newhart_memory` — can still load `agent_bootstrap_context` rows
from `nova_memory`; see `cognition/focus/bootstrap-context/hook/HOOK.md` for
the hook-side detail, including unknown-key handling that `loadPgEnv()` itself
does not provide). The **`agent_chat`** section is still used by the optional
agent_chat bus plugin, but that plugin now lives in the
`NOVA-Openclaw/agent-chat` repo and is only installed when a bus is detected
(see "Optional agent_chat Bus Peer Integration" below):

```json
{
  "host": "localhost",
  "port": 5432,
  "database": "nova_memory",
  "user": "nova",
  "password": "secret",
  "bootstrap": {
    "database": "nova_memory",
    "user": "nova",
    "password": "secret"
  }
}
```

Only `database`, `user`, and `password` are typically needed inside a nested
section — `host` and `port` fall back to the top-level flat keys (or their
defaults) if omitted from the section. Every loader function accepts an
optional `section` parameter; when given, fields inside that named object take
precedence over the top-level flat keys. **As of nova-mind#403, Python and
TypeScript agree on per-field section-over-ENV precedence** — see "Resolution
Order" below. Bash still has no section support at all. See "Loader Functions"
below for the exact call signature per language.

## Optional agent_chat Bus Peer Integration (nova-mind#579)

`agent-install.sh` no longer owns the `agent_chat` schema, migrations, plugin,
or OpenClaw config injection. Those moved to the `NOVA-Openclaw/agent-chat`
repository.

If a bus is present, `agent-install.sh` detects it and delegates to the peer
repo checkout:

1. **Detection** — the bus is "present" when `postgres.json` contains an
   `agent_chat` nested section **and** the configured database is reachable using
   the same connection params as the memory DB.
2. **Sibling-checkout resolution** — the peer repo is expected at
   `${AGENT_CHAT_REPO:-$HOME/agent-chat}`. Set `AGENT_CHAT_REPO` to point
   elsewhere if the checkout lives in a non-default location.
3. **Registration** — `register-agent.sh <agent>` creates the DB role, grants,
   and `.pgpass` entry for the current agent.
4. **Plugin install** — `install-plugin.sh` builds the TypeScript plugin, syncs
   it to `~/.openclaw/extensions/agent_chat`, writes the nested `agent_chat`
   section of `postgres.json`, and injects the stripped-down
   `channels.agent_chat` / `plugins.entries.agent_chat` config keys into
   `openclaw.json`.

If the bus is absent, the installer skips these steps silently (one
informational line), writes no `agent_chat` artifacts, and exits successfully.
If the bus is configured but unreachable, or if the peer checkout is missing,
the installer prints a clear warning and continues — the bus is optional.

For a from-scratch bus install, run the `NOVA-Openclaw/agent-chat` installer
instead of `agent-install.sh`.

## Resolution Order

**As of nova-mind#403, Python and TypeScript share the same per-field resolution order.** (Python got there first via #405; #403 ported the identical contract to the TypeScript `loadPgEnv()` copies in `lib/pg-env.ts` and `memory/lib/pg-env.ts`. The agent_chat plugin's copy now lives in the `NOVA-Openclaw/agent-chat` repo at `plugin/lib/pg-env.ts`.) Bash remains the odd one out — see below.

### Python (`lib/pg_env.py` / `memory/lib/pg_env.py`) and TypeScript (`lib/pg-env.ts` / `memory/lib/pg-env.ts` / `NOVA-Openclaw/agent-chat/plugin/lib/pg-env.ts`) — per-field precedence

Resolution happens **per field**, not once for the whole config:

1. **Nested section field** (if a `section` name is passed to the loader, the config file has a matching object at that key, **and that object explicitly defines this specific field** as non-null/non-empty) — wins over ENV for that field only
2. **Environment variables** — `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
3. **Config file top-level (flat) keys** — `~/.openclaw/postgres.json`
4. **Defaults** — `localhost` for host, `5432` for port, current OS user for username

A field the section **omits** is unaffected by the section at all — it falls through to the normal ENV → flat-config → default chain, exactly as if no section had been requested. This is why it's a *per-field* rule rather than a single global switch: a section that only sets `database` still lets ENV win for `host`/`port`/`user`/`password`.

This closes the gap that used to let a pre-exported ambient var (e.g. a gateway shell already exporting `PGDATABASE=nova_memory`) override a TypeScript-side `section` value — the agent_chat plugin's `src/channel.ts` (now in `NOVA-Openclaw/agent-chat`) calls `loadPgEnv(undefined, "agent_chat")` and is a confirmed beneficiary; it now reliably resolves the `agent_chat` database section even when `PGDATABASE` is set in the environment.

### Bash (`pg-env.sh`) — no section support

Bash has no section support at all (see the Bash loader note below) — only the flat top-level keys and the ENV → flat-config → default chain apply.

### Shared rules (all languages)

Empty environment strings are treated as unset (fall through to the next applicable step).  
Null/missing JSON values are treated as absent (fall through to the next step).  
If a `section` value exists but is not a JSON object, a warning is printed and
the loader falls back to the top-level flat keys.  
`PGDATABASE` and `PGPASSWORD` have no built-in defaults.

## Loader Functions

### Bash

```bash
source ~/.openclaw/lib/pg-env.sh
load_pg_env
# PG* env vars are now set; use psql, pg_dump, etc. directly
psql -c "SELECT 1"
```

> **No section support in Bash.** `pg-env.sh` does not currently support the
> nested-section feature described above — it only reads top-level flat keys.
> Scripts that need the optional `agent_chat` DB from Bash should read the nested
> JSON directly with `jq` (e.g. `jq -r '.agent_chat.database' ~/.openclaw/postgres.json`)
> rather than relying on `load_pg_env`.

### Python

```python
import sys; sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
from pg_env import load_pg_env

load_pg_env()
# os.environ now has PG* vars; use psycopg2, asyncpg, etc.
import psycopg2
conn = psycopg2.connect()  # reads PG* env vars automatically
```

With a nested section (e.g. to resolve the `agent_chat` database):

```python
load_pg_env(section="agent_chat")
# os.environ PG* vars now point at the agent_chat DB instead of the flat/default config.
# A later call with a different (or no) section fully overwrites these -- no stale values leak.
conn = psycopg2.connect()
```

> **Import path: deployed copy vs. repo-relative.** The `sys.path.insert(0,
> "~/.openclaw/lib")` pattern above imports whichever `pg_env.py` is currently
> *deployed* to the home directory by `agent-install.sh` — fine for scripts
> that only ever run post-install. Repo-internal scripts that must always run
> against the current repo checkout (e.g. `motivation/scripts/proactive-gate-check.py`
> and, as of #405, `cognition/scripts/pg-notify-listener.py`) instead resolve
> `lib/` relative to their own file location so they never silently pick up a
> stale deployed copy. **#406** tracks migrating the remaining hardcoded-path
> callers under `memory/scripts/` and `memory/templates/` to the same
> repo-relative pattern.

### TypeScript

```typescript
import { loadPgEnv } from "~/.openclaw/lib/pg-env";

const pgConfig = loadPgEnv();
// pgConfig is a connection-options object for pg.Client/pg.Pool -- does NOT
// mutate process.env, avoiding pollution for child processes/subagents.
import { Client } from "pg";
const client = new Client(pgConfig);
```

With a nested section:

```typescript
const agentChatConfig = loadPgEnv(undefined, "agent_chat");
const client = new Client(agentChatConfig);
```

This is exactly the pattern the agent_chat plugin (`NOVA-Openclaw/agent-chat/plugin/src/channel.ts`) uses to
resolve its dedicated database connection (`loadPgEnv(undefined, "agent_chat")`).

### Custom config path

All loaders accept an optional path argument to override the default location,
and (except Bash) an optional `section` argument:

- Bash: only the default path is supported (reads `~/.openclaw/postgres.json` only); no section support
- Python: `load_pg_env(config_path="/custom/path.json", section="agent_chat")`
- TypeScript: `loadPgEnv("/custom/path.json", "agent_chat")`

## How It Fits Together

```
shell-install.sh
  └─ Sources lib/pg-env.sh early (load_pg_env available throughout)
  └─ Prompts for DB credentials → writes ~/.openclaw/postgres.json
  └─ Calls load_pg_env() → tests reachability via psql
  └─ Warns if PGPASSWORD is empty for a TCP host
  └─ Exits (non-zero) if config needed but stdin is not a TTY
  └─ execs agent-install.sh

agent-install.sh
  └─ Installs lib/ → ~/.openclaw/lib/
  └─ source ~/.openclaw/lib/pg-env.sh → load_pg_env() → reads postgres.json → creates memory DB & runs migrations
  └─ Detects optional agent_chat bus (postgres.json section/DB probe)
  └─ If present, invokes ${AGENT_CHAT_REPO:-$HOME/agent-chat}/register-agent.sh then install-plugin.sh

hooks & scripts
  └─ source ~/.openclaw/lib/pg-env.sh (or import equivalent) → PG* vars set → use psql/psycopg2/pg natively
```

## Error Handling

- **Malformed JSON** — warned on stderr, config file ignored, falls through to defaults
- **Missing file** — silently falls through to env vars and defaults
- **Permission denied** — warned on stderr, falls through to defaults
- **Section value present but not a JSON object** — warned on stderr, falls back to top-level flat keys (as if no section had been requested)

## Security Notes

- The config file may contain a plaintext password (in both the flat top-level keys and any nested section such as `agent_chat`). Ensure `~/.openclaw/` has `700` permissions and `postgres.json` itself is mode `600`.
- Prefer peer authentication or env vars in production over storing passwords in the file.
- When the optional bus is present, the peer repo's `install-plugin.sh` provisions the `~/.pgpass` entry and the `postgres.json` `agent_chat` section, so most installs never need to hand-edit passwords into this file.
