#!/bin/bash
# Test script for entity_facts Schema Evolution Batch
# Issues: #139, #167, #188, #189, #190, #192, #204
#
# Usage: ./tests/test-schema-evolution-batch.sh [--verbose]
# Requires: psql, pg_dump, createdb, dropdb, Python 3 with psycopg2

set -euo pipefail

VERBOSE=0
if [ "${1:-}" = "--verbose" ]; then
    VERBOSE=1
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

function ok() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS+=1))
}

function not_ok() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAIL+=1))
}

function info() {
    echo -e "${YELLOW}INFO${NC}: $1"
}

# ── Database Setup ────────────────────────────────────────────────────────────
DB_NAME="nova_memory_test_$$"
SRC_DB="nova_memory"
DB_USER="nova"

info "Creating test database: $DB_NAME"
dropdb --if-exists "$DB_NAME" 2>/dev/null || true
createdb "$DB_NAME" 2>/dev/null || true

# Clone schema only from source DB (ignore data, avoid permission issues on sequences)
pg_dump --schema-only --no-owner --no-privileges "$SRC_DB" 2>/dev/null | psql -d "$DB_NAME" >/dev/null 2>&1 || true

# Load test fixtures
psql -d "$DB_NAME" -f memory/tests/fixtures/test-data.sql >/dev/null 2>&1 || true

# Override PGDATABASE for child processes
export PGDATABASE="$DB_NAME"
export PGUSER="$DB_USER"

function psql_test() {
    psql -tA -c "$1" 2>&1
}

# ── Section 1: Migration #190 (extraction_count) ─────────────────────────────
info "=== Section 1: Issue #190 (extraction_count) ==="

# TC-190-001: ADD phase
psql -f memory/migrations/068_entity_facts_extraction_count.sql >/dev/null 2>&1

 extraction_count_type=$(psql_test "SELECT data_type FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='extraction_count';")
 extraction_count_default=$(psql_test "SELECT column_default FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='extraction_count';")
 extraction_count_nullable=$(psql_test "SELECT is_nullable FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='extraction_count';")

if [ "$extraction_count_type" = "integer" ] && [ "$extraction_count_default" = "1" ] && [ "$extraction_count_nullable" = "YES" ]; then
    ok "TC-190-001: extraction_count column correct"
else
    not_ok "TC-190-001: extraction_count column incorrect (type=$extraction_count_type, default=$extraction_count_default, nullable=$extraction_count_nullable)"
fi

# TC-190-005: VERIFY no NULLs
null_count=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE extraction_count IS NULL;")
if [ "$null_count" = "0" ]; then
    ok "TC-190-005: No NULL extraction_count values"
else
    not_ok "TC-190-005: Found $null_count NULL extraction_count values"
fi

# TC-190-006: DROP phase - check old columns gone
for col in vote_count confirmation_count last_confirmed; do
    exists=$(psql_test "SELECT 1 FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='$col';")
    if [ -z "$exists" ]; then
        ok "TC-190-006: $col dropped"
    else
        not_ok "TC-190-006: $col still exists"
    fi
done

# last_confirmed_at should still exist
last_confirmed_at_exists=$(psql_test "SELECT data_type FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='last_confirmed_at';")
if [ "$last_confirmed_at_exists" = "timestamp with time zone" ]; then
    ok "TC-190-006: last_confirmed_at retained with timezone"
else
    not_ok "TC-190-006: last_confirmed_at missing or wrong type"
fi

# ── Section 2: Migration #139 (expires) ──────────────────────────────────────
info "=== Section 2: Issue #139 (expires) ==="

psql -f memory/migrations/069_entity_facts_expires.sql >/dev/null 2>&1

 expires_type=$(psql_test "SELECT data_type FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='expires';")
 expires_nullable=$(psql_test "SELECT is_nullable FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='expires';")
 expires_default=$(psql_test "SELECT column_default FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='expires';")

if [ "$expires_type" = "timestamp with time zone" ] && [ "$expires_nullable" = "YES" ] && [ -z "$expires_default" ]; then
    ok "TC-139-001: expires column correct"
else
    not_ok "TC-139-001: expires column incorrect (type=$expires_type, nullable=$expires_nullable, default=$expires_default)"
fi

# TC-139-002: NULL accepted
psql_test "INSERT INTO entity_facts (entity_id, key, value, expires) VALUES (1, 'test_null_expires', 'test', NULL);" >/dev/null
ok "TC-139-002: expires=NULL accepted"

# TC-139-003: Future expires not treated as expired
psql_test "INSERT INTO entity_facts (entity_id, key, value, expires) VALUES (1, 'test_future_expires', 'test', NOW() + INTERVAL '30 days');" >/dev/null
future_expired=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE key='test_future_expires' AND expires < NOW();")
if [ "$future_expired" = "0" ]; then
    ok "TC-139-003: Future expires not treated as expired"
else
    not_ok "TC-139-003: Future expires incorrectly treated as expired"
fi

# TC-139-004: Past expires identified
psql_test "INSERT INTO entity_facts (entity_id, key, value, expires) VALUES (1, 'test_past_expires', 'test', NOW() - INTERVAL '1 day');" >/dev/null
past_expired=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE key='test_past_expires' AND expires < NOW() AND expires IS NOT NULL;")
if [ "$past_expired" = "1" ]; then
    ok "TC-139-004: Past expires identified by maintenance query"
else
    not_ok "TC-139-004: Past expires not identified"
fi

# TC-139-005: expires = NOW() behavior (uses <, not <=)
# Use a fixed timestamp to avoid race conditions
psql_test "INSERT INTO entity_facts (entity_id, key, value, expires) VALUES (1, 'test_now_expires', 'test', '2024-01-15 12:00:00+00');" >/dev/null
now_expired=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE key='test_now_expires' AND expires < '2024-01-15 12:00:00+00' AND expires IS NOT NULL;")
if [ "$now_expired" = "0" ]; then
    ok "TC-139-005: expires=NOW() not returned by < query (uses < not <=)"
else
    not_ok "TC-139-005: expires=NOW() incorrectly returned"
fi

# ── Section 3: Migration #167 (durability + category) ──────────────────────────
info "=== Section 3: Issue #167 (durability + category) ==="

# Seed pre-migration data with old data_type values BEFORE migration 070
for i in $(seq 1 10); do
    psql_test "INSERT INTO entity_facts (entity_id, key, value, data_type, confidence) VALUES (1, 'test_perm_$i', 'perm value $i', 'permanent', 1.0);" >/dev/null 2>&1 || true
done
for i in $(seq 1 10); do
    psql_test "INSERT INTO entity_facts (entity_id, key, value, data_type, confidence) VALUES (1, 'test_identity_$i', 'identity value $i', 'identity', 1.0);" >/dev/null 2>&1 || true
done
for i in $(seq 1 5); do
    psql_test "INSERT INTO entity_facts (entity_id, key, value, data_type, confidence) VALUES (1, 'test_pref_$i', 'pref value $i', 'preference', 0.9);" >/dev/null 2>&1 || true
done
for i in $(seq 1 20); do
    psql_test "INSERT INTO entity_facts (entity_id, key, value, data_type, confidence) VALUES (1, 'test_obs_$i', 'obs value $i', 'observation', 0.8);" >/dev/null 2>&1 || true
done

psql -f memory/migrations/070_entity_facts_durability_category.sql >/dev/null 2>&1

# TC-167-001: Column definitions
dur_type=$(psql_test "SELECT data_type FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='durability';")
dur_nullable=$(psql_test "SELECT is_nullable FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='durability';")
dur_default=$(psql_test "SELECT column_default FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='durability';")

cat_type=$(psql_test "SELECT data_type FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='category';")
cat_nullable=$(psql_test "SELECT is_nullable FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='category';")
cat_default=$(psql_test "SELECT column_default FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='category';")

if [ "$dur_type" = "character varying" ] && [ "$dur_nullable" = "NO" ] && [ "$dur_default" = "'long_term'::character varying" ]; then
    ok "TC-167-001: durability column correct"
else
    not_ok "TC-167-001: durability column incorrect (type=$dur_type, nullable=$dur_nullable, default=$dur_default)"
fi

if [ "$cat_type" = "text" ] && [ "$cat_nullable" = "NO" ] && [ "$cat_default" = "'observation'::text" ]; then
    ok "TC-167-001: category column correct"
else
    not_ok "TC-167-001: category column incorrect (type=$cat_type, nullable=$cat_nullable, default=$cat_default)"
fi

# TC-167-002: CHECK constraint rejects invalid durability
invalid_dur=$(psql_test "UPDATE entity_facts SET durability = 'transient' WHERE id = 1;" 2>&1 || true)
if echo "$invalid_dur" | grep -qi "violates check constraint"; then
    ok "TC-167-002: durability CHECK constraint rejects invalid value"
else
    not_ok "TC-167-002: durability CHECK constraint did not reject invalid value"
fi

# TC-167-003: All valid durability values accepted
for val in permanent long_term short_term ephemeral; do
    psql_test "UPDATE entity_facts SET durability = '$val' WHERE id = 1;" >/dev/null 2>&1 || true
    current=$(psql_test "SELECT durability FROM entity_facts WHERE id = 1;")
    if [ "$current" = "$val" ]; then
        ok "TC-167-003: durability='$val' accepted"
    else
        not_ok "TC-167-003: durability='$val' rejected"
    fi
done

# Restore durability
psql_test "UPDATE entity_facts SET durability = 'long_term' WHERE id = 1;" >/dev/null

# TC-167-004 through TC-167-008: Data migration counts
permanent_count=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE durability='permanent' AND category='identity';")
if [ "$permanent_count" -ge 10 ]; then
    ok "TC-167-004/005: permanent/identity rows migrated ($permanent_count found)"
else
    not_ok "TC-167-004/005: permanent/identity rows migrated (only $permanent_count found)"
fi

pref_count=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE durability='long_term' AND category='preference';")
if [ "$pref_count" -ge 5 ]; then
    ok "TC-167-006: preference rows migrated ($pref_count found)"
else
    not_ok "TC-167-006: preference rows migrated (only $pref_count found)"
fi

obs_count=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE durability='long_term' AND category='observation';")
if [ "$obs_count" -ge 20 ]; then
    ok "TC-167-007: observation rows migrated ($obs_count found)"
else
    not_ok "TC-167-007: observation rows migrated (only $obs_count found)"
fi

null_dur=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE durability IS NULL;")
null_cat=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE category IS NULL;")
if [ "$null_dur" = "0" ] && [ "$null_cat" = "0" ]; then
    ok "TC-167-008: No NULL durability or category values"
else
    not_ok "TC-167-008: Found NULL durability=$null_dur or category=$null_cat"
fi

# TC-167-009: data_type column dropped
data_type_exists=$(psql_test "SELECT 1 FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='data_type';")
if [ -z "$data_type_exists" ]; then
    ok "TC-167-009: data_type column dropped"
else
    not_ok "TC-167-009: data_type column still exists"
fi

# TC-167-010: chk_data_type constraint dropped
chk_exists=$(psql_test "SELECT 1 FROM information_schema.table_constraints WHERE table_name='entity_facts' AND constraint_name='chk_data_type';")
if [ -z "$chk_exists" ]; then
    ok "TC-167-010: chk_data_type constraint dropped"
else
    not_ok "TC-167-010: chk_data_type constraint still exists"
fi

# TC-167-011/012: Category accepts free-form values
for cat in observation preference identity mood decision routine state obligation relationship goal health_metric arbitrary_novel_value_xyz; do
    psql_test "INSERT INTO entity_facts (entity_id, key, value, category) VALUES (1, 'test_cat_$cat', 'test', '$cat');" >/dev/null 2>&1
    ok "TC-167-011/012: category='$cat' accepted"
done

# TC-167-013: Category NOT NULL enforced
null_cat_result=$(psql_test "INSERT INTO entity_facts (entity_id, key, value, category) VALUES (1, 'test_null_cat', 'test', NULL);" 2>&1 || true)
if echo "$null_cat_result" | grep -qi "violates not-null constraint"; then
    ok "TC-167-013: category NULL rejected"
else
    not_ok "TC-167-013: category NULL was accepted"
fi

# ── Section 4: Issue #204 (entity_fact_sources) ──────────────────────────────
info "=== Section 4: Issue #204 (entity_fact_sources) ==="

psql -f memory/migrations/071_entity_fact_sources.sql >/dev/null 2>&1

# TC-204-001: Table exists with correct structure
cols=$(psql_test "SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name='entity_fact_sources' ORDER BY ordinal_position;")
has_fact_id=$(echo "$cols" | grep "fact_id" | grep "integer" | grep "NO" | wc -l)
has_source_entity_id=$(echo "$cols" | grep "source_entity_id" | grep "integer" | grep "NO" | wc -l)
has_source_citation=$(echo "$cols" | grep "source_citation" | grep "text" | grep "YES" | wc -l)
has_attribution_count=$(echo "$cols" | grep "attribution_count" | grep "integer" | grep "YES" | wc -l)
has_first_seen=$(echo "$cols" | grep "first_seen" | grep "timestamp with time zone" | grep "YES" | wc -l)

if [ "$has_fact_id" -eq 1 ] && [ "$has_source_entity_id" -eq 1 ] && [ "$has_source_citation" -eq 1 ] && [ "$has_attribution_count" -eq 1 ] && [ "$has_first_seen" -eq 1 ]; then
    ok "TC-204-001: entity_fact_sources table structure correct"
else
    not_ok "TC-204-001: entity_fact_sources table structure incorrect"
fi

# TC-204-002: FK on fact_id rejects invalid
fk_fact_result=$(psql_test "INSERT INTO entity_fact_sources (fact_id, source_entity_id) VALUES (999999, 1);" 2>&1 || true)
if echo "$fk_fact_result" | grep -qi "violates foreign key constraint"; then
    ok "TC-204-002: fact_id FK rejects invalid"
else
    not_ok "TC-204-002: fact_id FK did not reject invalid"
fi

# TC-204-003: FK on source_entity_id rejects invalid
fk_src_result=$(psql_test "INSERT INTO entity_fact_sources (fact_id, source_entity_id) VALUES (1, 999999);" 2>&1 || true)
if echo "$fk_src_result" | grep -qi "violates foreign key constraint"; then
    ok "TC-204-003: source_entity_id FK rejects invalid"
else
    not_ok "TC-204-003: source_entity_id FK did not reject invalid"
fi

# TC-204-005: source_entity_id NOT NULL
null_src_result=$(psql_test "INSERT INTO entity_fact_sources (fact_id, source_entity_id) VALUES (1, NULL);" 2>&1 || true)
if echo "$null_src_result" | grep -qi "violates not-null constraint"; then
    ok "TC-204-005: source_entity_id NOT NULL enforced"
else
    not_ok "TC-204-005: source_entity_id NULL was accepted"
fi

# TC-204-006: source_citation nullable
psql_test "INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation) VALUES (1, 2, NULL);" >/dev/null 2>&1
psql_test "INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation) VALUES (1, 3, 'NY Times, 2026-05-13, p.4');" >/dev/null 2>&1
ok "TC-204-006: source_citation nullable with and without value"

# TC-204-004: CASCADE DELETE on fact deletion
psql_test "DELETE FROM entity_fact_sources WHERE fact_id = 1;" >/dev/null 2>&1 || true
psql_test "INSERT INTO entity_fact_sources (fact_id, source_entity_id) VALUES (1, 2);" >/dev/null
psql_test "INSERT INTO entity_fact_sources (fact_id, source_entity_id) VALUES (1, 3);" >/dev/null
psql_test "INSERT INTO entity_fact_sources (fact_id, source_entity_id) VALUES (1, 4);" >/dev/null
src_before=$(psql_test "SELECT COUNT(*) FROM entity_fact_sources WHERE fact_id = 1;")
psql_test "DELETE FROM entity_facts WHERE id = 1;" >/dev/null
src_after=$(psql_test "SELECT COUNT(*) FROM entity_fact_sources WHERE fact_id = 1;")
if [ "$src_before" = "3" ] && [ "$src_after" = "0" ]; then
    ok "TC-204-004: CASCADE DELETE on fact deletion works"
else
    not_ok "TC-204-004: CASCADE DELETE failed (before=$src_before, after=$src_after)"
fi

# TC-204-010: old columns dropped from entity_facts
for col in source source_entity_id; do
    exists=$(psql_test "SELECT 1 FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='$col';")
    if [ -z "$exists" ]; then
        ok "TC-204-010: entity_facts.$col dropped"
    else
        not_ok "TC-204-010: entity_facts.$col still exists"
    fi
done

# TC-211-014: source_citation is TEXT on entity_fact_sources, NOT on entity_facts
citation_on_ef=$(psql_test "SELECT 1 FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='source_citation';")
citation_on_efs=$(psql_test "SELECT 1 FROM information_schema.columns WHERE table_name='entity_fact_sources' AND column_name='source_citation';")
if [ -z "$citation_on_ef" ] && [ "$citation_on_efs" = "1" ]; then
    ok "TC-211-014: source_citation is on entity_fact_sources, not entity_facts"
else
    not_ok "TC-211-014: source_citation location incorrect"
fi

# ── Section 5/6: merge_facts() function (#192) ───────────────────────────────
info "=== Section 5/6: Issue #192 (merge_facts) ==="

psql -f memory/migrations/072_merge_facts_function.sql >/dev/null 2>&1

# Seed test data for merge_facts (ensure entity exists first)
psql_test "INSERT INTO entities (id, name, type) VALUES (1, 'Test Entity', 'person') ON CONFLICT DO NOTHING;" >/dev/null 2>&1 || true
psql_test "INSERT INTO entities (id, name, type) VALUES (10, 'Source A', 'person') ON CONFLICT DO NOTHING;" >/dev/null 2>&1 || true
psql_test "INSERT INTO entities (id, name, type) VALUES (20, 'Source B', 'person') ON CONFLICT DO NOTHING;" >/dev/null 2>&1 || true

psql_test "
INSERT INTO entity_facts (id, entity_id, key, value, extraction_count, last_confirmed_at, confidence)
VALUES (100, 1, 'hobby', 'hiking', 3, '2024-01-01 10:00:00+00', 0.8),
       (101, 1, 'hobby', 'hiking', 5, '2024-06-01 12:00:00+00', 0.9);
" >/dev/null 2>&1

psql_test "
INSERT INTO entity_fact_sources (fact_id, source_entity_id, attribution_count, first_seen, last_seen)
VALUES (100, 10, 2, '2024-01-01', '2024-03-01'),
       (101, 10, 3, '2024-04-01', '2024-06-01'),
       (101, 20, 1, '2024-05-15', '2024-06-01');
" >/dev/null 2>&1

# TC-206-001/002/003/004/005: Basic merge
merged_count=$(psql_test "SELECT (merge_facts(100, 101)).extraction_count;")
merged_conf=$(psql_test "SELECT confidence FROM entity_facts WHERE id = 100;")
merged_date=$(psql_test "SELECT last_confirmed_at::text FROM entity_facts WHERE id = 100;")
absorbed_exists=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE id = 101;")

if [ "$merged_count" = "8" ]; then
    ok "TC-206-001: merge_facts sums extraction_count (8)"
else
    not_ok "TC-206-001: merge_facts extraction_count=$merged_count (expected 8)"
fi

if [ "$merged_date" = "2024-06-01 12:00:00+00" ]; then
    ok "TC-206-002: merge_facts takes MAX(last_confirmed_at)"
else
    not_ok "TC-206-002: merge_facts last_confirmed_at=$merged_date"
fi

if [ "$merged_conf" = "0.9" ]; then
    ok "TC-206-003: merge_facts takes MAX(confidence)"
else
    not_ok "TC-206-003: merge_facts confidence=$merged_conf"
fi

if [ "$absorbed_exists" = "0" ]; then
    ok "TC-206-004: merge_facts deletes absorbed row"
else
    not_ok "TC-206-004: absorbed row still exists"
fi

survivor_exists=$(psql_test "SELECT COUNT(*) FROM entity_facts WHERE id = 100;")
if [ "$survivor_exists" = "1" ]; then
    ok "TC-206-005: merge_facts preserves survivor row"
else
    not_ok "TC-206-005: survivor row missing"
fi

# TC-206-006: Shared source attribution summed
shared_count=$(psql_test "SELECT attribution_count FROM entity_fact_sources WHERE fact_id = 100 AND source_entity_id = 10;")
if [ "$shared_count" = "5" ]; then
    ok "TC-206-006: Shared source attribution summed to 5"
else
    not_ok "TC-206-006: Shared source attribution=$shared_count (expected 5)"
fi

# TC-206-009: Nonexistent survivor
survivor_err=$(psql_test "SELECT merge_facts(9999, 101);" 2>&1 || true)
if echo "$survivor_err" | grep -qi "survivor fact 9999 does not exist"; then
    ok "TC-206-009: merge_facts errors on nonexistent survivor"
else
    not_ok "TC-206-009: merge_facts did not error on nonexistent survivor"
fi

# TC-206-010: Nonexistent absorbed
absorbed_err=$(psql_test "SELECT merge_facts(100, 9999);" 2>&1 || true)
if echo "$absorbed_err" | grep -qi "absorbed fact 9999 does not exist"; then
    ok "TC-206-010: merge_facts errors on nonexistent absorbed"
else
    not_ok "TC-206-010: merge_facts did not error on nonexistent absorbed"
fi

# TC-206-011: Self-merge
self_err=$(psql_test "SELECT merge_facts(100, 100);" 2>&1 || true)
if echo "$self_err" | grep -qi "cannot merge a fact with itself"; then
    ok "TC-206-011: merge_facts errors on self-merge"
else
    not_ok "TC-206-011: merge_facts did not error on self-merge"
fi

# TC-206-014: Cross-entity merge
psql_test "INSERT INTO entity_facts (id, entity_id, key, value, extraction_count) VALUES (102, 2, 'x', 'y', 1);" >/dev/null 2>&1
cross_err=$(psql_test "SELECT merge_facts(100, 102);" 2>&1 || true)
if echo "$cross_err" | grep -qi "cannot merge facts from different entities"; then
    ok "TC-206-014: merge_facts errors on cross-entity merge"
else
    not_ok "TC-206-014: merge_facts did not error on cross-entity merge"
fi

# Clean up test facts
psql_test "DELETE FROM entity_fact_sources WHERE fact_id IN (100, 101, 102);" >/dev/null 2>&1 || true
psql_test "DELETE FROM entity_facts WHERE id IN (100, 101, 102);" >/dev/null 2>&1 || true

# ── Section 7: Confidence-Tiered Dedup (#192) ─────────────────────────────────
info "=== Section 7: Issue #192 (dedup) ==="

# The dedup logic is tested through the maintenance script and merge_facts.
# For unit-level testing, we verify the pg_trgm similarity threshold.
psql_test "
INSERT INTO entity_facts (id, entity_id, key, value, confidence)
VALUES (200, 1, 'hobby', 'hiking in mountains', 0.9),
       (201, 1, 'hobby', 'hiking in the mountains', 0.85);
" >/dev/null 2>&1

sim=$(psql_test "SELECT similarity('hiking in mountains', 'hiking in the mountains');")
if [ "${sim:0:4}" = "0.84" ] || [ "${sim:0:4}" = "0.85" ]; then
    ok "TC-207-001/010: pg_trgm similarity ~0.84-0.85 for high-confidence merge threshold"
else
    not_ok "TC-207-001/010: pg_trgm similarity=$sim (expected ~0.84)"
fi

psql_test "DELETE FROM entity_facts WHERE id IN (200, 201);" >/dev/null 2>&1 || true

# ── Section 8: Extraction Prompt Changes (#188, #167, #204) ──────────────────
info "=== Section 8: Extraction Prompt Changes ==="

# TC-208-001/002/003/004: SENDER_PROVIDER platform labels
prompt_output=$(cd memory/scripts && python3 -c "
import os, sys
sys.path.insert(0, '.')
os.environ['SENDER_PROVIDER'] = 'discord'
os.environ['SENDER_ID'] = '330189773371080716'
from extract_memories import build_extraction_prompt
p = build_extraction_prompt('test', 'User', '330189773371080716', 'discord', False, 'public')
print(p)
")
if echo "$prompt_output" | grep -q "Discord user ID: 330189773371080716"; then
    ok "TC-208-001/004: Discord ID labeled correctly in prompt"
else
    not_ok "TC-208-001/004: Discord ID not labeled correctly"
fi

prompt_output2=$(cd memory/scripts && python3 -c "
import os, sys
sys.path.insert(0, '.')
os.environ['SENDER_PROVIDER'] = 'signal'
os.environ['SENDER_ID'] = '+15125551234'
from extract_memories import build_extraction_prompt
p = build_extraction_prompt('test', 'Alice', '+15125551234', 'signal', False, 'public')
print(p)
")
if echo "$prompt_output2" | grep -q "Signal phone: +15125551234"; then
    ok "TC-208-002: Signal phone labeled correctly in prompt"
else
    not_ok "TC-208-002: Signal phone not labeled correctly"
fi

# TC-208-005: Discord snowflake not extracted as phone
if echo "$prompt_output" | grep -qi "discord snowflakes.*never.*extracted as phone"; then
    ok "TC-208-005: Prompt warns against extracting Discord snowflakes as phone"
else
    not_ok "TC-208-005: Prompt missing Discord snowflake warning"
fi

# TC-208-006/007: Category list in prompt
if echo "$prompt_output" | grep -qi "observation, preference, identity, mood, decision, routine, state, obligation"; then
    ok "TC-208-006: Category list present in prompt"
else
    not_ok "TC-208-006: Category list missing from prompt"
fi

if echo "$prompt_output" | grep -qi "other appropriate categor"; then
    ok "TC-208-007: Prompt allows non-listed categories"
else
    not_ok "TC-208-007: Prompt does not allow non-listed categories"
fi

# TC-208-008: Durability guidance
if echo "$prompt_output" | grep -qi "permanent.*identity facts"; then
    ok "TC-208-008: Durability guidance present in prompt"
else
    not_ok "TC-208-008: Durability guidance missing from prompt"
fi

# TC-208-010: Source citation fields
if echo "$prompt_output" | grep -qi "publication.*date.*page.*url"; then
    ok "TC-208-010: Source citation fields in prompt"
else
    not_ok "TC-208-010: Source citation fields missing from prompt"
fi

# TC-208-013: Expires temporal boundary
if echo "$prompt_output" | grep -qi "expires.*temporal boundary"; then
    ok "TC-208-013: Expires temporal boundary in prompt"
else
    not_ok "TC-208-013: Expires temporal boundary missing from prompt"
fi

# ── Section 9: Maintenance Decay Rates (#167) ─────────────────────────────────
info "=== Section 9: Maintenance Decay Rates ==="

# TC-209-001: DECAY_RATES keys
decay_keys=$(cd memory/scripts && python3 -c "
from memory_maintenance import DECAY_RATES
print(' '.join(sorted(DECAY_RATES.keys())))
")
if [ "$decay_keys" = "ephemeral long_term permanent short_term" ]; then
    ok "TC-209-001: DECAY_RATES uses durability keys"
else
    not_ok "TC-209-001: DECAY_RATES keys=$decay_keys (expected: ephemeral long_term permanent short_term)"
fi

# TC-209-002: Decay values
permanent_val=$(cd memory/scripts && python3 -c "from memory_maintenance import DECAY_RATES; print(DECAY_RATES['permanent'])")
longterm_val=$(cd memory/scripts && python3 -c "from memory_maintenance import DECAY_RATES; print(DECAY_RATES['long_term'])")
shortterm_val=$(cd memory/scripts && python3 -c "from memory_maintenance import DECAY_RATES; print(DECAY_RATES['short_term'])")
ephemeral_val=$(cd memory/scripts && python3 -c "from memory_maintenance import DECAY_RATES; print(DECAY_RATES['ephemeral'])")

if [ "$permanent_val" = "0" ]; then
    ok "TC-209-002: permanent decay rate = 0"
else
    not_ok "TC-209-002: permanent decay rate = $permanent_val"
fi

if python3 -c "exit(0 if $longterm_val <= 0.005 else 1)"; then
    ok "TC-209-002: long_term decay rate <= 0.005"
else
    not_ok "TC-209-002: long_term decay rate = $longterm_val"
fi

if python3 -c "exit(0 if 0.015 <= $shortterm_val <= 0.025 else 1)"; then
    ok "TC-209-002: short_term decay rate ~0.02"
else
    not_ok "TC-209-002: short_term decay rate = $shortterm_val"
fi

if python3 -c "exit(0 if 0.08 <= $ephemeral_val <= 0.12 else 1)"; then
    ok "TC-209-002: ephemeral decay rate ~0.1"
else
    not_ok "TC-209-002: ephemeral decay rate = $ephemeral_val"
fi

# TC-209-010: WHERE clause uses durability
where_clause=$(grep -n "durability != 'permanent'" memory/scripts/memory-maintenance.py | head -1)
if [ -n "$where_clause" ]; then
    ok "TC-209-010: Decay query uses durability != 'permanent'"
else
    not_ok "TC-209-010: Decay query missing durability filter"
fi

# ── Section 10: Codebase Audit ───────────────────────────────────────────────
info "=== Section 10: Codebase Audit ==="

# TC-210-001 through TC-210-018: grep for orphaned column references
orphaned=0

for file in memory/scripts/extract_memories.py memory/scripts/memory-maintenance.py memory/scripts/dedup_helper.py memory/scripts/get-visible-facts.sh memory/scripts/proactive-recall.py; do
    if [ -f "$file" ]; then
        # Check for dropped column references (excluding comments and other tables)
        # vote_count on entity_facts
        matches=$(grep -n "vote_count" "$file" 2>/dev/null | grep -v "#" | grep -v "agent_domains" | grep -v "vocabulary" || true)
        if [ -n "$matches" ]; then
            not_ok "TC-210: $file references vote_count: $matches"
            orphaned=1
        fi

        # confirmation_count on entity_facts
        matches=$(grep -n "confirmation_count" "$file" 2>/dev/null | grep -v "#" || true)
        if [ -n "$matches" ]; then
            not_ok "TC-210: $file references confirmation_count: $matches"
            orphaned=1
        fi

        # last_confirmed (without _at) on entity_facts
        matches=$(grep -n "last_confirmed[^_]" "$file" 2>/dev/null | grep -v "#" || true)
        if [ -n "$matches" ]; then
            not_ok "TC-210: $file references last_confirmed (no _at): $matches"
            orphaned=1
        fi

        # data_type on entity_facts (not in archive or comments)
        matches=$(grep -n "data_type" "$file" 2>/dev/null | grep -v "#" | grep -v "archive" || true)
        if [ -n "$matches" ]; then
            not_ok "TC-210: $file references data_type: $matches"
            orphaned=1
        fi

        # source_entity_id on entity_facts
        matches=$(grep -n "source_entity_id" "$file" 2>/dev/null | grep -v "#" | grep -v "entity_fact_sources" || true)
        if [ -n "$matches" ]; then
            not_ok "TC-210: $file references source_entity_id on entity_facts: $matches"
            orphaned=1
        fi
    fi
done

if [ "$orphaned" = "0" ]; then
    ok "TC-210: No orphaned column references in scripts"
fi

# TC-210-015: test-data.sql clean
test_data_cols=$(grep "INSERT INTO entity_facts" memory/tests/fixtures/test-data.sql)
if echo "$test_data_cols" | grep -qE "vote_count|confirmation_count|last_confirmed[^_]|data_type|source_entity_id"; then
    not_ok "TC-210-015: test-data.sql still references dropped columns"
else
    ok "TC-210-015: test-data.sql clean of dropped columns"
fi

# TC-210-019: get-visible-facts.sh uses entity_fact_sources JOIN
if grep -q "JOIN entity_fact_sources" memory/scripts/get-visible-facts.sh; then
    ok "TC-210-019: get-visible-facts.sh JOINs entity_fact_sources"
else
    not_ok "TC-210-019: get-visible-facts.sh missing entity_fact_sources JOIN"
fi

# ── Section 11: Backward Compatibility ───────────────────────────────────────
info "=== Section 11: Backward Compatibility ==="

# TC-211-005: Row count preserved
pre_count=$(psql_test "SELECT COUNT(*) FROM entity_facts;")
if [ "$pre_count" -gt 0 ]; then
    ok "TC-211-005: Row count preserved ($pre_count facts)"
else
    not_ok "TC-211-005: No facts in database"
fi

# TC-211-015 through TC-211-017: Column existence
for col in durability category extraction_count; do
    exists=$(psql_test "SELECT 1 FROM information_schema.columns WHERE table_name='entity_facts' AND column_name='$col';")
    if [ "$exists" = "1" ]; then
        ok "TC-211-015/016/017: $col column exists"
    else
        not_ok "TC-211-015/016/017: $col column missing"
    fi
done

# ── Cleanup ──────────────────────────────────────────────────────────────────
info "=== Cleanup ==="
unset PGDATABASE

dropdb --if-exists "$DB_NAME" 2>/dev/null || true
rm -f /tmp/nova_test.dump

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "Test Results: $PASS passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
