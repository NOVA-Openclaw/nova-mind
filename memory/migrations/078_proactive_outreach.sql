-- Migration 078: Create proactive_outreach table and Tabby email entity fact
-- Issue #232

-- 1. Create proactive_outreach table
CREATE TABLE IF NOT EXISTS proactive_outreach (
    id SERIAL PRIMARY KEY,
    entity_id INTEGER NOT NULL REFERENCES entities(id),
    blocker_type VARCHAR(50) NOT NULL,
    blocker_id INTEGER NOT NULL,
    channel VARCHAR(50) NOT NULL,
    channel_target TEXT,
    message_summary TEXT,
    attempt_at TIMESTAMPTZ DEFAULT NOW(),
    response_received BOOLEAN DEFAULT FALSE,
    response_at TIMESTAMPTZ,
    notes TEXT
);

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_proactive_outreach_entity ON proactive_outreach(entity_id);
CREATE INDEX IF NOT EXISTS idx_proactive_outreach_blocker ON proactive_outreach(blocker_type, blocker_id);
CREATE INDEX IF NOT EXISTS idx_proactive_outreach_cooldown ON proactive_outreach(entity_id, blocker_type, blocker_id, attempt_at);

-- 3. Tabby's email as entity_fact
INSERT INTO entity_facts (entity_id, key, value, source)
VALUES (3, 'email', 'yellowsubtab@gmail.com', 'I)ruid')
ON CONFLICT (entity_id, key, source) DO NOTHING;
