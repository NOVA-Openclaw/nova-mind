-- Migration 075: Add entity_id FK column to agents table
-- Issue #234

-- 1. Add nullable entity_id column with FK to entities(id)
ALTER TABLE agents ADD COLUMN IF NOT EXISTS entity_id INTEGER REFERENCES entities(id);

-- 2. Populate entity_id for agents whose name matches an entity of type 'ai'
UPDATE agents
SET entity_id = e.id
FROM entities e
WHERE e.name = agents.name
  AND e.type = 'ai'
  AND agents.entity_id IS NULL;

-- 3. Add index for fast lookups
CREATE INDEX IF NOT EXISTS idx_agents_entity_id ON agents(entity_id);
