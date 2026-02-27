#!/usr/bin/env python3
"""
Confidence Helper - Determine initial confidence for memory facts.

Based on source authority (entity trust level and source type).
"""

import psycopg2
import os
import sys
from typing import Optional

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


OWNER_ENTITY_ID = 2  # I)ruid


def get_db_connection():
    """Get database connection using PG* env vars."""
    return psycopg2.connect()


def get_entity_trust_level(entity_id: int, conn=None) -> str:
    """Query entity trust level from database."""
    should_close = False
    if conn is None:
        conn = get_db_connection()
        should_close = True
    
    try:
        cur = conn.cursor()
        cur.execute("SELECT trust_level FROM entities WHERE id = %s", (entity_id,))
        result = cur.fetchone()
        
        if result and result[0]:
            return result[0]
        return 'unknown'
    finally:
        if should_close:
            conn.close()


def get_initial_confidence(entity_id: int, source: Optional[str] = None, conn=None) -> float:
    """
    Determine initial confidence based on source authority.
    
    Args:
        entity_id: Entity making the statement
        source: Source type - 'direct', 'inferred', 'external', or None
        conn: Optional database connection (will create if not provided)
    
    Returns:
        Initial confidence score between 0.0 and 1.0
    """
    # Owner always gets 1.0
    if entity_id == OWNER_ENTITY_ID:
        return 1.0
    
    # Get entity trust level
    trust_level = get_entity_trust_level(entity_id, conn)
    
    # Base confidence by trust level
    trust_confidence = {
        'owner': 1.0,
        'admin': 0.9,
        'user': 0.7,
        'unknown': 0.4,
        'untrusted': 0.2,
    }
    
    # Source type multipliers
    # 'inferred' = AI deduction, 'external' = web/API, 'direct' = directly stated
    source_multipliers = {
        'inferred': 0.5,
        'external': 0.7,
        'direct': 1.0,
    }
    
    base = trust_confidence.get(trust_level, 0.4)
    multiplier = source_multipliers.get(source, 1.0) if source else 1.0
    
    return min(1.0, base * multiplier)


if __name__ == '__main__':
    import sys
    
    # CLI mode: confidence_helper.py <entity_id> [source_type]
    if len(sys.argv) > 1:
        try:
            entity_id = int(sys.argv[1])
            source_type = sys.argv[2] if len(sys.argv) > 2 else None
            confidence = get_initial_confidence(entity_id, source_type)
            print(confidence)
        except (ValueError, IndexError) as e:
            print("0.4", file=sys.stderr)
            sys.exit(1)
    else:
        # Test mode
        print("Testing confidence_helper...")
        
        # Test owner
        conf = get_initial_confidence(2)
        print(f"Owner (entity 2): {conf} (expected: 1.0)")
        
        # Test admin
        conf = get_initial_confidence(1)
        print(f"Admin (entity 1): {conf} (expected: 0.9)")
        
        # Test with source types
        conf = get_initial_confidence(1, 'direct')
        print(f"Admin + direct: {conf} (expected: 0.9)")
        
        conf = get_initial_confidence(1, 'inferred')
        print(f"Admin + inferred: {conf} (expected: 0.45)")
        
        conf = get_initial_confidence(1, 'external')
        print(f"Admin + external: {conf} (expected: 0.63)")
        
        print("\nTest complete!")
