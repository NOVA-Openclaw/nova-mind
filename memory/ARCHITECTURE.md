# NOVA Memory Architecture

## Overview

NOVA uses a multi-layer memory system designed to handle different types of information with appropriate persistence and access patterns.

```
┌─────────────────────────────────────────────────────────────────┐
│                     MEMORY HIERARCHY                            │
├─────────────────────────────────────────────────────────────────┤
│  LONG-TERM (PostgreSQL)       │ Structured data, queryable,     │
│  - Entities & relationships   │ survives indefinitely.          │
│  - Events & timeline          │ PRIMARY source of truth.        │
│  - SOPs & procedures          │                                 │
│  - Lessons learned            │                                 │
│  - Vocabulary for STT         │                                 │
├───────────────────────────────┼─────────────────────────────────┤
│  SHORT-TERM (MEMORY.md)       │ Working notes loaded every turn │
│  - Quick reference            │ Behavioral reminders included.  │
│  - Active context             │ Keep lean (~2-3KB).             │
│  - Key preferences            │                                 │
├───────────────────────────────┼─────────────────────────────────┤
│  DAILY (memory/YYYY-MM-DD.md) │ Raw session logs, scratch.      │
│  - Session notes              │ Reviewed and archived.          │
│  - Temporary context          │                                 │
├───────────────────────────────┼─────────────────────────────────┤
│  PERIODIC (REMINDERS.md)      │ Actions executed every 30 min   │
│  - Scan 1Password vault       │ via cron. Keeps memory fresh.   │
│  - Check SOPs from database   │                                 │
│  - Review pending tasks       │                                 │
├───────────────────────────────┼─────────────────────────────────┤
│  SEMANTIC (OpenClaw SQLite)   │ Embeddings for memory_search.   │
│  - Vector search over files   │ Auto-indexed by OpenClaw.       │
│  - Full-text search           │                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Memory Tiers Explained

### 1. Long-Term Memory (PostgreSQL) — PRIMARY

**Database:** `${USER//-/_}_memory` on localhost (e.g., `nova_memory` for user `nova`)

**Priority:** ALWAYS check database first before flat files.

This is the source of truth for persistent information.

#### Core Tables

| Table | Purpose |
|-------|---------|
| `entities` | People, AIs, organizations — things with agency |
| `entity_facts` | Key-value facts about entities (includes `visibility`, `privacy_scope`, `data_type` for access control — see note below) |
| `entity_relationships` | Connections between entities |
| `places` | Locations, networks, venues |
| `projects` | Active efforts with goals |
| `tasks` | Actionable items linked to projects |
| `events` | Timeline of what happened (`event_date` column) |
| `lessons` | Things learned from experience — confidence decays unless reinforced |
| `agent_bootstrap_context` | Standard Operating Procedures and bootstrapping context (not a standalone `sops` table) |
| `vocabulary` | Words for STT correction |
| `preferences` | User and system preferences |
| `agent_turn_context` | Per-turn context injected before every agent response (UNIVERSAL → GLOBAL → DOMAIN → AGENT priority) |
| `memory_type_priorities` | Priority weights for semantic recall by source_type |

#### Entity Facts Access Control Columns

The `entity_facts` table includes privacy and provenance columns that exist in the schema but **are not yet enforced at retrieval time**:

| Column | Type | Purpose |
|--------|------|---------|
| `visibility` | varchar(20) | `public`, `trusted`, `private` — intended audience level |
| `privacy_scope` | integer[] | Array of entity IDs explicitly allowed to see this fact |
| `data_type` | varchar(20) | One of `permanent`, `identity`, `preference`, `temporal`, `observation` |
| `source_entity_id` | int | FK to entity who provided the information (privacy ownership) |
| `vote_count` | int | Reinforcement count — incremented each time re-confirmed |
| `last_confirmed` | timestamptz | Most recent confirmation/reinforcement timestamp |

**⚠️ Privacy enforcement is schema-ready but NOT yet implemented in retrieval code** (semantic-recall hook, entity-resolver library). The `visibility` and `privacy_scope` columns exist, indexes are present (`idx_entity_facts_visibility`, `idx_entity_facts_privacy_scope`), but filtering by visibility at query time is not done. All facts are returned regardless of their visibility setting.

#### Turn Context Injection (`agent_turn_context`)

The `agent_turn_context` table stores short, high-priority context records that are injected into **every agent turn** via the `agent-turn-context` hook. Unlike `agent_bootstrap_context` (session-level bootstrap), these records fire on every `message:received` event.

**Key properties:**
- Each record capped at **500 characters** (CHECK constraint in DB)
- Total injected per agent capped at **2000 characters** (enforced by `get_agent_turn_context()`)
- Truncation appends a visible warning to the agent: `⚠️ Turn context truncated — some critical rules may be missing.`
- Cache TTL: **5 minutes** per agent — avoids per-turn DB queries
- Scopes: `UNIVERSAL` (all agents), `GLOBAL` (all agents), `DOMAIN` (agents in matching `agent_domains`), `AGENT` (specific agent)

**Migration:** `migrations/065_agent_turn_context.sql`  
**Hook:** `hooks/agent-turn-context/` (handler.ts, package.json, HOOK.md)

#### SOPs (Standard Operating Procedures)

SOPs are stored in the `agent_bootstrap_context` table as DOMAIN or GLOBAL context entries. They are automatically injected into agent sessions at startup via `get_agent_bootstrap()`.

Before performing any recurring task, check the agent bootstrap context for relevant SOPs:

```sql
SELECT file_key, LEFT(content, 200) FROM agent_bootstrap_context 
WHERE context_type IN ('GLOBAL', 'DOMAIN') AND file_key ILIKE '%WORKFLOW%';
```

### 2. Short-Term Memory (MEMORY.md) — Every Turn

**Location:** `~/.openclaw/workspace/MEMORY.md` (workspace root)

**Purpose:** Quick-reference context and behavioral reminders.

**How it works:** OpenClaw automatically loads workspace files (MEMORY.md, AGENTS.md, etc.) into the system prompt at the start of every turn. This survives context compaction because it's re-read from disk each time.

**Contents should include:**
- Key entity IDs (e.g., I)ruid = Entity 2)
- Important behaviors ("database first", "check SOPs")
- Account/service quick reference
- Active project status
- Communication preferences

**Keep it lean** — this loads every turn, so ~2-3KB is ideal.

**Security:** Only loaded in main sessions (direct chats). Not loaded in group chats or shared contexts.

### 3. Daily Notes (memory/YYYY-MM-DD.md)

**Location:** `~/.openclaw/workspace/memory/YYYY-MM-DD.md`

**Purpose:** Raw session logs and scratch space.

**Lifecycle:** 
1. Log notable events during the day
2. Review periodically
3. Extract significant items to database
4. Archive old daily files

### 4. Periodic Reminders (REMINDERS.md) — Every 30 Minutes

**Location:** `~/.openclaw/workspace/REMINDERS.md`

**Purpose:** Actions to EXECUTE periodically, not just read.

**How it works:** A cron job fires every 30 minutes, sending a system event that tells the agent to read REMINDERS.md and execute the listed actions.

**Typical actions:**
- Scan 1Password vault (`op item list`) to remember available accounts
- Query SOPs from database to refresh procedural knowledge
- Check pending tasks to stay on track

See `REMINDERS.md` in this repo for the template.

### 5. Semantic Memory (OpenClaw SQLite)

**Location:** `~/.openclaw/memory/main.sqlite`

**Purpose:** Powers the `memory_search` tool.

OpenClaw automatically indexes workspace markdown files and stores embeddings for semantic search. This is separate from the PostgreSQL long-term memory.

## Semantic Recall Priority Weighting

The `memory_type_priorities` table controls which memory types surface first during semantic recall. Higher priority = more likely to appear in results:

| Source Type | Priority | Notes |
|-------------|----------|-------|
| workflows | 1.50 | Highest — structural guidance |
| lessons | 1.30 | Correction learning, high value |
| tasks | 1.20 | Active work items |
| entity_fact | 1.00 | Baseline — entity knowledge |
| daily_log | 0.90 | Recent session history |
| agent_chat | 0.70 | Inter-agent messages (often verbose) |

Semantic search results are scored as `vector_similarity × priority_weight`. Adjust priorities via:
```sql
UPDATE memory_type_priorities SET priority = N WHERE source_type = 'lesson';
```

## Ghost Embeddings (Known Failure Mode)

**Ghost embeddings** are orphaned vector records in `memory_embeddings` where the source record (entity_fact, lesson, event, etc.) has been deleted or archived but the embedding row remains. These are the **worst failure mode** for semantic recall because they surface stale, outdated information with high confidence — the vector is still valid, but the data it points to is gone or replaced.

**Causes:**
- Deleting source records without cleaning up `memory_embeddings`
- Schema migration that drops/recreates tables
- Application-level deletes that bypass the embedding maintenance pipeline

**Detection:**
```sql
-- Find potentially orphaned embeddings
SELECT me.id, me.source_type, me.source_id
FROM memory_embeddings me
LEFT JOIN entity_facts ef ON me.source_type = 'entity_fact' AND me.source_id = ef.id
LEFT JOIN lessons l ON me.source_type = 'lesson' AND me.source_id = l.id
-- ... repeat for each source_type
WHERE me.source_type = 'entity_fact' AND ef.id IS NULL;
```

**Prevention:** Add cascading cleanup hooks that remove embeddings when source records are deleted. The `memory-maintenance.py` script handles some cleanup but does not yet detect ghost embeddings automatically.

## Memory Extraction Pipeline

A cron job runs every minute to extract memories from chat:

```
Chat transcript → memory-catchup.sh (every 1 min)
               → extract-memories.sh (Claude extracts 8 categories)
               → store-memories.sh (inserts to PostgreSQL)
               → New vocabulary? → STT service restarts
```

### Extraction Categories

1. **entities** — People, AIs, organizations
2. **places** — Locations, venues
3. **facts** — Objective information
4. **opinions** — Subjective views (with holder)
5. **preferences** — Likes/dislikes
6. **events** — Things that happened
7. **relationships** — Connections
8. **vocabulary** — Words for STT

## Data Flow

```
User speaks → STT (Whisper + vocabulary corrections)
           → Chat → Response
           → Memory extraction (async, 1/min)
           → PostgreSQL

Query needed → Check PostgreSQL first
            → Then MEMORY.md
            → Then memory_search (semantic)

Every 30 min → Cron fires
            → Read REMINDERS.md
            → Execute scans (1Password, SOPs, tasks)
            → Log findings to daily notes
```

## Key Principles

1. **Database first** — PostgreSQL is the source of truth
2. **SOPs exist** — Check `agent_bootstrap_context` for workflow documentation before improvising recurring tasks
3. **MEMORY.md is lean** — Quick reference only, loaded every turn
4. **REMINDERS.md is active** — Execute actions, don't just read
5. **Log important events** — Use `events` table, not just markdown
6. **Vocabulary grows** — New words auto-extracted and loaded to STT

## Modifications from Default OpenClaw

This setup extends the default OpenClaw memory with:

1. **PostgreSQL database** — Structured long-term storage (entities, events, SOPs, etc.)
2. **Memory extraction pipeline** — Auto-extracts memories from chat every minute
3. **REMINDERS.md + cron** — Periodic active scans to refresh memory
4. **Vocabulary table** — STT correction words, auto-loaded on restart

The default OpenClaw provides:
- MEMORY.md/AGENTS.md workspace file injection
- Semantic memory search via SQLite embeddings
- Heartbeat system for periodic check-ins
