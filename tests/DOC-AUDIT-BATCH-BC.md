# Documentation Audit — Batch BC (Entity Facts Schema Evolution)

**Date:** 2026-05-13
**Branch:** `feat/entity-facts-schema-evolution-batch`

## Docs Updated

### database/schema-reference.md
- `entity_facts` column count: 21 → 19 (reflects removal of `vote_count`, `confirmation_count`, `last_confirmed` (w/o tz), `data_type`, `source`, `source_entity_id`)
- `entity_facts_archive` column count: 22 → 20
- Added `entity_fact_sources` table row (7 columns)
- Added Functions section with `merge_facts(survivor_id, absorbed_id)` entry

### memory/docs/CONFIDENCE-DECAY.md
- `data_type='permanent'` → `durability='permanent'` (table header and exclusion section)
- `vote_count increments` → `extraction_count increments`
- `last_confirmed updates` → `last_confirmed_at updates`
- `last_confirmed timestamp` → `last_confirmed_at timestamp`

### memory/docs/SOURCE-AUTHORITY.md
- All `data_type` column references → `durability` (authority rules, implementation sections, flow diagram, SQL queries)
- All `vote_count` references → `extraction_count`
- All `last_confirmed` references → `last_confirmed_at`
- `source_entity_id` on `entity_facts` → `entity_fact_sources.source_entity_id` (database schema section, SQL query, Troubleshooting)
- Updated "Data Types" section → "Durability Levels" with new values (`permanent`, `long_term`, `short_term`, `ephemeral`)
- Added "Category Usage" section explaining free-form `category` column
- Updated agent logic example from `data_type` → `durability`
- Updated SQL example to use `LEFT JOIN entity_fact_sources`
- Updated bash example to mention `SENDER_ID` platform labeling

### memory/docs/database-schema-guide.md
- Replaced stale `entity_facts` CREATE TABLE snippet (had `source`, `data_type`, `vote_count`, `last_confirmed`)
- New snippet reflects current schema: `data JSONB`, `extraction_count`, `last_confirmed_at`, `decay_rate`, `expires`, `durability`, `category`, `updated_at`, `visibility`, `privacy_scope`
- Added note directing to `entity_fact_sources` for source attribution

### ARCHITECTURE.md
- `source_entity_id` → `entity_fact_sources.source_entity_id` (Privacy Gap section)

### memory/ARCHITECTURE.md
- Updated table description: `data_type` → `durability`, `category`
- Replaced entire Entity Facts Access Control Columns table:
  - `data_type` → `durability` + `category`
  - `source_entity_id` → moved to `entity_fact_sources` (added note)
  - `vote_count` → `extraction_count`
  - `last_confirmed` → `last_confirmed_at`
  - Added `expires`, `source_channel_transcript_id`, `source_channel_session_id` columns

### memory/docs/agent-delegation-memory.md
- Updated INSERT statements: `data_type` → `durability` (both examples)
- Changed `'observation'` → `'long_term'` for capability facts (more appropriate)

### memory/docs/memory-extraction-pipeline.md
- `vote_count++` → `extraction_count++` (reinforcement description)

### memory/skills/memory-extraction-pipeline/SKILL.md
- `vote_count` → `extraction_count`
- `last_confirmed` → `last_confirmed_at`
- Added `durability` and `category` to schema section
- Updated reinforcement pipeline description to mention `entity_fact_sources` UPSERT
- Updated log message from `+1 vote` → `+1 extraction`

## Stale Docs Found and Corrected

All stale column references (see list above) have been corrected. The following patterns were caught:

| Pattern | Occurrences Fixed | New Value |
|---------|------------------|-----------|
| `data_type` column on entity_facts | 15+ | `durability` + `category` |
| `vote_count` column on entity_facts | 10+ | `extraction_count` |
| `last_confirmed` column on entity_facts | 8+ | `last_confirmed_at` |
| `source_entity_id` on entity_facts | 5+ | `entity_fact_sources.source_entity_id` |
| old data_type enum values (identity/preference/temporal) | 3 | durability values (permanent/long_term/short_term/ephemeral) |

## Scope-Excluded Items

- **extract_memories.py line 709**: Uses `confirmation_count`/`last_confirmed` on the `vocabulary` table (not `entity_facts`). This is a code logic change, not a documentation issue. Needs separate vocabulary schema assessment.
- **QA validation docs** (`tests/QA-VALIDATION-*`, `tests/test-cases-batch-bc.md`): These document the schema migration process itself and are expected to reference old column names. Not updated.

## Verification

- `grep -rn 'vote_count\|confirmation_count\|last_confirmed[^_]' --include="*.md"` — Clean except vocabulary table code
- `grep -rn 'data_type\|source_entity_id[^s]' --include="*.md"` — All remaining references are correct (historical notes, entity_fact_sources references)
