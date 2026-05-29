# Test Cases: Nova-Mind Embeddings Batch (Issues #223, #233, #235, #245, #258, #259, #278)

**QA Designer:** Gem  
**SE Run:** #12  
**Scripts Under Test:**
- `memory/scripts/memory-maintenance.py` (primary)
- `memory/scripts/embed-full-database.py` (deprecated, maintained)
- `memory/scripts/embedding-config.json`

**Schema verified against:** nova_memory PostgreSQL (staging)  
**Date:** 2026-05-28

---

## Pre-Conditions & Test Environment

- All tests run on staging (`nova-staging@localhost`) — never production
- Staging must have `nova_memory` database with current schema applied
- Ollama must be available on `http://localhost:11434` for embedding tests  
  (or mocked — see TC-278-* for offline tests)
- Seed data SQL provided inline where exact row state matters
- All tests run in transactions; roll back after unless stated otherwise

---

## Issue #223 — Unify Embedding Model to snowflake-arctic-embed2

### TC-223-01: Config file uses correct model after change

**Type:** Happy path  
**Preconditions:** Fix applied to `embedding-config.json`  
**Input:** `cat memory/scripts/embedding-config.json`  
**Expected:**
```json
{
  "provider": "ollama",
  "model": "snowflake-arctic-embed2",
  "base_url": "http://localhost:11434",
  "dimensions": 1024
}
```
**Fail if:** `mxbai-embed-large` appears anywhere in the file, or `dimensions` ≠ 1024

---

### TC-223-02: Fallback in load_embedding_config() uses new model

**Type:** Edge case — config file absent  
**Preconditions:** Fix applied to `memory-maintenance.py`; `embedding-config.json` temporarily renamed/removed  
**Input:**
```bash
python3 -c "
import sys; sys.path.insert(0, 'memory/scripts')
# Remove config temporarily
import os, shutil
shutil.move('memory/scripts/embedding-config.json', '/tmp/ec.json.bak')
from memory_maintenance import load_embedding_config
cfg = load_embedding_config()
shutil.move('/tmp/ec.json.bak', 'memory/scripts/embedding-config.json')
print(cfg['model'])
"
```
**Expected:** Prints `snowflake-arctic-embed2`  
**Fail if:** Prints `mxbai-embed-large` or raises an exception

---

### TC-223-03: Config file present — loaded model overrides fallback

**Type:** Happy path  
**Preconditions:** `embedding-config.json` present with `snowflake-arctic-embed2`  
**Input:** Call `load_embedding_config()` normally  
**Expected:** Returns `{"model": "snowflake-arctic-embed2", "dimensions": 1024, ...}`  
**Fail if:** Returns fallback values or mismatch on model name

---

### TC-223-04: embed-full-database.py uses config model (not hardcoded fallback)

**Type:** Regression — no model hardcoding  
**Preconditions:** Fix applied  
**Input:**
```bash
grep -n "mxbai-embed-large" memory/scripts/embed-full-database.py
grep -n "mxbai-embed-large" memory/scripts/memory-maintenance.py
```
**Expected:** Both greps return zero matches (exit code 1, no output)  
**Fail if:** Any match found — the old model name must be eliminated from both scripts

---

## Issue #233 — Remove Stale trading_signals Reference

### TC-233-01: trading_signal removed from TABLE_EMBED_SPECS (memory-maintenance.py)

**Type:** Code removal verification  
**Preconditions:** Fix applied  
**Input:**
```bash
grep -n "trading_signal" memory/scripts/memory-maintenance.py
```
**Expected:** Zero matches  
**Fail if:** Any match found

---

### TC-233-02: trading_signal removed from TABLES_TO_EMBED (embed-full-database.py)

**Type:** Code removal verification  
**Preconditions:** Fix applied  
**Input:**
```bash
grep -n "trading_signal" memory/scripts/embed-full-database.py
```
**Expected:** Zero matches  
**Fail if:** Any match found

---

### TC-233-03: memory-maintenance.py embed phase completes without error when trading_signals table absent

**Type:** Runtime regression — confirms no crash on removed entry  
**Preconditions:** `trading_signals` table does not exist in staging schema; fix applied  
**Input:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup --skip-entity-dedup --verbose --force
```
**Expected:** Script exits 0; no `relation "trading_signals" does not exist` error in output  
**Fail if:** Any Postgres error about trading_signals, or non-zero exit code

---

### TC-233-04: embed-full-database.py completes without error when trading_signals table absent

**Type:** Runtime regression  
**Preconditions:** Same as TC-233-03  
**Input:**
```bash
python3 memory/scripts/embed-full-database.py
```
**Expected:** Script exits 0; no reference to trading_signals in output (no crash)  
**Fail if:** Any Postgres error about trading_signals, or non-zero exit code

---

## Issue #235 — Add Missing Tables

*Schema confirmed: `journal_entries` (content), `music_works` (title, description), `workflow_runs` (trigger_context, notes), `income_sources` (name, description) all exist in nova_memory.*

### TC-235-01: journal_entries embedded by memory-maintenance.py

**Type:** Happy path — new table  
**Preconditions:** Fix applied; seed data inserted:
```sql
INSERT INTO journal_entries (content, trigger) VALUES ('Test journal entry for embedding', 'manual');
```
**Input:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup --skip-entity-dedup --verbose --force
```
**Expected:**
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'journal_entry';
-- Returns >= 1
```
**Fail if:** `journal_entry` source_type has 0 rows in memory_embeddings after run

---

### TC-235-02: music_works embedded with title + description by memory-maintenance.py

**Type:** Happy path — new table  
**Preconditions:** Seed:
```sql
INSERT INTO music_works (title, description) VALUES ('Test Song', 'A test music work for embedding');
INSERT INTO music_works (title) VALUES ('Title Only Song');
```
**Expected:**
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'music_work';
-- Returns 2
```
Check content of embedding for first row includes both title and description in the embedded text.  
**Fail if:** 0 rows embedded, or title-only row skipped when it should be included

---

### TC-235-03: workflow_runs embedded with trigger_context + notes

**Type:** Happy path — new table  
**Preconditions:** Seed:
```sql
INSERT INTO workflow_runs (workflow_id, trigger_context, notes, channel) 
  VALUES (1, 'User triggered SE workflow', 'Step 3 complete', 'discord');
INSERT INTO workflow_runs (workflow_id, trigger_context, notes, channel)
  VALUES (1, NULL, NULL, 'discord');
```
**Expected:**  
- Row with trigger_context + notes → embedded  
- Row with both NULL → behavior determined by implementation (should skip or embed gracefully — verify no crash)  
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'workflow_run';
-- Returns >= 1
```
**Fail if:** Script crashes on NULL trigger_context/notes

---

### TC-235-04: income_sources embedded with name + description

**Type:** Happy path — new table  
**Preconditions:** Seed:
```sql
INSERT INTO income_sources (name, description, status) VALUES ('Contract Work', 'Software consulting', 'active');
INSERT INTO income_sources (name, status) VALUES ('Name Only Source', 'active');
```
**Expected:**
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'income_source';
-- Returns 2
```
**Fail if:** 0 rows embedded

---

### TC-235-05: portfolio_snapshots NOT added to either script

**Type:** Negative / scope verification  
**Preconditions:** Fix applied  
**Input:**
```bash
grep -n "portfolio_snapshot" memory/scripts/memory-maintenance.py
grep -n "portfolio_snapshot" memory/scripts/embed-full-database.py
```
**Expected:** Zero matches in both files  
**Fail if:** Any match found — this table was explicitly excluded per issue spec

---

### TC-235-06: All four new tables present in embed-full-database.py TABLES_TO_EMBED

**Type:** Code presence verification  
**Preconditions:** Fix applied  
**Input:**
```bash
grep -n -E "journal_entr|music_work|workflow_run|income_source" memory/scripts/embed-full-database.py
```
**Expected:** At least 4 matches (one per table)  
**Fail if:** Any of the four tables missing from embed-full-database.py

---

### TC-235-07: All four new tables present in memory-maintenance.py TABLE_EMBED_SPECS

**Type:** Code presence verification  
**Input:**
```bash
grep -n -E "journal_entr|music_work|workflow_run|income_source" memory/scripts/memory-maintenance.py
```
**Expected:** At least 4 matches  
**Fail if:** Any of the four tables missing

---

## Issue #245 — Fix lessons Column

### TC-245-01: memory-maintenance.py TABLE_EMBED_SPECS["lesson"] queries lessons.lesson column

**Type:** Code correctness  
**Preconditions:** Fix applied  
**Input:**
```bash
grep -A3 '"lesson"' memory/scripts/memory-maintenance.py | grep "FROM lessons"
```
**Expected:** Line contains `lesson AS text` (not `content AS text`)  
**Fail if:** `content` column still referenced in lesson query

---

### TC-245-02: Lessons rows actually embed after fix (would fail on old column name)

**Type:** Happy path — runtime correctness  
**Preconditions:** Seed:
```sql
INSERT INTO lessons (lesson, context) VALUES ('Test lesson text for embedding', 'test context');
```
**Input:** Run memory-maintenance.py with `--skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup --skip-entity-dedup --verbose --force`  
**Expected:**
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'lesson';
-- Returns >= 1
```
**Fail if:** `column lessons.content does not exist` error, or 0 rows embedded for lessons

---

### TC-245-03: embed-full-database.py already uses correct lessons.lesson column (regression guard)

**Type:** Regression — no regression on already-correct script  
**Input:**
```bash
grep -n "FROM lessons" memory/scripts/embed-full-database.py
```
**Expected:** Line contains `lesson` column reference, NOT `content`  
**Fail if:** `content` column referenced in lessons query in embed-full-database.py

---

### TC-245-04: NULL lesson rows skipped gracefully

**Type:** Edge case  
**Preconditions:** Seed:
```sql
-- lessons.lesson has NOT NULL constraint, so this tests the WHERE IS NOT NULL guard if added
-- Verify query includes WHERE lesson IS NOT NULL
```
**Input:**
```bash
grep -A5 '"lesson"' memory/scripts/memory-maintenance.py | grep -i "NOT NULL\|is not null"
```
**Expected:** Query includes NULL filter on `lesson` column  
**Note:** If DB constraint guarantees non-null, this is defense-in-depth; still verify no crash

---

## Issue #258 — Add Lessons Dedup/Cleanup Phase

### TC-258-01: Lessons dedup phase exists in memory-maintenance.py

**Type:** Code presence  
**Input:**
```bash
grep -n "lesson.*dedup\|dedup.*lesson\|phase_dedup_lessons\|lessons.*duplicate" memory/scripts/memory-maintenance.py
```
**Expected:** At least one match showing a dedicated lessons dedup function or phase  
**Fail if:** No dedup phase for lessons found

---

### TC-258-02: Exact duplicate lessons are removed

**Type:** Happy path — dedup logic  
**Preconditions:** Seed two identical lessons:
```sql
INSERT INTO lessons (lesson, context) VALUES ('Exact duplicate lesson', 'same context');
INSERT INTO lessons (lesson, context) VALUES ('Exact duplicate lesson', 'same context');
```
**Input:** Run lessons dedup phase (or full maintenance with `--force`)  
**Expected:**
```sql
SELECT COUNT(*) FROM lessons WHERE lesson = 'Exact duplicate lesson';
-- Returns 1 (one removed)
```
**Fail if:** Both rows remain, or both rows deleted (survivor must be retained)

---

### TC-258-03: Near-duplicate lessons handled (high-similarity threshold)

**Type:** Edge case — fuzzy dedup  
**Preconditions:** Seed near-duplicates:
```sql
INSERT INTO lessons (lesson) VALUES ('Always commit before deploying code.');
INSERT INTO lessons (lesson) VALUES ('Always commit before deploying.');
```
**Expected:** Dedup policy applied; either auto-merged or flagged in report  
**Pass criteria:** Script does not crash; one of: (a) merged to single row, or (b) written to review report file  
**Fail if:** No action taken AND no report written, or crash

---

### TC-258-04: Distinct lessons are NOT deduplicated

**Type:** Negative — no false merges  
**Preconditions:** Seed two clearly distinct lessons:
```sql
INSERT INTO lessons (lesson) VALUES ('Always validate config before applying.');
INSERT INTO lessons (lesson) VALUES ('Never run tests on production database.');
```
**Input:** Run lessons dedup phase  
**Expected:**
```sql
SELECT COUNT(*) FROM lessons WHERE lesson IN (
  'Always validate config before applying.',
  'Never run tests on production database.'
);
-- Returns 2 (both preserved)
```
**Fail if:** Either distinct lesson is removed

---

### TC-258-05: Dedup runs BEFORE embedding phase in pipeline order

**Type:** Phase ordering  
**Rationale:** Deduplicating before embedding avoids wasting embed calls on rows that will be removed  
**Input:** Trace phase execution order in memory-maintenance.py main() or phase_embed()  
**Expected:** Lessons dedup phase is invoked before `phase_embed_database` processes the `lesson` table, OR dedup runs early in the pipeline (before phase 2 embed)  
**Fail if:** Embeddings are generated for lessons that the dedup phase then removes

---

### TC-258-06: Lessons dedup handles empty lessons table gracefully

**Type:** Edge case — empty table  
**Preconditions:** Truncate lessons table (on staging transaction):
```sql
DELETE FROM lessons;
```
**Input:** Run maintenance with `--force`  
**Expected:** Script exits 0; dedup phase produces "0 lessons processed" or similar; no crash  
**Fail if:** Exception raised on empty result set

---

## Issue #259 — Fix All Stale Schema References

### TC-259-01: positions table fully removed from memory-maintenance.py

**Type:** Code removal  
**Input:**
```bash
grep -n "position[^a-z]" memory/scripts/memory-maintenance.py | grep -v "position[s]\?_type\|source_type\|source_position"
```
**Expected:** No reference to `FROM positions` table  
**Fail if:** `FROM positions` appears in any query

---

### TC-259-02: positions table fully removed from embed-full-database.py

**Type:** Code removal  
**Input:**
```bash
grep -n '"position"' memory/scripts/embed-full-database.py
grep -n "FROM positions" memory/scripts/embed-full-database.py
```
**Expected:** Zero matches for the `positions` table query entry  
**Fail if:** Any match referencing the removed `positions` table

---

### TC-259-03: library → library_works in memory-maintenance.py TABLE_EMBED_SPECS

**Type:** Schema fix — table rename  
**Input:**
```bash
grep -n '"library"' memory/scripts/memory-maintenance.py
grep -n "FROM library[^_]" memory/scripts/memory-maintenance.py
```
**Expected:**  
- Source type key may remain `"library"` (acceptable) or be updated to `"library_work"` — **verify with Coder which is intended**  
- Query must use `FROM library_works` not `FROM library`  
**Fail if:** `FROM library` appears (without `_works` suffix) in the library entry query

---

### TC-259-04: embed-full-database.py library query already uses library_works (regression guard)

**Type:** Regression — already correct, must not break  
**Input:**
```bash
grep -n "library_works" memory/scripts/embed-full-database.py
```
**Expected:** At least one match (the existing correct query)  
**Fail if:** Match removed, or changed to `FROM library`

---

### TC-259-05: research_conclusions uses COALESCE(title, summary) in memory-maintenance.py

**Type:** Schema fix — column name  
**Preconditions:** `research_conclusions` table confirmed: has `title` (nullable) and `summary` (NOT NULL), no `content` column  
**Input:**
```bash
grep -n "research_conclusion" memory/scripts/memory-maintenance.py | grep -i "content"
```
**Expected:** Zero matches — `content` column must NOT be referenced  
**Supplementary:**
```bash
grep -n "research_conclusion" memory/scripts/memory-maintenance.py | grep -i "COALESCE\|title\|summary"
```
**Expected:** Match found showing COALESCE(title, summary) or similar

---

### TC-259-06: research_conclusions query executes without error on real schema

**Type:** Runtime correctness  
**Preconditions:** Staging DB has research_conclusions table; seed:
```sql
INSERT INTO research_conclusions (task_id, title, summary)
  VALUES (1, 'Test Title', 'Test summary for embedding');
INSERT INTO research_conclusions (task_id, title, summary)
  VALUES (1, NULL, 'Summary only, no title');
```
**Input:** Run memory-maintenance.py embed phase only  
**Expected:**
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'research_conclusion';
-- Returns >= 2
```
Row with NULL title: embedded text should fall back to summary  
Row with both: embedded text should include title  
**Fail if:** `column research_conclusions.content does not exist` error

---

### TC-259-07: vocabulary uses word column in embed-full-database.py

**Type:** Schema fix  
**Schema confirmed:** `vocabulary` has `word` column (no `term` column)  
**Input:**
```bash
grep -n "FROM vocabulary" memory/scripts/embed-full-database.py
```
**Expected:** Line references `term` → **should be changed to** `word` (or confirm fix applied)  
Post-fix check:
```bash
grep -n "vocabulary" memory/scripts/embed-full-database.py | grep "term"
```
**Expected:** Zero matches for `term` in vocabulary context  
**Fail if:** `term` column still referenced in vocabulary query in embed-full-database.py

---

### TC-259-08: vocabulary.word in embed-full-database.py — runtime execution succeeds

**Type:** Runtime correctness  
**Preconditions:** Seed:
```sql
INSERT INTO vocabulary (word, category) VALUES ('embedtest', 'technical');
```
**Input:** `python3 memory/scripts/embed-full-database.py`  
**Expected:** Script exits 0; vocabulary row embedded:
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'vocabulary';
-- Returns >= 1
```
**Fail if:** `column vocabulary.term does not exist` error, or exit code non-zero

---

### TC-259-09: memory-maintenance.py already uses vocabulary.word (regression guard)

**Type:** Regression guard — already correct  
**Input:**
```bash
grep -n "FROM vocabulary" memory/scripts/memory-maintenance.py
```
**Expected:** References `word` column, NOT `term`  
**Fail if:** `term` appears in memory-maintenance.py vocabulary query

---

### TC-259-10: No phantom references to removed tables in either script

**Type:** Comprehensive cleanup check  
**Input:**
```bash
grep -n "FROM trading_signals\|FROM positions\|FROM library[^_]" \
  memory/scripts/memory-maintenance.py memory/scripts/embed-full-database.py
```
**Expected:** Zero matches across both files  
**Fail if:** Any match found

---

## Issue #278 — Graceful Error Handling

### TC-278-01: memory-maintenance.py continues when one TABLE_EMBED_SPECS table is missing

**Type:** Error path — graceful degradation  
**Scenario:** Temporarily introduce a bogus table to TABLE_EMBED_SPECS (or use a patched version)  
**Preconditions:** Add a fake entry to the spec dict that references a non-existent table:  
  (In a test harness or patched copy of the script)  
```python
TABLE_EMBED_SPECS["__nonexistent__"] = (
    "SELECT id, name FROM __nonexistent_table__",
    "__nonexistent__"
)
```
**Input:** Run the embed phase  
**Expected:**
- Script logs a WARNING for the missing table (not ERROR)  
- All other tables in TABLE_EMBED_SPECS process successfully  
- Script exits 0  
- Warning count reported in summary  
**Fail if:** Script crashes with unhandled exception, or exits non-zero, or skips all tables after the failure

---

### TC-278-02: memory-maintenance.py continues when one column is missing in TABLE_EMBED_SPECS

**Type:** Error path — column-level failure  
**Scenario:** Patch a table query to reference a non-existent column  
**Expected:** Same as TC-278-01 — WARNING logged, other tables proceed, exit 0  
**Fail if:** Unhandled `psycopg2.ProgrammingError`, or entire embed phase aborts

---

### TC-278-03: phase_embed_research handles individual sub-query failure gracefully

**Type:** Error path — research phase isolation  
**Scenario:** `research_tasks` table temporarily renamed (or patch the query to reference bad column)  
**Expected:**
- The failing sub-query logs a warning
- Other research sub-queries (research_findings, research_conclusions) still run and embed successfully
- Script exits 0
**Fail if:** Failure in one research sub-query aborts the remaining research embeds

---

### TC-278-04: embed-full-database.py continues when one TABLES_TO_EMBED entry fails

**Type:** Error path — deprecated script  
**Preconditions:** One entry in TABLES_TO_EMBED references a missing table or column (post-fix: e.g., if a new edge case arises)  
**Expected:**
- `⚠️` warning printed for the failing table
- All other tables processed  
- Script exits 0  
- `conn.rollback()` called on failure (no partial-table commits corrupting state)
**Fail if:** Exception propagates uncaught, or script exits non-zero on table-level failure

---

### TC-278-05: Both scripts exit 0 on partial success, non-zero only on total pipeline failure

**Type:** Exit code semantics  
**Scenario A (partial):** Two tables fail; eight succeed  
**Expected A:** Exit code 0; summary shows warn count  

**Scenario B (total):** Ollama unreachable (kill Ollama before test)  
**Expected B for memory-maintenance.py:** Exit code non-zero; `[ERROR]` logged  
**Expected B for embed-full-database.py:** Exit code non-zero or all tables show `⚠️ Ollama connection error`  
**Fail if:** Script exits 0 when Ollama is completely down and no embeddings can be generated

---

### TC-278-06: Success and warning counts reported in summary

**Type:** Output format  
**Preconditions:** Run with mixed success (some tables OK, one patched to fail)  
**Expected:** Final summary output includes count of successfully embedded tables AND count of warnings/skipped tables  
**Fail if:** Summary reports only total items; no visibility into which tables were skipped

---

### TC-278-07: Ollama down — memory-maintenance.py embed phase fails but other phases (dedup, decay, etc.) still run

**Type:** Phase isolation  
**Preconditions:** Stop Ollama before test  
**Input:** Run `memory-maintenance.py --verbose --force` (all phases enabled)  
**Expected:**
- Embed phase logs error about Ollama unavailable
- Dedup, decay, ghost cleanup, entity dedup phases still execute
- Script exits with appropriate code (non-zero if embed is considered critical, or 0 if embed is treated as best-effort)
- Clarification needed from Coder: is Ollama-down a fatal error or warning?  
**Note:** Document the intended exit code contract as part of this issue before marking closed.

---

## Cross-Phase Interaction Tests

### TC-X-01: Failure in one phase does not corrupt DB state for subsequent phases

**Type:** Phase isolation / transaction safety  
**Scenario:** Force an error in phase_embed_research by patching the research_conclusions query  
**Expected:**
- research_findings phase completes and commits (or rolls back atomically)
- Dedup phase runs on correct data
- No orphaned partial writes
**Verification:**
```sql
-- Check embedding counts before and after — no partial batch left uncommitted
SELECT source_type, COUNT(*) FROM memory_embeddings GROUP BY source_type ORDER BY source_type;
```
**Fail if:** Partial batch of embeddings from failed table appears in DB

---

### TC-X-02: Lessons dedup + embedding interaction — dedup before embed avoids wasted calls

**Type:** Ordering correctness  
**Preconditions:** Seed 5 duplicate lessons and 5 unique lessons  
**Input:** Run full pipeline  
**Expected:** After dedup runs, embedding phase processes 5 unique lessons (not 10)  
**Verification:** 
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'lesson';
-- Should equal count of unique lessons, not total pre-dedup count
```
**Fail if:** 10 lesson embeddings created (duplicates embedded before dedup removed them)

---

### TC-X-03: Removed tables (trading_signals, positions) leave no orphan embeddings after run

**Type:** Cleanup correctness  
**Preconditions:** If any `trading_signal` or `position` embeddings exist in memory_embeddings from prior runs  
**Input:** Run full maintenance pipeline  
**Expected:** Clean orphaned embeddings phase removes any `trading_signal` or `position` source_type rows from memory_embeddings (since source rows no longer exist)  
**Verification:**
```sql
SELECT COUNT(*) FROM memory_embeddings WHERE source_type IN ('trading_signal', 'position');
-- Returns 0 after cleanup phase
```
**Fail if:** Orphan embeddings for removed tables persist after clean_orphaned_embeddings phase

---

### TC-X-04: New model name (snowflake-arctic-embed2) used consistently across both scripts

**Type:** Configuration consistency  
**Input:**
```bash
grep -rn "model" memory/scripts/ | grep -v ".pyc" | grep "embed"
```
**Expected:** Only `snowflake-arctic-embed2` appears as model value; no `mxbai-embed-large` anywhere  
**Fail if:** Mixed model names found across config and fallback paths

---

### TC-X-05: Dry-run mode — no changes committed across all phases

**Type:** Dry-run regression  
**Input:**
```bash
python3 memory/scripts/memory-maintenance.py --dry-run --force --verbose
```
**Expected:**
- No rows added to memory_embeddings
- No rows deleted from any table
- No lessons deduplicated
- State file NOT updated (cooldown not reset)
- Script exits 0
- Output includes `DRY RUN — no changes committed`
**Verification:**
```sql
-- Run before and after; row counts must be identical
SELECT relname, n_live_tup FROM pg_stat_user_tables 
WHERE relname IN ('memory_embeddings','lessons','entity_facts','entities') 
ORDER BY relname;
```
**Fail if:** Any table row count changes during dry-run

---

### TC-X-06: Cooldown prevents re-run without --force

**Type:** Phase 1 state machine  
**Preconditions:** Run maintenance once successfully (state file written with recent timestamp)  
**Input:** Run again without `--force`  
**Expected:** Script logs `Cooldown active` and exits 0 without running any phase  
**Fail if:** Phases run within cooldown window, or exit code non-zero

---

### TC-X-07: Full pipeline run with all new tables — integration smoke test

**Type:** Integration / end-to-end  
**Preconditions:** Staging DB with seed data for all new tables:
```sql
INSERT INTO journal_entries (content, trigger) VALUES ('Journal embedding test', 'manual');
INSERT INTO music_works (title, description) VALUES ('Music test', 'Description test');
INSERT INTO workflow_runs (workflow_id, trigger_context, notes, channel) VALUES (1, 'test ctx', 'test notes', 'test');
INSERT INTO income_sources (name, description, status) VALUES ('Income test', 'Test desc', 'active');
INSERT INTO lessons (lesson) VALUES ('Unique lesson for full run test');
INSERT INTO vocabulary (word) VALUES ('testword' || now()::text);
```
**Input:** `python3 memory/scripts/memory-maintenance.py --force --verbose`  
**Expected:**
- Exit code 0
- All new source_types (journal_entry, music_work, workflow_run, income_source) have ≥ 1 embedding
- lesson and vocabulary embeddings generated without column errors
- Summary printed with non-zero embed count
- No Postgres errors in output
**Fail if:** Any new table produces zero embeddings, any column error, or non-zero exit

---

## Test Coverage Summary

| Issue | Test Cases | Areas Covered |
|-------|-----------|---------------|
| #223 — Model unification | TC-223-01 to TC-223-04 | Config file, fallback, consistency, no hardcoded old name |
| #233 — Remove trading_signals | TC-233-01 to TC-233-04 | Code removal, runtime with absent table, both scripts |
| #235 — Add missing tables | TC-235-01 to TC-235-07 | All 4 tables, both scripts, null handling, exclusion of portfolio_snapshots |
| #245 — Fix lessons column | TC-245-01 to TC-245-04 | Column name fix, runtime correctness, null handling, regression guard |
| #258 — Lessons dedup phase | TC-258-01 to TC-258-06 | Phase exists, exact dups, near-dups, false positive prevention, ordering, empty table |
| #259 — Fix stale schema refs | TC-259-01 to TC-259-10 | Positions gone, library→library_works, research_conclusions column, vocabulary.word, comprehensive grep |
| #278 — Graceful error handling | TC-278-01 to TC-278-07 | Missing table, missing column, research phase isolation, deprecated script, exit codes, summary counts, Ollama-down |
| Cross-phase | TC-X-01 to TC-X-07 | Transaction safety, lesson dedup+embed ordering, orphan cleanup, model consistency, dry-run, cooldown, full integration smoke test |

**Total test cases: 47**

---

## Pass/Fail Criteria for Quality Gate

- All TC-259-* and TC-245-* must pass before merge (known bugs — must be fixed)
- All TC-233-* must pass (stale table refs will crash on staging/production)
- TC-278-01 through TC-278-06 must pass (graceful handling required)
- TC-X-07 (integration smoke test) must pass
- TC-223-04 (no old model name anywhere) must pass

Blocking failures: any crash (unhandled exception), any non-zero exit on happy-path inputs, any column-not-found error in runtime tests.
