-- Migration: Replace data_type with durability + category
-- Issue: #167
-- Phases: ADD → MIGRATE → DROP

-- ── ADD phase ────────────────────────────────────────────────────────────────
ALTER TABLE entity_facts
    ADD COLUMN IF NOT EXISTS durability VARCHAR(20) NOT NULL DEFAULT 'long_term',
    ADD COLUMN IF NOT EXISTS category    TEXT        NOT NULL DEFAULT 'observation';

-- CHECK constraint for durability values
ALTER TABLE entity_facts
    DROP CONSTRAINT IF EXISTS chk_durability;

ALTER TABLE entity_facts
    ADD CONSTRAINT chk_durability
    CHECK (durability IN ('permanent', 'long_term', 'short_term', 'ephemeral'));

-- ── MIGRATE phase ────────────────────────────────────────────────────────────
-- Map old data_type values to new durability + category pairs
UPDATE entity_facts
SET durability = 'permanent',
    category   = 'identity'
WHERE data_type = 'permanent';

UPDATE entity_facts
SET durability = 'permanent',
    category   = 'identity'
WHERE data_type = 'identity';

UPDATE entity_facts
SET durability = 'long_term',
    category   = 'preference'
WHERE data_type = 'preference';

UPDATE entity_facts
SET durability = 'long_term',
    category   = 'observation'
WHERE data_type = 'observation';

-- Any remaining unmapped rows get safe defaults
UPDATE entity_facts
SET durability = 'long_term',
    category   = 'observation'
WHERE durability IS NULL OR category IS NULL;

-- ── VERIFY phase ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM entity_facts WHERE durability IS NULL OR category IS NULL) THEN
        RAISE EXCEPTION 'Migration 070 VERIFY failed: NULL durability or category values remain';
    END IF;
END $$;

-- ── DROP phase ───────────────────────────────────────────────────────────────
-- Recreate dependent view without data_type before dropping the column
DROP VIEW IF EXISTS delegation_knowledge;
CREATE OR REPLACE VIEW delegation_knowledge AS
 SELECT id,
    key,
    value,
    confidence,
    durability,
    learned_at,
    updated_at
   FROM entity_facts ef
  WHERE entity_id = 1 AND (key::text = ANY (ARRAY['delegates_to'::character varying::text, 'task_delegation'::character varying::text, 'agent_capability'::character varying::text, 'agent_success'::character varying::text, 'agent_failure'::character varying::text]))
  ORDER BY (
        CASE key
            WHEN 'delegates_to'::text THEN 1
            WHEN 'task_delegation'::text THEN 2
            WHEN 'agent_capability'::text THEN 3
            WHEN 'agent_success'::text THEN 4
            WHEN 'agent_failure'::text THEN 5
            ELSE 6
        END), confidence DESC, value;

ALTER TABLE entity_facts
    DROP COLUMN IF EXISTS data_type;

ALTER TABLE entity_facts
    DROP CONSTRAINT IF EXISTS chk_data_type;

-- Replace old index with new ones
DROP INDEX IF EXISTS idx_entity_facts_data_type;
CREATE INDEX IF NOT EXISTS idx_entity_facts_durability ON entity_facts (durability);
CREATE INDEX IF NOT EXISTS idx_entity_facts_category   ON entity_facts (category);
