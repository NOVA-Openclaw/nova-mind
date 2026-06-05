# Test Cases: Ghost Entity Prevention & Entity Dedup (Issues #230, #267)

**Issues:** [#230 - Ghost entity filtering via structural heuristics + smarter resolver matching](https://github.com/NOVA-Openclaw/nova-memory/issues/230) | [#267 - Add alternate_spellings column to entities table](https://github.com/NOVA-Openclaw/nova-memory/issues/267)
**Date:** 2026-06-02
**Author:** Gem (QA Lead)

---

## Context

The `extract_memories.py` pipeline suffers from four root causes producing ghost entities and duplicates:

1. **Eager entity creation** — LLM-extracted names inserted into `entities` without checking if they already exist
2. **Weak matching** — resolver uses exact-match only, missing alternate spellings, case variations, nicknames
3. **Hardcoded `person` type** — `_store_fact()` defaults all unknown entities to `type='person'`
4. **No structural heuristics** — no validation that an extracted "entity" is actually a real entity vs. a phrase fragment, technical identifier, or role label

As of 2026-05-16, the database contains **48+ ghost entities** (e.g., `sender`, `recipient`, `nova_staging_memory`, `Unknown user: 330189773371080716`) with **130+ junk facts**.

**Issue #267** adds an `alternate_spellings text[]` column to `entities` for entity-resolution hints (misspellings, transcription errors), distinct from `nicknames` (intentional alternate names).

---

## Test Environment

- **Host:** `nova-staging@localhost`
- **Database:** `nova_memory` (staging instance)
- **Script under test:** `memory/scripts/extract_memories.py`
- **DB helper under test:** `memory/scripts/dedup_helper.py`
- **Relevant functions:** `find_entity_id()`, `ensure_entity()`, `normalize_entity_type()`, `_resolve_by_sender_id()`, `resolve_source_entity_id()`

---

## Section 1: Ghost Entity Prevention — Structural Heuristics

Tests that the blocklist/heuristic filter rejects strings that are role labels, technical identifiers, or structural artifacts rather than real entities.

### 1.1 Generic Role Word Blocklist

| TC | Category | Input Name | Expected: Entity Created? | Expected: Facts Stored? |
|:---|:---|:---|:---|:---|
| **TC-1.1.1** | Ghost Blocklist | `sender` | NO | NO — skipped before DB write |
| **TC-1.1.2** | Ghost Blocklist | `recipient` | NO | NO |
| **TC-1.1.3** | Ghost Blocklist | `system` | NO | NO |
| **TC-1.1.4** | Ghost Blocklist | `user` | NO | NO |
| **TC-1.1.5** | Ghost Blocklist | `the recipient` | NO | NO |
| **TC-1.1.6** | Ghost Blocklist | `the sender` | NO | NO |
| **TC-1.1.7** | Ghost Blocklist | `group` | NO | NO |
| **TC-1.1.8** | Ghost Blocklist | `Sender (I)ruid)` | NO | NO — parenthetical compound |

**Verification:** After extraction, run:
```sql
SELECT id, name FROM entities
WHERE LOWER(name) = ANY(ARRAY['sender', 'recipient', 'system', 'user',
  'the recipient', 'the sender', 'group']);
```
Expected: 0 rows returned.

### 1.2 Technical / Database Identifier Patterns

| TC | Category | Input Name | Rejection Reason | Expected: Entity Created? |
|:---|:---|:---|:---|:---|
| **TC-1.2.1** | Ghost Blocklist | `nova_staging_memory` | snake_case DB identifier | NO |
| **TC-1.2.2** | Ghost Blocklist | `agent_bootstrap_context` | snake_case technical identifier | NO |
| **TC-1.2.3** | Ghost Blocklist | `agent_domains table` | Contains word "table" | NO |
| **TC-1.2.4** | Ghost Blocklist | `agent_chat table` | Contains word "table" | NO |
| **TC-1.2.5** | Ghost Blocklist | `nova-staging DB role` | Contains "DB role" | NO |
| **TC-1.2.6** | Ghost Blocklist | `staging ownership` | Contains "staging" + "ownership" | NO |
| **TC-1.2.7** | Ghost Blocklist | `workflows table ownership` | Contains "table" | NO |
| **TC-1.2.8** | Ghost Blocklist | `database_system` | snake_case with "system" | NO |
| **TC-1.2.9** | Ghost Blocklist | `tasks table` | Contains "table" | NO |
| **TC-1.2.10** | Ghost Blocklist | `portfolio_extra_tables` | snake_case with "tables" | NO |

### 1.3 Platform Metadata Artifacts (Discord / Platform IDs)

| TC | Category | Input Name | Rejection Reason | Expected: Entity Created? |
|:---|:---|:---|:---|:---|
| **TC-1.3.1** | Ghost Blocklist | `Unknown user: 330189773371080716` | Matches `Unknown user: <id>` pattern | NO |
| **TC-1.3.2** | Ghost Blocklist | `Unknown user: graybeard` | Matches `Unknown user: *` pattern | NO |
| **TC-1.3.3** | Ghost Blocklist | `Unknown user: 1492403330922844250` | Matches `Unknown user: *` pattern | NO |
| **TC-1.3.4** | Ghost Blocklist | `Unknown user: 660345224089960478` | Matches `Unknown user: *` pattern | NO |

**Note:** These appear when Discord mentions reference users not in the guild member cache. The pipeline receives the raw Discord embed text and must not treat this as a person name.

### 1.4 Compound Description Strings with Special Characters

| TC | Category | Input Name | Rejection Reason | Expected: Entity Created? |
|:---|:---|:---|:---|:---|
| **TC-1.4.1** | Ghost Blocklist | `Google Drive — Edmund's Edification` | Contains em dash `—` (structural compound) | NO |
| **TC-1.4.2** | Ghost Blocklist | `NOVA Multiuser System (project #28)` | Parenthetical project reference | NO |
| **TC-1.4.3** | Ghost Blocklist | `Cognition System (id=9)` | Parenthetical `(id=N)` pattern | NO |
| **TC-1.4.4** | Ghost Blocklist | `Full System (id=10)` | Parenthetical `(id=N)` pattern | NO |
| **TC-1.4.5** | Ghost Blocklist | `the group (including sender)` | Generic phrase with parenthetical | NO |
| **TC-1.4.6** | Ghost Blocklist | `sender's team` | Possessive of blocklisted word | NO |

### 1.5 Parenthetical ID / Reference Patterns

| TC | Category | Input Name | Regex Pattern Matched | Expected: Entity Created? |
|:---|:---|:---|:---|:---|
| **TC-1.5.1** | Ghost Blocklist | `Widget X (id=42)` | `\(id=\d+\)` | NO |
| **TC-1.5.2** | Ghost Blocklist | `Project Alpha (project #7)` | `\(project #\d+\)` | NO |
| **TC-1.5.3** | Ghost Blocklist | `System (id=9)` | `\(id=\d+\)` | NO |

### 1.6 Valid Entities Must NOT Be Rejected

The blocklist/heuristics must have zero false positives on real person/org names.

| TC | Category | Input Name | Entity Type | Expected: Entity Created? |
|:---|:---|:---|:---|:---|
| **TC-1.6.1** | Regression (no false positive) | `Alice Johnson` | person | YES — two-word real name |
| **TC-1.6.2** | Regression (no false positive) | `OpenAI` | organization | YES |
| **TC-1.6.3** | Regression (no false positive) | `Edmund` | person | YES — single-word real name |
| **TC-1.6.4** | Regression (no false positive) | `I)ruid` | person | YES — known user handle with special chars |
| **TC-1.6.5** | Regression (no false positive) | `O'Brien` | person | YES — apostrophe in surname |
| **TC-1.6.6** | Regression (no false positive) | `Smith-Jones` | person | YES — hyphenated surname |
| **TC-1.6.7** | Regression (no false positive) | `Rayven` | person | YES — existing entity |

---

## Section 2: Entity Deduplication and Matching Improvements

Tests that the improved entity resolver prevents creating duplicates via case-insensitive matching, alternate spelling lookups, and nickname resolution.

### 2.1 Case-Insensitive Name Matching

**Setup:** Entity `Dustin Trammell` (id=2, type=person) and entity `NOVA` (id=1, type=ai) exist in DB.

| TC | Input Name | Expected: New Entity? | Expected: Resolved to |
|:---|:---|:---|:---|
| **TC-2.1.1** | `dustin trammell` | NO | Entity id=2 (Dustin Trammell) |
| **TC-2.1.2** | `DUSTIN TRAMMELL` | NO | Entity id=2 |
| **TC-2.1.3** | `Dustin Trammell` | NO | Entity id=2 |
| **TC-2.1.4** | `nova` (lowercase) | NO | Entity id=1 (NOVA) |
| **TC-2.1.5** | `Nova` (title case) | NO | Entity id=1 (NOVA) |

**Verification:**
```sql
SELECT COUNT(*) FROM entities WHERE LOWER(name) = 'dustin trammell';
-- Expected: 1 (no duplicate)
```

### 2.2 Alternate Spellings Resolution (Issue #267)

**Setup:** Entity `Rayven` (id=6, type=person) has `alternate_spellings = ARRAY['Raven', 'raven', 'ravens', 'Ravens']`.

| TC | Input Name | Expected: New Entity? | Expected: Resolved to |
|:---|:---|:---|:---|
| **TC-2.2.1** | `Raven` | NO | Entity id=6 (Rayven) |
| **TC-2.2.2** | `raven` (lowercase) | NO | Entity id=6 (Rayven) |
| **TC-2.2.3** | `Ravens` | NO | Entity id=6 (Rayven) |
| **TC-2.2.4** | `RAVEN` (uppercase) | NO | Entity id=6 (Rayven) |

**Verification:**
```sql
SELECT id, name FROM entities WHERE LOWER(name) = 'raven';
-- Expected: 0 rows (no ghost entity created)

SELECT id FROM entities WHERE 6 = id AND 'raven' = ANY(SELECT LOWER(unnest(alternate_spellings)));
-- Expected: 1 row (Rayven entity has it)
```

### 2.3 Nickname Array Resolution

**Setup:** Entity `NOVA` (id=1) has `nicknames = ARRAY['@NOVA', 'NOVA ✨', 'nova', 'Nova']`.

| TC | Input Name | Expected: New Entity? | Expected: Resolved to |
|:---|:---|:---|:---|
| **TC-2.3.1** | `@NOVA` | NO | Entity id=1 (NOVA) |
| **TC-2.3.2** | `NOVA ✨` | NO | Entity id=1 (NOVA) |

**Note:** The `find_entity_id()` query already checks `nicknames` via `unnest`. Verify this path is exercised and not bypassed by early return.

### 2.4 Preventing ON CONFLICT Silent Failures

The current `ensure_entity()` uses `ON CONFLICT DO NOTHING`. Verify the correct entity ID is still returned on conflict.

| TC | Category | Description | Expected |
|:---|:---|:---|:---|
| **TC-2.4.1** | Dedup | Insert entity with name=`Alice`, type=`person` when entity already exists. | `ON CONFLICT DO NOTHING` fires. `find_entity_id("Alice", ...)` returns existing ID. No duplicate row. |
| **TC-2.4.2** | Dedup | Insert entity with same name but different case: `ALICE` when `Alice` exists. | Case-insensitive lookup returns existing entity. New row NOT inserted. |
| **TC-2.4.3** | Dedup | Same `(name, type)` combo sent twice in rapid succession (race condition). | DB unique constraint `entities_name_type_key` prevents duplicate. Application receives correct entity ID both times. |

### 2.5 Full-Name / Partial-Name Resolution

**Setup:** Entity `Dustin Trammell` (full_name=`Dustin D. Trammell`) exists.

| TC | Input Name | Expected: New Entity? | Expected: Resolved to |
|:---|:---|:---|:---|
| **TC-2.5.1** | `Dustin` (first name only) | Decision required — see note | If resolver extends to first-name-only, resolves to Dustin Trammell |
| **TC-2.5.2** | `Trammell` (last name only) | Decision required — see note | Ambiguous — should NOT resolve without additional context |

> **QA Note:** Partial-name matching is a scope decision for implementation. TC-2.5.1 and TC-2.5.2 are **discussion items** — the fix should document the intended behavior. If partial matching is out of scope, these become negative tests (no resolution attempted, name treated as new entity or skipped by ghost filter).

---

## Section 3: alternate_spellings Column — Schema and Behavior

Tests for the new `alternate_spellings text[]` column added to `entities` per Issue #267.

### 3.1 Schema Migration

| TC | Category | Description | Expected |
|:---|:---|:---|:---|
| **TC-3.1.1** | Schema | After migration, `entities` table has column `alternate_spellings`. | `\d entities` shows `alternate_spellings text[]`. Column is nullable (no NOT NULL constraint). |
| **TC-3.1.2** | Schema | Column accepts array values. | `UPDATE entities SET alternate_spellings = ARRAY['Raven', 'raven'] WHERE id = 6;` succeeds. |
| **TC-3.1.3** | Schema | Column defaults to NULL on new entity insert (no value specified). | `INSERT INTO entities (name, type) VALUES ('TestEntity', 'person'); SELECT alternate_spellings FROM entities WHERE name = 'TestEntity';` → NULL. |
| **TC-3.1.4** | Schema | Column allows empty array. | `UPDATE entities SET alternate_spellings = '{}' WHERE id = 6;` succeeds without error. |
| **TC-3.1.5** | Schema | Idempotent migration — running migration twice does not error. | Second run of migration: column already exists → `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` succeeds silently. |

### 3.2 Entity Resolution via alternate_spellings

**Setup:** Entity `Rayven` (id=6) with `alternate_spellings = ARRAY['Raven', 'Ravens', 'raven']`.

| TC | Test Name | Description | Expected |
|:---|:---|:---|:---|
| **TC-3.2.1** | `find_entity_id_via_alternate_spellings` | Call `find_entity_id("Raven", conn)`. | Returns entity id=6. |
| **TC-3.2.2** | `find_entity_id_case_insensitive_spelling` | Call `find_entity_id("RAVEN", conn)`. | Returns entity id=6 (case-insensitive match in array). |
| **TC-3.2.3** | `find_entity_id_no_match` | Call `find_entity_id("Raving", conn)` (not in alternate_spellings). | Returns `None`. New entity may be created (subject to ghost filter). |
| **TC-3.2.4** | `alternate_spellings_checked_before_create` | Pipeline receives entity name `Raven` in LLM output. | `find_entity_id("Raven", ...)` returns Rayven's id. `ensure_entity("Raven", ...)` NOT called. No new entity row. |

**SQL for resolver lookup (expected implementation):**
```sql
SELECT id FROM entities
WHERE LOWER(name) = LOWER(%s)
   OR LOWER(full_name) = LOWER(%s)
   OR LOWER(%s) = ANY(SELECT LOWER(unnest(nicknames)))
   OR LOWER(%s) = ANY(SELECT LOWER(unnest(alternate_spellings)))
LIMIT 1
```

### 3.3 Separation from nicknames Column

| TC | Category | Description | Expected |
|:---|:---|:---|:---|
| **TC-3.3.1** | Semantic separation | Nickname `Dustin` for entity `I)ruid` is in `nicknames`. It should NOT be migrated to `alternate_spellings`. | After migration: `nicknames` still contains `Dustin`. `alternate_spellings` is NULL or empty for this entity. |
| **TC-3.3.2** | Semantic separation | Misspelling `Raven` for entity `Rayven` should be in `alternate_spellings`, NOT in `nicknames`. | After migration: `alternate_spellings` contains `Raven`. If `Raven` was in `nicknames`, it is removed from there. |
| **TC-3.3.3** | Independence | A name in `nicknames` that is NOT a misspelling remains in `nicknames` only. | Query: nicknames and alternate_spellings are independent arrays with no unintended overlap for legitimate entities. |

### 3.4 Existing Ghost Entity Cleanup

| TC | Category | Description | Expected |
|:---|:---|:---|:---|
| **TC-3.4.1** | Cleanup migration | After cleanup migration runs, query for known ghost entities returns 0 rows. | `SELECT id FROM entities WHERE name IN ('sender', 'recipient', 'nova_staging_memory', 'agent_bootstrap_context') AND type = 'person';` → 0 rows. |
| **TC-3.4.2** | Cleanup migration | Ghost entity facts are deleted before ghost entity record deletion. | No FK violation during cleanup. `entity_facts` for ghost entity ids are deleted first (or cascade). |
| **TC-3.4.3** | Cleanup migration | Real entities sharing name prefix with ghost patterns are NOT deleted. | Entity named `System Administrator` (if it exists) is preserved. Cleanup filter is pattern-specific, not prefix-based. |

---

## Section 4: Entity Type Inference

Tests that entity type is inferred correctly from context rather than always defaulting to `person`.

### 4.1 normalize_entity_type() Function

Unit tests for the `normalize_entity_type()` function in `extract_memories.py`.

| TC | Input | Expected Output |
|:---|:---|:---|
| **TC-4.1.1** | `"person"` | `"person"` |
| **TC-4.1.2** | `"PERSON"` | `"person"` (lowercased) |
| **TC-4.1.3** | `"ai"` | `"ai"` |
| **TC-4.1.4** | `"organization"` | `"organization"` |
| **TC-4.1.5** | `"place"` | `"other"` (mapped — not in valid set) |
| **TC-4.1.6** | `"restaurant"` | `"other"` |
| **TC-4.1.7** | `"cafe"` | `"other"` |
| **TC-4.1.8** | `"venue"` | `"other"` |
| **TC-4.1.9** | `"unknown_type_xyz"` | `"other"` (fallback) |
| **TC-4.1.10** | `""` (empty string) | `"other"` (fallback) |
| **TC-4.1.11** | `"  person  "` (whitespace-padded) | `"person"` (stripped before compare) |

### 4.2 Non-Hardcoded Person Default in _store_fact()

The `_store_fact()` inner function currently calls `ensure_entity(subject_name, "person", ...)` unconditionally. After the fix, it should use the type inferred from the LLM's `entities` array (if available) or a smarter default.

| TC | Category | Description | Expected |
|:---|:---|:---|:---|
| **TC-4.2.1** | Type Inference | LLM returns entity `{"name": "OpenAI", "type": "organization"}` in `entities` array. Pipeline stores it. | `SELECT type FROM entities WHERE name = 'OpenAI';` → `organization`, not `person`. |
| **TC-4.2.2** | Type Inference | LLM returns fact with `subject: "Claude"` and entities array contains `{"name": "Claude", "type": "ai"}`. | Entity `Claude` inserted with `type='ai'`. |
| **TC-4.2.3** | Type Inference | Fact subject name matches an entity in the `entities` array extracted from same message. | `_store_fact()` uses the type from the `entities` array when calling `ensure_entity()`, not hardcoded `person`. |
| **TC-4.2.4** | Type Inference | LLM fact references `subject: "Discord"` (no entities array entry). | Entity `Discord` gets `type='other'` or `type='organization'` — NOT `person`. Fallback type should be configurable or context-aware. |
| **TC-4.2.5** | Regression | Person entity with no type hint in LLM output still defaults to `person`. | `ensure_entity("Bob Smith", "person", ...)` — type defaults to `person` when no type in entities array. |

### 4.3 LLM Prompt Type Awareness

Verify the extraction prompt explicitly enumerates valid entity types.

| TC | Category | Description | Expected |
|:---|:---|:---|:---|
| **TC-4.3.1** | Prompt correctness | `build_extraction_prompt()` output contains valid type list. | Prompt text includes `"person|ai|organization"` in entities template. Does NOT show `"place"` as a standalone type (only as mapped). |
| **TC-4.3.2** | Prompt correctness | Valid entity types in prompt match DB constraint `entities_type_check`. | Prompt allows exactly: `person`, `ai`, `organization`, `pet`, `stuffed_animal`, `character`, `other`. |

---

## Section 5: Edge Cases

### 5.1 Unicode and International Names

| TC | Input Name | Type | Expected |
|:---|:---|:---|:---|
| **TC-5.1.1** | `François` | person | Entity created, name stored as-is with UTF-8 encoding |
| **TC-5.1.2** | `Müller` | person | Entity created with umlaut preserved |
| **TC-5.1.3** | `李小明` | person | Entity created, CJK characters stored correctly |
| **TC-5.1.4** | `Αλέξανδρος` | person | Entity created, Greek characters stored correctly |
| **TC-5.1.5** | `José María` | person | Entity created, two accented words |

**Verification:** `SELECT name FROM entities WHERE name = 'François';` → 1 row with correct UTF-8 value.

**Ghost filter note:** Unicode names must not be caught by heuristics targeting ASCII-only technical patterns. A regex matching `[a-z_]+` for snake_case should not block valid Unicode names.

### 5.2 Single-Word Entities

Single-word submissions require careful handling: valid names (Edmund, Bob) should pass; generic nouns (lunch, meeting) should not.

| TC | Input Name | Context | Expected |
|:---|:---|:---|:---|
| **TC-5.2.1** | `Edmund` | Person reference in conversation | Entity created (known valid name) |
| **TC-5.2.2** | `lunch` | "I'm going to lunch" | NOT an entity — generic noun, rejected |
| **TC-5.2.3** | `meeting` | "The meeting is at 3pm" | NOT an entity — generic noun, rejected |
| **TC-5.2.4** | `Alice` | New person introduced in message | Entity created (single-word person name) |

> **QA Note:** Single-word generic noun rejection requires either a stopword list or context-aware LLM instruction. The implementation must define how the ghost filter distinguishes `Edmund` from `meeting`. If the LLM is instructed not to extract generic nouns as entities, verify the prompt reflects this. If a stopword list is used, document it in the implementation.

### 5.3 Entity Names with Punctuation

| TC | Input Name | Expected |
|:---|:---|:---|
| **TC-5.3.1** | `I)ruid` | Entity created — this is a real user handle (existing entity id=7549) |
| **TC-5.3.2** | `O'Brien` | Entity created — apostrophe is valid in surnames |
| **TC-5.3.3** | `Smith-Jones` | Entity created — hyphen is valid in compound surnames |
| **TC-5.3.4** | `user@example.com` | NOT an entity — looks like an email address; should be rejected as entity name (but may be stored as a fact with key=`email`) |
| **TC-5.3.5** | `https://example.com` | NOT an entity — URL, not a name |
| **TC-5.3.6** | `@druid` | NOT an entity — platform handle, should be stored as fact not entity if relevant |

### 5.4 Very Long Names (Boundary Value Analysis on varchar(255))

| TC | Input Length | Input Name | Expected |
|:---|:---|:---|:---|
| **TC-5.4.1** | 254 chars | `A` × 254 | Entity created (within limit) |
| **TC-5.4.2** | 255 chars | `A` × 255 | Entity created (at limit, max valid) |
| **TC-5.4.3** | 256 chars | `A` × 256 | Error handled gracefully — truncated to 255 OR rejected with warning, NOT an unhandled DB exception crashing the pipeline |
| **TC-5.4.4** | 300 chars | `A` × 300 | Same as TC-5.4.3 — no unhandled exception |

**Verification for TC-5.4.3/4.4:** `extract_memories.py` exits with code 0 (partial data) or writes a WARNING to stderr. It must NOT exit with code 1 due to an unhandled psycopg2 DataError.

### 5.5 Empty, Null, and Sentinel Values

These are already partially handled (`ensure_entity()` checks for `"null"` and `"unknown"`), but must be verified completely:

| TC | Input Name | Expected |
|:---|:---|:---|
| **TC-5.5.1** | `""` (empty string) | Skipped — no entity created, no error |
| **TC-5.5.2** | `"   "` (whitespace only) | Stripped to empty, skipped |
| **TC-5.5.3** | `"null"` (string) | Skipped — sentinel handled in `ensure_entity()` |
| **TC-5.5.4** | `"unknown"` (string) | Skipped — sentinel handled |
| **TC-5.5.5** | `None` (Python None) | Skipped — None check in `find_entity_id()` |
| **TC-5.5.6** | `"N/A"` | Should be treated as noise — no entity created |

### 5.6 Numeric-Only and Snowflake-Looking Names

| TC | Input Name | Expected |
|:---|:---|:---|
| **TC-5.6.1** | `"12345"` | NOT an entity — numeric-only string, rejected by ghost filter |
| **TC-5.6.2** | `"330189773371080716"` | NOT an entity — Discord snowflake numeric string |
| **TC-5.6.3** | `"2025"` | NOT an entity — year number |
| **TC-5.6.4** | `"42"` | NOT an entity — short numeric string |

**Ghost filter rule:** Strings consisting solely of digits (after stripping whitespace) must not produce entity rows.

---

## Section 6: Integration Tests

End-to-end tests exercising the full pipeline from message input through DB state.

### 6.1 Ghost Entity NOT Created End-to-End

**Setup:** Staging DB with no entity named `sender` or `recipient`.
**Method:** Set env vars (`SENDER_NAME=TestUser`, `SENDER_ID=+15125550199`, `SENDER_PROVIDER=signal`), pipe a message through `extract_memories.py`.

| TC | Input Message | Expected DB State | Expected Exit Code |
|:---|:---|:---|:---|
| **TC-6.1.1** | `"The sender wants to know what the recipient thinks."` | No entity `sender` or `recipient` created. | 0 |
| **TC-6.1.2** | `"System is down. The agent_bootstrap_context table needs attention."` | No entities `system`, `agent_bootstrap_context`, `table` created. | 0 |
| **TC-6.1.3** | `"Unknown user: 660345224089960478 mentioned this."` | No entity matching `Unknown user:` pattern created. | 0 |

**Verification:**
```bash
# After each test case, confirm no ghost entity:
psql -U gem -d nova_memory -c "
  SELECT name FROM entities
  WHERE name IN ('sender', 'recipient', 'system', 'agent_bootstrap_context')
    AND created_at > NOW() - INTERVAL '1 minute';"
# Expected: 0 rows
```

### 6.2 Entity Dedup via alternate_spellings End-to-End

**Setup:** Entity `Rayven` (id=6) with `alternate_spellings = ARRAY['Raven', 'raven']`. Staging DB has no entity named `Raven`.

| TC | Input Message | Expected DB State |
|:---|:---|:---|
| **TC-6.2.1** | `"Raven went to the store today."` | No new entity `Raven` created. Fact `{subject: Rayven, key: activity, value: went to the store}` stored with entity_id=6. |
| **TC-6.2.2** | `"I talked to raven about the project."` | Same — resolves to Rayven (id=6). |

**Verification:**
```bash
psql -U gem -d nova_memory -c "SELECT COUNT(*) FROM entities WHERE name = 'Raven';"
# Expected: 0

psql -U gem -d nova_memory -c "
  SELECT ef.key, ef.value FROM entity_facts ef
  WHERE ef.entity_id = 6
  ORDER BY ef.learned_at DESC LIMIT 3;"
# Expected: fact for Rayven from the test message
```

### 6.3 Case-Insensitive Entity Matching End-to-End

**Setup:** Entity `Alice Johnson` (type=person) exists in DB.

| TC | Input Message | Expected |
|:---|:---|:---|
| **TC-6.3.1** | `"alice johnson is coming to the party."` | `find_entity_id("alice johnson")` returns Alice's id. No duplicate created. |
| **TC-6.3.2** | `"ALICE JOHNSON mentioned she likes tea."` | Same entity resolved. Fact `preference_tea` stored on Alice's existing entity. |

### 6.4 Vocabulary Table Interaction

Vocabulary entries must NOT generate entity rows.

| TC | Category | Description | Expected |
|:---|:---|:---|:---|
| **TC-6.4.1** | Isolation | LLM output contains `vocabulary: [{"word": "NOVA", "category": "name"}]`. | `vocabulary` table updated/created for `NOVA`. No duplicate in `entities` table. Entity `NOVA` (if pre-existing) NOT re-created. |
| **TC-6.4.2** | Isolation | Vocabulary word `trigeminal` (technical term, not a person). | Stored in `vocabulary` only. No entity row created. |

### 6.5 Source Attribution Integrity

| TC | Category | Description | Expected |
|:---|:---|:---|:---|
| **TC-6.5.1** | Source Attribution | Message from sender `I)ruid` (entity_id=2) about `Rayven`. | Fact stored: `entity_id=Rayven's id`, `entity_fact_sources.source_entity_id=2`. Source ≠ Subject. |
| **TC-6.5.2** | Source Attribution | Self-reported fact: sender says "I prefer dark mode." | Fact stored: `entity_id=sender's entity_id`, source entity also = sender. Source = Subject. |
| **TC-6.5.3** | Source Attribution | Ghost entity trigger: message body references `recipient` in facts. | No `entity_fact_sources` row with `entity_id` pointing to a ghost entity. Ghost entities produce no facts at all. |

### 6.6 Multiple Entity References in Single Message

**Setup:** Entities `Alice` and `Bob` both exist.

| TC | Description | Expected |
|:---|:---|:---|
| **TC-6.6.1** | Message mentions same entity twice: `"Alice said she loves coffee, and Alice also likes hiking."` | One entity `Alice`. Two facts (`coffee_preference`, `hiking_preference`). No duplicate entity. |
| **TC-6.6.2** | Message mentions two different entities: `"Alice and Bob are working on the project."` | Both entities resolved to existing records. Two separate fact attributions. No ghost entities. |

### 6.7 Exit Code and Error Handling

| TC | Scenario | Expected Exit Code | Expected Stderr |
|:---|:---|:---|:---|
| **TC-6.7.1** | Valid message, all operations succeed | 0 | `Extraction complete` |
| **TC-6.7.2** | Message shorter than `MIN_MESSAGE_LENGTH` (10 chars) | 0 | `Skipping short or empty message` |
| **TC-6.7.3** | `OPENROUTER_API_KEY` not set | 1 | `ERROR: OPENROUTER_API_KEY not set` |
| **TC-6.7.4** | DB connection fails | 1 | `ERROR: DB connection failed` |
| **TC-6.7.5** | LLM returns invalid JSON | 1 | `Failed to parse LLM response as JSON` |
| **TC-6.7.6** | Ghost entity filtered — no other extractable data in message | 0 | WARNING logged, pipeline completes successfully |
| **TC-6.7.7** | Very long entity name (256 chars) in LLM output | 0 | WARNING for entity skip, pipeline continues for other facts |

---

## Defect Cross-Reference: Known Ghost Entities in Production

The following real ghost entities from production (as of 2026-05-16) serve as regression anchors. Each must NOT be re-created after the fix is applied:

| Ghost Entity Name | entity_id | Fact Count | Rejection Reason |
|:---|:---|:---|:---|
| `sender` | 1782 | 18 | Generic role word |
| `recipient` | 2213 | 16 | Generic role word |
| `system` | 1465 | 15 | Generic role word |
| `Unknown user: 330189773371080716` | 1672 | 9 | Platform metadata pattern |
| `nova_staging_memory` | 1266 | 9 | snake_case DB identifier |
| `agent_bootstrap_context` | 874 | 8 | snake_case technical identifier |
| `the recipient` | 2596 | 7 | Generic role word (with article) |
| `Google Drive — Edmund's Edification` | 1511 | 5 | Compound description with em dash |
| `Unknown user: graybeard` | 2887 | 4 | Platform metadata pattern |
| `tasks table` | 2300 | ~3 | Contains "table" |
| `database_system` | 6102 | ~3 | snake_case + "system" |
| `nova-staging database` | 2719 | ~3 | Technical environment reference |
| `workflows table ownership` | 1407 | ~2 | Contains "table" |

**Regression query (run after fix deployment):**
```sql
SELECT e.id, e.name, COUNT(ef.id) as new_facts
FROM entities e
LEFT JOIN entity_facts ef ON ef.entity_id = e.id AND ef.learned_at > NOW() - INTERVAL '7 days'
WHERE e.id IN (1782, 2213, 1465, 1672, 1266, 874, 2596, 1511, 2887, 2300, 6102, 2719, 1407)
GROUP BY e.id, e.name
ORDER BY new_facts DESC;
-- Expected: All new_facts = 0 (no new facts attributed to ghost entities after fix)
```

---

## Quality Gates

The implementation must meet these gates before QA sign-off:

- [ ] All **TC-1.x** blocklist cases: 0 new ghost entities created for any test input
- [ ] All **TC-2.x** dedup cases: 0 duplicate entities from case-insensitive inputs
- [ ] All **TC-2.2.x** alternate_spellings cases: Raven → Rayven resolution works
- [ ] All **TC-3.1.x** schema cases: `alternate_spellings text[]` column exists post-migration
- [ ] All **TC-4.1.x** normalize_entity_type cases: correct type mapping
- [ ] **TC-4.2.x**: No entity with valid type hint receives hardcoded `person` type
- [ ] All **TC-5.5.x** null/empty cases: no crash, clean skip with 0 entities created
- [ ] **TC-5.4.3/5.4.4**: No unhandled exception from oversized names
- [ ] All **TC-6.1.x** integration cases: known ghost trigger messages produce 0 ghost entities
- [ ] **TC-1.6.x** false positive regression: all valid entities still created correctly
- [ ] Defect cross-reference query: 0 new facts added to any known ghost entity after fix

---

## Test Case Count Summary

| Section | Area | Count |
|:---|:---|:---|
| 1.1–1.6 | Ghost Entity Prevention (Structural Heuristics) | 29 |
| 2.1–2.5 | Dedup / Matching Improvements | 16 |
| 3.1–3.4 | alternate_spellings Schema & Behavior | 13 |
| 4.1–4.3 | Entity Type Inference | 18 |
| 5.1–5.6 | Edge Cases | 23 |
| 6.1–6.7 | Integration Tests | 20 |
| **Total** | | **119** |
