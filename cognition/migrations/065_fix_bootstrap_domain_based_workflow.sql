-- Fix bootstrap domain based workflow assignment
CREATE OR REPLACE FUNCTION get_agent_bootstrap(p_agent_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_agent_record RECORD;
    v_domains TEXT[];
    v_capabilities TEXT[];
    v_workflows JSONB;
    v_workflow_steps JSONB;
BEGIN
    -- 1. Get basic agent info and domains
    SELECT 
        a.id, 
        a.name, 
        a.type, 
        a.provider_id, 
        a.model_id, 
        a.system_prompt,
        ARRAY(SELECT domain FROM agent_domains WHERE agent_id = a.id) as domains,
        ARRAY(SELECT capability FROM agent_capabilities WHERE agent_id = a.id) as capabilities
    INTO v_agent_record
    FROM agents a
    WHERE a.id = p_agent_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_domains := v_agent_record.domains;
    v_capabilities := v_agent_record.capabilities;

    -- 2. Get workflows where orchestrator_domain matches our agent's domains
    SELECT jsonb_agg(w.*) INTO v_workflows
    FROM workflows w
    WHERE w.orchestrator_domain = ANY(v_domains);

    -- 3. Get workflow steps where domain or domains overlap with agent's domains
    SELECT jsonb_agg(ws.*) INTO v_workflow_steps
    FROM workflow_steps ws
    WHERE ws.domain = ANY(v_domains)
       OR ws.domains && v_domains;

    RETURN jsonb_build_object(
        'agent', jsonb_build_object(
            'id', v_agent_record.id,
            'name', v_agent_record.name,
            'type', v_agent_record.type,
            'provider_id', v_agent_record.provider_id,
            'model_id', v_agent_record.model_id,
            'system_prompt', v_agent_record.system_prompt,
            'domains', v_domains,
            'capabilities', v_capabilities
        ),
        'workflows', COALESCE(v_workflows, '[]'::jsonb),
        'workflow_steps', COALESCE(v_workflow_steps, '[]'::jsonb)
    );
END;
$$ LANGUAGE plpgsql;
