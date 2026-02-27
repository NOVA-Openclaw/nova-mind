-- Issue #59: Domain-based bootstrap context architecture
-- Replaces per-agent bootstrap_context with GLOBAL + DOMAIN additive contexts
-- Migration date: 2026-02-12

BEGIN;

-- ============================================================================
-- 1. Create new agent_bootstrap_context table (GLOBAL + DOMAIN context)
-- ============================================================================
CREATE TABLE IF NOT EXISTS agent_bootstrap_context (
    id SERIAL PRIMARY KEY,
    context_type TEXT NOT NULL CHECK (context_type IN ('GLOBAL', 'DOMAIN')),
    domain_name TEXT,                     -- NULL for GLOBAL, domain name for DOMAIN
    file_key TEXT NOT NULL,               -- e.g., 'CODING_PRACTICES', 'SECURITY_GUIDELINES'
    content TEXT NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by TEXT DEFAULT 'system'
);

-- Unique index handling NULL domain_name correctly
CREATE UNIQUE INDEX IF NOT EXISTS agent_bootstrap_context_unique_idx 
ON agent_bootstrap_context (context_type, COALESCE(domain_name, ''), file_key);

COMMENT ON TABLE agent_bootstrap_context IS 'Domain-based bootstrap context. GLOBAL entries apply to all agents, DOMAIN entries apply to agents in that domain.';
COMMENT ON COLUMN agent_bootstrap_context.context_type IS 'GLOBAL (all agents) or DOMAIN (agents in specific domain)';
COMMENT ON COLUMN agent_bootstrap_context.domain_name IS 'NULL for GLOBAL, domain name from agent_domains for DOMAIN type';
COMMENT ON COLUMN agent_bootstrap_context.file_key IS 'Identifier for context block, becomes filename in bootstrap';

-- ============================================================================
-- 2. Rename bootstrap_context_universal → agent_bootstrap_context_universal
-- ============================================================================
ALTER TABLE IF EXISTS bootstrap_context_universal 
    RENAME TO agent_bootstrap_context_universal;

COMMENT ON TABLE agent_bootstrap_context_universal IS 'Workspace files loaded into all agent contexts (AGENTS.md, SOUL.md, etc.)';

-- ============================================================================
-- 3. Seed initial GLOBAL context
-- ============================================================================
INSERT INTO agent_bootstrap_context (context_type, domain_name, file_key, content, description, updated_by)
VALUES 
    ('GLOBAL', NULL, 'SYSTEM_CONTEXT', 
     E'# System Context\n\nYou are part of the NOVA agent ecosystem. All agents share:\n- Access to nova_memory database\n- SE (Software Engineering) workflow for code changes\n- Memory search via semantic recall\n\n## Communication\n- Use agent_chat table for peer-to-peer messaging\n- Spawn subagents via sessions_spawn for delegated work\n- Document decisions in memory files',
     'Universal system context for all agents', 'nova'),
    ('GLOBAL', NULL, 'COORDINATION_RULES',
     E'# Coordination Rules\n\n- Check if task is already in progress before starting\n- Use SE workflow for ALL source code changes\n- Document blockers and handoffs clearly\n- Respect agent specializations - delegate appropriately',
     'Rules for multi-agent coordination', 'nova')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 4. Seed initial DOMAIN context (from existing agent bootstrap_context)
-- ============================================================================

-- Software Engineering domain (from Coder-type agents)
INSERT INTO agent_bootstrap_context (context_type, domain_name, file_key, content, description, updated_by)
VALUES 
    ('DOMAIN', 'Software Engineering', 'CODING_PRACTICES',
     E'# Software Engineering Practices\n\n## Code Quality\n- Write tests for new functionality\n- Follow existing code style\n- Keep functions small and focused\n\n## Git Workflow\n- Use feature branches\n- Write meaningful commit messages\n- Push changes to trigger CI',
     'Coding standards and practices', 'nova'),
    ('DOMAIN', 'Software Engineering', 'SE_WORKFLOW',
     E'# SE Workflow\n\n1. Issues created in GitHub trigger SE workflow\n2. Gem generates test cases\n3. Implementation by specialist (Coder/Newhart/Scribe)\n4. Tests verified before merge\n5. Gidget syncs schema changes to git',
     'Software Engineering workflow reference', 'nova')
ON CONFLICT DO NOTHING;

-- Systems Administration domain
INSERT INTO agent_bootstrap_context (context_type, domain_name, file_key, content, description, updated_by)
VALUES 
    ('DOMAIN', 'Systems Administration', 'SYSADMIN_CONTEXT',
     E'# Systems Administration Context\n\n## Principles\n- Prefer native installs over Docker (project decision)\n- Document all config changes\n- Test in non-production first when possible\n\n## Key Services\n- PostgreSQL: nova_memory database\n- OpenProject: https://openproject.nova.dustintrammell.com\n- OpenClaw: Gateway on multiple ports',
     'Systems administration context and principles', 'nova')
ON CONFLICT DO NOTHING;

-- Technical Writing domain
INSERT INTO agent_bootstrap_context (context_type, domain_name, file_key, content, description, updated_by)
VALUES 
    ('DOMAIN', 'Technical Writing', 'DOCUMENTATION_STANDARDS',
     E'# Documentation Standards\n\n## Style\n- Use proper noun capitalization for Subject Matter Domains\n- Keep README files current\n- Document API changes in CHANGELOG\n\n## Locations\n- User docs: docs/ directory\n- API docs: inline + generated\n- Architecture: ARCHITECTURE.md or docs/architecture/',
     'Documentation and writing standards', 'nova')
ON CONFLICT DO NOTHING;

-- Version Control domain  
INSERT INTO agent_bootstrap_context (context_type, domain_name, file_key, content, description, updated_by)
VALUES 
    ('DOMAIN', 'Version Control', 'GIT_OPERATIONS',
     E'# Git Operations Context\n\n## Schema Sync\n- Export database schema to git after DDL changes\n- Use pg_dump with clean formatting\n- Commit with descriptive messages\n\n## Repositories\n- nova-cognition: Database schemas, migrations\n- nova-dashboard: Web UI\n- openclaw: Core agent runtime',
     'Git and version control operations', 'nova')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 5. Update get_agent_bootstrap() function for new architecture
-- ============================================================================
CREATE OR REPLACE FUNCTION get_agent_bootstrap(p_agent_name TEXT)
RETURNS TABLE(filename TEXT, content TEXT, source TEXT)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_agent_id INTEGER;
    v_enabled BOOLEAN;
BEGIN
    -- Check if bootstrap context is enabled
    SELECT value::boolean INTO v_enabled 
    FROM bootstrap_context_config 
    WHERE key = 'enabled';
    
    IF NOT COALESCE(v_enabled, true) THEN
        RETURN;
    END IF;
    
    -- Get agent ID
    SELECT id INTO v_agent_id FROM agents WHERE name = p_agent_name;
    
    RETURN QUERY
    SELECT DISTINCT ON (subq.filename)
        subq.filename,
        subq.content,
        subq.source
    FROM (
        -- 1. Universal workspace files (highest priority)
        SELECT 
            u.file_key || '.md' as filename,
            u.content,
            'universal'::TEXT as source,
            1 as priority
        FROM agent_bootstrap_context_universal u
        
        UNION ALL
        
        -- 2. GLOBAL context (applies to all agents)
        SELECT 
            bc.file_key || '.md' as filename,
            bc.content,
            'global'::TEXT as source,
            2 as priority
        FROM agent_bootstrap_context bc
        WHERE bc.context_type = 'GLOBAL'
        
        UNION ALL
        
        -- 3. DOMAIN context (for each domain the agent is assigned to)
        SELECT 
            bc.file_key || '.md' as filename,
            bc.content,
            'domain:' || bc.domain_name as source,
            3 as priority
        FROM agent_bootstrap_context bc
        JOIN agent_domains ad ON bc.domain_name = ad.domain_topic
        WHERE bc.context_type = 'DOMAIN'
            AND ad.agent_id = v_agent_id
        
        UNION ALL
        
        -- 4. Workflow context (existing logic preserved)
        SELECT 
            'WORKFLOW_CONTEXT.md' as filename,
            'Workflow: ' || w.name || E'\n\n' || w.description as content,
            'workflow:' || w.name as source,
            4 as priority
        FROM workflow_steps ws
        JOIN workflows w ON ws.workflow_id = w.id
        WHERE ws.agent_id = v_agent_id
            AND w.status = 'active'
        
        UNION ALL
        
        -- 5. Legacy agent-specific context (for backwards compatibility during migration)
        SELECT 
            kv.key || '.md' as filename,
            kv.value as content,
            'agent-legacy'::TEXT as source,
            5 as priority
        FROM agents a
        CROSS JOIN LATERAL jsonb_each_text(COALESCE(a.bootstrap_context, '{}'::jsonb)) AS kv
        WHERE a.name = p_agent_name
    ) subq
    ORDER BY subq.filename, subq.priority;
END;
$function$;

COMMENT ON FUNCTION get_agent_bootstrap(TEXT) IS 'Returns bootstrap context for agent: universal + GLOBAL + agent domains + workflows + legacy (additive merge)';

-- ============================================================================
-- 6. Create helper functions for context management
-- ============================================================================

-- Add or update domain context
CREATE OR REPLACE FUNCTION upsert_domain_context(
    p_domain_name TEXT,
    p_file_key TEXT,
    p_content TEXT,
    p_description TEXT DEFAULT NULL,
    p_updated_by TEXT DEFAULT 'system'
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO agent_bootstrap_context (context_type, domain_name, file_key, content, description, updated_by, updated_at)
    VALUES ('DOMAIN', p_domain_name, p_file_key, p_content, p_description, p_updated_by, NOW())
    ON CONFLICT (context_type, COALESCE(domain_name, ''), file_key) 
    DO UPDATE SET 
        content = EXCLUDED.content,
        description = COALESCE(EXCLUDED.description, agent_bootstrap_context.description),
        updated_by = EXCLUDED.updated_by,
        updated_at = NOW()
    RETURNING id INTO v_id;
    
    RETURN v_id;
END;
$function$;

-- Add or update global context
CREATE OR REPLACE FUNCTION upsert_global_context(
    p_file_key TEXT,
    p_content TEXT,
    p_description TEXT DEFAULT NULL,
    p_updated_by TEXT DEFAULT 'system'
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO agent_bootstrap_context (context_type, domain_name, file_key, content, description, updated_by, updated_at)
    VALUES ('GLOBAL', NULL, p_file_key, p_content, p_description, p_updated_by, NOW())
    ON CONFLICT (context_type, COALESCE(domain_name, ''), file_key) 
    DO UPDATE SET 
        content = EXCLUDED.content,
        description = COALESCE(EXCLUDED.description, agent_bootstrap_context.description),
        updated_by = EXCLUDED.updated_by,
        updated_at = NOW()
    RETURNING id INTO v_id;
    
    RETURN v_id;
END;
$function$;

-- List all context for an agent (for debugging/inspection)
CREATE OR REPLACE FUNCTION list_agent_context(p_agent_name TEXT)
RETURNS TABLE(
    source_type TEXT,
    domain_or_scope TEXT,
    file_key TEXT,
    content_preview TEXT
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_agent_id INTEGER;
BEGIN
    SELECT id INTO v_agent_id FROM agents WHERE name = p_agent_name;
    
    RETURN QUERY
    SELECT 
        'GLOBAL'::TEXT,
        'all agents'::TEXT,
        bc.file_key,
        LEFT(bc.content, 100) || '...'
    FROM agent_bootstrap_context bc
    WHERE bc.context_type = 'GLOBAL'
    
    UNION ALL
    
    SELECT 
        'DOMAIN'::TEXT,
        bc.domain_name,
        bc.file_key,
        LEFT(bc.content, 100) || '...'
    FROM agent_bootstrap_context bc
    JOIN agent_domains ad ON bc.domain_name = ad.domain_topic
    WHERE bc.context_type = 'DOMAIN'
        AND ad.agent_id = v_agent_id
    
    UNION ALL
    
    SELECT 
        'WORKFLOW'::TEXT,
        w.name,
        'WORKFLOW_CONTEXT'::TEXT,
        LEFT(w.description, 100) || '...'
    FROM workflow_steps ws
    JOIN workflows w ON ws.workflow_id = w.id
    WHERE ws.agent_id = v_agent_id
        AND w.status = 'active';
END;
$function$;

-- ============================================================================
-- 7. Update audit trigger for new table
-- ============================================================================
CREATE OR REPLACE FUNCTION audit_bootstrap_context_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO bootstrap_context_audit (table_name, record_id, operation, new_content, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', NEW.content, COALESCE(NEW.updated_by, current_user));
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO bootstrap_context_audit (table_name, record_id, operation, old_content, new_content, changed_by)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', OLD.content, NEW.content, COALESCE(NEW.updated_by, current_user));
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO bootstrap_context_audit (table_name, record_id, operation, old_content, changed_by)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', OLD.content, current_user);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$function$;

-- Create trigger on new table
DROP TRIGGER IF EXISTS audit_agent_bootstrap_context ON agent_bootstrap_context;
CREATE TRIGGER audit_agent_bootstrap_context
    AFTER INSERT OR UPDATE OR DELETE ON agent_bootstrap_context
    FOR EACH ROW EXECUTE FUNCTION audit_bootstrap_context_change();

-- ============================================================================
-- 8. Grant permissions
-- ============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_bootstrap_context TO nova;
GRANT SELECT ON agent_bootstrap_context TO newhart;
GRANT USAGE, SELECT ON SEQUENCE agent_bootstrap_context_id_seq TO nova;
GRANT SELECT ON bootstrap_context_config TO PUBLIC;  -- All agents need to read config

COMMIT;

-- ============================================================================
-- Verification queries (run after migration)
-- ============================================================================
-- SELECT * FROM agent_bootstrap_context ORDER BY context_type, domain_name, file_key;
-- SELECT * FROM get_agent_bootstrap('coder');
-- SELECT * FROM list_agent_context('coder');
