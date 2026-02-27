# Test Cases — Issue #95: Migrate DB connections to centralized loaders

**Issue:** nova-memory #95
**Depends on:** #94 (pg-env.sh, pg_env.py loaders)
**Author:** Gem (QA Engineer)
**Date:** 2026-02-16

---

## Scope

All scripts and hooks that connect to PostgreSQL must migrate from hardcoded/inline connection logic to the shared loaders (`lib/pg-env.sh`, `lib/pg_env.py`). This document covers test cases for verifying correctness of that migration.

### Files Under Test

**Bash scripts:**
| Script | Current Pattern |
|---|---|
| `scripts/store-memories.sh` | `DB_HOST="localhost"`, `DB_USER="${PGUSER:-$(whoami)}"`, `DB="${DB_USER//-/_}_memory"` |
| `scripts/extract-memories.sh` | `DB_USER="${PGUSER:-$(whoami)}"`, `DB_NAME="${DB_USER//-/_}_memory"`, `psql -h localhost` |
| `scripts/generate-session-context.sh` | `DB_HOST="localhost"`, same user/db pattern |
| `scripts/embed-delegation-facts.sh` | `DB_HOST="localhost"`, same pattern |
| `scripts/get-visible-facts.sh` | `DB_HOST="localhost"`, same pattern |
| `scripts/process-input-with-grammar.sh` | `psql -h localhost`, same user/db pattern |
| `scripts/resolve-participants.sh` | `DB_HOST="localhost"`, same pattern |
| `scripts/test-delegation-memory.sh` | Fully hardcoded: `DB_NAME="nova_memory"`, `DB_USER="nova"`, `DB_HOST="localhost"` |

**Python scripts:**
| Script | Current Pattern |
|---|---|
| `scripts/proactive-recall.py` | `psycopg2.connect(dbname=DB_NAME, host="localhost", user="nova")` |
| `scripts/memory-maintenance.py` | (audit — likely same pattern) |
| `scripts/confidence_helper.py` | (audit) |
| `scripts/dedup_helper.py` | (audit) |

**Hook handlers (TypeScript — shell out to above scripts):**
| Hook | Invocation |
|---|---|
| `hooks/memory-extract/handler.ts` | `exec()` with env prefix: `SENDER_NAME=... extract-memories.sh` |
| `hooks/semantic-recall/handler.ts` | `execSync()` with `env: { ...process.env }` → proactive-recall.py |
| `hooks/session-init/handler.ts` | `exec()` → generate-session-context.sh |

---

## TC-01: Loader sourced/imported before any DB operation

**Objective:** Every migrated script calls the loader before its first `psql` or `psycopg2` call.

| # | Check | Method |
|---|---|---|
| 01.1 | Each `.sh` script contains `source "$(dirname "$0")/../lib/pg-env.sh"` (or equivalent path) followed by `load_pg_env` before any `psql` invocation | `grep -n` for `source.*pg-env.sh` and `load_pg_env` appearing before first `psql` |
| 01.2 | Each `.py` script contains `from lib.pg_env import load_pg_env` (or `sys.path` + import) and calls `load_pg_env()` before any `psycopg2.connect` | `grep -n` for import and call |
| 01.3 | `load_pg_env` is called exactly once per script (not in a loop or conditional that could skip it) | Manual review |

---

## TC-02: Hardcoded connection variables removed

**Objective:** No script defines its own `DB_HOST`, `DB_USER`, `DB_NAME`/`DB`, or hardcodes `host="localhost"` / `user="nova"`.

| # | Check | Method |
|---|---|---|
| 02.1 | `grep -rn 'DB_HOST=' scripts/` returns no matches (except comments) | Automated grep |
| 02.2 | `grep -rn 'DB_USER=\|DB_NAME=\|DB=' scripts/` — no assignment lines remain (variables like `DB` as a local alias to `PGDATABASE` are also removed) | Grep + manual |
| 02.3 | `grep -rn 'host="localhost"\|host=.localhost' scripts/*.py` — no hardcoded host in Python connect calls | Grep |
| 02.4 | `grep -rn 'user="nova"' scripts/*.py` — no hardcoded user in Python connect calls | Grep |
| 02.5 | `psql` calls use no `-h`, `-U`, `-d` flags (rely on PG env vars set by loader) OR use `$PGHOST`, `$PGUSER`, `$PGDATABASE` | Grep for `psql -h`, `psql -U`, `psql -d` |
| 02.6 | Python `psycopg2.connect()` calls use no explicit `host=`, `user=`, `dbname=` args (rely on PG* env vars or libpq defaults) — OR use `os.environ` references | Review connect() calls |

---

## TC-03: Happy path — ENV vars set

**Objective:** Scripts work correctly when `PGHOST`, `PGUSER`, `PGDATABASE` are set in the environment and no `postgres.json` exists.

| # | Precondition | Action | Expected |
|---|---|---|---|
| 03.1 | `PGHOST=localhost PGUSER=nova PGDATABASE=nova_memory`; no `~/.openclaw/postgres.json` | Run `store-memories.sh` with valid JSON | Connects and stores successfully |
| 03.2 | Same env | Run `extract-memories.sh` with sample text | Connects, queries existing facts, calls LLM |
| 03.3 | Same env | Run `proactive-recall.py "test message"` | Connects, returns JSON recall output |
| 03.4 | Same env | Run `generate-session-context.sh` | Connects, generates context file |
| 03.5 | `PGHOST=badhost` (invalid) | Run any script | Fails with connection error (not a crash/traceback about missing variables) |

---

## TC-04: Config file only — no ENV vars

**Objective:** Scripts work when PG* env vars are unset but `~/.openclaw/postgres.json` exists with valid config.

| # | Precondition | Action | Expected |
|---|---|---|---|
| 04.1 | Unset `PGHOST`, `PGUSER`, `PGDATABASE`, `PGPASSWORD`, `PGPORT`; create `~/.openclaw/postgres.json` with `{"host":"localhost","user":"nova","database":"nova_memory"}` | Run `store-memories.sh` with valid JSON | Connects successfully; `PGHOST`/`PGUSER`/`PGDATABASE` set by loader |
| 04.2 | Same setup | Run `proactive-recall.py "test"` | Connects successfully |
| 04.3 | Config file has `port` set to non-default (e.g., `5433`) | Run any script | Uses port 5433 (connection may fail — that's expected; verify it *tried* 5433) |
| 04.4 | Config file is malformed JSON | Run any script | Warning to stderr, falls back to defaults, script doesn't crash |

---

## TC-05: Both ENV and config exist — precedence

**Objective:** ENV vars take precedence over `postgres.json` values, per loader spec.

| # | Precondition | Action | Expected |
|---|---|---|---|
| 05.1 | `PGHOST=envhost`; `postgres.json` has `"host":"confighost"` | Source `pg-env.sh && load_pg_env && echo $PGHOST` | Outputs `envhost` |
| 05.2 | `PGUSER=envuser`; `postgres.json` has `"user":"configuser"` | Same pattern | `PGUSER=envuser` |
| 05.3 | `PGHOST` unset; `postgres.json` has `"host":"confighost"` | Same pattern | `PGHOST=confighost` |
| 05.4 | Both unset, no config file | Same pattern | `PGHOST=localhost` (default) |
| 05.5 | `PGDATABASE=envdb`; config has `"database":"configdb"` | Run `proactive-recall.py` with `load_pg_env()` | `os.environ['PGDATABASE'] == 'envdb'` |

---

## TC-06: Regression — scripts still function correctly

**Objective:** End-to-end behavior is unchanged after migration.

| # | Test | Method |
|---|---|---|
| 06.1 | `store-memories.sh` — insert a fact, verify it exists in DB | Run with test JSON `{"facts":[{"entity":"TestBot","key":"color","value":"blue"}]}`, then query DB |
| 06.2 | `extract-memories.sh` — pass sample text, verify it produces valid JSON output | Run with controlled input, check stdout is valid JSON |
| 06.3 | `proactive-recall.py` — query with a known entity name, verify recall output structure | Run with `"Tell me about TestBot"`, check JSON output has expected keys |
| 06.4 | `get-visible-facts.sh` — verify it returns facts for a known entity | Run with entity name, check output |
| 06.5 | `resolve-participants.sh` — resolve a known phone number | Run with test number, verify entity resolution |
| 06.6 | `generate-session-context.sh` — generates a context file | Run, verify output file is created and non-empty |
| 06.7 | `embed-delegation-facts.sh` — processes delegation facts without error | Run, check exit code 0 |
| 06.8 | `process-input-with-grammar.sh` — runs grammar check pipeline | Run with sample input, verify exit 0 and output |
| 06.9 | `memory-maintenance.py` — runs maintenance cycle | Run, verify no errors |
| 06.10 | `test-delegation-memory.sh` — still reports correct counts | Run, check output format unchanged |

---

## TC-07: Hook → script ENV propagation

**Objective:** When `handler.ts` shells out to bash/python scripts, PG* env vars propagate correctly so the loader resolves them.

| # | Scenario | Check |
|---|---|---|
| 07.1 | `hooks/memory-extract/handler.ts` uses `exec()` with env prefix string: `SENDER_NAME=... SENDER_ID=... script.sh` — this uses shell string, so parent process env is inherited | Verify that if `PGHOST` is set in the Node.js process, the spawned shell script receives it. Test: `PGHOST=testhost node -e "require('child_process').exec('echo $PGHOST', (e,o)=>console.log(o))"` |
| 07.2 | `hooks/semantic-recall/handler.ts` uses `execSync()` with `env: { ...process.env }` — explicit spread | PG* vars from Node process env are forwarded. Verified by code inspection. |
| 07.3 | `hooks/session-init/handler.ts` uses `exec()` without explicit `env` option | Child inherits parent env by default. PG* vars propagate. |
| 07.4 | If `postgres.json` is the only config source (no PG* env vars on the Node process), the child script's loader reads it at runtime | Set up: no PG* env vars, valid `postgres.json`. Trigger hook. Script should connect successfully. |
| 07.5 | `memory-extract/handler.ts` prepends env vars via string (`SENDER_NAME='x' script.sh`). Verify this doesn't *clobber* PG* vars — i.e., only `SENDER_NAME`, `SENDER_ID`, `IS_GROUP` are prepended, not a full env replacement | Code review: confirm no `env:` option on the `exec()` call that would replace inherited env |

---

## TC-08: Edge cases

| # | Scenario | Expected |
|---|---|---|
| 08.1 | `postgres.json` exists but is empty file (`""`) | Loader warns, falls to defaults, script runs |
| 08.2 | `postgres.json` exists but is not readable (permissions `000`) | Loader warns, falls to defaults |
| 08.3 | `~/.openclaw/` directory doesn't exist | Loader skips config silently, uses defaults |
| 08.4 | `PGDATABASE` unset, config has no `database` key | `PGDATABASE` remains unset; `psql` uses its own default (username). Script should still work if DB name matches username. |
| 08.5 | Script is called via `sudo -u otheruser` — `whoami` changes | Loader default for `PGUSER` uses `whoami`/`getpass.getuser()`, which reflects the effective user. `$HOME` may also change, affecting config path. Verify loader handles this. |
| 08.6 | Multiple scripts sourcing the loader in the same shell session (e.g., `extract-memories.sh` calls `store-memories.sh` as a subprocess) | Each invocation calls `load_pg_env` independently. No variable pollution between parent/child since child is a subprocess. |
| 08.7 | `PGPASSWORD` set in env but not in config | Password is used (not overwritten/cleared by loader) |
| 08.8 | Config has `"password": null` | Treated as absent; if `PGPASSWORD` env is set, it's kept; if unset, no password exported |

---

## Verification Script (Automated Checks)

```bash
#!/bin/bash
# Run after migration to verify TC-01 and TC-02 automatically
set -e
SCRIPTS_DIR="$(dirname "$0")/../scripts"
FAIL=0

echo "=== TC-02: Checking for residual hardcoded connection vars ==="
if grep -rn --include='*.sh' 'DB_HOST=' "$SCRIPTS_DIR" | grep -v '^#'; then
  echo "FAIL: DB_HOST= still found"; FAIL=1
fi
if grep -rn --include='*.py' 'host="localhost"' "$SCRIPTS_DIR" | grep -v '^#'; then
  echo "FAIL: host=\"localhost\" still found in Python"; FAIL=1
fi
if grep -rn --include='*.py' 'user="nova"' "$SCRIPTS_DIR" | grep -v '^#'; then
  echo "FAIL: user=\"nova\" still found in Python"; FAIL=1
fi

echo "=== TC-01: Checking loader is sourced/imported ==="
for f in "$SCRIPTS_DIR"/*.sh; do
  if grep -q 'psql ' "$f" && ! grep -q 'load_pg_env' "$f"; then
    echo "FAIL: $f uses psql but doesn't call load_pg_env"; FAIL=1
  fi
done
for f in "$SCRIPTS_DIR"/*.py; do
  if grep -q 'psycopg2' "$f" && ! grep -q 'load_pg_env' "$f"; then
    echo "FAIL: $f uses psycopg2 but doesn't call load_pg_env"; FAIL=1
  fi
done

[ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $FAIL
```

---

## Pass Criteria

- All TC-01 and TC-02 checks pass (automated + manual)
- TC-03 through TC-04: at least one bash and one python script tested end-to-end in each config mode
- TC-05: precedence verified via unit-style shell/python test
- TC-06: all listed scripts exit 0 with valid input
- TC-07: at least one hook tested with env propagation
- TC-08: edge cases 08.1–08.4 verified
