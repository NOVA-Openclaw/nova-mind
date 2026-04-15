#!/usr/bin/env python3
"""
Embed library works for semantic search.
Creates embeddings for new records in library_works.

Usage:
    python embed-library.py              # Embed new library works only
    python embed-library.py --reindex    # Force re-embed all library works

Requires:
    - Ollama running with mxbai-embed-large model
    - PostgreSQL with pgvector extension
    - library_works, library_authors, library_work_authors, library_tags, library_work_tags tables
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.error
import psycopg2

EMBEDDING_MODEL = "mxbai-embed-large"
DB_NAME = os.environ.get("NOVA_MEMORY_DB", "nova_memory")
BATCH_SIZE = 50
SOURCE_TYPE = "library"

LIBRARY_QUERY = """
    SELECT w.id,
        w.title ||
        COALESCE(' (' || w.edition || ')', '') ||
        ' by ' ||
        COALESCE((
            SELECT string_agg(a.name, ', ' ORDER BY wa.author_order)
            FROM library_authors a
            JOIN library_work_authors wa ON a.id = wa.author_id
            WHERE wa.work_id = w.id
        ), 'Unknown') ||
        ' (' || w.work_type || ', ' || w.publication_date || '). ' ||
        left(w.summary, 1200) ||
        COALESCE(' Topics: ' || (
            SELECT string_agg(t.name, ', ' ORDER BY t.name)
            FROM library_tags t
            JOIN library_work_tags wt ON t.id = wt.tag_id
            WHERE wt.work_id = w.id
        ), '') ||
        COALESCE(' Notable quotes: ' || array_to_string(w.notable_quotes, ' | '), '')
    FROM library_works w
    WHERE w.embed = true
"""


def load_embedding_config():
    """Load embedding configuration from the script's directory."""
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'embedding-config.json')
    if not os.path.exists(config_path):
        print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)
    with open(config_path) as f:
        return json.load(f)


def get_embeddings_batch(config, texts):
    """Get embeddings via Ollama batch API."""
    url = f"{config['base_url']}/api/embed"
    payload = json.dumps({"model": config["model"], "input": texts}).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
        embeddings = result["embeddings"]
        # Validate dimensions
        for emb in embeddings:
            if len(emb) != config["dimensions"]:
                raise ValueError(f"Dimension mismatch: got {len(emb)}, expected {config['dimensions']}")
        return embeddings
    except urllib.error.URLError as e:
        print(f"  ⚠️  Ollama connection error: {e}", file=sys.stderr)
        raise


def main():
    parser = argparse.ArgumentParser(description="Embed library works for semantic search")
    parser.add_argument("--reindex", action="store_true", help="Force re-embed all library works")
    args = parser.parse_args()

    config = load_embedding_config()
    print(f"Using Ollama config: {config['provider']} / {config['model']} ({config['dimensions']} dims)")

    conn = psycopg2.connect(dbname=DB_NAME, host="localhost")

    print(f"📚 Embedding library works...")

    try:
        cur = conn.cursor()
        cur.execute(LIBRARY_QUERY)
        rows = cur.fetchall()
        cur.close()
    except Exception as e:
        print(f"  ⚠️  Query failed: {e}")
        conn.rollback()
        conn.close()
        sys.exit(1)

    if not rows:
        print("  (no library works found)")
        conn.close()
        return

    # Filter out already embedded (unless reindexing)
    cur = conn.cursor()
    if args.reindex:
        cur.execute("DELETE FROM memory_embeddings WHERE source_type = %s", (SOURCE_TYPE,))
        conn.commit()
        to_embed = [(str(id_), content[:2000]) for id_, content in rows if content and len(content.strip()) > 5]
        print(f"  Reindexing: {len(to_embed)} works")
    else:
        to_embed = []
        for id_, content in rows:
            if content and len(content.strip()) > 5:
                cur.execute(
                    "SELECT 1 FROM memory_embeddings WHERE source_type = %s AND source_id = %s",
                    (SOURCE_TYPE, str(id_))
                )
                if not cur.fetchone():
                    to_embed.append((str(id_), content[:2000]))
        print(f"  New works to embed: {len(to_embed)}")
    cur.close()

    if not to_embed:
        print("  ✓ All library works already embedded")
        conn.close()
        return

    # Embed in batches
    total = 0
    for i in range(0, len(to_embed), BATCH_SIZE):
        batch = to_embed[i:i + BATCH_SIZE]
        texts = [item[1] for item in batch]

        try:
            embeddings = get_embeddings_batch(config, texts)

            cur = conn.cursor()
            for (src_id, content), embedding in zip(batch, embeddings):
                cur.execute("""
                    INSERT INTO memory_embeddings (source_type, source_id, content, embedding)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT DO NOTHING
                """, (SOURCE_TYPE, src_id, content, embedding))
            conn.commit()
            cur.close()
            total += len(batch)
        except Exception as e:
            print(f"  ⚠️  Batch failed: {e}")
            conn.rollback()

    print(f"  ✓ {total} works embedded")

    # Show total count
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM memory_embeddings WHERE source_type = %s", (SOURCE_TYPE,))
    count = cur.fetchone()[0]
    print(f"\n✅ Total library embeddings: {count}")

    conn.close()


if __name__ == "__main__":
    main()
