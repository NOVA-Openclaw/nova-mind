# Source Authority

## Overview

The source authority feature ensures that facts from designated authority entities (e.g., I)ruid) are treated as permanent, authoritative, and immune to being overridden by non-authority sources.

> **Note:** The original grammar parser (`grammar_parser/`) that implemented this feature has been removed (#174). Authority detection and conflict resolution now follow the patterns described below, implemented in `store-memories.sh`, `confidence_helper.py`, and `memory-maintenance.py`.

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

## Implementation

### Current Architecture

Source authority is a cross-cutting concern implemented across multiple components:

#### `confidence_helper.py`

Calculates confidence scores based on source authority:

- Authority sources get confidence = 1.0
- Non-authority sources get confidence scaled by entity trust level and source type
- Used by `store-memories.sh` to set initial confidence on new facts

#### `memory-maintenance.py`

Enforces authority rules during maintenance operations:

- Permanent facts (`durability = 'permanent'`) are excluded from confidence decay
- Authority facts are never archived or cleaned up
- Non-authority facts with conflicting values are evaluated against existing authority facts

#### `store-memories.sh`

Handles conflict resolution at insertion time:

- Checks if the source is an authority entity via `SENDER_NAME` or entity ID lookup
- Sets `durability='permanent'` for authority-sourced facts
- Rejects non-authority insertions that conflict with existing authority facts
- Increments `extraction_count` when authority confirms an existing fact

### Database Schema

The following columns support authority enforcement:

- `entity_fact_sources.source_entity_id` — Tracks which entity provided the fact (via entity_fact_sources join)
- `entity_facts.durability` — Supports 'permanent', 'long_term', 'short_term', 'ephemeral'
- `entity_facts.category` — Free-form text replacing data_type (e.g., 'identity', 'preference', 'observation')
- `entity_facts.confidence` — Authority facts set to 1.0
- `entity_facts.extraction_count` — Incremented when fact is confirmed
- `entity_facts.last_confirmed_at` — Updated when fact is re-stated

### Authority Detection Flow

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

## Usage

### Basic Usage

Authority is automatically detected in `store-memories.sh` based on `SENDER_NAME` environment variable:

```bash
# I)ruid states a fact (automatically becomes permanent via Claude extraction → store)
SENDER_NAME="I)ruid" ./scripts/process-input.sh "My preferred name is I)ruid"
```

### Configurable Authority Entity

Override the default authority entity:

```bash
# Use entity_id=5 as authority instead of 2
export AUTHORITY_ENTITY_ID=5
export SENDER_NAME="CustomAuthority"
./scripts/process-input.sh "A fact from this authority"
```

## Testing

Run the test suite:

```bash
cd ~/.openclaw/workspace/nova-mind
./tests/test_authority_facts.sh
```

**Test Coverage**:
1. Authority fact insertion (new fact)
2. Authority fact confirmation (same value)
3. Authority fact override (conflicting value)
4. Non-authority cannot override authority fact
5. Configurable authority entity

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
