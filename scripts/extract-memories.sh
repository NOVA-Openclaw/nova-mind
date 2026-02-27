#!/bin/bash
set -e

# Load OpenClaw environment (API keys from openclaw.json)
ENV_LOADER="${HOME}/.openclaw/lib/env-loader.sh"
[ -f "$ENV_LOADER" ] && source "$ENV_LOADER" && load_openclaw_env

# Load centralized PostgreSQL configuration
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env

INPUT_TEXT="${1:-$(cat)}"
[ -z "$INPUT_TEXT" ] && exit 1

# Sender info from environment (set by hook)
SENDER="${SENDER_NAME:-unknown}"
SENDER_ID="${SENDER_ID:-}"
IS_GROUP="${IS_GROUP:-false}"

# API key must be set in environment (inherited from OpenClaw)
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "ERROR: ANTHROPIC_API_KEY not set in environment" >&2
    echo "This script should be run from OpenClaw hooks which inherit the API key" >&2
    exit 1
fi


# Look up user's default visibility preference
DEFAULT_VIS="public"
if [ -n "$SENDER_ID" ]; then
    DEFAULT_VIS=$(psql -t -A -c "
        SELECT ef2.value FROM entity_facts ef1
        JOIN entity_facts ef2 ON ef1.entity_id = ef2.entity_id
        WHERE ef1.key IN ('phone', 'has_phone_number', 'signal')
          AND REPLACE(REPLACE(ef1.value, '-', ''), ' ', '') LIKE '%$(echo "$SENDER_ID" | sed 's/[+ -]//g')%'
          AND ef2.key = 'default_visibility'
        LIMIT 1;
    " 2>/dev/null || echo "public")
    [ -z "$DEFAULT_VIS" ] && DEFAULT_VIS="public"
fi

# Get existing facts for deduplication check
EXISTING_FACTS=$(psql -t -A -c "
    SELECT DISTINCT CONCAT(e.name, '.', ef.key, '=', LEFT(ef.value, 100)) 
    FROM entity_facts ef 
    JOIN entities e ON e.id = ef.entity_id 
    ORDER BY 1 
    LIMIT 200;
" 2>/dev/null | tr '\n' '; ' | head -c 2000)

EXISTING_VOCAB=$(psql -t -A -c "
    SELECT word FROM vocabulary ORDER BY word LIMIT 200;
" 2>/dev/null | tr '\n' ', ' | head -c 1000)

# Build prompt with sender attribution and context awareness
PROMPT="Extract memory data as JSON from a CONVERSATION with context.

SENDER: ${SENDER}
IS_GROUP_CHAT: ${IS_GROUP}
USER_DEFAULT_VISIBILITY: ${DEFAULT_VIS}

CONVERSATION (oldest to newest, with speaker labels [USER] and [NOVA]):
${INPUT_TEXT}

IMPORTANT INSTRUCTIONS:

1. EXTRACT FROM THE CURRENT MESSAGE (marked [CURRENT USER MESSAGE] or [CURRENT NOVA MESSAGE]): The conversation includes both [USER] and [NOVA] (the AI assistant) messages for context. Use the full conversation to understand references like \"that\", \"he\", \"it\", etc. Extract facts, opinions, events, and actions from the CURRENT MESSAGE only.

2. USE CONTEXT TO RESOLVE REFERENCES: If current message says \"Yes, I love that\" and context shows they were discussing pizza, extract \"preference: pizza\".

3. FOR EVERY EXTRACTED ITEM, include:
   - source_person: \"${SENDER}\" (who said this)
   - visibility: privacy level (see below)
   - visibility_reason: ONLY if visibility differs from user default

4. DEDUPLICATION - DO NOT EXTRACT if we already have this info:
   Existing facts (sample): ${EXISTING_FACTS:-none}
   Existing vocabulary: ${EXISTING_VOCAB:-none}
   
   Skip any fact that duplicates existing data. Only extract NEW information.

PRIVACY DETECTION:
The user's default visibility is \"${DEFAULT_VIS}\". 
- If default is \"private\": everything is private UNLESS they say otherwise
- If default is \"public\": everything is public UNLESS they say otherwise

Look for privacy cues that OVERRIDE the default:
- Make PUBLIC: \"feel free to share\", \"this is public\", \"you can tell others\"
- Make PRIVATE: \"just between us\", \"don't tell anyone\", \"keep this secret\", \"confidential\"

DELEGATION CONTEXT:
NOVA frequently delegates tasks to specialized agents. When you see patterns like:
- \"Let me get [AGENT] to help\"
- \"I'll delegate this to [AGENT]\"
- \"[AGENT] fixed/completed/handled [TASK]\"
- \"Consider [AGENT] for this task\"
- \"[AGENT] is good at [CAPABILITY]\"

Extract as facts with subject=\"NOVA\":
- predicate: \"delegates_to\", value: \"AGENT_NAME for TASK_TYPE\"
- predicate: \"agent_capability\", value: \"AGENT_NAME: what they're good at\"
- predicate: \"agent_success\", value: \"AGENT_NAME: completed task description\"
- predicate: \"agent_failure\", value: \"AGENT_NAME: what went wrong\"

Set visibility=\"public\" for delegation facts (they're operational knowledge).
Known agents: Coder (coding), Gidget (git-ops), Scout (research), IRIS (creative), Hermes (comms), Scribe (docs), Ticker (portfolio), Athena (media), Newhart (meta/agents).

Return JSON with these categories (only include non-empty ones, skip if nothing NEW to extract):

entities: [{name, type (person|ai|organization|place), location?, source_person, visibility, visibility_reason?}]
facts: [{subject, predicate, value, source_person, confidence, visibility, visibility_reason?}]
opinions: [{holder, subject, opinion, source_person, confidence, visibility, visibility_reason?}]
preferences: [{person, category, preference, source_person, confidence, visibility, visibility_reason?}]
vocabulary: [{word, category, misheard_as?, source_person, visibility}]
events: [{description, date?, source_person, visibility, visibility_reason?}]

If the current message contains NO extractable new information (just casual chat, acknowledgments, etc), return: {}

Return ONLY valid JSON, no markdown fences."

# Build JSON payload
PAYLOAD=$(jq -n --arg prompt "$PROMPT" '{
  model: "claude-sonnet-4-20250514",
  max_tokens: 2048,
  messages: [{role: "user", content: $prompt}]
}')

curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD" | jq -r '.content[0].text // empty'
