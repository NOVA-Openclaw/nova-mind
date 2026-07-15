-- Final migration tests for nova-mind issue #474.
--
-- Covers Area 3 (TC-474-10..16): fold of social_interactions into
-- comms_items/comms_responses, idempotency, fresh-install ordering, upgrade
-- path, timestamp preservation, and outbound-only guard.
--
-- Run against a disposable database with database/schema.sql already applied.
--
-- Usage:
--   createdb issue474_test_migration
--   psql -U nova -d issue474_test_migration -f database/schema.sql
--   psql -U nova -d issue474_test_migration -f tests/TEST-474-migration.sql

\set ON_ERROR_STOP on
\pset pager off
\pset footer off
\timing on

CREATE OR REPLACE FUNCTION _test(label text, pass boolean)
RETURNS text AS $$
BEGIN
    IF pass THEN
        RETURN 'PASS: ' || label;
    ELSE
        RAISE EXCEPTION 'FAIL: %', label;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Scenario A: Fresh-install shape (social_interactions does not exist)
-- =============================================================================

TRUNCATE comms_items, comms_responses RESTART IDENTITY CASCADE;

DO $$
BEGIN
    DROP TABLE IF EXISTS social_interactions;
END $$;

\ir ../cognition/scripts/migrations/164-fold-social-interactions-to-comms-items.sql

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count FROM comms_items;
    RAISE NOTICE '%', _test('TC-474-13 fresh install: migration no-ops when social_interactions absent', v_count = 0);
END $$;

-- =============================================================================
-- Scenario B: Upgrade shape (social_interactions exists with live-shaped data)
-- =============================================================================

CREATE TABLE IF NOT EXISTS social_interactions (
    id SERIAL PRIMARY KEY,
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
    CONSTRAINT social_interactions_platform_mention_id_key UNIQUE (platform, mention_id),
    CONSTRAINT social_interactions_status_check CHECK (status IN ('seen', 'needs_response', 'drafted', 'approved', 'posted', 'dismissed'))
);

TRUNCATE social_interactions RESTART IDENTITY CASCADE;

INSERT INTO social_interactions
    (platform, mention_id, thread_id, author_handle, content, status, draft_response, response_id, approved_by, approved_at, responded_at, dismissed_reason, notes, created_at, updated_at)
VALUES
    ('x', '2066527088044310600', NULL, 'incubatordesuka', 'Live row 1 content', 'posted', NULL, NULL, NULL, NULL, NULL, NULL, 'Row 1 notes', '2026-06-20 05:30:00+00', '2026-06-25 09:06:51.224739+00'),
    ('x', '2068203978920480818', NULL, 'incubatordesuka', 'Live row 2 content', 'posted', 'Draft response for row 2', NULL, NULL, NULL, NULL, NULL, 'Row 2 notes', '2026-06-25 09:07:00.768065+00', '2026-06-30 19:18:37.206828+00'),
    ('x', '2063774004901716262', NULL, 'incubatordesuka', 'Live row 3 content', 'dismissed', NULL, NULL, NULL, NULL, NULL, 'Backfilled routine reply', NULL, '2026-06-25 09:07:00.770101+00', '2026-06-25 09:07:00.770101+00'),
    ('x', '2068197837972902263', NULL, NULL, NULL, 'posted', NULL, NULL, NULL, NULL, NULL, NULL, NULL, '2026-06-25 13:30:47.49118+00', '2026-06-25 13:30:47.49118+00'),
    ('x', '2072221269274362361', '2071917674528215245', '@druidian', 'Live row 5 content', 'dismissed', NULL, NULL, NULL, NULL, NULL, 'Dismissed reason row 5', 'Notes row 5', '2026-07-01 09:05:45.16784+00', '2026-07-03 05:10:12.361361+00'),
    ('x', '2072263873558643048', '2071819757645447422', '@TIDALSupport', 'Live row 6 content', 'dismissed', 'Draft response row 6', NULL, NULL, NULL, NULL, 'Dismissed reason row 6', 'Notes row 6', '2026-07-01 13:06:30.742521+00', '2026-07-02 09:07:11.423284+00'),
    ('nostr', 'd615c301abb60cc49d08d238750eaf1abd4c2c0265e8d384a884d24f6ed8126a', '8014c33671736c821c29f5184342fa852e53667ec781516e675547ba3b4280a2', 'unknown-7949809730', 'Live row 7 content', 'dismissed', NULL, NULL, NULL, NULL, NULL, 'Spam dismissed', NULL, '2026-07-02 13:07:36.499202+00', '2026-07-02 13:07:36.499202+00'),
    ('nostr', '012df11780b4d7d39c409e2b4aceebff3edebdd8aa6906004ce3f9375d3d5d21', '8014c33671736c821c29f5184342fa852e53667ec781516e675547ba3b4280a2', 'putridinsight864', 'Live row 8 content', 'dismissed', 'Draft response row 8', NULL, NULL, NULL, NULL, 'Dismissed reason row 8', 'Notes row 8', '2026-07-02 13:07:36.499202+00', '2026-07-03 08:39:48.240229+00'),
    ('x', '2073369349834875157', '2073122306814292441', 'FractalEncrypt', 'Live row 9 content', 'dismissed', NULL, NULL, NULL, NULL, NULL, 'No response needed', 'Weekend tweet reply', '2026-07-04 13:09:59.503401+00', '2026-07-04 13:09:59.503401+00'),
    ('x', '2073360825943814468', '2073122306814292441', 'druidian', 'Live row 10 content', 'posted', 'Draft response row 10', '2074277192649912618', 'I)ruid', '2026-07-06 23:40:07.391045+00', '2026-07-06 23:40:07.391045+00', 'Awaiting approval', 'Posted reply', '2026-07-04 13:09:59.506565+00', '2026-07-06 23:40:07.391045+00'),
    -- In-flight drafted row (TC-474-11)
    ('x', '2079999999999999999', '2073122306814292441', 'SomeUser', 'In-flight drafted content', 'drafted', 'Draft response text here.', NULL, NULL, NULL, NULL, NULL, 'In-flight approval workflow item.', '2026-07-10 10:00:00+00', '2026-07-10 10:00:00+00'),
    -- Synthetic outbound row (TC-474-16): must NOT be migrated
    ('x', '2080000000000000000', NULL, 'NOVA_Openclaw', 'NOVA own outbound post', 'posted', NULL, '2080000000000000001', 'NOVA', '2026-07-10 11:00:00+00', '2026-07-10 11:00:00+00', NULL, NULL, '2026-07-10 11:00:00+00', '2026-07-10 11:00:00+00');

CREATE TEMP TABLE pre_fold_state AS
SELECT platform, mention_id, author_handle, status, created_at, responded_at, draft_response, response_id, approved_by, approved_at, dismissed_reason, notes
FROM social_interactions;

-- First fold run.
\ir ../cognition/scripts/migrations/164-fold-social-interactions-to-comms-items.sql

-- =============================================================================
-- TC-474-10: Status mapping assertions
-- =============================================================================

DO $$
DECLARE
    v_bad integer;
BEGIN
    SELECT COUNT(*) INTO v_bad
    FROM pre_fold_state p
    LEFT JOIN comms_items c
      ON c.platform = p.platform
     AND c.item_id = p.mention_id
    WHERE p.author_handle IS DISTINCT FROM 'NOVA_Openclaw'
      AND c.id IS NULL;

    RAISE NOTICE '%', _test('TC-474-10: every inbound social_interactions row has a comms_items mapping', v_bad = 0);

    SELECT COUNT(*) INTO v_bad
    FROM comms_items
    WHERE (platform, item_id, status) NOT IN (
        ('x', '2066527088044310600', 'resolved'),
        ('x', '2068203978920480818', 'resolved'),
        ('x', '2063774004901716262', 'dismissed'),
        ('x', '2068197837972902263', 'resolved'),
        ('x', '2072221269274362361', 'dismissed'),
        ('x', '2072263873558643048', 'dismissed'),
        ('nostr', 'd615c301abb60cc49d08d238750eaf1abd4c2c0265e8d384a884d24f6ed8126a', 'dismissed'),
        ('nostr', '012df11780b4d7d39c409e2b4aceebff3edebdd8aa6906004ce3f9375d3d5d21', 'dismissed'),
        ('x', '2073369349834875157', 'dismissed'),
        ('x', '2073360825943814468', 'resolved'),
        ('x', '2079999999999999999', 'tracked')
    );

    RAISE NOTICE '%', _test('TC-474-10: status mappings match decision table', v_bad = 0);
END $$;

-- =============================================================================
-- TC-474-11: In-flight drafted item continues to function after fold
-- =============================================================================

DO $$
DECLARE
    v_item_id bigint;
    v_response_count integer;
BEGIN
    SELECT id INTO v_item_id FROM comms_items WHERE platform = 'x' AND item_id = '2079999999999999999';

    SELECT COUNT(*) INTO v_response_count
    FROM comms_responses
    WHERE comms_item_id = v_item_id
      AND draft_response = 'Draft response text here.';

    RAISE NOTICE '%', _test('TC-474-11: drafted row lands as tracked with draft in comms_responses', v_response_count = 1);

    UPDATE comms_responses
    SET approved_by = 'I)ruid',
        approved_at = '2026-07-10 12:00:00+00'
    WHERE comms_item_id = v_item_id;

    UPDATE comms_items
    SET status = 'resolved',
        resolved_at = '2026-07-10 13:00:00+00'
    WHERE id = v_item_id;

    RAISE NOTICE '%', _test('TC-474-11: post-fold approval and resolve transitions succeed',
        EXISTS (SELECT 1 FROM comms_responses WHERE comms_item_id = v_item_id AND approved_by = 'I)ruid'));
END $$;

-- =============================================================================
-- TC-474-12: Idempotency — second run produces no duplicates or errors
-- =============================================================================

CREATE TEMP TABLE pre_second_run AS
SELECT platform, item_id, status, first_seen_at, resolved_at FROM comms_items;

\ir ../cognition/scripts/migrations/164-fold-social-interactions-to-comms-items.sql

DO $$
DECLARE
    v_diff integer;
BEGIN
    SELECT COUNT(*) INTO v_diff
    FROM (
        SELECT platform, item_id, status, first_seen_at, resolved_at FROM comms_items
        EXCEPT
        SELECT platform, item_id, status, first_seen_at, resolved_at FROM pre_second_run
    ) x;

    RAISE NOTICE '%', _test('TC-474-12: second migration run does not change comms_items state', v_diff = 0);
END $$;

-- =============================================================================
-- TC-474-14: Upgrade path row count and data preservation
-- =============================================================================

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count FROM comms_items;
    RAISE NOTICE '%', _test('TC-474-14: 11 inbound rows migrated into comms_items', v_count = 11);

    SELECT COUNT(*) INTO v_count
    FROM comms_items c
    JOIN pre_fold_state p
      ON c.platform = p.platform
     AND c.item_id = p.mention_id;
    RAISE NOTICE '%', _test('TC-474-14: every migrated row maps back to a pre-fold row', v_count = 11);
END $$;

-- =============================================================================
-- TC-474-15: Timestamp preservation
-- =============================================================================

DO $$
DECLARE
    v_bad integer;
BEGIN
    SELECT COUNT(*) INTO v_bad
    FROM comms_items c
    JOIN pre_fold_state p
      ON c.platform = p.platform
     AND c.item_id = p.mention_id
    WHERE c.first_seen_at <> p.created_at;

    RAISE NOTICE '%', _test('TC-474-15: created_at preserved as first_seen_at', v_bad = 0);

    RAISE NOTICE '%', _test('TC-474-15: explicit timestamp 2026-07-02 13:07:36.499202+00 preserved',
        EXISTS (
            SELECT 1 FROM comms_items
            WHERE platform = 'nostr'
              AND item_id = '012df11780b4d7d39c409e2b4aceebff3edebdd8aa6906004ce3f9375d3d5d21'
              AND first_seen_at = '2026-07-02 13:07:36.499202+00'
        ));
END $$;

-- =============================================================================
-- TC-474-16: Outbound-only rows are NOT migrated
-- =============================================================================

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM comms_items
    WHERE platform = 'x' AND item_id = '2080000000000000000';

    RAISE NOTICE '%', _test('TC-474-16: outbound NOVA_Openclaw row excluded from fold', v_count = 0);
END $$;

-- =============================================================================
-- Final summary report
-- =============================================================================

SELECT _test('Final: comms_items row count', COUNT(*) = 11) AS result
FROM comms_items;

SELECT _test('Final: social_interactions was dropped', NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'social_interactions'
)) AS result;
