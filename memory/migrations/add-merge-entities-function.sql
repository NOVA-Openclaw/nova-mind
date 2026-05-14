-- Migration: add merge_entities() function for entity deduplication
-- Absorbs one entity into another, transferring all FK references and facts

CREATE OR REPLACE FUNCTION merge_entities(survivor_id INTEGER, absorbed_id INTEGER)
RETURNS entities AS $$
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
$$ LANGUAGE plpgsql;
