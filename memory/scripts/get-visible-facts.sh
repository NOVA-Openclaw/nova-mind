#!/bin/bash
# get-visible-facts.sh - Get facts visible to current session participants
# Usage: get-visible-facts.sh <participant_entity_ids> [query]
# Example: get-visible-facts.sh "2,56" "favorite color"

set -e

# Load centralized PostgreSQL configuration
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env

PARTICIPANT_IDS="${1:-}"
QUERY="${2:-}"


if [ -z "$PARTICIPANT_IDS" ]; then
    echo "Usage: get-visible-facts.sh <participant_entity_ids> [query]" >&2
    echo "Example: get-visible-facts.sh '2,56' 'favorite color'" >&2
    exit 1
fi

# Build the visibility filter
# Visible if:
#   1. visibility = 'public', OR
#   2. source_entity_id is one of the participants (their own data), OR
#   3. privacy_scope overlaps with participants (explicitly shared)
VISIBILITY_FILTER="(
    visibility = 'public'
    OR source_entity_id IN ($PARTICIPANT_IDS)
    OR privacy_scope && ARRAY[$PARTICIPANT_IDS]
)"

# Build optional text search
if [ -n "$QUERY" ]; then
    SEARCH_FILTER="AND (
        key ILIKE '%$(echo "$QUERY" | sed "s/'/''/g")%'
        OR value ILIKE '%$(echo "$QUERY" | sed "s/'/''/g")%'
    )"
else
    SEARCH_FILTER=""
fi

# Query with privacy filtering
psql -t << EOF
SELECT json_agg(row_to_json(t)) FROM (
    SELECT 
        e.name as entity_name,
        ef.key,
        ef.value,
        ef.source,
        ef.visibility,
        ef.learned_at
    FROM entity_facts ef
    JOIN entities e ON ef.entity_id = e.id
    WHERE $VISIBILITY_FILTER
    $SEARCH_FILTER
    ORDER BY ef.learned_at DESC
    LIMIT 100
) t;
EOF
