-- Migration: Add temporal validity (expires) to entity_facts
-- Issue: #139

-- Add expires column for temporal-boundary facts
ALTER TABLE entity_facts
    ADD COLUMN IF NOT EXISTS expires TIMESTAMPTZ;

-- expires is nullable (NULL means no expiration / permanent validity)
-- No default value — facts without temporal boundaries stay NULL
