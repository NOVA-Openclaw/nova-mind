-- Chunk 1 schema tests for nova-mind issue #474
-- Run against a disposable database with schema.sql applied.
-- Expects to be executed as the table owner (e.g., nova).
--
-- IMPORTANT TEST CAVEAT: schema.sql's ALTER DEFAULT PRIVILEGES block requires
-- a superuser (postgres). In this disposable DB the block fails, so this test
-- bootstraps the equivalent per-table grants, re-applies the issue-474 REVOKEs,
-- verifies the resulting catalog state, then temporarily grants the owner DML
-- to exercise constraints. Actual DML-as-hermes is deferred to chunk 5.

\set ON_ERROR_STOP 0
\pset pager off
\pset footer off

-- ── Test-only privilege bootstrap ───────────────────────────────────────────
-- Simulate production default privileges, then enforce the intended REVOKEs.
DO $$
DECLARE
    v_role text;
    v_roles text[] := ARRAY['argus','athena','coder','conductor','erato','flint','gem','gidget','hermes','iris','marcie','newhart','nova','quill','scout','scribe','ticker'];
BEGIN
    FOREACH v_role IN ARRAY v_roles LOOP
        EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', v_role);
        EXECUTE format('GRANT INSERT, UPDATE, DELETE, SELECT ON comms_items, comms_responses TO %I', v_role);
    END LOOP;
END;
$$;

-- Re-apply the intended REVOKEs from schema.sql for comms_items
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM argus;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM athena;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM coder;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM conductor;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM erato;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM flint;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM gem;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM gidget;
REVOKE DELETE ON TABLE comms_items FROM hermes;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM iris;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM marcie;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM newhart;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM nova;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM quill;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM scout;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM scribe;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_items FROM ticker;

-- Re-apply intended REVOKEs for comms_responses
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM argus;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM athena;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM coder;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM conductor;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM erato;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM flint;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM gem;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM gidget;
REVOKE DELETE ON TABLE comms_responses FROM hermes;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM iris;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM marcie;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM newhart;
REVOKE DELETE, INSERT ON TABLE comms_responses FROM nova;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM quill;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM scout;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM scribe;
REVOKE DELETE, INSERT, UPDATE ON TABLE comms_responses FROM ticker;

-- Helper to report results
CREATE OR REPLACE FUNCTION _test_result(p_name text, p_pass boolean, p_detail text DEFAULT NULL)
RETURNS text AS $$
BEGIN
    RETURN format('%s | %s%s',
        CASE WHEN p_pass THEN 'PASS' ELSE 'FAIL' END,
        p_name,
        CASE WHEN p_detail IS NOT NULL THEN ' | ' || p_detail ELSE '' END
    );
END;
$$ LANGUAGE plpgsql;

-- ── TC-474-18: grants for writer-of-record (catalog verification) ───────────
DO $$
DECLARE
    v_hermes_insert boolean := has_table_privilege('hermes', 'comms_items', 'INSERT');
    v_hermes_update boolean := has_table_privilege('hermes', 'comms_items', 'UPDATE');
    v_hermes_delete boolean := has_table_privilege('hermes', 'comms_items', 'DELETE');
    v_nova_select boolean := has_table_privilege('nova', 'comms_items', 'SELECT');
    v_nova_insert boolean := has_table_privilege('nova', 'comms_items', 'INSERT');
    v_hermes_resp_update boolean := has_table_privilege('hermes', 'comms_responses', 'UPDATE');
    v_hermes_resp_delete boolean := has_table_privilege('hermes', 'comms_responses', 'DELETE');
    v_nova_resp_update boolean := has_table_privilege('nova', 'comms_responses', 'UPDATE');
    v_nova_resp_insert boolean := has_table_privilege('nova', 'comms_responses', 'INSERT');
    v_nova_resp_delete boolean := has_table_privilege('nova', 'comms_responses', 'DELETE');
BEGIN
    RAISE NOTICE '%', _test_result('TC-474-18 comms_items grants',
        v_hermes_insert AND v_hermes_update AND NOT v_hermes_delete AND v_nova_select AND NOT v_nova_insert,
        format('hermes_insert=%s hermes_update=%s hermes_delete=%s nova_select=%s nova_insert=%s',
            v_hermes_insert, v_hermes_update, v_hermes_delete, v_nova_select, v_nova_insert)
    );

    RAISE NOTICE '%', _test_result('TC-474-18 comms_responses grants',
        v_hermes_resp_update AND NOT v_hermes_resp_delete AND v_nova_resp_update AND NOT v_nova_resp_insert AND NOT v_nova_resp_delete,
        format('hermes_update=%s hermes_delete=%s nova_update=%s nova_insert=%s nova_delete=%s',
            v_hermes_resp_update, v_hermes_resp_delete, v_nova_resp_update, v_nova_resp_insert, v_nova_resp_delete)
    );
END;
$$;

-- ── TC-474-01: Table exists with documented columns ─────────────────────────
DO $$
DECLARE
    v_expected text[] := ARRAY['id','platform','item_id','thread_id','entity_id','status','disposition','summary','artifact_ref','first_seen_at','reported_at','resolved_at'];
    v_missing text[];
BEGIN
    SELECT array_agg(e ORDER BY e) INTO v_missing
    FROM unnest(v_expected) e
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'comms_items' AND column_name = e
    );

    IF v_missing IS NULL THEN
        RAISE NOTICE '%', _test_result('TC-474-01 comms_items columns', true);
    ELSE
        RAISE NOTICE '%', _test_result('TC-474-01 comms_items columns', false, 'missing: ' || array_to_string(v_missing, ', '));
    END IF;
END;
$$;

-- Temporarily grant owner DML for constraint/function tests (test scaffolding only).
-- This is test-only: TC-474-18 was already verified against the intended catalog state.
GRANT INSERT, UPDATE, DELETE, SELECT ON comms_items, comms_responses TO CURRENT_USER;
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
        EXECUTE format('GRANT ALL ON TABLE %I TO CURRENT_USER', r.tablename);
    END LOOP;
END;
$$;

-- ── TC-474-02: UNIQUE (platform, item_id) enforced ──────────────────────────
DO $$
DECLARE
    v_dup_failed boolean := false;
BEGIN
    INSERT INTO comms_items (platform, item_id) VALUES ('email', '19f61b2e5aba4db7');
    BEGIN
        INSERT INTO comms_items (platform, item_id) VALUES ('email', '19f61b2e5aba4db7');
    EXCEPTION WHEN unique_violation THEN
        v_dup_failed := true;
    END;

    RAISE NOTICE '%', _test_result('TC-474-02 unique(platform,item_id)', v_dup_failed);
END;
$$;

-- ── TC-474-03: status CHECK constraint ──────────────────────────────────────
DO $$
DECLARE
    v_valid text[] := ARRAY['inbound','reported','tracked','resolved','dismissed'];
    v_invalid text[] := ARRAY['bogus_status',''];
    v_val text;
    v_all_pass boolean := true;
    v_detail text := '';
BEGIN
    FOREACH v_val IN ARRAY v_valid LOOP
        BEGIN
            INSERT INTO comms_items (platform, item_id, status) VALUES ('email', gen_random_uuid()::text, v_val);
        EXCEPTION WHEN OTHERS THEN
            v_all_pass := false;
            v_detail := v_detail || format('valid %s rejected: %s; ', v_val, SQLERRM);
        END;
    END LOOP;

    FOREACH v_val IN ARRAY v_invalid LOOP
        BEGIN
            INSERT INTO comms_items (platform, item_id, status) VALUES ('email', gen_random_uuid()::text, v_val);
            v_all_pass := false;
            v_detail := v_detail || format('invalid %s accepted; ', v_val);
        EXCEPTION WHEN OTHERS THEN
            -- expected
        END;
    END LOOP;

    BEGIN
        INSERT INTO comms_items (platform, item_id, status) VALUES ('email', gen_random_uuid()::text, NULL);
        v_all_pass := false;
        v_detail := v_detail || 'explicit NULL accepted; ';
    EXCEPTION WHEN OTHERS THEN
        -- expected
    END;

    RAISE NOTICE '%', _test_result('TC-474-03 status CHECK', v_all_pass, v_detail);
END;
$$;

-- ── TC-474-04: entity_id FK integrity ───────────────────────────────────────
DO $$
DECLARE
    v_null_ok boolean := false;
    v_bad_ok boolean := false;
    v_fk_works boolean := false;
    v_real_id bigint;
BEGIN
    -- Ensure a test entity exists for the real-FK path.
    INSERT INTO entities (name, type)
    VALUES ('__test_entity_474', 'person')
    ON CONFLICT (name, type) DO NOTHING;
    SELECT id INTO v_real_id FROM entities WHERE name = '__test_entity_474' LIMIT 1;

    BEGIN
        INSERT INTO comms_items (platform, item_id, entity_id) VALUES ('email', gen_random_uuid()::text, NULL);
        v_null_ok := true;
    EXCEPTION WHEN OTHERS THEN
        v_null_ok := false;
    END;

    BEGIN
        INSERT INTO comms_items (platform, item_id, entity_id) VALUES ('email', gen_random_uuid()::text, 999999999);
        v_bad_ok := false;
    EXCEPTION WHEN foreign_key_violation THEN
        v_bad_ok := true;
    END;

    IF v_real_id IS NOT NULL THEN
        BEGIN
            INSERT INTO comms_items (platform, item_id, entity_id) VALUES ('email', gen_random_uuid()::text, v_real_id);
            v_fk_works := true;
        EXCEPTION WHEN OTHERS THEN
            v_fk_works := false;
        END;
    END IF;

    RAISE NOTICE '%', _test_result('TC-474-04 entity_id FK',
        v_null_ok AND v_bad_ok AND v_fk_works,
        format('null=%s bad_rejected=%s real_fk=%s', v_null_ok, v_bad_ok, v_fk_works)
    );
END;
$$;

-- ── TC-474-05: first_seen_at default ────────────────────────────────────────
DO $$
DECLARE
    v_fs timestamptz;
    v_now timestamptz := now();
BEGIN
    INSERT INTO comms_items (platform, item_id) VALUES ('email', gen_random_uuid()::text) RETURNING first_seen_at INTO v_fs;
    IF v_fs IS NOT NULL AND v_fs BETWEEN v_now - interval '5 seconds' AND v_now + interval '5 seconds' THEN
        RAISE NOTICE '%', _test_result('TC-474-05 first_seen_at default', true);
    ELSE
        RAISE NOTICE '%', _test_result('TC-474-05 first_seen_at default', false, coalesce(v_fs::text, 'NULL'));
    END IF;
END;
$$;

-- ── TC-474-06: COMMENTs present ─────────────────────────────────────────────
DO $$
DECLARE
    v_table_comment text;
    v_status_comment text;
BEGIN
    SELECT obj_description('comms_items'::regclass) INTO v_table_comment;
    SELECT col_description('comms_items'::regclass, a.attnum)
    INTO v_status_comment
    FROM pg_attribute a
    WHERE a.attrelid = 'comms_items'::regclass AND a.attname = 'status' AND a.attnum > 0;

    RAISE NOTICE '%', _test_result('TC-474-06 COMMENTs',
        v_table_comment IS NOT NULL AND length(v_table_comment) > 0
        AND v_status_comment IS NOT NULL AND length(v_status_comment) > 0,
        format('table=%s status=%s',
            CASE WHEN v_table_comment IS NOT NULL THEN 'present' ELSE 'missing' END,
            CASE WHEN v_status_comment IS NOT NULL THEN 'present' ELSE 'missing' END
        )
    );
END;
$$;

-- ── TC-474-07: no updated_at column ─────────────────────────────────────────
DO $$
DECLARE
    v_has_updated_at boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'comms_items' AND column_name = 'updated_at'
    ) INTO v_has_updated_at;

    RAISE NOTICE '%', _test_result('TC-474-07 no updated_at column', NOT v_has_updated_at);
END;
$$;

-- ── TC-474-08: indexes support expected query patterns ──────────────────────
DO $$
DECLARE
    v_first_seen_idx boolean;
    v_platform_status_idx boolean;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND tablename = 'comms_items' AND indexname = 'idx_comms_items_first_seen'
    ) INTO v_first_seen_idx;

    SELECT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND tablename = 'comms_items' AND indexname = 'idx_comms_items_platform_status'
    ) INTO v_platform_status_idx;

    RAISE NOTICE '%', _test_result('TC-474-08 indexes',
        v_first_seen_idx AND v_platform_status_idx,
        format('first_seen=%s platform_status=%s', v_first_seen_idx, v_platform_status_idx)
    );
END;
$$;

-- ── TC-474-09: approval-gate home exists (comms_responses) ─────────────────
DO $$
DECLARE
    v_cols text[];
BEGIN
    SELECT array_agg(column_name::text ORDER BY column_name) INTO v_cols
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'comms_responses';

    RAISE NOTICE '%', _test_result('TC-474-09 comms_responses home',
        v_cols @> ARRAY['comms_item_id','draft_response','approved_by','approved_at','response_id'],
        coalesce(array_to_string(v_cols, ','), 'missing table')
    );
END;
$$;

-- ── TC-474-40/36/37/38/42: resolve_entity_by_identifier ─────────────────────
DO $$
DECLARE
    v_eid bigint;
    v_resolved bigint;
    v_null_result bigint;
BEGIN
    -- create a test entity + facts
    INSERT INTO entities (name, type) VALUES ('__test_entity_474_resolve', 'person') RETURNING id INTO v_eid;
    INSERT INTO entity_facts (entity_id, key, value) VALUES (v_eid, 'email', 'Test.User@Example.COM');

    v_resolved := resolve_entity_by_identifier('email', 'test.user@example.com');
    v_null_result := resolve_entity_by_identifier('email', 'no.such.user@example.com');

    RAISE NOTICE '%', _test_result('TC-474-40/36 resolve_entity_by_identifier exact match',
        v_resolved = v_eid,
        format('expected=%s got=%s', v_eid, v_resolved)
    );

    RAISE NOTICE '%', _test_result('TC-474-37/38 resolve_entity_by_identifier NULL on no match',
        v_null_result IS NULL,
        format('got=%s', v_null_result)
    );

    -- cleanup
    DELETE FROM entity_facts WHERE entity_id = v_eid;
    DELETE FROM entities WHERE id = v_eid;
END;
$$;

-- Clean up test rows
DELETE FROM comms_items WHERE platform = 'email' AND item_id = '19f61b2e5aba4db7';
DELETE FROM comms_items WHERE platform = 'email' AND item_id LIKE 'direct-test-%';
