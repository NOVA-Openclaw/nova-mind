-- Migration: Switch from OpenAI text-embedding-3-small (1536) to Ollama mxbai-embed-large (1024)
-- This drops and recreates the embedding column since you cannot ALTER vector dimensions
-- All existing embeddings will be lost and must be re-generated via embed scripts

DROP INDEX IF EXISTS idx_memory_embeddings_vector;
ALTER TABLE memory_embeddings DROP COLUMN IF EXISTS embedding;
ALTER TABLE memory_embeddings ADD COLUMN embedding vector(1024);
CREATE INDEX idx_memory_embeddings_vector ON memory_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists=100);
