-- Migration 082: Blocker registry and D100 roll history
-- Issues #356 (heartbeat-integrated blocker outreach) and #358 (forced D100 >12h)

-- ---------------------------------------------------------------------------
-- 1. Blockers table
-- ---------------------------------------------------------------------------
-- Curated registry of items that are blocked waiting on another entity.
-- Source types (per issue #356 as amended 2026-07-02):
--   task, github_issue, workflow_run, unanswered_question, agent_chat_request
--
-- entity_id is NOT NULL. Curation/insert logic must resolve a responsible
-- entity before inserting; if resolution fails, fall back to entity_id = 2
-- (I)ruid) per the spec-gap rulings for SE Run #333.
--
-- Reopen semantics: when a satisfied blocker becomes blocked again, clear
-- satisfied_at back to NULL (ruling #2).
--
-- proactive_outreach predates this table and remains polymorphic:
-- blocker_type references the logical source_type and blocker_id references
-- blockers.id. No FK is added to proactive_outreach (ruling #12).
CREATE TABLE IF NOT EXISTS blockers (
    id SERIAL PRIMARY KEY,
    source_type VARCHAR(50) NOT NULL,
    source_ref VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    needs TEXT NOT NULL,
    entity_id INTEGER NOT NULL REFERENCES entities(id),
    priority INTEGER DEFAULT 5,
    status VARCHAR(20) DEFAULT 'open',
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    satisfied_at TIMESTAMPTZ,
    CONSTRAINT blockers_status_check CHECK (status IN ('open', 'satisfied')),
    CONSTRAINT blockers_source_type_check CHECK (
        source_type IN (
            'task',
            'github_issue',
            'workflow_run',
            'unanswered_question',
            'agent_chat_request'
        )
    ),
    CONSTRAINT blockers_source_unique UNIQUE (source_type, source_ref)
);

CREATE INDEX IF NOT EXISTS idx_blockers_entity ON blockers(entity_id);
CREATE INDEX IF NOT EXISTS idx_blockers_status ON blockers(status);
CREATE INDEX IF NOT EXISTS idx_blockers_priority_first_seen ON blockers(priority ASC, first_seen ASC, id ASC);

-- ---------------------------------------------------------------------------
-- 2. D100 roll history table
-- ---------------------------------------------------------------------------
-- roll_d100() updates motivation_d100.last_rolled for the single slot that
-- was rolled. That column is per-slot and therefore insufficient to answer
-- "when was the most recent D100 roll across any slot?" for the forced-D100
-- gate (#358). This table records every roll event.
CREATE TABLE IF NOT EXISTS d100_roll_log (
    id SERIAL PRIMARY KEY,
    roll INTEGER NOT NULL,
    rolled_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT d100_roll_log_roll_check CHECK (roll >= 1 AND roll <= 100)
);

CREATE INDEX IF NOT EXISTS idx_d100_roll_log_rolled_at ON d100_roll_log(rolled_at DESC);

-- ---------------------------------------------------------------------------
-- 3. Trigger: keep roll_d100() history in sync
-- ---------------------------------------------------------------------------
-- The function is SECURITY DEFINER, so we log from its result via a trigger
-- on motivation_d100 instead of rewriting the function. The trigger fires
-- whenever last_rolled is updated (i.e. after a successful roll_d100() call)
-- and inserts a row into d100_roll_log. We ignore updates that do not change
-- last_rolled (idempotent re-runs).
CREATE OR REPLACE FUNCTION _trg_log_d100_roll()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.last_rolled IS DISTINCT FROM OLD.last_rolled AND NEW.last_rolled IS NOT NULL THEN
        INSERT INTO d100_roll_log (roll, rolled_at)
        VALUES (NEW.roll, NEW.last_rolled);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_d100_roll ON motivation_d100;
CREATE TRIGGER trg_log_d100_roll
    AFTER UPDATE ON motivation_d100
    FOR EACH ROW
    EXECUTE FUNCTION _trg_log_d100_roll();
