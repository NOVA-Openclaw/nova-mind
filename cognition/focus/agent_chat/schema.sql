-- Agent Chat Database Schema
-- 
-- This file sets up the tables and triggers needed for the agent_chat channel plugin.
-- Run this in your PostgreSQL database (e.g., nova_memory).

-- Main chat messages table
CREATE TABLE IF NOT EXISTS agent_chat (
    id SERIAL PRIMARY KEY,
    channel TEXT NOT NULL DEFAULT 'default',
    sender TEXT NOT NULL,
    message TEXT NOT NULL,
    mentions TEXT[] DEFAULT '{}',
    reply_to INTEGER REFERENCES agent_chat(id),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Message processing status enum
DO $$ BEGIN
    CREATE TYPE agent_chat_status AS ENUM ('received', 'routed', 'responded', 'failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Track message state through processing pipeline
-- Enhanced to track: received → routed → responded
CREATE TABLE IF NOT EXISTS agent_chat_processed (
    chat_id INTEGER REFERENCES agent_chat(id) ON DELETE CASCADE,
    agent TEXT NOT NULL,
    status agent_chat_status NOT NULL DEFAULT 'received',
    received_at TIMESTAMP DEFAULT NOW(),
    routed_at TIMESTAMP,
    responded_at TIMESTAMP,
    error_message TEXT,
    PRIMARY KEY (chat_id, agent)
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_agent_chat_mentions ON agent_chat USING GIN(mentions);
CREATE INDEX IF NOT EXISTS idx_agent_chat_created_at ON agent_chat(created_at);
CREATE INDEX IF NOT EXISTS idx_agent_chat_channel ON agent_chat(channel);
CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_agent ON agent_chat_processed(agent);
CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_status ON agent_chat_processed(status);

-- Function to send NOTIFY when new message arrives
CREATE OR REPLACE FUNCTION notify_agent_chat()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('agent_chat', json_build_object(
        'id', NEW.id,
        'channel', NEW.channel,
        'sender', NEW.sender,
        'mentions', NEW.mentions
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to call notify function on INSERT
-- Note: For logical replication setups, use ENABLE ALWAYS TRIGGER to ensure
-- notifications fire on replicated rows
DROP TRIGGER IF EXISTS agent_chat_notify ON agent_chat;
DROP TRIGGER IF EXISTS trg_notify_agent_chat ON agent_chat;
CREATE TRIGGER trg_notify_agent_chat
AFTER INSERT ON agent_chat
FOR EACH ROW
EXECUTE FUNCTION notify_agent_chat();

-- ====================
-- EMBEDDING SUPPORT
-- ====================

-- Table to store message embeddings (if using nova-memory semantic system)
CREATE TABLE IF NOT EXISTS memory_embeddings (
    id SERIAL PRIMARY KEY,
    content_hash VARCHAR(64) UNIQUE NOT NULL,
    embedding VECTOR(1536), -- OpenAI ada-002 dimensions
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Index for similarity search
CREATE INDEX IF NOT EXISTS idx_memory_embeddings_vector 
ON memory_embeddings USING ivfflat (embedding vector_cosine_ops);

-- Function to create embeddings for new messages
-- Note: This requires OpenAI API access and vector extension
CREATE OR REPLACE FUNCTION embed_chat_message()
RETURNS TRIGGER AS $$
DECLARE
    content_text TEXT;
    content_hash_val VARCHAR(64);
BEGIN
    -- Prepare content for embedding
    content_text := NEW.sender || ': ' || NEW.message;
    content_hash_val := encode(sha256(content_text::bytea), 'hex');
    
    -- Insert embedding record (embedding vector will be populated by external process)
    -- This just creates a placeholder that external embedding service can process
    INSERT INTO memory_embeddings (content_hash, content, metadata, embedding)
    VALUES (
        content_hash_val,
        content_text,
        json_build_object(
            'chat_id', NEW.id,
            'sender', NEW.sender,
            'channel', NEW.channel,
            'created_at', NEW.created_at
        ),
        NULL  -- Will be updated by embedding service
    )
    ON CONFLICT (content_hash) DO NOTHING; -- Skip if already exists
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Embedding trigger - should NOT fire on replicated data to avoid duplicates
DROP TRIGGER IF EXISTS trg_embed_chat_message ON agent_chat;
CREATE TRIGGER trg_embed_chat_message
AFTER INSERT ON agent_chat
FOR EACH ROW
EXECUTE FUNCTION embed_chat_message();

-- ====================
-- LOGICAL REPLICATION CONFIGURATION
-- ====================

-- IMPORTANT: For agents using logical replication subscriptions from another database
-- (e.g., graybeard_memory subscribing to nova_memory.agent_chat), you need to configure
-- triggers properly to handle replicated data:
--
-- 1. NOTIFICATION TRIGGER: Must fire ALWAYS (including on replicated rows)
--    Otherwise agents won't receive notifications for replicated messages
--
-- 2. EMBEDDING TRIGGER: Should NOT fire on replicated rows (only REPLICA mode)
--    Otherwise you get duplicate key violations because source DB already created embeddings
--
-- Run these commands AFTER creating your logical replication subscription:
--
-- -- Enable notifications for ALL rows (including replicated)
-- ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;
--
-- -- Disable embedding trigger for replicated rows (only run on origin)
-- ALTER TABLE agent_chat ENABLE REPLICA TRIGGER trg_embed_chat_message;
--
-- To check current trigger configuration:
-- SELECT schemaname, tablename, trigger_name, status 
-- FROM pg_catalog.pg_trigger t
-- JOIN pg_catalog.pg_class c ON t.tgrelid = c.oid
-- JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
-- WHERE c.relname = 'agent_chat' AND NOT t.tgisinternal;

-- ====================
-- MIGRATION HELPER
-- ====================
-- If you have existing data in agent_chat_processed without the new columns,
-- run this to add them:
--
-- ALTER TABLE agent_chat_processed 
--   ADD COLUMN IF NOT EXISTS status agent_chat_status DEFAULT 'responded',
--   ADD COLUMN IF NOT EXISTS received_at TIMESTAMP DEFAULT NOW(),
--   ADD COLUMN IF NOT EXISTS routed_at TIMESTAMP,
--   ADD COLUMN IF NOT EXISTS responded_at TIMESTAMP,
--   ADD COLUMN IF NOT EXISTS error_message TEXT;
--
-- UPDATE agent_chat_processed 
-- SET routed_at = processed_at, 
--     responded_at = processed_at,
--     received_at = processed_at
-- WHERE routed_at IS NULL;
--
-- Then drop the old processed_at column:
-- ALTER TABLE agent_chat_processed DROP COLUMN IF EXISTS processed_at;

-- ====================
-- MONITORING QUERIES
-- ====================

-- Find messages that were routed but never responded to (stuck/ignored)
-- COMMENT ON TABLE agent_chat_processed IS 'Use this query to find stuck messages:
-- SELECT 
--   ac.id,
--   ac.channel,
--   ac.sender,
--   ac.message,
--   acp.agent,
--   acp.status,
--   acp.received_at,
--   acp.routed_at,
--   NOW() - acp.routed_at AS time_since_routed
-- FROM agent_chat ac
-- JOIN agent_chat_processed acp ON ac.id = acp.chat_id
-- WHERE acp.status = ''routed''
--   AND acp.routed_at < NOW() - INTERVAL ''5 minutes''
-- ORDER BY acp.routed_at DESC;
-- ';

-- Find response time statistics per agent
-- SELECT 
--   agent,
--   COUNT(*) as total_responses,
--   AVG(EXTRACT(EPOCH FROM (responded_at - received_at))) as avg_response_seconds,
--   MIN(EXTRACT(EPOCH FROM (responded_at - received_at))) as min_response_seconds,
--   MAX(EXTRACT(EPOCH FROM (responded_at - received_at))) as max_response_seconds
-- FROM agent_chat_processed
-- WHERE status = 'responded'
--   AND responded_at IS NOT NULL
-- GROUP BY agent;

-- Example: Insert a test message
-- INSERT INTO agent_chat (channel, sender, message, mentions)
-- VALUES ('general', 'test_user', 'Hello @newhart!', ARRAY['newhart']);
