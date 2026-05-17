-- Migration: Add agent_id entity_facts for peer agent entity resolution
-- Issue: #225
--
-- Provides platform-prefixed agent identifiers (agent:nova, agent:newhart, etc.)
-- that the _resolve_by_sender_id() function can match via value-scan in entity_facts.

INSERT INTO entity_facts (entity_id, key, value, confidence)
VALUES
  (1, 'agent_id', 'agent:nova', 1.0),
  (256, 'agent_id', 'agent:newhart', 1.0),
  (388, 'agent_id', 'agent:graybeard', 1.0)
ON CONFLICT (entity_id, key) DO NOTHING;

COMMENT ON TABLE entity_facts IS 'Key-value facts about entities. agent_id values (agent:nova, etc.) enable sender resolution from outbound agent messages. Check current_timezone for I)ruid before time-based actions.';
