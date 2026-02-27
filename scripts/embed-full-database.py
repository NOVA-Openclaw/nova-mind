#!/usr/bin/env python3
"""
Embed full database for semantic search.
Creates embeddings for all relevant tables in nova_memory.
"""

import os
import psycopg2
import openai

EMBEDDING_MODEL = "text-embedding-3-small"
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
        SELECT id, name || ': ' || COALESCE(description, '') || 
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
        SELECT id, COALESCE(title, event_type, 'event') || ' (' || event_date::date || '): ' || COALESCE(description, '')
        FROM events WHERE (title IS NOT NULL OR description IS NOT NULL)
    """,
    "trading_signal": """
        SELECT id, signal_type || ' ' || symbol || ' (' || created_at::date || '): ' || COALESCE(reasoning, '')
        FROM trading_signals WHERE symbol IS NOT NULL
    """,
    "position": """
        SELECT id, asset_class || ': ' || symbol || ' - ' || quantity::text || ' ' || COALESCE(unit, 'units') ||
               CASE WHEN notes IS NOT NULL THEN ' (' || notes || ')' ELSE '' END
        FROM positions WHERE symbol IS NOT NULL AND sold_at IS NULL
    """,
    "media_consumed": """
        SELECT id, title || ' (' || COALESCE(media_type, 'media') || '): ' || COALESCE(summary, '')
        FROM media_consumed WHERE title IS NOT NULL
    """,
    "vocabulary": """
        SELECT id, term || ': ' || COALESCE(definition, '')
        FROM vocabulary WHERE term IS NOT NULL
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
}

def get_openai_client():
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise ValueError("OPENAI_API_KEY not set")
    return openai.OpenAI(api_key=api_key)

def get_embeddings_batch(client, texts):
    response = client.embeddings.create(model=EMBEDDING_MODEL, input=texts)
    return [item.embedding for item in response.data]

def main():
    client = get_openai_client()
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
                embeddings = get_embeddings_batch(client, texts)
                
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
