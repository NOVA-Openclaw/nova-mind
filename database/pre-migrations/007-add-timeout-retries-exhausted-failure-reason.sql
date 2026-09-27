-- Migration 007: Add 'timeout_retries_exhausted' to extraction_failures.failure_reason check.
-- Issue #680: real-time extraction retry loop needs a distinct dead-letter reason
-- when all transient retry attempts are exhausted.
--
-- This migration is idempotent and backward-compatible: it only expands the
-- allowed values of an existing CHECK constraint. Existing rows are untouched.

DO $$
BEGIN
    -- PostgreSQL does not support ALTER CONSTRAINT for CHECK expressions, so we
    -- drop and recreate the constraint only if it exists and lacks the new value.
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'extraction_failures_failure_reason_check'
          AND conrelid = 'extraction_failures'::regclass
    ) THEN
        ALTER TABLE extraction_failures
        DROP CONSTRAINT extraction_failures_failure_reason_check;
    END IF;

    ALTER TABLE extraction_failures
    ADD CONSTRAINT extraction_failures_failure_reason_check
    CHECK (
        failure_reason IS NULL
        OR failure_reason::text IN (
            'nonzero_exit',
            'timeout',
            'spawn_error',
            'unreplayable',
            'json_parse_failure',
            'timeout_retries_exhausted'
        )
    );
END
$$;
