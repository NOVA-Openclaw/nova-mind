#!/usr/bin/env python3
"""
Embed full database for semantic search.
Creates embeddings for all relevant tables in nova_memory.

DEPRECATED: This script has been absorbed into memory-maintenance.py.
Use: python3 memory-maintenance.py (embedding is Phase 2 of the unified pipeline)
"""

import os
import sys
import json
import urllib.request
import urllib.error
import psycopg2

EMBEDDING_MODEL = "snowflake-arctic-embed2"  # #223: updated to match embedding-config.json
DB_NAME = "nova_memory"
BATCH_SIZE = 50

# Tables and their content extraction queries (adjusted for actual schemas)
TABLES_TO_EMBED = {
    "task": """
        SELECT id, title || ': ' || COALESCE(description, '') || 
               CASE WHEN status IS NOT NULL THEN ' [Status: ' || status || ']' ELSE '' END
        FROM tasks WHERE title IS NOT NULL
    """,
    "entity": """
        SELECT id, name || COALESCE(' (' || type || ')', '') || COALESCE(': ' || notes, '')
        FROM entities WHERE name IS NOT NULL
    """,
    "entity_fact": """
        SELECT ef.id, e.name || ' - ' || ef.key || ': ' || ef.value
        FROM entity_facts ef JOIN entities e ON ef.entity_id = e.id
    """,
    "project": """
        SELECT id, name || ': ' || COALESCE(goal, '') || 
               CASE WHEN status IS NOT NULL THEN ' [' || status || ']' ELSE '' END
        FROM projects WHERE name IS NOT NULL
    """,
    "agent": """
        SELECT id, name || ' (' || COALESCE(role, 'agent') || '): ' || COALESCE(description, '')
        FROM agents WHERE name IS NOT NULL
    """,
    "lesson": """
        SELECT id, lesson || CASE WHEN context IS NOT NULL THEN ' (Context: ' || context || ')' ELSE '' END
        FROM lessons WHERE lesson IS NOT NULL
    """,
    "event": """
        SELECT id, COALESCE(title, 'event') || ' (' || event_date::date || '): ' || COALESCE(description, '')
        FROM events WHERE (title IS NOT NULL OR description IS NOT NULL)
    """,
    # #233/#259: stale table entries removed (see GitHub issues #233 and #259)
    # #259: position removed (positions table no longer exists)
    "media_consumed": """
        SELECT id, title || ' (' || COALESCE(media_type, 'media') || '): ' || COALESCE(summary, '')
        FROM media_consumed WHERE title IS NOT NULL
    """,
    # #259: fixed column reference -- vocabulary.word (see issue #259)
    "vocabulary": """
        SELECT id, word || COALESCE(' (' || category || ')', '')
        FROM vocabulary WHERE word IS NOT NULL
    """,
    "library": """
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
            w.summary ||
            COALESCE(' Notable quotes: ' || array_to_string(w.notable_quotes, ' | '), '') ||
            COALESCE(' Topics: ' || (
                SELECT string_agg(t.name, ', ' ORDER BY t.name)
                FROM library_tags t
                JOIN library_work_tags wt ON t.id = wt.tag_id
                WHERE wt.work_id = w.id
            ), '')
        FROM library_works w
        WHERE w.embed = true
    """,
    # #235: new tables
    "journal_entry": """
        SELECT id, content
        FROM journal_entries WHERE content IS NOT NULL
    """,
    "music_work": """
        SELECT id, title || ': ' || COALESCE(description, '')
        FROM music_works WHERE title IS NOT NULL
    """,
    "workflow_run": """
        SELECT id, trim(COALESCE(trigger_context, '') || ' ' || COALESCE(notes, ''))
        FROM workflow_runs
    """,
    "income_source": """
        SELECT id, name || ': ' || COALESCE(description, '')
        FROM income_sources WHERE name IS NOT NULL
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


def main():
    config = load_embedding_config()
    print(f"Using Ollama config: {config['provider']} / {config['model']} ({config['dimensions']} dims)")
    
    conn = psycopg2.connect(dbname=DB_NAME, host="localhost", user="nova")
    
    total_embedded = 0
    
    for source_type, query in TABLES_TO_EMBED.items():
        print(f"\n📊 Processing {source_type}...")
        
        try:
            cur = conn.cursor()  # Fresh cursor for each table
            cur.execute(query)
            rows = cur.fetchall()
            cur.close()
        except Exception as e:
            print(f"  ⚠️  Query failed: {e}")
            conn.rollback()
            continue
            
        if not rows:
            print(f"  (no rows)")
            continue
        
        # Filter out already embedded
        cur = conn.cursor()
        to_embed = []
        for id_, content in rows:
            if content and len(content.strip()) > 5:
                cur.execute(
                    "SELECT 1 FROM memory_embeddings WHERE source_type = %s AND source_id = %s",
                    (source_type, str(id_))
                )
                if not cur.fetchone():
                    to_embed.append((str(id_), content[:2000]))
        cur.close()
        
        if not to_embed:
            print(f"  (all already embedded)")
            continue
        
        # Embed in batches
        new_count = 0
        for i in range(0, len(to_embed), BATCH_SIZE):
            batch = to_embed[i:i+BATCH_SIZE]
            texts = [item[1] for item in batch]
            
            try:
                embeddings = get_embeddings_batch(config, texts)
                
                cur = conn.cursor()
                for (src_id, content), embedding in zip(batch, embeddings):
                    cur.execute("""
                        INSERT INTO memory_embeddings (source_type, source_id, content, embedding)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT DO NOTHING
                    """, (source_type, src_id, content, embedding))
                conn.commit()
                cur.close()
                new_count += len(batch)
            except Exception as e:
                print(f"  ⚠️  Batch failed: {e}")
                conn.rollback()
        
        print(f"  ✓ {new_count} embedded")
        total_embedded += new_count
    
    conn.close()
    print(f"\n✅ Total: {total_embedded} new embeddings")


if __name__ == "__main__":
    main()
