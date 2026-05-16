-- Migration: Add parent_agent_id to agents table
-- Issue: #226
--
-- Enables subagent → parent agent resolution for source attribution
-- (subagent output → parent entity).

ALTER TABLE agents ADD COLUMN IF NOT EXISTS parent_agent_id INTEGER REFERENCES agents(id);

COMMENT ON COLUMN agents.parent_agent_id IS 'For subagents: the peer agent that owns this subagent. NULL for peer/primary agents. Used for source attribution (subagent output → parent entity).';

-- Populate: all current subagents belong to nova
UPDATE agents SET parent_agent_id = (SELECT id FROM agents WHERE name = 'nova' AND status = 'active')
WHERE instance_type = 'subagent' AND parent_agent_id IS NULL;
