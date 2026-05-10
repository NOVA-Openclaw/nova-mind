---
name: memory-extract
description: "Extracts memories from incoming messages and stores in database"
metadata: {"openclaw":{"emoji":"🧠","events":["message:received"]}}
---

# Memory Extraction Hook

Automatically extracts entities, facts, opinions, and relationships from incoming messages and stores them in the PostgreSQL memory database.

## What It Does

1. Receives the incoming message and extracts sender info from the canonical hook context
2. Sender fields (`senderName`, `senderId`, `isGroup`, `senderUsername`, `senderTag`, `provider`, `channelName`, `guildId`) are resolved from `ctx.metadata` with top-level `ctx.*` fallbacks
3. Upserts `channel_sessions` and `channel_transcripts` rows in real-time, then passes FK IDs to the extraction subprocess
4. Runs the extraction pipeline (`process-input.sh`) via stdin for secure, shell-injection-free message processing

## Sender Field Resolution

Sender fields are read from the canonical location to support both old and new context shapes:

| Field | Resolution Order | Example |
|-------|-----------------|---------|
| `senderName` | `meta.senderName ?? ctx.senderName ?? ctx.from ?? "unknown"` | I)ruid |
| `senderId` | `meta.senderId ?? ctx.senderId ?? ""` | 330189773371080716 |
| `senderUsername` | `meta.senderUsername ?? ctx.senderUsername ?? ""` | druidian |
| `senderTag` | `meta.senderTag ?? ctx.senderTag ?? ""` | tag_123 |
| `isGroup` | `meta.isGroup ?? ctx.isGroup ?? false` | true/false |
| `provider` | `meta.provider ?? ctx.provider ?? ctx.channelId ?? "openclaw"` | discord |
| `channelName` | `meta.channelName ?? ctx.channelName ?? ""` | #software-engineering |
| `guildId` | `meta.guildId ?? ctx.guildId ?? ""` | 1492385947927445524 |

When metadata is absent (legacy context), the hook falls back to top-level `ctx.*` fields. When both are missing, defaults apply (`"unknown"`, `""`, `false`).

## Channel Transcript Upsert

### psql `RETURNING id` Parsing

The hook uses `psql -t -A` to insert/upsert `channel_sessions` and `channel_transcripts` rows and fetch the generated id via `RETURNING id`. However, psql may include a status line like `INSERT 0 1` alongside the actual id value.

**Parsing strategy:**
- Regex `/^(\d+)/m` extracts the first numeric line from the output
- Works for clean output: `"42"` → `"42"`
- Handles status line: `"42\nINSERT 0 1"` → `"42"`
- Handles empty (conflict DO NOTHING): `""` → `""` (no FK pointer)
- On psql failure (connection error, missing executable), the `.catch()` logs a warning and extraction continues without FK pointers

### senderUsername in Transcripts

When available, `sender_username` is conditionally included in the `channel_transcripts` INSERT alongside `sender_id` and `sender_name`. This ensures Discord usernames (e.g., `druidian`) are preserved for entity resolution.

## Security

The hook uses `spawn()` with stdin pipes to pass message text securely, avoiding shell injection vulnerabilities. Environment variables (`SENDER_NAME`, `SENDER_ID`, `IS_GROUP`, `SOURCE_CHANNEL_TRANSCRIPT_ID`, `SOURCE_CHANNEL_SESSION_ID`) are passed via the `env` option, not shell string interpolation. The underlying scripts sanitize `SENDER_ID` and use SQL parameterization to prevent injection.

See test cases at `tests/TEST-CASES-ISSUE-179.md` for edge cases including metadata fallback, psql parsing, and graceful failure.
