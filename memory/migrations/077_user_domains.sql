-- Migration 077: Create user_domains table and seed data
-- Issue #232

-- 1. Create user_domains table
CREATE TABLE IF NOT EXISTS user_domains (
    id SERIAL PRIMARY KEY,
    entity_id INTEGER NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
    domain_topic VARCHAR(255) NOT NULL,
    priority INTEGER DEFAULT 1,
    notes TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT user_domains_entity_domain_key UNIQUE (entity_id, domain_topic)
);

-- 2. Indexes
CREATE INDEX IF NOT EXISTS idx_user_domains_entity ON user_domains(entity_id);
CREATE INDEX IF NOT EXISTS idx_user_domains_topic ON user_domains(domain_topic);

-- 3. Seed data — 17 rows across 5 users
-- I)ruid (entity 2)
INSERT INTO user_domains (entity_id, domain_topic, priority) VALUES
    (2, 'Database', 1),
    (2, 'Information Security', 1),
    (2, 'IT Security', 1),
    (2, 'NOVA Operations', 1),
    (2, 'Penetration Testing', 1),
    (2, 'Project Leadership', 1),
    (2, 'Software Engineering', 1),
    (2, 'Systems Administration', 1)
ON CONFLICT (entity_id, domain_topic) DO NOTHING;

-- Neva (entity 8)
INSERT INTO user_domains (entity_id, domain_topic, priority) VALUES
    (8, 'Marketing/Branding', 1),
    (8, 'Visual Art', 1)
ON CONFLICT (entity_id, domain_topic) DO NOTHING;

-- Regan (entity 5)
INSERT INTO user_domains (entity_id, domain_topic, priority) VALUES
    (5, 'Creative Writing', 1),
    (5, 'Marketing/Branding', 1)
ON CONFLICT (entity_id, domain_topic) DO NOTHING;

-- Tabatha Wilson (entity 3)
INSERT INTO user_domains (entity_id, domain_topic, priority) VALUES
    (3, 'Crafting', 1),
    (3, 'Visual Art', 2)
ON CONFLICT (entity_id, domain_topic) DO NOTHING;

-- Zonk Ruehl (entity 56)
INSERT INTO user_domains (entity_id, domain_topic, priority) VALUES
    (56, 'DevOps', 1),
    (56, 'Information Security', 1),
    (56, 'Music', 1)
ON CONFLICT (entity_id, domain_topic) DO NOTHING;
