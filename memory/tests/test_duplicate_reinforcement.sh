#!/bin/bash
# Test duplicate fact reinforcement (Issue #44)
# Verifies that vote_count increments and last_confirmed updates on duplicate facts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${DB_USER//-/_}_memory"

echo "========================================="
echo "Testing Duplicate Fact Reinforcement (Issue #44)"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run SQL
run_sql() {
    psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "$1" 2>/dev/null
}

# Function to test result
test_result() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    if [ "$expected" == "$actual" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: $expected"
        echo "  Got: $actual"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Setup: Create test entity
echo "Setup: Creating test entity..."
run_sql "DELETE FROM entities WHERE name = 'TestPerson44';"
run_sql "INSERT INTO entities (name, type) VALUES ('TestPerson44', 'person');"

TEST_ENTITY_ID=$(run_sql "SELECT id FROM entities WHERE name = 'TestPerson44';")
echo "Test entity ID: $TEST_ENTITY_ID"
echo ""

# ======================
# Test 1: store-memories.sh - Initial fact insertion
# ======================
echo "Test 1: Initial fact insertion via store-memories.sh"
JSON_FACT='{"facts":[{"subject":"TestPerson44","predicate":"favorite_color","value":"blue","source_person":"test-script"}]}'
echo "$JSON_FACT" | ./scripts/store-memories.sh > /tmp/test44_output1.txt 2>&1

INITIAL_VOTE_COUNT=$(run_sql "SELECT vote_count FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'favorite_color';")
INITIAL_CONFIRMED=$(run_sql "SELECT last_confirmed FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'favorite_color';")

test_result "Initial fact created" "1" "$INITIAL_VOTE_COUNT"

# ======================
# Test 2: store-memories.sh - Duplicate fact reinforcement
# ======================
echo ""
echo "Test 2: Duplicate fact reinforcement via store-memories.sh"
sleep 2  # Ensure timestamp difference
echo "$JSON_FACT" | ./scripts/store-memories.sh > /tmp/test44_output2.txt 2>&1

SECOND_VOTE_COUNT=$(run_sql "SELECT vote_count FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'favorite_color';")
SECOND_CONFIRMED=$(run_sql "SELECT last_confirmed FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'favorite_color';")

test_result "Vote count incremented" "2" "$SECOND_VOTE_COUNT"

if [[ "$SECOND_CONFIRMED" > "$INITIAL_CONFIRMED" ]]; then
    echo -e "${GREEN}✓${NC} last_confirmed timestamp updated"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} last_confirmed timestamp NOT updated"
    echo "  Initial: $INITIAL_CONFIRMED"
    echo "  Second: $SECOND_CONFIRMED"
    ((TESTS_FAILED++))
fi

# Check log message
if grep -q "✓ Fact reinforced.*vote_count++" /tmp/test44_output2.txt; then
    echo -e "${GREEN}✓${NC} Correct log message (reinforced vs created)"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Missing or incorrect log message"
    cat /tmp/test44_output2.txt
    ((TESTS_FAILED++))
fi

# ======================
# Test 3: store-memories.sh - Opinion reinforcement
# ======================
echo ""
echo "Test 3: Opinion reinforcement via store-memories.sh"
run_sql "DELETE FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'opinion_pizza';"

JSON_OPINION='{"opinions":[{"holder":"TestPerson44","subject":"pizza","opinion":"delicious","source_person":"test-script"}]}'
echo "$JSON_OPINION" | ./scripts/store-memories.sh > /tmp/test44_output3a.txt 2>&1
sleep 1
echo "$JSON_OPINION" | ./scripts/store-memories.sh > /tmp/test44_output3b.txt 2>&1

OPINION_VOTE_COUNT=$(run_sql "SELECT vote_count FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'opinion_pizza';")

test_result "Opinion vote_count = 2 after reinforcement" "2" "$OPINION_VOTE_COUNT"

if grep -q "✓ Opinion reinforced.*vote_count++" /tmp/test44_output3b.txt; then
    echo -e "${GREEN}✓${NC} Opinion reinforcement logged correctly"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Opinion reinforcement log missing"
    ((TESTS_FAILED++))
fi

# ======================
# Test 4: store-memories.sh - Preference reinforcement
# ======================
echo ""
echo "Test 4: Preference reinforcement via store-memories.sh"
run_sql "DELETE FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'preference_food';"

JSON_PREF='{"preferences":[{"person":"TestPerson44","category":"food","preference":"sushi","source_person":"test-script"}]}'
echo "$JSON_PREF" | ./scripts/store-memories.sh > /tmp/test44_output4a.txt 2>&1
sleep 1
echo "$JSON_PREF" | ./scripts/store-memories.sh > /tmp/test44_output4b.txt 2>&1

PREF_VOTE_COUNT=$(run_sql "SELECT vote_count FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'preference_food';")

test_result "Preference vote_count = 2 after reinforcement" "2" "$PREF_VOTE_COUNT"

if grep -q "✓ Preference reinforced.*vote_count++" /tmp/test44_output4b.txt; then
    echo -e "${GREEN}✓${NC} Preference reinforcement logged correctly"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Preference reinforcement log missing"
    ((TESTS_FAILED++))
fi

# ======================
# Test 5: store_relations.py - Attribute reinforcement
# ======================
echo ""
echo "Test 5: Attribute reinforcement via store_relations.py"
run_sql "DELETE FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'age';"

JSON_REL='[{"relation_type":"attribute","subject":"TestPerson44","predicate":"age","object":"30","confidence":0.9}]'
echo "$JSON_REL" | SENDER_NAME="test-script" ./grammar_parser/store_relations.py > /tmp/test44_output5a.txt 2>&1
sleep 1
echo "$JSON_REL" | SENDER_NAME="test-script" ./grammar_parser/store_relations.py > /tmp/test44_output5b.txt 2>&1

ATTR_VOTE_COUNT=$(run_sql "SELECT vote_count FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'age';")

test_result "Attribute vote_count = 2 after reinforcement" "2" "$ATTR_VOTE_COUNT"

if grep -q "✓.*confirmed.*vote_count++" /tmp/test44_output5b.txt; then
    echo -e "${GREEN}✓${NC} Attribute reinforcement logged correctly"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗${NC} Attribute reinforcement log missing"
    cat /tmp/test44_output5b.txt
    ((TESTS_FAILED++))
fi

# ======================
# Test 6: confirmation_count also increments
# ======================
echo ""
echo "Test 6: confirmation_count increments on reinforcement"

CONF_COUNT=$(run_sql "SELECT confirmation_count FROM entity_facts WHERE entity_id = $TEST_ENTITY_ID AND key = 'favorite_color';")

test_result "confirmation_count = 2" "2" "$CONF_COUNT"

# ======================
# Cleanup
# ======================
echo ""
echo "Cleanup: Removing test entity..."
run_sql "DELETE FROM entities WHERE name = 'TestPerson44';"

# ======================
# Summary
# ======================
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
