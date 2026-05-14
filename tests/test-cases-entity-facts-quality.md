# Test Cases: Entity Facts Quality — Batch `entity-facts-quality`

**Issues:** #216 (Unified nightly memory maintenance), #202 (FK reference rewiring during merges), #200 (Ghost entity cleanup), #203 (Entity-level deduplication)  
**Branch:** `feature/entity-facts-quality` (or per-issue branches)  
**Deliverable:** Rewritten `memory-maintenance.py` with embedding absorption, cross-key consolidation, `merge_entities()` DB function, ghost entity cleanup, and entity-level deduplication  
**Author:** Gem (QA Lead)  
**Date:** 2026-05-14

---

## Scope

### What Is Being Tested
1. `memory/scripts/memory-maintenance.py` — unified nightly maintenance script absorbing all three embed scripts
2. `merge_entities(survivor_id, absorbed_id)` — new DB function (rewires all 21 FK references)
3. `merge_facts(survivor_id, absorbed_id)` — existing DB function (already tested; tested here for integration correctness)
4. Cross-key fact consolidation via pgvector cosine similarity (≥0.92 threshold)
5. Ghost entity detection and cleanup (#200)
6. Entity-level deduplication — auto-merge (≥80% overlap) and manual review queue (<80%) (#203)
7. Cooldown gate (4-hour minimum between runs)
8. State file tracking of last-run timestamp
9. CLI flags: `--dry-run`, `--verbose`, `--skip-embed`, `--skip-consolidation`, `--skip-dedup`, `--skip-decay`, `--skip-ghost-cleanup`, `--force`

### What Is NOT Tested Here
- Same-key deduplication logic (existing, tested via prior test suites)
- Confidence decay math (existing, tested via prior test suites)
- Archiving / purging of old records (existing, tested via prior test suites)
- Embedding model quality or semantic accuracy
- Crontab removal (operational change, not a code test)
- Heartbeat idle cascade trigger mechanism (separate subsystem test)

---

## Entry Criteria
- `memory-maintenance.py` exists at `memory/scripts/memory-maintenance.py` with all new phases
- `merge_entities()` DB function exists in `nova_memory` database
- pgvector extension loaded; `memory_embeddings` table has correct schema
- Ollama running with `mxbai-embed-large` model available at configured `base_url`
- Staging `nova_memory` database reachable (never run against production)
- Python 3.10+, `psycopg2` installed
- State file path writable by test runner
- `embedding-config.json` present in script directory

## Exit Criteria
- All TC (happy-path) cases pass
- All TC-ERR (error/edge) cases correctly handle/reject bad input without data corruption
- All TC-DRY (dry-run) cases produce zero DB changes
- Zero unhandled exceptions from any test case
- `merge_entities()` function correctly rewires all 21 FK-referencing tables
- Cross-key consolidation never merges facts with cosine similarity <0.92
- Ghost entity cleanup never deletes an entity with active FK references outside entity_facts
- Entity dedup auto-merge never fires below 80% overlap threshold
- No S1/S2 defects open

---

## Test Data Setup

All tests use a dedicated staging database. Run this setup SQL before the test suite:

```sql
-- Standard test entities
INSERT INTO entities (id, name, type) VALUES
  (9001, 'TestPerson Alpha', 'person'),
  (9002, 'TestPerson Beta', 'person'),
  (9003, 'entity 9003', 'person'),    -- ghost: name pattern matches id
  (9004, 'Ghost With No Facts', 'person'),  -- ghost: 0 facts, 0 FKs
  (9005, 'LowFact Entity', 'person'), -- low-fact: exactly 2 facts
  (9006, 'TestOrg Gamma', 'organization'),
  (9007, 'TestPerson Delta', 'person')
ON CONFLICT DO NOTHING;

-- Facts for entity 9001 (Alice-like)
INSERT INTO entity_facts (id, entity_id, key, value, confidence, durability, extraction_count, learned_at, last_confirmed_at)
VALUES
  (90001, 9001, 'location', 'Austin, Texas', 0.90, 'long_term', 3, NOW()-INTERVAL '10 days', NOW()-INTERVAL '2 days'),
  (90002, 9001, 'hometown', 'Austin TX', 0.85, 'long_term', 2, NOW()-INTERVAL '15 days', NOW()-INTERVAL '5 days'),
  (90003, 9001, 'occupation', 'software engineer', 0.80, 'long_term', 1, NOW()-INTERVAL '5 days', NOW()-INTERVAL '1 day'),
  (90004, 9001, 'job_title', 'software developer', 0.75, 'long_term', 1, NOW()-INTERVAL '5 days', NOW()-INTERVAL '1 day')
ON CONFLICT DO NOTHING;

-- Facts for entity 9002 (Bob-like) — near-duplicate of 9001
INSERT INTO entity_facts (id, entity_id, key, value, confidence, durability, extraction_count, learned_at, last_confirmed_at)
VALUES
  (90010, 9002, 'location', 'Austin, Texas', 0.88, 'long_term', 2, NOW()-INTERVAL '8 days', NOW()-INTERVAL '3 days'),
  (90011, 9002, 'occupation', 'software engineer', 0.82, 'long_term', 1, NOW()-INTERVAL '6 days', NOW()-INTERVAL '2 days')
ON CONFLICT DO NOTHING;

-- Facts for low-fact entity 9005
INSERT INTO entity_facts (id, entity_id, key, value, confidence, durability, extraction_count, learned_at, last_confirmed_at)
VALUES
  (90020, 9005, 'name', 'something', 0.50, 'short_term', 1, NOW()-INTERVAL '3 days', NOW()-INTERVAL '3 days'),
  (90021, 9005, 'type', 'unknown', 0.50, 'short_term', 1, NOW()-INTERVAL '3 days', NOW()-INTERVAL '3 days')
ON CONFLICT DO NOTHING;

-- Embeddings for cross-key consolidation testing (must be seeded by the embedding phase or manually)
-- NOTE: After embed phase runs on staging, verify embeddings exist:
-- SELECT source_type, source_id FROM memory_embeddings WHERE source_type = 'entity_fact' AND source_id IN ('90001','90002','90003','90004');

-- FK references to test merge_entities rewiring
-- At minimum: entity_fact_sources, entity_relationships, preferences, project_entities
INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen)
VALUES (90001, 9001, 'test-citation-1', 1, NOW()-INTERVAL '10 days', NOW()-INTERVAL '2 days')
ON CONFLICT DO NOTHING;

INSERT INTO entity_relationships (entity_a, entity_b, relationship_type) VALUES (9001, 9006, 'works_at')
ON CONFLICT DO NOTHING;
```

---

## Section 1 — Cooldown Gate (#216)

### TC-COOL-001: Cooldown respected — exit when last run <4h ago

**Preconditions:** State file exists with `last_run` timestamp set to `NOW() - 2 hours`.

**Steps:**
```bash
# Write a recent state file
echo "{\"last_run\": \"$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ)\"}" > /tmp/mm-test-state.json
python3 memory/scripts/memory-maintenance.py --state-file /tmp/mm-test-state.json
```

**Expected:**
- Exit code 0 (graceful exit, not error)
- Stdout/stderr contains message indicating cooldown active (e.g., "cooldown", "last run was", "skipping")
- No DB modifications
- State file `last_run` unchanged

**Pass criteria:** Exit code 0 AND `last_run` in state file equals the pre-test value AND no entity_facts rows modified.

---

### TC-COOL-002: Cooldown bypassed with `--force`

**Preconditions:** State file with `last_run` set to 2 hours ago (same as TC-COOL-001).

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --state-file /tmp/mm-test-state.json --force --dry-run
```

**Expected:**
- Exit code 0
- Script proceeds past cooldown check (phases execute or are reported as dry-run)
- Log does not say "cooldown skipping"

**Pass criteria:** Script reaches at least the embed phase (or first phase that has work to do); no early-exit message.

---

### TC-COOL-003: Cooldown not applied when state file is absent

**Preconditions:** State file path does not exist.

**Steps:**
```bash
rm -f /tmp/mm-test-state-new.json
python3 memory/scripts/memory-maintenance.py --state-file /tmp/mm-test-state-new.json --dry-run
```

**Expected:**
- Exit code 0
- Script proceeds normally (no cooldown message)
- State file created with `last_run` timestamp after run

**Pass criteria:** State file `/tmp/mm-test-state-new.json` exists after run AND contains `last_run` field.

---

### TC-COOL-004: Cooldown not applied when last run >4h ago

**Preconditions:** State file with `last_run` = `NOW() - 5 hours`.

**Steps:**
```bash
echo "{\"last_run\": \"$(date -u -d '5 hours ago' +%Y-%m-%dT%H:%M:%SZ)\"}" > /tmp/mm-test-state-old.json
python3 memory/scripts/memory-maintenance.py --state-file /tmp/mm-test-state-old.json --dry-run
```

**Expected:**
- Exit code 0
- Script proceeds (no cooldown message)

**Pass criteria:** No "cooldown" message in output.

---

### TC-COOL-005: Cooldown boundary — exactly 4 hours (edge)

**Preconditions:** State file with `last_run` = exactly `NOW() - 4 hours`.

**Steps:**
```bash
echo "{\"last_run\": \"$(date -u -d '4 hours ago' +%Y-%m-%dT%H:%M:%SZ)\"}" > /tmp/mm-test-state-boundary.json
python3 memory/scripts/memory-maintenance.py --state-file /tmp/mm-test-state-boundary.json --dry-run
```

**Expected:**
- Script proceeds (4h is the boundary; exactly at boundary should be allowed)

**Pass criteria:** No early cooldown exit.

---

### TC-COOL-006: State file updated after successful run

**Preconditions:** State file with `last_run` = 8 hours ago. `--dry-run` NOT set (allow actual run in isolation test).

**Steps:**
```bash
BEFORE=$(cat /tmp/mm-test-state.json)
python3 memory/scripts/memory-maintenance.py --state-file /tmp/mm-test-state.json
AFTER=$(cat /tmp/mm-test-state.json)
```

**Expected:**
- `last_run` in state file is updated to approximately NOW() (within 60 seconds of test time)
- `last_run` value is later than the pre-run value

**Pass criteria:** `jq .last_run /tmp/mm-test-state.json` returns a timestamp within 60s of current time.

---

## Section 2 — Embedding Absorption (#216)

### TC-EMBED-001: Script embeds entity_facts that lack embeddings

**Preconditions:** Entity fact ID 90001 exists; no `memory_embeddings` row where `source_type='entity_fact' AND source_id='90001'`.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup --dry-run
# Then without dry-run for actual embed:
python3 memory/scripts/memory-maintenance.py --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**
- Exit code 0
- `memory_embeddings` table gains rows for entity_fact source type
- Each new row has `embedding` dimension = 1024

**Pass criteria:**
```sql
SELECT COUNT(*) FROM memory_embeddings 
WHERE source_type = 'entity_fact' AND source_id = '90001' 
AND array_length(embedding::real[], 1) = 1024;
```
Returns ≥ 1.

---

### TC-EMBED-002: Already-embedded facts are not re-embedded (idempotent)

**Preconditions:** entity_fact 90001 has an existing embedding in `memory_embeddings`.

**Steps:**
```bash
BEFORE_COUNT=$(psql -U nova -d nova_memory -h localhost -t -c "SELECT COUNT(*) FROM memory_embeddings WHERE source_type='entity_fact' AND source_id='90001';")
python3 memory/scripts/memory-maintenance.py --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup
AFTER_COUNT=$(...)
```

**Expected:**
- `AFTER_COUNT == BEFORE_COUNT` (no duplicate embeddings added)

**Pass criteria:** Count unchanged before and after run.

---

### TC-EMBED-003: `--skip-embed` flag prevents embedding phase

**Preconditions:** entity_fact 90003 has no embedding.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup --dry-run
```

**Expected:**
- Exit code 0
- No new embedding rows for entity_fact 90003
- Log message indicates embed phase was skipped

**Pass criteria:** No `memory_embeddings` row for source_id='90003' after run.

---

### TC-EMBED-004: Embed phase handles Ollama connection failure gracefully

**Preconditions:** Ollama service stopped or pointing to unreachable URL.

**Steps:** Set `embedding-config.json` `base_url` to `http://localhost:9999` (unreachable), then run.

**Expected:**
- Exit code non-zero OR graceful skip with error logged
- No partial/corrupt embeddings written
- No crash without error message

**Pass criteria:** No unhandled exception traceback; error message references Ollama/connection; DB state unchanged.

---

### TC-EMBED-005: Re-embed modified facts after merges

**Preconditions:** entity_fact 90001 has an embedding; merge operation updates 90001 (extraction_count increases); new embedding should be generated.

**Steps:** After running merge phase (via consolidation or dedup), run the re-embed modified phase.

**Expected:**
- 90001's `memory_embeddings` row has an updated `updated_at` timestamp
- Embedding vector may differ (content changed)

**Pass criteria:** `updated_at` on the embedding row for 90001 is later than `updated_at` before the merge run.

---

### TC-EMBED-006: `--dry-run` produces no embedding writes

**Preconditions:** entity_fact 90007 has no embedding.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --dry-run
```

**Expected:** Zero new rows in `memory_embeddings` for source_id='90007'.

**Pass criteria:** `SELECT COUNT(*) FROM memory_embeddings WHERE source_type='entity_fact' AND source_id='90007'` = 0 after dry run.

---

## Section 3 — Cross-Key Fact Consolidation (#216)

### TC-XKEY-001: Near-duplicate cross-key facts auto-merged at ≥0.92 similarity

**Preconditions:**
- entity_fact 90001 (`location = 'Austin, Texas'`) and 90002 (`hometown = 'Austin TX'`) both have embeddings.
- Cosine similarity between their embeddings is ≥0.92 (confirm via `1 - (embedding1 <=> embedding2)` in SQL).
- Both belong to entity 9001.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**
- One of {90001, 90002} is absorbed into the other via `merge_facts()`
- Survivor has summed `extraction_count` (should be 3+2=5)
- Absorbed fact ID no longer exists in `entity_facts`
- Survivor's `confidence` = GREATEST(0.90, 0.85) = 0.90

**Pass criteria:**
```sql
-- Exactly one of the two facts remains
SELECT COUNT(*) FROM entity_facts WHERE id IN (90001, 90002);
-- Returns 1

-- Survivor has correct extraction_count
SELECT extraction_count FROM entity_facts WHERE id IN (90001, 90002);
-- Returns 5 (3+2)

-- Survivor has correct confidence
SELECT confidence FROM entity_facts WHERE id IN (90001, 90002);
-- Returns 0.90
```

---

### TC-XKEY-002: Facts with cosine similarity <0.92 are NOT merged

**Preconditions:**
- entity_fact 90003 (`occupation = 'software engineer'`) and 90001 (`location = 'Austin, Texas'`) are different enough that their cosine similarity is <0.92.
- Both belong to entity 9001.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:** Both 90003 and 90001 still exist in `entity_facts` after run.

**Pass criteria:**
```sql
SELECT COUNT(*) FROM entity_facts WHERE id IN (90001, 90003);
-- Returns 2
```

---

### TC-XKEY-003: Cross-key consolidation only merges within same entity_id

**Preconditions:**
- entity_fact 90001 (entity 9001, `location = 'Austin, Texas'`) and entity_fact 90010 (entity 9002, `location = 'Austin, Texas'`) may have cosine similarity ≥0.92.
- They belong to different entities.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:** Both 90001 and 90010 still exist (different entity_ids must never be merged by cross-key consolidation).

**Pass criteria:**
```sql
SELECT COUNT(*) FROM entity_facts WHERE id IN (90001, 90010);
-- Returns 2
```

---

### TC-XKEY-004: `--skip-consolidation` skips cross-key phase

**Preconditions:** Facts 90001 and 90002 not yet merged (or freshly seeded).

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup --dry-run
```

**Expected:** Both 90001 and 90002 still exist; log indicates consolidation phase skipped.

**Pass criteria:** Both fact IDs present; "skip" or "consolidation" in log output.

---

### TC-XKEY-005: Survivor selection — higher confidence wins

**Preconditions:**
- Fact A: `confidence=0.90`, `extraction_count=1`
- Fact B: `confidence=0.70`, `extraction_count=5`
- Cosine similarity ≥0.92.

**Expected:** Fact A (higher confidence) is survivor. Survivor's `extraction_count` = 6.

**Pass criteria:** Fact B ID gone; Fact A's `extraction_count = 6`.

---

### TC-XKEY-006: Survivor selection — tie-breaking by extraction_count

**Preconditions:**
- Fact A: `confidence=0.80`, `extraction_count=3`
- Fact B: `confidence=0.80`, `extraction_count=7`
- Cosine similarity ≥0.92.

**Expected:** Fact B (higher extraction_count) is survivor, OR deterministic rule documented in spec.  
**Note to implementer:** Confirm tie-breaking rule in spec; test must match implementation.

---

### TC-XKEY-007: `--dry-run` does not merge cross-key facts

**Preconditions:** Facts 90001 and 90002 both exist with embeddings at ≥0.92 similarity.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-dedup --skip-decay --skip-ghost-cleanup --dry-run
```

**Expected:** Both 90001 and 90002 still exist after dry run.

**Pass criteria:**
```sql
SELECT COUNT(*) FROM entity_facts WHERE id IN (90001, 90002);
-- Returns 2
```

---

## Section 4 — `merge_entities()` DB Function (#202, #203)

### TC-MENT-001: merge_entities() rewires entity_facts to survivor

**Preconditions:** Entities 9001 and 9002 exist with facts 90001-90004 (entity 9001) and 90010-90011 (entity 9002).

**Steps:**
```sql
BEGIN;
SELECT merge_entities(9001, 9002);
```

**Expected:**
- All facts formerly belonging to 9002 (90010, 90011) now have `entity_id = 9001`
- Entity 9002 deleted from `entities`
- `entity_facts` count for 9001 = original_9001_count + original_9002_count

**Pass criteria:**
```sql
SELECT COUNT(*) FROM entity_facts WHERE entity_id = 9001;
-- Returns 6 (4 + 2)

SELECT COUNT(*) FROM entity_facts WHERE entity_id = 9002;
-- Returns 0

SELECT COUNT(*) FROM entities WHERE id = 9002;
-- Returns 0
```

---

### TC-MENT-002: merge_entities() rewires all 21 FK-referencing tables

**Preconditions:** Create FK references from entity 9002 in several tables, then call merge_entities(9001, 9002).

**Setup:**
```sql
INSERT INTO entity_relationships (entity_a, entity_b, relationship_type) VALUES (9002, 9006, 'knows');
INSERT INTO preferences (entity_id, key, value) VALUES (9002, 'test_pref', 'test_val');
INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen)
  VALUES (90001, 9002, 'cross-source-test', 1, NOW(), NOW());
```

**Steps:**
```sql
SELECT merge_entities(9001, 9002);
```

**Expected (check all 21 tables):**
- `entity_relationships` rows with `entity_a=9002` → `entity_a=9001` (or de-duplicated if 9001-9006 already exists)
- `entity_relationships` rows with `entity_b=9002` → `entity_b=9001`
- `preferences` rows with `entity_id=9002` → `entity_id=9001`
- `entity_fact_sources` rows with `source_entity_id=9002` → `source_entity_id=9001`
- All other FK tables similarly rewired (see full list below)

**Full FK table checklist:**
```
agent_actions.agent_id
certificates.entity_id
channel_transcripts.sender_entity_id
entity_fact_conflicts.entity_id
entity_fact_sources.source_entity_id
entity_facts.entity_id
entity_relationships.entity_a
entity_relationships.entity_b
event_entities.entity_id
gambling_logs.entity_id
media_consumed.consumed_by
media_queue.requested_by
preferences.entity_id
project_entities.entity_id
shopping_history.entity_id
shopping_preferences.entity_id
shopping_wishlist.entity_id
tasks.blocked_on
tasks.created_by
tasks.assigned_to
vehicles.owner_id
```

**Pass criteria:** For each table, run: `SELECT COUNT(*) FROM <table> WHERE <fk_column> = 9002;` — must return 0 for all 21.

---

### TC-MENT-003: merge_entities() discovers FKs via information_schema (not hardcoded)

**Preconditions:** A new test table with an `entity_id` FK is added to the staging database after `merge_entities` function definition.

**Steps:**
```sql
-- Add a new FK table not in the original list
CREATE TABLE test_new_entity_fk (id SERIAL, entity_id INT REFERENCES entities(id));
INSERT INTO test_new_entity_fk (entity_id) VALUES (9002);
SELECT merge_entities(9001, 9002);
SELECT COUNT(*) FROM test_new_entity_fk WHERE entity_id = 9002;
DROP TABLE test_new_entity_fk;
```

**Expected:** `test_new_entity_fk` row is rewired to entity 9001 — proving dynamic FK discovery.

**Pass criteria:** `COUNT(*) = 0` (no orphaned refs to 9002).

---

### TC-MENT-004: merge_entities() raises exception when survivor_id = absorbed_id

**Steps:**
```sql
SELECT merge_entities(9001, 9001);
```

**Expected:** Exception raised with message indicating self-merge is not allowed.

**Pass criteria:** `RAISE EXCEPTION` triggered; transaction rolled back.

---

### TC-MENT-005: merge_entities() raises exception when either entity does not exist

**Steps:**
```sql
SELECT merge_entities(9001, 99999);  -- 99999 doesn't exist
SELECT merge_entities(99998, 9001);  -- 99998 doesn't exist
```

**Expected:** Exception for each call: entity not found.

**Pass criteria:** Both calls raise exceptions cleanly; no partial changes.

---

### TC-MENT-006: merge_entities() merges entity_facts for both entities before deleting absorbed

**Preconditions:** Both entities have entity_facts. entity 9001 has fact with key='location'; entity 9002 also has key='location'.

**Expected:**
- Facts with same key that pass trgm similarity check are themselves merged via `merge_facts()`
- Facts with different keys are simply re-pointed to survivor entity_id
- No duplicate (entity_id, key) violations if UNIQUE constraint exists

**Pass criteria:** No DB constraint violation after merge; all facts accounted for.

---

### TC-MENT-007: merge_entities() also merges memory_embeddings for absorbed entity

**Preconditions:** entity 9002 has `memory_embeddings` rows with `source_type='entity'` and `source_id='9002'`.

**Expected:**
- These embedding rows are re-pointed to survivor entity 9001 OR deleted (spec must define behavior)
- No orphaned embedding rows pointing to deleted entity 9002

**Pass criteria:** `SELECT COUNT(*) FROM memory_embeddings WHERE source_type='entity' AND source_id='9002'` = 0 after merge.

---

### TC-MENT-008: merge_entities() handles entity with zero FK references (clean delete)

**Preconditions:** Entity 9004 (Ghost With No Facts) has no FK references anywhere.

**Steps:**
```sql
-- Verify truly clean
SELECT COUNT(*) FROM entity_facts WHERE entity_id = 9004;  -- expect 0
-- Then merge into any survivor
SELECT merge_entities(9001, 9004);
```

**Expected:** Entity 9004 deleted; function returns cleanly.

**Pass criteria:** Entity 9004 absent from `entities`; no exceptions.

---

## Section 5 — Ghost Entity Cleanup (#200)

### TC-GHOST-001: Pattern-match ghost "entity N" merged into entity with id=N

**Preconditions:** Entity 9003 exists with `name = 'entity 9003'`. Entity with `id=9003` would need to exist for merge target. Use a real entity pattern for this test.

**Setup alternative:** Create entity 9100 with `name = 'entity 9100'` and a distinct entity 9100 (actually, pattern merge means: entity named "entity 9003" should merge into entity id=9003 if that entity exists).

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-decay
```

**Expected:**
- Entity 9003 (`name='entity 9003'`) is absorbed into the entity with `id=9003` (if it exists)
- If target id does not exist, should flag for manual review (not auto-delete)

**Pass criteria (when target exists):** `SELECT COUNT(*) FROM entities WHERE name='entity 9003'` = 0 after cleanup; facts re-pointed to id=9003.

---

### TC-GHOST-002: Zero-fact zero-FK entity hard-deleted

**Preconditions:** Entity 9004 (`Ghost With No Facts`) has zero entity_facts AND zero FK references in any other table.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-decay
```

**Expected:**
- Entity 9004 is hard-deleted from `entities`
- No orphaned rows anywhere

**Pass criteria:**
```sql
SELECT COUNT(*) FROM entities WHERE id = 9004;
-- Returns 0
```
Plus check all FK tables return 0 for entity_id=9004.

---

### TC-GHOST-003: Zero-fact entity WITH FK references is NOT hard-deleted

**Preconditions:** Create entity 9008 with zero entity_facts but with a row in `entity_relationships` referencing it.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-decay
```

**Expected:**
- Entity 9008 is NOT deleted (has FK references)
- Entity 9008 is either flagged for review OR silently skipped (not deleted)

**Pass criteria:**
```sql
SELECT COUNT(*) FROM entities WHERE id = 9008;
-- Returns 1 (entity preserved)
```

---

### TC-GHOST-004: Low-fact entity flagged for manual review queue, not deleted

**Preconditions:** Entity 9005 has exactly 2 facts (below "low-fact" threshold defined in implementation).

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-decay
```

**Expected:**
- Entity 9005 is NOT deleted or merged automatically
- A manual review record is created in the appropriate queue table (or log file)

**Pass criteria:** `SELECT COUNT(*) FROM entities WHERE id = 9005` = 1 (entity preserved); review queue has entry for entity 9005.

---

### TC-GHOST-005: `--skip-ghost-cleanup` skips ghost entity phase

**Preconditions:** Entity 9004 (zero facts, zero FKs) exists.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:** Entity 9004 still exists after run.

**Pass criteria:** `SELECT COUNT(*) FROM entities WHERE id = 9004` = 1.

---

### TC-GHOST-006: `--dry-run` does not delete any entities

**Preconditions:** Entities 9003, 9004, 9005 in database.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --dry-run
```

**Expected:** All entities still exist; dry-run output describes what WOULD be done.

**Pass criteria:** All three entity IDs still present after dry run.

---

## Section 6 — Entity-Level Deduplication (#203)

### TC-EDUP-001: Auto-merge when overlap ≥80%

**Preconditions:**
- Entities 9001 and 9002 share facts: both have `location='Austin, Texas'` and `occupation='software engineer'` (≥80% fact overlap by count + similarity).
- Set up overlapping facts deliberately:
  ```sql
  -- Entity 9001 has facts: location, hometown, occupation, job_title (4 facts)
  -- Entity 9002 has facts: location, occupation (2 facts — 2/4 = 50% by count, but may qualify by similarity)
  ```
  **Note:** The 80% threshold spec must clarify how overlap is computed (shared/(total unique)), test accordingly.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-decay --skip-ghost-cleanup
```

**Expected (only if overlap truly ≥80%):**
- Lower-confidence or fewer-fact entity absorbed into higher-confidence entity via `merge_entities()`
- Absorbed entity no longer in `entities`

**Pass criteria:** (Depends on seed data triggering ≥80% — adjust seed data to match threshold.)

---

### TC-EDUP-002: Manual review queue written when overlap <80%

**Preconditions:** Entities 9001 and 9007 with some shared facts but <80% overlap.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-decay --skip-ghost-cleanup
```

**Expected:**
- Neither entity deleted or merged
- Manual review record written to review queue with both entity IDs, overlap score, candidate type

**Pass criteria:** Both entities exist; review queue has entry with entity_ids 9001 and 9007.

---

### TC-EDUP-003: Entity dedup considers name similarity, fact overlap, and embedding similarity

**Preconditions:** Two entities: "Dustin Trammell" (id=9009) and "D. Trammell" (id=9010) with partial fact overlap.

**Expected:**
- Script computes combined overlap score using name similarity + shared facts + embedding similarity
- If combined score ≥80% → auto-merge; else → review queue

**Pass criteria:** Combined scoring is consistent with spec; output reports overlap breakdown.

---

### TC-EDUP-004: merge_entities used for auto-merge (not merge_facts)

**Preconditions:** Two entities confirmed to have ≥80% overlap.

**Steps:** Run dedup phase; observe DB changes.

**Expected:**
- `merge_entities(survivor_id, absorbed_id)` called (not `merge_facts`)
- All 21 FK references rewired
- Absorbed entity deleted

**Pass criteria:** All 21 FK tables have zero refs to absorbed entity_id after merge.

---

### TC-EDUP-005: `--skip-entity-dedup` skips entity-level dedup phase *(flag corrected — see Section 14)*

> **Flag correction:** The original version of this test used `--skip-dedup` to skip entity dedup. That flag controls *same-key fact dedup only*. The correct flag for skipping entity-level dedup is `--skip-entity-dedup`. See TC-FLAG-004 in Section 14 for the definitive test.

**Preconditions:** High-overlap entity pair in DB.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-entity-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:** Both entities still present; log shows entity dedup skipped.

**Pass criteria:** Both entity IDs present; "skip" and "entity-dedup" (or equivalent) in log.

---

### TC-EDUP-006: `--dry-run` does not merge entities

**Preconditions:** High-overlap entity pair in DB.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --dry-run
```

**Expected:** Both entities present after dry run; report describes candidate pairs.

**Pass criteria:** Both entity IDs present; dry-run report shows overlap candidates.

---

### TC-EDUP-007: Entity dedup does not merge entities of different types

**Preconditions:** Entity 9001 (type='person') and entity 9006 (type='organization') share some facts.

**Expected:** Script does not merge across entity types (person vs organization cannot be the same entity).

**Pass criteria:** Both entities present; no merge attempted.

---

## Section 7 — Phase Ordering and Integration (#216)

### TC-PHASE-001: Phase order: cooldown → embed → cross-key consolidation → same-key dedup → confidence decay → ghost cleanup → re-embed modified → archive & purge

**Steps:** Run script with `--verbose`, capture log.

**Expected:** Log messages appear in the documented phase order.

**Pass criteria:** Phase start messages appear in correct sequence in stdout/stderr.

---

### TC-PHASE-002: All phases can be selectively skipped

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup --dry-run
```

**Expected:**
- Exit code 0
- Log shows each skipped phase
- No DB changes

**Pass criteria:** All skip messages present; no DB modifications.

---

### TC-PHASE-003: Script fails cleanly on DB connection error

**Preconditions:** PostgreSQL not reachable (wrong host or port).

**Steps:** Set invalid `PGHOST` env var; run script.

**Expected:**
- Exit code non-zero
- Error message references DB connection failure
- No partial state changes
- State file NOT updated (run did not complete)

**Pass criteria:** Non-zero exit; state file `last_run` unchanged from pre-run value.

---

### TC-PHASE-004: Full end-to-end run with all phases (non-dry-run)

**Preconditions:** Full staging DB seed applied. State file last_run > 4 hours ago.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --verbose
```

**Expected:**
- Exit code 0
- All phases execute
- State file updated
- Summary log written (counts per phase)
- No unhandled exceptions

**Pass criteria:** Exit code 0; state file updated; log contains summary line with phase result counts.

---

### TC-PHASE-005: Script logs a complete summary on successful run

**Steps:** Full run (TC-PHASE-004).

**Expected:** Summary includes:
- Facts consolidated (cross-key)
- Facts deduped (same-key, existing)
- Entities merged
- Ghost entities cleaned
- Embeddings added
- Facts decayed
- Facts archived
- Facts purged

**Pass criteria:** All summary fields present in log output.

---

## Section 8 — Boundary Value Analysis

### TC-BVA-001: Cosine similarity boundary — exactly 0.92 triggers merge

**Preconditions:** Two facts engineered to have cosine similarity = 0.92 (as close as feasible).

**Expected:** Merge triggered.

**Pass criteria:** Absorbed fact ID absent from `entity_facts` post-run.

---

### TC-BVA-002: Cosine similarity boundary — 0.919 does NOT trigger merge

**Preconditions:** Two facts with cosine similarity ≈0.919 (just below threshold).

**Expected:** No merge.

**Pass criteria:** Both fact IDs present post-run.

---

### TC-BVA-003: Entity overlap boundary — exactly 80% triggers auto-merge

**Preconditions:** Two entities with exactly 80% data match.

**Expected:** Auto-merge triggered (not review queue).

**Pass criteria:** Absorbed entity absent from `entities`.

---

### TC-BVA-004: Entity overlap boundary — 79.9% goes to review queue (not auto-merge)

**Preconditions:** Two entities with ~79% data match.

**Expected:** Review queue entry; no merge.

**Pass criteria:** Both entities present; review record exists.

---

### TC-BVA-005: Cooldown gate — 3h 59m last run → blocked

**Preconditions:** State file `last_run` = `NOW() - 3 hours 59 minutes`.

**Expected:** Script exits with cooldown message.

**Pass criteria:** Exit code 0 with cooldown message; no DB changes.

---

### TC-BVA-006: Cooldown gate — 4h 1m last run → allowed

**Preconditions:** State file `last_run` = `NOW() - 4 hours 1 minute`.

**Expected:** Script proceeds.

**Pass criteria:** No cooldown message; phases execute.

---

## Section 9 — Error and Edge Cases

### TC-ERR-001: merge_facts called with already-absorbed ID is idempotent/safe

**Preconditions:** Fact 90002 already absorbed into 90001 (does not exist).

**Steps:**
```sql
SELECT merge_facts(90001, 90002);
```

**Expected:** Exception raised: "absorbed fact does not exist" — not a silent failure.

**Pass criteria:** Exception message references missing fact ID.

---

### TC-ERR-002: merge_entities with entity that has only one FK reference (entity_fact_sources)

**Preconditions:** Entity 9002 has one entity_fact_source row referencing it.

**Steps:** `SELECT merge_entities(9001, 9002);`

**Expected:** `entity_fact_sources.source_entity_id` rewired to 9001; entity 9002 deleted.

**Pass criteria:** `SELECT COUNT(*) FROM entity_fact_sources WHERE source_entity_id=9002` = 0.

---

### TC-ERR-003: Cross-key consolidation handles facts with NULL embeddings

**Preconditions:** entity_fact 90005 exists but has no corresponding `memory_embeddings` row.

**Expected:** Script skips this fact in consolidation (no crash); logs warning or silently skips.

**Pass criteria:** No exception; fact 90005 untouched.

---

### TC-ERR-004: Ghost cleanup with malformed entity name (pattern match edge case)

**Preconditions:** Entity named `"entity abc"` (non-numeric suffix) — should NOT match the `"entity N"` pattern.

**Expected:** Entity not treated as a ghost by pattern; not merged.

**Pass criteria:** Entity with name `"entity abc"` still exists.

---

### TC-ERR-005: Ghost pattern entity N where target entity id=N does not exist

**Preconditions:** Entity named `"entity 99999"` exists; no entity with id=99999.

**Expected:** Entity `"entity 99999"` flagged for review (not auto-merged into non-existent target).

**Pass criteria:** Entity `"entity 99999"` still exists; review queue entry written.

---

### TC-ERR-006: Entity dedup does not loop (A→B, B→C does not create A→B→C chain in one run)

**Preconditions:** Entities A (9001), B (9002), C (9006) where A≈B and B≈C.

**Expected:** Only the highest-overlap pair is merged per run; no cascading chain in a single execution.

**Pass criteria:** At most one merge per entity pair per run; no infinite loops.

---

### TC-ERR-007: Script handles empty database (no entity_facts) without error

**Preconditions:** Test against a staging DB with entities table but empty entity_facts.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --dry-run
```

**Expected:** Exit code 0; zero-count summary; no exceptions.

**Pass criteria:** Exit code 0; summary shows 0 for all phase counts.

---

### TC-ERR-008: State file corrupted/invalid JSON — script handles gracefully

**Preconditions:** State file contains `{"broken: json"`.

**Steps:**
```bash
echo '{"broken: json"' > /tmp/mm-corrupt-state.json
python3 memory/scripts/memory-maintenance.py --state-file /tmp/mm-corrupt-state.json --dry-run
```

**Expected:**
- Script treats state file as absent (treats cooldown as expired) OR exits with clear error
- Does not crash with unhandled JSON decode exception

**Pass criteria:** Clean error message or graceful default; no traceback.

---

## Section 10 — Regression: Existing Functionality Not Broken

### TC-REG-001: Same-key dedup still works after rewrite

**Preconditions:** Two entity_facts with same entity_id, same key, similarity ≥0.80 (existing trgm dedup).

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-decay --skip-ghost-cleanup
```

**Expected:** High-similarity same-key pair merged; medium-similarity pair flagged in dedup report.

**Pass criteria:** Existing dedup behavior preserved (see prior test suites for exact criteria).

---

### TC-REG-002: Confidence decay still runs correctly

**Preconditions:** entity_fact with `durability='short_term'`, `last_confirmed_at = 30 days ago`.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-ghost-cleanup
```

**Expected:** Fact's `confidence` decremented per exponential decay formula `e^(-0.02 * 30)`.

**Pass criteria:** New confidence ≈ `old_confidence * e^(-0.6)` (within ±0.001).

---

### TC-REG-003: Archive of low-confidence facts still runs

**Preconditions:** entity_fact with `confidence < 0.10`, `learned_at > 7 days ago`, `durability != 'permanent'`.

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --skip-embed --skip-consolidation --skip-dedup --skip-ghost-cleanup
```

**Expected:** Fact moved to `entity_facts_archive` with `archive_reason='low_confidence'`.

**Pass criteria:** Fact absent from `entity_facts`; present in `entity_facts_archive`.

---

### TC-REG-004: `--dry-run` flag prevents all writes across all phases

**Steps:**
```bash
python3 memory/scripts/memory-maintenance.py --dry-run
```

**Expected:** Zero DB modifications across all tables.

**Pass criteria:** Record counts in all affected tables identical before and after dry run.

---

### TC-REG-005: Embed scripts no longer exist as standalone cron entries

**Steps:**
```bash
crontab -l | grep -E 'embed-memories|embed-full-database|embed-research'
```

**Expected:** Zero matches (these scripts removed from crontab).

**Pass criteria:** No cron entries found for the three old embed scripts.

---

## Section 11 — Source Aggregation Verification

### TC-SRC-001: entity_fact_sources rows correctly aggregated during cross-key consolidation

**Preconditions:**

Two entity_facts for the same entity (9001), each with their own `entity_fact_sources` rows including `source_url`:

```sql
-- Fact A: location (different key from Fact B)
INSERT INTO entity_facts (id, entity_id, key, value, confidence, durability, extraction_count, learned_at, last_confirmed_at)
VALUES (91001, 9001, 'location2', 'Austin, Texas', 0.90, 'long_term', 3, NOW()-INTERVAL '10 days', NOW()-INTERVAL '2 days')
ON CONFLICT DO NOTHING;

-- Fact B: hometown (semantically equivalent, different key)
INSERT INTO entity_facts (id, entity_id, key, value, confidence, durability, extraction_count, learned_at, last_confirmed_at)
VALUES (91002, 9001, 'hometown2', 'Austin TX', 0.85, 'long_term', 2, NOW()-INTERVAL '15 days', NOW()-INTERVAL '5 days')
ON CONFLICT DO NOTHING;

-- Sources for Fact A (one shared source + one unique source)
INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, source_url, attribution_count, first_seen, last_seen)
VALUES
  (91001, 9001, 'shared-chat-session-42', 'https://example.com/chat/42', 2, NOW()-INTERVAL '10 days', NOW()-INTERVAL '2 days'),
  (91001, 9001, 'unique-source-fact-a',   'https://example.com/doc/a',   1, NOW()-INTERVAL '9 days',  NOW()-INTERVAL '3 days')
ON CONFLICT DO NOTHING;

-- Sources for Fact B (the same shared source + one unique source)
INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, source_url, attribution_count, first_seen, last_seen)
VALUES
  (91002, 9001, 'shared-chat-session-42', 'https://example.com/chat/42', 1, NOW()-INTERVAL '15 days', NOW()-INTERVAL '5 days'),
  (91002, 9001, 'unique-source-fact-b',   'https://example.com/doc/b',   3, NOW()-INTERVAL '14 days', NOW()-INTERVAL '6 days')
ON CONFLICT DO NOTHING;

-- Seed embeddings at >=0.92 cosine similarity for facts 91001 and 91002
-- (via embed phase or manual INSERT into memory_embeddings)
```

**Steps:**

1. Seed the data above.
2. Confirm cosine similarity between fact 91001 and 91002 embeddings is >=0.92.
3. Run cross-key consolidation:
   ```bash
   python3 memory/scripts/memory-maintenance.py \
     --skip-embed --skip-dedup --skip-decay --skip-ghost-cleanup
   ```
4. Identify the survivor fact ID (whichever of 91001/91002 remains).

**Expected:**

- The absorbed fact is removed from `entity_facts`.
- The survivor retains all `entity_fact_sources` rows from both facts (3 total distinct sources, since `shared-chat-session-42` is shared).
- Shared source `shared-chat-session-42` has `attribution_count` summed (2+1=3).
- Unique sources (`unique-source-fact-a` and `unique-source-fact-b`) are moved to the survivor with their original `attribution_count` values intact.
- `source_url` values are preserved on all surviving source rows.

**Pass criteria:**
```sql
-- Three distinct source citations on the survivor
SELECT COUNT(*) FROM entity_fact_sources WHERE fact_id = <survivor_id>;
-- Returns 3

-- Shared source has summed attribution_count
SELECT attribution_count FROM entity_fact_sources
  WHERE fact_id = <survivor_id> AND source_citation = 'shared-chat-session-42';
-- Returns 3

-- Unique sources preserved with correct source_url
SELECT source_citation, source_url, attribution_count
  FROM entity_fact_sources WHERE fact_id = <survivor_id>
  ORDER BY source_citation;
-- Rows: shared-chat-session-42 / https://example.com/chat/42 (3),
--        unique-source-fact-a   / https://example.com/doc/a   (1),
--        unique-source-fact-b   / https://example.com/doc/b   (3)
-- All source_url values non-null and matching originals

-- Absorbed fact has no source rows
SELECT COUNT(*) FROM entity_fact_sources WHERE fact_id = <absorbed_id>;
-- Returns 0
```

---

## Section 12 — Embedding Dimension Mismatch

### TC-DIM-001: Script handles 1536-dim legacy embeddings gracefully during consolidation

**Preconditions:**

Seed an entity_fact with a 1536-dimensional embedding (legacy OpenAI format) instead of the current 1024-dim Ollama `mxbai-embed-large` format:

```sql
-- Create a test fact
INSERT INTO entity_facts (id, entity_id, key, value, confidence, durability, extraction_count, learned_at, last_confirmed_at)
VALUES (92001, 9001, 'legacy_dim_test', 'some value', 0.75, 'long_term', 1, NOW()-INTERVAL '3 days', NOW()-INTERVAL '1 day')
ON CONFLICT DO NOTHING;

-- Manually insert a 1536-dim embedding (fill with 0.001 to avoid zero-vector issues)
INSERT INTO memory_embeddings (source_type, source_id, embedding, model, created_at, updated_at)
VALUES (
  'entity_fact',
  '92001',
  (SELECT array_fill(0.001::float4, ARRAY[1536])::vector),
  'openai/text-embedding-ada-002',
  NOW()-INTERVAL '30 days',
  NOW()-INTERVAL '30 days'
)
ON CONFLICT (source_type, source_id) DO UPDATE
  SET embedding = EXCLUDED.embedding,
      model     = EXCLUDED.model,
      updated_at = EXCLUDED.updated_at;
```

**Steps:**

```bash
python3 memory/scripts/memory-maintenance.py \
  --skip-embed --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**

The script must NOT crash (no unhandled exception). One of these behaviors is acceptable (whichever the spec defines):
- **Skip**: Fact 92001 is excluded from consolidation comparisons; a warning is logged (e.g., "Skipping entity_fact 92001: embedding dimension 1536 != expected 1024").
- **Re-embed**: The 1536-dim embedding is replaced with a fresh 1024-dim embedding before comparison proceeds.
- **Structured error**: An error is raised, logged, and the script continues with remaining facts (no full abort).

Under no scenario should the script:
- Silently attempt to compute cosine similarity between 1536-dim and 1024-dim vectors (pgvector will raise a dimension mismatch error).
- Exit with an unhandled Python traceback.
- Leave entity_fact 92001 in a corrupt or missing state.

**Pass criteria:**

```bash
# No Python traceback in output
python3 memory/scripts/memory-maintenance.py ... 2>&1 | grep -c "Traceback"
# Returns 0
```

```sql
-- entity_fact 92001 still intact after run
SELECT COUNT(*) FROM entity_facts WHERE id = 92001;
-- Returns 1
```

- If **skip** behavior: log output contains a dimension mismatch warning for fact 92001.
- If **re-embed** behavior: `memory_embeddings` row for `source_id='92001'` has `array_length(embedding::real[], 1) = 1024`.

---

## Section 13 — Multi-Fact Cluster Consolidation (3+ Facts)

### TC-CLUSTER-001: Three-way cross-key fact cluster fully consolidated into one survivor

**Preconditions:**

Seed three semantically equivalent facts (different keys, same entity) whose pairwise cosine similarities are all >=0.92:

```sql
-- The "pizza scenario": three keys all expressing the same preference
INSERT INTO entity_facts (id, entity_id, key, value, confidence, durability, extraction_count, learned_at, last_confirmed_at)
VALUES
  (93001, 9001, 'pizza_preference',      'loves pizza',               0.88, 'long_term', 4, NOW()-INTERVAL '20 days', NOW()-INTERVAL '5 days'),
  (93002, 9001, 'preference_food_likes', 'pizza is a favourite',      0.82, 'long_term', 3, NOW()-INTERVAL '18 days', NOW()-INTERVAL '6 days'),
  (93003, 9001, 'liked_pizza_types',     'enjoys pizza of all kinds', 0.80, 'long_term', 2, NOW()-INTERVAL '15 days', NOW()-INTERVAL '7 days')
ON CONFLICT DO NOTHING;

-- Source rows for each fact
INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen)
VALUES
  (93001, 9001, 'pizza-source-a', 2, NOW()-INTERVAL '20 days', NOW()-INTERVAL '5 days'),
  (93002, 9001, 'pizza-source-b', 1, NOW()-INTERVAL '18 days', NOW()-INTERVAL '6 days'),
  (93003, 9001, 'pizza-source-c', 3, NOW()-INTERVAL '15 days', NOW()-INTERVAL '7 days')
ON CONFLICT DO NOTHING;

-- NOTE: Embeddings must be generated or manually seeded such that:
--   cosine_sim(93001, 93002) >= 0.92
--   cosine_sim(93001, 93003) >= 0.92
--   cosine_sim(93002, 93003) >= 0.92
-- Verify:
--   SELECT 1-(e1.embedding<=>e2.embedding) AS sim,
--          e1.source_id AS a, e2.source_id AS b
--   FROM memory_embeddings e1, memory_embeddings e2
--   WHERE e1.source_id IN ('93001','93002','93003')
--     AND e2.source_id IN ('93001','93002','93003')
--     AND e1.source_id < e2.source_id;
```

**Steps:**

```bash
python3 memory/scripts/memory-maintenance.py \
  --skip-embed --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**

- All three facts are merged into a single survivor (highest confidence wins; tie-break by extraction_count).
- Two absorbed facts removed from `entity_facts`.
- Survivor's `extraction_count` = 4+3+2 = 9.
- Survivor's `confidence` = GREATEST(0.88, 0.82, 0.80) = 0.88.
- All three source records exist on the survivor in `entity_fact_sources`.

**Pass criteria:**

```sql
-- Only one fact remains from the cluster
SELECT COUNT(*) FROM entity_facts WHERE id IN (93001, 93002, 93003);
-- Returns 1

-- Survivor has summed extraction_count
SELECT extraction_count FROM entity_facts WHERE id IN (93001, 93002, 93003);
-- Returns 9

-- Survivor has highest confidence
SELECT confidence FROM entity_facts WHERE id IN (93001, 93002, 93003);
-- Returns 0.88

-- All three sources aggregated onto survivor
SELECT COUNT(*) FROM entity_fact_sources WHERE fact_id = <survivor_id>;
-- Returns 3 (pizza-source-a, pizza-source-b, pizza-source-c)

-- Absorbed facts have no source rows
SELECT COUNT(*) FROM entity_fact_sources WHERE fact_id IN (<absorbed_id_1>, <absorbed_id_2>);
-- Returns 0
```

---

### TC-CLUSTER-002: 4-fact cluster consolidated in a single run (no partial convergence)

**Preconditions:** Four semantically near-identical facts for the same entity (e.g., four different phrasings of the same address). All pairwise cosine similarities >=0.92.

**Steps:** Run cross-key consolidation.

**Expected:**
- All four facts collapse into one survivor in a single script run (not requiring 3 separate runs to converge).
- Survivor `extraction_count` = sum of all four.

**Pass criteria:**
```sql
SELECT COUNT(*) FROM entity_facts WHERE id IN (<f1>, <f2>, <f3>, <f4>);
-- Returns 1
```

---

### TC-CLUSTER-003: Partial cluster — 3 facts where only 2 pairs meet the threshold

**Preconditions:**
- Fact A and Fact B: cosine similarity >=0.92.
- Fact A and Fact C: cosine similarity >=0.92.
- Fact B and Fact C: cosine similarity 0.88 (<0.92).

**Expected:**
- The consolidation algorithm produces a deterministic, documented result (depends on clustering strategy: single-linkage, complete-linkage, or union-find).
- No merge of any fact pair with cosine similarity <0.92.
- **Note to implementer:** Document the clustering algorithm used. This test validates it is deterministic and spec-compliant.

**Pass criteria:** Behavior matches the documented clustering algorithm; no fact pair with similarity <0.92 is merged.

---

## Section 14 — Flag Scope Clarity for Dedup Phases

> **Background:** TC-EDUP-005 previously used `--skip-dedup` to skip entity-level dedup. However, `--skip-dedup` is the existing flag for *same-key fact dedup only*. Entity-level dedup has its own separate flag `--skip-entity-dedup`. This section tests both flags in isolation to confirm each skips only its intended phase.

### TC-FLAG-001: `--skip-dedup` skips same-key fact dedup only (not entity dedup)

**Preconditions:**

- Two entity_facts with the same `entity_id` and same `key`, trgm similarity >=0.80 (same-key dedup candidate).
- Two entities with >=80% fact overlap (entity dedup auto-merge candidate).

```sql
-- Same-key dedup pair
INSERT INTO entity_facts (id, entity_id, key, value, confidence, durability, extraction_count, learned_at, last_confirmed_at)
VALUES
  (94001, 9001, 'same_key_test', 'software engineer at NOVA', 0.85, 'long_term', 2, NOW()-INTERVAL '5 days', NOW()-INTERVAL '1 day'),
  (94002, 9001, 'same_key_test', 'software engineer',         0.80, 'long_term', 1, NOW()-INTERVAL '6 days', NOW()-INTERVAL '2 days')
ON CONFLICT DO NOTHING;

-- High-overlap entity pair (reuse 9001/9002 if they meet >=80% threshold, or seed a dedicated pair)
```

**Steps:**

```bash
python3 memory/scripts/memory-maintenance.py \
  --skip-embed --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**

- Same-key dedup phase SKIPPED: facts 94001 and 94002 both remain in `entity_facts`.
- Entity dedup phase RUNS: high-overlap entity pair evaluated and (if >=80%) auto-merged.
- Log confirms `--skip-dedup` applies to same-key fact dedup phase only.

**Pass criteria:**

```sql
-- Same-key facts untouched
SELECT COUNT(*) FROM entity_facts WHERE id IN (94001, 94002);
-- Returns 2

-- Entity dedup ran: verify the high-overlap entity candidate was processed
-- (check relevant entity IDs based on test setup)
```

---

### TC-FLAG-002: `--skip-entity-dedup` skips entity-level dedup only (not same-key fact dedup)

**Preconditions:** Same as TC-FLAG-001.

**Steps:**

```bash
python3 memory/scripts/memory-maintenance.py \
  --skip-embed --skip-consolidation --skip-entity-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**

- Same-key fact dedup phase RUNS: facts 94001 and 94002 evaluated for merge (one absorbed).
- Entity dedup phase SKIPPED: high-overlap entity pair remains unmerged.
- Log confirms `--skip-entity-dedup` applies to entity dedup phase only.

**Pass criteria:**

```sql
-- Same-key dedup ran: one fact absorbed
SELECT COUNT(*) FROM entity_facts WHERE id IN (94001, 94002);
-- Returns 1

-- Entity dedup skipped: both entities still present
-- (verify entity IDs for the high-overlap candidate pair)
```

---

### TC-FLAG-003: `--skip-dedup --skip-entity-dedup` skips both dedup phases

**Preconditions:** Both same-key and entity dedup candidates present.

**Steps:**

```bash
python3 memory/scripts/memory-maintenance.py \
  --skip-embed --skip-consolidation --skip-dedup --skip-entity-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**

- Both same-key fact dedup and entity dedup phases skipped.
- Log shows skip messages for both phases.
- No merges of either type.

**Pass criteria:**

```sql
-- Same-key candidate facts untouched
SELECT COUNT(*) FROM entity_facts WHERE id IN (94001, 94002);
-- Returns 2

-- Entity dedup candidate entities untouched (verify IDs)
```

---

### TC-FLAG-004 (Replaces TC-EDUP-005): `--skip-entity-dedup` skips entity-level dedup phase

> **Note:** This test supersedes the original TC-EDUP-005, which incorrectly used `--skip-dedup` to skip entity dedup. The correct flag is `--skip-entity-dedup`.

**Preconditions:** A high-overlap entity pair in DB (>=80% fact overlap, entity dedup auto-merge candidate).

**Steps:**

```bash
python3 memory/scripts/memory-maintenance.py \
  --skip-embed --skip-consolidation --skip-entity-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**

- Entity dedup phase skipped.
- Both entities remain in `entities`.
- Log contains message indicating entity dedup was skipped.

**Pass criteria:**

```sql
-- Both entities still present
SELECT COUNT(*) FROM entities WHERE id IN (<entity_a_id>, <entity_b_id>);
-- Returns 2
```

Log output: contains "skip" and "entity-dedup" (or equivalent phrasing).

---

### TC-FLAG-005: `--skip-dedup` does not suppress entity dedup (negative confirmation)

**Preconditions:** Same-key dedup candidate (facts 94001/94002) AND high-overlap entity dedup candidate both present.

**Steps:**

```bash
# skip-entity-dedup is NOT set; only skip-dedup is set
python3 memory/scripts/memory-maintenance.py \
  --skip-embed --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup
```

**Expected:**

- Same-key dedup is skipped (facts 94001/94002 both remain).
- Entity dedup RUNS (not suppressed by `--skip-dedup`); high-overlap pair evaluated.

**Pass criteria:**

```sql
-- Same-key candidates untouched
SELECT COUNT(*) FROM entity_facts WHERE id IN (94001, 94002);
-- Returns 2

-- Entity dedup processed the candidate pair (verify entity IDs)
```

---

## Coverage Summary

| Area | Test Cases | Pattern |
|------|-----------|---------|
| Cooldown gate | TC-COOL-001–006 | Happy path, BVA, edge |
| Embedding absorption | TC-EMBED-001–006 | Happy path, idempotency, skip, error |
| Cross-key consolidation | TC-XKEY-001–007 | Happy path, threshold BVA, isolation, dry-run |
| merge_entities() function | TC-MENT-001–008 | FK rewiring, all 21 tables, error paths |
| Ghost entity cleanup | TC-GHOST-001–006 | Pattern match, hard-delete, FK protection, low-fact |
| Entity-level dedup | TC-EDUP-001–007 | Auto-merge, review queue, type isolation |
| Phase ordering/integration | TC-PHASE-001–005 | Order, skip-all, DB error, E2E |
| Boundary value analysis | TC-BVA-001–006 | Thresholds at ±1 |
| Error/edge cases | TC-ERR-001–008 | Null embeddings, malformed input, cascades |
| Regression | TC-REG-001–005 | Existing functionality preserved |
| Source aggregation | TC-SRC-001 | Cross-key merge: source rows preserved, shared sources summed, source_url retained |
| Embedding dimension mismatch | TC-DIM-001 | 1536-dim legacy embedding handled gracefully (skip/re-embed/error, no crash) |
| Multi-fact clusters (3+) | TC-CLUSTER-001–003 | 3-way merge, 4-way merge, partial cluster (non-transitive similarity) |
| Flag scope clarity | TC-FLAG-001–005 | --skip-dedup vs --skip-entity-dedup isolated; both-skip; negative confirmation |

**Total test cases: 72** *(added 15: TC-SRC-001, TC-DIM-001, TC-CLUSTER-001–003, TC-FLAG-001–005; TC-EDUP-005 flag corrected)*

---

## Notes for Flint (QA Executor)

1. **Staging only.** Never run these tests against production. Use `nova-staging@localhost` per team rules.
2. **Seed data first.** Run the SQL in "Test Data Setup" before any test case.
3. **Rollback after destructive tests.** Wrap destructive SQL tests (merge, delete) in transactions with ROLLBACK unless you specifically need to confirm the committed state. Use explicit `BEGIN; ... ROLLBACK;` unless testing commit behavior.
4. **Embedding tests require Ollama.** TC-EMBED-* require `mxbai-embed-large` to be loaded. Confirm with `curl http://localhost:11434/api/tags`.
5. **TC-MENT-003 requires a temp table.** Drop it after the test as instructed.
6. **Cosine similarity seeding.** For TC-XKEY-001/002 and TC-BVA-001/002, verify similarity values before running: `SELECT 1 - (e1.embedding <=> e2.embedding) AS cosine_sim FROM memory_embeddings e1, memory_embeddings e2 WHERE e1.source_id = '90001' AND e2.source_id = '90002';`
7. **Review queue table.** TC-EDUP-002, TC-GHOST-004, TC-ERR-005 reference a "manual review queue." The table name must be confirmed from the implementation spec before execution.
8. **State file path.** The `--state-file` flag is assumed from spec. Confirm the actual flag name with the implementation.
9. **TC-SRC-001 source_url column.** If `entity_fact_sources` does not have a `source_url` column in the current schema, confirm the column name from the implementation spec before executing TC-SRC-001.
10. **TC-DIM-001 embedding seed.** The `array_fill(0.001::float4, ARRAY[1536])::vector` cast requires the `vector` type to accept variable-dimension input, or the `memory_embeddings.embedding` column to be untyped. Adjust the seed SQL if the column enforces a fixed 1024-dim type (use `vector(1536)` cast or a workaround agreed with the implementer).
11. **TC-CLUSTER-001–003 embedding seeding.** Three-way cluster tests require all three pairwise cosine similarities >=0.92. Verify all three pairs before running, not just one pair.
12. **TC-FLAG-001–005 flag names.** `--skip-entity-dedup` is the expected flag name per spec. If the implementation uses a different name (e.g., `--skip-entity-level-dedup`), update all TC-FLAG-* steps accordingly.
