#!/bin/bash
# embed-delegation-facts.sh
# Generates embeddings for delegation facts and stores them in memory_embeddings
# This makes delegation knowledge searchable via semantic recall
#
# Usage: ./scripts/embed-delegation-facts.sh

set -e

# Resolve config from same directory as this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/embedding-config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    exit 1
fi

OLLAMA_URL=$(jq -r '.base_url' "$CONFIG_FILE")
OLLAMA_MODEL=$(jq -r '.model' "$CONFIG_FILE")

# Load centralized PostgreSQL configuration
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env

echo "🧠 Embedding delegation facts for semantic recall..."
echo "   Model: $OLLAMA_MODEL @ $OLLAMA_URL"

# Get all delegation facts that aren't already embedded
QUERY="
SELECT 
    ef.id,
    ef.key,
    ef.value,
    ef.confidence,
    'entity_' || ef.entity_id || '_fact_' || ef.id as source_id
FROM entity_facts ef
LEFT JOIN memory_embeddings me ON me.source_id = 'entity_' || ef.entity_id || '_fact_' || ef.id
WHERE ef.entity_id = 1 
  AND ef.key IN ('delegates_to', 'task_delegation', 'agent_capability', 'agent_success', 'agent_failure')
  AND me.id IS NULL
ORDER BY ef.confidence DESC, ef.id;
"

# Export as pipe-delimited rows
FACTS=$(psql -t -A -F'|' -c "$QUERY" 2>/dev/null)

if [ -z "$FACTS" ]; then
    echo "✅ All delegation facts already embedded"
    exit 0
fi

COUNT=$(echo "$FACTS" | wc -l)
echo "📝 Found $COUNT new delegation facts to embed"

# Process each fact
PROCESSED=0
echo "$FACTS" | while IFS='|' read -r fact_id key value confidence source_id; do
    [ -z "$fact_id" ] && continue
    
    # Format content for embedding
    case "$key" in
        delegates_to)
            CONTENT="NOVA delegates to $value"
            ;;
        task_delegation)
            CONTENT="For tasks involving $value, NOVA delegates appropriately"
            ;;
        agent_capability)
            CONTENT="Agent capability: $value"
            ;;
        agent_success)
            CONTENT="Success: $value"
            ;;
        agent_failure)
            CONTENT="Lesson learned: $value"
            ;;
        *)
            CONTENT="$value"
            ;;
    esac
    
    # Skip empty content
    if [ -z "$CONTENT" ]; then
        echo "⚠️  Skipping fact $fact_id: empty content"
        continue
    fi
    
    # Get embedding from Ollama (local, no API key needed)
    EMBEDDING=$(curl -s --max-time 30 "${OLLAMA_URL}/api/embeddings" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"${OLLAMA_MODEL}\", \"prompt\": $(echo "$CONTENT" | jq -Rs .)}" \
        | jq -r '.embedding | @json')
    
    if [ -z "$EMBEDDING" ] || [ "$EMBEDDING" = "null" ]; then
        echo "⚠️  Failed to embed fact $fact_id: $CONTENT"
        continue
    fi
    
    # Insert into memory_embeddings
    psql -c "
        INSERT INTO memory_embeddings (source_type, source_id, content, embedding, confidence)
        VALUES (
            'entity_fact',
            '$source_id',
            \$\$${CONTENT}\$\$,
            '$EMBEDDING'::vector,
            $confidence
        )
        ON CONFLICT (source_id) DO UPDATE SET
            content = EXCLUDED.content,
            embedding = EXCLUDED.embedding,
            updated_at = NOW();
    " 2>/dev/null
    
    PROCESSED=$((PROCESSED + 1))
    echo "✅ [$PROCESSED/$COUNT] Embedded: $CONTENT"
done

echo ""
echo "🎯 Embedding complete!"
echo ""
echo "Test with:"
echo "  python3 ~/.openclaw/scripts/proactive-recall.py 'help me debug this code'"
echo "  python3 ~/.openclaw/scripts/proactive-recall.py 'commit these changes'"
