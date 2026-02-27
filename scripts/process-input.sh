#!/bin/bash
# process-input.sh - Main entry point for memory extraction pipeline
# Extracts entities/facts/opinions from text and stores in database

# Load OpenClaw environment (API keys from openclaw.json)
ENV_LOADER="${HOME}/.openclaw/lib/env-loader.sh"
[ -f "$ENV_LOADER" ] && source "$ENV_LOADER" && load_openclaw_env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get input
if [ -n "$1" ]; then
    INPUT="$1"
else
    INPUT=$(cat)
fi

if [ -z "$INPUT" ]; then
    echo "Usage: process-input.sh <text>" >&2
    echo "   or: echo 'text' | process-input.sh" >&2
    exit 1
fi

echo "=== Extracting memories from input ===" >&2
echo "Input: ${INPUT:0:100}..." >&2
echo "" >&2

# Extract structured data
EXTRACTED=$("$SCRIPT_DIR/extract-memories.sh" "$INPUT")

# Check if extraction succeeded
if echo "$EXTRACTED" | jq . >/dev/null 2>&1; then
    echo "=== Extracted data ===" >&2
    echo "$EXTRACTED" | jq -C . >&2
    echo "" >&2
    
    # Store in database
    echo "=== Storing memories ===" >&2
    echo "$EXTRACTED" | "$SCRIPT_DIR/store-memories.sh"
    
    # Output the JSON for potential further processing
    echo "$EXTRACTED"
else
    echo "Error: Failed to extract valid JSON" >&2
    echo "$EXTRACTED" >&2
    exit 1
fi
