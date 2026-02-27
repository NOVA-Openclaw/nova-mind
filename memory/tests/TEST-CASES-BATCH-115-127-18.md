# Test Cases: Batch SE — #115 / #127 / #18

**Created:** 2026-02-16  
**Author:** Gem (QA)  
**Scope:** env-loader integration into standalone scripts, POSTGRES_*→PG* migration  
**Note:** env-loader internals tested in #98 (28 cases). These tests focus on *integration* only.  
**Revised:** 2026-02-16 — per NOVA feedback (relaxed pattern checks, resolver flexibility, added 18-I14, X-06, replaced 127-A05)

---

## 1. nova-memory #115 — Bash Scripts (env-loader)

Scripts: extract-memories.sh, memory-catchup.sh, embed-delegation-facts.sh, test-delegation-memory.sh, store-memories.sh, process-input.sh, process-input-with-grammar.sh

| ID | Description | Steps | Expected Result | Pass/Fail Criteria |
|----|-------------|-------|-----------------|-------------------|
| 115-B01 | env-loader block present in all 7 bash scripts | `grep -l "env-loader.sh" <each script>` | All 7 scripts contain the env-loader pattern | All 7 match |
| 115-B02 | env-loader block placed before any API key usage | For each script, confirm env-loader source line appears before first use of OPENAI_API_KEY or similar | env-loader runs before vars are needed | Line number of loader < line number of first API key ref |
| 115-B03 | pg-env loader still present alongside env-loader | `grep -l "pg-env" <each script>` | Both pg-env and env-loader blocks coexist | Both patterns found in all 7 |
| 115-B04 | Script runs normally with env-loader lib present | Set up `~/.openclaw/lib/env-loader.sh` + valid `openclaw.json`. Run script (e.g. `extract-memories.sh --help` or dry mode) | Script starts, loads env, no errors from loader | Exit 0 or normal operation |
| 115-B05 | Script runs when env-loader lib is missing | Remove/rename `~/.openclaw/lib/env-loader.sh`. Run any of the 7 scripts | Script continues (guard `[ -f "$ENV_LOADER" ]` skips missing loader). Falls back to existing env vars | No crash, no "file not found" error |
| 115-B06 | Script runs when openclaw.json is missing | env-loader.sh exists but `~/.openclaw/openclaw.json` is absent. Run script | env-loader loads but finds no config; script continues with ambient env | No crash |
| 115-B07 | Pre-set env vars take precedence | `export OPENAI_API_KEY=manual-test-key`. Run script with env-loader that would set a different value | Script uses the pre-set value (env-loader doesn't overwrite existing) | `echo $OPENAI_API_KEY` inside script = "manual-test-key" |
| 115-B08 | env-loader pattern contains 3 essential elements | Inspect each script's loader block | Pattern includes all 3 elements: (a) `ENV_LOADER` path variable set (pointing to `~/.openclaw/lib/env-loader.sh`), (b) file existence check (`[ -f "$ENV_LOADER" ]`), (c) `load_openclaw_env` call. May be multi-line or condensed — form doesn't matter, presence of all 3 elements does | All 3 elements present in all 7 scripts |

## 2. nova-memory #115 — Python Scripts (env-loader)

Scripts: proactive-recall.py, memory-maintenance.py, confidence_helper.py, dedup_helper.py

| ID | Description | Steps | Expected Result | Pass/Fail Criteria |
|----|-------------|-------|-----------------|-------------------|
| 115-P01 | env-loader block present in all 4 python scripts | `grep -l "env_loader" <each script>` | All 4 contain the python env-loader pattern | All 4 match |
| 115-P02 | Import placed before any API key usage | Check that `load_openclaw_env()` call precedes first `os.environ.get('OPENAI_API_KEY')` or similar | Loader runs first | Line number check |
| 115-P03 | pg_env loader still present alongside env-loader | `grep -l "pg_env" <each script>` | Both pg_env and env_loader imports coexist | Both found |
| 115-P04 | Script runs with env-loader lib present | `python3 <script> --help` or dry-run mode | Normal operation | Exit 0 |
| 115-P05 | Script runs when env_loader.py is missing | Remove `~/.openclaw/lib/env_loader.py`. Run script | Script should handle ImportError gracefully (try/except or conditional) | No crash from missing import |
| 115-P06 | Script runs when openclaw.json missing | env_loader.py exists, no openclaw.json | Loader finds no config, script continues | No crash |
| 115-P07 | Pre-set env vars preserved | `OPENAI_API_KEY=test python3 <script>` | Pre-set value not overwritten | Var retains value |
| 115-P08 | Python pattern contains 3 essential elements | Inspect each script's loader block | Pattern includes all 3 elements: (a) `sys.path.insert` adding `~/.openclaw/lib` to path, (b) `from env_loader import load_openclaw_env` (or equivalent import), (c) `load_openclaw_env()` call. May be split across lines with try/except wrapping — form doesn't matter, presence of all 3 elements does | All 3 elements present in all 4 scripts |
| 115-P09 | sys.path insertion is idempotent | If script is imported multiple times or path already contains the lib dir | No duplicate path entries cause issues | Script works regardless |

## 3. nova-memory #115 — POSTGRES_*→PG* (test-entity-resolution.js)

| ID | Description | Steps | Expected Result | Pass/Fail Criteria |
|----|-------------|-------|-----------------|-------------------|
| 115-J01 | No POSTGRES_* references remain | `grep -n "POSTGRES_" hooks/semantic-recall/test-entity-resolution.js` | Zero matches | grep returns empty |
| 115-J02 | All 4 PG vars used correctly | grep for PGHOST, PGDATABASE, PGUSER, PGPASSWORD | All 4 present | 4 matches |
| 115-J03 | Mapping is correct | POSTGRES_HOST→PGHOST, POSTGRES_DB→PGDATABASE, POSTGRES_USER→PGUSER, POSTGRES_PASSWORD→PGPASSWORD | Each old var maps to correct new var | Manual review |
| 115-J04 | Script connects to DB with PG* vars set | Export PGHOST/PGDATABASE/PGUSER/PGPASSWORD, run the test script | Successful DB connection | Script completes or connects |
| 115-J05 | Script fails gracefully with PG* vars unset | Unset all PG* vars, run script | Clear error message about missing connection config | No undefined behavior |

## 4. nova-cognition #127 — Audit & Pattern Establishment

| ID | Description | Steps | Expected Result | Pass/Fail Criteria |
|----|-------------|-------|-----------------|-------------------|
| 127-A01 | shell-aliases.sh does NOT need env-loader | Review `scripts/shell-aliases.sh` — it only defines aliases, no API key or DB usage | No env-loader added (not needed) | Confirmed no API/DB refs |
| 127-A02 | No hooks need env-loader | `find hooks/ -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" \)` — review each for API key or standalone execution | No hooks require env-loader (they run inside OpenClaw which sets env) | Audit documented |
| 127-A03 | No plugins need env-loader | `find plugins/ -type f` — review | No plugins require env-loader | Audit documented |
| 127-A04 | Audit results documented | Issue #127 contains audit findings | Clear statement of what was checked and why nothing needed changes | Documentation exists |
| 127-A05 | agent-install.sh checks for loader libs as prerequisite | Review `agent-install.sh` in nova-cognition. It should verify `~/.openclaw/lib/` loader files exist before proceeding (same pattern as #18 — nova-cognition also depends on nova-memory) | Prerequisite check present; missing libs → clear error referencing nova-memory | Check block exists, error message is actionable |

## 5. nova-relationships #18 — Prerequisite Check (agent-install.sh)

| ID | Description | Steps | Expected Result | Pass/Fail Criteria |
|----|-------------|-------|-----------------|-------------------|
| 18-I01 | All 3 loader files present → install proceeds | Create `~/.openclaw/lib/pg-env.sh`, `pg_env.py`, `pg-env.ts`. Run `agent-install.sh` | Install continues past prerequisite check | No error about missing loaders |
| 18-I02 | All 3 loader files missing → install fails | Remove all 3 files. Run `agent-install.sh` | Fails with clear error listing missing files and stating nova-memory is prerequisite | Non-zero exit, error message mentions nova-memory |
| 18-I03 | Only pg-env.sh present (2 missing) | Only `pg-env.sh` exists. Run install | Fails, lists the 2 missing files | Error names `pg_env.py` and `pg-env.ts` |
| 18-I04 | Only pg_env.py present (2 missing) | Only `pg_env.py` exists | Fails, lists the 2 missing files | Error names `pg-env.sh` and `pg-env.ts` |
| 18-I05 | Only pg-env.ts present (2 missing) | Only `pg-env.ts` exists | Fails, lists the 2 missing files | Error names `pg-env.sh` and `pg_env.py` |
| 18-I06 | 2 of 3 present (pg-env.ts missing) | `pg-env.sh` + `pg_env.py` exist, `pg-env.ts` missing | Fails, lists only the 1 missing file | Error names only `pg-env.ts` |
| 18-I07 | Files exist but are empty (0 bytes) | Touch all 3 files (empty). Run install | Install proceeds (existence check only, not content validation) | Passes prereq check |
|     | | | **Note:** Content validation is intentionally out of scope here — the loader functions themselves handle malformed content. | |
| 18-I08 | Files are symlinks → accepted | All 3 are symlinks to valid targets | Install proceeds (`[ -f ]` follows symlinks) | Passes prereq check |
| 18-I09 | POSTGRES_USER export removed | `grep "POSTGRES_USER" agent-install.sh` | Zero matches | grep empty |
| 18-I10 | POSTGRES_DB export removed | `grep "POSTGRES_DB" agent-install.sh` | Zero matches | grep empty |
| 18-I11 | PGUSER export present at former line ~237 | `grep "PGUSER" agent-install.sh` | Found, exports PGUSER | Match found |
| 18-I12 | PGDATABASE export present at former line ~238 | `grep "PGDATABASE" agent-install.sh` | Found, exports PGDATABASE | Match found |
| 18-I13 | No other POSTGRES_* refs remain in agent-install.sh | `grep "POSTGRES_" agent-install.sh` | Zero matches anywhere in file | grep empty |
| 18-I14 | ~~MOVED to nova-relationships #19~~ | Stale `~/.openclaw/workspace/` path references are a separate concern (hardcoded workspace paths). Tracked in #19, not part of this batch | N/A | N/A |

## 6. nova-relationships #18 — resolver.ts (POSTGRES_*→PG* + loadPgEnv)

| ID | Description | Steps | Expected Result | Pass/Fail Criteria |
|----|-------------|-------|-----------------|-------------------|
| 18-R01 | No POSTGRES_* references remain | `grep "POSTGRES_" lib/entity-resolver/resolver.ts` | Zero matches | grep empty |
| 18-R02 | All 4 PG vars used | grep PGHOST, PGDATABASE, PGUSER, PGPASSWORD | All 4 present | 4 matches |
| 18-R03 | PG env is available at runtime (loadPgEnv preferred) | Inspect resolver.ts for either approach: **(a) Preferred:** imports `loadPgEnv` from `~/.openclaw/lib/pg-env.ts` (via path resolution — e.g. `import { loadPgEnv } from "${homedir}/.openclaw/lib/pg-env.ts"` or constructed path) and calls it before DB connection. **(b) Acceptable:** relies on process-level pg-env already loaded at startup (no import needed since the calling process runs loadPgEnv). Verify the import path, if present, resolves to `~/.openclaw/lib/pg-env.ts` | Either approach works. If (a), import resolves correctly and call precedes connection. If (b), no loadPgEnv import/call present and PG* vars are assumed available | Code review — prefer (a) for standalone safety |
| 18-R04 | loadPgEnv() called before DB connection (if approach a) | If loadPgEnv is imported, verify invocation precedes connection setup | Env loaded before use | Line number check (skip if approach b) |
| 18-R05 | Resolver connects with PG* vars | Set PG* vars, run entity resolution | Successful DB connection and query | Resolver functions |
| 18-R06 | Resolver fails clearly with no PG* vars | Unset all PG* vars, no pg-env loader available | Clear connection error | Meaningful error message |
| 18-R07 | Mapping correctness | POSTGRES_HOST→PGHOST, POSTGRES_DB→PGDATABASE, POSTGRES_USER→PGUSER, POSTGRES_PASSWORD→PGPASSWORD | 1:1 correct mapping | Manual review |

## 7. Cross-Issue Integration

| ID | Description | Steps | Expected Result | Pass/Fail Criteria |
|----|-------------|-------|-----------------|-------------------|
| X-01 | nova-memory installed before nova-relationships | Install nova-memory first (creates loader libs), then nova-relationships | Relationships prereq check passes | Clean install |
| X-02 | nova-relationships installed WITHOUT nova-memory | Fresh system, install nova-relationships only | Fails at prereq check with actionable error | Error says "install nova-memory first" |
| X-03 | No POSTGRES_* refs remain across all 3 repos | `grep -r "POSTGRES_" <each repo>` excluding test case files and changelogs | Zero matches in runtime code | grep empty (excluding docs/tests) |
| X-04 | All modified scripts still function end-to-end | Run representative script from each repo in a configured environment | Scripts execute, connect to DB, use API keys | Normal operation |
| X-05 | env-loader + pg-env coexist without conflict | Both loaders active in same script execution | No var clobbering, both load their respective configs | Both sets of vars available |
| X-06 | Full POSTGRES_* sweep across all 3 repos | Run `grep -r "POSTGRES_" --include='*.ts' --include='*.js' --include='*.sh' --include='*.py'` across nova-memory, nova-relationships, nova-cognition (exclude node_modules, test case docs, changelogs) | ZERO hits in runtime code | grep returns empty after exclusions |

---

**Total: 49 test cases**  
- #115 Bash: 8  
- #115 Python: 9  
- #115 JS: 5  
- #127 Audit: 5  
- #18 Install: 14  
- #18 Resolver: 7  
- Cross-issue: 6  

**Changes in this revision:**  
- 115-B08: Relaxed from character-exact to 3-element presence check  
- 115-P08: Relaxed from character-exact to 3-element presence check  
- 18-R03/R04: Updated to accept either loadPgEnv import or process-level loading (prefer loadPgEnv)  
- 127-A05: Replaced docs test with agent-install.sh prerequisite check for nova-cognition  
- 18-I07: Added note that content validation is intentionally out of scope  
- 18-I14: New — verify stale `~/.openclaw/workspace/` paths updated in agent-install.sh error messages  
- X-06: New — full POSTGRES_* sweep across all 3 repos  
