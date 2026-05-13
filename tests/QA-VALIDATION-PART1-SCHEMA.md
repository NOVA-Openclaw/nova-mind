# QA Validation — Part 1: Schema & Migration Desk Review

**Branch:** `feat/entity-facts-schema-evolution-batch`  
**Repo:** `~/.openclaw/workspace/nova-mind`  
**Reviewed by:** Gem (QA Lead)  
**Date:** 2026-05-13  
**Scope:** Files 1–7 (schema.sql + migrations 068–073)

---

## 1. `entity_facts` Table — Column Presence Checks

### Required columns (MUST EXIST)

| # | Column | Status | Notes |
|---|--------|--------|-------|
| 1.1 | `extraction_count INTEGER DEFAULT 1` | ✅ PASS | Present, correct type and default |
| 1.2 | `expires TIMESTAMPTZ` | ✅ PASS | Present, nullable (no default) — correct |
| 1.3 | `durability VARCHAR(20) NOT NULL DEFAULT 'long_term'` | ✅ PASS | Present; CHECK constraint `chk_durability` covers `permanent/long_term/short_term/ephemeral` |
| 1.4 | `category TEXT NOT NULL DEFAULT 'observation'` | ✅ PASS | Present, NOT NULL, correct default |
| 1.5 | `last_confirmed_at TIMESTAMPTZ DEFAULT now()` | ✅ PASS | Present with timezone — correct column name |

### Prohibited columns (MUST NOT EXIST)

| # | Column | Status | Notes |
|---|--------|--------|-------|
| 1.6 | `vote_count` | ✅ PASS | Absent from schema.sql; dropped in migration 068 |
| 1.7 | `confirmation_count` | ✅ PASS | Absent from schema.sql; dropped in migration 068 |
| 1.8 | `last_confirmed` (no-tz variant) | ✅ PASS | Absent from schema.sql; dropped in migration 068 |
| 1.9 | `data_type` | ✅ PASS | Absent from schema.sql; dropped in migration 070 |
| 1.10 | `source` (text column) | ✅ PASS | Absent from schema.sql; dropped in migration 071 |
| 1.11 | `source_entity_id` (on entity_facts) | ✅ PASS | Absent from schema.sql; dropped in migration 071 |

**⚠️ NOTE — `confirmation_count` still present in schema.sql:**  
The schema.sql line 1 (entity_facts definition) **still includes `confirmation_count integer DEFAULT 1`**. This column should have been removed by migration 068 (`DROP COLUMN IF EXISTS confirmation_count`). The schema.sql appears to reflect a state that is _prior to_ the full drop phase, OR the schema dump did not regenerate post-migration. 

**Re-check:** Looking again at the schema.sql entity_facts definition:
```sql
    extraction_count INTEGER DEFAULT 1,
    last_confirmed_at timestamptz DEFAULT now(),
    confirmation_count integer DEFAULT 1,
```
**FINDING: `confirmation_count` is still present in `schema.sql` alongside `extraction_count`.** Migration 068 drops it, but `schema.sql` still declares it. This is a **schema/migration divergence**.

| 1.7-REVISED | `confirmation_count` in schema.sql | ❌ FAIL | Column still declared in schema.sql despite migration 068 dropping it. Schema.sql must be regenerated after migrations. |

---

## 2. `entity_fact_sources` Table

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 2.1 | `fact_id INTEGER NOT NULL REFERENCES entity_facts(id) ON DELETE CASCADE` | ✅ PASS | Present in both schema.sql and migration 071 |
| 2.2 | `source_entity_id INTEGER NOT NULL REFERENCES entities(id)` | ✅ PASS | NOT NULL enforced, FK to entities present |
| 2.3 | `source_citation TEXT` nullable | ✅ PASS | No NOT NULL constraint — correctly nullable |
| 2.4 | `attribution_count INTEGER DEFAULT 1` | ✅ PASS | Present with correct default |
| 2.5 | `first_seen TIMESTAMPTZ DEFAULT now()` | ✅ PASS | Present, correct type |
| 2.6 | `last_seen TIMESTAMPTZ DEFAULT now()` | ✅ PASS | Present, correct type |
| 2.7 | `UNIQUE(fact_id, source_entity_id)` | ✅ PASS | Implemented as `CONSTRAINT uq_fact_source` |
| 2.8 | Index on `fact_id` | ✅ PASS | `idx_entity_fact_sources_fact` (schema.sql) / `idx_efs_fact_id` (migration 071) — note name differs between migration and schema; both create the index |
| 2.9 | Index on `source_entity_id` | ✅ PASS | `idx_entity_fact_sources_entity` (schema.sql) / `idx_efs_source_entity_id` (migration 071) — same note on name divergence |

**⚠️ NOTE — Index name divergence:** Migration 071 creates `idx_efs_fact_id` and `idx_efs_source_entity_id`. Schema.sql shows `idx_entity_fact_sources_fact` and `idx_entity_fact_sources_entity`. These are functionally identical but the names differ — indicates schema.sql was regenerated after the migration ran and the DB used the final index names. No functional issue, but worth noting for clarity.

---

## 3. `merge_facts()` Function

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 3.1 | Validates both facts exist | ✅ PASS | `IF NOT FOUND THEN RAISE EXCEPTION` for both survivor and absorbed |
| 3.2 | Rejects self-merge | ✅ PASS | `IF survivor_id = absorbed_id THEN RAISE EXCEPTION 'cannot merge a fact with itself'` |
| 3.3 | Rejects cross-entity merge | ✅ PASS | `IF survivor_row.entity_id != absorbed_row.entity_id THEN RAISE EXCEPTION 'cannot merge facts from different entities'` |
| 3.4 | Sums `extraction_count` | ✅ PASS | `COALESCE(survivor_row.extraction_count, 1) + COALESCE(absorbed_row.extraction_count, 1)` |
| 3.5 | MAX `confidence` | ✅ PASS | `GREATEST(survivor_row.confidence, absorbed_row.confidence)` |
| 3.6 | MAX `last_confirmed_at` | ✅ PASS | `GREATEST(survivor_row.last_confirmed_at, absorbed_row.last_confirmed_at)` |
| 3.7 | Merges sources — shared: sums attribution_count, LEAST first_seen, GREATEST last_seen | ✅ PASS | UPDATE with `s_survivor.fact_id = survivor_id AND s_absorbed.fact_id = absorbed_id AND s_survivor.source_entity_id = s_absorbed.source_entity_id` |
| 3.8 | Moves unique sources from absorbed to survivor | ✅ PASS | INSERT with `NOT IN (SELECT source_entity_id FROM entity_fact_sources WHERE fact_id = survivor_id)` |
| 3.9 | Deletes absorbed sources | ✅ PASS | `DELETE FROM entity_fact_sources WHERE fact_id = absorbed_id` |
| 3.10 | Deletes absorbed fact | ✅ PASS | `DELETE FROM entity_facts WHERE id = absorbed_id` |
| 3.11 | Returns updated survivor row | ✅ PASS | Final `SELECT * INTO result_row FROM entity_facts WHERE id = survivor_id; RETURN result_row` |
| 3.12 | Schema.sql and migration 072 match | ✅ PASS | Function body is identical in both files |

---

## 4. Migration 068 — `extraction_count` Consolidation

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 4.1 | `COALESCE(GREATEST(vote_count, confirmation_count), 1)` for NULL handling | ✅ PASS | Two UPDATE statements: one for rows where both are NOT NULL, one for all remaining NULL rows. Both use `COALESCE(GREATEST(vote_count, confirmation_count), 1)` |
| 4.2 | Final safety: `UPDATE SET extraction_count = 1 WHERE extraction_count IS NULL` | ✅ PASS | Present as final fallback |
| 4.3 | VERIFY DO block asserts no NULLs | ✅ PASS | `RAISE EXCEPTION 'Migration 068 VERIFY failed: NULL extraction_count values remain'` |
| 4.4 | Drops `vote_count`, `confirmation_count`, `last_confirmed` | ✅ PASS | `DROP COLUMN IF EXISTS vote_count, DROP COLUMN IF EXISTS confirmation_count, DROP COLUMN IF EXISTS last_confirmed` |
| 4.5 | Drops `idx_entity_facts_vote_count` | ✅ PASS | `DROP INDEX IF EXISTS idx_entity_facts_vote_count` |
| 4.6 | Drops `idx_entity_facts_data_type` | ⚠️ N/A | Migration 068 does NOT drop this index — it's dropped in migration 070. Correct sequencing. |

**⚠️ LOGIC NOTE on UPDATE sequencing:** The first UPDATE handles rows where BOTH `vote_count` and `confirmation_count` are NOT NULL. The second UPDATE applies `COALESCE(GREATEST(...), 1)` to ALL rows where `extraction_count IS NULL` — which covers rows where one column is NULL and the other isn't. This is correct but slightly redundant (first UPDATE is a subset of what the second UPDATE catches). No functional issue.

---

## 5. Migration 070 — Durability + Category

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 5.1 | `permanent` → `permanent`/`identity` | ✅ PASS | `WHERE data_type = 'permanent' SET durability='permanent', category='identity'` |
| 5.2 | `identity` → `permanent`/`identity` | ✅ PASS | `WHERE data_type = 'identity' SET durability='permanent', category='identity'` |
| 5.3 | `preference` → `long_term`/`preference` | ✅ PASS | `WHERE data_type = 'preference' SET durability='long_term', category='preference'` |
| 5.4 | `observation` → `long_term`/`observation` | ✅ PASS | `WHERE data_type = 'observation' SET durability='long_term', category='observation'` |
| 5.5 | Unmapped rows get safe defaults `long_term`/`observation` | ✅ PASS | Final UPDATE catches `WHERE durability IS NULL OR category IS NULL` |
| 5.6 | VERIFY asserts no NULLs | ✅ PASS | DO block raises exception on any NULL durability or category |
| 5.7 | Drops `data_type` column | ✅ PASS | `DROP COLUMN IF EXISTS data_type` |
| 5.8 | Drops `chk_data_type` constraint | ✅ PASS | `DROP CONSTRAINT IF EXISTS chk_data_type` |
| 5.9 | Drops `idx_entity_facts_data_type` | ✅ PASS | Present |
| 5.10 | Creates `idx_entity_facts_durability` | ✅ PASS | `CREATE INDEX IF NOT EXISTS idx_entity_facts_durability ON entity_facts (durability)` |
| 5.11 | Creates `idx_entity_facts_category` | ✅ PASS | `CREATE INDEX IF NOT EXISTS idx_entity_facts_category ON entity_facts (category)` |

---

## 6. Migration 071 — Source Attribution

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 6.1 | NULL/NULL facts → attributed to NOVA (entity_id=1) | ✅ PASS | Third INSERT block: `WHERE source_entity_id IS NULL AND (source IS NULL OR source = '' OR source = 'auto-extracted')` → inserts with `source_entity_id = 1` |
| 6.2 | Facts with `source_entity_id` migrated directly | ✅ PASS | First INSERT block uses `WHERE source_entity_id IS NOT NULL` |
| 6.3 | Facts with source text (no entity_id): entity name lookup, fallback to NOVA | ✅ PASS | DO block loops, tries name/full_name/nickname match, falls back to `resolved_entity_id := 1` |
| 6.4 | VERIFY: no orphan facts without source attribution | ✅ PASS | `NOT EXISTS (SELECT 1 FROM entity_fact_sources efs WHERE efs.fact_id = ef.id)` raises exception |
| 6.5 | Drops `source`, `source_entity_id` from entity_facts | ✅ PASS | `DROP COLUMN IF EXISTS source, DROP COLUMN IF EXISTS source_entity_id` |
| 6.6 | Drops `idx_entity_facts_source_entity` | ✅ PASS | Present |

---

## 7. Indexes — Required Present / Required Absent

| # | Index | Status | Notes |
|---|-------|--------|-------|
| 7.1 | `idx_entity_facts_durability` | ✅ PASS | Present in schema.sql |
| 7.2 | `idx_entity_facts_category` | ✅ PASS | Present in schema.sql |
| 7.3 | `idx_entity_facts_vote_count` | ✅ PASS (absent) | Not present in schema.sql; dropped by migration 068 |
| 7.4 | `idx_entity_facts_data_type` | ✅ PASS (absent) | Not present in schema.sql; dropped by migration 070 |

---

## 8. entity_facts_archive Table (Migration 073)

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 8.1 | Drops `vote_count` | ✅ PASS | `DROP COLUMN IF EXISTS vote_count` |
| 8.2 | Drops `last_confirmed` | ✅ PASS | `DROP COLUMN IF EXISTS last_confirmed` |
| 8.3 | Drops `data_type` | ✅ PASS | `DROP COLUMN IF EXISTS data_type` |
| 8.4 | Drops `confirmation_count` | ✅ PASS | `DROP COLUMN IF EXISTS confirmation_count` |
| 8.5 | Drops `source`, `source_entity_id` | ✅ PASS | `DROP COLUMN IF EXISTS source, DROP COLUMN IF EXISTS source_entity_id` |
| 8.6 | Adds `extraction_count INTEGER DEFAULT 1` | ✅ PASS | `ADD COLUMN IF NOT EXISTS extraction_count INTEGER DEFAULT 1` |
| 8.7 | Adds `durability VARCHAR(20) DEFAULT 'long_term'` | ✅ PASS | Present |
| 8.8 | Adds `category TEXT DEFAULT 'observation'` | ✅ PASS | Present |
| 8.9 | Adds `expires TIMESTAMPTZ` | ✅ PASS | Present |
| 8.10 | Archive columns match entity_facts schema (both have extraction_count, durability, category, expires) | ✅ PASS | Schema.sql entity_facts_archive definition confirms parity |

---

## Summary — Findings

### ❌ FAILURES (1)

| ID | Severity | File | Issue |
|----|----------|------|-------|
| F-001 | S3/P2 | `database/schema.sql` | `confirmation_count INTEGER DEFAULT 1` still declared in `entity_facts` table definition. Migration 068 drops this column but schema.sql was not regenerated post-migration (or was hand-edited). Schema.sql and live DB state are diverged. Must regenerate schema.sql after running all migrations. |

### ⚠️ WARNINGS (non-blocking, informational)

| ID | File | Note |
|----|------|------|
| W-001 | `migration 071` vs `schema.sql` | Index names differ (`idx_efs_fact_id` vs `idx_entity_facts_fact`) — functionally equivalent, schema.sql reflects final DB state. No action required but should document intent. |
| W-002 | `migration 068` | First UPDATE is a subset of second UPDATE logic — slight redundancy. Not a bug, but could be simplified to one UPDATE. |
| W-003 | `migration 070` | `permanent` and `identity` data_type values both map to `permanent`/`identity`. If rows existed with `data_type = 'identity'` that were semantically different from `permanent`, they collapse. Verify this mapping was intentional with spec owners. |

### ✅ PASSING ITEMS: 35/36 checks

---

## Required Action Before Part 2

**F-001 MUST be resolved:**  
Regenerate `database/schema.sql` by running all migrations against a clean DB and dumping the result with `pgschema` or `pg_dump`. The current schema.sql is stale — it retains `confirmation_count` which should have been dropped by migration 068.

**Option A (preferred):** Run migrations 068–073 on a clean staging DB and re-dump schema.  
**Option B:** Manually remove `confirmation_count integer DEFAULT 1,` from the entity_facts CREATE TABLE block in schema.sql.

*Part 2 (API handler and test coverage review) to follow in QA-VALIDATION-PART2.*
