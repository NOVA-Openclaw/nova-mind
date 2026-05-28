-- pre-migration 005: Drop unique date index on portfolio_snapshots
-- Run BEFORE pgschema apply.
-- Purpose: The unique index idx_snapshots_day prevents multiple snapshots per day.
--          Issue #7 requires intra-day snapshots (market-open, midday, close, etc.)
--          The unique index must be dropped to allow this.
--          A non-unique btree index on snapshot_at is retained for query performance.
-- Idempotent: IF EXISTS on drop.

BEGIN;

DROP INDEX IF EXISTS idx_snapshots_day;

COMMIT;
