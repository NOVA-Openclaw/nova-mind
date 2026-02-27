#!/bin/bash
# Test script for source authority feature (Issue #43)
# Tests I)ruid's authority over facts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Database configuration
DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${DB_USER//-/_}_memory"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "Testing Source Authority Feature (#43)"
echo "========================================"
echo ""

# Helper function to run SQL and get result
run_sql() {
    psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -A -c "$1" 2>/dev/null
}

# Helper function to extract fact value
get_fact_value() {
    local entity="$1"
    local key="$2"
    run_sql "
        SELECT ef.value, ef.data_type, ef.confidence, ef.source_entity_id, ef.vote_count
        FROM entity_facts ef
        JOIN entities e ON e.id = ef.entity_id
        WHERE LOWER(e.name) = LOWER('$entity') AND LOWER(ef.key) = LOWER('$key')
        LIMIT 1;
    "
}

# Test 1: Authority fact insertion (new fact)
echo "Test 1: Authority entity (I)ruid) states a new fact"
echo "-----------------------------------------------------"

# Create test JSON (I)ruid says Nova's favorite color is blue)
TEST_JSON='[{
    "relation_type": "preference",
    "subject": "Nova",
    "object": "blue",
    "predicate": "favorite_color",
    "confidence": 0.9
}]'

# Simulate I)ruid as source
export SENDER_NAME="I)ruid"
echo "$TEST_JSON" | "$PROJECT_ROOT/grammar_parser/run_store.sh" 2>&1 | grep -E "(AUTHORITY|Fact:|permanent)"

# Check database
RESULT=$(get_fact_value "Nova" "preference_favorite_color")
if echo "$RESULT" | grep -q "permanent"; then
    echo -e "${GREEN}✓ PASS: Fact marked as permanent${NC}"
else
    echo -e "${RED}✗ FAIL: Fact not marked as permanent${NC}"
    echo "  Result: $RESULT"
fi

if echo "$RESULT" | grep -q "^blue|"; then
    echo -e "${GREEN}✓ PASS: Correct value stored${NC}"
else
    echo -e "${RED}✗ FAIL: Incorrect value${NC}"
fi

echo ""

# Test 2: Authority fact confirmation (same value)
echo "Test 2: I)ruid repeats the same fact (should increment vote_count)"
echo "-------------------------------------------------------------------"

echo "$TEST_JSON" | "$PROJECT_ROOT/grammar_parser/run_store.sh" 2>&1 | grep -E "(confirmed|vote_count)"

RESULT=$(get_fact_value "Nova" "preference_favorite_color")
VOTE_COUNT=$(echo "$RESULT" | cut -d'|' -f5)

if [ "$VOTE_COUNT" -eq 2 ]; then
    echo -e "${GREEN}✓ PASS: Vote count incremented to 2${NC}"
else
    echo -e "${RED}✗ FAIL: Vote count is $VOTE_COUNT (expected 2)${NC}"
fi

echo ""

# Test 3: Authority fact override (conflicting value)
echo "Test 3: I)ruid changes his mind (blue → green)"
echo "------------------------------------------------"

# I)ruid now says favorite color is green
TEST_JSON_CONFLICT='[{
    "relation_type": "preference",
    "subject": "Nova",
    "object": "green",
    "predicate": "favorite_color",
    "confidence": 0.9
}]'

export SENDER_NAME="I)ruid"
echo "$TEST_JSON_CONFLICT" | "$PROJECT_ROOT/grammar_parser/run_store.sh" 2>&1 | grep -E "(AUTHORITY UPDATE|override)"

RESULT=$(get_fact_value "Nova" "preference_favorite_color")
if echo "$RESULT" | grep -q "^green|"; then
    echo -e "${GREEN}✓ PASS: Value updated to 'green'${NC}"
else
    echo -e "${RED}✗ FAIL: Value not updated${NC}"
    echo "  Result: $RESULT"
fi

echo ""

# Test 4: Non-authority cannot override authority fact
echo "Test 4: Non-authority user tries to override I)ruid's fact"
echo "------------------------------------------------------------"

# Someone else says favorite color is red
TEST_JSON_NON_AUTH='[{
    "relation_type": "preference",
    "subject": "Nova",
    "object": "red",
    "predicate": "favorite_color",
    "confidence": 0.95
}]'

export SENDER_NAME="RandomUser"
echo "$TEST_JSON_NON_AUTH" | "$PROJECT_ROOT/grammar_parser/run_store.sh" 2>&1 | grep -E "(rejected|authority)"

RESULT=$(get_fact_value "Nova" "preference_favorite_color")
if echo "$RESULT" | grep -q "^green|"; then
    echo -e "${GREEN}✓ PASS: Authority fact protected (still 'green')${NC}"
else
    echo -e "${RED}✗ FAIL: Authority fact was overridden!${NC}"
    echo "  Result: $RESULT"
fi

echo ""

# Test 5: Check change log
echo "Test 5: Verify change log records authority override"
echo "------------------------------------------------------"

CHANGE_LOG=$(run_sql "
    SELECT old_value, new_value, reason 
    FROM fact_change_log 
    WHERE reason = 'authority_override'
    ORDER BY id DESC
    LIMIT 1;
")

if echo "$CHANGE_LOG" | grep -q "authority_override"; then
    echo -e "${GREEN}✓ PASS: Change log recorded${NC}"
    echo "  Log entry: $CHANGE_LOG"
else
    echo -e "${YELLOW}⚠ WARNING: No change log entry found${NC}"
fi

echo ""

# Test 6: Configurable authority entity
echo "Test 6: Test configurable authority entity via AUTHORITY_ENTITY_ID"
echo "--------------------------------------------------------------------"

# Create a test entity
run_sql "INSERT INTO entities (name, type) VALUES ('TestAuthority', 'person') ON CONFLICT DO NOTHING;" >/dev/null

# Get the ID
AUTH_ID=$(run_sql "SELECT id FROM entities WHERE name = 'TestAuthority' LIMIT 1;")

# Use this entity as authority
export AUTHORITY_ENTITY_ID="$AUTH_ID"
export SENDER_NAME="TestAuthority"

TEST_JSON_CONFIG='[{
    "relation_type": "attribute",
    "subject": "TestSubject",
    "object": "test_value",
    "predicate": "test_key",
    "confidence": 0.8
}]'

# Ensure TestSubject exists
run_sql "INSERT INTO entities (name, type) VALUES ('TestSubject', 'person') ON CONFLICT DO NOTHING;" >/dev/null

echo "$TEST_JSON_CONFIG" | "$PROJECT_ROOT/grammar_parser/run_store.sh" 2>&1 | grep -E "(AUTHORITY|permanent)"

RESULT=$(get_fact_value "TestSubject" "test_key")
if echo "$RESULT" | grep -q "permanent"; then
    echo -e "${GREEN}✓ PASS: Configurable authority works${NC}"
else
    echo -e "${RED}✗ FAIL: Configurable authority not working${NC}"
    echo "  Result: $RESULT"
fi

echo ""

# Cleanup
echo "Cleaning up test data..."
run_sql "DELETE FROM entity_facts WHERE entity_id IN (SELECT id FROM entities WHERE name IN ('Nova', 'TestSubject'));" >/dev/null
run_sql "DELETE FROM entities WHERE name IN ('TestAuthority', 'TestSubject');" >/dev/null

echo ""
echo "========================================"
echo "Testing Complete"
echo "========================================"
