-- Migration: Create merge_facts() function and dedup support
-- Issue: #192

-- merge_facts(survivor_id, absorbed_id) merges two entity_facts rows.
-- Rules:
--   - extraction_count = survivor.extraction_count + absorbed.extraction_count
--   - last_confirmed_at = MAX(survivor.last_confirmed_at, absorbed.last_confirmed_at)
--   - confidence        = MAX(survivor.confidence, absorbed.confidence)
--   - entity_fact_sources rows are merged (attribution_count summed for shared sources)
--   - absorbed row is deleted
--   - Returns the merged survivor row

CREATE OR REPLACE FUNCTION merge_facts(
    survivor_id INTEGER,
    absorbed_id INTEGER
)
RETURNS entity_facts
LANGUAGE plpgsql
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
