#!/bin/bash
# store-memories.sh - Store extracted memories into PostgreSQL database
# Takes JSON from extract-memories.sh and inserts into nova_memory database
# Includes deduplication checks to avoid storing redundant information

set -e

# Load OpenClaw environment (API keys from openclaw.json)
ENV_LOADER="${HOME}/.openclaw/lib/env-loader.sh"
[ -f "$ENV_LOADER" ] && source "$ENV_LOADER" && load_openclaw_env

# Load centralized PostgreSQL configuration
PG_ENV="${HOME}/.openclaw/lib/pg-env.sh"
[ -f "$PG_ENV" ] && source "$PG_ENV" && load_pg_env

# Read JSON from stdin or argument
if [ -n "$1" ]; then
    JSON_DATA="$1"
else
    JSON_DATA=$(cat)
fi

if [ -z "$JSON_DATA" ] || [ "$JSON_DATA" = "null" ] || [ "$JSON_DATA" = "{}" ]; then
    echo "No data to store" >&2
    exit 0
fi

# Validate JSON
if ! echo "$JSON_DATA" | jq . >/dev/null 2>&1; then
    echo "Invalid JSON input" >&2
    exit 1
fi


# Function to safely escape SQL strings
sql_escape() {
    echo "$1" | sed "s/'/''/g"
}

# Function to check if a fact already exists (fuzzy match)
fact_exists() {
    local entity_name="$1"
    local key="$2"
    local value="$3"
    
    # Check for exact or similar match
    local count=$(psql -t -A -c "
        SELECT COUNT(*) FROM entity_facts ef
        JOIN entities e ON e.id = ef.entity_id
        WHERE (LOWER(e.name) = LOWER('$(sql_escape "$entity_name")')
               OR LOWER(e.full_name) = LOWER('$(sql_escape "$entity_name")')
               OR LOWER('$(sql_escape "$entity_name")') = ANY(SELECT LOWER(unnest(e.nicknames))))
          AND LOWER(ef.key) = LOWER('$(sql_escape "$key")')
          AND (LOWER(ef.value) = LOWER('$(sql_escape "$value")')
               OR ef.value ILIKE '%$(sql_escape "$value")%'
               OR '$(sql_escape "$value")' ILIKE '%' || ef.value || '%');
    " 2>/dev/null || echo "0")
    
    [ "$count" -gt 0 ]
}

# Function to reinforce existing fact (increment vote_count, update last_confirmed)
reinforce_fact() {
    local entity_name="$1"
    local key="$2"
    local value="$3"
    
    psql -t -A -c "
        UPDATE entity_facts ef
        SET vote_count = vote_count + 1,
            last_confirmed = NOW(),
            confirmation_count = COALESCE(confirmation_count, 0) + 1,
            updated_at = NOW()
        FROM entities e
        WHERE ef.entity_id = e.id
          AND (LOWER(e.name) = LOWER('$(sql_escape "$entity_name")')
               OR LOWER(e.full_name) = LOWER('$(sql_escape "$entity_name")')
               OR LOWER('$(sql_escape "$entity_name")') = ANY(SELECT LOWER(unnest(e.nicknames))))
          AND LOWER(ef.key) = LOWER('$(sql_escape "$key")')
          AND (LOWER(ef.value) = LOWER('$(sql_escape "$value")')
               OR ef.value ILIKE '%$(sql_escape "$value")%'
               OR '$(sql_escape "$value")' ILIKE '%' || ef.value || '%');
    " 2>/dev/null >/dev/null
}

# Function to check if vocabulary word exists
vocab_exists() {
    local word="$1"
    local count=$(psql -t -A -c "
        SELECT COUNT(*) FROM vocabulary WHERE LOWER(word) = LOWER('$(sql_escape "$word")');
    " 2>/dev/null || echo "0")
    
    [ "$count" -gt 0 ]
}

# Function to resolve source name to entity ID
resolve_source_entity_id() {
    local source_name="$1"
    local sender_id="${SENDER_ID:-}"
    
    if [ -z "$source_name" ] || [ "$source_name" = "null" ] || [ "$source_name" = "unknown" ]; then
        echo ""
        return
    fi
    
    # First try matching by sender_id (phone number) in entity_facts
    if [ -n "$sender_id" ] && [ "$sender_id" != "unknown" ]; then
        local id_match=$(psql -t -A -c "
            SELECT DISTINCT entity_id FROM entity_facts 
            WHERE (key IN ('phone', 'has_phone_number', 'signal', 'signal_id') 
                   AND REPLACE(REPLACE(value, '-', ''), ' ', '') LIKE '%$(echo "$sender_id" | tr -d '+-  ')%')
            LIMIT 1;
        " 2>/dev/null | head -1)
        
        if [ -n "$id_match" ]; then
            echo "$id_match"
            return
        fi
    fi
    
    # Fall back to name/nickname matching
    psql -t -A -c "
        SELECT id FROM entities 
        WHERE LOWER(name) = LOWER('$(sql_escape "$source_name")')
           OR LOWER(full_name) = LOWER('$(sql_escape "$source_name")')
           OR LOWER('$(sql_escape "$source_name")') = ANY(SELECT LOWER(unnest(nicknames)))
        LIMIT 1;
    " 2>/dev/null | head -1
}

# Function to find existing entity by name or nickname
find_entity() {
    local search_name="$1"
    psql -t -A -c "
        SELECT name FROM entities 
        WHERE LOWER(name) = LOWER('$(sql_escape "$search_name")')
           OR LOWER(full_name) = LOWER('$(sql_escape "$search_name")')
           OR LOWER(name) LIKE LOWER('$(sql_escape "$search_name")') || ' %'
           OR LOWER(name) LIKE '% ' || LOWER('$(sql_escape "$search_name")')
           OR LOWER(name) LIKE '% ' || LOWER('$(sql_escape "$search_name")') || ' %'
           OR LOWER(full_name) LIKE LOWER('$(sql_escape "$search_name")') || ' %'
           OR LOWER(full_name) LIKE '% ' || LOWER('$(sql_escape "$search_name")')
           OR LOWER(full_name) LIKE '% ' || LOWER('$(sql_escape "$search_name")') || ' %'
           OR LOWER('$(sql_escape "$search_name")') = ANY(SELECT LOWER(unnest(nicknames)))
        LIMIT 1;
    " 2>/dev/null | head -1
}

STORED_COUNT=0
SKIPPED_COUNT=0

# Create entity for unknown sender (#38)
if [ -n "$SENDER_NAME" ] && [ "$SENDER_NAME" != "null" ] && [ "$SENDER_NAME" != "unknown" ]; then
    existing=$(find_entity "$SENDER_NAME")
    if [ -z "$existing" ]; then
        psql -q -c "
            INSERT INTO entities (name, type) VALUES ('$(sql_escape "$SENDER_NAME")', 'person')
            ON CONFLICT DO NOTHING;
        " 2>/dev/null
        # Store phone number as fact if available
        if [ -n "$SENDER_ID" ] && [ "$SENDER_ID" != "unknown" ]; then
            psql -q -c "
                INSERT INTO entity_facts (entity_id, key, value, source)
                SELECT id, 'phone', '$(sql_escape "$SENDER_ID")', 'auto-extracted'
                FROM entities WHERE LOWER(name) = LOWER('$(sql_escape "$SENDER_NAME")')
                ON CONFLICT DO NOTHING;
            " 2>/dev/null
        fi
        echo "  + Entity (auto-created): $SENDER_NAME"
    fi
fi

# Process entities
echo "$JSON_DATA" | jq -c '.entities[]? // empty' | while read -r entity; do
    name=$(echo "$entity" | jq -r '.name')
    type=$(echo "$entity" | jq -r '.type // "other"')
    location=$(echo "$entity" | jq -r '.location // empty')
    
    case "$type" in
        restaurant|cafe|bar|venue) 
            existing=$(psql -t -A -c "SELECT name FROM places WHERE LOWER(name) = LOWER('$(sql_escape "$name")') LIMIT 1;" 2>/dev/null)
            if [ -z "$existing" ]; then
                echo "INSERT INTO places (name, type, city) VALUES ('$(sql_escape "$name")', 'venue', '$(sql_escape "$location")') ON CONFLICT DO NOTHING;" | psql -q 2>/dev/null || true
                echo "  + Place: $name (new)"
            else
                echo "  = Place: $name (exists)"
            fi
            ;;
        person|ai|organization)
            existing=$(find_entity "$name")
            if [ -z "$existing" ]; then
                echo "INSERT INTO entities (name, type) VALUES ('$(sql_escape "$name")', '$type') ON CONFLICT DO NOTHING;" | psql -q 2>/dev/null || true
                echo "  + Entity: $name ($type) (new)"
            else
                echo "  = Entity: $name -> exists as: $existing"
            fi
            ;;
    esac
done

# Process facts with deduplication
echo "$JSON_DATA" | jq -c '.facts[]? // empty' | while read -r fact; do
    subject=$(echo "$fact" | jq -r '.subject')
    predicate=$(echo "$fact" | jq -r '.predicate')
    value=$(echo "$fact" | jq -r '.value')
    source_person=$(echo "$fact" | jq -r '.source_person // "auto-extracted"')
    visibility=$(echo "$fact" | jq -r '.visibility // "public"')
    visibility_reason=$(echo "$fact" | jq -r '.visibility_reason // empty')
    source_entity_id=$(resolve_source_entity_id "$source_person")
    
    actual_subject=$(find_entity "$subject")
    [ -z "$actual_subject" ] && actual_subject="$subject"
    
    # Check for duplicate and reinforce if exists
    if fact_exists "$actual_subject" "$predicate" "$value"; then
        reinforce_fact "$actual_subject" "$predicate" "$value"
        echo "  ✓ Fact reinforced: $actual_subject.$predicate = $value (vote_count++)"
        continue
    fi
    
    cols="entity_id, key, value, source, visibility"
    vals="id, '$(sql_escape "$predicate")', '$(sql_escape "$value")', '$(sql_escape "$source_person")', '$(sql_escape "$visibility")'"
    
    [ -n "$source_entity_id" ] && cols="$cols, source_entity_id" && vals="$vals, $source_entity_id"
    [ -n "$visibility_reason" ] && cols="$cols, visibility_reason" && vals="$vals, '$(sql_escape "$visibility_reason")'"
    
    echo "INSERT INTO entity_facts ($cols) SELECT $vals
          FROM entities WHERE name = '$(sql_escape "$actual_subject")'
          ON CONFLICT DO NOTHING;" | psql -q 2>/dev/null || true
    echo "  + Fact: $actual_subject.$predicate = $value"
done

# Process opinions with deduplication
echo "$JSON_DATA" | jq -c '.opinions[]? // empty' | while read -r opinion; do
    holder=$(echo "$opinion" | jq -r '.holder')
    subject=$(echo "$opinion" | jq -r '.subject')
    opinion_text=$(echo "$opinion" | jq -r '.opinion')
    source_person=$(echo "$opinion" | jq -r '.source_person // "auto-extracted"')
    visibility=$(echo "$opinion" | jq -r '.visibility // "public"')
    visibility_reason=$(echo "$opinion" | jq -r '.visibility_reason // empty')
    source_entity_id=$(resolve_source_entity_id "$source_person")
    
    actual_holder=$(find_entity "$holder")
    [ -z "$actual_holder" ] && actual_holder="$holder"
    
    key="opinion_$subject"
    
    # Check for duplicate and reinforce if exists
    if fact_exists "$actual_holder" "$key" "$opinion_text"; then
        reinforce_fact "$actual_holder" "$key" "$opinion_text"
        echo "  ✓ Opinion reinforced: $actual_holder on $subject (vote_count++)"
        continue
    fi
    
    cols="entity_id, key, value, source, visibility"
    vals="id, '$(sql_escape "$key")', '$(sql_escape "$opinion_text")', '$(sql_escape "$source_person")', '$(sql_escape "$visibility")'"
    
    [ -n "$source_entity_id" ] && cols="$cols, source_entity_id" && vals="$vals, $source_entity_id"
    [ -n "$visibility_reason" ] && cols="$cols, visibility_reason" && vals="$vals, '$(sql_escape "$visibility_reason")'"
    
    echo "INSERT INTO entity_facts ($cols) SELECT $vals
          FROM entities WHERE name = '$(sql_escape "$actual_holder")'
          ON CONFLICT DO NOTHING;" | psql -q 2>/dev/null || true
    echo "  + Opinion: $actual_holder thinks '$opinion_text' about $subject"
done

# Process preferences with deduplication
echo "$JSON_DATA" | jq -c '.preferences[]? // empty' | while read -r pref; do
    person=$(echo "$pref" | jq -r '.person // .holder')
    preference=$(echo "$pref" | jq -r '.preference // .likes // .prefers')
    category=$(echo "$pref" | jq -r '.category // "general"')
    source_person=$(echo "$pref" | jq -r '.source_person // "auto-extracted"')
    visibility=$(echo "$pref" | jq -r '.visibility // "public"')
    visibility_reason=$(echo "$pref" | jq -r '.visibility_reason // empty')
    source_entity_id=$(resolve_source_entity_id "$source_person")
    
    actual_person=$(find_entity "$person")
    [ -z "$actual_person" ] && actual_person="$person"
    
    key="preference_$category"
    
    # Check for duplicate and reinforce if exists
    if fact_exists "$actual_person" "$key" "$preference"; then
        reinforce_fact "$actual_person" "$key" "$preference"
        echo "  ✓ Preference reinforced: $actual_person prefers $preference (vote_count++)"
        continue
    fi
    
    cols="entity_id, key, value, source, visibility"
    vals="id, '$(sql_escape "$key")', '$(sql_escape "$preference")', '$(sql_escape "$source_person")', '$(sql_escape "$visibility")'"
    
    [ -n "$source_entity_id" ] && cols="$cols, source_entity_id" && vals="$vals, $source_entity_id"
    [ -n "$visibility_reason" ] && cols="$cols, visibility_reason" && vals="$vals, '$(sql_escape "$visibility_reason")'"
    
    echo "INSERT INTO entity_facts ($cols) SELECT $vals
          FROM entities WHERE name = '$(sql_escape "$actual_person")'
          ON CONFLICT DO NOTHING;" | psql -q 2>/dev/null || true
    echo "  + Preference: $actual_person prefers $preference"
done

# Process vocabulary with deduplication
echo "$JSON_DATA" | jq -c '.vocabulary[]? // empty' | while read -r vocab; do
    word=$(echo "$vocab" | jq -r '.word')
    category=$(echo "$vocab" | jq -r '.category // "custom"')
    misheard_raw=$(echo "$vocab" | jq -r '.misheard_as // [] | @json')
    
    # Check for duplicate
    if vocab_exists "$word"; then
        echo "  ~ Vocabulary (duplicate, skipped): $word"
        continue
    fi
    
    misheard_pg=$(echo "$misheard_raw" | jq -r 'if type == "array" and length > 0 then "ARRAY[" + (map("'\''" + . + "'\''") | join(",")) + "]" else "NULL" end')
    
    if [ "$misheard_pg" != "NULL" ] && [ -n "$misheard_pg" ]; then
        echo "INSERT INTO vocabulary (word, category, misheard_as) VALUES ('$(sql_escape "$word")', '$(sql_escape "$category")', $misheard_pg) ON CONFLICT (word) DO UPDATE SET misheard_as = EXCLUDED.misheard_as;" | psql -q 2>/dev/null || true
    else
        echo "INSERT INTO vocabulary (word, category) VALUES ('$(sql_escape "$word")', '$(sql_escape "$category")') ON CONFLICT (word) DO NOTHING;" | psql -q 2>/dev/null || true
    fi
    
    echo "  + Vocabulary (NEW): $word ($category)"
    echo "1" >> /tmp/vocab_added_flag
done

# Restart STT service if new vocabulary was added
if [ -f /tmp/vocab_added_flag ]; then
    NEW_COUNT=$(wc -l < /tmp/vocab_added_flag)
    rm -f /tmp/vocab_added_flag
    echo "  >> Restarting STT service to load $NEW_COUNT new vocabulary word(s)..."
    systemctl --user restart nova-stt-ws 2>/dev/null || true
fi

echo "Memory storage complete."
