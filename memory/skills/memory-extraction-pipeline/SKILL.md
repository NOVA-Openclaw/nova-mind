---
name: memory-extraction-pipeline
description: Automated pipeline that processes chat messages to extract memories, facts, and vocabulary
---

# Memory Extraction Pipeline

> **Updated (nova-mind#485 documentation audit):** This file described the pre-#174
> shell pipeline (`process-input.sh` → `extract-memories.sh` → `store-memories.sh`,
> orchestrated by `memory-catchup.sh` on every `message.received` event). That pipeline
> was consolidated into a single Python script, `memory/scripts/extract_memories.py`,
> as part of the #174 grammar-parser removal. None of `extract-memories.sh`,
> `store-memories.sh`, or `process-input.sh` exist in `memory/scripts/` anymore, and
> `memory-catchup.sh` is a separate cron-driven session-transcript ingestion path, not
> the real-time extraction trigger. This revision documents the current pipeline. See
> `memory/docs/memory-extraction-pipeline.md` for the full guide (setup, troubleshooting,
> failure-handling/dead-letter path added in #485).

## Trigger

Runs via the `memory-extract` OpenClaw hook, which fires on `message.received` events —
**not** via `memory-catchup.sh` and not via cron. `memory-catchup.sh` is a separate,
cron-driven path that ingests session JSONL transcripts into `channel_sessions`/
`channel_transcripts`; it does not perform real-time per-message extraction (its
attempt to also invoke a legacy `process-input.sh` for message-level re-extraction is a
known-broken code path — see `memory/docs/memory-extraction-pipeline.md`'s top-of-file
note).

## Tools

- `memory/hooks/memory-extract/handler.ts` — hook entry point; spawns the extraction
  process per message, resolves `channel_transcripts`/`channel_sessions` FK pointers,
  captures stderr/stdout tails, enforces a timeout, and writes to `extraction_failures`
  on failure (#485)
- `memory/scripts/extract_memories.py` — single Python script that calls the Claude API
  to parse a message into structured JSON (facts, entities, events, vocabulary) in one
  pass; replaces the old three-script shell chain
- `memory/scripts/dedup_helper.py` — deduplication / reinforcement logic
- `memory/scripts/extraction-replay.sh` — replays dead-lettered failures from
  `extraction_failures` (#485)
- `psql` — database operations

## Context Window

Real-time extraction context resolution happens per-message via the hook's own context
passing — there is no separate cache file for this path. (`memory-catchup.sh`
separately maintains its own rolling cache at `~/.openclaw/memory-message-cache.json`
for its transcript-ingestion path; that cache is unrelated to real-time extraction.)

## Bidirectional Extraction

Both user and assistant messages are processed:
- User message → extracted with prior context available
- Assistant message → extracted with prior context available

This captures both what the user said/decided/prefers and what the agent did/updated/created.

## Reinforcement (Vote-Based Confidence)

Instead of deduplication, matching data reinforces existing knowledge:

**Schema (`entity_facts`):**
- `extraction_count INTEGER` — incremented on each re-extraction/reinforcement
- `last_confirmed_at TIMESTAMPTZ` — tracks recency of confirmation
- `durability VARCHAR(20)` — `permanent`, `long_term`, `short_term`, `ephemeral`
- `category TEXT` — free-form (e.g., `identity`, `preference`, `observation`)
- `visibility VARCHAR(20)` — `public`, `trusted`, `private`

Source attribution lives in `entity_fact_sources` (one row per fact-source pair), not a
single column on `entity_facts`.

`dedup_helper.py` performs fuzzy matching on entity+key+value to find an existing fact
and reinforce it (increment `extraction_count`, update `last_confirmed_at`) rather than
inserting a duplicate.

## Procedure (Current)

1. `memory-extract` hook fires on `message.received`
2. Hook resolves/upserts `channel_sessions` + `channel_transcripts` FK pointers if not
   already present in the event context
3. Hook spawns `extract_memories.py` via stdin (never as a shell argument), passing
   sender/session metadata as environment variables (`SENDER_NAME`, `SENDER_ID`,
   `IS_GROUP`, `SOURCE_SESSION_ID`, `SOURCE_TIMESTAMP`, `SOURCE_CHANNEL_TRANSCRIPT_ID`,
   `SOURCE_CHANNEL_SESSION_ID`)
4. `extract_memories.py` calls the Claude API once to extract facts, entities, events,
   and vocabulary, and writes directly to PostgreSQL (via `dedup_helper.py` for
   reinforcement logic)
5. **On success:** hook logs completion. **On failure (nonzero exit, timeout, or spawn
   error):** hook writes a dead-letter row to `extraction_failures` instead of losing the
   message (#485) — see `memory/docs/memory-extraction-pipeline.md` for the full
   failure-handling section and the `extraction-replay.sh` recovery path
6. If new vocabulary is added, the STT service picks it up (see the vocabulary docs for
   the current reload mechanism — verify against `extract_memories.py`'s current output
   contract before relying on this)

## Extracted Categories

Per `extract_memories.py`'s current extraction template (see the script for the
authoritative/up-to-date list):
- **facts** — entity-scoped key/value facts, each carrying `subject`, `key`, `value`,
  `category`, `durability`, `confidence`, `visibility` (covers what used to be split
  across separate facts/opinions/preferences categories, disambiguated via `category`)
- **entities** — people, AIs, organizations, places
- **events** — things that happened (with dates)
- **vocabulary** — new words for STT correction

## Privacy

- Source attribution via `entity_fact_sources`, not a single `source_person` column
- `visibility` field (`public`/`trusted`/`private`) on `entity_facts`
- **Note:** privacy/visibility filtering is schema-ready but not yet enforced at
  retrieval time — see `memory/ARCHITECTURE.md`'s Entity Facts Access Control section
  for the current (as of this writing) enforcement gap
