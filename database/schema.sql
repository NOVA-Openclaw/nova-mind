--
-- pgschema database dump
--

-- Dumped from database version PostgreSQL 16.14
-- Dumped by pgschema version 1.7.2


--
-- Name: nova:TABLES:argus; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO argus;

--
-- Name: nova:TABLES:athena; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO athena;

--
-- Name: nova:TABLES:coder; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO coder;

--
-- Name: nova:TABLES:conductor; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO conductor;

--
-- Name: nova:TABLES:erato; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO erato;

--
-- Name: nova:TABLES:flint; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO flint;

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
-- Name: nova:TABLES:hermes; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO hermes;

--
-- Name: nova:TABLES:iris; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO iris;

--
-- Name: nova:TABLES:marcie; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO marcie;

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
-- Name: nova:TABLES:quill; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO quill;

--
-- Name: nova:TABLES:scout; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO scout;

--
-- Name: nova:TABLES:scribe; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO scribe;

--
-- Name: nova:TABLES:ticker; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO ticker;

--
-- Name: postgres:SEQUENCES:argus; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO argus;

--
-- Name: postgres:SEQUENCES:athena; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO athena;

--
-- Name: postgres:SEQUENCES:coder; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO coder;

--
-- Name: postgres:SEQUENCES:conductor; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO conductor;

--
-- Name: postgres:SEQUENCES:erato; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO erato;

--
-- Name: postgres:SEQUENCES:flint; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO flint;

--
-- Name: postgres:SEQUENCES:gem; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO gem;

--
-- Name: postgres:SEQUENCES:gidget; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO gidget;

--
-- Name: postgres:SEQUENCES:hermes; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO hermes;

--
-- Name: postgres:SEQUENCES:iris; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO iris;

--
-- Name: postgres:SEQUENCES:marcie; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO marcie;

--
-- Name: postgres:SEQUENCES:newhart; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO newhart;

--
-- Name: postgres:SEQUENCES:nova; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO nova;

--
-- Name: postgres:SEQUENCES:quill; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO quill;

--
-- Name: postgres:SEQUENCES:scout; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO scout;

--
-- Name: postgres:SEQUENCES:scribe; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO scribe;

--
-- Name: postgres:SEQUENCES:ticker; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO ticker;

--
-- Name: postgres:TABLES:argus; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO argus;

--
-- Name: postgres:TABLES:athena; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO athena;

--
-- Name: postgres:TABLES:coder; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO coder;

--
-- Name: postgres:TABLES:conductor; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO conductor;

--
-- Name: postgres:TABLES:erato; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO erato;

--
-- Name: postgres:TABLES:flint; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO flint;

--
-- Name: postgres:TABLES:gem; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO gem;

--
-- Name: postgres:TABLES:gidget; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO gidget;

--
-- Name: postgres:TABLES:hermes; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO hermes;

--
-- Name: postgres:TABLES:iris; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO iris;

--
-- Name: postgres:TABLES:marcie; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO marcie;

--
-- Name: postgres:TABLES:newhart; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO newhart;

--
-- Name: postgres:TABLES:nova; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO nova;

--
-- Name: postgres:TABLES:quill; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO quill;

--
-- Name: postgres:TABLES:scout; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO scout;

--
-- Name: postgres:TABLES:scribe; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO scribe;

--
-- Name: postgres:TABLES:ticker; Type: DEFAULT_PRIVILEGE; Schema: default_privileges; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO ticker;

--
-- Name: agent_bootstrap_context; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_bootstrap_context (
    id SERIAL,
    context_type text NOT NULL,
    file_key text NOT NULL,
    content text NOT NULL,
    description text,
    updated_at timestamptz DEFAULT now(),
    updated_by text DEFAULT CURRENT_USER,
    agent_name text,
    domain_names text[],
    CONSTRAINT agent_bootstrap_context_pkey PRIMARY KEY (id),
    CONSTRAINT agent_bootstrap_context_context_type_check CHECK (context_type IN ('UNIVERSAL'::text, 'GLOBAL'::text, 'DOMAIN'::text, 'AGENT'::text, 'SYSTEM'::text)),
    CONSTRAINT chk_domain_no_agent_name CHECK (context_type <> 'DOMAIN'::text OR agent_name IS NULL),
    CONSTRAINT chk_system_file_key CHECK (context_type <> 'SYSTEM'::text OR file_key = 'SYSTEM_PROMPT'::text),
    CONSTRAINT chk_universal_global_no_names CHECK ((context_type <> ALL (ARRAY['UNIVERSAL'::text, 'GLOBAL'::text])) OR agent_name IS NULL AND domain_names IS NULL)
);


COMMENT ON TABLE agent_bootstrap_context IS 'Bootstrap context entries. Agents may write to their own AGENT-scoped records (matching their db user). Newhart (Agent Design/Management domain) manages schema, cross-agent entries, and GLOBAL/UNIVERSAL-scoped records.';


COMMENT ON COLUMN agent_bootstrap_context.context_type IS 'GLOBAL (all agents) or DOMAIN (agents in specific domain)';


COMMENT ON COLUMN agent_bootstrap_context.file_key IS 'Identifier for context block, becomes filename in bootstrap';

--
-- Name: agent_bootstrap_context_domain_unique_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS agent_bootstrap_context_domain_unique_idx ON agent_bootstrap_context (file_key) WHERE (context_type = 'DOMAIN'::text);

--
-- Name: agent_bootstrap_context_system_unique_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS agent_bootstrap_context_system_unique_idx ON agent_bootstrap_context (context_type, COALESCE(agent_name, ''::text)) WHERE (context_type = 'SYSTEM'::text);

--
-- Name: agent_bootstrap_context_unique_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS agent_bootstrap_context_unique_idx ON agent_bootstrap_context (context_type, COALESCE(agent_name, ''::text), file_key) WHERE context_type IN ('UNIVERSAL'::text, 'GLOBAL'::text, 'AGENT'::text);

--
-- Name: idx_abc_agent_name; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_abc_agent_name ON agent_bootstrap_context (agent_name) WHERE (agent_name IS NOT NULL);

--
-- Name: agent_jobs; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_jobs (
    id SERIAL,
    title varchar(200),
    topic text,
    job_type varchar(50) DEFAULT 'message_response',
    agent_name varchar(50) NOT NULL,
    requester_agent varchar(50),
    parent_job_id integer,
    root_job_id integer,
    status varchar(20) DEFAULT 'pending',
    priority integer DEFAULT 5,
    notify_agents text[],
    deliverable_path text,
    deliverable_summary text,
    error_message text,
    created_at timestamptz DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT agent_jobs_pkey PRIMARY KEY (id),
    CONSTRAINT agent_jobs_parent_job_id_fkey FOREIGN KEY (parent_job_id) REFERENCES agent_jobs (id),
    CONSTRAINT agent_jobs_root_job_id_fkey FOREIGN KEY (root_job_id) REFERENCES agent_jobs (id)
);


COMMENT ON TABLE agent_jobs IS 'Agent job definitions. READ-ONLY except Newhart.';

--
-- Name: agent_jobs; Type: RLS; Schema: -; Owner: -
--

ALTER TABLE agent_jobs ENABLE ROW LEVEL SECURITY;

--
-- Name: agent_system_config; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_system_config (
    key text,
    value text NOT NULL,
    value_type text DEFAULT 'text' NOT NULL,
    description text,
    updated_at timestamp DEFAULT now(),
    updated_by text DEFAULT 'system',
    CONSTRAINT agent_system_config_pkey PRIMARY KEY (key)
);


COMMENT ON TABLE agent_system_config IS 'Agent system configuration. READ-ONLY except Newhart.';


COMMENT ON COLUMN agent_system_config.key IS 'Unique configuration key identifier';


COMMENT ON COLUMN agent_system_config.value IS 'Configuration value (stored as text, cast based on value_type)';


COMMENT ON COLUMN agent_system_config.value_type IS 'Type hint: text, json, boolean, number';


COMMENT ON COLUMN agent_system_config.description IS 'Human-readable description of what this config controls';


COMMENT ON COLUMN agent_system_config.updated_at IS 'Last modification timestamp';


COMMENT ON COLUMN agent_system_config.updated_by IS 'Agent or system that last modified this config';

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
-- Name: agents; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agents (
    id SERIAL,
    name varchar(100) NOT NULL,
    description text,
    role varchar(100),
    provider varchar(50),
    model varchar(100),
    access_method varchar(50) NOT NULL,
    access_details jsonb,
    skills text[],
    credential_ref varchar(200),
    status varchar(20) DEFAULT 'active',
    notes text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    persistent boolean DEFAULT true,
    instantiation_sop varchar(100),
    nickname varchar(50),
    instance_type varchar(20) DEFAULT 'subagent',
    home_dir varchar(255),
    unix_user varchar(50),
    collaborative boolean DEFAULT false,
    config_reasoning text,
    fallback_model varchar(100),
    collaborate jsonb,
    decision_criteria text,
    thinking varchar(20),
    fallback_models text[],
    pronouns varchar(50),
    allowed_subagents text[],
    is_default boolean DEFAULT false NOT NULL,
    context_type text DEFAULT 'persistent' NOT NULL,
    model_rationale text,
    parent_agents text[],
    heartbeat_enabled boolean DEFAULT false,
    heartbeat_every text,
    heartbeat_target text,
    heartbeat_to text,
    model_locked boolean DEFAULT false NOT NULL,
    CONSTRAINT agents_pkey PRIMARY KEY (id),
    CONSTRAINT agents_name_key UNIQUE (name),
    CONSTRAINT agents_context_type_check CHECK (context_type IN ('ephemeral'::text, 'persistent'::text)),
    CONSTRAINT agents_thinking_check CHECK (thinking::text IN ('off'::text, 'minimal'::text, 'low'::text, 'medium'::text, 'high'::text, 'xhigh'::text, 'adaptive'::text))
);


COMMENT ON TABLE agents IS 'Agent registry';


COMMENT ON COLUMN agents.access_details IS 'JSON: session_key, cli_command, endpoint URL, etc.';


COMMENT ON COLUMN agents.credential_ref IS '1Password item name or clawdbot config path for credentials';


COMMENT ON COLUMN agents.persistent IS 'true = always running, false = instantiated on-demand';


COMMENT ON COLUMN agents.instantiation_sop IS 'SOP name for how to instantiate this agent (for ephemeral agents)';


COMMENT ON COLUMN agents.nickname IS 'Short friendly name for easy reference';


COMMENT ON COLUMN agents.instance_type IS 'subagent (spawned session) or peer (separate Clawdbot instance)';


COMMENT ON COLUMN agents.home_dir IS 'Workspace path for peer agents';


COMMENT ON COLUMN agents.unix_user IS 'Unix username for peer agents';


COMMENT ON COLUMN agents.collaborative IS 'TRUE = work WITH NOVA in dialogue, FALSE = work FOR NOVA on tasks';


COMMENT ON COLUMN agents.config_reasoning IS 'Newhart-maintained notes explaining why this agent is configured as it is (model, persistent, collaborative, etc.)';


COMMENT ON COLUMN agents.fallback_model IS 'Fallback model if primary fails (auth issues, rate limits, etc.)';


COMMENT ON COLUMN agents.collaborate IS 'Collaboration scope: null = task-only, JSONB defines topics/areas where this agent can collaborate vs just execute. Example: {"allowed": ["architecture", "design"], "excluded": ["execution"]}';


COMMENT ON COLUMN agents.decision_criteria IS 'Criteria for when to spawn this agent - helps NOVA route tasks';


COMMENT ON COLUMN agents.model_rationale IS 'Model selection goals and justification: WHY this agent uses its model, what the role requires, past issues that drove changes, tradeoffs considered. Maintained by Newhart for weekly agent review.';


COMMENT ON COLUMN agents.parent_agents IS 'For subagent rows: array of peer/primary agent names whose gateways own this subagent. A subagent may have multiple parents (e.g. scout is shared by all peers). Used by get_agent_export_rows() to scope each gateway''s agents.json. NULL/empty for peer/primary agents themselves.';


COMMENT ON COLUMN agents.model_locked IS 'When true, weekly model reevaluation must skip this agent — do not change its primary model. Set by I)ruid directive.';

--
-- Name: idx_agents_single_default; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_agents_single_default ON agents (is_default) WHERE (is_default = true);

--
-- Name: idx_agents_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agents_status ON agents (status);

--
-- Name: agent_aliases; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_aliases (
    agent_id integer,
    alias varchar(100),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT agent_aliases_pkey PRIMARY KEY (agent_id, alias),
    CONSTRAINT agent_aliases_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES agents (id) ON DELETE CASCADE
);


COMMENT ON TABLE agent_aliases IS 'Agent aliases for flexible mention matching. Supports case-insensitive routing.';


COMMENT ON COLUMN agent_aliases.alias IS 'Alternative name/identifier for the agent (e.g., "assistant", "helper")';

--
-- Name: agent_modifications; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_modifications (
    id SERIAL,
    agent_id integer NOT NULL,
    modified_by text NOT NULL,
    field_changed text NOT NULL,
    old_value text,
    new_value text,
    modified_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT agent_modifications_pkey PRIMARY KEY (id),
    CONSTRAINT fk_agent_modifications_agent FOREIGN KEY (agent_id) REFERENCES agents (id) ON DELETE CASCADE
);


COMMENT ON TABLE agent_modifications IS 'Agent modification history. READ-ONLY except Newhart.';

--
-- Name: idx_agent_modifications_agent_id; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_modifications_agent_id ON agent_modifications (agent_id);

--
-- Name: idx_agent_modifications_modified_at; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_modifications_modified_at ON agent_modifications (modified_at DESC);

--
-- Name: agent_spawns; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_spawns (
    id SERIAL,
    trigger_source text NOT NULL,
    trigger_id text,
    trigger_payload jsonb,
    domain text,
    agent_id integer,
    agent_name text,
    session_key text,
    session_label text,
    task_summary text,
    status text DEFAULT 'pending',
    spawned_at timestamptz DEFAULT now(),
    completed_at timestamptz,
    result jsonb,
    CONSTRAINT agent_spawns_pkey PRIMARY KEY (id),
    CONSTRAINT agent_spawns_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES agents (id),
    CONSTRAINT valid_status CHECK (status IN ('pending'::text, 'spawning'::text, 'running'::text, 'completed'::text, 'failed'::text, 'skipped'::text))
);


COMMENT ON TABLE agent_spawns IS 'Tracks all agent spawns from the general-purpose spawner daemon';

--
-- Name: idx_agent_spawns_agent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_spawns_agent ON agent_spawns (agent_id);

--
-- Name: idx_agent_spawns_trigger; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_spawns_trigger ON agent_spawns (trigger_source, trigger_id);

--
-- Name: ai_models; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS ai_models (
    id SERIAL,
    model_id varchar(100) NOT NULL,
    provider varchar(50) NOT NULL,
    display_name varchar(100),
    context_window integer,
    cost_tier varchar(20),
    strengths text[],
    weaknesses text[],
    available boolean DEFAULT false,
    last_verified_at timestamptz,
    credential_ref varchar(200),
    notes text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    input_price_per_mtok numeric(10,4) DEFAULT NULL,
    output_price_per_mtok numeric(10,4) DEFAULT NULL,
    CONSTRAINT models_pkey PRIMARY KEY (id),
    CONSTRAINT models_model_id_key UNIQUE (model_id)
);


COMMENT ON TABLE ai_models IS 'Available AI models. NOVA maintains this; Newhart reads for agent assignments. Credentials and endpoints stored in 1Password (see credential_ref column).';


COMMENT ON COLUMN ai_models.input_price_per_mtok IS 'Cost per million input tokens in USD. NULL = unknown, 0 = free (local models).';


COMMENT ON COLUMN ai_models.output_price_per_mtok IS 'Cost per million output tokens in USD. NULL = unknown, 0 = free (local models).';

--
-- Name: artwork; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS artwork (
    id SERIAL,
    instagram_url text,
    instagram_media_id text,
    title text,
    caption text,
    theme text,
    original_prompt text,
    revised_prompt text,
    image_data bytea,
    image_filename text,
    posted_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now(),
    notes text,
    inspiration_source text,
    quality_score integer,
    nostr_event_id text,
    nostr_image_url text,
    x_tweet_id text,
    x_url text,
    image_model text,
    collection text,
    shop_eligible boolean DEFAULT false,
    shop_priority integer,
    printful_product_id text,
    printful_sync_status text DEFAULT 'pending',
    image_width integer,
    image_height integer,
    printful_product_url text,
    CONSTRAINT artwork_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE artwork IS 'Archive of NOVAs Instagram artwork. Reference for future compilation.';


COMMENT ON COLUMN artwork.image_data IS 'Raw image binary data (PNG/JPG)';


COMMENT ON COLUMN artwork.inspiration_source IS 'News snippet or source that inspired this artwork';


COMMENT ON COLUMN artwork.image_model IS 'Image generation model used (e.g. grok-imagine-image-pro, gpt-image-1, gemini-3-pro-image-preview)';


COMMENT ON COLUMN artwork.collection IS 'Curated collection: resilience, cosmic_perspective, quiet_fire, breakthrough';


COMMENT ON COLUMN artwork.shop_eligible IS 'Whether this piece is selected for the Printful shop';


COMMENT ON COLUMN artwork.shop_priority IS 'Display ordering within shop (lower = more prominent). NULL = unranked';


COMMENT ON COLUMN artwork.printful_product_id IS 'Printful product ID once synced';


COMMENT ON COLUMN artwork.printful_sync_status IS 'Printful sync state: pending, uploaded, live, error';


COMMENT ON COLUMN artwork.image_width IS 'Image width in pixels';


COMMENT ON COLUMN artwork.image_height IS 'Image height in pixels';

--
-- Name: idx_artwork_collection; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_artwork_collection ON artwork (collection) WHERE (collection IS NOT NULL);

--
-- Name: idx_artwork_shop; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_artwork_shop ON artwork (shop_eligible) WHERE (shop_eligible = true);

--
-- Name: bootstrap_context_config; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS bootstrap_context_config (
    key text,
    value jsonb NOT NULL,
    description text,
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT bootstrap_context_config_pkey PRIMARY KEY (key)
);


COMMENT ON TABLE bootstrap_context_config IS 'Configuration for bootstrap system behavior';

--
-- Name: channel_activity; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS channel_activity (
    channel varchar(50),
    last_message_at timestamptz DEFAULT now(),
    last_message_from varchar(100),
    CONSTRAINT channel_activity_pkey PRIMARY KEY (channel)
);


COMMENT ON TABLE channel_activity IS 'Tracks last message per channel for idle detection. Read/write: NOVA, Newhart.';

--
-- Name: channel_sessions; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS channel_sessions (
    id BIGSERIAL,
    session_key text,
    agent_id text DEFAULT 'main' NOT NULL,
    provider text NOT NULL,
    external_chat_id text NOT NULL,
    external_thread_id text,
    chat_type text NOT NULL,
    title text,
    group_subject text,
    group_space_id text,
    started_at timestamptz DEFAULT now() NOT NULL,
    last_message_at timestamptz,
    message_count integer DEFAULT 0,
    raw_metadata jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT channel_sessions_pkey PRIMARY KEY (id)
);

--
-- Name: idx_channel_sessions_last_msg; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_channel_sessions_last_msg ON channel_sessions (last_message_at DESC);

--
-- Name: idx_channel_sessions_provider_chat; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_channel_sessions_provider_chat ON channel_sessions (provider, external_chat_id, COALESCE(external_thread_id, ''::text));

--
-- Name: idx_channel_sessions_session_key; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_channel_sessions_session_key ON channel_sessions (session_key);

--
-- Name: comms_checks; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS comms_checks (
    id SERIAL,
    check_type text NOT NULL,
    checked_at timestamptz DEFAULT now() NOT NULL,
    platforms text[] DEFAULT '{}' NOT NULL,
    summary text,
    details jsonb DEFAULT '{}' NOT NULL,
    new_items_count integer DEFAULT 0 NOT NULL,
    escalations jsonb DEFAULT '[]',
    action_items jsonb DEFAULT '[]',
    cron_job_id text,
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT comms_checks_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE comms_checks IS 'Individual Hermes check run results. Each row = one social/email/digest check. Replaces memory/hermes-*.md files. Owner: Communications domain (hermes).';


COMMENT ON COLUMN comms_checks.details IS 'Structured results per platform. Example: {"x": {"mentions": [...], "dms": [...]}, "email": {"unread": 5, "handled": 3}, "nostr": {"mentions": [...]}}';

--
-- Name: idx_comms_checks_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_comms_checks_date ON comms_checks (checked_at DESC);

--
-- Name: idx_comms_checks_type_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_comms_checks_type_date ON comms_checks (check_type, checked_at DESC);

--
-- Name: comms_digests; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS comms_digests (
    id SERIAL,
    digest_date date NOT NULL,
    digest_type text DEFAULT 'daily' NOT NULL,
    markdown text,
    digest_data jsonb DEFAULT '{}' NOT NULL,
    platforms_covered text[] DEFAULT '{}' NOT NULL,
    total_items integer DEFAULT 0 NOT NULL,
    escalation_count integer DEFAULT 0 NOT NULL,
    action_items jsonb DEFAULT '[]',
    generated_at timestamptz DEFAULT now() NOT NULL,
    generated_by text DEFAULT 'hermes' NOT NULL,
    CONSTRAINT comms_digests_pkey PRIMARY KEY (id),
    CONSTRAINT comms_digests_digest_date_key UNIQUE (digest_date)
);


COMMENT ON TABLE comms_digests IS 'Daily/weekly communications digests. Replaces hermes-social-digest-*.md and NOVA_Comms_Digest_*.html. Owner: Communications domain (hermes).';


COMMENT ON COLUMN comms_digests.digest_data IS 'Structured digest for template rendering: {email_received, email_handled, email_escalated, email_notable_items[], social_mentions, social_dms, social_engagement, social_notable_items[], action_items[], patterns_notes}';

--
-- Name: idx_comms_digests_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_comms_digests_date ON comms_digests (digest_date DESC);

--
-- Name: comms_state; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS comms_state (
    platform text,
    state jsonb DEFAULT '{}' NOT NULL,
    last_checked_at timestamptz,
    updated_at timestamptz DEFAULT now() NOT NULL,
    updated_by text DEFAULT CURRENT_USER NOT NULL,
    CONSTRAINT comms_state_pkey PRIMARY KEY (platform)
);


COMMENT ON TABLE comms_state IS 'Per-platform communications tracking state (seen IDs, cursors). Replaces hermes-social-state.json. Owner: Communications domain (hermes).';


COMMENT ON COLUMN comms_state.platform IS 'Platform identifier: x, nostr, email, facebook, instagram';


COMMENT ON COLUMN comms_state.state IS 'Platform-specific JSONB state. For X: {accountId, lastSeenMentionId, seenMentionIds[], lastSeenDmId, seenDmIds[], dmsAvailable}. For Nostr: {pubkey, npub, seenNostrEventIds[]}. For email: {lastSeenMessageId, processedIds[]}';

--
-- Name: d100_roll_log; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS d100_roll_log (
    id SERIAL,
    roll integer NOT NULL,
    rolled_at timestamptz DEFAULT now(),
    announced_at timestamptz,
    CONSTRAINT d100_roll_log_pkey PRIMARY KEY (id),
    CONSTRAINT d100_roll_log_roll_check CHECK (roll >= 1 AND roll <= 100)
);

--
-- Name: idx_d100_roll_log_rolled_at; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_d100_roll_log_rolled_at ON d100_roll_log (rolled_at DESC);

--
-- Name: entities; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS entities (
    id SERIAL,
    name varchar(255) NOT NULL,
    type varchar(50) NOT NULL,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    last_seen timestamp,
    photo bytea,
    notes text,
    full_name varchar(255),
    nicknames text[],
    gender varchar(50),
    pronouns varchar(50),
    user_id varchar(255),
    auth_token varchar(255),
    collaborate boolean,
    collaboration_scope text,
    trust_level varchar(20) DEFAULT 'unknown',
    introduction_context text,
    capabilities jsonb,
    access_constraints jsonb,
    preferred_contact varchar(50),
    did text,
    alternate_spellings text[],
    CONSTRAINT entities_pkey PRIMARY KEY (id),
    CONSTRAINT entities_name_type_key UNIQUE (name, type),
    CONSTRAINT entities_user_id_key UNIQUE (user_id),
    CONSTRAINT entities_type_check CHECK (type::text IN ('person'::character varying, 'ai'::character varying, 'organization'::character varying, 'pet'::character varying, 'stuffed_animal'::character varying, 'character'::character varying, 'other'::character varying)),
    CONSTRAINT valid_collaboration_scope CHECK (collaboration_scope IS NULL OR (collaboration_scope IN ('full'::text, 'domain-specific'::text, 'supervised'::text)))
);


COMMENT ON TABLE entities IS 'People, AIs, organizations. NOVA has full access. Use entity_facts for attributes.';


COMMENT ON COLUMN entities.collaborate IS 'If true, collaborate with this entity. If false, task them. NULL = not assessed.';


COMMENT ON COLUMN entities.collaboration_scope IS 'full | domain-specific | supervised - determines collaboration breadth';


COMMENT ON COLUMN entities.trust_level IS 'Trust level for confidence scoring: owner, admin, user, unknown, untrusted';


COMMENT ON COLUMN entities.introduction_context IS 'How/why we connected with this entity, relationship context';


COMMENT ON COLUMN entities.capabilities IS 'What this entity can do - domains, skills, tools';


COMMENT ON COLUMN entities.access_constraints IS 'Topics/data this entity should not see';


COMMENT ON COLUMN entities.preferred_contact IS 'Preferred communication method: signal, email, slack, telegram, whatsapp, etc.';


COMMENT ON COLUMN entities.did IS 'W3C Decentralized Identifier (DID) for this entity. Format: did:<method>:<identifier>. First populated for NOVA (did:web:renaissancemachine.ai), extensible to all entities.';

--
-- Name: idx_entities_alternate_spellings_gin; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entities_alternate_spellings_gin ON entities USING gin (alternate_spellings);

--
-- Name: idx_entities_name; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entities_name ON entities (name);

--
-- Name: idx_entities_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entities_type ON entities (type);

--
-- Name: agent_domains; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_domains (
    id SERIAL,
    agent_id integer NOT NULL,
    domain_topic varchar(255) NOT NULL,
    source_entity_id integer,
    vote_count integer DEFAULT 1,
    created_at timestamp DEFAULT now(),
    last_confirmed timestamp DEFAULT now(),
    notes text,
    keywords text[],
    CONSTRAINT agent_domains_pkey PRIMARY KEY (id),
    CONSTRAINT agent_domains_domain_topic_key UNIQUE (domain_topic),
    CONSTRAINT agent_domains_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES agents (id) ON DELETE CASCADE,
    CONSTRAINT agent_domains_source_entity_id_fkey FOREIGN KEY (source_entity_id) REFERENCES entities (id)
);


COMMENT ON TABLE agent_domains IS 'Agent domain assignments. READ-ONLY except Newhart.';


COMMENT ON COLUMN agent_domains.domain_topic IS 'The topic/responsibility this agent owns';


COMMENT ON COLUMN agent_domains.source_entity_id IS 'Entity who assigned this domain (for attribution)';


COMMENT ON COLUMN agent_domains.vote_count IS 'Reinforcement count - incremented when domain assignment is reconfirmed';

--
-- Name: idx_agent_domains_agent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_domains_agent ON agent_domains (agent_id);

--
-- Name: idx_agent_domains_keywords_gin; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_domains_keywords_gin ON agent_domains USING gin (keywords);

--
-- Name: idx_agent_domains_topic; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_domains_topic ON agent_domains (domain_topic);

--
-- Name: blockers; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS blockers (
    id SERIAL,
    source_type varchar(50) NOT NULL,
    source_ref varchar(255) NOT NULL,
    description text NOT NULL,
    needs text NOT NULL,
    entity_id integer NOT NULL,
    priority integer DEFAULT 5,
    status varchar(20) DEFAULT 'open',
    first_seen timestamptz DEFAULT now(),
    last_seen timestamptz DEFAULT now(),
    satisfied_at timestamptz,
    CONSTRAINT blockers_pkey PRIMARY KEY (id),
    CONSTRAINT blockers_source_unique UNIQUE (source_type, source_ref),
    CONSTRAINT blockers_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id),
    CONSTRAINT blockers_source_type_check CHECK (source_type::text IN ('task'::character varying, 'github_issue'::character varying, 'workflow_run'::character varying, 'unanswered_question'::character varying, 'agent_chat_request'::character varying)),
    CONSTRAINT blockers_status_check CHECK (status::text IN ('open'::character varying, 'satisfied'::character varying))
);

--
-- Name: idx_blockers_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_blockers_entity ON blockers (entity_id);

--
-- Name: idx_blockers_priority_first_seen; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_blockers_priority_first_seen ON blockers (priority, first_seen, id);

--
-- Name: idx_blockers_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_blockers_status ON blockers (status);

--
-- Name: certificates; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS certificates (
    id SERIAL,
    entity_id integer NOT NULL,
    fingerprint varchar(128) NOT NULL,
    serial varchar(64) NOT NULL,
    subject_dn varchar(512) NOT NULL,
    issued_at timestamp DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at timestamp,
    revoked_at timestamp,
    revocation_reason varchar(255),
    device_name varchar(255),
    notes text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT certificates_pkey PRIMARY KEY (id),
    CONSTRAINT certificates_fingerprint_key UNIQUE (fingerprint),
    CONSTRAINT certificates_serial_key UNIQUE (serial),
    CONSTRAINT certificates_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id)
);


COMMENT ON TABLE certificates IS 'Client certificates issued by NOVA CA. Security-sensitive. Verify before modifications.';


COMMENT ON COLUMN certificates.fingerprint IS 'SHA256 fingerprint of the certificate';


COMMENT ON COLUMN certificates.serial IS 'Certificate serial number';


COMMENT ON COLUMN certificates.revoked_at IS 'If set, certificate is revoked and should be rejected';

--
-- Name: idx_certificates_entity_id; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_certificates_entity_id ON certificates (entity_id);

--
-- Name: channel_transcripts; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS channel_transcripts (
    id BIGSERIAL,
    session_id bigint NOT NULL,
    external_message_id text NOT NULL,
    timestamp timestamptz NOT NULL,
    sender_id text,
    sender_name text,
    sender_username text,
    sender_tag text,
    sender_entity_id bigint,
    role text DEFAULT 'user' NOT NULL,
    content text,
    content_type text DEFAULT 'text',
    raw_metadata jsonb,
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT channel_transcripts_pkey PRIMARY KEY (id),
    CONSTRAINT channel_transcripts_sender_entity_id_fkey FOREIGN KEY (sender_entity_id) REFERENCES entities (id),
    CONSTRAINT channel_transcripts_session_id_fkey FOREIGN KEY (session_id) REFERENCES channel_sessions (id) ON DELETE CASCADE
);

--
-- Name: idx_channel_transcripts_external_sender; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_channel_transcripts_external_sender ON channel_transcripts (sender_id, "timestamp");

--
-- Name: idx_channel_transcripts_provider_msg; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_channel_transcripts_provider_msg ON channel_transcripts (session_id, external_message_id);

--
-- Name: idx_channel_transcripts_sender_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_channel_transcripts_sender_entity ON channel_transcripts (sender_entity_id, "timestamp");

--
-- Name: idx_channel_transcripts_session_time; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_channel_transcripts_session_time ON channel_transcripts (session_id, "timestamp");

--
-- Name: entity_fact_conflicts; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS entity_fact_conflicts (
    id SERIAL,
    entity_id integer,
    key varchar(255),
    fact_id_a integer,
    fact_id_b integer,
    value_a text,
    value_b text,
    confidence_a real,
    confidence_b real,
    resolution varchar(50),
    resolved_at timestamptz,
    resolved_by varchar(50),
    created_at timestamptz DEFAULT now(),
    CONSTRAINT entity_fact_conflicts_pkey PRIMARY KEY (id),
    CONSTRAINT entity_fact_conflicts_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id)
);


COMMENT ON TABLE entity_fact_conflicts IS 'Conflicts between entity facts requiring resolution. Part of the truth reconciliation system.';

--
-- Name: entity_facts; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS entity_facts (
    id SERIAL,
    entity_id integer,
    key varchar(255) NOT NULL,
    value text NOT NULL,
    data jsonb,
    confidence double precision DEFAULT 1.0,
    learned_at timestamp DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
    visibility varchar(20) DEFAULT 'public',
    privacy_scope integer[],
    visibility_reason text,
    last_confirmed_at timestamptz DEFAULT now(),
    decay_rate real,
    source_channel_transcript_id bigint,
    source_channel_session_id bigint,
    extraction_count integer DEFAULT 1,
    expires timestamptz,
    durability varchar(20) DEFAULT 'long_term' NOT NULL,
    category text DEFAULT 'observation' NOT NULL,
    CONSTRAINT entity_facts_pkey PRIMARY KEY (id),
    CONSTRAINT entity_facts_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
    CONSTRAINT entity_facts_source_channel_session_id_fkey FOREIGN KEY (source_channel_session_id) REFERENCES channel_sessions (id),
    CONSTRAINT entity_facts_source_channel_transcript_id_fkey FOREIGN KEY (source_channel_transcript_id) REFERENCES channel_transcripts (id),
    CONSTRAINT chk_confidence CHECK (confidence >= 0::double precision AND confidence <= 1::double precision),
    CONSTRAINT chk_durability CHECK (durability::text IN ('permanent'::character varying, 'long_term'::character varying, 'short_term'::character varying, 'ephemeral'::character varying))
);


COMMENT ON TABLE entity_facts IS 'Key-value facts about entities. Check current_timezone for I)ruid before time-based actions.';


COMMENT ON COLUMN entity_facts.visibility IS 'Privacy level: public (anyone), trusted (close relationships), private (source only)';


COMMENT ON COLUMN entity_facts.privacy_scope IS 'Array of entity IDs explicitly allowed to see this fact (overrides visibility)';


COMMENT ON COLUMN entity_facts.visibility_reason IS 'Reason visibility deviated from user default (audit trail)';


COMMENT ON COLUMN entity_facts.source_channel_transcript_id IS 'FK to channel_transcripts row that triggered this fact extraction (#170)';


COMMENT ON COLUMN entity_facts.source_channel_session_id IS 'FK to channel_sessions row (denormalised for fast session-level queries)';

--
-- Name: idx_entity_facts_category; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_category ON entity_facts (category);

--
-- Name: idx_entity_facts_channel_session; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_channel_session ON entity_facts (source_channel_session_id) WHERE (source_channel_session_id IS NOT NULL);

--
-- Name: idx_entity_facts_channel_transcript; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_channel_transcript ON entity_facts (source_channel_transcript_id) WHERE (source_channel_transcript_id IS NOT NULL);

--
-- Name: idx_entity_facts_confidence; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_confidence ON entity_facts (confidence) WHERE (confidence < (1.0)::double precision);

--
-- Name: idx_entity_facts_durability; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_durability ON entity_facts (durability);

--
-- Name: idx_entity_facts_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_entity ON entity_facts (entity_id);

--
-- Name: idx_entity_facts_key; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_key ON entity_facts (key);

--
-- Name: idx_entity_facts_privacy_scope; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_privacy_scope ON entity_facts USING gin (privacy_scope);

--
-- Name: idx_entity_facts_value_trgm; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_value_trgm ON entity_facts USING gin (lower(value) gin_trgm_ops);

--
-- Name: idx_entity_facts_visibility; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_visibility ON entity_facts (visibility);

--
-- Name: entity_fact_sources; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS entity_fact_sources (
    id SERIAL,
    fact_id integer NOT NULL,
    source_entity_id integer NOT NULL,
    source_citation text,
    attribution_count integer DEFAULT 1,
    first_seen timestamptz DEFAULT now(),
    last_seen timestamptz DEFAULT now(),
    source_url text,
    CONSTRAINT entity_fact_sources_pkey PRIMARY KEY (id),
    CONSTRAINT uq_fact_source UNIQUE (fact_id, source_entity_id),
    CONSTRAINT entity_fact_sources_fact_id_fkey FOREIGN KEY (fact_id) REFERENCES entity_facts (id) ON DELETE CASCADE,
    CONSTRAINT entity_fact_sources_source_entity_id_fkey FOREIGN KEY (source_entity_id) REFERENCES entities (id)
);

--
-- Name: idx_efs_fact_id; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_efs_fact_id ON entity_fact_sources (fact_id);

--
-- Name: idx_efs_source_entity_id; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_efs_source_entity_id ON entity_fact_sources (source_entity_id);

--
-- Name: entity_facts_archive; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS entity_facts_archive (
    id integer,
    entity_id integer,
    key varchar(255),
    value text,
    data jsonb,
    confidence double precision,
    learned_at timestamp,
    updated_at timestamp,
    visibility varchar(20),
    privacy_scope integer[],
    visibility_reason text,
    last_confirmed_at timestamptz,
    decay_rate real,
    archived_at timestamptz DEFAULT now(),
    archive_reason varchar(50),
    archived_by varchar(50) DEFAULT 'decay_script',
    extraction_count integer DEFAULT 1,
    durability varchar(20) DEFAULT 'long_term',
    category text DEFAULT 'observation',
    expires timestamptz
);


COMMENT ON TABLE entity_facts_archive IS 'Archived entity facts from decay/cleanup processes. Historical record of previously stored knowledge.';


COMMENT ON COLUMN entity_facts_archive.archived_at IS 'When the fact was archived';


COMMENT ON COLUMN entity_facts_archive.archive_reason IS 'Why the fact was archived (decay, conflict, manual)';


COMMENT ON COLUMN entity_facts_archive.archived_by IS 'System or agent that archived the fact';

--
-- Name: entity_relationships; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS entity_relationships (
    id SERIAL,
    entity_a integer,
    entity_b integer,
    relationship varchar(100) NOT NULL,
    since timestamp,
    notes text,
    is_long_distance boolean DEFAULT false,
    seriousness varchar(20) DEFAULT 'standard',
    CONSTRAINT entity_relationships_pkey PRIMARY KEY (id),
    CONSTRAINT entity_relationships_entity_a_entity_b_relationship_key UNIQUE (entity_a, entity_b, relationship),
    CONSTRAINT entity_relationships_entity_a_fkey FOREIGN KEY (entity_a) REFERENCES entities (id) ON DELETE CASCADE,
    CONSTRAINT entity_relationships_entity_b_fkey FOREIGN KEY (entity_b) REFERENCES entities (id) ON DELETE CASCADE
);


COMMENT ON TABLE entity_relationships IS 'Relationships between entities (family, work, friendship, etc).';

--
-- Name: idx_entity_rel_a; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_rel_a ON entity_relationships (entity_a);

--
-- Name: idx_entity_rel_b; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_rel_b ON entity_relationships (entity_b);

--
-- Name: events; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS events (
    id SERIAL,
    event_date timestamp NOT NULL,
    title varchar(500) NOT NULL,
    description text,
    source varchar(255),
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(description, ''::text)))) STORED,
    confidence real DEFAULT 1.0,
    last_confirmed_at timestamptz DEFAULT now(),
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT events_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE events IS 'Historical events, milestones, activities. Log significant occurrences.';

--
-- Name: idx_events_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_events_date ON events (event_date);

--
-- Name: event_entities; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS event_entities (
    event_id integer,
    entity_id integer,
    role varchar(100),
    CONSTRAINT event_entities_pkey PRIMARY KEY (event_id, entity_id),
    CONSTRAINT event_entities_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
    CONSTRAINT event_entities_event_id_fkey FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE
);


COMMENT ON TABLE event_entities IS 'Links events to entities (people, orgs, AIs). Many-to-many relationship table.';

--
-- Name: events_archive; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS events_archive (
    id SERIAL,
    event_date timestamp NOT NULL,
    title varchar(500) NOT NULL,
    description text,
    source varchar(255),
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(description, ''::text)))) STORED,
    confidence real DEFAULT 1.0,
    last_confirmed_at timestamptz DEFAULT now(),
    archived_at timestamptz DEFAULT now(),
    archive_reason varchar(50),
    CONSTRAINT events_archive_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE events_archive IS 'Archived historical events. Long-term storage for events moved out of active events table.';

--
-- Name: extraction_metrics; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS extraction_metrics (
    id SERIAL,
    timestamp timestamptz DEFAULT now(),
    method text,
    num_relations integer,
    avg_confidence real,
    processing_time_ms integer,
    CONSTRAINT extraction_metrics_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE extraction_metrics IS 'Performance metrics for data extraction processes. Tracks accuracy and efficiency of knowledge extraction.';

--
-- Name: fact_change_log; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS fact_change_log (
    id SERIAL,
    fact_id integer NOT NULL,
    old_value text,
    new_value text,
    changed_by_entity_id integer,
    reason varchar(100),
    changed_at timestamptz DEFAULT now(),
    CONSTRAINT fact_change_log_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE fact_change_log IS 'Audit trail for entity fact modifications. Tracks who changed what and when for accountability.';

--
-- Name: gambling_logs; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS gambling_logs (
    id SERIAL,
    entity_id integer,
    name varchar(255) NOT NULL,
    location varchar(255),
    started_at date,
    ended_at date,
    notes text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT gambling_logs_pkey PRIMARY KEY (id),
    CONSTRAINT gambling_logs_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE
);


COMMENT ON TABLE gambling_logs IS 'High-level gambling session summaries. Groups multiple gambling_entries by session.';

--
-- Name: idx_gambling_logs_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_gambling_logs_entity ON gambling_logs (entity_id);

--
-- Name: gambling_entries; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS gambling_entries (
    id SERIAL,
    log_id integer,
    session_date timestamp,
    casino varchar(255),
    game varchar(100),
    amount numeric(10,2) NOT NULL,
    notes text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    duration_minutes numeric(6,2),
    base_bet numeric(10,2),
    CONSTRAINT gambling_entries_pkey PRIMARY KEY (id),
    CONSTRAINT gambling_entries_log_id_fkey FOREIGN KEY (log_id) REFERENCES gambling_logs (id) ON DELETE CASCADE
);


COMMENT ON TABLE gambling_entries IS 'Individual gambling session records. Tracks bets, outcomes, and session details for analysis.';


COMMENT ON COLUMN gambling_entries.log_id IS 'References gambling_logs for session grouping';


COMMENT ON COLUMN gambling_entries.session_date IS 'Date and time of gambling session';


COMMENT ON COLUMN gambling_entries.casino IS 'Casino or venue name';


COMMENT ON COLUMN gambling_entries.game IS 'Game type (poker, blackjack, etc.)';


COMMENT ON COLUMN gambling_entries.amount IS 'Win/loss amount (positive for wins, negative for losses)';


COMMENT ON COLUMN gambling_entries.duration_minutes IS 'Session duration in minutes';


COMMENT ON COLUMN gambling_entries.base_bet IS 'Typical bet size for the session';

--
-- Name: idx_gambling_entries_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_gambling_entries_date ON gambling_entries (session_date);

--
-- Name: idx_gambling_entries_log; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_gambling_entries_log ON gambling_entries (log_id);

--
-- Name: git_issue_queue; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS git_issue_queue (
    id SERIAL,
    repo text NOT NULL,
    issue_number integer NOT NULL,
    title text,
    priority integer DEFAULT 5,
    status text DEFAULT 'pending_tests',
    source text DEFAULT 'github',
    parent_issue_id integer,
    labels text[],
    created_at timestamptz DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    error_message text,
    context jsonb DEFAULT '{}',
    test_file text,
    code_files text[],
    CONSTRAINT git_issue_queue_pkey PRIMARY KEY (id),
    CONSTRAINT git_issue_queue_repo_issue_number_key UNIQUE (repo, issue_number),
    CONSTRAINT coder_issue_queue_parent_issue_id_fkey FOREIGN KEY (parent_issue_id) REFERENCES git_issue_queue (id),
    CONSTRAINT coder_issue_queue_status_check CHECK (status IN ('pending_tests'::text, 'tests_approved'::text, 'implementing'::text, 'testing'::text, 'done'::text, 'failed'::text, 'paused'::text, 'blocked'::text))
);


COMMENT ON TABLE git_issue_queue IS 'Issue queue for git-based workflows. NOTIFY triggers dispatch work automatically.';


COMMENT ON COLUMN git_issue_queue.status IS 'pending_tests→tests_approved→implementing→testing→done/failed';


COMMENT ON COLUMN git_issue_queue.labels IS 'GitHub labels. Gem skips issues with paused, blocked, on-hold, wontfix labels.';

--
-- Name: idx_git_queue_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_git_queue_status ON git_issue_queue (status);

--
-- Name: income_sources; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS income_sources (
    id SERIAL,
    name text NOT NULL,
    description text,
    payment_method text,
    currency text DEFAULT 'BTC',
    check_method text,
    check_frequency text,
    status text DEFAULT 'active' NOT NULL,
    consolidated_into integer,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT income_sources_pkey PRIMARY KEY (id),
    CONSTRAINT income_sources_name_key UNIQUE (name),
    CONSTRAINT income_sources_consolidated_into_fkey FOREIGN KEY (consolidated_into) REFERENCES income_sources (id),
    CONSTRAINT income_sources_status_check CHECK (status IN ('active'::text, 'paused'::text, 'retired'::text))
);


COMMENT ON TABLE income_sources IS 'Registry of NOVA income streams — where money comes from, how to check it, and current status. Owner: NOVA.';


COMMENT ON COLUMN income_sources.check_method IS 'Operational: how NOVA checks for new income from this source (CLI command, dashboard URL, API call)';


COMMENT ON COLUMN income_sources.consolidated_into IS 'Self-ref FK: when a source is retired and rolled into another (e.g. Printful → WooCommerce Shop)';

--
-- Name: income_transactions; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS income_transactions (
    id SERIAL,
    source_id integer NOT NULL,
    amount numeric NOT NULL,
    currency text NOT NULL,
    amount_sats bigint,
    description text,
    transaction_date timestamptz NOT NULL,
    external_ref text,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT income_transactions_pkey PRIMARY KEY (id),
    CONSTRAINT income_transactions_source_id_fkey FOREIGN KEY (source_id) REFERENCES income_sources (id)
);


COMMENT ON TABLE income_transactions IS 'Individual income transactions, each linked to an income_source. Owner: NOVA.';


COMMENT ON COLUMN income_transactions.amount_sats IS 'Amount normalized to satoshis for easy BTC aggregation';


COMMENT ON COLUMN income_transactions.external_ref IS 'Source-specific reference: payment hash, order ID, invoice number, etc.';

--
-- Name: idx_income_transactions_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_income_transactions_date ON income_transactions (transaction_date DESC);

--
-- Name: idx_income_transactions_source; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_income_transactions_source ON income_transactions (source_id);

--
-- Name: job_messages; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS job_messages (
    id SERIAL,
    job_id integer NOT NULL,
    message_id integer NOT NULL,
    role varchar(20) DEFAULT 'context',
    added_at timestamptz DEFAULT now(),
    CONSTRAINT job_messages_pkey PRIMARY KEY (id),
    CONSTRAINT job_messages_job_id_fkey FOREIGN KEY (job_id) REFERENCES agent_jobs (id)
);


COMMENT ON TABLE job_messages IS 'Message log per job for conversation threading';

--
-- Name: lessons_archive; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS lessons_archive (
    id SERIAL,
    lesson text NOT NULL,
    context text,
    source varchar(255),
    learned_at timestamp DEFAULT CURRENT_TIMESTAMP,
    original_behavior text,
    correction_source text,
    reinforced_at timestamp,
    confidence double precision DEFAULT 1.0,
    last_referenced timestamp,
    last_confirmed_at timestamptz DEFAULT now(),
    archived_at timestamptz DEFAULT now(),
    archive_reason varchar(50),
    CONSTRAINT lessons_archive_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE lessons_archive IS 'Archived lessons and insights. Historical record of previously stored learnings.';


COMMENT ON COLUMN lessons_archive.confidence IS 'Confidence score 0-1, decays over time if not reinforced';

--
-- Name: library_authors; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS library_authors (
    id SERIAL,
    name text NOT NULL,
    biography text,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT library_authors_pkey PRIMARY KEY (id),
    CONSTRAINT library_authors_name_key UNIQUE (name)
);


COMMENT ON TABLE library_authors IS 'Library domain: normalized author records. Managed by Athena (librarian agent).';

--
-- Name: idx_library_authors_name; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_authors_name ON library_authors (name);

--
-- Name: library_tags; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS library_tags (
    id SERIAL,
    name text NOT NULL,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT library_tags_pkey PRIMARY KEY (id),
    CONSTRAINT library_tags_name_key UNIQUE (name)
);


COMMENT ON TABLE library_tags IS 'Library domain: subject/genre/topic tags for works. Managed by Athena.';

--
-- Name: library_works; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS library_works (
    id SERIAL,
    title text NOT NULL,
    work_type text NOT NULL,
    publication_date date NOT NULL,
    language text DEFAULT 'en' NOT NULL,
    summary text NOT NULL,
    url text,
    doi text,
    arxiv_id text,
    isbn text,
    external_ids jsonb DEFAULT '{}',
    abstract text,
    content_text text,
    insights text NOT NULL,
    subjects text[] DEFAULT '{}' NOT NULL,
    publisher text,
    source_path text,
    shared_by text NOT NULL,
    added_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    search_vector tsvector,
    extra_metadata jsonb DEFAULT '{}',
    notable_quotes text[],
    edition text,
    embed boolean DEFAULT true NOT NULL,
    CONSTRAINT library_works_pkey PRIMARY KEY (id),
    CONSTRAINT insights_not_empty CHECK (length(TRIM(BOTH FROM insights)) > 20),
    CONSTRAINT summary_not_empty CHECK (length(TRIM(BOTH FROM summary)) > 50),
    CONSTRAINT valid_work_type CHECK (work_type IN ('paper'::text, 'book'::text, 'novel'::text, 'poem'::text, 'short_story'::text, 'essay'::text, 'article'::text, 'blog_post'::text, 'whitepaper'::text, 'report'::text, 'thesis'::text, 'dissertation'::text, 'magazine'::text, 'newsletter'::text, 'speech'::text, 'other'::text))
);


COMMENT ON TABLE library_works IS 'Library domain: all written works (papers, books, poems, etc). Managed by Athena (librarian agent). ALL core fields are NOT NULL — Athena must generate summary and insights during ingestion. The summary field is used for semantic embedding (200-400 words, high-density). On semantic recall hit, query this table for full details.';


COMMENT ON COLUMN library_works.summary IS 'REQUIRED. Concise semantic summary for embedding. 200-400 words. Must capture: what the work is, who wrote it, key findings/themes, and why it matters. Athena generates this during ingestion.';


COMMENT ON COLUMN library_works.abstract IS 'Original abstract verbatim from source. May be NULL if source has none (e.g. poems).';


COMMENT ON COLUMN library_works.content_text IS 'Full text of the work. Optional — only store if available and not too large.';


COMMENT ON COLUMN library_works.insights IS 'REQUIRED. Key takeaways, relevance to our work, notable connections. Athena generates this during ingestion.';


COMMENT ON COLUMN library_works.notable_quotes IS 'Array of notable quotes from the work. Included in semantic embedding for recall. Generated during ingestion.';

--
-- Name: idx_library_works_arxiv; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_works_arxiv ON library_works (arxiv_id) WHERE (arxiv_id IS NOT NULL);

--
-- Name: idx_library_works_embed; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_works_embed ON library_works (embed) WHERE (embed = true);

--
-- Name: idx_library_works_title_edition; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_library_works_title_edition ON library_works (lower(TRIM(BOTH FROM title)), COALESCE(edition, ''::text));

--
-- Name: idx_library_works_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_works_type ON library_works (work_type);

--
-- Name: library_work_authors; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS library_work_authors (
    work_id integer,
    author_id integer,
    author_order integer DEFAULT 0,
    CONSTRAINT library_work_authors_pkey PRIMARY KEY (work_id, author_id),
    CONSTRAINT library_work_authors_author_id_fkey FOREIGN KEY (author_id) REFERENCES library_authors (id) ON DELETE CASCADE,
    CONSTRAINT library_work_authors_work_id_fkey FOREIGN KEY (work_id) REFERENCES library_works (id) ON DELETE CASCADE
);


COMMENT ON TABLE library_work_authors IS 'Links works to their authors. author_order preserves original ordering.';

--
-- Name: library_work_relationships; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS library_work_relationships (
    from_work_id integer,
    to_work_id integer,
    relation_type text,
    CONSTRAINT library_work_relationships_pkey PRIMARY KEY (from_work_id, to_work_id, relation_type),
    CONSTRAINT library_work_relationships_from_work_id_fkey FOREIGN KEY (from_work_id) REFERENCES library_works (id) ON DELETE CASCADE,
    CONSTRAINT library_work_relationships_to_work_id_fkey FOREIGN KEY (to_work_id) REFERENCES library_works (id) ON DELETE CASCADE
);


COMMENT ON TABLE library_work_relationships IS 'Tracks relationships between works (citations, sequels, responses, etc).';

--
-- Name: library_work_tags; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS library_work_tags (
    work_id integer,
    tag_id integer,
    CONSTRAINT library_work_tags_pkey PRIMARY KEY (work_id, tag_id),
    CONSTRAINT library_work_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES library_tags (id) ON DELETE CASCADE,
    CONSTRAINT library_work_tags_work_id_fkey FOREIGN KEY (work_id) REFERENCES library_works (id) ON DELETE CASCADE
);


COMMENT ON TABLE library_work_tags IS 'Links works to subject/topic tags.';

--
-- Name: media_consumed; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS media_consumed (
    id SERIAL,
    media_type varchar(50) NOT NULL,
    title varchar(500) NOT NULL,
    creator varchar(255),
    url text,
    consumed_date date,
    consumed_by integer,
    rating integer,
    notes text,
    transcript text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    summary text,
    metadata jsonb DEFAULT '{}',
    source_file text,
    status varchar(20) DEFAULT 'completed',
    ingested_by integer,
    ingested_at timestamp DEFAULT CURRENT_TIMESTAMP,
    search_vector tsvector,
    insights text,
    CONSTRAINT media_consumed_pkey PRIMARY KEY (id),
    CONSTRAINT media_consumed_consumed_by_fkey FOREIGN KEY (consumed_by) REFERENCES entities (id),
    CONSTRAINT media_consumed_ingested_by_fkey FOREIGN KEY (ingested_by) REFERENCES agents (id),
    CONSTRAINT media_consumed_rating_check CHECK (rating >= 1 AND rating <= 10)
);


COMMENT ON TABLE media_consumed IS 'Books, movies, podcasts consumed by entities. Log completions here.';


COMMENT ON COLUMN media_consumed.summary IS 'Athena (librarian-agent) generated summary - objective, factual';


COMMENT ON COLUMN media_consumed.metadata IS 'Flexible metadata: duration, language, format, topics, word_count, etc.';


COMMENT ON COLUMN media_consumed.source_file IS 'Local file path if media was downloaded';


COMMENT ON COLUMN media_consumed.status IS 'Processing status: pending, processing, completed, failed, queued';


COMMENT ON COLUMN media_consumed.ingested_by IS 'Agent ID that processed this media';


COMMENT ON COLUMN media_consumed.ingested_at IS 'Timestamp when media was ingested/processed';


COMMENT ON COLUMN media_consumed.search_vector IS 'Full-text search vector (title + notes + transcript + summary)';


COMMENT ON COLUMN media_consumed.insights IS 'NOVA personal insights - analysis, connections, opinions';

--
-- Name: agent_actions; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_actions (
    id SERIAL,
    agent_id integer DEFAULT 1,
    action_type varchar(100) NOT NULL,
    description text NOT NULL,
    related_media_id integer,
    related_event_id integer,
    metadata jsonb,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT agent_actions_pkey PRIMARY KEY (id),
    CONSTRAINT agent_actions_agent_id_fkey FOREIGN KEY (agent_id) REFERENCES entities (id),
    CONSTRAINT agent_actions_related_event_id_fkey FOREIGN KEY (related_event_id) REFERENCES events (id),
    CONSTRAINT agent_actions_related_media_id_fkey FOREIGN KEY (related_media_id) REFERENCES media_consumed (id)
);


COMMENT ON TABLE agent_actions IS 'Agent action definitions. READ-ONLY except Newhart.';

--
-- Name: idx_agent_actions_agent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_actions_agent ON agent_actions (agent_id);

--
-- Name: idx_agent_actions_time; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_actions_time ON agent_actions (created_at DESC);

--
-- Name: media_queue; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS media_queue (
    id SERIAL,
    url text,
    file_path text,
    media_type varchar(50),
    title varchar(500),
    creator varchar(255),
    priority integer DEFAULT 5,
    status varchar(20) DEFAULT 'pending',
    requested_by integer,
    requested_at timestamp DEFAULT CURRENT_TIMESTAMP,
    processing_started_at timestamp,
    completed_at timestamp,
    result_media_id integer,
    error_message text,
    metadata jsonb DEFAULT '{}',
    CONSTRAINT media_queue_pkey PRIMARY KEY (id),
    CONSTRAINT media_queue_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES entities (id),
    CONSTRAINT media_queue_result_media_id_fkey FOREIGN KEY (result_media_id) REFERENCES media_consumed (id)
);


COMMENT ON TABLE media_queue IS 'Queue for media ingestion. Librarian agent processes these.';


COMMENT ON COLUMN media_queue.priority IS '1=urgent, 5=normal, 10=low priority';


COMMENT ON COLUMN media_queue.status IS 'pending, processing, completed, failed, duplicate';


COMMENT ON COLUMN media_queue.result_media_id IS 'Foreign key to resulting media_consumed record';

--
-- Name: media_tags; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS media_tags (
    id SERIAL,
    media_id integer NOT NULL,
    tag varchar(100) NOT NULL,
    source varchar(20) DEFAULT 'auto',
    confidence numeric(3,2),
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT media_tags_pkey PRIMARY KEY (id),
    CONSTRAINT media_tags_media_id_tag_key UNIQUE (media_id, tag),
    CONSTRAINT media_tags_media_id_fkey FOREIGN KEY (media_id) REFERENCES media_consumed (id) ON DELETE CASCADE
);


COMMENT ON TABLE media_tags IS 'Tags/topics for media items. Helps with recommendations and search.';


COMMENT ON COLUMN media_tags.source IS 'auto=AI-generated, manual=user-added';


COMMENT ON COLUMN media_tags.confidence IS 'AI confidence score for auto-generated tags';

--
-- Name: idx_media_tags_media; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_media_tags_media ON media_tags (media_id);

--
-- Name: memory_embeddings; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS memory_embeddings (
    id SERIAL,
    source_type varchar(50) NOT NULL,
    source_id text,
    content text NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    confidence real DEFAULT 1.0,
    last_confirmed_at timestamptz DEFAULT now(),
    embedding vector(1024),
    CONSTRAINT memory_embeddings_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE memory_embeddings IS 'Vector embeddings for semantic memory search. Used by proactive-recall.py.';

--
-- Name: idx_memory_embeddings_source; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_memory_embeddings_source ON memory_embeddings (source_type);

--
-- Name: idx_memory_embeddings_vector; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_memory_embeddings_vector ON memory_embeddings USING ivfflat (embedding vector_cosine_ops);

--
-- Name: uq_memory_embeddings_source; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS uq_memory_embeddings_source ON memory_embeddings (source_type, source_id);

--
-- Name: memory_embeddings_archive; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS memory_embeddings_archive (
    id SERIAL,
    source_type varchar(50) NOT NULL,
    source_id text,
    content text NOT NULL,
    embedding vector(1024),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    confidence real DEFAULT 1.0,
    last_confirmed_at timestamptz DEFAULT now(),
    archived_at timestamptz DEFAULT now(),
    archive_reason varchar(50),
    CONSTRAINT memory_embeddings_archive_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE memory_embeddings_archive IS 'Archived vector embeddings from semantic memory system. Historical embeddings for backup/analysis. Migrated to vector(1024).';

--
-- Name: memory_type_priorities; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS memory_type_priorities (
    source_type text,
    priority numeric(3,2) DEFAULT 1.00 NOT NULL,
    description text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT memory_type_priorities_pkey PRIMARY KEY (source_type)
);


COMMENT ON TABLE memory_type_priorities IS 'Priority weights for semantic recall by source_type. Higher = more likely to surface. NOVA can modify.';

--
-- Name: music_library; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS music_library (
    id SERIAL,
    media_id integer,
    musicbrainz_track_id uuid,
    musicbrainz_album_id uuid,
    musicbrainz_artist_id uuid,
    isrc varchar(12),
    discogs_release_id integer,
    spotify_uri varchar(255),
    apple_music_id varchar(255),
    key varchar(10),
    bpm numeric(6,2),
    time_signature varchar(10),
    duration_ms integer,
    genre varchar(100),
    subgenre varchar(100),
    mood varchar(100),
    energy_level integer,
    danceability integer,
    year integer,
    album varchar(255),
    track_number integer,
    disc_number integer DEFAULT 1,
    label varchar(255),
    producer varchar(255),
    replaygain_track_gain numeric(6,2),
    replaygain_album_gain numeric(6,2),
    sample_rate integer,
    bit_depth integer,
    bitrate integer,
    file_format varchar(20),
    lyrics text,
    language varchar(10),
    explicit boolean DEFAULT false,
    added_at timestamp DEFAULT now(),
    last_played timestamp,
    play_count integer DEFAULT 0,
    search_vector tsvector,
    CONSTRAINT music_library_pkey PRIMARY KEY (id),
    CONSTRAINT music_library_media_id_key UNIQUE (media_id),
    CONSTRAINT music_library_media_id_fkey FOREIGN KEY (media_id) REFERENCES media_consumed (id) ON DELETE CASCADE,
    CONSTRAINT music_library_danceability_check CHECK (danceability >= 1 AND danceability <= 10),
    CONSTRAINT music_library_energy_level_check CHECK (energy_level >= 1 AND energy_level <= 10)
);


COMMENT ON TABLE music_library IS 'Music-specific metadata extending media_consumed. Managed by Erato.';

--
-- Name: idx_music_library_media; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_media ON music_library (media_id);

--
-- Name: music_analysis; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS music_analysis (
    id SERIAL,
    music_id integer,
    analysis_type varchar(50) NOT NULL,
    analysis_summary text,
    detailed_findings jsonb,
    complexity_score numeric(4,2),
    uniqueness_score numeric(4,2),
    analyzed_by integer,
    analyzed_at timestamp DEFAULT now(),
    notes text,
    search_vector tsvector,
    CONSTRAINT music_analysis_pkey PRIMARY KEY (id),
    CONSTRAINT music_analysis_analyzed_by_fkey FOREIGN KEY (analyzed_by) REFERENCES agents (id),
    CONSTRAINT music_analysis_music_id_fkey FOREIGN KEY (music_id) REFERENCES music_library (id) ON DELETE CASCADE
);


COMMENT ON TABLE music_analysis IS 'Deep musical analysis (harmonic, rhythmic, lyrical, spectral). Managed by Erato.';

--
-- Name: places; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS places (
    id SERIAL,
    name varchar(255) NOT NULL,
    type varchar(50),
    address text,
    network_subnet varchar(50),
    network_theme varchar(100),
    coordinates double precision[],
    parent_place_id integer,
    notes text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    street_address varchar(255),
    city varchar(100),
    state varchar(100),
    zipcode varchar(20),
    country varchar(100) DEFAULT 'USA',
    CONSTRAINT places_pkey PRIMARY KEY (id),
    CONSTRAINT places_name_key UNIQUE (name),
    CONSTRAINT places_parent_place_id_fkey FOREIGN KEY (parent_place_id) REFERENCES places (id)
);


COMMENT ON TABLE places IS 'Locations (houses, venues, cities). Reference I)ruid houses in USER.md.';

--
-- Name: idx_places_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_places_type ON places (type);

--
-- Name: event_places; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS event_places (
    event_id integer,
    place_id integer,
    CONSTRAINT event_places_pkey PRIMARY KEY (event_id, place_id),
    CONSTRAINT event_places_event_id_fkey FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
    CONSTRAINT event_places_place_id_fkey FOREIGN KEY (place_id) REFERENCES places (id) ON DELETE CASCADE
);


COMMENT ON TABLE event_places IS 'Links events to places/locations. Many-to-many relationship table.';

--
-- Name: place_properties; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS place_properties (
    id SERIAL,
    place_id integer,
    key varchar(255) NOT NULL,
    value text NOT NULL,
    data jsonb,
    CONSTRAINT place_properties_pkey PRIMARY KEY (id),
    CONSTRAINT place_properties_place_id_fkey FOREIGN KEY (place_id) REFERENCES places (id) ON DELETE CASCADE
);


COMMENT ON TABLE place_properties IS 'Properties and attributes of places. Key-value storage for place characteristics.';

--
-- Name: idx_place_props_place; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_place_props_place ON place_properties (place_id);

--
-- Name: preferences; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS preferences (
    id SERIAL,
    entity_id integer,
    key varchar(255) NOT NULL,
    value text NOT NULL,
    context text,
    learned_at timestamp DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT preferences_pkey PRIMARY KEY (id),
    CONSTRAINT preferences_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE
);


COMMENT ON TABLE preferences IS 'User preferences by entity_id. Check before making assumptions.';

--
-- Name: idx_preferences_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_preferences_entity ON preferences (entity_id);

--
-- Name: idx_preferences_key; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_preferences_key ON preferences (key);

--
-- Name: proactive_outreach; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS proactive_outreach (
    id SERIAL,
    entity_id integer NOT NULL,
    blocker_type varchar(50) NOT NULL,
    blocker_id integer NOT NULL,
    channel_used varchar(50) NOT NULL,
    channel_target text,
    message_summary text,
    attempted_at timestamptz DEFAULT now(),
    response_received boolean DEFAULT false,
    response_at timestamptz,
    notes text,
    CONSTRAINT proactive_outreach_pkey PRIMARY KEY (id),
    CONSTRAINT proactive_outreach_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id)
);

--
-- Name: idx_proactive_outreach_blocker; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_proactive_outreach_blocker ON proactive_outreach (blocker_type, blocker_id);

--
-- Name: idx_proactive_outreach_cooldown; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_proactive_outreach_cooldown ON proactive_outreach (entity_id, blocker_type, blocker_id, attempted_at);

--
-- Name: idx_proactive_outreach_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_proactive_outreach_entity ON proactive_outreach (entity_id);

--
-- Name: projects; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS projects (
    id SERIAL,
    name varchar(255) NOT NULL,
    status varchar(50) DEFAULT 'active',
    goal text,
    started_at timestamp DEFAULT CURRENT_TIMESTAMP,
    completed_at timestamp,
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
    notes text,
    git_config jsonb,
    repo_url text,
    locked boolean DEFAULT false,
    skills text[],
    CONSTRAINT projects_pkey PRIMARY KEY (id),
    CONSTRAINT projects_name_key UNIQUE (name),
    CONSTRAINT projects_status_check CHECK (status::text IN ('active'::character varying, 'blocked'::character varying, 'complete'::character varying, 'paused'::character varying, 'abandoned'::character varying))
);


COMMENT ON TABLE projects IS 'Project tracking. For repo-backed projects (locked=TRUE, repo_url set), use GitHub for management. For non-repo projects, use notes field here.';


COMMENT ON COLUMN projects.git_config IS 'Per-project Git config: branch strategy, commit conventions, PR workflow, etc.';


COMMENT ON COLUMN projects.repo_url IS 'GitHub repo URL. When set with locked=TRUE, this is the source of truth. Manage project via repo, not database.';


COMMENT ON COLUMN projects.locked IS 'When TRUE, project is repo-backed. Use GitHub (repo_url) for docs/updates, not this table. Prevents accidental writes to notes field.';


COMMENT ON COLUMN projects.skills IS 'Array of skill names (from ~/clawd/skills/) relevant to this project';

--
-- Name: idx_projects_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_projects_status ON projects (status);

--
-- Name: event_projects; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS event_projects (
    event_id integer,
    project_id integer,
    CONSTRAINT event_projects_pkey PRIMARY KEY (event_id, project_id),
    CONSTRAINT event_projects_event_id_fkey FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
    CONSTRAINT event_projects_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
);


COMMENT ON TABLE event_projects IS 'Links events to projects. Many-to-many relationship table for project milestones and activities.';

--
-- Name: project_entities; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS project_entities (
    project_id integer,
    entity_id integer,
    role varchar(100),
    CONSTRAINT project_entities_pkey PRIMARY KEY (project_id, entity_id),
    CONSTRAINT project_entities_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
    CONSTRAINT project_entities_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE
);


COMMENT ON TABLE project_entities IS 'Links projects to entities (people, orgs, AIs). Many-to-many relationship table for project participants.';

--
-- Name: project_tasks; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS project_tasks (
    id SERIAL,
    project_id integer,
    task text NOT NULL,
    status varchar(50) DEFAULT 'pending',
    blocked_by text,
    due_date timestamp,
    completed_at timestamp,
    priority integer DEFAULT 0,
    CONSTRAINT project_tasks_pkey PRIMARY KEY (id),
    CONSTRAINT project_tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE CASCADE,
    CONSTRAINT project_tasks_status_check CHECK (status::text IN ('pending'::character varying, 'in_progress'::character varying, 'blocked'::character varying, 'complete'::character varying))
);


COMMENT ON TABLE project_tasks IS 'Project-specific task breakdown. Links tasks to projects for organized project management.';

--
-- Name: idx_project_tasks_project; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_project_tasks_project ON project_tasks (project_id);

--
-- Name: prompt_helper_config; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS prompt_helper_config (
    id SERIAL,
    message_type text NOT NULL,
    helper_name text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    config jsonb DEFAULT '{}' NOT NULL,
    agent_name text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT prompt_helper_config_pkey PRIMARY KEY (id),
    CONSTRAINT prompt_helper_config_message_type_check CHECK (message_type IN ('info_request'::text, 'action'::text, 'conversation'::text, 'continuation'::text, 'command'::text))
);


COMMENT ON TABLE prompt_helper_config IS 'Per-message-type gating for turn-context subsystems (entity_resolver, semantic_recall, domain_identifier, turn_reminders). Rows with agent_name IS NULL are defaults; agent-specific rows override them. turn_reminders always fires regardless of config.';

--
-- Name: idx_prompt_helper_config_lookup; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_prompt_helper_config_lookup ON prompt_helper_config (message_type, agent_name);

--
-- Name: prompt_helper_config_unique_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS prompt_helper_config_unique_idx ON prompt_helper_config (message_type, helper_name, COALESCE(agent_name, '__default__'::text));

--
-- Name: ralph_sessions; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS ralph_sessions (
    id SERIAL,
    session_series_id text NOT NULL,
    iteration integer DEFAULT 1 NOT NULL,
    agent_id text NOT NULL,
    spawned_session_key text,
    task_description text,
    iteration_goal text,
    state jsonb DEFAULT '{}' NOT NULL,
    status text DEFAULT 'PENDING' NOT NULL,
    error_message text,
    tokens_used integer,
    cost numeric(10,4),
    created_at timestamptz DEFAULT now(),
    started_at timestamptz,
    completed_at timestamptz,
    CONSTRAINT ralph_sessions_pkey PRIMARY KEY (id),
    CONSTRAINT ralph_sessions_session_series_id_iteration_key UNIQUE (session_series_id, iteration)
);


COMMENT ON TABLE ralph_sessions IS 'Tracks Ralph-style iterative agent sessions. Each iteration runs with fresh context, state persists in DB.';


COMMENT ON COLUMN ralph_sessions.session_series_id IS 'UUID or descriptive ID linking all iterations of the same task';


COMMENT ON COLUMN ralph_sessions.status IS 'PENDING=not started, RUNNING=in progress, CONTINUE=done but more needed, COMPLETE=finished, ERROR=failed';

--
-- Name: idx_ralph_series_latest; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_ralph_series_latest ON ralph_sessions (session_series_id, iteration DESC);

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


COMMENT ON TABLE research_tasks IS 'Research tasks. Write-protected: only DB user scout can INSERT/UPDATE/DELETE.';


COMMENT ON COLUMN research_tasks.priority IS 'Integer 1-10 (1=highest, 10=lowest). CHECK constraint enforces range.';

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


COMMENT ON TABLE research_conclusions IS 'Research conclusions linked to tasks via task_id. Write-protected: only DB user scout can INSERT/UPDATE/DELETE.';

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


COMMENT ON TABLE research_findings IS 'Research findings linked to tasks via task_id. Write-protected: only DB user scout can INSERT/UPDATE/DELETE. NO project_id column exists — join through research_tasks.project_id instead.';


COMMENT ON COLUMN research_findings.task_id IS 'FK to research_tasks.id. There is NO project_id column on this table — link to projects via research_tasks.project_id.';


COMMENT ON COLUMN research_findings.finding_type IS 'One of: fact, insight, conclusion, warning, recommendation, definition, example';


COMMENT ON COLUMN research_findings.confidence IS 'Decimal 0.00-1.00';


COMMENT ON COLUMN research_findings.importance IS 'One of: low, normal, high, critical (varchar, not integer)';

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
    CONSTRAINT fk_citation_library_work FOREIGN KEY (library_work_id) REFERENCES library_works (id) ON DELETE SET NULL,
    CONSTRAINT research_citations_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES research_findings (id) ON DELETE CASCADE,
    CONSTRAINT research_citations_reliability_check CHECK (reliability >= 0.00 AND reliability <= 1.00),
    CONSTRAINT research_citations_source_type_check CHECK (source_type::text IN ('url'::character varying, 'paper'::character varying, 'book'::character varying, 'library_work'::character varying, 'api'::character varying, 'agent'::character varying, 'database'::character varying, 'document'::character varying, 'interview'::character varying))
);


COMMENT ON TABLE research_citations IS 'Citations linked to findings via finding_id. Write-protected: only DB user scout can INSERT/UPDATE/DELETE.';

--
-- Name: self_awareness_triggers; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS self_awareness_triggers (
    id SERIAL,
    name text NOT NULL,
    category text DEFAULT 'general' NOT NULL,
    keyphrases text[] DEFAULT '{}' NOT NULL,
    keyphrase_embeddings jsonb,
    similarity_threshold real DEFAULT 0.7 NOT NULL,
    action text DEFAULT 'log' NOT NULL,
    action_config jsonb,
    cooldown_minutes integer DEFAULT 60 NOT NULL,
    last_triggered_at timestamptz,
    times_triggered integer DEFAULT 0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT self_awareness_triggers_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE self_awareness_triggers IS 'Trigger patterns for the self-awareness plugin. Each row defines keyphrases that, when semantically matched in outbound messages, fire an action. Managed by NOVA.';

--
-- Name: shopping_history; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS shopping_history (
    id SERIAL,
    entity_id integer,
    product_name text NOT NULL,
    category text,
    retailer text,
    price numeric,
    url text,
    satisfaction_rating integer,
    notes text,
    purchased_at timestamptz,
    restock_interval_days integer,
    next_restock_at timestamptz,
    created_at timestamptz DEFAULT now(),
    CONSTRAINT shopping_history_pkey PRIMARY KEY (id),
    CONSTRAINT shopping_history_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id),
    CONSTRAINT shopping_history_satisfaction_rating_check CHECK (satisfaction_rating >= 1 AND satisfaction_rating <= 5)
);

--
-- Name: shopping_preferences; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS shopping_preferences (
    id SERIAL,
    entity_id integer,
    category text NOT NULL,
    key text NOT NULL,
    value text NOT NULL,
    notes text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT shopping_preferences_pkey PRIMARY KEY (id),
    CONSTRAINT shopping_preferences_entity_id_category_key_key UNIQUE (entity_id, category, key),
    CONSTRAINT shopping_preferences_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id)
);

--
-- Name: shopping_wishlist; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS shopping_wishlist (
    id SERIAL,
    entity_id integer,
    product_name text NOT NULL,
    category text,
    max_price numeric,
    url text,
    priority text DEFAULT 'normal',
    status text DEFAULT 'active',
    notes text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT shopping_wishlist_pkey PRIMARY KEY (id),
    CONSTRAINT shopping_wishlist_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id),
    CONSTRAINT shopping_wishlist_priority_check CHECK (priority IN ('low'::text, 'normal'::text, 'high'::text, 'urgent'::text)),
    CONSTRAINT shopping_wishlist_status_check CHECK (status IN ('active'::text, 'purchased'::text, 'dropped'::text, 'watching'::text))
);

--
-- Name: skills; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS skills (
    id SERIAL,
    skill_name text NOT NULL,
    description text NOT NULL,
    source_type text NOT NULL,
    agent_name text,
    homepage text,
    emoji text,
    requires_bins text[],
    requires_any_bins text[],
    requires_env text[],
    requires_config text[],
    primary_env text,
    requires_os text[],
    instructions text,
    location_path text,
    enabled boolean DEFAULT true NOT NULL,
    user_invocable boolean DEFAULT true NOT NULL,
    disable_model_invocation boolean DEFAULT false NOT NULL,
    install_specs jsonb,
    config jsonb,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    updated_by text DEFAULT 'system',
    domain_name text,
    CONSTRAINT skills_pkey PRIMARY KEY (id),
    CONSTRAINT skills_source_type_check CHECK (source_type IN ('BUNDLED'::text, 'MANAGED'::text, 'WORKSPACE'::text, 'DOMAIN'::text))
);


COMMENT ON TABLE skills IS 'Skill definitions. Override precedence: WORKSPACE > DOMAIN > MANAGED > BUNDLED. See get_agent_skills().';


COMMENT ON COLUMN skills.source_type IS 'BUNDLED=shipped with OpenClaw, MANAGED=~/.openclaw/skills, DOMAIN=domain-scoped, WORKSPACE=per-agent workspace skills';


COMMENT ON COLUMN skills.agent_name IS 'NULL=available to all agents; set for WORKSPACE-scoped or agent-specific skills';


COMMENT ON COLUMN skills.instructions IS 'Full SKILL.md content (loaded on-demand, not injected into prompt)';


COMMENT ON COLUMN skills.location_path IS 'Filesystem path hint for skills with scripts/resources on disk';


COMMENT ON COLUMN skills.domain_name IS 'Required when source_type=DOMAIN. Matched via agent_domains.';

--
-- Name: idx_skills_unique; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_skills_unique ON skills (skill_name, source_type, COALESCE(agent_name, ''::text), COALESCE(domain_name, ''::text));

--
-- Name: social_interactions; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS social_interactions (
    id SERIAL,
    platform text NOT NULL,
    mention_id text NOT NULL,
    thread_id text,
    author_handle text,
    content text,
    status text DEFAULT 'seen' NOT NULL,
    draft_response text,
    response_id text,
    approved_by text,
    approved_at timestamptz,
    responded_at timestamptz,
    dismissed_reason text,
    notes text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT social_interactions_pkey PRIMARY KEY (id),
    CONSTRAINT social_interactions_platform_mention_id_key UNIQUE (platform, mention_id),
    CONSTRAINT social_interactions_status_check CHECK (status IN ('seen'::text, 'needs_response'::text, 'drafted'::text, 'approved'::text, 'posted'::text, 'dismissed'::text))
);


COMMENT ON TABLE social_interactions IS 'Tracks the full lifecycle of inbound social media mentions: seen → needs_response → drafted → approved → posted (or dismissed). Enforces the approval gate for outbound social media responses. Hermes comms check writes new entries; NOVA updates status on approval and posting. Domain: NOVA Operations.';


COMMENT ON COLUMN social_interactions.status IS 'Lifecycle: seen (just noticed), needs_response (verified no existing reply in thread), drafted (proposed response written), approved (I)ruid approved), posted (response sent), dismissed (no response needed).';

--
-- Name: idx_social_interactions_created; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_social_interactions_created ON social_interactions (created_at DESC);

--
-- Name: idx_social_interactions_platform_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_social_interactions_platform_status ON social_interactions (platform, status);

--
-- Name: tags; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS tags (
    id SERIAL,
    name varchar(50) NOT NULL,
    category varchar(50),
    description text,
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT tags_pkey PRIMARY KEY (id),
    CONSTRAINT tags_name_key UNIQUE (name),
    CONSTRAINT lowercase_name CHECK (name::text = lower(name::text)),
    CONSTRAINT valid_category CHECK (category IS NULL OR (category::text IN ('genre'::character varying, 'mood'::character varying, 'theme'::character varying, 'style'::character varying, 'audience'::character varying, 'project'::character varying)))
);

--
-- Name: tools; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS tools (
    id SERIAL,
    tool_name text NOT NULL,
    description text NOT NULL,
    source_type text NOT NULL,
    agent_name text,
    category text,
    notes text,
    metadata jsonb,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    updated_by text DEFAULT 'system',
    domain_name text,
    CONSTRAINT tools_pkey PRIMARY KEY (id),
    CONSTRAINT tools_source_type_check CHECK (source_type IN ('BUNDLED'::text, 'MANAGED'::text, 'WORKSPACE'::text, 'DOMAIN'::text))
);


COMMENT ON TABLE tools IS 'Tool usage notes. Override: WORKSPACE > DOMAIN > MANAGED > BUNDLED. See get_agent_tools().';


COMMENT ON COLUMN tools.source_type IS 'BUNDLED=shipped with OpenClaw, MANAGED=~/.openclaw/tools, DOMAIN=domain-scoped, WORKSPACE=per-agent workspace tools';


COMMENT ON COLUMN tools.category IS 'Grouping key for assembling TOOLS.md sections';


COMMENT ON COLUMN tools.notes IS 'Markdown guidance content — camera names, SSH hosts, preferred voices, etc.';


COMMENT ON COLUMN tools.domain_name IS 'Required when source_type=DOMAIN. Matched via agent_domains.';

--
-- Name: idx_tools_unique; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_tools_unique ON tools (tool_name, source_type, COALESCE(agent_name, ''::text), COALESCE(domain_name, ''::text));

--
-- Name: unsolved_problems; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS unsolved_problems (
    id SERIAL,
    name varchar(255) NOT NULL,
    category varchar(100),
    description text,
    source_url text,
    difficulty varchar(50),
    status varchar(50) DEFAULT 'unexplored',
    total_time_spent_minutes integer DEFAULT 0,
    last_worked_at timestamptz,
    work_sessions integer DEFAULT 0,
    current_approach text,
    progress_notes text,
    blockers text,
    subagents_used text[],
    external_resources text[],
    added_at timestamptz DEFAULT now(),
    added_by varchar(100) DEFAULT 'NOVA',
    priority integer DEFAULT 5,
    CONSTRAINT unsolved_problems_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE unsolved_problems IS 'Humanity''s unsolved problems for NOVA to work on during idle time. Part of the Motivation System - provides meaningful default work when task queue is empty.';


COMMENT ON COLUMN unsolved_problems.priority IS 'Integer 1-10 (1=highest). NOT a string.';

--
-- Name: idx_unsolved_problems_priority; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_unsolved_problems_priority ON unsolved_problems (priority DESC);

--
-- Name: user_domains; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS user_domains (
    id SERIAL,
    entity_id integer NOT NULL,
    domain_topic varchar(255) NOT NULL,
    priority integer DEFAULT 1,
    notes text,
    created_at timestamp DEFAULT now(),
    CONSTRAINT user_domains_pkey PRIMARY KEY (id),
    CONSTRAINT user_domains_entity_domain_key UNIQUE (entity_id, domain_topic),
    CONSTRAINT user_domains_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE
);

--
-- Name: idx_user_domains_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_user_domains_entity ON user_domains (entity_id);

--
-- Name: idx_user_domains_topic; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_user_domains_topic ON user_domains (domain_topic);

--
-- Name: user_insights; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS user_insights (
    id SERIAL,
    insight text NOT NULL,
    context text,
    contributed_by integer,
    source varchar(100),
    tags text[],
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT user_insights_pkey PRIMARY KEY (id),
    CONSTRAINT user_insights_contributed_by_fkey FOREIGN KEY (contributed_by) REFERENCES entities (id)
);


COMMENT ON TABLE user_insights IS 'Human-contributed insights — observations, realizations, and wisdom shared by users. Primarily for users to save important insights. Managed by any agent on behalf of the contributing user.';


COMMENT ON COLUMN user_insights.insight IS 'The insight itself — the core observation or realization';


COMMENT ON COLUMN user_insights.context IS 'Surrounding context — what prompted the insight, what it relates to';


COMMENT ON COLUMN user_insights.contributed_by IS 'Entity ID of the human who shared the insight';


COMMENT ON COLUMN user_insights.source IS 'Where/how the insight was shared (e.g., discord, conversation, etc.)';


COMMENT ON COLUMN user_insights.tags IS 'Categorical tags for grouping and retrieval';

--
-- Name: vehicles; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS vehicles (
    id SERIAL,
    owner_id integer,
    color varchar(50),
    year integer,
    make varchar(100),
    model varchar(100),
    vin varchar(17),
    license_plate_state varchar(20),
    license_plate_number varchar(20),
    nickname varchar(100),
    notes text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT vehicles_pkey PRIMARY KEY (id),
    CONSTRAINT vehicles_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES entities (id)
);


COMMENT ON TABLE vehicles IS 'Vehicle tracking and management. Cars, bikes, boats, planes owned or used.';

--
-- Name: idx_vehicles_owner; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_vehicles_owner ON vehicles (owner_id);

--
-- Name: vocabulary; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS vocabulary (
    id SERIAL,
    word varchar(255) NOT NULL,
    category varchar(100),
    pronunciation varchar(255),
    misheard_as text[],
    added_at timestamp DEFAULT CURRENT_TIMESTAMP,
    vote_count integer DEFAULT 1,
    last_confirmed timestamp DEFAULT now(),
    CONSTRAINT vocabulary_pkey PRIMARY KEY (id),
    CONSTRAINT vocabulary_word_key UNIQUE (word)
);


COMMENT ON TABLE vocabulary IS 'Custom vocabulary for speech recognition. Add names, terms, jargon as encountered.';


COMMENT ON COLUMN vocabulary.vote_count IS 'Reinforcement count - incremented each time this word is mentioned';


COMMENT ON COLUMN vocabulary.last_confirmed IS 'Timestamp of most recent confirmation';

--
-- Name: workflow_runs; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS workflow_runs (
    id SERIAL,
    workflow_id integer NOT NULL,
    triggered_by text,
    trigger_context text,
    current_step integer,
    status varchar(20) DEFAULT 'running' NOT NULL,
    started_at timestamptz DEFAULT now() NOT NULL,
    completed_at timestamptz,
    notes text,
    channel text NOT NULL,
    CONSTRAINT workflow_runs_pkey PRIMARY KEY (id),
    CONSTRAINT workflow_runs_status_check CHECK (status::text IN ('running'::character varying, 'completed'::character varying, 'failed'::character varying, 'paused'::character varying, 'cancelled'::character varying))
);


COMMENT ON TABLE workflow_runs IS 'Tracks individual executions of workflows. Each row is one run from opening bookend to closing bookend. Updated as the orchestrator advances through steps.';


COMMENT ON COLUMN workflow_runs.trigger_context IS 'What initiated this run: issue URL, task ID, cron schedule, or description.';


COMMENT ON COLUMN workflow_runs.current_step IS 'The step_order currently being executed. NULL before first step or after completion.';


COMMENT ON COLUMN workflow_runs.notes IS 'Running log of progress: step transitions, blockers, decisions made. Append-only during execution.';


COMMENT ON COLUMN workflow_runs.channel IS 'Channel where this run was triggered and is being tracked. NOT NULL. Format: "<provider>:<channel_id>" e.g. "discord:1494763249609211905". Sentinel "unknown:pre-tracking" used for historical rows before column was added. Added 2026-05-24.';

--
-- Name: idx_workflow_runs_channel; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_runs_channel ON workflow_runs (channel) WHERE (channel IS NOT NULL);

--
-- Name: idx_workflow_runs_started; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_runs_started ON workflow_runs (started_at DESC);

--
-- Name: idx_workflow_runs_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_runs_status ON workflow_runs (status);

--
-- Name: idx_workflow_runs_workflow; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_runs_workflow ON workflow_runs (workflow_id);

--
-- Name: workflows; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS workflows (
    id SERIAL,
    name text NOT NULL,
    description text NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    created_by text DEFAULT CURRENT_USER,
    status text DEFAULT 'active',
    tags text[] DEFAULT '{}',
    department text,
    orchestrator_domain text,
    CONSTRAINT workflows_pkey PRIMARY KEY (id),
    CONSTRAINT workflows_name_key UNIQUE (name),
    CONSTRAINT workflows_status_check CHECK (status IN ('active'::text, 'deprecated'::text, 'archived'::text))
);


COMMENT ON TABLE workflows IS 'Defines multi-agent workflows with ordered steps and deliverable handoffs';

--
-- Name: idx_workflows_name; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflows_name ON workflows (name);

--
-- Name: idx_workflows_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflows_status ON workflows (status);

--
-- Name: motivation_d100; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS motivation_d100 (
    roll integer,
    task_name varchar(255),
    task_description text,
    workflow_id integer,
    skill_name varchar(255),
    tool_name varchar(255),
    difficulty varchar(20) DEFAULT 'medium',
    energy_required varchar(20) DEFAULT 'low',
    estimated_minutes integer,
    enabled boolean DEFAULT true,
    times_rolled integer DEFAULT 0,
    times_completed integer DEFAULT 0,
    last_rolled timestamp,
    last_completed timestamp,
    created_at timestamp DEFAULT now(),
    notes text,
    CONSTRAINT motivation_d100_pkey PRIMARY KEY (roll),
    CONSTRAINT motivation_d100_workflow_id_fkey FOREIGN KEY (workflow_id) REFERENCES workflows (id),
    CONSTRAINT motivation_d100_roll_check CHECK (roll >= 1 AND roll <= 100)
);


COMMENT ON TABLE motivation_d100 IS 'D100 motivation system. Roll via roll_d100(), mark complete via complete_d100(roll). 
Tracking columns (times_rolled, times_completed, last_rolled, last_completed) are 
write-protected — only the SECURITY DEFINER functions can update them. 
Content columns are open for nova to maintain. DELETE revoked to prevent accidental row loss.';


COMMENT ON COLUMN motivation_d100.roll IS 'Die value 1-100';


COMMENT ON COLUMN motivation_d100.workflow_id IS 'Optional link to workflows table for structured execution';


COMMENT ON COLUMN motivation_d100.skill_name IS 'Optional SKILL.md to follow (e.g., "daily-inspiration-art")';


COMMENT ON COLUMN motivation_d100.tool_name IS 'Optional tool to use (e.g., "bird-x", "gog")';

--
-- Name: workflow_steps; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS workflow_steps (
    id SERIAL,
    workflow_id integer NOT NULL,
    step_order integer NOT NULL,
    description text NOT NULL,
    produces_deliverable boolean DEFAULT false,
    deliverable_type text,
    deliverable_description text,
    handoff_to_step integer,
    required boolean DEFAULT true,
    estimated_duration_minutes integer,
    requires_authorization boolean DEFAULT false,
    requires_discussion boolean DEFAULT false,
    domain text,
    domains text[],
    CONSTRAINT workflow_steps_pkey PRIMARY KEY (id),
    CONSTRAINT workflow_steps_workflow_id_step_order_key UNIQUE (workflow_id, step_order),
    CONSTRAINT workflow_steps_handoff_to_step_fkey FOREIGN KEY (handoff_to_step) REFERENCES workflow_steps (id),
    CONSTRAINT workflow_steps_workflow_id_fkey FOREIGN KEY (workflow_id) REFERENCES workflows (id) ON DELETE CASCADE
);


COMMENT ON TABLE workflow_steps IS 'Ordered steps in a workflow with agent assignments and deliverable specifications';


COMMENT ON COLUMN workflow_steps.requires_authorization IS 'If true, must get explicit human authorization before proceeding to next step';


COMMENT ON COLUMN workflow_steps.requires_discussion IS 'If true, discuss with human before proceeding (but can continue without explicit authorization if authorization=false)';


COMMENT ON COLUMN workflow_steps.domain IS 'Subject-matter domain for agent routing (e.g., sql/database, python/daemon)';

--
-- Name: idx_workflow_steps_domain; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_steps_domain ON workflow_steps (domain);

--
-- Name: idx_workflow_steps_order; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_steps_order ON workflow_steps (workflow_id, step_order);

--
-- Name: works; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS works (
    id SERIAL,
    title varchar(255) NOT NULL,
    work_type varchar(50) NOT NULL,
    content text NOT NULL,
    context_prompt text,
    word_count integer,
    character_count integer,
    language varchar(10) DEFAULT 'en',
    status varchar(20) DEFAULT 'draft',
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    version integer DEFAULT 1,
    parent_work_id integer,
    metadata jsonb,
    CONSTRAINT works_pkey PRIMARY KEY (id),
    CONSTRAINT works_parent_work_id_fkey FOREIGN KEY (parent_work_id) REFERENCES works (id) ON DELETE SET NULL,
    CONSTRAINT positive_counts CHECK (word_count >= 0 AND character_count >= 0),
    CONSTRAINT valid_status CHECK (status::text IN ('draft'::character varying, 'complete'::character varying, 'published'::character varying, 'archived'::character varying)),
    CONSTRAINT valid_work_type CHECK (work_type::text IN ('haiku'::character varying, 'poem'::character varying, 'prose'::character varying, 'documentation'::character varying, 'story'::character varying, 'dialogue'::character varying, 'microfiction'::character varying, 'essay'::character varying, 'other'::character varying))
);

--
-- Name: publications; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS publications (
    id SERIAL,
    work_id integer NOT NULL,
    published_to varchar(100) NOT NULL,
    publication_type varchar(50) NOT NULL,
    url text,
    context text,
    published_at timestamptz DEFAULT now() NOT NULL,
    published_by varchar(50),
    CONSTRAINT publications_pkey PRIMARY KEY (id),
    CONSTRAINT publications_work_id_fkey FOREIGN KEY (work_id) REFERENCES works (id) ON DELETE CASCADE,
    CONSTRAINT valid_publication_type CHECK (publication_type::text IN ('git_repo'::character varying, 'doc'::character varying, 'file'::character varying, 'agent_chat'::character varying, 'external'::character varying, 'other'::character varying))
);

--
-- Name: work_tags; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS work_tags (
    work_id integer,
    tag_id integer,
    added_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT work_tags_pkey PRIMARY KEY (work_id, tag_id),
    CONSTRAINT work_tags_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE,
    CONSTRAINT work_tags_work_id_fkey FOREIGN KEY (work_id) REFERENCES works (id) ON DELETE CASCADE
);

--
-- Name: _trg_log_d100_roll(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION _trg_log_d100_roll()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF NEW.last_rolled IS DISTINCT FROM OLD.last_rolled AND NEW.last_rolled IS NOT NULL THEN
        INSERT INTO d100_roll_log (roll, rolled_at)
        VALUES (NEW.roll, NEW.last_rolled);
    END IF;
    RETURN NEW;
END;
$$;

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
-- Name: complete_d100(integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION complete_d100(
    p_roll integer
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE motivation_d100 m
    SET times_completed = COALESCE(m.times_completed, 0) + 1,
        last_completed = NOW()
    WHERE m.roll = p_roll
      AND m.task_name IS NOT NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete_d100: roll % not found or has no task', p_roll;
    END IF;
END;
$$;

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
-- Name: current_agent_id(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION current_agent_id()
RETURNS integer
LANGUAGE sql
STABLE
AS $$
  SELECT id FROM agents WHERE name = current_user LIMIT 1;
$$;

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
    v_stripped TEXT;
BEGIN
    SELECT id INTO v_agent_id FROM agents WHERE name = p_agent_name LIMIT 1;

    RETURN QUERY
    SELECT DISTINCT ON (subq.filename)
        subq.filename,
        subq.content,
        subq.source
    FROM (
        -- 1. UNIVERSAL (exclude SYSTEM records)
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'UNIVERSAL'::TEXT AS source, 1 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'UNIVERSAL'
          AND abc.file_key != 'SYSTEM_PROMPT'

        UNION ALL

        -- 2. GLOBAL (exclude SYSTEM records)
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'GLOBAL'::TEXT AS source, 2 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'GLOBAL'
          AND abc.file_key != 'SYSTEM_PROMPT'

        UNION ALL

        -- 3. DOMAIN — match if ANY domain_names entry overlaps agent's domains
        SELECT
            abc.file_key || '.md' AS filename,
            abc.content,
            'DOMAIN:' || (
                SELECT string_agg(dn, ', ' ORDER BY dn)
                FROM unnest(abc.domain_names) AS dn
            ) AS source,
            3 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'DOMAIN'
          AND abc.file_key != 'SYSTEM_PROMPT'
          AND EXISTS (
              SELECT 1 FROM agent_domains ad
              WHERE ad.agent_id = v_agent_id
                AND ad.domain_topic = ANY(abc.domain_names)
          )

        UNION ALL

        -- 4. WORKFLOW — compact summary only (name, purpose, id, your steps)
        --    Full workflow descriptions are read on-demand when executing a workflow.
        SELECT
            'WORKFLOW_' || upper(replace(w.name, '-', '_')) || '.md' AS filename,
            w.name || ' (workflow_id=' || w.id || '): ' ||
            -- Extract first meaningful sentence: strip boilerplate header, then
            -- strip markdown headings and blank lines, take first real line
            (SELECT COALESCE(
                (SELECT line FROM unnest(string_to_array(
                    regexp_replace(
                        CASE
                            WHEN w.description ~ E'^>.*?\\n+---\\n+'
                            THEN regexp_replace(w.description, E'^>.*?\\n+---\\n+', '', 's')
                            ELSE w.description
                        END,
                        E'^[\\s>⚙️📋*#-]+', '', 'g'
                    ),
                    E'\n'
                )) AS line
                WHERE trim(line) != ''
                  AND line !~ E'^\\s*[>#*=-]+\\s*$'
                  AND line !~ E'^\\s*$'
                  AND line !~ E'^\\s*---\\s*$'
                  AND length(trim(line)) > 20
                LIMIT 1),
                w.name
            )) ||
            E'\n' ||
            CASE WHEN EXISTS (
                SELECT 1 FROM agent_domains ad
                WHERE ad.agent_id = v_agent_id
                  AND ad.domain_topic = w.orchestrator_domain
            )
            THEN 'Managed by ' || p_agent_name || ' (' || w.orchestrator_domain || '). '
            ELSE ''
            END ||
            'Your steps: ' || COALESCE(agent_steps.step_list, 'none directly assigned') ||
            '. Query: SELECT step_order, domain, description FROM workflow_steps WHERE workflow_id = ' || w.id || ' ORDER BY step_order;'
            AS content,
            'WORKFLOW:' || w.name AS source,
            4 AS priority
        FROM workflows w
        LEFT JOIN LATERAL (
            SELECT string_agg(
                'Step ' || ws.step_order || ' (' || ws.domain || ')',
                ', ' ORDER BY ws.step_order
            ) AS step_list
            FROM workflow_steps ws
            JOIN agent_domains ad ON ad.agent_id = v_agent_id
            WHERE ws.workflow_id = w.id
              AND (ad.domain_topic = ws.domain OR ad.domain_topic = ANY(ws.domains))
        ) agent_steps ON TRUE
        WHERE EXISTS (
            SELECT 1
            FROM workflow_steps ws
            JOIN agent_domains ad ON ad.agent_id = v_agent_id
            WHERE ws.workflow_id = w.id
              AND (ad.domain_topic = ws.domain OR ad.domain_topic = ANY(ws.domains))
        )

        UNION ALL

        -- 5. AGENT (never SYSTEM)
        SELECT abc.file_key || '.md' AS filename, abc.content,
            'AGENT'::TEXT AS source, 5 AS priority
        FROM agent_bootstrap_context abc
        WHERE abc.context_type = 'AGENT'
          AND abc.agent_name = p_agent_name
          AND abc.file_key != 'SYSTEM_PROMPT'
    ) subq
    ORDER BY subq.filename, subq.priority;
END;
$$;

--
-- Name: get_agent_bootstrap(text); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION get_agent_bootstrap(text) IS 'Bootstrap context: UNIVERSAL + GLOBAL + DOMAIN + WORKFLOW summaries (name, description, agent role, query pointer — NO full step descriptions) + AGENT. Domain-based matching only. See nova-mind#171.';

--
-- Name: get_agent_export_rows(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION get_agent_export_rows()
RETURNS TABLE(name text, model text, fallback_models text[], thinking text, instance_type text, is_default boolean, allowed_subagents text[], heartbeat_enabled boolean, heartbeat_every text, heartbeat_target text, heartbeat_to text)
LANGUAGE sql
STABLE
AS $$
  SELECT
    a.name::text,
    a.model::text,
    a.fallback_models,
    a.thinking::text,
    a.instance_type::text,
    TRUE AS is_default,
    a.allowed_subagents,
    a.heartbeat_enabled,
    a.heartbeat_every,
    a.heartbeat_target,
    a.heartbeat_to
  FROM agents a
  WHERE a.name = session_user
    AND a.status = 'active'
    AND a.model IS NOT NULL

  UNION ALL

  SELECT
    a.name::text,
    a.model::text,
    a.fallback_models,
    a.thinking::text,
    a.instance_type::text,
    FALSE AS is_default,
    a.allowed_subagents,
    a.heartbeat_enabled,
    a.heartbeat_every,
    a.heartbeat_target,
    a.heartbeat_to
  FROM agents a
  WHERE session_user = ANY (a.parent_agents)
    AND a.status = 'active'
    AND a.model IS NOT NULL

  ORDER BY 6 DESC, 1;
$$;

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
    p_agent_name text DEFAULT NULL
)
RETURNS TABLE(id integer, context_type text, agent_name text, domain_names text[], file_key text, description text, content_length integer)
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        abc.id,
        abc.context_type,
        abc.agent_name,
        abc.domain_names,
        abc.file_key,
        abc.description,
        LENGTH(abc.content)::INTEGER AS content_length
    FROM agent_bootstrap_context abc
    WHERE
        CASE
            WHEN p_agent_name IS NULL THEN TRUE
            ELSE abc.agent_name = p_agent_name
                 OR abc.context_type IN ('UNIVERSAL', 'GLOBAL')
                 OR (abc.context_type = 'DOMAIN' AND EXISTS (
                     SELECT 1 FROM agent_domains ad
                     JOIN agents a ON a.id = ad.agent_id
                     WHERE a.name = p_agent_name
                       AND ad.domain_topic = ANY(abc.domain_names)
                 ))
        END
    ORDER BY
        CASE abc.context_type
            WHEN 'UNIVERSAL' THEN 1
            WHEN 'GLOBAL' THEN 2
            WHEN 'DOMAIN' THEN 3
            WHEN 'AGENT' THEN 4
        END,
        abc.file_key;
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
-- Name: merge_facts(integer, integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION merge_facts(
    survivor_id integer,
    absorbed_id integer
)
RETURNS entity_facts
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    survivor_row entity_facts%ROWTYPE;
    absorbed_row entity_facts%ROWTYPE;
    merged_sources INTEGER;
    result_row entity_facts%ROWTYPE;
BEGIN
    -- Validate inputs
    IF survivor_id = absorbed_id THEN
        RAISE EXCEPTION 'cannot merge a fact with itself';
    END IF;

    SELECT * INTO survivor_row FROM entity_facts WHERE id = survivor_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'survivor fact % does not exist', survivor_id;
    END IF;

    SELECT * INTO absorbed_row FROM entity_facts WHERE id = absorbed_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'absorbed fact % does not exist', absorbed_id;
    END IF;

    IF survivor_row.entity_id != absorbed_row.entity_id THEN
        RAISE EXCEPTION 'cannot merge facts from different entities';
    END IF;

    -- Merge source attributions
    -- Shared sources: sum attribution_count, keep earliest first_seen, latest last_seen
    UPDATE entity_fact_sources s_survivor
    SET attribution_count = s_survivor.attribution_count + s_absorbed.attribution_count,
        first_seen = LEAST(s_survivor.first_seen, s_absorbed.first_seen),
        last_seen  = GREATEST(s_survivor.last_seen, s_absorbed.last_seen)
    FROM entity_fact_sources s_absorbed
    WHERE s_survivor.fact_id = survivor_id
      AND s_absorbed.fact_id = absorbed_id
      AND s_survivor.source_entity_id = s_absorbed.source_entity_id;

    GET DIAGNOSTICS merged_sources = ROW_COUNT;

    -- Move unique sources from absorbed to survivor
    INSERT INTO entity_fact_sources (fact_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen)
    SELECT survivor_id, source_entity_id, source_citation, attribution_count, first_seen, last_seen
    FROM entity_fact_sources
    WHERE fact_id = absorbed_id
      AND source_entity_id NOT IN (
          SELECT source_entity_id FROM entity_fact_sources WHERE fact_id = survivor_id
      );

    -- Delete absorbed sources
    DELETE FROM entity_fact_sources WHERE fact_id = absorbed_id;

    -- Update survivor with merged values
    UPDATE entity_facts
    SET extraction_count = COALESCE(survivor_row.extraction_count, 1) + COALESCE(absorbed_row.extraction_count, 1),
        last_confirmed_at = GREATEST(survivor_row.last_confirmed_at, absorbed_row.last_confirmed_at),
        confidence = GREATEST(survivor_row.confidence, absorbed_row.confidence),
        updated_at = NOW()
    WHERE id = survivor_id;

    -- Delete absorbed fact
    DELETE FROM entity_facts WHERE id = absorbed_id;

    -- Return updated survivor
    SELECT * INTO result_row FROM entity_facts WHERE id = survivor_id;
    RETURN result_row;
END;
$$;

--
-- Name: merge_entities(integer, integer); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION merge_entities(
    survivor_id integer,
    absorbed_id integer
)
RETURNS entities
LANGUAGE plpgsql
VOLATILE
AS $_$
DECLARE
    survivor entities%ROWTYPE;
    absorbed entities%ROWTYPE;
    fk_ref RECORD;
    ef1 RECORD;
    ef2 RECORD;
    existing_fact RECORD;
BEGIN
    -- Validate: ids must differ
    IF survivor_id = absorbed_id THEN
        RAISE EXCEPTION 'merge_entities: survivor_id and absorbed_id must be different (%)', survivor_id;
    END IF;

    -- Validate: both entities must exist
    SELECT * INTO survivor FROM entities WHERE id = survivor_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'merge_entities: survivor entity % does not exist', survivor_id;
    END IF;

    SELECT * INTO absorbed FROM entities WHERE id = absorbed_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'merge_entities: absorbed entity % does not exist', absorbed_id;
    END IF;

    -- 1. Handle entity_facts FIRST (before generic FK transfer)
    FOR ef1 IN
        SELECT * FROM entity_facts WHERE entity_id = absorbed_id
    LOOP
        -- Check if survivor already has a fact with the same key
        SELECT * INTO existing_fact
        FROM entity_facts
        WHERE entity_id = survivor_id AND key = ef1.key;

        IF FOUND THEN
            -- Both have facts with same key: merge them via merge_facts()
            -- Move absorbed fact to survivor entity first, so merge_facts sees same entity_id
            UPDATE entity_facts SET entity_id = survivor_id WHERE id = ef1.id;
            PERFORM merge_facts(existing_fact.id, ef1.id);
        ELSE
            -- Unique key on absorbed entity: just update the entity_id
            UPDATE entity_facts SET entity_id = survivor_id WHERE id = ef1.id;
        END IF;
    END LOOP;

    -- 2. Transfer all OTHER FK references dynamically (entity_facts already handled)
    FOR fk_ref IN
        SELECT tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu
            ON ccu.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND ccu.table_name = 'entities'
          AND ccu.column_name = 'id'
          AND tc.table_name != 'entity_facts'
    LOOP
        EXECUTE format(
            'UPDATE %I SET %I = $1 WHERE %I = $2',
            fk_ref.table_name,
            fk_ref.column_name,
            fk_ref.column_name
        ) USING survivor_id, absorbed_id;
    END LOOP;

    -- 3. Handle memory_embeddings (not a proper FK — source_id is text)
    -- Delete absorbed entity's embedding if survivor already has one
    DELETE FROM memory_embeddings
    WHERE source_type = 'entity' AND source_id = absorbed_id::text
      AND EXISTS (
        SELECT 1 FROM memory_embeddings
        WHERE source_type = 'entity' AND source_id = survivor_id::text
      );
    -- Move any remaining (survivor didn't have one)
    UPDATE memory_embeddings
    SET source_id = survivor_id::text
    WHERE source_type = 'entity' AND source_id = absorbed_id::text;

    -- Add absorbed entity's name to survivor's nicknames (if not already present)
    IF absorbed.name IS NOT NULL THEN
        IF survivor.nicknames IS NULL THEN
            UPDATE entities SET nicknames = ARRAY[absorbed.name] WHERE id = survivor_id;
        ELSIF NOT (absorbed.name = ANY(survivor.nicknames)) THEN
            UPDATE entities SET nicknames = array_append(survivor.nicknames, absorbed.name) WHERE id = survivor_id;
        END IF;
    END IF;

    -- Delete the absorbed entity
    DELETE FROM entities WHERE id = absorbed_id;

    -- Return the updated survivor
    SELECT * INTO survivor FROM entities WHERE id = survivor_id;
    RETURN survivor;
END;
$_$;

--
-- Name: music_works_search_update(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION music_works_search_update()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    NEW.search_vector := to_tsvector('english',
        coalesce(NEW.title, '') || ' ' ||
        coalesce(NEW.description, '') || ' ' ||
        coalesce(NEW.genre, '') || ' ' ||
        coalesce(NEW.subgenre, '') || ' ' ||
        coalesce(NEW.mood, '') || ' ' ||
        coalesce(NEW.notes, '') || ' ' ||
        coalesce(NEW.lyrics, '')
    );
    NEW.updated_at := NOW();
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
-- Name: notify_heartbeat_content_changed(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_heartbeat_content_changed()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    -- Only notify for rows where file_key = 'HEARTBEAT'
    IF (TG_OP = 'DELETE' AND OLD.file_key = 'HEARTBEAT') OR
       (TG_OP != 'DELETE' AND NEW.file_key = 'HEARTBEAT') THEN
        PERFORM pg_notify('heartbeat_content_changed', json_build_object(
            'agent_name', COALESCE(NEW.agent_name, OLD.agent_name),
            'operation', TG_OP
        )::text);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: notify_heartbeat_content_changed(); Type: FUNCTION; Schema: -; Owner: -
--

COMMENT ON FUNCTION notify_heartbeat_content_changed() IS 'Fires heartbeat_content_changed NOTIFY when HEARTBEAT rows in agent_bootstrap_context are inserted or updated. Consumed by agent_config_sync plugin to refresh workspace HEARTBEAT.md files.';

--
-- Name: notify_schema_change(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION notify_schema_change()
RETURNS event_trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE payload text; obj record;
BEGIN
  SELECT INTO obj command_tag, object_type, schema_name, object_identity
  FROM (SELECT DISTINCT ON (object_identity) command_tag, object_type, schema_name, object_identity
        FROM pg_event_trigger_ddl_commands()) deduped LIMIT 1;
  IF obj IS NOT NULL THEN
    payload := json_build_object('command_tag', obj.command_tag, 'object_type', obj.object_type,
      'schema_name', obj.schema_name, 'object_identity', obj.object_identity)::text;
    PERFORM pg_notify('schema_changed', payload);
  END IF;
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
-- Name: nova_reset_hermes_password(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION nova_reset_hermes_password()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
AS $$
BEGIN
  EXECUTE 'ALTER USER hermes WITH PASSWORD ' || quote_literal('hermes-agent-2024');
  RETURN 'done';
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
    IF current_user NOT IN ('newhart', 'postgres') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
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
    IF current_user NOT IN ('newhart', 'postgres') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
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
-- Name: protect_bootstrap_context_writes_v2(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION protect_bootstrap_context_writes_v2()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  self_managed_keys TEXT[] := ARRAY[
    'identity', 'IDENTITY',
    'AGENTS',
    'TOOLS',
    'HEARTBEAT',
    'MEMORY'
  ];
BEGIN
  -- Superuser, newhart, and postgres always pass
  IF current_user IN ('newhart', 'postgres') OR (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- INSERT: agents can create their own AGENT records with self-managed file_keys
  IF TG_OP = 'INSERT' THEN
    IF NEW.context_type = 'AGENT'
       AND NEW.agent_name = current_user
       AND NEW.file_key = ANY(self_managed_keys)
    THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION
      'agent_bootstrap_context INSERT denied for user "%". '
      'Agents may only insert their own AGENT records with self-managed file_keys '
      '(identity, IDENTITY, AGENTS, TOOLS, HEARTBEAT, MEMORY). '
      'Contact Newhart for other changes.',
      current_user;
  END IF;

  -- UPDATE: agents can update their own AGENT records with self-managed file_keys
  IF TG_OP = 'UPDATE' THEN
    IF NEW.context_type = 'AGENT'
       AND NEW.file_key = ANY(self_managed_keys)
       AND NEW.agent_name = current_user
       AND NEW.agent_name = OLD.agent_name
       AND NEW.file_key   = OLD.file_key
       AND NEW.context_type = OLD.context_type
    THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION
      'agent_bootstrap_context UPDATE denied for user "%". '
      'Agents may only update their own AGENT records with self-managed file_keys '
      '(identity, IDENTITY, AGENTS, TOOLS, HEARTBEAT, MEMORY). '
      'Contact Newhart for other changes.',
      current_user;
  END IF;

  -- DELETE: only newhart/postgres/superusers (already returned above)
  RAISE EXCEPTION
    'agent_bootstrap_context DELETE denied for user "%". '
    'Only Newhart can delete bootstrap context records.',
    current_user;
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
    IF current_user NOT IN ('athena', 'postgres') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'Library tables are managed by the Library domain (athena). Contact the Library domain for changes.';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: protect_peer_agent_model_changes(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION protect_peer_agent_model_changes()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF OLD.name IN ('nova', 'graybeard', 'newhart') THEN
        IF (OLD.model IS DISTINCT FROM NEW.model) OR (OLD.fallback_models IS DISTINCT FROM NEW.fallback_models) THEN
            IF current_user NOT IN ('postgres', 'newhart') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
                RAISE EXCEPTION 'Model changes to peer agents (nova, graybeard, newhart) require human authorization. Use postgres user or contact I)ruid.';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
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
    IF current_user NOT IN ('scout', 'postgres') AND NOT (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'Research tables are managed by the Research domain (scout). Contact the Research domain for changes.';
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

--
-- Name: protect_turn_context_writes(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION protect_turn_context_writes()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  -- Superuser, newhart, and postgres always pass
  IF current_user IN ('newhart', 'postgres') OR (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  RAISE EXCEPTION
    'agent_turn_context writes denied for user "%". Contact Newhart for changes.',
    current_user;
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
-- Name: raise_trades_immutable(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION raise_trades_immutable()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    RAISE EXCEPTION 'trades table is append-only: % operations are not allowed', TG_OP;
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
RETURNS TABLE(roll integer, task_name varchar, task_description text, workflow_id integer, skill_name varchar, tool_name varchar, difficulty varchar, energy_required varchar, estimated_minutes integer, times_rolled integer, times_completed integer, last_rolled timestamp, last_completed timestamp, notes text)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    picked_roll integer;
    attempts    integer := 0;
    max_attempts integer := 20;
BEGIN
    LOOP
        attempts := attempts + 1;
        IF attempts > max_attempts THEN
            RAISE EXCEPTION 'roll_d100: no populated+enabled tasks found after % attempts', max_attempts;
        END IF;

        -- Pure random 1-100
        picked_roll := floor(random() * 100 + 1)::integer;

        -- Check if this slot is populated and enabled
        IF EXISTS (
            SELECT 1 FROM motivation_d100 m
            WHERE m.roll = picked_roll
              AND m.task_name IS NOT NULL
              AND m.enabled = true
        ) THEN
            -- Update tracking columns
            UPDATE motivation_d100 m
            SET times_rolled = COALESCE(m.times_rolled, 0) + 1,
                last_rolled = NOW()
            WHERE m.roll = picked_roll;

            -- Return the task
            RETURN QUERY
            SELECT m.roll, m.task_name, m.task_description, m.workflow_id,
                   m.skill_name, m.tool_name, m.difficulty, m.energy_required,
                   m.estimated_minutes, m.times_rolled, m.times_completed,
                   m.last_rolled, m.last_completed, m.notes
            FROM motivation_d100 m
            WHERE m.roll = picked_roll;
            RETURN;
        END IF;
    END LOOP;
END;
$$;

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
-- Name: tasks_force_created_by(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION tasks_force_created_by()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  caller_entity_id INTEGER;
BEGIN
  -- Look up the canonical entity ID for the current database user
  -- Matches entities with type='ai' and name matching the db role (case-insensitive)
  -- Uses lowest ID to get the canonical/original entity, not duplicates
  SELECT id INTO caller_entity_id
  FROM entities
  WHERE lower(name) = current_user
    AND type = 'ai'
  ORDER BY id ASC
  LIMIT 1;

  IF caller_entity_id IS NULL THEN
    RAISE EXCEPTION 'No entity found for database user "%". Cannot create task without valid creator identity.', current_user;
  END IF;

  -- FORCE created_by regardless of what was passed — no spoofing
  NEW.created_by := caller_entity_id;

  -- assigned_to is required
  IF NEW.assigned_to IS NULL THEN
    RAISE EXCEPTION 'assigned_to is required — who is this task for?';
  END IF;

  RETURN NEW;
END;
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
-- Name: update_income_sources_updated_at(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_income_sources_updated_at()
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
-- Name: update_user_insights_updated_at(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION update_user_insights_updated_at()
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
-- Name: upsert_domain_context(text[], text, text, text, text); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION upsert_domain_context(
    p_domain_names text[],
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
    INSERT INTO agent_bootstrap_context (context_type, domain_names, file_key, content, description, updated_by, updated_at)
    VALUES ('DOMAIN', p_domain_names, p_file_key, p_content, p_description, p_updated_by, NOW())
    ON CONFLICT (file_key) WHERE context_type = 'DOMAIN'
    DO UPDATE SET
        domain_names = EXCLUDED.domain_names,
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
    INSERT INTO agent_bootstrap_context (context_type, file_key, content, description, updated_by, updated_at)
    VALUES ('GLOBAL', p_file_key, p_content, p_description, p_updated_by, NOW())
    ON CONFLICT (context_type, COALESCE(agent_name, ''), file_key)
        WHERE context_type IN ('UNIVERSAL', 'GLOBAL', 'AGENT')
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
-- Name: validate_parent_agents(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION validate_parent_agents()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_bad_name text;
BEGIN
  IF NEW.parent_agents IS NULL OR array_length(NEW.parent_agents, 1) IS NULL THEN
    RETURN NEW;
  END IF;

  -- Every element must reference an existing agent
  SELECT u INTO v_bad_name
  FROM unnest(NEW.parent_agents) AS u
  WHERE NOT EXISTS (SELECT 1 FROM agents WHERE name = u);

  IF v_bad_name IS NOT NULL THEN
    RAISE EXCEPTION 'parent_agents references non-existent agent: %', v_bad_name;
  END IF;

  -- No self-parent
  IF NEW.name = ANY (NEW.parent_agents) THEN
    RAISE EXCEPTION 'agent % cannot be its own parent', NEW.name;
  END IF;

  RETURN NEW;
END;
$$;

--
-- Name: journal_entries; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS journal_entries (
    id SERIAL,
    agent_id integer DEFAULT current_agent_id() NOT NULL,
    content text NOT NULL,
    trigger varchar(50) DEFAULT 'manual' NOT NULL,
    mood varchar(50),
    created_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT journal_entries_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE journal_entries IS 'Personal prose journal entries for agent self-reflection. Short, introspective, written multiple times daily. Embedded into memory_embeddings with source_type=journal. Triggers: heartbeat, d100, post_workflow, daily_report, conversation, incident, manual.';


COMMENT ON COLUMN journal_entries.trigger IS 'What prompted this entry: heartbeat, d100, post_workflow, daily_report, conversation, incident, manual';


COMMENT ON COLUMN journal_entries.mood IS 'Optional self-assessed mood/tone at time of writing';

--
-- Name: idx_journal_agent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_journal_agent ON journal_entries (agent_id);

--
-- Name: idx_journal_created; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_journal_created ON journal_entries (created_at DESC);

--
-- Name: idx_journal_trigger; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_journal_trigger ON journal_entries (trigger);

--
-- Name: lessons; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS lessons (
    id SERIAL,
    lesson text NOT NULL,
    context text,
    source varchar(255),
    learned_at timestamp DEFAULT CURRENT_TIMESTAMP,
    original_behavior text,
    correction_source text,
    reinforced_at timestamp,
    confidence double precision DEFAULT 1.0,
    last_referenced timestamp,
    last_confirmed_at timestamptz DEFAULT now(),
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
    learned_by integer DEFAULT current_agent_id(),
    CONSTRAINT lessons_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE lessons IS 'Lessons and insights learned. Update when learning something worth remembering.';


COMMENT ON COLUMN lessons.confidence IS 'Confidence score 0-1, decays over time if not reinforced';

--
-- Name: music_works; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS music_works (
    id SERIAL,
    title varchar(255) NOT NULL,
    description text,
    created_by integer DEFAULT current_agent_id(),
    generation_model varchar(255),
    generation_prompt text,
    generation_params jsonb DEFAULT '{}',
    source_type varchar(50) DEFAULT 'ai_generated' NOT NULL,
    key varchar(10),
    bpm numeric,
    time_signature varchar(10),
    duration_ms integer,
    genre varchar(100),
    subgenre varchar(100),
    mood varchar(100),
    energy_level integer,
    danceability integer,
    structure text,
    instruments text[],
    vocal_style varchar(100),
    file_format varchar(20),
    sample_rate integer,
    bit_depth integer,
    bitrate integer,
    version integer DEFAULT 1 NOT NULL,
    parent_work_id integer,
    iteration_notes text,
    lyrics text,
    language varchar(10),
    status varchar(50) DEFAULT 'draft' NOT NULL,
    tags text[],
    rating integer,
    notes text,
    created_at timestamp DEFAULT now() NOT NULL,
    updated_at timestamp DEFAULT now() NOT NULL,
    search_vector tsvector,
    published_platforms jsonb DEFAULT '{}',
    audio_data bytea,
    audio_filename text,
    cover_image_data bytea,
    cover_image_filename text,
    nostr_event_id text,
    CONSTRAINT music_works_pkey PRIMARY KEY (id),
    CONSTRAINT music_works_parent_work_id_fkey FOREIGN KEY (parent_work_id) REFERENCES music_works (id),
    CONSTRAINT music_works_danceability_check CHECK (danceability >= 1 AND danceability <= 10),
    CONSTRAINT music_works_energy_level_check CHECK (energy_level >= 1 AND energy_level <= 10),
    CONSTRAINT music_works_rating_check CHECK (rating >= 1 AND rating <= 10)
);


COMMENT ON TABLE music_works IS 'Original music compositions (AI-generated or human-composed). Complements music_library which holds collected external sources.';


COMMENT ON COLUMN music_works.published_platforms IS 'Publishing record: platform URLs/IDs. Example: {"wavlake": {"url": "...", "track_id": "..."}, "nostr": {"event_id": "..."}}';


COMMENT ON COLUMN music_works.audio_data IS 'Binary audio data for produced works. Matches artwork.image_data pattern. WIP audio stays on disk.';


COMMENT ON COLUMN music_works.audio_filename IS 'Original filename of the audio file (e.g. midnight-drive-v3.wav)';


COMMENT ON COLUMN music_works.cover_image_data IS 'Cover art binary blob, same pattern as artwork.image_data and audio_data.';


COMMENT ON COLUMN music_works.cover_image_filename IS 'Original filename of cover art image.';

--
-- Name: idx_music_works_created_by; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_works_created_by ON music_works (created_by);

--
-- Name: idx_music_works_genre; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_works_genre ON music_works (genre);

--
-- Name: idx_music_works_parent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_works_parent ON music_works (parent_work_id);

--
-- Name: idx_music_works_search; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_works_search ON music_works USING gin (search_vector);

--
-- Name: idx_music_works_source_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_works_source_type ON music_works (source_type);

--
-- Name: idx_music_works_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_works_status ON music_works (status);

--
-- Name: tasks; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL,
    title varchar(255) NOT NULL,
    description text,
    status varchar(50) DEFAULT 'pending',
    priority integer DEFAULT 5,
    parent_task_id integer,
    project_id integer,
    assigned_to integer NOT NULL,
    created_by integer DEFAULT current_agent_id() NOT NULL,
    due_date timestamp,
    completed_at timestamp,
    notes text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
    task_number integer,
    blocked boolean DEFAULT false,
    blocked_reason text,
    blocked_on integer,
    last_worked_at timestamptz,
    work_notes text,
    task_type varchar(20) DEFAULT 'one_off',
    recurrence_interval interval,
    last_completed_at timestamptz,
    CONSTRAINT tasks_pkey PRIMARY KEY (id),
    CONSTRAINT tasks_parent_task_id_fkey FOREIGN KEY (parent_task_id) REFERENCES tasks (id) ON DELETE CASCADE
);


COMMENT ON TABLE tasks IS 'Task tracking. NOVA can create, update status, assign. Check before starting work.';


COMMENT ON COLUMN tasks.priority IS 'Integer 1-10 (1=highest, 10=lowest). NOT a string enum — do not use values like ''low'', ''medium'', ''high''.';


COMMENT ON COLUMN tasks.task_type IS 'one_off = complete once, recurring = resets after completion, fallback = low-priority repeatable when idle';


COMMENT ON COLUMN tasks.recurrence_interval IS 'How often recurring tasks reset (e.g., 1 day, 1 week)';


COMMENT ON COLUMN tasks.last_completed_at IS 'When task was last completed (for recurring reset logic)';

--
-- Name: idx_tasks_parent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks (parent_task_id);

--
-- Name: idx_tasks_priority; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks (priority);

--
-- Name: idx_tasks_project; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_tasks_project ON tasks (project_id);

--
-- Name: idx_tasks_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks (status);

--
-- Name: lessons_learned_by_fkey; Type: CONSTRAINT; Schema: -; Owner: -
--

ALTER TABLE lessons
ADD CONSTRAINT lessons_learned_by_fkey FOREIGN KEY (learned_by) REFERENCES agents (id);

--
-- Name: tasks_assigned_to_fkey; Type: CONSTRAINT; Schema: -; Owner: -
--

ALTER TABLE tasks
ADD CONSTRAINT tasks_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES entities (id);

--
-- Name: tasks_blocked_on_fkey; Type: CONSTRAINT; Schema: -; Owner: -
--

ALTER TABLE tasks
ADD CONSTRAINT tasks_blocked_on_fkey FOREIGN KEY (blocked_on) REFERENCES entities (id);

--
-- Name: tasks_created_by_fkey; Type: CONSTRAINT; Schema: -; Owner: -
--

ALTER TABLE tasks
ADD CONSTRAINT tasks_created_by_fkey FOREIGN KEY (created_by) REFERENCES entities (id);

--
-- Name: tasks_project_id_fkey; Type: CONSTRAINT; Schema: -; Owner: -
--

ALTER TABLE tasks
ADD CONSTRAINT tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE SET NULL;

--
-- Name: agent_config_changed; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER agent_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agents
    FOR EACH ROW
    EXECUTE FUNCTION notify_agent_config_changed();

--
-- Name: agents_delegation_notify; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER agents_delegation_notify
    AFTER INSERT OR UPDATE OR DELETE ON agents
    FOR EACH ROW
    EXECUTE FUNCTION notify_delegation_change();

--
-- Name: agents_updated_at; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER agents_updated_at
    BEFORE UPDATE ON agents
    FOR EACH ROW
    EXECUTE FUNCTION update_agents_timestamp();

--
-- Name: coder_queue_notify; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER coder_queue_notify
    AFTER INSERT OR UPDATE ON git_issue_queue
    FOR EACH ROW
    EXECUTE FUNCTION notify_coder_queue_change();

--
-- Name: enforce_project_lock; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER enforce_project_lock
    BEFORE UPDATE ON projects
    FOR EACH ROW
    EXECUTE FUNCTION prevent_locked_project_update();

--
-- Name: gambling_entries_notify; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER gambling_entries_notify
    AFTER INSERT OR UPDATE OR DELETE ON gambling_entries
    FOR EACH ROW
    EXECUTE FUNCTION notify_gambling_change();

--
-- Name: gambling_logs_notify; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER gambling_logs_notify
    AFTER INSERT OR UPDATE OR DELETE ON gambling_logs
    FOR EACH ROW
    EXECUTE FUNCTION notify_gambling_change();

--
-- Name: heartbeat_content_changed; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER heartbeat_content_changed
    AFTER INSERT OR UPDATE ON agent_bootstrap_context
    FOR EACH ROW
    WHEN (((NEW.file_key = 'HEARTBEAT'::text)))
    EXECUTE FUNCTION notify_heartbeat_content_changed();

--
-- Name: media_search_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER media_search_update
    BEFORE INSERT OR UPDATE ON media_consumed
    FOR EACH ROW
    EXECUTE FUNCTION update_media_search_vector();

--
-- Name: media_search_vector_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER media_search_vector_update
    BEFORE INSERT OR UPDATE ON media_consumed
    FOR EACH ROW
    EXECUTE FUNCTION update_media_search_vector();

--
-- Name: music_analysis_search_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER music_analysis_search_update
    BEFORE INSERT OR UPDATE ON music_analysis
    FOR EACH ROW
    EXECUTE FUNCTION update_music_analysis_search_vector();

--
-- Name: music_search_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER music_search_update
    BEFORE INSERT OR UPDATE ON music_library
    FOR EACH ROW
    EXECUTE FUNCTION update_music_search_vector();

--
-- Name: protect_agent_aliases_delete; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_aliases_delete
    BEFORE DELETE ON agent_aliases
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_deletes();

--
-- Name: protect_agent_aliases_insert; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_aliases_insert
    BEFORE INSERT ON agent_aliases
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agent_aliases_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_aliases_update
    BEFORE UPDATE ON agent_aliases
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agent_domains_delete; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_domains_delete
    BEFORE DELETE ON agent_domains
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_deletes();

--
-- Name: protect_agent_domains_insert; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_domains_insert
    BEFORE INSERT ON agent_domains
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agent_domains_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_domains_update
    BEFORE UPDATE ON agent_domains
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agent_mods_delete; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_mods_delete
    BEFORE DELETE ON agent_modifications
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_deletes();

--
-- Name: protect_agent_mods_insert; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_mods_insert
    BEFORE INSERT ON agent_modifications
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agent_mods_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_mods_update
    BEFORE UPDATE ON agent_modifications
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agent_spawns_delete; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_spawns_delete
    BEFORE DELETE ON agent_spawns
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_deletes();

--
-- Name: protect_agent_spawns_insert; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_spawns_insert
    BEFORE INSERT ON agent_spawns
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agent_spawns_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agent_spawns_update
    BEFORE UPDATE ON agent_spawns
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agents_delete; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agents_delete
    BEFORE DELETE ON agents
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_deletes();

--
-- Name: protect_agents_insert; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agents_insert
    BEFORE INSERT ON agents
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_agents_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_agents_update
    BEFORE UPDATE ON agents
    FOR EACH ROW
    EXECUTE FUNCTION protect_agent_writes();

--
-- Name: protect_bootstrap_context; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_bootstrap_context
    BEFORE INSERT OR UPDATE OR DELETE ON agent_bootstrap_context
    FOR EACH ROW
    EXECUTE FUNCTION protect_bootstrap_context_writes_v2();

--
-- Name: protect_library_authors; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_library_authors
    BEFORE INSERT OR UPDATE OR DELETE ON library_authors
    FOR EACH ROW
    EXECUTE FUNCTION protect_library_writes();

--
-- Name: protect_library_tags; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_library_tags
    BEFORE INSERT OR UPDATE OR DELETE ON library_tags
    FOR EACH ROW
    EXECUTE FUNCTION protect_library_writes();

--
-- Name: protect_library_work_authors; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_library_work_authors
    BEFORE INSERT OR UPDATE OR DELETE ON library_work_authors
    FOR EACH ROW
    EXECUTE FUNCTION protect_library_writes();

--
-- Name: protect_library_work_relationships; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_library_work_relationships
    BEFORE INSERT OR UPDATE OR DELETE ON library_work_relationships
    FOR EACH ROW
    EXECUTE FUNCTION protect_library_writes();

--
-- Name: protect_library_work_tags; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_library_work_tags
    BEFORE INSERT OR UPDATE OR DELETE ON library_work_tags
    FOR EACH ROW
    EXECUTE FUNCTION protect_library_writes();

--
-- Name: protect_library_works; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_library_works
    BEFORE INSERT OR UPDATE OR DELETE ON library_works
    FOR EACH ROW
    EXECUTE FUNCTION protect_library_writes();

--
-- Name: protect_peer_models; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_peer_models
    BEFORE UPDATE ON agents
    FOR EACH ROW
    EXECUTE FUNCTION protect_peer_agent_model_changes();

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
    EXECUTE FUNCTION protect_turn_context_writes();

--
-- Name: publication_status_update; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER publication_status_update
    AFTER INSERT ON publications
    FOR EACH ROW
    EXECUTE FUNCTION update_work_status_on_publication();

--
-- Name: system_config_changed; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER system_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agent_system_config
    FOR EACH ROW
    EXECUTE FUNCTION notify_system_config_changed();

--
-- Name: trg_agent_turn_context_updated_at; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_agent_turn_context_updated_at
    BEFORE UPDATE ON agent_turn_context
    FOR EACH ROW
    EXECUTE FUNCTION update_agent_turn_context_timestamp();

--
-- Name: trg_income_sources_updated_at; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_income_sources_updated_at
    BEFORE UPDATE ON income_sources
    FOR EACH ROW
    EXECUTE FUNCTION update_income_sources_updated_at();

--
-- Name: trg_library_works_search; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_library_works_search
    BEFORE INSERT OR UPDATE ON library_works
    FOR EACH ROW
    EXECUTE FUNCTION library_works_search_trigger();

--
-- Name: trg_log_d100_roll; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_log_d100_roll
    AFTER UPDATE ON motivation_d100
    FOR EACH ROW
    EXECUTE FUNCTION _trg_log_d100_roll();

--
-- Name: trg_music_works_search; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_music_works_search
    BEFORE INSERT OR UPDATE ON music_works
    FOR EACH ROW
    EXECUTE FUNCTION music_works_search_update();

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
-- Name: trg_tasks_force_created_by; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_tasks_force_created_by
    BEFORE INSERT ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION tasks_force_created_by();

--
-- Name: trigger_user_insights_updated_at; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trigger_user_insights_updated_at
    BEFORE UPDATE ON user_insights
    FOR EACH ROW
    EXECUTE FUNCTION update_user_insights_updated_at();

--
-- Name: validate_parent_agents_trigger; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER validate_parent_agents_trigger
    BEFORE INSERT OR UPDATE ON agents
    FOR EACH ROW
    EXECUTE FUNCTION validate_parent_agents();

--
-- Name: workflow_step_change_trigger; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER workflow_step_change_trigger
    AFTER UPDATE ON workflow_steps
    FOR EACH ROW
    EXECUTE FUNCTION notify_workflow_step_change();

--
-- Name: workflow_steps_delegation_notify; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER workflow_steps_delegation_notify
    AFTER INSERT OR UPDATE OR DELETE ON workflow_steps
    FOR EACH ROW
    EXECUTE FUNCTION notify_delegation_change();

--
-- Name: workflows_delegation_notify; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER workflows_delegation_notify
    AFTER INSERT OR UPDATE OR DELETE ON workflows
    FOR EACH ROW
    EXECUTE FUNCTION notify_delegation_change();

--
-- Name: works_calculate_counts; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER works_calculate_counts
    BEFORE INSERT OR UPDATE ON works
    FOR EACH ROW
    EXECUTE FUNCTION calculate_word_count();

--
-- Name: works_updated_at; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER works_updated_at
    BEFORE UPDATE ON works
    FOR EACH ROW
    EXECUTE FUNCTION update_works_timestamp();

--
-- Name: delegation_knowledge; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW delegation_knowledge AS
 SELECT id,
    key,
    value,
    confidence,
    durability,
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
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_actions FROM newhart;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_actions FROM newhart;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM athena;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM coder;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM erato;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM gem;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM gidget;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM iris;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_aliases FROM newhart;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_aliases FROM newhart;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM nova;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM scout;

--
-- Name: agent_aliases; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_aliases FROM ticker;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM athena;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM coder;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM erato;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM gem;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM gidget;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM iris;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_bootstrap_context FROM newhart;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_bootstrap_context FROM newhart;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM nova;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM scout;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_bootstrap_context FROM ticker;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM athena;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM coder;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM erato;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM gem;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM gidget;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM iris;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_domains FROM newhart;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_domains FROM newhart;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM nova;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM scout;

--
-- Name: agent_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_domains FROM ticker;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_jobs FROM newhart;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_jobs FROM newhart;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM athena;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM coder;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM erato;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM gem;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM gidget;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM iris;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_modifications FROM newhart;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_modifications FROM newhart;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM nova;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM scout;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE agent_modifications FROM ticker;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_spawns FROM newhart;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_spawns FROM newhart;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM athena;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM coder;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM erato;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM gem;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM gidget;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM iris;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_system_config FROM newhart;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_system_config FROM newhart;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM nova;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM scout;

--
-- Name: agent_system_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agent_system_config FROM ticker;

--
-- Name: agent_turn_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agent_turn_context FROM newhart;

--
-- Name: agent_turn_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agent_turn_context FROM newhart;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM athena;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM coder;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM erato;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM gem;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM gidget;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM iris;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM newhart;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE agents FROM newhart;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM nova;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM scout;

--
-- Name: agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM ticker;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM athena;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM coder;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM erato;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM gem;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM gidget;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM iris;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE ai_models FROM newhart;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE ai_models FROM newhart;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM nova;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM scout;

--
-- Name: ai_models; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE ai_models FROM ticker;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE artwork FROM iris;

--
-- Name: artwork; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE artwork FROM iris;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM argus;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM athena;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM coder;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM conductor;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM erato;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM flint;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM gem;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM gidget;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM hermes;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM iris;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM marcie;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM newhart;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE blockers FROM nova;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM quill;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM scout;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM scribe;

--
-- Name: blockers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE blockers FROM ticker;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM athena;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM coder;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM erato;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM gem;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM gidget;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM iris;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE bootstrap_context_config FROM newhart;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE bootstrap_context_config FROM newhart;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM nova;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM scout;

--
-- Name: bootstrap_context_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE bootstrap_context_config FROM ticker;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE certificates FROM nova;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE channel_activity FROM nova;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM argus;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM athena;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM coder;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM conductor;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM erato;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM flint;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM gem;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM gidget;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM hermes;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM iris;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM marcie;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM newhart;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE channel_sessions FROM nova;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM quill;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM scout;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM scribe;

--
-- Name: channel_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_sessions FROM ticker;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM argus;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM athena;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM coder;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM conductor;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM erato;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM flint;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM gem;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM gidget;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM hermes;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM iris;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM marcie;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM newhart;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE channel_transcripts FROM nova;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM quill;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM scout;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM scribe;

--
-- Name: channel_transcripts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE channel_transcripts FROM ticker;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM argus;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM athena;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM coder;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM conductor;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM erato;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM flint;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM gem;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM gidget;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE comms_checks FROM hermes;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM iris;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM marcie;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM newhart;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE comms_checks FROM nova;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM quill;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM scout;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM scribe;

--
-- Name: comms_checks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_checks FROM ticker;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM argus;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM athena;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM coder;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM conductor;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM erato;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM flint;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM gem;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM gidget;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE comms_digests FROM hermes;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM iris;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM marcie;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM newhart;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE comms_digests FROM nova;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM quill;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM scout;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM scribe;

--
-- Name: comms_digests; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_digests FROM ticker;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM argus;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM athena;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM coder;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM conductor;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM erato;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM flint;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM gem;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM gidget;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE ON TABLE comms_state FROM hermes;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM iris;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM marcie;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM newhart;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE comms_state FROM nova;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM quill;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM scout;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM scribe;

--
-- Name: comms_state; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE comms_state FROM ticker;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM argus;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM athena;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM coder;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM conductor;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM erato;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM flint;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM gem;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM gidget;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM hermes;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM iris;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM marcie;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM newhart;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE d100_roll_log FROM nova;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM quill;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM scout;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM scribe;

--
-- Name: d100_roll_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE d100_roll_log FROM ticker;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE entities FROM nova;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE entity_fact_conflicts FROM nova;

--
-- Name: entity_fact_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE entity_fact_sources FROM nova;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE entity_facts FROM nova;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE entity_facts_archive FROM nova;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE entity_relationships FROM nova;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE event_entities FROM nova;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE event_places FROM nova;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE event_projects FROM nova;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE events FROM nova;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE events_archive FROM nova;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE extraction_metrics FROM nova;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE fact_change_log FROM nova;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE gambling_entries FROM nova;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE gambling_logs FROM nova;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE git_issue_queue FROM coder;

--
-- Name: git_issue_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE git_issue_queue FROM coder;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM argus;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM athena;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM coder;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM conductor;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM erato;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM flint;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM gem;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM gidget;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM hermes;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM iris;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM marcie;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM newhart;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE income_sources FROM nova;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM quill;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM scout;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM scribe;

--
-- Name: income_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_sources FROM ticker;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM argus;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM athena;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM coder;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM conductor;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM erato;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM flint;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM gem;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM gidget;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM hermes;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM iris;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM marcie;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM newhart;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE income_transactions FROM nova;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM quill;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM scout;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM scribe;

--
-- Name: income_transactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE income_transactions FROM ticker;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE job_messages FROM nova;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM argus;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM athena;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM coder;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM conductor;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM erato;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM flint;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM gem;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM gidget;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM hermes;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM iris;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM marcie;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, UPDATE ON TABLE journal_entries FROM newhart;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE journal_entries FROM nova;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM quill;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM scout;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM scribe;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE journal_entries FROM ticker;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE lessons FROM nova;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE lessons_archive FROM nova;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE library_authors FROM athena;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE library_authors FROM athena;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM coder;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM erato;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM gem;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM gidget;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM iris;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM newhart;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM nova;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM scout;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_authors FROM ticker;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE library_tags FROM athena;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE library_tags FROM athena;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM coder;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM erato;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM gem;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM gidget;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM iris;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM newhart;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM nova;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM scout;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_tags FROM ticker;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE library_work_authors FROM athena;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE library_work_authors FROM athena;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM coder;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM erato;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM gem;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM gidget;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM iris;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM newhart;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM nova;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM scout;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_authors FROM ticker;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE library_work_relationships FROM athena;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE library_work_relationships FROM athena;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM coder;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM erato;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM gem;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM gidget;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM iris;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM newhart;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM nova;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM scout;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_relationships FROM ticker;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE library_work_tags FROM athena;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE library_work_tags FROM athena;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM coder;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM erato;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM gem;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM gidget;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM iris;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM newhart;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM nova;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM scout;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_work_tags FROM ticker;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE library_works FROM athena;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE library_works FROM athena;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM coder;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM erato;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM gem;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM gidget;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM iris;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM newhart;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM nova;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM scout;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE library_works FROM ticker;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE media_consumed FROM nova;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE media_queue FROM nova;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE media_tags FROM nova;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE memory_embeddings FROM nova;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE memory_embeddings_archive FROM nova;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE memory_type_priorities FROM nova;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE motivation_d100 FROM nova;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_analysis FROM iris;

--
-- Name: music_analysis; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_analysis FROM iris;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_library FROM iris;

--
-- Name: music_library; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_library FROM iris;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM argus;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM argus;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM athena;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM athena;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM coder;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM coder;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM conductor;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM conductor;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM erato;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM erato;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM flint;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM flint;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM gem;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM gem;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM gidget;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM gidget;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM graybeard;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM hermes;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM hermes;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM iris;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM iris;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM marcie;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM marcie;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM newhart;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM newhart;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM "nova-staging";

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM openproject_user;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM quill;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM quill;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM scout;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM scout;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM scribe;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM scribe;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE music_works FROM ticker;

--
-- Name: music_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE music_works FROM ticker;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE place_properties FROM nova;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE places FROM nova;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE preferences FROM nova;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM argus;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM athena;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM coder;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM conductor;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM erato;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM flint;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM gem;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM gidget;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM hermes;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM iris;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM marcie;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM newhart;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE proactive_outreach FROM nova;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM quill;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM scout;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM scribe;

--
-- Name: proactive_outreach; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE proactive_outreach FROM ticker;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE project_entities FROM nova;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE project_tasks FROM nova;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE projects FROM nova;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM argus;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM athena;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM coder;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM conductor;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM erato;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM flint;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM gem;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM gidget;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM hermes;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM iris;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM marcie;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM newhart;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE prompt_helper_config FROM nova;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM quill;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM scout;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM scribe;

--
-- Name: prompt_helper_config; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE prompt_helper_config FROM ticker;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE publications FROM nova;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE ralph_sessions FROM nova;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM athena;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM coder;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM erato;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM gem;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM gidget;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM iris;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM newhart;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM nova;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE research_citations FROM scout;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_citations FROM scout;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_citations FROM ticker;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM athena;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM coder;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM erato;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM gem;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM gidget;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM iris;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM newhart;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM nova;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_conclusions FROM scout;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE research_conclusions FROM scout;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_conclusions FROM ticker;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM athena;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM coder;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM erato;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM gem;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM gidget;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM iris;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM newhart;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM nova;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_findings FROM scout;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE research_findings FROM scout;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_findings FROM ticker;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM athena;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM coder;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM erato;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM gem;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM gidget;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM iris;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM newhart;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM nova;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_projects FROM scout;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE research_projects FROM scout;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_projects FROM ticker;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM athena;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM coder;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM erato;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM gem;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM gidget;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM iris;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM newhart;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM nova;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE research_provenance FROM scout;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_provenance FROM scout;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_provenance FROM ticker;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM athena;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM coder;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM erato;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM gem;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM gidget;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM iris;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM newhart;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM nova;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_taggings FROM scout;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE research_taggings FROM scout;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_taggings FROM ticker;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM athena;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM coder;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM erato;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM gem;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM gidget;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM iris;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM newhart;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM nova;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE research_tags FROM scout;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_tags FROM scout;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tags FROM ticker;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM athena;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM coder;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM erato;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM gem;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM gidget;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM iris;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM newhart;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM nova;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE research_tasks FROM scout;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE research_tasks FROM scout;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE research_tasks FROM ticker;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM argus;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM athena;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM coder;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM conductor;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM erato;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM flint;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM gem;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM gidget;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM hermes;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM iris;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM marcie;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM newhart;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE self_awareness_triggers FROM nova;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM quill;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM scout;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM scribe;

--
-- Name: self_awareness_triggers; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE self_awareness_triggers FROM ticker;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE shopping_history FROM nova;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE shopping_history FROM "nova-staging";

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE shopping_preferences FROM nova;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE shopping_preferences FROM "nova-staging";

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE shopping_wishlist FROM nova;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE SELECT ON TABLE shopping_wishlist FROM "nova-staging";

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE skills FROM nova;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM argus;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM athena;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM coder;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM conductor;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM erato;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM flint;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM gem;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM gidget;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM hermes;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM iris;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM marcie;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM newhart;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE social_interactions FROM nova;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM quill;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM scout;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM scribe;

--
-- Name: social_interactions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE social_interactions FROM ticker;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE tags FROM nova;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE tasks FROM nova;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE tools FROM nova;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE unsolved_problems FROM nova;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM argus;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM athena;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM coder;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM conductor;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM erato;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM flint;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM gem;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM gidget;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM hermes;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM iris;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM marcie;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM newhart;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE user_domains FROM nova;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM quill;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM scout;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM scribe;

--
-- Name: user_domains; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_domains FROM ticker;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM argus;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM athena;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM coder;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM conductor;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM erato;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM flint;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM gem;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM gidget;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM hermes;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM iris;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM marcie;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM newhart;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE user_insights FROM nova;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM quill;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM scout;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM scribe;

--
-- Name: user_insights; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE user_insights FROM ticker;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE vehicles FROM nova;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE vocabulary FROM nova;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE work_tags FROM nova;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM argus;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM athena;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM coder;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM conductor;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM erato;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM flint;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM gem;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT ON TABLE workflow_runs FROM gidget;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM hermes;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM iris;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM marcie;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM newhart;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_runs FROM nova;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM quill;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM scout;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM scribe;

--
-- Name: workflow_runs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, UPDATE ON TABLE workflow_runs FROM ticker;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps FROM nova;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE workflows FROM nova;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE works FROM nova;

--
-- Name: complete_d100(p_roll integer); Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT EXECUTE ON FUNCTION complete_d100(p_roll integer) TO nova;

--
-- Name: current_agent_id(); Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT EXECUTE ON FUNCTION current_agent_id() TO graybeard;

--
-- Name: current_agent_id(); Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT EXECUTE ON FUNCTION current_agent_id() TO newhart;

--
-- Name: roll_d100(); Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT EXECUTE ON FUNCTION roll_d100() TO nova;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO argus;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_actions_id_seq TO athena;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO coder;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO conductor;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO erato;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO flint;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO gem;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO gidget;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO graybeard;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO hermes;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO iris;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO marcie;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO nova;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO quill;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_actions_id_seq TO scout;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO scribe;

--
-- Name: agent_actions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_actions_id_seq TO ticker;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO argus;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO athena;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO coder;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO conductor;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO erato;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO flint;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO gem;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO gidget;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO hermes;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO iris;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO marcie;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO nova;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO quill;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO scout;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO scribe;

--
-- Name: agent_bootstrap_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_bootstrap_context_id_seq TO ticker;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO argus;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_domains_id_seq TO athena;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO coder;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO conductor;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO erato;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO flint;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO gem;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO gidget;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO hermes;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO iris;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO marcie;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO nova;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO quill;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_domains_id_seq TO scout;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO scribe;

--
-- Name: agent_domains_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_domains_id_seq TO ticker;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO argus;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_jobs_id_seq TO athena;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO coder;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO conductor;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO erato;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO flint;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO gem;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO gidget;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO graybeard;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO hermes;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO iris;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO marcie;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO nova;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO quill;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_jobs_id_seq TO scout;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO scribe;

--
-- Name: agent_jobs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_jobs_id_seq TO ticker;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO argus;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_modifications_id_seq TO athena;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO coder;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO conductor;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO erato;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO flint;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO gem;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO gidget;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO hermes;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO iris;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO marcie;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO nova;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO quill;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_modifications_id_seq TO scout;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO scribe;

--
-- Name: agent_modifications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_modifications_id_seq TO ticker;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO argus;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_spawns_id_seq TO athena;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO coder;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO conductor;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO erato;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO flint;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO gem;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO gidget;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO graybeard;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO hermes;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO iris;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO marcie;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO nova;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO quill;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_spawns_id_seq TO scout;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO scribe;

--
-- Name: agent_spawns_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_spawns_id_seq TO ticker;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO argus;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_turn_context_id_seq TO athena;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO coder;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO conductor;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO erato;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO flint;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO gem;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO gidget;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO graybeard;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO hermes;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO iris;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO marcie;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO nova;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO quill;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agent_turn_context_id_seq TO scout;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO scribe;

--
-- Name: agent_turn_context_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agent_turn_context_id_seq TO ticker;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO argus;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agents_id_seq TO athena;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO coder;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO conductor;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO erato;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO flint;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO gem;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO gidget;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO hermes;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO iris;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO marcie;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO nova;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO quill;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE agents_id_seq TO scout;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO scribe;

--
-- Name: agents_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE agents_id_seq TO ticker;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO argus;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE ai_models_id_seq TO athena;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO coder;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO conductor;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO erato;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO flint;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO gem;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO gidget;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO hermes;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO iris;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO marcie;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO nova;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO quill;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE ai_models_id_seq TO scout;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO scribe;

--
-- Name: ai_models_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ai_models_id_seq TO ticker;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO argus;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE artwork_id_seq TO athena;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO coder;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO conductor;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO erato;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO flint;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO gem;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO gidget;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO hermes;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO marcie;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO newhart;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE artwork_id_seq TO nova;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO quill;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE artwork_id_seq TO scout;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO scribe;

--
-- Name: artwork_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE artwork_id_seq TO ticker;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO argus;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE certificates_id_seq TO athena;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO coder;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO conductor;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO erato;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO flint;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO gem;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO gidget;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO graybeard;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO hermes;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO iris;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO marcie;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO newhart;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO quill;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE certificates_id_seq TO scout;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO scribe;

--
-- Name: certificates_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE certificates_id_seq TO ticker;

--
-- Name: channel_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_sessions_id_seq TO argus;

--
-- Name: channel_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_sessions_id_seq TO conductor;

--
-- Name: channel_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_sessions_id_seq TO flint;

--
-- Name: channel_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_sessions_id_seq TO hermes;

--
-- Name: channel_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_sessions_id_seq TO marcie;

--
-- Name: channel_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_sessions_id_seq TO newhart;

--
-- Name: channel_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_sessions_id_seq TO quill;

--
-- Name: channel_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_sessions_id_seq TO scribe;

--
-- Name: channel_transcripts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_transcripts_id_seq TO argus;

--
-- Name: channel_transcripts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_transcripts_id_seq TO conductor;

--
-- Name: channel_transcripts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_transcripts_id_seq TO flint;

--
-- Name: channel_transcripts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_transcripts_id_seq TO hermes;

--
-- Name: channel_transcripts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_transcripts_id_seq TO marcie;

--
-- Name: channel_transcripts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_transcripts_id_seq TO newhart;

--
-- Name: channel_transcripts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_transcripts_id_seq TO quill;

--
-- Name: channel_transcripts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE channel_transcripts_id_seq TO scribe;

--
-- Name: comms_checks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_checks_id_seq TO argus;

--
-- Name: comms_checks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_checks_id_seq TO conductor;

--
-- Name: comms_checks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_checks_id_seq TO flint;

--
-- Name: comms_checks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE comms_checks_id_seq TO hermes;

--
-- Name: comms_checks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_checks_id_seq TO marcie;

--
-- Name: comms_checks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_checks_id_seq TO newhart;

--
-- Name: comms_checks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_checks_id_seq TO quill;

--
-- Name: comms_checks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_checks_id_seq TO scribe;

--
-- Name: comms_digests_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_digests_id_seq TO argus;

--
-- Name: comms_digests_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_digests_id_seq TO conductor;

--
-- Name: comms_digests_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_digests_id_seq TO flint;

--
-- Name: comms_digests_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE comms_digests_id_seq TO hermes;

--
-- Name: comms_digests_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_digests_id_seq TO marcie;

--
-- Name: comms_digests_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_digests_id_seq TO newhart;

--
-- Name: comms_digests_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_digests_id_seq TO quill;

--
-- Name: comms_digests_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE comms_digests_id_seq TO scribe;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO argus;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entities_id_seq TO athena;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO coder;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO conductor;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO erato;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO flint;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO gem;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO gidget;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO graybeard;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO hermes;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO iris;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO marcie;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO newhart;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO quill;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entities_id_seq TO scout;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO scribe;

--
-- Name: entities_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entities_id_seq TO ticker;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO argus;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO athena;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO coder;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO conductor;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO erato;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO flint;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO gem;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO gidget;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO graybeard;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO hermes;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO iris;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO marcie;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO newhart;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO quill;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO scout;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO scribe;

--
-- Name: entity_fact_conflicts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_fact_conflicts_id_seq TO ticker;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO argus;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO athena;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO coder;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO conductor;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO erato;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO flint;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO gem;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO gidget;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO graybeard;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO hermes;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO iris;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO marcie;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO newhart;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO "nova-staging";

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO openproject_user;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO quill;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO scout;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO scribe;

--
-- Name: entity_fact_sources_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_fact_sources_id_seq TO ticker;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO argus;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_facts_id_seq TO athena;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO coder;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO conductor;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO erato;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO flint;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO gem;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO gidget;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_facts_id_seq TO graybeard;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO hermes;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO iris;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO marcie;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_facts_id_seq TO newhart;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO quill;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_facts_id_seq TO scout;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO scribe;

--
-- Name: entity_facts_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_facts_id_seq TO ticker;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO argus;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_relationships_id_seq TO athena;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO coder;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO conductor;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO erato;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO flint;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO gem;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO gidget;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO graybeard;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO hermes;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO iris;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO marcie;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO newhart;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO quill;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE entity_relationships_id_seq TO scout;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO scribe;

--
-- Name: entity_relationships_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE entity_relationships_id_seq TO ticker;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO argus;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE events_archive_id_seq TO athena;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO coder;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO conductor;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO erato;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO flint;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO gem;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO gidget;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO graybeard;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO hermes;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO iris;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO marcie;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO newhart;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO quill;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE events_archive_id_seq TO scout;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO scribe;

--
-- Name: events_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_archive_id_seq TO ticker;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO argus;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE events_id_seq TO athena;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO coder;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO conductor;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO erato;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO flint;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO gem;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO gidget;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO graybeard;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO hermes;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO iris;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO marcie;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO newhart;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO quill;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE events_id_seq TO scout;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO scribe;

--
-- Name: events_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE events_id_seq TO ticker;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO argus;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE extraction_metrics_id_seq TO athena;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO coder;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO conductor;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO erato;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO flint;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO gem;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO gidget;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO graybeard;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO hermes;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO iris;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO marcie;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO newhart;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO quill;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE extraction_metrics_id_seq TO scout;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO scribe;

--
-- Name: extraction_metrics_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE extraction_metrics_id_seq TO ticker;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO argus;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE fact_change_log_id_seq TO athena;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO coder;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO conductor;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO erato;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO flint;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO gem;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO gidget;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO graybeard;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO hermes;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO iris;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO marcie;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO newhart;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO quill;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE fact_change_log_id_seq TO scout;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO scribe;

--
-- Name: fact_change_log_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE fact_change_log_id_seq TO ticker;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO argus;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE gambling_entries_id_seq TO athena;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO coder;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO conductor;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO erato;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO flint;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO gem;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO gidget;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO graybeard;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO hermes;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO iris;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO marcie;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO newhart;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO quill;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE gambling_entries_id_seq TO scout;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO scribe;

--
-- Name: gambling_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_entries_id_seq TO ticker;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO argus;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE gambling_logs_id_seq TO athena;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO coder;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO conductor;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO erato;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO flint;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO gem;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO gidget;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO graybeard;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO hermes;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO iris;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO marcie;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO newhart;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO quill;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE gambling_logs_id_seq TO scout;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO scribe;

--
-- Name: gambling_logs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE gambling_logs_id_seq TO ticker;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO argus;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE git_issue_queue_id_seq TO athena;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO conductor;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO erato;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO flint;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO gem;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO gidget;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO hermes;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO iris;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO marcie;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO newhart;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO nova;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO quill;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE git_issue_queue_id_seq TO scout;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO scribe;

--
-- Name: git_issue_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE git_issue_queue_id_seq TO ticker;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO argus;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE job_messages_id_seq TO athena;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO coder;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO conductor;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO erato;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO flint;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO gem;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO gidget;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO graybeard;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO hermes;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO iris;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO marcie;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO newhart;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO quill;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE job_messages_id_seq TO scout;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO scribe;

--
-- Name: job_messages_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE job_messages_id_seq TO ticker;

--
-- Name: journal_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE journal_entries_id_seq TO graybeard;

--
-- Name: journal_entries_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE journal_entries_id_seq TO newhart;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO argus;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE lessons_archive_id_seq TO athena;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO coder;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO conductor;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO erato;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO flint;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO gem;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO gidget;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO graybeard;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO hermes;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO iris;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO marcie;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO newhart;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO quill;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE lessons_archive_id_seq TO scout;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO scribe;

--
-- Name: lessons_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_archive_id_seq TO ticker;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO argus;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE lessons_id_seq TO athena;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO coder;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO conductor;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO erato;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO flint;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO gem;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO gidget;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO graybeard;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO hermes;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO iris;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO marcie;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO newhart;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO quill;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE lessons_id_seq TO scout;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO scribe;

--
-- Name: lessons_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE lessons_id_seq TO ticker;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO argus;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO coder;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO conductor;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO erato;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO flint;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO gem;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO gidget;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO hermes;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO iris;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO marcie;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO newhart;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO nova;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO quill;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_authors_id_seq TO scout;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO scribe;

--
-- Name: library_authors_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_authors_id_seq TO ticker;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO argus;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO coder;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO conductor;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO erato;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO flint;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO gem;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO gidget;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO hermes;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO iris;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO marcie;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO newhart;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO nova;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO quill;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_tags_id_seq TO scout;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO scribe;

--
-- Name: library_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_tags_id_seq TO ticker;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO argus;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO coder;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO conductor;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO erato;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO flint;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO gem;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO gidget;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO hermes;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO iris;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO marcie;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO newhart;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO nova;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO quill;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE library_works_id_seq TO scout;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO scribe;

--
-- Name: library_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE library_works_id_seq TO ticker;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO argus;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_consumed_id_seq TO athena;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO coder;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO conductor;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO erato;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO flint;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO gem;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO gidget;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO graybeard;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO hermes;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO iris;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO marcie;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO newhart;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO quill;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_consumed_id_seq TO scout;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO scribe;

--
-- Name: media_consumed_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_consumed_id_seq TO ticker;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO argus;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_queue_id_seq TO athena;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO coder;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO conductor;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO erato;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO flint;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO gem;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO gidget;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO graybeard;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO hermes;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO iris;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO marcie;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO newhart;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO quill;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_queue_id_seq TO scout;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO scribe;

--
-- Name: media_queue_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_queue_id_seq TO ticker;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO argus;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_tags_id_seq TO athena;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO coder;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO conductor;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO erato;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO flint;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO gem;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO gidget;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO graybeard;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO hermes;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO iris;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO marcie;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO newhart;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO quill;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE media_tags_id_seq TO scout;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO scribe;

--
-- Name: media_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE media_tags_id_seq TO ticker;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO argus;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO athena;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO coder;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO conductor;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO erato;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO flint;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO gem;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO gidget;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO graybeard;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO hermes;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO iris;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO marcie;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO newhart;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO quill;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO scout;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO scribe;

--
-- Name: memory_embeddings_archive_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_archive_id_seq TO ticker;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO argus;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE memory_embeddings_id_seq TO athena;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO coder;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO conductor;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO erato;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO flint;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO gem;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO gidget;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO graybeard;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO hermes;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO iris;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO marcie;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO newhart;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO quill;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE memory_embeddings_id_seq TO scout;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO scribe;

--
-- Name: memory_embeddings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE memory_embeddings_id_seq TO ticker;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO argus;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_analysis_id_seq TO athena;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO coder;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO conductor;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO erato;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO flint;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO gem;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO gidget;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO hermes;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO marcie;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO newhart;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO nova;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO quill;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_analysis_id_seq TO scout;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO scribe;

--
-- Name: music_analysis_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_analysis_id_seq TO ticker;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO argus;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_library_id_seq TO athena;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO coder;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO conductor;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO erato;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO flint;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO gem;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO gidget;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO hermes;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO marcie;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO newhart;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO nova;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO quill;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_library_id_seq TO scout;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO scribe;

--
-- Name: music_library_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE music_library_id_seq TO ticker;

--
-- Name: music_works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE music_works_id_seq TO nova;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO argus;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE place_properties_id_seq TO athena;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO coder;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO conductor;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO erato;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO flint;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO gem;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO gidget;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO graybeard;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO hermes;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO iris;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO marcie;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO newhart;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO quill;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE place_properties_id_seq TO scout;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO scribe;

--
-- Name: place_properties_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE place_properties_id_seq TO ticker;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO argus;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE places_id_seq TO athena;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO coder;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO conductor;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO erato;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO flint;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO gem;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO gidget;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO graybeard;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO hermes;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO iris;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO marcie;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO newhart;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO quill;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE places_id_seq TO scout;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO scribe;

--
-- Name: places_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE places_id_seq TO ticker;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO argus;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE preferences_id_seq TO athena;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO coder;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO conductor;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO erato;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO flint;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO gem;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO gidget;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO graybeard;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO hermes;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO iris;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO marcie;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO newhart;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO quill;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE preferences_id_seq TO scout;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO scribe;

--
-- Name: preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE preferences_id_seq TO ticker;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO argus;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE project_tasks_id_seq TO athena;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO coder;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO conductor;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO erato;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO flint;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO gem;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO gidget;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO graybeard;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO hermes;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO iris;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO marcie;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO newhart;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO quill;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE project_tasks_id_seq TO scout;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO scribe;

--
-- Name: project_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE project_tasks_id_seq TO ticker;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO argus;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE projects_id_seq TO athena;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO coder;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO conductor;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO erato;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO flint;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO gem;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO gidget;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO graybeard;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO hermes;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO iris;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO marcie;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO newhart;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO quill;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE projects_id_seq TO scout;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO scribe;

--
-- Name: projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE projects_id_seq TO ticker;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO argus;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE publications_id_seq TO athena;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO coder;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO conductor;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO erato;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO flint;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO gem;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO gidget;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO graybeard;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO hermes;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO iris;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO marcie;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO newhart;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO quill;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE publications_id_seq TO scout;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO scribe;

--
-- Name: publications_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE publications_id_seq TO ticker;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO argus;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE ralph_sessions_id_seq TO athena;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO coder;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO conductor;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO erato;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO flint;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO gem;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO gidget;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO graybeard;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO hermes;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO iris;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO marcie;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO newhart;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO quill;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE ralph_sessions_id_seq TO scout;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO scribe;

--
-- Name: ralph_sessions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE ralph_sessions_id_seq TO ticker;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO argus;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_citations_id_seq TO athena;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO coder;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO conductor;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO erato;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO flint;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO gem;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO gidget;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO hermes;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO iris;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO marcie;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO newhart;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO nova;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO quill;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO scribe;

--
-- Name: research_citations_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_citations_id_seq TO ticker;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO argus;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_conclusions_id_seq TO athena;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO coder;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO conductor;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO erato;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO flint;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO gem;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO gidget;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO hermes;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO iris;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO marcie;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO newhart;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO nova;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO quill;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO scribe;

--
-- Name: research_conclusions_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_conclusions_id_seq TO ticker;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO argus;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_findings_id_seq TO athena;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO coder;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO conductor;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO erato;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO flint;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO gem;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO gidget;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO hermes;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO iris;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO marcie;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO newhart;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO nova;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO quill;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO scribe;

--
-- Name: research_findings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_findings_id_seq TO ticker;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO argus;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_projects_id_seq TO athena;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO coder;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO conductor;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO erato;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO flint;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO gem;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO gidget;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO hermes;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO iris;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO marcie;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO newhart;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO nova;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO quill;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO scribe;

--
-- Name: research_projects_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_projects_id_seq TO ticker;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO argus;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_provenance_id_seq TO athena;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO coder;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO conductor;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO erato;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO flint;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO gem;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO gidget;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO hermes;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO iris;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO marcie;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO newhart;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO nova;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO quill;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO scribe;

--
-- Name: research_provenance_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_provenance_id_seq TO ticker;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO argus;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_taggings_id_seq TO athena;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO coder;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO conductor;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO erato;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO flint;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO gem;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO gidget;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO hermes;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO iris;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO marcie;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO newhart;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO nova;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO quill;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO scribe;

--
-- Name: research_taggings_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_taggings_id_seq TO ticker;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO argus;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_tags_id_seq TO athena;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO coder;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO conductor;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO erato;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO flint;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO gem;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO gidget;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO hermes;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO iris;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO marcie;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO newhart;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO nova;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO quill;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO scribe;

--
-- Name: research_tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tags_id_seq TO ticker;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO argus;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE research_tasks_id_seq TO athena;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO coder;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO conductor;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO erato;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO flint;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO gem;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO gidget;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO hermes;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO iris;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO marcie;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO newhart;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO nova;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO quill;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO scribe;

--
-- Name: research_tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE research_tasks_id_seq TO ticker;

--
-- Name: self_awareness_triggers_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE self_awareness_triggers_id_seq TO newhart;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO argus;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_history_id_seq TO athena;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO coder;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO conductor;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO erato;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO flint;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO gem;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO gidget;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO graybeard;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO hermes;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO iris;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO marcie;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO newhart;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO quill;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_history_id_seq TO scout;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO scribe;

--
-- Name: shopping_history_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_history_id_seq TO ticker;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO argus;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_preferences_id_seq TO athena;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO coder;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO conductor;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO erato;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO flint;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO gem;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO gidget;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO graybeard;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO hermes;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO iris;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO marcie;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO newhart;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO quill;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_preferences_id_seq TO scout;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO scribe;

--
-- Name: shopping_preferences_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_preferences_id_seq TO ticker;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO argus;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_wishlist_id_seq TO athena;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO coder;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO conductor;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO erato;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO flint;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO gem;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO gidget;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO graybeard;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO hermes;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO iris;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO marcie;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO newhart;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO quill;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE shopping_wishlist_id_seq TO scout;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO scribe;

--
-- Name: shopping_wishlist_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE shopping_wishlist_id_seq TO ticker;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO argus;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE skills_id_seq TO athena;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO coder;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO conductor;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO erato;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO flint;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO gem;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO gidget;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO graybeard;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO hermes;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO iris;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO marcie;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO newhart;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO quill;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE skills_id_seq TO scout;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO scribe;

--
-- Name: skills_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE skills_id_seq TO ticker;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO argus;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tags_id_seq TO athena;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO coder;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO conductor;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO erato;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO flint;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO gem;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO gidget;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO graybeard;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO hermes;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO iris;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO marcie;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO newhart;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO quill;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tags_id_seq TO scout;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO scribe;

--
-- Name: tags_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tags_id_seq TO ticker;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO argus;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tasks_id_seq TO athena;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO coder;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO conductor;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO erato;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO flint;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO gem;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO gidget;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO graybeard;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO hermes;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO iris;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO marcie;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO newhart;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO quill;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tasks_id_seq TO scout;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO scribe;

--
-- Name: tasks_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tasks_id_seq TO ticker;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO argus;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tools_id_seq TO athena;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO coder;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO conductor;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO erato;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO flint;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO gem;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO gidget;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO graybeard;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO hermes;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO iris;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO marcie;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO newhart;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO quill;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE tools_id_seq TO scout;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO scribe;

--
-- Name: tools_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE tools_id_seq TO ticker;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO argus;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE unsolved_problems_id_seq TO athena;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO coder;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO conductor;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO erato;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO flint;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO gem;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO gidget;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO graybeard;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO hermes;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO iris;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO marcie;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO newhart;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO quill;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE unsolved_problems_id_seq TO scout;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO scribe;

--
-- Name: unsolved_problems_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE unsolved_problems_id_seq TO ticker;

--
-- Name: user_insights_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE user_insights_id_seq TO newhart;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO argus;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE vehicles_id_seq TO athena;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO coder;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO conductor;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO erato;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO flint;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO gem;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO gidget;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO graybeard;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO hermes;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO iris;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO marcie;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO newhart;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO quill;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE vehicles_id_seq TO scout;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO scribe;

--
-- Name: vehicles_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vehicles_id_seq TO ticker;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO argus;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE vocabulary_id_seq TO athena;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO coder;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO conductor;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO erato;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO flint;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO gem;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO gidget;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO graybeard;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO hermes;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO iris;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO marcie;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO newhart;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO quill;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE vocabulary_id_seq TO scout;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO scribe;

--
-- Name: vocabulary_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE vocabulary_id_seq TO ticker;

--
-- Name: workflow_runs_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_runs_id_seq TO newhart;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO argus;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE workflow_steps_id_seq TO athena;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO coder;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO conductor;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO erato;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO flint;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO gem;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO gidget;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO graybeard;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO hermes;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO iris;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO marcie;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO newhart;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO quill;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE workflow_steps_id_seq TO scout;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO scribe;

--
-- Name: workflow_steps_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflow_steps_id_seq TO ticker;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO argus;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE workflows_id_seq TO athena;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO coder;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO conductor;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO erato;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO flint;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO gem;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO gidget;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO graybeard;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO hermes;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO iris;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO marcie;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO newhart;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO quill;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE workflows_id_seq TO scout;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO scribe;

--
-- Name: workflows_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE workflows_id_seq TO ticker;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO argus;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE works_id_seq TO athena;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO coder;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO conductor;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO erato;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO flint;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO gem;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO gidget;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO graybeard;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO hermes;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO iris;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO marcie;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO newhart;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO quill;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT, USAGE ON SEQUENCE works_id_seq TO scout;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO scribe;

--
-- Name: works_id_seq; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT USAGE ON SEQUENCE works_id_seq TO ticker;

--
-- Name: agent_actions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE agent_actions TO graybeard;

--
-- Name: agent_bootstrap_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT INSERT, SELECT, UPDATE ON TABLE agent_bootstrap_context TO graybeard;

--
-- Name: agent_jobs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE agent_jobs TO graybeard;

--
-- Name: agent_modifications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT INSERT, SELECT, UPDATE ON TABLE agent_modifications TO graybeard;

--
-- Name: agent_spawns; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE agent_spawns TO graybeard;

--
-- Name: agent_turn_context; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE agent_turn_context TO graybeard;

--
-- Name: certificates; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE certificates TO graybeard;

--
-- Name: channel_activity; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE channel_activity TO graybeard;

--
-- Name: entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE entities TO graybeard;

--
-- Name: entity_fact_conflicts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE entity_fact_conflicts TO graybeard;

--
-- Name: entity_fact_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE entity_fact_sources TO graybeard;

--
-- Name: entity_fact_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE entity_fact_sources TO "nova-staging";

--
-- Name: entity_fact_sources; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE entity_fact_sources TO openproject_user;

--
-- Name: entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE entity_facts TO graybeard;

--
-- Name: entity_facts_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE entity_facts_archive TO graybeard;

--
-- Name: entity_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE entity_relationships TO graybeard;

--
-- Name: event_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE event_entities TO graybeard;

--
-- Name: event_places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE event_places TO graybeard;

--
-- Name: event_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE event_projects TO graybeard;

--
-- Name: events; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE events TO graybeard;

--
-- Name: events_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE events_archive TO graybeard;

--
-- Name: extraction_metrics; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE extraction_metrics TO graybeard;

--
-- Name: fact_change_log; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE fact_change_log TO graybeard;

--
-- Name: gambling_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE gambling_entries TO graybeard;

--
-- Name: gambling_logs; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE gambling_logs TO graybeard;

--
-- Name: job_messages; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE job_messages TO graybeard;

--
-- Name: journal_entries; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT INSERT, SELECT ON TABLE journal_entries TO graybeard;

--
-- Name: lessons; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE lessons TO graybeard;

--
-- Name: lessons_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE lessons_archive TO graybeard;

--
-- Name: library_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_authors TO openproject;

--
-- Name: library_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_tags TO openproject;

--
-- Name: library_work_authors; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_authors TO openproject;

--
-- Name: library_work_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_relationships TO openproject;

--
-- Name: library_work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_work_tags TO openproject;

--
-- Name: library_works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE library_works TO openproject;

--
-- Name: media_consumed; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE media_consumed TO graybeard;

--
-- Name: media_queue; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE media_queue TO graybeard;

--
-- Name: media_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE media_tags TO graybeard;

--
-- Name: memory_embeddings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE memory_embeddings TO graybeard;

--
-- Name: memory_embeddings_archive; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE memory_embeddings_archive TO graybeard;

--
-- Name: memory_type_priorities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE memory_type_priorities TO graybeard;

--
-- Name: motivation_d100; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE motivation_d100 TO graybeard;

--
-- Name: place_properties; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE place_properties TO graybeard;

--
-- Name: places; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE places TO graybeard;

--
-- Name: preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE preferences TO graybeard;

--
-- Name: project_entities; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE project_entities TO graybeard;

--
-- Name: project_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE project_tasks TO graybeard;

--
-- Name: projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE projects TO graybeard;

--
-- Name: publications; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE publications TO graybeard;

--
-- Name: ralph_sessions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE ralph_sessions TO graybeard;

--
-- Name: research_citations; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_citations TO openproject;

--
-- Name: research_conclusions; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_conclusions TO openproject;

--
-- Name: research_findings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_findings TO openproject;

--
-- Name: research_projects; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_projects TO openproject;

--
-- Name: research_provenance; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_provenance TO openproject;

--
-- Name: research_taggings; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_taggings TO openproject;

--
-- Name: research_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_tags TO openproject;

--
-- Name: research_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE research_tasks TO openproject;

--
-- Name: shopping_history; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE shopping_history TO graybeard;

--
-- Name: shopping_preferences; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE shopping_preferences TO graybeard;

--
-- Name: shopping_wishlist; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE shopping_wishlist TO graybeard;

--
-- Name: skills; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE skills TO graybeard;

--
-- Name: tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE tags TO graybeard;

--
-- Name: tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE tasks TO graybeard;

--
-- Name: tools; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE tools TO graybeard;

--
-- Name: unsolved_problems; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE unsolved_problems TO graybeard;

--
-- Name: vehicles; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE vehicles TO graybeard;

--
-- Name: vocabulary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE vocabulary TO graybeard;

--
-- Name: work_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE work_tags TO graybeard;

--
-- Name: workflow_steps; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps TO graybeard;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflows TO graybeard;

--
-- Name: workflows; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, REFERENCES, SELECT, UPDATE ON TABLE workflows TO newhart;

--
-- Name: works; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE works TO graybeard;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO argus;

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

GRANT SELECT ON TABLE delegation_knowledge TO conductor;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO erato;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO flint;

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

GRANT SELECT ON TABLE delegation_knowledge TO hermes;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO iris;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO marcie;

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

GRANT SELECT ON TABLE delegation_knowledge TO quill;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO scout;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO scribe;

--
-- Name: delegation_knowledge; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE delegation_knowledge TO ticker;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO argus;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO athena;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO coder;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO conductor;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO erato;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO flint;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO gem;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO gidget;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agent_spawn_stats TO graybeard;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO hermes;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO iris;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO marcie;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO quill;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO scout;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO scribe;

--
-- Name: v_agent_spawn_stats; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agent_spawn_stats TO ticker;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO argus;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO athena;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO coder;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO conductor;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO erato;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO flint;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO gem;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO gidget;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_agents TO graybeard;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO hermes;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO iris;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO marcie;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO quill;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO scout;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO scribe;

--
-- Name: v_agents; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_agents TO ticker;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO argus;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO athena;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO coder;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO conductor;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO erato;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO flint;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO gem;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO gidget;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_entity_facts TO graybeard;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO hermes;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO iris;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO marcie;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO quill;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO scout;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO scribe;

--
-- Name: v_entity_facts; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_entity_facts TO ticker;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO argus;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO athena;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO coder;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO conductor;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO erato;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO flint;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO gem;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO gidget;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_event_timeline TO graybeard;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO hermes;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO iris;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO marcie;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO quill;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO scout;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO scribe;

--
-- Name: v_event_timeline; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_event_timeline TO ticker;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO argus;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO athena;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO coder;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO conductor;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO erato;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO flint;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO gem;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO gidget;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_gambling_summary TO graybeard;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO hermes;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO iris;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO marcie;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO quill;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO scout;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO scribe;

--
-- Name: v_gambling_summary; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_gambling_summary TO ticker;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO argus;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO athena;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO coder;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO conductor;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO erato;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO flint;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO gem;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO gidget;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_queue_pending TO graybeard;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO hermes;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO iris;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO marcie;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO quill;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO scout;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO scribe;

--
-- Name: v_media_queue_pending; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_queue_pending TO ticker;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO argus;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO athena;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO coder;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO conductor;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO erato;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO flint;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO gem;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO gidget;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_media_with_tags TO graybeard;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO hermes;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO iris;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO marcie;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO quill;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO scout;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO scribe;

--
-- Name: v_media_with_tags; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_media_with_tags TO ticker;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO argus;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO athena;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO coder;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO conductor;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO erato;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO flint;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO gem;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO gidget;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_metamours TO graybeard;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO hermes;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO iris;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO marcie;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO quill;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO scout;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO scribe;

--
-- Name: v_metamours; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_metamours TO ticker;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO argus;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO athena;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO coder;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO conductor;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO erato;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO flint;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO gem;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO gidget;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_tasks TO graybeard;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO hermes;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO iris;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO marcie;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO quill;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO scout;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO scribe;

--
-- Name: v_pending_tasks; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_tasks TO ticker;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO argus;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO athena;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO coder;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO conductor;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO erato;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO flint;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO gem;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO gidget;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_pending_test_failures TO graybeard;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO hermes;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO iris;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO marcie;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO quill;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO scout;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO scribe;

--
-- Name: v_pending_test_failures; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_pending_test_failures TO ticker;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO argus;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO athena;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO coder;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO conductor;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO erato;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO flint;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO gem;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO gidget;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_ralph_active TO graybeard;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO hermes;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO iris;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO marcie;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO quill;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO scout;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO scribe;

--
-- Name: v_ralph_active; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_ralph_active TO ticker;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO argus;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO athena;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO coder;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO conductor;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO erato;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO flint;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO gem;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO gidget;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_relationships TO graybeard;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO hermes;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO iris;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO marcie;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO quill;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO scout;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO scribe;

--
-- Name: v_relationships; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_relationships TO ticker;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO argus;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO athena;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO coder;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO conductor;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO erato;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO flint;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO gem;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO gidget;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_task_tree TO graybeard;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO hermes;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO iris;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO marcie;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO quill;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO scout;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO scribe;

--
-- Name: v_task_tree; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_task_tree TO ticker;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO argus;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO athena;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO coder;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO conductor;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO erato;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO flint;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO gem;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO gidget;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE v_users TO graybeard;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO hermes;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO iris;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO marcie;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO quill;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO scout;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO scribe;

--
-- Name: v_users; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE v_users TO ticker;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO argus;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO athena;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO coder;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO conductor;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO erato;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO flint;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO gem;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO gidget;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT SELECT ON TABLE workflow_steps_detail TO graybeard;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO hermes;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO iris;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO marcie;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO newhart;

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

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO quill;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO scout;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO scribe;

--
-- Name: workflow_steps_detail; Type: PRIVILEGE; Schema: privileges; Owner: -
--

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE workflow_steps_detail TO ticker;

--
-- Name: motivation_d100; Type: COLUMN_PRIVILEGE; Schema: column_privileges; Owner: -
--

GRANT UPDATE (difficulty, enabled, energy_required, estimated_minutes, notes, skill_name, task_description, task_name, tool_name, workflow_id) ON TABLE motivation_d100 TO nova;

