# Test Cases: Issue #179 — Sender Fields + psql Parsing Fix

**Branch:** `fix/issue-179-sender-fields-and-psql-parsing`
**Batched with:** nova-openclaw #41 (parallel)

---

## Sender Fields from ctx.metadata

### TC-001: Discord message — sender fields populated
**Input:** Discord message from I)ruid in #software-engineering
**Context shape:**
```json
{
  "from": "discord:channel:1492386247862390824",
  "content": "test message",
  "metadata": {
    "senderId": "330189773371080716",
    "senderName": "I)ruid",
    "senderUsername": "druidian",
    "provider": "discord",
    "guildId": "1492385947927445524",
    "channelName": "#software-engineering"
  }
}
```
**Expected:**
- `SENDER_NAME=I)ruid` passed to extraction subprocess
- `SENDER_ID=330189773371080716` passed to extraction subprocess
- `channel_transcripts` row has `sender_id='330189773371080716'`, `sender_name='I)ruid'`, `sender_username='druidian'`

### TC-002: Signal message — sender fields from metadata
**Input:** Signal group message with metadata containing `senderId`, `senderName`
**Expected:** Same extraction path works, sender fields populated from `ctx.metadata`.

### TC-003: Fallback to top-level ctx fields
**Input:** Message where `ctx.metadata` is absent but `ctx.senderName` exists at top level (e.g. after nova-openclaw #41 is deployed)
**Expected:** Hook reads from top-level `ctx.senderName` / `ctx.senderId` as fallback. Both paths work.

### TC-004: Missing metadata and top-level sender — graceful default
**Input:** Message with no sender info anywhere (no `ctx.metadata.senderName`, no `ctx.senderName`)
**Expected:** `senderName` defaults to `"unknown"`, `senderId` defaults to `""`. No crash. Transcript row created with NULL sender fields.

### TC-005: Provider detection from metadata
**Input:** Discord message with `ctx.metadata.provider = "discord"`
**Expected:** `channel_sessions` row has `provider='discord'` (not 'openclaw'). Provider read from `ctx.metadata.provider` with fallbacks to `ctx.provider`, then `ctx.channelId`.

### TC-006: Group metadata from ctx.metadata
**Input:** Message with `ctx.metadata.guildId = "1492385947927445524"` and `ctx.metadata.channelName = "#software-engineering"`
**Expected:** `channel_sessions` row has `group_space_id='1492385947927445524'`, `group_subject='#software-engineering'`, `title='#software-engineering'`.

### TC-007: isGroup detection
**Input:** Message with `ctx.metadata` present but no `isGroup` field. `ctx.metadata.channelName` is set (indicating a group channel).
**Expected:** `chat_type` correctly determined. Falls back to checking `channelName` or `guildId` presence.

---

## psql RETURNING id Parsing

### TC-008: psql output with INSERT status line
**Input:** psql `-t -A` returns `"11\nINSERT 0 1"` from `RETURNING id` on conflict update
**Expected:** Regex `stdout.match(/^(\d+)/m)` extracts `"11"` correctly. Session ID set, transcript upsert proceeds.

### TC-009: psql output clean single line
**Input:** psql returns `"42"` (new row, no conflict)
**Expected:** Regex extracts `"42"` correctly.

### TC-010: psql output empty (conflict DO NOTHING, no RETURNING)
**Input:** psql returns empty string (duplicate message, `ON CONFLICT DO NOTHING`)
**Expected:** `resolvedTranscriptId` is empty. No crash. FK pointers not set (acceptable for duplicates).

### TC-011: psql failure — connection error
**Input:** psql executable not found or connection fails
**Expected:** `.catch()` handler fires, logs warning with error message. Extraction continues without FK pointers.

---

## Semantic Recall JSON Payload

### TC-012: semantic-recall reads sender from metadata
**Verification:** The JSON stdin payload constructed by `semantic-recall/handler.ts` reads sender fields from `event.context.metadata`:
```typescript
senderId: meta.senderId ?? ctx.senderId ?? '',
senderName: meta.senderName ?? ctx.senderName ?? '',
provider: meta.provider ?? ctx.provider ?? '',
```
**Expected:** JSON payload contains correct sender/provider values, not empty strings.

### TC-013: Backward compatibility — top-level fields after #41
**Input:** After nova-openclaw #41, sender fields available at top level
**Expected:** The `meta.X ?? ctx.X` fallback chain works — reads from whichever level has the data.

---

## Regression

### TC-014: Content extraction still works
**Verification:** `ctx.content` still used as primary message body source.
**Expected:** No regression from #174 fix.

### TC-015: Channel transcript upsert still creates rows
**Verification:** After fix, both `channel_sessions` and `channel_transcripts` rows created on every message.
**Expected:** `message_count` increments, `last_message_at` updates.

### TC-016: entity_facts source pointers still wired
**Verification:** Extracted facts have non-NULL `source_channel_transcript_id` and `source_channel_session_id`.
**Expected:** End-to-end FK wiring from fact → transcript → session.
