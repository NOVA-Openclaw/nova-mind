-- Migration 088: heartbeat isolatedSession flag
-- Issue #714: preserve isolatedSession: true on nova's heartbeat config and
-- propagate it through agent-config-sync / agents.json generation.
--
-- Adds heartbeat_isolated_session boolean to agents so the per-agent heartbeat
-- block can carry the OpenClaw 2026.9.x isolatedSession field. Defaults to
-- false for every agent except nova, whose heartbeat already runs in an
-- isolated session today and must keep doing so.

ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS heartbeat_isolated_session boolean DEFAULT false;

-- Seed nova's existing heartbeat row to keep its isolated session behaviour.
-- The predicate `heartbeat_enabled = true` avoids touching agents that have
-- not opted into heartbeat; the COALESCE guard makes the migration idempotent.
UPDATE agents
   SET heartbeat_isolated_session = true
 WHERE name = 'nova'
   AND heartbeat_enabled = true
   AND COALESCE(heartbeat_isolated_session, false) = false;

COMMENT ON COLUMN agents.heartbeat_isolated_session IS
    'When true, the agent heartbeat runs with isolatedSession: true (fresh '
    'session each run). Mirrors OpenClaw 2026.9.x HeartbeatSchema.isolatedSession.';
