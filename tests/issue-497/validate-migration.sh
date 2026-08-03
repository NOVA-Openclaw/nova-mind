#!/usr/bin/env bash
# validate-migration.sh — Chunk 1 tests for issue #497
# Validates migration 086_extraction_failures_json_parse_failure.sql for
# idempotency, CHECK constraint extension, and existing-data safety.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATION="${REPO_ROOT}/memory/migrations/086_extraction_failures_json_parse_failure.sql"
LOGFILE="${1:-$(mktemp -t issue497-migration-XXXXXX.log)}"

: "${TEST_PGDATABASE:?TEST_PGDATABASE is not set}"
: "${TEST_PGUSER:?TEST_PGUSER is not set}"
: "${TEST_PGHOST:?TEST_PGHOST is not set}"
TEST_PGUSER_DDL="${TEST_PGUSER_DDL:-$TEST_PGUSER}"

# Redirect all stdout/stderr to the log file AND still show it on console.
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "[issue-497:chunk1] Migration validation started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[issue-497:chunk1] Database: $TEST_PGDATABASE host: $TEST_PGHOST user: $TEST_PGUSER ddl-user: $TEST_PGUSER_DDL"
echo "[issue-497:chunk1] Migration file: $MIGRATION"
echo "[issue-497:chunk1] Log file: $LOGFILE"

if [ ! -f "$MIGRATION" ]; then
    echo "ERROR: migration file not found: $MIGRATION"
    exit 1
fi

# Doc-presence assertion (D3): header must disclose forward-only / irreversible state.
if grep -qi "forward-only" "$MIGRATION" && grep -qi "irreversible state" "$MIGRATION"; then
    echo "PASS: TC-D3 migration header documents forward-only accepted irreversible state"
else
    echo "FAIL: TC-D3 migration header missing required forward-only/irreversible disclosure"
    exit 1
fi

# Helper: run psql with a single command.
run_psql() {
    unset PGPASSWORD; psql -U "$TEST_PGUSER" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -t -A -c "$1"
}

run_psql_ddl() {
    unset PGPASSWORD; psql -U "$TEST_PGUSER_DDL" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -t -A -c "$1"
}

# TC-D1: run migration twice, both must succeed.
echo "[issue-497:chunk1] TC-D1: applying migration (first run)..."
run_psql_ddl "$(cat "$MIGRATION")"
echo "[issue-497:chunk1] TC-D1: first run exit code $?"

echo "[issue-497:chunk1] TC-D1: re-applying migration (second run)..."
run_psql_ddl "$(cat "$MIGRATION")"
echo "[issue-497:chunk1] TC-D1: second run exit code $?"

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

# Verify the failure_reason CHECK enum includes json_parse_failure.
REASON_CHECK_DEF=$(run_psql "
    SELECT pg_get_constraintdef(oid)
    FROM pg_constraint
    WHERE conrelid = 'extraction_failures'::regclass
      AND contype = 'c'
      AND conname = 'extraction_failures_failure_reason_check';
" | head -1)

assert "TC-D1: failure_reason CHECK exists" "1" "$(run_psql "
    SELECT COUNT(*)
    FROM pg_constraint
    WHERE conrelid = 'extraction_failures'::regclass
      AND contype = 'c'
      AND conname = 'extraction_failures_failure_reason_check';
" | head -1)"

assert "TC-D1: CHECK includes json_parse_failure" "yes" "$([[ "$REASON_CHECK_DEF" == *"json_parse_failure"* ]] && echo yes || echo no)"

# TC-D2: existing rows with old reason values are untouched and still valid.
TEST_SESSION_KEY="issue497-tc-d2-$(date +%s%N)"
echo "[issue-497:chunk1] TC-D2: seeding existing rows with session_key=$TEST_SESSION_KEY"

run_psql_ddl "
INSERT INTO channel_sessions (session_key, agent_id, provider, external_chat_id, chat_type)
VALUES ('$TEST_SESSION_KEY', 'main', 'openclaw', '$TEST_SESSION_KEY', 'direct')
ON CONFLICT (provider, external_chat_id, COALESCE(external_thread_id, '')) DO NOTHING;
"

run_psql_ddl "
WITH sess AS (
    SELECT id FROM channel_sessions WHERE session_key = '$TEST_SESSION_KEY' LIMIT 1
)
INSERT INTO channel_transcripts (session_id, external_message_id, timestamp, role, content)
SELECT sess.id, '$TEST_SESSION_KEY-msg', NOW(), 'user', 'TC-D2 test body'
FROM sess
ON CONFLICT (session_id, external_message_id) DO NOTHING;
"

run_psql_ddl "
WITH tx AS (
    SELECT id FROM channel_transcripts WHERE external_message_id = '$TEST_SESSION_KEY-msg' LIMIT 1
)
INSERT INTO extraction_failures (
    channel_transcript_id, session_key, sender_name, stderr_tail, exit_code, failure_reason
)
SELECT tx.id, '$TEST_SESSION_KEY', 'tc-d2-sender', 'tc-d2 stderr', 1, 'nonzero_exit'
FROM tx;
"

BEFORE_COUNT=$(run_psql "SELECT COUNT(*) FROM extraction_failures WHERE session_key = '$TEST_SESSION_KEY';" | head -1)
assert "TC-D2: seed row exists" "1" "$BEFORE_COUNT"

# Apply migration again over existing data (idempotency + existing-row validation).
run_psql_ddl "$(cat "$MIGRATION")"

AFTER_COUNT=$(run_psql "SELECT COUNT(*) FROM extraction_failures WHERE session_key = '$TEST_SESSION_KEY';" | head -1)
assert "TC-D2: existing row count unchanged" "$BEFORE_COUNT" "$AFTER_COUNT"

AFTER_REASON=$(run_psql "SELECT failure_reason FROM extraction_failures WHERE session_key = '$TEST_SESSION_KEY';" | head -1)
assert "TC-D2: existing row reason unchanged" "nonzero_exit" "$AFTER_REASON"

# Negative control: json_parse_failure INSERT succeeds post-migration.
run_psql_ddl "
INSERT INTO extraction_failures (
    channel_transcript_id, session_key, sender_name, stderr_tail, exit_code, failure_reason
)
SELECT NULL, '$TEST_SESSION_KEY-json', 'tc-d2-json', 'parse error', 2, 'json_parse_failure';
"
JSON_ROW=$(run_psql "SELECT failure_reason FROM extraction_failures WHERE session_key = '$TEST_SESSION_KEY-json';" | head -1)
assert "TC-D2: json_parse_failure row inserts successfully" "json_parse_failure" "$JSON_ROW"

# Clean up TC-D2 rows.
run_psql_ddl "DELETE FROM extraction_failures WHERE session_key LIKE '$TEST_SESSION_KEY%';"
run_psql_ddl "DELETE FROM channel_transcripts WHERE external_message_id = '$TEST_SESSION_KEY-msg';"
run_psql_ddl "DELETE FROM channel_sessions WHERE session_key = '$TEST_SESSION_KEY';"

echo "[issue-497:chunk1] Summary: PASS=$PASS FAIL=$FAIL"
echo "[issue-497:chunk1] Validation finished at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
exit 0
