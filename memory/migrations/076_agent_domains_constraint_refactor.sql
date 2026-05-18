-- Migration 076: Refactor agent_domains constraints — add priority, change UNIQUE
-- Issue #234

-- 1. Drop old UNIQUE constraint on domain_topic (allows multiple agents per domain)
ALTER TABLE agent_domains
DROP CONSTRAINT IF EXISTS agent_domains_domain_topic_key;

-- 2. Add priority column with DEFAULT 1
ALTER TABLE agent_domains
ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 1;

-- 3. Populate priority for existing rows (should already be 1 via DEFAULT)
UPDATE agent_domains SET priority = 1 WHERE priority IS NULL;

-- 4. Add UNIQUE constraint on (agent_id, domain_topic)
ALTER TABLE agent_domains
ADD CONSTRAINT agent_domains_agent_id_domain_topic_key UNIQUE (agent_id, domain_topic);
