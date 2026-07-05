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
# Custom exceptions
# ---------------------------------------------------------------------------
class OllamaConnectionError(Exception):
    """Raised when Ollama is unreachable (network-level failure, not model errors)."""
    pass


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DEFAULT_STATE_FILE = os.path.expanduser("~/.openclaw/state/memory-maintenance-last-run.json")
COOLDOWN_HOURS = 4
DECAY_COOLDOWN_HOURS = 24
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
            "model": "snowflake-arctic-embed2",
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


def check_decay_cooldown(state_file, force=False):
    if force:
        return True
    try:
        with open(state_file) as f:
            state = json.load(f)
        last_decay_run = datetime.fromisoformat(state["last_decay_run"])
        if datetime.now(timezone.utc) - last_decay_run < timedelta(hours=DECAY_COOLDOWN_HOURS):
            logger.info(
                f"Decay cooldown active — last run {last_decay_run.isoformat()}, skipping"
            )
            return False
    except (FileNotFoundError, KeyError, json.JSONDecodeError):
        pass
    return True


def update_state(state_file, ran_decay=False):
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    state = {"last_run": datetime.now(timezone.utc).isoformat()}
    try:
        with open(state_file) as f:
            state.update(json.load(f))
    except (FileNotFoundError, json.JSONDecodeError):
        pass
    state["last_run"] = datetime.now(timezone.utc).isoformat()
    if ran_decay:
        state["last_decay_run"] = datetime.now(timezone.utc).isoformat()
    with open(state_file, "w") as f:
        json.dump(state, f)


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
    except requests.exceptions.ConnectionError as e:
        raise OllamaConnectionError(f"Cannot reach Ollama at {url}: {e}") from e
    except requests.exceptions.Timeout as e:
        raise OllamaConnectionError(f"Ollama connection timed out at {url}: {e}") from e
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
    except requests.exceptions.ConnectionError as e:
        raise OllamaConnectionError(f"Cannot reach Ollama at {url}: {e}") from e
    except requests.exceptions.Timeout as e:
        raise OllamaConnectionError(f"Ollama connection timed out at {url}: {e}") from e
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
    # #245: fixed column: lessons.lesson (not .content)
    "lesson": (
        "SELECT id, lesson AS text FROM lessons WHERE lesson IS NOT NULL",
        "lesson",
    ),
    "event": (
        "SELECT id, description AS text FROM events WHERE description IS NOT NULL",
        "event",
    ),
    # #233: stale table entry removed (see GitHub issue #233)
    # #259: stale table entry removed (see GitHub issue #259)
    "media_consumed": (
        "SELECT id, title AS text FROM media_consumed WHERE title IS NOT NULL",
        "media_consumed",
    ),
    "vocabulary": (
        "SELECT id, word AS text FROM vocabulary WHERE word IS NOT NULL",
        "vocabulary",
    ),
    # #259: table renamed library → library_works; source_type stays 'library' for backward compat
    # (187 existing rows in memory_embeddings use source_type='library')
    "library": (
        "SELECT id, title AS text FROM library_works WHERE title IS NOT NULL",
        "library",
    ),
    # #235: new tables
    "journal_entry": (
        "SELECT id, content AS text FROM journal_entries WHERE content IS NOT NULL",
        "journal_entry",
    ),
    "music_work": (
        "SELECT id, title || ': ' || COALESCE(description, '') AS text FROM music_works WHERE title IS NOT NULL",
        "music_work",
    ),
    "workflow_run": (
        "SELECT id, trim(COALESCE(trigger_context, '') || ' ' || COALESCE(notes, '')) AS text FROM workflow_runs",
        "workflow_run",
    ),
    "income_source": (
        "SELECT id, name || ': ' || COALESCE(description, '') AS text FROM income_sources WHERE name IS NOT NULL",
        "income_source",
    ),
}


def _embed_table(cur, query, source_type, cfg):
    cur.execute(query)
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
    """Embed all TABLE_EMBED_SPECS tables.

    Returns (total_embedded, success_count, warn_count).
    psycopg2 errors per table are caught, logged as warnings, and the table is skipped.
    OllamaConnectionError propagates (fatal -- Ollama is unreachable).
    """
    total = 0
    success_count = 0
    warn_count = 0
    cur = conn.cursor()
    for idx, (name, (query, source_type)) in enumerate(TABLE_EMBED_SPECS.items()):
        sp = f"embed_sp_{idx}"
        try:
            cur.execute(f"SAVEPOINT {sp}")
            count = _embed_table(cur, query, source_type, cfg)
            cur.execute(f"RELEASE SAVEPOINT {sp}")
            success_count += 1
            if count:
                total += count
                if verbose:
                    logger.info(f"  Embedded {count} {name} records")
        except psycopg2.Error as e:
            try:
                cur.execute(f"ROLLBACK TO SAVEPOINT {sp}")
            except psycopg2.Error:
                pass
            logger.warning(f"[WARN] Skipping table '{name}' ({source_type}): {e}")
            warn_count += 1
        # OllamaConnectionError intentionally not caught here -- propagates to phase_embed
    return total, success_count, warn_count


# ---- Embed research tables ----
def phase_embed_research(conn, cfg, dry_run=False, verbose=False):
    """Embed research tables with per-sub-query error isolation.

    Returns (total_embedded, warn_count).
    psycopg2 errors per sub-query are caught and logged as warnings.
    OllamaConnectionError propagates (fatal).
    """
    cur = conn.cursor()
    total = 0
    warn_count = 0

    # research_task
    try:
        cur.execute("SAVEPOINT embed_research_task")
        cur.execute("SELECT id, query AS text FROM research_tasks WHERE query IS NOT NULL")
        rows = cur.fetchall()
        items = [{"id": r[0], "text": r[1]} for r in rows if not _already_embedded(cur, "research_task", r[0])]
        if items:
            for i in range(0, len(items), EMBED_BATCH_SIZE):
                batch = items[i : i + EMBED_BATCH_SIZE]
                embeddings = embed_texts([it["text"] for it in batch], cfg)
                _store_embeddings(cur, "research_task", batch, embeddings)
                total += len(batch)
        cur.execute("RELEASE SAVEPOINT embed_research_task")
    except psycopg2.Error as e:
        try:
            cur.execute("ROLLBACK TO SAVEPOINT embed_research_task")
        except psycopg2.Error:
            pass
        logger.warning(f"[WARN] Skipping research_task: {e}")
        warn_count += 1

    # research_finding (is_current=true)
    try:
        cur.execute("SAVEPOINT embed_research_finding")
        cur.execute("SELECT id, content AS text FROM research_findings WHERE is_current = true AND content IS NOT NULL")
        rows = cur.fetchall()
        items = [{"id": r[0], "text": r[1]} for r in rows if not _already_embedded(cur, "research_finding", r[0])]
        if items:
            for i in range(0, len(items), EMBED_BATCH_SIZE):
                batch = items[i : i + EMBED_BATCH_SIZE]
                embeddings = embed_texts([it["text"] for it in batch], cfg)
                _store_embeddings(cur, "research_finding", batch, embeddings)
                total += len(batch)
        cur.execute("RELEASE SAVEPOINT embed_research_finding")
    except psycopg2.Error as e:
        try:
            cur.execute("ROLLBACK TO SAVEPOINT embed_research_finding")
        except psycopg2.Error:
            pass
        logger.warning(f"[WARN] Skipping research_finding: {e}")
        warn_count += 1

    # #259 fix: research_conclusion uses COALESCE(title, summary) as text source -- title+summary columns only
    try:
        cur.execute("SAVEPOINT embed_research_conclusion")
        cur.execute("""
            SELECT id, trim(COALESCE(title || ' ', '') || summary) AS text
            FROM research_conclusions
            WHERE is_current = true AND summary IS NOT NULL
        """)
        rows = cur.fetchall()
        items = [{"id": r[0], "text": r[1]} for r in rows if not _already_embedded(cur, "research_conclusion", r[0])]
        if items:
            for i in range(0, len(items), EMBED_BATCH_SIZE):
                batch = items[i : i + EMBED_BATCH_SIZE]
                embeddings = embed_texts([it["text"] for it in batch], cfg)
                _store_embeddings(cur, "research_conclusion", batch, embeddings)
                total += len(batch)
        cur.execute("RELEASE SAVEPOINT embed_research_conclusion")
    except psycopg2.Error as e:
        try:
            cur.execute("ROLLBACK TO SAVEPOINT embed_research_conclusion")
        except psycopg2.Error:
            pass
        logger.warning(f"[WARN] Skipping research_conclusion: {e}")
        warn_count += 1

    if verbose and total:
        logger.info(f"  Embedded {total} research records")
    return total, warn_count


# ---- Embed memory files ----
_HEADER_RE = re.compile(r"^#{1,6}\s")
_SENTENCE_RE = re.compile(r"(?<=[.!?])\s+(?=\S)")


def _chunk_text(text, chunk_size=1000, overlap=200):
    """Boundary-aware chunker for memory file embeddings.

    Splits text on paragraph breaks and markdown headers (# through ######),
    merges adjacent short paragraphs greedily up to ~80% of ``chunk_size``,
    and splits oversized paragraphs at sentence boundaries, then word
    boundaries, then single-token boundaries as a last resort.

    Headers always start a new chunk and stay attached to the following
    content. Fenced code blocks (`` ``` ``) are treated as atomic units:
    they are never split internally, even if they exceed ``chunk_size``.
    Single unbroken tokens (no whitespace) longer than ``chunk_size`` are
    likewise emitted as single oversized chunks. These two cases are the
    only documented atomic exceptions to the nominal chunk-size ceiling.

    Overlap is boundary-aware: the suffix of the previous chunk that is
    prepended to the next chunk begins at a sentence or paragraph boundary
    where possible. Consequently a chunk may be up to ``chunk_size + overlap``
    characters long.

    Because chunking is structure-dependent (paragraph/header boundaries),
    appending content to a previously-embedded file can shift earlier chunk
    boundaries. After editing a file that has already been embedded, run with
    ``--reindex-files`` to delete the old embeddings and regenerate clean
    boundaries for the whole file.

    Args:
        text: Input text to chunk.
        chunk_size: Target maximum chunk size (default 1000).
        overlap: Target overlap between consecutive chunks (default 200).

    Returns:
        List of chunk strings. Empty or whitespace-only input returns ``[]``.
    """
    if text is None:
        return []

    # Normalize line endings and discard leading/trailing whitespace.
    text = text.replace("\r\n", "\n").strip()
    if not text:
        return []

    units = _parse_units(text)
    if not units:
        return []

    candidate_chunks = _merge_units(units, chunk_size)

    split_chunks = []
    for chunk_text, is_atomic in candidate_chunks:
        if is_atomic or len(chunk_text) <= chunk_size:
            split_chunks.append(chunk_text)
        else:
            split_chunks.extend(_split_oversized(chunk_text, chunk_size))

    return _apply_overlap(split_chunks, overlap, chunk_size)


def _parse_units(text):
    """Parse text into semantic units for chunk assembly.

    Returns a list of ``(text, kind)`` tuples where ``kind`` is one of
    ``header``, ``paragraph``, or ``code``.
    """
    lines = text.split("\n")
    units = []
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]
        stripped = line.lstrip()

        # Skip blank lines between units.
        if not stripped:
            i += 1
            continue

        # Fenced code block: keep everything from the opening fence to the
        # matching closing fence in a single atomic unit.
        if stripped.startswith("```"):
            fence_match = re.match(r"^`+", stripped)
            fence = fence_match.group(0) if fence_match else "```"
            block_lines = [line]
            i += 1
            closed = False
            while i < n:
                block_lines.append(lines[i])
                if lines[i].strip() == fence:
                    closed = True
                    i += 1
                    break
                i += 1
            if not closed:
                # Unclosed fence: treat remainder as code to avoid splitting
                # inside what is clearly intended as a code block.
                pass
            units.append(("\n".join(block_lines), "code"))
            continue

        # Markdown header (# through ######).
        if _HEADER_RE.match(stripped):
            units.append((line, "header"))
            i += 1
            continue

        # Paragraph: lines until a blank line, header, or code fence.
        para_lines = [line]
        i += 1
        while i < n:
            next_line = lines[i]
            next_stripped = next_line.lstrip()
            if not next_stripped:
                break
            if _HEADER_RE.match(next_stripped) or next_stripped.startswith("```"):
                break
            para_lines.append(next_line)
            i += 1
        units.append(("\n".join(para_lines), "paragraph"))

    return units


def _merge_units(units, chunk_size):
    """Merge adjacent units greedily, stopping at header boundaries.

    Adjacent paragraphs are merged until the running total reaches roughly
    80% of ``chunk_size``. A header always starts a new chunk and remains
    attached to the content that follows it.

    Finalized chunks (except the very last) append the original paragraph
    separator (``\\n\\n``) so that concatenating the chunks reconstructs the
    source text.

    Returns a list of ``(text, is_atomic)`` tuples. A chunk is marked atomic
    if it contains a fenced code block, which prevents later sentence/word
    splitting from breaking it apart.
    """
    target = int(chunk_size * 0.8)
    chunks = []
    current = []
    current_len = 0
    has_code = False

    for text, kind in units:
        if kind == "header":
            if current:
                chunks.append(("\n\n".join(current) + "\n\n", has_code))
                current = []
                current_len = 0
                has_code = False
            current.append(text)
            current_len += len(text)
            continue

        # ``kind`` is ``paragraph`` or ``code``.
        is_code = kind == "code"
        separator_len = 2 if current else 0
        add_len = len(text) + separator_len

        if not current or current_len + add_len <= target:
            current.append(text)
            current_len += add_len
            if is_code:
                has_code = True
        else:
            chunks.append(("\n\n".join(current) + "\n\n", has_code))
            current = [text]
            current_len = len(text)
            has_code = is_code

    if current:
        chunks.append(("\n\n".join(current), has_code))

    return chunks


def _split_oversized(text, chunk_size):
    """Split non-atomic text at sentence boundaries, then word boundaries.

    Falls back to an oversized single chunk only when an individual token
    contains no whitespace and exceeds ``chunk_size``.
    """
    if len(text) <= chunk_size:
        return [text]

    boundaries = [0]
    for match in _SENTENCE_RE.finditer(text):
        boundaries.append(match.end())
    if boundaries[-1] != len(text):
        boundaries.append(len(text))

    chunks = []
    start = 0
    prev_end = 0
    for end in boundaries[1:]:
        if end - start > chunk_size:
            # Current chunk would exceed the limit; flush what fits so far.
            if start < prev_end:
                chunks.append(text[start:prev_end])
                start = prev_end

            # The sentence at [start:end] is itself too long; split it.
            if end - start > chunk_size:
                sentence = text[start:end]
                chunks.extend(_split_at_word_boundary(sentence, chunk_size))
                start = end
        prev_end = end

    if start < len(text):
        chunks.append(text[start:])

    # Final safety pass: split any remaining oversized chunk at word bounds.
    final = []
    for chunk in chunks:
        if len(chunk) <= chunk_size:
            final.append(chunk)
        else:
            final.extend(_split_at_word_boundary(chunk, chunk_size))
    return final


def _split_at_word_boundary(text, chunk_size):
    """Split text at whitespace, emitting an oversized chunk for huge tokens."""
    if len(text) <= chunk_size:
        return [text]

    chunks = []
    start = 0
    n = len(text)
    while start < n:
        remaining = n - start
        if remaining <= chunk_size:
            chunks.append(text[start:])
            break

        end = start + chunk_size
        space_idx = text.rfind(" ", start, end)
        if space_idx <= start:
            # No whitespace within the window: find the end of this token.
            next_space = text.find(" ", end)
            if next_space == -1:
                chunks.append(text[start:])
                break
            chunks.append(text[start:next_space])
            start = next_space + 1
        else:
            # Include the space in the current chunk so content is not lost.
            chunks.append(text[start : space_idx + 1])
            start = space_idx + 1

    return chunks


def _apply_overlap(chunks, overlap, chunk_size):
    """Prepend boundary-aligned trailing context from the previous chunk.

    The overlap region is taken from the end of the previous chunk and is
    aligned to start at the latest sentence or paragraph boundary that falls
    within the overlap window. If no boundary is available, a word boundary
    is used. The resulting chunks may therefore be up to ``chunk_size +
    overlap`` characters long.
    """
    if not chunks:
        return []

    result = [chunks[0]]
    for i in range(1, len(chunks)):
        prev = chunks[i - 1]
        boundary = _find_overlap_boundary(prev, overlap)
        overlap_text = prev[boundary:]
        if overlap_text:
            result.append(overlap_text + chunks[i])
        else:
            result.append(chunks[i])
    return result


def _find_overlap_boundary(text, overlap):
    """Return the start index of a boundary-aligned overlap suffix.

    Searches the last ``overlap`` characters of ``text`` for the latest
    sentence or paragraph boundary. Falls back to a word boundary, then to
    the earliest position that keeps the overlap within the requested size.
    """
    min_pos = max(0, len(text) - overlap)
    max_pos = len(text)

    candidates = []
    for match in _SENTENCE_RE.finditer(text):
        pos = match.end()
        if min_pos <= pos < max_pos:
            candidates.append(pos)

    idx = text.find("\n\n")
    while idx != -1:
        boundary = idx + 2
        # Exclude the trailing end-of-chunk position; it yields zero overlap.
        if min_pos <= boundary < max_pos:
            candidates.append(boundary)
        idx = text.find("\n\n", idx + 1)

    if candidates:
        return max(candidates)

    # Word boundary fallback: latest space within the window that yields a
    # non-empty overlap region.
    for i in range(max_pos - 1, min_pos - 1, -1):
        if text[i] == " ":
            candidate = i + 1
            if candidate < max_pos:
                return candidate

    return min_pos


def _embed_file_chunks(cur, cfg, source_name, text, dry_run=False, verbose=False):
    """Embed chunks for a single memory file. Returns count embedded."""
    chunks = _chunk_text(text)
    total = 0
    for idx, chunk in enumerate(chunks):
        source_id = f"{source_name}#{idx}"
        if _already_embedded(cur, "memory_file", source_id):
            continue
        if dry_run:
            if verbose:
                logger.info(f"    DRY RUN would embed {source_id}")
            total += 1
            continue
        emb = embed_single(chunk, cfg)
        if emb:
            _store_embeddings(cur, "memory_file", [{"id": source_id, "text": chunk}], [emb])
            total += 1
    return total


def _delete_file_embeddings(cur, source_types, verbose=False):
    """Delete file-based embeddings for reindexing.

    ``source_types`` is an iterable of source_type strings to remove.
    Returns a dict mapping source_type to deleted row count.
    """
    counts = {}
    for source_type in source_types:
        cur.execute(
            "DELETE FROM memory_embeddings WHERE source_type = %s",
            (source_type,),
        )
        counts[source_type] = cur.rowcount
    if verbose:
        for source_type, count in counts.items():
            logger.info(f"  Reindex: deleted {count} {source_type} embeddings")
    return counts


def phase_embed_files(conn, cfg, dry_run=False, verbose=False, reindex_files=False):
    """Embed memory files (daily logs and MEMORY.md).

    When ``reindex_files`` is True, all existing ``memory_file`` and stale
    ``daily_log`` embeddings are deleted inside a single SAVEPOINT before
    re-chunking and re-embedding. A failure at any point during the delete or
    reinsert rolls back to that savepoint, leaving the database in its
    pre-run state.

    ``dry_run`` with ``reindex_files`` performs no database mutations and
    makes no Ollama calls.
    """
    cur = conn.cursor()
    total = 0

    if reindex_files and dry_run:
        if verbose:
            logger.info(
                "DRY RUN: --reindex-files would delete all memory_file and "
                "daily_log embeddings, then re-chunk and re-embed files."
            )
        return 0

    memory_dir = Path.home() / ".openclaw" / "workspace" / "memory"
    memory_md = Path.home() / ".openclaw" / "workspace" / "MEMORY.md"

    if reindex_files:
        cur.execute("SAVEPOINT reindex_files")
        try:
            _delete_file_embeddings(
                cur, ("memory_file", "daily_log"), verbose=verbose
            )
        except psycopg2.Error as e:
            try:
                cur.execute("ROLLBACK TO SAVEPOINT reindex_files")
            except psycopg2.Error:
                pass
            logger.error(f"[ERROR] Reindex deletion failed: {e}")
            raise

        try:
            if memory_dir.exists():
                for md_file in sorted(memory_dir.glob("*.md")):
                    text = md_file.read_text(encoding="utf-8")
                    total += _embed_file_chunks(
                        cur, cfg, md_file.name, text,
                        dry_run=dry_run, verbose=verbose
                    )

            if memory_md.exists():
                text = memory_md.read_text(encoding="utf-8")
                total += _embed_file_chunks(
                    cur, cfg, "MEMORY.md", text,
                    dry_run=dry_run, verbose=verbose
                )

            cur.execute("RELEASE SAVEPOINT reindex_files")
        except psycopg2.Error as e:
            try:
                cur.execute("ROLLBACK TO SAVEPOINT reindex_files")
            except psycopg2.Error:
                pass
            logger.error(f"[ERROR] Reindex insert failed: {e}")
            raise
        except OllamaConnectionError as e:
            try:
                cur.execute("ROLLBACK TO SAVEPOINT reindex_files")
            except psycopg2.Error:
                pass
            logger.error(f"[ERROR] Reindex embedding failed: {e}")
            raise
    else:
        if memory_dir.exists():
            for md_file in sorted(memory_dir.glob("*.md")):
                text = md_file.read_text(encoding="utf-8")
                total += _embed_file_chunks(
                    cur, cfg, md_file.name, text,
                    dry_run=dry_run, verbose=verbose
                )

        if memory_md.exists():
            text = memory_md.read_text(encoding="utf-8")
            total += _embed_file_chunks(
                cur, cfg, "MEMORY.md", text,
                dry_run=dry_run, verbose=verbose
            )

    if verbose and total:
        logger.info(f"  Embedded {total} memory file chunks")
    return total


# ---------------------------------------------------------------------------
# Lessons deduplication phase (runs BEFORE embedding to avoid wasted embed calls)
# ---------------------------------------------------------------------------
def phase_dedup_lessons(conn, dry_run=False, verbose=False):
    """Deduplicate lessons before the embedding phase.

    Exact duplicates (identical lesson text): keep oldest (lowest id), delete newer.
    Near-duplicates (similarity >= 0.80 but not identical): write to review report.
    Cleans up orphaned memory_embeddings rows for deleted lessons.
    Returns count of exact duplicates deleted.
    """
    cur = conn.cursor()
    total_deleted = 0

    # --- Exact duplicate removal ---
    cur.execute("""
        SELECT lesson, array_agg(id ORDER BY id) AS ids, COUNT(*) AS cnt
        FROM lessons
        GROUP BY lesson
        HAVING COUNT(*) > 1
    """)
    groups = cur.fetchall()

    if not groups:
        if verbose:
            logger.info("Lesson dedup: no exact duplicates found")
    else:
        for lesson_text, ids, cnt in groups:
            survivor_id = ids[0]  # oldest (lowest id)
            to_delete = ids[1:]
            if not dry_run:
                cur.execute("DELETE FROM lessons WHERE id = ANY(%s)", (to_delete,))
                deleted = cur.rowcount
                # Clean orphaned embeddings for deleted lessons
                cur.execute(
                    "DELETE FROM memory_embeddings WHERE source_type = 'lesson' AND source_id = ANY(%s)",
                    ([str(i) for i in to_delete],),
                )
                total_deleted += deleted
            else:
                total_deleted += len(to_delete)
            if verbose:
                logger.info(
                    f"  Dedup lessons: kept id={survivor_id}, "
                    f"removed {len(to_delete)} duplicate(s) of '{lesson_text[:60]}'"
                )
        logger.info(f"Lesson dedup: {total_deleted} exact duplicates removed ({len(groups)} group(s))")

    # --- Near-duplicate detection (write review report, do not auto-merge) ---
    try:
        cur.execute("""
            SELECT l1.id AS id1, l2.id AS id2,
                   LEFT(l1.lesson, 80) AS lesson1_preview,
                   LEFT(l2.lesson, 80) AS lesson2_preview,
                   similarity(l1.lesson, l2.lesson) AS sim
            FROM lessons l1
            JOIN lessons l2 ON l1.id < l2.id
            WHERE similarity(l1.lesson, l2.lesson) >= 0.80
              AND l1.lesson != l2.lesson
            ORDER BY sim DESC
            LIMIT 100
        """)
        near_dups = cur.fetchall()
        if near_dups:
            logs_dir = Path.home() / ".openclaw" / "logs"
            logs_dir.mkdir(parents=True, exist_ok=True)
            today = datetime.now().strftime("%Y-%m-%d")
            report_path = logs_dir / f"lesson-dedup-review-{today}.md"
            dry_str = " (DRY RUN)" if dry_run else ""
            with open(report_path, "w") as f:
                f.write(f"# Lesson Near-Duplicate Review — {today}{dry_str}\n\n")
                f.write(f"Found {len(near_dups)} near-duplicate pair(s) (similarity >= 0.80). Manual review needed.\n\n")
                for id1, id2, p1, p2, sim in near_dups:
                    f.write(f"- id={id1} vs id={id2} (sim={sim:.3f}): '{p1}' vs '{p2}'\n")
            logger.info(f"Lesson dedup: {len(near_dups)} near-duplicate pair(s) written to {report_path}")
    except psycopg2.Error as e:
        logger.warning(f"Near-duplicate lesson detection skipped (pg_trgm unavailable?): {e}")

    return total_deleted


def phase_embed(conn, args):
    """Run all embedding sub-phases. Returns (total_embedded, total_warns)."""
    cfg = load_embedding_config()
    total = 0
    total_warns = 0

    db_total, _db_success, db_warns = phase_embed_database(conn, cfg, args.dry_run, args.verbose)
    total += db_total
    total_warns += db_warns

    research_total, research_warns = phase_embed_research(conn, cfg, args.dry_run, args.verbose)
    total += research_total
    total_warns += research_warns

    total += phase_embed_files(
        conn, cfg, args.dry_run, args.verbose, reindex_files=args.reindex_files
    )

    if args.verbose:
        logger.info(f"Embed phase complete: {total} items embedded, {total_warns} warning(s)")
    return total, total_warns


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
        new_confidence = decay_factor
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
        new_confidence = decay_factor
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
    if not check_decay_cooldown(args.state_file, args.force):
        return 0, 0, 0, 0
    decayed_facts = apply_decay_to_entity_facts(conn, args.dry_run, args.verbose)
    decayed_events = apply_decay_to_table(conn, 'events', TABLE_DECAY_RATES['events'], args.dry_run, args.verbose)
    decayed_lessons = apply_decay_to_table(conn, 'lessons', TABLE_DECAY_RATES['lessons'], args.dry_run, args.verbose)
    decayed_embeddings = apply_decay_to_table(conn, 'memory_embeddings', TABLE_DECAY_RATES['memory_embeddings'], args.dry_run, args.verbose)
    args._ran_decay = True
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
    parser.add_argument("--skip-lesson-dedup", action="store_true", help="Skip lessons deduplication phase")
    parser.add_argument(
        "--reindex-files",
        action="store_true",
        default=False,
        help=(
            "Delete all memory_file and stale daily_log embeddings, then "
            "re-chunk and re-embed all memory files. DESTRUCTIVE: use with care."
        ),
    )
    return parser.parse_args()


def main():
    args = parse_args()

    if not check_cooldown(args.state_file, args.force):
        return 0

    conn = psycopg2.connect("")
    conn.autocommit = False

    # Tracks whether Ollama was completely unreachable during the embed phase.
    # If True, the embed phase was skipped and we exit non-zero at the end,
    # but all other maintenance phases (dedup, decay, cleanup) still run.
    embed_ollama_failed = False

    try:
        # Phase: Lessons deduplication (must run BEFORE embed to avoid wasted calls)
        lessons_deduped = 0
        if not args.skip_lesson_dedup:
            lessons_deduped = phase_dedup_lessons(conn, args.dry_run, args.verbose)

        embed_count = 0
        embed_warns = 0
        if not args.skip_embed:
            try:
                embed_count, embed_warns = phase_embed(conn, args)
            except OllamaConnectionError as e:
                logger.error(f"[ERROR] Ollama unavailable -- embed phase skipped: {e}")
                embed_ollama_failed = True

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
        if not args.skip_embed and not embed_ollama_failed and modified_fact_ids:
            reembedded = reembed_modified_facts(conn, modified_fact_ids, args.dry_run, args.verbose)

        cleaned = 0
        if not args.skip_embed:
            cleaned = clean_orphaned_embeddings(conn, args.dry_run, args.verbose)

        archived = archive_low_confidence(conn, args.dry_run, args.verbose)
        purged = purge_old_archives(conn, args.dry_run, args.verbose)

        if not args.dry_run:
            conn.commit()
            update_state(args.state_file, ran_decay=getattr(args, '_ran_decay', False))
            logger.info("Committed all changes.")
        else:
            logger.info("DRY RUN — no changes committed.")
            conn.rollback()

        logger.info("=" * 50)
        logger.info("Memory Maintenance Summary")
        logger.info("=" * 50)
        logger.info(f"  Lessons deduped:        {lessons_deduped}")
        logger.info(f"  Embedded:               {embed_count}")
        logger.info(f"  Embed warnings:         {embed_warns}")
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
        if embed_ollama_failed:
            logger.error("[ERROR] Embed phase failed: Ollama was unreachable. Other phases ran normally.")
    except Exception as e:
        conn.rollback()
        logger.error(f"Transaction rolled back due to error: {e}")
        raise
    finally:
        conn.close()

    # Exit code contract:
    # - 1 if Ollama was completely unreachable (entire embed pipeline broken)
    # - 0 if all phases completed (even if some individual tables warned/skipped)
    return 1 if embed_ollama_failed else 0


if __name__ == "__main__":
    sys.exit(main())
