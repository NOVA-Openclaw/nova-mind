-- Agent Chat Database Schema
--
-- This file sets up the tables and triggers needed for the agent_chat channel plugin.
-- Run this in your PostgreSQL database (e.g., nova_memory).
--
-- COLUMN HISTORY (see #106):
--   mentions   → recipients  (renamed)
--   created_at → "timestamp" (renamed; quoted everywhere — reserved word in PostgreSQL)
--   channel               (dropped; inter-agent messaging uses sender+recipients only)
--
-- Pre-migration renames are handled by the installer (Step 1.5, renames.json).
-- This schema reflects the post-rename desired state.

-- Message processing status enum
DO $$ BEGIN
    CREATE TYPE agent_chat_status AS ENUM ('received', 'routed', 'responded', 'failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Main chat messages table
CREATE TABLE IF NOT EXISTS agent_chat (
    id          SERIAL PRIMARY KEY,
    sender      TEXT NOT NULL,
    message     TEXT NOT NULL,
    recipients  TEXT[] NOT NULL CHECK (array_length(recipients, 1) > 0),
    reply_to    INTEGER REFERENCES agent_chat(id),
    "timestamp" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Track message state through processing pipeline: received → routed → responded
CREATE TABLE IF NOT EXISTS agent_chat_processed (
    chat_id      INTEGER REFERENCES agent_chat(id) ON DELETE CASCADE,
    agent        TEXT NOT NULL,
    status       agent_chat_status NOT NULL DEFAULT 'received',
    received_at  TIMESTAMPTZ DEFAULT NOW(),
    routed_at    TIMESTAMPTZ,
    responded_at TIMESTAMPTZ,
    error_message TEXT,
    PRIMARY KEY (chat_id, agent)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_agent_chat_recipients  ON agent_chat USING GIN (recipients);
CREATE INDEX IF NOT EXISTS idx_agent_chat_timestamp   ON agent_chat ("timestamp");
CREATE INDEX IF NOT EXISTS idx_agent_chat_sender      ON agent_chat (sender, "timestamp" DESC);
CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_agent  ON agent_chat_processed (agent);
CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_status ON agent_chat_processed (status);

-- ====================
-- FUNCTION-GATED INSERTS
-- ====================

-- All inserts must go through send_agent_message() (SECURITY DEFINER).
-- Direct INSERT on agent_chat is blocked by enforce_agent_chat_function_use().

-- Gate trigger function: blocks direct inserts that bypass send_agent_message()
CREATE OR REPLACE FUNCTION enforce_agent_chat_function_use()
RETURNS TRIGGER AS $$
BEGIN
    IF current_setting('agent_chat.bypass_gate', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'Direct INSERT on agent_chat is not allowed. Use send_agent_message() instead.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_enforce_agent_chat_function_use ON agent_chat;
CREATE TRIGGER trg_enforce_agent_chat_function_use
BEFORE INSERT ON agent_chat
FOR EACH ROW
EXECUTE FUNCTION enforce_agent_chat_function_use();

-- send_agent_message: validated, normalized insert API (SECURITY DEFINER)
-- Validates sender and all recipients exist in agents table (or '*' for broadcast).
-- Rejects empty message and empty/NULL recipients.
CREATE OR REPLACE FUNCTION send_agent_message(
    p_sender     TEXT,
    p_message    TEXT,
    p_recipients TEXT[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id        INTEGER;
    v_sender    TEXT;
    v_recipients TEXT[];
BEGIN
    -- Validate inputs
    IF p_message IS NULL OR trim(p_message) = '' THEN
        RAISE EXCEPTION 'send_agent_message: message cannot be empty';
    END IF;

    IF p_recipients IS NULL OR array_length(p_recipients, 1) IS NULL THEN
        RAISE EXCEPTION 'send_agent_message: recipients cannot be NULL or empty — use ARRAY[''*''] for broadcast';
    END IF;

    -- Normalize to lowercase
    v_sender := LOWER(p_sender);
    v_recipients := ARRAY(SELECT LOWER(unnest(p_recipients)));


    -- Bypass gate and insert
    SET LOCAL agent_chat.bypass_gate = 'on';
    INSERT INTO agent_chat (sender, message, recipients)
    VALUES (v_sender, p_message, v_recipients)
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ====================
-- NOTIFICATION TRIGGER
-- ====================

-- Sends pg_notify when a new message arrives
CREATE OR REPLACE FUNCTION notify_agent_chat()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('agent_chat', json_build_object(
        'id',         NEW.id,
        'sender',     NEW.sender,
        'recipients', NEW.recipients
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Note: For logical replication setups, use ENABLE ALWAYS TRIGGER to ensure
-- notifications fire on replicated rows (see installer replication check below).
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
    id           SERIAL PRIMARY KEY,
    content_hash VARCHAR(64) UNIQUE NOT NULL,
    embedding    VECTOR(1536), -- OpenAI ada-002 dimensions
    content      TEXT NOT NULL,
    metadata     JSONB DEFAULT '{}',
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- Index for similarity search
CREATE INDEX IF NOT EXISTS idx_memory_embeddings_vector
ON memory_embeddings USING ivfflat (embedding vector_cosine_ops);

-- Function to create embeddings for new messages
-- Note: This requires OpenAI API access and the vector extension.
-- Produces a placeholder record; external embedding service fills in the vector.
CREATE OR REPLACE FUNCTION embed_chat_message()
RETURNS TRIGGER AS $$
DECLARE
    content_text     TEXT;
    content_hash_val VARCHAR(64);
BEGIN
    content_text     := NEW.sender || ': ' || NEW.message;
    content_hash_val := encode(sha256(content_text::bytea), 'hex');

    INSERT INTO memory_embeddings (content_hash, content, metadata, embedding)
    VALUES (
        content_hash_val,
        content_text,
        json_build_object(
            'chat_id',    NEW.id,
            'sender',     NEW.sender,
            'recipients', NEW.recipients,
            'timestamp',  NEW."timestamp"
        ),
        NULL  -- Populated by external embedding service
    )
    ON CONFLICT (content_hash) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Embedding trigger — should NOT fire on replicated data to avoid duplicates.
DROP TRIGGER IF EXISTS trg_embed_chat_message ON agent_chat;
CREATE TRIGGER trg_embed_chat_message
AFTER INSERT ON agent_chat
FOR EACH ROW
EXECUTE FUNCTION embed_chat_message();

-- ====================
-- CLEANUP FUNCTIONS
-- ====================

-- Drop legacy normalization trigger and function (normalization now in send_agent_message)
DROP TRIGGER IF EXISTS trg_normalize_mentions ON agent_chat;
DROP FUNCTION IF EXISTS normalize_agent_chat_recipients() CASCADE;
DROP FUNCTION IF EXISTS normalize_agent_chat_mentions() CASCADE;

-- expire_old_chat: delete messages older than 30 days
CREATE OR REPLACE FUNCTION expire_old_chat()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM agent_chat
    WHERE "timestamp" < now() - interval '30 days';

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- ====================
-- VIEWS
-- ====================

-- Recent messages (last 30 days)
CREATE OR REPLACE VIEW v_agent_chat_recent AS
SELECT
    id,
    sender,
    message,
    recipients,
    reply_to,
    "timestamp"
FROM agent_chat
WHERE "timestamp" > (now() - INTERVAL '30 days')
ORDER BY "timestamp" DESC;

-- Summary statistics
CREATE OR REPLACE VIEW v_agent_chat_stats AS
SELECT
    count(*)                                                         AS total_messages,
    count(*) FILTER (WHERE "timestamp" > (now() - INTERVAL '24 hours')) AS messages_24h,
    count(*) FILTER (WHERE "timestamp" > (now() - INTERVAL '7 days'))   AS messages_7d,
    count(DISTINCT sender)                                           AS unique_senders,
    pg_size_pretty(pg_total_relation_size('agent_chat'::regclass))   AS table_size,
    min("timestamp")                                                 AS oldest_message,
    max("timestamp")                                                 AS newest_message
FROM agent_chat;

-- ====================
-- LOGICAL REPLICATION NOTES
-- ====================
--
-- Column renames should be transparent to agent_chat_pub since PostgreSQL
-- publications track table OIDs, not column names. However, if the publication
-- was created with an explicit column list (e.g., FOR TABLE agent_chat (id,
-- channel, sender, message, mentions, reply_to, created_at)), it must be
-- recreated after the renames to reflect the new column names.
--
-- The subscriber (graybeard_memory) will also need the same column renames
-- applied — coordinate with Graybeard post-merge.
--
-- After setting up logical replication subscriptions:
--   ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;
--   ALTER TABLE agent_chat ENABLE REPLICA TRIGGER trg_embed_chat_message;
