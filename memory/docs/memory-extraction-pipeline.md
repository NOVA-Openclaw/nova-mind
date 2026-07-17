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
                                              ↓ (nonzero exit / timeout / spawn error)
                                        extraction_failures dead-letter row (#485)
                                              ↓
                                        extraction-replay.sh (manual or cron) → retry

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

### 1a. Failure Handling: `extraction_failures` Dead-Letter Table + Replay (#485)

**Problem this solves:** Before #485, the `memory-extract` hook spawned `extract_memories.py` as fire-and-forget — no stderr/stdout capture, no retry, no persistence of the failed message. A System Diagnostic run (#447) found ~10% of extractions failing silently (10 of 112 messages in a 33-hour window), and because the message body only exists at hook time, a failed extraction lost those facts permanently.

**What changed:**

- **Stderr/stdout capture.** The hook now attaches a tail-buffer reader (`attachTailBuffer()`) to the child's `stderr`/`stdout` streams, retaining only the **last 16384 bytes** (`PIPE_TAIL_CAP_BYTES`) of each. This also prevents the latent hang risk noted in #447 — an unread pipe stalls a child writing more than the OS pipe buffer (~64KB), and continuously draining the stream (even while discarding old bytes) keeps the child unblocked.
- **Child-process timeout.** Extraction now has a hard **30-second timeout** (`EXTRACTION_TIMEOUT_MS`). On timeout, the hook sends `SIGTERM`, then `SIGKILL` after a **5-second grace period** (`KILL_GRACE_MS`) if the child hasn't exited.
- **`extraction_failures` dead-letter table** (migration `085_extraction_failures.sql`). On nonzero exit, timeout, or spawn error, the hook inserts a row capturing the message body (or a `channel_transcript_id` FK when available), sender/session metadata, the captured stderr/stdout tails, exit code, and a `failure_reason`.
- **Failure-reason taxonomy** (`failure_reason` CHECK constraint): `nonzero_exit`, `timeout`, `spawn_error`, `unreplayable` (the last one is set only by the replay script, never by the hook — see below).
- **Logged `psql` catches.** The two `channel_sessions`/`channel_transcripts` upsert calls that previously swallowed errors via `.catch(() => ({stdout: ''}))` now log the error message (via `logPsqlError()`) before returning the same empty-stdout fallback — behavior is unchanged, but failures are no longer silent.
- **Replay script** (`memory/scripts/extraction-replay.sh`, installed to `~/.openclaw/scripts/` by the standard scripts-copy step in `agent-install.sh` — no special-cased install logic was needed since it's just another `.sh` file in `memory/scripts/`). See below for details.

**`extraction_failures` schema (migration 085):**

| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL | PK |
| `channel_transcript_id` | BIGINT | FK → `channel_transcripts(id)`, **`ON DELETE SET NULL`** — deleting the parent session cascades to `channel_transcripts`, but the dead-letter row survives with a NULL FK so failure evidence is retained |
| `session_key`, `sender_name`, `sender_id` | TEXT | Attribution metadata |
| `content` | TEXT | Raw message body **fallback**, capped at 65535 chars — only populated when no transcript FK is available; when the FK is intact, this column is left NULL to avoid duplicating the body |
| `stderr_tail`, `stdout_tail` | TEXT | Captured pipe tails (up to 16384 bytes each, last-N-bytes semantics) |
| `exit_code` | INTEGER | NULL for `timeout`/`spawn_error` (no exit code available) |
| `failure_reason` | VARCHAR(50) | CHECK: `nonzero_exit`, `timeout`, `spawn_error`, `unreplayable` |
| `retry_count` | INTEGER | Default 0, CHECK `>= 0`, incremented by the replay script on each failed retry |
| `status` | VARCHAR(20) | CHECK: `pending`, `resolved`, `retry_exhausted`, `unreplayable` — see state machine below |
| `created_at`, `updated_at`, `last_attempt_at`, `resolved_at` | TIMESTAMPTZ | Standard lifecycle timestamps |

**Status state machine:**

```
pending  ──(replay succeeds)──────────────► resolved
   │
   ├──(replay fails, retry_count < MAX_RETRIES)──► pending (retry_count++)
   │
   ├──(replay fails, retry_count >= MAX_RETRIES)──► retry_exhausted
   │
   └──(no channel_transcript_id AND no content fallback)──► unreplayable
```

Named indexes: `idx_extraction_failures_status` (eligibility filter), `idx_extraction_failures_channel_transcript_id` (partial, `WHERE channel_transcript_id IS NOT NULL`), `idx_extraction_failures_created_at` (age-based monitoring), `idx_extraction_failures_replay_order` (composite on `status, retry_count ASC, created_at ASC, id ASC` — matches the replay script's batch-selection query exactly).

**`extraction-replay.sh` — replay path:**

Following the `memory-catchup.sh` cron-script pattern (and per `GLOBAL/CRON_DESIGN`: DB writes belong in the script, not an agent-turn prompt), `extraction-replay.sh`:

1. Acquires an exclusive **non-blocking flock** on `~/.openclaw/run/extraction-replay.lock` (fd 200) — if another invocation holds the lock, the script logs and exits 0 immediately rather than blocking or double-processing.
2. Sources `~/.openclaw/lib/env-loader.sh` (API keys) and `~/.openclaw/lib/pg-env.sh` (PostgreSQL env vars), same as other cron scripts in this repo.
3. Fetches up to `EXTRACTION_REPLAY_BATCH_LIMIT` (default **10**) pending rows via `SELECT row_to_json(t) FROM (...) t`, ordered `status, retry_count ASC, created_at ASC, id ASC` (same ordering as the replay-order index). Rows are parsed with `jq` — **`row_to_json` + `jq` was a QA-driven fix (BUG-1)**: an earlier pipe-delimited (`-A`) parse broke on message bodies containing embedded pipe characters or newlines; `row_to_json` safely escapes both.
4. For each row: reconstructs the message body from `channel_transcripts.content` (when `channel_transcript_id` is set) or the row's own `content` fallback. **If neither is available, the row is marked `unreplayable` immediately** — this is a terminal state; the script does not retry these rows on future runs.
5. Feeds the reconstructed body to `extract_memories.py` via **stdin** (never as a shell argument — same untrusted-input rule as the hook itself, #155), passing the same `SENDER_NAME`/`SENDER_ID`/`SOURCE_*` environment variables the hook would have set.
6. On success: `status='resolved'`, `resolved_at=NOW()`.
7. On failure: `retry_count` is incremented and `last_attempt_at=NOW()`. If the new `retry_count >= EXTRACTION_REPLAY_MAX_RETRIES` (default **5**), status becomes `retry_exhausted` (another terminal state — no further automatic retries). Otherwise the row stays `pending` for the next run.

**Environment variables (script-level overrides):**

| Variable | Default | Purpose |
|----------|---------|---------|
| `EXTRACTION_REPLAY_BATCH_LIMIT` | `10` | Max rows processed per invocation |
| `EXTRACTION_REPLAY_MAX_RETRIES` | `5` | Retry ceiling before `retry_exhausted` |
| `EXTRACTION_SCRIPT_PATH_OVERRIDE` | `~/.openclaw/scripts/extract_memories.py` | Same override var the hook uses — lets tests point at a mock script |
| `PGDATABASE` | `nova_memory` | **Hardcoded fallback default, not user/host-dynamic** — tracked as known debt under #487 (umbrella) / #481, same class of issue as the hook's own `PGDATABASE` fallback below. Documenting current behavior; no new issue needed. |

**Manually triggering a replay run:**

```bash
~/.openclaw/scripts/extraction-replay.sh
```

**Inspecting dead-letter rows:**

```sql
-- Pending failures awaiting replay
SELECT id, sender_name, failure_reason, retry_count, created_at
FROM extraction_failures
WHERE status = 'pending'
ORDER BY created_at ASC;

-- Rows that exhausted retries (needs manual investigation)
SELECT id, sender_name, failure_reason, stderr_tail, retry_count
FROM extraction_failures
WHERE status = 'retry_exhausted';

-- Permanently unreplayable rows (no FK, no body fallback)
SELECT id, sender_name, created_at
FROM extraction_failures
WHERE status = 'unreplayable';
```

**Known tracked debt:** Both the hook (`handler.ts`) and `extraction-replay.sh` fall back to a hardcoded `PGDATABASE` default of `nova_memory` rather than deriving it from the current OS user the way the rest of the installer does (see `memory/INSTALLATION.md`'s dynamic-DB-naming section). This is tracked by issue **#487** (umbrella, Tier 1) and **#481** — no new issue is needed; this doc describes current (as-shipped) behavior only.

**Setting up automatic replay (cron):** As of this writing, `extraction-replay.sh` is deployed to `~/.openclaw/scripts/` by the installer's generic scripts-copy step, but **no cron entry installs it automatically** (unlike `generate-daily-log.py`, which gets a dedicated installer step — see `memory/INSTALLATION.md`). Add a crontab entry manually if you want scheduled replay, e.g.:

```bash
# Replay failed extractions every 15 minutes
*/15 * * * * ~/.openclaw/scripts/extraction-replay.sh >> ~/.openclaw/logs/extraction-replay.log 2>&1
```

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

### Issue: Extraction Fails Silently (Historical — Fixed by #485)

**Symptoms (pre-#485):** No new `entity_facts`/`events` rows for a specific message, no error visible anywhere, and the original message body is unrecoverable since it only existed transiently at hook invocation time.

**Fixed by #485:** The hook now captures stderr/stdout tails, enforces a 30s timeout, and writes a dead-letter row to `extraction_failures` on any failure (nonzero exit, timeout, or spawn error) — the message body (or its transcript FK) is preserved and can be replayed via `extraction-replay.sh`. See "Failure Handling" above for the full mechanism.

**Diagnosis:**
```sql
SELECT id, sender_name, failure_reason, stderr_tail, created_at
FROM extraction_failures
WHERE status = 'pending'
ORDER BY created_at DESC
LIMIT 20;
```

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
2. **Add a cron entry for `extraction-replay.sh`** (#485) — the script is deployed but not scheduled by default; see the "Setting up automatic replay" note above
3. **Set up monitoring:** Implement extraction metrics tracking, including alerting on `extraction_failures` row growth (e.g., pending count exceeding a threshold, or a rising `retry_exhausted`/`unreplayable` count)
4. **Tune performance:** Adjust batch sizes and API limits based on usage
5. **Extend categories:** Add task extraction, sentiment analysis
6. **Add validation:** Implement data quality checks and correction flows

The memory extraction pipeline is the heart of nova-memory's automatic learning capability. Understanding and maintaining it properly ensures your AI assistant continuously builds comprehensive, searchable knowledge from every conversation.
