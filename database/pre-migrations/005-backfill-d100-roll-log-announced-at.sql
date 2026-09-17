-- pre-migration 005: Backfill d100_roll_log.announced_at for historical rows
-- Issue #432
--
-- Run as: nova (table owner)
-- Idempotent: only touches rows where announced_at IS NULL; safe to re-run.
-- Stamps historical rows at rolled_at so the first announcer cron run does
-- not burst-post history to #proactive-mode.
--
-- nova-mind#662: pre-migrations run BEFORE the base schema apply, so on a
-- fresh (first-install) DB d100_roll_log does not exist yet -- ALTER TABLE
-- and UPDATE below would both fail with "relation does not exist". Guarded
-- with to_regclass so this cleanly no-ops on first install (the table gets
-- created empty later by the base schema apply, so there is nothing to
-- backfill anyway) and still runs its intended work on an upgrade where the
-- table already exists.

DO $$
BEGIN
    IF to_regclass('public.d100_roll_log') IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'd100_roll_log'
              AND column_name = 'announced_at'
        ) THEN
            ALTER TABLE d100_roll_log ADD COLUMN announced_at timestamptz;
        END IF;

        UPDATE d100_roll_log
        SET announced_at = rolled_at
        WHERE announced_at IS NULL;
    END IF;
END $$;
