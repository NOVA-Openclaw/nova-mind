#!/bin/bash
# test-delegation-memory.sh
# Test the delegation memory system end-to-end
#
# Usage: ./scripts/test-delegation-memory.sh

set -e

# Load OpenClaw environment (API keys from openclaw.json)
ENV_LOADER="${HOME}/.openclaw/lib/env-loader.sh"
[ -f "$ENV_LOADER" ] && source "$ENV_LOADER" && load_openclaw_env

# Load centralized PostgreSQL configuration
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env


echo "🧪 Testing Delegation Memory System"
echo "===================================="
echo ""

# Test 1: Check if delegation facts exist
echo "📊 Test 1: Check delegation facts in database"
FACT_COUNT=$(psql -t -A -c "SELECT COUNT(*) FROM entity_facts WHERE entity_id = 1 AND key IN ('delegates_to', 'task_delegation', 'agent_capability');" 2>/dev/null)
echo "   Found $FACT_COUNT delegation facts"
if [ "$FACT_COUNT" -lt 1 ]; then
    echo "   ⚠️  No delegation facts found. Run: psql -f scripts/seed-delegation-knowledge.sql"
else
    echo "   ✅ Delegation facts exist"
fi
echo ""

# Test 2: Check embeddings
echo "📊 Test 2: Check delegation embeddings"
EMBED_COUNT=$(psql -t -A -c "SELECT COUNT(*) FROM memory_embeddings WHERE source_type = 'entity_fact' AND source_id LIKE 'entity_1_fact_%';" 2>/dev/null)
echo "   Found $EMBED_COUNT embeddings for NOVA's facts"
if [ "$EMBED_COUNT" -lt 1 ]; then
    echo "   ⚠️  No embeddings found. Run: ./scripts/embed-delegation-facts.sh"
else
    echo "   ✅ Embeddings exist"
fi
echo ""

# Test 3: Sample delegation facts
echo "📊 Test 3: Sample delegation knowledge"
echo "   Delegates to:"
psql -t -c "
    SELECT '     • ' || value 
    FROM entity_facts 
    WHERE entity_id = 1 AND key = 'delegates_to' 
    ORDER BY value 
    LIMIT 5;
" 2>/dev/null
echo ""

# Test 4: Semantic search (if proactive-recall.py is available)
if [ -f "$HOME/.openclaw/scripts/proactive-recall.py" ]; then
    echo "📊 Test 4: Semantic search for delegation"
    
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "   ⚠️  OPENAI_API_KEY not set in environment, skipping semantic search test"
        echo "      Set OPENAI_API_KEY environment variable to run this test"
    else
        export OPENAI_API_KEY
        echo "   Query: 'help me debug this Python code'"
        RESULT=$(python3 "$HOME/.openclaw/scripts/proactive-recall.py" "help me debug this Python code" --max-tokens 300 2>/dev/null || echo "failed")
        if [ "$RESULT" = "failed" ]; then
            echo "   ⚠️  Semantic search failed"
        else
            echo "   Results:"
            echo "$RESULT" | jq -r '.memories[]?.content' 2>/dev/null | head -3 | sed 's/^/     • /'
            echo "   ✅ Semantic search working"
        fi
    fi
else
    echo "📊 Test 4: Semantic search - SKIPPED (proactive-recall.py not found)"
fi
echo ""

# Test 5: Memory extraction test
echo "📊 Test 5: Memory extraction with delegation"
if [ -f "$HOME/.openclaw/scripts/extract-memories.sh" ]; then
    export SENDER_NAME="I)ruid"
    export SENDER_ID=""
    export IS_GROUP="false"
    
    TEST_CONVO="[USER] Can you help me fix this bug?
[CURRENT NOVA MESSAGE] Let me get Coder to help with that code issue."
    
    EXTRACTED=$(echo "$TEST_CONVO" | "$HOME/.openclaw/scripts/extract-memories.sh" 2>/dev/null || echo "{}")
    
    if echo "$EXTRACTED" | jq -e '.facts[]? | select(.predicate == "delegates_to")' > /dev/null 2>&1; then
        echo "   ✅ Extraction recognizes delegation patterns"
        echo "   Extracted:"
        echo "$EXTRACTED" | jq -r '.facts[]? | select(.predicate == "delegates_to") | "     • " + .predicate + ": " + .value' 2>/dev/null
    else
        echo "   ℹ️  No delegation facts extracted from test (this is OK if prompt didn't strongly indicate delegation)"
    fi
else
    echo "   ⚠️  extract-memories.sh not found"
fi
echo ""

# Summary
echo "===================================="
echo "📋 Summary"
echo "===================================="
echo "Database facts:   $FACT_COUNT"
echo "Embeddings:       $EMBED_COUNT"
echo ""
if [ "$FACT_COUNT" -gt 0 ] && [ "$EMBED_COUNT" -gt 0 ]; then
    echo "✅ Delegation memory system is operational!"
    echo ""
    echo "Try queries like:"
    echo "  • 'help me debug this code' → should surface Coder"
    echo "  • 'commit these changes' → should surface Gidget"
    echo "  • 'research this topic' → should surface Scout"
else
    echo "⚠️  System needs setup. Run:"
    echo "  1. psql -f scripts/seed-delegation-knowledge.sql"
    echo "  2. ./scripts/embed-delegation-facts.sh"
fi
