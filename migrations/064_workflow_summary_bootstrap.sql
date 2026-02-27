-- Migration 064: Inject workflow summaries instead of full steps in bootstrap context
-- Issue: NOVA-Openclaw/nova-cognition#188
--
-- Changes get_agent_bootstrap() section 4 (WORKFLOW) to inject:
--   - Workflow name and description
--   - Which steps the agent owns (by domain match)
--   - Whether the agent is the orchestrator
--   - Total step count and all domains involved
--   - Instruction about understanding their role
--   - SQL query to load full steps on demand
--
-- Saves ~3,500 tokens per bootstrap for agents with multiple workflows.

CREATE OR REPLACE FUNCTION public.get_agent_bootstrap(p_agent_name text)
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

        -- 4. WORKFLOW — inject workflow SUMMARIES with agent role context
        SELECT
            'WORKFLOW_' || upper(replace(w.name, '-', '_')) || '.md' AS filename,
            w.name || ': ' || w.description ||
            E'\n\n' ||
            -- Orchestrator note
            CASE WHEN EXISTS (
                SELECT 1 FROM agent_domains ad
                WHERE ad.agent_id = v_agent_id
                  AND ad.domain_topic = w.orchestrator_domain
            )
            THEN 'You are the **orchestrator** of this workflow (via ' || w.orchestrator_domain || ' domain). '
                 || 'You are responsible for reading and understanding the entire workflow, maintaining state, delegating to domain-appropriate agents, and tracking progress.'
                 || E'\n\n'
            ELSE ''
            END ||
            -- Agent's steps
            'Your steps: ' || COALESCE(agent_steps.step_list, 'none directly assigned') ||
            E'\n' ||
            -- All domains
            'All domains involved: ' || COALESCE(all_domains.domain_list, 'none') ||
            ' (' || COALESCE(step_count.cnt, 0) || ' steps total).' ||
            E'\n\n' ||
            '> When you are employed to participate in this workflow, understand your role and what is expected of you in the steps you own before beginning. ' ||
            'Query your steps for full details:' ||
            E'\n> ```sql' ||
            E'\n> SELECT step_order, domain, requires_discussion, requires_authorization, description' ||
            E'\n> FROM workflow_steps WHERE workflow_id = ' || w.id || ' ORDER BY step_order;' ||
            E'\n> ```'
            AS content,
            'workflow:' || w.name AS source,
            4 AS priority
        FROM workflows w
        -- Agent's specific steps (by domain match)
        LEFT JOIN LATERAL (
            SELECT string_agg(
                'Step ' || ws.step_order || ' (' || ws.domain || ')',
                ', ' ORDER BY ws.step_order
            ) AS step_list
            FROM workflow_steps ws
            JOIN agent_domains ad ON ad.agent_id = v_agent_id
            WHERE ws.workflow_id = w.id
              AND (ad.domain_topic = ws.domain OR ad.domain_topic = ANY(ws.domains))
        ) agent_steps ON true
        -- All domains across all steps
        LEFT JOIN LATERAL (
            SELECT string_agg(DISTINCT ws.domain, ', ' ORDER BY ws.domain) AS domain_list
            FROM workflow_steps ws
            WHERE ws.workflow_id = w.id
        ) all_domains ON true
        -- Step count
        LEFT JOIN LATERAL (
            SELECT count(*)::int AS cnt
            FROM workflow_steps ws
            WHERE ws.workflow_id = w.id
        ) step_count ON true
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
