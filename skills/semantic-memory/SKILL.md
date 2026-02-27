---
name: semantic-memory
description: Implement semantic search over agent memory using vector embeddings. Use when building AI memory systems, enabling meaning-based recall, or setting up proactive context retrieval. Covers PostgreSQL pgvector, OpenAI embeddings, and memory search patterns.
---

# Semantic Memory System

## Overview

Enable meaning-based search across agent memory using vector embeddings. Query by concept, not just keywords.

## Quick Start

Search memory semantically:
```bash
source ~/.openclaw/workspace/scripts/tts-venv/bin/activate
python ~/.openclaw/workspace/scripts/proactive-recall.py "user's question here"
```

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Source Content  │────▶│ Embed (OpenAI)   │────▶│ memory_embeddings│
│ (markdown, DB)  │     │ text-embedding-3 │     │ (pgvector)      │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
┌─────────────────┐     ┌──────────────────┐              │
│ Search Results  │◀────│ Cosine Similarity│◀─────────────┘
└─────────────────┘     └──────────────────┘
```

## Database Schema

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE memory_embeddings (
    id SERIAL PRIMARY KEY,
    source_type VARCHAR(50) NOT NULL,  -- 'daily_log', 'lesson', 'entity', etc.
    source_id TEXT,                     -- Reference to source record
    content TEXT NOT NULL,              -- The text that was embedded
    embedding vector(1536),             -- OpenAI text-embedding-3-small
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- WARNING: Only create IVFFlat index after you have > 1000 embeddings
-- With < 1000 rows, IVFFlat breaks queries and returns 0-1 results
-- Exact search (no index) is fast enough for < 1000 rows
-- See INSTALLATION.md for details on when to add this
-- CREATE INDEX idx_memory_embeddings_vector 
-- ON memory_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

## Embedding Content

```python
import os
import openai
from psycopg2 import connect

# Database name is dynamic: ${USER//-/_}_memory (e.g., nova_memory, argus_memory)
# Uses PG* environment variables set by ~/.openclaw/lib/pg_env.py or pg-env.sh
def get_db_name() -> str:
    return os.environ.get("PGDATABASE", f"{os.environ.get('USER', 'nova').replace('-', '_')}_memory")

def embed_and_store(content: str, source_type: str, source_id: str):
    # Generate embedding
    response = openai.embeddings.create(
        model="text-embedding-3-small",
        input=content
    )
    embedding = response.data[0].embedding
    
    # Store in PostgreSQL (reads PGHOST, PGUSER, PGDATABASE, PGPASSWORD from environment)
    conn = connect(dbname=get_db_name())
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO memory_embeddings (source_type, source_id, content, embedding)
        VALUES (%s, %s, %s, %s)
    """, (source_type, source_id, content, embedding))
    conn.commit()
```

## Semantic Search

```python
def search_memory(query: str, limit: int = 5) -> list:
    # Embed the query
    response = openai.embeddings.create(
        model="text-embedding-3-small",
        input=query
    )
    query_embedding = response.data[0].embedding
    
    # Find similar content (reads PG* env vars set by pg_env.py / pg-env.sh)
    conn = connect(dbname=get_db_name())
    cur = conn.cursor()
    cur.execute("""
        SELECT source_type, source_id, content,
               1 - (embedding <=> %s::vector) as similarity
        FROM memory_embeddings
        ORDER BY embedding <=> %s::vector
        LIMIT %s
    """, (query_embedding, query_embedding, limit))
    
    return cur.fetchall()
```

## What to Embed

Good candidates for embedding:
- Daily logs and notes
- Lessons learned
- Entity facts and relationships
- Project context
- Conversation summaries
- SOPs and procedures

## Integration Pattern

For proactive recall before answering questions:
1. Embed the user's question
2. Search memory_embeddings for relevant context
3. Include top results in agent context
4. Answer with enriched knowledge
