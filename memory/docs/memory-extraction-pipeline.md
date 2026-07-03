# Memory Extraction Pipeline Guide

The memory extraction pipeline automatically transforms natural language conversations into structured database records. This guide covers how it works, how to troubleshoot issues, and how to optimize performance.

> **Note:** This doc previously described a three-script shell pipeline (`extract-memories.sh` → `store-memories.sh`, driven by `process-input.sh`). That pipeline was consolidated into a single Python script, `memory/scripts/extract_memories.py`, as part of the #174 grammar-parser removal. None of `extract-memories.sh`, `store-memories.sh`, or `process-input.sh` exist in this repo's `memory/scripts/` anymore. This revision documents the current pipeline.
>
> **Known issue:** `memory/scripts/memory-catchup.sh` (current repo source) still references `EXTRACT_SCRIPT="${SCRIPT_DIR}/process-input.sh"` and calls it directly — that script does not exist in this repo. A `process-input.sh` happens to exist as a stale deployed artifact at `~/.openclaw/scripts/`/`~/.openclaw/workspace/scripts/` on at least one host, but it in turn calls `extract-memories.sh`, which also does not exist. This is a real latent bug in `memory-catchup.sh` worth a GitHub issue and a fix from the Software Engineering domain — flagging here rather than silently patching the script, since that's outside Technical Writing's scope.

## Overview

There are two related but distinct paths into nova-memory:

```
Real-time path (per-message):
Incoming message → memory-extract hook → extract_memories.py → PostgreSQL
                                              ↓
                                        Claude API extraction
                                        (LLM judges durability/category/confidence per fact)

Catch-up path (session transcript ingestion, cron-driven):
Session JSONL → memory-catchup.sh → channel_sessions/transcripts (DB)
                      ↓
              (also attempts message-level re-extraction via the
               process-input.sh code path described above — currently broken)
```

**Key Features:**
- Extraction is LLM-driven in a single pass: the extraction prompt (in `extract_memories.py`) asks Claude to classify `durability`, `category`, `confidence`, and `visibility` per fact directly, rather than a separate deterministic storage script applying rules after the fact
- Bidirectional extraction (both user and assistant messages)
- Real-time deduplication to prevent data corruption (`memory/scripts/dedup_helper.py`)
- Automatic vocabulary/entity-identifier extraction (phone, email, Discord/GitHub/Signal handles)
- Rate limiting and error recovery
- JSONL → DB ingest with provider detection (Discord, Signal, Telegram, generic) via `memory-catchup.sh`

## Components

### 1. `memory-extract` hook + `extract_memories.py` — Real-Time Extraction

**Purpose:** Extracts structured data (entities, facts, events, vocabulary) from a single incoming message as it arrives, using sender metadata passed via environment variables.

**Location:** `memory/scripts/extract_memories.py` (source), deployed via the `memory-extract` hook

**Env vars consumed (see the script's module docstring for the full/current list):** `SENDER_NAME`, `SENDER_ID`, `IS_GROUP`, `SOURCE_SESSION_ID`, and related sender/session metadata.

**Output:** JSON with these categories (see the script's extraction prompt/template for the authoritative list):
- `facts` (entity-scoped key/value facts, each carrying `subject`, `key`, `value`, `category`, `durability`, `confidence`, `visibility`, optional `expires`)
- `entities` (people, AIs, organizations, places)
- `events` (dated occurrences)
- `vocabulary` (STT-relevant terms: names, brands, technical jargon, slang)

Facts about identifiers (phone, email, Discord/GitHub handle, Signal UUID) are extracted directly into `entity_facts` with the appropriate `key` (e.g. `key="phone"`), not into a separate "entities" bucket, and phone numbers are always marked `visibility="private"`.

**Durability guidance baked into the prompt:**
- `permanent`: Identity facts that rarely change. Never auto-decays.
- `long_term`: Durable preferences/observations. Slow decay.
- `short_term`: Current states/moods. Moderate decay.
- `ephemeral`: Temporary/fleeting conditions. Aggressive decay.

**Troubleshooting:**

| Problem | Symptoms | Solution |
|---------|----------|----------|
| API timeouts | Extraction hangs or times out | Check `ANTHROPIC_API_KEY` and network connectivity |
| No extraction happening | No new `entity_facts`/`events` rows despite active chat | Verify the `memory-extract` hook is enabled: `openclaw hooks list` |
| Missing context | Poor reference resolution ("that", "yes", "do it" not extracted) | Check the rolling context window the hook passes in (see hook config) |
| Rate limiting | HTTP 429 errors | Add/adjust delay handling in the hook or extraction call |

### 2. `dedup_helper.py` — Deduplication

**Purpose:** Prevents duplicate entity/fact rows during extraction storage.

**Location:** `memory/scripts/dedup_helper.py`

Imports `get_initial_confidence` from `confidence_helper.py` to set a starting confidence score based on the reporting entity's `trust_level` (see `SOURCE-AUTHORITY.md`). Facts that already exist are reinforced (`extraction_count` incremented, `last_confirmed_at` updated) rather than duplicated.

### 3. `memory-catchup.sh` — Session Transcript Ingestion (Cron-Driven)

**Purpose:** Scans session transcripts and ingests them into the database; also attempts a legacy per-message re-extraction path (see the known-issue note above).

**Location:** `memory/scripts/memory-catchup.sh`

**How it works:**
1. Reads session transcripts from `~/.openclaw/agents/main/sessions/`
2. Tracks last processed timestamp in `~/.openclaw/memory-catchup-state.json`
3. Maintains a rolling message cache at `~/.openclaw/memory-message-cache.json`
4. **Ingests JSONL files into DB:** Parses session files from `~/.openclaw/agents/*/sessions/*.jsonl` and upserts into `channel_sessions` + `channel_transcripts` with provider detection, rich metadata parsing (sender names, IDs, group info), and deduplication via composite unique indexes
5. **Deletes source files:** After successful DB commit, source JSONL files are removed. Extraction failures do NOT block transcript ingestion.
6. Attempts to invoke `process-input.sh` for message-level extraction — **currently broken** (see known-issue note above); this does not block transcript ingestion, which is why the JSONL → DB path continues to work even though this sub-path is broken

**State file structure:**
```json
{
  "last_processed_ts": "2026-02-08T15:30:00.000Z",
  "processed_count": 1847
}
```

**Transcript ingest fields parsed from JSONL:**
- `chat_id` → `provider` detection (channel: → discord, group: → signal)
- `is_group_chat`, `group_subject`, `group_space` → session metadata
- `sender_id`, `sender`, `sender_username`, `sender_tag` → transcript sender fields
- `session_key` → `channel_sessions.session_key`

**Troubleshooting:**

| Problem | Symptoms | Solution |
|---------|----------|----------|
| No new extractions | State file timestamp stuck | Delete state file: `rm ~/.openclaw/memory-catchup-state.json` |
| Missing recent messages | Extractions lag behind chat | Check cron job is running: `crontab -l \| grep memory-catchup` |
| Duplicate processing | Same messages processed twice | State file corruption - recreate with current timestamp |
| Script hangs | Process doesn't complete | Check for stuck Claude API calls, or the broken `process-input.sh` path noted above |

## Context Window System

Real-time extraction context resolution happens per-message via the hook's own context passing (not a separate cache file for that path). `memory-catchup.sh` separately maintains its own rolling cache at `~/.openclaw/memory-message-cache.json` for its ingestion path.

### Cache Structure

**File:** `~/.openclaw/memory-message-cache.json`

```json
[
  {"role": "user", "timestamp": "2026-02-08T15:00:00Z", "content": "How much do crawlers cost?"},
  {"role": "assistant", "timestamp": "2026-02-08T15:00:15Z", "content": "About $130M in today's dollars"}
]
```

### Cache Maintenance

- **Rotation:** FIFO (oldest messages removed first)
- **Persistence:** Survives script restarts
- **Reset:** Delete cache file to start fresh

## Setup and Configuration

### Prerequisites

```bash
# 1. PostgreSQL with the nova-mind database, schema applied via pgschema
#    (see memory/INSTALLATION.md for the full installer-based flow)

# 2. Anthropic API key
export ANTHROPIC_API_KEY="your-key-here"

# 3. Required tools
sudo apt install postgresql-client jq curl
```

### Automated Setup (Cron Job)

```bash
# Add to crontab (memory-catchup.sh runs on its own schedule; check current
# crontab for the exact cadence rather than assuming "every minute")
crontab -l | grep memory-catchup
```

### Manual Testing

There is no standalone CLI to manually trigger real-time extraction for a single message — it runs via the `memory-extract` hook as part of live message handling. To test the transcript-ingestion path:

```bash
# Process recent session transcripts (one-time run)
~/.openclaw/scripts/memory-catchup.sh --log
```

## Monitoring and Debugging

### Log Files

```bash
# Main processing log
tail -f ~/.openclaw/logs/memory-catchup.log

# PostgreSQL logs (Ubuntu)
sudo tail -f /var/log/postgresql/postgresql-16-main.log

# Check cron job execution
grep CRON /var/log/syslog | grep memory-catchup
```

### Health Checks

```bash
# 1. Verify the memory-extract hook is enabled
openclaw hooks list

# 2. Verify cron job
ps aux | grep memory-catchup
ls -la ~/.openclaw/memory-catchup-state.json

# 3. Database connectivity
psql -d nova_memory -c "SELECT COUNT(*) FROM entities;"
```

### Performance Metrics

```sql
-- Extraction volume per day
SELECT DATE(created_at) as date, COUNT(*) as extractions
FROM entities 
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date;

-- Most active extraction categories
SELECT 'entities' as category, COUNT(*) as count FROM entities WHERE created_at > NOW() - INTERVAL '1 day'
UNION ALL
SELECT 'events', COUNT(*) FROM events WHERE created_at > NOW() - INTERVAL '1 day'  
UNION ALL
SELECT 'facts', COUNT(*) FROM entity_facts WHERE created_at > NOW() - INTERVAL '1 day';
```

## Common Issues and Solutions

### Issue: Extractions Stop Working

**Symptoms:**
- No new database records despite active chat
- State file timestamp not updating (for the catchup path) or no hook activity (for the real-time path)

**Diagnosis:**
```bash
# Real-time path: verify hook is enabled
openclaw hooks list

# Catchup path: check cron and recent logs
crontab -l | grep memory-catchup
tail -50 ~/.openclaw/logs/memory-catchup.log
```

**Solutions:**
1. **Missing API key:** Ensure `ANTHROPIC_API_KEY` is exported in the relevant environment (hook process or cron environment)
2. **Script permissions:** `chmod +x memory/scripts/*.sh memory/scripts/*.py`
3. **Path issues:** Use absolute paths in crontab
4. **PostgreSQL down:** `sudo systemctl start postgresql`
5. **Hook not enabled:** `openclaw hooks enable memory-extract`

### Issue: Duplicate Entries

**Symptoms:**
- Same entity appears multiple times with slight variations
- Facts being re-inserted

**Solutions:**
1. **Check `dedup_helper.py`** logic and thresholds
2. **Add database constraints:**
```sql
-- Prevent duplicate entities
ALTER TABLE entities ADD CONSTRAINT unique_entity_name_type UNIQUE (name, type);

-- Prevent duplicate facts  
ALTER TABLE entity_facts ADD CONSTRAINT unique_entity_fact UNIQUE (entity_id, key, value);
```

### Issue: High API Costs

**Symptoms:**
- Large Anthropic bills
- Many API calls per minute

**Solutions:**
1. **Filter trivial messages:** Skip messages like "ok", "thanks", emoji-only before calling the extraction API
2. **Review hook trigger conditions** for over-eager invocation

## Advanced Configuration

### Custom Extraction Categories

Modify the extraction prompt directly in `extract_memories.py` (the `TEMPLATE`/instructions block) to add new categories or fields.

### Database Schema Extensions

Add new tables via the declarative schema (`database/schema.sql` at the repo root), following the pattern used for existing tables like `extraction_metrics`.

## Integration with OpenClaw

### Hook Installation

The `memory-extract` hook is installed automatically by `agent-install.sh`. To verify or re-enable manually:

```bash
openclaw hooks list
openclaw hooks enable memory-extract
```

### Memory Search Integration

The extracted data becomes searchable via the `turn-context` Plugin SDK plugin (semantic recall) and direct SQL:

```sql
-- Database queries
SELECT * FROM entity_facts ef JOIN entities e ON e.id = ef.entity_id WHERE e.name ILIKE '%brooklyn%';
```

## Performance Optimization

### Database Indexing

```sql
-- Speed up entity lookups
CREATE INDEX idx_entities_name ON entities(name);
CREATE INDEX idx_entities_type ON entities(type);

-- Speed up fact queries
CREATE INDEX idx_entity_facts_key ON entity_facts(key);
CREATE INDEX idx_entity_facts_entity_id ON entity_facts(entity_id);

-- Speed up timeline queries
CREATE INDEX idx_events_date ON events(date);
```

## Next Steps

1. **Fix the `memory-catchup.sh` → `process-input.sh` broken call path** (see known-issue note at the top of this doc)
2. **Set up monitoring:** Implement extraction metrics tracking
3. **Tune performance:** Adjust batch sizes and API limits based on usage
4. **Extend categories:** Add task extraction, sentiment analysis
5. **Add validation:** Implement data quality checks and correction flows

The memory extraction pipeline is the heart of nova-memory's automatic learning capability. Understanding and maintaining it properly ensures your AI assistant continuously builds comprehensive, searchable knowledge from every conversation.
