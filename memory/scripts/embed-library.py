#!/usr/bin/env python3
"""
Embed library works for semantic search.
Creates embeddings for new records in library_works.

Usage:
    python embed-library.py              # Embed new library works only
    python embed-library.py --reindex    # Force re-embed all library works

Requires:
    - OPENAI_API_KEY environment variable
    - PostgreSQL with pgvector extension
    - library_works, library_authors, library_work_authors, library_tags, library_work_tags tables
"""

import os
import sys
import argparse
import psycopg2
import openai

EMBEDDING_MODEL = "text-embedding-3-small"
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


def get_openai_client():
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        # Try to load from OpenClaw config
        sys.path.insert(0, os.path.expanduser('~/.openclaw/lib'))
        try:
            from env_loader import load_openclaw_env
            load_openclaw_env()
            api_key = os.environ.get("OPENAI_API_KEY")
        except ImportError:
            pass

    if not api_key:
        print("Error: OPENAI_API_KEY not set", file=sys.stderr)
        sys.exit(1)
    return openai.OpenAI(api_key=api_key)


def get_embeddings_batch(client, texts):
    response = client.embeddings.create(model=EMBEDDING_MODEL, input=texts)
    return [item.embedding for item in response.data]


def main():
    parser = argparse.ArgumentParser(description="Embed library works for semantic search")
    parser.add_argument("--reindex", action="store_true", help="Force re-embed all library works")
    args = parser.parse_args()

    client = get_openai_client()
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
            embeddings = get_embeddings_batch(client, texts)

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
