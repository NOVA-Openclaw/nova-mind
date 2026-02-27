#!/usr/bin/env python3
"""
Store relations in memory database.
Reads JSON from stdin, writes to entity_facts and entity_relationships.

Implements source authority rules (Issue #43):
- Facts from authority entities (e.g., I)ruid, entity_id=2) are marked as 'permanent'
- Authority facts override conflicts and are never questioned
- Authority entity is configurable via AUTHORITY_ENTITY_ID env var

Usage:
    extract_cli.py "message" | store_relations.py
"""

import sys
import json
import os
import subprocess
from typing import List, Dict, Optional, Tuple


def sql_escape(text: str) -> str:
    """Escape single quotes for SQL."""
    return text.replace("'", "''")


def run_sql(sql: str, db_user: str, db_name: str) -> Optional[str]:
    """Execute SQL and return result."""
    try:
        result = subprocess.run(
            ["psql", "-h", "localhost", "-U", db_user, "-d", db_name, "-t", "-A", "-c", sql],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
        else:
            print(f"SQL error: {result.stderr}", file=sys.stderr)
            return None
    except Exception as e:
        print(f"Error running SQL: {e}", file=sys.stderr)
        return None


def find_entity(name: str, db_user: str, db_name: str) -> Optional[str]:
    """Find existing entity by name or nickname."""
    sql = f"""
        SELECT name FROM entities 
        WHERE LOWER(name) = LOWER('{sql_escape(name)}')
           OR LOWER(full_name) = LOWER('{sql_escape(name)}')
           OR LOWER('{sql_escape(name)}') = ANY(SELECT LOWER(unnest(nicknames)))
        LIMIT 1;
    """
    return run_sql(sql, db_user, db_name)


def find_entity_id(name: str, db_user: str, db_name: str) -> Optional[int]:
    """Find entity ID by name or nickname."""
    sql = f"""
        SELECT id FROM entities 
        WHERE LOWER(name) = LOWER('{sql_escape(name)}')
           OR LOWER(full_name) = LOWER('{sql_escape(name)}')
           OR LOWER('{sql_escape(name)}') = ANY(SELECT LOWER(unnest(nicknames)))
        LIMIT 1;
    """
    result = run_sql(sql, db_user, db_name)
    return int(result) if result and result.isdigit() else None


def is_authority_entity(entity_id: Optional[int], authority_entity_id: int) -> bool:
    """Check if an entity is the authority entity."""
    return entity_id is not None and entity_id == authority_entity_id


def get_existing_fact(entity_name: str, key: str, db_user: str, db_name: str) -> Optional[Tuple[int, str, str, int, float]]:
    """
    Get existing fact details for conflict resolution.
    Returns: (fact_id, current_value, data_type, source_entity_id, confidence) or None
    """
    sql = f"""
        SELECT ef.id, ef.value, ef.data_type, ef.source_entity_id, ef.confidence
        FROM entity_facts ef
        JOIN entities e ON e.id = ef.entity_id
        WHERE (LOWER(e.name) = LOWER('{sql_escape(entity_name)}')
               OR LOWER(e.full_name) = LOWER('{sql_escape(entity_name)}')
               OR LOWER('{sql_escape(entity_name)}') = ANY(SELECT LOWER(unnest(e.nicknames))))
          AND LOWER(ef.key) = LOWER('{sql_escape(key)}')
        LIMIT 1;
    """
    result = run_sql(sql, db_user, db_name)
    if result:
        parts = result.split('|')
        if len(parts) >= 5:
            return (
                int(parts[0]),
                parts[1],
                parts[2],
                int(parts[3]) if parts[3] and parts[3] != '' else None,
                float(parts[4]) if parts[4] else 1.0
            )
    return None


def ensure_entity_exists(name: str, entity_type: str, db_user: str, db_name: str):
    """Create entity if it doesn't exist."""
    existing = find_entity(name, db_user, db_name)
    if not existing:
        sql = f"INSERT INTO entities (name, type) VALUES ('{sql_escape(name)}', '{entity_type}') ON CONFLICT DO NOTHING;"
        run_sql(sql, db_user, db_name)


def fact_exists(entity_name: str, key: str, value: str, db_user: str, db_name: str) -> bool:
    """Check if a fact already exists (fuzzy match)."""
    sql = f"""
        SELECT COUNT(*) FROM entity_facts ef
        JOIN entities e ON e.id = ef.entity_id
        WHERE (LOWER(e.name) = LOWER('{sql_escape(entity_name)}')
               OR LOWER(e.full_name) = LOWER('{sql_escape(entity_name)}')
               OR LOWER('{sql_escape(entity_name)}') = ANY(SELECT LOWER(unnest(e.nicknames))))
          AND LOWER(ef.key) = LOWER('{sql_escape(key)}')
          AND (LOWER(ef.value) = LOWER('{sql_escape(value)}')
               OR ef.value ILIKE '%{sql_escape(value)}%'
               OR '{sql_escape(value)}' ILIKE '%' || ef.value || '%');
    """
    result = run_sql(sql, db_user, db_name)
    return result and int(result) > 0


def store_relation(relation: Dict, db_user: str, db_name: str, source_person: str = "grammar-parser", authority_entity_id: int = 2):
    """
    Store a single relation in the database with source authority support.
    
    Authority rules (Issue #43):
    - Facts from authority entity are data_type='permanent' with confidence=1.0
    - Authority facts override conflicting facts from other sources
    - Non-authority sources cannot override authority facts
    """
    
    rel_type = relation["relation_type"]
    subject = relation["subject"]
    obj = relation.get("object", "")
    predicate = relation["predicate"]
    confidence = relation["confidence"]
    
    # Determine source entity ID
    source_entity_id = find_entity_id(source_person, db_user, db_name)
    is_authority = is_authority_entity(source_entity_id, authority_entity_id)
    
    # Authority facts always have confidence=1.0 and data_type='permanent'
    if is_authority:
        confidence = 1.0
        data_type = 'permanent'
        print(f"  [AUTHORITY] Source is authority entity (id={source_entity_id}), setting permanent", file=sys.stderr)
    else:
        data_type = 'observation'
    
    # Skip low-confidence relations (but never skip authority facts)
    if not is_authority and confidence < 0.6:
        print(f"  ~ Skipping low-confidence: {subject} --{predicate}--> {obj} (confidence: {confidence:.2f})", file=sys.stderr)
        return
    
    # Ensure subject entity exists
    ensure_entity_exists(subject, "person", db_user, db_name)
    
    # Ensure object entity exists for relationship types
    if obj and rel_type in ["family", "romantic", "social", "professional"]:
        ensure_entity_exists(obj, "person", db_user, db_name)
    
    # Map relation types to database storage
    
    if rel_type in ["family", "romantic", "social", "professional"]:
        # Store in entity_relationships table
        is_symmetric = relation.get("is_symmetric", False)
        subtype = relation.get("subtype", predicate)
        
        # Check if relationship already exists
        sql = f"""
            SELECT COUNT(*) FROM entity_relationships er
            JOIN entities e1 ON er.entity_a = e1.id
            JOIN entities e2 ON er.entity_b = e2.id
            WHERE (LOWER(e1.name) = LOWER('{sql_escape(subject)}') 
                   AND LOWER(e2.name) = LOWER('{sql_escape(obj)}'))
               OR ('{is_symmetric}' = 'True' AND LOWER(e1.name) = LOWER('{sql_escape(obj)}') 
                   AND LOWER(e2.name) = LOWER('{sql_escape(subject)}'));
        """
        result = run_sql(sql, db_user, db_name)
        
        if result and int(result) > 0:
            print(f"  ~ Relationship (duplicate, skipped): {subject} --{subtype}--> {obj}", file=sys.stderr)
        else:
            # Insert relationship
            sql = f"""
                INSERT INTO entity_relationships (entity_a, entity_b, relationship, is_symmetric, source)
                SELECT e1.id, e2.id, '{sql_escape(subtype)}', {is_symmetric}, '{sql_escape(source_person)}'
                FROM entities e1, entities e2
                WHERE LOWER(e1.name) = LOWER('{sql_escape(subject)}')
                  AND LOWER(e2.name) = LOWER('{sql_escape(obj)}')
                ON CONFLICT DO NOTHING;
            """
            run_sql(sql, db_user, db_name)
            print(f"  + Relationship: {subject} --{subtype}--> {obj} (confidence: {confidence:.2f})", file=sys.stderr)
    
    elif rel_type in ["attribute", "preference", "opinion"]:
        # Store in entity_facts table with authority logic
        key = predicate if rel_type == "attribute" else f"{rel_type}_{predicate}"
        
        # Check for existing fact
        existing = get_existing_fact(subject, key, db_user, db_name)
        
        if existing:
            fact_id, current_value, current_data_type, current_source_id, current_confidence = existing
            current_is_authority = is_authority_entity(current_source_id, authority_entity_id)
            
            # Case 1: Values match - increment vote_count, update last_confirmed
            if current_value.lower() == obj.lower():
                sql = f"""
                    UPDATE entity_facts 
                    SET vote_count = vote_count + 1,
                        last_confirmed = NOW(),
                        confirmation_count = confirmation_count + 1
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ✓ Fact confirmed: {subject}.{key} = {obj} (vote_count++)", file=sys.stderr)
            
            # Case 2: Conflict - authority source wins
            elif is_authority:
                # Authority overrides existing fact
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = 1.0,
                        data_type = 'permanent',
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id},
                        updated_at = NOW(),
                        vote_count = 1,
                        confirmation_count = 1
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ⚡ AUTHORITY UPDATE: {subject}.{key}: '{current_value}' → '{obj}' (authority override)", file=sys.stderr)
                
                # Log the conflict
                log_sql = f"""
                    INSERT INTO fact_change_log (fact_id, old_value, new_value, changed_by_entity_id, reason)
                    VALUES ({fact_id}, '{sql_escape(current_value)}', '{sql_escape(obj)}', {source_entity_id}, 'authority_override');
                """
                run_sql(log_sql, db_user, db_name)
            
            elif current_is_authority:
                # Cannot override authority fact with non-authority source
                print(f"  ✗ Conflict rejected: {subject}.{key} - existing authority fact prevents update ('{current_value}' vs '{obj}')", file=sys.stderr)
            
            else:
                # Both non-authority: update if new confidence is higher
                if confidence > current_confidence:
                    sql = f"""
                        UPDATE entity_facts 
                        SET value = '{sql_escape(obj)}',
                            confidence = {confidence},
                            source = '{sql_escape(source_person)}',
                            source_entity_id = {source_entity_id if source_entity_id else 'NULL'},
                            updated_at = NOW(),
                            vote_count = 1
                        WHERE id = {fact_id};
                    """
                    run_sql(sql, db_user, db_name)
                    print(f"  ↻ Fact updated: {subject}.{key}: '{current_value}' → '{obj}' (higher confidence: {confidence:.2f} > {current_confidence:.2f})", file=sys.stderr)
                else:
                    print(f"  ~ Conflict (lower confidence): {subject}.{key} - kept '{current_value}', rejected '{obj}' ({confidence:.2f} ≤ {current_confidence:.2f})", file=sys.stderr)
        
        else:
            # New fact - insert with appropriate data_type
            sql = f"""
                INSERT INTO entity_facts (entity_id, key, value, source, source_entity_id, confidence, data_type, visibility, vote_count, confirmation_count)
                SELECT id, '{sql_escape(key)}', '{sql_escape(obj)}', '{sql_escape(source_person)}', 
                       {source_entity_id if source_entity_id else 'NULL'}, 
                       {confidence}, '{data_type}', 'public', 1, 1
                FROM entities WHERE LOWER(name) = LOWER('{sql_escape(subject)}')
                ON CONFLICT DO NOTHING;
            """
            run_sql(sql, db_user, db_name)
            authority_marker = " [PERMANENT]" if is_authority else ""
            print(f"  + Fact: {subject}.{key} = {obj} (confidence: {confidence:.2f}, data_type: {data_type}){authority_marker}", file=sys.stderr)
    
    elif rel_type in ["location", "residence", "origin"]:
        # Store as entity fact (location) with authority logic
        key = rel_type
        
        existing = get_existing_fact(subject, key, db_user, db_name)
        
        if existing:
            fact_id, current_value, current_data_type, current_source_id, current_confidence = existing
            current_is_authority = is_authority_entity(current_source_id, authority_entity_id)
            
            if current_value.lower() == obj.lower():
                sql = f"""
                    UPDATE entity_facts 
                    SET vote_count = vote_count + 1,
                        last_confirmed = NOW(),
                        confirmation_count = confirmation_count + 1
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ✓ Location confirmed: {subject} @ {obj}", file=sys.stderr)
            elif is_authority:
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = 1.0,
                        data_type = 'permanent',
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id},
                        updated_at = NOW()
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ⚡ AUTHORITY UPDATE: {subject} location: '{current_value}' → '{obj}'", file=sys.stderr)
            elif current_is_authority:
                print(f"  ✗ Conflict rejected: {subject} location - authority fact prevents update", file=sys.stderr)
            elif confidence > current_confidence:
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = {confidence},
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id if source_entity_id else 'NULL'},
                        updated_at = NOW()
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ↻ Location updated: {subject} @ '{obj}' (confidence: {confidence:.2f})", file=sys.stderr)
        else:
            sql = f"""
                INSERT INTO entity_facts (entity_id, key, value, source, source_entity_id, confidence, data_type, visibility)
                SELECT id, '{sql_escape(key)}', '{sql_escape(obj)}', '{sql_escape(source_person)}', 
                       {source_entity_id if source_entity_id else 'NULL'}, 
                       {confidence}, '{data_type}', 'public'
                FROM entities WHERE LOWER(name) = LOWER('{sql_escape(subject)}')
                ON CONFLICT DO NOTHING;
            """
            run_sql(sql, db_user, db_name)
            authority_marker = " [PERMANENT]" if is_authority else ""
            print(f"  + Location: {subject} @ {obj} (confidence: {confidence:.2f}){authority_marker}", file=sys.stderr)
    
    elif rel_type in ["employment", "education"]:
        # Store as entity fact with authority logic
        key = rel_type
        
        existing = get_existing_fact(subject, key, db_user, db_name)
        
        if existing:
            fact_id, current_value, current_data_type, current_source_id, current_confidence = existing
            current_is_authority = is_authority_entity(current_source_id, authority_entity_id)
            
            if current_value.lower() == obj.lower():
                sql = f"""
                    UPDATE entity_facts 
                    SET vote_count = vote_count + 1,
                        last_confirmed = NOW(),
                        confirmation_count = confirmation_count + 1
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ✓ {rel_type.title()} confirmed: {subject} @ {obj}", file=sys.stderr)
            elif is_authority:
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = 1.0,
                        data_type = 'permanent',
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id},
                        updated_at = NOW()
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ⚡ AUTHORITY UPDATE: {subject} {rel_type}: '{current_value}' → '{obj}'", file=sys.stderr)
            elif current_is_authority:
                print(f"  ✗ Conflict rejected: {subject} {rel_type} - authority fact prevents update", file=sys.stderr)
            elif confidence > current_confidence:
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = {confidence},
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id if source_entity_id else 'NULL'},
                        updated_at = NOW()
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ↻ {rel_type.title()} updated: {subject} @ '{obj}'", file=sys.stderr)
        else:
            sql = f"""
                INSERT INTO entity_facts (entity_id, key, value, source, source_entity_id, confidence, data_type, visibility)
                SELECT id, '{sql_escape(key)}', '{sql_escape(obj)}', '{sql_escape(source_person)}', 
                       {source_entity_id if source_entity_id else 'NULL'}, 
                       {confidence}, '{data_type}', 'public'
                FROM entities WHERE LOWER(name) = LOWER('{sql_escape(subject)}')
                ON CONFLICT DO NOTHING;
            """
            run_sql(sql, db_user, db_name)
            authority_marker = " [PERMANENT]" if is_authority else ""
            print(f"  + {rel_type.title()}: {subject} @ {obj} (confidence: {confidence:.2f}){authority_marker}", file=sys.stderr)
    
    elif rel_type == "possession":
        key = "owns"
        
        existing = get_existing_fact(subject, key, db_user, db_name)
        
        if existing:
            fact_id, current_value, current_data_type, current_source_id, current_confidence = existing
            current_is_authority = is_authority_entity(current_source_id, authority_entity_id)
            
            if current_value.lower() == obj.lower():
                sql = f"""
                    UPDATE entity_facts 
                    SET vote_count = vote_count + 1,
                        last_confirmed = NOW(),
                        confirmation_count = confirmation_count + 1
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ✓ Possession confirmed: {subject} owns {obj}", file=sys.stderr)
            elif is_authority:
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = 1.0,
                        data_type = 'permanent',
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id},
                        updated_at = NOW()
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ⚡ AUTHORITY UPDATE: {subject} possession: '{current_value}' → '{obj}'", file=sys.stderr)
            elif current_is_authority:
                print(f"  ✗ Conflict rejected: {subject} possession - authority fact prevents update", file=sys.stderr)
            elif confidence > current_confidence:
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = {confidence},
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id if source_entity_id else 'NULL'},
                        updated_at = NOW()
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ↻ Possession updated: {subject} owns '{obj}'", file=sys.stderr)
        else:
            sql = f"""
                INSERT INTO entity_facts (entity_id, key, value, source, source_entity_id, confidence, data_type, visibility)
                SELECT id, '{sql_escape(key)}', '{sql_escape(obj)}', '{sql_escape(source_person)}', 
                       {source_entity_id if source_entity_id else 'NULL'}, 
                       {confidence}, '{data_type}', 'public'
                FROM entities WHERE LOWER(name) = LOWER('{sql_escape(subject)}')
                ON CONFLICT DO NOTHING;
            """
            run_sql(sql, db_user, db_name)
            authority_marker = " [PERMANENT]" if is_authority else ""
            print(f"  + Possession: {subject} owns {obj} (confidence: {confidence:.2f}){authority_marker}", file=sys.stderr)
    
    else:
        # Generic storage as fact with authority logic
        key = f"other_{predicate}"
        
        existing = get_existing_fact(subject, key, db_user, db_name)
        
        if existing:
            fact_id, current_value, current_data_type, current_source_id, current_confidence = existing
            current_is_authority = is_authority_entity(current_source_id, authority_entity_id)
            
            if current_value.lower() == obj.lower():
                sql = f"""
                    UPDATE entity_facts 
                    SET vote_count = vote_count + 1,
                        last_confirmed = NOW(),
                        confirmation_count = confirmation_count + 1
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ✓ Other confirmed: {subject} --{predicate}--> {obj}", file=sys.stderr)
            elif is_authority:
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = 1.0,
                        data_type = 'permanent',
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id},
                        updated_at = NOW()
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ⚡ AUTHORITY UPDATE: {subject} --{predicate}--> '{obj}'", file=sys.stderr)
            elif current_is_authority:
                print(f"  ✗ Conflict rejected: {subject} --{predicate}--> - authority fact prevents update", file=sys.stderr)
            elif confidence > current_confidence:
                sql = f"""
                    UPDATE entity_facts 
                    SET value = '{sql_escape(obj)}',
                        confidence = {confidence},
                        source = '{sql_escape(source_person)}',
                        source_entity_id = {source_entity_id if source_entity_id else 'NULL'},
                        updated_at = NOW()
                    WHERE id = {fact_id};
                """
                run_sql(sql, db_user, db_name)
                print(f"  ↻ Other updated: {subject} --{predicate}--> '{obj}'", file=sys.stderr)
        else:
            sql = f"""
                INSERT INTO entity_facts (entity_id, key, value, source, source_entity_id, confidence, data_type, visibility)
                SELECT id, '{sql_escape(key)}', '{sql_escape(obj)}', '{sql_escape(source_person)}', 
                       {source_entity_id if source_entity_id else 'NULL'}, 
                       {confidence}, '{data_type}', 'public'
                FROM entities WHERE LOWER(name) = LOWER('{sql_escape(subject)}')
                ON CONFLICT DO NOTHING;
            """
            run_sql(sql, db_user, db_name)
            authority_marker = " [PERMANENT]" if is_authority else ""
            print(f"  + Other: {subject} --{predicate}--> {obj} (confidence: {confidence:.2f}){authority_marker}", file=sys.stderr)


def ensure_fact_change_log_table(db_user: str, db_name: str):
    """Create fact_change_log table if it doesn't exist."""
    sql = """
        CREATE TABLE IF NOT EXISTS fact_change_log (
            id SERIAL PRIMARY KEY,
            fact_id INTEGER NOT NULL,
            old_value TEXT,
            new_value TEXT,
            changed_by_entity_id INTEGER,
            reason VARCHAR(100),
            changed_at TIMESTAMPTZ DEFAULT NOW()
        );
    """
    run_sql(sql, db_user, db_name)


def main():
    # Database configuration
    db_user = os.environ.get("PGUSER", os.environ.get("USER", "nova"))
    db_name = f"{db_user.replace('-', '_')}_memory"
    source_person = os.environ.get("SENDER_NAME", "grammar-parser")
    
    # Authority entity configuration (Issue #43)
    # Default: entity_id=2 (I)ruid / Dustin Trammell)
    # Can be overridden via AUTHORITY_ENTITY_ID env var
    authority_entity_id = int(os.environ.get("AUTHORITY_ENTITY_ID", "2"))
    
    print(f"Source authority: entity_id={authority_entity_id} (configurable via AUTHORITY_ENTITY_ID)", file=sys.stderr)
    
    # Ensure change log table exists
    ensure_fact_change_log_table(db_user, db_name)
    
    # Read JSON from stdin
    try:
        input_json = sys.stdin.read()
    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        sys.exit(1)
    
    if not input_json.strip():
        print("No relations to store", file=sys.stderr)
        sys.exit(0)
    
    try:
        relations = json.loads(input_json)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    
    if not isinstance(relations, list):
        print("Expected JSON array of relations", file=sys.stderr)
        sys.exit(1)
    
    # Store each relation
    stored_count = 0
    for rel in relations:
        try:
            store_relation(rel, db_user, db_name, source_person, authority_entity_id)
            stored_count += 1
        except Exception as e:
            print(f"Error storing relation: {e}", file=sys.stderr)
    
    print(f"Grammar parser stored {stored_count}/{len(relations)} relation(s)", file=sys.stderr)


if __name__ == "__main__":
    main()
