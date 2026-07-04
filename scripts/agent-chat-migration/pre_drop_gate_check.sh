#!/usr/bin/env bash
# pre_drop_gate_check.sh — Verify all six decommission gates before dropping
# agent_chat objects from nova_memory.
#
# Issue: NOVA-Openclaw/nova-mind#320
#
# Gates:
#   1. Row counts match between source and target databases.
#   2. Sequence last_value >= max(id) in target database.
#   3. Round-trip freshness verified (manual attestation required).
#   4. Zero unresolved delta rows in source database after cutoff.
#   5. No unresolved dependent objects blocking DROP (pg_depend check).
#   6. Consumer scripts repointed (manual attestation required).
#
# Usage:
#   ./pre_drop_gate_check.sh \
#       [--source-db nova_memory] [--target-db agent_chat] \
#       [--host localhost] [--port 5432] [--user postgres] \
#       [--round-trip-log path/to/roundtrip.log] \
#       [--consumer-attestation path/to/consumers.log] \
#       [--gate-pass-marker /var/run/agent_chat_gate_pass.timestamp] \
#       [--delta-cutoff-id ID] [--delta-cutoff-ts ISO8601]
#
# Exit codes:
#   0  All gates passed; marker file written.
#   1  One or more gates failed (details printed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE_DB="nova_memory"
TARGET_DB="agent_chat"
HOST="localhost"
PORT="5432"
USER="postgres"
ROUND_TRIP_LOG=""
CONSUMER_ATTESTATION=""
GATE_PASS_MARKER=""
DELTA_CUTOFF_ID=""
DELTA_CUTOFF_TS=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --source-db DB                  Source database (default: nova_memory)
  --target-db DB                  Target database (default: agent_chat)
  --host HOST                     PostgreSQL host (default: localhost)
  --port PORT                     PostgreSQL port (default: 5432)
  --user USER                     PostgreSQL user (default: postgres)
  --round-trip-log PATH           Log file attesting fresh round-trip tests (gate 3)
  --consumer-attestation PATH     File attesting consumer scripts are repointed (gate 6)
  --gate-pass-marker PATH         Path to write on success (default: none)
  --delta-cutoff-id ID            Cutoff id for delta check (default: target max id)
  --delta-cutoff-ts ISO8601       Cutoff timestamp for delta check (default: target newest)
  -h, --help                      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-db) SOURCE_DB="$2"; shift 2 ;;
        --target-db) TARGET_DB="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --user) USER="$2"; shift 2 ;;
        --round-trip-log) ROUND_TRIP_LOG="$2"; shift 2 ;;
        --consumer-attestation) CONSUMER_ATTESTATION="$2"; shift 2 ;;
        --gate-pass-marker) GATE_PASS_MARKER="$2"; shift 2 ;;
        --delta-cutoff-id) DELTA_CUTOFF_ID="$2"; shift 2 ;;
        --delta-cutoff-ts) DELTA_CUTOFF_TS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

PSQL="psql -h ${HOST} -p ${PORT} -U ${USER} -v ON_ERROR_STOP=1"

run_sql_value() {
    local db="$1"
    local sql="$2"
    ${PSQL} -d "${db}" -tA -c "${sql}"
}

run_sql() {
    local db="$1"
    local sql="$2"
    ${PSQL} -d "${db}" -c "${sql}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
fail_gate() {
    local gate="$1"
    local reason="$2"
    echo ""
    echo "GATE ${gate} FAILED: ${reason}" >&2
}

GATES_PASSED=true

# ---------------------------------------------------------------------------
# Gate 1: Row count match
# ---------------------------------------------------------------------------
echo "== Gate 1: Row count match =="
COUNTS=$(cat <<'EOF'
SELECT
    (SELECT count(*)::bigint FROM public.agent_chat) || '|' ||
    (SELECT count(*)::bigint FROM public.agent_chat_processed);
EOF
)
SRC_COUNTS=$(run_sql_value "${SOURCE_DB}" "${COUNTS}")
TGT_COUNTS=$(run_sql_value "${TARGET_DB}" "${COUNTS}")

SRC_CHAT_COUNT=$(echo "${SRC_COUNTS}" | cut -d'|' -f1)
SRC_PROC_COUNT=$(echo "${SRC_COUNTS}" | cut -d'|' -f2)
TGT_CHAT_COUNT=$(echo "${TGT_COUNTS}" | cut -d'|' -f1)
TGT_PROC_COUNT=$(echo "${TGT_COUNTS}" | cut -d'|' -f2)

echo "   Source: agent_chat=${SRC_CHAT_COUNT}, agent_chat_processed=${SRC_PROC_COUNT}"
echo "   Target: agent_chat=${TGT_CHAT_COUNT}, agent_chat_processed=${TGT_PROC_COUNT}"

if [[ "${SRC_CHAT_COUNT}" != "${TGT_CHAT_COUNT}" || "${SRC_PROC_COUNT}" != "${TGT_PROC_COUNT}" ]]; then
    fail_gate 1 "Row counts differ between ${SOURCE_DB} and ${TARGET_DB}."
    GATES_PASSED=false
else
    echo "   PASS"
fi

# ---------------------------------------------------------------------------
# Gate 2: Sequence / max(id) alignment
# ---------------------------------------------------------------------------
echo "== Gate 2: Sequence / max(id) alignment =="
ALIGN=$(cat <<'EOF'
SELECT
    (SELECT COALESCE(max(id), 0) FROM public.agent_chat) || '|' ||
    (SELECT last_value FROM public.agent_chat_id_seq) || '|' ||
    (SELECT is_called FROM public.agent_chat_id_seq);
EOF
)
ALIGN_RESULT=$(run_sql_value "${TARGET_DB}" "${ALIGN}")
MAX_ID=$(echo "${ALIGN_RESULT}" | cut -d'|' -f1)
SEQ_LAST=$(echo "${ALIGN_RESULT}" | cut -d'|' -f2)
SEQ_IS_CALLED=$(echo "${ALIGN_RESULT}" | cut -d'|' -f3)

echo "   max(id): ${MAX_ID}, last_value: ${SEQ_LAST}, is_called: ${SEQ_IS_CALLED}"

if [[ "${SEQ_LAST}" -lt "${MAX_ID}" ]]; then
    fail_gate 2 "Sequence last_value (${SEQ_LAST}) is less than max(id) (${MAX_ID})."
    GATES_PASSED=false
elif [[ "${SEQ_IS_CALLED}" != "t" && "${SEQ_IS_CALLED}" != "true" ]]; then
    fail_gate 2 "Sequence is_called flag is not true (would cause next nextval to repeat max id)."
    GATES_PASSED=false
else
    echo "   PASS"
fi

# ---------------------------------------------------------------------------
# Gate 3: Round-trip freshness attestation
# ---------------------------------------------------------------------------
echo "== Gate 3: Round-trip freshness =="
if [[ -z "${ROUND_TRIP_LOG}" || ! -f "${ROUND_TRIP_LOG}" ]]; then
    fail_gate 3 "Missing or unreadable round-trip attestation log (--round-trip-log). Fresh round-trips for all peers/subagents/Victoria must be recorded."
    GATES_PASSED=false
else
    echo "   Attestation file: ${ROUND_TRIP_LOG}"
    echo "   Contents:"
    sed 's/^/      /' "${ROUND_TRIP_LOG}"
    echo "   PASS (operator attestation accepted)"
fi

# ---------------------------------------------------------------------------
# Gate 4: Zero unresolved delta rows
# ---------------------------------------------------------------------------
# Delegate to delta_check_and_migrate.py in report-only mode. The Python
# script implements the authoritative two-part delta check:
#   A) agent_chat rows with id > cutoff_id
#   B) agent_chat_processed rows updated after cutoff_ts for chat_ids already
#      migrated (chat_id <= cutoff_id).
# Re-implementing this logic in shell/SQL caused the original Gate 4 bug
# (NOVA-Openclaw/nova-mind#375): the SQL-only check missed part B.
echo "== Gate 4: Zero unresolved delta rows =="

if [[ -z "${DELTA_CUTOFF_ID}" ]]; then
    DELTA_CUTOFF_ID=$(run_sql_value "${TARGET_DB}" "SELECT COALESCE(max(id), 0) FROM public.agent_chat;")
fi
if [[ -z "${DELTA_CUTOFF_TS}" ]]; then
    DELTA_CUTOFF_TS=$(run_sql_value "${TARGET_DB}" "SELECT max(\"timestamp\")::text FROM public.agent_chat;")
fi

echo "   Delta cutoff id: ${DELTA_CUTOFF_ID}"
echo "   Delta cutoff ts: ${DELTA_CUTOFF_TS}"

DELTA_CHECK_ARGS=(
    "--source-db" "${SOURCE_DB}"
    "--target-db" "${TARGET_DB}"
    "--host" "${HOST}"
    "--port" "${PORT}"
    "--user" "${USER}"
    "--cutoff-id" "${DELTA_CUTOFF_ID}"
    "--cutoff-ts" "${DELTA_CUTOFF_TS}"
)

echo "   Delegating delta check to delta_check_and_migrate.py (report-only)..."
DELTA_RC=0
DELTA_OUT=$("${SCRIPT_DIR}/delta_check_and_migrate.py" "${DELTA_CHECK_ARGS[@]}" 2>&1) || DELTA_RC=$?

# delta_check_and_migrate.py returns:
#   0 = no delta rows
#   1 = delta rows found (report-only mode)
#   2 = id-space collision
#   3 = sequence misalignment after migration (only possible with --migrate)
# Any non-zero result means the gate fails.
if [[ ${DELTA_RC} -ne 0 ]]; then
    echo "   delta_check_and_migrate.py exited with code ${DELTA_RC}:" >&2
    echo "${DELTA_OUT}" >&2
    fail_gate 4 "Unresolved delta rows remain in ${SOURCE_DB}. Run delta_check_and_migrate.py --migrate before decommission."
    GATES_PASSED=false
else
    echo "${DELTA_OUT}"
    echo "   PASS"
fi

# ---------------------------------------------------------------------------
# Gate 5: Dependent-object resolution
# ---------------------------------------------------------------------------
echo "== Gate 5: Dependent-object resolution =="

# Find any objects in the source DB that still depend on agent_chat/agent_chat_processed
# and are NOT the expected objects we plan to drop ourselves.
DEP_SQL=$(cat <<'EOF'
SELECT
    d.classid::regclass AS dependent_type,
    d.objid::regclass::text AS dependent_object,
    d.refobjid::regclass::text AS referenced_object
FROM pg_depend d
JOIN pg_class c ON c.oid = d.objid
WHERE d.refobjid IN ('public.agent_chat'::regclass, 'public.agent_chat_processed'::regclass)
  AND d.deptype = 'n'
  AND c.relname NOT IN (
      'agent_chat', 'agent_chat_processed', 'agent_chat_id_seq',
      'idx_agent_chat_recipients', 'idx_agent_chat_sender', 'idx_agent_chat_timestamp',
      'idx_agent_chat_processed_agent', 'idx_agent_chat_processed_status', 'idx_agent_chat_processed_unique',
      'idx_chat_processed_agent',
      'v_agent_chat_recent', 'v_agent_chat_stats'
  )
ORDER BY referenced_object, dependent_object;
EOF
)

DEP_COUNT=$(run_sql_value "${SOURCE_DB}" "SELECT count(*) FROM (${DEP_SQL}) sub;")
if [[ "${DEP_COUNT}" -ne 0 ]]; then
    echo "   Unresolved dependencies:" >&2
    run_sql "${SOURCE_DB}" "${DEP_SQL}" >&2
    fail_gate 5 "Found ${DEP_COUNT} dependent object(s) in ${SOURCE_DB} that are not in the planned drop list."
    GATES_PASSED=false
else
    echo "   No unexpected dependencies."
    echo "   PASS"
fi

# ---------------------------------------------------------------------------
# Gate 6: Consumer-script repoint attestation
# ---------------------------------------------------------------------------
echo "== Gate 6: Consumer-script repoint attestation =="
if [[ -z "${CONSUMER_ATTESTATION}" || ! -f "${CONSUMER_ATTESTATION}" ]]; then
    fail_gate 6 "Missing or unreadable consumer attestation (--consumer-attestation). Required scripts (proactive-gate-check.py, pg-notify-listener.py, agent_chat plugin configs) must be repointed and smoke-tested."
    GATES_PASSED=false
else
    echo "   Attestation file: ${CONSUMER_ATTESTATION}"
    echo "   Contents:"
    sed 's/^/      /' "${CONSUMER_ATTESTATION}"
    echo "   PASS (operator attestation accepted)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ "${GATES_PASSED}" != "true" ]]; then
    echo "ERROR: One or more decommission gates failed. DROP blocked." >&2
    exit 1
fi

echo "SUCCESS: All decommission gates passed."
if [[ -n "${GATE_PASS_MARKER}" ]]; then
    MARKER_DIR=$(dirname "${GATE_PASS_MARKER}")
    if [[ ! -d "${MARKER_DIR}" ]]; then
        mkdir -p "${MARKER_DIR}"
    fi
    {
        echo "agent_chat decommission gates passed"
        echo "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "source_db: ${SOURCE_DB}"
        echo "target_db: ${TARGET_DB}"
        echo "chat_count: ${TGT_CHAT_COUNT}"
        echo "processed_count: ${TGT_PROC_COUNT}"
        echo "max_id: ${MAX_ID}"
        echo "seq_last_value: ${SEQ_LAST}"
    } > "${GATE_PASS_MARKER}"
    echo "Marker written: ${GATE_PASS_MARKER}"
fi

exit 0
