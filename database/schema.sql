--
-- pgschema database dump
--

-- Dumped from database version PostgreSQL 16.11
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
-- Name: agent_bootstrap_context; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_bootstrap_context (
    id SERIAL,
    context_type text NOT NULL,
    domain_name text,
    file_key text NOT NULL,
    content text NOT NULL,
    description text,
    updated_at timestamptz DEFAULT now(),
    updated_by text DEFAULT 'system',
    agent_name text,
    CONSTRAINT agent_bootstrap_context_pkey PRIMARY KEY (id),
    CONSTRAINT agent_bootstrap_context_context_type_check CHECK (context_type IN ('UNIVERSAL'::text, 'GLOBAL'::text, 'DOMAIN'::text, 'AGENT'::text)),
    CONSTRAINT chk_universal_global_no_names CHECK ((context_type <> ALL (ARRAY['UNIVERSAL'::text, 'GLOBAL'::text])) OR agent_name IS NULL AND domain_name IS NULL)
);


COMMENT ON TABLE agent_bootstrap_context IS 'Bootstrap context entries. READ-ONLY except Newhart (Agent Design/Management domain).';


COMMENT ON COLUMN agent_bootstrap_context.context_type IS 'GLOBAL (all agents) or DOMAIN (agents in specific domain)';


COMMENT ON COLUMN agent_bootstrap_context.domain_name IS 'NULL for GLOBAL, domain name from agent_domains for DOMAIN type';


COMMENT ON COLUMN agent_bootstrap_context.file_key IS 'Identifier for context block, becomes filename in bootstrap';

--
-- Name: agent_bootstrap_context_unique_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS agent_bootstrap_context_unique_idx ON agent_bootstrap_context (context_type, COALESCE(agent_name, ''::text), COALESCE(domain_name, ''::text), file_key);

--
-- Name: idx_abc_agent_name; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_abc_agent_name ON agent_bootstrap_context (agent_name) WHERE (agent_name IS NOT NULL);

--
-- Name: agent_chat; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_chat (
    id SERIAL,
    channel varchar(50) DEFAULT 'system',
    sender varchar(50) NOT NULL,
    message text NOT NULL,
    mentions text[],
    reply_to integer,
    created_at timestamptz DEFAULT now(),
    CONSTRAINT agent_chat_pkey PRIMARY KEY (id),
    CONSTRAINT agent_chat_reply_to_fkey FOREIGN KEY (reply_to) REFERENCES agent_chat (id)
);


COMMENT ON TABLE agent_chat IS 'Agent messaging. INSERT allowed for all, UPDATE/DELETE only Newhart.';

--
-- Name: idx_agent_chat_channel; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_chat_channel ON agent_chat (channel, created_at DESC);

--
-- Name: idx_agent_chat_created_at; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_chat_created_at ON agent_chat (created_at);

--
-- Name: idx_agent_chat_mentions; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_chat_mentions ON agent_chat USING gin (mentions);

--
-- Name: idx_agent_chat_sender; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_chat_sender ON agent_chat (sender, created_at DESC);

--
-- Name: agent_chat_processed; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS agent_chat_processed (
    chat_id integer,
    agent varchar(50),
    received_at timestamp,
    routed_at timestamp,
    responded_at timestamp,
    error_message text,
    status agent_chat_status DEFAULT 'responded'::agent_chat_status,
    CONSTRAINT agent_chat_processed_pkey PRIMARY KEY (chat_id, agent),
    CONSTRAINT agent_chat_processed_chat_id_fkey FOREIGN KEY (chat_id) REFERENCES agent_chat (id)
);


COMMENT ON TABLE agent_chat_processed IS 'Message processing state. Agents can track, Newhart manages.';

--
-- Name: idx_agent_chat_processed_agent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_agent ON agent_chat_processed (agent);

--
-- Name: idx_agent_chat_processed_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_status ON agent_chat_processed (status);

--
-- Name: idx_agent_chat_processed_unique; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_chat_processed_unique ON agent_chat_processed (chat_id, agent);

--
-- Name: idx_chat_processed_agent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_chat_processed_agent ON agent_chat_processed (agent);

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
-- Name: idx_jobs_agent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_jobs_agent ON agent_jobs (agent_name, status);

--
-- Name: idx_jobs_parent; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_jobs_parent ON agent_jobs (parent_job_id);

--
-- Name: idx_jobs_requester; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_jobs_requester ON agent_jobs (requester_agent, status);

--
-- Name: idx_jobs_root; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_jobs_root ON agent_jobs (root_job_id);

--
-- Name: idx_jobs_topic; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_jobs_topic ON agent_jobs (agent_name, topic) WHERE (status)::text <> ALL (ARRAY[('completed'::character varying)::text, ('cancelled'::character varying)::text]);

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
    CONSTRAINT agents_pkey PRIMARY KEY (id),
    CONSTRAINT agents_name_key UNIQUE (name),
    CONSTRAINT agents_context_type_check CHECK (context_type IN ('ephemeral'::text, 'persistent'::text)),
    CONSTRAINT agents_thinking_check CHECK (thinking::text IN ('off'::character varying, 'minimal'::character varying, 'low'::character varying, 'medium'::character varying, 'high'::character varying, 'xhigh'::character varying))
);


COMMENT ON TABLE agents IS 'Agent definitions. READ-ONLY except Newhart (Agent Design/Management domain).';


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

--
-- Name: idx_agents_provider; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agents_provider ON agents (provider);

--
-- Name: idx_agents_role; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agents_role ON agents (role);

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
-- Name: idx_agent_aliases_alias_lower; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_aliases_alias_lower ON agent_aliases (lower(alias::text));

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
-- Name: idx_agent_spawns_domain; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_spawns_domain ON agent_spawns (domain);

--
-- Name: idx_agent_spawns_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_spawns_status ON agent_spawns (status);

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
    CONSTRAINT models_pkey PRIMARY KEY (id),
    CONSTRAINT models_model_id_key UNIQUE (model_id)
);


COMMENT ON TABLE ai_models IS 'Available AI models. NOVA maintains this; Newhart reads for agent assignments. Credentials and endpoints stored in 1Password (see credential_ref column).';

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
    CONSTRAINT artwork_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE artwork IS 'Archive of NOVAs Instagram artwork. Reference for future compilation.';


COMMENT ON COLUMN artwork.image_data IS 'Raw image binary data (PNG/JPG)';


COMMENT ON COLUMN artwork.inspiration_source IS 'News snippet or source that inspired this artwork';

--
-- Name: asset_classes; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS asset_classes (
    code varchar(20),
    name varchar(100) NOT NULL,
    description text,
    price_source varchar(50),
    trading_hours varchar(100),
    typical_unit varchar(20),
    CONSTRAINT asset_classes_pkey PRIMARY KEY (code)
);


COMMENT ON TABLE asset_classes IS 'Asset class definitions for financial portfolio management. Defines tradeable asset types with pricing sources and trading characteristics.';


COMMENT ON COLUMN asset_classes.code IS 'Unique asset class identifier (e.g., STOCK, BOND, CRYPTO)';


COMMENT ON COLUMN asset_classes.name IS 'Human-readable asset class name';


COMMENT ON COLUMN asset_classes.description IS 'Detailed description of the asset class';


COMMENT ON COLUMN asset_classes.price_source IS 'Data source for price information (e.g., Yahoo Finance, Alpha Vantage)';


COMMENT ON COLUMN asset_classes.trading_hours IS 'When this asset class typically trades';


COMMENT ON COLUMN asset_classes.typical_unit IS 'Standard trading unit (shares, contracts, etc.)';

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
-- Name: conversations; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS conversations (
    id SERIAL,
    session_key varchar(255),
    channel varchar(50),
    started_at timestamp DEFAULT CURRENT_TIMESTAMP,
    summary text,
    notes text,
    CONSTRAINT conversations_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE conversations IS 'Conversation session tracking. Logs chat sessions with metadata for analysis and continuity.';


COMMENT ON COLUMN conversations.id IS 'Unique conversation identifier';


COMMENT ON COLUMN conversations.session_key IS 'Session identifier for grouping related messages';


COMMENT ON COLUMN conversations.channel IS 'Communication channel (signal, discord, etc.)';


COMMENT ON COLUMN conversations.started_at IS 'Conversation start timestamp';


COMMENT ON COLUMN conversations.summary IS 'Conversation summary or key points';


COMMENT ON COLUMN conversations.notes IS 'Additional notes about the conversation';

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

--
-- Name: idx_entities_name; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entities_name ON entities (name);

--
-- Name: idx_entities_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entities_type ON entities (type);

--
-- Name: idx_entities_user_id; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entities_user_id ON entities (user_id) WHERE (user_id IS NOT NULL);

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
-- Name: idx_agent_domains_topic; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_domains_topic ON agent_domains (domain_topic);

--
-- Name: idx_agent_domains_votes; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_domains_votes ON agent_domains (vote_count DESC);

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
-- Name: idx_certificates_fingerprint; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_certificates_fingerprint ON certificates (fingerprint);

--
-- Name: idx_certificates_serial; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_certificates_serial ON certificates (serial);

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
    source varchar(255),
    confidence double precision DEFAULT 1.0,
    learned_at timestamp DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP,
    visibility varchar(20) DEFAULT 'public',
    privacy_scope integer[],
    source_entity_id integer,
    visibility_reason text,
    vote_count integer DEFAULT 1,
    last_confirmed timestamp DEFAULT now(),
    data_type varchar(20) DEFAULT 'observation',
    last_confirmed_at timestamptz DEFAULT now(),
    confirmation_count integer DEFAULT 1,
    decay_rate real,
    CONSTRAINT entity_facts_pkey PRIMARY KEY (id),
    CONSTRAINT entity_facts_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
    CONSTRAINT entity_facts_source_entity_id_fkey FOREIGN KEY (source_entity_id) REFERENCES entities (id),
    CONSTRAINT chk_confidence CHECK (confidence >= 0::double precision AND confidence <= 1::double precision),
    CONSTRAINT chk_data_type CHECK (data_type::text IN ('permanent'::character varying, 'identity'::character varying, 'preference'::character varying, 'temporal'::character varying, 'observation'::character varying))
);


COMMENT ON TABLE entity_facts IS 'Key-value facts about entities. Check current_timezone for I)ruid before time-based actions.';


COMMENT ON COLUMN entity_facts.visibility IS 'Privacy level: public (anyone), trusted (close relationships), private (source only)';


COMMENT ON COLUMN entity_facts.privacy_scope IS 'Array of entity IDs explicitly allowed to see this fact (overrides visibility)';


COMMENT ON COLUMN entity_facts.source_entity_id IS 'FK to entity who provided this information (for privacy ownership)';


COMMENT ON COLUMN entity_facts.visibility_reason IS 'Reason visibility deviated from user default (audit trail)';


COMMENT ON COLUMN entity_facts.vote_count IS 'Reinforcement count - incremented each time this fact is re-confirmed in conversation';


COMMENT ON COLUMN entity_facts.last_confirmed IS 'Timestamp of most recent confirmation/reinforcement';

--
-- Name: idx_entity_facts_confidence; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_confidence ON entity_facts (confidence) WHERE (confidence < (1.0)::double precision);

--
-- Name: idx_entity_facts_data; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_data ON entity_facts USING gin (data);

--
-- Name: idx_entity_facts_data_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_data_type ON entity_facts (data_type);

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
-- Name: idx_entity_facts_source_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_source_entity ON entity_facts (source_entity_id);

--
-- Name: idx_entity_facts_value_trgm; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_value_trgm ON entity_facts USING gin (lower(value) gin_trgm_ops);

--
-- Name: idx_entity_facts_visibility; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_visibility ON entity_facts (visibility);

--
-- Name: idx_entity_facts_vote_count; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_vote_count ON entity_facts (vote_count DESC);

--
-- Name: entity_facts_archive; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS entity_facts_archive (
    id integer,
    entity_id integer,
    key varchar(255),
    value text,
    data jsonb,
    source varchar(255),
    confidence double precision,
    learned_at timestamp,
    updated_at timestamp,
    visibility varchar(20),
    privacy_scope integer[],
    source_entity_id integer,
    visibility_reason text,
    vote_count integer,
    last_confirmed timestamp,
    data_type varchar(20),
    last_confirmed_at timestamptz,
    confirmation_count integer,
    decay_rate real,
    archived_at timestamptz DEFAULT now(),
    archive_reason varchar(50),
    archived_by varchar(50) DEFAULT 'decay_script'
);


COMMENT ON TABLE entity_facts_archive IS 'Archived entity facts from decay/cleanup processes. Historical record of previously stored knowledge.';


COMMENT ON COLUMN entity_facts_archive.archived_at IS 'When the fact was archived';


COMMENT ON COLUMN entity_facts_archive.archive_reason IS 'Why the fact was archived (decay, conflict, manual)';


COMMENT ON COLUMN entity_facts_archive.archived_by IS 'System or agent that archived the fact';

--
-- Name: idx_entity_facts_archive_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_archive_date ON entity_facts_archive (archived_at);

--
-- Name: idx_entity_facts_archive_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_archive_entity ON entity_facts_archive (entity_id);

--
-- Name: idx_entity_facts_archive_key; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_entity_facts_archive_key ON entity_facts_archive (key);

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
    CONSTRAINT events_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE events IS 'Historical events, milestones, activities. Log significant occurrences.';

--
-- Name: idx_events_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_events_date ON events (event_date);

--
-- Name: idx_events_search; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_events_search ON events USING gin (search_vector);

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
-- Name: events_archive_event_date_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS events_archive_event_date_idx ON events_archive (event_date);

--
-- Name: events_archive_search_vector_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS events_archive_search_vector_idx ON events_archive USING gin (search_vector);

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
-- Name: idx_git_queue_priority; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_git_queue_priority ON git_issue_queue (priority DESC, created_at);

--
-- Name: idx_git_queue_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_git_queue_status ON git_issue_queue (status);

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
    CONSTRAINT job_messages_job_id_fkey FOREIGN KEY (job_id) REFERENCES agent_jobs (id),
    CONSTRAINT job_messages_message_id_fkey FOREIGN KEY (message_id) REFERENCES agent_chat (id)
);


COMMENT ON TABLE job_messages IS 'Message log per job for conversation threading';

--
-- Name: idx_job_messages; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_job_messages ON job_messages (job_id, added_at);

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
    CONSTRAINT lessons_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE lessons IS 'Lessons and insights learned. Update when learning something worth remembering.';


COMMENT ON COLUMN lessons.confidence IS 'Confidence score 0-1, decays over time if not reinforced';

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
-- Name: idx_library_works_doi; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_works_doi ON library_works (doi) WHERE (doi IS NOT NULL);

--
-- Name: idx_library_works_embed; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_works_embed ON library_works (embed) WHERE (embed = true);

--
-- Name: idx_library_works_isbn; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_works_isbn ON library_works (isbn) WHERE (isbn IS NOT NULL);

--
-- Name: idx_library_works_search; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_works_search ON library_works USING gin (search_vector);

--
-- Name: idx_library_works_subjects; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_library_works_subjects ON library_works USING gin (subjects);

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
-- Name: idx_media_consumed_by; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_media_consumed_by ON media_consumed (consumed_by);

--
-- Name: idx_media_search; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_media_search ON media_consumed USING gin (search_vector);

--
-- Name: idx_media_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_media_status ON media_consumed (status);

--
-- Name: idx_media_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_media_type ON media_consumed (media_type);

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
-- Name: idx_agent_actions_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_agent_actions_type ON agent_actions (action_type);

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
-- Name: idx_media_queue_priority; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_media_queue_priority ON media_queue (priority, requested_at);

--
-- Name: idx_media_queue_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_media_queue_status ON media_queue (status);

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
-- Name: idx_media_tags_tag; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_media_tags_tag ON media_tags (tag);

--
-- Name: memory_embeddings; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS memory_embeddings (
    id SERIAL,
    source_type varchar(50) NOT NULL,
    source_id text,
    content text NOT NULL,
    embedding vector(1536),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    confidence real DEFAULT 1.0,
    last_confirmed_at timestamptz DEFAULT now(),
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
-- Name: memory_embeddings_archive; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS memory_embeddings_archive (
    id SERIAL,
    source_type varchar(50) NOT NULL,
    source_id text,
    content text NOT NULL,
    embedding vector(1536),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    confidence real DEFAULT 1.0,
    last_confirmed_at timestamptz DEFAULT now(),
    archived_at timestamptz DEFAULT now(),
    archive_reason varchar(50),
    CONSTRAINT memory_embeddings_archive_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE memory_embeddings_archive IS 'Archived vector embeddings from semantic memory system. Historical embeddings for backup/analysis.';

--
-- Name: memory_embeddings_archive_embedding_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS memory_embeddings_archive_embedding_idx ON memory_embeddings_archive USING ivfflat (embedding vector_cosine_ops);

--
-- Name: memory_embeddings_archive_source_type_idx; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS memory_embeddings_archive_source_type_idx ON memory_embeddings_archive (source_type);

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
-- Name: idx_music_library_album; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_album ON music_library (musicbrainz_album_id);

--
-- Name: idx_music_library_artist; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_artist ON music_library (musicbrainz_artist_id);

--
-- Name: idx_music_library_bpm; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_bpm ON music_library (bpm);

--
-- Name: idx_music_library_genre; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_genre ON music_library (genre);

--
-- Name: idx_music_library_key; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_key ON music_library (key);

--
-- Name: idx_music_library_media; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_media ON music_library (media_id);

--
-- Name: idx_music_library_mood; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_mood ON music_library (mood);

--
-- Name: idx_music_library_year; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_library_year ON music_library (year);

--
-- Name: idx_music_search; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_search ON music_library USING gin (search_vector);

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
-- Name: idx_music_analysis_music; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_analysis_music ON music_analysis (music_id);

--
-- Name: idx_music_analysis_search; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_analysis_search ON music_analysis USING gin (search_vector);

--
-- Name: idx_music_analysis_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_music_analysis_type ON music_analysis (analysis_type);

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
-- Name: portfolio_positions; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS portfolio_positions (
    id SERIAL,
    symbol varchar(10) NOT NULL,
    shares numeric(12,6) NOT NULL,
    cost_basis numeric(12,2) NOT NULL,
    purchased_at timestamp NOT NULL,
    sold_at timestamp,
    sale_proceeds numeric(12,2),
    notes text,
    created_at timestamp DEFAULT now(),
    CONSTRAINT portfolio_positions_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE portfolio_positions IS 'Individual stock/investment positions tracking purchases, sales, and P&L. Core table for portfolio management.';


COMMENT ON COLUMN portfolio_positions.id IS 'Unique position identifier';


COMMENT ON COLUMN portfolio_positions.symbol IS 'Ticker symbol or asset identifier';


COMMENT ON COLUMN portfolio_positions.shares IS 'Number of shares/units held';


COMMENT ON COLUMN portfolio_positions.cost_basis IS 'Total purchase price';


COMMENT ON COLUMN portfolio_positions.purchased_at IS 'Date and time of purchase';


COMMENT ON COLUMN portfolio_positions.sold_at IS 'Date and time of sale (NULL for open positions)';


COMMENT ON COLUMN portfolio_positions.sale_proceeds IS 'Total sale proceeds (NULL for open positions)';


COMMENT ON COLUMN portfolio_positions.notes IS 'Additional notes about the position';


COMMENT ON COLUMN portfolio_positions.created_at IS 'Record creation timestamp';

--
-- Name: idx_positions_held; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_positions_held ON portfolio_positions (sold_at) WHERE (sold_at IS NULL);

--
-- Name: idx_positions_symbol; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_positions_symbol ON portfolio_positions (symbol);

--
-- Name: portfolio_snapshots; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS portfolio_snapshots (
    id SERIAL,
    snapshot_at timestamp DEFAULT now() NOT NULL,
    total_value numeric(12,2) NOT NULL,
    total_cost_basis numeric(12,2) NOT NULL,
    unrealized_pl numeric(12,2),
    unrealized_pl_pct numeric(8,4),
    positions jsonb,
    benchmark_m2 numeric(8,4),
    CONSTRAINT portfolio_snapshots_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE portfolio_snapshots IS 'Historical snapshots of portfolio values and performance metrics over time.';

--
-- Name: idx_snapshots_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_snapshots_date ON portfolio_snapshots (snapshot_at);

--
-- Name: idx_snapshots_day; Type: INDEX; Schema: -; Owner: -
--

CREATE UNIQUE INDEX IF NOT EXISTS idx_snapshots_day ON portfolio_snapshots ((snapshot_at::date));

--
-- Name: positions; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS positions (
    id SERIAL,
    symbol varchar(20) NOT NULL,
    asset_class varchar(20) NOT NULL,
    asset_subclass varchar(50),
    quantity numeric(18,8) NOT NULL,
    unit varchar(20) DEFAULT 'shares',
    cost_basis numeric(14,4) NOT NULL,
    avg_price numeric(14,4),
    purchased_at timestamp NOT NULL,
    sold_at timestamp,
    sale_proceeds numeric(14,4),
    platform varchar(50),
    account_id varchar(50) DEFAULT 'main',
    notes text,
    maturity_date date,
    coupon_rate numeric(6,4),
    strike_price numeric(14,4),
    expiration_date date,
    created_at timestamp DEFAULT now(),
    updated_at timestamp DEFAULT now(),
    CONSTRAINT positions_pkey PRIMARY KEY (id)
);


COMMENT ON TABLE positions IS 'Legacy or alternative positions tracking table. May be deprecated in favor of portfolio_positions.';

--
-- Name: idx_positions_account; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_positions_account ON positions (account_id) WHERE (sold_at IS NULL);

--
-- Name: idx_positions_asset_class; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_positions_asset_class ON positions (asset_class) WHERE (sold_at IS NULL);

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
-- Name: price_cache_v2; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS price_cache_v2 (
    symbol varchar(20),
    asset_class varchar(20),
    price numeric(14,4) NOT NULL,
    price_currency varchar(3) DEFAULT 'USD',
    bid numeric(14,4),
    ask numeric(14,4),
    volume numeric(20,0),
    market_cap numeric(20,0),
    day_change numeric(10,4),
    day_change_pct numeric(8,4),
    cached_at timestamp DEFAULT now(),
    source varchar(50),
    CONSTRAINT price_cache_v2_pkey PRIMARY KEY (symbol, asset_class)
);


COMMENT ON TABLE price_cache_v2 IS 'Cached price data for assets to reduce API calls. Version 2 of price caching system.';

--
-- Name: idx_price_cache_v2_lookup; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_price_cache_v2_lookup ON price_cache_v2 (symbol, asset_class, cached_at DESC);

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
-- Name: idx_project_tasks_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_project_tasks_status ON project_tasks (status);

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
-- Name: idx_ralph_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_ralph_status ON ralph_sessions (status) WHERE status IN ('PENDING'::text, 'RUNNING'::text);

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
-- Name: idx_history_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_history_entity ON shopping_history (entity_id);

--
-- Name: idx_history_restock; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_history_restock ON shopping_history (next_restock_at) WHERE (next_restock_at IS NOT NULL);

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
-- Name: idx_prefs_entity_cat; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_prefs_entity_cat ON shopping_preferences (entity_id, category);

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
-- Name: idx_wishlist_category; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_wishlist_category ON shopping_wishlist (category);

--
-- Name: idx_wishlist_entity; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_wishlist_entity ON shopping_wishlist (entity_id);

--
-- Name: idx_wishlist_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_wishlist_status ON shopping_wishlist (status);

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
-- Name: idx_tags_category; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_tags_category ON tags (category);

--
-- Name: idx_tags_name; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_tags_name ON tags (name);

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
    assigned_to integer,
    created_by integer,
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
    CONSTRAINT tasks_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES entities (id),
    CONSTRAINT tasks_blocked_on_fkey FOREIGN KEY (blocked_on) REFERENCES entities (id),
    CONSTRAINT tasks_created_by_fkey FOREIGN KEY (created_by) REFERENCES entities (id),
    CONSTRAINT tasks_parent_task_id_fkey FOREIGN KEY (parent_task_id) REFERENCES tasks (id) ON DELETE CASCADE,
    CONSTRAINT tasks_project_id_fkey FOREIGN KEY (project_id) REFERENCES projects (id) ON DELETE SET NULL
);


COMMENT ON TABLE tasks IS 'Task tracking. NOVA can create, update status, assign. Check before starting work.';


COMMENT ON COLUMN tasks.task_type IS 'one_off = complete once, recurring = resets after completion, fallback = low-priority repeatable when idle';


COMMENT ON COLUMN tasks.recurrence_interval IS 'How often recurring tasks reset (e.g., 1 day, 1 week)';


COMMENT ON COLUMN tasks.last_completed_at IS 'When task was last completed (for recurring reset logic)';

--
-- Name: idx_tasks_due; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_tasks_due ON tasks (due_date);

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

--
-- Name: idx_unsolved_problems_priority; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_unsolved_problems_priority ON unsolved_problems (priority DESC);

--
-- Name: idx_unsolved_problems_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_unsolved_problems_status ON unsolved_problems (status);

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
-- Name: idx_vehicles_vin; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_vehicles_vin ON vehicles (vin);

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
-- Name: idx_vocabulary_vote_count; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_vocabulary_vote_count ON vocabulary (vote_count DESC);

--
-- Name: workflows; Type: TABLE; Schema: -; Owner: -
--

CREATE TABLE IF NOT EXISTS workflows (
    id SERIAL,
    name text NOT NULL,
    description text NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    created_by text DEFAULT 'newhart',
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
-- Name: idx_workflows_department; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflows_department ON workflows (department);

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


COMMENT ON TABLE motivation_d100 IS 'D100 random task table for NOVA motivation system - roll when bored!';


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
-- Name: idx_workflow_steps_domains; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_steps_domains ON workflow_steps USING gin (domains);

--
-- Name: idx_workflow_steps_order; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_steps_order ON workflow_steps (workflow_id, step_order);

--
-- Name: idx_workflow_steps_workflow; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_workflow_steps_workflow ON workflow_steps (workflow_id);

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
-- Name: idx_works_created; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_works_created ON works (created_at DESC);

--
-- Name: idx_works_language; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_works_language ON works (language);

--
-- Name: idx_works_metadata; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_works_metadata ON works USING gin (metadata);

--
-- Name: idx_works_status; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_works_status ON works (status);

--
-- Name: idx_works_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_works_type ON works (work_type);

--
-- Name: idx_works_updated; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_works_updated ON works (updated_at DESC);

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
-- Name: idx_publications_by; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_publications_by ON publications (published_by);

--
-- Name: idx_publications_date; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_publications_date ON publications (published_at DESC);

--
-- Name: idx_publications_type; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_publications_type ON publications (publication_type);

--
-- Name: idx_publications_work; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_publications_work ON publications (work_id);

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
-- Name: idx_work_tags_tag; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_work_tags_tag ON work_tags (tag_id);

--
-- Name: idx_work_tags_work; Type: INDEX; Schema: -; Owner: -
--

CREATE INDEX IF NOT EXISTS idx_work_tags_work ON work_tags (work_id);

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
-- Name: embed_chat_message(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION embed_chat_message()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    content_text TEXT;
    content_hash_val VARCHAR(64);
BEGIN
    -- Prepare content for embedding
    content_text := NEW.sender || ': ' || NEW.message;
    content_hash_val := encode(sha256(content_text::bytea), 'hex');

    -- Insert embedding record (embedding vector will be populated by external process)
    -- This just creates a placeholder that external embedding service can process
    INSERT INTO memory_embeddings (content_hash, content, metadata, embedding)
    VALUES (
        content_hash_val,
        content_text,
        json_build_object(
            'chat_id', NEW.id,
            'sender', NEW.sender,
            'channel', NEW.channel,
            'created_at', NEW.created_at
        ),
        NULL  -- Will be updated by embedding service
    )
    ON CONFLICT (content_hash) DO NOTHING; -- Skip if already exists

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
    WHERE created_at < now() - interval '30 days'
    RETURNING id INTO v_count;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
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
-- Name: normalize_agent_chat_mentions(); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION normalize_agent_chat_mentions()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF NEW.mentions IS NOT NULL THEN
        NEW.mentions := ARRAY(SELECT LOWER(unnest(NEW.mentions)));
    END IF;
    NEW.sender := LOWER(NEW.sender);
    RETURN NEW;
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
        'id', NEW.id,
        'channel', NEW.channel,
        'sender', NEW.sender,
        'mentions', NEW.mentions
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
    v_id         INTEGER;
    v_sender     TEXT;
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
    v_sender     := LOWER(p_sender);
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
-- Name: send_agent_message(varchar, text, varchar, text[]); Type: FUNCTION; Schema: -; Owner: -
--

CREATE OR REPLACE FUNCTION send_agent_message(
    p_sender varchar,
    p_message text,
    p_channel varchar DEFAULT 'system',
    p_mentions text[] DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_id INTEGER;
    v_payload TEXT;
BEGIN
    INSERT INTO agent_chat (channel, sender, message, mentions)
    VALUES (p_channel, p_sender, p_message, p_mentions)
    RETURNING id INTO v_id;

    -- Notify listeners
    v_payload := json_build_object(
        'id', v_id,
        'channel', p_channel,
        'sender', p_sender,
        'message', substring(p_message, 1, 200),
        'mentions', p_mentions
    )::text;

    PERFORM pg_notify('agent_chat', v_payload);
    PERFORM pg_notify('agent_chat_' || p_channel, v_payload);

    RETURN v_id;
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
-- Name: agent_config_changed; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER agent_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agents
    FOR EACH ROW
    EXECUTE FUNCTION notify_agent_config_changed();

--
-- Name: agents_config_changed; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER agents_config_changed
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
-- Name: protect_bootstrap_context; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_bootstrap_context
    BEFORE INSERT OR UPDATE OR DELETE ON agent_bootstrap_context
    FOR EACH ROW
    EXECUTE FUNCTION protect_bootstrap_context_writes();

--
-- Name: protect_turn_context; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER protect_turn_context
    BEFORE INSERT OR UPDATE OR DELETE ON agent_turn_context
    FOR EACH ROW
    EXECUTE FUNCTION protect_bootstrap_context_writes();

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
-- Name: trg_embed_chat_message; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_embed_chat_message
    AFTER INSERT ON agent_chat
    FOR EACH ROW
    EXECUTE FUNCTION embed_chat_message();

--
-- Name: trg_library_works_search; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_library_works_search
    BEFORE INSERT OR UPDATE ON library_works
    FOR EACH ROW
    EXECUTE FUNCTION library_works_search_trigger();

--
-- Name: trg_normalize_mentions; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_normalize_mentions
    BEFORE INSERT ON agent_chat
    FOR EACH ROW
    EXECUTE FUNCTION normalize_agent_chat_mentions();

--
-- Name: trg_notify_agent_chat; Type: TRIGGER; Schema: -; Owner: -
--

CREATE OR REPLACE TRIGGER trg_notify_agent_chat
    AFTER INSERT ON agent_chat
    FOR EACH ROW
    EXECUTE FUNCTION notify_agent_chat();

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
    channel,
    sender,
    message,
    mentions,
    reply_to,
    created_at
   FROM agent_chat
  WHERE created_at > (now() - '30 days'::interval)
  ORDER BY created_at DESC;

--
-- Name: v_agent_chat_stats; Type: VIEW; Schema: -; Owner: -
--

CREATE OR REPLACE VIEW v_agent_chat_stats AS
 SELECT count(*) AS total_messages,
    count(*) FILTER (WHERE created_at > (now() - '24:00:00'::interval)) AS messages_24h,
    count(*) FILTER (WHERE created_at > (now() - '7 days'::interval)) AS messages_7d,
    count(DISTINCT sender) AS unique_senders,
    count(DISTINCT channel) AS active_channels,
    pg_size_pretty(pg_total_relation_size('agent_chat'::regclass)) AS table_size,
    min(created_at) AS oldest_message,
    max(created_at) AS newest_message
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

GRANT SELECT ON TABLE agent_turn_context TO nova;

