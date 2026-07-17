---
name: db-bootstrap-context
description: "Loads agent bootstrap context from PostgreSQL database"
metadata: {"openclaw":{"events":["agent:bootstrap"]}}
---

# Database Bootstrap Context Hook

Loads agent context from PostgreSQL database instead of filesystem files.

## How It Works

1. Intercepts `agent:bootstrap` event (fires before agent session starts)
2. Loads PostgreSQL connection settings from `~/.openclaw/postgres.json`
3. If a `bootstrap` section exists, uses it to choose the bootstrap database
4. Queries `get_agent_bootstrap(agent_name)` against the resolved database
5. Returns universal context + agent-specific context
6. Falls back to static files in `~/.openclaw/bootstrap-fallback/` if database unavailable
7. Uses emergency minimal context if everything fails

## Database Table

- `agent_bootstrap_context` - All bootstrap context (UNIVERSAL, GLOBAL, DOMAIN, AGENT types)

## Bootstrap Database Override

Agents whose `postgres.json` points at their own primary DB (for example
`newhart_memory`) can force the bootstrap-context hook to query a different
database for `agent_bootstrap_context` rows by adding a `bootstrap` section to
`~/.openclaw/postgres.json`:

```json
{
  "host": "localhost",
  "port": 5432,
  "database": "newhart_memory",
  "user": "newhart",
  "password": "",
  "bootstrap": {
    "database": "nova_memory"
  }
}
```

### Resolution order

Connection fields are resolved **per-field** in this order:

1. `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` environment variables
2. The matching key inside the `bootstrap` section (e.g. `bootstrap.database`)
3. The matching flat/top-level key in `postgres.json`
4. Built-in defaults (`localhost:5432`, `nova_memory`, current OS user)

Only the fields you want to override need to be present in the `bootstrap`
section. Omitted fields fall back to the flat keys or defaults as usual.

### Whitespace-only values are ignored

Values that contain only whitespace are treated as absent and fall back to the
next source. This prevents accidental blank strings from being passed to the
PostgreSQL driver as host or database names.

### Unknown keys are rejected with a warning

If the `bootstrap` section contains an unrecognized key (for example a typo
like `datbase` instead of `database`), the hook logs a warning naming that key,
ignores it, and still honors any valid keys in the same section. The warning is
non-fatal — the hook always degrades to fallback files rather than crashing.

### Environment-variable sharp edge

Because environment variables always win, a stray `PGDATABASE` in the gateway
process environment will silently override the `bootstrap.database` value and
send bootstrap queries to the wrong database. Always check `env` (or the
`env.vars` section of `~/.openclaw/openclaw.json`) before debugging a
configured override that does not seem to take effect.

### pg-env loader failure

If `~/.openclaw/lib/pg-env.ts` cannot be loaded at all, the override cannot be
applied. The hook falls back to a hardcoded literal
(`localhost:5432/nova_memory`) and emits a distinct log line when a `bootstrap`
section was present, so operators can tell the override was ignored because the
loader was broken rather than because of a syntax error in the section.

### Multi-file hooks: use explicit `.ts` specifiers for sibling imports

This hook is split across two files (`handler.ts` and `bootstrap-pg-config.ts`).
OpenClaw's hook loader imports the entry file via Node's native ESM `import()`
with type-stripping (Node 22+), which does **not** remap a `.js` specifier to a
sibling `.ts` file the way bundler-based tooling does. A sibling import written
as `from './bootstrap-pg-config.js'` fails at load time with `Cannot find
module '.../bootstrap-pg-config.js'`, even though the `.ts` file exists right
next to it — because single-file hooks (`memory-extract`, `session-init`) never
exercise this path, the defect only surfaces once a hook is split into multiple
files. **Any future multi-file hook must import sibling modules with the
explicit `.ts` extension** (`from './bootstrap-pg-config.ts'`), not `.js` and
not extension-less. Test files that import the same sibling module should use
the same `.ts` specifier so the source works identically under `npx tsx --test`
and `node --test`.

## Fallback System

Three-tier fallback:
1. **Database** - Primary source (via `get_agent_bootstrap()`)
2. **Static files** - `~/.openclaw/bootstrap-fallback/*.md`
3. **Emergency context** - Minimal recovery instructions

## Owner

Newhart (NHR Agent) - Non-Human Resources
