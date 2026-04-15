#!/usr/bin/env python3
"""
Embed research data for semantic search.
Creates embeddings for new records in research_tasks, research_findings, and research_conclusions.

Usage:
    python embed-research.py              # Embed new research records only
    python embed-research.py --reindex    # Force re-embed all research records

Requires:
    - Ollama running with mxbai-embed-large model
    - PostgreSQL with pgvector extension
    - research_tasks, research_findings, research_conclusions tables
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
SOURCE_TYPE = "research"

TABLES_TO_EMBED = {
    "research_task": """
        SELECT id, title || ': ' || COALESCE(query, '') || ' ' || COALESCE(methodology, '')
        FROM research_tasks
    """,
    "research_finding": """
        SELECT id, COALESCE(finding_type, '') || ': ' || content
        FROM research_findings
        WHERE is_current = true
    """,
    "research_conclusion": """
        SELECT id, COALESCE(title, '') || ': ' || COALESCE(summary, '') || ' ' || COALESCE(full_content, '')
        FROM research_conclusions
        WHERE is_current = true
    """,
}


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


def get_all_source_ids(conn, source_type):
    """Get all source IDs for a source type."""
    cur = conn.cursor()
    cur.execute("SELECT source_id FROM memory_embeddings WHERE source_type = %s", (source_type,))
    ids = {row[0] for row in cur.fetchall()}
    cur.close()
    return ids


def main():
    parser = argparse.ArgumentParser(description="Embed research data for semantic search")
    parser.add_argument("--reindex", action="store_true", help="Force re-embed all research records")
    args = parser.parse_args()

    config = load_embedding_config()
    print(f"Using Ollama config: {config['provider']} / {config['model']} ({config['dimensions']} dims)")

    conn = psycopg2.connect(dbname=DB_NAME, host="localhost")

    print(f"📚 Embedding research data...")

    try:
        cur = conn.cursor()

        if args.reindex:
            # Delete all existing research embeddings
            cur.execute("DELETE FROM memory_embeddings WHERE source_type = %s", (SOURCE_TYPE,))
            conn.commit()
            print(f"  Reindexing: will embed all research records")

        all_source_ids = get_all_source_ids(conn, SOURCE_TYPE) if not args.reindex else set()

        total_to_embed = 0
        for table_name, query in TABLES_TO_EMBED.items():
            cur.execute(query)
            rows = cur.fetchall()

            # Filter out already embedded (unless reindexing)
            to_embed = []
            for id_, content in rows:
                if content and len(content.strip()) > 5:
                    source_id = f"{table_name}:{id_}"
                    if args.reindex or source_id not in all_source_ids:
                        to_embed.append((source_id, content[:2000]))

            print(f"  {table_name}: {len(to_embed)} records to embed")
            total_to_embed += len(to_embed)

            # Embed in batches
            for i in range(0, len(to_embed), BATCH_SIZE):
                batch = to_embed[i:i + BATCH_SIZE]
                texts = [item[1] for item in batch]

                try:
                    embeddings = get_embeddings_batch(config, texts)

                    for (src_id, content), embedding in zip(batch, embeddings):
                        cur.execute("""
                            INSERT INTO memory_embeddings (source_type, source_id, content, embedding)
                            VALUES (%s, %s, %s, %s)
                            ON CONFLICT DO NOTHING
                        """, (SOURCE_TYPE, src_id, content, embedding))
                    conn.commit()
                except Exception as e:
                    print(f"  ⚠️  Batch failed for {table_name}: {e}")
                    conn.rollback()

        cur.close()

    except Exception as e:
        print(f"  ⚠️  Query failed: {e}", file=sys.stderr)
        conn.rollback()
        conn.close()
        sys.exit(1)

    if total_to_embed == 0:
        print("  ✓ All research records already embedded")
        conn.close()
        return

    print(f"  ✓ {total_to_embed} research records embedded")

    # Show total count
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM memory_embeddings WHERE source_type = %s", (SOURCE_TYPE,))
    count = cur.fetchone()[0]
    print(f"\n✅ Total research embeddings: {count}")

    conn.close()


if __name__ == "__main__":
    main()
