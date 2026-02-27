-- Migration: Issue #163 — Sync system-wide subagent config from agent_system_config to agents.json
--
-- Creates a PostgreSQL trigger that fires pg_notify on changes to agent_system_config,
-- reusing the existing 'agent_config_changed' channel so the agent-config-sync plugin
-- picks up changes without any index.ts modifications.
--
-- Also seeds initial default values (idempotent: ON CONFLICT DO NOTHING).

-- ── Trigger function ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION notify_system_config_changed()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM pg_notify('agent_config_changed', json_build_object(
            'source', 'agent_system_config',
            'key', OLD.key,
            'operation', TG_OP
        )::text);
        RETURN OLD;
    END IF;

    PERFORM pg_notify('agent_config_changed', json_build_object(
        'source', 'agent_system_config',
        'key', NEW.key,
        'operation', TG_OP
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── Trigger on agent_system_config ──────────────────────────────────────────

-- Drop and recreate for idempotency
DROP TRIGGER IF EXISTS system_config_changed ON agent_system_config;
CREATE TRIGGER system_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agent_system_config
    FOR EACH ROW EXECUTE FUNCTION notify_system_config_changed();

-- ── Seed data ───────────────────────────────────────────────────────────────

-- Seed max_spawn_depth = 5 (OpenClaw's maximum valid value for nested subagent chains)
-- ON CONFLICT DO NOTHING ensures existing custom values are never overwritten.
INSERT INTO agent_system_config (key, value, value_type)
VALUES ('max_spawn_depth', '5', 'integer')
ON CONFLICT (key) DO NOTHING;
