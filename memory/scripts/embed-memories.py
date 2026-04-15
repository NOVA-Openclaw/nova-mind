#!/usr/bin/env python3
"""
Embed file-based memory content using Ollama and store in PostgreSQL pgvector.

Scoped to FILE sources only:
  - Daily log files (memory/*.md)
  - MEMORY.md

Database table embeddings are handled by embed-full-database.py.

Usage:
    python embed-memories.py                    # Embed all file sources
    python embed-memories.py --source daily_log # Embed only daily logs
    python embed-memories.py --source memory_md # Embed only MEMORY.md
    python embed-memories.py --reindex          # Drop and recreate all embeddings
"""

import os
import sys
import json
import argparse
import hashlib
import urllib.request
import urllib.error
from pathlib import Path
import psycopg2

# Configuration
MEMORY_DIR = Path.home() / ".openclaw" / "workspace" / "memory"
MEMORY_MD = Path.home() / ".openclaw" / "workspace" / "MEMORY.md"
CHUNK_SIZE = 1000  # Characters per chunk (with overlap)
CHUNK_OVERLAP = 200
EMBEDDING_MODEL = "mxbai-embed-large"
DB_NAME = os.environ.get("NOVA_MEMORY_DB", "nova_memory")


def load_embedding_config():
    """Load embedding configuration from the script's directory."""
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'embedding-config.json')
    if not os.path.exists(config_path):
        print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)
    with open(config_path) as f:
        return json.load(f)


def chunk_text(text, chunk_size=CHUNK_SIZE, overlap=CHUNK_OVERLAP):
    """Split text into overlapping chunks."""
    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size
        chunk = text[start:end]
        if chunk.strip():
            chunks.append(chunk.strip())
        start = end - overlap
    return chunks


def get_embedding(config, text):
    """Get embedding vector from Ollama."""
    url = f"{config['base_url']}/api/embeddings"
    payload = json.dumps({"model": config["model"], "prompt": text}).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read())
    embedding = result["embedding"]
    if len(embedding) != config["dimensions"]:
        raise ValueError(f"Dimension mismatch: got {len(embedding)}, expected {config['dimensions']}")
    return embedding


def embed_daily_logs(conn, config, force=False):
    """Embed daily memory log files."""
    cur = conn.cursor()
    count = 0

    for log_file in sorted(MEMORY_DIR.glob("*.md")):
        source_id = log_file.name
        content = log_file.read_text()

        if not content.strip():
            print(f"  ⚠️  Skipping {source_id}: empty content", file=sys.stderr)
            continue

        if not force:
            cur.execute(
                "SELECT id FROM memory_embeddings WHERE source_type = 'daily_log' AND source_id = %s",
                (source_id,)
            )
            if cur.fetchone():
                print(f"  Skipping {source_id} (already embedded)")
                continue

        chunks = chunk_text(content)
        for i, chunk in enumerate(chunks):
            chunk_id = f"{source_id}:chunk{i}"
            embedding = get_embedding(config, chunk)

            cur.execute("""
                INSERT INTO memory_embeddings (source_type, source_id, content, embedding)
                VALUES ('daily_log', %s, %s, %s)
                ON CONFLICT DO NOTHING
            """, (chunk_id, chunk, embedding))
            count += 1

        print(f"  Embedded {source_id} ({len(chunks)} chunks)")

    conn.commit()
    return count


def embed_memory_md(conn, config, force=False):
    """Embed MEMORY.md file."""
    cur = conn.cursor()

    if not MEMORY_MD.exists():
        return 0

    content = MEMORY_MD.read_text()
    source_id = "MEMORY.md"

    if not force:
        cur.execute(
            "SELECT id FROM memory_embeddings WHERE source_type = 'memory_md' AND source_id LIKE %s",
            (f"{source_id}%",)
        )
        if cur.fetchone():
            print(f"  Skipping {source_id} (already embedded)")
            return 0
    else:
        cur.execute("DELETE FROM memory_embeddings WHERE source_type = 'memory_md'")

    chunks = chunk_text(content)
    count = 0
    for i, chunk in enumerate(chunks):
        chunk_id = f"{source_id}:chunk{i}"
        embedding = get_embedding(config, chunk)

        cur.execute("""
            INSERT INTO memory_embeddings (source_type, source_id, content, embedding)
            VALUES ('memory_md', %s, %s, %s)
        """, (chunk_id, chunk, embedding))
        count += 1

    conn.commit()
    print(f"  Embedded {source_id} ({count} chunks)")
    return count


def main():
    parser = argparse.ArgumentParser(description="Embed file-based memories for semantic search")
    parser.add_argument("--source", choices=["daily_log", "memory_md", "all"],
                        default="all", help="Which file source to embed")
    parser.add_argument("--reindex", action="store_true", help="Force re-embed everything")
    args = parser.parse_args()

    print("Loading embedding config...")
    config = load_embedding_config()
    print(f"  Provider: {config['provider']}")
    print(f"  Model: {config['model']}")
    print(f"  Dimensions: {config['dimensions']}")

    print("Connecting to database...")
    conn = psycopg2.connect(dbname=DB_NAME, host="localhost")

    total = 0

    if args.source in ["daily_log", "all"]:
        print("\nEmbedding daily logs...")
        total += embed_daily_logs(conn, config, args.reindex)

    if args.source in ["memory_md", "all"]:
        print("\nEmbedding MEMORY.md...")
        total += embed_memory_md(conn, config, args.reindex)

    print(f"\nDone! Embedded {total} chunks total.")

    # Show stats
    cur = conn.cursor()
    cur.execute("SELECT source_type, COUNT(*) FROM memory_embeddings GROUP BY source_type ORDER BY source_type")
    print("\nEmbedding stats:")
    for source_type, count in cur.fetchall():
        print(f"  {source_type}: {count}")

    conn.close()


if __name__ == "__main__":
    main()
