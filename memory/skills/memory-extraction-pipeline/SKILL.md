---
name: memory-extraction-pipeline
description: Automated pipeline that processes chat messages to extract memories, facts, and vocabulary
---

# Memory Extraction Pipeline

## Trigger
Runs via `message.received` hook (NOT cron) - fires on every incoming message.

## Tools

- `memory-catchup.sh` - Main pipeline orchestrator
- `process-input.sh` - Entry point for extraction
- `extract-memories.sh` - Claude-powered extraction (claude-sonnet-4)
- `store-memories.sh` - PostgreSQL storage with deduplication
- `psql` - Database operations

## Context Window (2026-02-07)

**20-message rolling cache** stored in `~/.openclaw/memory-message-cache.json`

- Interleaved user + assistant messages (chronological)
- ~10 exchanges worth of conversation
- Expires oldest as new messages arrive

**Format passed to extraction:**
```
[USER] 1: How much do crawlers cost?
[NOVA] 2: About $130M in today's dollars...
[USER] 3: Let's build one for Burning Man
[NOVA] 4: That would be legendary...
---
[CURRENT USER MESSAGE - EXTRACT FROM THIS]
Yes, keep the aesthetic
```

## Bidirectional Extraction

**BOTH user AND assistant messages get processed:**
- User message → extracted with NOVA's responses as context
- NOVA message → extracted with user's messages as context

This captures:
- What the user said/decided/prefers
- What NOVA did/updated/created

## Reinforcement Learning (Vote-Based Confidence)

**Instead of deduplication, matching data REINFORCES existing knowledge:**

**Schema:**
- `vote_count INTEGER DEFAULT 1` - incremented on each re-confirmation
- `last_confirmed TIMESTAMP` - tracks recency of confirmation

**Layer 1 - Extraction Prompt:**
- Queries existing facts/vocab for context
- Extracts even if similar fact exists (for reinforcement)

**Layer 2 - Storage Script:**
- `fact_find_match()` - fuzzy match on entity+key+value, returns ID
- `reinforce_fact()` - increments vote_count, updates last_confirmed
- Logs `↑ (reinforced, +1 vote)` when strengthening existing facts

**Benefits:**
- Facts mentioned once = low confidence (vote_count: 1)
- Facts mentioned repeatedly = high confidence (vote_count: 10+)
- Enables confidence-weighted retrieval
- Can detect stale knowledge via last_confirmed

## Procedure

1. Hook triggers `memory-catchup.sh` on message.received
2. Finds new messages (user + assistant) from session transcript
3. Builds 20-message context window from cache
4. Labels messages: `[USER] N:` / `[NOVA] N:` / `[CURRENT MESSAGE]`
5. Calls `process-input.sh` with full context
6. `extract-memories.sh` uses Claude to extract: entities, facts, opinions, preferences, events, vocabulary
7. `store-memories.sh` checks for duplicates, inserts new data
8. If NEW vocabulary added → STT service auto-restarts
9. Rate limited: 3 messages per run

## Extracted Categories

- **entities** - people, organizations, AIs, places
- **facts** - subject.predicate = value
- **opinions** - who thinks what about what
- **preferences** - who prefers what (category)
- **events** - things that happened (with dates)
- **vocabulary** - new words for STT (with misheard variants)

## Privacy

- `source_person` attribution on all extractions
- `visibility` field (public/private/shared)
- Per-user `default_visibility` preference
- Override detection via privacy cues in text

## Files

- Cache: `~/.openclaw/memory-message-cache.json`
- State: `~/.openclaw/memory-catchup-state.json`
- Logs: `~/.openclaw/logs/memory-extractions.log`
- Scripts: `~/.openclaw/workspace/scripts/memory-*.sh`, `extract-memories.sh`, `store-memories.sh`

## Notes

- Use `--log` flag for verbose extraction logging
- Context resolves references like "yes", "that", "do it"
- Both speakers' messages build shared context
- My actions become part of my memory, not just user's
