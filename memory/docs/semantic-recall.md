# Semantic Recall System

Automatic context injection based on semantic similarity search.

## Overview

The semantic recall system searches embedded memories when messages arrive and injects relevant context before the agent processes the message. This enables meaning-based recall ("what did we discuss about X") rather than keyword matching.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Incoming        │────▶│ Embed Query      │────▶│ Vector Search   │
│ Message         │     │ (OpenAI)         │     │ (pgvector)      │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
┌─────────────────┐     ┌──────────────────┐              │
│ Agent Context   │◀────│ Format & Inject  │◀─────────────┘
│ (with memories) │     │ (token budget)   │
└─────────────────┘     └──────────────────┘
```

## Components

### proactive-recall.py

Main search script with configurable limits:

```bash
# Basic usage
python proactive-recall.py "search query"

# With token budget
python proactive-recall.py "query" --max-tokens 500

# Formatted for injection
python proactive-recall.py "query" --inject
```

**Configuration:**
- `--max-tokens` - Maximum tokens to return (default: 1000)
- `--threshold` - Minimum similarity score (default: 0.4)
- `--high-confidence` - Threshold for full vs summary content (default: 0.7)

### Hook (semantic-recall/)

OpenClaw hook that runs on `message:received`:
1. Receives incoming message
2. Resolves sender to entity (phone/UUID lookup)
3. Runs semantic search
4. Injects entity profile + relevant memories

**Environment Variables:**
- `SEMANTIC_RECALL_TOKEN_BUDGET` - Max injection tokens (default: 1000)
- `SEMANTIC_RECALL_HIGH_CONFIDENCE` - Full content threshold (default: 0.7)

## Features

### 1. Token Budget Control

Prevents context window overconsumption by limiting total injected tokens:

```python
result = recall(message, token_budget=1000)
# Returns: {"memories": [...], "tokens_used": 450, "token_budget": 1000}
```

### 2. Tiered Retrieval

Different detail levels based on match confidence:

| Similarity | Content | Indicator |
|------------|---------|-----------|
| ≥ 0.7 | Full content (300-600 chars) | 🎯 |
| < 0.7 | Summary only (100-200 chars) | 📝 |

### 3. Dynamic Content Limits

Content length scales based on result count:

| Results | Summary | Full |
|---------|---------|------|
| 1-2 | ~200 chars | ~600 chars |
| 5-6 | ~150 chars | ~450 chars |
| 9-10 | ~100 chars | ~300 chars |

This efficiently distributes the token budget — fewer results get more detail.

### 4. Entity Resolution

Integrates with entity-resolver to identify message senders and inject their profile:

```
👤 **Talking with:** I)ruid
• **Timezone:** America/Chicago
• **Communication Style:** Direct, technical
```

## Database Schema

Requires `memory_embeddings` table with pgvector:

```sql
CREATE TABLE memory_embeddings (
    id SERIAL PRIMARY KEY,
    source_type VARCHAR(50) NOT NULL,
    source_id TEXT,
    content TEXT NOT NULL,
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- IVFFlat index (optional, only for > 1000 embeddings)
-- Do NOT create this on new installs - it breaks queries with < 1000 rows
-- See INSTALLATION.md for details on when to add this
-- CREATE INDEX idx_memory_embeddings_vector 
-- ON memory_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists='100');
```

## Integration

To use in an OpenClaw installation:

1. Copy `scripts/proactive-recall.py` to your scripts directory
2. Copy `hooks/semantic-recall/` to your hooks directory
3. Ensure pgvector extension and memory_embeddings table exist
4. Set OPENAI_API_KEY environment variable

## OpenClaw Session Memory Indexing (2026.2.6+)

OpenClaw 2026.2.6 includes native session memory indexing that complements the semantic recall system. This feature indexes session transcripts for semantic search, enabling recall of conversations across compactions.

### Configuration

Add to `~/.openclaw/openclaw.json`:

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "experimental": {
          "sessionMemory": true
        },
        "sources": ["memory", "sessions"]
      }
    }
  }
}
```

### What It Does

- **Session JSONL indexing**: Transcripts in `~/.openclaw/agents/<id>/sessions/*.jsonl` are indexed with embeddings
- **Unified search**: `memory_search` queries both `memory/*.md` AND session transcripts
- **Background sync**: Delta-based updates (~100KB or ~50 messages triggers re-index)
- **Cross-compaction recall**: Ask "what did we discuss last week?" and get results

### How It Works

```
Session Transcript (JSONL)
    ↓
Delta threshold reached (~100KB / ~50 msgs)
    ↓
Background indexing (embeddings generated)
    ↓
Stored in per-agent SQLite index
    ↓
memory_search queries both memory + sessions
```

### Relationship to NOVA Memory

This OpenClaw feature is **complementary** to the NOVA Memory database:

| Feature | NOVA Memory DB | OpenClaw Session Index |
|---------|---------------|----------------------|
| Storage | PostgreSQL + pgvector | SQLite + embeddings |
| Content | Curated facts, entities, events | Raw session transcripts |
| Extraction | Explicit (memory-extract hook) | Automatic (all turns) |
| Query | `proactive-recall.py`, direct SQL | `memory_search` tool |

**Best practice**: Use both. NOVA Memory for structured, curated knowledge. OpenClaw session indexing for conversational context and recall.

### Enabling (NOVA Installation)

Enabled 2026-02-08. Config applied via:

```bash
# Using gateway config.patch
gateway config.patch '{
  "agents": {
    "defaults": {
      "memorySearch": {
        "experimental": { "sessionMemory": true },
        "sources": ["memory", "sessions"]
      }
    }
  }
}'
```

Gateway restarts automatically after config patch.

---

*Part of the NOVA Memory project — an agent-agnostic memory system.*
