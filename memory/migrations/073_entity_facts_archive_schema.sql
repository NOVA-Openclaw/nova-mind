-- Migration: Update entity_facts_archive to match new entity_facts schema
-- Issue: #190, #167, #204 (archive table alignment)

-- Drop legacy columns from archive table (data preserved in archived rows is historical)
ALTER TABLE entity_facts_archive
    DROP COLUMN IF EXISTS vote_count,
    DROP COLUMN IF EXISTS last_confirmed,
    DROP COLUMN IF EXISTS data_type,
    DROP COLUMN IF EXISTS confirmation_count,
    DROP COLUMN IF EXISTS source,
    DROP COLUMN IF EXISTS source_entity_id;

-- Add new columns to archive table
ALTER TABLE entity_facts_archive
    ADD COLUMN IF NOT EXISTS extraction_count INTEGER DEFAULT 1,
    ADD COLUMN IF NOT EXISTS durability VARCHAR(20) DEFAULT 'long_term',
    ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'observation',
    ADD COLUMN IF NOT EXISTS expires TIMESTAMPTZ;
