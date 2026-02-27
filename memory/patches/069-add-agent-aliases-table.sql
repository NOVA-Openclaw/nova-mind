-- Migration for Issue #69: Add agent_aliases table for case-insensitive agent matching
-- This allows agents to be matched by multiple identifiers (name, aliases) case-insensitively

-- Create agent_aliases table
CREATE TABLE IF NOT EXISTS agent_aliases (
    agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    alias VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (agent_id, alias)
);

-- Add index for fast lookup by alias (case-insensitive)
CREATE INDEX IF NOT EXISTS idx_agent_aliases_alias_lower ON agent_aliases (LOWER(alias));

-- Add comment
COMMENT ON TABLE agent_aliases IS 'Agent aliases for flexible mention matching. Supports case-insensitive routing.';
COMMENT ON COLUMN agent_aliases.alias IS 'Alternative name/identifier for the agent (e.g., "assistant", "helper")';

-- Optional: Seed some example aliases if needed
-- INSERT INTO agent_aliases (agent_id, alias) 
-- SELECT id, nickname FROM agents WHERE nickname IS NOT NULL
-- ON CONFLICT DO NOTHING;
