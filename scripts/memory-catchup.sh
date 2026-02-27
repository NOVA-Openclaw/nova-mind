#!/bin/bash
# memory-catchup.sh - Process unprocessed messages from session transcripts
# Processes BOTH user AND assistant messages for memory extraction
# Maintains a rolling cache of 20 messages for context
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
