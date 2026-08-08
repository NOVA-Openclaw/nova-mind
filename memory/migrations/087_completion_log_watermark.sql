-- Migration 087: completion-log watermark columns
-- Issue #561: deterministic daily-log reconcile for work_queue + workflow_runs.
--
-- Adds completion_logged_at timestamptz to both tables and seeds the watermark
-- for all already-closed rows at deploy time. The seed UPDATE is guarded by
-- `completion_logged_at IS NULL` so re-applying the migration does not re-stamp
-- already-seeded rows; however, re-applying against a live system will also
-- seed any row that became terminal between the two applies, permanently
-- excluding it from reconcile.py's scan. Run completion-log-reconcile.py before
-- re-applying this migration against a live system.

-- work_queue: terminal statuses are done/failed/stale/cancelled.
ALTER TABLE work_queue
    ADD COLUMN IF NOT EXISTS completion_logged_at timestamptz;

UPDATE work_queue
   SET completion_logged_at = COALESCE(completed_at, now())
 WHERE status IN ('done', 'failed', 'stale', 'cancelled')
   AND completion_logged_at IS NULL;

COMMENT ON COLUMN work_queue.completion_logged_at IS
    'Watermark set when the row''s completion line was appended to the daily log. '
    'Seeded by migration 087 for pre-existing closed rows; updated by completion-log-reconcile.py.';

-- workflow_runs: terminal statuses are completed/failed/cancelled.
ALTER TABLE workflow_runs
    ADD COLUMN IF NOT EXISTS completion_logged_at timestamptz;

UPDATE workflow_runs
   SET completion_logged_at = COALESCE(completed_at, now())
 WHERE status IN ('completed', 'failed', 'cancelled')
   AND completion_logged_at IS NULL;

COMMENT ON COLUMN workflow_runs.completion_logged_at IS
    'Watermark set when the row''s completion line was appended to the daily log. '
    'Seeded by migration 087 for pre-existing closed rows; updated by completion-log-reconcile.py.';
