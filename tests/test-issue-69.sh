#!/bin/bash

# Test script for Issue #69: Case-Insensitive Agent Matching
# This script validates the agent_chat matching implementation

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
print_test "Applying migration (if not already applied)"
if psql -U $DB_USER -d $DB_NAME -f patches/069-add-agent-aliases-table.sql > /dev/null 2>&1; then
    print_pass "Migration applied successfully"
else
    print_info "Migration may already be applied (this is OK)"
fi

echo ""

# Clean up test data first
print_test "Cleaning up any existing test data"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null 2>&1
DELETE FROM agent_chat_processed WHERE chat_id IN (SELECT id FROM agent_chat WHERE sender = 'test-user');
DELETE FROM agent_chat WHERE sender = 'test-user';
DELETE FROM agent_aliases WHERE agent_id IN (SELECT id FROM agents WHERE name IN ('test-agent-1', 'test-agent-2'));
DELETE FROM agents WHERE name IN ('test-agent-1', 'test-agent-2');
EOF
print_pass "Test data cleaned up"

echo ""

# Set up test agents
print_test "Setting up test agents"
psql -U $DB_USER -d $DB_NAME << EOF
-- Test Agent 1: Config name differs from database name
INSERT INTO agents (name, description, access_method, status)
VALUES ('test-agent-1', 'Test agent for issue #69', 'openclaw', 'active')
ON CONFLICT DO NOTHING;

-- Test Agent 2: With nickname
INSERT INTO agents (name, nickname, description, access_method, status)
VALUES ('test-agent-2', 'test-bot', 'Test agent with nickname', 'openclaw', 'active')
ON CONFLICT DO NOTHING;

-- Add aliases for test-agent-1
INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'helper' FROM agents WHERE name = 'test-agent-1'
ON CONFLICT DO NOTHING;

INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'assistant' FROM agents WHERE name = 'test-agent-1'
ON CONFLICT DO NOTHING;
EOF

if [ $? -eq 0 ]; then
    print_pass "Test agents created successfully"
else
    print_fail "Failed to create test agents"
    exit 1
fi

echo ""

# Test Case 1: Agent name matching (case-insensitive)
print_test "Test Case 1: Case-insensitive agent name matching"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @test-agent-1', ARRAY['test-agent-1']);

INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @TEST-AGENT-1', ARRAY['TEST-AGENT-1']);

INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @Test-Agent-1', ARRAY['Test-Agent-1']);
EOF

# Check if messages would be matched
MATCHED=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (
    SELECT LOWER(name) FROM agents WHERE name = 'test-agent-1'
    UNION
    SELECT LOWER(alias) FROM agent_aliases aa
    JOIN agents a ON aa.agent_id = a.id
    WHERE a.name = 'test-agent-1'
  )
)
AND sender = 'test-user';
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
VALUES ('test-channel', 'test-user', 'Hello @helper', ARRAY['helper']);

INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @ASSISTANT', ARRAY['ASSISTANT']);
EOF

MATCHED=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (
    SELECT LOWER(aa.alias)
    FROM agent_aliases aa
    JOIN agents a ON aa.agent_id = a.id
    WHERE a.name = 'test-agent-1'
  )
)
AND sender = 'test-user';
")

if [ $(echo $MATCHED | tr -d ' ') -eq 2 ]; then
    print_pass "Both aliases matched correctly"
else
    print_fail "Expected 2 alias matches, got: $MATCHED"
fi

echo ""

# Test Case 3: Nickname matching
print_test "Test Case 3: Nickname matching"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @test-bot', ARRAY['test-bot']);

INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @TEST-BOT', ARRAY['TEST-BOT']);
EOF

MATCHED=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) = LOWER((SELECT nickname FROM agents WHERE name = 'test-agent-2'))
)
AND sender = 'test-user';
")

if [ $(echo $MATCHED | tr -d ' ') -eq 2 ]; then
    print_pass "Nickname matched correctly (case-insensitive)"
else
    print_fail "Expected 2 nickname matches, got: $MATCHED"
fi

echo ""

# Test Case 4: Non-matching mentions
print_test "Test Case 4: Non-matching mentions should not match"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @nonexistent', ARRAY['nonexistent']);
EOF

MATCHED=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (
    SELECT LOWER(name) FROM agents WHERE name = 'test-agent-1'
    UNION
    SELECT LOWER(alias) FROM agent_aliases aa
    JOIN agents a ON aa.agent_id = a.id
    WHERE a.name = 'test-agent-1'
  )
)
AND sender = 'test-user'
AND 'nonexistent' = ANY(mentions);
")

if [ $(echo $MATCHED | tr -d ' ') -eq 0 ]; then
    print_pass "Non-existent agent correctly not matched"
else
    print_fail "Non-existent agent incorrectly matched: $MATCHED"
fi

echo ""

# Test Case 5: Multiple mentions in one message
print_test "Test Case 5: Multiple mentions in single message"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @test-agent-1 and @test-agent-2',
        ARRAY['test-agent-1', 'test-agent-2']);
EOF

# Check if message matches for agent 1
MATCHED_1=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (
    SELECT LOWER(name) FROM agents WHERE name = 'test-agent-1'
  )
)
AND sender = 'test-user'
AND message LIKE '%@test-agent-1 and @test-agent-2%';
")

# Check if message matches for agent 2
MATCHED_2=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (
    SELECT LOWER(name) FROM agents WHERE name = 'test-agent-2'
  )
)
AND sender = 'test-user'
AND message LIKE '%@test-agent-1 and @test-agent-2%';
")

if [ $(echo $MATCHED_1 | tr -d ' ') -eq 1 ] && [ $(echo $MATCHED_2 | tr -d ' ') -eq 1 ]; then
    print_pass "Message correctly matched for both agents"
else
    print_fail "Multiple mentions not handled correctly"
fi

echo ""

# Clean up test data
print_test "Cleaning up test data"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null 2>&1
DELETE FROM agent_chat_processed WHERE chat_id IN (SELECT id FROM agent_chat WHERE sender = 'test-user');
DELETE FROM agent_chat WHERE sender = 'test-user';
DELETE FROM agent_aliases WHERE agent_id IN (SELECT id FROM agents WHERE name IN ('test-agent-1', 'test-agent-2'));
DELETE FROM agents WHERE name IN ('test-agent-1', 'test-agent-2');
EOF
print_pass "Test data cleaned up"

echo ""
echo "=========================================="
echo "All tests completed!"
echo "=========================================="
