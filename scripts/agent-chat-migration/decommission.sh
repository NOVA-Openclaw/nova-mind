#!/usr/bin/env bash
# decommission.sh — Drop agent_chat bus objects from the legacy nova_memory database.
#
# Issue: NOVA-Openclaw/nova-mind#320
#
# This script performs explicit, object-by-object drops (NO CASCADE) in the
# required order:
#   1. Drop the job_messages.message_id FK constraint (decision #3).
#   2. Drop triggers on agent_chat.
#   3. Drop views that depend on agent_chat.
#   4. Drop functions (including the broken chat() helper and embed_chat_message).
#   5. Drop tables (processed first because of the FK to agent_chat).
#   6. Drop the sequence.
#   7. Drop the enum type.
#
# Safety:
#   * Refuses to run unless a fresh gate-pass marker exists, OR the operator
#     passes --rerun-gate (which re-runs pre_drop_gate_check.sh before DROP).
#   * Refuses to run if --i-understand-the-risk is not provided.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_CHECK_SCRIPT="${SCRIPT_DIR}/pre_drop_gate_check.sh"

SOURCE_DB="nova_memory"
TARGET_DB="agent_chat"
HOST="localhost"
PORT="5432"
USER="postgres"
GATE_PASS_MARKER=""
RERUN_GATE=false
I_UNDERSTAND=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --source-db DB          Source/legacy database (default: nova_memory)
  --target-db DB          Target database (default: agent_chat)
  --host HOST             PostgreSQL host (default: localhost)
  --port PORT             PostgreSQL port (default: 5432)
  --user USER             PostgreSQL user (default: postgres)
  --gate-pass-marker PATH Path to gate-pass marker file (required unless --rerun-gate)
  --rerun-gate            Re-run the gate check before dropping
  --i-understand-the-risk Acknowledge that this DESTROYS agent_chat data in the source DB
  -h, --help              Show this help

Example:
  $(basename "$0") --gate-pass-marker /run/agent_chat_gate_pass.timestamp --i-understand-the-risk
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-db) SOURCE_DB="$2"; shift 2 ;;
        --target-db) TARGET_DB="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --user) USER="$2"; shift 2 ;;
        --gate-pass-marker) GATE_PASS_MARKER="$2"; shift 2 ;;
        --rerun-gate) RERUN_GATE=true; shift ;;
        --i-understand-the-risk) I_UNDERSTAND=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ "${I_UNDERSTAND}" != "true" ]]; then
    echo "ERROR: This script drops agent_chat objects from ${SOURCE_DB}. Re-run with --i-understand-the-risk." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Gate check
# ---------------------------------------------------------------------------
if [[ "${RERUN_GATE}" == "true" ]]; then
    echo "== Re-running decommission gate check =="
    if ! "${GATE_CHECK_SCRIPT}" \
            --source-db "${SOURCE_DB}" \
            --target-db "${TARGET_DB}" \
            --host "${HOST}" \
            --port "${PORT}" \
            --user "${USER}" \
            --gate-pass-marker "${GATE_PASS_MARKER:-/dev/null}"; then
        echo "ERROR: Gate check failed. DROP aborted." >&2
        exit 1
    fi
    echo "Gate check passed."
elif [[ -z "${GATE_PASS_MARKER}" || ! -f "${GATE_PASS_MARKER}" ]]; then
    echo "ERROR: Gate-pass marker missing: ${GATE_PASS_MARKER}" >&2
    echo "Run pre_drop_gate_check.sh first, or pass --rerun-gate." >&2
    exit 1
else
    # Marker exists; verify it is fresh (within last 24 hours) to avoid stale passes.
    MARKER_AGE_MINUTES=$(( ($(date +%s) - $(stat -c %Y "${GATE_PASS_MARKER}")) / 60 ))
    if [[ "${MARKER_AGE_MINUTES}" -gt 1440 ]]; then
        echo "ERROR: Gate-pass marker is older than 24 hours (${MARKER_AGE_MINUTES} minutes). Re-run gate check." >&2
        exit 1
    fi
    echo "== Using gate-pass marker: ${GATE_PASS_MARKER} (age ${MARKER_AGE_MINUTES} minutes) =="
fi

PSQL="psql -h ${HOST} -p ${PORT} -U ${USER} -d ${SOURCE_DB} -v ON_ERROR_STOP=1"

run_sql() {
    local sql="$1"
    ${PSQL} -c "${sql}"
}

# ---------------------------------------------------------------------------
# 1. Drop FK constraint on job_messages.message_id
# ---------------------------------------------------------------------------
echo "== Step 1: Drop job_messages.message_id FK =="
run_sql "ALTER TABLE public.job_messages DROP CONSTRAINT IF EXISTS job_messages_message_id_fkey;"

# ---------------------------------------------------------------------------
# 2. Drop triggers on agent_chat
# ---------------------------------------------------------------------------
echo "== Step 2: Drop triggers on agent_chat =="
run_sql "DROP TRIGGER IF EXISTS trg_embed_chat_message ON public.agent_chat;"
run_sql "DROP TRIGGER IF EXISTS trg_enforce_agent_chat_function_use ON public.agent_chat;"
run_sql "DROP TRIGGER IF EXISTS trg_enforce_function_use ON public.agent_chat;"
run_sql "DROP TRIGGER IF EXISTS trg_notify_agent_chat ON public.agent_chat;"

# ---------------------------------------------------------------------------
# 3. Drop views
# ---------------------------------------------------------------------------
echo "== Step 3: Drop views =="
run_sql "DROP VIEW IF EXISTS public.v_agent_chat_recent;"
run_sql "DROP VIEW IF EXISTS public.v_agent_chat_stats;"

# ---------------------------------------------------------------------------
# 4. Drop functions
# ---------------------------------------------------------------------------
echo "== Step 4: Drop functions =="
run_sql "DROP FUNCTION IF EXISTS public.send_agent_message(text, text, text[]);"
run_sql "DROP FUNCTION IF EXISTS public.notify_agent_chat();"
run_sql "DROP FUNCTION IF EXISTS public.enforce_agent_chat_function_use();"
run_sql "DROP FUNCTION IF EXISTS public.expire_old_chat(integer);"
run_sql "DROP FUNCTION IF EXISTS public.chat(text, varchar);"
run_sql "DROP FUNCTION IF EXISTS public.embed_chat_message();"

# ---------------------------------------------------------------------------
# 5. Drop tables
# ---------------------------------------------------------------------------
echo "== Step 5: Drop tables =="
run_sql "DROP TABLE IF EXISTS public.agent_chat_processed;"
run_sql "DROP TABLE IF EXISTS public.agent_chat;"

# ---------------------------------------------------------------------------
# 6. Drop sequence
# ---------------------------------------------------------------------------
echo "== Step 6: Drop sequence =="
run_sql "DROP SEQUENCE IF EXISTS public.agent_chat_id_seq;"

# ---------------------------------------------------------------------------
# 7. Drop type
# ---------------------------------------------------------------------------
echo "== Step 7: Drop enum type =="
run_sql "DROP TYPE IF EXISTS public.agent_chat_status;"

# ---------------------------------------------------------------------------
# Confirm source DB no longer contains the objects
# ---------------------------------------------------------------------------
echo "== Step 8: Post-DROP sanity check =="
REMAINING=$(run_sql "SELECT count(*) FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname IN ('agent_chat','agent_chat_processed','agent_chat_id_seq');")
echo "   Remaining agent_chat class count: ${REMAINING}"

if [[ "${REMAINING}" -ne 0 ]]; then
    echo "ERROR: Some agent_chat objects remain in ${SOURCE_DB}." >&2
    exit 1
fi

echo ""
echo "SUCCESS: agent_chat bus objects decommissioned from ${SOURCE_DB}."
echo "The shared messaging bus now lives only in ${TARGET_DB}."
