# QA Test Cases: entity_facts Schema Evolution Batch (Issues #139, #167, #188, #189, #190, #192, #204)
# Designed by Gem (QA Lead) — SE Workflow Step 3
# 2026-05-13

---

## Section 1: Schema Migration — Issue #190 (extraction_count)

### TC-190-001
**Category:** Schema Migration / ADD phase
**Description:** `extraction_count` column added with correct definition
**Preconditions:** Migration script run through ADD phase only (before MIGRATE)
**Steps:**
1. Run ADD phase of #190 migration
2. Query `information_schema.columns` for `entity_facts.extraction_count`
**Expected:** Column exists, `data_type = 'integer'`, `column_default = '1'`, `is_nullable = 'YES'`

### TC-190-002
**Category:** Schema Migration / MIGRATE phase — happy path
**Description:** `extraction_count` correctly populated from GREATEST(vote_count, confirmation_count)
**Preconditions:** Seed rows with known values:
- Row A: vote_count=3, confirmation_count=5 → expect 5
- Row B: vote_count=7, confirmation_count=2 → expect 7
- Row C: vote_count=4, confirmation_count=4 → expect 4
**Steps:**
1. Run MIGRATE phase
2. SELECT extraction_count for rows A, B, C
**Expected:** extraction_count = 5, 7, 4 respectively

### TC-190-003
**Category:** Schema Migration / MIGRATE phase — NULL inputs (edge case)
**Description:** GREATEST(NULL, NULL) returns NULL; migration must handle this
**Preconditions:** Seed row D: vote_count=NULL, confirmation_count=NULL
**Steps:**
1. Run MIGRATE phase
2. SELECT extraction_count for row D
**Expected:** extraction_count = 1 (DEFAULT must be applied via COALESCE in migration SQL). **Note to Coder:** Migration UPDATE must use `COALESCE(GREATEST(vote_count, confirmation_count), 1)`, not bare GREATEST.

### TC-190-004
**Category:** Schema Migration / MIGRATE phase — one NULL input
**Description:** GREATEST(NULL, 5) behavior
**Preconditions:** Seed row E: vote_count=NULL, confirmation_count=5
**Steps:**
1. Run MIGRATE phase
2. SELECT extraction_count for row E
**Expected:** extraction_count = 5 (PostgreSQL GREATEST ignores NULLs when at least one non-null)

### TC-190-005
**Category:** Schema Migration / VERIFY phase
**Description:** No NULLs in extraction_count after migration
**Preconditions:** Full dataset migrated
**Steps:**
1. `SELECT COUNT(*) FROM entity_facts WHERE extraction_count IS NULL;`
**Expected:** 0 rows

### TC-190-006
**Category:** Schema Migration / DROP phase
**Description:** vote_count, confirmation_count, last_confirmed (no-tz) columns removed; last_confirmed_at (with-tz) retained
**Preconditions:** DROP phase executed
**Steps:**
1. Query `information_schema.columns` for all four column names
**Expected:**
- `vote_count`: not found
- `confirmation_count`: not found
- `last_confirmed` (without tz): not found
- `last_confirmed_at` (with tz): found, `data_type = 'timestamp with time zone'`

### TC-190-007
**Category:** Schema Migration / backward compatibility
**Description:** Code that reads `extraction_count` works between ADD and DROP (old columns still present)
**Preconditions:** ADD phase complete, DROP not yet run
**Steps:**
1. INSERT new fact via extraction script
2. Verify `extraction_count` defaults to 1
3. Verify `vote_count` and `confirmation_count` still readable (NULL for new row)
**Expected:** No errors; extraction_count=1; old columns present but NULL

---

## Section 2: Schema Migration — Issue #139 (expires column)

### TC-139-001
**Category:** Schema / Column Definition
**Description:** `expires` column has correct type and nullability
**Preconditions:** #139 migration applied
**Steps:**
1. Query `information_schema.columns` for `entity_facts.expires`
**Expected:** `data_type = 'timestamp with time zone'`, `is_nullable = 'YES'`, no default value

### TC-139-002
**Category:** New Column Behavior / NULL (standard case)
**Description:** Fact without expiration stores NULL, not rejected
**Preconditions:** Migration applied
**Steps:**
1. INSERT entity_fact with expires=NULL
2. SELECT expires
**Expected:** NULL accepted, row stored cleanly

### TC-139-003
**Category:** New Column Behavior / Future expiration
**Description:** Fact with future expires is not treated as expired
**Preconditions:** Migration applied
**Steps:**
1. INSERT fact with `expires = NOW() + INTERVAL '30 days'`
2. Run maintenance decay check: `SELECT * FROM entity_facts WHERE expires < NOW()`
**Expected:** Row NOT returned by decay query

### TC-139-004
**Category:** New Column Behavior / Past expiration
**Description:** Expired fact identified by maintenance query
**Preconditions:** Migration applied
**Steps:**
1. INSERT fact with `expires = NOW() - INTERVAL '1 day'`
2. Run `SELECT id FROM entity_facts WHERE expires < NOW() AND expires IS NOT NULL`
**Expected:** Row IS returned

### TC-139-005
**Category:** Boundary — expires = NOW() exactly
**Description:** Fact expiring at exactly the current timestamp
**Preconditions:** Migration applied
**Steps:**
1. INSERT fact with `expires = NOW()`
2. Immediately run expiry check
**Expected:** Behavior depends on `<` vs `<=` in maintenance script. **Flag for Coder:** Document whether maintenance uses `<` or `<=` and be consistent.

### TC-139-006
**Category:** Extraction Prompt / expires population
**Description:** Extraction correctly populates `expires` when message contains temporal qualifier
**Preconditions:** Extraction script running against updated schema
**Steps:**
1. Feed message: "I'll be in Austin until Friday"
2. Run extraction
3. Check extracted fact for location/travel key
**Expected:** `expires` set to Friday's date (approximate, within same week), `value` contains "Austin"

### TC-139-007
**Category:** Extraction Prompt / expires not populated for permanent facts
**Description:** Fact with no expiration signal leaves expires NULL
**Preconditions:** Extraction script running
**Steps:**
1. Feed message: "My favorite color is blue"
2. Extract and check
**Expected:** `expires = NULL`

---

## Section 3: Schema Migration — Issue #167 (durability + category)

### TC-167-001
**Category:** Schema / Column Definitions
**Description:** Both new columns added with correct constraints
**Preconditions:** #167 migration ADD phase complete
**Steps:**
1. Query `information_schema.columns` for `durability` and `category`
**Expected:**
- `durability`: character varying(20), NOT NULL, default 'long_term'
- `category`: text, NOT NULL, default 'observation'

### TC-167-002
**Category:** Schema / CHECK constraint
**Description:** durability column rejects invalid values
**Preconditions:** Migration complete
**Steps:**
1. `UPDATE entity_facts SET durability = 'transient' WHERE id = <any_id>;`
**Expected:** `ERROR: new row violates check constraint "chk_durability"` (or similar)

### TC-167-003
**Category:** Schema / CHECK constraint — all valid values
**Description:** All four valid durability values accepted
**Preconditions:** Migration complete
**Steps:**
1. UPDATE rows to each of: 'permanent', 'long_term', 'short_term', 'ephemeral'
**Expected:** All four succeed without error

### TC-167-004
**Category:** Data Migration — permanent (84 rows)
**Description:** All 84 `data_type='permanent'` rows → durability=permanent, category=identity
**Preconditions:** Pre-migration count captured: `SELECT COUNT(*) FROM entity_facts WHERE data_type='permanent';`
**Steps:**
1. Run MIGRATE phase
2. `SELECT COUNT(*) FROM entity_facts WHERE durability='permanent' AND category='identity' AND data_type='permanent';`
**Expected:** Count = 84; all permanent rows correctly mapped

### TC-167-005
**Category:** Migration — Identity Rows
**Description:** Verify all 82 identity-typed rows are migrated with correct durability and category values
**Preconditions:** Pre-migration state: 82 rows with `data_type = 'identity'`
**Steps:**
1. Count pre-migration: `SELECT COUNT(*) FROM entity_facts WHERE data_type = 'identity';` → confirm 82
2. Run migration
3. `SELECT COUNT(*) FROM entity_facts WHERE durability = 'permanent' AND category = 'identity';`
**Expected:** Count in step 3 = 82 + 84 = 166 total (both permanent and identity map to durability=permanent, category=identity)

### TC-167-006
**Category:** Migration — Preference Rows
**Description:** Verify all 4 preference-typed rows are migrated with correct durability and category values
**Preconditions:** Pre-migration state: 4 rows with `data_type = 'preference'`
**Steps:**
1. Count pre-migration: confirm 4
2. Run migration
3. `SELECT COUNT(*) FROM entity_facts WHERE durability = 'long_term' AND category = 'preference';`
**Expected:** Count = 4; all preference rows have `durability = 'long_term'` and `category = 'preference'`

### TC-167-007
**Category:** Migration — Observation Rows
**Description:** Verify all 400 observation-typed rows are migrated to durability='long_term', category='observation'
**Preconditions:** Pre-migration state: 400 rows with `data_type = 'observation'`
**Steps:**
1. Count pre-migration: `SELECT COUNT(*) FROM entity_facts WHERE data_type = 'observation';` → confirm 400
2. Run migration
3. `SELECT COUNT(*) FROM entity_facts WHERE durability = 'long_term' AND category = 'observation';`
4. `SELECT COUNT(*) FROM entity_facts WHERE category = 'observation' AND durability = 'short_term';` → confirm 0
**Expected:** Count in step 3 = 400; count in step 4 = 0; no data loss or corruption in non-migrated columns

### TC-167-008
**Category:** Migration — Total Row Count Integrity
**Description:** Verify total row count is preserved across all data_type groups after migration
**Preconditions:** Pre-migration totals: permanent=84, identity=82, preference=4, observation=400 (total varies with other rows)
**Steps:**
1. Record `SELECT COUNT(*) FROM entity_facts;` pre-migration
2. Run migration
3. Record `SELECT COUNT(*) FROM entity_facts;` post-migration
4. Verify no rows with NULL durability or NULL category exist
**Expected:** Total count unchanged; zero rows with `durability IS NULL` or `category IS NULL`

### TC-167-009
**Category:** Schema Change — data_type Column DROP
**Description:** Verify `data_type` column is removed after DROP phase
**Preconditions:** Migration fully applied including DROP phase
**Steps:**
1. `SELECT column_name FROM information_schema.columns WHERE table_name = 'entity_facts' AND column_name = 'data_type';`
2. `SELECT data_type FROM entity_facts LIMIT 1;`
**Expected:** Step 1 returns zero rows; step 2 raises column does not exist error

### TC-167-010
**Category:** Schema Change — chk_data_type Constraint DROP
**Description:** Verify `chk_data_type` CHECK constraint is removed
**Preconditions:** Migration fully applied including DROP phase
**Steps:**
1. `SELECT constraint_name FROM information_schema.table_constraints WHERE table_name = 'entity_facts' AND constraint_name = 'chk_data_type';`
**Expected:** Zero rows returned

### TC-167-011
**Category:** Category Column — Free-Form Accepts Suggested Values
**Description:** `category` accepts all extraction-prompt-suggested values
**Preconditions:** Migration complete
**Steps:**
1. Insert test rows with each suggested category: observation, preference, identity, mood, decision, routine, state, obligation
**Expected:** All 8 inserts succeed without error

### TC-167-012
**Category:** Category Column — Free-Form Accepts Novel LLM Categories
**Description:** `category` accepts novel values not in the suggested list
**Preconditions:** Migration complete
**Steps:**
1. Insert rows with categories: 'relationship', 'goal', 'health_metric', 'arbitrary_novel_value_xyz'
**Expected:** All 4 inserts succeed; no constraint violation

### TC-167-013
**Category:** Category Column — NOT NULL Constraint Enforced
**Description:** Inserting a row with `category = NULL` is rejected
**Preconditions:** Migration complete
**Steps:**
1. `INSERT INTO entity_facts (..., category) VALUES (..., NULL);`
**Expected:** NOT NULL violation error

---

## Section 4: Issue #204 — entity_fact_sources Table

### TC-204-001
**Category:** Schema — Table Exists with Correct Structure
**Description:** `entity_fact_sources` table created with all required columns and types
**Preconditions:** Migration applied
**Steps:**
1. Query `information_schema.columns` for `entity_fact_sources`
2. Confirm: id SERIAL PK, fact_id INTEGER NOT NULL, source_entity_id INTEGER NOT NULL, source_citation TEXT (nullable), attribution_count INTEGER DEFAULT 1, first_seen TIMESTAMPTZ DEFAULT now(), last_seen TIMESTAMPTZ DEFAULT now()
**Expected:** All 7 columns present with correct types

### TC-204-002
**Category:** Schema — FK Constraint: fact_id → entity_facts(id)
**Description:** fact_id rejects non-existent fact IDs
**Preconditions:** Table exists
**Steps:**
1. Insert row with valid fact_id → success
2. Insert row with fact_id=999999 (non-existent)
**Expected:** Step 1 succeeds; step 2 raises FK violation

### TC-204-003
**Category:** Schema — FK Constraint: source_entity_id → entities(id)
**Description:** source_entity_id rejects non-existent entity IDs
**Preconditions:** Table exists
**Steps:**
1. Insert row with valid source_entity_id → success
2. Insert row with source_entity_id=999999 (non-existent)
**Expected:** Step 1 succeeds; step 2 raises FK violation

### TC-204-004
**Category:** Schema — CASCADE DELETE on fact deletion
**Description:** Deleting an entity_fact cascades to entity_fact_sources
**Preconditions:** Fact with 3 source rows exists
**Steps:**
1. Count sources: `SELECT COUNT(*) FROM entity_fact_sources WHERE fact_id = <id>;` → 3
2. `DELETE FROM entity_facts WHERE id = <id>;`
3. Count sources again
**Expected:** Step 3 returns 0; all 3 source rows deleted

### TC-204-005
**Category:** Schema — source_entity_id NOT NULL enforced
**Description:** Cannot insert source row without a resolved entity
**Preconditions:** Table exists
**Steps:**
1. `INSERT INTO entity_fact_sources (fact_id, source_entity_id) VALUES (<valid>, NULL);`
**Expected:** NOT NULL violation error

### TC-204-006
**Category:** Schema — source_citation nullable (both with and without entity)
**Description:** source_citation can be NULL or populated alongside entity
**Preconditions:** Table exists
**Steps:**
1. Insert: source_entity_id=2, source_citation=NULL → success
2. Insert: source_entity_id=7, source_citation='NY Times, 2026-05-13, p.4' → success
**Expected:** Both succeed; source_citation is optional metadata

### TC-204-007
**Category:** Migration — rows with source_entity_id populated
**Description:** Existing entity_facts.source_entity_id migrates to entity_fact_sources
**Preconditions:** Seed facts with known source_entity_id values
**Steps:**
1. Count facts with non-null source_entity_id pre-migration
2. Run migration
3. Count entity_fact_sources rows
4. Verify each fact_id + source_entity_id pair exists
**Expected:** 1:1 migration; every source_entity_id appears in new table

### TC-204-008
**Category:** Migration — rows with only source text (no entity_id)
**Description:** Existing entity_facts.source (text only, no source_entity_id) must resolve to entity
**Preconditions:** Seed facts with source='I)ruid', source_entity_id=NULL
**Steps:**
1. Run migration
2. Check entity_fact_sources for these facts
3. Verify source resolved to entity (I)ruid → entity_id=2)
**Expected:** Source text resolved to entity; entity_fact_sources row created with correct source_entity_id

### TC-204-009
**Category:** Migration — rows with BOTH source and source_entity_id NULL
**Description:** Edge case where no source data exists at all
**Preconditions:** Seed fact with source=NULL AND source_entity_id=NULL
**Steps:**
1. Count such rows pre-migration
2. Run migration
3. Check how these rows were handled
**Expected:** Strategy documented and applied consistently. Options: assign to system entity (NOVA, id=1), flag for manual review, or create "unknown" source entity. **Flag for Coder:** Decide strategy and document.

### TC-204-010
**Category:** Migration — old columns dropped
**Description:** source and source_entity_id removed from entity_facts after migration
**Preconditions:** DROP phase executed
**Steps:**
1. Query information_schema for both columns
**Expected:** Neither column found on entity_facts

### TC-204-011
**Category:** Reinforcement — UPSERT on existing source
**Description:** When same entity reinforces same fact, attribution_count increments
**Preconditions:** Fact exists with source (entity_id=2, attribution_count=1)
**Steps:**
1. Reinforce same fact from same source entity
2. Check attribution_count
3. Check last_seen updated
**Expected:** attribution_count=2; last_seen updated; first_seen unchanged; no duplicate row

### TC-204-012
**Category:** Multiple sources — independent corroboration
**Description:** A fact can have multiple independent source rows
**Preconditions:** Fact exists
**Steps:**
1. Add source: entity_id=2 (I)ruid)
2. Add source: entity_id=7 (NY Times), citation='2026-05-13, p.4'
3. `SELECT COUNT(*) FROM entity_fact_sources WHERE fact_id = <id>;`
**Expected:** Count = 2; two independent source rows with different entity_ids

---

## Section 5: Source Entity Auto-Creation

_Sections 5-11 to be added in next run_
# Test Cases — SE Workflow Step 3 (Sections 5–11)

**Issues covered:** #204 (source auto-creation), #192 (merge_facts + dedup), #188 (extraction prompt), #167 (decay rates)  
**Author:** Gem (QA Lead)  
**Date:** 2026-05-13  
**Starts at:** TC-205-001  
**Prior runs:** TC-190-001 through TC-204-012 (Sections 1–4)

---

## Notation

- **Preconditions** assume a clean test database unless otherwise stated
- **pgTAP** tests run via `pg_prove` against the test database
- **Python/Shell** tests run against `nova-staging` environment
- All IDs in examples are synthetic test values

---

## Section 5 — Source Entity Auto-Creation (#204)

> The extraction pipeline must resolve ALL sources to entities. If a source entity doesn't exist, auto-create it. For publications, source entity = author (person), NOT the publication. Publication metadata goes into `source_citation`.

### Fixtures

**F-SRC-1:** Database with known person entity
```sql
INSERT INTO entities (id, name, type, status) VALUES (50, 'John Smith', 'person', 'active');
```

**F-SRC-2:** Empty entities table (no existing sources)

**F-SRC-3:** Ambiguous name scenario
```sql
INSERT INTO entities (id, name, type) VALUES (60, 'John Smith', 'person'), (61, 'John Smith', 'organization');
```

**F-SRC-4:** Publication with known author entity (F-SRC-1 present)

**F-SRC-5:** Publication with unknown author (no entity exists)

**F-SRC-6:** Publication with no identifiable author

---

| ID | Category | Description | Preconditions | Steps | Expected Result |
|----|----------|-------------|---------------|-------|-----------------|
| TC-205-001 | Happy path | Known person source — no auto-creation needed | F-SRC-1 | Extract message citing "John Smith" as source | Entity lookup returns id=50; no new entity created; `source_entity_id` set to 50 on the fact |
| TC-205-002 | Auto-creation | Unknown person source triggers auto-creation | F-SRC-2 | Extract message citing "Alice Carter" as source | New entity inserted: `name='Alice Carter'`, `type='person'`, `status='active'`; returned id used as `source_entity_id` |
| TC-205-003 | Publication — author is source | Publication with known author | F-SRC-4 | Extract fact from "Nature, by Jane Doe" | `source_entity_id` = entity id for "Jane Doe" (person); publication title + date stored in `source_citation`; NOT a separate entity for "Nature" |
| TC-205-004 | Publication — author auto-created | Publication with unknown author | F-SRC-5 | Extract fact from "MIT Press, by Dr. Alan Turing, 1950" | New entity created for "Dr. Alan Turing" (person); `source_citation` holds: `{publication: "MIT Press", date: "1950"}`; `source_entity_id` → Alan Turing |
| TC-205-005 | Resolution hierarchy | No author → fall back to publisher | F-SRC-6 | Extract fact from article with no byline, published by "Reuters" | Entity created for "Reuters" with `type='organization'`; `source_entity_id` set to Reuters entity |
| TC-205-006 | Resolution hierarchy | No author, no publisher → fall back to publication title | F-SRC-2 | Source is only "The Atlantic" (title) | Entity created for "The Atlantic" with `type='publication'`; `source_entity_id` set accordingly |
| TC-205-007 | Auto-creation defaults | New entity gets sensible defaults | F-SRC-2 | Any auto-created entity | `status='active'`, `type` matches resolution tier (person/organization/publication), `created_at=NOW()`, no NULL required fields |
| TC-205-008 | Edge case — auto-creation failure | DB constraint violation during auto-create | F-SRC-2, DB trigger that rejects inserts | Trigger blocks entity INSERT | Extraction pipeline does NOT crash; fact is stored with `source_entity_id=NULL`; error logged; pipeline continues |
| TC-205-009 | Edge case — ambiguous entity name | Two entities with same name | F-SRC-3 | Source is "John Smith" (no disambiguating info) | Pipeline selects the `type='person'` record (prefer person over org); if ambiguous person vs person, selects most recently active; logs ambiguity warning |
| TC-205-010 | Edge case — ambiguous, no winner | Multiple active persons with identical name | Two persons: same name, same type, same status | Extract with source "John Smith" | One of the two is selected deterministically (e.g., lowest id); ambiguity event recorded in logs; `source_entity_id` is NOT NULL |
| TC-205-011 | Publication — source_citation structure | All publication fields stored correctly | F-SRC-4 | Extract from "Wired, Jane Doe, 2024-03-15, p.42, https://wired.com/article-123" | `source_citation` JSONB contains: `{author: "Jane Doe", publication: "Wired", date: "2024-03-15", page: "42", url: "https://wired.com/article-123"}`; no extra fields on `entity_facts` row itself |
| TC-205-012 | Publication — partial metadata | Article with only title and URL | F-SRC-2, source "The Guardian, https://guardian.com/x" | Extract citation | `source_citation` has only `publication` and `url` keys present; no NULL-valued keys inserted |
| TC-205-013 | No source at all | Extraction from direct user statement | F-SRC-1, user message with no attributed source | User says "I prefer tea" | `source_entity_id` = user's own entity; `source_citation` = NULL or empty; no auto-creation triggered |
| TC-205-014 | Idempotency | Same source referenced twice in one extraction batch | F-SRC-2 | Two facts both citing "Alice Carter" as source | Auto-create fires only once; second fact reuses the just-created entity; exactly 1 new entity row |

---

## Section 6 — merge_facts() Function (#192)

> `merge_facts(survivor_id INTEGER, absorbed_id INTEGER) RETURNS entity_facts`  
> Sums `extraction_count`, takes MAX of `last_confirmed_at` and `confidence`, moves `entity_fact_sources` rows, deletes absorbed, returns merged survivor.

### Fixtures

**F-MRG-1:** Two mergeable entity_facts rows
```sql
INSERT INTO entity_facts (id, entity_id, key, value, extraction_count, last_confirmed_at, confidence)
VALUES (100, 1, 'hobby', 'hiking', 3, '2024-01-01 10:00:00+00', 0.8),
       (101, 1, 'hobby', 'hiking', 5, '2024-06-01 12:00:00+00', 0.9);
```

**F-MRG-2:** entity_fact_sources for both facts
```sql
INSERT INTO entity_fact_sources (entity_fact_id, entity_id, attribution_count, first_seen, last_seen)
VALUES (100, 10, 2, '2024-01-01', '2024-03-01'),
       (101, 10, 3, '2024-04-01', '2024-06-01'),   -- same source entity as id=100
       (101, 20, 1, '2024-05-15', '2024-06-01');    -- source only on absorbed
```

**F-MRG-3:** Absorbed fact with unique source (no overlap with survivor)
```sql
INSERT INTO entity_fact_sources (entity_fact_id, entity_id, attribution_count, first_seen, last_seen)
VALUES (101, 99, 4, '2024-02-01', '2024-05-01');
```

---

| ID | Category | Description | Preconditions | Steps | Expected Result |
|----|----------|-------------|---------------|-------|-----------------|
| TC-206-001 | Happy path | Basic merge — extraction_count summed | F-MRG-1 | `SELECT merge_facts(100, 101)` | Returned row: `extraction_count = 8` (3 + 5) |
| TC-206-002 | Happy path | MAX(last_confirmed_at) taken | F-MRG-1 | `SELECT merge_facts(100, 101)` | `last_confirmed_at = '2024-06-01 12:00:00+00'` (max of the two) |
| TC-206-003 | Happy path | MAX(confidence) taken | F-MRG-1 | `SELECT merge_facts(100, 101)` | `confidence = 0.9` (max of the two) |
| TC-206-004 | Happy path | Absorbed row deleted | F-MRG-1 | `SELECT merge_facts(100, 101)` | `SELECT COUNT(*) FROM entity_facts WHERE id = 101` → 0 |
| TC-206-005 | Happy path | Survivor row preserved | F-MRG-1 | `SELECT merge_facts(100, 101)` | `SELECT COUNT(*) FROM entity_facts WHERE id = 100` → 1; id is unchanged |
| TC-206-006 | Source merging — shared source | Both facts have same source entity_id | F-MRG-1, F-MRG-2 (shared source entity_id=10) | `SELECT merge_facts(100, 101)` | Single entity_fact_sources row for source entity_id=10 on survivor: `attribution_count = 5` (2+3), `first_seen = '2024-01-01'` (earliest), `last_seen = '2024-06-01'` (latest) |
| TC-206-007 | Source merging — unique absorbed source | Absorbed has source survivor doesn't | F-MRG-1, F-MRG-2 + F-MRG-3 | `SELECT merge_facts(100, 101)` | entity_fact_sources row for entity_id=20 moved to survivor (id=100); row for entity_id=99 moved to survivor; absorbed's original rows deleted |
| TC-206-008 | Return value | Function returns merged survivor record | F-MRG-1 | `SELECT * FROM merge_facts(100, 101)` | Returns complete entity_facts row for id=100 with all merged values |
| TC-206-009 | Edge case — nonexistent survivor | survivor_id doesn't exist | Empty entity_facts | `SELECT merge_facts(9999, 101)` | Raises error: "survivor fact 9999 does not exist" |
| TC-206-010 | Edge case — nonexistent absorbed | absorbed_id doesn't exist | F-MRG-1 (only id=100) | `SELECT merge_facts(100, 9999)` | Raises error: "absorbed fact 9999 does not exist" |
| TC-206-011 | Edge case — self-merge | survivor_id == absorbed_id | F-MRG-1 | `SELECT merge_facts(100, 100)` | Raises error: "cannot merge a fact with itself"; no data modification |
| TC-206-012 | Edge case — idempotency / absorbed already deleted | Re-calling after absorbed is gone | F-MRG-1, run merge once, then call again | `SELECT merge_facts(100, 101)` called twice | Second call raises "absorbed fact 101 does not exist"; survivor data unchanged from first merge |
| TC-206-013 | Transaction integrity | If any step fails mid-merge, all changes rolled back | F-MRG-1, F-MRG-2; simulate FK violation during source move | Introduce constraint that blocks source row update | Both absorbed row AND source rows remain in original state; no partial merge |
| TC-206-014 | Cross-entity merge attempt | survivor and absorbed belong to different entity_ids | Two facts: entity_id=1 and entity_id=2 | `SELECT merge_facts(survivor_on_entity_1, absorbed_on_entity_2)` | Raises error: "cannot merge facts from different entities"; no data modification |

---

## Section 7 — Confidence-Tiered Dedup in Maintenance (#192)

> High confidence match → auto-merge via `merge_facts()`. Medium → daily report. Low → skip. Entity dedup is OUT OF SCOPE.

### Fixtures

**F-DDP-1:** Two facts with exact key + high text similarity + same entity_id
```sql
INSERT INTO entity_facts (id, entity_id, key, value, confidence)
VALUES (200, 1, 'hobby', 'hiking in mountains', 0.9),
       (201, 1, 'hobby', 'hiking in the mountains', 0.85);
-- pg_trgm similarity('hiking in mountains', 'hiking in the mountains') ≈ 0.84
```

**F-DDP-2:** Two facts with same key but moderate similarity
```sql
INSERT INTO entity_facts (id, entity_id, key, value, confidence)
VALUES (202, 1, 'food_preference', 'loves Italian food', 0.8),
       (203, 1, 'food_preference', 'really enjoys pasta', 0.75);
-- similarity ≈ 0.35 (moderate)
```

**F-DDP-3:** Two facts with same key, low similarity
```sql
INSERT INTO entity_facts (id, entity_id, key, value)
VALUES (204, 1, 'location', 'Austin, TX'),
       (205, 1, 'location', 'Pacific Northwest');
-- similarity ≈ 0.10 (low)
```

**F-DDP-4:** Two facts from different entities, exact key + high similarity
```sql
INSERT INTO entity_facts (id, entity_id, key, value)
VALUES (206, 1, 'job', 'software engineer'),
       (207, 2, 'job', 'software engineer');
```

---

| ID | Category | Description | Preconditions | Steps | Expected Result |
|----|----------|-------------|---------------|-------|-----------------|
| TC-207-001 | High confidence | Exact key + high similarity + same entity → auto-merge | F-DDP-1 | Run maintenance dedup pass | `merge_facts(200, 201)` called automatically; absorbed row (201) deleted; no report entry generated |
| TC-207-002 | High confidence threshold | Similarity exactly at high threshold → auto-merge | Facts with trgm similarity = 0.80 (configured threshold) | Run maintenance dedup | Auto-merge fires; not queued for report |
| TC-207-003 | High confidence threshold — just below | Similarity just below high threshold | Facts with trgm similarity = 0.79 | Run maintenance dedup | NOT auto-merged; queued in daily report as medium confidence |
| TC-207-004 | Medium confidence | Similar key OR moderate similarity → report | F-DDP-2 | Run maintenance dedup | No merge; report entry created: fact IDs (202, 203), keys, values, similarity score, recommended action = "manual review" |
| TC-207-005 | Medium confidence report format | Report entry contains all required fields | F-DDP-2, after dedup run | Read daily report output | Each entry has: `fact_id_1`, `fact_id_2`, `key`, `value_1`, `value_2`, `similarity_score`, `recommended_action` |
| TC-207-006 | Low confidence | Very low similarity → skip entirely | F-DDP-3 | Run maintenance dedup | No merge; no report entry; facts untouched |
| TC-207-007 | Cross-entity dedup — out of scope | Different entity_id → not considered for merge | F-DDP-4 | Run maintenance dedup | Facts 206 and 207 NOT evaluated for merge (entity dedup is out of scope per #203); no auto-merge, no report entry for them |
| TC-207-008 | Auto-merge selects correct survivor | Higher confidence fact is survivor | F-DDP-1 (id=200 has confidence=0.9) | Auto-merge fires | Survivor = id=200 (higher confidence); absorbed = id=201 |
| TC-207-009 | Auto-merge tie-breaking | Equal confidence → consistent survivor selection | Two facts: same entity, same key, same confidence, high similarity | Run maintenance | Lower id becomes survivor (deterministic tiebreak); no error |
| TC-207-010 | Similarity threshold — high definition | Document what "high" means | N/A — configuration check | Inspect dedup config or code | High threshold ≥ 0.80 (pg_trgm similarity); Medium: 0.50–0.79; Low: < 0.50 |
| TC-207-011 | Report not generated when nothing to report | No near-duplicates exist | Clean database with unique facts | Run maintenance | No daily report file created (or report is empty/has zero dedup entries) |
| TC-207-012 | Multiple pairs in one run | Three pairs: 1 high, 1 medium, 1 low | F-DDP-1 + F-DDP-2 + F-DDP-3 | Run single maintenance pass | High pair auto-merged; medium pair in report; low pair skipped; exactly 1 report entry |

---

## Section 8 — Extraction Prompt Changes (#188, #167, #204)

> SENDER_ID labeled with platform type. Discord snowflake NOT extracted as phone. Category list in prompt. Durability classification. Publication source attribution. `expires` temporal boundary.

### Fixtures

**F-PRMPT-1:** Discord context
```bash
export SENDER_ID="330189773371080716"
export SENDER_PROVIDER="discord"
export SENDER_NAME="I)ruid"
```

**F-PRMPT-2:** Signal context
```bash
export SENDER_ID="+15125551234"
export SENDER_PROVIDER="signal"
export SENDER_NAME="Alice"
```

**F-PRMPT-3:** SMS/unknown context
```bash
export SENDER_ID="+15125551234"
export SENDER_PROVIDER="sms"
```

**F-PRMPT-4:** Publication message
```
User: According to Sarah Chen in the March 2024 issue of Wired, neural interfaces will be mainstream by 2030.
```

**F-PRMPT-5:** Expiring fact message
```
User: I'll be in Austin through next Friday.
```

---

| ID | Category | Description | Preconditions | Steps | Expected Result |
|----|----------|-------------|---------------|-------|-----------------|
| TC-208-001 | SENDER_ID platform label | Discord ID labeled in prompt | F-PRMPT-1 | Build extraction prompt | Prompt contains "Discord user ID: 330189773371080716" (not bare ID) |
| TC-208-002 | SENDER_ID platform label | Signal phone labeled in prompt | F-PRMPT-2 | Build extraction prompt | Prompt contains "Signal phone: +15125551234" |
| TC-208-003 | SENDER_ID platform label | Unknown/SMS provider labeled | F-PRMPT-3 | Build extraction prompt | Prompt contains platform hint from `SENDER_PROVIDER` value; bare number still not passed unlabeled |
| TC-208-004 | SENDER_PROVIDER env var | Script reads SENDER_PROVIDER | F-PRMPT-1 with `SENDER_PROVIDER=discord` | Inspect prompt construction | `SENDER_PROVIDER` is read and used to compose the label string; env var is documented in script header |
| TC-208-005 | Discord snowflake not as phone | Discord ID not extracted as phone number | F-PRMPT-1, input "my Discord is 330189773371080716" | Run extraction | Output JSON does NOT contain a `phone` or `phone_number` fact with value `330189773371080716`; if extracted at all, key is `discord_id` |
| TC-208-006 | Category list in prompt | Prompt contains canonical category list | Any extraction run | Inspect prompt text | Prompt lists: `observation, preference, identity, mood, decision, routine, state, obligation` |
| TC-208-007 | Category list — LLM can extend | Prompt allows LLM to use non-listed categories | Any extraction run | Inspect prompt text | Prompt indicates categories are examples/defaults, not an exclusive list; phrasing like "or other appropriate categories" |
| TC-208-008 | Durability guidance | Prompt includes durability classification | Any extraction run | Inspect prompt text | Prompt explains `permanent` / `long_term` / `short_term` / `ephemeral` with brief guidance on which facts get which |
| TC-208-009 | Publication source attribution | Author > publisher > title hierarchy | F-PRMPT-4 | Run extraction on publication message | Extracted fact has `source_person = "Sarah Chen"` (author, not "Wired"); `source_citation` populated with publication metadata |
| TC-208-010 | Source citation metadata | Prompt instructs LLM on citation fields | F-PRMPT-4 | Inspect prompt text | Prompt names expected citation fields: author, publication, date, page (optional), url (optional) |
| TC-208-011 | Expires temporal boundary | Temporary location fact gets expires | F-PRMPT-5 | Run extraction | Extracted fact includes `expires` field; value is a timestamp approximating "next Friday" relative to extraction time |
| TC-208-012 | Expires only for temporal facts | Permanent fact does not get expires | Input "My name is Dustin" | Run extraction | `name` fact does NOT have `expires` field (or `expires = NULL`) |
| TC-208-013 | Expires recognized in prompt | Prompt instructs LLM to recognize temporal boundaries | Any extraction run | Inspect prompt text | Prompt says to set `expires` when the statement implies a temporal boundary (e.g., "until", "through", "this week", "temporarily") |

---

## Section 9 — Maintenance Decay Rates (#167)

> `DECAY_RATES` must use durability keys. `expires < NOW()` → aggressive/immediate decay. `durability='permanent'` skips decay. Custom `decay_rate` column still overrides.

### Fixtures

**F-DKY-1:** Facts with each durability value
```sql
INSERT INTO entity_facts (id, entity_id, key, value, durability, confidence, last_confirmed_at, decay_rate)
VALUES
  (300, 1, 'name',      'Dustin',         'permanent',  1.0, NOW() - INTERVAL '30 days', NULL),
  (301, 1, 'career',    'security expert','long_term',  0.9, NOW() - INTERVAL '30 days', NULL),
  (302, 1, 'mood',      'excited',        'short_term', 0.8, NOW() - INTERVAL '7 days',  NULL),
  (303, 1, 'location',  'Austin',         'ephemeral',  0.9, NOW() - INTERVAL '2 days',  NULL),
  (304, 1, 'custom',    'custom fact',    'short_term', 0.7, NOW() - INTERVAL '7 days',  0.5);
```

**F-DKY-2:** Expired fact
```sql
INSERT INTO entity_facts (id, entity_id, key, value, durability, confidence, expires, last_confirmed_at)
VALUES (305, 1, 'travel', 'in Austin', 'ephemeral', 0.9, NOW() - INTERVAL '1 day', NOW() - INTERVAL '5 days');
```

**F-DKY-3:** Old DECAY_RATES using data_type keys (contrast/regression fixture)
```python
# Wrong pattern (should NOT be in code after fix):
DECAY_RATES = {'permanent': 0, 'identity': 0.001, 'preference': 0.005, 'temporal': 0.05, 'observation': 0.1}
```

---

| ID | Category | Description | Preconditions | Steps | Expected Result |
|----|----------|-------------|---------------|-------|-----------------|
| TC-209-001 | DECAY_RATES keys | Dict uses durability keys, not data_type keys | Code inspection | Inspect `DECAY_RATES` dict in `memory-maintenance.py` | Keys are exactly: `permanent`, `long_term`, `short_term`, `ephemeral` (not `identity`, `preference`, `temporal`, `observation`) |
| TC-209-002 | Decay rates — values | Rates match documented decay schedule | Code inspection | Inspect values | `permanent: 0` or equivalent no-decay; `long_term: ≤0.005`; `short_term: ~0.02`; `ephemeral: ~0.1` |
| TC-209-003 | permanent skips decay | Permanent fact not decayed | F-DKY-1 (id=300) | Run decay pass | `confidence` for id=300 unchanged after 30 days; NOT archived |
| TC-209-004 | long_term decays slowly | Long-term fact decays at slow rate | F-DKY-1 (id=301, 30 days old) | Run decay pass | Confidence reduced by ≤5% for 30 days (consistent with ≤0.005/day); still above archive threshold |
| TC-209-005 | short_term decays moderately | Short-term fact decays at moderate rate | F-DKY-1 (id=302, 7 days old) | Run decay pass | Confidence reduced ~13% for 7 days at 0.02/day; still positive |
| TC-209-006 | ephemeral decays aggressively | Ephemeral fact decays fast | F-DKY-1 (id=303, 2 days old) | Run decay pass | Confidence drops noticeably (≥18% for 2 days at 0.1/day); may reach archive threshold quickly |
| TC-209-007 | custom decay_rate overrides | Custom rate takes precedence over durability default | F-DKY-1 (id=304, decay_rate=0.5) | Run decay pass | id=304 decays at rate 0.5/day, NOT at the short_term default of 0.02; confidence ≈ 0.7 × e^(-0.5×7) ≈ 0.02 |
| TC-209-008 | expires past NOW() | Expired fact gets aggressive/immediate decay | F-DKY-2 (id=305, expires 1 day ago) | Run decay pass | Fact either: (a) confidence set to 0 and archived, OR (b) decay rate set to maximum and archived in same run; NOT left at high confidence |
| TC-209-009 | expires in future | Non-expired temporal fact decays normally | Fact with `expires = NOW() + INTERVAL '3 days'` | Run decay pass | Fact uses normal durability-based rate; no accelerated decay |
| TC-209-010 | WHERE clause correction | Decay query uses `durability != 'permanent'` not `data_type != 'permanent'` | Code inspection | Inspect WHERE clause in decay query in `memory-maintenance.py` | Query reads `WHERE durability != 'permanent'` (or `durability <> 'permanent'`) |
| TC-209-011 | Archive threshold still applies | Ephemeral fact reaching threshold is archived | F-DKY-1 (id=303), extend to 30+ days | Run decay multiple times or simulate days elapsed | When confidence drops below `ARCHIVE_THRESHOLD` (0.1), fact moved to `entity_facts_archive` |
| TC-209-012 | Archive reason set correctly | Archived facts have reason populated | F-DKY-1 after decay | Inspect `entity_facts_archive` row | `archive_reason = 'decay'`; `archived_by` is set to maintenance script identifier |
| TC-209-013 | Decay with NULL durability | Fact with NULL durability gets fallback rate | Insert fact with `durability = NULL` | Run decay | Falls back to default rate (e.g., `observation` rate or 0.01); does NOT crash; does NOT get permanent treatment |

---

## Section 10 — Codebase Audit Verification

> After all changes, no orphaned references to dropped columns on `entity_facts`. Specific indexes dropped/replaced.

### Files to audit
- `memory/scripts/extract-memories.sh`
- `memory/scripts/memory-maintenance.py`
- `memory/scripts/dedup_helper.py`
- (not yet found) `check-fact-conflict.py`
- `memory/scripts/get-visible-facts.sh`
- `memory/skills/semantic-memory/scripts/proactive-recall.py`
- `memory/schema.sql` and `memory/schema/schema.sql`
- `memory/tests/fixtures/test-data.sql`

### Dropped columns on entity_facts (NOT on other tables)
- `vote_count`
- `confirmation_count`
- `last_confirmed` (without `_at` suffix)
- `data_type`
- `source` (the column, not the word)
- `source_entity_id`

---

| ID | Category | Description | Preconditions | Steps | Expected Result |
|----|----------|-------------|---------------|-------|-----------------|
| TC-210-001 | vote_count — extract script | No reference to vote_count on entity_facts | Post-migration schema | `grep -n "vote_count" memory/scripts/extract-memories.sh` | No output (0 matches) |
| TC-210-002 | vote_count — maintenance | No reference in maintenance script | Post-migration | `grep -n "vote_count" memory/scripts/memory-maintenance.py` | No output; note: `agent_domains.vote_count` and `vocabulary.vote_count` are ALLOWED (different tables) |
| TC-210-003 | vote_count — schema | idx_entity_facts_vote_count index dropped | Post-migration schema | `grep "idx_entity_facts_vote_count" memory/schema.sql` | No CREATE INDEX statement for this index found |
| TC-210-004 | vote_count — schema 2 | vote_count column not in entity_facts CREATE TABLE | Post-migration schema | Inspect `CREATE TABLE entity_facts` block | `vote_count` not listed as a column; still present on `agent_domains` and `vocabulary` (those are correct) |
| TC-210-005 | confirmation_count — all files | No orphaned confirmation_count references | Post-migration | `grep -rn "confirmation_count" memory/scripts/` | No matches in any script file |
| TC-210-006 | confirmation_count — schema | Not in entity_facts table definition | Post-migration schema | Inspect `CREATE TABLE entity_facts` | `confirmation_count` column absent |
| TC-210-007 | last_confirmed (no _at) | No bare last_confirmed column reference | Post-migration | `grep -rn "last_confirmed[^_]" memory/scripts/ memory/schema.sql` | No matches (post-fix only `last_confirmed_at` acceptable) |
| TC-210-008 | data_type — entity_facts | data_type removed from entity_facts | Post-migration schema | `grep -n "data_type" memory/schema.sql` | `data_type` NOT found inside `CREATE TABLE entity_facts` block; references in archive table are acceptable |
| TC-210-009 | data_type — scripts | No reference in scripts post-migration | Post-migration | `grep -rn "data_type" memory/scripts/memory-maintenance.py` | After fix: no references; if during transition, only migration-phase code paths acceptable |
| TC-210-010 | data_type — idx replaced | idx_entity_facts_data_type replaced | Post-migration schema | `grep "idx_entity_facts_data_type\|idx_entity_facts_durability\|idx_entity_facts_category" memory/schema.sql` | `idx_entity_facts_data_type` absent; `idx_entity_facts_durability` and `idx_entity_facts_category` both present |
| TC-210-011 | source column — entity_facts | source column removed from entity_facts | Post-migration | Inspect `CREATE TABLE entity_facts` in schema.sql | No `source` column (the plain column); `source_citation` JSONB column may exist; foreign key `source_entity_id` is the correct replacement |
| TC-210-012 | source column — scripts | No bare `source` column in SQL queries in scripts | Post-migration | `grep -n "\"source\"\|'source'\|\.source\b" memory/scripts/extract-memories.sh memory/scripts/memory-maintenance.py memory/scripts/dedup_helper.py` | No matches targeting the dropped column |
| TC-210-013 | source_entity_id — entity_facts | source_entity_id removed from entity_facts | Post-migration | Inspect `CREATE TABLE entity_facts` | `source_entity_id` NOT in entity_facts column list; note: it correctly remains on `agent_domains` table |
| TC-210-014 | source_entity_id — scripts | Scripts don't reference entity_facts.source_entity_id | Post-migration | `grep -rn "source_entity_id" memory/scripts/` | No matches in script files (if entity resolution is now via `entity_fact_sources` table) |
| TC-210-015 | test-data.sql clean | Test fixture doesn't insert dropped columns | Post-migration | Inspect `INSERT INTO entity_facts` in test-data.sql | INSERT column list does not include `vote_count`, `confirmation_count`, `last_confirmed`, `data_type`, `source`, `source_entity_id` |
| TC-210-016 | get-visible-facts.sh clean | Shell script has no orphaned column refs | Post-migration | `grep -n "vote_count\|confirmation_count\|data_type\|\.source\b\|source_entity_id" memory/scripts/get-visible-facts.sh` | No matches for dropped entity_facts columns |
| TC-210-017 | proactive-recall.py clean | Recall script has no orphaned column refs | Post-migration | `grep -n "vote_count\|confirmation_count\|data_type\|source_entity_id" memory/skills/semantic-memory/scripts/proactive-recall.py memory/scripts/proactive-recall.py` | No matches |
| TC-210-018 | False positive check | "source" in comments/other contexts is acceptable | Post-migration | Review grep results for false positives | Occurrences of "source" in comments, docs, or other table names are NOT flagged; only column references in SQL queries targeting entity_facts matter |

---

## Section 11 — Backward Compatibility & Integration

> System must stay functional during migration window (ADD phase + DROP phase). No downtime. Row count preserved.

### Fixtures

**F-BC-1:** Pre-migration schema state (old columns present)

**F-BC-2:** Post-ADD migration (both old and new columns present)

**F-BC-3:** Post-DROP migration (only new columns present)

**F-BC-4:** Known entity_facts row count before migration
```sql
SELECT COUNT(*) FROM entity_facts;  -- record this number
```

---

| ID | Category | Description | Preconditions | Steps | Expected Result |
|----|----------|-------------|---------------|-------|-----------------|
| TC-211-001 | ADD phase — extraction works | Extraction script functions with old + new columns | F-BC-2 (both present) | Run extract-memories.sh with a test message | Extraction completes without error; new fact inserted with new column values populated |
| TC-211-002 | ADD phase — maintenance works | Maintenance script functions with old + new columns | F-BC-2 | Run memory-maintenance.py | Script completes without column reference errors; decay applied |
| TC-211-003 | DROP phase — extraction works | Extraction works after old columns removed | F-BC-3 (new only) | Run extract-memories.sh | Extraction succeeds; no references to dropped columns cause errors |
| TC-211-004 | DROP phase — maintenance works | Maintenance works after old columns removed | F-BC-3 | Run memory-maintenance.py | Script completes; uses durability-based decay rates |
| TC-211-005 | Row count preserved | No facts lost during full migration | F-BC-4 (pre-count), run ADD migration, run DROP migration | `SELECT COUNT(*) FROM entity_facts` after DROP migration | Count matches pre-migration count; no accidental deletions |
| TC-211-006 | Row count — archive excluded | Archived facts during migration window acceptable | F-BC-4 | Compare `entity_facts` + `entity_facts_archive` counts | Total across both tables ≥ pre-migration count; any difference explained by intentional decay/archival during migration window |
| TC-211-007 | No production downtime — ADD | ADD migration is non-breaking | F-BC-1 | Apply ADD migration against running system | Existing queries continue to work; new columns are nullable or have defaults; no lock contention required |
| TC-211-008 | No production downtime — DROP | DROP migration does not break before code deployed | F-BC-2, old code still running | Apply DROP migration while old code active | Old code should have been deployed already; test confirms migration is deployed AFTER code update |
| TC-211-009 | Migration rollback | ADD migration can be rolled back | F-BC-2 | Run rollback/down migration | Old schema restored; existing data in old columns preserved; new columns removed |
| TC-211-010 | Extraction idempotency across phases | Same message extracted in ADD and DROP phases | F-BC-2 and F-BC-3 | Run identical extraction in both phases | Same semantic fact produced (same entity_id, key, value); confidence/durability values consistent |
| TC-211-011 | dedup_helper.py — ADD phase | dedup helper works with both column sets | F-BC-2 | Run dedup helper on test database | No column-not-found errors; deduplication produces correct results |
| TC-211-012 | dedup_helper.py — DROP phase | dedup helper works with new schema only | F-BC-3 | Run dedup helper | Works correctly; uses `extraction_count` and `last_confirmed_at` not `confirmation_count` / `last_confirmed` |
| TC-211-013 | entity_fact_sources table exists | New attribution table created in migration | Post-ADD migration | `\d entity_fact_sources` in psql | Table exists with columns: `id`, `entity_fact_id` (FK), `entity_id` (FK), `attribution_count`, `first_seen`, `last_seen` |
| TC-211-014 | source_citation column exists | JSONB citation column added to entity_facts | Post-ADD migration | `\d entity_facts` in psql | `source_citation JSONB` column present with no NOT NULL constraint |
| TC-211-015 | durability column exists | durability column added with correct type/constraint | Post-ADD migration | `\d entity_facts` | `durability VARCHAR` or equivalent; CHECK constraint accepts `permanent`, `long_term`, `short_term`, `ephemeral` |
| TC-211-016 | category column exists | category column added | Post-ADD migration | `\d entity_facts` | `category VARCHAR` column present; accepts values from the canonical list plus extensible others |
| TC-211-017 | extraction_count column exists | extraction_count replaces confirmation_count | Post-ADD migration | `\d entity_facts` | `extraction_count INTEGER DEFAULT 1` present; `confirmation_count` absent post-DROP |
| TC-211-018 | Full round-trip | End-to-end: extract → dedup → maintenance → recall | F-BC-3 (post-migration) | Run full pipeline: extract new message, run maintenance, run proactive recall | All phases complete without errors; extracted fact survives and is recallable |

---

## Summary

| Section | Issue(s) | Test Count | ID Range |
|---------|----------|------------|----------|
| 5 — Source Entity Auto-Creation | #204 | 14 | TC-205-001 – TC-205-014 |
| 6 — merge_facts() | #192 | 14 | TC-206-001 – TC-206-014 |
| 7 — Confidence-Tiered Dedup | #192 | 12 | TC-207-001 – TC-207-012 |
| 8 — Extraction Prompt Changes | #188, #167, #204 | 13 | TC-208-001 – TC-208-013 |
| 9 — Maintenance Decay Rates | #167 | 13 | TC-209-001 – TC-209-013 |
| 10 — Codebase Audit | All | 18 | TC-210-001 – TC-210-018 |
| 11 — Backward Compatibility | All | 18 | TC-211-001 – TC-211-018 |
| **Total (Sections 5–11)** | | **102** | |

**Grand total across all three runs:** TC-190-001 → TC-211-018

---

## Quality Gates (Step 3 Exit Criteria)

1. All TC-21x integration tests pass on staging
2. `grep` audit (TC-210-xxx) returns zero orphaned column references  
3. `entity_facts` row count unchanged post-migration (TC-211-005)
4. `merge_facts()` handles all 4 edge cases without data corruption (TC-206-009 – TC-206-014)
5. `DECAY_RATES` keys confirmed as durability values, not data_type values (TC-209-001)
6. No Discord snowflake extracted as phone number (TC-208-005)

---

## Corrections Applied (Step 4 Review)

### TC-204-009 (CORRECTED) — NULL/NULL Source Attribution
**Category:** Migration — source attribution for orphaned rows
**Description:** Rows where BOTH source AND source_entity_id are NULL → attribute to NOVA (entity_id=1)
**Preconditions:** Rows seeded with source=NULL AND source_entity_id=NULL; NOVA entity exists (id=1)
**Steps:**
1. Run migration
2. Check entity_fact_sources for these fact IDs
**Expected:** All orphaned facts receive source_entity_id=1 (NOVA) in entity_fact_sources. source_citation set to 'system: attributed to NOVA on migration' or NULL. Zero rows skipped. Zero rows with source_entity_id IS NULL.

### TC-205-008 (CORRECTED) — Auto-Creation Failure: Skip and Log
**Category:** Pipeline — entity auto-creation failure handling
**Description:** If entity auto-creation fails, skip the fact and log error (do NOT violate NOT NULL constraint)
**Preconditions:** Auto-creation mocked to fail; entity_fact_sources.source_entity_id is NOT NULL
**Steps:**
1. Pipeline processes a fact whose source entity cannot be auto-created
2. Check entity_facts and entity_fact_sources counts
3. Check error log
**Expected:** Fact is skipped — no insert into entity_facts or entity_fact_sources. Error logged with fact identifier, source name, failure reason. Pipeline continues processing remaining facts. No NOT NULL constraint violation.

### TC-205-011 (CORRECTED) — source_citation is TEXT not JSONB
**Category:** Publication — source_citation structure
**Description:** source_citation stored as free-form TEXT, not structured JSONB
**Preconditions:** Table exists; fact with publication source
**Steps:**
1. Extract from "Wired, Jane Doe, 2024-03-15, p.42, https://wired.com/article-123"
2. Check source_citation value
**Expected:** source_citation stored as plain TEXT string: "Wired, Jane Doe, 2024-03-15, p.42, https://wired.com/article-123". No JSONB parsing. No structured keys.

### TC-209-013 (REPLACED) — Default durability Applied When Not Explicitly Set
**Category:** entity_facts — column default behavior
**Description:** When durability is omitted from INSERT, it defaults to 'long_term'
**Preconditions:** entity_facts.durability is NOT NULL DEFAULT 'long_term'
**Steps:**
1. INSERT into entity_facts with all required fields EXCEPT durability
2. SELECT durability for the new row
**Expected:** durability = 'long_term'; no NULL; no error. Replaces prior test of NULL durability which is impossible.

### TC-211-013 (CORRECTED) — Column Names on entity_fact_sources
**Category:** entity_fact_sources — schema verification
**Description:** Verify correct column names: fact_id (not entity_fact_id), source_entity_id (not entity_id)
**Preconditions:** entity_fact_sources table exists
**Steps:**
1. INSERT using correct column names: fact_id, source_entity_id, source_citation
2. SELECT and verify
**Expected:** Row inserted successfully with correct FK relationships.

### TC-211-014 (CORRECTED) — source_citation is TEXT on entity_fact_sources
**Category:** entity_fact_sources — source_citation storage
**Description:** source_citation is TEXT on entity_fact_sources table, NOT JSONB on entity_facts
**Preconditions:** entity_fact_sources table exists
**Steps:**
1. INSERT with source_citation = 'Wired, Jane Doe, 2024-03-15, p.42'
2. SELECT source_citation
3. Confirm entity_facts does NOT have a source_citation column
**Expected:** source_citation stored as free-form TEXT. entity_facts has no source_citation column.

### TC-210-019 (NEW) — get-visible-facts.sh Visibility Filter Migration
**Category:** Codebase Audit — functional regression
**Description:** Visibility filter must JOIN entity_fact_sources instead of querying entity_facts.source_entity_id
**Preconditions:** Post-migration schema (source_entity_id dropped from entity_facts)
**Steps:**
1. Seed: fact owned by entity_id=2, with source in entity_fact_sources (source_entity_id=2)
2. Seed: fact owned by entity_id=3, with source NOT in participant list
3. Run `get-visible-facts.sh "2"` 
4. Verify fact 1 is returned (source is a participant)
5. Verify fact 2 is NOT returned (source is not a participant)
6. Inspect script: confirm JOIN to entity_fact_sources, no reference to entity_facts.source_entity_id
**Expected:** Visibility filter correctly uses `JOIN entity_fact_sources efs ON efs.fact_id = ef.id WHERE efs.source_entity_id IN ($PARTICIPANT_IDS)`. No orphaned reference to dropped column. This is a security-critical test — regression here means facts visible to wrong participants.
