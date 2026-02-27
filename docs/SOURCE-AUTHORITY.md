# Source Authority (Issue #43)

## Overview

The source authority feature ensures that facts from designated authority entities (e.g., I)ruid) are treated as permanent, authoritative, and immune to being overridden by non-authority sources.

## Key Concepts

### Authority Entity

- **Default Authority**: Entity ID 2 (I)ruid / Dustin Trammell)
- **Configurable**: Set via `AUTHORITY_ENTITY_ID` environment variable
- **Identification**: Matched by entity name or any nickname

### Authority Rules

1. **Permanent Facts**: All facts from authority entities are marked `data_type='permanent'`
2. **Confidence Override**: Authority facts always have `confidence=1.0` regardless of input
3. **Conflict Resolution**:
   - Authority fact vs. non-authority fact → Authority wins
   - Authority fact vs. same value → Increment `vote_count`, update `last_confirmed`
   - Authority fact vs. conflicting authority fact → Update to new value
   - Non-authority vs. authority fact → Rejected with log message

## Implementation

### Modified Files

#### `grammar_parser/store_relations.py`

Enhanced with authority detection and conflict resolution:

```python
def is_authority_entity(entity_id: Optional[int], authority_entity_id: int) -> bool:
    """Check if an entity is the authority entity."""
    return entity_id is not None and entity_id == authority_entity_id
```

**Key Changes**:
- Added `find_entity_id()` to lookup entity ID by name/nickname
- Added `get_existing_fact()` to retrieve existing fact details for conflict resolution
- Modified `store_relation()` to:
  - Detect authority source
  - Set `data_type='permanent'` for authority facts
  - Implement conflict resolution logic
  - Log authority overrides to `fact_change_log` table

### Database Schema

**Existing Schema Support**:
- `entity_facts.source_entity_id` - Tracks which entity provided the fact
- `entity_facts.data_type` - Supports 'permanent', 'identity', 'preference', 'temporal', 'observation'
- `entity_facts.confidence` - Authority facts set to 1.0
- `entity_facts.vote_count` - Incremented when fact is confirmed
- `entity_facts.last_confirmed` - Updated when fact is re-stated

**New Table**:
```sql
CREATE TABLE fact_change_log (
    id SERIAL PRIMARY KEY,
    fact_id INTEGER NOT NULL,
    old_value TEXT,
    new_value TEXT,
    changed_by_entity_id INTEGER,
    reason VARCHAR(100),
    changed_at TIMESTAMPTZ DEFAULT NOW()
);
```

## Usage

### Basic Usage

Authority is automatically detected based on `SENDER_NAME` environment variable:

```bash
# I)ruid states a fact (automatically becomes permanent)
export SENDER_NAME="I)ruid"
echo '[{
    "relation_type": "attribute",
    "subject": "Nova",
    "object": "AI agent",
    "predicate": "type",
    "confidence": 0.9
}]' | ./grammar_parser/run_store.sh
```

Output:
```
[AUTHORITY] Source is authority entity (id=2), setting permanent
+ Fact: Nova.type = AI agent (confidence: 1.00, data_type: permanent) [PERMANENT]
```

### Conflict Resolution Examples

#### Case 1: Authority Confirms Existing Fact
```bash
# I)ruid states the same fact again
# Result: vote_count++, last_confirmed updated
✓ Fact confirmed: Nova.type = AI agent (vote_count++)
```

#### Case 2: Authority Updates Own Fact
```bash
# I)ruid changes the fact
# Result: Value updated, vote_count reset
⚡ AUTHORITY UPDATE: Nova.type: 'AI agent' → 'AI assistant' (authority override)
```

#### Case 3: Non-Authority Tries to Override
```bash
# Someone else tries to change an authority fact
export SENDER_NAME="RandomUser"
# Result: Rejected
✗ Conflict rejected: Nova.type - existing authority fact prevents update
```

#### Case 4: Non-Authority Conflict (No Authority Involved)
```bash
# Higher confidence wins
↻ Fact updated: Nova.type: 'bot' → 'AI agent' (higher confidence: 0.95 > 0.75)
```

### Configurable Authority Entity

Override the default authority entity:

```bash
# Use entity_id=5 as authority instead of 2
export AUTHORITY_ENTITY_ID=5
export SENDER_NAME="CustomAuthority"
./grammar_parser/run_store.sh < input.json
```

## Testing

Run the test suite:

```bash
cd ~/.openclaw/workspace/nova-memory
./tests/test_authority_facts.sh
```

**Test Coverage**:
1. Authority fact insertion (new fact)
2. Authority fact confirmation (same value)
3. Authority fact override (conflicting value)
4. Non-authority cannot override authority fact
5. Change log verification
6. Configurable authority entity

## Logging and Debugging

### Console Output Markers

- `[AUTHORITY]` - Authority source detected
- `[PERMANENT]` - Fact marked as permanent
- `⚡ AUTHORITY UPDATE` - Authority fact overriding existing fact
- `✓ Fact confirmed` - Fact re-stated (vote_count++)
- `✗ Conflict rejected` - Non-authority attempted override
- `↻ Fact updated` - Normal update (higher confidence)

### Database Queries

**Check authority facts**:
```sql
SELECT e.name, ef.key, ef.value, ef.data_type, ef.source_entity_id, ef.confidence
FROM entity_facts ef
JOIN entities e ON e.id = ef.entity_id
WHERE ef.data_type = 'permanent'
ORDER BY ef.updated_at DESC;
```

**View change log**:
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
- `data_type='permanent'`
- `source_entity_id=2` (I)ruid)
- High `vote_count` and `confidence`

**DO question** facts from:
- Unknown or low-trust sources
- Low confidence (<0.7)
- Conflicting with high-confidence facts

### Example Agent Logic

```python
def should_question_fact(fact):
    # Never question authority facts
    if fact['data_type'] == 'permanent':
        return False
    
    if fact['source_entity_id'] == 2:  # I)ruid
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

- **#22**: Grammar parser integration (provides extraction pipeline)
- **#44**: Agent questioning logic (will use authority rules)
- **#45**: Decay exemptions (permanent facts don't decay)

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTHORITY_ENTITY_ID` | `2` | Entity ID of authority (I)ruid) |
| `SENDER_NAME` | `grammar-parser` | Name of message sender (used to lookup entity) |
| `SENDER_ID` | - | Unique sender ID (phone number, UUID) |

### Data Types

| Type | Description | Decay | Authority |
|------|-------------|-------|-----------|
| `permanent` | Never decays | No | Yes (always) |
| `identity` | Core identity facts | Slow | Maybe |
| `preference` | User preferences | Slow | Maybe |
| `temporal` | Time-sensitive | Fast | Rarely |
| `observation` | General observations | Normal | No |

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
3. Run test suite: `./tests/test_authority_facts.sh`

### Non-Authority Override Succeeded

**Check**:
1. Was the existing fact from authority? Check `source_entity_id`
2. Was confidence higher? Check `confidence` values
3. Review `fact_change_log` for reason

## Support

For issues or questions:
- GitHub: https://github.com/NOVA-Openclaw/nova-memory/issues/43
- Logs: Check stderr output from `run_store.sh`
- Database: Query `entity_facts` and `fact_change_log` tables
