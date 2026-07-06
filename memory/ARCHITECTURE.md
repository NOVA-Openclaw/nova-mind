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
| `entity_facts` | Key-value facts about entities (includes `visibility`, `privacy_scope`, `durability`, `category` for access control — see note below). Now includes `source_channel_transcript_id` and `source_channel_session_id` FK columns linking facts back to their source chat messages. |
| `entity_relationships` | Connections between entities |
| `places` | Locations, networks, venues |
| `projects` | Active efforts with goals |
| `tasks` | Actionable items linked to projects |
| `events` | Timeline of what happened (`event_date` column) |
| `lessons` | Things learned from experience — confidence decays unless reinforced |
| `workflows` / `workflow_steps` | Structured multi-step procedures with domain routing, discussion triggers, and authorization gates (replaced the old SOPs concept — looked up on demand, not injected into bootstrap context) |
| `vocabulary` | Words for STT correction |
| `preferences` | User and system preferences |
| `agent_turn_context` | Per-turn context injected before every agent response (UNIVERSAL → GLOBAL → DOMAIN → AGENT priority) |
| `memory_type_priorities` | Priority weights for semantic recall by source_type |
| `channel_sessions` | Structured chat session records — one row per provider+chat+thread. Replaces legacy JSONL file storage and the deprecated `conversations` table. |
| `channel_transcripts` | Individual message transcripts linked to `channel_sessions`. FK source for `entity_facts.source_channel_transcript_id`. |

#### Entity Facts Access Control Columns

The `entity_facts` table includes privacy and provenance columns that exist in the schema but **are not yet enforced at retrieval time**:

| Column | Type | Purpose |
|--------|------|---------|
| `visibility` | varchar(20) | `public`, `trusted`, `private` — intended audience level |
| `privacy_scope` | integer[] | Array of entity IDs explicitly allowed to see this fact |
| `durability` | varchar(20) | `permanent`, `long_term`, `short_term`, `ephemeral` — fact lifespan category |
| `category` | text | Free-form category replacing `data_type` (e.g., `identity`, `preference`, `observation`) |
| `extraction_count` | integer | Reinforcement count — incremented each time re-extracted/reinforced |
| `last_confirmed_at` | timestamptz | Most recent confirmation/reinforcement timestamp |
| `expires` | timestamptz | Temporal validity boundary — fact is eligible for cleanup after this timestamp |
| `source_channel_transcript_id` | bigint | FK to channel_transcripts row that triggered extraction |
| `source_channel_session_id` | bigint | FK to channel_sessions row (denormalised for fast queries) |

**Note:** Source attribution (`source_entity_id`) moved to `entity_fact_sources` table, enabling multi-source tracking.

**⚠️ Privacy enforcement is schema-ready but NOT yet implemented in retrieval code** (turn-context plugin's recall module, entity-resolver library). The `visibility` and `privacy_scope` columns exist, indexes are present (`idx_entity_facts_visibility`, `idx_entity_facts_privacy_scope`), but filtering by visibility at query time is not done. All facts are returned regardless of their visibility setting.

#### Turn Context Injection (`agent_turn_context`)

The `agent_turn_context` table stores short, high-priority context records that are injected into **every agent turn** via the `turn-context` plugin's turn-reminders module. Unlike `agent_bootstrap_context` (session-level bootstrap), these records fire before every agent response via the `before_prompt_build` hook (not a separate `after_message` hook — this repo's only two turn-context plugin hooks are `message_received` and `before_prompt_build`; see `memory/plugins/turn-context/README.md`).

**Key properties:**
- Each record capped at **500 characters** (CHECK constraint in DB)
- Total injected per agent capped at **2000 characters** (enforced by `get_agent_turn_context()`)
- Truncation appends a visible warning to the agent: `⚠️ Turn context truncated — some critical rules may be missing.`
- Cache TTL: **5 minutes** per agent — avoids per-turn DB queries
- Scopes: `UNIVERSAL` (all agents), `GLOBAL` (all agents), `DOMAIN` (agents in matching `agent_domains`), `AGENT` (specific agent)

**Migration:** `migrations/065_agent_turn_context.sql`  
**Plugin:** `plugins/turn-context/` (openclaw.plugin.json, src/turn-reminders.ts)

> **Note:** The old `hooks/agent-turn-context/` hook was removed and replaced by the turn-context Plugin SDK plugin (#182).

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

**Purpose:** Raw session logs and scratch space — **plus, as of nova-mind#397, an auto-generated system-activity summary.**

Each day's file is no longer purely hand-written. `memory/scripts/generate-daily-log.py` runs from cron (nightly + 3x intraday, installed by `agent-install.sh`) and writes/updates a delimited **generated block** (marked by `<!-- BEGIN GENERATED DAILY LOG -->` / `<!-- END GENERATED DAILY LOG -->` HTML comments) summarizing that day's `agent_chat` activity, `workflow_runs`, `lessons`, `events`, and `tasks` — pulled directly from the database. Agent-written narrative outside the markers is preserved byte-for-byte on every run. See `memory/docs/daily-log-generation.md` for the full marker contract, flags, cron schedule, and backfill runbook.

**Lifecycle:** 
1. Generated block auto-populates/refreshes from DB state (cron-driven)
2. Log notable events during the day (agents/humans write narrative outside the generated block)
3. Review periodically
4. Extract significant items to database
5. Archive old daily files

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
| agent_chat | 0.70 | Inter-agent messages (often verbose). **Note (#320):** the trigger that embedded new `agent_chat` messages was dropped when `agent_chat` moved to its own dedicated database (cross-database triggers aren't supported); this priority weight currently only affects any embeddings from before that migration. See `memory/docs/semantic-search-guide.md`. |

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

Real-time extraction happens per-message via a hook; session transcript ingestion runs on a separate cron-driven cadence:

```
Real-time path:
Incoming message → memory-extract hook → extract_memories.py (Claude extracts
                                          facts/entities/events/vocabulary in one pass,
                                          LLM judges durability/category/confidence)
                                       → PostgreSQL

Catch-up path (separate cadence, check crontab for current schedule):
Session JSONL files → memory-catchup.sh
                    → channel_sessions + channel_transcripts (DB ingest)
                    → delete source JSONL files
```

> **Note:** `extract-memories.sh` and `store-memories.sh` (the old two-script shell pipeline this diagram used to describe) were removed as part of the #174 grammar-parser removal and consolidated into `memory/scripts/extract_memories.py`. See `memory/docs/memory-extraction-pipeline.md` for the current pipeline, including a known bug where `memory-catchup.sh` still calls a nonexistent `process-input.sh`.

**Transcript ingestion:** JSONL files from `~/.openclaw/agents/*/sessions/*.jsonl` are parsed, upserted into `channel_sessions` and `channel_transcripts`, then the source files are deleted. Rich metadata (sender names, IDs, group info, providers) is extracted from the JSONL structure. The `memory-extract` hook does real-time upserts during message processing, and `extract_memories.py` sets `SOURCE_CHANNEL_TRANSCRIPT_ID`/`SOURCE_CHANNEL_SESSION_ID`-derived FK pointers so `entity_facts` rows link back to their source transcripts.

### Extraction Categories

Per `extract_memories.py`'s current extraction template:
1. **facts** — Entity-scoped key/value facts (covers what used to be split across facts/opinions/preferences — disambiguated via `category`: observation, preference, identity, mood, decision, routine, state, obligation)
2. **entities** — People, AIs, organizations, places
3. **events** — Things that happened
4. **vocabulary** — Words for STT (names, brands, technical jargon, slang)

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
