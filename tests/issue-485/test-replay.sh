#!/usr/bin/env bash
# test-replay.sh — Chunk 3 tests for issue #485 replay script.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPLAY_SCRIPT="${REPO_ROOT}/memory/scripts/extraction-replay.sh"
MOCKS_DIR="$(mktemp -d -t issue485-replay-mocks-XXXXXX)"
LOGFILE="${1:-$(mktemp -t issue485-replay-XXXXXX.log)}"
LOCK_FILE="${HOME}/.openclaw/run/extraction-replay.lock"

PASS=0
FAIL=0

assert() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected='$expected', actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assertContains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

assertNotContains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (expected NOT to contain '$needle')"
        FAIL=$((FAIL + 1))
    fi
}

run_psql() {
    unset PGPASSWORD; psql -U nova -d nova_memory -h localhost -t -A -c "$1"
}

cleanup_test_rows() {
    local marker="$1"
    run_psql "DELETE FROM extraction_failures WHERE session_key LIKE '${marker}%';" || true
    run_psql "DELETE FROM channel_transcripts WHERE external_message_id LIKE '${marker}%';" || true
    run_psql "DELETE FROM channel_sessions WHERE session_key LIKE '${marker}%';" || true
}

# Mock extract_memories.py scripts
cat > "$MOCKS_DIR/ok.py" <<'PY'
import sys
sys.stdin.read()
sys.exit(0)
PY

cat > "$MOCKS_DIR/fail.py" <<'PY'
import sys
sys.stdin.read()
sys.exit(1)
PY

cat > "$MOCKS_DIR/slow.py" <<'PY'
import sys, time
sys.stdin.read()
time.sleep(300)
PY

chmod +x "$MOCKS_DIR"/*.py

run_replay() {
    # Run replay as the nova DB owner so INSERT/UPDATE/DELETE on
    # extraction_failures succeeds under default privileges.
    PGUSER=nova \
    EXTRACTION_SCRIPT_PATH_OVERRIDE="${EXTRACTION_SCRIPT_PATH_OVERRIDE:-$MOCKS_DIR/ok.py}" \
    EXTRACTION_REPLAY_BATCH_LIMIT="${EXTRACTION_REPLAY_BATCH_LIMIT:-10}" \
    EXTRACTION_REPLAY_MAX_RETRIES="${EXTRACTION_REPLAY_MAX_RETRIES:-5}" \
        bash "$REPLAY_SCRIPT"
}

echo "[issue-485:chunk3] Replay script validation started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[issue-485:chunk3] Replay script: $REPLAY_SCRIPT"
echo "[issue-485:chunk3] Log file: $LOGFILE"
exec > >(tee -a "$LOGFILE")
exec 2>&1

# TC-D10: env sourcing static check
assertContains 'TC-D10: sources env-loader.sh' "$(cat "$REPLAY_SCRIPT")" 'env-loader.sh'
assertContains 'TC-D10: sources pg-env.sh' "$(cat "$REPLAY_SCRIPT")" 'pg-env.sh'

# TC-D6: FK row vs body-fallback row
MARKER="tc-d6-$(date +%s%N)"
cleanup_test_rows "$MARKER"
run_psql "
INSERT INTO channel_sessions (session_key, agent_id, provider, external_chat_id, chat_type)
VALUES ('${MARKER}-session', 'main', 'openclaw', '${MARKER}-chat', 'direct');
"
SESS_ID=$(run_psql "SELECT id FROM channel_sessions WHERE session_key = '${MARKER}-session';")
run_psql "
INSERT INTO channel_transcripts (session_id, external_message_id, timestamp, role, content)
VALUES (${SESS_ID}, '${MARKER}-msg', NOW(), 'user', 'FK-row body content');
"
TX_ID=$(run_psql "SELECT id FROM channel_transcripts WHERE external_message_id = '${MARKER}-msg';")
run_psql "
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status)
VALUES (${TX_ID}, '${MARKER}-session', 'FKSender', NULL, 'pending');
"
run_psql "
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status)
VALUES (NULL, '${MARKER}-session', 'FallbackSender', 'fallback body content', 'pending');
"
# Mock script that echoes stdin to a temp file so we can verify reconstruction.
BODY_RECORD="$(mktemp)"
cat > "$MOCKS_DIR/record.py" <<PY
import sys
with open('$BODY_RECORD', 'a') as f:
    f.write(sys.stdin.read())
    f.write('\\n---END---\\n')
sys.exit(0)
PY
chmod +x "$MOCKS_DIR/record.py"
EXTRACTION_SCRIPT_PATH_OVERRIDE="$MOCKS_DIR/record.py" run_replay "$MARKER"
# Verify both bodies reached the mock.
assertContains 'TC-D6: FK-row body reconstructed from transcript' "$(cat "$BODY_RECORD")" 'FK-row body content'
assertContains 'TC-D6: fallback-row body uses stored content' "$(cat "$BODY_RECORD")" 'fallback body content'
rm -f "$BODY_RECORD"
cleanup_test_rows "$MARKER"

# TC-D9: successful replay -> resolved
MARKER="tc-d9-$(date +%s%N)"
cleanup_test_rows "$MARKER"
run_psql "
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status)
VALUES (NULL, '${MARKER}-session', 'SuccessSender', 'success body', 'pending');
"
EXTRACTION_SCRIPT_PATH_OVERRIDE="$MOCKS_DIR/ok.py" run_replay "$MARKER"
RESOLVED=$(run_psql "SELECT status FROM extraction_failures WHERE session_key = '${MARKER}-session';")
assert 'TC-D9: row marked resolved on success' 'resolved' "$RESOLVED"
RESOLVED_AT=$(run_psql "SELECT resolved_at IS NOT NULL FROM extraction_failures WHERE session_key = '${MARKER}-session';")
assert 'TC-D9: resolved_at populated' 't' "$RESOLVED_AT"
cleanup_test_rows "$MARKER"

# TC-D8: retry_count increment + exhaustion
MARKER="tc-d8-$(date +%s%N)"
cleanup_test_rows "$MARKER"
run_psql "
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status, retry_count)
VALUES (NULL, '${MARKER}-fresh', 'FreshSender', 'fresh body', 'pending', 0);
"
run_psql "
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status, retry_count)
VALUES (NULL, '${MARKER}-exhaust', 'ExhaustSender', 'exhaust body', 'pending', 4);
"
EXTRACTION_SCRIPT_PATH_OVERRIDE="$MOCKS_DIR/fail.py" EXTRACTION_REPLAY_MAX_RETRIES=5 run_replay "$MARKER"
FRESH_RETRY=$(run_psql "SELECT retry_count FROM extraction_failures WHERE session_key = '${MARKER}-fresh';")
assert 'TC-D8: fresh row retry_count incremented to 1' '1' "$FRESH_RETRY"
FRESH_STATUS=$(run_psql "SELECT status FROM extraction_failures WHERE session_key = '${MARKER}-fresh';")
assert 'TC-D8: fresh row still pending' 'pending' "$FRESH_STATUS"
EXHAUST_STATUS=$(run_psql "SELECT status FROM extraction_failures WHERE session_key = '${MARKER}-exhaust';")
assert 'TC-D8: exhausted row marked retry_exhausted' 'retry_exhausted' "$EXHAUST_STATUS"
EXHAUST_RETRY=$(run_psql "SELECT retry_count FROM extraction_failures WHERE session_key = '${MARKER}-exhaust';")
assert 'TC-D8: exhausted row retry_count = 5' '5' "$EXHAUST_RETRY"
# Second run should not process exhausted row.
LOG2="$(mktemp)"
EXTRACTION_SCRIPT_PATH_OVERRIDE="$MOCKS_DIR/fail.py" run_replay "$MARKER" > "$LOG2" 2>&1
assertNotContains 'TC-D8: exhausted row not retried on second run' "$(cat "$LOG2")" '${MARKER}-exhaust'
rm -f "$LOG2"
cleanup_test_rows "$MARKER"

# TC-D7: rate limiting per run
MARKER="tc-d7-$(date +%s%N)"
cleanup_test_rows "$MARKER"
for i in $(seq 1 12); do
    run_psql "
    INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status)
    VALUES (NULL, '${MARKER}-s${i}', 'RateSender${i}', 'body ${i}', 'pending');
    "
done
LOG7="$(mktemp)"
EXTRACTION_SCRIPT_PATH_OVERRIDE="$MOCKS_DIR/ok.py" EXTRACTION_REPLAY_BATCH_LIMIT=10 run_replay "$MARKER" > "$LOG7" 2>&1
RESOLVED_COUNT=$(run_psql "SELECT COUNT(*) FROM extraction_failures WHERE session_key LIKE '${MARKER}-%' AND status = 'resolved';")
PENDING_COUNT=$(run_psql "SELECT COUNT(*) FROM extraction_failures WHERE session_key LIKE '${MARKER}-%' AND status = 'pending';")
assert 'TC-D7: exactly 10 rows processed (resolved)' '10' "$RESOLVED_COUNT"
assert 'TC-D7: 2 rows left pending' '2' "$PENDING_COUNT"
rm -f "$LOG7"
cleanup_test_rows "$MARKER"

# TC-D12: unreplayable rows (NULL FK + NULL body)
MARKER="tc-d12-$(date +%s%N)"
cleanup_test_rows "$MARKER"
run_psql "
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status, retry_count)
VALUES (NULL, '${MARKER}-unreplay', 'UnreplaySender', NULL, 'pending', 0);
"
# Also add a normal replayable row to confirm sibling processing unaffected.
run_psql "
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status, retry_count)
VALUES (NULL, '${MARKER}-normal', 'NormalSender', 'normal body', 'pending', 0);
"
LOG12="$(mktemp)"
EXTRACTION_SCRIPT_PATH_OVERRIDE="$MOCKS_DIR/ok.py" run_replay "$MARKER" > "$LOG12" 2>&1 || true
UNREPLAY_STATUS=$(run_psql "SELECT status FROM extraction_failures WHERE session_key = '${MARKER}-unreplay';")
assert 'TC-D12: unreplayable row marked unreplayable' 'unreplayable' "$UNREPLAY_STATUS"
UNREPLAY_RETRY=$(run_psql "SELECT retry_count FROM extraction_failures WHERE session_key = '${MARKER}-unreplay';")
assert 'TC-D12: unreplayable row retry_count unchanged' '0' "$UNREPLAY_RETRY"
NORMAL_STATUS=$(run_psql "SELECT status FROM extraction_failures WHERE session_key = '${MARKER}-normal';")
assert 'TC-D12: sibling row resolved normally' 'resolved' "$NORMAL_STATUS"
assertContains 'TC-D12: log mentions unreplayable' "$(cat "$LOG12")" 'unreplayable'
# Second run should not re-process unreplayable row.
LOG12B="$(mktemp)"
EXTRACTION_SCRIPT_PATH_OVERRIDE="$MOCKS_DIR/ok.py" run_replay "$MARKER" > "$LOG12B" 2>&1
assertNotContains 'TC-D12: unreplayable row absent from second run log' "$(cat "$LOG12B")" '${MARKER}-unreplay'
rm -f "$LOG12" "$LOG12B"
cleanup_test_rows "$MARKER"

# TC-D5: flock overlapping-run protection
MARKER="tc-d5-$(date +%s%N)"
cleanup_test_rows "$MARKER"
run_psql "
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status)
VALUES (NULL, '${MARKER}-slow', 'SlowSender', 'slow body', 'pending');
"
LOCK_HOLD="$(mktemp)"
# Hold the lock in a subshell and run a slow replay.
(
    exec 201>"$LOCK_FILE"
    flock -n 201 || exit 1
    touch "$LOCK_HOLD"
    sleep 5
) &
HOLDER=$!
# Wait until holder has acquired the lock.
for _ in $(seq 1 50); do
    [ -f "$LOCK_HOLD" ] && break
    sleep 0.1
done
LOG5="$(mktemp)"
EXTRACTION_SCRIPT_PATH_OVERRIDE="$MOCKS_DIR/slow.py" run_replay "$MARKER" > "$LOG5" 2>&1 || true
assertContains 'TC-D5: second invocation detects lock and exits' "$(cat "$LOG5")" 'Lock held'
wait "$HOLDER" 2>/dev/null || true
rm -f "$LOG5" "$LOCK_HOLD"
cleanup_test_rows "$MARKER"

echo "[issue-485:chunk3] Summary: PASS=$PASS FAIL=$FAIL"
echo "[issue-485:chunk3] Validation finished at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

rm -rf "$MOCKS_DIR"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
exit 0
