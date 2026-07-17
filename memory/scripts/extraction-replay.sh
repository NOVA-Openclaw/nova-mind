#!/usr/bin/env bash
# extraction-replay.sh — Replay failed memory extractions from extraction_failures.
# Issue #485 dead-letter replay path.
#
# Design:
#   - flock-protected (single concurrent invocation)
#   - Sources env-loader.sh + pg-env.sh so cron runs with API keys / PG vars
#   - Processes up to BATCH_LIMIT pending rows per run
#   - Reconstructs message body from channel_transcripts.content (FK case) or
#     the stored content fallback; rows with neither are marked unreplayable.
#   - Feeds extract_memories.py via stdin (never as shell args)
#   - On success: status='resolved', resolved_at=NOW()
#   - On failure: retry_count++, last_attempt_at=NOW(); if retry_count >= MAX_RETRIES
#     status='retry_exhausted'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load OpenClaw env (API keys) and PostgreSQL env.
ENV_LOADER="${HOME}/.openclaw/lib/env-loader.sh"
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$ENV_LOADER" ] && source "$ENV_LOADER" && load_openclaw_env
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env 2>/dev/null || true

# Flock lock file
LOCK_FILE="${HOME}/.openclaw/run/extraction-replay.lock"
mkdir -p "$(dirname "$LOCK_FILE")"

# Try to acquire exclusive non-blocking lock on file descriptor 200.
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[extraction-replay] Lock held ($LOCK_FILE), another invocation is running. Exiting."
    exit 0
fi

# Config
BATCH_LIMIT="${EXTRACTION_REPLAY_BATCH_LIMIT:-10}"
MAX_RETRIES="${EXTRACTION_REPLAY_MAX_RETRIES:-5}"
EXTRACT_SCRIPT="${EXTRACTION_SCRIPT_PATH_OVERRIDE:-${HOME}/.openclaw/scripts/extract_memories.py}"
PYTHON_CMD="${EXTRACTION_PYTHON_CMD_OVERRIDE:-python3}"

if [ ! -f "$EXTRACT_SCRIPT" ]; then
    echo "[extraction-replay] ERROR: extract_memories.py not found at $EXTRACT_SCRIPT" >&2
    exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
    echo "[extraction-replay] ERROR: psql not found in PATH" >&2
    exit 1
fi

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "[extraction-replay] WARNING: ANTHROPIC_API_KEY not set — extractions will likely fail" >&2
fi

DB="${PGDATABASE:-nova_memory}"

# Helper: run psql with the configured database.
psql_run() {
    psql "$DB" -t -A -c "$1"
}

# Fetch the next batch of pending rows.
ROWS=$(psql_run "
    SELECT id,
           channel_transcript_id,
           session_key,
           sender_name,
           sender_id,
           content,
           retry_count
    FROM extraction_failures
    WHERE status = 'pending'
    ORDER BY retry_count ASC, created_at ASC, id ASC
    LIMIT ${BATCH_LIMIT};
")

if [ -z "$ROWS" ]; then
    echo "[extraction-replay] No pending rows to replay."
    exit 0
fi

PROCESSED=0
SUCCESS=0
FAILED=0
UNREPLAYABLE=0

while IFS='|' read -r id channel_transcript_id session_key sender_name sender_id content retry_count; do
    [ -z "$id" ] && continue
    PROCESSED=$((PROCESSED + 1))

    echo "[extraction-replay] Processing row id=$id (retry_count=$retry_count)"

    # Determine message body.
    body=""
    if [ -n "$channel_transcript_id" ]; then
        body=$(psql_run "
            SELECT content FROM channel_transcripts WHERE id = ${channel_transcript_id} LIMIT 1;
        " || true)
    fi
    if [ -z "$body" ] && [ -n "$content" ]; then
        body="$content"
    fi

    # NULL FK + NULL body => permanently unreplayable.
    if [ -z "$body" ]; then
        echo "[extraction-replay] Row id=$id has no transcript FK and no body fallback — marking unreplayable"
        psql_run "
            UPDATE extraction_failures
            SET status = 'unreplayable',
                updated_at = NOW()
            WHERE id = ${id};
        " || true
        UNREPLAYABLE=$((UNREPLAYABLE + 1))
        continue
    fi

    # Resolve session_id for env var when we have a transcript FK.
    session_db_id=""
    if [ -n "$channel_transcript_id" ]; then
        session_db_id=$(psql_run "
            SELECT session_id FROM channel_transcripts WHERE id = ${channel_transcript_id} LIMIT 1;
        " || true)
    fi

    sender_name_esc="${sender_name:-unknown}"
    sender_id_esc="${sender_id:-}"
    session_key_esc="${session_key:-}"
    timestamp_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Feed extract_memories.py via stdin; do NOT pass body as a shell arg.
    exit_code=0
    printf '%s' "$body" | \
        SENDER_NAME="$sender_name_esc" \
        SENDER_ID="$sender_id_esc" \
        IS_GROUP="false" \
        SOURCE_SESSION_ID="$session_key_esc" \
        SOURCE_TIMESTAMP="$timestamp_iso" \
        SOURCE_CHANNEL_TRANSCRIPT_ID="${channel_transcript_id:-}" \
        SOURCE_CHANNEL_SESSION_ID="${session_db_id:-}" \
        "$PYTHON_CMD" "$EXTRACT_SCRIPT" >/dev/null 2>&1 || exit_code=$?


    if [ "$exit_code" -eq 0 ]; then
        echo "[extraction-replay] Row id=$id replay succeeded"
        psql_run "
            UPDATE extraction_failures
            SET status = 'resolved',
                resolved_at = NOW(),
                updated_at = NOW()
            WHERE id = ${id};
        " || true
        SUCCESS=$((SUCCESS + 1))
    else
        echo "[extraction-replay] Row id=$id replay failed (exit_code=$exit_code)"
        new_retry=$((retry_count + 1))
        if [ "$new_retry" -ge "$MAX_RETRIES" ]; then
            psql_run "
                UPDATE extraction_failures
                SET retry_count = ${new_retry},
                    last_attempt_at = NOW(),
                    status = 'retry_exhausted',
                    updated_at = NOW()
                WHERE id = ${id};
            " || true
            echo "[extraction-replay] Row id=$id reached max retries, marked retry_exhausted"
        else
            psql_run "
                UPDATE extraction_failures
                SET retry_count = ${new_retry},
                    last_attempt_at = NOW(),
                    updated_at = NOW()
                WHERE id = ${id};
            " || true
        fi
        FAILED=$((FAILED + 1))
    fi
done <<< "$ROWS"

echo "[extraction-replay] Run complete: processed=$PROCESSED success=$SUCCESS failed=$FAILED unreplayable=$UNREPLAYABLE"
exit 0
