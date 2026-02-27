#!/usr/bin/env python3
"""
Proactive Recall: Get relevant memories before processing a message.

Usage (as a standalone):
    python proactive-recall.py "user's message here"
    
Output: JSON with relevant memories to inject into context.

For Clawdbot integration, call this from a hook or message preprocessor.
"""

import os
import sys
import json
from pathlib import Path
import psycopg2
import openai

EMBEDDING_MODEL = "text-embedding-3-small"
DB_NAME = "nova_memory"
DEFAULT_LIMIT = 3
DEFAULT_THRESHOLD = 0.4  # Lower threshold for proactive recall

def get_openai_client():
    """Get OpenAI client with API key."""
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        config_path = Path.home() / ".openclaw" / "openclaw.json"
        if config_path.exists():
            with open(config_path) as f:
                config = json.load(f)
                api_key = config.get("skills", {}).get("entries", {}).get("openai-image-gen", {}).get("apiKey")
    
    if not api_key:
        return None
    
    return openai.OpenAI(api_key=api_key)

def get_embedding(client, text):
    """Get embedding vector from OpenAI."""
    response = client.embeddings.create(
        model=EMBEDDING_MODEL,
        input=text
    )
    return response.data[0].embedding

def recall(message, limit=DEFAULT_LIMIT, threshold=DEFAULT_THRESHOLD):
    """Get relevant memories for a message."""
    client = get_openai_client()
    if not client:
        return {"error": "No OpenAI API key", "memories": []}
    
    try:
        conn = psycopg2.connect(dbname=DB_NAME, host="localhost", user="nova")
        query_embedding = get_embedding(client, message)
        
        cur = conn.cursor()
        cur.execute("""
            SELECT 
                source_type,
                source_id,
                content,
                1 - (embedding <=> %s::vector) AS similarity
            FROM memory_embeddings
            WHERE 1 - (embedding <=> %s::vector) > %s
            ORDER BY embedding <=> %s::vector
            LIMIT %s
        """, (query_embedding, query_embedding, threshold, query_embedding, limit))
        
        results = cur.fetchall()
        conn.close()
        
        memories = []
        for source_type, source_id, content, similarity in results:
            memories.append({
                "source": f"{source_type}/{source_id}",
                "content": content[:500] + "..." if len(content) > 500 else content,
                "similarity": round(similarity, 3)
            })
        
        return {
            "query": message,
            "memories": memories,
            "count": len(memories)
        }
        
    except Exception as e:
        return {"error": str(e), "memories": []}

def format_for_injection(recall_result):
    """Format recall results for context injection."""
    if not recall_result.get("memories"):
        return ""
    
    lines = ["## Relevant Memories (auto-recalled)"]
    for mem in recall_result["memories"]:
        lines.append(f"- [{mem['source']}] ({mem['similarity']:.0%}): {mem['content'][:200]}...")
    
    return "\n".join(lines)

def main():
    if len(sys.argv) < 2:
        print("Usage: proactive-recall.py <message>", file=sys.stderr)
        sys.exit(1)
    
    message = " ".join(sys.argv[1:])
    result = recall(message)
    
    # Check for --inject flag for formatted output
    if "--inject" in sys.argv:
        print(format_for_injection(result))
    else:
        print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
