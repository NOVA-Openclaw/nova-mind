-- pre-migration 009: Recreate get_agent_export_rows() for nova-mind#714 return-type change
-- SE #1231 r5 fix — upgrade path item 1.
--
-- Problem:
--   database/schema.sql now defines get_agent_export_rows() with a 12th
--   RETURNS TABLE column, heartbeat_isolated_session boolean (#714).
--   Existing production/staging databases still have the 11-column version.
--   pgschema plans a CREATE OR REPLACE FUNCTION for the new return type, but
--   Postgres rejects changing the return type of an existing function
--   (SQLSTATE 42P13), causing the installer to exit 1 at schema apply.
--
-- Fix:
--   Before pgschema runs, and only when the live function still returns 11
--   columns, add the agents.heartbeat_isolated_session column if it is missing
--   and recreate the function with the 12-column signature from schema.sql.
--   The ALTER TABLE + DROP FUNCTION + CREATE FUNCTION are wrapped in a single
--   DO block so they execute as one transaction; if any part fails, Postgres
--   rolls back and the existing function remains in place (gateways still get
--   agents.json NOTIFY regeneration).
--
-- Fresh-install no-op:
--   On a brand-new database neither the agents table nor the function exists
--   yet, so to_regclass / to_regprocedure return NULL and we return immediately.
--
-- Idempotence:
--   On re-run, pg_get_function_result() already contains
--   heartbeat_isolated_session, so we return immediately.
--
-- Privileges/owner:
--   Production proacl for this function is NULL (default PUBLIC EXECUTE).
--   Recreating it with default privileges preserves that. pgschema creates
--   objects as PG_SUPERUSER; the installer later reassigns ownership to DB_USER
--   when the two differ, so the recreated function follows the same ownership
--   path as every other schema object.
--
-- Run as: superuser (DDL). Mirrors the pattern used by 008.

DO $do$
DECLARE
    v_agents_class regclass;
    v_func_oid     regprocedure;
    v_result       text;
BEGIN
    -- Fresh install: nothing to migrate yet.
    v_agents_class := to_regclass('public.agents');
    IF v_agents_class IS NULL THEN
        RETURN;
    END IF;

    v_func_oid := to_regprocedure('public.get_agent_export_rows()');
    IF v_func_oid IS NULL THEN
        RETURN;
    END IF;

    -- Already upgraded; nothing to do.
    v_result := pg_get_function_result(v_func_oid);
    IF v_result LIKE '%heartbeat_isolated_session%' THEN
        RETURN;
    END IF;

    -- Existing function is the 11-column version. Add the column first so the
    -- new function body can reference it.
    ALTER TABLE public.agents
        ADD COLUMN IF NOT EXISTS heartbeat_isolated_session boolean DEFAULT false;

    -- Drop the stale 11-column definition and recreate the 12-column one
    -- exactly as it appears in database/schema.sql (#714).
    DROP FUNCTION public.get_agent_export_rows();

    CREATE OR REPLACE FUNCTION public.get_agent_export_rows()
    RETURNS TABLE(name text, model text, fallback_models text[], thinking text, instance_type text, is_default boolean, allowed_subagents text[], heartbeat_enabled boolean, heartbeat_every text, heartbeat_target text, heartbeat_to text, heartbeat_isolated_session boolean)
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
        a.heartbeat_to,
        a.heartbeat_isolated_session
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
        a.heartbeat_to,
        a.heartbeat_isolated_session
      FROM agents a
      WHERE session_user = ANY (a.parent_agents)
        AND a.status = 'active'
        AND a.model IS NOT NULL

      ORDER BY 6 DESC, 1;
    $$;
END $do$;
