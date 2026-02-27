-- Patch: Add edition/version support to library_works
-- Issue: NOVA-Openclaw/nova-memory#139
--
-- Adds:
-- 1. edition column (nullable text) for edition/version identifier
-- 2. embed column (boolean, default true) to control semantic embedding
--
-- Existing works are unaffected: edition=NULL, embed=true

BEGIN;

-- Add edition column (nullable — only set for works with editions)
ALTER TABLE library_works ADD COLUMN IF NOT EXISTS edition TEXT;

-- Add embed column (controls whether work is embedded for semantic recall)
-- Default true so existing works continue to be embedded
ALTER TABLE library_works ADD COLUMN IF NOT EXISTS embed BOOLEAN NOT NULL DEFAULT true;

-- Add index for embed filtering (used by embed-library.py)
CREATE INDEX IF NOT EXISTS idx_library_works_embed ON library_works (embed) WHERE embed = true;

-- Unique constraint: prevent duplicate title+edition combinations
CREATE UNIQUE INDEX IF NOT EXISTS idx_library_works_title_edition
ON library_works (LOWER(TRIM(title)), COALESCE(edition, ''));

COMMIT;
