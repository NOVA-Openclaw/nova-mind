-- Migration 062: Fix get_agent_bootstrap() function
-- Issue: NOVA-Openclaw/nova-cognition#179
--
-- Problems fixed:
-- 1. Referenced bootstrap_context_config (dropped) for enabled check
-- 2. Workflow section referenced ws.agent_id (doesn't exist in workflow_steps)
-- 3. Workflow section referenced w.orchestrator_agent_id (doesn't exist in workflows)
-- 4. Step text builder joined agents a2 ON a2.id = ws.agent_id (nonexistent column)
--
-- Design principles:
-- - UNIVERSAL + GLOBAL: everyone gets these
-- - DOMAIN: matched via agent's domains in agent_domains table
-- - WORKFLOW: matched by domain overlap (orchestrator_domain or step domains vs agent domains)
-- - AGENT: the ONLY lookup by agent name directly

BEGIN;

-- Drop both overloaded versions
DROP FUNCTION IF EXISTS get_agent_bootstrap(text);
DROP FUNCTION IF EXISTS get_agent_bootstrap(varchar);

CREATE OR REPLACE FUNCTION get_agent_bootstrap(p_agent_name text)
RETURNS TABLE(filename text, content text, source text)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_agent_id INTEGER;
BEGIN
    -- Resolve agent ID (may be NULL if agent not in agents table)
    SELECT id INTO v_agent_id FROM agents WHERE name = p_agent_name LIMIT 1;

    RETURN QUERY
    SELECT DISTINCT ON (subq.filename)
        subq.filename,
        subq.content,
        subq.source
    FROM (
        -- 1. UNIVERSAL — everyone gets these
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'universal'::TEXT AS source, 1 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'UNIVERSAL'

        UNION ALL

        -- 2. GLOBAL — everyone gets these
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'global'::TEXT AS source, 2 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'GLOBAL'

        UNION ALL

        -- 3. DOMAIN — matched via agent's domains in agent_domains
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'domain:' || abc.domain_name AS source, 3 AS priority
        FROM agent_bootstrap_context abc
        JOIN agent_domains ad ON ad.domain_topic = abc.domain_name
        WHERE abc.context_type = 'DOMAIN'
          AND ad.agent_id = v_agent_id

        UNION ALL

        -- 4. WORKFLOW — inject workflows the agent participates in (by domain overlap)
        SELECT
            'WORKFLOW_' || upper(replace(w.name, '-', '_')) || '.md' AS filename,
            w.name || ': ' || w.description ||
            CASE WHEN steps_text IS NOT NULL
                 THEN E'\n\nSteps:\n' || steps_text
                 ELSE ''
            END AS content,
            'workflow:' || w.name AS source,
            4 AS priority
        FROM workflows w
        LEFT JOIN LATERAL (
            SELECT string_agg(
                ws.step_order || '. ' || ws.description ||
                COALESCE(' [domain: ' || ws.domain || ']', ''),
                E'\n' ORDER BY ws.step_order
            ) AS steps_text
            FROM workflow_steps ws
            WHERE ws.workflow_id = w.id
        ) ws_agg ON true
        WHERE w.status = 'active'
          AND (
            -- Workflow's orchestrator domain matches one of the agent's domains
            EXISTS (
                SELECT 1 FROM agent_domains ad
                WHERE ad.agent_id = v_agent_id
                  AND ad.domain_topic = w.orchestrator_domain
            )
            OR
            -- Workflow step domains overlap with agent's domains
            EXISTS (
                SELECT 1 FROM workflow_steps ws
                JOIN agent_domains ad ON ad.agent_id = v_agent_id
                WHERE ws.workflow_id = w.id
                  AND (ad.domain_topic = ws.domain OR ad.domain_topic = ANY(ws.domains))
            )
          )

        UNION ALL

        -- 5. AGENT — the ONLY lookup by agent name directly
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'agent'::TEXT AS source, 5 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'AGENT'
          AND abc.agent_name = p_agent_name
    ) subq
    ORDER BY subq.filename, subq.priority;
END;
$function$;

COMMIT;
