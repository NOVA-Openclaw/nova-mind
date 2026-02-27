---
name: semantic-recall
description: "Runs semantic search on incoming messages and loads entity context before processing"
metadata: {"openclaw":{"emoji":"🧠","events":["message:received"],"requires":{"bins":["python3"],"env":["OPENAI_API_KEY"]}}}
---

# Semantic Recall Hook

Automatically runs semantic search on incoming messages to retrieve relevant memories
from the database and loads entity profile information before the agent processes the message.

## What It Does

1. Receives the incoming message text and sender information
2. **Resolves sender to entity** using phone or Signal UUID
3. **Loads entity profile** with key facts (timezone, communication style, expertise, preferences)
4. Runs `proactive-recall.py` with the message as query for semantic memories
5. Injects entity context and relevant memories into the hook event messages
6. Agent sees both entity profile and semantic context before formulating a response

## Entity Resolution

The hook attempts to resolve the message sender to an entity by:
- Extracting sender ID from `event.context.senderId`
- Querying PostgreSQL `entities` and `entity_facts` tables
- Matching against `phone` or `signal_uuid` facts
- Loading key profile facts: timezone, communication_style, expertise, preferences

## Requirements

- Python 3 with psycopg2 and openai packages
- OPENAI_API_KEY environment variable
- PostgreSQL connection to `${USER//-/_}_memory` database (e.g., `nova_memory`)
- `proactive-recall.py` script installed to `~/.openclaw/scripts/` by `agent-install.sh`
- pgvector extension in PostgreSQL
- Entity Relations System (entities and entity_facts tables)

## Configuration

Database connection is configured via `~/.openclaw/postgres.json` (loaded by `~/.openclaw/lib/pg-env.sh`). Environment variable overrides are supported:
- `PGHOST` (default: localhost)
- `PGDATABASE` (default: `${USER//-/_}_memory`, e.g., `nova_memory`)
- `PGUSER` (default: current OS user)
- `PGPASSWORD` (optional)

Recall settings (configurable via environment variables):
- `SEMANTIC_RECALL_TOKEN_BUDGET` - Max tokens to inject (default: 1000)
- `SEMANTIC_RECALL_HIGH_CONFIDENCE` - Threshold for full content vs summary (default: 0.7)
- Similarity threshold: 0.4 minimum

## Tiered Retrieval

To manage context window usage, memories are injected at different detail levels:

| Similarity | Content | Indicator |
|------------|---------|-----------|
| ≥ 0.7 (high confidence) | Full content (300-600 chars) | 🎯 |
| < 0.7 (lower confidence) | Summary only (100-200 chars) | 📝 |

The system fetches up to 10 candidates, then packs as many as fit within the token budget, prioritizing by similarity score.

## Dynamic Limits

Content length adjusts based on result count — fewer results get more content each:

| Results | Summary Length | Full Length |
|---------|---------------|-------------|
| 1-2 | ~200 chars | ~600 chars |
| 5-6 | ~150 chars | ~450 chars |
| 9-10 | ~100 chars | ~300 chars |

This ensures context window is used efficiently regardless of how many memories match.

## Error Handling

The hook fails gracefully:
- Entity resolution errors don't block message processing
- Database connection failures are logged but don't throw
- Timeouts: 2s for entity resolution, 1s for facts loading, 5s for semantic recall
- Missing entities result in semantic recall only (no entity context injection)
