-- Migration 065: agent_turn_context table and per-turn injection function
-- Adds per-turn context injection system separate from agent_bootstrap_context.
-- Each record is capped at 500 chars; total per agent capped at 2000 chars.

-- ============================================================
-- Table: agent_turn_context
-- ============================================================

CREATE TABLE IF NOT EXISTS agent_turn_context (
    id SERIAL PRIMARY KEY,
    context_type TEXT NOT NULL CHECK (context_type IN ('UNIVERSAL', 'GLOBAL', 'DOMAIN', 'AGENT')),
    context_key TEXT NOT NULL,       -- '*' for UNIVERSAL/GLOBAL, domain name for DOMAIN, agent name for AGENT
    file_key TEXT NOT NULL,          -- unique identifier
    content TEXT NOT NULL CHECK (LENGTH(content) > 0 AND LENGTH(content) <= 500),
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (context_type, file_key)
);

-- ============================================================
-- Trigger: keep updated_at current on row updates
-- ============================================================

CREATE OR REPLACE FUNCTION update_agent_turn_context_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_agent_turn_context_updated_at ON agent_turn_context;

CREATE TRIGGER trg_agent_turn_context_updated_at
    BEFORE UPDATE ON agent_turn_context
    FOR EACH ROW
    EXECUTE FUNCTION update_agent_turn_context_timestamp();

-- ============================================================
-- Function: get_agent_turn_context(p_agent_name TEXT)
-- Returns concatenated context for an agent, up to 2000 chars.
-- Priority order: UNIVERSAL → GLOBAL → DOMAIN → AGENT
-- Returns truncation metadata so the hook can warn when budget is exceeded.
-- ============================================================

CREATE OR REPLACE FUNCTION get_agent_turn_context(p_agent_name TEXT)
RETURNS TABLE (content TEXT, truncated BOOLEAN, records_skipped INT, total_chars INT) AS $$
DECLARE
    v_content TEXT := '';
    v_budget INT := 2000;
    v_total_chars INT := 0;
    v_records_skipped INT := 0;
    v_truncated BOOLEAN := false;
    rec RECORD;
BEGIN
    -- Iterate through records in priority order: UNIVERSAL → GLOBAL → DOMAIN → AGENT
    FOR rec IN
        SELECT atc.content AS rec_content, atc.context_type
        FROM agent_turn_context atc
        WHERE atc.enabled = true
        AND (
            atc.context_type IN ('UNIVERSAL', 'GLOBAL')
            OR (atc.context_type = 'DOMAIN' AND atc.context_key IN (
                SELECT ad.domain_topic FROM agent_domains ad
                JOIN agents a ON a.id = ad.agent_id
                WHERE a.name = p_agent_name
            ))
            OR (atc.context_type = 'AGENT' AND atc.context_key = p_agent_name)
        )
        ORDER BY
            CASE atc.context_type
                WHEN 'UNIVERSAL' THEN 1
                WHEN 'GLOBAL' THEN 2
                WHEN 'DOMAIN' THEN 3
                WHEN 'AGENT' THEN 4
            END,
            atc.file_key
    LOOP
        IF v_total_chars + LENGTH(rec.rec_content) > v_budget THEN
            v_truncated := true;
            v_records_skipped := v_records_skipped + 1;
        ELSE
            IF v_content != '' THEN
                v_content := v_content || E'\n\n';
                v_total_chars := v_total_chars + 2;
            END IF;
            v_content := v_content || rec.rec_content;
            v_total_chars := v_total_chars + LENGTH(rec.rec_content);
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_content, v_truncated, v_records_skipped, v_total_chars;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================
-- Seed data: initial UNIVERSAL turn context records
-- ============================================================

INSERT INTO agent_turn_context (context_type, context_key, file_key, content) VALUES
('UNIVERSAL', '*', 'READING_DISCIPLINE',
'⚠️ Read files/scripts/skills COMPLETELY before acting. After failure, re-read source material before retrying. When delegating, reference source paths — do not abbreviate.')
ON CONFLICT (context_type, file_key) DO NOTHING;
