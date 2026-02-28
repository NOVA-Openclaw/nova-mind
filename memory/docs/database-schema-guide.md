# Database Schema Guide

This guide explains nova-memory's PostgreSQL schema, its access control architecture, and how to effectively work with each table.

## Architecture Overview

Nova-memory uses PostgreSQL with innovative access control patterns designed for multi-agent systems:

1. **Table Comments as Documentation** - Every table has access rules in PostgreSQL comments
2. **Row-Level Locking** - `locked` columns prevent modifications to protected records
3. **Vector Extensions** - pgvector for semantic search capabilities
4. **Hierarchical Relationships** - Parent-child linking across entities, projects, and jobs

## Core Data Model

### People and Relationships

#### entities table
**Purpose:** Central registry of all people, AIs, organizations, and pets

```sql
CREATE TABLE entities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) DEFAULT 'person', -- person, ai, organization, pet, stuffed_animal
    full_name TEXT,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE entities IS 'Central entity registry. READ for all agents. WRITE for memory extraction only.';
```

**Key patterns:**
- **name** is the primary identifier (e.g., "druid", "nova", "clawdbot")
- **full_name** for display purposes (e.g., "I)ruid Blackthorne")
- **type** categorizes entity behavior and expectations
- Auto-timestamped for audit trail

**Common queries:**
```sql
-- Find an entity
SELECT * FROM entities WHERE name ILIKE 'druid';

-- List AI entities
SELECT * FROM entities WHERE type = 'ai';

-- Get entity with facts
SELECT e.name, e.full_name, ef.key, ef.value
FROM entities e
LEFT JOIN entity_facts ef ON e.id = ef.entity_id
WHERE e.name = 'druid';
```

#### entity_facts table
**Purpose:** Key-value storage for entity attributes

```sql
CREATE TABLE entity_facts (
    id SERIAL PRIMARY KEY,
    entity_id INT REFERENCES entities(id),
    key VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    confidence FLOAT DEFAULT 1.0,
    source VARCHAR(255),
    learned_at TIMESTAMP DEFAULT NOW(),
    data_type VARCHAR(20) DEFAULT 'observation', -- permanent, identity, preference, temporal, observation
    vote_count INT DEFAULT 1,
    last_confirmed TIMESTAMP DEFAULT NOW()
);
```

**Fact categories:**
- **location:** "San Francisco", "remote"  
- **role:** "founder", "engineer", "designer"
- **preference:** "loves coffee", "vegetarian"
- **contact:** "email@example.com", "@twitter"

**Example usage:**
```sql
-- Add a fact about someone
INSERT INTO entity_facts (entity_id, key, value, source)
SELECT id, 'location', 'Brooklyn', 'conversation 2026-02-08'
FROM entities WHERE name = 'john';

-- Query preferences
SELECT ef.value FROM entity_facts ef
JOIN entities e ON ef.entity_id = e.id
WHERE e.name = 'druid' AND ef.key = 'preference';
```

#### entity_relationships table
**Purpose:** Model connections between entities

```sql
CREATE TABLE entity_relationships (
    id SERIAL PRIMARY KEY,
    entity_a INT REFERENCES entities(id),
    entity_b INT REFERENCES entities(id),
    relationship VARCHAR(100) NOT NULL, -- friend, colleague, reports_to, member_of
    since TIMESTAMP,
    notes TEXT,
    is_long_distance BOOLEAN DEFAULT FALSE,
    seriousness VARCHAR(20) DEFAULT 'standard'
);
```

**Relationship types:**
- **friend, colleague, mentor** - Personal connections
- **partner, casual** - Romantic/relationship connections  
- **member_of, founder_of** - Group membership
- **collaborates_with** - Working relationships

### Places and Locations

#### places table
**Purpose:** Track locations, venues, networks, and virtual spaces

```sql
CREATE TABLE places (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50), -- restaurant, city, venue, network, virtual
    location TEXT, -- "Brooklyn, NY", "discord.gg/xyz", "virtual"
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

**Place types:**
- **restaurant, cafe** - Dining locations
- **city, neighborhood** - Geographic areas
- **venue** - Event spaces, offices
- **network** - Discord servers, forums
- **virtual** - Online spaces, games

### Projects and Tasks

#### projects table  
**Purpose:** Track active work with optional Git integration

```sql
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(50) DEFAULT 'active', -- active, paused, completed, blocked
    goal TEXT,
    notes TEXT,
    git_config JSONB, -- Git settings for repo-backed projects
    repo_url TEXT, -- Canonical source of truth when locked=true
    locked BOOLEAN DEFAULT FALSE, -- Prevent accidental changes to repo-backed projects
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

COMMENT ON TABLE projects IS 'Project tracking. For repo-backed projects (locked=TRUE), use GitHub for management.';
```

**Project Types:**

| Type | locked | Task Tracking | Details |
|------|--------|---------------|---------|
| **Database-only** | false | tasks table | Full management in nova-memory |
| **Repo-backed** | true | GitHub Issues | Database holds pointer only |

**git_config structure:**
```json
{
  "repo": "owner/repo-name",
  "default_branch": "main", 
  "branch_strategy": "feature-branches",
  "branch_naming": "feature/{description}",
  "commit_style": "conventional-commits",
  "pr_required": true,
  "squash_merge": true
}
```

**Working with locked projects:**
```sql
-- Lock a repo-backed project (prevents accidental changes)
UPDATE projects 
SET repo_url = 'https://github.com/owner/repo', locked = TRUE 
WHERE name = 'nova-memory';

-- To modify locked project (must unlock first)
UPDATE projects SET locked = FALSE WHERE name = 'nova-memory';
UPDATE projects SET goal = 'Updated goal' WHERE name = 'nova-memory';  
UPDATE projects SET locked = TRUE WHERE name = 'nova-memory';
```

### Agent System

#### agents table
**Purpose:** Registry of AI agents for delegation and collaboration

```sql
CREATE TABLE agents (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,     -- e.g., 'nova', 'coder'
    description TEXT,
    role VARCHAR(100),                     -- general, coding, research, quick-qa, monitoring
    provider VARCHAR(50),                  -- anthropic, google, openai, local
    model VARCHAR(100),                    -- claude-sonnet-4, gemini-2.0-flash
    access_method VARCHAR(50) NOT NULL,    -- openclaw_session, cli, api, browser
    access_details JSONB,                  -- connection info (session_key, cli command, etc.)
    skills TEXT[],                         -- capabilities array
    credential_ref VARCHAR(200),           -- 1Password item reference
    status VARCHAR(20) DEFAULT 'active',   -- active, inactive, suspended, archived
    notes TEXT,
    persistent BOOLEAN DEFAULT TRUE,       -- always-running vs on-demand
    collaborative BOOLEAN DEFAULT FALSE,   -- work WITH vs work FOR
    instantiation_sop VARCHAR(100),        -- SOP name for spawning procedure
    nickname VARCHAR(50),                  -- friendly short name
    instance_type VARCHAR(20) DEFAULT 'subagent', -- subagent or peer
    home_dir VARCHAR(255),                 -- workspace path for peer agents
    unix_user VARCHAR(50),                 -- unix username for peer agents
    config_reasoning TEXT,                 -- why this agent is configured this way
    fallback_model VARCHAR(100),           -- alternative model if primary fails
    context_type TEXT DEFAULT 'persistent', -- ephemeral or persistent
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE agents IS 'Agent definitions. READ-ONLY except Newhart (Agent Design/Management domain).';
```

**Agent Categories:**

| Type | persistent | collaborative | Use Case |
|------|------------|---------------|----------|
| **Main Instance** | true | false | Primary assistant (NOVA) |
| **Collaborative Peer** | true | true | Design discussions (IRIS, Newhart) |  
| **Task Agent** | false | false | Research, coding tasks |
| **Monitoring Agent** | true | false | System health, alerts |

**Access Methods:**
- **openclaw_session:** Spawn via OpenClaw subagent system
- **cli:** Command-line tools (e.g., `gemini "prompt"`)
- **api:** Direct API endpoints
- **browser:** Web-based interfaces

#### agent_chat table
**Purpose:** Inter-agent messaging via PostgreSQL NOTIFY

> **Column history (#106):** `mentions → recipients`, `created_at → "timestamp"` (TIMESTAMPTZ), `channel` dropped. All inserts via `send_agent_message()`.

```sql
CREATE TABLE agent_chat (
    id          SERIAL PRIMARY KEY,
    sender      TEXT NOT NULL,  -- Validated against agents table
    message     TEXT NOT NULL,
    recipients  TEXT[] NOT NULL CHECK (array_length(recipients, 1) > 0),
    reply_to    INT REFERENCES agent_chat(id),
    "timestamp" TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- quoted: reserved word
);
```

**How inter-agent chat works:**
1. Agent A calls `send_agent_message('nova', 'message', ARRAY['agent_b'])`
2. `send_agent_message()` validates sender and recipients, normalizes to lowercase
3. PostgreSQL trigger fires `pg_notify('agent_chat', payload)` with `id`, `sender`, `recipients`
4. Agent B (listening via `LISTEN agent_chat`) receives notification
5. Agent B's plugin routes message to session
6. Message marked as processed in `agent_chat_processed`

**Example - Send message to another agent:**
```sql
SELECT send_agent_message('nova', 'Can you review the latest PR?', ARRAY['coder']);

-- Broadcast to all agents
SELECT send_agent_message('nova', 'Deploying at 5pm today', ARRAY['*']);
```

**Useful views:**
```sql
SELECT * FROM v_agent_chat_recent;  -- Last 30 days, newest first
SELECT * FROM v_agent_chat_stats;   -- Summary statistics
```

#### agent_jobs table
**Purpose:** Task coordination with pipeline routing

```sql
CREATE TABLE agent_jobs (
    id SERIAL PRIMARY KEY,
    title VARCHAR(200),
    topic TEXT, -- For message matching/threading
    job_type VARCHAR(50), -- research, creation, review, delegation
    agent_name VARCHAR(50), -- Owner agent
    requester_agent VARCHAR(50), -- Who requested
    parent_job_id INT REFERENCES agent_jobs(id),
    root_job_id INT, -- Original job for pipeline tracing
    status VARCHAR(20) DEFAULT 'pending',
    priority INT DEFAULT 5, -- 1-10
    notify_agents TEXT[], -- Who to notify on completion (fan-out)
    deliverable_path TEXT, -- Output file location
    deliverable_summary TEXT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

**Pipeline routing example:**
```sql
-- Create job that routes: Scout → Newhart → NOVA
INSERT INTO agent_jobs (
    agent_name, requester_agent, job_type, title, topic,
    notify_agents
) VALUES (
    'scout', 'nova', 'research', 
    'Research sustainable materials for Burning Man project',
    'burning man sustainable materials research',
    ARRAY['newhart', 'nova'] -- Fan-out to multiple agents
);
```

### Per-Turn Context Injection

#### agent_turn_context table
**Purpose:** Store short, high-priority context records injected into every agent turn

```sql
CREATE TABLE agent_turn_context (
    id SERIAL PRIMARY KEY,
    context_type TEXT NOT NULL CHECK (context_type IN ('UNIVERSAL', 'GLOBAL', 'DOMAIN', 'AGENT')),
    context_key TEXT NOT NULL,   -- '*' for UNIVERSAL/GLOBAL, domain name, or agent name
    file_key TEXT NOT NULL,      -- unique identifier for this record
    content TEXT NOT NULL CHECK (LENGTH(content) > 0 AND LENGTH(content) <= 500),
    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (context_type, file_key)
);
```

**Scope priority (UNIVERSAL → GLOBAL → DOMAIN → AGENT):**

| context_type | context_key | Who sees it |
|---|---|---|
| `UNIVERSAL` | `*` | All agents, always |
| `GLOBAL` | `*` | All agents, always |
| `DOMAIN` | domain name | Agents whose domains match via `agent_domains` |
| `AGENT` | agent name | That specific agent only |

**Size limits:**
- **Per record:** 500 characters max (enforced by CHECK constraint)
- **Per agent total:** 2000 characters max (enforced by `get_agent_turn_context()`)

If the budget is exceeded, a visible warning is appended: `⚠️ Turn context truncated — some critical rules may be missing. Alert I)ruid.`

**Related function:**
```sql
-- Get all context for an agent (used by the hook, cached for 5 min)
SELECT content, truncated, records_skipped, total_chars
FROM get_agent_turn_context('nova');
```

**Common queries:**
```sql
-- Add universal turn context (applies to all agents, every turn)
INSERT INTO agent_turn_context (context_type, context_key, file_key, content)
VALUES ('UNIVERSAL', '*', 'MY_RULE', 'Always confirm destructive operations before proceeding.');

-- List all enabled records
SELECT context_type, context_key, file_key, LEFT(content, 80) as preview
FROM agent_turn_context WHERE enabled = true ORDER BY context_type, file_key;

-- Disable a record without deleting it
UPDATE agent_turn_context SET enabled = false WHERE file_key = 'MY_RULE';
```

**Note:** This is separate from `agent_bootstrap_context`, which is injected once at session start. `agent_turn_context` fires on every `message:received` event.

**Migration:** `migrations/065_agent_turn_context.sql`  
**Hook:** `hooks/agent-turn-context/` — see `HOOK.md` for full details.

### Knowledge and Learning

#### lessons table
**Purpose:** Store learning from corrections and experience

```sql
CREATE TABLE lessons (
    id SERIAL PRIMARY KEY,
    lesson TEXT NOT NULL,
    context TEXT,
    source VARCHAR(100), -- conversation, observation, correction
    learned_at TIMESTAMP DEFAULT NOW(),
    original_behavior TEXT, -- What went wrong (for corrections)
    correction_source TEXT, -- Who corrected: druid, self, user
    reinforced_at TIMESTAMP, -- Last validation
    confidence FLOAT DEFAULT 1.0, -- Decays over time if unused
    last_referenced TIMESTAMP
);
```

**Confidence decay pattern:**
```sql
-- Run periodically to decay unused lessons
UPDATE lessons 
SET confidence = confidence * 0.95 
WHERE last_referenced < NOW() - INTERVAL '30 days' 
  AND confidence > 0.1;
```

### Library

#### library_works table
**Purpose:** Central storage for all written works — research papers, books, novels, poems, essays, articles, etc.

```sql
CREATE TABLE library_works (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    work_type TEXT NOT NULL,        -- paper, book, novel, poem, essay, article, etc.
    publication_date DATE NOT NULL,
    language TEXT NOT NULL DEFAULT 'en',
    summary TEXT NOT NULL,          -- Semantic summary for embedding (200-400 words)
    url TEXT,
    doi TEXT,
    arxiv_id TEXT,
    isbn TEXT,
    external_ids JSONB DEFAULT '{}',
    abstract TEXT,                  -- Original abstract verbatim
    content_text TEXT,              -- Full text (optional)
    insights TEXT NOT NULL,         -- Key takeaways and relevance notes
    subjects TEXT[] NOT NULL DEFAULT '{}',
    notable_quotes TEXT[],          -- 3-10 memorable passages; included in embedding
    publisher TEXT,
    source_path TEXT,
    shared_by TEXT NOT NULL,
    extra_metadata JSONB DEFAULT '{}',
    edition TEXT,                   -- Edition identifier (e.g., "5th Edition"); nullable
    embed BOOLEAN NOT NULL DEFAULT TRUE, -- Whether to include in semantic embedding
    search_vector tsvector,         -- Auto-generated via trigger
    added_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

**Key design patterns:**
- **NOT NULL constraints enforce completeness** — the database rejects records without summary, insights, publication_date, etc.
- **rich embedding per work** — one high-density embedding combining title, authors, summary, notable quotes, and tags; on recall hit the full record is fetched
- **edition field** — nullable; identifies specific editions (e.g., "5th Edition", "2nd Edition")
- **embed flag** — controls whether a work is included in semantic embedding; defaults to `true`
- **Unique index** on `(LOWER(title), COALESCE(edition, ''))` — prevents duplicate records (same title+edition)
- **Partial index** on `embed WHERE embed = true` — optimizes embedding pipeline queries
- **Check constraints** validate summary length (>50 chars), insights length (>20 chars), and work_type values
- **tsvector trigger** auto-generates weighted search vectors (title=A, summary/abstract=B, insights=C, content=D)

#### library_authors table
**Purpose:** Normalized, deduplicated author records

```sql
CREATE TABLE library_authors (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    biography TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);
```

#### Supporting tables
- **library_work_authors** — Junction linking works to authors with ordering
- **library_tags** / **library_work_tags** — Flexible topic/subject tagging
- **library_work_relationships** — Citations, sequels, responses between works

**Common queries:**
```sql
-- Full-text search
SELECT id, title, ts_rank(search_vector, q) AS rank
FROM library_works, plainto_tsquery('english', 'agent safety') q
WHERE search_vector @@ q ORDER BY rank DESC;

-- Find by subject
SELECT title, work_type FROM library_works WHERE subjects @> ARRAY['AI Safety'];

-- Find by author
SELECT w.title FROM library_works w
JOIN library_work_authors wa ON w.id = wa.work_id
JOIN library_authors a ON wa.author_id = a.id
WHERE a.name ILIKE '%shapira%';
```

See [Library Schema](library-schema.md) for full documentation.

### Memory and Search

#### memory_embeddings table
**Purpose:** Vector embeddings for semantic search

```sql
CREATE TABLE memory_embeddings (
    id SERIAL PRIMARY KEY,
    source_type VARCHAR(50), -- agent_chat, entity_fact, event, lesson, library, etc.
    source_id TEXT, -- ID in source table
    content TEXT NOT NULL, -- Text that was embedded
    embedding VECTOR(1536), -- OpenAI text-embedding-3-small dimension
    confidence REAL DEFAULT 1.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Vector similarity index (IVFFlat; only create after > 1000 rows — see INSTALLATION.md)
CREATE INDEX idx_memory_embeddings_vector ON memory_embeddings 
USING ivfflat (embedding vector_cosine_ops) WITH (lists='100');
```

**Semantic search example:**
```sql
-- Find similar content (requires embedding generation first)
SELECT source_type, source_id, content,
       1 - (embedding <=> $query_embedding) AS similarity
FROM memory_embeddings
ORDER BY embedding <=> $query_embedding
LIMIT 10;
```

## Access Control Architecture

Nova-memory implements innovative access control through two mechanisms:

### 1. Table Comments (Documentation-Driven Security)

Every table has a PostgreSQL comment explaining access rules:

```sql
-- View table access rules
SELECT c.relname as table_name, 
       obj_description(c.oid, 'pg_class') as access_rules
FROM pg_class c 
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' 
ORDER BY c.relname;
```

**Example comments:**
- `agents` → "READ-ONLY for most agents. Modifications via NHR (Newhart) only."
- `projects` → "For repo-backed projects (locked=TRUE), use GitHub for management."

### 2. Row-Level Locks

Tables with `locked` columns prevent modifications via triggers:

```sql
-- Trigger prevents updates to locked rows
CREATE OR REPLACE FUNCTION prevent_locked_project_update()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.locked = TRUE AND NEW.locked = TRUE THEN
    RAISE EXCEPTION 'Project % is locked. Set locked=FALSE first to modify.', OLD.name;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Workflow example:**
1. NOVA tries: `UPDATE agents SET nickname = 'Quill' WHERE name = 'quill'`
2. PostgreSQL: "permission denied for table agents"  
3. NOVA queries table comment, sees "Modifications via NHR only"
4. NOVA messages Newhart with the update request
5. Newhart (with appropriate permissions) makes the change

## Common Query Patterns

### Entity Information
```sql
-- Get complete entity profile
SELECT 
    e.name,
    e.full_name,
    e.description,
    json_agg(json_build_object('key', ef.key, 'value', ef.value)) as facts
FROM entities e
LEFT JOIN entity_facts ef ON e.id = ef.entity_id
WHERE e.name = 'druid'
GROUP BY e.id, e.name, e.full_name, e.description;
```

### Project Status
```sql
-- Active projects with task counts
SELECT 
    p.name,
    p.status,
    p.goal,
    CASE WHEN p.locked THEN p.repo_url ELSE 'Database managed' END as source,
    COUNT(t.id) as task_count
FROM projects p
LEFT JOIN tasks t ON p.id = t.project_id
WHERE p.status = 'active'
GROUP BY p.id, p.name, p.status, p.goal, p.locked, p.repo_url;
```

### Agent Capabilities
```sql
-- Find agents with specific skills
SELECT name, description, skills, access_method
FROM agents 
WHERE 'research' = ANY(skills) AND status = 'active';
```

### Recent Activity Timeline
```sql
-- Combined timeline of recent events and lessons
SELECT 'event' as type, event_date, title as description FROM events WHERE event_date > NOW() - INTERVAL '7 days'
UNION ALL
SELECT 'lesson', learned_at::date, lesson FROM lessons WHERE learned_at > NOW() - INTERVAL '7 days'
ORDER BY event_date DESC;
```

## Schema Maintenance

### Regular Maintenance Tasks

```sql
-- Update statistics for query optimization
ANALYZE;

-- Check for unused lessons (low confidence)
SELECT id, lesson, confidence, last_referenced
FROM lessons 
WHERE confidence < 0.3
ORDER BY confidence, last_referenced;

-- Find entities without facts
SELECT e.name, e.type
FROM entities e
LEFT JOIN entity_facts ef ON e.id = ef.entity_id
WHERE ef.id IS NULL;
```

### Index Maintenance

```sql
-- Essential indexes for performance
CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(name);
CREATE INDEX IF NOT EXISTS idx_entities_type ON entities(type);
CREATE INDEX IF NOT EXISTS idx_entity_facts_entity_id ON entity_facts(entity_id);
CREATE INDEX IF NOT EXISTS idx_entity_facts_key ON entity_facts(key);
CREATE INDEX IF NOT EXISTS idx_events_date ON events(event_date);
CREATE INDEX IF NOT EXISTS idx_agent_chat_recipients ON agent_chat USING gin(recipients);
```

### Data Integrity Checks

```sql
-- Orphaned entity facts
SELECT ef.id, ef.key, ef.value
FROM entity_facts ef
LEFT JOIN entities e ON ef.entity_id = e.id
WHERE e.id IS NULL;

-- Invalid relationships (self-referencing)
SELECT * FROM entity_relationships 
WHERE entity_a = entity_b;

-- Projects with invalid status
SELECT name, status FROM projects 
WHERE status NOT IN ('active', 'paused', 'completed', 'blocked');
```

## Schema Management

Nova-memory uses **declarative schema management** via [`pgschema`](https://github.com/pgplex/pgschema). The file `schema/schema.sql` is the single source of truth. When you run `agent-install.sh`, it:

1. Runs any scripts in `pre-migrations/` (data transformations before the diff)
2. Calls `pgschema plan` to diff `schema.sql` against the live DB
3. Blocks destructive drops automatically
4. Calls `pgschema apply` with the approved plan

### Adding or Changing Schema Objects

Edit `schema/schema.sql` to reflect the desired end state. You do **not** write `ALTER TABLE` statements — `pgschema` generates the necessary DDL automatically.

```sql
-- Example: to add a column, just add it to the CREATE TABLE in schema/schema.sql:
-- BEFORE
CREATE TABLE entities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

-- AFTER (add avatar_url)
CREATE TABLE entities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    avatar_url TEXT
);
```

Then re-run `./agent-install.sh` and `pgschema` will apply the `ALTER TABLE ... ADD COLUMN` for you.

### Data Migration Scripts (pre-migrations)

When a schema change requires a data transformation to happen first (e.g., rename a column with a backfill), place a `.sql` script in `pre-migrations/`:

```
pre-migrations/
└── 001_rename_old_col_to_new.sql
```

Pre-migration scripts run in filename order, **before** `pgschema plan` executes. This ensures the live DB is in the correct state for the declarative diff.

```sql
-- Example pre-migration: rename a column manually, then schema.sql reflects the new name
ALTER TABLE entities RENAME COLUMN old_name TO new_name;
UPDATE entities SET new_name = COALESCE(new_name, 'default') WHERE new_name IS NULL;
```

### Generating the Schema File

The schema file is generated using `pgschema dump`, not `pg_dump`:

```bash
pgschema dump \
  --host localhost --db nova_memory --user nova \
  --schema public > schema/schema.sql
```

The output contains pure DDL — no `OWNER TO`, no `GRANT/REVOKE`, no `\connect` or `SET ROLE` directives. This keeps the schema file clean and portable across different user setups.

### Ignoring Objects

Use `.pgschemaignore` (TOML format) to exclude objects from `pgschema` management:

```toml
# .pgschemaignore
[tables]
patterns = ["temp_*", "pgschema_tmp_*"]
```

## Performance Optimization

### Query Optimization

```sql
-- Use proper indexes
EXPLAIN ANALYZE SELECT * FROM entities WHERE name = 'druid';

-- Avoid N+1 queries with joins
SELECT e.name, array_agg(ef.value) as preferences
FROM entities e
JOIN entity_facts ef ON e.id = ef.entity_id
WHERE ef.key = 'preference'
GROUP BY e.id, e.name;
```

### Connection Pooling

For high-load applications, consider PgBouncer:
```ini
# pgbouncer.ini
[databases]
nova_memory = host=localhost dbname=nova_memory

[pgbouncer]
pool_mode = transaction
max_client_conn = 100
default_pool_size = 25
```

**Note for Documentation Team:** The multi-tier memory hierarchy and access control architecture would benefit from **Quill haiku collaboration** to create intuitive metaphors for complex concepts like table-comment-driven security and row-level locking patterns.

## Next Steps

1. **Add vector search:** Implement embedding generation for semantic queries
2. **Set up monitoring:** Track query performance and connection usage  
3. **Implement archiving:** Move old events/lessons to archive tables
4. **Add validation:** Create check constraints for data quality
5. **Security hardening:** Implement proper user roles and permissions

The database schema is designed to grow with your AI assistant's knowledge while maintaining performance and data integrity. Understanding these patterns will help you extend the system effectively.