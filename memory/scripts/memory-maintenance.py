#!/usr/bin/env python3
"""
Memory confidence decay and soft-deletion script.
Task: #53 - Memory Confidence & Expiration System

Run daily via cron: 0 4 * * * ~/.openclaw/scripts/memory-decay.py

Usage:
    memory-decay.py [--dry-run] [--verbose] [--skip-dedup]

Options:
    --dry-run     Show what would be done without modifying the database
    --verbose     Print detailed information
    --skip-dedup  Skip the duplicate merge phase
"""

# Load OpenClaw environment (API keys from openclaw.json)
import sys, os
sys.path.insert(0, os.path.expanduser('~/.openclaw/lib'))
try:
    from env_loader import load_openclaw_env
    load_openclaw_env()
except ImportError:
    pass  # Library not installed yet

import psycopg2
import psycopg2.extras
from datetime import datetime, timedelta, timezone
import math
import logging
import sys
import os
from pathlib import Path

# Load centralized PostgreSQL configuration
sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
from pg_env import load_pg_env
load_pg_env()

# Configuration
ARCHIVE_THRESHOLD = 0.1  # Archive when confidence drops below this
MIN_AGE_DAYS = 7         # Don't archive anything less than 7 days old

# Decay rates (per day) — keyed by durability, not old data_type
DECAY_RATES = {
    'permanent': 0,           # Never decays
    'long_term': 0.005,       # ~0.5% per day, 16% after 1 year
    'short_term': 0.02,       # ~2% per day, moderate decay
    'ephemeral': 0.1,         # ~10% per day, near zero after 3 weeks
}

# Table-specific decay rates
TABLE_DECAY_RATES = {
    'events': 0.001,          # Very slow - historical records
    'lessons': 0.001,         # Very slow - learnings persist
    'memory_embeddings': 0.01 # Medium - can get stale
}

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


def calculate_decay(durability: str, days_since_confirmed: int, custom_rate: float = None) -> float:
    """Calculate confidence decay factor based on durability and time.
    
    Args:
        durability: Durability level (permanent, long_term, short_term, ephemeral)
        days_since_confirmed: Number of days since last confirmation
        custom_rate: Optional custom decay rate (overrides durability default)
        
    Returns:
        Decay factor (multiplier for current confidence, 0-1)
    """
    if days_since_confirmed <= 0:
        return 1.0
    
    rate = custom_rate if custom_rate is not None else DECAY_RATES.get(durability, 0.01)
    
    # Exponential decay: confidence_new = confidence_old * e^(-rate * days)
    decay_factor = math.exp(-rate * days_since_confirmed)
    
    return decay_factor


def merge_duplicates(conn, dry_run=False, verbose=False):
    """Find and merge/categorize duplicate entity_facts using three-tier confidence system.
    
    Uses pg_trgm similarity() for text comparison. Three tiers:
    - High (similarity >= 0.80): auto-merge via merge_facts(survivor_id, absorbed_id)
        survivor = higher confidence fact; extraction_counts are summed by merge_facts
    - Medium (0.50-0.79 similarity): add to daily report for manual review
    - Low (< 0.50): skip entirely
    """
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    
    # Find all candidate pairs with similarity >= 0.50
    cur.execute("""
        SELECT 
            f1.id as id1, f2.id as id2,
            f1.entity_id, f1.key,
            f1.value as value1, f2.value as value2,
            f1.confidence as conf1, f2.confidence as conf2,
            f1.last_confirmed_at as date1, f2.last_confirmed_at as date2,
            similarity(LOWER(f1.value), LOWER(f2.value)) as sim
        FROM entity_facts f1
        JOIN entity_facts f2 ON 
            f1.entity_id = f2.entity_id 
            AND f1.key = f2.key 
            AND f1.id < f2.id
        WHERE similarity(LOWER(f1.value), LOWER(f2.value)) >= 0.50
        ORDER BY sim DESC, f1.id, f2.id
    """)
    
    pairs = cur.fetchall()
    
    absorbed_ids = set()
    high_merges = 0
    medium_candidates = []
    
    for row in pairs:
        id1, id2 = row['id1'], row['id2']
        
        # Skip if either fact was already absorbed in a previous high-confidence merge
        if id1 in absorbed_ids or id2 in absorbed_ids:
            continue
        
        sim = row['sim']
        
        if sim >= 0.80:
            # High confidence: auto-merge
            if row['conf1'] > row['conf2']:
                survivor, absorbed = id1, id2
            elif row['conf2'] > row['conf1']:
                survivor, absorbed = id2, id1
            elif row['date1'] > row['date2']:
                survivor, absorbed = id1, id2
            elif row['date2'] > row['date1']:
                survivor, absorbed = id2, id1
            else:
                # Perfect tie — use lower ID as survivor for determinism
                survivor, absorbed = (id1, id2) if id1 < id2 else (id2, id1)
            
            if not dry_run:
                cur.execute("SELECT merge_facts(%s, %s)", (survivor, absorbed))
            
            absorbed_ids.add(absorbed)
            high_merges += 1
            
            if verbose:
                logger.info(f"  [high, sim={sim:.2f}] {row['key']}: auto-merged ID {absorbed} into ID {survivor}")
        
        elif sim >= 0.50:
            # Medium confidence: flag for manual review
            medium_candidates.append({
                'id1': id1,
                'id2': id2,
                'entity_id': row['entity_id'],
                'key': row['key'],
                'value1': row['value1'],
                'value2': row['value2'],
                'similarity': sim
            })
            
            if verbose:
                logger.info(f"  [medium, sim={sim:.2f}] {row['key']}: '{row['value1']}' vs '{row['value2']}' — flagged for review")
    
    if verbose:
        logger.info(f"Found {high_merges} high-confidence merges, {len(medium_candidates)} medium-confidence candidates")
    
    return {
        'high_merges': high_merges,
        'medium_count': len(medium_candidates),
        'medium_candidates': medium_candidates
    }


def write_dedup_report(candidates, dry_run=False):
    """Write medium-confidence dedup candidates to daily report file."""
    if not candidates:
        return
    
    logs_dir = Path.home() / '.openclaw' / 'logs'
    logs_dir.mkdir(parents=True, exist_ok=True)
    
    today = datetime.now().strftime('%Y-%m-%d')
    report_path = logs_dir / f'dedup-report-{today}.md'
    
    mode_str = " (DRY RUN)" if dry_run else ""
    
    with open(report_path, 'w') as f:
        f.write(f"# Duplicate Detection Report — {today}{mode_str}\n\n")
        f.write("Medium-confidence candidates (0.50–0.79 similarity) for manual review:\n\n")
        f.write("| fact_id_1 | fact_id_2 | entity_id | key | value_1 | value_2 | similarity_score | recommended_action |\n")
        f.write("|-----------|-----------|-----------|-----|---------|---------|------------------|-------------------|\n")
        for c in candidates:
            f.write(f"| {c['id1']} | {c['id2']} | {c['entity_id']} | {c['key']} | {c['value1']} | {c['value2']} | {c['similarity']:.3f} | Manual review: potential duplicate |\n")
        f.write("\n")
    
    logger.info(f"Wrote dedup report with {len(candidates)} medium-confidence candidates to {report_path}")


def apply_decay_to_entity_facts(conn, dry_run=False, verbose=False):
    """Apply confidence decay to entity_facts table."""
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    
    # Get all non-permanent facts with confidence data
    cur.execute("""
        SELECT id, entity_id, key, durability, confidence, 
               last_confirmed_at, decay_rate, expires
        FROM entity_facts
        WHERE durability != 'permanent'
          AND confidence > %s
    """, (ARCHIVE_THRESHOLD,))
    
    rows = cur.fetchall()
    updates = []
    
    for row in rows:
        days_since = (datetime.now(timezone.utc) - row['last_confirmed_at']).days
        
        if days_since <= 0:
            continue
        
        # If fact has expired, apply aggressive immediate decay
        if row['expires'] is not None and row['expires'] < datetime.now(timezone.utc):
            decay_factor = 0.0  # immediate archive
        else:
            decay_factor = calculate_decay(row['durability'], days_since, row['decay_rate'])
        
        new_confidence = row['confidence'] * decay_factor
        
        # Only update if there's a meaningful change (>0.001)
        if abs(new_confidence - row['confidence']) > 0.001:
            updates.append({
                'id': row['id'],
                'entity_id': row['entity_id'],
                'key': row['key'],
                'old_confidence': row['confidence'],
                'new_confidence': new_confidence,
                'days_since': days_since,
                'durability': row['durability']
            })
    
    if verbose:
        logger.info(f"Entity facts to decay: {len(updates)}")
        if updates and len(updates) <= 10:
            for u in updates:
                logger.info(f"  [{u['durability']}] {u['key']}: {u['old_confidence']:.3f} → {u['new_confidence']:.3f} ({u['days_since']} days)")
    
    if not dry_run and updates:
        # Batch update
        psycopg2.extras.execute_batch(cur, """
            UPDATE entity_facts 
            SET confidence = %(new_confidence)s, updated_at = NOW()
            WHERE id = %(id)s
        """, updates, page_size=100)
    
    return len(updates)


def apply_decay_to_table(conn, table_name: str, decay_rate: float, dry_run=False, verbose=False):
    """Apply confidence decay to a specific table (events, lessons, memory_embeddings)."""
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    
    cur.execute(f"""
        SELECT id, confidence, last_confirmed_at
        FROM {table_name}
        WHERE confidence > %s
    """, (ARCHIVE_THRESHOLD,))
    
    rows = cur.fetchall()
    updates = []
    
    for row in rows:
        days_since = (datetime.now(timezone.utc) - row['last_confirmed_at']).days
        
        if days_since <= 0:
            continue
            
        decay_factor = math.exp(-decay_rate * days_since)
        new_confidence = row['confidence'] * decay_factor
        
        if abs(new_confidence - row['confidence']) > 0.001:
            updates.append({
                'id': row['id'],
                'old_confidence': row['confidence'],
                'new_confidence': new_confidence,
                'days_since': days_since
            })
    
    if verbose and updates:
        logger.info(f"{table_name} to decay: {len(updates)}")
        if len(updates) <= 5:
            for u in updates:
                logger.info(f"  ID {u['id']}: {u['old_confidence']:.3f} → {u['new_confidence']:.3f}")
    
    if not dry_run and updates:
        psycopg2.extras.execute_batch(cur, f"""
            UPDATE {table_name}
            SET confidence = %(new_confidence)s, updated_at = NOW()
            WHERE id = %(id)s
        """, updates, page_size=100)
    
    return len(updates)


def archive_low_confidence(conn, dry_run=False, verbose=False):
    """Move low-confidence entity_facts to archive table."""
    cur = conn.cursor()
    
    if dry_run:
        # Just count what would be archived
        cur.execute("""
            SELECT COUNT(*) FROM entity_facts
            WHERE confidence < %s
              AND learned_at < NOW() - INTERVAL '%s days'
              AND durability != 'permanent'
        """, (ARCHIVE_THRESHOLD, MIN_AGE_DAYS))
        count = cur.fetchone()[0]
        return count
    
    # Archive facts below threshold that are old enough
    cur.execute("""
        WITH archived AS (
            DELETE FROM entity_facts
            WHERE confidence < %s
              AND learned_at < NOW() - INTERVAL '%s days'
              AND durability != 'permanent'
            RETURNING *
        )
        INSERT INTO entity_facts_archive 
            (id, entity_id, key, value, confidence,
             last_confirmed_at, extraction_count, decay_rate,
             durability, category, expires,
             learned_at, updated_at, archive_reason)
        SELECT 
            id, entity_id, key, value, confidence,
            last_confirmed_at, extraction_count, decay_rate,
            durability, category, expires,
            learned_at, updated_at, 'low_confidence'
        FROM archived
        RETURNING id
    """, (ARCHIVE_THRESHOLD, MIN_AGE_DAYS))
    
    archived_ids = cur.fetchall()
    
    if verbose and archived_ids:
        logger.info(f"Archived {len(archived_ids)} low-confidence facts")
    
    return len(archived_ids)


def detect_conflicts(conn, dry_run=False, verbose=False):
    """Find and resolve conflicting facts for same entity+key with different values."""
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    
    # Find duplicate entity+key combinations with different values
    cur.execute("""
        SELECT entity_id, key, array_agg(id) as ids, 
               array_agg(value) as values, array_agg(confidence) as confidences
        FROM entity_facts
        GROUP BY entity_id, key
        HAVING COUNT(*) > 1 AND COUNT(DISTINCT value) > 1
    """)
    
    conflicts = cur.fetchall()
    auto_archived = 0
    pending_review = 0
    
    for row in conflicts:
        entity_id = row['entity_id']
        key = row['key']
        ids = row['ids']
        values = row['values']
        confidences = row['confidences']
        
        max_conf = max(confidences)
        min_conf = min(confidences)
        
        # If one is significantly higher confidence (>2x), archive the lower ones
        if max_conf > min_conf * 2:
            winner_idx = confidences.index(max_conf)
            
            for i, fact_id in enumerate(ids):
                if i != winner_idx:
                    if verbose:
                        logger.info(f"Auto-archiving conflict: entity={entity_id}, key={key}, "
                                  f"kept conf={confidences[winner_idx]:.2f}, archived conf={confidences[i]:.2f}")
                    
                    if not dry_run:
                        # Archive the lower-confidence fact
                        cur.execute("""
                            WITH archived AS (
                                DELETE FROM entity_facts
                                WHERE id = %s
                                RETURNING *
                            )
                            INSERT INTO entity_facts_archive 
                                (id, entity_id, key, value, confidence,
                                 last_confirmed_at, extraction_count, decay_rate,
                                 durability, category, expires,
                                 learned_at, updated_at, archive_reason)
                            SELECT 
                                id, entity_id, key, value, confidence,
                                last_confirmed_at, extraction_count, decay_rate,
                                durability, category, expires,
                                learned_at, updated_at, 'conflict_resolution'
                            FROM archived
                        """, (fact_id,))
                        
                        # Log the conflict resolution
                        cur.execute("""
                            INSERT INTO entity_fact_conflicts 
                                (entity_id, key, fact_id_a, fact_id_b, value_a, value_b,
                                 confidence_a, confidence_b, resolution, resolved_at, resolved_by)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'auto_archived', NOW(), 'decay_script')
                        """, (entity_id, key, ids[winner_idx], fact_id, 
                             values[winner_idx], values[i], confidences[winner_idx], confidences[i]))
                    
                    auto_archived += 1
        
        # Similar confidence - flag for human review
        else:
            if verbose:
                logger.info(f"Conflict needs review: entity={entity_id}, key={key}, "
                          f"values={values}, confidences={[f'{c:.2f}' for c in confidences]}")
            
            if not dry_run:
                # Log all pairs as pending conflicts
                for i in range(len(ids)):
                    for j in range(i + 1, len(ids)):
                        cur.execute("""
                            INSERT INTO entity_fact_conflicts 
                                (entity_id, key, fact_id_a, fact_id_b, value_a, value_b,
                                 confidence_a, confidence_b, resolution)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'pending')
                            ON CONFLICT DO NOTHING
                        """, (entity_id, key, ids[i], ids[j], values[i], values[j], 
                             confidences[i], confidences[j]))
            
            pending_review += 1
    
    if verbose:
        logger.info(f"Conflicts: {auto_archived} auto-archived, {pending_review} pending review")
    
    return auto_archived, pending_review


def purge_old_archives(conn, dry_run=False, verbose=False):
    """Hard delete archived facts older than 1 year using cleanup functions."""
    cur = conn.cursor()
    
    if dry_run:
        # Count what would be purged
        cur.execute("""
            SELECT 
                (SELECT COUNT(*) FROM entity_facts_archive WHERE archived_at < NOW() - INTERVAL '1 year') as facts,
                (SELECT COUNT(*) FROM events_archive WHERE archived_at < NOW() - INTERVAL '1 year') as events,
                (SELECT COUNT(*) FROM lessons_archive WHERE archived_at < NOW() - INTERVAL '1 year') as lessons,
                (SELECT COUNT(*) FROM memory_embeddings_archive WHERE archived_at < NOW() - INTERVAL '1 year') as embeddings
        """)
        counts = cur.fetchone()
        total = sum(counts)
        if verbose and total > 0:
            logger.info(f"Would purge: {counts[0]} facts, {counts[1]} events, {counts[2]} lessons, {counts[3]} embeddings")
        return total
    
    # Call cleanup functions
    cur.execute("SELECT cleanup_old_archives()")
    facts_purged = cur.fetchone()[0]
    
    cur.execute("SELECT cleanup_old_events_archive()")
    events_purged = cur.fetchone()[0]
    
    cur.execute("SELECT cleanup_old_lessons_archive()")
    lessons_purged = cur.fetchone()[0]
    
    cur.execute("SELECT cleanup_old_embeddings_archive()")
    embeddings_purged = cur.fetchone()[0]
    
    total = facts_purged + events_purged + lessons_purged + embeddings_purged
    
    if verbose and total > 0:
        logger.info(f"Purged: {facts_purged} facts, {events_purged} events, {lessons_purged} lessons, {embeddings_purged} embeddings")
    
    return total


def log_summary(duplicates_merged: int, decayed_facts: int, decayed_events: int, 
                decayed_lessons: int, decayed_embeddings: int, archived: int, purged: int, 
                conflicts_archived: int, conflicts_pending: int, medium_report_count: int = 0, dry_run=False):
    """Log summary to daily memory file."""
    
    total_decayed = decayed_facts + decayed_events + decayed_lessons + decayed_embeddings
    
    mode = " (DRY RUN)" if dry_run else ""
    logger.info(f"Memory decay complete{mode}: {duplicates_merged} duplicates merged, {total_decayed} decayed, {archived} archived, {purged} purged, "
               f"{conflicts_archived} conflicts resolved, {conflicts_pending} pending review")
    if medium_report_count > 0:
        logger.info(f"Medium-confidence dedup candidates: {medium_report_count} (see dedup report)")
    
    # Write to daily memory file
    memory_dir = Path.home() / '.openclaw' / 'workspace' / 'memory'
    memory_dir.mkdir(parents=True, exist_ok=True)
    
    daily_file = memory_dir / f'{datetime.now():%Y-%m-%d}.md'
    
    with open(daily_file, 'a') as f:
        f.write(f"\n### Memory Decay Script ({datetime.now():%H:%M UTC}){mode}\n")
        if duplicates_merged > 0:
            f.write(f"- Duplicates merged: {duplicates_merged}\n")
        if medium_report_count > 0:
            f.write(f"- Medium-confidence dedup candidates: {medium_report_count} (see dedup report)\n")
        f.write(f"- Decayed: {total_decayed} total ({decayed_facts} facts, {decayed_events} events, {decayed_lessons} lessons, {decayed_embeddings} embeddings)\n")
        f.write(f"- Archived: {archived} facts (confidence < {ARCHIVE_THRESHOLD})\n")
        if purged > 0:
            f.write(f"- Purged: {purged} archived records (older than 1 year)\n")
        if conflicts_archived > 0 or conflicts_pending > 0:
            f.write(f"- Conflicts: {conflicts_archived} auto-resolved, {conflicts_pending} pending human review\n")


def main():
    """Main entry point."""
    dry_run = '--dry-run' in sys.argv
    verbose = '--verbose' in sys.argv or dry_run
    skip_dedup = '--skip-dedup' in sys.argv
    
    if dry_run:
        logger.info("Running in DRY RUN mode - no changes will be made")
    
    try:
        conn = psycopg2.connect()
        
        # 1. Merge duplicates (unless skipped)
        if skip_dedup:
            logger.info("Skipping duplicate merge (--skip-dedup)")
            duplicates_merged = 0
            medium_report_count = 0
        else:
            logger.info("Merging duplicates...")
            dedup_result = merge_duplicates(conn, dry_run, verbose)
            duplicates_merged = dedup_result['high_merges']
            medium_report_count = dedup_result['medium_count']
            if medium_report_count > 0:
                write_dedup_report(dedup_result['medium_candidates'], dry_run)
            if dry_run and duplicates_merged > 0:
                logger.info(f"{duplicates_merged} duplicates would be merged")
        
        # 2. Apply decay to all tables
        logger.info("Applying confidence decay...")
        decayed_facts = apply_decay_to_entity_facts(conn, dry_run, verbose)
        decayed_events = apply_decay_to_table(conn, 'events', TABLE_DECAY_RATES['events'], dry_run, verbose)
        decayed_lessons = apply_decay_to_table(conn, 'lessons', TABLE_DECAY_RATES['lessons'], dry_run, verbose)
        decayed_embeddings = apply_decay_to_table(conn, 'memory_embeddings', TABLE_DECAY_RATES['memory_embeddings'], dry_run, verbose)
        
        # 3. Detect and resolve conflicts
        logger.info("Detecting conflicts...")
        conflicts_archived, conflicts_pending = detect_conflicts(conn, dry_run, verbose)
        
        # 4. Archive low-confidence facts (soft delete)
        logger.info("Archiving low-confidence facts...")
        archived = archive_low_confidence(conn, dry_run, verbose)
        
        # 5. Hard delete archives older than 1 year
        logger.info("Purging old archives...")
        purged = purge_old_archives(conn, dry_run, verbose)
        
        # 6. Log summary
        log_summary(duplicates_merged, decayed_facts, decayed_events, decayed_lessons, decayed_embeddings, 
                   archived, purged, conflicts_archived, conflicts_pending, medium_report_count, dry_run)
        
        if not dry_run:
            conn.commit()
            logger.info("Changes committed to database")
        else:
            logger.info("Dry run complete - no changes made")
        
        conn.close()
        
    except Exception as e:
        logger.error(f"Error during memory decay: {e}", exc_info=True)
        sys.exit(1)


if __name__ == '__main__':
    main()
