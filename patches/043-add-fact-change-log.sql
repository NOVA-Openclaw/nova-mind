-- Migration: Add fact_change_log table for tracking authority overrides
-- Issue: #43 - Source Authority
-- Date: 2026-02-11

CREATE TABLE IF NOT EXISTS fact_change_log (
    id SERIAL PRIMARY KEY,
    fact_id INTEGER NOT NULL REFERENCES entity_facts(id) ON DELETE CASCADE,
    old_value TEXT,
    new_value TEXT,
    changed_by_entity_id INTEGER REFERENCES entities(id) ON DELETE SET NULL,
    reason VARCHAR(100),
    changed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fact_change_log_fact_id ON fact_change_log(fact_id);
CREATE INDEX IF NOT EXISTS idx_fact_change_log_reason ON fact_change_log(reason);
CREATE INDEX IF NOT EXISTS idx_fact_change_log_changed_at ON fact_change_log(changed_at DESC);

COMMENT ON TABLE fact_change_log IS 'Tracks changes to entity facts, especially authority overrides';
COMMENT ON COLUMN fact_change_log.fact_id IS 'Reference to entity_facts.id';
COMMENT ON COLUMN fact_change_log.changed_by_entity_id IS 'Entity that made the change';
COMMENT ON COLUMN fact_change_log.reason IS 'Reason for change (e.g., authority_override, confidence_update)';
