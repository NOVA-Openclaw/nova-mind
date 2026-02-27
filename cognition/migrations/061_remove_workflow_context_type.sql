-- Issue #95: Remove WORKFLOW context_type; source workflow context dynamically
-- Migration date: 2026-02-15
BEGIN;

-- 1. Update get_agent_bootstrap() to source workflows dynamically
CREATE OR REPLACE FUNCTION public.get_agent_bootstrap(p_agent_name text)
 RETURNS TABLE(filename text, content text, source text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_agent_id INTEGER;
BEGIN
    IF NOT (SELECT value::boolean FROM bootstrap_context_config WHERE key = 'enabled') THEN
        RETURN;
    END IF;

    SELECT id INTO v_agent_id FROM agents WHERE name = p_agent_name LIMIT 1;

    RETURN QUERY
    SELECT DISTINCT ON (subq.filename)
        subq.filename,
        subq.content,
        subq.source
    FROM (
        -- 1. UNIVERSAL (highest priority)
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'universal'::TEXT AS source, 1 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'UNIVERSAL'

        UNION ALL

        -- 2. GLOBAL
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'global'::TEXT AS source, 2 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'GLOBAL'

        UNION ALL

        -- 3. DOMAIN (matched via agent_domains)
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'domain:' || abc.domain_name AS source, 3 AS priority
        FROM agent_bootstrap_context abc
        JOIN agent_domains ad ON ad.domain_topic = abc.domain_name
        WHERE abc.context_type = 'DOMAIN'
          AND ad.agent_id = v_agent_id

        UNION ALL

        -- 4. WORKFLOW (dynamic from workflows/workflow_steps)
        -- Matches where agent is assigned to steps OR step domains overlap agent domains
        SELECT 
            'WORKFLOW_' || upper(replace(w.name, '-', '_')) || '.md' AS filename,
            w.name || ': ' || w.description || E'\n\nSteps:\n' ||
            string_agg(
                ws.step_order || '. ' || ws.description || 
                COALESCE(' [agent: ' || a2.name || ']', '') ||
                COALESCE(' [domain: ' || ws.domain || ']', ''),
                E'\n' ORDER BY ws.step_order
            ) AS content,
            'workflow:' || w.name AS source,
            4 AS priority
        FROM workflows w
        JOIN workflow_steps ws ON ws.workflow_id = w.id
        LEFT JOIN agents a2 ON a2.id = ws.agent_id
        WHERE w.status = 'active'
          AND (
            ws.agent_id = v_agent_id
            OR EXISTS (
                SELECT 1 FROM agent_domains ad
                WHERE ad.agent_id = v_agent_id
                  AND (ad.domain_topic = ws.domain OR ad.domain_topic = ANY(ws.domains))
            )
          )
        GROUP BY w.id, w.name, w.description

        UNION ALL

        -- 5. AGENT-specific (lowest priority)
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'agent'::TEXT AS source, 5 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'AGENT'
          AND abc.agent_name = p_agent_name
    ) subq
    ORDER BY subq.filename, subq.priority;
END;
$function$;

-- 2. Remove WORKFLOW from context_type constraint
ALTER TABLE agent_bootstrap_context DROP CONSTRAINT IF EXISTS agent_bootstrap_context_context_type_check;
ALTER TABLE agent_bootstrap_context ADD CONSTRAINT agent_bootstrap_context_context_type_check 
    CHECK (context_type = ANY (ARRAY['UNIVERSAL', 'GLOBAL', 'DOMAIN', 'AGENT']));

-- 3. Clean up any orphaned WORKFLOW rows
DELETE FROM agent_bootstrap_context WHERE context_type = 'WORKFLOW';

COMMENT ON FUNCTION get_agent_bootstrap(TEXT) IS 'Returns bootstrap context: UNIVERSAL + GLOBAL + DOMAIN + dynamic workflows (from workflows/workflow_steps) + AGENT. Issue #95.';

COMMIT;
