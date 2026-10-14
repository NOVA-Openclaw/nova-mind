---
name: memory-extract
description: "Extracts memories from incoming messages and stores in database"
metadata: {"openclaw":{"emoji":"🧠","events":["message:received"]}}
---

# Memory Extraction Hook

Automatically extracts entities, facts, opinions, and relationships from incoming messages and stores them in the PostgreSQL memory database.

This is a **legacy internal hook** installed into `~/.openclaw/hooks/`.  The
legacy loader requires a static `events` field in `HOOK.md` and expects
`handler.ts` to default-export an async function `(event) => Promise<void>`.

## What It Does

1. Receives the incoming message and extracts sender info from the canonical hook context
2. Sender fields (`senderName`, `senderId`, `isGroup`, `senderUsername`, `senderTag`, `provider`, `channelName`, `guildId`) are resolved from `ctx.metadata` with top-level `ctx.*` fallbacks
3. Upserts `channel_sessions` and `channel_transcripts` rows in real-time, then passes FK IDs to the extraction subprocess
4. Spawns `extract_memories.py` directly (interpreter resolved by `resolvePythonCmd()` — see below — no shell wrapper) and feeds the message body over **stdin** for secure, shell-injection-free processing. There is no `process-input.sh` in this repo's `memory/scripts/` — the hook's `scriptPath` points straight at `extract_memories.py` (overridable via `EXTRACTION_SCRIPT_PATH_OVERRIDE`, used by tests to point at a mock script).

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

## Interpreter Resolution (nova-mind#554, #555)

Both spawn paths that invoke `extract_memories.py` — this plugin's `handler.ts` and the standalone `extraction-replay.sh` — resolve the Python interpreter with the same first-match-wins order via `resolvePythonCmd()` (handler.ts) / `resolve_python_cmd()` (extraction-replay.sh):

1. `EXTRACTION_PYTHON_CMD_OVERRIDE` environment variable (test-only)
2. `python_cmd` key in `~/.openclaw/scripts/memory-extraction-config.json` (read fresh per event — hot-reload friendly, same as `extraction_timeout_ms`)
3. Agent venv python at `~/.local/share/<user>/venv/bin/python3`, if present
4. Bare `python3` from `PATH`

The plugin logs the result once per invocation so deploy verification can confirm which interpreter is actually selected in production — useful when diagnosing `ModuleNotFoundError` failures caused by the wrong python being picked (see Troubleshooting in `memory/docs/memory-extraction-pipeline.md`).

`extraction-replay.sh` derives the venv path using `$(id -un)` rather than `$USER`, because `$USER` is unset under cron and would otherwise silently collapse the venv path and fall through to bare `python3` under cron (nova-mind#555).

**Graceful `json_repair` degradation (nova-mind#554):** `extract_memories.py`'s `json_repair` import is lazy and guarded, not a top-level unconditional import. If the resolved interpreter's environment lacks `json_repair` (e.g. it resolved to bare system `python3` instead of the venv), the extraction still completes end-to-end — one stderr warning is logged, no repair attempt is made, and malformed JSON goes straight to exit code 2 / `failure_reason='json_parse_failure'`.

## Timeout and Failure Handling (nova-mind#485, #497)

The plugin spawns `extract_memories.py` as a child process and enforces a timeout on it. If the child exceeds the timeout, is killed, exits nonzero, fails to spawn, or exits with code 2, the plugin writes a dead-letter row to the `extraction_failures` table instead of silently dropping the message. Full mechanism, schema, and replay path: `memory/docs/memory-extraction-pipeline.md` (sections "1a. Failure Handling" and "1b. JSON Repair and Parse-Failure Handling").

**Timeout:** Read per-event from `extraction_timeout_ms` in `~/.openclaw/scripts/memory-extraction-config.json` (`loadExtractionTimeoutMs()`), with no caching — every event does a fresh file read, so edits hot-reload on the next message with no gateway restart. Precedence: `EXTRACTION_TIMEOUT_MS_OVERRIDE` env var (test-only) > config file > hardcoded default. Default is **90000ms (90s)**, chosen because the Python child's own inner HTTP request timeout (`requests.post(..., timeout=60)` in `extract_memories.py`) is 60s — the outer hook timeout must exceed it so a slow LLM call fails cleanly inside the child (raising a normal error, exit 1) rather than being `SIGTERM`'d by the plugin mid-request. On timeout, the plugin sends `SIGTERM`, then `SIGKILL` after a 5-second grace period if the child hasn't exited.

**Exit-code contract:**

| Exit code | Meaning | `failure_reason` written |
|-----------|---------|---------------------------|
| `0` | Success | — (no dead-letter row) |
| `1` | Generic error | `nonzero_exit` |
| `2` | JSON parse/repair failure (`JsonParseFailure` in `extract_memories.py`) | `json_parse_failure` |

Timeout detection takes precedence over exit-code inspection in the plugin's `child.on('close', ...)` handler: a killed-for-timeout child is always recorded as `failure_reason='timeout'`, regardless of what exit code the killed process happens to report.

## Lifecycle and Summary Logging (nova-mind#716)

All output is routed through `api.logger` captured at registration time:

* **Startup:** one INFO line at registration with version, resolved memory DB name, DB resolution source (`PGDATABASE` or `postgres.json`), Python interpreter path, and extraction model. If DB resolution fails, one immediate ERROR line.
* **Shutdown:** one INFO line on `gateway_stop` with session totals (`received / extracted / stored / skipped / failed`), even with zero activity.
* **Periodic summary:** one INFO line every 30 minutes (configurable via `pluginConfig.summaryIntervalMs`) **only if there was activity** since the last summary; includes counts and the timestamp of the last successful store.
* **Failures:** one WARN/ERROR line per failure with a stable reason token (`db_unresolved`, `db_unreachable`, `peer_guard_refused`, `extractor_spawn_failed`, `extractor_exit_nonzero`, `provider_key_missing`, `timeout`) and the session key. `db_unresolved` after startup is rate-limited to once per 10 minutes.
* **Stall warning:** one WARN line when messages arrived but nothing was stored for more than 6 hours (configurable via `pluginConfig.stallThresholdMs`); repeats at most once per hour (configurable via `pluginConfig.stallRepeatIntervalMs`) while still stalled; one INFO `stall recovered` line on recovery.

Timers are unref'd so they do not keep the gateway process alive, and are cleared on `gateway_stop`.

## Channel Transcript Upsert

### psql `RETURNING id` Parsing

The plugin uses `psql -t -A` to insert/upsert `channel_sessions` and `channel_transcripts` rows and fetch the generated id via `RETURNING id`. However, psql may include a status line like `INSERT 0 1` alongside the actual id value.

**Parsing strategy:**
- Regex `/^(\d+)/m` extracts the first numeric line from the output
- Works for clean output: `"42"` → `"42"`
- Handles status line: `"42\nINSERT 0 1"` → `"42"`
- Handles empty (conflict DO NOTHING): `""` → `""` (no FK pointer)
- On psql failure (connection error, missing executable), the `.catch()` logs a warning and extraction continues without FK pointers

### senderUsername in Transcripts

When available, `sender_username` is conditionally included in the `channel_transcripts` INSERT alongside `sender_id` and `sender_name`. This ensures Discord usernames (e.g., `druidian`) are preserved for entity resolution.

## Security

The plugin uses `spawn()` with stdin pipes to pass message text securely, avoiding shell injection vulnerabilities. Environment variables (`SENDER_NAME`, `SENDER_ID`, `IS_GROUP`, `SOURCE_CHANNEL_TRANSCRIPT_ID`, `SOURCE_CHANNEL_SESSION_ID`) are passed via the `env` option, not shell string interpolation. The underlying scripts sanitize `SENDER_ID` and use SQL parameterization to prevent injection.

Log lines intentionally contain **only** the resolved DB name, session key, and safe operational metadata — never message bodies, connection credentials, or API key values.

See test cases at `tests/TEST-CASES-ISSUE-716.md` for the full logging acceptance matrix.
