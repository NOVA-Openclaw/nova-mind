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
        -- Matches workflows where agent is assigned to steps,
        -- workflow domains overlap agent domains,
        -- OR agent is the workflow orchestrator
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
                COALESCE(' [agent: ' || a2.name || ']', '') ||
                COALESCE(' [domain: ' || ws.domain || ']', ''),
                E'\n' ORDER BY ws.step_order
            ) AS steps_text
            FROM workflow_steps ws
            LEFT JOIN agents a2 ON a2.id = ws.agent_id
            WHERE ws.workflow_id = w.id
        ) ws_agg ON true
        WHERE w.status = 'active'
          AND (
            -- Agent is the workflow orchestrator
            w.orchestrator_agent_id = v_agent_id
            OR
            -- Agent is directly assigned to a step
            EXISTS (
                SELECT 1 FROM workflow_steps ws2
                WHERE ws2.workflow_id = w.id AND ws2.agent_id = v_agent_id
            )
            OR
            -- Workflow step domains overlap with agent's domains
            EXISTS (
                SELECT 1 FROM workflow_steps ws3
                JOIN agent_domains ad ON ad.agent_id = v_agent_id
                WHERE ws3.workflow_id = w.id
                  AND (ad.domain_topic = ws3.domain OR ad.domain_topic = ANY(ws3.domains))
            )
          )

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
$function$
;

COMMENT ON FUNCTION get_agent_bootstrap IS 'Get all bootstrap files for an agent: universal + GLOBAL + agent domains + workflows (dynamic, includes orchestrator_agent_id matching) + agent-specific. Issue #97: orchestrator_agent_id support.';
