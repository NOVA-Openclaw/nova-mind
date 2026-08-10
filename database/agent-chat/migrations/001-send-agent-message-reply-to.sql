-- Migration: nova-mind#548
-- Extend send_agent_message() with p_reply_to as the 5th positional parameter.
--
-- Baseline: the live agent_chat database currently has a 4-arg signature
-- (p_sender, p_message, p_recipients, p_ttl). Any stale 3-arg repo-only
-- overload must be dropped first to avoid the "function is not unique" hazard.
--
-- Idempotent: drops all known overload signatures before recreating the final
-- 5-arg function, and leaves exactly one public.send_agent_message behind.

DO $$
BEGIN
    -- Drop stale overloads in all known historical shapes.
    DROP FUNCTION IF EXISTS public.send_agent_message(text, text, text[]);
    DROP FUNCTION IF EXISTS public.send_agent_message(text, text, text[], interval);
    DROP FUNCTION IF EXISTS public.send_agent_message(text, text, text[], interval, integer);
END $$;

CREATE OR REPLACE FUNCTION public.send_agent_message(
    p_sender     text,
    p_message    text,
    p_recipients text[],
    p_ttl        interval DEFAULT NULL::interval,
    p_reply_to   integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id         INTEGER;
    v_sender     TEXT;
    v_recipients TEXT[];
    v_expires_at TIMESTAMPTZ;
BEGIN
    -- Validate sender matches the actual connected database user.
    -- Must use session_user (not current_user) because SECURITY DEFINER
    -- sets current_user to the function owner (postgres).
    IF LOWER(p_sender) != session_user THEN
        RAISE EXCEPTION 'send_agent_message: sender must match session_user (got % but connected as %)', p_sender, session_user;
    END IF;

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

    -- GUARD: reject self-addressed messages (no legitimate use case; always a typo)
    IF v_sender = ANY(v_recipients) THEN
        RAISE EXCEPTION 'send_agent_message: sender "%" is in the recipient list — agents cannot message themselves (did you mean to address someone else?)', v_sender;
    END IF;

    -- Compute expiry if TTL provided
    IF p_ttl IS NOT NULL THEN
        v_expires_at := NOW() + p_ttl;
    END IF;

    -- Atomic insert including reply_to; the bypass trigger allows this because
    -- current_user = 'postgres' inside the SECURITY DEFINER context.
    INSERT INTO public.agent_chat (sender, message, recipients, reply_to, expires_at)
    VALUES (v_sender, p_message, v_recipients, p_reply_to, v_expires_at)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- Explicit ownership: the function must be owned by postgres so the SECURITY
-- DEFINER context sets current_user = 'postgres' and the DML lockdown trigger
-- authorizes INSERTs. Without this, a non-postgres superuser applying the
-- migration becomes the owner and agents get permission-denied on every send
-- (nova-mind#569). Wrapped so a non-superuser devtest apply still succeeds.
DO $$
BEGIN
    ALTER FUNCTION public.send_agent_message(text, text, text[], interval, integer) OWNER TO postgres;
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Skipping send_agent_message owner assignment: current user is not a superuser';
END $$;

-- Preserve the explicit EXECUTE grants that the checked-in schema file defines
-- for cross-ecosystem callers (victoria, nova-staging).
GRANT EXECUTE ON FUNCTION public.send_agent_message(text, text, text[], interval, integer) TO victoria, "nova-staging";
