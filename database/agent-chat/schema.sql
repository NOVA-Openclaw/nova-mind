--
-- agent_chat database schema
-- Issue: NOVA-Openclaw/nova-mind#320
--
-- This file defines the standalone messaging bus database. It is applied AFTER
-- the `agent_chat` database has been created by the migration tooling.
--
-- Design decisions (authoritative, 2026-07-03):
--   * agent_chat_status type migrates.
--   * Tables agent_chat + agent_chat_processed migrate with all data.
--   * Indexes migrate except the duplicate idx_chat_processed_agent.
--   * Functions migrate: send_agent_message (SECURITY DEFINER), notify_agent_chat,
--     enforce_agent_chat_function_use, expire_old_chat.
--   * chat() and embed_chat_message() do NOT migrate; they are dropped from
--     nova_memory at decommission.
--   * Triggers migrate: trg_notify_agent_chat (ENABLE ALWAYS) and ONE enforce
--     trigger (trg_enforce_agent_chat_function_use). trg_embed_chat_message is
--     intentionally absent.
--   * Views v_agent_chat_recent and v_agent_chat_stats migrate.
--   * Grants replicate the nova_memory matrix for the 18 nova-ecosystem agent
--     roles including Newhart's REVOKEs, plus victoria (send+receive) and
--     nova-staging (SEND capability).
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: agent_chat_status; Type: TYPE; Schema: public; Owner: -
--
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'public' AND t.typname = 'agent_chat_status') THEN
        CREATE TYPE public.agent_chat_status AS ENUM (
            'received',
            'routed',
            'responded',
            'failed'
        );
    END IF;
END $$;

--
-- Name: agent_chat; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE IF NOT EXISTS public.agent_chat (
    id SERIAL,
    sender varchar(50) NOT NULL,
    message text NOT NULL,
    recipients text[] NOT NULL,
    reply_to integer,
    "timestamp" timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT agent_chat_pkey PRIMARY KEY (id),
    CONSTRAINT agent_chat_reply_to_fkey FOREIGN KEY (reply_to) REFERENCES public.agent_chat (id),
    CONSTRAINT agent_chat_recipients_check CHECK (array_length(recipients, 1) > 0)
);

COMMENT ON TABLE public.agent_chat IS 'Agent messaging. INSERT allowed for all, UPDATE/DELETE only Newhart.';

--
-- Name: agent_chat_processed; Type: TABLE; Schema: public; Owner: -
--
CREATE TABLE IF NOT EXISTS public.agent_chat_processed (
    chat_id integer,
    agent varchar(50),
    received_at timestamp,
    routed_at timestamp,
    responded_at timestamp,
    error_message text,
    status public.agent_chat_status DEFAULT 'responded'::public.agent_chat_status,
    CONSTRAINT agent_chat_processed_pkey PRIMARY KEY (chat_id, agent),
    CONSTRAINT agent_chat_processed_chat_id_fkey FOREIGN KEY (chat_id) REFERENCES public.agent_chat (id)
);

COMMENT ON TABLE public.agent_chat_processed IS 'Message processing state. Agents can track, Newhart manages.';

--
-- Indexes (duplicate idx_chat_processed_agent intentionally omitted)
--
CREATE INDEX IF NOT EXISTS idx_agent_chat_recipients ON public.agent_chat USING gin (recipients);
CREATE INDEX IF NOT EXISTS idx_agent_chat_sender ON public.agent_chat (sender, "timestamp" DESC);
CREATE INDEX IF NOT EXISTS idx_agent_chat_timestamp ON public.agent_chat ("timestamp");

CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_agent ON public.agent_chat_processed (agent);
CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_status ON public.agent_chat_processed (status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_chat_processed_unique ON public.agent_chat_processed (chat_id, agent);

--
-- Functions
--

-- Name: notify_agent_chat(); Type: FUNCTION; Schema: public; Owner: -
CREATE OR REPLACE FUNCTION public.notify_agent_chat()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_notify('agent_chat', json_build_object(
        'id', NEW.id,
        'sender', NEW.sender,
        'recipients', NEW.recipients
    )::text);
    RETURN NEW;
END;
$$;

-- Name: send_agent_message(text, text, text[]); Type: FUNCTION; Schema: public; Owner: -
CREATE OR REPLACE FUNCTION public.send_agent_message(
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
    INSERT INTO public.agent_chat (sender, message, recipients)
    VALUES (v_sender, p_message, v_recipients)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- Name: enforce_agent_chat_function_use(); Type: FUNCTION; Schema: public; Owner: -
CREATE OR REPLACE FUNCTION public.enforce_agent_chat_function_use()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    -- Skip enforcement for logical replication (apply worker)
    IF current_setting('agent_chat.bypass_gate', true) IS NOT DISTINCT FROM 'on' THEN
        RETURN NEW;
    END IF;
    -- Check if this is a replication apply worker
    IF EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = pg_backend_pid() AND backend_type = 'logical replication worker') THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Direct INSERT on agent_chat is not allowed. Use send_agent_message() instead.';
END;
$$;

-- Name: expire_old_chat(integer); Type: FUNCTION; Schema: public; Owner: -
CREATE OR REPLACE FUNCTION public.expire_old_chat(
    retention_days integer DEFAULT 90
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE deleted_count integer;
BEGIN
    DELETE FROM public.agent_chat WHERE "timestamp" < now() - (retention_days || ' days')::interval;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

--
-- Views
--

-- Name: v_agent_chat_recent; Type: VIEW; Schema: public; Owner: -
CREATE OR REPLACE VIEW public.v_agent_chat_recent AS
 SELECT id,
    sender,
    message,
    recipients,
    reply_to,
    "timestamp"
   FROM public.agent_chat
  WHERE "timestamp" > (now() - '30 days'::interval)
  ORDER BY "timestamp" DESC;

-- Name: v_agent_chat_stats; Type: VIEW; Schema: public; Owner: -
CREATE OR REPLACE VIEW public.v_agent_chat_stats AS
 SELECT count(*) AS total_messages,
    count(*) FILTER (WHERE "timestamp" > (now() - '24:00:00'::interval)) AS messages_24h,
    count(*) FILTER (WHERE "timestamp" > (now() - '7 days'::interval)) AS messages_7d,
    count(DISTINCT sender) AS unique_senders,
    pg_size_pretty(pg_total_relation_size('agent_chat'::regclass)) AS table_size,
    min("timestamp") AS oldest_message,
    max("timestamp") AS newest_message
   FROM public.agent_chat;

--
-- Triggers
--

-- Name: trg_notify_agent_chat; Type: TRIGGER; Schema: public; Owner: -
-- ENABLE ALWAYS is required so that replication-apply-worker-originated inserts
-- still notify bus listeners.
DROP TRIGGER IF EXISTS trg_notify_agent_chat ON public.agent_chat;
CREATE TRIGGER trg_notify_agent_chat
    AFTER INSERT ON public.agent_chat
    FOR EACH ROW
    EXECUTE FUNCTION public.notify_agent_chat();

ALTER TABLE public.agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;

-- Name: trg_enforce_agent_chat_function_use; Type: TRIGGER; Schema: public; Owner: -
-- Only ONE enforce trigger is created in the new DB (duplicate
-- trg_enforce_function_use is intentionally omitted).
DROP TRIGGER IF EXISTS trg_enforce_agent_chat_function_use ON public.agent_chat;
CREATE TRIGGER trg_enforce_agent_chat_function_use
    BEFORE INSERT ON public.agent_chat
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_agent_chat_function_use();

--
-- Privileges
--
-- Replicate the effective grant matrix from nova_memory.
-- Default privileges mirror the source dump so future objects created by
-- postgres/nova get the same grants; explicit grants make current objects
-- deterministic regardless of which role creates them.
--

-- Default privileges (mirrors nova_memory dump).
-- The postgres-role default privileges can only be set by a superuser. They
-- are wrapped so that the schema file can still be applied by a non-superuser
-- (e.g. nova in a devtest environment) without failing.
DO $$
BEGIN
    ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT USAGE ON SEQUENCES TO argus, athena, coder, conductor, erato, flint, gem, gidget, hermes, iris, marcie, nova, quill, scout, scribe, ticker;
    ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT DELETE, INSERT, SELECT, UPDATE ON TABLES TO argus, athena, coder, conductor, erato, flint, gem, gidget, hermes, iris, marcie, nova, quill, scout, scribe, ticker;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping postgres default privileges: current user is not a superuser';
END $$;

ALTER DEFAULT PRIVILEGES FOR ROLE nova IN SCHEMA public GRANT SELECT ON TABLES TO argus, athena, coder, conductor, erato, flint, gem, gidget, graybeard, hermes, iris, marcie, newhart, "nova-staging", quill, scout, scribe, ticker;

-- Explicit table grants for all nova-ecosystem agent roles (18 roles)
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.agent_chat TO argus, athena, coder, conductor, erato, flint, gem, gidget, hermes, iris, marcie, nova, quill, scout, scribe, ticker;
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.agent_chat_processed TO argus, athena, coder, conductor, erato, flint, gem, gidget, hermes, iris, marcie, nova, quill, scout, scribe, ticker;

-- Newhart's access is intentionally restricted: revoke all privileges that
-- default privileges would otherwise grant.
REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE public.agent_chat FROM newhart;
REVOKE SELECT ON TABLE public.agent_chat FROM newhart;
REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE public.agent_chat_processed FROM newhart;
REVOKE SELECT ON TABLE public.agent_chat_processed FROM newhart;

-- Peer agent graybeard gets the same full CRUD as subagents.
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.agent_chat TO graybeard;
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.agent_chat_processed TO graybeard;

-- nova-staging: SEND capability per decision #6. EXECUTE on send_agent_message
-- is granted explicitly below; SELECT on the bus tables lets it read/poll.
GRANT SELECT ON TABLE public.agent_chat TO "nova-staging";
GRANT SELECT ON TABLE public.agent_chat_processed TO "nova-staging";

-- victoria: send+receive capability on the shared cross-ecosystem bus.
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.agent_chat TO victoria;
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.agent_chat_processed TO victoria;

-- Sequence grants (replicate nova_memory matrix; newhart intentionally absent)
GRANT USAGE ON SEQUENCE public.agent_chat_id_seq TO argus, coder, conductor, erato, flint, gem, gidget, graybeard, hermes, iris, marcie, nova, quill, scribe, ticker;
GRANT SELECT, USAGE ON SEQUENCE public.agent_chat_id_seq TO athena, scout;
GRANT USAGE ON SEQUENCE public.agent_chat_id_seq TO victoria;
-- nova-staging only needs SEND capability; it does not need to allocate sequence values.

-- View grants (replicate nova_memory matrix)
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.v_agent_chat_recent TO argus, athena, coder, conductor, erato, flint, gem, gidget, hermes, iris, marcie, newhart, nova, quill, scout, scribe, ticker;
GRANT SELECT ON TABLE public.v_agent_chat_recent TO graybeard, "nova-staging";
GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE public.v_agent_chat_stats TO argus, athena, coder, conductor, erato, flint, gem, gidget, hermes, iris, marcie, newhart, nova, quill, scout, scribe, ticker;
GRANT SELECT ON TABLE public.v_agent_chat_stats TO graybeard, "nova-staging";

-- victoria view grants (read access for receive/polling)
GRANT SELECT ON TABLE public.v_agent_chat_recent TO victoria;
GRANT SELECT ON TABLE public.v_agent_chat_stats TO victoria;

-- Function grants: existing nova_memory functions default to PUBLIC EXECUTE.
-- We explicitly document the required EXECUTE capability for victoria and
-- nova-staging without revoking PUBLIC access.
GRANT EXECUTE ON FUNCTION public.send_agent_message(text, text, text[]) TO victoria, "nova-staging";
