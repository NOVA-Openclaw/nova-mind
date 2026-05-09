# Test Cases: Issues #165, #138, #170 — Channel Transcripts + Memory Reinforcement

**Branch:** `feature/issue-165-138-memory-reinforcement`
**Migration:** `memory/migrations/067_channel_sessions_transcripts.sql`

---

## TC-001: Happy Path — Discord Message Ingestion

**Input:** JSONL file containing a Discord message with full untrusted metadata:
```json
{
  "chat_id": "channel:1492386247862390824",
  "message_id": "1502589947721547817",
  "sender_id": "330189773371080716",
  "conversation_label": "#software-engineering channel id:1492386247862390824",
  "sender": "I)ruid",
  "timestamp": "Sat 2026-05-09 08:36 UTC",
  "group_subject": "#software-engineering",
  "group_channel": "#software-engineering",
  "group_space": "1492385947927445524",
  "is_group_chat": true
}
```

**Expected:**
- `channel_sessions` row created with `provider='discord'`, `external_chat_id='channel:1492386247862390824'`, `chat_type='group'`
- `channel_transcripts` row created with `external_message_id='1502589947721547817'`, full `raw_metadata` JSONB stored
- `sender_id`, `sender_name`, `sender_username`, `sender_tag` populated from sender block
- `message_count` and `last_message_at` updated on session

---

## TC-002: Happy Path — Signal Group Message

**Input:** Signal-style inbound metadata (no `group_space`, different `chat_id` format):
```json
{
  "chat_id": "group:abc123def456",
  "message_id": "signal-msg-001",
  "sender_id": "+15551234567",
  "sender": "Neva",
  "timestamp": "2026-05-08T14:30:00.000Z",
  "group_subject": "SE Workflow with Neva",
  "is_group_chat": true
}
```

**Expected:**
- `channel_sessions` row with `provider='signal'`, `external_chat_id='group:abc123def456'`, no `group_space_id`, `chat_type='group'`
- `channel_transcripts` row with full metadata preserved
- No errors from missing `group_space` field

---

## TC-003: Session Reconstruction from Single Message

**Given:** A `channel_transcripts` row with `id=42`, `session_id=7`
**Query:**
```sql
SELECT * FROM channel_transcripts
WHERE session_id = (SELECT session_id FROM channel_transcripts WHERE id = 42)
ORDER BY timestamp;
```
**Expected:** Returns the full ordered conversation for that session regardless of provider.

---

## TC-004: Idempotent Upsert — Same Message Twice

**Action:** Run `memory-catchup.sh` against the same JSONL file twice.
**Expected:**
- Second run produces no duplicate `channel_transcripts` rows
- `ON CONFLICT (session_id, external_message_id) DO NOTHING` fires silently
- `channel_sessions.message_count` remains accurate (not double-counted)

---

## TC-005: Idempotent Upsert — Minor Metadata Change

**Action:** Re-import same `external_message_id` with a slight difference in `raw_metadata`.
**Expected:** Current implementation uses `DO NOTHING` — the original row is preserved. Document whether this is acceptable or if `DO UPDATE` is preferred for metadata freshness.

---

## TC-006: Daily Memory File Ingestion + Deletion

**Input:** `memory/2026-05-09.md` containing daily session notes.
**Action:** `memory-catchup.sh` processes the file.
**Expected:**
- Content stored as entity_fact on the NOVA entity
- Source file deleted ONLY after successful DB insert
- Re-running after deletion is a no-op (file gone)

---

## TC-007: Deletion Safety — DB Insert Fails

**Scenario:** Database is unavailable or INSERT fails.
**Expected:** Source file (`*.jsonl` or `*.md`) is NOT deleted. Script logs a warning and continues.
**Review:** Check that `rm -f` only executes after confirmed successful psql exit.

---

## TC-008: Missing Sender Fields

**Input:** Message with no sender block (only `sender_id` in chat metadata).
**Expected:**
- `sender_name`, `sender_username`, `sender_tag` are NULL
- Row still inserts successfully
- No crash in `memory-catchup.sh` or downstream hooks

---

## TC-009: Null or Missing external_message_id

**Input:** JSONL line with no `id`, `message_id`, or `timestamp` field.
**Expected:** Row is skipped (not inserted). Script does not crash. Logged as warning.

---

## TC-010: Corrupt/Malformed JSON in raw_metadata

**Input:** JSONL line with invalid JSON structure.
**Expected:** `jq` parsing fails gracefully. Row is skipped. Script continues processing remaining lines.

---

## TC-011: Very Long Session — Performance

**Setup:** 500+ messages in a single `channel_sessions` row.
**Verification:**
- `EXPLAIN ANALYZE` on reconstruction query uses `idx_channel_transcripts_session_time` index
- Query returns 500 messages in < 80 ms
- `message_count` accurately reflects total

---

## TC-012: Concurrent Import Safety

**Scenario:** Two `memory-catchup.sh` processes run simultaneously on overlapping JSONL files.
**Expected:**
- Unique constraint `(session_id, external_message_id)` prevents duplicates
- No deadlocks
- Final state is consistent

---

## TC-013: Backfill of Old JSONL Files

**Setup:** Historical JSONL files from before migration 067.
**Action:** Run `memory-catchup.sh` against them.
**Expected:** All historical transcripts land in `channel_transcripts` with proper session grouping. Files deleted after successful import.

---

## TC-014: entity_facts Source Pointers — New Fact

**Scenario:** Memory extraction creates a new `entity_facts` row from a message already in `channel_transcripts`.
**Expected:**
- `source_channel_transcript_id` populated with the correct `channel_transcripts.id`
- `source_channel_session_id` populated with the correct `channel_sessions.id`

---

## TC-015: entity_facts Source Pointers — Reinforcement

**Scenario:** A duplicate fact is extracted from a newer message.
**Expected:**
- `vote_count` incremented
- `source_channel_transcript_id` updated to the newer message (COALESCE — never overwrite with NULL)
- Old pointer preserved if new pointer is NULL

---

## TC-016: sender_entity_id Population

**Scenario:** Transcript row imported with raw sender fields but no `sender_entity_id`.
**Action:** Entity resolver runs later and maps `sender_id='330189773371080716'` to `entities.id` for I)ruid.
**Expected:** `sender_entity_id` FK is updated. JOIN to `entities` table works.

---

## TC-017: memory-extract Hook — Context Passing

**Verification:** `memory/hooks/memory-extract/handler.ts` reads `channelTranscriptId` and `channelSessionId` from event context and passes them as `SOURCE_CHANNEL_TRANSCRIPT_ID` and `SOURCE_CHANNEL_SESSION_ID` env vars.
**Expected:** Extraction subprocess receives the env vars. `store-memories.sh` uses them for FK columns.

---

## TC-018: Schema Migration — conversations Table Dropped

**Verification:**
```sql
SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='conversations');
-- Expected: false
```
**Also verify:** `DROP TABLE IF EXISTS conversations CASCADE;` in migration 067.

---

## TC-019: Legacy Code Audit — No conversations References

**Verification:**
```bash
git grep -n 'conversations' -- '*.ts' '*.sh' '*.sql' ':!**/node_modules/**' ':!**/TEST-CASES*' ':!**/CHANGELOG*' | grep -v 'DROP TABLE' | grep -v '-- '
```
**Expected:** Zero hits in active codepaths. Only acceptable in migration DROP statement and historical test/doc files.

---

## TC-020: Daily .md File Format — Unknown Format Fallback

**Input:** A `memory/*.md` file with no structured chat references (just plain prose notes).
**Expected:** Content ingested as-is into entity_facts. No crash. File deleted after successful insert.

---

## TC-021: SQL Injection Safety

**Review:** All shell-to-SQL paths in `memory-catchup.sh` and `store-memories.sh` use proper escaping.
**Check:** `sed "s/'/''/g"` applied to all user-controlled values before interpolation into SQL strings.
**Flag:** Any path where raw content reaches `psql -c` without escaping.

---

## TC-022: Additional Happy Path — Discord Message (message_id 1502593273334599721)

**Input:** Second real Discord message from the #software-engineering channel.
**Expected:** Attaches to the existing `channel_sessions` row (same `external_chat_id`). `message_count` increments. `last_message_at` updates. Full `raw_metadata` preserved.
