-- Migration: Consolidate vote_count + confirmation_count into extraction_count
-- Issue: #190
-- Phases: ADD → MIGRATE → VERIFY → DROP

-- ── ADD phase ────────────────────────────────────────────────────────────────
-- Add the new column with sensible default
ALTER TABLE entity_facts
    ADD COLUMN IF NOT EXISTS extraction_count INTEGER DEFAULT 1;

-- Backfill from legacy columns (safe even if they don't exist yet in this txn)
UPDATE entity_facts
SET extraction_count = COALESCE(GREATEST(vote_count, confirmation_count), 1)
WHERE extraction_count IS NULL
  AND vote_count IS NOT NULL
  AND confirmation_count IS NOT NULL;

-- For rows where one of the legacy counts is NULL but the other isn't
UPDATE entity_facts
SET extraction_count = COALESCE(GREATEST(vote_count, confirmation_count), 1)
WHERE extraction_count IS NULL;

-- Ensure no NULLs remain
UPDATE entity_facts
SET extraction_count = 1
WHERE extraction_count IS NULL;

-- ── MIGRATE phase ────────────────────────────────────────────────────────────
-- (Data already migrated in ADD phase above)

-- ── VERIFY phase ─────────────────────────────────────────────────────────────
-- Assert zero NULLs in extraction_count
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM entity_facts WHERE extraction_count IS NULL) THEN
        RAISE EXCEPTION 'Migration 068 VERIFY failed: NULL extraction_count values remain';
    END IF;
END $$;

-- ── DROP phase ───────────────────────────────────────────────────────────────
-- Remove legacy columns and their index
ALTER TABLE entity_facts
    DROP COLUMN IF EXISTS vote_count,
    DROP COLUMN IF EXISTS confirmation_count,
    DROP COLUMN IF EXISTS last_confirmed;  -- no-tz duplicate of last_confirmed_at

DROP INDEX IF EXISTS idx_entity_facts_vote_count;
