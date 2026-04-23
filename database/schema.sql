--
-- pgschema database dump
--

-- Dumped from database version PostgreSQL 16.13
-- Dumped by pgschema version 1.7.2


--
-- Name: agent_chat_status; Type: TYPE; Schema: -; Owner: -
--

CREATE TYPE agent_chat_status AS ENUM (
    'received',
    'routed',
    'responded',
    'failed'
);

--
-- Name: nova:TABLES:athena; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO athena;

--
-- Name: nova:TABLES:coder; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO coder;

--
-- Name: nova:TABLES:erato; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO erato;

--
-- Name: nova:TABLES:gem; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO gem;

--
-- Name: nova:TABLES:gidget; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO gidget;

--
-- Name: nova:TABLES:graybeard; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO graybeard;

--
-- Name: nova:TABLES:iris; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO iris;

--
-- Name: nova:TABLES:newhart; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO newhart;

--
-- Name: nova:TABLES:nova-staging; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO "nova-staging";

--
-- Name: nova:TABLES:openproject_user; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO openproject_user;

--
-- Name: nova:TABLES:scout; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO scout;

--
-- Name: nova:TABLES:ticker; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO ticker;

--
-- Name: agent_turn_context; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_turn_context (
    id SERIAL,
    context_type text NOT NULL,
    context_key text NOT NULL,
    file_key text NOT NULL,
    content text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT agent_turn_context_pkey PRIMARY KEY (id),
    CONSTRAINT agent_turn_context_context_type_file_key_key UNIQUE (context_type, file_key),
    CONSTRAINT agent_turn_context_content_check CHECK (length(content) > 0 AND length(content) <= 500),
    CONSTRAINT agent_turn_context_context_type_check CHECK (context_type IN ('UNIVERSAL'::text, 'GLOBAL'::text, 'DOMAIN'::text, 'AGENT'::text))
);

--
-- Name: research_projects; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS research_projects (
    id SERIAL,
    name varchar(255) NOT NULL,
    description text,
    status varchar(50) DEFAULT 'active' NOT NULL,
    requested_by varchar(100),
    created_by varchar(100) DEFAULT CURRENT_USER NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}' NOT NULL,
    CONSTRAINT research_projects_pkey PRIMARY KEY (id),
    CONSTRAINT research_projects_status_check CHECK (status::text IN ('active'::character varying, 'completed'::character varying, 'archived'::character varying, 'paused'::character varying))
);


COMMENT ON TABLE research_projects IS 'Top-level research project containers. Write access: Research domain (scout) only.';

--
-- Name: research_provenance; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS research_provenance (
    id SERIAL,
    entity_type varchar(50) NOT NULL,
    entity_id integer NOT NULL,
    activity_type varchar(50) NOT NULL,
    source_entities jsonb,
    agent varchar(100) DEFAULT CURRENT_USER NOT NULL,
    method text,
    started_at timestamptz,
    ended_at timestamptz DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}' NOT NULL,
    CONSTRAINT research_provenance_pkey PRIMARY KEY (id),
    CONSTRAINT research_provenance_activity_type_check CHECK (activity_type::text IN ('creation'::character varying, 'derivation'::character varying, 'revision'::character varying, 'aggregation'::character varying, 'review'::character varying, 'archival'::character varying)),
    CONSTRAINT research_provenance_entity_type_check CHECK (entity_type::text IN ('project'::character varying, 'task'::character varying, 'finding'::character varying, 'conclusion'::character varying))
);


COMMENT ON TABLE research_provenance IS 'W3C PROV-O inspired lineage tracking for research data. Write access: Research domain (scout) only.';

--
-- Name: research_tags; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS research_tags (
    id SERIAL,
    name varchar(255) NOT NULL,
    slug varchar(255) NOT NULL,
    parent_id integer,
    tag_type varchar(50) DEFAULT 'topic' NOT NULL,
    description text,
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT research_tags_pkey PRIMARY KEY (id),
    CONSTRAINT research_tags_slug_key UNIQUE (slug),
    CONSTRAINT research_tags_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES research_tags (id) ON DELETE SET NULL,
    CONSTRAINT research_tags_tag_type_check CHECK (tag_type::text IN ('topic'::character varying, 'domain'::character varying, 'method'::character varying, 'source_type'::character varying, 'confidence'::character varying, 'status'::character varying))
);


COMMENT ON TABLE research_tags IS 'Hierarchical, polymorphic tag taxonomy for research entities. Write access: Research domain (scout) only.';

--
-- Name: research_taggings; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS research_taggings (
    id SERIAL,
    tag_id integer NOT NULL,
    taggable_id integer NOT NULL,
    taggable_type varchar(50) NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    created_by varchar(100) DEFAULT CURRENT_USER NOT NULL,
    CONSTRAINT research_taggings_pkey PRIMARY KEY (id),
    CONSTRAINT research_taggings_tag_id_taggable_id_taggable_type_key UNIQUE (tag_id, taggable_id, taggable_type),
    CONSTRAINT research_taggings_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES research_tags (id) ON DELETE CASCADE,
    CONSTRAINT research_taggings_taggable_type_check CHECK (taggable_type::text IN ('project'::character varying, 'task'::character varying, 'finding'::character varying, 'conclusion'::character varying))
);


COMMENT ON TABLE research_taggings IS 'Junction table linking tags to research entities. Write access: Research domain (scout) only.';

--
-- Name: research_tasks; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS research_tasks (
    id SERIAL,
    project_id integer,
    title varchar(500) NOT NULL,
    query text NOT NULL,
    methodology text,
    status varchar(50) DEFAULT 'pending' NOT NULL,
    priority integer DEFAULT 5 NOT NULL,
    assigned_to varchar(100) DEFAULT CURRENT_USER NOT NULL,
    started_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}' NOT NULL,
    search_vector tsvector,
    CONSTRAINT research_tasks_pkey PRIMARY KEY (id),
    CONSTRAINT research_tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES research_projects (id) ON DELETE CASCADE,
    CONSTRAINT research_tasks_priority_check CHECK (priority >= 1 AND priority <= 10),
    CONSTRAINT research_tasks_status_check CHECK (status::text IN ('pending'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'failed'::character varying, 'superseded'::character varying))
);


COMMENT ON TABLE research_tasks IS 'Individual research investigation tasks within projects. Write access: Research domain (scout) only.';

--
-- Name: idx_research_tasks_project; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_research_tasks_project ON research_tasks (project_id);

--
-- Name: research_conclusions; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS research_conclusions (
    id SERIAL,
    task_id integer NOT NULL,
    title varchar(500),
    summary text NOT NULL,
    full_content text,
    finding_ids integer[] DEFAULT '{}'::integer[] NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    is_current boolean DEFAULT true NOT NULL,
    superseded_by integer,
    superseded_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}' NOT NULL,
    search_vector tsvector,
    CONSTRAINT research_conclusions_pkey PRIMARY KEY (id),
    CONSTRAINT research_conclusions_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES research_conclusions (id),
    CONSTRAINT research_conclusions_task_id_fkey FOREIGN KEY (task_id) REFERENCES research_tasks (id) ON DELETE CASCADE
);


COMMENT ON TABLE research_conclusions IS 'Synthesized conclusions aggregating multiple findings. Write access: Research domain (scout) only.';

--
-- Name: idx_research_conclusions_current; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_research_conclusions_current ON research_conclusions (task_id) WHERE (is_current = true);

--
-- Name: idx_research_conclusions_task; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_research_conclusions_task ON research_conclusions (task_id);

--
-- Name: research_findings; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS research_findings (
    id SERIAL,
    task_id integer NOT NULL,
    finding_type varchar(50) NOT NULL,
    content text NOT NULL,
    confidence numeric(3,2),
    importance varchar(20) DEFAULT 'normal' NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    is_current boolean DEFAULT true NOT NULL,
    superseded_by integer,
    superseded_at timestamptz,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}' NOT NULL,
    search_vector tsvector,
    CONSTRAINT research_findings_pkey PRIMARY KEY (id),
    CONSTRAINT research_findings_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES research_findings (id),
    CONSTRAINT research_findings_task_id_fkey FOREIGN KEY (task_id) REFERENCES research_tasks (id) ON DELETE CASCADE,
    CONSTRAINT research_findings_confidence_check CHECK (confidence >= 0.00 AND confidence <= 1.00),
    CONSTRAINT research_findings_finding_type_check CHECK (finding_type::text IN ('fact'::character varying, 'insight'::character varying, 'conclusion'::character varying, 'warning'::character varying, 'recommendation'::character varying, 'definition'::character varying, 'example'::character varying)),
    CONSTRAINT research_findings_importance_check CHECK (importance::text IN ('low'::character varying, 'normal'::character varying, 'high'::character varying, 'critical'::character varying))
);


COMMENT ON TABLE research_findings IS 'Discrete facts, insights, and conclusions from research. Supports copy-on-write versioning. Write access: Research domain (scout) only.';

--
-- Name: research_citations; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS research_citations (
    id SERIAL,
    finding_id integer NOT NULL,
    source_type varchar(50) NOT NULL,
    source_url text,
    source_title varchar(500),
    source_author varchar(255),
    source_date date,
    quote text,
    page_or_section varchar(100),
    reliability numeric(3,2),
    library_work_id integer,
    accessed_at timestamptz DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}' NOT NULL,
    CONSTRAINT research_citations_pkey PRIMARY KEY (id),
    CONSTRAINT research_citations_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES research_findings (id) ON DELETE CASCADE,
    CONSTRAINT research_citations_reliability_check CHECK (reliability >= 0.00 AND reliability <= 1.00),
    CONSTRAINT research_citations_source_type_check CHECK (source_type::text IN ('url'::character varying, 'paper'::character varying, 'book'::character varying, 'library_work'::character varying, 'api'::character varying, 'agent'::character varying, 'database'::character varying, 'document'::character varying, 'interview'::character varying))
);


COMMENT ON TABLE research_citations IS 'Source citations linking findings to original sources. Write access: Research domain (scout) only.';

--
-- Name: audit_bootstrap_agents(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION audit_bootstrap_agents()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO bootstrap_context_audit (
            table_name,
            record_id,
            operation,
            old_content,
            new_content,
            changed_by,
            changed_at
        ) VALUES (
            'bootstrap_context_agents',
            OLD.id,
            'DELETE',
            OLD.content,
            NULL,
            OLD.updated_by,
            NOW()
        );
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO bootstrap_context_audit (
            table_name,
            record_id,
            operation,
            old_content,
            new_content,
            changed_by,
            changed_at
        ) VALUES (
            'bootstrap_context_agents',
            NEW.id,
            'UPDATE',
            OLD.content,
            NEW.content,
            NEW.updated_by,
            NOW()
        );
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO bootstrap_context_audit (
            table_name,
            record_id,
            operation,
            old_content,
            new_content,
            changed_by,
            changed_at
        ) VALUES (
            'bootstrap_context_agents',
            NEW.id,
            'INSERT',
            NULL,
            NEW.content,
            NEW.updated_by,
            NOW()
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

--
-- Name: audit_bootstrap_agents(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION audit_bootstrap_agents() IS 'Audit trigger function for agent-specific context changes';

--
-- Name: audit_bootstrap_universal(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION audit_bootstrap_universal()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        INSERT INTO bootstrap_context_audit (
            table_name,
            record_id,
            operation,
            old_content,
            new_content,
            changed_by,
            changed_at
        ) VALUES (
            'bootstrap_context_universal',
            OLD.id,
            'DELETE',
            OLD.content,
            NULL,
            OLD.updated_by,
            NOW()
        );
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO bootstrap_context_audit (
            table_name,
            record_id,
            operation,
            old_content,
            new_content,
            changed_by,
            changed_at
        ) VALUES (
            'bootstrap_context_universal',
            NEW.id,
            'UPDATE',
            OLD.content,
            NEW.content,
            NEW.updated_by,
            NOW()
        );
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO bootstrap_context_audit (
            table_name,
            record_id,
            operation,
            old_content,
            new_content,
            changed_by,
            changed_at
        ) VALUES (
            'bootstrap_context_universal',
            NEW.id,
            'INSERT',
            NULL,
            NEW.content,
            NEW.updated_by,
            NOW()
        );
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

--
-- Name: audit_bootstrap_universal(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION audit_bootstrap_universal() IS 'Audit trigger function for universal context changes';

--
-- Name: calculate_word_count(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION calculate_word_count()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.word_count = array_length(regexp_split_to_array(trim(NEW.content), '\s+'), 1);
    NEW.character_count = length(NEW.content);
    RETURN NEW;
END;
$$;

--
-- Name: claim_coder_issue(integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION claim_coder_issue(
    issue_id integer
)
RETURNS boolean
LANGUAGE sql
VOLATILE
AS $$
  UPDATE git_issue_queue
  SET status = 'implementing', started_at = NOW()
  WHERE id = issue_id AND status = 'tests_approved'
  RETURNING TRUE;
$$;

--
-- Name: cleanup_old_archives(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION cleanup_old_archives()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM entity_facts_archive
    WHERE archived_at < NOW() - INTERVAL '1 year';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

--
-- Name: cleanup_old_archives(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION cleanup_old_archives() IS 'Hard deletes archived facts older than 1 year. Run via cron or decay script.';

--
-- Name: cleanup_old_embeddings_archive(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION cleanup_old_embeddings_archive()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM memory_embeddings_archive WHERE archived_at < NOW() - INTERVAL '1 year';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

--
-- Name: cleanup_old_embeddings_archive(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION cleanup_old_embeddings_archive() IS 'Hard deletes archived embeddings older than 1 year.';

--
-- Name: cleanup_old_events_archive(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION cleanup_old_events_archive()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM events_archive WHERE archived_at < NOW() - INTERVAL '1 year';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

--
-- Name: cleanup_old_events_archive(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION cleanup_old_events_archive() IS 'Hard deletes archived events older than 1 year.';

--
-- Name: cleanup_old_lessons_archive(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION cleanup_old_lessons_archive()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM lessons_archive WHERE archived_at < NOW() - INTERVAL '1 year';
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

--
-- Name: cleanup_old_lessons_archive(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION cleanup_old_lessons_archive() IS 'Hard deletes archived lessons older than 1 year.';

--
-- Name: copy_file_to_bootstrap(text, text, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION copy_file_to_bootstrap(
    p_file_path text,
    p_file_content text,
    p_agent_name text DEFAULT NULL,
    p_updated_by text DEFAULT 'migration'
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_file_key TEXT;
    v_result TEXT;
BEGIN
    v_file_key := upper(regexp_replace(
        regexp_replace(p_file_path, '^.*/([^/]+)\.md$', '\1'),
        '-', '_', 'g'
    ));

    IF p_agent_name IS NULL THEN
        PERFORM update_universal_context(
            v_file_key,
            p_file_content,
            'Migrated from ' || p_file_path,
            p_updated_by
        );
        v_result := 'universal:' || v_file_key;
    ELSE
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
$$;

--
-- Name: copy_file_to_bootstrap(text, text, text, text); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION copy_file_to_bootstrap(text, text, text, text) IS 'Migrate file content to database (auto-detects universal vs agent)';

--
-- Name: delete_agent_context(text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION delete_agent_context(
    p_agent_name text,
    p_file_key text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM bootstrap_context_agents
    WHERE agent_name = p_agent_name AND file_key = p_file_key;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted > 0;
END;
$$;

--
-- Name: delete_universal_context(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION delete_universal_context(
    p_file_key text
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM bootstrap_context_universal WHERE file_key = p_file_key;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted > 0;
END;
$$;

--
-- Name: embed_chat_message(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION embed_chat_message()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    content_text     TEXT;
    content_hash_val VARCHAR(64);
BEGIN
    content_text     := NEW.sender || ': ' || NEW.message;
    content_hash_val := encode(sha256(content_text::bytea), 'hex');

    INSERT INTO memory_embeddings (content_hash, content, metadata, embedding)
    VALUES (
        content_hash_val,
        content_text,
        json_build_object(
            'chat_id',    NEW.id,
            'sender',     NEW.sender,
            'recipients', NEW.recipients,
            'timestamp',  NEW."timestamp"
        ),
        NULL  -- Populated by external embedding service
    )
    ON CONFLICT (content_hash) DO NOTHING;

    RETURN NEW;
END;
$$;

--
-- Name: expire_old_chat(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION expire_old_chat()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM agent_chat
    WHERE "timestamp" < now() - interval '30 days';

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

--
-- Name: expire_old_chat(integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION expire_old_chat(
    retention_days integer DEFAULT 90
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE deleted_count integer;
BEGIN
    DELETE FROM agent_chat WHERE "timestamp" < now() - (retention_days || ' days')::interval;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

--
-- Name: get_agent_bootstrap(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_agent_bootstrap(
    p_agent_name text
)
RETURNS TABLE(filename text, content text, source text)
LANGUAGE plpgsql
VOLATILE
AS $$
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
$$;

--
-- Name: get_agent_bootstrap(text); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION get_agent_bootstrap(text) IS 'Get all bootstrap files for an agent: universal + GLOBAL + agent domains + workflows (dynamic, includes orchestrator_agent_id matching) + agent-specific. Issue #97: orchestrator_agent_id support.';

--
-- Name: get_agent_skills(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_agent_skills(
    p_agent_name text
)
RETURNS TABLE(skill_name text, description text, source_type text, domain_name text, location_path text, instructions text, emoji text, requires_bins text[], requires_any_bins text[], requires_env text[], requires_config text[], primary_env text, requires_os text[], enabled boolean)
LANGUAGE sql
STABLE
AS $$
    SELECT DISTINCT ON (s.skill_name)
        s.skill_name, s.description, s.source_type, s.domain_name,
        s.location_path, s.instructions, s.emoji,
        s.requires_bins, s.requires_any_bins, s.requires_env,
        s.requires_config, s.primary_env, s.requires_os, s.enabled
    FROM skills s
    LEFT JOIN agents a ON a.name = p_agent_name
    LEFT JOIN agent_domains ad ON ad.agent_id = a.id AND s.source_type = 'DOMAIN' AND ad.domain_topic = s.domain_name
    WHERE s.enabled = TRUE
      AND (
          s.source_type IN ('BUNDLED', 'MANAGED')
          OR (s.source_type = 'WORKSPACE' AND (s.agent_name IS NULL OR s.agent_name = p_agent_name))
          OR (s.source_type = 'DOMAIN' AND ad.id IS NOT NULL)
      )
    ORDER BY s.skill_name,
        CASE WHEN s.source_type = 'WORKSPACE' AND s.agent_name = p_agent_name THEN 1
             WHEN s.source_type = 'WORKSPACE' AND s.agent_name IS NULL THEN 2
             WHEN s.source_type = 'DOMAIN' THEN 3
             WHEN s.source_type = 'MANAGED' THEN 4
             WHEN s.source_type = 'BUNDLED' THEN 5
        END;
$$;

--
-- Name: build_skills_xml(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION build_skills_xml(
    p_agent_name text
)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT '<available_skills>' || E'\n' ||
        string_agg(
            '  <skill>' || E'\n' ||
            '    <name>' || s.skill_name || '</name>' || E'\n' ||
            '    <description>' || s.description || '</description>' || E'\n' ||
            CASE WHEN s.location_path IS NOT NULL
                 THEN '    <location>' || s.location_path || '</location>' || E'\n'
                 ELSE ''
            END ||
            '  </skill>',
            E'\n'
        ) || E'\n' ||
        '</available_skills>'
    FROM get_agent_skills(p_agent_name) s
    WHERE s.enabled = TRUE;
$$;

--
-- Name: build_skills_xml(text); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION build_skills_xml(text) IS 'Generates the <available_skills> XML block matching OpenClaw prompt format.';

--
-- Name: get_agent_tools(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_agent_tools(
    p_agent_name text
)
RETURNS TABLE(tool_name text, description text, source_type text, domain_name text, category text, notes text, metadata jsonb, enabled boolean)
LANGUAGE sql
STABLE
AS $$
    SELECT DISTINCT ON (t.tool_name)
        t.tool_name, t.description, t.source_type, t.domain_name,
        t.category, t.notes, t.metadata, t.enabled
    FROM tools t
    LEFT JOIN agents a ON a.name = p_agent_name
    LEFT JOIN agent_domains ad ON ad.agent_id = a.id AND t.source_type = 'DOMAIN' AND ad.domain_topic = t.domain_name
    WHERE t.enabled = TRUE
      AND (
          t.source_type IN ('BUNDLED', 'MANAGED')
          OR (t.source_type = 'WORKSPACE' AND (t.agent_name IS NULL OR t.agent_name = p_agent_name))
          OR (t.source_type = 'DOMAIN' AND ad.id IS NOT NULL)
      )
    ORDER BY t.tool_name,
        CASE WHEN t.source_type = 'WORKSPACE' AND t.agent_name = p_agent_name THEN 1
             WHEN t.source_type = 'WORKSPACE' AND t.agent_name IS NULL THEN 2
             WHEN t.source_type = 'DOMAIN' THEN 3
             WHEN t.source_type = 'MANAGED' THEN 4
             WHEN t.source_type = 'BUNDLED' THEN 5
        END;
$$;

--
-- Name: get_agent_turn_context(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_agent_turn_context(
    p_agent_name text
)
RETURNS TABLE(content text, truncated boolean, records_skipped integer, total_chars integer)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_content TEXT := '';
    v_budget INT := 2000;
    v_total_chars INT := 0;
    v_records_skipped INT := 0;
    v_truncated BOOLEAN := false;
    rec RECORD;
BEGIN
    -- Iterate through records in priority order: UNIVERSAL → GLOBAL → DOMAIN → AGENT
    FOR rec IN
        SELECT atc.content AS rec_content, atc.context_type
        FROM agent_turn_context atc
        WHERE atc.enabled = true
        AND (
            atc.context_type IN ('UNIVERSAL', 'GLOBAL')
            OR (atc.context_type = 'DOMAIN' AND atc.context_key IN (
                SELECT ad.domain_topic FROM agent_domains ad
                JOIN agents a ON a.id = ad.agent_id
                WHERE a.name = p_agent_name
            ))
            OR (atc.context_type = 'AGENT' AND atc.context_key = p_agent_name)
        )
        ORDER BY
            CASE atc.context_type
                WHEN 'UNIVERSAL' THEN 1
                WHEN 'GLOBAL' THEN 2
                WHEN 'DOMAIN' THEN 3
                WHEN 'AGENT' THEN 4
            END,
            atc.file_key
    LOOP
        IF v_total_chars + LENGTH(rec.rec_content) > v_budget THEN
            v_truncated := true;
            v_records_skipped := v_records_skipped + 1;
        ELSE
            IF v_content != '' THEN
                v_content := v_content || E'\n\n';
                v_total_chars := v_total_chars + 2;
            END IF;
            v_content := v_content || rec.rec_content;
            v_total_chars := v_total_chars + LENGTH(rec.rec_content);
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_content, v_truncated, v_records_skipped, v_total_chars;
END;
$$;

--
-- Name: get_bootstrap_config(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_bootstrap_config()
RETURNS TABLE(key text, value jsonb, description text)
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    RETURN QUERY SELECT c.key, c.value, c.description FROM bootstrap_context_config c;
END;
$$;

--
-- Name: get_bootstrap_config(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION get_bootstrap_config() IS 'Get bootstrap system configuration';

--
-- Name: get_ralph_state(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_ralph_state(
    p_series_id text
)
RETURNS TABLE(iteration integer, state jsonb, status text)
LANGUAGE sql
VOLATILE
AS $$
  SELECT iteration, state, status
  FROM ralph_sessions
  WHERE session_series_id = p_series_id
  ORDER BY iteration DESC
  LIMIT 1;
$$;

--
-- Name: get_research_tag_tree(integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_research_tag_tree(
    root_tag_id integer
)
RETURNS TABLE(id integer, name varchar, slug varchar, depth integer)
LANGUAGE sql
VOLATILE
AS $$
WITH RECURSIVE tag_tree AS (
    SELECT rt.id, rt.name, rt.slug, 0 AS depth
    FROM research_tags rt WHERE rt.id = root_tag_id
    UNION ALL
    SELECT t.id, t.name, t.slug, tt.depth + 1
    FROM research_tags t
    JOIN tag_tree tt ON t.parent_id = tt.id
)
SELECT * FROM tag_tree;
$$;

--
-- Name: insert_workflow_step(integer, integer, text, text, boolean, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION insert_workflow_step(
    p_workflow_id integer,
    p_step_order integer,
    p_agent_name text,
    p_description text,
    p_produces_deliverable boolean DEFAULT false,
    p_deliverable_type text DEFAULT NULL,
    p_deliverable_description text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
AS $$
DECLARE
  v_agent_id INT;
  v_step_id INT;
BEGIN
  SELECT id INTO v_agent_id FROM agents WHERE name = p_agent_name;
  IF v_agent_id IS NULL THEN
    RAISE EXCEPTION 'Agent not found: %', p_agent_name;
  END IF;

  INSERT INTO workflow_steps (workflow_id, step_order, agent_id, description, produces_deliverable, deliverable_type, deliverable_description)
  VALUES (p_workflow_id, p_step_order, v_agent_id, p_description, p_produces_deliverable, p_deliverable_type, p_deliverable_description)
  RETURNING id INTO v_step_id;

  RETURN v_step_id;
END;
$$;

--
-- Name: library_works_search_trigger(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION library_works_search_trigger()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.summary, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.abstract, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.insights, '')), 'C') ||
        setweight(to_tsvector('english', coalesce(array_to_string(NEW.notable_quotes, ' '), '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.content_text, '')), 'D');
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END
$$;

--
-- Name: link_github_issue(integer, integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION link_github_issue(
    p_queue_id integer,
    p_github_issue integer
)
RETURNS void
LANGUAGE sql
VOLATILE
AS $$
  UPDATE git_issue_queue
  SET issue_number = p_github_issue
  WHERE id = p_queue_id;
$$;

--
-- Name: list_agent_context(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION list_agent_context(
    p_agent_name text
)
RETURNS TABLE(source_type text, domain_or_scope text, file_key text, content_preview text)
LANGUAGE plpgsql
VOLATILE
AS $$
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
$$;

--
-- Name: list_all_context(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION list_all_context()
RETURNS TABLE(type text, agent_name text, file_key text, content_length integer, updated_at timestamptz, updated_by text)
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        'universal'::TEXT,
        NULL::TEXT,
        u.file_key,
        length(u.content),
        u.updated_at,
        u.updated_by
    FROM bootstrap_context_universal u

    UNION ALL

    SELECT
        'agent'::TEXT,
        a.agent_name,
        a.file_key,
        length(a.content),
        a.updated_at,
        a.updated_by
    FROM bootstrap_context_agents a
    ORDER BY type, agent_name, file_key;
END;
$$;

--
-- Name: list_all_context(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION list_all_context() IS 'List all context files with metadata';

--
-- Name: log_agent_modification(integer, text, text, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION log_agent_modification(
    p_agent_id integer,
    p_modified_by text,
    p_field_changed text,
    p_old_value text,
    p_new_value text
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    INSERT INTO agent_modifications (
        agent_id, modified_by, field_changed, old_value, new_value
    ) VALUES (
        p_agent_id, p_modified_by, p_field_changed, p_old_value, p_new_value
    );
END;
$$;

--
-- Name: agent_set_collaborative(integer, boolean, jsonb, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION agent_set_collaborative(
    p_agent_id integer,
    p_collaborative boolean,
    p_collaborate_config jsonb DEFAULT NULL,
    p_modified_by text DEFAULT 'system'
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_old_collaborative BOOLEAN;
    v_old_config JSONB;
BEGIN
    -- Get old values
    SELECT collaborative, collaborate_config
    INTO v_old_collaborative, v_old_config
    FROM agents
    WHERE id = p_agent_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Agent not found';
        RETURN;
    END IF;

    -- Update collaborative settings
    UPDATE agents
    SET collaborative = p_collaborative,
        collaborate_config = COALESCE(p_collaborate_config, collaborate_config),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_agent_id;

    -- Log collaborative change
    PERFORM log_agent_modification(
        p_agent_id, p_modified_by, 'collaborative',
        v_old_collaborative::TEXT, p_collaborative::TEXT
    );

    -- Log config change if provided
    IF p_collaborate_config IS NOT NULL THEN
        PERFORM log_agent_modification(
            p_agent_id, p_modified_by, 'collaborate_config',
            v_old_config::TEXT, p_collaborate_config::TEXT
        );
    END IF;

    RETURN QUERY SELECT TRUE, 'Collaborative settings updated successfully';
END;
$$;

--
-- Name: agent_set_model(integer, text, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION agent_set_model(
    p_agent_id integer,
    p_new_model text,
    p_new_fallback text DEFAULT NULL,
    p_modified_by text DEFAULT 'system'
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_old_model TEXT;
    v_old_fallback TEXT;
BEGIN
    -- Get old values
    SELECT model, fallback_model INTO v_old_model, v_old_fallback
    FROM agents
    WHERE id = p_agent_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Agent not found';
        RETURN;
    END IF;

    -- Update model
    UPDATE agents
    SET model = p_new_model,
        fallback_model = COALESCE(p_new_fallback, fallback_model),
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_agent_id;

    -- Log model change
    PERFORM log_agent_modification(
        p_agent_id, p_modified_by, 'model',
        v_old_model, p_new_model
    );

    -- Log fallback change if provided
    IF p_new_fallback IS NOT NULL THEN
        PERFORM log_agent_modification(
            p_agent_id, p_modified_by, 'fallback_model',
            v_old_fallback, p_new_fallback
        );
    END IF;

    RETURN QUERY SELECT TRUE, 'Model configuration updated successfully';
END;
$$;

--
-- Name: agent_set_status(integer, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION agent_set_status(
    p_agent_id integer,
    p_new_status text,
    p_modified_by text DEFAULT 'system'
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_old_status TEXT;
    v_valid_statuses TEXT[] := ARRAY['active', 'inactive', 'suspended', 'archived'];
BEGIN
    -- Validate status value
    IF NOT (p_new_status = ANY(v_valid_statuses)) THEN
        RETURN QUERY SELECT FALSE,
            'Invalid status. Must be one of: active, inactive, suspended, archived';
        RETURN;
    END IF;

    -- Get old status
    SELECT status INTO v_old_status
    FROM agents
    WHERE id = p_agent_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Agent not found';
        RETURN;
    END IF;

    -- Update status
    UPDATE agents
    SET status = p_new_status,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_agent_id;

    -- Log modification
    PERFORM log_agent_modification(
        p_agent_id, p_modified_by, 'status', v_old_status, p_new_status
    );

    RETURN QUERY SELECT TRUE, 'Status updated successfully';
END;
$$;

--
-- Name: agent_update(integer, text, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION agent_update(
    p_agent_id integer,
    p_field_name text,
    p_new_value text,
    p_modified_by text DEFAULT 'system'
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
VOLATILE
AS $_$
DECLARE
    v_old_value TEXT;
    v_protected_fields TEXT[] := ARRAY['id', 'created_at'];
    v_sql TEXT;
BEGIN
    -- Check if field is protected
    IF p_field_name = ANY(v_protected_fields) THEN
        RETURN QUERY SELECT FALSE,
            'Cannot modify protected field: ' || p_field_name;
        RETURN;
    END IF;

    -- Verify agent exists and get old value
    v_sql := format('SELECT %I::TEXT FROM agents WHERE id = $1', p_field_name);
    BEGIN
        EXECUTE v_sql INTO v_old_value USING p_agent_id;
    EXCEPTION
        WHEN undefined_column THEN
            RETURN QUERY SELECT FALSE, 'Invalid field name: ' || p_field_name;
            RETURN;
        WHEN OTHERS THEN
            RETURN QUERY SELECT FALSE, 'Error reading field: ' || SQLERRM;
            RETURN;
    END;

    IF v_old_value IS NULL AND NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Agent not found';
        RETURN;
    END IF;

    -- Update the field
    v_sql := format(
        'UPDATE agents SET %I = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        p_field_name
    );
    BEGIN
        EXECUTE v_sql USING p_new_value, p_agent_id;
    EXCEPTION
        WHEN OTHERS THEN
            RETURN QUERY SELECT FALSE, 'Error updating field: ' || SQLERRM;
            RETURN;
    END;

    -- Log modification
    PERFORM log_agent_modification(
        p_agent_id, p_modified_by, p_field_name, v_old_value, p_new_value
    );

    RETURN QUERY SELECT TRUE, 'Field updated successfully';
END;
$_$;

--
-- Name: agent_update_jsonb(integer, text, jsonb, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION agent_update_jsonb(
    p_agent_id integer,
    p_field_name text,
    p_new_value jsonb,
    p_modified_by text DEFAULT 'system'
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
VOLATILE
AS $_$
DECLARE
    v_old_value JSONB;
    v_protected_fields TEXT[] := ARRAY['id', 'created_at'];
    v_sql TEXT;
BEGIN
    -- Check if field is protected
    IF p_field_name = ANY(v_protected_fields) THEN
        RETURN QUERY SELECT FALSE,
            'Cannot modify protected field: ' || p_field_name;
        RETURN;
    END IF;

    -- Get old value
    v_sql := format('SELECT %I FROM agents WHERE id = $1', p_field_name);
    BEGIN
        EXECUTE v_sql INTO v_old_value USING p_agent_id;
    EXCEPTION
        WHEN undefined_column THEN
            RETURN QUERY SELECT FALSE, 'Invalid field name: ' || p_field_name;
            RETURN;
        WHEN OTHERS THEN
            RETURN QUERY SELECT FALSE, 'Error reading field: ' || SQLERRM;
            RETURN;
    END;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Agent not found';
        RETURN;
    END IF;

    -- Update the field
    v_sql := format(
        'UPDATE agents SET %I = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
        p_field_name
    );
    EXECUTE v_sql USING p_new_value, p_agent_id;

    -- Log modification
    PERFORM log_agent_modification(
        p_agent_id, p_modified_by, p_field_name,
        v_old_value::TEXT, p_new_value::TEXT
    );

    RETURN QUERY SELECT TRUE, 'Field updated successfully';
END;
$_$;

--
-- Name: agent_update_skills(integer, text[], text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION agent_update_skills(
    p_agent_id integer,
    p_skills text[],
    p_modified_by text DEFAULT 'system'
)
RETURNS TABLE(success boolean, message text)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_old_skills TEXT[];
BEGIN
    -- Get old skills
    SELECT skills INTO v_old_skills
    FROM agents
    WHERE id = p_agent_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 'Agent not found';
        RETURN;
    END IF;

    -- Update skills
    UPDATE agents
    SET skills = p_skills,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = p_agent_id;

    -- Log modification
    PERFORM log_agent_modification(
        p_agent_id, p_modified_by, 'skills',
        array_to_string(v_old_skills, ','),
        array_to_string(p_skills, ',')
    );

    RETURN QUERY SELECT TRUE, 'Skills updated successfully';
END;
$$;

--
-- Name: notify_agent_chat(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_agent_chat()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_notify('agent_chat', json_build_object(
        'id',         NEW.id,
        'sender',     NEW.sender,
        'recipients', NEW.recipients
    )::text);
    RETURN NEW;
END;
$$;

--
-- Name: notify_agent_config_changed(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_agent_config_changed()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_notify('agent_config_changed', json_build_object(
        'agent_id', COALESCE(NEW.id, OLD.id),
        'agent_name', COALESCE(NEW.name, OLD.name),
        'operation', TG_OP
    )::text);
    RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: notify_agents_changed(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_agents_changed()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_notify('agent_config_changed', json_build_object(
        'op', TG_OP,
        'agent', COALESCE(NEW.name, OLD.name),
        'ts', NOW()
    )::text);
    RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: notify_coder_queue_change(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_coder_queue_change()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM pg_notify('coder_queue', json_build_object(
      'op', 'insert',
      'id', NEW.id,
      'repo', NEW.repo,
      'issue', NEW.issue_number,
      'status', NEW.status
    )::text);
  ELSIF TG_OP = 'UPDATE' AND OLD.status != NEW.status THEN
    PERFORM pg_notify('coder_queue', json_build_object(
      'op', 'status_change',
      'id', NEW.id,
      'repo', NEW.repo,
      'issue', NEW.issue_number,
      'old_status', OLD.status,
      'new_status', NEW.status
    )::text);
  END IF;
  RETURN NEW;
END;
$$;

--
-- Name: notify_delegation_change(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_delegation_change()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  PERFORM pg_notify('delegation_changed', TG_TABLE_NAME);
  RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: notify_delegation_change(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION notify_delegation_change() IS 'SHORT-TERM: Triggers DELEGATION_CONTEXT.md regeneration. Remove when PR #9 long-term solution is active.';

--
-- Name: notify_gambling_change(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_gambling_change()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_notify('gambling_changed', TG_TABLE_NAME || ':' || TG_OP);
    RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: notify_schema_change(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_schema_change()
RETURNS event_trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    obj record;
    payload text;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
        payload := json_build_object(
            'command_tag', obj.command_tag,
            'object_type', obj.object_type,
            'schema_name', obj.schema_name,
            'object_identity', obj.object_identity,
            'query', current_query()
        )::text;
        PERFORM pg_notify('schema_changed', payload);
    END LOOP;
END;
$$;

--
-- Name: notify_system_config_changed(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_system_config_changed()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
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
$$;

--
-- Name: notify_workflow_step_change(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_workflow_step_change()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
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
$$;

--
-- Name: prevent_locked_project_update(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION prevent_locked_project_update()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  -- If record is locked and we're not just unlocking it
  IF OLD.locked = TRUE THEN
    -- Allow ONLY if we're explicitly unlocking (locked going from true to false)
    IF NEW.locked = FALSE THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Project % is locked. Set locked=FALSE first to modify.', OLD.name;
  END IF;
  RETURN NEW;
END;
$$;

--
-- Name: protect_agent_deletes(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION protect_agent_deletes()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF current_user NOT IN ('newhart', 'postgres') THEN
        RAISE EXCEPTION 'Agent tables are managed by the Agent Architecture domain (newhart). Contact the Agent Architecture domain for changes.';
    END IF;
    RETURN OLD;
END;
$$;

--
-- Name: protect_agent_writes(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION protect_agent_writes()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF current_user NOT IN ('newhart', 'postgres') THEN
        RAISE EXCEPTION 'Agent tables are managed by the Agent Architecture domain (newhart). Contact the Agent Architecture domain for changes.';
    END IF;
    RETURN NEW;
END;
$$;

--
-- Name: protect_bootstrap_context_writes(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION protect_bootstrap_context_writes()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  IF current_user NOT IN ('newhart', 'postgres') THEN
    RAISE EXCEPTION 'agent_bootstrap_context is managed by Newhart (Agent Design/Management). Contact Newhart for changes.';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: protect_library_writes(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION protect_library_writes()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF current_user NOT IN ('athena', 'postgres') THEN
        RAISE EXCEPTION 'Library tables are managed by the Library domain (athena). Contact the Library domain for changes.';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: protect_research_writes(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION protect_research_writes()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF current_user NOT IN ('scout', 'postgres') THEN
        RAISE EXCEPTION 'Research tables are managed by the Research domain (scout). Contact the Research domain for changes.';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: queue_test_failure(text, integer, text, text, integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION queue_test_failure(
    p_repo text,
    p_parent_issue integer,
    p_test_name text,
    p_error_message text,
    p_priority integer DEFAULT 7
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_title TEXT;
  v_issue_number INTEGER;
  v_queue_id INTEGER;
BEGIN
  v_title := 'Test failure: ' || p_test_name;

  v_issue_number := -1 * (SELECT COALESCE(MAX(ABS(issue_number)), 0) + 1
                          FROM git_issue_queue
                          WHERE repo = p_repo AND issue_number < 0);

  INSERT INTO git_issue_queue (
    repo, issue_number, title, priority, status, source,
    parent_issue_id, error_message
  ) VALUES (
    p_repo, v_issue_number, v_title, p_priority, 'pending_tests',
    'test_failure',
    (SELECT id FROM git_issue_queue WHERE repo = p_repo AND issue_number = p_parent_issue),
    p_error_message
  )
  RETURNING id INTO v_queue_id;

  PERFORM pg_notify('test_failure', json_build_object(
    'queue_id', v_queue_id,
    'repo', p_repo,
    'parent_issue', p_parent_issue,
    'test_name', p_test_name,
    'error', LEFT(p_error_message, 500)
  )::text);

  RETURN v_queue_id;
END;
$$;

--
-- Name: queue_test_failure(text, integer, text, text, integer); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION queue_test_failure(text, integer, text, text, integer) IS 'Queue a test failure for Coder to fix. Creates placeholder issue, notifies for gh issue creation.';

--
-- Name: queue_test_failure(text, integer, text, text, text, text[], jsonb, integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION queue_test_failure(
    p_repo text,
    p_parent_issue integer,
    p_test_name text,
    p_error_message text,
    p_test_file text DEFAULT NULL,
    p_code_files text[] DEFAULT NULL,
    p_context jsonb DEFAULT '{}',
    p_priority integer DEFAULT 7
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_title TEXT;
  v_issue_number INTEGER;
  v_queue_id INTEGER;
  v_parent_title TEXT;
  v_full_context JSONB;
  v_semantic_context JSONB;
  v_query_text TEXT;
BEGIN
  v_title := 'Test failure: ' || p_test_name;

  SELECT title INTO v_parent_title
  FROM git_issue_queue
  WHERE repo = p_repo AND issue_number = p_parent_issue;

  v_query_text := p_test_name || ' ' || COALESCE(p_test_file, '') || ' ' || p_error_message;

  SELECT jsonb_agg(jsonb_build_object(
    'source_type', source_type,
    'source_id', source_id,
    'content', LEFT(content, 500),
    'relevance', 'high'
  ))
  INTO v_semantic_context
  FROM (
    SELECT source_type, source_id, content
    FROM memory_embeddings
    WHERE content ILIKE '%' || p_test_name || '%'
       OR content ILIKE '%' || COALESCE(p_test_file, 'NOMATCH') || '%'
    LIMIT 5
  ) relevant;

  v_full_context := p_context || jsonb_build_object(
    'parent_title', v_parent_title,
    'test_file', p_test_file,
    'code_files', p_code_files,
    'queued_at', NOW(),
    'semantic_context', COALESCE(v_semantic_context, '[]'::jsonb)
  );

  v_issue_number := -1 * (SELECT COALESCE(MAX(ABS(issue_number)), 0) + 1
                          FROM git_issue_queue
                          WHERE repo = p_repo AND issue_number < 0);

  INSERT INTO git_issue_queue (
    repo, issue_number, title, priority, status, source,
    parent_issue_id, error_message, test_file, code_files, context
  ) VALUES (
    p_repo, v_issue_number, v_title, p_priority, 'pending_tests',
    'test_failure',
    (SELECT id FROM git_issue_queue WHERE repo = p_repo AND issue_number = p_parent_issue),
    p_error_message, p_test_file, p_code_files, v_full_context
  )
  RETURNING id INTO v_queue_id;

  PERFORM pg_notify('test_failure', json_build_object(
    'queue_id', v_queue_id,
    'repo', p_repo,
    'parent_issue', p_parent_issue,
    'parent_title', v_parent_title,
    'test_name', p_test_name,
    'test_file', p_test_file,
    'code_files', p_code_files,
    'error', LEFT(p_error_message, 1000),
    'context', v_full_context
  )::text);

  RETURN v_queue_id;
END;
$$;

--
-- Name: research_conclusions_search_trigger(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION research_conclusions_search_trigger()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.summary, '') || ' ' || COALESCE(NEW.full_content, ''));
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

--
-- Name: research_findings_search_trigger(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION research_findings_search_trigger()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', COALESCE(NEW.content, ''));
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

--
-- Name: research_tasks_search_trigger(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION research_tasks_search_trigger()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.search_vector := to_tsvector('english', COALESCE(NEW.title, '') || ' ' || COALESCE(NEW.query, '') || ' ' || COALESCE(NEW.methodology, ''));
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

--
-- Name: roll_d100(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION roll_d100()
RETURNS TABLE(roll integer, task_name varchar, task_description text, workflow_id integer, skill_name varchar, tool_name varchar, estimated_minutes integer)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    rolled_value INTEGER;
BEGIN
    rolled_value := floor(random() * 100 + 1)::int;

    -- Log the roll
    UPDATE motivation_d100 m
    SET times_rolled = m.times_rolled + 1, last_rolled = NOW()
    WHERE m.roll = rolled_value AND m.task_name IS NOT NULL;

    -- Return the result
    RETURN QUERY
    SELECT m.roll, m.task_name, m.task_description, m.workflow_id, m.skill_name, m.tool_name, m.estimated_minutes
    FROM motivation_d100 m
    WHERE m.roll = rolled_value;
END;
$$;

--
-- Name: roll_d100(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION roll_d100() IS 'Roll the D100 motivation die - returns task if one exists at that number';

--
-- Name: search_media(text, integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION search_media(
    query_text text,
    result_limit integer DEFAULT 20
)
RETURNS TABLE(id integer, media_type varchar, title varchar, creator varchar, summary text, rank real)
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        mc.id,
        mc.media_type,
        mc.title,
        mc.creator,
        mc.summary,
        ts_rank(mc.search_vector, plainto_tsquery('english', query_text)) as rank
    FROM media_consumed mc
    WHERE mc.search_vector @@ plainto_tsquery('english', query_text)
    ORDER BY rank DESC
    LIMIT result_limit;
END;
$$;

--
-- Name: search_memories(vector, integer, double precision); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION search_memories(
    query_embedding vector,
    match_count integer DEFAULT 5,
    similarity_threshold double precision DEFAULT 0.7
)
RETURNS TABLE(id integer, source_type varchar, source_id text, content text, similarity double precision)
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        me.id,
        me.source_type,
        me.source_id,
        me.content,
        1 - (me.embedding <=> query_embedding) AS similarity
    FROM memory_embeddings me
    WHERE 1 - (me.embedding <=> query_embedding) > similarity_threshold
    ORDER BY me.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

--
-- Name: search_research_text(text, integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION search_research_text(
    search_query text,
    result_limit integer DEFAULT 20
)
RETURNS TABLE(source_type text, source_id integer, title text, content_snippet text, rank real)
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM (
        SELECT 'task'::TEXT, rt.id, rt.title, LEFT(rt.query, 300),
               ts_rank(rt.search_vector, plainto_tsquery('english', search_query))
        FROM research_tasks rt
        WHERE rt.search_vector @@ plainto_tsquery('english', search_query)
        UNION ALL
        SELECT 'finding'::TEXT, rf.id, rf.finding_type::TEXT, LEFT(rf.content, 300),
               ts_rank(rf.search_vector, plainto_tsquery('english', search_query))
        FROM research_findings rf
        WHERE rf.search_vector @@ plainto_tsquery('english', search_query)
          AND rf.is_current = true
        UNION ALL
        SELECT 'conclusion'::TEXT, rc.id, rc.title, LEFT(rc.summary, 300),
               ts_rank(rc.search_vector, plainto_tsquery('english', search_query))
        FROM research_conclusions rc
        WHERE rc.search_vector @@ plainto_tsquery('english', search_query)
          AND rc.is_current = true
    ) combined
    ORDER BY rank DESC
    LIMIT result_limit;
END;
$$;

--
-- Name: send_agent_message(text, text, text[]); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION send_agent_message(
    p_sender text,
    p_message text,
    p_recipients text[]
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
AS $$
DECLARE
    v_id        INTEGER;
    v_sender    TEXT;
    v_recipients TEXT[];
BEGIN
    -- Validate inputs
    IF p_message IS NULL OR trim(p_message) = '' THEN
        RAISE EXCEPTION 'send_agent_message: message cannot be empty';
    END IF;

    IF p_recipients IS NULL OR array_length(p_recipients, 1) IS NULL THEN
        RAISE EXCEPTION 'send_agent_message: recipients cannot be NULL or empty — use ARRAY[''*''] for broadcast';
    END IF;

    -- Normalize to lowercase
    v_sender := LOWER(p_sender);
    v_recipients := ARRAY(SELECT LOWER(unnest(p_recipients)));


    -- Bypass gate and insert
    SET LOCAL agent_chat.bypass_gate = 'on';
    INSERT INTO agent_chat (sender, message, recipients)
    VALUES (v_sender, p_message, v_recipients)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

--
-- Name: chat(text, varchar); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION chat(
    p_message text,
    p_sender varchar DEFAULT 'nova'
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM send_agent_message(p_sender, p_message, 'system', NULL);
END;
$$;

--
-- Name: enforce_agent_chat_function_use(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION enforce_agent_chat_function_use()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF current_setting('agent_chat.bypass_gate', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'Direct INSERT on agent_chat is not allowed. Use send_agent_message() instead.';
    END IF;
    RETURN NEW;
END;
$$;

--
-- Name: should_skip_issue(text[]); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION should_skip_issue(
    p_labels text[]
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN p_labels && ARRAY['paused', 'blocked', 'on-hold', 'wontfix', 'waiting'];
END;
$$;

--
-- Name: get_next_coder_issue(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_next_coder_issue()
RETURNS TABLE(id integer, repo text, issue_number integer, title text)
LANGUAGE sql
VOLATILE
AS $$
  SELECT id, repo, issue_number, title
  FROM git_issue_queue
  WHERE status = 'tests_approved'
    AND NOT should_skip_issue(COALESCE(labels, '{}'))
  ORDER BY priority DESC, created_at
  LIMIT 1;
$$;

--
-- Name: table_comment(text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION table_comment(
    tbl text
)
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
  SELECT obj_description(tbl::regclass, 'pg_class');
$$;

--
-- Name: update_agent_turn_context_timestamp(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_agent_turn_context_timestamp()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

--
-- Name: update_agents_timestamp(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_agents_timestamp()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

--
-- Name: update_media_search_vector(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_media_search_vector()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.creator, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.notes, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.summary, '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.insights, '')), 'C');
  RETURN NEW;
END;
$$;

--
-- Name: update_music_analysis_search_vector(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_music_analysis_search_vector()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.analysis_type, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.analysis_summary, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.notes, '')), 'C');
    RETURN NEW;
END;
$$;

--
-- Name: update_music_search_vector(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_music_search_vector()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', COALESCE(NEW.genre, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.subgenre, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.mood, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.album, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.lyrics, '')), 'C') ||
        setweight(to_tsvector('english', COALESCE(NEW.label, '')), 'D') ||
        setweight(to_tsvector('english', COALESCE(NEW.producer, '')), 'D');
    RETURN NEW;
END;
$$;

--
-- Name: update_work_status_on_publication(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_work_status_on_publication()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    UPDATE works SET status = 'published' WHERE id = NEW.work_id AND status = 'complete';
    RETURN NEW;
END;
$$;

--
-- Name: update_works_timestamp(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_works_timestamp()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

--
-- Name: upsert_domain_context(text, text, text, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION upsert_domain_context(
    p_domain_name text,
    p_file_key text,
    p_content text,
    p_description text DEFAULT NULL,
    p_updated_by text DEFAULT 'system'
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
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
$$;

--
-- Name: upsert_global_context(text, text, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION upsert_global_context(
    p_file_key text,
    p_content text,
    p_description text DEFAULT NULL,
    p_updated_by text DEFAULT 'system'
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
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
$$;

--
-- Name: fk_citation_library_work; Type: CONSTRAINT; Schema: -; Owner: -
--

ALTER TABLE research_citations
ADD CONSTRAINT fk_citation_library_work FOREIGN KEY (library_work_id) REFERENCES library_works (id) ON DELETE SET NULL;

--
-- Name: protect_research_citations; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_research_citations
    BEFORE INSERT OR UPDATE OR DELETE ON research_citations
    FOR EACH ROW
    EXECUTE FUNCTION protect_research_writes();

--
-- Name: protect_research_conclusions; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_research_conclusions
    BEFORE INSERT OR UPDATE OR DELETE ON research_conclusions
    FOR EACH ROW
    EXECUTE FUNCTION protect_research_writes();

--
-- Name: protect_research_findings; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_research_findings
    BEFORE INSERT OR UPDATE OR DELETE ON research_findings
    FOR EACH ROW
    EXECUTE FUNCTION protect_research_writes();

--
-- Name: protect_research_projects; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_research_projects
    BEFORE INSERT OR UPDATE OR DELETE ON research_projects
    FOR EACH ROW
    EXECUTE FUNCTION protect_research_writes();

--
-- Name: protect_research_provenance; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_research_provenance
    BEFORE INSERT OR UPDATE OR DELETE ON research_provenance
    FOR EACH ROW
    EXECUTE FUNCTION protect_research_writes();

--
-- Name: protect_research_taggings; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_research_taggings
    BEFORE INSERT OR UPDATE OR DELETE ON research_taggings
    FOR EACH ROW
    EXECUTE FUNCTION protect_research_writes();

--
-- Name: protect_research_tags; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_research_tags
    BEFORE INSERT OR UPDATE OR DELETE ON research_tags
    FOR EACH ROW
    EXECUTE FUNCTION protect_research_writes();

--
-- Name: protect_research_tasks; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_research_tasks
    BEFORE INSERT OR UPDATE OR DELETE ON research_tasks
    FOR EACH ROW
    EXECUTE FUNCTION protect_research_writes();

--
-- Name: protect_turn_context; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_turn_context
    BEFORE INSERT OR UPDATE OR DELETE ON agent_turn_context
    FOR EACH ROW
    EXECUTE FUNCTION protect_bootstrap_context_writes();

--
-- Name: trg_agent_turn_context_updated_at; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_agent_turn_context_updated_at
    BEFORE UPDATE ON agent_turn_context
    FOR EACH ROW
    EXECUTE FUNCTION update_agent_turn_context_timestamp();

--
-- Name: trg_research_conclusions_search; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_research_conclusions_search
    BEFORE INSERT OR UPDATE ON research_conclusions
    FOR EACH ROW
    EXECUTE FUNCTION research_conclusions_search_trigger();

--
-- Name: trg_research_findings_search; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_research_findings_search
    BEFORE INSERT OR UPDATE ON research_findings
    FOR EACH ROW
    EXECUTE FUNCTION research_findings_search_trigger();

--
-- Name: trg_research_tasks_search; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_research_tasks_search
    BEFORE INSERT OR UPDATE ON research_tasks
    FOR EACH ROW
    EXECUTE FUNCTION research_tasks_search_trigger();

--
-- Name: delegation_knowledge; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW delegation_knowledge AS
 SELECT id,
    key,
    value,
    confidence,
    data_type,
    source,
    learned_at,
    updated_at
   FROM entity_facts ef
  WHERE entity_id = 1 AND (key::text = ANY (ARRAY['delegates_to'::character varying::text, 'task_delegation'::character varying::text, 'agent_capability'::character varying::text, 'agent_success'::character varying::text, 'agent_failure'::character varying::text]))
  ORDER BY (
        CASE key
            WHEN 'delegates_to'::text THEN 1
            WHEN 'task_delegation'::text THEN 2
            WHEN 'agent_capability'::text THEN 3
            WHEN 'agent_success'::text THEN 4
            WHEN 'agent_failure'::text THEN 5
            ELSE 6
        END), confidence DESC, value;

--
-- Name: v_agent_chat_recent; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_agent_chat_recent AS
 SELECT id,
    sender,
    message,
    recipients,
    reply_to,
    "timestamp"
   FROM agent_chat
  WHERE "timestamp" > (now() - '30 days'::interval)
  ORDER BY "timestamp" DESC;

--
-- Name: v_agent_chat_stats; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_agent_chat_stats AS
 SELECT count(*) AS total_messages,
    count(*) FILTER (WHERE "timestamp" > (now() - '24:00:00'::interval)) AS messages_24h,
    count(*) FILTER (WHERE "timestamp" > (now() - '7 days'::interval)) AS messages_7d,
    count(DISTINCT sender) AS unique_senders,
    pg_size_pretty(pg_total_relation_size('agent_chat'::regclass)) AS table_size,
    min("timestamp") AS oldest_message,
    max("timestamp") AS newest_message
   FROM agent_chat;

--
-- Name: v_agent_spawn_stats; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_agent_spawn_stats AS
 SELECT agent_name,
    domain,
    count(*) AS total_spawns,
    count(*) FILTER (WHERE status = 'completed'::text) AS completed,
    count(*) FILTER (WHERE status = 'failed'::text) AS failed,
    count(*) FILTER (WHERE status = ANY (ARRAY['pending'::text, 'spawning'::text, 'running'::text])) AS active,
    avg(EXTRACT(epoch FROM completed_at - spawned_at)) FILTER (WHERE completed_at IS NOT NULL) AS avg_duration_seconds
   FROM agent_spawns
  GROUP BY agent_name, domain;

--
-- Name: v_agents; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_agents AS
 SELECT id,
    name,
    role,
    provider,
    model,
    access_method,
    persistent,
    array_to_string(skills, ', '::text) AS skills_list,
    status,
    credential_ref
   FROM agents
  WHERE status::text = 'active'::text
  ORDER BY persistent DESC, role, name;

--
-- Name: v_entity_facts; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_entity_facts AS
 SELECT e.id,
    e.name,
    e.type,
    ef.key,
    ef.value,
    ef.data,
    ef.learned_at
   FROM entities e
     JOIN entity_facts ef ON e.id = ef.entity_id;

--
-- Name: v_event_timeline; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_event_timeline AS
 SELECT ev.event_date,
    ev.title,
    ev.description,
    array_agg(DISTINCT e.name) FILTER (WHERE e.name IS NOT NULL) AS entities,
    array_agg(DISTINCT p.name) FILTER (WHERE p.name IS NOT NULL) AS places
   FROM events ev
     LEFT JOIN event_entities ee ON ev.id = ee.event_id
     LEFT JOIN entities e ON ee.entity_id = e.id
     LEFT JOIN event_places ep ON ev.id = ep.event_id
     LEFT JOIN places p ON ep.place_id = p.id
  GROUP BY ev.id, ev.event_date, ev.title, ev.description
  ORDER BY ev.event_date DESC;

--
-- Name: v_gambling_summary; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_gambling_summary AS
 SELECT l.name AS log_name,
    l.location,
    count(e.id) AS sessions,
    sum(e.amount) AS total,
    sum(
        CASE
            WHEN e.amount > 0::numeric THEN e.amount
            ELSE 0::numeric
        END) AS total_won,
    sum(
        CASE
            WHEN e.amount < 0::numeric THEN e.amount
            ELSE 0::numeric
        END) AS total_lost
   FROM gambling_logs l
     LEFT JOIN gambling_entries e ON e.log_id = l.id
  WHERE l.entity_id = 2
  GROUP BY l.id, l.name, l.location;

--
-- Name: v_media_queue_pending; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_media_queue_pending AS
 SELECT mq.id,
    mq.url,
    mq.file_path,
    mq.media_type,
    mq.title,
    mq.creator,
    mq.priority,
    mq.status,
    mq.requested_by,
    mq.requested_at,
    mq.processing_started_at,
    mq.completed_at,
    mq.result_media_id,
    mq.error_message,
    mq.metadata,
    e.name AS requested_by_name
   FROM media_queue mq
     LEFT JOIN entities e ON mq.requested_by = e.id
  WHERE mq.status::text = 'pending'::text
  ORDER BY mq.priority, mq.requested_at;

--
-- Name: v_media_with_tags; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_media_with_tags AS
 SELECT mc.id,
    mc.media_type,
    mc.title,
    mc.creator,
    mc.url,
    mc.consumed_date,
    mc.consumed_by,
    mc.rating,
    mc.notes,
    mc.transcript,
    mc.created_at,
    mc.summary,
    mc.metadata,
    mc.source_file,
    mc.status,
    mc.ingested_by,
    mc.ingested_at,
    mc.search_vector,
    array_agg(mt.tag) FILTER (WHERE mt.tag IS NOT NULL) AS tags
   FROM media_consumed mc
     LEFT JOIN media_tags mt ON mc.id = mt.media_id
  GROUP BY mc.id;

--
-- Name: v_metamours; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_metamours AS
 SELECT DISTINCT e1.name AS person,
    e3.name AS metamour,
    e2.name AS connected_through
   FROM entities e1
     JOIN entity_relationships r1 ON e1.id = r1.entity_a
     JOIN entities e2 ON r1.entity_b = e2.id
     JOIN entity_relationships r2 ON e2.id = r2.entity_a OR e2.id = r2.entity_b
     JOIN entities e3 ON r2.entity_a = e3.id OR r2.entity_b = e3.id
  WHERE e1.name::text = 'I)ruid'::text AND (r1.relationship::text = ANY (ARRAY['partner'::character varying::text, 'casual'::character varying::text])) AND e3.id <> e1.id AND e3.id <> e2.id AND e3.type::text = 'person'::text;

--
-- Name: v_pending_tasks; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_pending_tasks AS
 SELECT t.id,
    t.title,
    t.status,
    t.priority,
    t.due_date,
    p.name AS project_name,
    t.parent_task_id,
    t.notes
   FROM tasks t
     LEFT JOIN projects p ON t.project_id = p.id
  WHERE t.status::text = ANY (ARRAY['pending'::character varying::text, 'in_progress'::character varying::text, 'blocked'::character varying::text])
  ORDER BY t.priority, t.due_date;

--
-- Name: v_pending_test_failures; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_pending_test_failures AS
 SELECT id,
    repo,
    title,
    error_message,
    created_at
   FROM git_issue_queue
  WHERE source = 'test_failure'::text AND issue_number < 0
  ORDER BY created_at;


COMMENT ON VIEW v_pending_test_failures IS 'Test failures that need GitHub issues created via gh CLI';

--
-- Name: v_portfolio_allocation; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_portfolio_allocation AS
 SELECT p.asset_class,
    count(*) AS num_positions,
    sum(p.quantity * COALESCE(pc.price, p.avg_price)) AS market_value,
    sum(p.cost_basis) AS total_cost_basis,
    sum(p.quantity * COALESCE(pc.price, p.avg_price)) - sum(p.cost_basis) AS unrealized_pl
   FROM positions p
     LEFT JOIN price_cache_v2 pc ON p.symbol::text = pc.symbol::text AND p.asset_class::text = pc.asset_class::text
  WHERE p.sold_at IS NULL
  GROUP BY p.asset_class;

--
-- Name: v_ralph_active; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_ralph_active AS
 SELECT session_series_id,
    agent_id,
    max(iteration) AS current_iteration,
    ( SELECT r2.status
           FROM ralph_sessions r2
          WHERE r2.session_series_id = r1.session_series_id
          ORDER BY r2.iteration DESC
         LIMIT 1) AS latest_status,
    min(created_at) AS started_at,
    sum(tokens_used) AS total_tokens,
    sum(cost) AS total_cost
   FROM ralph_sessions r1
  GROUP BY session_series_id, agent_id
 HAVING (( SELECT r2.status
           FROM ralph_sessions r2
          WHERE r2.session_series_id = r1.session_series_id
          ORDER BY r2.iteration DESC
         LIMIT 1)) = ANY (ARRAY['PENDING'::text, 'RUNNING'::text, 'CONTINUE'::text]);

--
-- Name: v_relationships; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_relationships AS
 SELECT e1.name AS entity_a_name,
    e1.type AS entity_a_type,
    r.relationship,
    e2.name AS entity_b_name,
    e2.type AS entity_b_type,
    r.since
   FROM entity_relationships r
     JOIN entities e1 ON r.entity_a = e1.id
     JOIN entities e2 ON r.entity_b = e2.id;

--
-- Name: v_task_tree; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_task_tree AS
 WITH RECURSIVE task_hierarchy AS (
         SELECT tasks.id,
            tasks.title,
            tasks.status,
            tasks.priority,
            tasks.parent_task_id,
            tasks.project_id,
            tasks.due_date,
            0 AS depth,
            ARRAY[tasks.id] AS path
           FROM tasks
          WHERE tasks.parent_task_id IS NULL
        UNION ALL
         SELECT t.id,
            t.title,
            t.status,
            t.priority,
            t.parent_task_id,
            t.project_id,
            t.due_date,
            th.depth + 1,
            th.path || t.id
           FROM tasks t
             JOIN task_hierarchy th ON t.parent_task_id = th.id
        )
 SELECT id,
    title,
    status,
    priority,
    parent_task_id,
    project_id,
    due_date,
    depth,
    path
   FROM task_hierarchy
  ORDER BY path;

--
-- Name: v_users; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_users AS
 SELECT e.id,
    e.name,
    e.full_name,
    e.type,
    max(
        CASE
            WHEN ef.key::text = 'phone'::text THEN ef.value
            ELSE NULL::text
        END) AS phone,
    max(
        CASE
            WHEN ef.key::text = 'email'::text THEN ef.value
            ELSE NULL::text
        END) AS email,
    max(
        CASE
            WHEN ef.key::text = 'current_timezone'::text THEN ef.value
            ELSE NULL::text
        END) AS current_timezone,
    max(
        CASE
            WHEN ef.key::text = 'home_timezone'::text THEN ef.value
            ELSE NULL::text
        END) AS home_timezone,
    max(
        CASE
            WHEN ef.key::text = 'onboarded'::text THEN ef.value
            ELSE NULL::text
        END) AS onboarded_date,
    max(
        CASE
            WHEN ef.key::text = 'owner_number'::text THEN ef.value
            ELSE NULL::text
        END) AS owner_number,
    max(
        CASE
            WHEN ef.key::text = 'signal_uuid'::text THEN ef.value
            ELSE NULL::text
        END) AS signal_uuid
   FROM entities e
     JOIN entity_facts ef ON e.id = ef.entity_id
  WHERE (EXISTS ( SELECT 1
           FROM entity_facts ef2
          WHERE ef2.entity_id = e.id AND (ef2.key::text = ANY (ARRAY['is_user'::character varying::text, 'onboarded'::character varying::text]))))
  GROUP BY e.id, e.name, e.full_name, e.type;

--
-- Name: workflow_steps_detail; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW workflow_steps_detail AS
 SELECT w.name AS workflow_name,
    w.description AS workflow_description,
    ws.step_order,
    ws.domain,
    ws.domains,
    ws.description AS step_description,
    ws.produces_deliverable,
    ws.deliverable_type,
    ws.deliverable_description,
    ws.estimated_duration_minutes
   FROM workflow_steps ws
     JOIN workflows w ON w.id = ws.workflow_id
  ORDER BY w.name, ws.step_order;

--
-- Name: agent_turn_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_turn_context FROM newhart;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_citations FROM newhart;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_conclusions FROM newhart;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_findings FROM newhart;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_projects FROM newhart;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_provenance FROM newhart;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_taggings FROM newhart;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_tags FROM newhart;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_tasks FROM newhart;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_actions_id_seq TO athena;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_actions_id_seq TO scout;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO athena;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO scout;

--
-- Name: agent_chat_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_chat_id_seq TO athena;

--
-- Name: agent_chat_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_chat_id_seq TO scout;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_domains_id_seq TO athena;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_domains_id_seq TO scout;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_jobs_id_seq TO athena;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_jobs_id_seq TO scout;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_modifications_id_seq TO athena;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_modifications_id_seq TO scout;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_spawns_id_seq TO athena;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_spawns_id_seq TO scout;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_turn_context_id_seq TO athena;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_turn_context_id_seq TO scout;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agents_id_seq TO athena;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agents_id_seq TO scout;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE ai_models_id_seq TO athena;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE ai_models_id_seq TO scout;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE artwork_id_seq TO athena;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE artwork_id_seq TO scout;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE certificates_id_seq TO athena;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE certificates_id_seq TO scout;

--
-- Name: conversations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE conversations_id_seq TO athena;

--
-- Name: conversations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE conversations_id_seq TO scout;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entities_id_seq TO athena;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entities_id_seq TO scout;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO athena;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO scout;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_facts_id_seq TO athena;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_facts_id_seq TO scout;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_relationships_id_seq TO athena;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_relationships_id_seq TO scout;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE events_archive_id_seq TO athena;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE events_archive_id_seq TO scout;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE events_id_seq TO athena;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE events_id_seq TO scout;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE extraction_metrics_id_seq TO athena;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE extraction_metrics_id_seq TO scout;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE fact_change_log_id_seq TO athena;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE fact_change_log_id_seq TO scout;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE gambling_entries_id_seq TO athena;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE gambling_entries_id_seq TO scout;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE gambling_logs_id_seq TO athena;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE gambling_logs_id_seq TO scout;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE git_issue_queue_id_seq TO athena;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE git_issue_queue_id_seq TO scout;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE job_messages_id_seq TO athena;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE job_messages_id_seq TO scout;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE lessons_archive_id_seq TO athena;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE lessons_archive_id_seq TO scout;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE lessons_id_seq TO athena;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE lessons_id_seq TO scout;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_authors_id_seq TO athena;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_authors_id_seq TO scout;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_tags_id_seq TO athena;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_tags_id_seq TO scout;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_works_id_seq TO athena;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_works_id_seq TO scout;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_consumed_id_seq TO athena;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_consumed_id_seq TO scout;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_queue_id_seq TO athena;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_queue_id_seq TO scout;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_tags_id_seq TO athena;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_tags_id_seq TO scout;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO athena;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO scout;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE memory_embeddings_id_seq TO athena;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE memory_embeddings_id_seq TO scout;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_analysis_id_seq TO athena;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_analysis_id_seq TO scout;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_library_id_seq TO athena;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_library_id_seq TO scout;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE place_properties_id_seq TO athena;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE place_properties_id_seq TO scout;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE places_id_seq TO athena;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE places_id_seq TO scout;

--
-- Name: portfolio_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_history_id_seq TO athena;

--
-- Name: portfolio_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_history_id_seq TO scout;

--
-- Name: portfolio_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_metrics_id_seq TO athena;

--
-- Name: portfolio_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_metrics_id_seq TO scout;

--
-- Name: portfolio_positions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_positions_id_seq TO athena;

--
-- Name: portfolio_positions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_positions_id_seq TO scout;

--
-- Name: portfolio_snapshots_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_snapshots_id_seq TO athena;

--
-- Name: portfolio_snapshots_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_snapshots_id_seq TO scout;

--
-- Name: portfolio_updates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_updates_id_seq TO athena;

--
-- Name: portfolio_updates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE portfolio_updates_id_seq TO scout;

--
-- Name: positions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE positions_id_seq TO athena;

--
-- Name: positions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE positions_id_seq TO scout;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE preferences_id_seq TO athena;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE preferences_id_seq TO scout;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE project_tasks_id_seq TO athena;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE project_tasks_id_seq TO scout;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE projects_id_seq TO athena;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE projects_id_seq TO scout;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE publications_id_seq TO athena;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE publications_id_seq TO scout;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE ralph_sessions_id_seq TO athena;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE ralph_sessions_id_seq TO scout;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_citations_id_seq TO athena;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_citations_id_seq TO scout;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_conclusions_id_seq TO athena;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_conclusions_id_seq TO scout;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_findings_id_seq TO athena;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_findings_id_seq TO scout;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_projects_id_seq TO athena;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_projects_id_seq TO scout;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_provenance_id_seq TO athena;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_provenance_id_seq TO scout;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_taggings_id_seq TO athena;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_taggings_id_seq TO scout;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_tags_id_seq TO athena;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_tags_id_seq TO scout;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_tasks_id_seq TO athena;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_tasks_id_seq TO scout;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_history_id_seq TO athena;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_history_id_seq TO scout;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_preferences_id_seq TO athena;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_preferences_id_seq TO scout;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_wishlist_id_seq TO athena;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_wishlist_id_seq TO scout;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE skills_id_seq TO athena;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE skills_id_seq TO scout;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tags_id_seq TO athena;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tags_id_seq TO scout;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tasks_id_seq TO athena;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tasks_id_seq TO scout;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tools_id_seq TO athena;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tools_id_seq TO scout;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE unsolved_problems_id_seq TO athena;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE unsolved_problems_id_seq TO scout;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE vehicles_id_seq TO athena;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE vehicles_id_seq TO scout;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE vocabulary_id_seq TO athena;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE vocabulary_id_seq TO scout;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE workflow_steps_id_seq TO athena;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE workflow_steps_id_seq TO scout;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE workflows_id_seq TO athena;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE workflows_id_seq TO scout;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE works_id_seq TO athena;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE works_id_seq TO scout;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO athena;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO coder;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO erato;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO gem;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO gidget;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO graybeard;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO iris;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO "nova-staging";

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO openproject_user;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO scout;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_actions TO ticker;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO athena;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO coder;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO erato;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO gem;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO gidget;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO graybeard;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO iris;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO "nova-staging";

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO openproject_user;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO scout;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_aliases TO ticker;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO athena;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO coder;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO erato;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO gem;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO gidget;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO graybeard;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO iris;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO "nova-staging";

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO openproject_user;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO scout;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_bootstrap_context TO ticker;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO athena;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO coder;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO erato;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO gem;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO gidget;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO graybeard;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO iris;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO "nova-staging";

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO openproject_user;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO scout;

--
-- Name: agent_chat; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat TO ticker;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO athena;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO coder;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO erato;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO gem;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO gidget;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO graybeard;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO iris;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO "nova-staging";

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO openproject_user;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO scout;

--
-- Name: agent_chat_processed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_chat_processed TO ticker;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO athena;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO coder;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO erato;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO gem;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO gidget;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO graybeard;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO iris;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO "nova-staging";

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO openproject_user;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO scout;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_domains TO ticker;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO athena;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO coder;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO erato;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO gem;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO gidget;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO graybeard;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO iris;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO "nova-staging";

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO openproject_user;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO scout;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_jobs TO ticker;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO athena;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO coder;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO erato;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO gem;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO gidget;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO graybeard;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO iris;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO "nova-staging";

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO openproject_user;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO scout;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_modifications TO ticker;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO athena;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO coder;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO erato;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO gem;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO gidget;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO graybeard;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO iris;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO "nova-staging";

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO openproject_user;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO scout;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_spawns TO ticker;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO athena;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO coder;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO erato;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO gem;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO gidget;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO graybeard;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO iris;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO "nova-staging";

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO openproject_user;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO scout;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_system_config TO ticker;

--
-- Name: agent_turn_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agent_turn_context TO nova;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO athena;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO coder;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO erato;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO gem;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO gidget;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO graybeard;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO iris;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO "nova-staging";

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO openproject_user;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO scout;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE agents TO ticker;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO athena;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO coder;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO erato;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO gem;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO gidget;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO graybeard;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO iris;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO "nova-staging";

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO openproject_user;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO scout;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ai_models TO ticker;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO athena;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO coder;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO erato;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO gem;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO gidget;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO graybeard;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO iris;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO "nova-staging";

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO openproject_user;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO scout;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE artwork TO ticker;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO athena;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO coder;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO erato;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO gem;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO gidget;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO graybeard;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO iris;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO "nova-staging";

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO openproject_user;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO scout;

--
-- Name: asset_classes; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE asset_classes TO ticker;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO athena;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO coder;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO erato;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO gem;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO gidget;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO graybeard;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO iris;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO "nova-staging";

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO openproject_user;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO scout;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE bootstrap_context_config TO ticker;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO athena;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO coder;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO erato;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO gem;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO gidget;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO graybeard;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO iris;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO "nova-staging";

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO openproject_user;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO scout;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE certificates TO ticker;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO athena;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO coder;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO erato;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO gem;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO gidget;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO graybeard;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO iris;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO "nova-staging";

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO openproject_user;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO scout;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE channel_activity TO ticker;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO athena;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO coder;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO erato;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO gem;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO gidget;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO graybeard;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO iris;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO "nova-staging";

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO openproject_user;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO scout;

--
-- Name: conversations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE conversations TO ticker;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO athena;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO coder;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO erato;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO gem;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO gidget;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO graybeard;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO iris;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO "nova-staging";

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO openproject_user;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO scout;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entities TO ticker;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO athena;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO coder;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO erato;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO gem;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO gidget;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO graybeard;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO iris;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO "nova-staging";

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO openproject_user;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO scout;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_fact_conflicts TO ticker;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO athena;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO coder;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO erato;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO gem;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO gidget;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO graybeard;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO iris;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO "nova-staging";

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO openproject_user;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO scout;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts TO ticker;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO athena;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO coder;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO erato;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO gem;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO gidget;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO graybeard;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO iris;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO "nova-staging";

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO openproject_user;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO scout;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_facts_archive TO ticker;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO athena;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO coder;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO erato;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO gem;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO gidget;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO graybeard;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO iris;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO "nova-staging";

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO openproject_user;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO scout;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE entity_relationships TO ticker;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO athena;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO coder;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO erato;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO gem;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO gidget;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO graybeard;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO iris;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO "nova-staging";

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO openproject_user;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO scout;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_entities TO ticker;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO athena;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO coder;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO erato;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO gem;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO gidget;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO graybeard;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO iris;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO "nova-staging";

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO openproject_user;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO scout;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_places TO ticker;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO athena;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO coder;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO erato;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO gem;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO gidget;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO graybeard;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO iris;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO "nova-staging";

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO openproject_user;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO scout;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE event_projects TO ticker;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO athena;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO coder;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO erato;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO gem;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO gidget;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO graybeard;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO iris;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO "nova-staging";

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO openproject_user;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO scout;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events TO ticker;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO athena;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO coder;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO erato;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO gem;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO gidget;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO graybeard;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO iris;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO "nova-staging";

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO openproject_user;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO scout;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE events_archive TO ticker;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO athena;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO coder;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO erato;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO gem;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO gidget;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO graybeard;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO iris;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO "nova-staging";

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO openproject_user;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO scout;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE extraction_metrics TO ticker;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO athena;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO coder;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO erato;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO gem;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO gidget;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO graybeard;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO iris;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO "nova-staging";

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO openproject_user;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO scout;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE fact_change_log TO ticker;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO athena;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO coder;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO erato;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO gem;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO gidget;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO graybeard;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO iris;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO "nova-staging";

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO openproject_user;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO scout;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_entries TO ticker;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO athena;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO coder;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO erato;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO gem;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO gidget;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO graybeard;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO iris;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO "nova-staging";

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO openproject_user;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO scout;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE gambling_logs TO ticker;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO athena;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO coder;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO erato;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO gem;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO gidget;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO graybeard;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO iris;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO "nova-staging";

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO openproject_user;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO scout;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE git_issue_queue TO ticker;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO athena;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO coder;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO erato;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO gem;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO gidget;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO graybeard;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO iris;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO "nova-staging";

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO openproject_user;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO scout;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE job_messages TO ticker;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO athena;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO coder;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO erato;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO gem;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO gidget;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO graybeard;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO iris;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO "nova-staging";

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO openproject_user;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO scout;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons TO ticker;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO athena;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO coder;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO erato;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO gem;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO gidget;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO graybeard;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO iris;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO "nova-staging";

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO openproject_user;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO scout;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE lessons_archive TO ticker;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE library_authors TO athena;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO coder;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO erato;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO gem;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO gidget;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO graybeard;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO iris;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO "nova-staging";

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO openproject;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO openproject_user;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO scout;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO ticker;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE library_tags TO athena;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO coder;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO erato;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO gem;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO gidget;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO graybeard;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO iris;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO "nova-staging";

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO openproject;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO openproject_user;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO scout;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO ticker;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE library_work_authors TO athena;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO coder;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO erato;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO gem;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO gidget;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO graybeard;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO iris;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO "nova-staging";

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO openproject;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO openproject_user;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO scout;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO ticker;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE library_work_relationships TO athena;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO coder;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO erato;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO gem;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO gidget;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO graybeard;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO iris;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO "nova-staging";

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO openproject;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO openproject_user;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO scout;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO ticker;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE library_work_tags TO athena;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO coder;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO erato;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO gem;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO gidget;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO graybeard;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO iris;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO "nova-staging";

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO openproject;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO openproject_user;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO scout;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO ticker;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE library_works TO athena;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO coder;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO erato;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO gem;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO gidget;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO graybeard;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO iris;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO "nova-staging";

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO openproject;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO openproject_user;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO scout;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO ticker;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO athena;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO coder;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO erato;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO gem;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO gidget;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO graybeard;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO iris;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO "nova-staging";

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO openproject_user;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO scout;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_consumed TO ticker;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO athena;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO coder;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO erato;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO gem;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO gidget;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO graybeard;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO iris;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO "nova-staging";

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO openproject_user;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO scout;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_queue TO ticker;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO athena;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO coder;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO erato;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO gem;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO gidget;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO graybeard;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO iris;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO "nova-staging";

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO openproject_user;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO scout;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE media_tags TO ticker;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO athena;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO coder;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO erato;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO gem;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO gidget;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO graybeard;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO iris;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO "nova-staging";

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO openproject_user;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO scout;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings TO ticker;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO athena;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO coder;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO erato;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO gem;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO gidget;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO graybeard;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO iris;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO "nova-staging";

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO openproject_user;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO scout;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_embeddings_archive TO ticker;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO athena;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO coder;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO erato;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO gem;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO gidget;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO graybeard;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO iris;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO "nova-staging";

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO openproject_user;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO scout;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE memory_type_priorities TO ticker;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO athena;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO coder;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO erato;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO gem;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO gidget;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO graybeard;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO iris;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO "nova-staging";

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO openproject_user;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO scout;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE motivation_d100 TO ticker;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO athena;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO coder;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO erato;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO gem;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO gidget;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO graybeard;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO iris;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO "nova-staging";

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO openproject_user;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO scout;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_analysis TO ticker;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO athena;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO coder;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO erato;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO gem;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO gidget;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO graybeard;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO iris;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO "nova-staging";

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO openproject_user;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO scout;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE music_library TO ticker;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO athena;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO coder;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO erato;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO gem;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO gidget;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO graybeard;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO iris;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO "nova-staging";

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO openproject_user;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO scout;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE place_properties TO ticker;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO athena;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO coder;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO erato;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO gem;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO gidget;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO graybeard;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO iris;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO "nova-staging";

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO openproject_user;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO scout;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE places TO ticker;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO athena;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO coder;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO erato;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO gem;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO gidget;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO graybeard;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO iris;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO "nova-staging";

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO openproject_user;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO scout;

--
-- Name: pm_domain_portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE pm_domain_portfolio_snapshots TO ticker;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO athena;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO coder;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO erato;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO gem;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO gidget;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO graybeard;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO iris;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO "nova-staging";

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO openproject_user;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO scout;

--
-- Name: portfolio_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_history TO ticker;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO athena;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO coder;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO erato;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO gem;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO gidget;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO graybeard;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO iris;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO "nova-staging";

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO openproject_user;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO scout;

--
-- Name: portfolio_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_metrics TO ticker;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO athena;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO coder;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO erato;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO gem;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO gidget;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO graybeard;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO iris;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO "nova-staging";

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO openproject_user;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO scout;

--
-- Name: portfolio_positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_positions TO ticker;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO athena;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO coder;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO erato;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO gem;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO gidget;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO graybeard;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO iris;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO "nova-staging";

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO openproject_user;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO scout;

--
-- Name: portfolio_snapshots; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_snapshots TO ticker;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO athena;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO coder;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO erato;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO gem;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO gidget;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO graybeard;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO iris;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO "nova-staging";

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO openproject_user;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO scout;

--
-- Name: portfolio_updates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE portfolio_updates TO ticker;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO athena;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO coder;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO erato;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO gem;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO gidget;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO graybeard;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO iris;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO "nova-staging";

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO openproject_user;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO scout;

--
-- Name: positions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE positions TO ticker;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO athena;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO coder;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO erato;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO gem;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO gidget;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO graybeard;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO iris;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO "nova-staging";

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO openproject_user;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO scout;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE preferences TO ticker;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO athena;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO coder;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO erato;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO gem;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO gidget;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO graybeard;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO iris;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO "nova-staging";

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO openproject_user;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO scout;

--
-- Name: price_cache_v2; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE price_cache_v2 TO ticker;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO athena;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO coder;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO erato;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO gem;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO gidget;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO graybeard;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO iris;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO "nova-staging";

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO openproject_user;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO scout;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_entities TO ticker;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO athena;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO coder;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO erato;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO gem;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO gidget;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO graybeard;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO iris;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO "nova-staging";

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO openproject_user;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO scout;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE project_tasks TO ticker;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO athena;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO coder;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO erato;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO gem;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO gidget;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO graybeard;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO iris;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO "nova-staging";

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO openproject_user;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO scout;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE projects TO ticker;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO athena;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO coder;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO gem;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO gidget;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO graybeard;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO iris;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO "nova-staging";

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO openproject_user;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO scout;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE publications TO ticker;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO athena;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO coder;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO erato;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO gem;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO gidget;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO graybeard;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO iris;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO "nova-staging";

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO openproject_user;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO scout;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ralph_sessions TO ticker;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_citations TO nova;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_citations TO openproject;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE research_citations TO scout;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_conclusions TO nova;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_conclusions TO openproject;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE research_conclusions TO scout;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_findings TO nova;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_findings TO openproject;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE research_findings TO scout;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_projects TO nova;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_projects TO openproject;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE research_projects TO scout;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_provenance TO nova;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_provenance TO openproject;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE research_provenance TO scout;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_taggings TO nova;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_taggings TO openproject;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE research_taggings TO scout;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_tags TO nova;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_tags TO openproject;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE research_tags TO scout;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_tasks TO nova;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_tasks TO openproject;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE research_tasks TO scout;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO athena;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO coder;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO erato;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO gem;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO gidget;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO graybeard;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO iris;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO openproject_user;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO scout;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_history TO ticker;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO athena;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO coder;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO erato;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO gem;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO gidget;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO graybeard;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO iris;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO openproject_user;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO scout;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_preferences TO ticker;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO athena;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO coder;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO erato;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO gem;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO gidget;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO graybeard;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO iris;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO openproject_user;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO scout;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE shopping_wishlist TO ticker;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO athena;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO coder;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO erato;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO gem;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO gidget;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO graybeard;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO iris;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO "nova-staging";

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO openproject_user;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO scout;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE skills TO ticker;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO athena;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO coder;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO gem;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO gidget;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO graybeard;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO iris;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO "nova-staging";

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO openproject_user;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO scout;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tags TO ticker;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO athena;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO coder;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO erato;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO gem;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO gidget;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO graybeard;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO iris;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO "nova-staging";

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO openproject_user;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO scout;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tasks TO ticker;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO athena;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO coder;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO erato;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO gem;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO gidget;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO graybeard;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO iris;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO "nova-staging";

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO openproject_user;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO scout;

--
-- Name: ticker_portfolio; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE ticker_portfolio TO ticker;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO athena;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO coder;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO erato;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO gem;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO gidget;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO graybeard;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO iris;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO "nova-staging";

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO openproject_user;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO scout;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE tools TO ticker;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO athena;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO coder;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO erato;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO gem;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO gidget;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO graybeard;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO iris;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO "nova-staging";

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO openproject_user;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO scout;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE unsolved_problems TO ticker;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO athena;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO coder;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO erato;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO gem;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO gidget;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO graybeard;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO iris;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO "nova-staging";

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO openproject_user;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO scout;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vehicles TO ticker;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO athena;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO coder;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO erato;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO gem;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO gidget;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO graybeard;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO iris;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO "nova-staging";

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO openproject_user;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO scout;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE vocabulary TO ticker;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO athena;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO coder;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO gem;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO gidget;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO graybeard;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO iris;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO "nova-staging";

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO openproject_user;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO scout;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE work_tags TO ticker;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO athena;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO coder;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO erato;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO gem;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO gidget;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO graybeard;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO iris;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO "nova-staging";

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO openproject_user;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO scout;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps TO ticker;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO athena;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO coder;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO erato;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO gem;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO gidget;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO graybeard;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO iris;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO "nova-staging";

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO openproject_user;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO scout;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflows TO ticker;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO athena;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO coder;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO gem;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO gidget;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO graybeard;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO iris;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO "nova-staging";

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO openproject_user;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO scout;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE works TO ticker;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO athena;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO coder;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO erato;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO gem;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO gidget;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO graybeard;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO iris;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO newhart;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO "nova-staging";

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO openproject_user;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO scout;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO ticker;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO athena;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO coder;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO erato;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO gem;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO gidget;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO graybeard;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO iris;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO newhart;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO "nova-staging";

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO openproject_user;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO scout;

--
-- Name: v_agent_chat_recent; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_recent TO ticker;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO athena;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO coder;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO erato;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO gem;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO gidget;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO graybeard;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO iris;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO newhart;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO "nova-staging";

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO openproject_user;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO scout;

--
-- Name: v_agent_chat_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_chat_stats TO ticker;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO athena;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO coder;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO erato;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO gem;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO gidget;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO graybeard;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO iris;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO newhart;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO "nova-staging";

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO openproject_user;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO scout;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO ticker;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO athena;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO coder;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO erato;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO gem;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO gidget;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO graybeard;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO iris;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO newhart;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO "nova-staging";

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO openproject_user;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO scout;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO ticker;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO athena;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO coder;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO erato;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO gem;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO gidget;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO graybeard;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO iris;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO newhart;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO "nova-staging";

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO openproject_user;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO scout;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO ticker;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO athena;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO coder;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO erato;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO gem;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO gidget;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO graybeard;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO iris;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO newhart;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO "nova-staging";

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO openproject_user;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO scout;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO ticker;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO athena;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO coder;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO erato;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO gem;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO gidget;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO graybeard;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO iris;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO newhart;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO "nova-staging";

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO openproject_user;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO scout;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO ticker;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO athena;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO coder;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO erato;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO gem;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO gidget;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO graybeard;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO iris;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO newhart;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO "nova-staging";

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO openproject_user;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO scout;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO ticker;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO athena;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO coder;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO erato;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO gem;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO gidget;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO graybeard;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO iris;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO newhart;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO "nova-staging";

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO openproject_user;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO scout;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO ticker;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO athena;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO coder;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO erato;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO gem;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO gidget;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO graybeard;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO iris;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO newhart;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO "nova-staging";

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO openproject_user;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO scout;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO ticker;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO athena;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO coder;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO erato;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO gem;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO gidget;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO graybeard;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO iris;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO newhart;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO "nova-staging";

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO openproject_user;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO scout;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO ticker;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO athena;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO coder;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO erato;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO gem;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO gidget;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO graybeard;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO iris;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO newhart;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO "nova-staging";

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO openproject_user;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO scout;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO ticker;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO athena;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO coder;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO erato;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO gem;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO gidget;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO graybeard;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO iris;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO newhart;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO "nova-staging";

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO openproject_user;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO scout;

--
-- Name: v_portfolio_allocation; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_portfolio_allocation TO ticker;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO athena;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO coder;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO erato;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO gem;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO gidget;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO graybeard;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO iris;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO newhart;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO "nova-staging";

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO openproject_user;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO scout;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO ticker;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO athena;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO coder;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO erato;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO gem;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO gidget;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO graybeard;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO iris;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO newhart;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO "nova-staging";

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO openproject_user;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO scout;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO ticker;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO athena;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO coder;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO erato;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO gem;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO gidget;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO graybeard;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO iris;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO newhart;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO "nova-staging";

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO openproject_user;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO scout;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO ticker;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO athena;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO coder;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO erato;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO gem;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO gidget;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO graybeard;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO iris;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO newhart;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO "nova-staging";

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO openproject_user;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO scout;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO ticker;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO athena;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO coder;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO erato;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO gem;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO gidget;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO graybeard;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO iris;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO newhart;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO "nova-staging";

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO openproject_user;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO scout;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO ticker;

