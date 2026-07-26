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

UPDATE entity_facts
SET value = lower(value)
WHERE key = 'irc_username'
  AND value != lower(value);
