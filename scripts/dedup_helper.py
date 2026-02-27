#!/usr/bin/env python3
"""
Deduplication Helper - Smart deduplication for memory extractor.

Implements exact and fuzzy matching to prevent duplicate facts, and reinforces
confidence when facts are re-confirmed.
"""

import psycopg2
import os
import sys
from typing import Optional, Dict, Any

# Load OpenClaw environment (API keys from openclaw.json)
sys.path.insert(0, os.path.expanduser('~/.openclaw/lib'))
try:
    from env_loader import load_openclaw_env
    load_openclaw_env()
except ImportError:
    pass  # Library not installed yet

# Load centralized PostgreSQL configuration
sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
from pg_env import load_pg_env
load_pg_env()

from confidence_helper import get_initial_confidence


def get_db_connection():
    """Get database connection using PG* env vars."""
    return psycopg2.connect()


def find_existing_fact(entity_id: int, key: str, new_value: str, conn=None) -> Optional[Dict[str, Any]]:
    """
    Find existing fact that matches or is semantically equivalent.
    
    Args:
        entity_id: Entity ID to check
        key: Fact key
        new_value: Value to match
        conn: Optional database connection
    
    Returns:
        Dict with id, value, confidence, confirmation_count if found, else None
    """
    should_close = False
    if conn is None:
        conn = get_db_connection()
        should_close = True
    
    try:
        cur = conn.cursor()
        
        # First try exact match (case-insensitive)
        cur.execute("""
            SELECT id, value, confidence, confirmation_count 
            FROM entity_facts
            WHERE entity_id = %s 
              AND LOWER(key) = LOWER(%s) 
              AND LOWER(value) = LOWER(%s)
            LIMIT 1
        """, (entity_id, key, new_value))
        
        result = cur.fetchone()
        if result:
            return {
                'id': result[0],
                'value': result[1],
                'confidence': result[2],
                'confirmation_count': result[3]
            }
        
        # Try fuzzy match using pg_trgm similarity (threshold > 0.85)
        cur.execute("""
            SELECT id, value, confidence, confirmation_count,
                   similarity(LOWER(value), LOWER(%s)) as sim
            FROM entity_facts
            WHERE entity_id = %s 
              AND LOWER(key) = LOWER(%s)
              AND similarity(LOWER(value), LOWER(%s)) > 0.85
            ORDER BY sim DESC
            LIMIT 1
        """, (new_value, entity_id, key, new_value))
        
        result = cur.fetchone()
        if result:
            return {
                'id': result[0],
                'value': result[1],
                'confidence': result[2],
                'confirmation_count': result[3],
                'similarity': result[4]
            }
        
        return None
        
    finally:
        if should_close:
            conn.close()


def reinforce_confidence(current: float, confirmation_count: int) -> float:
    """
    Increase confidence when data is confirmed (another 'vote').
    
    Uses diminishing returns formula: boost = 0.15 / (1 + count * 0.2)
    
    Args:
        current: Current confidence score (0.0-1.0)
        confirmation_count: Number of previous confirmations
    
    Returns:
        New confidence score (capped at 1.0)
    """
    boost = 0.15 / (1 + confirmation_count * 0.2)
    return min(1.0, current + boost)


def store_or_reinforce_fact(
    entity_id: int,
    key: str,
    value: str,
    source_entity_id: Optional[int] = None,
    source: str = 'direct',
    visibility: str = 'public',
    visibility_reason: Optional[str] = None,
    conn=None
) -> Dict[str, Any]:
    """
    Store new fact or reinforce existing one.
    
    Main entry point for memory storage with smart deduplication.
    
    Args:
        entity_id: Entity this fact is about
        key: Fact key/predicate
        value: Fact value
        source_entity_id: Entity who stated this fact
        source: Source type ('direct', 'inferred', 'external')
        visibility: Visibility level ('public', 'private', etc.)
        visibility_reason: Optional reason for visibility level
        conn: Optional database connection
    
    Returns:
        Dict with:
            - action: 'reinforced' or 'created'
            - fact_id: ID of the fact
            - confidence: New/current confidence
            - (reinforced only) previous_confidence: Old confidence
    """
    should_close = False
    if conn is None:
        conn = get_db_connection()
        should_close = True
    
    try:
        # Check for existing match
        existing = find_existing_fact(entity_id, key, value, conn)
        
        if existing:
            # REINFORCE existing fact
            new_confidence = reinforce_confidence(
                existing['confidence'],
                existing['confirmation_count']
            )
            
            cur = conn.cursor()
            cur.execute("""
                UPDATE entity_facts SET
                    confidence = %s,
                    confirmation_count = confirmation_count + 1,
                    last_confirmed_at = NOW(),
                    updated_at = NOW()
                WHERE id = %s
            """, (new_confidence, existing['id']))
            
            conn.commit()
            
            return {
                'action': 'reinforced',
                'fact_id': existing['id'],
                'confidence': new_confidence,
                'previous_confidence': existing['confidence'],
                'confirmation_count': existing['confirmation_count'] + 1
            }
        
        else:
            # NEW fact - use source-based initial confidence
            initial_confidence = get_initial_confidence(source_entity_id or 0, source, conn)
            
            cur = conn.cursor()
            
            # Build INSERT query dynamically based on optional fields
            cols = ['entity_id', 'key', 'value', 'confidence', 'confirmation_count', 'source', 'visibility']
            vals = [entity_id, key, value, initial_confidence, 1, source, visibility]
            placeholders = ['%s'] * len(vals)
            
            if source_entity_id:
                cols.append('source_entity_id')
                vals.append(source_entity_id)
                placeholders.append('%s')
            
            if visibility_reason:
                cols.append('visibility_reason')
                vals.append(visibility_reason)
                placeholders.append('%s')
            
            query = f"""
                INSERT INTO entity_facts ({', '.join(cols)})
                VALUES ({', '.join(placeholders)})
                RETURNING id
            """
            
            cur.execute(query, vals)
            fact_id = cur.fetchone()[0]
            
            conn.commit()
            
            return {
                'action': 'created',
                'fact_id': fact_id,
                'confidence': initial_confidence,
                'confirmation_count': 1
            }
    
    finally:
        if should_close:
            conn.close()


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) == 1:
        # Test mode
        print("Testing dedup_helper...")
        
        conn = get_db_connection()
        
        # Test 1: Create new fact
        print("\n1. Testing new fact creation...")
        result = store_or_reinforce_fact(
            entity_id=2,  # I)ruid
            key='test_fact',
            value='test value',
            source_entity_id=2,
            source='direct',
            conn=conn
        )
        print(f"Result: {result}")
        assert result['action'] == 'created'
        assert result['confidence'] == 1.0
        fact_id = result['fact_id']
        
        # Test 2: Reinforce same fact (exact match)
        print("\n2. Testing reinforcement (exact match)...")
        result = store_or_reinforce_fact(
            entity_id=2,
            key='test_fact',
            value='test value',
            source_entity_id=2,
            source='direct',
            conn=conn
        )
        print(f"Result: {result}")
        assert result['action'] == 'reinforced'
        assert result['fact_id'] == fact_id
        assert result['confidence'] > 1.0 or result['confidence'] == 1.0  # Already at max
        
        # Test 3: Reinforce with fuzzy match
        print("\n3. Testing reinforcement (fuzzy match)...")
        result = store_or_reinforce_fact(
            entity_id=2,
            key='test_fact',
            value='Test Value',  # Different case and spacing
            source_entity_id=2,
            source='direct',
            conn=conn
        )
        print(f"Result: {result}")
        assert result['action'] == 'reinforced'
        assert result['fact_id'] == fact_id
        
        # Clean up test data
        print("\n4. Cleaning up test data...")
        cur = conn.cursor()
        cur.execute("DELETE FROM entity_facts WHERE id = %s", (fact_id,))
        conn.commit()
        
        conn.close()
        
        print("\n✓ All tests passed!")
        
    else:
        # CLI usage: dedup_helper.py find <entity_id> <key> <value>
        # Or: dedup_helper.py store <entity_id> <key> <value> [source_entity_id] [source] [visibility] [visibility_reason]
        action = sys.argv[1]
        
        if action == 'find':
            entity_id = int(sys.argv[2])
            key = sys.argv[3]
            value = sys.argv[4]
            
            result = find_existing_fact(entity_id, key, value)
            if result:
                print(f"Found: {result}")
            else:
                print("Not found")
        
        elif action == 'store':
            entity_id = int(sys.argv[2])
            key = sys.argv[3]
            value = sys.argv[4]
            source_entity_id = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] not in ['null', ''] else None
            source = sys.argv[6] if len(sys.argv) > 6 else 'direct'
            visibility = sys.argv[7] if len(sys.argv) > 7 else 'public'
            visibility_reason = sys.argv[8] if len(sys.argv) > 8 and sys.argv[8] not in ['null', 'empty', ''] else None
            
            result = store_or_reinforce_fact(
                entity_id, key, value, 
                source_entity_id, source, 
                visibility, visibility_reason
            )
            print(f"{result['action']} - fact_id: {result['fact_id']}, confidence: {result['confidence']:.3f}")
        
        else:
            print("Usage:")
            print("  dedup_helper.py find <entity_id> <key> <value>")
            print("  dedup_helper.py store <entity_id> <key> <value> [source_entity_id] [source] [visibility] [visibility_reason]")
            sys.exit(1)
