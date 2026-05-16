-- Migration: Create self_awareness_triggers table
-- Issue: #221
--
-- Table for self-awareness trigger patterns. The self-awareness plugin on
-- message_sent embeds content via local ollama and cosine-compares against
-- keyphrase_embeddings.

CREATE TABLE IF NOT EXISTS self_awareness_triggers (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL,  -- significant_conversation, uncertainty, memory_reinforcement, self_expression, pattern_detection
    keyphrases TEXT[] NOT NULL,
    keyphrase_embeddings JSONB,  -- pre-computed embeddings, populated by hook self-heal
    similarity_threshold FLOAT DEFAULT 0.65,
    action TEXT NOT NULL,  -- system_event, database_update, context_inject, log_only
    action_config JSONB,
    enabled BOOLEAN DEFAULT true,
    cooldown_minutes INTEGER DEFAULT 30,
    last_triggered_at TIMESTAMPTZ,
    times_triggered INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE self_awareness_triggers IS 'Self-awareness trigger patterns for outbound message monitoring. The self-awareness plugin on message_sent embeds content via local ollama and cosine-compares against keyphrase_embeddings.';

-- Seed initial triggers
INSERT INTO self_awareness_triggers (name, category, keyphrases, similarity_threshold, action, action_config, cooldown_minutes) VALUES
('Reflective language', 'significant_conversation',
 ARRAY['hit different', 'satisfying conversation', 'proud of', 'surprised me', 'did not expect', 'feels important', 'learned something', 'this was meaningful'],
 0.65, 'log_only', '{"log_category": "significant_conversation"}', 30),
('Self-doubt signals', 'uncertainty',
 ARRAY['I am not sure', 'I need to check', 'I might be wrong', 'let me verify', 'I could be wrong'],
 0.70, 'log_only', '{"log_category": "uncertainty", "flag_for_review": true}', 15),
('Strong knowledge claims', 'memory_reinforcement',
 ARRAY['I remember', 'we decided', 'the lesson was', 'last time we'],
 0.70, 'log_only', '{"log_category": "memory_reinforcement"}', 15);
