#!/usr/bin/env python3
"""
Seed Domain Embeddings: Embed all agent_domain descriptions into memory_embeddings.

Reads domain descriptions from agent_domains.notes, embeds via Ollama,
and upserts into memory_embeddings with source_type='agent_domain'.

Usage:
    python seed-domain-embeddings.py [--dry-run]

Idempotent: uses ON CONFLICT to update existing rows.

Issue: nova-mind #150
"""

import os
import sys
import json
import argparse
import urllib.request
import urllib.error

import psycopg2

# Load centralized PostgreSQL configuration
sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))
from pg_env import load_pg_env
load_pg_env()


def load_embedding_config():
    """Load embedding configuration from the script's directory."""
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'embedding-config.json')
    if not os.path.exists(config_path):
        print(f"Error: Config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)
    with open(config_path) as f:
        return json.load(f)


def get_embedding(config, text):
    """Get embedding vector via Ollama API."""
    url = f"{config['base_url']}/api/embeddings"
    payload = json.dumps({"model": config["model"], "prompt": text}).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read())
    embedding = result["embedding"]
    if len(embedding) != config["dimensions"]:
        raise ValueError(f"Dimension mismatch: got {len(embedding)}, expected {config['dimensions']}")
    return embedding


def main():
    parser = argparse.ArgumentParser(description="Seed domain description embeddings into memory_embeddings")
    parser.add_argument("--dry-run", action="store_true", help="Print domains without embedding or writing")
    args = parser.parse_args()

    config = load_embedding_config()
    print(f"Embedding config: {config['provider']} / {config['model']} ({config['dimensions']} dims)", file=sys.stderr)

    conn = psycopg2.connect()
    cur = conn.cursor()

    # Fetch all domains with descriptions
    cur.execute("""
        SELECT ad.domain_topic, ad.notes,
               a.name AS agent_name
        FROM agent_domains ad
        JOIN agents a ON a.id = ad.agent_id
        WHERE ad.notes IS NOT NULL AND ad.notes != ''
        ORDER BY ad.domain_topic
    """)
    domains = cur.fetchall()

    if not domains:
        print("No domains with descriptions found. Run migration 081 first.", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(domains)} domains with descriptions", file=sys.stderr)

    if args.dry_run:
        for topic, notes, agent in domains:
            print(f"  {topic} ({agent}): {notes[:80]}...")
        print(f"\nDry run: would embed {len(domains)} domains", file=sys.stderr)
        conn.close()
        return

    embedded = 0
    skipped = 0
    errors = 0

    for topic, notes, agent in domains:
        # Build embedding content: domain name + description for rich context
        embed_text = f"Subject matter domain: {topic}. {notes}"
        try:
            embedding = get_embedding(config, embed_text)
        except Exception as e:
            print(f"  ERROR embedding '{topic}': {e}", file=sys.stderr)
            errors += 1
            continue

        try:
            # Upsert into memory_embeddings
            # source_type='agent_domain', source_id=domain_topic
            cur.execute("""
                INSERT INTO memory_embeddings (source_type, source_id, content, embedding)
                VALUES ('agent_domain', %s, %s, %s::vector)
                ON CONFLICT (source_type, source_id)
                DO UPDATE SET content = EXCLUDED.content, embedding = EXCLUDED.embedding
            """, (topic, embed_text, embedding))
            embedded += 1
            print(f"  ✓ {topic} ({agent})", file=sys.stderr)
        except Exception as e:
            print(f"  ERROR upserting '{topic}': {e}", file=sys.stderr)
            errors += 1
            conn.rollback()

    conn.commit()
    conn.close()

    print(f"\nDone: {embedded} embedded, {skipped} skipped, {errors} errors", file=sys.stderr)
    if errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
