#!/bin/bash
# resolve-participants.sh - Resolve Signal IDs/phones to entity IDs
# Usage: resolve-participants.sh "+18178964104" "+15125551234" ...
# Output: comma-separated entity IDs (e.g., "2,56")

set -e

# Load centralized PostgreSQL configuration
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env


ENTITY_IDS=""

for PARTICIPANT in "$@"; do
    # Skip empty args
    [ -z "$PARTICIPANT" ] && continue
    
    # Normalize phone number (remove spaces, dashes, plus)
    NORMALIZED=$(echo "$PARTICIPANT" | sed 's/[+ -]//g')
    
    # Try to find entity by phone number in entity_facts
    ENTITY_ID=$(psql -t -A -c "
        SELECT DISTINCT entity_id FROM entity_facts 
        WHERE key IN ('phone', 'has_phone_number', 'signal', 'signal_id')
          AND REPLACE(REPLACE(value, '-', ''), ' ', '') LIKE '%$NORMALIZED%'
        LIMIT 1;
    " 2>/dev/null)
    
    if [ -n "$ENTITY_ID" ]; then
        if [ -n "$ENTITY_IDS" ]; then
            ENTITY_IDS="$ENTITY_IDS,$ENTITY_ID"
        else
            ENTITY_IDS="$ENTITY_ID"
        fi
    fi
done

echo "$ENTITY_IDS"
