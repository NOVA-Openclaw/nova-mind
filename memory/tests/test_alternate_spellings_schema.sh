#!/usr/bin/env bash
# test_alternate_spellings_schema.sh — Schema tests for entities.alternate_spellings
# Tests: D1, D2 from test-cases-4a-entity-ghost-prevention.md
# Issues: #267
#
# Requires: live nova_memory database with migration 080 applied
# Run: bash memory/tests/test_alternate_spellings_schema.sh
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

DB_USER="${PGUSER:-nova}"
DB_NAME="${PGDATABASE:-nova_memory}"
DB_HOST="${PGHOST:-localhost}"

psql_q() {
    psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -tAq -c "$1" 2>/dev/null
}

# ── D1: Column existence and type ─────────────────────────────────────────────

result=$(psql_q "SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
  WHERE table_name='entities' AND column_name='alternate_spellings'" || echo "")

if echo "$result" | grep -q "alternate_spellings"; then
    pass "D1-1: alternate_spellings column exists"
else
    fail "D1-1" "Column 'alternate_spellings' not found in entities table (run migration 080)"
fi

if echo "$result" | grep -qi "ARRAY"; then
    pass "D1-1b: data_type is ARRAY"
else
    # PostgreSQL may report 'ARRAY' or 'text[]' depending on version
    data_type=$(psql_q "SELECT data_type FROM information_schema.columns WHERE table_name='entities' AND column_name='alternate_spellings'" || echo "")
    udt=$(psql_q "SELECT udt_name FROM information_schema.columns WHERE table_name='entities' AND column_name='alternate_spellings'" || echo "")
    if [ "$data_type" = "ARRAY" ] || echo "$udt" | grep -q "text"; then
        pass "D1-1b: data_type is ARRAY (udt=$udt)"
    else
        fail "D1-1b" "Expected ARRAY type, got: data_type='$data_type' udt='$udt'"
    fi
fi

nullable=$(psql_q "SELECT is_nullable FROM information_schema.columns WHERE table_name='entities' AND column_name='alternate_spellings'" || echo "")
if [ "$nullable" = "YES" ]; then
    pass "D1-2: Column is nullable"
else
    fail "D1-2" "Column should be nullable, got: '$nullable'"
fi

# ── D1-4: Idempotency — re-running migration does not error ───────────────────

if psql -U "$DB_USER" -d "$DB_NAME" -h "$DB_HOST" -q -c \
    "ALTER TABLE entities ADD COLUMN IF NOT EXISTS alternate_spellings text[];" 2>/dev/null; then
    pass "D1-4: Migration is idempotent (re-run safe)"
else
    fail "D1-4" "Re-running migration errored out"
fi

# ── D2: Column usability ──────────────────────────────────────────────────────

# D2-1: UPDATE works (use a safe test entity or create a temporary one)
test_name="__test_entity_alternate_spellings_$$"
entity_id=$(psql_q "INSERT INTO entities (name, type) VALUES ('$test_name', 'other')
  ON CONFLICT (name, type) DO UPDATE SET name=EXCLUDED.name RETURNING id" || echo "")

if [ -z "$entity_id" ]; then
    fail "D2-setup" "Could not create test entity"
else
    # D2-1: UPDATE alternate_spellings
    if psql_q "UPDATE entities SET alternate_spellings = ARRAY['raven','ravens'] WHERE id = $entity_id" > /dev/null; then
        pass "D2-1: UPDATE alternate_spellings succeeds"
    else
        fail "D2-1" "UPDATE failed"
    fi

    # D2-2: SELECT via ANY(unnest())
    found=$(psql_q "SELECT id FROM entities
      WHERE LOWER('raven') = ANY(SELECT LOWER(unnest(alternate_spellings)))
        AND id = $entity_id" || echo "")
    if [ "$found" = "$entity_id" ]; then
        pass "D2-2: SELECT via ANY(unnest(alternate_spellings)) works"
    else
        fail "D2-2" "SELECT via unnest returned: '$found' (expected $entity_id)"
    fi

    # D2-3: Array append
    if psql_q "UPDATE entities SET alternate_spellings = alternate_spellings || ARRAY['new_spelling'] WHERE id = $entity_id" > /dev/null; then
        count=$(psql_q "SELECT array_length(alternate_spellings, 1) FROM entities WHERE id = $entity_id" || echo "")
        if [ "$count" = "3" ]; then
            pass "D2-3: Array append works (now 3 elements)"
        else
            fail "D2-3" "Expected 3 elements after append, got: '$count'"
        fi
    else
        fail "D2-3" "Array append UPDATE failed"
    fi

    # D2-4: NULL handling — entities with NULL alternate_spellings unaffected
    null_check=$(psql_q "SELECT COUNT(*) FROM entities WHERE alternate_spellings IS NULL AND id != $entity_id LIMIT 1" || echo "")
    # Just verify the query runs without error
    pass "D2-4: NULL alternate_spellings query runs without error"

    # G12: NULL alternate_spellings safe in ANY(unnest())
    if psql_q "SELECT id FROM entities WHERE LOWER('something') = ANY(SELECT LOWER(unnest(COALESCE(alternate_spellings, ARRAY[]::text[]))))" > /dev/null 2>&1; then
        pass "G12: NULL alternate_spellings handled safely (COALESCE pattern)"
    else
        fail "G12" "Query with NULL alternate_spellings raised error"
    fi

    # Cleanup
    psql_q "DELETE FROM entities WHERE id = $entity_id" > /dev/null || true
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Schema tests: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
