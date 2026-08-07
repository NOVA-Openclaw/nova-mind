#!/usr/bin/env bash
# test-append-run-note.sh — Automated test suite for nova-mind#557
# Implements TC-1 through TC-16 from the Step 3 test design.
# TC-17 and TC-18 (pgschema apply idempotency) are documented as manual
# staging steps in README.md because pgschema's temporary-schema planning
# phase cannot apply this schema.sql against an embedded/empty plan database
# that lacks the production role set.
#
# Environment:
#   TEST_PGDATABASE  target database (default: nova_staging)
#   TEST_PGUSER      privileged user for DDL and test orchestration (default: nova)
#   TEST_PGHOST      database host (default: localhost)
#   TEST_PGPASSWORD  optional password for non-DDL role connection probes
#
# Safety:
#   * Targets staging only. Refuses to run against production-looking DBs.
#   * Creates workflow_runs in public schema if absent, then removes only the
#     test rows it created. Leaves the function in place (idempotent).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCHEMA_SQL="${REPO_ROOT}/database/schema.sql"

TEST_PGDATABASE="${TEST_PGDATABASE:-nova_staging}"
TEST_PGUSER="${TEST_PGUSER:-nova}"
TEST_PGHOST="${TEST_PGHOST:-localhost}"
TEST_PGPASSWORD="${TEST_PGPASSWORD:-}"

LOGFILE="${1:-$(mktemp -t issue557-test-XXXXXX.log)}"

PASS=0
FAIL=0
SKIP=0

# --- safety guardrails --------------------------------------------------------

if [[ "$TEST_PGDATABASE" == "nova_memory" || "$TEST_PGDATABASE" == "postgres" ]]; then
    echo "ERROR: refusing to run against production-looking database '$TEST_PGDATABASE'" >&2
    exit 1
fi

if [[ ! -f "$SCHEMA_SQL" ]]; then
    echo "ERROR: schema.sql not found: $SCHEMA_SQL" >&2
    exit 1
fi

# --- helpers ------------------------------------------------------------------

log() {
    echo "[issue-557] $*"
}

run_psql() {
    local sql="$1"
    local user="${2:-$TEST_PGUSER}"
    if [[ -n "$TEST_PGPASSWORD" ]]; then
        PGPASSWORD="$TEST_PGPASSWORD" psql -U "$user" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -t -A -c "$sql"
    else
        unset PGPASSWORD
        psql -U "$user" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -t -A -c "$sql"
    fi
}

run_psql_file() {
    local file="$1"
    local user="${2:-$TEST_PGUSER}"
    if [[ -n "$TEST_PGPASSWORD" ]]; then
        PGPASSWORD="$TEST_PGPASSWORD" psql -U "$user" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -f "$file"
    else
        unset PGPASSWORD
        psql -U "$user" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -f "$file"
    fi
}

# Run a SQL expression that returns a single scalar; strip whitespace.
scalar() {
    run_psql "$1" | head -1 | tr -d '\r'
}

assert_eq() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        log "PASS: $name"
        PASS=$((PASS + 1))
    else
        log "FAIL: $name (expected='$expected', actual='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_true() {
    local name="$1"
    local actual="$2"
    assert_eq "$name" "t" "$actual"
}

assert_false() {
    local name="$1"
    local actual="$2"
    assert_eq "$name" "f" "$actual"
}

# --- setup --------------------------------------------------------------------

log "Test suite started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
log "Database: $TEST_PGDATABASE host: $TEST_PGHOST user: $TEST_PGUSER"
log "Log file: $LOGFILE"

exec > >(tee -a "$LOGFILE")
exec 2>&1

log "Ensuring workflow_runs table exists..."
run_psql "
CREATE TABLE IF NOT EXISTS workflow_runs (
    id SERIAL,
    workflow_id integer NOT NULL,
    triggered_by text,
    trigger_context text,
    current_step integer,
    status varchar(20) DEFAULT 'running' NOT NULL,
    started_at timestamptz DEFAULT now() NOT NULL,
    completed_at timestamptz,
    notes text,
    channel text NOT NULL,
    CONSTRAINT workflow_runs_pkey PRIMARY KEY (id),
    CONSTRAINT workflow_runs_status_check CHECK (status::text IN ('running'::character varying, 'completed'::character varying, 'failed'::character varying, 'paused'::character varying, 'cancelled'::character varying))
);
" >/dev/null

log "Applying append_run_note function from schema.sql..."
# Extract the function + comment from schema.sql and apply them.
awk '
  /^-- Name: append_run_note\(integer, text\); Type: FUNCTION; Schema: -; Owner: -$/ { capture=1 }
  capture { print }
  /^COMMENT ON FUNCTION append_run_note\(integer, text\) IS / { capture=0 }
' "$SCHEMA_SQL" > /tmp/issue557-function.sql

if [[ ! -s /tmp/issue557-function.sql ]]; then
    log "ERROR: could not extract append_run_note from schema.sql"
    exit 1
fi

run_psql_file /tmp/issue557-function.sql >/dev/null

# --- test data ----------------------------------------------------------------

SESSION_KEY="issue557-$(date +%s%N)"
log "Session key for test rows: $SESSION_KEY"

RUN_ID_WITH_NOTES=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', 'existing note')
RETURNING id;
")

RUN_ID_NULL_NOTES=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', NULL)
RETURNING id;
")

RUN_ID_EMPTY_NOTES=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', '')
RETURNING id;
")

NONEXISTENT_RUN_ID=$(scalar "SELECT COALESCE(MAX(id), 0) + 100000 FROM workflow_runs;")

log "Run IDs: notes=$RUN_ID_WITH_NOTES null=$RUN_ID_NULL_NOTES empty=$RUN_ID_EMPTY_NOTES ghost=$NONEXISTENT_RUN_ID"

# --- TC-1: happy path as privileged role (nova) -------------------------------

log "TC-1: append as privileged role (nova)..."
run_psql "SELECT append_run_note($RUN_ID_WITH_NOTES, 'first append');" >/dev/null
assert_true "TC-1: preserves existing note" "$(scalar "SELECT position('existing note' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_WITH_NOTES;")"
assert_true "TC-1: appended note present" "$(scalar "SELECT position('first append' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_WITH_NOTES;")"
assert_true "TC-1: stamp separator present" "$(scalar "SELECT position(' UTC — ' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_WITH_NOTES;")"

# --- TC-2: happy path as SELECT-only role (gem) -------------------------------

log "TC-2: append as SELECT-only role (gem) — catalog verification..."
assert_true "TC-2: gem has EXECUTE on append_run_note" "$(scalar "SELECT has_function_privilege('gem', 'append_run_note(integer,text)', 'EXECUTE');")"
assert_false "TC-2: gem lacks direct UPDATE on workflow_runs" "$(scalar "SELECT has_table_privilege('gem', 'workflow_runs', 'UPDATE');")"

# Optional end-to-end as gem if credentials are available.
if [[ -n "$TEST_PGPASSWORD" ]]; then
    log "TC-2: attempting end-to-end call as gem..."
    RUN_ID_GEM=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', 'gem base')
RETURNING id;
")
    PGPASSWORD="$TEST_PGPASSWORD" psql -U gem -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -c "SELECT append_run_note($RUN_ID_GEM, 'gem appended this');" >/dev/null
    assert_true "TC-2: gem end-to-end append succeeded" "$(scalar "SELECT position('gem appended this' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_GEM;")"
else
    log "TC-2: skipping end-to-end gem connection (TEST_PGPASSWORD not set)"
    SKIP=$((SKIP + 1))
fi

# --- TC-3: timestamp correctness ---------------------------------------------

log "TC-3: timestamp correctness..."
RUN_ID_TC3=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', 'ts base')
RETURNING id;
")
BEFORE=$(scalar "SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI');")
run_psql "SET timezone = 'America/Chicago'; SELECT append_run_note($RUN_ID_TC3, 'timestamp check');" >/dev/null
AFTER=$(scalar "SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI');")
STAMP_TC3=$(scalar "SELECT (regexp_match(notes, '\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}'))[1] FROM workflow_runs WHERE id = $RUN_ID_TC3;")
assert_true "TC-3: stamp separator is UTC" "$(scalar "SELECT position(' UTC — ' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_TC3;")"
if [[ "$STAMP_TC3" < "$BEFORE" || "$STAMP_TC3" > "$AFTER" ]]; then
    log "FAIL: TC-3 stamp $STAMP_TC3 not in [$BEFORE, $AFTER]"
    FAIL=$((FAIL + 1))
else
    log "PASS: TC-3 stamp $STAMP_TC3 within bracket [$BEFORE, $AFTER]"
    PASS=$((PASS + 1))
fi

# --- TC-4: NULL notes column --------------------------------------------------

log "TC-4: NULL notes column (first note)..."
run_psql "SELECT append_run_note($RUN_ID_NULL_NOTES, 'the very first note');" >/dev/null
assert_true "TC-4: note appended to NULL column" "$(scalar "SELECT position('the very first note' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_NULL_NOTES;")"
assert_false "TC-4: notes has no leading newline" "$(scalar "SELECT starts_with(notes, chr(10)) FROM workflow_runs WHERE id = $RUN_ID_NULL_NOTES;")"

# --- TC-5: empty-string note --------------------------------------------------

log "TC-5: empty-string note..."
run_psql "SELECT append_run_note($RUN_ID_EMPTY_NOTES, '');" >/dev/null
assert_true "TC-5: empty note appended with separator" "$(scalar "SELECT position(' UTC — ' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_EMPTY_NOTES;")"
assert_true "TC-5: line ends with separator and nothing after" "$(scalar "SELECT notes LIKE '% UTC — ' FROM workflow_runs WHERE id = $RUN_ID_EMPTY_NOTES;")"

# --- TC-6: very long note -----------------------------------------------------

log "TC-6: very long note (10KB)..."
LONG_NOTE=$(python3 -c "print('x' * 10000)")
RUN_ID_TC6=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', 'long base')
RETURNING id;
")
BEFORE_LEN=$(scalar "SELECT length(notes) FROM workflow_runs WHERE id = $RUN_ID_TC6;")
run_psql "SELECT append_run_note($RUN_ID_TC6, '$LONG_NOTE');" >/dev/null
AFTER_LEN=$(scalar "SELECT length(notes) FROM workflow_runs WHERE id = $RUN_ID_TC6;")
# base length + newline(1) + stamp prefix(23) + note(10000)
EXPECTED_LEN=$((BEFORE_LEN + 1 + 23 + 10000))
assert_eq "TC-6: length increased by stamped long note" "$EXPECTED_LEN" "$AFTER_LEN"

# --- TC-7: quotes, embedded newlines, escape-like sequences --------------------

log "TC-7: quotes, embedded newlines, escape-like sequences..."
RUN_ID_TC7=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', 'escape base')
RETURNING id;
")
# Dollar-quoted payload avoids needing to escape single quotes.
run_psql "SELECT append_run_note($RUN_ID_TC7, \$\$quote ' test
mid-note newline and literal \n text\$\$);" >/dev/null
assert_true "TC-7: single quote preserved" "$(scalar "SELECT position('quote '' test' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_TC7;")"
assert_true "TC-7: embedded newline preserved" "$(scalar "SELECT position('mid-note newline' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_TC7;")"
assert_true "TC-7: literal backslash-n preserved" "$(scalar "SELECT position('literal \n text' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_TC7;")"

# --- TC-8: unicode and emoji --------------------------------------------------

log "TC-8: unicode and emoji..."
RUN_ID_TC8=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', 'unicode base')
RETURNING id;
")
run_psql "SELECT append_run_note($RUN_ID_TC8, 'unicode test: café, naïve, 日本語, 🎉🔥💎');" >/dev/null
assert_true "TC-8: unicode preserved" "$(scalar "SELECT position('unicode test: café, naïve, 日本語, 🎉🔥💎' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_TC8;")"
assert_eq "TC-8: server encoding is UTF8" "UTF8" "$(scalar "SHOW server_encoding;")"

# --- TC-9: nonexistent run_id -------------------------------------------------

log "TC-9: nonexistent run_id..."
set +e
ERROR_TC9=$(run_psql "SELECT append_run_note($NONEXISTENT_RUN_ID, 'ghost note');" 2>&1)
RC_TC9=$?
set -e
assert_eq "TC-9: raises exception" "1" "$RC_TC9"
if [[ "$ERROR_TC9" == *"append_run_note: run_id"* && "$ERROR_TC9" == *"$NONEXISTENT_RUN_ID"* ]]; then
    log "PASS: TC-9: error mentions run_id not found"
    PASS=$((PASS + 1))
else
    log "FAIL: TC-9: error mentions run_id not found"
    FAIL=$((FAIL + 1))
fi

# --- TC-10: NULL run_id -------------------------------------------------------

log "TC-10: NULL run_id..."
set +e
ERROR_TC10=$(run_psql "SELECT append_run_note(NULL, 'note for null run');" 2>&1)
RC_TC10=$?
set -e
assert_eq "TC-10: raises exception" "1" "$RC_TC10"
if [[ "$ERROR_TC10" == *"append_run_note: run_id"* ]]; then
    log "PASS: TC-10: error mentions run_id not found"
    PASS=$((PASS + 1))
else
    log "FAIL: TC-10: error mentions run_id not found"
    FAIL=$((FAIL + 1))
fi

# --- TC-11: NULL note ---------------------------------------------------------

log "TC-11: NULL note (P0 data-loss guard)..."
BEFORE_TC11=$(scalar "SELECT notes FROM workflow_runs WHERE id = $RUN_ID_WITH_NOTES;")
set +e
ERROR_TC11=$(run_psql "SELECT append_run_note($RUN_ID_WITH_NOTES, NULL);" 2>&1)
RC_TC11=$?
set -e
AFTER_TC11=$(scalar "SELECT notes FROM workflow_runs WHERE id = $RUN_ID_WITH_NOTES;")
assert_eq "TC-11: raises exception" "1" "$RC_TC11"
if [[ "$ERROR_TC11" == *"append_run_note: p_note cannot be NULL"* ]]; then
    log "PASS: TC-11: error mentions NULL note"
    PASS=$((PASS + 1))
else
    log "FAIL: TC-11: error mentions NULL note"
    FAIL=$((FAIL + 1))
fi
assert_eq "TC-11: notes column unchanged after NULL note attempt" "$BEFORE_TC11" "$AFTER_TC11"

# --- TC-12: SECURITY DEFINER + search_path hardening --------------------------

log "TC-12: SECURITY DEFINER and search_path hardening..."
assert_true "TC-12: prosecdef is true" "$(scalar "SELECT prosecdef FROM pg_proc WHERE proname = 'append_run_note';")"
PROCONFIG=$(scalar "SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE proname = 'append_run_note';")
if [[ "$PROCONFIG" == *"search_path=public"* ]]; then
    log "PASS: TC-12: search_path pinned to public"
    PASS=$((PASS + 1))
else
    log "FAIL: TC-12: search_path pinned to public (proconfig='$PROCONFIG')"
    FAIL=$((FAIL + 1))
fi

# --- TC-13: SQL injection safety ----------------------------------------------

log "TC-13: SQL injection safety..."
RUN_ID_TC13=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', 'inject base')
RETURNING id;
")
PAYLOAD="'; DROP TABLE workflow_runs; --"
# Use dollar-quoted string so single quotes in the payload are literal data.
run_psql "SELECT append_run_note($RUN_ID_TC13, \$p\$${PAYLOAD}\$p\$);" >/dev/null
TABLE_EXISTS=$(scalar "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'workflow_runs';")
assert_eq "TC-13: workflow_runs table still exists" "1" "$TABLE_EXISTS"
assert_true "TC-13: payload stored verbatim" "$(scalar "SELECT position('; DROP TABLE workflow_runs; --' in notes) > 0 FROM workflow_runs WHERE id = $RUN_ID_TC13;")"

# --- TC-14: EXECUTE grants cover intended roles -------------------------------

log "TC-14: EXECUTE grants cover intended agent roles..."
ROLES=(gem coder scribe scout iris marcie ticker quill athena argus conductor erato flint hermes newhart gidget nova)
for role in "${ROLES[@]}"; do
    assert_true "TC-14: $role can EXECUTE append_run_note" "$(scalar "SELECT has_function_privilege('$role', 'append_run_note(integer,text)', 'EXECUTE');")"
done

# --- TC-15: agent role still cannot UPDATE directly ---------------------------

log "TC-15: agent role still cannot UPDATE workflow_runs directly..."
assert_false "TC-15: gem lacks direct UPDATE on workflow_runs" "$(scalar "SELECT has_table_privilege('gem', 'workflow_runs', 'UPDATE');")"
assert_false "TC-15: scout lacks direct UPDATE on workflow_runs" "$(scalar "SELECT has_table_privilege('scout', 'workflow_runs', 'UPDATE');")"
assert_true "TC-15: nova (table owner) can UPDATE workflow_runs" "$(scalar "SELECT has_table_privilege('nova', 'workflow_runs', 'UPDATE');")"

# --- TC-16: concurrency — no lost update --------------------------------------

log "TC-16: concurrent appends to the same run..."
RUN_ID_TC16=$(scalar "
INSERT INTO workflow_runs (workflow_id, status, channel, notes)
VALUES (1, 'running', 'test:$SESSION_KEY', 'concurrent base')
RETURNING id;
")

PIDS=()
for i in $(seq 1 10); do
    (
        if [[ -n "$TEST_PGPASSWORD" ]]; then
            PGPASSWORD="$TEST_PGPASSWORD" psql -U "$TEST_PGUSER" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -c "SELECT append_run_note($RUN_ID_TC16, 'concurrent note ' || '$i');" >/dev/null 2>&1
        else
            unset PGPASSWORD
            psql -U "$TEST_PGUSER" -d "$TEST_PGDATABASE" -h "$TEST_PGHOST" -c "SELECT append_run_note($RUN_ID_TC16, 'concurrent note ' || '$i');" >/dev/null 2>&1
        fi
    ) &
    PIDS+=("$!")
done
for pid in "${PIDS[@]}"; do
    wait "$pid"
done

LINE_COUNT=$(scalar "SELECT array_length(regexp_split_to_array(notes, chr(10)), 1) FROM workflow_runs WHERE id = $RUN_ID_TC16;")
# base line + 10 appended lines = 11 total lines
assert_eq "TC-16: all 10 concurrent notes landed (11 lines)" "11" "$LINE_COUNT"

# --- cleanup ------------------------------------------------------------------

log "Cleaning up test rows for session $SESSION_KEY..."
run_psql "DELETE FROM workflow_runs WHERE channel = 'test:$SESSION_KEY';" >/dev/null

# --- summary ------------------------------------------------------------------

log "Summary: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
log "Test suite finished at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi
exit 0
