-- Migration 080: Add alternate_spellings column to entities table
-- Issues: #267 (alternate_spellings for entity resolution)
--
-- Adds a nullable text[] column for storing alternate name spellings that
-- find_entity_id() will check when matching entities to avoid fragmentation.
-- Idempotent — safe to run multiple times.

ALTER TABLE entities ADD COLUMN IF NOT EXISTS alternate_spellings text[];

-- Index for fast ANY(unnest()) lookups
CREATE INDEX IF NOT EXISTS idx_entities_alternate_spellings_gin
    ON entities USING GIN (alternate_spellings);

-- No default, no NOT NULL — existing rows get NULL which is correct and
-- means "no alternate spellings" (handled in queries with COALESCE).
