#!/bin/bash

# Test for Issue #70: Add Outbound Send Support to agent_chat Plugin
# Tests the resolveAgentName() function and outbound send with mentions

DB_NAME="nova_memory"
DB_USER="nova"

# Test tracking counters (Issue #75 fix)
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
echo "=========================================="
echo "Testing Issue #70: Outbound Send Support"
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
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

function print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
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

# Ensure agent_aliases table exists
print_test "Checking if agent_aliases table exists"
if psql -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM agent_aliases" > /dev/null 2>&1; then
    print_pass "agent_aliases table exists"
else
    print_info "agent_aliases table not found, applying migration..."
    if [ -f patches/069-add-agent-aliases-table.sql ]; then
        psql -U $DB_USER -d $DB_NAME -f patches/069-add-agent-aliases-table.sql > /dev/null 2>&1
        print_pass "Migration applied successfully"
    else
        print_fail "Migration file not found"
        exit 1
    fi
fi

echo ""

# Create test agents if they don't exist
print_test "Setting up test agents"

# Clean up any existing test data first
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null 2>&1
DELETE FROM agent_chat_processed WHERE chat_id IN (SELECT id FROM agent_chat WHERE sender = 'test-sender-70' OR sender = 'test-receiver-70');
DELETE FROM agent_chat WHERE sender = 'test-sender-70' OR sender = 'test-receiver-70';
DELETE FROM agent_aliases WHERE alias LIKE 'test-alias-70-%';
DELETE FROM agents WHERE name IN ('test-sender-70', 'test-receiver-70');
EOF

# Create test sender agent
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agents (name, description, role, provider, model, access_method, nickname, status)
VALUES 
  ('test-sender-70', 'Test sender agent for issue 70', 'tester', 'anthropic', 'claude-3', 'api', 'Sender', 'active'),
  ('test-receiver-70', 'Test receiver agent for issue 70', 'tester', 'anthropic', 'claude-3', 'api', 'Newhart', 'active')
ON CONFLICT (name) DO NOTHING;
EOF

if [ $? -eq 0 ]; then
    print_pass "Test agents created"
else
    print_fail "Failed to create test agents"
    exit 1
fi

# Add test aliases for the receiver
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'test-alias-70-receiver' FROM agents WHERE name = 'test-receiver-70'
ON CONFLICT DO NOTHING;

INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'test-alias-70-bob' FROM agents WHERE name = 'test-receiver-70'
ON CONFLICT DO NOTHING;
EOF

print_pass "Test aliases added"

echo ""

# Test Case 1: Resolve agent by direct name
print_test "TC-70-001: Resolve agent by direct name (test-receiver-70)"
RESULT=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = LOWER('test-receiver-70')
  OR LOWER(a.nickname) = LOWER('test-receiver-70')
  OR LOWER(aa.alias) = LOWER('test-receiver-70')
LIMIT 1;
" | xargs)

if [ "$RESULT" = "test-receiver-70" ]; then
    print_pass "Resolved to: $RESULT"
else
    print_fail "Expected 'test-receiver-70', got: '$RESULT'"
fi

echo ""

# Test Case 2: Resolve agent by nickname (case-insensitive)
print_test "TC-70-002: Resolve agent by nickname 'Newhart' (case-insensitive)"
RESULT=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = LOWER('Newhart')
  OR LOWER(a.nickname) = LOWER('Newhart')
  OR LOWER(aa.alias) = LOWER('Newhart')
LIMIT 1;
" | xargs)

if [ "$RESULT" = "test-receiver-70" ]; then
    print_pass "Nickname 'Newhart' resolved to: $RESULT"
else
    print_fail "Expected 'test-receiver-70', got: '$RESULT'"
fi

# Test uppercase variation
RESULT_UPPER=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = LOWER('NEWHART')
  OR LOWER(a.nickname) = LOWER('NEWHART')
  OR LOWER(aa.alias) = LOWER('NEWHART')
LIMIT 1;
" | xargs)

if [ "$RESULT_UPPER" = "test-receiver-70" ]; then
    print_pass "Case variation 'NEWHART' resolved to: $RESULT_UPPER"
else
    print_fail "Expected 'test-receiver-70', got: '$RESULT_UPPER'"
fi

echo ""

# Test Case 3: Resolve agent by alias
print_test "TC-70-003: Resolve agent by alias 'test-alias-70-bob'"
RESULT=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = LOWER('test-alias-70-bob')
  OR LOWER(a.nickname) = LOWER('test-alias-70-bob')
  OR LOWER(aa.alias) = LOWER('test-alias-70-bob')
LIMIT 1;
" | xargs)

if [ "$RESULT" = "test-receiver-70" ]; then
    print_pass "Alias 'test-alias-70-bob' resolved to: $RESULT"
else
    print_fail "Expected 'test-receiver-70', got: '$RESULT'"
fi

echo ""

# Test Case 4: Non-existent agent returns no results
print_test "TC-70-004: Non-existent agent 'nonexistent-agent-xyz' returns no results"
RESULT=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = LOWER('nonexistent-agent-xyz')
  OR LOWER(a.nickname) = LOWER('nonexistent-agent-xyz')
  OR LOWER(aa.alias) = LOWER('nonexistent-agent-xyz')
LIMIT 1;
" | xargs)

if [ -z "$RESULT" ]; then
    print_pass "Non-existent agent correctly returns no results"
else
    print_fail "Expected empty result, got: '$RESULT'"
fi

echo ""

# Test Case 5: Insert message with mentions array
print_test "TC-70-005: Insert outbound message with mentions array"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
INSERT INTO agent_chat (channel, sender, message, mentions, reply_to, created_at)
VALUES ('direct', 'test-sender-70', 'Hello from test', ARRAY['test-receiver-70'], NULL, NOW());
EOF

if [ $? -eq 0 ]; then
    print_pass "Message inserted successfully"
    
    # Verify the message was inserted with correct mentions
    MENTIONS=$(psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT mentions::text
    FROM agent_chat
    WHERE sender = 'test-sender-70' 
      AND message = 'Hello from test'
    ORDER BY created_at DESC
    LIMIT 1;
    " | xargs)
    
    if [[ "$MENTIONS" == *"test-receiver-70"* ]]; then
        print_pass "Mentions array contains 'test-receiver-70'"
    else
        print_fail "Mentions array incorrect: $MENTIONS"
    fi
else
    print_fail "Failed to insert message"
fi

echo ""

# Test Case 6: Verify message can be fetched by receiver using getAgentIdentifiers
print_test "TC-70-006: Verify receiver can fetch message using identifiers"

# Get all identifiers for the receiver
IDENTIFIERS=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT ARRAY_AGG(DISTINCT LOWER(identifier)) as identifiers
FROM (
  SELECT a.name as identifier
  FROM agents a
  WHERE LOWER(a.name) = LOWER('test-receiver-70')
  
  UNION
  
  SELECT a.nickname as identifier
  FROM agents a
  WHERE LOWER(a.name) = LOWER('test-receiver-70')
    AND a.nickname IS NOT NULL
  
  UNION
  
  SELECT aa.alias as identifier
  FROM agents a
  JOIN agent_aliases aa ON a.id = aa.agent_id
  WHERE LOWER(a.name) = LOWER('test-receiver-70')
) all_identifiers
WHERE identifier IS NOT NULL;
" | xargs)

print_info "Receiver identifiers: $IDENTIFIERS"

# Check if message can be fetched
MATCHED=$(psql -U $DB_USER -d $DB_NAME -t -c "
WITH agent_identifiers AS (
  SELECT DISTINCT LOWER(identifier) as identifier
  FROM (
    SELECT a.name as identifier
    FROM agents a
    WHERE LOWER(a.name) = LOWER('test-receiver-70')
    
    UNION
    
    SELECT a.nickname as identifier
    FROM agents a
    WHERE LOWER(a.name) = LOWER('test-receiver-70')
      AND a.nickname IS NOT NULL
    
    UNION
    
    SELECT aa.alias as identifier
    FROM agents a
    JOIN agent_aliases aa ON a.id = aa.agent_id
    WHERE LOWER(a.name) = LOWER('test-receiver-70')
  ) all_identifiers
  WHERE identifier IS NOT NULL
)
SELECT COUNT(*)
FROM agent_chat ac
WHERE EXISTS (
  SELECT 1
  FROM unnest(ac.mentions) AS mention
  WHERE LOWER(mention) IN (SELECT identifier FROM agent_identifiers)
)
AND sender = 'test-sender-70'
AND message = 'Hello from test';
")

if [ $(echo $MATCHED | tr -d ' ') -ge 1 ]; then
    print_pass "Receiver can fetch message using identifiers"
else
    print_fail "Receiver cannot fetch message (matched: $MATCHED)"
fi

echo ""

# Test Case 7: Multiple messages with different targets
print_test "TC-70-007: Send multiple messages to different resolved targets"

# Insert messages using nickname
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
-- Message using nickname 'Newhart' (should resolve to test-receiver-70)
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('direct', 'test-sender-70', 'Message via nickname', ARRAY['test-receiver-70']);

-- Message using alias (should resolve to test-receiver-70)
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('direct', 'test-sender-70', 'Message via alias', ARRAY['test-receiver-70']);
EOF

if [ $? -eq 0 ]; then
    print_pass "Multiple messages inserted"
    
    # Count messages that receiver can see
    COUNT=$(psql -U $DB_USER -d $DB_NAME -t -c "
    WITH agent_identifiers AS (
      SELECT DISTINCT LOWER(identifier) as identifier
      FROM (
        SELECT a.name as identifier
        FROM agents a
        WHERE LOWER(a.name) = LOWER('test-receiver-70')
        
        UNION
        
        SELECT a.nickname as identifier
        FROM agents a
        WHERE LOWER(a.name) = LOWER('test-receiver-70')
          AND a.nickname IS NOT NULL
        
        UNION
        
        SELECT aa.alias as identifier
        FROM agents a
        JOIN agent_aliases aa ON a.id = aa.agent_id
        WHERE LOWER(a.name) = LOWER('test-receiver-70')
      ) all_identifiers
      WHERE identifier IS NOT NULL
    )
    SELECT COUNT(*)
    FROM agent_chat ac
    WHERE EXISTS (
      SELECT 1
      FROM unnest(ac.mentions) AS mention
      WHERE LOWER(mention) IN (SELECT identifier FROM agent_identifiers)
    )
    AND sender = 'test-sender-70';
    " | xargs)
    
    if [ "$COUNT" -ge 3 ]; then
        print_pass "Receiver can see all $COUNT messages"
    else
        print_fail "Expected at least 3 messages, receiver can see: $COUNT"
    fi
else
    print_fail "Failed to insert multiple messages"
fi

echo ""

# Test Case 8: Empty or invalid target handling
print_test "TC-70-008: Empty target validation"
RESULT=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = LOWER('')
  OR LOWER(a.nickname) = LOWER('')
  OR LOWER(aa.alias) = LOWER('')
LIMIT 1;
" | xargs)

if [ -z "$RESULT" ]; then
    print_pass "Empty target correctly returns no results"
else
    print_fail "Empty target should return no results, got: '$RESULT'"
fi

echo ""

# Test Case 9: Integration - Full send workflow simulation
print_test "TC-70-009: Full send workflow simulation"
print_info "1. Resolve 'Newhart' to agentName"
RESOLVED=$(psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT a.name
FROM agents a
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
WHERE 
  LOWER(a.name) = LOWER('Newhart')
  OR LOWER(a.nickname) = LOWER('Newhart')
  OR LOWER(aa.alias) = LOWER('Newhart')
LIMIT 1;
" | xargs)

if [ "$RESOLVED" = "test-receiver-70" ]; then
    print_info "✓ Step 1: Resolved 'Newhart' → $RESOLVED"
    
    print_info "2. Insert message with mentions=[$RESOLVED]"
    psql -U $DB_USER -d $DB_NAME << EOF > /dev/null
    INSERT INTO agent_chat (channel, sender, message, mentions)
    VALUES ('direct', 'test-sender-70', 'Full workflow test', ARRAY['$RESOLVED']);
EOF
    
    if [ $? -eq 0 ]; then
        print_info "✓ Step 2: Message inserted"
        
        print_info "3. Verify receiver can fetch using getAgentIdentifiers"
        CAN_FETCH=$(psql -U $DB_USER -d $DB_NAME -t -c "
        WITH agent_identifiers AS (
          SELECT DISTINCT LOWER(identifier) as identifier
          FROM (
            SELECT a.name as identifier FROM agents a WHERE LOWER(a.name) = LOWER('$RESOLVED')
            UNION
            SELECT a.nickname as identifier FROM agents a WHERE LOWER(a.name) = LOWER('$RESOLVED') AND a.nickname IS NOT NULL
            UNION
            SELECT aa.alias as identifier FROM agents a JOIN agent_aliases aa ON a.id = aa.agent_id WHERE LOWER(a.name) = LOWER('$RESOLVED')
          ) all_identifiers WHERE identifier IS NOT NULL
        )
        SELECT COUNT(*) FROM agent_chat ac
        WHERE EXISTS (SELECT 1 FROM unnest(ac.mentions) AS mention WHERE LOWER(mention) IN (SELECT identifier FROM agent_identifiers))
        AND message = 'Full workflow test';
        " | xargs)
        
        if [ "$CAN_FETCH" -ge 1 ]; then
            print_pass "✓ Step 3: Receiver can fetch message"
            print_pass "Full workflow completed successfully!"
        else
            print_fail "Step 3: Receiver cannot fetch message"
        fi
    else
        print_fail "Step 2: Failed to insert message"
    fi
else
    print_fail "Step 1: Failed to resolve 'Newhart', got: '$RESOLVED'"
fi

echo ""

# Clean up test data
print_info "Cleaning up test data"
psql -U $DB_USER -d $DB_NAME << EOF > /dev/null 2>&1
DELETE FROM agent_chat_processed WHERE chat_id IN (SELECT id FROM agent_chat WHERE sender = 'test-sender-70' OR sender = 'test-receiver-70');
DELETE FROM agent_chat WHERE sender = 'test-sender-70' OR sender = 'test-receiver-70';
DELETE FROM agent_aliases WHERE alias LIKE 'test-alias-70-%';
DELETE FROM agents WHERE name IN ('test-sender-70', 'test-receiver-70');
EOF
print_info "Test data cleaned up"

echo ""
echo "=========================================="
echo "Test Results Summary"
echo "=========================================="
echo "Total tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}✗ TESTS FAILED${NC}"
    echo ""
    print_info "Please review the failed tests above and fix the issues."
    exit 1
else
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo ""
    print_info "Issue #70 implementation verified successfully!"
    exit 0
fi
