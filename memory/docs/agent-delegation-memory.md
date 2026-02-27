# Agent Delegation as Memory

## Problem Statement

Agent delegation is CORE to how NOVA operates, but it was previously handled as runtime hints (keyword matching). This is fragile and doesn't learn from experience. 

**New approach:** Agent delegation knowledge lives in the memory system and is surfaced through semantic recall.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    DELEGATION MEMORY FLOW                        │
├─────────────────────────────────────────────────────────────────┤
│  1. SEED DATA                                                    │
│     Agent roster → entity_facts (role, skills, purpose)          │
│     Initial delegation patterns from agents table                │
├─────────────────────────────────────────────────────────────────┤
│  2. EXPERIENCE EXTRACTION                                        │
│     Conversations → memory-extract.sh recognizes:                │
│     - "Let me get Coder to help with this"                       │
│     - "Coder fixed the bug in the parser"                        │
│     - "Scout found that information about..."                    │
│     → Stores as entity_facts: who did what, success/failure      │
├─────────────────────────────────────────────────────────────────┤
│  3. SEMANTIC RECALL                                              │
│     Query: "How do I fix this code?"                             │
│     → Semantic search surfaces: "Coder handles coding tasks"     │
│     → Agent sees delegation knowledge as context                 │
├─────────────────────────────────────────────────────────────────┤
│  4. CONTINUOUS LEARNING                                          │
│     Over time, facts accumulate:                                 │
│     - Coder is good at Python debugging                          │
│     - Gidget handles git operations reliably                     │
│     - Scout excels at research queries                           │
└─────────────────────────────────────────────────────────────────┘
```

## Schema Design

### entity_facts Storage

Agent delegation knowledge is stored as `entity_facts` for NOVA (entity_id=1):

```sql
-- Agent relationships
INSERT INTO entity_facts (entity_id, key, value, category, confidence, data_type) VALUES
(1, 'delegates_to', 'Coder for coding tasks', 'delegation', 1.0, 'permanent'),
(1, 'delegates_to', 'Gidget for git operations', 'delegation', 1.0, 'permanent'),
(1, 'delegates_to', 'Scout for research', 'delegation', 1.0, 'permanent');

-- Agent capabilities (learned from experience)
INSERT INTO entity_facts (entity_id, key, value, category, confidence, data_type) VALUES
(1, 'agent_capability', 'Coder: excellent at Python debugging', 'delegation', 0.9, 'observation'),
(1, 'agent_capability', 'Gidget: reliable for git operations', 'delegation', 0.95, 'observation'),
(1, 'agent_success', 'Scout successfully researched X topic on YYYY-MM-DD', 'delegation', 1.0, 'observation');
```

### memory_embeddings Integration

Delegation facts are embedded for semantic recall:

```sql
INSERT INTO memory_embeddings (source_type, source_id, content, confidence)
SELECT 
    'entity_fact' as source_type,
    'entity_' || entity_id || '_fact_' || id as source_id,
    'NOVA delegates to ' || value as content,
    confidence
FROM entity_facts
WHERE entity_id = 1 AND category = 'delegation';
```

## Implementation Components

### 1. Seed Script (`scripts/seed-delegation-knowledge.sql`)

Populates initial delegation knowledge from the agents table:

- Agent roster with roles
- Basic capabilities from agent descriptions
- Foundational "delegates_to" relationships

### 2. Memory Extractor Enhancement (`scripts/extract-memories.sh`)

Updated prompt to recognize delegation patterns:

```text
DELEGATION CONTEXT:
When NOVA says things like:
- "Let me get Coder to help"
- "I'll delegate this to Scout"
- "Coder fixed the bug"
- "Gidget pushed the changes"

Extract as entity_facts:
- delegates_to: "AGENT_NAME for TASK_TYPE"
- agent_capability: "AGENT_NAME: description of what they did well"
- agent_success/agent_failure: outcome observations

Include the agent name in the value field for searchability.
```

### 3. Embedding Sync (`scripts/embed-delegation-facts.sh`)

Ensures delegation facts are embedded for semantic search:

- Runs after seed or after fact insertion
- Generates embeddings for category='delegation' facts
- Stores in memory_embeddings table

### 4. Semantic Recall (proactive-recall.py - already exists)

No changes needed! Existing semantic recall will surface delegation knowledge when queries are task-related.

Query: "How do I fix this code?"
→ Embedding matches "NOVA delegates to Coder for coding tasks"
→ Context injected with agent info

## Usage Examples

### Seeding Initial Knowledge

```bash
cd ~/.openclaw/workspace/nova-memory
psql -f scripts/seed-delegation-knowledge.sql  # Uses PG* env vars from ~/.openclaw/lib/pg-env.sh
./scripts/embed-delegation-facts.sh
```

### Extracting Delegation from Conversations

```bash
# Hook automatically runs on message:received
# Or manually:
echo "[USER] Can you fix this bug in the code?
[NOVA] Let me get Coder to help with that." | \
SENDER_NAME="I)ruid" ./scripts/extract-memories.sh
```

### Querying Delegation Knowledge

```sql
-- What can NOVA delegate?
SELECT value FROM entity_facts 
WHERE entity_id = 1 AND key = 'delegates_to'
ORDER BY confidence DESC;

-- What has Coder done successfully?
SELECT value FROM entity_facts
WHERE entity_id = 1 
  AND category = 'delegation'
  AND value LIKE '%Coder%'
ORDER BY learned_at DESC
LIMIT 10;
```

### Semantic Search for Delegation

```bash
# Will surface relevant agent info
python3 ~/.openclaw/workspace/nova-memory/scripts/proactive-recall.py "I need help debugging this Python code"
# → Returns: "NOVA delegates to Coder for coding tasks"
```

## Benefits Over Hook Approach

| Hook Approach | Memory Approach |
|---------------|-----------------|
| Keyword matching (fragile) | Semantic matching (robust) |
| Static patterns | Learns from experience |
| No context awareness | Full conversational context |
| Can't improve over time | Accumulates expertise knowledge |
| Runtime-only | Persists across sessions |

## Maintenance

### Regular Tasks

1. **Weekly**: Review delegation facts for outdated info
2. **Monthly**: Re-embed facts if confidence scores change significantly
3. **Continuous**: Memory extractor automatically captures new delegation patterns

### Cleanup Query

```sql
-- Remove low-confidence delegation facts older than 90 days
DELETE FROM entity_facts
WHERE category = 'delegation'
  AND confidence < 0.5
  AND learned_at < NOW() - INTERVAL '90 days';
```

## Migration from Hooks

The existing `agent-delegation-hints` hook can be:

1. **Kept temporarily** for immediate runtime hints while memory builds
2. **Gradually deprecated** as memory accumulates delegation knowledge
3. **Removed** once semantic recall reliably surfaces agent info

No breaking changes — both systems can coexist during transition.

---

**Status:** Design complete, ready for implementation  
**Next Steps:** 
1. Create seed script
2. Update memory extractor prompt
3. Create embedding sync script
4. Test with sample queries
