# QA Validation Report — Part 2: Python Scripts, Shell Script & Codebase Audit

**Branch:** `feat/entity-facts-schema-evolution-batch`  
**Reviewer:** Gem (QA Lead)  
**Date:** 2026-05-13  
**Scope:** memory/scripts/ Python + shell files, memory/tests/fixtures/test-data.sql, codebase audit greps

---

## 1. `memory/scripts/extract_memories.py`

### 1.1 extraction_count used (not vote_count/confirmation_count)
**PASS** — `entity_facts` SELECT/UPDATE use `extraction_count` throughout (lines 249, 258, 264, 276, 305).  
**PARTIAL FAIL** — Line 709: `vocabulary` table UPDATE still uses `confirmation_count` and `last_confirmed` (old column names):
```python
"UPDATE vocabulary SET confirmation_count = COALESCE(confirmation_count, 0) + 1, last_confirmed = NOW() WHERE id = %s"
```
This is a vocabulary-table issue, not entity_facts, but must be assessed: if the `vocabulary` table schema was NOT updated, this is fine. If it was updated to `extraction_count`/`last_confirmed_at`, this is a **FAIL**.  
**Action required:** Confirm whether vocabulary table schema was migrated. If yes → bug.

### 1.2 last_confirmed_at used (not last_confirmed)
**PASS** — `entity_facts` use `last_confirmed_at` correctly (lines 306, 307).  
**CONDITIONAL FAIL** — Same line 709 as above: vocabulary UPDATE uses `last_confirmed` not `last_confirmed_at`. Same caveat as 1.1.

### 1.3 durability + category in INSERT/UPDATE (not data_type)
**PASS** — `store_or_reinforce_fact()` INSERT cols include `durability` and `category` (lines 354-360). No `data_type` references.

### 1.4 entity_fact_sources UPSERT after insert/reinforce
**PASS** — Both the reinforce path (lines 329-339) and the insert path (lines 374-384) perform:
```sql
INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen)
VALUES (%s, %s, %s, 1, NOW(), NOW())
ON CONFLICT (fact_id, source_entity_id)
DO UPDATE SET attribution_count = entity_fact_sources.attribution_count + 1, last_seen = NOW()
```

### 1.5 SENDER_ID labeled with platform type in prompt
**PASS** — `build_extraction_prompt()` builds `sender_label` with provider-aware logic (lines 401-409):
- Discord → `"Discord user ID: {sender_id}"`
- Signal → `"Signal phone: {sender_id}"`
- Telegram → `"Telegram user: {sender_id}"`
- Default → `"{provider.Capitalize()} user: {sender_id}"`

### 1.6 SENDER_PROVIDER env var read
**PASS** — Line 867: `sender_provider = os.environ.get("SENDER_PROVIDER", "").strip()`

### 1.7 Prompt includes: category list, durability guidance, expires temporal boundary, publication attribution guidance
**PASS** — All four are present in `build_extraction_prompt()`:
- Category list: lines in `CATEGORY LIST (examples, not exhaustive)` section
- Durability guidance: `DURABILITY GUIDANCE` block (permanent/long_term/short_term/ephemeral with descriptions)
- Expires temporal boundary: `TEMPORAL BOUNDARY RULE` and `expires` field documented in the JSON schema
- Publication attribution guidance: `SOURCE ATTRIBUTION` block (source_person = author, source_citation = publication metadata)

### 1.8 Source entity auto-creation logic present
**PASS** — `ensure_entity()` called for sender entity at lines 825-840. `_store_fact()` helper calls `ensure_entity(subject_name, "person", conn)` when entity not found (lines 578-585). New entity types auto-created on extraction.

---

## 2. `memory/scripts/memory-maintenance.py`

### 2.1 DECAY_RATES uses durability keys (permanent/long_term/short_term/ephemeral), not data_type keys
**PASS** — Lines 46-51:
```python
DECAY_RATES = {
    'permanent': 0,
    'long_term': 0.005,
    'short_term': 0.02,
    'ephemeral': 0.1,
}
```
Comment on line 44 explicitly says "keyed by durability, not old data_type".

### 2.2 WHERE clause uses `durability != 'permanent'` not `data_type != 'permanent'`
**PASS** — Lines 295 and 401-412:
```sql
WHERE durability != 'permanent'
  AND confidence > %s
```
and archive:
```sql
WHERE confidence < %s
  AND learned_at < NOW() - INTERVAL '%s days'
  AND durability != 'permanent'
```

### 2.3 expires < NOW() check for aggressive decay
**PASS** — Lines 309-311:
```python
if row['expires'] is not None and row['expires'] < datetime.now(timezone.utc):
    decay_factor = 0.0  # immediate archive
```

### 2.4 confirmation_count replaced with extraction_count
**PARTIAL PASS / FAIL** — SQL queries use `extraction_count` correctly throughout (lines 109, 126, 249, 257).  
**FAIL** — Line 99 in docstring still says "Summing confirmation_counts" (minor, documentation only).  
**Verdict:** SQL is correct; docstring is stale — low severity.

### 2.5 Confidence-tiered dedup: high (>=0.80 similarity, auto-merge), medium (0.50-0.79, daily report), low (skip)
**FAIL** — The spec requires three confidence tiers:
- High (similarity ≥ 0.80): auto-merge
- Medium (0.50-0.79): flag in daily report
- Low (< 0.50): skip

The implementation uses a single threshold (> 0.85 for fuzzy matching) and a binary auto-archive vs pending-review split based on **confidence score ratio** (>2x), NOT the required similarity-based tiers. There is no medium tier that generates a daily report entry. The confidence-tiered dedup spec is **not implemented**.

### 2.6 Daily report generation
**FAIL** — `log_summary()` writes a summary to a daily markdown file (`~/.openclaw/workspace/memory/YYYY-MM-DD.md`), but this is a decay script operational log, NOT a "daily report" in the sense of flagging medium-tier duplicate candidates for human review. No specific "daily report" output for medium-confidence dedup candidates exists.

---

## 3. `memory/scripts/dedup_helper.py`

### 3.1 confirmation_count → extraction_count
**PASS** — `find_existing_fact()` selects `extraction_count` (line 65). `store_or_reinforce_fact()` UPDATE uses `extraction_count = extraction_count + 1` (line 174). No `confirmation_count` references.

### 3.2 source/source_entity_id column writes replaced with entity_fact_sources
**PASS** — INSERT into `entity_facts` uses these columns only: `entity_id, key, value, confidence, extraction_count, visibility, durability, category` (line 211). No `source` column in the INSERT.  
**PASS** — Both the reinforce and create paths include an `entity_fact_sources` UPSERT (lines 184-192, 230-238).

---

## 4. `memory/scripts/get-visible-facts.sh`

### 4.1 JOIN entity_fact_sources for visibility (not entity_facts.source_entity_id)
**PASS** — Line 54: `LEFT JOIN entity_fact_sources efs ON efs.fact_id = ef.id`  
**PASS** — Visibility filter (lines 27-31) uses `efs.source_entity_id IN ($PARTICIPANT_IDS)` — correctly references the join, not a direct column on `entity_facts`.

---

## 5. `memory/tests/fixtures/test-data.sql`

### 5.1 No dropped column references
**PASS** — No occurrences of `vote_count`, `data_type`, `confirmation_count`, or `source_entity_id` as column names in INSERT statements.

**MINOR FAIL** — Line 98: Frank's `favorite_quote` fact has a column count/type mismatch:
```sql
(6, 'favorite_quote', 'Don''t just market—tell a story!', 'conversation', 0.8, 'public', 'observation'),
```
The INSERT declaration is `(entity_id, key, value, confidence, visibility, durability, category)` — 7 columns.  
This row has 7 values but the 4th value is `'conversation'` (a string) where `confidence` (numeric) is expected, and `0.8` lands in the `visibility` slot. This is a **data type mismatch / wrong column order bug** in the test fixture.

---

## 6. Codebase Audit (Section 10) — grep results

### vote_count (in scripts, excluding vocabulary/agent_domains)
```
(none found)
```
**PASS**

### confirmation_count (in scripts)
```
memory/scripts/memory-maintenance.py:99:    - Summing confirmation_counts   [docstring only]
memory/scripts/extract_memories.py:709:  vocabulary table UPDATE uses confirmation_count + last_confirmed
```
**FAIL (extract_memories.py line 709)** — vocabulary table still uses old column names. Requires schema check.  
**INFO (memory-maintenance.py line 99)** — stale docstring, not SQL.

### last_confirmed (not last_confirmed_at) in scripts
```
memory/scripts/extract_memories.py:709:  last_confirmed = NOW()   [vocabulary UPDATE]
```
**FAIL** — Same line 709 issue.

### data_type in scripts
```
memory/scripts/memory-maintenance.py:44:  # keyed by durability, not old data_type   [comment only]
```
**PASS** — Comment only, no functional code uses `data_type`.

### .source["'] in extract_memories.py and dedup_helper.py
```
(none found)
```
**PASS**

### source_entity_id in scripts NOT referencing entity_fact_sources
All occurrences in `dedup_helper.py` and `extract_memories.py` use `source_entity_id` as a **Python variable** (function parameter / local var) that is then passed into `entity_fact_sources` UPSERT statements. No `source_entity_id` column is written directly to `entity_facts`.  
**PASS** — `get-visible-facts.sh` line 29 uses `efs.source_entity_id` where `efs` is aliased from `entity_fact_sources` join — correct.

---

## Summary

| # | File / Check | Status | Notes |
|---|---|---|---|
| 1.1 | extract_memories.py — extraction_count (entity_facts) | ✅ PASS | |
| 1.1b | extract_memories.py — extraction_count (vocabulary table) | ⚠️ CONDITIONAL FAIL | Line 709: uses confirmation_count — depends on vocabulary schema |
| 1.2 | extract_memories.py — last_confirmed_at (entity_facts) | ✅ PASS | |
| 1.2b | extract_memories.py — last_confirmed_at (vocabulary table) | ⚠️ CONDITIONAL FAIL | Line 709: uses last_confirmed — same caveat |
| 1.3 | extract_memories.py — durability + category in INSERT | ✅ PASS | |
| 1.4 | extract_memories.py — entity_fact_sources UPSERT | ✅ PASS | Both paths |
| 1.5 | extract_memories.py — SENDER_ID platform label in prompt | ✅ PASS | |
| 1.6 | extract_memories.py — SENDER_PROVIDER env var | ✅ PASS | |
| 1.7 | extract_memories.py — prompt contents complete | ✅ PASS | All 4 elements present |
| 1.8 | extract_memories.py — source entity auto-creation | ✅ PASS | |
| 2.1 | memory-maintenance.py — DECAY_RATES durability keys | ✅ PASS | |
| 2.2 | memory-maintenance.py — WHERE uses durability (not data_type) | ✅ PASS | |
| 2.3 | memory-maintenance.py — expires < NOW() aggressive decay | ✅ PASS | |
| 2.4 | memory-maintenance.py — extraction_count (SQL) | ✅ PASS | Docstring stale (S4) |
| 2.5 | memory-maintenance.py — confidence-tiered dedup | ❌ FAIL | Not implemented per spec |
| 2.6 | memory-maintenance.py — daily report generation | ❌ FAIL | Decay log only, not dedup candidate report |
| 3.1 | dedup_helper.py — extraction_count | ✅ PASS | |
| 3.2 | dedup_helper.py — entity_fact_sources (not source col) | ✅ PASS | |
| 4.1 | get-visible-facts.sh — JOIN entity_fact_sources | ✅ PASS | |
| 5.1 | test-data.sql — no dropped column refs | ✅ PASS | |
| 5.1b | test-data.sql — Frank's favorite_quote column mismatch | ❌ FAIL | Column order bug line 98 |
| 10.A | grep: vote_count | ✅ PASS (none) | |
| 10.B | grep: confirmation_count | ❌ FAIL | Line 709 + docstring |
| 10.C | grep: last_confirmed[^_] | ❌ FAIL | Line 709 |
| 10.D | grep: data_type | ✅ PASS (comment only) | |
| 10.E | grep: .source["'] | ✅ PASS (none) | |
| 10.F | grep: source_entity_id (not entity_fact_sources) | ✅ PASS | All are variable refs or efs. alias |

---

## Defects Identified

| ID | File | Line | Severity | Description |
|---|---|---|---|---|
| D1 | extract_memories.py | 709 | S3/P2 | Vocabulary UPDATE uses `confirmation_count` and `last_confirmed` — verify if vocabulary schema was migrated |
| D2 | memory-maintenance.py | merge_duplicates() | S2/P2 | Confidence-tiered dedup not implemented: spec requires high(≥0.80 auto-merge), medium(0.50-0.79 daily report), low(skip); implementation uses single 0.85 threshold with binary outcome |
| D3 | memory-maintenance.py | log_summary() | S3/P2 | No daily report output for medium-tier dedup candidates — spec requires daily report for 0.50-0.79 similarity matches |
| D4 | test-data.sql | 98 | S2/P1 | Frank's `favorite_quote` row has wrong column order: `'conversation'` lands in confidence slot (expects numeric), `0.8` lands in visibility slot — fixture will fail on INSERT |
| D5 | memory-maintenance.py | 99 | S4/P3 | Stale docstring: "Summing confirmation_counts" should be "Summing extraction_counts" |

---

## QA Verdict

**NOT APPROVED** — 3 functional defects (D1 conditional, D2 definite, D4 definite) block approval.

- **D2** (confidence-tiered dedup) is the most significant gap — the spec requirement is entirely absent.
- **D4** (test fixture column mismatch) will cause INSERT failures — must fix before tests can run.
- **D1** needs schema verification to determine if it is a real bug or intentional (vocabulary table may not have been migrated).

Recommend routing D2 and D4 to Coder for fixes before re-review.
