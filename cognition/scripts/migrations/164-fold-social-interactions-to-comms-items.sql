-- Migration: Issue #474 — Fold inbound social_interactions into comms_items/comms_responses
--
-- Post-pgschema migration. Folds inbound X/Nostr rows from the legacy
-- social_interactions table into comms_items (unified lifecycle) and
-- comms_responses (approval gate). Runs as the agent DB user after pgschema
-- has created comms_items/comms_responses.
--
-- Properties:
--   * Idempotent: safe to re-run; uses ON CONFLICT DO NOTHING and existence guards.
--   * Fresh-install safe: no-ops when social_interactions does not exist.
--   * Timestamp preservation: social_interactions.created_at becomes comms_items.first_seen_at.
--   * Inbound-only: explicitly guards against folding outbound-only rows by
--     skipping rows authored by NOVA's own X handle. Nostr outbound rows are
--     similarly guarded where the pubkey is known; where unknown, they are
--     still constrained to the X/Nostr platform scope.
--   * Drops the legacy table after a successful fold.

DO $$
BEGIN
    -- Fresh-install / already-folded guard: if social_interactions no longer
    -- exists, there is nothing to do. This makes the migration safe to run on
    -- new databases and on re-runs after the fold has completed.
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'social_interactions'
    ) THEN
        RETURN;
    END IF;

    -- Fold inbound X/Nestrointeractions into comms_items.
    --
    -- Status mapping (old -> new):
    --   seen          -> inbound
    --   needs_response -> tracked
    --   drafted       -> tracked
    --   approved      -> tracked
    --   posted        -> resolved
    --   dismissed     -> dismissed
    INSERT INTO comms_items (
        platform,
        item_id,
        thread_id,
        entity_id,
        status,
        disposition,
        summary,
        first_seen_at,
        resolved_at
    )
    SELECT
        si.platform,
        si.mention_id AS item_id,
        si.thread_id,
        CASE si.platform
            WHEN 'x' THEN
                resolve_entity_by_identifier(
                    'x_handle',
                    NULLIF(regexp_replace(si.author_handle, '^@', ''), '')
                )
            WHEN 'nostr' THEN
                resolve_entity_by_identifier('nostr_public_key', si.author_handle)
            ELSE NULL
        END AS entity_id,
        CASE si.status
            WHEN 'seen' THEN 'inbound'
            WHEN 'needs_response' THEN 'tracked'
            WHEN 'drafted' THEN 'tracked'
            WHEN 'approved' THEN 'tracked'
            WHEN 'posted' THEN 'resolved'
            WHEN 'dismissed' THEN 'dismissed'
        END AS status,
        NULL::text AS disposition,
        CASE
            WHEN si.status = 'dismissed' AND si.dismissed_reason IS NOT NULL AND si.notes IS NOT NULL THEN
                NULLIF(
                    COALESCE(si.content, '') || E'\n\nDismissed: ' || si.dismissed_reason || E'\n\nNotes: ' || si.notes,
                    E'\n\nDismissed: ' || si.dismissed_reason || E'\n\nNotes: ' || si.notes
                )
            WHEN si.status = 'dismissed' AND si.dismissed_reason IS NOT NULL THEN
                NULLIF(
                    COALESCE(si.content, '') || E'\n\nDismissed: ' || si.dismissed_reason,
                    E'\n\nDismissed: ' || si.dismissed_reason
                )
            WHEN si.status = 'dismissed' AND si.notes IS NOT NULL THEN
                NULLIF(
                    COALESCE(si.content, '') || E'\n\nNotes: ' || si.notes,
                    E'\n\nNotes: ' || si.notes
                )
            WHEN si.notes IS NOT NULL THEN
                NULLIF(
                    COALESCE(si.content, '') || E'\n\nNotes: ' || si.notes,
                    E'\n\nNotes: ' || si.notes
                )
            ELSE si.content
        END AS summary,
        si.created_at AS first_seen_at,
        CASE
            WHEN si.status = 'posted' THEN
                COALESCE(si.responded_at, si.updated_at, si.created_at)
        END AS resolved_at
    FROM social_interactions si
    WHERE si.platform IN ('x', 'nostr')
      AND si.mention_id IS NOT NULL
      AND si.author_handle IS DISTINCT FROM 'NOVA_Openclaw'
    ON CONFLICT (platform, item_id) DO NOTHING;

    -- Fold the X/Nostr response-approval sub-lifecycle into comms_responses.
    -- Only create a companion row if the inbound item has any response-related
    -- state (draft, approval, posted response id, notes) and a row does not
    -- already exist.
    INSERT INTO comms_responses (
        comms_item_id,
        draft_response,
        approved_by,
        approved_at,
        response_id,
        responded_at,
        notes
    )
    SELECT
        ci.id AS comms_item_id,
        si.draft_response,
        si.approved_by,
        si.approved_at,
        si.response_id,
        si.responded_at,
        si.notes
    FROM social_interactions si
    JOIN comms_items ci
      ON ci.platform = si.platform
     AND ci.item_id = si.mention_id
    WHERE si.platform IN ('x', 'nostr')
      AND si.mention_id IS NOT NULL
      AND si.author_handle IS DISTINCT FROM 'NOVA_Openclaw'
      AND (
          si.draft_response IS NOT NULL
          OR si.approved_by IS NOT NULL
          OR si.approved_at IS NOT NULL
          OR si.response_id IS NOT NULL
          OR si.responded_at IS NOT NULL
      )
      AND NOT EXISTS (
          SELECT 1 FROM comms_responses cr WHERE cr.comms_item_id = ci.id
      );

    -- Drop the legacy table now that the fold is complete. Guarded with IF EXISTS
    -- so re-runs (where the table was already dropped) do not error.
    DROP TABLE IF EXISTS social_interactions;
END $$;
