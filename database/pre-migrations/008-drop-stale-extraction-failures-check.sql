-- pre-migration 008: Drop stale extraction_failures_failure_reason_check
-- SE Run #866 / nova-mind#660 (unblocks schema apply; references #371/#574/#498)
--
-- This is a FALSE DIFF: the live constraint and database/schema.sql define the
-- IDENTICAL allowed value set {nonzero_exit, timeout, spawn_error, unreplayable,
-- json_parse_failure}. Postgres stores the check as = ANY(ARRAY[...]) while
-- schema.sql expresses it as IN (...); pgschema does not canonicalize these
-- forms, so it plans a DROP + recreate. All existing failure_reason values
-- satisfy both forms, so the DROP is data-safe.
--
-- Dropping the constraint here moves the destructive op out of pgschema's plan,
-- allowing schema.sql to re-add the identical constraint on the same run without
-- pgschema seeing a destructive delta that would collateral-skip additive CREATEs.
--
-- Run as: nova (table owner)
-- Idempotent: IF EXISTS guard prevents errors on repeat runs; DO-block
-- to_regclass check no-ops on first install where extraction_failures does not
-- exist yet.
--
-- nova-mind#662: pre-migrations run BEFORE the base schema apply, so on a
-- fresh (first-install) DB extraction_failures does not exist yet -- ALTER TABLE
-- would fail with "relation does not exist". Guarded with to_regclass so this
-- cleanly no-ops on first install (the table and constraint get created later
-- by the base schema apply) and still drops the stale constraint on upgrades.

DO $$
BEGIN
    IF to_regclass('public.extraction_failures') IS NOT NULL THEN
        ALTER TABLE extraction_failures
        DROP CONSTRAINT IF EXISTS extraction_failures_failure_reason_check;
    END IF;
END $$;
