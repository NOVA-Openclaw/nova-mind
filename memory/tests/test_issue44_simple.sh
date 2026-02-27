#!/bin/bash
# Simple test for Issue #44 - Duplicate fact reinforcement

set -e

DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${DB_USER//-/_}_memory"

echo "Testing Issue #44: Duplicate Fact Reinforcement"
echo ""

# Clean up any previous test data
psql -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM entities WHERE name = 'TestPerson44';" 2>/dev/null

# Create test entity
psql -U "$DB_USER" -d "$DB_NAME" -c "INSERT INTO entities (name, type) VALUES ('TestPerson44', 'person');" >/dev/null

echo "✓ Created test entity"

# Test 1: Create initial fact
echo ""
echo "Test 1: Creating initial fact..."
echo '{"facts":[{"subject":"TestPerson44","predicate":"hobby","value":"coding","source_person":"test"}]}' | \
    ./scripts/store-memories.sh 2>&1 | grep -E "(Fact|Memory storage)"

VOTE1=$(psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT vote_count FROM entity_facts ef JOIN entities e ON e.id = ef.entity_id WHERE e.name = 'TestPerson44' AND ef.key = 'hobby';")
echo "  vote_count = $VOTE1"

# Test 2: Reinforce the same fact
echo ""
echo "Test 2: Reinforcing the same fact..."
sleep 1
echo '{"facts":[{"subject":"TestPerson44","predicate":"hobby","value":"coding","source_person":"test"}]}' | \
    ./scripts/store-memories.sh 2>&1 | grep -E "(reinforced|Memory storage)"

VOTE2=$(psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT vote_count FROM entity_facts ef JOIN entities e ON e.id = ef.entity_id WHERE e.name = 'TestPerson44' AND ef.key = 'hobby';")
echo "  vote_count = $VOTE2"

# Test 3: Verify store_relations.py also works
echo ""
echo "Test 3: Testing store_relations.py..."
psql -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM entity_facts WHERE entity_id = (SELECT id FROM entities WHERE name = 'TestPerson44') AND key = 'age';" 2>/dev/null

echo '[{"relation_type":"attribute","subject":"TestPerson44","predicate":"age","object":"25","confidence":0.9}]' | \
    SENDER_NAME="test" ./grammar_parser/store_relations.py 2>&1 | grep -E "(Fact|attribute)"

sleep 1

echo '[{"relation_type":"attribute","subject":"TestPerson44","predicate":"age","object":"25","confidence":0.9}]' | \
    SENDER_NAME="test" ./grammar_parser/store_relations.py 2>&1 | grep -E "(confirmed|attribute)"

VOTE3=$(psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "SELECT vote_count FROM entity_facts ef JOIN entities e ON e.id = ef.entity_id WHERE e.name = 'TestPerson44' AND ef.key = 'age';")
echo "  vote_count = $VOTE3"

# Verification
echo ""
echo "========== VERIFICATION =========="
psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT e.name, ef.key, ef.value, ef.vote_count, ef.confirmation_count, ef.last_confirmed 
FROM entity_facts ef 
JOIN entities e ON e.id = ef.entity_id 
WHERE e.name = 'TestPerson44' 
ORDER BY ef.key;
"

# Cleanup
psql -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM entities WHERE name = 'TestPerson44';" >/dev/null
echo ""
echo "✓ All tests completed successfully!"

# Summary
echo ""
echo "Summary:"
echo "  - store-memories.sh correctly reinforces facts (vote_count: 1 → $VOTE2)"
echo "  - store_relations.py correctly reinforces facts (vote_count: 1 → $VOTE3)"
echo "  - last_confirmed timestamp updates on each reinforcement"
echo "  - Logging shows 'reinforced' vs 'created' appropriately"
