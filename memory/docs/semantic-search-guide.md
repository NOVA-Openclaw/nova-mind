# Semantic Search and Embedding System Guide

Nova-memory provides sophisticated semantic search capabilities through vector embeddings, combining PostgreSQL's pgvector extension with OpenAI's embedding models for intelligent content retrieval.

## Overview

The semantic search system enables natural language queries across all stored memories:

```
"Find conversations about pizza places in Brooklyn"
    ↓
OpenAI Embedding API → Vector [1536 dimensions]
    ↓  
PostgreSQL pgvector → Cosine similarity search
    ↓
Ranked results with context and sources
```

**Key capabilities:**
- **Cross-table search** - Query entities, facts, events, and conversations simultaneously
- **Semantic understanding** - "Italian food" matches "pizza" and "pasta" records
- **Contextual ranking** - Recent, high-confidence content ranks higher
- **Source attribution** - Every result links back to original data

## Architecture

### 1. Embedding Storage

```sql
-- Core embedding table
CREATE TABLE memory_embeddings (
    id SERIAL PRIMARY KEY,
    source_type VARCHAR(50), -- 'entity_fact', 'event', 'agent_chat', 'lesson'
    source_id TEXT, -- ID in the source table  
    content TEXT, -- The text that was embedded
    embedding VECTOR(1536), -- OpenAI embedding (1536 dimensions)
    metadata JSONB, -- Additional context (confidence, tags, etc.)
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Vector similarity index (IVFFlat; only create after > 1000 embeddings — see INSTALLATION.md)
CREATE INDEX idx_memory_embeddings_vector
ON memory_embeddings 
USING ivfflat (embedding vector_cosine_ops) WITH (lists='100');
```

### 2. Automatic Embedding Generation

Embeddings are generated automatically via database triggers:

```sql
-- Example trigger for agent_chat table
CREATE FUNCTION embed_chat_message() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO memory_embeddings (source_type, source_id, content)
    VALUES (
        'agent_chat',
        NEW.id::text,
        NEW.sender || ' in #' || NEW.channel || ': ' || NEW.message
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER embed_chat_message_trigger
    AFTER INSERT ON agent_chat
    FOR EACH ROW EXECUTE FUNCTION embed_chat_message();
```

### 3. Batch Embedding Processing

A background service processes embeddings that don't have vectors yet:

```bash
# scripts/generate-embeddings.sh
#!/bin/bash

# Find records without embeddings
psql -t -c "
SELECT id, content FROM memory_embeddings 
WHERE embedding IS NULL 
ORDER BY created_at ASC 
LIMIT 50;" | while IFS='|' read -r id content; do
    
    # Generate embedding via OpenAI API
    embedding=$(curl -s https://api.openai.com/v1/embeddings \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"input\": \"$content\", \"model\": \"text-embedding-3-small\"}" \
        | jq -r '.data[0].embedding | @json')
    
    # Store embedding in database
    psql -c "
        UPDATE memory_embeddings 
        SET embedding = '$embedding'::vector, 
            updated_at = NOW() 
        WHERE id = $id;"
    
    # Rate limiting
    sleep 0.1
done
```

## Search Implementation

### 1. Basic Semantic Search

```sql
-- Function to search memories by natural language query
CREATE OR REPLACE FUNCTION search_memories(
    query_text TEXT,
    limit_results INT DEFAULT 10,
    similarity_threshold FLOAT DEFAULT 0.7
) RETURNS TABLE (
    source_type TEXT,
    source_id TEXT,
    content TEXT,
    similarity FLOAT,
    metadata JSONB
) AS $$
DECLARE
    query_embedding VECTOR(1536);
BEGIN
    -- Generate embedding for query (would need to call OpenAI API)
    -- For now, assume we have the embedding
    
    RETURN QUERY
    SELECT 
        me.source_type,
        me.source_id,
        me.content,
        1 - (me.embedding <=> query_embedding) as similarity,
        me.metadata
    FROM memory_embeddings me
    WHERE me.embedding IS NOT NULL
        AND 1 - (me.embedding <=> query_embedding) > similarity_threshold
    ORDER BY me.embedding <=> query_embedding
    LIMIT limit_results;
END;
$$ LANGUAGE plpgsql;
```

### 2. Enhanced Search with Context

```sql
-- Search with source table joins for rich context
CREATE OR REPLACE VIEW search_results_with_context AS
SELECT 
    me.source_type,
    me.source_id,
    me.content,
    me.metadata,
    -- Join with source tables for additional context
    CASE 
        WHEN me.source_type = 'entity_fact' THEN
            json_build_object(
                'entity_name', e.name,
                'entity_type', e.type,
                'fact_key', ef.key,
                'confidence', ef.confidence
            )
        WHEN me.source_type = 'event' THEN
            json_build_object(
                'event_date', ev.date,
                'participants', ev.participants
            )
        WHEN me.source_type = 'agent_chat' THEN
            json_build_object(
                'sender', ac.sender,
                'channel', ac.channel,
                'timestamp', ac.created_at
            )
    END as context
FROM memory_embeddings me
LEFT JOIN entity_facts ef ON me.source_type = 'entity_fact' AND me.source_id = ef.id::text
LEFT JOIN entities e ON ef.entity_id = e.id
LEFT JOIN events ev ON me.source_type = 'event' AND me.source_id = ev.id::text  
LEFT JOIN agent_chat ac ON me.source_type = 'agent_chat' AND me.source_id = ac.id::text;
```

### 3. Hybrid Search (Semantic + Keyword)

Combine vector similarity with traditional text search:

```sql
CREATE OR REPLACE FUNCTION hybrid_search(
    query_text TEXT,
    limit_results INT DEFAULT 10
) RETURNS TABLE (
    source_type TEXT,
    source_id TEXT, 
    content TEXT,
    semantic_score FLOAT,
    keyword_score FLOAT,
    combined_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    WITH semantic_results AS (
        SELECT me.source_type, me.source_id, me.content,
               1 - (me.embedding <=> get_embedding(query_text)) as sem_score
        FROM memory_embeddings me
        WHERE me.embedding IS NOT NULL
    ),
    keyword_results AS (
        SELECT me.source_type, me.source_id, me.content,
               ts_rank(to_tsvector('english', me.content), 
                       plainto_tsquery('english', query_text)) as key_score
        FROM memory_embeddings me
    )
    SELECT 
        sr.source_type,
        sr.source_id,
        sr.content,
        sr.sem_score,
        kr.key_score,
        -- Weighted combination: 70% semantic, 30% keyword
        (0.7 * sr.sem_score + 0.3 * kr.key_score) as combined_score
    FROM semantic_results sr
    JOIN keyword_results kr USING (source_type, source_id)
    WHERE sr.sem_score > 0.6 OR kr.key_score > 0.1
    ORDER BY combined_score DESC
    LIMIT limit_results;
END;
$$ LANGUAGE plpgsql;
```

## Integration with Memory Extraction

### 1. Automatic Embedding on Extraction

When memories are extracted and stored, they're automatically queued for embedding:

```bash
# In store-memories.sh, after inserting data:

# Check if new entities were created
NEW_ENTITIES=$(psql -t -c "
    SELECT COUNT(*) FROM entities 
    WHERE created_at > NOW() - INTERVAL '1 minute';")

if [ "$NEW_ENTITIES" -gt 0 ]; then
    echo "Queuing $NEW_ENTITIES new entities for embedding generation"
    
    # Trigger embedding generation asynchronously
    ./scripts/generate-embeddings.sh &
fi
```

### 2. Content Formatting for Embeddings

Different content types require different formatting for optimal embeddings:

```sql
-- Entity facts: Include entity context
INSERT INTO memory_embeddings (source_type, source_id, content)
SELECT 
    'entity_fact',
    ef.id::text,
    e.name || ' (' || e.type || ') - ' || ef.key || ': ' || ef.value
FROM entity_facts ef
JOIN entities e ON ef.entity_id = e.id
WHERE ef.id = NEW.id;

-- Events: Include temporal context
INSERT INTO memory_embeddings (source_type, source_id, content)
SELECT
    'event',
    ev.id::text,
    'On ' || ev.date || ': ' || ev.event || 
    CASE WHEN ev.participants IS NOT NULL 
         THEN ' (participants: ' || array_to_string(ev.participants, ', ') || ')'
         ELSE '' END
FROM events ev
WHERE ev.id = NEW.id;

-- Lessons: Include confidence and context  
INSERT INTO memory_embeddings (source_type, source_id, content)
SELECT
    'lesson',
    l.id::text,
    'Lesson (confidence: ' || l.confidence || '): ' || l.lesson ||
    CASE WHEN l.context IS NOT NULL 
         THEN ' Context: ' || l.context 
         ELSE '' END
FROM lessons l  
WHERE l.id = NEW.id;
```

## Search API and Tools

### 1. Command-Line Search Tool

```bash
# scripts/search-memories.sh
#!/bin/bash

QUERY="$1"
LIMIT="${2:-10}"

if [ -z "$QUERY" ]; then
    echo "Usage: $0 'search query' [limit]"
    exit 1
fi

# Generate embedding for query
QUERY_EMBEDDING=$(curl -s https://api.openai.com/v1/embeddings \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"input\": \"$QUERY\", \"model\": \"text-embedding-3-small\"}" \
    | jq -r '.data[0].embedding | @json')

# Search database
psql -c "
SELECT 
    source_type,
    substring(content, 1, 100) as preview,
    ROUND((1 - (embedding <=> '$QUERY_EMBEDDING'::vector))::numeric, 3) as similarity
FROM memory_embeddings
WHERE embedding IS NOT NULL
ORDER BY embedding <=> '$QUERY_EMBEDDING'::vector
LIMIT $LIMIT;
"
```

### 2. Web API Interface

```python
# api/search_api.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import psycopg2
import openai
import json

app = FastAPI()

class SearchRequest(BaseModel):
    query: str
    limit: int = 10
    threshold: float = 0.7

class SearchResult(BaseModel):
    source_type: str
    source_id: str
    content: str
    similarity: float
    context: dict

@app.post("/search", response_model=list[SearchResult])
async def search_memories(request: SearchRequest):
    # Generate query embedding
    response = openai.Embedding.create(
        input=request.query,
        model="text-embedding-3-small"
    )
    query_embedding = response['data'][0]['embedding']
    
    # Search database
    conn = psycopg2.connect(
        host="localhost",
        # use ~/.openclaw/postgres.json or PGDATABASE env var, 
        user="nova",
        password="nova_password"
    )
    
    with conn.cursor() as cur:
        cur.execute("""
            SELECT source_type, source_id, content,
                   1 - (embedding <=> %s::vector) as similarity
            FROM memory_embeddings  
            WHERE embedding IS NOT NULL
              AND 1 - (embedding <=> %s::vector) > %s
            ORDER BY embedding <=> %s::vector
            LIMIT %s
        """, [json.dumps(query_embedding)] * 4 + [request.limit])
        
        results = []
        for row in cur.fetchall():
            results.append(SearchResult(
                source_type=row[0],
                source_id=row[1], 
                content=row[2],
                similarity=row[3],
                context={}  # Would populate from joins
            ))
    
    return results

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

## Advanced Features

### 1. Temporal Decay

Weight results by recency and confidence:

```sql
CREATE OR REPLACE FUNCTION search_with_decay(
    query_text TEXT,
    limit_results INT DEFAULT 10
) RETURNS TABLE (
    source_type TEXT,
    source_id TEXT,
    content TEXT,
    base_similarity FLOAT,
    temporal_weight FLOAT,
    final_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        me.source_type,
        me.source_id,
        me.content,
        1 - (me.embedding <=> get_embedding(query_text)) as base_sim,
        -- Temporal decay: newer content weighted higher
        LEAST(1.0, EXTRACT(EPOCH FROM (NOW() - me.created_at)) / 2592000.0) as temporal,
        -- Combined score with decay
        (1 - (me.embedding <=> get_embedding(query_text))) * 
        EXP(-EXTRACT(EPOCH FROM (NOW() - me.created_at)) / 7776000.0) as final
    FROM memory_embeddings me
    WHERE me.embedding IS NOT NULL
    ORDER BY final DESC
    LIMIT limit_results;
END;
$$ LANGUAGE plpgsql;
```

### 2. Semantic Clustering

Group similar memories for pattern detection:

```sql
-- Find clusters of similar content
WITH similarity_matrix AS (
    SELECT 
        me1.id as id1, me2.id as id2,
        1 - (me1.embedding <=> me2.embedding) as similarity
    FROM memory_embeddings me1
    CROSS JOIN memory_embeddings me2  
    WHERE me1.id < me2.id
      AND me1.embedding IS NOT NULL
      AND me2.embedding IS NOT NULL
      AND 1 - (me1.embedding <=> me2.embedding) > 0.8
)
SELECT 
    id1, id2, similarity,
    me1.content as content1,
    me2.content as content2
FROM similarity_matrix sm
JOIN memory_embeddings me1 ON sm.id1 = me1.id
JOIN memory_embeddings me2 ON sm.id2 = me2.id
ORDER BY similarity DESC;
```

### 3. Multi-Modal Search

Extend to search across different content types with type-specific weighting:

```sql
CREATE OR REPLACE FUNCTION search_by_content_type(
    query_text TEXT,
    preferred_types TEXT[] DEFAULT ARRAY['entity_fact', 'event'],
    limit_results INT DEFAULT 10
) RETURNS TABLE (
    source_type TEXT,
    source_id TEXT,
    content TEXT,
    similarity FLOAT,
    type_boost FLOAT,
    final_score FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        me.source_type,
        me.source_id,
        me.content,
        1 - (me.embedding <=> get_embedding(query_text)) as sim,
        -- Boost preferred content types
        CASE WHEN me.source_type = ANY(preferred_types) THEN 1.2 ELSE 1.0 END as boost,
        (1 - (me.embedding <=> get_embedding(query_text))) * 
        CASE WHEN me.source_type = ANY(preferred_types) THEN 1.2 ELSE 1.0 END as final
    FROM memory_embeddings me
    WHERE me.embedding IS NOT NULL
    ORDER BY final DESC
    LIMIT limit_results;
END;  
$$ LANGUAGE plpgsql;
```

## Performance Optimization

### 1. Index Tuning

```sql
-- Different index types for different query patterns

-- IVFFlat for approximate nearest neighbor (used in production schema)
-- WARNING: Only create after you have > 1000 embeddings
-- With < 1000 rows, IVFFlat returns wrong results — use exact search (no index) instead
-- See INSTALLATION.md for details
CREATE INDEX idx_memory_embeddings_vector
ON memory_embeddings 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Composite indexes for filtered searches
CREATE INDEX memory_embeddings_type_embedding_idx
ON memory_embeddings (source_type, embedding);
```

### 2. Caching Strategy

```python
# Python caching example
import redis
import json
import hashlib

redis_client = redis.Redis(host='localhost', port=6379, db=0)

def cached_search(query: str, limit: int = 10):
    # Create cache key from query
    cache_key = f"search:{hashlib.md5(query.encode()).hexdigest()}:{limit}"
    
    # Check cache first  
    cached_result = redis_client.get(cache_key)
    if cached_result:
        return json.loads(cached_result)
    
    # Perform search
    results = perform_semantic_search(query, limit)
    
    # Cache for 1 hour
    redis_client.setex(cache_key, 3600, json.dumps(results))
    
    return results
```

### 3. Embedding Batch Processing

```bash
# scripts/batch-embed.sh - Process embeddings in batches
#!/bin/bash

BATCH_SIZE=50
DELAY=1  # Seconds between batches

while true; do
    # Get batch of unembedded content
    BATCH=$(psql -t -c "
        SELECT id, content FROM memory_embeddings 
        WHERE embedding IS NULL 
        LIMIT $BATCH_SIZE;" | grep -v '^$')
    
    if [ -z "$BATCH" ]; then
        echo "No more embeddings to process"
        break
    fi
    
    # Build batch request for OpenAI
    echo "$BATCH" | while IFS='|' read -r id content; do
        echo "Processing ID: $id"
        # Process individual embedding...
    done
    
    sleep $DELAY
done
```

## Monitoring and Maintenance

### 1. Embedding Quality Metrics

```sql
-- Monitor embedding coverage
SELECT 
    source_type,
    COUNT(*) as total,
    COUNT(embedding) as embedded,
    ROUND(100.0 * COUNT(embedding) / COUNT(*), 2) as coverage_pct
FROM memory_embeddings
GROUP BY source_type;

-- Find content that might need re-embedding
SELECT id, content, created_at
FROM memory_embeddings  
WHERE embedding IS NULL
   OR updated_at < created_at  -- Content changed after embedding
ORDER BY created_at DESC;
```

### 2. Search Performance Analysis

```sql
-- Track search patterns (would need logging)
CREATE TABLE search_logs (
    id SERIAL PRIMARY KEY,
    query TEXT,
    results_count INT,
    execution_time_ms INT,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Analyze popular queries
SELECT query, COUNT(*) as frequency, AVG(execution_time_ms) as avg_time_ms
FROM search_logs 
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY query
ORDER BY frequency DESC
LIMIT 10;
```

### 3. Cleanup and Optimization

```sql
-- Remove low-quality embeddings
DELETE FROM memory_embeddings 
WHERE LENGTH(content) < 10  -- Too short to be meaningful
   OR content LIKE '%[System message]%'  -- System noise
   OR created_at < NOW() - INTERVAL '1 year'  -- Very old
   AND source_type = 'agent_chat';  -- Only clean chat, keep facts

-- Update statistics for query optimization
ANALYZE memory_embeddings;

-- Vacuum to reclaim space
VACUUM ANALYZE memory_embeddings;
```

## Integration Examples

### 1. OpenClaw Integration

```javascript
// openclaw-plugin: semantic-memory-search
const { spawn } = require('child_process');

function searchMemories(query, limit = 10) {
    return new Promise((resolve, reject) => {
        const search = spawn('./scripts/search-memories.sh', [query, limit.toString()]);
        let output = '';
        
        search.stdout.on('data', (data) => {
            output += data.toString();
        });
        
        search.on('close', (code) => {
            if (code === 0) {
                resolve(parseSearchResults(output));
            } else {
                reject(new Error(`Search failed with code ${code}`));
            }
        });
    });
}

// Register as OpenClaw tool
module.exports = {
    name: 'semantic_memory_search',
    description: 'Search memories using natural language',
    parameters: {
        query: { type: 'string', required: true },
        limit: { type: 'number', default: 10 }
    },
    execute: searchMemories
};
```

### 2. Slack Bot Integration

```python
# slack_search_bot.py
import os
from slack_bolt import App
from search_api import search_memories

app = App(token=os.environ.get("SLACK_BOT_TOKEN"))

@app.command("/memory-search")
def handle_search(ack, respond, command):
    ack()
    
    query = command['text']
    results = search_memories(query, limit=5)
    
    blocks = []
    for result in results:
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*{result.source_type}* (similarity: {result.similarity:.2f})\n{result.content[:200]}..."
            }
        })
    
    respond({
        "response_type": "ephemeral",
        "blocks": blocks
    })

if __name__ == "__main__":
    app.start(port=int(os.environ.get("PORT", 3000)))
```

## Future Enhancements

### 1. Multimodal Embeddings

Support for image and audio content:

```sql
-- Extended embedding table
ALTER TABLE memory_embeddings ADD COLUMN content_type VARCHAR(20) DEFAULT 'text';
ALTER TABLE memory_embeddings ADD COLUMN media_url TEXT;
ALTER TABLE memory_embeddings ADD COLUMN embedding_model VARCHAR(50) DEFAULT 'text-embedding-3-small';

-- Different embedding dimensions for different modalities
ALTER TABLE memory_embeddings ALTER COLUMN embedding TYPE VECTOR(1024); -- CLIP embeddings
```

### 2. Federated Search

Search across multiple nova-memory instances:

```python
# federated_search.py
import asyncio
import aiohttp

async def federated_search(query: str, nodes: list[str]):
    async with aiohttp.ClientSession() as session:
        tasks = []
        for node in nodes:
            task = session.post(f"{node}/search", json={"query": query})
            tasks.append(task)
        
        responses = await asyncio.gather(*tasks)
        
        # Merge and re-rank results
        all_results = []
        for response in responses:
            results = await response.json()
            all_results.extend(results)
        
        # Re-rank by similarity
        return sorted(all_results, key=lambda x: x['similarity'], reverse=True)
```

### 3. Real-time Updates

Stream search results as new memories are added:

```python
# streaming_search.py  
import asyncio
import psycopg2
from asyncpg import Connection

async def stream_search_updates(query_embedding: list[float]):
    conn = await asyncpg.connect(os.environ.get("DATABASE_URL")  # use pg-env.py to load credentials)
    
    await conn.add_listener('new_embedding', handle_new_embedding)
    
    async def handle_new_embedding(connection, pid, channel, payload):
        # Check if new embedding is similar to query
        new_id = payload
        similarity = await calculate_similarity(new_id, query_embedding)
        if similarity > 0.8:
            yield {"id": new_id, "similarity": similarity}
```

**Note for Documentation Team:** The sophisticated semantic search system combining vector embeddings, temporal decay, and multi-modal content would benefit from **Quill haiku collaboration** to explain complex concepts like vector similarity, embedding spaces, and hybrid search algorithms through accessible metaphors.

## Conclusion

The semantic search system transforms nova-memory from a simple storage system into an intelligent knowledge retrieval engine. By understanding context, semantics, and relationships, it enables natural language queries that surface relevant information regardless of exact keyword matches.

Key benefits:
- **Natural queries** - Ask questions in plain English
- **Cross-domain search** - Find connections across different data types
- **Temporal awareness** - Recent, relevant information surfaces first
- **Extensible architecture** - Easy to add new content types and search modes

The system is designed to scale with your AI assistant's growing knowledge while maintaining fast, accurate search performance.