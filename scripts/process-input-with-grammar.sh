#!/bin/bash
# process-input-with-grammar.sh - Memory extraction with grammar parser pre-processing
# Tries grammar parser first, falls back to LLM if confidence is low

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load OpenClaw environment (API keys from openclaw.json)
ENV_LOADER="${HOME}/.openclaw/lib/env-loader.sh"
[ -f "$ENV_LOADER" ] && source "$ENV_LOADER" && load_openclaw_env

# Load centralized PostgreSQL configuration
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env

# Get input
if [ -n "$1" ]; then
    INPUT="$1"
else
    INPUT=$(cat)
fi

if [ -z "$INPUT" ]; then
    echo "Usage: process-input-with-grammar.sh <text>" >&2
    echo "   or: echo 'text' | process-input-with-grammar.sh" >&2
    exit 1
fi

# Logging
echo "=== Memory extraction with grammar parser ===" >&2
echo "Input: ${INPUT:0:100}..." >&2
echo "" >&2


# Metrics tracking function
log_metric() {
    local method="$1"
    local num_relations="$2"
    local avg_confidence="$3"
    local processing_time="$4"
    
    psql -c "
        CREATE TABLE IF NOT EXISTS extraction_metrics (
            id SERIAL PRIMARY KEY,
            timestamp TIMESTAMPTZ DEFAULT NOW(),
            method TEXT,
            num_relations INTEGER,
            avg_confidence REAL,
            processing_time_ms INTEGER
        );
        
        INSERT INTO extraction_metrics (method, num_relations, avg_confidence, processing_time_ms)
        VALUES ('$method', $num_relations, $avg_confidence, $processing_time);
    " >/dev/null 2>&1
}

# ============================================================================
# STAGE 1: Grammar-Based Extraction
# ============================================================================

echo "=== Stage 1: Grammar parser ===" >&2
START_TIME=$(date +%s%3N)

# Run grammar parser (using wrapper script with venv)
GRAMMAR_OUTPUT=$("$PROJECT_ROOT/grammar_parser/run_extract.sh" "$INPUT" 2>&1)
GRAMMAR_EXIT=$?

END_TIME=$(date +%s%3N)
PROCESSING_TIME=$((END_TIME - START_TIME))

if [ $GRAMMAR_EXIT -eq 0 ] && [ -n "$GRAMMAR_OUTPUT" ] && [ "$GRAMMAR_OUTPUT" != "[]" ]; then
    echo "Grammar parser extracted relations" >&2
    echo "$GRAMMAR_OUTPUT" | jq -C '.' >&2 2>/dev/null || echo "$GRAMMAR_OUTPUT" >&2
    echo "" >&2
    
    # Calculate average confidence
    AVG_CONFIDENCE=$(echo "$GRAMMAR_OUTPUT" | jq '[.[] | .confidence] | if length > 0 then (add / length) else 0 end' 2>/dev/null)
    NUM_RELATIONS=$(echo "$GRAMMAR_OUTPUT" | jq 'length' 2>/dev/null)
    
    if [ -z "$AVG_CONFIDENCE" ] || [ "$AVG_CONFIDENCE" = "null" ]; then
        AVG_CONFIDENCE="0"
    fi
    
    if [ -z "$NUM_RELATIONS" ] || [ "$NUM_RELATIONS" = "null" ]; then
        NUM_RELATIONS="0"
    fi
    
    echo "Average confidence: $AVG_CONFIDENCE" >&2
    echo "Number of relations: $NUM_RELATIONS" >&2
    echo "" >&2
    
    # Check confidence threshold
    CONFIDENCE_CHECK=$(echo "$AVG_CONFIDENCE >= 0.75" | bc -l 2>/dev/null)
    
    if [ "$CONFIDENCE_CHECK" = "1" ] && [ "$NUM_RELATIONS" -gt 0 ]; then
        echo "✓ High confidence (≥0.75) - storing grammar results and SKIPPING LLM" >&2
        echo "" >&2
        
        # Store relations
        echo "=== Storing grammar relations ===" >&2
        echo "$GRAMMAR_OUTPUT" | "$PROJECT_ROOT/grammar_parser/run_store.sh"
        STORE_EXIT=$?
        
        # Log metrics
        log_metric "grammar" "$NUM_RELATIONS" "$AVG_CONFIDENCE" "$PROCESSING_TIME"
        
        if [ $STORE_EXIT -eq 0 ]; then
            echo "" >&2
            echo "✓ Grammar extraction complete - LLM call avoided!" >&2
            echo "  Cost saved: ~\$0.01-0.02" >&2
            exit 0
        else
            echo "⚠ Grammar storage failed, falling back to LLM" >&2
        fi
    else
        echo "⚠ Low confidence (<0.75) or no relations - falling back to LLM" >&2
        echo "" >&2
        
        # Still store grammar results if any (they might be useful)
        if [ "$NUM_RELATIONS" -gt 0 ]; then
            echo "=== Storing low-confidence grammar relations ===" >&2
            echo "$GRAMMAR_OUTPUT" | "$PROJECT_ROOT/grammar_parser/run_store.sh" 2>&1 | head -5
            echo "" >&2
        fi
        
        # Log metrics
        log_metric "grammar_low_conf" "$NUM_RELATIONS" "$AVG_CONFIDENCE" "$PROCESSING_TIME"
    fi
else
    echo "⚠ Grammar parser failed or returned no results" >&2
    if [ -n "$GRAMMAR_OUTPUT" ]; then
        echo "Grammar output: $GRAMMAR_OUTPUT" >&2
    fi
    echo "" >&2
    
    # Log metrics
    log_metric "grammar_failed" 0 0 "$PROCESSING_TIME"
fi

# ============================================================================
# STAGE 2: LLM Fallback
# ============================================================================

echo "=== Stage 2: LLM extraction (fallback) ===" >&2
START_TIME=$(date +%s%3N)

EXTRACTED=$("$SCRIPT_DIR/extract-memories.sh" "$INPUT")
LLM_EXIT=$?

END_TIME=$(date +%s%3N)
LLM_TIME=$((END_TIME - START_TIME))

# Check if extraction succeeded
if [ $LLM_EXIT -eq 0 ] && echo "$EXTRACTED" | jq . >/dev/null 2>&1; then
    echo "=== LLM extracted data ===" >&2
    echo "$EXTRACTED" | jq -C . >&2
    echo "" >&2
    
    # Count LLM relations
    LLM_FACTS=$(echo "$EXTRACTED" | jq '[.facts // [], .opinions // [], .preferences // []] | length' 2>/dev/null || echo 0)
    
    # Store in database
    echo "=== Storing LLM memories ===" >&2
    echo "$EXTRACTED" | "$SCRIPT_DIR/store-memories.sh"
    
    # Log metrics
    log_metric "llm_fallback" "$LLM_FACTS" 1.0 "$LLM_TIME"
    
    # Output the JSON for potential further processing
    echo "$EXTRACTED"
else
    echo "Error: LLM extraction failed" >&2
    echo "$EXTRACTED" >&2
    
    # Log metrics
    log_metric "llm_failed" 0 0 "$LLM_TIME"
    
    exit 1
fi
