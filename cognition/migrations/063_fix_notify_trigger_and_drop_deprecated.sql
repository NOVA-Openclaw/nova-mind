-- Migration 063: Fix notify trigger, drop deprecated tables
-- Issues: NOVA-Openclaw/nova-cognition#81, #99
--
-- Fixes applied:
-- 1. notify_workflow_step_change() referenced OLD.status and NEW.agent_id (neither exist)
-- 2. Drop deprecated bootstrap_context_* tables (replaced by agent_bootstrap_context)
-- 3. Drop agent_id from workflow_steps (step assignment is purely domain-based via agent_domains)

BEGIN;

-- 1. Fix notify_workflow_step_change() trigger function
-- Old version referenced OLD.status (no status column) and NEW.agent_id (column dropped)
CREATE OR REPLACE FUNCTION notify_workflow_step_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM pg_notify('workflow_step', json_build_object(
        'id', NEW.id,
        'workflow_id', NEW.workflow_id,
        'step_order', NEW.step_order,
        'description', NEW.description,
        'domain', NEW.domain
    )::text);
    RETURN NEW;
END;
$function$;

-- 2. Drop deprecated bootstrap context tables (superseded by agent_bootstrap_context)
-- These were the old multi-table design; all context now lives in agent_bootstrap_context.
DROP TABLE IF EXISTS bootstrap_context_audit CASCADE;
DROP TABLE IF EXISTS bootstrap_context_config CASCADE;
DROP TABLE IF EXISTS bootstrap_context_agents CASCADE;
DROP TABLE IF EXISTS bootstrap_context_universal CASCADE;

-- Drop functions that operated on the deprecated tables
DROP FUNCTION IF EXISTS update_universal_context(text, text, text, text);
DROP FUNCTION IF EXISTS delete_universal_context(text);
DROP FUNCTION IF EXISTS update_agent_context(text, text, text, text, text);
DROP FUNCTION IF EXISTS delete_agent_context(text, text);
DROP FUNCTION IF EXISTS list_all_context();
DROP FUNCTION IF EXISTS get_bootstrap_config();
DROP FUNCTION IF EXISTS audit_bootstrap_universal();
DROP FUNCTION IF EXISTS audit_bootstrap_agents();
DROP FUNCTION IF EXISTS audit_bootstrap_context_change();

-- 3. Drop agent_id from workflow_steps if it still exists
-- Step assignment is now purely domain-based via agent_domains table.
-- The get_agent_bootstrap() function matches workflows by domain overlap,
-- not by agent_id assignment.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'workflow_steps' AND column_name = 'agent_id'
    ) THEN
        ALTER TABLE workflow_steps DROP CONSTRAINT IF EXISTS workflow_steps_agent_id_fkey;
        DROP INDEX IF EXISTS idx_workflow_steps_agent;
        ALTER TABLE workflow_steps DROP COLUMN agent_id;
    END IF;
END $$;

COMMIT;
