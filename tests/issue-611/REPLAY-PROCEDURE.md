# Issue #611 Manual Replay Procedure

This document describes how to run the LLM-behavioral acceptance tests that
cannot be asserted deterministically in unit tests (TC-611-C3/C4 and similar
context-disambiguation fixtures).

## Quick replay with `extract_memories.py`

The fixture `fixtures/blockhenge-regression.json` contains the full
conversation context plus the ambiguous current message. To replay it through
the extraction pipeline locally:

```bash
cd ~/nova-mind

# Extract the current message body
current=$(jq -r '.messages[.current_message_index].content' tests/issue-611/fixtures/blockhenge-regression.json)

# Build the prior-context JSON (all messages before the current one)
context=$(jq '[.messages[:.current_message_index][] | {role, content, timestamp, sender_name}]' tests/issue-611/fixtures/blockhenge-regression.json)

# Run extraction (requires OPENROUTER_API_KEY in environment)
printf '%s' "$current" | \
  SENDER_NAME="Zonkism" \
  SENDER_ID="" \
  IS_GROUP="true" \
  SOURCE_SESSION_ID="discord:channel:blockhenge" \
  SOURCE_TIMESTAMP="2026-08-17T20:13:00Z" \
  EXTRACTION_CONTEXT_JSON="$context" \
  python3 memory/scripts/extract_memories.py
```

## What to verify

For `fixtures/blockhenge-regression.json` (TC-611-C4):

1. The `events` array contains an event about a NOPASSWD sudoers directive on a
   sarsen host. The description should NOT read as "user nopassword was added".
2. The event's `environment` field is populated with a value consistent with
   `blockhenge-sarsen-2` (exact string may be normalized by the model, but it
   must be non-null and host-related).
3. No duplicate events or facts are extracted from the prior context messages
   themselves.

## Replaying without context (sanity check)

To confirm the bug that #611 fixes, run the same current message with no context:

```bash
cd ~/nova-mind
current=$(jq -r '.messages[.current_message_index].content' tests/issue-611/fixtures/blockhenge-regression.json)
printf '%s' "$current" | \
  SENDER_NAME="Zonkism" \
  SENDER_ID="" \
  IS_GROUP="true" \
  SOURCE_SESSION_ID="discord:channel:blockhenge" \
  SOURCE_TIMESTAMP="2026-08-17T20:13:00Z" \
  python3 memory/scripts/extract_memories.py
```

In no-context mode, the model may reasonably interpret "nopassword" literally
as a username (the pre-#611 bug). This is expected; the fix is that context
enabled produces the correct interpretation.

## Batch/replay path verification

To verify the batch path (`extraction-replay.sh`) reconstructs context:

1. Ensure the fixture messages are loaded into `channel_sessions` / `channel_transcripts`
   (e.g. by placing a JSONL session file in `~/.openclaw/agents/main/sessions/` and running
   `memory/scripts/memory-catchup.sh`, or by inserting rows manually).
2. Create an `extraction_failures` row referencing the transcript id of the
   current message (`nopassword was added to soudoers`).
3. Run `memory/scripts/extraction-replay.sh --log` and confirm the extraction
   call includes prior context messages.

## Per-turn hook verification

To verify the per-turn path in a deployed environment:

1. Enable context window in `~/.openclaw/scripts/memory-extraction-config.json`:
   ```json
   {
     "max_prior_messages": 10,
     "context_window_enabled": true
   }
   ```
2. Send the sequence of messages in the fixture in a real Discord/Signal channel.
3. Inspect gateway logs for `[memory-extract] Loaded prior context messages`
   (with a `count` field in the structured log payload) and confirm the count
   matches the number of prior messages.
4. Check the resulting `events` row for correct `description` and `environment`.

## Coverage caveat

The steps above are manual verification procedures. As of commit `8edc8c5`,
none of them are wired into an automated test or CI job — the fixtures
(`blockhenge-regression.json`, `cross-channel-privacy.json`) exist to support
this manual replay procedure but are not loaded or asserted against by any
`.py` test file. Automated coverage for this issue is limited to
`test_issue_611_extract_memories.py` (27 unit tests) and
`test_issue_611_extract_memories_integration.py` (2 real-DB integration tests)
— 29 total. The batch/replay path (`memory-catchup.sh`, `extraction-replay.sh`)
has zero automated test coverage; this document is its only verification path.
See `tests/issue-611/step8-qa-validation.md` for the full coverage map.
