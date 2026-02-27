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

## Resolution Order

Every loader follows the same precedence:

1. **Environment variables** — `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
2. **Config file** — `~/.openclaw/postgres.json`
3. **Defaults** — `localhost` for host, `5432` for port, current OS user for username

Empty environment strings are treated as unset (fall through to step 2).  
Null/missing JSON values are treated as absent (fall through to step 3).  
`PGDATABASE` and `PGPASSWORD` have no built-in defaults.

## Loader Functions

### Bash

```bash
source ~/.openclaw/lib/pg-env.sh
load_pg_env
# PG* env vars are now set; use psql, pg_dump, etc. directly
psql -c "SELECT 1"
```

### Python

```python
import sys; sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
from pg_env import load_pg_env

load_pg_env()
# os.environ now has PG* vars; use psycopg2, asyncpg, etc.
import psycopg2
conn = psycopg2.connect()  # reads PG* env vars automatically
```

### TypeScript

```typescript
import { loadPgEnv } from "~/.openclaw/lib/pg-env";

loadPgEnv();
// process.env now has PG* vars; node-postgres reads them automatically
import { Pool } from "pg";
const pool = new Pool(); // uses PGHOST, PGPORT, etc.
```

### Custom config path

All loaders accept an optional path argument to override the default location:

- Bash: not supported (reads `~/.openclaw/postgres.json` only)
- Python: `load_pg_env(config_path="/custom/path.json")`
- TypeScript: `loadPgEnv("/custom/path.json")`

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
  └─ source ~/.openclaw/lib/pg-env.sh → load_pg_env() → reads postgres.json → creates DB & runs migrations

hooks & scripts
  └─ source ~/.openclaw/lib/pg-env.sh (or import equivalent) → PG* vars set → use psql/psycopg2/pg natively
```

## Error Handling

- **Malformed JSON** — warned on stderr, config file ignored, falls through to defaults
- **Missing file** — silently falls through to env vars and defaults
- **Permission denied** — warned on stderr, falls through to defaults

## Security Notes

- The config file may contain a plaintext password. Ensure `~/.openclaw/` has `700` permissions.
- Prefer peer authentication or env vars in production over storing passwords in the file.
