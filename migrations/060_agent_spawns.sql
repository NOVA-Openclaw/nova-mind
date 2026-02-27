-- Migration: 060_agent_spawns.sql
-- Purpose: Tracking table for agent spawns and notify triggers
-- Issue: nova-cognition#68

-- Agent spawn tracking table
CREATE TABLE IF NOT EXISTS agent_spawns (
    id SERIAL PRIMARY KEY,
    trigger_source TEXT NOT NULL,           -- 'agent_chat', 'workflow_step', 'task', 'manual'
    trigger_id TEXT,                        -- source record id (chat id, step id, etc.)
    trigger_payload JSONB,                  -- original notification payload
    domain TEXT,                            -- resolved domain
    agent_id INTEGER REFERENCES agents(id),
    agent_name TEXT,                        -- denormalized for easy querying
    session_key TEXT,                       -- OpenClaw session key
    session_label TEXT,                     -- Human-readable label
    task_summary TEXT,                      -- Brief description of spawned task
    status TEXT DEFAULT 'pending',          -- pending, spawning, running, completed, failed
    spawned_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    result JSONB,                           -- completion result/error
    CONSTRAINT valid_status CHECK (status IN ('pending', 'spawning', 'running', 'completed', 'failed', 'skipped'))
);

-- Index for status queries
CREATE INDEX IF NOT EXISTS idx_agent_spawns_status ON agent_spawns(status);
CREATE INDEX IF NOT EXISTS idx_agent_spawns_agent ON agent_spawns(agent_id);
CREATE INDEX IF NOT EXISTS idx_agent_spawns_domain ON agent_spawns(domain);
CREATE INDEX IF NOT EXISTS idx_agent_spawns_trigger ON agent_spawns(trigger_source, trigger_id);

-- Add domain column to workflow_steps if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'workflow_steps' AND column_name = 'domain'
    ) THEN
        ALTER TABLE workflow_steps ADD COLUMN domain TEXT;
        COMMENT ON COLUMN workflow_steps.domain IS 'Subject-matter domain for agent routing (e.g., sql/database, python/daemon)';
    END IF;
END $$;

-- Notify trigger for workflow_step status changes
CREATE OR REPLACE FUNCTION notify_workflow_step_change() RETURNS TRIGGER AS $$
BEGIN
    -- Only notify on status changes that might need agent action
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        PERFORM pg_notify('workflow_step', json_build_object(
            'id', NEW.id,
            'workflow_id', NEW.workflow_id,
            'step_number', NEW.step_number,
            'name', NEW.name,
            'old_status', OLD.status,
            'new_status', NEW.status,
            'domain', NEW.domain,
            'assigned_agent', NEW.assigned_agent
        )::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger if not exists
DROP TRIGGER IF EXISTS workflow_step_change_trigger ON workflow_steps;
CREATE TRIGGER workflow_step_change_trigger
    AFTER UPDATE ON workflow_steps
    FOR EACH ROW
    EXECUTE FUNCTION notify_workflow_step_change();

-- View for spawn statistics
CREATE OR REPLACE VIEW v_agent_spawn_stats AS
SELECT 
    agent_name,
    domain,
    COUNT(*) as total_spawns,
    COUNT(*) FILTER (WHERE status = 'completed') as completed,
    COUNT(*) FILTER (WHERE status = 'failed') as failed,
    COUNT(*) FILTER (WHERE status IN ('pending', 'spawning', 'running')) as active,
    AVG(EXTRACT(EPOCH FROM (completed_at - spawned_at))) FILTER (WHERE completed_at IS NOT NULL) as avg_duration_seconds
FROM agent_spawns
GROUP BY agent_name, domain;

COMMENT ON TABLE agent_spawns IS 'Tracks all agent spawns from the general-purpose spawner daemon';
