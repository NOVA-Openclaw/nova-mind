#!/bin/bash
# memory-catchup.sh - Process unprocessed messages from session transcripts
# Processes BOTH user AND assistant messages for memory extraction
# Maintains a rolling cache of 20 messages for context
# Also ingests JSONL session transcripts and daily memory/*.md files into the DB.
# Usage: memory-catchup.sh [--log]   # --log enables detailed extraction logging

set -e

# Load OpenClaw environment (API keys from openclaw.json)
ENV_LOADER="${HOME}/.openclaw/lib/env-loader.sh"
[ -f "$ENV_LOADER" ] && source "$ENV_LOADER" && load_openclaw_env

# Check for --log flag
VERBOSE_LOG=false
if [[ "$1" == "--log" ]]; then
    VERBOSE_LOG=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${HOME}/.openclaw/memory-catchup-state.json"
CACHE_FILE="${HOME}/.openclaw/memory-message-cache.json"
TRANSCRIPT_DIR="${HOME}/.openclaw/agents/main/sessions"
EXTRACT_SCRIPT="${SCRIPT_DIR}/process-input.sh"
CACHE_SIZE=20

# Ensure state/cache files exist
mkdir -p "$(dirname "$STATE_FILE")"
if [ ! -f "$STATE_FILE" ]; then
    echo '{"last_processed_ts": "1970-01-01T00:00:00.000Z", "processed_count": 0}' > "$STATE_FILE"
fi
if [ ! -f "$CACHE_FILE" ]; then
    echo '[]' > "$CACHE_FILE"
fi

# Get last processed timestamp
LAST_TS=$(jq -r '.last_processed_ts // "1970-01-01T00:00:00.000Z"' "$STATE_FILE")
CURRENT_TS=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

echo "[memory-catchup] Last processed: $LAST_TS"
echo "[memory-catchup] Looking for new messages..."

# Find the most recent session transcript
MAIN_SESSION=$(ls -t "$TRANSCRIPT_DIR"/*.jsonl 2>/dev/null | head -1)

if [ -z "$MAIN_SESSION" ] || [ ! -f "$MAIN_SESSION" ]; then
    echo "[memory-catchup] No session transcripts found"
    exit 0
fi

echo "[memory-catchup] Processing: $MAIN_SESSION"

# Extract ALL messages (user + assistant) to process - BOTH get extracted now
MESSAGES_TO_PROCESS=$(mktemp)

jq -c --arg last_ts "$LAST_TS" '
    select(.type == "message") |
    select(.message.role == "user" or .message.role == "assistant") |
    select(.timestamp > $last_ts) |
    {
        content: (
            if (.message.content | type) == "array" then
                (.message.content[] | select(.type == "text") | .text) // ""
            elif (.message.content | type) == "string" then
                .message.content
            else
                ""
            end
        ),
        timestamp: .timestamp,
        role: .message.role
    } |
    select(.content != "" and .content != null)
' "$MAIN_SESSION" 2>/dev/null > "$MESSAGES_TO_PROCESS" || true

MSG_COUNT=$(wc -l < "$MESSAGES_TO_PROCESS" | tr -d ' ')
echo "[memory-catchup] Found $MSG_COUNT new messages (user + assistant)"

if [ "$MSG_COUNT" -eq 0 ] || [ ! -s "$MESSAGES_TO_PROCESS" ]; then
    rm -f "$MESSAGES_TO_PROCESS"
    TOTAL=$(jq -r '.processed_count // 0' "$STATE_FILE")
    echo "{\"last_processed_ts\": \"$CURRENT_TS\", \"processed_count\": $TOTAL}" > "$STATE_FILE"
    echo "[memory-catchup] No new messages"
    exit 0
fi

# Get all recent messages for context pool
ALL_MESSAGES=$(mktemp)
jq -c '
    select(.type == "message") |
    select(.message.role == "user" or .message.role == "assistant") |
    {
        content: (
            if (.message.content | type) == "array" then
                (.message.content[] | select(.type == "text") | .text) // ""
            elif (.message.content | type) == "string" then
                .message.content
            else
                ""
            end
        ),
        timestamp: .timestamp,
        role: .message.role
    } |
    select(.content != "" and .content != null)
' "$MAIN_SESSION" 2>/dev/null | tail -100 > "$ALL_MESSAGES" || true

# Function to build context and check for duplicates
add_to_cache_and_get_context() {
    local target_ts="$1"
    local target_content="$2"
    local target_role="$3"
    
    # Read current cache
    local cache=$(cat "$CACHE_FILE")
    
    # Check for duplicate (same content in last 5 messages)
    local is_dup=$(echo "$cache" | jq -r --arg content "$target_content" '
        .[-5:] | map(select(.content == $content)) | length > 0
    ')
    
    if [ "$is_dup" = "true" ]; then
        echo "DUPLICATE"
        return
    fi
    
    # Get messages BEFORE target timestamp for context
    local context_messages=$(cat "$ALL_MESSAGES" | jq -c --arg ts "$target_ts" '
        select(.timestamp < $ts)
    ' | tail -19)
    
    # Build new cache
    local new_cache=$(echo "$context_messages" | jq -s --arg content "$target_content" --arg ts "$target_ts" --arg role "$target_role" '
        . + [{content: $content, timestamp: $ts, role: $role}] | .[-20:]
    ')
    
    # Save updated cache
    echo "$new_cache" > "$CACHE_FILE"
    
    # Format context with speaker labels
    local speaker_label
    if [ "$target_role" = "assistant" ]; then
        speaker_label="[CURRENT NOVA MESSAGE - EXTRACT FROM THIS]"
    else
        speaker_label="[CURRENT USER MESSAGE - EXTRACT FROM THIS]"
    fi
    
    echo "$new_cache" | jq -r --arg current_label "$speaker_label" '
        to_entries | map(
            if .key == (length - 1) then
                $current_label + "\n" + .value.content
            else
                (if .value.role == "assistant" then "[NOVA]" else "[USER]" end) + " " + 
                (.key + 1 | tostring) + ":\n" + .value.content
            end
        ) | join("\n\n---\n\n")
    '
}

# Process each message (both user AND assistant)
PROCESSED=0
NEWEST_TS="$LAST_TS"
while IFS= read -r line; do
    CONTENT=$(echo "$line" | jq -r '.content // empty' 2>/dev/null)
    MSG_TS=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null)
    MSG_ROLE=$(echo "$line" | jq -r '.role // "user"' 2>/dev/null)
    
    # Skip empty or very short messages
    if [ -z "$CONTENT" ] || [ ${#CONTENT} -lt 20 ]; then
        continue
    fi
    
    # Skip system-like content
    if [[ "$CONTENT" == /* ]] || [[ "$CONTENT" == "HEARTBEAT"* ]] || [[ "$CONTENT" == "NO_REPLY"* ]]; then
        continue
    fi
    if [[ "$CONTENT" == "System:"* ]]; then
        continue
    fi
    if [[ "$CONTENT" == *"Read HEARTBEAT.md"* ]] || [[ "$CONTENT" == *"DASHBOARD UPDATE"* ]]; then
        continue
    fi
    
    # Build context
    CONTEXT=$(add_to_cache_and_get_context "$MSG_TS" "$CONTENT" "$MSG_ROLE")
    
    if [ "$CONTEXT" = "DUPLICATE" ]; then
        echo "[memory-catchup] Skipping duplicate: ${CONTENT:0:50}..."
        continue
    fi
    
    SPEAKER="USER"
    [ "$MSG_ROLE" = "assistant" ] && SPEAKER="NOVA"
    echo "[memory-catchup] Processing $SPEAKER message: ${CONTENT:0:70}..."
    
    # Set sender info based on role
    if [ "$MSG_ROLE" = "assistant" ]; then
        export SENDER_NAME="NOVA"
        export SENDER_ID="nova-assistant"
    else
        export SENDER_NAME="${SENDER_NAME:-I)ruid}"
        # SENDER_ID should come from the hook for user messages
    fi
    
    # Run extraction (API key must be in environment, inherited from OpenClaw)
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo "ERROR: ANTHROPIC_API_KEY not set in environment" >&2
        echo "This script should be run from OpenClaw hooks which inherit the API key" >&2
        exit 1
    fi
    
    if [ "$VERBOSE_LOG" = true ]; then
        EXTRACT_LOG="${HOME}/.openclaw/logs/memory-extractions.log"
        echo "---" >> "$EXTRACT_LOG"
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $SPEAKER MESSAGE (with conversation context):" >> "$EXTRACT_LOG"
        echo "$CONTEXT" | head -60 >> "$EXTRACT_LOG"
        echo "..." >> "$EXTRACT_LOG"
        
        RESULT=$("$EXTRACT_SCRIPT" "$CONTEXT" 2>&1)
        echo "$RESULT" | tail -25 >> "$EXTRACT_LOG"
        echo "" >> "$EXTRACT_LOG"
    else
        "$EXTRACT_SCRIPT" "$CONTEXT" &>/dev/null &
    fi
    
    PROCESSED=$((PROCESSED + 1))
    
    if [[ "$MSG_TS" > "$NEWEST_TS" ]]; then
        NEWEST_TS="$MSG_TS"
    fi
    
    # Rate limit - max 3 per run
    if [ "$PROCESSED" -ge 3 ]; then
        echo "[memory-catchup] Rate limit reached (3/run), will continue next run"
        break
    fi
    
    sleep 1
done < "$MESSAGES_TO_PROCESS"

rm -f "$MESSAGES_TO_PROCESS" "$ALL_MESSAGES"

# Update state
TOTAL=$(jq -r '.processed_count // 0' "$STATE_FILE")
NEW_TOTAL=$((TOTAL + PROCESSED))

if [[ "$NEWEST_TS" > "$LAST_TS" ]]; then
    echo "{\"last_processed_ts\": \"$NEWEST_TS\", \"processed_count\": $NEW_TOTAL}" > "$STATE_FILE"
else
    echo "{\"last_processed_ts\": \"$CURRENT_TS\", \"processed_count\": $NEW_TOTAL}" > "$STATE_FILE"
fi

echo "[memory-catchup] Processed $PROCESSED messages (total: $NEW_TOTAL)"
echo "[memory-catchup] Cache: $(cat "$CACHE_FILE" | jq 'length') messages"

# ─────────────────────────────────────────────────────────────
# Ingest JSONL session files → channel_sessions + channel_transcripts
# ─────────────────────────────────────────────────────────────

# Load PostgreSQL env so psql works without explicit credentials
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env 2>/dev/null || true

ALL_SESSIONS_DIR="${HOME}/.openclaw/agents"
INGEST_COUNT=0
INGEST_ERRORS=0

if command -v psql >/dev/null 2>&1; then
    # Check that channel_sessions table exists before attempting ingest
    TABLE_EXISTS=$(psql nova_memory -t -A -c \
        "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='channel_sessions');" \
        2>/dev/null || echo 'f')

    if [ "$TABLE_EXISTS" = 't' ]; then
        # Find all JSONL session files across all agents
        while IFS= read -r jsonl_file; do
            [ -f "$jsonl_file" ] || continue

            # Derive provider / agent_id from path: agents/<agent_id>/sessions/<file>.jsonl
            agent_id=$(echo "$jsonl_file" | sed -E 's|.*/agents/([^/]+)/sessions/.*|\1|')
            provider='openclaw'
            # Use filename stem as external_chat_id (stable per session file)
            external_chat_id=$(basename "$jsonl_file" .jsonl)

            # Extract first-message timestamp for started_at
            started_at=$(jq -r 'select(.timestamp) | .timestamp' "$jsonl_file" 2>/dev/null | head -1)
            [ -z "$started_at" ] && started_at=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

            # Extract session_key from any line that has it
            session_key=$(jq -r 'select(.session_key) | .session_key' "$jsonl_file" 2>/dev/null | head -1)
            [ -z "$session_key" ] && session_key="$external_chat_id"

            # Upsert channel_sessions row
            session_db_id=$(psql nova_memory -t -A -c "
                INSERT INTO channel_sessions
                    (session_key, agent_id, provider, external_chat_id, chat_type, started_at)
                VALUES
                    ('$(echo "$session_key" | sed "s/'/''/g")',
                     '$(echo "$agent_id" | sed "s/'/''/g")',
                     '$(echo "$provider" | sed "s/'/''/g")',
                     '$(echo "$external_chat_id" | sed "s/'/''/g")',
                     'direct',
                     '$(echo "$started_at" | sed "s/'/''/g")')
                ON CONFLICT (provider, external_chat_id, COALESCE(external_thread_id, ''))
                DO UPDATE SET
                    updated_at = NOW()
                RETURNING id;
            " 2>/dev/null | tr -d '[:space:]')

            if [ -z "$session_db_id" ]; then
                echo "[memory-catchup] WARNING: Could not upsert session for $jsonl_file" >&2
                INGEST_ERRORS=$((INGEST_ERRORS + 1))
                continue
            fi

            # Upsert each message into channel_transcripts
            msg_count=0
            while IFS= read -r line; do
                # Only process message-type entries
                msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
                [ "$msg_type" = 'message' ] || continue

                # Validate JSON line
                if ! echo "$line" | jq -e '.' >/dev/null 2>&1; then
                    echo "[memory-catchup] WARNING: Malformed JSON in $(basename "$jsonl_file"), skipping line" >&2
                    continue
                fi

                ext_msg_id=$(echo "$line" | jq -r '.id // .message_id // empty' 2>/dev/null)
                # Timestamp fallback with counter suffix to prevent collisions
                if [ -z "$ext_msg_id" ]; then
                    raw_ts=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null)
                    [ -n "$raw_ts" ] && ext_msg_id="${raw_ts}_${msg_count}"
                fi
                [ -z "$ext_msg_id" ] && continue

                msg_ts=$(echo "$line" | jq -r '.timestamp // empty' 2>/dev/null)
                [ -z "$msg_ts" ] && continue

                role=$(echo "$line" | jq -r '.message.role // "user"' 2>/dev/null)

                # Parse rich metadata fields from JSONL content
                chat_id=$(echo "$line" | jq -r '.chat_id // empty' 2>/dev/null)
                sender_id=$(echo "$line" | jq -r '.sender_id // empty' 2>/dev/null)
                sender_name=$(echo "$line" | jq -r '.sender // empty' 2>/dev/null)
                sender_username=$(echo "$line" | jq -r '.sender_username // empty' 2>/dev/null)
                is_group=$(echo "$line" | jq -r '.is_group_chat // false' 2>/dev/null)
                group_subject=$(echo "$line" | jq -r '.group_subject // empty' 2>/dev/null)

                content=$(echo "$line" | jq -r '
                    if (.message.content | type) == "array" then
                        (.message.content[] | select(.type=="text") | .text) // ""
                    elif (.message.content | type) == "string" then
                        .message.content
                    else ""
                    end
                ' 2>/dev/null | head -c 65535)

                raw_meta=$(echo "$line" | jq -c '.' 2>/dev/null | head -c 65535 | sed "s/'/''/g")

                # Build dynamic column list for rich metadata
                ct_cols="session_id, external_message_id, timestamp, role, content, raw_metadata"
                ct_vals="$session_db_id, '$(echo "$ext_msg_id" | sed "s/'/''/g")', '$(echo "$msg_ts" | sed "s/'/''/g")', '$(echo "$role" | sed "s/'/''/g")', '$(echo "$content" | sed "s/'/''/g")', '$(echo "$raw_meta")'::jsonb"
                [ -n "$sender_id" ] && ct_cols="$ct_cols, sender_id" && ct_vals="$ct_vals, '$(echo "$sender_id" | sed "s/'/''/g")'"
                [ -n "$sender_name" ] && ct_cols="$ct_cols, sender_name" && ct_vals="$ct_vals, '$(echo "$sender_name" | sed "s/'/''/g")'"
                [ -n "$sender_username" ] && ct_cols="$ct_cols, sender_username" && ct_vals="$ct_vals, '$(echo "$sender_username" | sed "s/'/''/g")'"

                transcript_db_id=$(psql nova_memory -t -A -c "
                    INSERT INTO channel_transcripts ($ct_cols)
                    VALUES ($ct_vals)
                    ON CONFLICT (session_id, external_message_id) DO NOTHING
                    RETURNING id;
                " 2>/dev/null | tr -d '[:space:]')

                msg_count=$((msg_count + 1))

                # Pass transcript/session FK ids to extraction pipeline
                if [ -n "$transcript_db_id" ]; then
                    export SOURCE_CHANNEL_TRANSCRIPT_ID="$transcript_db_id"
                    export SOURCE_CHANNEL_SESSION_ID="$session_db_id"
                fi
            done < "$jsonl_file"

            # Always recompute message_count and last_message_at from actual DB state
            psql nova_memory -q -c "
                UPDATE channel_sessions SET
                    message_count = (SELECT COUNT(*) FROM channel_transcripts WHERE session_id = $session_db_id),
                    last_message_at = (SELECT MAX(timestamp) FROM channel_transcripts WHERE session_id = $session_db_id),
                    updated_at = NOW()
                WHERE id = $session_db_id;
            " 2>/dev/null || true

            INGEST_COUNT=$((INGEST_COUNT + msg_count))

            # Only delete source JSONL if psql session upsert succeeded (session_db_id is set)
            if [ -n "$session_db_id" ]; then
                rm -f "$jsonl_file"
                echo "[memory-catchup] Ingested $msg_count messages from $(basename "$jsonl_file") → channel_transcripts (session $session_db_id)"
            else
                echo "[memory-catchup] WARNING: Skipped deletion of $(basename "$jsonl_file") — session upsert failed" >&2
            fi

        done < <(find "$ALL_SESSIONS_DIR" -path '*/sessions/*.jsonl' -type f 2>/dev/null)

        echo "[memory-catchup] Transcript ingest: $INGEST_COUNT messages, $INGEST_ERRORS errors"
    else
        echo "[memory-catchup] channel_sessions table not found — skipping transcript ingest (run migration 067 first)"
    fi
else
    echo "[memory-catchup] psql not available — skipping transcript ingest"
fi

# ─────────────────────────────────────────────────────────────
# Ingest daily memory/*.md files into DB (content only), then delete
# ─────────────────────────────────────────────────────────────
MEMORY_MD_DIR="${HOME}/.openclaw/memory"
if [ -d "$MEMORY_MD_DIR" ]; then
    while IFS= read -r md_file; do
        [ -f "$md_file" ] || continue
        md_content=$(cat "$md_file" 2>/dev/null)
        [ -z "$md_content" ] && rm -f "$md_file" && continue

        # Store the file content as an entity fact on the 'NOVA' entity (agent notes)
        md_key="daily_memory_note"
        md_date=$(date -u +"%Y-%m-%d")

        # Warn if content is being truncated
        md_len=${#md_content}
        if [ "$md_len" -gt 4000 ]; then
            echo "[memory-catchup] WARNING: $(basename "$md_file") is $md_len chars, truncating to 4000" >&2
        fi

        if psql nova_memory -q -c "
            INSERT INTO entity_facts (entity_id, key, value, source)
            SELECT id, '$(echo "$md_key" | sed "s/'/''/g")',
                   '$(echo "$md_content" | sed "s/'/''/g" | head -c 4000)',
                   'memory-catchup:$(echo "$md_date" | sed "s/'/''/g")'
            FROM entities WHERE LOWER(name) = 'nova'
            ON CONFLICT DO NOTHING;
        " 2>/dev/null; then
            echo "[memory-catchup] Ingested memory MD: $(basename "$md_file")"
            rm -f "$md_file"
        else
            echo "[memory-catchup] WARNING: Failed to ingest $(basename "$md_file"), keeping file" >&2
        fi
    done < <(find "$MEMORY_MD_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null)
fi
