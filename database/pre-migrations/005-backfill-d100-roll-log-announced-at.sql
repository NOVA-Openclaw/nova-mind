-- pre-migration 005: Backfill d100_roll_log.announced_at for historical rows
-- Issue #432
--
-- Run as: nova (table owner)
-- Idempotent: only touches rows where announced_at IS NULL; safe to re-run.
-- Stamps historical rows at rolled_at so the first announcer cron run does
-- not burst-post history to #proactive-mode.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'd100_roll_log'
          AND column_name = 'announced_at'
    ) THEN
        ALTER TABLE d100_roll_log ADD COLUMN announced_at timestamptz;
    END IF;
END $$;

UPDATE d100_roll_log
SET announced_at = rolled_at
WHERE announced_at IS NULL;
