-- Migration 086: extend extraction_failures failure_reason taxonomy with json_parse_failure
-- Issue #497: memory extraction reliability — distinguish JSON parse/repair failures
-- from generic nonzero_exit dead-letter rows.

-- Forward-only migration per repo convention. Reverting mid-rollout leaves any
-- already-written `json_parse_failure` rows as an accepted irreversible state:
-- PostgreSQL does not retroactively re-validate existing rows against a CHECK
-- constraint when it is later dropped or loosened, so those rows simply become
-- data inconsistent with a reverted (narrower) constraint rather than causing a
-- re-validation failure on revert itself.

ALTER TABLE extraction_failures
DROP CONSTRAINT IF EXISTS extraction_failures_failure_reason_check;

ALTER TABLE extraction_failures
ADD CONSTRAINT extraction_failures_failure_reason_check CHECK (
    failure_reason IS NULL
    OR failure_reason IN ('nonzero_exit', 'timeout', 'spawn_error', 'unreplayable', 'json_parse_failure')
);
