# Test Cases for Issue #127: Installer Schema Migrations

## Overview
This test plan validates that `agent-install.sh`:
1. Correctly identifies missing columns in existing tables.
2. Applies necessary `ALTER TABLE` operations idempotently.
3. Migrates legacy data (e.g., `fallback_model` -> `fallback_models`).
4. Maintains constraints and permissions.

## Test Environment Setup
Tests should be performed against a temporary test database to avoid disrupting production.

```bash
# Setup test DB
export PGUSER="nova"
export PGDATABASE="nova_memory_test_127"
createdb $PGDATABASE
```

---

## 1. Fresh Install
**Goal:** Verify that a fresh run on an empty database creates all tables with current schema correctly.
- **Pre-conditions:** Test database is empty.
- **Action:** Run `agent-install.sh --database $PGDATABASE`.
- **Expected Results:**
    - All tables in `schema.sql` are created.
    - `agents` table has columns: `fallback_models` (TEXT[]), `thinking` (VARCHAR(20)), `pronouns` (VARCHAR(50)).
    - `agents` table has `agents_thinking_check` constraint.
    - No migration warnings reported.

## 2. Existing Install - Missing Columns
**Goal:** Verify installer adds missing columns to an existing table.
- **Pre-conditions:** 
    - `agents` table exists but was created without the new columns.
    - Manually drop columns if they exist: `ALTER TABLE agents DROP COLUMN IF EXISTS fallback_models, DROP COLUMN IF EXISTS thinking, DROP COLUMN IF EXISTS pronouns;`
- **Action:** Run `agent-install.sh --database $PGDATABASE`.
- **Expected Results:**
    - Installer reports adding columns `fallback_models`, `thinking`, `pronouns`.
    - `verify_schema` (run at end of script) passes.
    - `thinking` column has the correct `CHECK` constraint.

## 3. Data Migration (`fallback_model` -> `fallback_models`)
**Goal:** Verify data from legacy varchar column is migrated to new array column.
- **Pre-conditions:**
    - `agents` table has data in `fallback_model`.
    - `fallback_models` is empty OR not yet added.
    - Example record: `{ name: 'test-agent', fallback_model: 'gpt-4o' }`.
- **Action:** Run `agent-install.sh --database $PGDATABASE`.
- **Expected Results:**
    - `fallback_models` for `test-agent` now contains `{'gpt-4o'}`.
    - Legacy data preserved.

## 4. Data Migration Edge Cases
**Goal:** Handle empty or already migrated records.
- **Pre-conditions:**
    - Record A: `fallback_model` is NULL.
    - Record B: `fallback_model` is empty string `''`.
    - Record C: `fallback_models` already has data `{ 'primary-fallback' }`.
- **Action:** Run `agent-install.sh --database $PGDATABASE`.
- **Expected Results:**
    - Record A: `fallback_models` remains NULL or empty.
    - Record B: `fallback_models` remains NULL or empty.
    - Record C: `fallback_models` is NOT overwritten or appended with redundant data if the logic handles "already migrated".

## 5. Idempotency Run
**Goal:** Verify consecutive runs do not cause errors or duplicate migrations.
- **Pre-conditions:** Schema is already up-to-date.
- **Action:** Run `agent-install.sh --database $PGDATABASE` twice.
- **Expected Results:**
    - Second run executes without errors.
    - No new columns are (redundantly) added.
    - No duplicate data added to array columns.
    - Script reports "Schema up to date" or equivalent.

## 6. Up-to-date Schema Verification
**Goal:** Verify `verify_schema()` correctly identifies a complete schema.
- **Pre-conditions:** Manual verification of DB columns matches `schema.sql`.
- **Action:** Run `agent-install.sh --verify-only --database $PGDATABASE`.
- **Expected Results:**
    - Output shows `✅ Table 'agents' schema present (28 columns)` (or current correct count).
    - Status: All checks passed.

## 7. Migration Reporting
**Goal:** Verify human-readable output of migration steps.
- **Action:** Run installer when migrations are pending.
- **Expected Results:**
    - Console output clearly states: `Adding missing column 'thinking' to table 'agents'...`
    - Console output states: `Migrating data from 'fallback_model' to 'fallback_models'...`

## 8. Cross-User Compatibility
**Goal:** Ensure migration works for both `nova` and `nova-staging`.
- **Action:** Run test setup and installer using `PGUSER=nova-staging`.
- **Expected Results:**
    - Deployment succeeds.
    - Table ownership and permissions (ACLs) remain correct as per `schema.sql` (Granting to newhart, gem, etc.).

## 9. CHECK Constraint Validation
**Goal:** Verify new columns honor constraints.
- **Action:** Attempt an invalid update: `UPDATE agents SET thinking = 'hyper-mega-high' WHERE name = 'test-agent';`
- **Expected Results:**
    - PostgreSQL throws constraint violation error: `new row for relation "agents" violates check constraint "agents_thinking_check"`.

## 10. Coexisting Old and New Columns
**Goal:** Verify migration handles the case where both `fallback_model` (old VARCHAR) and `fallback_models` (new TEXT[]) exist simultaneously.
- **Pre-conditions:**
    - `agents` table has both `fallback_model` (VARCHAR) and `fallback_models` (TEXT[]) columns.
    - Some agents have data in `fallback_model` only, some in `fallback_models` only, some in both.
- **Action:** Run `agent-install.sh`.
- **Expected Results:**
    - Migration does NOT drop or rename `fallback_model` — both columns coexist.
    - Data is copied from `fallback_model` to `fallback_models` only where `fallback_models` is NULL.
    - Agents with existing `fallback_models` data are untouched.
    - No type conflict errors between the VARCHAR and TEXT[] columns.

## 11. Integration - Plugin Query
**Goal:** Ensure downstream plugins (like `agent_config_sync`) work after migration.
- **Action:** Run query: `SELECT name, fallback_models, thinking FROM agents WHERE name = 'gem';`
- **Expected Results:**
    - Query returns successfully with expected data types.
    - No "column does not exist" errors.
