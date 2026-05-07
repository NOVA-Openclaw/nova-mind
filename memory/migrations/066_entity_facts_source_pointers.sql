-- Add source pointer columns to entity_facts
-- These point to the chat transcript entry that triggered the extraction
-- Currently points to JSONL session files; will migrate to DB message IDs (#170)

ALTER TABLE entity_facts ADD COLUMN IF NOT EXISTS source_session_id TEXT;
ALTER TABLE entity_facts ADD COLUMN IF NOT EXISTS source_timestamp TIMESTAMPTZ;

COMMENT ON COLUMN entity_facts.source_session_id IS 'Session UUID where this fact was extracted from. Maps to JSONL filename, future: DB session ID (#170)';
COMMENT ON COLUMN entity_facts.source_timestamp IS 'Timestamp of the message that triggered extraction. Used with source_session_id to locate exact source context.';

-- Index for lookups by session
CREATE INDEX IF NOT EXISTS idx_entity_facts_source_session ON entity_facts(source_session_id) WHERE source_session_id IS NOT NULL;
