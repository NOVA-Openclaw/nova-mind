-- MANUAL-007: Drop deprecated public.agent_bootstrap_context_local table
-- SE Run #866 / nova-mind#498 (manual migration; NOT run by the installer)
--
-- This is a DELIBERATE DESTRUCTIVE migration. It must be run manually by a
-- DBA/agent only after confirming the table is truly unused. The installer is
-- additive-by-construction (#498) and never applies destructive schema changes
-- automatically.
--
-- Guards:
--   1. to_regclass existence check — no-op if the table was already dropped.
--   2. Rowcount emptiness guard — REFUSES to drop if the table contains rows,
--      preventing data loss on agents (e.g. Victoria) that still have live
--      data in this table.
--
-- Run manually as the table owner (typically nova) when both guards pass:
--   psql -U nova -d <database> -f database/manual-migrations/MANUAL-007-drop-agent-bootstrap-context-local.sql

DO $$
DECLARE
    row_count bigint;
BEGIN
    IF to_regclass('public.agent_bootstrap_context_local') IS NULL THEN
        RAISE NOTICE 'Table public.agent_bootstrap_context_local does not exist; nothing to do.';
        RETURN;
    END IF;

    EXECUTE 'SELECT COUNT(*) FROM public.agent_bootstrap_context_local' INTO row_count;

    IF row_count > 0 THEN
        RAISE EXCEPTION
            'Refusing to drop public.agent_bootstrap_context_local because it contains % rows. '
            'Migrate or truncate the data first, then re-run this script.',
            row_count;
    END IF;

    DROP TABLE IF EXISTS public.agent_bootstrap_context_local;
    RAISE NOTICE 'Dropped empty public.agent_bootstrap_context_local table.';
END $$;
