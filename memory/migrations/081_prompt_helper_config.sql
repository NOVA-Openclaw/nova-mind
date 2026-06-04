-- Migration 081: Prompt Helper Config, agent_domains keywords/notes, domain seeding
-- Issues: #150 (classifier-first dispatch), #140 (tiered recall), #168 (visibility filter)
--
-- Parts that modify agent_domains (ALTER TABLE, UPDATE) require the table owner
-- (newhart) or a superuser. Run this migration as newhart or postgres.
--
-- Idempotent: all statements use IF NOT EXISTS / ON CONFLICT / conditional UPDATE.

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 1: Create prompt_helper_config table
-- Controls which turn-context subsystems are enabled per message_type per agent.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS prompt_helper_config (
    id           SERIAL PRIMARY KEY,
    message_type TEXT    NOT NULL,
    helper_name  TEXT    NOT NULL,
    enabled      BOOLEAN NOT NULL DEFAULT true,
    priority     INT     NOT NULL DEFAULT 0,
    config       JSONB   NOT NULL DEFAULT '{}',
    agent_name   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT prompt_helper_config_message_type_check CHECK (
        message_type IN ('info_request', 'action', 'conversation', 'continuation', 'command')
    )
);

-- Functional unique index: one row per (message_type, helper_name, agent_name|default)
-- NULL agent_name = default config; agent-specific rows override defaults.
CREATE UNIQUE INDEX IF NOT EXISTS prompt_helper_config_unique_idx
    ON prompt_helper_config (message_type, helper_name, COALESCE(agent_name, '__default__'));

CREATE INDEX IF NOT EXISTS idx_prompt_helper_config_lookup
    ON prompt_helper_config (message_type, agent_name);

COMMENT ON TABLE prompt_helper_config IS
    'Per-message-type gating for turn-context subsystems (entity_resolver, semantic_recall, domain_identifier, turn_reminders). '
    'Rows with agent_name IS NULL are defaults; agent-specific rows override them. '
    'turn_reminders always fires regardless of config.';

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 2: Add keywords column to agent_domains
-- NOTE: Requires table owner (newhart) or superuser.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE agent_domains ADD COLUMN IF NOT EXISTS keywords TEXT[];

CREATE INDEX IF NOT EXISTS idx_agent_domains_keywords_gin
    ON agent_domains USING GIN (keywords);

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 3: Populate notes for the 20 domains missing them
-- NOTE: Requires table owner (newhart) or superuser (trigger: protect_agent_writes).
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE agent_domains SET notes = 'Agent lifecycle management — creating, configuring, and maintaining AI agents'
    WHERE domain_topic = 'Agent Management' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Financial asset trading, portfolio management, and market analysis'
    WHERE domain_topic = 'Asset Trading' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Cross-platform messaging, notifications, and communication routing'
    WHERE domain_topic = 'Communications' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Fiction, poetry, storytelling, and narrative composition'
    WHERE domain_topic = 'Creative Writing' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'PostgreSQL administration, schema design, query optimization, and data management'
    WHERE domain_topic = 'Database' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Delaware corporate law, LLC formation, and business entity regulations'
    WHERE domain_topic = 'Delaware Law' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Infrastructure automation, CI/CD pipelines, and deployment orchestration'
    WHERE domain_topic = 'DevOps' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Technical documentation writing, README maintenance, and API docs'
    WHERE domain_topic = 'Documentation' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Git version control operations — branching, merging, rebasing, and conflict resolution'
    WHERE domain_topic = 'Git operations' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'General IT infrastructure, networking, and system configuration'
    WHERE domain_topic = 'Information Technology' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Web research, information gathering, and source verification'
    WHERE domain_topic = 'Internet Search' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'General legal research, analysis, and compliance'
    WHERE domain_topic = 'Law' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Knowledge curation, cataloging, and reference management'
    WHERE domain_topic = 'Library' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Music composition, production, and audio engineering'
    WHERE domain_topic = 'Music' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'NOVA agent system operations, orchestration, and workflow management'
    WHERE domain_topic = 'NOVA Operations' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Server and dependency updates, patch management'
    WHERE domain_topic = 'Node updates' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'General software development, coding, and architecture design'
    WHERE domain_topic = 'Software Development' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Linux server administration, service management, and monitoring'
    WHERE domain_topic = 'Systems Administration' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Texas state law, regulations, and legal procedures'
    WHERE domain_topic = 'Texas Law' AND (notes IS NULL OR notes = '');

UPDATE agent_domains SET notes = 'Digital art creation, image generation, and visual design'
    WHERE domain_topic = 'Visual Art' AND (notes IS NULL OR notes = '');

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 4: Seed keywords for all 38 domains
-- NOTE: Requires table owner (newhart) or superuser (trigger: protect_agent_writes).
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE agent_domains SET keywords = ARRAY[
    'agent', 'agent design', 'agent architecture', 'agent creation', 'agent onboarding',
    'system prompt', 'persona', 'SOUL.md', 'IDENTITY.md', 'bootstrap context',
    'agent config', 'agent schema', 'new agent', 'agent definition', 'agent role'
] WHERE domain_topic = 'Agent Architecture';

UPDATE agent_domains SET keywords = ARRAY[
    'agent', 'manage agent', 'agent lifecycle', 'agent setup', 'configure agent',
    'agent maintenance', 'spawn agent', 'agent update', 'agent modification',
    'agent list', 'agent status', 'disable agent', 'enable agent'
] WHERE domain_topic = 'Agent Management';

UPDATE agent_domains SET keywords = ARRAY[
    'trade', 'trading', 'buy stock', 'sell stock', 'crypto', 'bitcoin', 'portfolio',
    'market', 'investment', 'asset', 'ticker', 'NASDAQ', 'NYSE', 'equity',
    'option', 'futures', 'technical analysis', 'fundamental analysis', 'price chart',
    'bull', 'bear', 'ETF', 'dividend', 'yield', 'position', 'shares'
] WHERE domain_topic = 'Asset Trading';

UPDATE agent_domains SET keywords = ARRAY[
    'message', 'send message', 'notification', 'notify', 'alert', 'email',
    'SMS', 'chat', 'channel', 'telegram', 'signal', 'slack', 'discord',
    'WhatsApp', 'broadcast', 'comms', 'communication', 'messaging', 'route message'
] WHERE domain_topic = 'Communications';

UPDATE agent_domains SET keywords = ARRAY[
    'write', 'writing', 'story', 'fiction', 'poem', 'poetry', 'narrative',
    'character', 'plot', 'creative', 'author', 'novel', 'short story', 'prose',
    'script', 'dialogue', 'worldbuilding', 'fantasy', 'sci-fi', 'genre'
] WHERE domain_topic = 'Creative Writing';

UPDATE agent_domains SET keywords = ARRAY[
    'sql', 'postgres', 'postgresql', 'psql', 'query', 'schema', 'migration',
    'table', 'index', 'trigger', 'function', 'database', 'db', 'pgvector',
    'embedding', 'constraint', 'foreign key', 'primary key', 'transaction',
    'DDL', 'DML', 'view', 'stored procedure', 'pg', 'nova_memory'
] WHERE domain_topic = 'Database';

UPDATE agent_domains SET keywords = ARRAY[
    'deal', 'price', 'pricing', 'coupon', 'discount', 'sale', 'offer',
    'promo', 'promotion', 'bargain', 'compare price', 'best price', 'lowest price',
    'coupon code', 'voucher', 'cashback', 'rebate', 'clearance'
] WHERE domain_topic = 'Deals & Pricing';

UPDATE agent_domains SET keywords = ARRAY[
    'delaware', 'DE', 'delaware law', 'LLC', 'incorporation', 'delaware corporation',
    'registered agent', 'corporate charter', 'bylaws', 'court of chancery',
    'delaware code', 'DGCL', 'articles of incorporation', 'operating agreement'
] WHERE domain_topic = 'Delaware Law';

UPDATE agent_domains SET keywords = ARRAY[
    'devops', 'CI', 'CD', 'CI/CD', 'pipeline', 'deploy', 'deployment',
    'kubernetes', 'k8s', 'docker', 'container', 'automation', 'infrastructure',
    'IaC', 'terraform', 'ansible', 'github actions', 'jenkins', 'helm',
    'ArgoCD', 'GitOps', 'build pipeline', 'release'
] WHERE domain_topic = 'DevOps';

UPDATE agent_domains SET keywords = ARRAY[
    'document', 'documentation', 'docs', 'README', 'wiki', 'guide', 'manual',
    'API docs', 'docstring', 'changelog', 'release notes', 'write docs',
    'update docs', 'technical guide', 'how-to', 'reference doc'
] WHERE domain_topic = 'Documentation';

UPDATE agent_domains SET keywords = ARRAY[
    'fable', 'fables', 'moral', 'aesop', 'allegory', 'parable', 'fairy tale',
    'story with moral', 'animal story', 'tale', 'moral story', 'lesson story'
] WHERE domain_topic = 'Fables';

UPDATE agent_domains SET keywords = ARRAY[
    'gift', 'gift ideas', 'present', 'birthday', 'anniversary', 'holiday gift',
    'what to buy', 'gift suggestion', 'gift for', 'surprise', 'gift recommendation',
    'wish list', 'gift shopping'
] WHERE domain_topic = 'Gift Ideas';

UPDATE agent_domains SET keywords = ARRAY[
    'git', 'github', 'branch', 'merge', 'pull request', 'PR', 'commit',
    'repo', 'repository', 'rebase', 'cherry-pick', 'stash', 'diff', 'clone',
    'fork', 'push', 'pull', 'git log', 'git blame', 'conflict', 'merge conflict',
    'git status', 'remote', 'origin', 'upstream', 'tag', 'git fetch'
] WHERE domain_topic = 'Git operations';

UPDATE agent_domains SET keywords = ARRAY[
    'security', 'vulnerability', 'CVE', 'patch', 'hardening', 'firewall',
    'IDS', 'IPS', 'SIEM', 'security audit', 'compliance', 'SSL', 'TLS',
    'certificate', 'WAF', 'network security', 'ACL', 'access control'
] WHERE domain_topic = 'IT Security';

UPDATE agent_domains SET keywords = ARRAY[
    'infosec', 'information security', 'cyber', 'cybersecurity', 'threat',
    'attack', 'defense', 'encryption', 'authentication', 'authorization',
    'zero trust', 'IAM', 'RBAC', 'SAST', 'DAST', 'security policy',
    'incident response', 'risk', 'vulnerability management'
] WHERE domain_topic = 'Information Security';

UPDATE agent_domains SET keywords = ARRAY[
    'IT', 'infrastructure', 'network', 'networking', 'DNS', 'DHCP', 'server',
    'hardware', 'operating system', 'OS', 'Windows', 'Linux', 'macOS',
    'cloud', 'AWS', 'Azure', 'GCP', 'virtualization', 'VPN', 'router',
    'switch', 'firewall', 'IP address', 'subnet'
] WHERE domain_topic = 'Information Technology';

UPDATE agent_domains SET keywords = ARRAY[
    'search', 'google', 'web search', 'research', 'find information', 'look up',
    'browse', 'internet', 'online', 'website', 'URL', 'scrape', 'crawl',
    'aggregate', 'fact check', 'verify', 'web research'
] WHERE domain_topic = 'Internet Search';

UPDATE agent_domains SET keywords = ARRAY[
    'law', 'legal', 'attorney', 'lawyer', 'contract', 'lawsuit', 'litigation',
    'court', 'judge', 'statute', 'regulation', 'compliance', 'legal advice',
    'terms', 'agreement', 'NDA', 'IP', 'intellectual property', 'legal research'
] WHERE domain_topic = 'Law';

UPDATE agent_domains SET keywords = ARRAY[
    'library', 'book', 'reference', 'catalog', 'knowledge', 'source',
    'citation', 'bibliography', 'archive', 'collection', 'knowledge base',
    'curate', 'library work', 'reading list', 'literature'
] WHERE domain_topic = 'Library';

UPDATE agent_domains SET keywords = ARRAY[
    'music', 'song', 'audio', 'composition', 'melody', 'harmony', 'chord',
    'beat', 'rhythm', 'lyrics', 'track', 'album', 'artist', 'genre',
    'production', 'mixing', 'mastering', 'DAW', 'MIDI', 'instrument',
    'recording', 'sound design', 'music theory'
] WHERE domain_topic = 'Music';

UPDATE agent_domains SET keywords = ARRAY[
    'nova', 'agent system', 'NOVA', 'orchestration', 'workflow', 'agent ecosystem',
    'coordination', 'task routing', 'openclaw', 'nova-mind', 'system config',
    'operations', 'nova agent', 'agent routing', 'agent coordination'
] WHERE domain_topic = 'NOVA Operations';

UPDATE agent_domains SET keywords = ARRAY[
    'node', 'node.js', 'npm', 'yarn', 'pnpm', 'package', 'dependency',
    'update package', 'upgrade package', 'patch', 'node version', 'nvm',
    'security patch', 'npm audit', 'package.json', 'lock file'
] WHERE domain_topic = 'Node updates';

UPDATE agent_domains SET keywords = ARRAY[
    'openclaw', 'openclaw config', 'plugin', 'hook', 'skill', 'clawhub',
    'gateway', 'channel config', 'agent config', 'openclaw.json', 'plugin SDK',
    'hook system', 'before_prompt_build', 'message_received', 'turn-context',
    'openclaw plugin', 'openclaw hook', 'openclaw skill', 'openclaw gateway'
] WHERE domain_topic = 'OpenClaw Development';

UPDATE agent_domains SET keywords = ARRAY[
    'pentest', 'penetration test', 'pen test', 'red team', 'exploit',
    'vulnerability', 'attack vector', 'privilege escalation', 'lateral movement',
    'payload', 'metasploit', 'nmap', 'burp suite', 'OWASP', 'CTF',
    'recon', 'enumeration', 'post exploitation', 'phishing', 'social engineering'
] WHERE domain_topic = 'Penetration Testing';

UPDATE agent_domains SET keywords = ARRAY[
    'product', 'review', 'spec', 'specification', 'comparison', 'benchmark',
    'feature', 'evaluate', 'product research', 'consumer', 'rating',
    'best product', 'compare products', 'buy guide', 'pros cons'
] WHERE domain_topic = 'Product Research';

UPDATE agent_domains SET keywords = ARRAY[
    'project', 'planning', 'coordination', 'leadership', 'strategy', 'roadmap',
    'milestone', 'deadline', 'stakeholder', 'team', 'sprint', 'agile',
    'kanban', 'prioritize', 'delegate', 'project management', 'PM'
] WHERE domain_topic = 'Project Leadership';

UPDATE agent_domains SET keywords = ARRAY[
    'QA', 'quality', 'testing', 'test', 'test case', 'bug', 'defect',
    'validation', 'verification', 'acceptance criteria', 'regression',
    'test plan', 'smoke test', 'UAT', 'quality assurance', 'test coverage'
] WHERE domain_topic = 'Quality Assurance';

UPDATE agent_domains SET keywords = ARRAY[
    'research', 'investigate', 'analysis', 'data', 'study', 'survey', 'report',
    'source', 'reference', 'fact-check', 'background', 'deep dive', 'explore',
    'gather information', 'literature review', 'investigation'
] WHERE domain_topic = 'Research';

UPDATE agent_domains SET keywords = ARRAY[
    'restock', 'inventory', 'replenish', 'stock', 'supply', 'order',
    'consumable', 'out of stock', 'low stock', 'purchase order', 'vendor',
    'supplier', 'track inventory', 'reorder', 'stock level'
] WHERE domain_topic = 'Restock Management';

UPDATE agent_domains SET keywords = ARRAY[
    'shop', 'shopping', 'buy', 'purchase', 'order', 'Amazon', 'checkout',
    'cart', 'product', 'item', 'store', 'retailer', 'price', 'cost',
    'sale', 'deal', 'online shopping', 'e-commerce', 'add to cart'
] WHERE domain_topic = 'Shopping';

UPDATE agent_domains SET keywords = ARRAY[
    'code', 'coding', 'develop', 'development', 'software', 'program',
    'programming', 'implement', 'feature', 'refactor', 'API', 'backend',
    'frontend', 'full stack', 'architecture', 'design pattern', 'codebase',
    'library', 'framework', 'module', 'class', 'function', 'method'
] WHERE domain_topic = 'Software Development';

UPDATE agent_domains SET keywords = ARRAY[
    'engineer', 'engineering', 'system design', 'scalability', 'performance',
    'optimization', 'algorithm', 'data structure', 'OOP', 'SOLID', 'clean code',
    'TDD', 'DDD', 'microservices', 'distributed', 'software engineering',
    'architecture review', 'technical debt', 'code review'
] WHERE domain_topic = 'Software Engineering';

UPDATE agent_domains SET keywords = ARRAY[
    'test', 'testing', 'unit test', 'integration test', 'e2e', 'end-to-end',
    'test execution', 'test runner', 'jest', 'pytest', 'mocha', 'cypress',
    'selenium', 'automated testing', 'test suite', 'run tests', 'flaky test'
] WHERE domain_topic = 'Software Testing';

UPDATE agent_domains SET keywords = ARRAY[
    'sysadmin', 'system admin', 'linux', 'ubuntu', 'debian', 'centos', 'RHEL',
    'systemd', 'service', 'cron', 'bash', 'shell', 'server management',
    'process', 'daemon', 'log', 'monitoring', 'disk', 'CPU', 'memory',
    'top', 'htop', 'journalctl', 'systemctl'
] WHERE domain_topic = 'Systems Administration';

UPDATE agent_domains SET keywords = ARRAY[
    'technical writing', 'documentation', 'API doc', 'user guide', 'manual',
    'specification', 'runbook', 'playbook', 'procedure', 'SOP', 'style guide',
    'release notes', 'CHANGELOG', 'tech doc', 'write specification'
] WHERE domain_topic = 'Technical Writing';

UPDATE agent_domains SET keywords = ARRAY[
    'texas', 'TX', 'texas law', 'texas statute', 'texas court', 'texas regulations',
    'texas business', 'texas LLC', 'texas corporation', 'Texas Family Code',
    'Texas Property Code', 'Texas Penal Code', 'TexasBar'
] WHERE domain_topic = 'Texas Law';

UPDATE agent_domains SET keywords = ARRAY[
    'git', 'version control', 'github', 'gitlab', 'bitbucket', 'branch', 'tag',
    'release', 'versioning', 'merge request', 'code review', 'PR review',
    'git flow', 'trunk based', 'merge', 'rebase', 'cherry-pick', 'commit history'
] WHERE domain_topic = 'Version Control';

UPDATE agent_domains SET keywords = ARRAY[
    'art', 'visual', 'design', 'image', 'illustration', 'graphic', 'digital art',
    'painting', 'drawing', 'color', 'typography', 'UI design', 'UX design',
    'canvas', 'generative art', 'stable diffusion', 'DALL-E', 'midjourney',
    'image generation', 'prompt', 'visual style', 'palette', 'composition'
] WHERE domain_topic = 'Visual Art';

-- ─────────────────────────────────────────────────────────────────────────────
-- Part 5: Seed default prompt_helper_config rows
-- ─────────────────────────────────────────────────────────────────────────────
-- Gating rules per message type:
--   info_request:  all subsystems enabled (user wants info, need full context)
--   action:        all subsystems enabled (user wants action, need routing + recall)
--   conversation:  entity_resolver only; skip recall+domain (casual chat, no context needed)
--   continuation:  reminders only; skip all others (short ack, no lookup overhead)
--   command:       reminders only; skip all others (command handling, no context needed)

INSERT INTO prompt_helper_config (message_type, helper_name, enabled, agent_name)
VALUES
    -- info_request: all enabled
    ('info_request', 'entity_resolver',   true,  NULL),
    ('info_request', 'semantic_recall',   true,  NULL),
    ('info_request', 'domain_identifier', true,  NULL),
    ('info_request', 'turn_reminders',    true,  NULL),
    -- action: all enabled
    ('action', 'entity_resolver',   true,  NULL),
    ('action', 'semantic_recall',   true,  NULL),
    ('action', 'domain_identifier', true,  NULL),
    ('action', 'turn_reminders',    true,  NULL),
    -- conversation: entity_resolver only; recall+domain skipped
    ('conversation', 'entity_resolver',   true,  NULL),
    ('conversation', 'semantic_recall',   false, NULL),
    ('conversation', 'domain_identifier', false, NULL),
    ('conversation', 'turn_reminders',    true,  NULL),
    -- continuation: reminders only
    ('continuation', 'entity_resolver',   false, NULL),
    ('continuation', 'semantic_recall',   false, NULL),
    ('continuation', 'domain_identifier', false, NULL),
    ('continuation', 'turn_reminders',    true,  NULL),
    -- command: reminders only
    ('command', 'entity_resolver',   false, NULL),
    ('command', 'semantic_recall',   false, NULL),
    ('command', 'domain_identifier', false, NULL),
    ('command', 'turn_reminders',    true,  NULL)
ON CONFLICT DO NOTHING;
