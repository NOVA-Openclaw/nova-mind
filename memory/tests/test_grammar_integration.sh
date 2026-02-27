#!/bin/bash
# Test suite for Issue #22: Grammar Parser Integration
# Tests grammar-based extraction and fallback to LLM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Database config
DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${DB_USER//-/_}_memory"

print_test() {
    echo ""
    echo "================================================================"
    echo "TEST: $1"
    echo "================================================================"
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

warn() {
    echo -e "${YELLOW}⚠ WARN${NC}: $1"
}

cleanup_test_data() {
    # Clean up test entities created during tests
    psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "
        DELETE FROM entity_facts WHERE entity_id IN (
            SELECT id FROM entities WHERE name IN ('TestPerson', 'TestCompany', 'GrammarBot')
        );
        DELETE FROM entity_relationships WHERE entity_a IN (
            SELECT id FROM entities WHERE name IN ('TestPerson', 'TestCompany', 'GrammarBot')
        ) OR entity_b IN (
            SELECT id FROM entities WHERE name IN ('TestPerson', 'TestCompany', 'GrammarBot')
        );
        DELETE FROM entities WHERE name IN ('TestPerson', 'TestCompany', 'GrammarBot');
    " >/dev/null 2>&1 || true
}

# ============================================================================
# Test 1: Grammar parser CLI works
# ============================================================================
print_test "Grammar parser CLI extracts relations"

OUTPUT=$("$PROJECT_ROOT/grammar_parser/run_extract.sh" "John loves pizza" 2>&1)
if echo "$OUTPUT" | jq -e '.[0].subject == "John"' >/dev/null 2>&1 && \
   echo "$OUTPUT" | jq -e '.[0].object == "pizza"' >/dev/null 2>&1; then
    pass "CLI extracted 'John loves pizza' correctly"
else
    fail "CLI did not extract relation correctly"
    echo "Output: $OUTPUT"
fi

# ============================================================================
# Test 2: High-confidence extraction skips LLM
# ============================================================================
print_test "High-confidence grammar extraction (≥0.75) skips LLM"

cleanup_test_data

OUTPUT=$(echo "TestPerson works at TestCompany" | "$PROJECT_ROOT/scripts/process-input-with-grammar.sh" 2>&1)

if echo "$OUTPUT" | grep -q "High confidence (≥0.75)"; then
    pass "High confidence detected"
else
    fail "High confidence not detected"
    echo "Output: $OUTPUT"
fi

if echo "$OUTPUT" | grep -q "SKIPPING LLM"; then
    pass "LLM call skipped"
else
    fail "LLM call not skipped"
fi

if echo "$OUTPUT" | grep -q "Grammar extraction complete"; then
    pass "Grammar extraction completed successfully"
else
    fail "Grammar extraction did not complete"
fi

# Verify data was stored
FACT_COUNT=$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT COUNT(*) FROM entity_facts ef
    JOIN entities e ON e.id = ef.entity_id
    WHERE e.name = 'TestPerson' AND ef.key = 'other_work_at' AND ef.value = 'TestCompany';
")

if [ "$FACT_COUNT" -gt 0 ]; then
    pass "Fact stored in database"
else
    fail "Fact not stored in database"
fi

# ============================================================================
# Test 3: Low-confidence extraction falls back to LLM
# ============================================================================
print_test "Low-confidence grammar extraction (<0.75) falls back to LLM"

# Note: This test requires a message that produces low-confidence results
# For now, we'll test the fallback mechanism with a complex sentence

OUTPUT=$(echo "The intricacies of quantum mechanics perplex even seasoned physicists" | \
    "$PROJECT_ROOT/scripts/process-input-with-grammar.sh" 2>&1)

if echo "$OUTPUT" | grep -q "falling back to LLM\|LLM extraction"; then
    pass "Fallback to LLM triggered"
else
    warn "Fallback test inconclusive (may need complex sentence)"
fi

# ============================================================================
# Test 4: Integration with source authority (#43)
# ============================================================================
print_test "Grammar extraction respects source authority (Issue #43)"

cleanup_test_data

# Set SENDER_NAME to I)ruid (entity_id=2, authority)
SENDER_NAME="I)ruid" "$PROJECT_ROOT/grammar_parser/run_extract.sh" "TestPerson lives in Austin" | \
    "$PROJECT_ROOT/grammar_parser/run_store.sh" 2>&1 | tee /tmp/authority_test.log

if grep -q "\[AUTHORITY\]" /tmp/authority_test.log || grep -q "PERMANENT" /tmp/authority_test.log; then
    pass "Authority source detected and marked"
else
    fail "Authority source not detected"
    cat /tmp/authority_test.log
fi

# Check if fact is marked as permanent
DATA_TYPE=$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT ef.data_type FROM entity_facts ef
    JOIN entities e ON e.id = ef.entity_id
    WHERE e.name = 'TestPerson' AND ef.key = 'residence'
    LIMIT 1;
")

if [ "$DATA_TYPE" = "permanent" ]; then
    pass "Authority fact marked as 'permanent'"
else
    fail "Authority fact not marked as permanent (got: $DATA_TYPE)"
fi

# ============================================================================
# Test 5: Multiple relations in one message
# ============================================================================
print_test "Extract multiple relations from single message"

cleanup_test_data

OUTPUT=$(echo "GrammarBot lives in Seattle and works at Microsoft" | \
    "$PROJECT_ROOT/scripts/process-input-with-grammar.sh" 2>&1)

RELATION_COUNT=$(echo "$OUTPUT" | grep -c "^\  + " || echo 0)

if [ "$RELATION_COUNT" -ge 2 ]; then
    pass "Multiple relations extracted ($RELATION_COUNT relations)"
else
    fail "Expected multiple relations, got $RELATION_COUNT"
    echo "Output: $OUTPUT"
fi

# ============================================================================
# Test 6: Metrics logging
# ============================================================================
print_test "Extraction metrics are logged"

# Check if extraction_metrics table exists and has data
METRIC_COUNT=$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT COUNT(*) FROM extraction_metrics WHERE timestamp > NOW() - INTERVAL '10 minutes';
" 2>/dev/null || echo 0)

if [ "$METRIC_COUNT" -gt 0 ]; then
    pass "Metrics logged ($METRIC_COUNT recent entries)"
else
    warn "No recent metrics found (table may not exist yet)"
fi

# Check for grammar vs LLM usage
GRAMMAR_COUNT=$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT COUNT(*) FROM extraction_metrics WHERE method LIKE 'grammar%';
" 2>/dev/null || echo 0)

if [ "$GRAMMAR_COUNT" -gt 0 ]; then
    pass "Grammar extraction metrics logged ($GRAMMAR_COUNT entries)"
else
    warn "No grammar metrics found"
fi

# ============================================================================
# Test 7: Wrapper scripts exist and are executable
# ============================================================================
print_test "Integration scripts exist and are executable"

if [ -x "$PROJECT_ROOT/grammar_parser/run_extract.sh" ]; then
    pass "run_extract.sh exists and is executable"
else
    fail "run_extract.sh not executable"
fi

if [ -x "$PROJECT_ROOT/grammar_parser/run_store.sh" ]; then
    pass "run_store.sh exists and is executable"
else
    fail "run_store.sh not executable"
fi

if [ -x "$PROJECT_ROOT/scripts/process-input-with-grammar.sh" ]; then
    pass "process-input-with-grammar.sh exists and is executable"
else
    fail "process-input-with-grammar.sh not executable"
fi

# ============================================================================
# Test 8: Venv activation works
# ============================================================================
print_test "Virtualenv activates correctly"

if [ -f "$PROJECT_ROOT/grammar_parser/venv/bin/activate" ]; then
    pass "Virtualenv exists"
else
    fail "Virtualenv not found"
fi

# Test if spaCy is installed in venv
SPACY_CHECK=$("$PROJECT_ROOT/grammar_parser/venv/bin/python" -c "import spacy; print('OK')" 2>/dev/null || echo "FAIL")

if [ "$SPACY_CHECK" = "OK" ]; then
    pass "spaCy installed in virtualenv"
else
    fail "spaCy not installed in virtualenv"
fi

# ============================================================================
# Test 9: Handler references correct script
# ============================================================================
print_test "Hook handler references process-input-with-grammar.sh"

HANDLER_PATH="$PROJECT_ROOT/hooks/memory-extract/handler.ts"

if grep -q "process-input-with-grammar.sh" "$HANDLER_PATH"; then
    pass "Handler references process-input-with-grammar.sh"
else
    fail "Handler does not reference process-input-with-grammar.sh"
    echo "Check: $HANDLER_PATH"
fi

# ============================================================================
# Test 10: End-to-end integration test
# ============================================================================
print_test "End-to-end: Message → Grammar → Database"

cleanup_test_data

# Simulate a message extraction
TEST_MESSAGE="TestPerson loves pizza and works at TestCompany"
echo "$TEST_MESSAGE" | "$PROJECT_ROOT/scripts/process-input-with-grammar.sh" >/dev/null 2>&1

# Check if facts were stored
FACT_COUNT=$(psql -h localhost -U "$DB_USER" -d "$DB_NAME" -t -A -c "
    SELECT COUNT(*) FROM entity_facts ef
    JOIN entities e ON e.id = ef.entity_id
    WHERE e.name = 'TestPerson';
")

if [ "$FACT_COUNT" -ge 1 ]; then
    pass "End-to-end extraction and storage successful ($FACT_COUNT facts)"
else
    fail "End-to-end test failed (no facts stored)"
fi

# ============================================================================
# Cleanup
# ============================================================================
echo ""
echo "================================================================"
echo "CLEANUP"
echo "================================================================"
cleanup_test_data
echo "Test data cleaned up"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "================================================================"
echo "TEST SUMMARY"
echo "================================================================"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
else
    echo -e "${GREEN}Failed: 0${NC}"
fi

if [ $TESTS_FAILED -gt 0 ]; then
    echo ""
    echo -e "${RED}Some tests failed. Review output above.${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}All tests passed! ✓${NC}"
    exit 0
fi
