# Memory Extraction Pipeline Guide

The memory extraction pipeline automatically transforms natural language conversations into structured database records. This guide covers how it works, how to troubleshoot issues, and how to optimize performance.

## Overview

```
Chat Message → memory-catchup.sh → extract-memories.sh → store-memories.sh → PostgreSQL
     ↓               ↓                    ↓                    ↓
Every message   Every minute      Claude API           Structured data
received        (cron job)        extraction           with deduplication
```

**Key Features:**
- 20-message rolling context window for reference resolution
- Bidirectional extraction (both user and assistant messages)
- Real-time deduplication to prevent data corruption
- Automatic vocabulary extraction for STT improvement
- Rate limiting and error recovery

## Components

### 1. memory-catchup.sh - Collection & Batching

**Purpose:** Scans session transcripts and queues messages for processing

**Location:** `~/.openclaw/workspace/nova-memory/scripts/memory-catchup.sh`

**How it works:**
1. Reads session transcripts from `~/.openclaw/agents/main/sessions/`
2. Tracks last processed timestamp in `~/.openclaw/memory-catchup-state.json`
3. Rate-limits to 3 messages per run to avoid API overload
4. Builds 20-message context window for each extraction

**State file structure:**
```json
{
  "last_processed": "2026-02-08T15:30:00Z",
  "message_count": 1847,
  "last_session": "2026-02-08.jsonl"
}
```

**Troubleshooting:**

| Problem | Symptoms | Solution |
|---------|----------|----------|
| No new extractions | State file timestamp stuck | Delete state file: `rm ~/.openclaw/memory-catchup-state.json` |
| Missing recent messages | Extractions lag behind chat | Check cron job is running: `systemctl status cron` |
| Duplicate processing | Same messages processed twice | State file corruption - recreate with current timestamp |
| Script hangs | Process doesn't complete | Check for stuck Claude API calls in extract-memories.sh |

### 2. extract-memories.sh - Natural Language Processing

**Purpose:** Uses Claude to extract structured data from conversational text

**Location:** `~/.openclaw/workspace/nova-memory/scripts/extract-memories.sh`

**Input format:**
```
Context: [Last 20 messages for reference resolution]
---
[CURRENT MESSAGE TO EXTRACT]
```

**Output:** JSON with 8 categories:
- entities (people, AIs, organizations)
- places (locations, venues, networks)
- facts (objective information)
- opinions (subjective views with holder)
- preferences (likes/dislikes)
- events (timeline items)
- relationships (connections between entities)
- vocabulary (new words for STT)

**Example extraction:**
```bash
# Input message
"Yes, let's use that design for the Burning Man crawler"

# With context understanding "that design" refers to previous discussion
{
  "entities": [],
  "places": [{"name": "Burning Man", "type": "event", "location": "Nevada"}],
  "facts": [{"fact": "Design approved for Burning Man crawler project"}],
  "events": [{"event": "Design approval for Burning Man crawler", "date": "2026-02-08"}],
  "preferences": [{"holder": "user", "subject": "crawler design", "preference": "approved"}]
}
```

**Troubleshooting:**

| Problem | Symptoms | Solution |
|---------|----------|----------|
| API timeouts | Script hangs on Claude calls | Check `ANTHROPIC_API_KEY` and network connectivity |
| Invalid JSON output | Store script fails with parse errors | Add JSON validation to extract script |
| Missing context | Poor reference resolution | Verify context cache in `~/.openclaw/memory-message-cache.json` |
| Rate limiting | HTTP 429 errors | Increase delay between API calls |

### 3. store-memories.sh - Database Storage

**Purpose:** Validates and stores extracted JSON in PostgreSQL with deduplication

**Location:** `~/.openclaw/workspace/nova-memory/scripts/store-memories.sh`

**Deduplication strategy:**
- **Layer 1 (Prompt):** Existing facts queried and shown to Claude
- **Layer 2 (Storage):** Database checks before every insert

**Storage flow:**
1. Parse and validate JSON
2. For each category, check existing records
3. Skip duplicates, insert new records
4. Update vocabulary table for STT
5. Log insertion results

**Troubleshooting:**

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Constraint violations | UNIQUE constraint errors | Normal - deduplication working correctly |
| Connection failures | psql connection errors | Check PostgreSQL service and database credentials |
| Malformed data | Data truncation warnings | Increase column sizes in schema.sql |
| Performance issues | Slow inserts | Add indexes: `CREATE INDEX ON entities(name)` |

## Context Window System

The pipeline maintains a **20-message rolling cache** for improved reference resolution.

### Cache Structure

**File:** `~/.openclaw/memory-message-cache.json`

```json
[
  {"role": "user", "timestamp": "2026-02-08T15:00:00Z", "content": "How much do crawlers cost?"},
  {"role": "assistant", "timestamp": "2026-02-08T15:00:15Z", "content": "About $130M in today's dollars"},
  {"role": "user", "timestamp": "2026-02-08T15:01:00Z", "content": "Let's build one for Burning Man"},
  {"role": "assistant", "timestamp": "2026-02-08T15:01:30Z", "content": "That would be legendary..."}
]
```

### Context Benefits

**Before (no context):**
```
Message: "Yes, keep that aesthetic"
Extraction: {} // Can't resolve "that"
```

**After (with context):**
```
Context shows previous discussion about retro-futuristic crawler design
Message: "Yes, keep that aesthetic"  
Extraction: {"preferences": [{"holder": "user", "subject": "retro-futuristic aesthetic", "preference": "approved"}]}
```

### Cache Maintenance

- **Size limit:** 20 messages maximum
- **Rotation:** FIFO (oldest messages removed first)
- **Persistence:** Survives script restarts
- **Reset:** Delete cache file to start fresh

## Setup and Configuration

### Prerequisites

```bash
# 1. PostgreSQL with nova_memory database
createdb nova_memory
psql -d nova_memory -f ~/.openclaw/workspace/nova-memory/schema.sql

# 2. Anthropic API key
export ANTHROPIC_API_KEY="your-key-here"

# 3. Required tools
sudo apt install postgresql-client jq curl
```

### Automated Setup (Cron Job)

```bash
# Add to crontab (runs every minute)
* * * * * source ~/.bashrc && /path/to/nova-memory/scripts/memory-catchup.sh >> ~/.openclaw/logs/memory-catchup.log 2>&1
```

### Manual Processing

```bash
# Process a specific message
./scripts/process-input.sh "John mentioned he loves coffee from Blue Bottle"

# Process recent messages (one-time)
./scripts/memory-catchup.sh

# Extract only (no storage)
echo "Test message" | ./scripts/extract-memories.sh

# Store pre-extracted JSON
echo '{"entities": [{"name": "John", "type": "person"}]}' | ./scripts/store-memories.sh
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
# 1. Check extraction is working
./scripts/process-input.sh "Test entity John Doe mentioned pizza"
psql -d nova_memory -c "SELECT * FROM entities WHERE name = 'John Doe';"

# 2. Verify cron job
ps aux | grep memory-catchup
ls -la ~/.openclaw/memory-catchup-state.json

# 3. Check API connectivity  
echo "Test" | ./scripts/extract-memories.sh

# 4. Database connectivity
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
- State file timestamp not updating
- Cron log shows no activity

**Diagnosis:**
```bash
# Check if cron job is running
crontab -l | grep memory-catchup

# Check for script errors
tail -50 ~/.openclaw/logs/memory-catchup.log

# Test manual execution
./scripts/memory-catchup.sh
```

**Solutions:**
1. **Missing API key:** Ensure `ANTHROPIC_API_KEY` is exported in cron environment
2. **Script permissions:** `chmod +x scripts/*.sh`
3. **Path issues:** Use absolute paths in crontab
4. **PostgreSQL down:** `sudo systemctl start postgresql`

### Issue: Duplicate Entries

**Symptoms:**
- Same entity appears multiple times with slight variations
- Facts being re-inserted

**Solutions:**
1. **Update deduplication logic** in store-memories.sh
2. **Add database constraints:**
```sql
-- Prevent duplicate entities
ALTER TABLE entities ADD CONSTRAINT unique_entity_name_type UNIQUE (name, type);

-- Prevent duplicate facts  
ALTER TABLE entity_facts ADD CONSTRAINT unique_entity_fact UNIQUE (entity_id, key, value);
```

### Issue: Poor Reference Resolution

**Symptoms:**
- Messages like "yes", "that", "do it" not being extracted
- Missing context connections

**Solutions:**
1. **Check context cache:** Verify `~/.openclaw/memory-message-cache.json` has recent messages
2. **Increase context window:** Modify CONTEXT_SIZE in memory-catchup.sh
3. **Improve Claude prompt:** Add more examples of pronoun resolution

### Issue: High API Costs

**Symptoms:**
- Large Anthropic bills
- Many API calls per minute

**Solutions:**
1. **Reduce extraction frequency:** Change cron to every 5 minutes
2. **Batch processing:** Modify catchup script to process multiple messages per API call
3. **Filter trivial messages:** Skip messages like "ok", "thanks", emoji-only

## Advanced Configuration

### Rate Limiting

Edit `memory-catchup.sh`:
```bash
# Change from 3 messages per run to 1
MAX_MESSAGES_PER_RUN=1

# Add delay between messages  
sleep 2
```

### Custom Extraction Categories

Modify the prompt in `extract-memories.sh` to add new categories:
```bash
# Add "tasks" category
echo "tasks: actionable items or todo items with deadlines"
```

### Database Schema Extensions

Add new tables for specialized data:
```sql
-- Track extraction metrics
CREATE TABLE extraction_stats (
    id SERIAL PRIMARY KEY,
    script VARCHAR(50),
    message_count INT,
    api_calls INT,
    errors INT,
    runtime_seconds INT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

## Integration with OpenClaw

### Hook Installation

For automatic extraction on incoming messages:
```bash
cp -r hooks/memory-extract ~/.openclaw/workspace/hooks/
openclaw hooks enable memory-extract
export NOVA_MEMORY_SCRIPTS="/path/to/nova-memory/scripts"
```

### Memory Search Integration

The extracted data becomes searchable via OpenClaw's memory system:
```bash
# Semantic search across all memory
/memory_search "pizza places in Brooklyn" 

# Database queries
psql -d nova_memory -c "SELECT * FROM places WHERE location ILIKE '%brooklyn%';"
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

### Batch Processing

For high-volume systems, modify memory-catchup.sh to process multiple messages per API call:
```bash
# Instead of 1 message per API call
# Batch 5 messages together
BATCH_SIZE=5
```

**Note for Documentation Team:** The memory extraction pipeline's sophisticated NLP processing chain and context window management would benefit from **Quill haiku collaboration** to explain complex concepts like reference resolution and deduplication in accessible metaphors.

## Next Steps

1. **Set up monitoring:** Implement extraction metrics tracking
2. **Tune performance:** Adjust batch sizes and API limits based on usage
3. **Extend categories:** Add task extraction, sentiment analysis
4. **Add validation:** Implement data quality checks and correction flows

The memory extraction pipeline is the heart of nova-memory's automatic learning capability. Understanding and maintaining it properly ensures your AI assistant continuously builds comprehensive, searchable knowledge from every conversation.