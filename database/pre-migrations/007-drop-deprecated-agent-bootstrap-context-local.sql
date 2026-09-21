-- pre-migration 007: Drop deprecated public.agent_bootstrap_context_local table
-- SE Run #866 / nova-mind#660 (unblocks schema apply; references #371/#574/#498)
--
-- This table is no longer defined in database/schema.sql, has zero FK references,
-- and was already dropped from production. Removing it from upgrade targets moves
-- the destructive DROP out of pgschema's plan so the additive CREATEs for
-- work_queue, agent_model_denylists, and social_interactions are no longer
-- collateral-skipped.
--
-- Run as: nova (table owner)
-- Idempotent: IF EXISTS guard prevents errors on repeat runs; DO-block
-- to_regclass check no-ops on first install where the table never existed.
--
-- nova-mind#662: pre-migrations run BEFORE the base schema apply, so on a
-- fresh (first-install) DB the relation does not exist yet. Guarded with
-- to_regclass so this cleanly no-ops on first install.

DO $$
BEGIN
    IF to_regclass('public.agent_bootstrap_context_local') IS NOT NULL THEN
        DROP TABLE IF EXISTS agent_bootstrap_context_local;
    END IF;
END $$;
