-- Migration: Add unique constraint on memory_embeddings(source_type, source_id)
-- Required for ON CONFLICT upsert in _store_embeddings()

CREATE UNIQUE INDEX IF NOT EXISTS uq_memory_embeddings_source
ON memory_embeddings (source_type, source_id);
