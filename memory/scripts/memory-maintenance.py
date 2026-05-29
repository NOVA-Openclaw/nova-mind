#!/usr/bin/env python3
"""
Unified memory maintenance script.
Replaces: embed-full-database.py, embed-memories.py, embed-research.py,
          and previous memory-maintenance.py.

Phases:
  1. Cooldown check
  2. Embed (database rows, research, memory files)
  3. Cross-key consolidation
  4. Same-key deduplication
  5. Confidence decay
  6. Ghost entity cleanup
  7. Entity-level deduplication
  8. Clean orphaned embeddings
  9. Archive & purge low-confidence facts
"""

import argparse
import json
import logging
import os
import re
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

import psycopg2
import psycopg2.errors
import psycopg2.extras
import requests

# ---------------------------------------------------------------------------
# Library loading pattern (backward compatible)
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
sys.path.insert(0, str(SCRIPT_DIR))

try:
    from env_loader import load_openclaw_env
    load_openclaw_env()
except ImportError:
    pass

try:
    from pg_env import load_pg_env
    load_pg_env()
except ImportError:
    pass

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger("memory-maintenance")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DEFAULT_STATE_FILE = os.path.expanduser("~/.openclaw/state/memory-maintenance-last-run.json")
COOLDOWN_HOURS = 4
EMBED_BATCH_SIZE = 64
ARCHIVE_THRESHOLD = 0.1
MIN_AGE_DAYS = 7

DECAY_RATES = {
    'permanent': 0,
    'long_term': 0.005,
    'short_term': 0.02,
    'ephemeral': 0.1,
}

TABLE_DECAY_RATES = {
    'events': 0.001,
    'lessons': 0.001,
    'memory_embeddings': 0.01,
}


def load_embedding_config():
    cfg_path = SCRIPT_DIR / "embedding-config.json"
    if not cfg_path.exists():
        return {
            "provider": "ollama",
            "model": "mxbai-embed-large",
            "base_url": "http://localhost:11434",
            "dimensions": 1024,
        }
    with open(cfg_path) as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Phase 1: Cooldown
# ---------------------------------------------------------------------------
def check_cooldown(state_file, force=False):
    if force:
        return True
    try:
        with open(state_file) as f:
            state = json.load(f)
        last_run = datetime.fromisoformat(state["last_run"])
        if datetime.now(timezone.utc) - last_run < timedelta(hours=COOLDOWN_HOURS):
            logger.info(f"Cooldown active — last run {last_run.isoformat()}, skipping")
            return False
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        pass
    return True


def update_state(state_file):
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    with open(state_file, "w") as f:
        json.dump({"last_run": datetime.now(timezone.utc).isoformat()}, f)


# ---------------------------------------------------------------------------
# Phase 2: Embed
# ---------------------------------------------------------------------------
def _already_embedded(cur, source_type, source_id):
    cur.execute(
        "SELECT 1 FROM memory_embeddings WHERE source_type = %s AND source_id = %s LIMIT 1",
        (source_type, str(source_id)),
    )
    return cur.fetchone() is not None


def embed_batch(texts, cfg):
    if not texts:
        return []
    url = f"{cfg['base_url'].rstrip('/')}/api/embed"
    payload = {"model": cfg["model"], "input": texts}
    try:
        resp = requests.post(url, json=payload, timeout=300)
        resp.raise_for_status()
        data = resp.json()
        return data.get("embeddings", [])
    except Exception as e:
        logger.error(f"Batch embed failed: {e}")
        return []


def embed_single(text, cfg):
    url = f"{cfg['base_url'].rstrip('/')}/api/embeddings"
    payload = {"model": cfg["model"], "prompt": text}
    try:
        resp = requests.post(url, json=payload, timeout=120)
        resp.raise_for_status()
        data = resp.json()
        return data.get("embedding", [])
    except Exception as e:
        logger.error(f"Single embed failed: {e}")
        return []


def embed_texts(texts, cfg):
    if not texts:
        return []
    result = embed_batch(texts, cfg)
    if result and len(result) == len(texts):
        return result
    logger.warning("Batch embed incomplete, falling back to single embeds")
    return [embed_single(t, cfg) for t in texts]


def _store_embeddings(cur, source_type, items, embeddings):
    for item, emb in zip(items, embeddings):
        if not emb:
            continue
        emb_json = json.dumps(emb)
        cur.execute(
            """
            INSERT INTO memory_embeddings (source_type, source_id, content, embedding)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (source_type, source_id) DO UPDATE
            SET content = EXCLUDED.content,
                embedding = EXCLUDED.embedding,
                updated_at = NOW()
            """,
            (source_type, str(item["id"]), item["text"], emb_json),
        )


# ---- Embed database tables ----
TABLE_EMBED_SPECS = {
    "entity_fact": (
        """
        SELECT ef.id, e.name || ' - ' || ef.key || ': ' || ef.value AS text
        FROM entity_facts ef
        JOIN entities e ON e.id = ef.entity_id
        """,
        "entity_fact",
    ),
    "entity": (
        "SELECT id, name AS text FROM entities WHERE name IS NOT NULL",
        "entity",
    ),
    "task": (
        "SELECT id, title AS text FROM tasks WHERE title IS NOT NULL",
        "task",
    ),
    "project": (
        "SELECT id, name AS text FROM projects WHERE name IS NOT NULL",
        "project",
    ),
    "agent": (
        "SELECT id, name AS text FROM agents WHERE name IS NOT NULL",
        "agent",
    ),
    "lesson": (
        "SELECT id, lesson AS text FROM lessons WHERE lesson IS NOT NULL",
        "lesson",
    ),
    "event": (
        "SELECT id, description AS text FROM events WHERE description IS NOT NULL",
        "event",
    ),
    "trading_signal": (
        "SELECT id, COALESCE(signal_type, '') || ' ' || COALESCE(symbol, '') AS text FROM trading_signals",
        "trading_signal",
    ),
    "position": (
        "SELECT id, COALESCE(symbol, '') || ' @ ' || COALESCE(entry_price::text, '') AS text FROM positions",
        "position",
    ),
    "media_consumed": (
        "SELECT id, title AS text FROM media_consumed WHERE title IS NOT NULL",
        "media_consumed",
    ),
    "vocabulary": (
        "SELECT id, word AS text FROM vocabulary WHERE word IS NOT NULL",
        "vocabulary",
    ),
    "library": (
        "SELECT id, title AS text FROM library WHERE title IS NOT NULL",
        "library",
    ),
}


def _embed_table(cur, query, source_type, cfg):
    cur.execute("SAVEPOINT embed_check")
    try:
        cur.execute(query)
    except psycopg2.errors.UndefinedTable:
        cur.execute("ROLLBACK TO SAVEPOINT embed_check")
        logger.warning("[WARN] Table not found, skipping: %s", source_type)
        return 0
    rows = cur.fetchall()
    items = [{"id": r[0], "text": r[1]} for r in rows if r[1] and not _already_embedded(cur, source_type, r[0])]
    if not items:
        return 0
    total = 0
    for i in range(0, len(items), EMBED_BATCH_SIZE):
        batch = items[i : i + EMBED_BATCH_SIZE]
        texts = [it["text"] for it in batch]
        embeddings = embed_texts(texts, cfg)
        _store_embeddings(cur, source_type, batch, embeddings)
        total += len(batch)
    return total


def phase_embed_database(conn, cfg, dry_run=False, verbose=False):
    cur = conn.cursor()
    total = 0
    for name, (query, source_type) in TABLE_EMBED_SPECS.items():
        count = _embed_table(cur, query, source_type, cfg)
        if count:
            total += count
            if verbose:
                logger.info(f"  Embedded {count} {name} records")
    return total


# ---- Embed research tables ----
def phase_embed_research(conn, cfg, dry_run=False, verbose=False):
    cur = conn.cursor()
    total = 0

    # research_task
    cur.execute("SELECT id, query AS text FROM research_tasks WHERE query IS NOT NULL")
    rows = cur.fetchall()
    items = [{"id": r[0], "text": r[1]} for r in rows if not _already_embedded(cur, "research_task", r[0])]
    if items:
        for i in range(0, len(items), EMBED_BATCH_SIZE):
            batch = items[i : i + EMBED_BATCH_SIZE]
            embeddings = embed_texts([it["text"] for it in batch], cfg)
            _store_embeddings(cur, "research_task", batch, embeddings)
            total += len(batch)

    # research_finding (is_current=true)
    cur.execute("SELECT id, content AS text FROM research_findings WHERE is_current = true AND content IS NOT NULL")
    rows = cur.fetchall()
    items = [{"id": r[0], "text": r[1]} for r in rows if not _already_embedded(cur, "research_finding", r[0])]
    if items:
        for i in range(0, len(items), EMBED_BATCH_SIZE):
            batch = items[i : i + EMBED_BATCH_SIZE]
            embeddings = embed_texts([it["text"] for it in batch], cfg)
            _store_embeddings(cur, "research_finding", batch, embeddings)
            total += len(batch)

    # research_conclusion (is_current=true)
    cur.execute("SELECT id, content AS text FROM research_conclusions WHERE is_current = true AND content IS NOT NULL")
    rows = cur.fetchall()
    items = [{"id": r[0], "text": r[1]} for r in rows if not _already_embedded(cur, "research_conclusion", r[0])]
    if items:
        for i in range(0, len(items), EMBED_BATCH_SIZE):
            batch = items[i : i + EMBED_BATCH_SIZE]
            embeddings = embed_texts([it["text"] for it in batch], cfg)
            _store_embeddings(cur, "research_conclusion", batch, embeddings)
            total += len(batch)

    if verbose and total:
        logger.info(f"  Embedded {total} research records")
    return total


# ---- Embed memory files ----
def _chunk_text(text, chunk_size=1000, overlap=200):
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + chunk_size, len(text))
        chunks.append(text[start:end])
        start += chunk_size - overlap
        if start >= len(text):
            break
    return chunks


def phase_embed_files(conn, cfg, dry_run=False, verbose=False):
    cur = conn.cursor()
    total = 0

    memory_dir = Path.home() / ".openclaw" / "workspace" / "memory"
    if memory_dir.exists():
        for md_file in sorted(memory_dir.glob("*.md")):
            text = md_file.read_text(encoding="utf-8")
            chunks = _chunk_text(text)
            for idx, chunk in enumerate(chunks):
                source_id = f"{md_file.name}#{idx}"
                if _already_embedded(cur, "memory_file", source_id):
                    continue
                emb = embed_single(chunk, cfg)
                if emb:
                    _store_embeddings(cur, "memory_file", [{"id": source_id, "text": chunk}], [emb])
                    total += 1

    memory_md = Path.home() / ".openclaw" / "workspace" / "MEMORY.md"
    if memory_md.exists():
        text = memory_md.read_text(encoding="utf-8")
        chunks = _chunk_text(text)
        for idx, chunk in enumerate(chunks):
            source_id = f"MEMORY.md#{idx}"
            if _already_embedded(cur, "memory_file", source_id):
                continue
            emb = embed_single(chunk, cfg)
            if emb:
                _store_embeddings(cur, "memory_file", [{"id": source_id, "text": chunk}], [emb])
                total += 1

    if verbose and total:
        logger.info(f"  Embedded {total} memory file chunks")
    return total


def phase_embed(conn, args):
    cfg = load_embedding_config()
    total = 0
    total += phase_embed_database(conn, cfg, args.dry_run, args.verbose)
    total += phase_embed_research(conn, cfg, args.dry_run, args.verbose)
    total += phase_embed_files(conn, cfg, args.dry_run, args.verbose)
    if args.verbose:
        logger.info(f"Embed phase complete: {total} items embedded")
    return total


# ---------------------------------------------------------------------------
# Phase 3: Cross-key consolidation
# ---------------------------------------------------------------------------
def cross_key_consolidation(conn, dry_run=False, verbose=False):
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    try:
        cur.execute("""
            SELECT DISTINCT ef.entity_id
            FROM entity_facts ef
            JOIN memory_embeddings me ON me.source_type = 'entity_fact' AND me.source_id = ef.id::text
        """)
    except psycopg2.Error as e:
        logger.error(f"Cross-key consolidation dimension mismatch or query error: {e}")
        return 0, set()

    entity_ids = [row[0] for row in cur.fetchall()]

    total_merged = 0
    modified_survivor_ids = set()

    for entity_id in entity_ids:
        try:
            cur.execute("""
                SELECT ef1.id AS id1, ef2.id AS id2,
                       ef1.key AS key1, ef2.key AS key2,
                       ef1.value AS val1, ef2.value AS val2,
                       ef1.confidence AS conf1, ef2.confidence AS conf2,
                       1 - (me1.embedding <=> me2.embedding) AS cosine_sim
                FROM entity_facts ef1
                JOIN entity_facts ef2 ON ef1.entity_id = ef2.entity_id AND ef1.id < ef2.id
                JOIN memory_embeddings me1 ON me1.source_type = 'entity_fact' AND me1.source_id = ef1.id::text
                JOIN memory_embeddings me2 ON me2.source_type = 'entity_fact' AND me2.source_id = ef2.id::text
                WHERE ef1.entity_id = %s
                  AND ef1.key != ef2.key
                  AND 1 - (me1.embedding <=> me2.embedding) >= 0.92
                ORDER BY cosine_sim DESC
            """, (entity_id,))
        except psycopg2.Error as e:
            logger.error(f"Dimension mismatch in cross-key query for entity {entity_id}: {e}")
            continue

        pairs = cur.fetchall()
        absorbed_ids = set()

        for row in pairs:
            id1, id2 = row["id1"], row["id2"]
            if id1 in absorbed_ids or id2 in absorbed_ids:
                continue
            if row["conf1"] >= row["conf2"]:
                survivor, absorbed = id1, id2
            else:
                survivor, absorbed = id2, id1

            if not dry_run:
                cur.execute("SELECT merge_facts(%s, %s)", (survivor, absorbed))
            absorbed_ids.add(absorbed)
            modified_survivor_ids.add(survivor)
            total_merged += 1
            if verbose:
                logger.info(
                    f"  [cross-key, sim={row['cosine_sim']:.3f}] "
                    f"merged {row['key2']}:{row['val2']} into {row['key1']}:{row['val1']}"
                )

    return total_merged, modified_survivor_ids


# ---------------------------------------------------------------------------
# Phase 4: Same-key deduplication (original production logic preserved)
# ---------------------------------------------------------------------------
def merge_duplicates(conn, dry_run=False, verbose=False):
    """Find and merge/categorize duplicate entity_facts using three-tier confidence system.

    Uses pg_trgm similarity() for text comparison. Three tiers:
    - High (similarity >= 0.80): auto-merge via merge_facts(survivor_id, absorbed_id)
        survivor = higher confidence fact; extraction_counts are summed by merge_facts
    - Medium (0.50-0.79 similarity): add to daily report for manual review
    - Low (< 0.50): skip entirely
    """
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

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
    modified_survivor_ids = set()
    high_merges = 0
    medium_candidates = []

    for row in pairs:
        id1, id2 = row['id1'], row['id2']

        if id1 in absorbed_ids or id2 in absorbed_ids:
            continue

        sim = row['sim']

        if sim >= 0.80:
            if row['conf1'] > row['conf2']:
                survivor, absorbed = id1, id2
            elif row['conf2'] > row['conf1']:
                survivor, absorbed = id2, id1
            elif row['date1'] and row['date2'] and row['date1'] > row['date2']:
                survivor, absorbed = id1, id2
            elif row['date2'] and row['date1'] and row['date2'] > row['date1']:
                survivor, absorbed = id2, id1
            else:
                survivor, absorbed = (id1, id2) if id1 < id2 else (id2, id1)

            if not dry_run:
                cur.execute("SELECT merge_facts(%s, %s)", (survivor, absorbed))

            absorbed_ids.add(absorbed)
            modified_survivor_ids.add(survivor)
            high_merges += 1

            if verbose:
                logger.info(f"  [high, sim={sim:.2f}] {row['key']}: auto-merged ID {absorbed} into ID {survivor}")

        elif sim >= 0.50:
            medium_candidates.append({
                'id1': id1, 'id2': id2,
                'entity_id': row['entity_id'], 'key': row['key'],
                'value1': row['value1'], 'value2': row['value2'],
                'similarity': sim
            })
            if verbose:
                logger.info(f"  [medium, sim={sim:.2f}] {row['key']}: '{row['value1']}' vs '{row['value2']}' — flagged for review")

    if verbose:
        logger.info(f"Found {high_merges} high-confidence merges, {len(medium_candidates)} medium-confidence candidates")

    if medium_candidates:
        write_dedup_report(medium_candidates, dry_run)

    return {'high_merges': high_merges, 'medium_count': len(medium_candidates), 'medium_candidates': medium_candidates, 'modified_ids': modified_survivor_ids}


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
        for c in candidates:
            f.write(f"- fact {c['id1']} vs {c['id2']} (entity {c['entity_id']}, key={c['key']}): "
                    f"'{c['value1']}' vs '{c['value2']}' (sim={c['similarity']:.3f})\n")
    logger.info(f"Wrote dedup report with {len(candidates)} candidates to {report_path}")


# ---------------------------------------------------------------------------
# Phase 5: Confidence decay (original production logic preserved)
# ---------------------------------------------------------------------------
import math


def calculate_decay(durability, days_since_confirmed, custom_rate=None):
    """Calculate confidence decay factor based on durability and time."""
    if days_since_confirmed <= 0:
        return 1.0
    rate = custom_rate if custom_rate is not None else DECAY_RATES.get(durability, 0.01)
    return math.exp(-rate * days_since_confirmed)


def apply_decay_to_entity_facts(conn, dry_run=False, verbose=False):
    """Apply confidence decay to entity_facts table."""
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
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
        if row['last_confirmed_at'] is None:
            continue
        days_since = (datetime.now(timezone.utc) - row['last_confirmed_at']).days
        if days_since <= 0:
            continue
        if row['expires'] is not None and row['expires'] < datetime.now(timezone.utc):
            decay_factor = 0.0
        else:
            decay_factor = calculate_decay(row['durability'], days_since, row['decay_rate'])
        new_confidence = row['confidence'] * decay_factor
        if abs(new_confidence - row['confidence']) > 0.001:
            updates.append({'id': row['id'], 'new_confidence': new_confidence})
    if verbose:
        logger.info(f"Entity facts to decay: {len(updates)}")
    if not dry_run and updates:
        psycopg2.extras.execute_batch(cur, """
            UPDATE entity_facts SET confidence = %(new_confidence)s, updated_at = NOW() WHERE id = %(id)s
        """, updates, page_size=100)
    return len(updates)


def apply_decay_to_table(conn, table_name, decay_rate, dry_run=False, verbose=False):
    """Apply confidence decay to a specific table."""
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    # Check if table has updated_at column
    cur.execute("""
        SELECT 1 FROM information_schema.columns
        WHERE table_name = %s AND column_name = 'updated_at'
    """, (table_name,))
    has_updated_at = cur.fetchone() is not None

    cur.execute(f"""
        SELECT id, confidence, last_confirmed_at FROM {table_name} WHERE confidence > %s
    """, (ARCHIVE_THRESHOLD,))
    rows = cur.fetchall()
    updates = []
    for row in rows:
        if row['last_confirmed_at'] is None:
            continue
        days_since = (datetime.now(timezone.utc) - row['last_confirmed_at']).days
        if days_since <= 0:
            continue
        decay_factor = math.exp(-decay_rate * days_since)
        new_confidence = row['confidence'] * decay_factor
        if abs(new_confidence - row['confidence']) > 0.001:
            updates.append({'id': row['id'], 'new_confidence': new_confidence})
    if verbose and updates:
        logger.info(f"{table_name} to decay: {len(updates)}")
    if not dry_run and updates:
        if has_updated_at:
            psycopg2.extras.execute_batch(cur, f"""
                UPDATE {table_name} SET confidence = %(new_confidence)s, updated_at = NOW() WHERE id = %(id)s
            """, updates, page_size=100)
        else:
            psycopg2.extras.execute_batch(cur, f"""
                UPDATE {table_name} SET confidence = %(new_confidence)s WHERE id = %(id)s
            """, updates, page_size=100)
    return len(updates)


def apply_decay(conn, args):
    """Run confidence decay across all tables."""
    decayed_facts = apply_decay_to_entity_facts(conn, args.dry_run, args.verbose)
    decayed_events = apply_decay_to_table(conn, 'events', TABLE_DECAY_RATES['events'], args.dry_run, args.verbose)
    decayed_lessons = apply_decay_to_table(conn, 'lessons', TABLE_DECAY_RATES['lessons'], args.dry_run, args.verbose)
    decayed_embeddings = apply_decay_to_table(conn, 'memory_embeddings', TABLE_DECAY_RATES['memory_embeddings'], args.dry_run, args.verbose)
    return decayed_facts, decayed_events, decayed_lessons, decayed_embeddings


def archive_low_confidence(conn, dry_run=False, verbose=False):
    """Move low-confidence entity_facts to archive table."""
    cur = conn.cursor()
    if dry_run:
        cur.execute("""
            SELECT COUNT(*) FROM entity_facts
            WHERE confidence < %s
              AND learned_at < NOW() - INTERVAL '%s days'
              AND durability != 'permanent'
        """, (ARCHIVE_THRESHOLD, MIN_AGE_DAYS))
        return cur.fetchone()[0]
    cur.execute("""
        WITH archived AS (
            DELETE FROM entity_facts
            WHERE confidence < %s
              AND learned_at < NOW() - INTERVAL '%s days'
              AND durability != 'permanent'
            RETURNING id, entity_id, key, value, data, confidence, learned_at,
                      updated_at, visibility, privacy_scope, visibility_reason,
                      last_confirmed_at, decay_rate, extraction_count,
                      durability, category, expires
        )
        INSERT INTO entity_facts_archive (
            id, entity_id, key, value, data, confidence, learned_at,
            updated_at, visibility, privacy_scope, visibility_reason,
            last_confirmed_at, decay_rate, extraction_count,
            durability, category, expires, archived_at, archive_reason, archived_by
        )
        SELECT
            id, entity_id, key, value, data, confidence, learned_at,
            updated_at, visibility, privacy_scope, visibility_reason,
            last_confirmed_at, decay_rate, extraction_count,
            durability, category, expires,
            NOW() as archived_at, 'low_confidence' as archive_reason, 'maintenance_script' as archived_by
        FROM archived
    """, (ARCHIVE_THRESHOLD, MIN_AGE_DAYS))
    archived = cur.rowcount
    if verbose:
        logger.info(f"  Archived {archived} low-confidence facts")
    return archived


def purge_old_archives(conn, dry_run=False, verbose=False):
    """Hard delete archives older than 1 year."""
    cur = conn.cursor()
    if dry_run:
        cur.execute("SELECT COUNT(*) FROM entity_facts_archive WHERE archived_at < NOW() - INTERVAL '1 year'")
        return cur.fetchone()[0]
    cur.execute("DELETE FROM entity_facts_archive WHERE archived_at < NOW() - INTERVAL '1 year'")
    purged = cur.rowcount
    if verbose:
        logger.info(f"  Purged {purged} old archived facts")
    return purged


# ---------------------------------------------------------------------------
# Phase 6: Ghost entity cleanup
# ---------------------------------------------------------------------------
def ghost_entity_cleanup(conn, dry_run=False, verbose=False):
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    # Sub-phase A: Pattern-based ghosts (e.g. "entity 21" -> entity id 21)
    cur.execute("SELECT id, name FROM entities WHERE name ~* '^entity \\d+$'")
    pattern_merges = 0
    for row in cur.fetchall():
        target_id = int(re.search(r"\d+", row["name"]).group())
        cur.execute("SELECT id FROM entities WHERE id = %s AND id != %s", (target_id, row["id"]))
        if cur.fetchone():
            if not dry_run:
                cur.execute("SELECT merge_entities(%s, %s)", (target_id, row["id"]))
            pattern_merges += 1
            if verbose:
                logger.info(f"  Ghost merge: '{row['name']}' (id={row['id']}) -> entity {target_id}")

    # Sub-phase B: Zero-fact + zero-FK orphans
    cur.execute("""
        SELECT tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND ccu.table_name = 'entities' AND ccu.column_name = 'id'
          AND tc.table_name != 'entity_facts'
    """)
    fk_tables = cur.fetchall()

    cur.execute("""
        SELECT e.id, e.name FROM entities e
        LEFT JOIN entity_facts ef ON e.id = ef.entity_id
        GROUP BY e.id HAVING COUNT(ef.id) = 0
    """)
    zero_fact_entities = cur.fetchall()

    deleted = 0
    for entity in zero_fact_entities:
        has_fk = False
        for table_name, col_name in fk_tables:
            cur.execute(
                f"SELECT 1 FROM {table_name} WHERE {col_name} = %s LIMIT 1",
                (entity["id"],),
            )
            if cur.fetchone():
                has_fk = True
                break
        if not has_fk:
            if not dry_run:
                cur.execute("DELETE FROM entities WHERE id = %s", (entity["id"],))
            deleted += 1
            if verbose:
                logger.info(f"  Deleted orphan: '{entity['name']}' (id={entity['id']})")

    # Sub-phase C: Low-fact entities (1-2 facts) -> review queue
    cur.execute("""
        SELECT e.id, e.name, COUNT(ef.id) AS fact_count
        FROM entities e JOIN entity_facts ef ON e.id = ef.entity_id
        GROUP BY e.id HAVING COUNT(ef.id) <= 2
    """)
    low_fact = cur.fetchall()
    if low_fact:
        review_path = Path.home() / ".openclaw" / "logs" / f"ghost-review-{datetime.now():%Y-%m-%d}.md"
        review_path.parent.mkdir(parents=True, exist_ok=True)
        with open(review_path, "w") as f:
            f.write(f"# Low-Fact Entity Review — {datetime.now():%Y-%m-%d}\n\n")
            for e in low_fact:
                f.write(f"- Entity {e['id']}: {e['name']} ({e['fact_count']} facts)\n")
        if verbose:
            logger.info(f"  Wrote {len(low_fact)} low-fact entities to {review_path}")

    return pattern_merges, deleted, len(low_fact)


# ---------------------------------------------------------------------------
# Phase 7: Entity-level deduplication
# ---------------------------------------------------------------------------
def entity_dedup(conn, dry_run=False, verbose=False):
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cur.execute("""
        SELECT e1.id AS id1, e2.id AS id2, e1.name AS name1, e2.name AS name2,
               e1.type AS type1, e2.type AS type2,
               similarity(LOWER(e1.name), LOWER(e2.name)) AS name_sim
        FROM entities e1
        JOIN entities e2 ON e1.id < e2.id AND e1.type = e2.type
        WHERE similarity(LOWER(e1.name), LOWER(e2.name)) >= 0.5
    """)
    candidates = cur.fetchall()

    auto_merged = 0
    review_candidates = []
    absorbed_ids = set()

    for cand in candidates:
        if cand["id1"] in absorbed_ids or cand["id2"] in absorbed_ids:
            continue

        # Skip candidates of different types (defensive — SQL already filters)
        if cand.get("type1") != cand.get("type2"):
            continue

        cur.execute("SELECT COUNT(*) FROM entity_facts WHERE entity_id = %s", (cand["id1"],))
        count1 = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM entity_facts WHERE entity_id = %s", (cand["id2"],))
        count2 = cur.fetchone()[0]

        if count1 + count2 == 0:
            continue

        cur.execute("""
            SELECT COUNT(*) FROM entity_facts f1
            JOIN entity_facts f2 ON f1.key = f2.key
              AND similarity(LOWER(f1.value), LOWER(f2.value)) >= 0.7
            WHERE f1.entity_id = %s AND f2.entity_id = %s
        """, (cand["id1"], cand["id2"]))
        shared = cur.fetchone()[0]

        total = max(count1, count2)
        overlap = shared / total if total > 0 else 0
        overall = 0.4 * cand["name_sim"] + 0.6 * overlap

        if overall >= 0.80:
            survivor = cand["id1"] if count1 >= count2 else cand["id2"]
            absorbed = cand["id2"] if survivor == cand["id1"] else cand["id1"]
            if not dry_run:
                cur.execute("SELECT merge_entities(%s, %s)", (survivor, absorbed))
            absorbed_ids.add(absorbed)
            auto_merged += 1
            if verbose:
                logger.info(
                    f"  Entity auto-merge: '{cand['name2']}' into '{cand['name1']}' (score={overall:.2f})"
                )
        elif overall >= 0.50:
            review_candidates.append({
                "id1": cand["id1"], "name1": cand["name1"],
                "id2": cand["id2"], "name2": cand["name2"],
                "score": overall, "name_sim": cand["name_sim"],
                "fact_overlap": overlap,
            })

    if review_candidates:
        review_path = Path.home() / ".openclaw" / "logs" / f"entity-dedup-review-{datetime.now():%Y-%m-%d}.md"
        review_path.parent.mkdir(parents=True, exist_ok=True)
        with open(review_path, "w") as f:
            f.write(f"# Entity Dedup Review — {datetime.now():%Y-%m-%d}\n\n")
            for c in review_candidates:
                f.write(
                    f"- {c['name1']} (id={c['id1']}) vs {c['name2']} (id={c['id2']}) "
                    f"— score={c['score']:.2f}\n"
                )
        if verbose:
            logger.info(f"  Wrote {len(review_candidates)} review candidates to {review_path}")

    return auto_merged, len(review_candidates)


# ---------------------------------------------------------------------------
# Phase 8: Clean orphaned embeddings
# ---------------------------------------------------------------------------
def clean_orphaned_embeddings(conn, dry_run=False, verbose=False):
    cur = conn.cursor()
    if dry_run:
        cur.execute("""
            SELECT COUNT(*) FROM memory_embeddings me
            WHERE me.source_type = 'entity_fact'
              AND NOT EXISTS (SELECT 1 FROM entity_facts ef WHERE ef.id::text = me.source_id)
        """)
        count = cur.fetchone()[0]
    else:
        cur.execute("""
            DELETE FROM memory_embeddings me
            WHERE me.source_type = 'entity_fact'
              AND NOT EXISTS (SELECT 1 FROM entity_facts ef WHERE ef.id::text = me.source_id)
        """)
        count = cur.rowcount

    # Also clean orphaned entity embeddings
    if dry_run:
        cur.execute("""
            SELECT COUNT(*) FROM memory_embeddings me
            WHERE me.source_type = 'entity'
              AND NOT EXISTS (SELECT 1 FROM entities e WHERE e.id::text = me.source_id)
        """)
        count += cur.fetchone()[0]
    else:
        cur.execute("""
            DELETE FROM memory_embeddings me
            WHERE me.source_type = 'entity'
              AND NOT EXISTS (SELECT 1 FROM entities e WHERE e.id::text = me.source_id)
        """)
        count += cur.rowcount

    if verbose:
        logger.info(f"  Cleaned {count} orphaned embeddings")
    return count


# ---------------------------------------------------------------------------
# Re-embed modified facts
# ---------------------------------------------------------------------------
def reembed_modified_facts(conn, modified_fact_ids, dry_run=False, verbose=False):
    """Delete stale embeddings for modified facts and re-embed them."""
    if not modified_fact_ids:
        return 0
    cfg = load_embedding_config()
    cur = conn.cursor()
    id_list = [str(fid) for fid in modified_fact_ids]
    # Delete stale embeddings
    if not dry_run:
        cur.execute("""
            DELETE FROM memory_embeddings
            WHERE source_type = 'entity_fact'
              AND source_id = ANY(%s)
        """, (id_list,))
        if verbose:
            logger.info(f"  Deleted {cur.rowcount} stale embeddings for modified facts")
    # Re-embed
    cur.execute("""
        SELECT ef.id, e.name || ' - ' || ef.key || ': ' || ef.value AS text
        FROM entity_facts ef JOIN entities e ON e.id = ef.entity_id
        WHERE ef.id = ANY(%s)
    """, (list(modified_fact_ids),))
    rows = cur.fetchall()
    items = [{"id": r[0], "text": r[1]} for r in rows if r[1]]
    if not items:
        return 0
    total = 0
    for i in range(0, len(items), EMBED_BATCH_SIZE):
        batch = items[i:i+EMBED_BATCH_SIZE]
        texts = [it["text"] for it in batch]
        embeddings = embed_texts(texts, cfg)
        if not dry_run:
            _store_embeddings(cur, "entity_fact", batch, embeddings)
        total += len(batch)
    if verbose:
        logger.info(f"  Re-embedded {total} modified facts")
    return total


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def parse_args():
    parser = argparse.ArgumentParser(description="Unified memory maintenance")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without modifying")
    parser.add_argument("--verbose", action="store_true", help="Log detailed per-item actions")
    parser.add_argument("--force", action="store_true", help="Ignore cooldown")
    parser.add_argument("--state-file", default=DEFAULT_STATE_FILE, help="Path to cooldown state file")
    parser.add_argument("--skip-embed", action="store_true", help="Skip embedding phase")
    parser.add_argument("--skip-consolidation", action="store_true", help="Skip cross-key consolidation")
    parser.add_argument("--skip-dedup", action="store_true", help="Skip same-key deduplication")
    parser.add_argument("--skip-decay", action="store_true", help="Skip confidence decay")
    parser.add_argument("--skip-ghost-cleanup", action="store_true", help="Skip ghost entity cleanup")
    parser.add_argument("--skip-entity-dedup", action="store_true", help="Skip entity deduplication")
    return parser.parse_args()


def main():
    args = parse_args()

    if not check_cooldown(args.state_file, args.force):
        return 0

    conn = psycopg2.connect("")
    conn.autocommit = False

    try:
        embed_count = 0
        if not args.skip_embed:
            embed_count = phase_embed(conn, args)

        cross_merged = 0
        modified_fact_ids = set()
        if not args.skip_consolidation:
            cross_merged, xkey_modified = cross_key_consolidation(conn, args.dry_run, args.verbose)
            modified_fact_ids.update(xkey_modified)

        dup_merged = 0
        medium_report_count = 0
        if not args.skip_dedup:
            dedup_result = merge_duplicates(conn, args.dry_run, args.verbose)
            dup_merged = dedup_result['high_merges']
            medium_report_count = dedup_result['medium_count']
            modified_fact_ids.update(dedup_result.get('modified_ids', set()))

        if not args.skip_decay:
            apply_decay(conn, args)

        pattern_merges = deleted_orphans = low_fact_count = 0
        if not args.skip_ghost_cleanup:
            pattern_merges, deleted_orphans, low_fact_count = ghost_entity_cleanup(
                conn, args.dry_run, args.verbose
            )

        auto_merged = review_count = 0
        if not args.skip_entity_dedup:
            auto_merged, review_count = entity_dedup(conn, args.dry_run, args.verbose)

        reembedded = 0
        if not args.skip_embed and modified_fact_ids:
            reembedded = reembed_modified_facts(conn, modified_fact_ids, args.dry_run, args.verbose)

        cleaned = 0
        if not args.skip_embed:
            cleaned = clean_orphaned_embeddings(conn, args.dry_run, args.verbose)

        archived = archive_low_confidence(conn, args.dry_run, args.verbose)
        purged = purge_old_archives(conn, args.dry_run, args.verbose)

        if not args.dry_run:
            conn.commit()
            update_state(args.state_file)
            logger.info("Committed all changes.")
        else:
            logger.info("DRY RUN — no changes committed.")
            conn.rollback()

        logger.info("=" * 50)
        logger.info("Memory Maintenance Summary")
        logger.info("=" * 50)
        logger.info(f"  Embedded:               {embed_count}")
        logger.info(f"  Cross-key merged:       {cross_merged}")
        logger.info(f"  Same-key merged:        {dup_merged}")
        logger.info(f"  Dedup review queued:    {medium_report_count}")
        logger.info(f"  Ghost pattern merges:   {pattern_merges}")
        logger.info(f"  Orphan entities deleted:{deleted_orphans}")
        logger.info(f"  Low-fact entities:      {low_fact_count}")
        logger.info(f"  Entity auto-merges:     {auto_merged}")
        logger.info(f"  Entity review queued:   {review_count}")
        logger.info(f"  Re-embedded modified:   {reembedded}")
        logger.info(f"  Orphaned embeddings:    {cleaned}")
        logger.info(f"  Archived facts:         {archived}")
        logger.info(f"  Purged old archives:    {purged}")
    except Exception as e:
        conn.rollback()
        logger.error(f"Transaction rolled back due to error: {e}")
        raise
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    sys.exit(main())
