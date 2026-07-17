-- Migration 085: extraction_failures dead-letter table + replay support
-- Issue #485: memory-extract hook stderr capture, dead-letter persistence, and replay path.

-- ---------------------------------------------------------------------------
-- Dead-letter table for memory extraction failures.
-- ---------------------------------------------------------------------------
-- Purpose: preserve message bodies and stderr tails when extract_memories.py
-- fails, exits nonzero, or the child process times out, so that facts are not
-- permanently lost and can be retried via extraction-replay.sh.
--
-- FK semantics:
--   channel_transcript_id REFERENCES channel_transcripts(id) ON DELETE SET NULL.
--   Deleting a parent session cascades to channel_transcripts, but the dead-letter
--   row survives with a NULL FK so failure evidence is retained.
--   When the FK cannot be resolved at write time, the raw message body is stored
--   in `content` as a fallback.
--
-- State machine (status column):
--   pending         -> eligible for replay
--   resolved        -> replay succeeded, resolved_at set
--   retry_exhausted -> replay failed and max retries reached
--   unreplayable    -> no FK and no body (cannot be reconstructed)
CREATE TABLE IF NOT EXISTS extraction_failures (
    id                      BIGSERIAL PRIMARY KEY,
    channel_transcript_id   BIGINT REFERENCES channel_transcripts(id) ON DELETE SET NULL,
    session_key             TEXT,
    sender_name             TEXT,
    sender_id               TEXT,
    content                 TEXT,
    stderr_tail             TEXT,
    stdout_tail             TEXT,
    exit_code               INTEGER,
    failure_reason          VARCHAR(50),
    retry_count             INTEGER NOT NULL DEFAULT 0,
    status                  VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_attempt_at         TIMESTAMPTZ,
    resolved_at             TIMESTAMPTZ,
    CONSTRAINT extraction_failures_status_check CHECK (
        status IN ('pending', 'resolved', 'retry_exhausted', 'unreplayable')
    ),
    CONSTRAINT extraction_failures_failure_reason_check CHECK (
        failure_reason IS NULL
        OR failure_reason IN ('nonzero_exit', 'timeout', 'spawn_error', 'unreplayable')
    ),
    CONSTRAINT extraction_failures_retry_count_nonnegative CHECK (retry_count >= 0)
);

-- Eligibility query filter.
CREATE INDEX IF NOT EXISTS idx_extraction_failures_status
    ON extraction_failures (status);

-- Look up dead-letter rows by transcript (when FK is intact).
CREATE INDEX IF NOT EXISTS idx_extraction_failures_channel_transcript_id
    ON extraction_failures (channel_transcript_id)
    WHERE channel_transcript_id IS NOT NULL;

-- Age-based monitoring and future retention/cleanup policies.
CREATE INDEX IF NOT EXISTS idx_extraction_failures_created_at
    ON extraction_failures (created_at);

-- Replay ordering: oldest pending rows first, with retry_count secondary.
CREATE INDEX IF NOT EXISTS idx_extraction_failures_replay_order
    ON extraction_failures (status, retry_count ASC, created_at ASC, id ASC);

COMMENT ON TABLE extraction_failures IS
    'Dead-letter store for failed memory extractions from memory-extract hook (#485). '
    'Rows are inserted on nonzero exit, timeout, or spawn error and may be retried via extraction-replay.sh.';
