# Integration Guide: Grammar Parser → Memory System

How to integrate the grammar-based parser with the existing memory extraction pipeline.

## Architecture Overview

```
Signal Message
    ↓
memory-extract hook
    ↓
┌──────────────────────────────────┐
│   Grammar Parser (NEW)           │
│   - Fast, deterministic          │
│   - Extracts common patterns     │
│   - Returns high-confidence      │
│     relations                    │
└───────────┬──────────────────────┘
            ↓
    Confidence ≥ 0.7?
       ↙        ↘
     Yes         No
      ↓           ↓
   Store      LLM Extraction
  Directly    (existing system)
      ↓           ↓
      └─────┬─────┘
            ↓
     Memory Database
    (entity_facts,
   entity_relationships)
```

---

## Current System

**Location:** `~/.openclaw/workspace/nova-memory/hooks/memory-extract/`

**Current Flow:**
1. Hook triggered by Signal messages
2. Messages sent to `extract-memories.sh`
3. Script calls Claude API with extraction prompt
4. Returns JSON with facts, events, preferences
5. Stored in `entity_facts` and `entity_relationships` tables

**Scripts:**
- `~/.openclaw/workspace/scripts/extract-memories.sh` - Main extraction script
- Prompt defined inline (long system prompt)

---

## Integration Options

### Option 1: Pre-processing Step (Recommended)

Add grammar parser as **first stage** before LLM:

```bash
#!/bin/bash
# extract-memories.sh (modified)

MESSAGE="$1"

# NEW: Grammar-based extraction
GRAMMAR_RELATIONS=$(python ~/.openclaw/workspace/nova-memory/grammar_parser/extract_cli.py "$MESSAGE")

# Check if high-confidence relations found
if [ -n "$GRAMMAR_RELATIONS" ]; then
    echo "$GRAMMAR_RELATIONS" | python store_relations.py
    
    # If all relations extracted with high confidence, skip LLM
    CONFIDENCE=$(echo "$GRAMMAR_RELATIONS" | jq '[.[] | .confidence] | add / length')
    
    if (( $(echo "$CONFIDENCE >= 0.8" | bc -l) )); then
        echo "High-confidence extraction complete (grammar-based)"
        exit 0
    fi
fi

# Fall back to LLM for complex/low-confidence cases
# ... existing LLM call ...
```

---

### Option 2: Parallel Extraction + Merge

Run **both** grammar parser and LLM, then merge:

```python
# Pseudo-code
grammar_relations = grammar_parser.parse(message)
llm_relations = llm_extract(message)

# Merge, preferring grammar when confidence is high
merged = []
for g_rel in grammar_relations:
    if g_rel.confidence >= 0.7:
        merged.append(g_rel)
    else:
        # Check if LLM found similar relation
        llm_match = find_similar(g_rel, llm_relations)
        if llm_match:
            merged.append(llm_match)  # Prefer LLM's version
        else:
            merged.append(g_rel)

# Add LLM-only relations
for llm_rel in llm_relations:
    if not any(similar(llm_rel, m) for m in merged):
        merged.append(llm_rel)

store_relations(merged)
```

**Pros:** Most accurate, combines strengths of both
**Cons:** Higher cost (still calls LLM every time)

---

### Option 3: Grammar-Only Mode (Dev/Testing)

Completely replace LLM for testing:

```bash
# extract-memories-grammar-only.sh
MESSAGE="$1"

python ~/.openclaw/workspace/nova-memory/grammar_parser/extract_cli.py "$MESSAGE" | \
    python store_relations.py
```

Use for development and cost-free testing.

---

## Implementation Steps

### Step 1: Create CLI Wrapper

**File:** `~/.openclaw/workspace/nova-memory/grammar_parser/extract_cli.py`

```python
#!/usr/bin/env python3
"""
CLI wrapper for grammar parser.
Takes message text, outputs JSON relations.
"""

import sys
import json
from grammar_parser import parse_sentence

def main():
    if len(sys.argv) < 2:
        print("Usage: extract_cli.py <message_text>", file=sys.stderr)
        sys.exit(1)
    
    message = sys.argv[1]
    
    # Parse message
    relations = parse_sentence(message)
    
    # Convert to JSON
    output = [rel.to_dict() for rel in relations]
    
    # Output JSON
    print(json.dumps(output, indent=2))

if __name__ == "__main__":
    main()
```

**Make executable:**
```bash
chmod +x ~/.openclaw/workspace/nova-memory/grammar_parser/extract_cli.py
```

---

### Step 2: Create Relation Storage Script

**File:** `~/.openclaw/workspace/nova-memory/grammar_parser/store_relations.py`

```python
#!/usr/bin/env python3
"""
Store relations in memory database.
Reads JSON from stdin, writes to entity_facts and entity_relationships.
"""

import sys
import json
from typing import List, Dict

# Import your database module
# from nova_memory.db import store_relation, get_or_create_entity


def store_relation(relation: Dict):
    """Store a single relation in the database."""
    
    rel_type = relation["relation_type"]
    subject = relation["subject"]
    obj = relation["object"]
    predicate = relation["predicate"]
    
    # Map relation types to database tables/fields
    
    if rel_type in ["family", "romantic", "social", "professional"]:
        # Store in entity_relationships
        # subject_entity = get_or_create_entity(subject)
        # object_entity = get_or_create_entity(obj)
        # create_relationship(subject_entity, object_entity, predicate)
        print(f"Would store relationship: {subject} --{predicate}--> {obj}")
    
    elif rel_type in ["attribute", "preference", "opinion"]:
        # Store in entity_facts
        # entity = get_or_create_entity(subject)
        # create_fact(entity, key=predicate, value=obj)
        print(f"Would store fact: {subject}.{predicate} = {obj}")
    
    elif rel_type in ["location", "residence", "origin"]:
        # Store as entity fact (location)
        # entity = get_or_create_entity(subject)
        # create_fact(entity, key="location", value=obj)
        print(f"Would store location: {subject} @ {obj}")
    
    elif rel_type in ["employment", "education"]:
        # Store as entity fact
        # entity = get_or_create_entity(subject)
        # create_fact(entity, key=rel_type, value=obj)
        print(f"Would store {rel_type}: {subject} @ {obj}")
    
    else:
        # Generic storage
        print(f"Would store other: {subject} --{predicate}--> {obj}")


def main():
    # Read JSON from stdin
    input_json = sys.stdin.read()
    
    if not input_json.strip():
        print("No relations to store", file=sys.stderr)
        sys.exit(0)
    
    try:
        relations = json.loads(input_json)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Store each relation
    for rel in relations:
        try:
            store_relation(rel)
        except Exception as e:
            print(f"Error storing relation: {e}", file=sys.stderr)
    
    print(f"Stored {len(relations)} relation(s)", file=sys.stderr)


if __name__ == "__main__":
    main()
```

**Note:** Replace print statements with actual database calls using your DB schema.

---

### Step 3: Modify memory-extract Hook

**Original:** `~/.openclaw/workspace/nova-memory/hooks/memory-extract/hook.sh`

**Add grammar parser stage:**

```bash
#!/bin/bash
# memory-extract hook (modified)

MESSAGE_FILE="$1"
MESSAGE=$(cat "$MESSAGE_FILE")

# Grammar-based extraction
GRAMMAR_OUTPUT=$(python ~/.openclaw/workspace/nova-memory/grammar_parser/extract_cli.py "$MESSAGE" 2>&1)

if [ $? -eq 0 ] && [ -n "$GRAMMAR_OUTPUT" ]; then
    echo "$GRAMMAR_OUTPUT" | python ~/.openclaw/workspace/nova-memory/grammar_parser/store_relations.py
    
    # Calculate average confidence
    AVG_CONFIDENCE=$(echo "$GRAMMAR_OUTPUT" | jq '[.[] | .confidence] | add / length' 2>/dev/null)
    
    # If high confidence, skip LLM
    if (( $(echo "$AVG_CONFIDENCE >= 0.75" | bc -l 2>/dev/null) )); then
        echo "Grammar extraction complete (confidence: $AVG_CONFIDENCE)"
        exit 0
    fi
fi

# Fall back to existing LLM extraction
exec ~/.openclaw/workspace/scripts/extract-memories.sh "$MESSAGE"
```

---

### Step 4: Database Schema Mapping

Map relation types to existing database schema:

#### entity_relationships Table
**Store:** Family, romantic, social, professional relations

```python
relation_type = "family"
subtype = "sibling"  # brother, sister, etc.

# Insert
INSERT INTO entity_relationships (
    entity_a, entity_b, relationship, is_symmetric
) VALUES (
    get_entity_id(subject),
    get_entity_id(object),
    subtype,
    True  # siblings are symmetric
)
```

#### entity_facts Table
**Store:** Attributes, preferences, locations, employment

```python
relation_type = "preference"
predicate = "loves"
object = "pizza"

# Insert
INSERT INTO entity_facts (
    entity_id, key, value
) VALUES (
    get_entity_id(subject),
    'preference',
    json.dumps({"predicate": "loves", "object": "pizza"})
)
```

#### entities Table
**Create entities** from subject/object if not exists:

```python
def get_or_create_entity(name: str) -> int:
    # Check if entity exists
    entity = db.query("SELECT id FROM entities WHERE name = ?", name)
    if entity:
        return entity.id
    
    # Create new entity
    return db.insert("INSERT INTO entities (name) VALUES (?)", name)
```

---

## Testing Integration

### 1. Unit Test Storage Script

```bash
echo '[{
  "subject": "John",
  "predicate": "loves",
  "object": "pizza",
  "relation_type": "preference",
  "confidence": 0.95
}]' | python store_relations.py
```

### 2. Test CLI Wrapper

```bash
python extract_cli.py "John loves pizza"
```

Expected output:
```json
[
  {
    "subject": "John",
    "predicate": "love",
    "object": "pizza",
    "relation_type": "preference",
    "confidence": 0.85,
    ...
  }
]
```

### 3. Test Full Pipeline

```bash
echo "Sarah works at Google and lives in Austin" | \
    ./extract_cli.py | \
    ./store_relations.py
```

Should extract and store:
- Employment: Sarah @ Google
- Residence: Sarah @ Austin

---

## Performance Optimization

### Batch Processing

For multiple messages, batch parse:

```python
# batch_extract.py
messages = [msg1, msg2, msg3, ...]

parser = GrammarParser()  # Load spaCy once

all_relations = []
for msg in messages:
    relations = parser.parse_sentence(msg)
    all_relations.extend(relations)

# Batch store
store_relations_batch(all_relations)
```

### Caching

Cache parsed messages to avoid re-parsing:

```python
import hashlib
import json
from functools import lru_cache

@lru_cache(maxsize=1000)
def parse_cached(message: str) -> str:
    relations = parse_sentence(message)
    return json.dumps([r.to_dict() for r in relations])
```

---

## Monitoring & Metrics

Track grammar parser effectiveness:

```sql
-- Create metrics table
CREATE TABLE extraction_metrics (
    id INTEGER PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    method TEXT,  -- 'grammar' or 'llm'
    num_relations INTEGER,
    avg_confidence REAL,
    processing_time_ms INTEGER
);

-- Insert metrics
INSERT INTO extraction_metrics (
    method, num_relations, avg_confidence, processing_time_ms
) VALUES (
    'grammar', 3, 0.87, 45
);
```

**Dashboard queries:**

```sql
-- Grammar vs LLM usage
SELECT method, COUNT(*) as count, AVG(avg_confidence) as avg_conf
FROM extraction_metrics
GROUP BY method;

-- Cost savings
-- (Assume LLM costs $0.01 per extraction)
SELECT 
    SUM(CASE WHEN method = 'grammar' THEN 1 ELSE 0 END) * 0.01 as cost_saved,
    COUNT(*) * 0.01 as total_cost_without_grammar
FROM extraction_metrics;
```

---

## Fallback Strategy

When grammar parser fails or has low confidence:

```python
def extract_with_fallback(message: str) -> List[Relation]:
    # Try grammar first
    relations = parse_sentence(message)
    
    # Check if sufficient
    if not relations or avg_confidence(relations) < 0.6:
        # Fall back to LLM
        llm_relations = llm_extract(message)
        return llm_relations
    
    return relations
```

---

## Debugging

Enable verbose logging:

```python
# In grammar_parser.py
import logging

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# In extraction functions
logger.debug(f"Extracting from: {doc}")
logger.debug(f"Found subject: {subject}, object: {obj}")
```

**Log to file:**

```bash
python extract_cli.py "message" 2>> extraction.log
```

---

## Deployment Checklist

- [ ] Install spaCy and download model: `python -m spacy download en_core_web_sm`
- [ ] Make CLI scripts executable: `chmod +x extract_cli.py store_relations.py`
- [ ] Test grammar parser independently
- [ ] Test storage script with mock data
- [ ] Integrate into memory-extract hook
- [ ] Test end-to-end with sample messages
- [ ] Monitor metrics for first 100 extractions
- [ ] Compare cost/accuracy with LLM-only approach
- [ ] Adjust confidence thresholds based on results

---

## Future Enhancements

1. **Anaphora Resolution**
   - Track entities across sentences
   - Resolve pronouns to previous mentions

2. **Context-Aware Extraction**
   - Use conversation history for disambiguation
   - Track speaker identities in multi-party chats

3. **Hybrid Confidence Scoring**
   - Combine grammar confidence + LLM verification
   - Use LLM to re-rank grammar-extracted relations

4. **Relation Deduplication**
   - Merge similar relations across messages
   - Update existing relations rather than duplicate

5. **Active Learning**
   - Flag uncertain extractions for human review
   - Improve patterns based on feedback

---

## Support

Questions? Check:
- `GRAMMAR_RULES.md` - Detailed pattern documentation
- `tests/` - Example usage and test cases
- Task spec: `~/.openclaw/workspace/docs/tasks/grammar-parsing-rules-for-memory-extraction.md`
