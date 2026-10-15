-- Rollback: 504-provenance-grading
-- Reverses all changes from 504-provenance-grading.sql
-- Run this if the migration needs to be backed out.

BEGIN;

-- Drop views first (depend on columns/tables)
DROP VIEW IF EXISTS v_current_stateful_facts;
DROP VIEW IF EXISTS v_fact_grades;

-- Drop function
DROP FUNCTION IF EXISTS get_strictest_mutability(INTEGER, VARCHAR);

-- Drop new table
DROP TABLE IF EXISTS entity_credibility;

-- Remove added columns from entity_fact_sources
ALTER TABLE entity_fact_sources
    DROP COLUMN IF EXISTS source_session_id,
    DROP COLUMN IF EXISTS verification_quality,
    DROP COLUMN IF EXISTS reporting_distance;

-- Remove added indexes from entity_facts
DROP INDEX IF EXISTS idx_entity_facts_mutability;
DROP INDEX IF EXISTS idx_entity_facts_gradable;
DROP INDEX IF EXISTS idx_entity_facts_assertion_intent;

-- Remove added columns from entity_facts
ALTER TABLE entity_facts
    DROP COLUMN IF EXISTS mutability_class,
    DROP COLUMN IF EXISTS assertion_intent;

-- Drop enum types
DROP TYPE IF EXISTS mutability_class_enum;
DROP TYPE IF EXISTS assertion_intent_enum;

COMMIT;
