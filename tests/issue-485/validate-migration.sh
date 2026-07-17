#!/usr/bin/env bash
# validate-migration.sh — Chunk 1 tests for issue #485
# Validates migration 085_extraction_failures.sql for idempotency (TC-D3)
# and schema conformance (TC-D4).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATION="${REPO_ROOT}/memory/migrations/085_extraction_failures.sql"
LOGFILE="${1:-$(mktemp -t issue485-migration-XXXXXX.log)}"

: "${TEST_PGDATABASE:?TEST_PGDATABASE is not set}"
: "${TEST_PGUSER:?TEST_PGUSER is not set}"
: "${TEST_PGHOST:?TEST_PGHOST is not set}"
TEST_PGUSER_DDL="${TEST_PGUSER_DDL:-$TEST_PGUSER}"

# Redirect all stdout/stderr to the log file AND still show it on console.
exec > >(tee -a "$LOGFILE")
exec 2>&1

echo "[issue-485:chunk1] Migration validation started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[issue-485:chunk1] Database: $TEST_PGDATABASE host: $TEST_PGHOST user: $TEST_PGUSER ddl-user: $TEST_PGUSER_DDL"
echo "[issue-485:chunk1] Migration file: $MIGRATION"
echo "[issue-485:chunk1] Log file: $LOGFILE"

if [ ! -f "$MIGRATION" ]; then
    echo "ERROR: migration file not found: $MIGRATION"
    exit 1
fi

# Helper: run psql with a single command.
run_psql() {
    unset PGPASSWORD; psql -U "$TEST_PGUSER" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -t -A -c "$1"
}

# Helper for DDL: the migration references channel_transcripts, which requires
# REFERENCES privilege. Use TEST_PGUSER_DDL (often the schema owner).
run_psql_ddl() {
    unset PGPASSWORD; psql -U "$TEST_PGUSER_DDL" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -t -A -c "$1"
}

# TC-D3: run migration twice, both must succeed.
echo "[issue-485:chunk1] TC-D3: applying migration (first run) as nova..."
run_psql_ddl "$(cat "$MIGRATION")"
echo "[issue-485:chunk1] TC-D3: first run exit code $?"

echo "[issue-485:chunk1] TC-D3: re-applying migration (second run) as nova..."
run_psql_ddl "$(cat "$MIGRATION")"
echo "[issue-485:chunk1] TC-D3: second run exit code $?"

# TC-D4 sub-assertions.
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

# 1. id is PK / BIGSERIAL.
PK_TYPE=$(run_psql "
    SELECT data_type
    FROM information_schema.columns
    WHERE table_name = 'extraction_failures' AND column_name = 'id';
" | head -1)
assert "TC-D4: id column is bigint (BIGSERIAL materializes as bigint)" "bigint" "$PK_TYPE"

PK_EXISTS=$(run_psql "
    SELECT COUNT(*)
    FROM pg_constraint
    WHERE conrelid = 'extraction_failures'::regclass AND contype = 'p';
" | head -1)
assert "TC-D4: primary key constraint exists" "1" "$PK_EXISTS"

# 2. created_at is TIMESTAMPTZ NOT NULL DEFAULT NOW().
CREATED_AT_TYPE=$(run_psql "
    SELECT data_type
    FROM information_schema.columns
    WHERE table_name = 'extraction_failures' AND column_name = 'created_at';
" | head -1)
assert "TC-D4: created_at is timestamp with time zone" "timestamp with time zone" "$CREATED_AT_TYPE"

CREATED_AT_NULLABLE=$(run_psql "
    SELECT is_nullable
    FROM information_schema.columns
    WHERE table_name = 'extraction_failures' AND column_name = 'created_at';
" | head -1)
assert "TC-D4: created_at is NOT NULL" "NO" "$CREATED_AT_NULLABLE"

CREATED_AT_DEFAULT=$(run_psql "
    SELECT column_default
    FROM information_schema.columns
    WHERE table_name = 'extraction_failures' AND column_name = 'created_at';
" | head -1)
if [[ "$CREATED_AT_DEFAULT" == *"now()"* ]]; then
    assert "TC-D4: created_at default is NOW()-like" "yes" "yes"
else
    assert "TC-D4: created_at default is NOW()-like" "yes" "no (actual: $CREATED_AT_DEFAULT)"
fi

# 3. FK to channel_transcripts with ON DELETE SET NULL.
FK_EXISTS=$(run_psql "
    SELECT COUNT(*)
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.confrelid
    WHERE c.conrelid = 'extraction_failures'::regclass
      AND c.contype = 'f'
      AND t.relname = 'channel_transcripts';
" | head -1)
assert "TC-D4: foreign key to channel_transcripts exists" "1" "$FK_EXISTS"

FK_DELETE_RULE=$(run_psql "
    SELECT CASE c.confdeltype
        WHEN 'a' THEN 'NO ACTION'
        WHEN 'r' THEN 'RESTRICT'
        WHEN 'c' THEN 'CASCADE'
        WHEN 'n' THEN 'SET NULL'
        WHEN 'd' THEN 'SET DEFAULT'
    END
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.confrelid
    WHERE c.conrelid = 'extraction_failures'::regclass
      AND c.contype = 'f'
      AND t.relname = 'channel_transcripts';
" | head -1)
assert "TC-D4: FK delete rule is SET NULL" "SET NULL" "$FK_DELETE_RULE"

# 4. At least one CHECK constraint exists.
CHECK_COUNT=$(run_psql "
    SELECT COUNT(*)
    FROM pg_constraint
    WHERE conrelid = 'extraction_failures'::regclass AND contype = 'c';
" | head -1)
if [ "$CHECK_COUNT" -ge 1 ]; then
    assert "TC-D4: at least one CHECK constraint exists" "yes" "yes"
else
    assert "TC-D4: at least one CHECK constraint exists" "yes" "no"
fi

# Verify the specific status CHECK enum.
STATUS_CHECK=$(run_psql "
    SELECT COUNT(*)
    FROM pg_constraint
    WHERE conrelid = 'extraction_failures'::regclass
      AND contype = 'c'
      AND conname = 'extraction_failures_status_check';
" | head -1)
assert "TC-D4: status CHECK constraint exists" "1" "$STATUS_CHECK"

# 5. Indexes are named explicitly (not anonymous).
ANON_INDEXES=$(run_psql "
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE tablename = 'extraction_failures'
      AND indexname LIKE 'pg_toast%'
      AND schemaname = 'public';
" | head -1)
# We just want to confirm that the indexes we expect exist and are named.
IDX_STATUS=$(run_psql "
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE tablename = 'extraction_failures'
      AND indexname = 'idx_extraction_failures_status'
      AND schemaname = 'public';
" | head -1)
assert "TC-D4: named index idx_extraction_failures_status exists" "1" "$IDX_STATUS"

IDX_TRANSCRIPT=$(run_psql "
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE tablename = 'extraction_failures'
      AND indexname = 'idx_extraction_failures_channel_transcript_id'
      AND schemaname = 'public';
" | head -1)
assert "TC-D4: named index idx_extraction_failures_channel_transcript_id exists" "1" "$IDX_TRANSCRIPT"

IDX_CREATED=$(run_psql "
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE tablename = 'extraction_failures'
      AND indexname = 'idx_extraction_failures_created_at'
      AND schemaname = 'public';
" | head -1)
assert "TC-D4: named index idx_extraction_failures_created_at exists" "1" "$IDX_CREATED"

IDX_REPLAY=$(run_psql "
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE tablename = 'extraction_failures'
      AND indexname = 'idx_extraction_failures_replay_order'
      AND schemaname = 'public';
" | head -1)
assert "TC-D4: named index idx_extraction_failures_replay_order exists" "1" "$IDX_REPLAY"

# 6. COMMENT ON TABLE is present and non-empty.
TABLE_COMMENT=$(run_psql "
    SELECT obj_description('extraction_failures'::regclass, 'pg_class');
" | head -1)
if [ -n "$TABLE_COMMENT" ] && [ "$TABLE_COMMENT" != "NULL" ]; then
    assert "TC-D4: table comment is present and non-empty" "yes" "yes"
else
    assert "TC-D4: table comment is present and non-empty" "yes" "no"
fi

# Optional: list CHECK constraint names for the report.
echo "[issue-485:chunk1] CHECK constraints on extraction_failures:"
run_psql "
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'extraction_failures'::regclass AND contype = 'c'
    ORDER BY conname;
"

echo "[issue-485:chunk1] Indexes on extraction_failures:"
run_psql "
    SELECT indexname
    FROM pg_indexes
    WHERE tablename = 'extraction_failures' AND schemaname = 'public'
    ORDER BY indexname;
"

# TC-D2: deleting parent session cascades to transcripts but dead-letter row survives.
TEST_SESSION_KEY="issue485-tc-d2-$(date +%s%N)"
echo "[issue-485:chunk1] TC-D2: testing cascade-delete survival with session_key=$TEST_SESSION_KEY"

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
INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, stderr_tail, exit_code, failure_reason)
SELECT tx.id, '$TEST_SESSION_KEY', 'tc-d2-sender', 'tc-d2 stderr', 1, 'nonzero_exit'
FROM tx;
"

BEFORE_SURVIVES=$(run_psql "
    SELECT COUNT(*) FROM extraction_failures WHERE session_key = '$TEST_SESSION_KEY';
" | head -1)
assert "TC-D2: dead-letter row exists before session delete" "1" "$BEFORE_SURVIVES"

run_psql_ddl "DELETE FROM channel_sessions WHERE session_key = '$TEST_SESSION_KEY';"

AFTER_SURVIVES=$(run_psql "
    SELECT COUNT(*) FROM extraction_failures WHERE session_key = '$TEST_SESSION_KEY';
" | head -1)
assert "TC-D2: dead-letter row survives session delete" "1" "$AFTER_SURVIVES"

AFTER_FK_NULL=$(run_psql "
    SELECT COUNT(*) FROM extraction_failures
    WHERE session_key = '$TEST_SESSION_KEY' AND channel_transcript_id IS NULL;
" | head -1)
assert "TC-D2: channel_transcript_id is NULL after cascade" "1" "$AFTER_FK_NULL"

# Clean up the TC-D2 row.
run_psql_ddl "DELETE FROM extraction_failures WHERE session_key = '$TEST_SESSION_KEY';"

echo "[issue-485:chunk1] Summary: PASS=$PASS FAIL=$FAIL"
echo "[issue-485:chunk1] Validation finished at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
exit 0
