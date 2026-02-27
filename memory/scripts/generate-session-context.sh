#!/bin/bash
# generate-session-context.sh - Generate privacy-filtered context for session
# Usage: generate-session-context.sh <output_file> <participant_phones...>
# Example: generate-session-context.sh /tmp/session-context.md "+18178964104" "+15125551234"

set -e

# Load centralized PostgreSQL configuration
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${1:-/tmp/session-context.md}"
shift

# Resolve participants to entity IDs
ENTITY_IDS=$("$SCRIPT_DIR/resolve-participants.sh" "$@")

if [ -z "$ENTITY_IDS" ]; then
    echo "# Session Context" > "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "No recognized participants." >> "$OUTPUT_FILE"
    exit 0
fi

# Get participant names

PARTICIPANT_NAMES=$(psql -t -A -c "
    SELECT string_agg(name, ', ') FROM entities WHERE id IN ($ENTITY_IDS);
" 2>/dev/null)

# Generate context header
cat > "$OUTPUT_FILE" << EOF
# Session Context (Privacy-Filtered)

**Participants:** $PARTICIPANT_NAMES
**Entity IDs:** $ENTITY_IDS
**Generated:** $(date -u +"%Y-%m-%d %H:%M UTC")

## Visible Facts

EOF

# Get visible facts and format as markdown
FACTS=$("$SCRIPT_DIR/get-visible-facts.sh" "$ENTITY_IDS" 2>/dev/null)

if [ -n "$FACTS" ] && [ "$FACTS" != "null" ]; then
    echo "$FACTS" | jq -r '.[] | "- **\(.entity_name)**: \(.key) = \(.value) [\(.visibility)]"' >> "$OUTPUT_FILE" 2>/dev/null || echo "No facts available." >> "$OUTPUT_FILE"
else
    echo "No facts available." >> "$OUTPUT_FILE"
fi

echo "" >> "$OUTPUT_FILE"
echo "---" >> "$OUTPUT_FILE"
echo "*This context is filtered based on participant privacy settings.*" >> "$OUTPUT_FILE"

echo "Generated: $OUTPUT_FILE"
