#!/usr/bin/env python3
"""
Generate embeddings for test data in the memory system.

This script:
1. Connects to the specified PostgreSQL database
2. Reads entity_facts that should have embeddings (excluding sensitive data)
3. Generates embeddings using OpenAI API
4. Populates the memory_embeddings table

Usage:
    ./generate-test-embeddings.py [--database DB_NAME] [--dry-run] [--api-key KEY]

Environment variables:
    OPENAI_API_KEY: OpenAI API key (required unless --dry-run or --api-key specified)
    DATABASE_URL: Full PostgreSQL connection URL (alternative to --database)
"""

import argparse
import os
import sys
import json
from typing import List, Dict, Any, Optional
import psycopg2
from psycopg2.extras import RealDictCursor

# Check if openai is available
try:
    import openai
    HAS_OPENAI = True
except ImportError:
    HAS_OPENAI = False
    print("Warning: openai package not installed. Run: pip install openai", file=sys.stderr)


class EmbeddingGenerator:
    def __init__(self, db_name: str, api_key: Optional[str] = None, dry_run: bool = False):
        self.db_name = db_name
        self.dry_run = dry_run
        self.api_key = api_key or os.getenv('OPENAI_API_KEY')
        
        if not dry_run and not self.api_key and HAS_OPENAI:
            raise ValueError("OpenAI API key required. Set OPENAI_API_KEY or use --api-key")
        
        if HAS_OPENAI and not dry_run:
            openai.api_key = self.api_key
        
        self.conn = None
    
    def connect(self):
        """Connect to PostgreSQL database."""
        try:
            # Try DATABASE_URL first
            database_url = os.getenv('DATABASE_URL')
            if database_url:
                self.conn = psycopg2.connect(database_url)
            else:
                # Fall back to dbname
                self.conn = psycopg2.connect(
                    dbname=self.db_name,
                    user=os.getenv('PGUSER', 'nova'),
                    password=os.getenv('PGPASSWORD', ''),
                    host=os.getenv('PGHOST', 'localhost'),
                    port=os.getenv('PGPORT', '5432')
                )
            print(f"✓ Connected to database: {self.db_name}")
        except Exception as e:
            print(f"✗ Failed to connect to database: {e}", file=sys.stderr)
            sys.exit(1)
    
    def close(self):
        """Close database connection."""
        if self.conn:
            self.conn.close()
    
    def fetch_facts_to_embed(self) -> List[Dict[str, Any]]:
        """
        Fetch entity facts that should have embeddings.
        Excludes 'sensitive' visibility facts for privacy.
        """
        query = """
            SELECT 
                ef.id,
                ef.entity_id,
                ef.key,
                ef.value,
                ef.visibility,
                ef.confidence,
                e.name as entity_name,
                e.type as entity_type
            FROM entity_facts ef
            JOIN entities e ON ef.entity_id = e.id
            WHERE ef.visibility != 'sensitive'  -- Privacy: don't embed sensitive data
            ORDER BY ef.entity_id, ef.id;
        """
        
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query)
            facts = cur.fetchall()
        
        print(f"✓ Found {len(facts)} facts to embed (excluding sensitive data)")
        return facts
    
    def create_embedding_content(self, fact: Dict[str, Any]) -> str:
        """
        Create the text content to embed from a fact.
        Format: "Entity (type): key = value"
        """
        return f"{fact['entity_name']} ({fact['entity_type']}): {fact['key']} = {fact['value']}"
    
    def generate_embedding(self, text: str) -> List[float]:
        """
        Generate embedding using OpenAI API.
        Returns a 1536-dimensional vector.
        """
        if self.dry_run:
            # Return a dummy embedding for dry-run mode
            return [0.0] * 1536
        
        if not HAS_OPENAI:
            raise RuntimeError("openai package not installed")
        
        try:
            response = openai.embeddings.create(
                model="text-embedding-ada-002",
                input=text
            )
            return response.data[0].embedding
        except Exception as e:
            print(f"✗ Error generating embedding: {e}", file=sys.stderr)
            raise
    
    def insert_embedding(self, fact_id: int, content: str, embedding: List[float], confidence: float):
        """Insert embedding into memory_embeddings table."""
        query = """
            INSERT INTO memory_embeddings 
            (source_type, source_id, content, embedding, confidence)
            VALUES (%s, %s, %s, %s::vector, %s)
            ON CONFLICT (source_type, source_id) DO UPDATE
            SET content = EXCLUDED.content,
                embedding = EXCLUDED.embedding,
                confidence = EXCLUDED.confidence,
                updated_at = NOW();
        """
        
        with self.conn.cursor() as cur:
            # Convert embedding to PostgreSQL vector format
            embedding_str = '[' + ','.join(map(str, embedding)) + ']'
            cur.execute(query, ('entity_fact', str(fact_id), content, embedding_str, confidence))
        
        self.conn.commit()
    
    def generate_all_embeddings(self):
        """Main process: fetch facts, generate embeddings, insert into DB."""
        facts = self.fetch_facts_to_embed()
        
        if not facts:
            print("No facts found to embed.")
            return
        
        print(f"\nGenerating embeddings for {len(facts)} facts...")
        print(f"Mode: {'DRY RUN' if self.dry_run else 'LIVE'}")
        
        success_count = 0
        error_count = 0
        
        for i, fact in enumerate(facts, 1):
            try:
                content = self.create_embedding_content(fact)
                
                if self.dry_run:
                    print(f"  [{i}/{len(facts)}] Would embed: {content[:80]}...")
                else:
                    embedding = self.generate_embedding(content)
                    self.insert_embedding(
                        fact['id'],
                        content,
                        embedding,
                        fact['confidence']
                    )
                    
                    if i % 10 == 0:
                        print(f"  [{i}/{len(facts)}] Processed {i} facts...")
                
                success_count += 1
                
            except Exception as e:
                print(f"  ✗ Error processing fact {fact['id']}: {e}", file=sys.stderr)
                error_count += 1
        
        print(f"\n{'Dry run' if self.dry_run else 'Embedding generation'} complete!")
        print(f"  ✓ Success: {success_count}")
        if error_count > 0:
            print(f"  ✗ Errors: {error_count}")
        
        return success_count, error_count
    
    def verify_embeddings(self):
        """Verify that embeddings were created correctly."""
        query = """
            SELECT 
                COUNT(*) as total,
                COUNT(DISTINCT source_id) as unique_facts,
                AVG(array_length(embedding::real[], 1)) as avg_dimensions
            FROM memory_embeddings
            WHERE source_type = 'entity_fact';
        """
        
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query)
            stats = cur.fetchone()
        
        print("\nEmbedding Statistics:")
        print(f"  Total embeddings: {stats['total']}")
        print(f"  Unique facts: {stats['unique_facts']}")
        print(f"  Avg dimensions: {stats['avg_dimensions']}")
        
        return stats


def main():
    parser = argparse.ArgumentParser(
        description='Generate embeddings for test data',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument(
        '--database', '-d',
        default='test_memory',
        help='Database name (default: test_memory)'
    )
    parser.add_argument(
        '--api-key', '-k',
        help='OpenAI API key (or set OPENAI_API_KEY env var)'
    )
    parser.add_argument(
        '--dry-run', '-n',
        action='store_true',
        help='Dry run - show what would be done without calling API'
    )
    parser.add_argument(
        '--verify-only', '-v',
        action='store_true',
        help='Only verify existing embeddings, don\'t generate new ones'
    )
    
    args = parser.parse_args()
    
    # Create generator
    generator = EmbeddingGenerator(
        db_name=args.database,
        api_key=args.api_key,
        dry_run=args.dry_run
    )
    
    try:
        # Connect to database
        generator.connect()
        
        if args.verify_only:
            # Just verify
            generator.verify_embeddings()
        else:
            # Generate embeddings
            generator.generate_all_embeddings()
            
            # Verify results
            if not args.dry_run:
                print("\n" + "="*60)
                generator.verify_embeddings()
        
        print("\n✓ Done!")
        
    except KeyboardInterrupt:
        print("\n\n✗ Interrupted by user", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Fatal error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        generator.close()


if __name__ == '__main__':
    main()
