-- Migration 067: channel_sessions and channel_transcripts tables
-- Implements structured chat transcript storage (#165, #138, #170)
-- Replaces conversations table with properly normalised session/transcript schema.
-- entity_facts gains FK source pointers to channel_transcripts.

-- ============================================================
-- Table: channel_sessions
-- ============================================================

CREATE TABLE IF NOT EXISTS channel_sessions (
    id                      BIGSERIAL PRIMARY KEY,
    session_key             TEXT,
    agent_id                TEXT NOT NULL DEFAULT 'main',
    provider                TEXT NOT NULL,
    external_chat_id        TEXT NOT NULL,
    external_thread_id      TEXT,
    chat_type               TEXT NOT NULL,
    title                   TEXT,
    group_subject           TEXT,
    group_space_id          TEXT,
    started_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at         TIMESTAMPTZ,
    message_count           INTEGER DEFAULT 0,
    raw_metadata            JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_channel_sessions_provider_chat
    ON channel_sessions (provider, external_chat_id, COALESCE(external_thread_id, ''));

CREATE INDEX IF NOT EXISTS idx_channel_sessions_session_key
    ON channel_sessions (session_key);

CREATE INDEX IF NOT EXISTS idx_channel_sessions_last_msg
    ON channel_sessions (last_message_at DESC);

-- ============================================================
-- Table: channel_transcripts
-- ============================================================

CREATE TABLE IF NOT EXISTS channel_transcripts (
    id                          BIGSERIAL PRIMARY KEY,
    session_id                  BIGINT NOT NULL REFERENCES channel_sessions(id) ON DELETE CASCADE,
    external_message_id         TEXT NOT NULL,
    timestamp                   TIMESTAMPTZ NOT NULL,
    sender_id                   TEXT,
    sender_name                 TEXT,
    sender_username             TEXT,
    sender_tag                  TEXT,
    sender_entity_id            BIGINT REFERENCES entities(id),
    role                        TEXT NOT NULL DEFAULT 'user',
    content                     TEXT,
    content_type                TEXT DEFAULT 'text',
    raw_metadata                JSONB,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_channel_transcripts_session_time
    ON channel_transcripts (session_id, timestamp);

CREATE UNIQUE INDEX IF NOT EXISTS idx_channel_transcripts_provider_msg
    ON channel_transcripts (session_id, external_message_id);

CREATE INDEX IF NOT EXISTS idx_channel_transcripts_sender_entity
    ON channel_transcripts (sender_entity_id, timestamp);

CREATE INDEX IF NOT EXISTS idx_channel_transcripts_external_sender
    ON channel_transcripts (sender_id, timestamp);

-- ============================================================
-- entity_facts: add FK source pointers to channel tables
-- ============================================================

ALTER TABLE entity_facts
    ADD COLUMN IF NOT EXISTS source_channel_transcript_id BIGINT REFERENCES channel_transcripts(id),
    ADD COLUMN IF NOT EXISTS source_channel_session_id BIGINT REFERENCES channel_sessions(id);

COMMENT ON COLUMN entity_facts.source_channel_transcript_id IS 'FK to channel_transcripts row that triggered this fact extraction (#170)';
COMMENT ON COLUMN entity_facts.source_channel_session_id IS 'FK to channel_sessions row (denormalised for fast session-level queries)';

CREATE INDEX IF NOT EXISTS idx_entity_facts_channel_transcript
    ON entity_facts (source_channel_transcript_id)
    WHERE source_channel_transcript_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_entity_facts_channel_session
    ON entity_facts (source_channel_session_id)
    WHERE source_channel_session_id IS NOT NULL;

-- ============================================================
-- Drop legacy conversations table (superseded by channel_sessions)
-- ============================================================

DROP TABLE IF EXISTS conversations CASCADE;
