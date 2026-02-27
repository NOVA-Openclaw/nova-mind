-- Bootstrap Context Database Schema
-- Stores agent bootstrap context files for automatic loading

-- Universal context (applies to all agents)
CREATE TABLE IF NOT EXISTS bootstrap_context_universal (
    id SERIAL PRIMARY KEY,
    file_key TEXT NOT NULL UNIQUE CHECK (file_key <> ''),  -- e.g., 'AGENTS', 'SOUL', 'TOOLS'
    content TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by TEXT  -- agent or user who made the change
);

-- Per-agent context (specific to individual agents)
CREATE TABLE IF NOT EXISTS bootstrap_context_agents (
    id SERIAL PRIMARY KEY,
    agent_name TEXT NOT NULL,  -- matches agents.name
    file_key TEXT NOT NULL CHECK (file_key <> ''),    -- e.g., 'SEED_CONTEXT', 'DOMAIN_KNOWLEDGE'
    content TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by TEXT,
    UNIQUE(agent_name, file_key)
);

-- Configuration for bootstrap behavior
CREATE TABLE IF NOT EXISTS bootstrap_context_config (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Audit log for context changes
CREATE TABLE IF NOT EXISTS bootstrap_context_audit (
    id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,  -- which table was modified
    record_id INTEGER,
    operation TEXT NOT NULL,  -- INSERT, UPDATE, DELETE
    old_content TEXT,
    new_content TEXT,
    changed_by TEXT,
    changed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_bootstrap_agents_name ON bootstrap_context_agents(agent_name);
CREATE INDEX IF NOT EXISTS idx_bootstrap_audit_table ON bootstrap_context_audit(table_name, changed_at);

-- Insert default configuration
INSERT INTO bootstrap_context_config (key, value, description) VALUES
('enabled', 'true'::jsonb, 'Master switch for database bootstrap loading'),
('fallback_enabled', 'true'::jsonb, 'Use file fallbacks if database query fails'),
('max_file_size', '20000'::jsonb, 'Maximum characters per file (matches OpenClaw default)')
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE bootstrap_context_universal IS 'Universal context files loaded for all agents (AGENTS.md, SOUL.md, etc.)';
COMMENT ON TABLE bootstrap_context_agents IS 'Per-agent context files (SEED_CONTEXT.md, domain knowledge)';
COMMENT ON TABLE bootstrap_context_config IS 'Configuration for bootstrap system behavior';
COMMENT ON TABLE bootstrap_context_audit IS 'Audit trail of all context modifications';
