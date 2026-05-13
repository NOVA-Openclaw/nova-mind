-- Migration: Extract source attribution into entity_fact_sources table
-- Issue: #204
-- Phases: ADD → MIGRATE → DROP

-- ── ADD phase ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS entity_fact_sources (
    id                SERIAL PRIMARY KEY,
    fact_id           INTEGER NOT NULL REFERENCES entity_facts(id) ON DELETE CASCADE,
    source_entity_id  INTEGER NOT NULL REFERENCES entities(id),
    source_citation   TEXT,
    attribution_count INTEGER DEFAULT 1,
    first_seen        TIMESTAMPTZ DEFAULT now(),
    last_seen         TIMESTAMPTZ DEFAULT now(),

    -- Unique constraint: one source-entity per fact
    CONSTRAINT uq_fact_source UNIQUE (fact_id, source_entity_id)
);

-- Indexes for common lookups
CREATE INDEX IF NOT EXISTS idx_efs_fact_id          ON entity_fact_sources (fact_id);
CREATE INDEX IF NOT EXISTS idx_efs_source_entity_id ON entity_fact_sources (source_entity_id);

-- ── MIGRATE phase ────────────────────────────────────────────────────────────
-- Migrate facts that have a source_entity_id directly
INSERT INTO entity_fact_sources (fact_id, source_entity_id, attribution_count, first_seen, last_seen)
SELECT
    id,
    source_entity_id,
    COALESCE(extraction_count, 1),
    COALESCE(last_confirmed_at, learned_at, NOW()),
    COALESCE(last_confirmed_at, learned_at, NOW())
FROM entity_facts
WHERE source_entity_id IS NOT NULL
ON CONFLICT (fact_id, source_entity_id) DO NOTHING;

-- Migrate facts that have source text but no source_entity_id:
-- Attempt to resolve source text to an entity by name match.
-- If no match, attribute to NOVA (entity_id=1) as system source.
DO $$
DECLARE
    rec RECORD;
    resolved_entity_id INTEGER;
BEGIN
    FOR rec IN
        SELECT id, source, learned_at, last_confirmed_at, extraction_count
        FROM entity_facts
        WHERE source_entity_id IS NULL
          AND source IS NOT NULL
          AND source != ''
          AND source != 'auto-extracted'
    LOOP
        -- Try to resolve source text to entity name
        SELECT e.id INTO resolved_entity_id
        FROM entities e
        WHERE LOWER(e.name) = LOWER(rec.source)
           OR LOWER(e.full_name) = LOWER(rec.source)
           OR LOWER(rec.source) = ANY(SELECT LOWER(unnest(e.nicknames)))
        LIMIT 1;

        IF resolved_entity_id IS NULL THEN
            -- Fall back to NOVA system entity (id=1)
            resolved_entity_id := 1;
        END IF;

        INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen)
        VALUES (
            rec.id,
            resolved_entity_id,
            rec.source,
            COALESCE(rec.extraction_count, 1),
            COALESCE(rec.last_confirmed_at, rec.learned_at, NOW()),
            COALESCE(rec.last_confirmed_at, rec.learned_at, NOW())
        )
        ON CONFLICT (fact_id, source_entity_id) DO NOTHING;
    END LOOP;
END $$;

-- For facts with BOTH source=NULL AND source_entity_id=NULL,
-- attribute to NOVA (entity_id=1) so every fact has a source trail.
INSERT INTO entity_fact_sources (fact_id, source_entity_id, attribution_count, first_seen, last_seen)
SELECT
    id,
    1,  -- NOVA system entity
    COALESCE(extraction_count, 1),
    COALESCE(last_confirmed_at, learned_at, NOW()),
    COALESCE(last_confirmed_at, learned_at, NOW())
FROM entity_facts
WHERE source_entity_id IS NULL
  AND (source IS NULL OR source = '' OR source = 'auto-extracted')
ON CONFLICT (fact_id, source_entity_id) DO NOTHING;

-- ── VERIFY phase ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    orphan_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO orphan_count
    FROM entity_facts ef
    WHERE NOT EXISTS (SELECT 1 FROM entity_fact_sources efs WHERE efs.fact_id = ef.id);

    IF orphan_count > 0 THEN
        RAISE EXCEPTION 'Migration 071 VERIFY failed: % facts without source attribution', orphan_count;
    END IF;
END $$;

-- ── DROP phase ───────────────────────────────────────────────────────────────
-- Recreate dependent view without source before dropping the column
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
    DROP COLUMN IF EXISTS source,
    DROP COLUMN IF EXISTS source_entity_id;

DROP INDEX IF EXISTS idx_entity_facts_source_entity;
