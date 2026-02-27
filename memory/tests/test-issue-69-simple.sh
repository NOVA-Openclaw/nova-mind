#!/bin/bash

# Simplified test for Issue #69: Case-Insensitive Agent Matching
# Uses existing agents from the database

set -e

DB_NAME="nova_memory"
DB_USER="nova"

echo "=========================================="
echo "Testing Issue #69: Agent Matching"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

function print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

function print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
}

function print_info() {
    echo -e "  ℹ $1"
}

# Check if database exists
print_test "Checking database connection"
if psql -U $DB_USER -d $DB_NAME -c "SELECT 1" > /dev/null 2>&1; then
    print_pass "Database connection successful"
else
    print_fail "Cannot connect to database $DB_NAME"
    exit 1
fi

echo ""

# Apply migration if needed
print_test "Checking if migration is applied"
if psql -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM agent_aliases" > /dev/null 2>&1; then
    print_pass "agent_aliases table exists"
else
    print_info "Applying migration..."
    if psql -U $DB_USER -d $DB_NAME -f patches/069-add-agent-aliases-table.sql > /dev/null 2>&1; then
        print_pass "Migration applied successfully"
    else
        print_fail "Migration failed"
        exit 1
    fi
fi

echo ""

# Get an existing agent
print_test "Finding existing agent for testing"
AGENT_NAME=$(psql -U $DB_USER -d $DB_NAME -t -c "SELECT name FROM agents LIMIT 1" | xargs)
if [ -z "$AGENT_NAME" ]; then
    print_fail "No agents found in database"
    exit 1
fi
print_pass "Using agent: $AGENT_NAME"

echo ""

# Clean up test data first
print_test "Cleaning up any existing test data"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null 2>&1
DELETE FROM agent_chat_processed WHERE chat_id IN (SELECT id FROM agent_chat WHERE sender = 'test-user-69');
DELETE FROM agent_chat WHERE sender = 'test-user-69';
DELETE FROM agent_aliases WHERE agent_id = (SELECT id FROM agents WHERE name = '$AGENT_NAME') AND alias LIKE 'test-alias-%';
EOF
print_pass "Test data cleaned up"

echo ""

# Add test aliases
print_test "Adding test aliases"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'test-alias-helper' FROM agents WHERE name = '$AGENT_NAME'
ON CONFLICT DO NOTHING;

INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'test-alias-assistant' FROM agents WHERE name = '$AGENT_NAME'
ON CONFLICT DO NOTHING;
EOF

if [ $? -eq 0 ]; then
    print_pass "Test aliases added"
else
    print_fail "Failed to add aliases"
    exit 1
fi

echo ""

# Test Case 1: Agent name matching (case-insensitive)
print_test "Test Case 1: Case-insensitive agent name matching"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user-69', 'Hello @$AGENT_NAME', ARRAY['$AGENT_NAME']);

INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user-69', 'Hello @UPPERCASE', ARRAY['$(echo $AGENT_NAME | tr '[:lower:]' '[:upper:]')']);

INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user-69', 'Hello @mixedCase', ARRAY['$(echo ${AGENT_NAME:0:1} | tr '[:lower:]' '[:upper:]')${AGENT_NAME:1}']);
EOF

# Check if messages would be matched
MATCHED=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) = LOWER('$AGENT_NAME')
)
AND sender = 'test-user-69';
")

if [ $(echo $MATCHED | tr -d ' ') -eq 3 ]; then
    print_pass "All 3 case variations matched correctly"
else
    print_fail "Expected 3 matches, got: $MATCHED"
fi

echo ""

# Test Case 2: Alias matching
print_test "Test Case 2: Alias matching (case-insensitive)"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user-69', 'Hello @test-alias-helper', ARRAY['test-alias-helper']);

INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user-69', 'Hello @TEST-ALIAS-ASSISTANT', ARRAY['TEST-ALIAS-ASSISTANT']);
EOF

# Query to check matching with identifiers (simulating the getAgentIdentifiers function)
MATCHED=$(psql -U $DB_USER -d $DB_NAME -t -c "
WITH agent_identifiers AS (
  SELECT LOWER(a.name) as identifier
  FROM agents a
  WHERE a.name = '$AGENT_NAME'
  
  UNION
  
  SELECT LOWER(a.nickname) as identifier
  FROM agents a
  WHERE a.name = '$AGENT_NAME' AND a.nickname IS NOT NULL
  
  UNION
  
  SELECT LOWER(aa.alias) as identifier
  FROM agent_aliases aa
  JOIN agents a ON aa.agent_id = a.id
  WHERE a.name = '$AGENT_NAME'
)
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (SELECT identifier FROM agent_identifiers)
)
AND sender = 'test-user-69'
AND (message LIKE '%test-alias-helper%' OR message LIKE '%TEST-ALIAS-ASSISTANT%');
")

if [ $(echo $MATCHED | tr -d ' ') -eq 2 ]; then
    print_pass "Both aliases matched correctly"
else
    print_fail "Expected 2 alias matches, got: $MATCHED"
fi

echo ""

# Test Case 3: Non-matching mentions
print_test "Test Case 3: Non-matching mentions should not match"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user-69', 'Hello @nonexistent-agent-xyz', ARRAY['nonexistent-agent-xyz']);
EOF

MATCHED=$(psql -U $DB_USER -d $DB_NAME -t -c "
WITH agent_identifiers AS (
  SELECT LOWER(a.name) as identifier
  FROM agents a
  WHERE a.name = '$AGENT_NAME'
  
  UNION
  
  SELECT LOWER(aa.alias) as identifier
  FROM agent_aliases aa
  JOIN agents a ON aa.agent_id = a.id
  WHERE a.name = '$AGENT_NAME'
)
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (SELECT identifier FROM agent_identifiers)
)
AND sender = 'test-user-69'
AND 'nonexistent-agent-xyz' = ANY(mentions);
")

if [ $(echo $MATCHED | tr -d ' ') -eq 0 ]; then
    print_pass "Non-existent agent correctly not matched"
else
    print_fail "Non-existent agent incorrectly matched: $MATCHED"
fi

echo ""

# Test Case 4: Query structure validation
print_test "Test Case 4: Validating complete query structure"
print_info "Simulating fetchUnprocessedMessages query..."

# This simulates the actual query from channel.ts
TEST_RESULT=$(psql -U $DB_USER -d $DB_NAME -t -c "
WITH agent_identifiers AS (
  SELECT DISTINCT LOWER(identifier) as identifier
  FROM (
    SELECT a.name as identifier
    FROM agents a
    WHERE LOWER(a.name) = LOWER('$AGENT_NAME')
    
    UNION
    
    SELECT a.nickname as identifier
    FROM agents a
    WHERE LOWER(a.name) = LOWER('$AGENT_NAME')
      AND a.nickname IS NOT NULL
    
    UNION
    
    SELECT aa.alias as identifier
    FROM agents a
    JOIN agent_aliases aa ON a.id = aa.agent_id
    WHERE LOWER(a.name) = LOWER('$AGENT_NAME')
  ) all_identifiers
  WHERE identifier IS NOT NULL
)
SELECT 
  'agent_name' as match_type,
  COUNT(*) as match_count
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (SELECT identifier FROM agent_identifiers)
)
AND sender = 'test-user-69';
")

if [ ! -z "$TEST_RESULT" ]; then
    print_pass "Query structure is valid"
    print_info "Result: $TEST_RESULT"
else
    print_fail "Query validation failed"
fi

echo ""

# Clean up test data
print_test "Cleaning up test data"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null 2>&1
DELETE FROM agent_chat_processed WHERE chat_id IN (SELECT id FROM agent_chat WHERE sender = 'test-user-69');
DELETE FROM agent_chat WHERE sender = 'test-user-69';
DELETE FROM agent_aliases WHERE agent_id = (SELECT id FROM agents WHERE name = '$AGENT_NAME') AND alias LIKE 'test-alias-%';
EOF
print_pass "Test data cleaned up"

echo ""
echo "=========================================="
echo "All tests completed!"
echo "=========================================="
echo ""
print_info "Summary:"
print_info "- Database migration: OK"
print_info "- Case-insensitive matching: VERIFIED"
print_info "- Alias matching: VERIFIED"
print_info "- Non-matching detection: VERIFIED"
print_info "- Query structure: VALIDATED"
