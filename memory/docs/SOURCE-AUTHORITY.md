# Source Authority

> **Note:** The Fact Judgement & Testimony Model (`fact-judgement-model.md`) **supersedes** the old "authority wins" approach described here for contradiction handling. Under the new model, contradictory facts are no longer rejected at write time — they persist alongside authority facts for query-time reasoning. Authority self-reports still carry the highest credibility weight, but that weight is applied at query time rather than as a write-time lock. This file remains the reference for the authority *concept*, confidence scoring, and the current schema.

> **Note:** The original grammar parser (`grammar_parser/`) that implemented this feature has been removed (#174), and the shell pipeline described below (`store-memories.sh`, `extract-memories.sh`) no longer exists either. Extraction is now a single Python script, `memory/scripts/extract_memories.py`, which asks the LLM to judge `durability`/`category`/`confidence` per fact directly in its extraction prompt — there is no separate write-time step that force-sets `durability='permanent'` for a hardcoded authority entity, and no write-time rejection of non-authority facts that conflict with authority facts. `memory/scripts/confidence_helper.py` (function `get_initial_confidence()`) computes an initial confidence score from the entity's `trust_level` (owner=1.0, admin=0.9, user=0.7, unknown=0.4, untrusted=0.2) and a source-type multiplier (direct/inferred/external) — entity_id 2 (I)ruid) always gets 1.0 via the `OWNER_ENTITY_ID` constant, but there is no `AUTHORITY_ENTITY_ID` env var override, no `SENDER_NAME`-based authority lookup, and no automatic `durability='permanent'` promotion baked into that helper. The rules below describe the *intended* authority behavior/schema; treat the "Implementation" and "Usage"/"Testing" sections further down as historical (pre-#174) unless re-verified against current code.

## Key Concepts

### Authority Entity

- **Default Authority**: Entity ID 2 (I)ruid / Dustin Trammell)
- **Configurable**: Set via `AUTHORITY_ENTITY_ID` environment variable
- **Identification**: Matched by entity name or any nickname

### Authority Rules

1. **Permanent Facts**: All facts from authority entities are marked `durability='permanent'`
2. **Confidence Override**: Authority facts always have `confidence=1.0` regardless of input
3. **Conflict Resolution**:
   - Authority fact vs. non-authority fact → Authority wins
   - Authority fact vs. same value → Increment `extraction_count`, update `last_confirmed_at`
   - Authority fact vs. conflicting authority fact → Update to new value
   - Non-authority vs. authority fact → Rejected with log message

## Implementation (current, as of extract_memories.py + confidence_helper.py)

### Current Architecture

Source authority is a cross-cutting concern implemented across multiple components:

#### `memory/scripts/confidence_helper.py`

`get_initial_confidence(entity_id, source)` calculates an initial confidence score:

- `entity_id == OWNER_ENTITY_ID` (2, I)ruid) always returns `1.0`
- Otherwise, base confidence comes from the entity's `trust_level` column (`owner`=1.0, `admin`=0.9, `user`=0.7, `unknown`=0.4, `untrusted`=0.2), scaled by a source-type multiplier (`direct`=1.0, `external`=0.7, `inferred`=0.5)
- Used by `memory/scripts/dedup_helper.py` (imports `get_initial_confidence`)

#### `memory/templates/memory-maintenance.py`

Enforces authority-adjacent rules during the unified maintenance pipeline (see `memory/README.md`):

- Permanent facts (`durability = 'permanent'`) are excluded from confidence decay
- Non-authority facts still decay and can be archived per the normal `durability`-based rates

#### `memory/scripts/extract_memories.py`

The current extraction pipeline does **not** implement deterministic authority-based conflict rejection at write time. Instead:

- The extraction LLM call judges `durability`, `category`, and `confidence` per fact directly (see the DURABILITY GUIDANCE in the extraction prompt) — there is no separate `SENDER_NAME`-based authority check that force-promotes a fact to `durability='permanent'`
- Source attribution (who said it) is recorded via the `entity_fact_sources` table, populated from sender metadata automatically — not from a `source`/`source_entity_id` column on `entity_facts` itself
- Conflicting facts from different sources are **not** rejected at insertion — per the Fact Judgement & Testimony Model (`fact-judgement-model.md`), they persist side-by-side for query-time reasoning rather than being blocked write-time

The deterministic `AUTHORITY_ENTITY_ID`-driven write-time rejection flow described in the sections below (Usage, Testing, Authority Detection Flow) predates the #174 grammar-parser removal and the Fact Judgement model; it does not reflect the current pipeline. Verify against `extract_memories.py` / `confidence_helper.py` before relying on it.

### Database Schema

The following columns support authority enforcement:

- `entity_fact_sources.source_entity_id` — Tracks which entity provided the fact (via entity_fact_sources join)
- `entity_facts.durability` — Supports 'permanent', 'long_term', 'short_term', 'ephemeral'
- `entity_facts.category` — Free-form text replacing data_type (e.g., 'identity', 'preference', 'observation')
- `entity_facts.confidence` — Authority facts set to 1.0
- `entity_facts.extraction_count` — Incremented when fact is confirmed
- `entity_facts.last_confirmed_at` — Updated when fact is re-stated

### Authority Detection Flow (historical — pre-#174 / pre-Fact-Judgement-Model; see the note above)

```
Message received
    ↓
memory-extract hook → ctx.content → extract-memories.sh (Claude extraction)
    ↓
store-memories.sh
    ├── Lookup entity by SENDER_NAME → get entity_id
    ├── Compare entity_id to AUTHORITY_ENTITY_ID
    ├── If authority match:
    │   ├── Set durability = 'permanent'
    │   ├── Set confidence = 1.0
    │   └── Override existing conflicting facts
    └── If non-authority:
        ├── Check if existing fact is permanent (authority-sourced)
        ├── If authority fact exists → reject update
        └── If no authority fact → insert normally
```

**Current flow** is simpler: `memory-extract` hook → `extract_memories.py` (LLM judges durability/category/confidence per fact in one pass) → direct INSERT into `entity_facts` + `entity_fact_sources`. No deterministic authority branch; I)ruid's facts get `confidence=1.0` only via `confidence_helper.py`'s `OWNER_ENTITY_ID` check when that helper is invoked (`dedup_helper.py`), not from the extraction path itself setting `durability='permanent'` unconditionally.

## Usage

### Basic Usage (current pipeline)

The extraction pipeline runs via the `memory-extract` hook, which invokes `memory/scripts/extract_memories.py` with sender metadata (`SENDER_NAME`, `SENDER_ID`, etc. — see the script's module docstring) passed as environment variables. There is no standalone CLI entry point to manually trigger extraction for a single message; extraction happens as part of normal message processing.

### Configurable Authority Entity

There is currently no `AUTHORITY_ENTITY_ID` environment variable in the live pipeline. `confidence_helper.py` hardcodes `OWNER_ENTITY_ID = 2` (I)ruid). To change the authority entity, that constant would need to be edited directly.

## Testing

`tests/test_authority_facts.sh` was removed as part of the grammar-parser removal (#174) and does not exist in the current repo. See `memory/tests/` for current test coverage relevant to fact storage and confidence.

## Logging and Debugging

### Console Output Markers

- `[AUTHORITY]` — Authority source detected
- `[PERMANENT]` — Fact marked as permanent
- `⚡ AUTHORITY UPDATE` — Authority fact overriding existing fact
- `✓ Fact confirmed` — Fact re-stated (extraction_count++)
- `✗ Conflict rejected` — Non-authority attempted override

### Database Queries

**Check authority facts**:
```sql
SELECT e.name, ef.key, ef.value, ef.category, efs.source_entity_id, ef.confidence
FROM entity_facts ef
JOIN entities e ON e.id = ef.entity_id
LEFT JOIN entity_fact_sources efs ON efs.fact_id = ef.id
WHERE ef.durability = 'permanent'
ORDER BY ef.updated_at DESC;
```

**View change log** (if `fact_change_log` table exists):
```sql
SELECT 
    fcl.*, 
    e.name as changed_by
FROM fact_change_log fcl
LEFT JOIN entities e ON e.id = fcl.changed_by_entity_id
WHERE fcl.reason = 'authority_override'
ORDER BY fcl.changed_at DESC;
```

## Agent Behavior Guidelines

### When to Question Facts

**NEVER question** facts with:
- `durability='permanent'`
- `source_entity_id=2` (I)ruid) via entity_fact_sources
- High `extraction_count` and `confidence`

**DO question** facts from:
- Unknown or low-trust sources
- Low confidence (<0.7)
- Conflicting with high-confidence facts

### Example Agent Logic

```python
def should_question_fact(fact):
    # Never question authority facts
    if fact['durability'] == 'permanent':
        return False
    
    if fact['source_entity_id'] == 2:         # I)ruid (via entity_fact_sources join)
        return False
    
    # Question low-confidence facts from others
    if fact['confidence'] < 0.7:
        return True
    
    return False
```

## Future Enhancements

Potential improvements for future issues:

1. **Multiple Authority Entities**: Support authority hierarchy or domains
2. **Time-based Authority**: Authority expires after certain time
3. **Domain-specific Authority**: Entity is authority for specific topics only
4. **Authority Delegation**: Authority can delegate sub-authorities
5. **Confidence Boost**: Facts confirmed by authority get confidence boost even if not permanent

## Related Issues

- **#43**: Source authority (this feature, original implementation via grammar_parser)
- **#44**: Agent questioning logic (uses authority rules)
- **#45**: Decay exemptions (permanent facts don't decay)

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTHORITY_ENTITY_ID` | `2` | Entity ID of authority (I)ruid) |
| `SENDER_NAME` | (auto-detected) | Name of message sender (used to lookup entity) |
| `SENDER_ID` | — | Unique sender ID (phone number, UUID) |

### Durability Levels (`durability` column)

| Level | Description | Decay | Authority |
|-------|-------------|-------|-----------|
| `permanent` | Never decays | No | Yes (always) |
| `long_term` | Core identity/preference facts | Slow | Maybe |
| `short_term` | Time-sensitive observations | Fast | Rarely |
| `ephemeral` | Transient, quickly forgotten | Fastest | No |

### Category Usage (`category` column, free-form)

Categories replace the old `data_type` enum with free-form text. Common values:
- `identity` — Core identity facts
- `preference` — User preferences
- `observation` — General observations
- `temporal` — Time-sensitive information

## Troubleshooting

### Authority Not Detected

**Check**:
1. Is `SENDER_NAME` set correctly?
2. Does the sender match entity name or nickname?
3. Run: `SELECT id, name, nicknames FROM entities WHERE id = 2;`

### Fact Not Marked Permanent

**Check**:
1. Is authority detection working? Look for `[AUTHORITY]` in logs
2. Is `AUTHORITY_ENTITY_ID` set correctly?
3. Run: `psql -d nova_memory -c "SELECT id, name FROM entities LIMIT 10;"`

### Non-Authority Override Succeeded

**Check**:
1. Was the existing fact from authority? Check `entity_fact_sources.source_entity_id`
2. Was confidence higher? Check `confidence` values
3. Review the memory maintenance logs

## Support

For issues or questions:
- GitHub: https://github.com/NOVA-Openclaw/nova-mind/issues/43
- Logs: Check gateway logs for extract/store output
- Database: Query `entity_facts` table
