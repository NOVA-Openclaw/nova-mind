-- Migration: Consolidate Bootstrap Context into Agents Table
-- Issue #53: Move from bootstrap_context_agents table to agents.bootstrap_context column
--
-- IMPORTANT: This migration renames seed_context -> bootstrap_context
-- and updates all functions to read from agents table instead of bootstrap_context_agents.
--
-- DO NOT DROP OLD TABLES YET - they remain for backward compatibility/rollback

BEGIN;

-- Step 1: Rename seed_context column to bootstrap_context (idempotent)
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'agents' AND column_name = 'seed_context'
    ) THEN
        ALTER TABLE agents RENAME COLUMN seed_context TO bootstrap_context;
        RAISE NOTICE 'Renamed seed_context to bootstrap_context';
    ELSE
        RAISE NOTICE 'Column seed_context does not exist (already migrated or never existed)';
    END IF;
END $$;

-- Step 2: Update get_agent_bootstrap() to query agents.bootstrap_context
-- This function now returns context from three sources:
--   1. agents.bootstrap_context (agent-specific, highest priority)
--   2. bootstrap_context_universal (universal context, medium priority)  
--   3. workflows.description via workflow_steps (workflow context, if applicable)
CREATE OR REPLACE FUNCTION get_agent_bootstrap(p_agent_name TEXT)
RETURNS TABLE (
    filename TEXT,
    content TEXT,
    source TEXT  -- 'agent', 'universal', or 'workflow'
) AS $$
DECLARE
    v_agent_id INTEGER;
BEGIN
    -- Get agent ID
    SELECT id INTO v_agent_id FROM agents WHERE name = p_agent_name;
    
    RETURN QUERY
    SELECT DISTINCT ON (subq.filename)
        subq.filename,
        subq.content,
        subq.source
    FROM (
        -- 1. Agent-specific context from agents.bootstrap_context JSONB (highest priority)
        SELECT 
            kv.key || '.md' as filename,
            kv.value as content,
            'agent'::TEXT as source,
            1 as priority
        FROM agents a
        CROSS JOIN LATERAL jsonb_each_text(COALESCE(a.bootstrap_context, '{}'::jsonb)) AS kv
        WHERE a.name = p_agent_name
            AND (SELECT value::boolean FROM bootstrap_context_config WHERE key = 'enabled')
        
        UNION ALL
        
        -- 2. Workflow context (medium priority)
        -- Include workflow description as WORKFLOW_CONTEXT.md for agents in workflows
        (SELECT 
            'WORKFLOW_CONTEXT.md' as filename,
            'Workflow: ' || w.name || E'\n\n' || w.description as content,
            'workflow'::TEXT as source,
            2 as priority
        FROM workflow_steps ws
        JOIN workflows w ON ws.workflow_id = w.id
        WHERE ws.agent_id = v_agent_id
            AND w.status = 'active'
            AND (SELECT value::boolean FROM bootstrap_context_config WHERE key = 'enabled')
        LIMIT 1)
        
        UNION ALL
        
        -- 3. Universal context files (lowest priority)
        SELECT 
            file_key || '.md' as filename,
            u.content,
            'universal'::TEXT as source,
            3 as priority
        FROM bootstrap_context_universal u
        WHERE (SELECT value::boolean FROM bootstrap_context_config WHERE key = 'enabled')
    ) subq
    ORDER BY subq.filename, subq.priority;
END;
$$ LANGUAGE plpgsql;

-- Step 3: Update update_agent_context() to modify agents.bootstrap_context JSONB
CREATE OR REPLACE FUNCTION update_agent_context(
    p_agent_name TEXT,
    p_file_key TEXT,
    p_content TEXT,
    p_description TEXT DEFAULT NULL,  -- Ignored, kept for API compatibility
    p_updated_by TEXT DEFAULT 'system'  -- Ignored, kept for API compatibility
) RETURNS INTEGER AS $$
DECLARE
    v_agent_id INTEGER;
    v_max_size INTEGER;
BEGIN
    -- Enforce max_file_size from config
    SELECT (value::text)::integer INTO v_max_size 
    FROM bootstrap_context_config 
    WHERE key = 'max_file_size';
    
    IF length(p_content) > v_max_size THEN
        RAISE EXCEPTION 'Content size (% chars) exceeds maximum allowed size (% chars)', 
            length(p_content), v_max_size;
    END IF;
    
    -- Update agents.bootstrap_context JSONB column
    UPDATE agents
    SET bootstrap_context = COALESCE(bootstrap_context, '{}'::jsonb) || 
                           jsonb_build_object(p_file_key, p_content),
        updated_at = NOW()
    WHERE name = p_agent_name
    RETURNING id INTO v_agent_id;
    
    IF v_agent_id IS NULL THEN
        RAISE EXCEPTION 'Agent not found: %', p_agent_name;
    END IF;
    
    RETURN v_agent_id;
END;
$$ LANGUAGE plpgsql;

-- Step 4: Update delete_agent_context() to remove key from agents.bootstrap_context
CREATE OR REPLACE FUNCTION delete_agent_context(p_agent_name TEXT, p_file_key TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    v_updated INTEGER;
BEGIN
    UPDATE agents
    SET bootstrap_context = bootstrap_context - p_file_key,
        updated_at = NOW()
    WHERE name = p_agent_name
      AND bootstrap_context ? p_file_key;
    
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    RETURN v_updated > 0;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Update list_all_context() to query agents table
CREATE OR REPLACE FUNCTION list_all_context()
RETURNS TABLE (
    type TEXT,
    agent_name TEXT,
    file_key TEXT,
    content_length INTEGER,
    updated_at TIMESTAMPTZ,
    updated_by TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM (
        -- Universal context (unchanged)
        SELECT 
            'universal'::TEXT as type,
            NULL::TEXT as agent_name,
            u.file_key,
            length(u.content) as content_length,
            u.updated_at,
            u.updated_by
        FROM bootstrap_context_universal u
        
        UNION ALL
        
        -- Agent-specific context from agents.bootstrap_context JSONB
        SELECT 
            'agent'::TEXT as type,
            a.name as agent_name,
            kv.key as file_key,
            length(kv.value) as content_length,
            a.updated_at,
            'system'::TEXT as updated_by
        FROM agents a
        CROSS JOIN LATERAL jsonb_each_text(COALESCE(a.bootstrap_context, '{}'::jsonb)) AS kv
        WHERE a.bootstrap_context IS NOT NULL
    ) subq
    ORDER BY type, agent_name, file_key;
END;
$$ LANGUAGE plpgsql;

-- Step 6: Update copy_file_to_bootstrap() to write to agents.bootstrap_context
CREATE OR REPLACE FUNCTION copy_file_to_bootstrap(
    p_file_path TEXT,
    p_file_content TEXT,
    p_agent_name TEXT DEFAULT NULL,
    p_updated_by TEXT DEFAULT 'migration'
) RETURNS TEXT AS $$
DECLARE
    v_file_key TEXT;
    v_result TEXT;
BEGIN
    -- Extract file key from path (strip .md extension)
    v_file_key := upper(regexp_replace(
        regexp_replace(p_file_path, '^.*/([^/]+)\.md$', '\1'),
        '-', '_', 'g'
    ));
    
    -- Determine if universal or agent-specific
    IF p_agent_name IS NULL THEN
        -- Universal context (unchanged)
        PERFORM update_universal_context(
            v_file_key,
            p_file_content,
            'Migrated from ' || p_file_path,
            p_updated_by
        );
        v_result := 'universal:' || v_file_key;
    ELSE
        -- Agent-specific context - write to agents.bootstrap_context
        PERFORM update_agent_context(
            p_agent_name,
            v_file_key,
            p_file_content,
            'Migrated from ' || p_file_path,
            p_updated_by
        );
        v_result := p_agent_name || ':' || v_file_key;
    END IF;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Add helpful comments
COMMENT ON COLUMN agents.bootstrap_context IS 'Agent-specific bootstrap context files (JSONB map of file_key -> content). Replaces bootstrap_context_agents table.';
COMMENT ON FUNCTION get_agent_bootstrap IS 'Get all bootstrap files for an agent from agents.bootstrap_context + universal + workflow context';
COMMENT ON FUNCTION update_agent_context IS 'Update agent-specific context in agents.bootstrap_context JSONB column';
COMMENT ON FUNCTION delete_agent_context IS 'Delete a key from agents.bootstrap_context JSONB column';
COMMENT ON FUNCTION list_all_context IS 'List all context files from agents.bootstrap_context + universal sources';

COMMIT;

-- Verification queries (run these after migration)
-- SELECT name, bootstrap_context FROM agents WHERE bootstrap_context IS NOT NULL;
-- SELECT * FROM get_agent_bootstrap('coder');
-- SELECT * FROM list_all_context();
