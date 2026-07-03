#!/usr/bin/env bash
# migrate.sh — Create the dedicated agent_chat database and migrate the bus.
# Issue: NOVA-Openclaw/nova-mind#320
#
# Usage:
#   ./migrate.sh [--source-db nova_memory] [--target-db agent_chat]
#                [--host localhost] [--port 5432] [--superuser postgres]
#                [--dry-run]
#
# This script is idempotent for the schema-creation path: re-running it after a
# successful migration will skip the database creation and re-apply the schema
# (CREATE IF NOT EXISTS / OR REPLACE are safe). Data is NOT copied twice unless
# the target tables are empty; if target tables already contain rows, the data
# copy step is skipped and a warning is printed.
#
# The script must be run as a PostgreSQL superuser (or a role with CREATEDB and
# REPLICATION/ bypass-replication-session privileges so that --disable-triggers
# works during the data copy).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCHEMA_FILE="${REPO_ROOT}/database/agent-chat/schema.sql"

SOURCE_DB="nova_memory"
TARGET_DB="agent_chat"
HOST="localhost"
PORT="5432"
SUPERUSER="postgres"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --source-db DB      Source database (default: nova_memory)
  --target-db DB      Target database to create (default: agent_chat)
  --host HOST         PostgreSQL host (default: localhost)
  --port PORT         PostgreSQL port (default: 5432)
  --superuser USER    Superuser name for DB creation/schema apply (default: postgres)
  --dry-run           Print commands without executing them
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-db) SOURCE_DB="$2"; shift 2 ;;
        --target-db) TARGET_DB="$2"; shift 2 ;;
        --host) HOST="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --superuser) SUPERUSER="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

PSQL_SUPER="psql -h ${HOST} -p ${PORT} -U ${SUPERUSER} -d"
PSQL_TARGET="psql -h ${HOST} -p ${PORT} -U ${SUPERUSER} -d ${TARGET_DB}"

run_sql() {
    local db="$1"
    local sql="$2"
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "DRY-RUN: psql -h ${HOST} -p ${PORT} -U ${SUPERUSER} -d ${db} -c '${sql}'"
        return 0
    fi
    psql -h "${HOST}" -p "${PORT}" -U "${SUPERUSER}" -d "${db}" -v ON_ERROR_STOP=1 -c "${sql}"
}

run_sql_value() {
    local db="$1"
    local sql="$2"
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "DRY-RUN: psql -h ${HOST} -p ${PORT} -U ${SUPERUSER} -d ${db} -tA -c '${sql}'"
        return 0
    fi
    psql -h "${HOST}" -p "${PORT}" -U "${SUPERUSER}" -d "${db}" -v ON_ERROR_STOP=1 -tA -c "${sql}"
}

run_file() {
    local db="$1"
    local file="$2"
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "DRY-RUN: psql -h ${HOST} -p ${PORT} -U ${SUPERUSER} -d ${db} -f ${file}"
        return 0
    fi
    psql -h "${HOST}" -p "${PORT}" -U "${SUPERUSER}" -d "${db}" -v ON_ERROR_STOP=1 -f "${file}"
}

# ---------------------------------------------------------------------------
# 1. Validate source database and count rows before migration.
# ---------------------------------------------------------------------------
echo "== Step 1: Validate source database ${SOURCE_DB} =="
if [[ "${DRY_RUN}" == "true" ]]; then
    SOURCE_CHAT_COUNT="DRYRUN"
    SOURCE_PROC_COUNT="DRYRUN"
    SOURCE_MAX_ID="DRYRUN"
    SOURCE_ORPHAN_REPLY=0
    SOURCE_ORPHAN_PROC=0
else
    SOURCE_CHAT_COUNT=$(run_sql_value "${SOURCE_DB}" "SELECT count(*)::bigint FROM public.agent_chat;")
    SOURCE_PROC_COUNT=$(run_sql_value "${SOURCE_DB}" "SELECT count(*)::bigint FROM public.agent_chat_processed;")
    SOURCE_MAX_ID=$(run_sql_value "${SOURCE_DB}" "SELECT coalesce(max(id), 0) FROM public.agent_chat;")
    SOURCE_ORPHAN_REPLY=$(run_sql_value "${SOURCE_DB}" "SELECT count(*) FROM public.agent_chat WHERE reply_to IS NOT NULL AND reply_to NOT IN (SELECT id FROM public.agent_chat);")
    SOURCE_ORPHAN_PROC=$(run_sql_value "${SOURCE_DB}" "SELECT count(*) FROM public.agent_chat_processed WHERE chat_id NOT IN (SELECT id FROM public.agent_chat);")
fi

echo "   Source agent_chat rows:        ${SOURCE_CHAT_COUNT}"
echo "   Source agent_chat_processed rows: ${SOURCE_PROC_COUNT}"
echo "   Source max(agent_chat.id):     ${SOURCE_MAX_ID}"
echo "   Source orphan reply_to refs:   ${SOURCE_ORPHAN_REPLY}"
echo "   Source orphan processed refs:  ${SOURCE_ORPHAN_PROC}"

if [[ "${DRY_RUN}" != "true" && ( -z "${SOURCE_CHAT_COUNT}" || -z "${SOURCE_PROC_COUNT}" || -z "${SOURCE_MAX_ID}" ) ]]; then
    echo "ERROR: Could not read source counts. Check connection and privileges." >&2
    exit 1
fi

if [[ "${SOURCE_ORPHAN_REPLY}" -gt 0 || "${SOURCE_ORPHAN_PROC}" -gt 0 ]]; then
    echo "   WARNING: source database has ${SOURCE_ORPHAN_REPLY} orphan reply_to and ${SOURCE_ORPHAN_PROC} orphan processed references." >&2
    echo "   These will be preserved in the target and FK constraints re-added as NOT VALID." >&2
fi

# ---------------------------------------------------------------------------
# 2. Create target database if it does not exist.
# ---------------------------------------------------------------------------
echo "== Step 2: Create target database ${TARGET_DB} (if missing) =="
DB_EXISTS=$(run_sql_value "postgres" "SELECT 1 FROM pg_database WHERE datname = '${TARGET_DB}';")
if [[ "${DB_EXISTS}" == "1" ]]; then
    echo "   Database ${TARGET_DB} already exists."
else
    run_sql "postgres" "CREATE DATABASE \"${TARGET_DB}\";"
    echo "   Created database ${TARGET_DB}."
fi

# ---------------------------------------------------------------------------
# 3. Apply schema to target database.
# ---------------------------------------------------------------------------
echo "== Step 3: Apply schema to ${TARGET_DB} =="
if [[ ! -f "${SCHEMA_FILE}" ]]; then
    echo "ERROR: Schema file not found: ${SCHEMA_FILE}" >&2
    exit 1
fi
run_file "${TARGET_DB}" "${SCHEMA_FILE}"
echo "   Schema applied."

# ---------------------------------------------------------------------------
# 4. Copy data from source to target.
#    --disable-triggers avoids firing notify/enforce triggers during bulk load.
# ---------------------------------------------------------------------------
echo "== Step 4: Copy data from ${SOURCE_DB} to ${TARGET_DB} =="

if [[ "${DRY_RUN}" == "true" ]]; then
    TARGET_CHAT_COUNT=0
else
    TARGET_CHAT_COUNT=$(run_sql_value "${TARGET_DB}" "SELECT count(*)::bigint FROM public.agent_chat;")
fi
if [[ "${TARGET_CHAT_COUNT}" -gt 0 ]]; then
    echo "   WARNING: target agent_chat already has ${TARGET_CHAT_COUNT} rows. Skipping data copy." >&2
    echo "   If you want to re-copy, truncate the target tables first." >&2
else
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "DRY-RUN: COPY data from ${SOURCE_DB} to ${TARGET_DB} with triggers disabled"
    else
        # Disable user triggers in target to avoid firing notify/enforce triggers
        # on historical data. Drop the self-referential reply_to FK temporarily
        # so the bulk load does not have to be ordered; re-add it after load.
        run_sql "${TARGET_DB}" "ALTER TABLE public.agent_chat DISABLE TRIGGER USER; ALTER TABLE public.agent_chat_processed DISABLE TRIGGER USER; ALTER TABLE public.agent_chat DROP CONSTRAINT IF EXISTS agent_chat_reply_to_fkey; ALTER TABLE public.agent_chat_processed DROP CONSTRAINT IF EXISTS agent_chat_processed_chat_id_fkey;"

        # Stream COPY from source to target for agent_chat.
        psql -h "${HOST}" -p "${PORT}" -U "${SUPERUSER}" -d "${SOURCE_DB}" -v ON_ERROR_STOP=1 -c "COPY public.agent_chat (id, sender, message, recipients, reply_to, \"timestamp\") TO STDOUT;" \
            | psql -h "${HOST}" -p "${PORT}" -U "${SUPERUSER}" -d "${TARGET_DB}" -v ON_ERROR_STOP=1 -c "COPY public.agent_chat (id, sender, message, recipients, reply_to, \"timestamp\") FROM STDIN;"

        # Stream COPY from source to target for agent_chat_processed.
        psql -h "${HOST}" -p "${PORT}" -U "${SUPERUSER}" -d "${SOURCE_DB}" -v ON_ERROR_STOP=1 -c "COPY public.agent_chat_processed (chat_id, agent, received_at, routed_at, responded_at, error_message, status) TO STDOUT;" \
            | psql -h "${HOST}" -p "${PORT}" -U "${SUPERUSER}" -d "${TARGET_DB}" -v ON_ERROR_STOP=1 -c "COPY public.agent_chat_processed (chat_id, agent, received_at, routed_at, responded_at, error_message, status) FROM STDIN;"

        # Re-add FK constraints and re-enable triggers. If the source has orphan
        # references, re-add constraints as NOT VALID to preserve data exactly.
        if [[ "${SOURCE_ORPHAN_REPLY}" -gt 0 ]]; then
            REPLY_VALID="NOT VALID"
        else
            REPLY_VALID=""
        fi
        if [[ "${SOURCE_ORPHAN_PROC}" -gt 0 ]]; then
            PROC_VALID="NOT VALID"
        else
            PROC_VALID=""
        fi
        run_sql "${TARGET_DB}" "ALTER TABLE public.agent_chat ADD CONSTRAINT agent_chat_reply_to_fkey FOREIGN KEY (reply_to) REFERENCES public.agent_chat(id) ${REPLY_VALID}; ALTER TABLE public.agent_chat_processed ADD CONSTRAINT agent_chat_processed_chat_id_fkey FOREIGN KEY (chat_id) REFERENCES public.agent_chat(id) ${PROC_VALID}; ALTER TABLE public.agent_chat ENABLE TRIGGER USER; ALTER TABLE public.agent_chat_processed ENABLE TRIGGER USER; ALTER TABLE public.agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;"
    fi
    echo "   Data copy complete."
fi

# ---------------------------------------------------------------------------
# 5. Set sequence to max(id) with is_called = true.
# ---------------------------------------------------------------------------
echo "== Step 5: Align agent_chat_id_seq with migrated data =="
run_sql "${TARGET_DB}" "SELECT setval('public.agent_chat_id_seq', (SELECT COALESCE(max(id), 1) FROM public.agent_chat), true);"
echo "   Sequence aligned."

# ---------------------------------------------------------------------------
# 6. Post-copy verification.
# ---------------------------------------------------------------------------
echo "== Step 6: Post-copy verification =="
VERIFY_SQL=$(cat <<'EOF'
SELECT
    (SELECT count(*)::bigint FROM public.agent_chat) AS chat_rows,
    (SELECT count(*)::bigint FROM public.agent_chat_processed) AS proc_rows,
    (SELECT COALESCE(max(id), 0) FROM public.agent_chat) AS max_chat_id,
    (SELECT last_value FROM public.agent_chat_id_seq) AS seq_last_value,
    (SELECT COALESCE(max(id), 0) FROM public.agent_chat_id_seq) AS seq_max,  -- dummy, same as last_value
    (SELECT count(*) FROM public.agent_chat WHERE reply_to IS NOT NULL AND reply_to NOT IN (SELECT id FROM public.agent_chat)) AS orphan_reply_to,
    (SELECT count(*) FROM public.agent_chat_processed WHERE chat_id NOT IN (SELECT id FROM public.agent_chat)) AS orphan_processed;
EOF
)

# Re-run verification using a clean, pipe-delimited query.
VERIFY_SQL=$(cat <<'EOF'
SELECT
    (SELECT count(*)::bigint FROM public.agent_chat) || '|' ||
    (SELECT count(*)::bigint FROM public.agent_chat_processed) || '|' ||
    (SELECT COALESCE(max(id), 0) FROM public.agent_chat) || '|' ||
    (SELECT last_value FROM public.agent_chat_id_seq) || '|' ||
    (SELECT count(*) FROM public.agent_chat WHERE reply_to IS NOT NULL AND reply_to NOT IN (SELECT id FROM public.agent_chat)) || '|' ||
    (SELECT count(*) FROM public.agent_chat_processed WHERE chat_id NOT IN (SELECT id FROM public.agent_chat));
EOF
)

if [[ "${DRY_RUN}" == "true" ]]; then
    VERIFY_RESULT="0|0|0|0|0|0"
else
    VERIFY_RESULT=$(run_sql_value "${TARGET_DB}" "${VERIFY_SQL}")
fi

echo "   Verification result: ${VERIFY_RESULT}"

# Parse the result.
TGT_CHAT_COUNT=$(echo "${VERIFY_RESULT}" | cut -d'|' -f1)
TGT_PROC_COUNT=$(echo "${VERIFY_RESULT}" | cut -d'|' -f2)
TGT_MAX_ID=$(echo "${VERIFY_RESULT}" | cut -d'|' -f3)
TGT_SEQ_LAST=$(echo "${VERIFY_RESULT}" | cut -d'|' -f4)
TGT_ORPHAN_REPLY=$(echo "${VERIFY_RESULT}" | cut -d'|' -f5)
TGT_ORPHAN_PROC=$(echo "${VERIFY_RESULT}" | cut -d'|' -f6)

if [[ "${DRY_RUN}" == "true" ]]; then
    echo ""
    echo "DRY-RUN: Migration plan complete (no changes made)."
    exit 0
fi

PASS=true
if [[ "${TGT_CHAT_COUNT}" != "${SOURCE_CHAT_COUNT}" ]]; then
    echo "   FAIL: agent_chat row count mismatch (source=${SOURCE_CHAT_COUNT}, target=${TGT_CHAT_COUNT})" >&2
    PASS=false
fi
if [[ "${TGT_PROC_COUNT}" != "${SOURCE_PROC_COUNT}" ]]; then
    echo "   FAIL: agent_chat_processed row count mismatch (source=${SOURCE_PROC_COUNT}, target=${TGT_PROC_COUNT})" >&2
    PASS=false
fi
if [[ "${TGT_SEQ_LAST}" -lt "${TGT_MAX_ID}" ]]; then
    echo "   FAIL: sequence last_value (${TGT_SEQ_LAST}) < max(id) (${TGT_MAX_ID})" >&2
    PASS=false
fi
if [[ "${TGT_ORPHAN_REPLY}" != "${SOURCE_ORPHAN_REPLY}" ]]; then
    echo "   FAIL: target has ${TGT_ORPHAN_REPLY} orphan reply_to refs but source had ${SOURCE_ORPHAN_REPLY}" >&2
    PASS=false
fi
if [[ "${TGT_ORPHAN_PROC}" != "${SOURCE_ORPHAN_PROC}" ]]; then
    echo "   FAIL: target has ${TGT_ORPHAN_PROC} orphan processed refs but source had ${SOURCE_ORPHAN_PROC}" >&2
    PASS=false
fi
if [[ "${TGT_ORPHAN_REPLY}" -gt 0 || "${TGT_ORPHAN_PROC}" -gt 0 ]]; then
    echo "   WARNING: target preserved ${TGT_ORPHAN_REPLY} reply_to and ${TGT_ORPHAN_PROC} processed orphans from source." >&2
fi

if [[ "${PASS}" == "true" ]]; then
    echo ""
    echo "SUCCESS: Migration verification passed."
    echo "   Target DB: ${TARGET_DB}"
    echo "   agent_chat rows: ${TGT_CHAT_COUNT}"
    echo "   agent_chat_processed rows: ${TGT_PROC_COUNT}"
    echo "   max(chat.id): ${TGT_MAX_ID}"
    echo "   sequence last_value: ${TGT_SEQ_LAST}"
else
    echo ""
    echo "ERROR: Migration verification failed. Do not proceed to rollout." >&2
    exit 1
fi
