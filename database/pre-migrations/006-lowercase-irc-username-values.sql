-- pre-migration 006: Lowercase existing irc_username fact values
-- Issue #522
--
-- The new IRC entity resolver composes lowercased `<network>/<nick>` values
-- (e.g. `late.sh/druidian`). Existing production rows such as entity_facts
-- id=26989 store the mixed-case value `late.sh/Druidian`. This migration
-- normalizes all `irc_username` fact values to lowercase so exact-match
-- resolution works immediately after deploy.
--
-- Run as: nova (table owner)
-- Idempotent: only touches rows where key = 'irc_username' and value
-- differs from lower(value); safe to re-run.
--
-- nova-mind#662: pre-migrations run BEFORE the base schema apply, so on a
-- fresh (first-install) DB entity_facts does not exist yet -- the UPDATE
-- below would fail with "relation does not exist". Guarded with
-- to_regclass so this cleanly no-ops on first install (the table gets
-- created empty later by the base schema apply, so there is nothing to
-- normalize anyway) and still runs its intended work on an upgrade where
-- the table already exists.

DO $$
BEGIN
    IF to_regclass('public.entity_facts') IS NOT NULL THEN
        UPDATE entity_facts
        SET value = lower(value)
        WHERE key = 'irc_username'
          AND value != lower(value);
    END IF;
END $$;
