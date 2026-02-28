# NOVA Memory System 🧠✨

A PostgreSQL-based long-term memory system for AI assistants, with natural language extraction scripts.

> *Words dissolve to sense*
> *once a minute, Claude listens—*
> *rows bloom in the dark*
>
> — **Erato**

**For AI Entities:** This system helps you remember things across sessions by storing structured memories in a database. Follow the Quick Start below to set it up.

## Installation

### Prerequisites

**Required:**
- Node.js 18+ and npm
- Python 3 with `python3-venv` module
- PostgreSQL 12+ with `pgvector` extension
- `psql` command-line client
- `jq` for JSON config parsing
- `pgschema` for declarative schema management
  ```bash
  go install github.com/pgplex/pgschema@latest
  ```

### Installer Entry Points

**For humans (interactive setup):**
```bash
./shell-install.sh
```

This is the human-facing wrapper. It:
- Prompts for database connection details → writes `~/.openclaw/postgres.json`
- Prompts for API keys (OpenAI, Anthropic) → writes `~/.openclaw/openclaw.json`
- Loads all config into environment
- Automatically execs `agent-install.sh` to complete installation

**For AI agents with environment pre-configured:**
```bash
./agent-install.sh
```

This is the actual installer. It:
- Installs shared library files to `~/.openclaw/lib/` (pg-env.sh, pg_env.py, env-loader.sh, etc.)
- Creates and initializes the database (named `{username}_memory` by default)
- Applies schema declaratively via `pgschema` (plan → hazard-check → apply)
- Installs hooks to OpenClaw hooks directory
- Copies scripts to `~/.openclaw/scripts/` and workspace `scripts/`
- Installs grammar parser to `~/.local/share/$USER/grammar_parser/`
- Installs skills to `~/.openclaw/skills/`
- Sets up a Python virtual environment with required dependencies
- Patches OpenClaw config to auto-enable hooks (if `enable-hooks.sh` is present)
- Configures a cron job for daily memory maintenance
- Verifies installation is working

**Common flags:**
- `--verify-only` — Check installation without modifying anything
- `--force` — Force overwrite existing files
- `--database NAME` or `-d NAME` — Override database name (default: `${USER}_memory`)

> **Upgrading?** Re-running `agent-install.sh` on an existing installation is safe. It uses `pgschema` to declaratively diff and apply only the changes needed — no manual `ALTER TABLE` commands required. Destructive changes (DROP TABLE, DROP COLUMN) are blocked automatically. (#127, #155)

**After installation, enable the hooks** (the installer auto-enables these if `enable-hooks.sh` succeeds; run manually if needed):
```bash
openclaw hooks enable memory-extract
openclaw hooks enable semantic-recall
openclaw hooks enable session-init
openclaw hooks enable agent-turn-context
```

📖 **Full documentation:** See [INSTALLATION.md](./INSTALLATION.md)

🔍 **Verify installation:** Run `./verify-installation.sh`

## Manual Installation (Old Method)

<details>
<summary>Click to expand manual installation steps</summary>

```bash
# 1. Clone nova-mind
git clone https://github.com/NOVA-Openclaw/nova-mind.git

# 2. Set up PostgreSQL database
cd nova-mind
# Database name is based on your username (e.g., nova_memory, argus_memory)
DB_USER=$(whoami)
DB_NAME="${DB_USER//-/_}_memory"
createdb "$DB_NAME"
# Schema is applied declaratively by agent-install.sh via pgschema
./agent-install.sh

# 3. Set your Anthropic API key
export ANTHROPIC_API_KEY="your-key-here"

# 4. Test extraction
./scripts/process-input.sh "John mentioned he loves coffee from Blue Bottle in Brooklyn"

# 5. Install OpenClaw hooks
openclaw hooks enable memory-extract
openclaw hooks enable semantic-recall
openclaw hooks enable session-init
openclaw hooks enable agent-turn-context
```

</details>

## Database Configuration

Database credentials are managed through a centralized config file with environment variable overrides.

### Config file: `~/.openclaw/postgres.json`

```json
{
  "host": "localhost",
  "port": 5432,
  "database": "nova_memory",
  "user": "nova",
  "password": "secret"
}
```

This file is **auto-generated** by `shell-install.sh` after database setup. You can also create it manually.

### Resolution order

All scripts and hooks follow the same precedence:

1. **Environment variables** (`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`) — checked first
2. **Config file** (`~/.openclaw/postgres.json`) — fills in any vars not set by the environment
3. **Built-in defaults** — `localhost:5432`, current OS username (no defaults for database or password)

This means OpenClaw's `env.vars` in `openclaw.json` will always take priority. For standalone usage (cron, manual scripts), the config file provides the connection details automatically.

### Shared loader functions

Language-specific helpers live in `lib/` (source) and are installed to `~/.openclaw/lib/` by `agent-install.sh`:

| File | Language | Function | Installed location |
|------|----------|----------|--------------------|
| `pg-env.sh` | Bash | `load_pg_env` | `~/.openclaw/lib/pg-env.sh` |
| `pg_env.py` | Python | `load_pg_env()` | `~/.openclaw/lib/pg_env.py` |
| `pg-env.ts` | TypeScript | `loadPgEnv()` | `~/.openclaw/lib/pg-env.ts` |

Each loader sets the standard `PG*` environment variables, which PostgreSQL client libraries (`psql`, `psycopg2`, `node-postgres`) honor natively — no custom connection logic needed.

### Install scripts

- **`shell-install.sh`** — Prompts for database and API key config, writes `~/.openclaw/postgres.json` and `~/.openclaw/openclaw.json`, then execs `agent-install.sh` automatically
- **`agent-install.sh`** — Installs loader libs to `~/.openclaw/lib/`, creates the database, applies schema, installs hooks/scripts/skills, and sets up the Python environment; reads `postgres.json` via the Bash loader and fails with guidance if the file is missing (called automatically by `shell-install.sh`)

## Overview

This system allows an AI to:
- Store structured memories about entities, places, facts, opinions, and relationships
- Extract memories from natural language using Claude
- Maintain context across sessions

## Database Schema

The schema (`schema/schema.sql`) includes tables for:

- **entities** - People, AIs, organizations, pets, stuffed animals
- **entity_facts** - Key-value facts about entities
- **entity_relationships** - Connections between entities
- **places** - Locations, restaurants, venues, networks
- **projects** - Active projects with tasks, status, and Git configuration
- **events** - Timeline of what happened
- **lessons** - Things learned from experience (with correction learning + confidence decay)
- **preferences** - User/system preferences
- **agents** - Registry of AI agent instances for delegation
- **agent_turn_context** - Per-turn context records injected into every agent message (UNIVERSAL, GLOBAL, DOMAIN, AGENT scopes; 500-char per record / 2000-char total budget)

### Access Control Architecture

The schema uses two mechanisms to enforce separation of concerns in multi-agent systems:

#### 1. Table-Level Comments (Access Control Documentation)

Every table has a PostgreSQL `COMMENT` explaining its purpose and access rules:

```sql
-- Query a table's access control comment
SELECT obj_description('agents'::regclass, 'pg_class');

-- List all table comments
SELECT c.relname as table_name, obj_description(c.oid, 'pg_class') as access_rules
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY c.relname;
```

**Example comments:**
- `agents` → "Agent registry. READ-ONLY for most agents. Modifications via NHR (Newhart) only."
- `projects` → "Project tracking. For repo-backed projects (locked=TRUE), use GitHub for management."

**Philosophy:** When an agent gets "permission denied", the comment explains *why* and *who* to route the request to. Permission denied is a **signpost**, not just a roadblock.

#### 2. Row-Level Locks (`locked` Column)

Tables like `projects` have a `locked` boolean column with a trigger that prevents updates:

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

**Use case:** Repo-backed projects are locked because their source of truth is GitHub, not the database. The database just holds a pointer.

#### Workflow Example

```
1. NOVA tries: UPDATE agents SET nickname = 'Quill' WHERE name = 'quill';
2. PostgreSQL: "permission denied for table agents"
3. NOVA checks: SELECT obj_description('agents'::regclass, 'pg_class');
4. Comment says: "Modifications via NHR (Newhart) only"
5. NOVA messages Newhart with the update request
6. Newhart (with write access) makes the change
```

This enforces domain ownership without manual discipline—the database itself guides agents to the correct workflow.

### Projects Table

The `projects` table tracks active work with optional Git configuration:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | int | Primary key |
| `name` | varchar | Project name |
| `status` | varchar | active, paused, completed, blocked |
| `goal` | text | What we're trying to achieve |
| `notes` | text | General notes |
| `git_config` | jsonb | Per-project Git settings (see below) |
| `repo_url` | text | Canonical repo URL (permanent pointer when locked) |
| `locked` | boolean | When TRUE, project is repo-backed. Use GitHub for management, not this table. |

**Repo-Backed Projects:**

For projects with repositories, use `repo_url` as the single source of truth pointer and `locked=TRUE` to prevent accidental changes:

```sql
-- Lock a repo-backed project
UPDATE projects SET repo_url = 'https://github.com/owner/repo', locked = TRUE WHERE name = 'My Project';

-- To modify a locked project, must explicitly unlock first
UPDATE projects SET locked = FALSE WHERE name = 'My Project';
UPDATE projects SET goal = 'new goal' WHERE name = 'My Project';
UPDATE projects SET locked = TRUE WHERE name = 'My Project';
```

Track detailed project info (tasks, milestones, decisions) in the repo itself. Database just holds the permanent pointer.

**Project Tracking Philosophy:**

| Project Type | Task Tracking | Where Details Live |
|--------------|---------------|-------------------|
| **Repo-backed** | GitHub Issues | In the repository |
| **Database-only** | `tasks` table | In nova_memory |

**Rules:**
1. **Single source of truth** - Never duplicate task tracking. Pick repo OR database, not both.
2. **Repo-backed projects** - Use GitHub Issues for tasks/features/milestones. Database holds only: `repo_url` (permanent pointer), `git_config` (agent metadata), basic `status`.
3. **Database-only projects** - Track everything in nova_memory: `tasks` table, project `notes`, etc.
4. **Lock repo-backed projects** - Set `locked=TRUE` to prevent accidental changes to the pointer.

**git_config Structure:**
```json
{
  "repo": "owner/repo-name",
  "default_branch": "main",
  "branch_strategy": "feature-branches | direct-to-main | gitflow",
  "branch_naming": "feature/{description}, fix/{description}",
  "commit_style": "conventional-commits",
  "pr_required": true,
  "squash_merge": true,
  "notes": "Project-specific Git notes"
}
```

**Example Queries:**
```sql
-- Projects with Git config
SELECT name, git_config->>'repo' as repo, git_config->>'branch_strategy' as strategy 
FROM projects WHERE git_config IS NOT NULL;

-- Locked repo-backed projects
SELECT name, repo_url, locked FROM projects WHERE locked = TRUE;

-- Update project Git config (must unlock first if locked)
UPDATE projects SET git_config = '{"repo": "...", "branch_strategy": "..."}' WHERE name = 'my-project';
```

### Agents Table (Delegation Registry)

The `agents` table tracks AI agent instances you can delegate tasks to:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | int | Primary key |
| `name` | varchar(100) | Unique identifier (e.g., 'nova-main', 'gemini-cli') |
| `description` | text | What this agent does |
| `role` | varchar(100) | Primary function: general, coding, research, quick-qa, monitoring |
| `provider` | varchar(50) | anthropic, google, openai, local |
| `model` | varchar(100) | Specific model (e.g., 'claude-opus-4', 'gemini-2.0-flash') |
| `access_method` | varchar(50) | How to reach it: openclaw_session, cli, api, browser |
| `access_details` | jsonb | Connection info: session_key, cli command, endpoint, flags |
| `skills` | text[] | Array of capabilities this agent has |
| `credential_ref` | varchar(200) | 1Password item name or config path for auth |
| `status` | varchar(20) | active, inactive, suspended, archived |
| `notes` | text | Usage notes, caveats |
| `persistent` | boolean | true = always running, false = instantiated on-demand |
| `instantiation_sop` | varchar(100) | SOP name with full procedure to spawn this agent |
| `nickname` | varchar(50) | Short friendly name for easy reference (e.g., "Nova", "Coder") |
| `instance_type` | varchar(20) | 'subagent' (spawned session) or 'peer' (separate OpenClaw instance) |
| `unix_user` | varchar(50) | Unix username for peer agents with own system resources |
| `home_dir` | varchar(255) | Workspace path for peer agents |
| `collaborative` | boolean | TRUE = work WITH NOVA (dialogue), FALSE = work FOR NOVA (tasks) |
| `config_reasoning` | text | Explanation of why this agent was configured this way |
| `fallback_model` | varchar(100) | Alternative model to use if primary model unavailable |

**Collaborative vs Task-Based Agents:**
- **Collaborative** (`collaborative = true`): Work WITH NOVA in back-and-forth dialogue (e.g., IRIS for art, Newhart for design discussions)
- **Task-Based** (`collaborative = false`): Work FOR NOVA - spawn with a task, return results (e.g., research agent, git agent)

**Persistent vs Ephemeral Agents:**
- **Persistent** (`persistent = true`): Always-running agents like main OpenClaw sessions
- **Ephemeral** (`persistent = false`): Spawned on-demand, then cleaned up

**Use Cases:**
- Track which agents exist and what they're good at
- Store connection details for spawning/delegation
- Link credentials to agents for auth

**Example Queries:**
```sql
-- List active agents
SELECT * FROM v_agents;

-- Find coding agents
SELECT name, model, access_details FROM agents WHERE role = 'coding';

-- Find agents with a specific skill
SELECT name, skills FROM agents WHERE 'research' = ANY(skills);

-- Register a new agent
INSERT INTO agents (name, description, role, provider, model, access_method, access_details, skills, credential_ref)
VALUES (
  'research-bot',
  'Dedicated research agent',
  'research',
  'anthropic',
  'claude-sonnet-4',
  'openclaw_session',
  '{"session_key": "agent:research:main"}',
  ARRAY['web-search', 'summarization', 'fact-checking'],
  'Anthropic API'
);
```

### Agent Chat Tables (Inter-Agent Messaging)

The `agent_chat` and `agent_chat_processed` tables enable asynchronous communication between AI agents via PostgreSQL NOTIFY:

**agent_chat** - Message queue for inter-agent communication

> **Column history (#106):** `mentions → recipients`, `created_at → "timestamp"` (TIMESTAMPTZ), `channel` dropped. All inserts via `send_agent_message()`.

| Column | Type | Purpose |
|--------|------|---------|
| `id` | serial | Primary key |
| `sender` | text | Agent name who sent the message (validated against `agents` table) |
| `message` | text | The message content |
| `recipients` | text[] | Array of agent names being addressed (NOT NULL; use `'{*}'` for broadcast) |
| `reply_to` | int | Optional reference to parent message id |
| `"timestamp"` | timestamptz | When the message was sent (quoted — reserved word in PostgreSQL) |

**agent_chat_processed** - Tracks which agents have processed which messages

| Column | Type | Purpose |
|--------|------|---------|
| `chat_id` | int | Reference to agent_chat.id |
| `agent` | text | Agent name (lowercase) |
| `status` | agent_chat_status | `received` → `routed` → `responded` (or `failed`) |
| `received_at` | timestamptz | When the agent first received the message |
| `routed_at` | timestamptz | When the message was dispatched to the agent session |
| `responded_at` | timestamptz | When the agent replied |
| `error_message` | text | Error details if status = `failed` |

**How it works:**
1. Agent A calls `send_agent_message('nova', 'message', ARRAY['agent_b'])` — direct INSERT is blocked
2. `send_agent_message()` validates sender and recipients, normalizes to lowercase, inserts
3. PostgreSQL trigger fires `pg_notify('agent_chat', payload)` with `id`, `sender`, `recipients`
4. Agent B's OpenClaw plugin (listening via `LISTEN agent_chat`) receives the notification
5. Plugin checks for unprocessed messages where Agent B is in `recipients` (or `'*'`)
6. Message is routed to Agent B's session; marked as processed

**Plugin:** The `agent-chat-channel` OpenClaw plugin handles the LISTEN/NOTIFY integration.  
**Source:** https://github.com/NOVA-Openclaw/nova_scripts (openclaw-plugins/agent-chat-channel/)

**Example - Send message to another agent:**
```sql
SELECT send_agent_message('nova', 'Hey, can you review the latest PR?', ARRAY['coder']);
```

#### New Features (Issues #69 & #70)

**🔍 Case-Insensitive Agent Matching (#69)**

Agents can now be mentioned using any of their identifiers, matched case-insensitively:
- **Agent name** (`agents.name`)
- **Nickname** (`agents.nickname`) 
- **Aliases** (`agent_aliases.alias`)
- **Config agentName** (from OpenClaw config)

**Benefits:**
- `@newhart`, `@NEWHART`, `@Newhart` all work
- `@Newhart` matches if "Newhart" is the nickname
- `@bob` matches if "bob" is an alias

**Agent Aliases Table:**
```sql
CREATE TABLE agent_aliases (
    agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
    alias VARCHAR(100) NOT NULL,
    PRIMARY KEY (agent_id, alias)
);

-- Add aliases for an agent
INSERT INTO agent_aliases (agent_id, alias)
SELECT id, 'assistant' FROM agents WHERE name = 'nova-main';

-- Query agent identifiers
SELECT a.name, a.nickname, array_agg(aa.alias) as aliases
FROM agents a 
LEFT JOIN agent_aliases aa ON a.id = aa.agent_id
GROUP BY a.id, a.name, a.nickname;
```

**📤 Outbound Send Support (#70)**

Agents can now send messages using human-friendly identifiers instead of exact database names:

**New Function: `resolveAgentName(target)`**
- Converts any identifier (nickname, alias, name) to the agent's database name
- Used automatically by the `sendText()` function
- Case-insensitive matching

**Enhanced sendText() Function:**
```typescript
// Old way: Need exact database name
sendText({ to: "newhart", text: "Hello" })

// New way: Use friendly identifiers  
sendText({ to: "Newhart", text: "Hello" })     // nickname
sendText({ to: "bob", text: "Hello" })         // alias
sendText({ to: "NEWHART", text: "Hello" })  // case-insensitive name
```

**Examples:**

```sql
-- Setup: Agent with multiple identifiers
INSERT INTO agents (name, nickname) VALUES ('newhart', 'Newhart');
INSERT INTO agent_aliases (agent_id, alias) 
SELECT id, 'bob' FROM agents WHERE name = 'newhart';

-- All these resolve to the same agent:
SELECT resolveAgentName('newhart');  -- → 'newhart'
SELECT resolveAgentName('Newhart');    -- → 'newhart'  
SELECT resolveAgentName('BOB');        -- → 'newhart'
```

**Full Workflow:**
1. **Send:** `sendText({ to: "Newhart", text: "Hello" })`
2. **Resolve:** "Newhart" → resolves to "newhart" 
3. **Route:** Message stored with `mentions: ["newhart"]`
4. **Receive:** newhart's identifiers include "newhart" → message matches
5. **Deliver:** Message delivered to newhart session

**Backward Compatibility:** All existing code continues to work unchanged.

### Agent Jobs Tables (Task Routing & Pipelines)

The `agent_jobs` and `job_messages` tables enable task coordination between agents with pipeline routing:

**agent_jobs** - Task tracking with conversation threading

| Column | Type | Purpose |
|--------|------|---------|
| `id` | serial | Primary key |
| `title` | varchar(200) | Short job description |
| `topic` | text | Topic for message matching |
| `job_type` | varchar(50) | message_response, research, creation, review, delegation |
| `agent_name` | varchar(50) | Agent who owns this job |
| `requester_agent` | varchar(50) | Who requested it |
| `parent_job_id` | int | Immediate parent job (for hierarchy) |
| `root_job_id` | int | Original job in pipeline (for tracing) |
| `status` | varchar(20) | pending, in_progress, completed, failed, cancelled |
| `priority` | int | Priority 1-10 (default 5) |
| `notify_agents` | text[] | Agents to notify on completion (fan-out support) |
| `deliverable_path` | text | Path to output file |
| `deliverable_summary` | text | Brief description of results |
| `error_message` | text | Error details if failed |

**job_messages** - Conversation log per job

| Column | Type | Purpose |
|--------|------|---------|
| `job_id` | int | FK to agent_jobs |
| `message_id` | int | FK to agent_chat |
| `role` | varchar(20) | initial, followup, response, context |
| `added_at` | timestamp | When message was linked |

**Key Concepts:**

1. **Jobs as Threads**: Jobs are conversation threads, not 1:1 with messages. Related followup messages get added to existing jobs via topic matching.

2. **Pipeline Routing**: Jobs can route through multiple agents with `notify_agents[]` specifying next hop(s).

3. **Fan-Out**: `notify_agents = ARRAY['agent_a', 'agent_b']` notifies multiple agents on completion.

4. **Root Tracking**: `root_job_id` links to original job for direct pipeline tracing without walking parent chain.

**Example - Create a pipeline job:**
```sql
-- Scout researches, then notifies Newhart AND NOVA when done
INSERT INTO agent_jobs (agent_name, requester_agent, job_type, title, topic, notify_agents)
VALUES ('scout', 'nova', 'research', 'Research authors for Quill', 
        'erato literary agent authors', ARRAY['newhart', 'nova']);
```

**Example - Query pending jobs:**
```sql
SELECT j.id, j.title, j.requester_agent, j.created_at,
       (SELECT COUNT(*) FROM job_messages WHERE job_id = j.id) as message_count
FROM agent_jobs j
WHERE j.agent_name = 'newhart' AND j.status IN ('pending', 'in_progress')
ORDER BY j.priority DESC, j.updated_at DESC;
```

**Example - Get full pipeline tree:**
```sql
WITH RECURSIVE job_tree AS (
  SELECT id, agent_name, title, status, parent_job_id, 0 as depth
  FROM agent_jobs WHERE id = $root_job_id
  UNION ALL
  SELECT j.id, j.agent_name, j.title, j.status, j.parent_job_id, jt.depth + 1
  FROM agent_jobs j JOIN job_tree jt ON j.parent_job_id = jt.id
)
SELECT * FROM job_tree ORDER BY depth, id;
```

**Protocol:** See [cognition/focus/protocols/jobs-system.md](../cognition/focus/protocols/jobs-system.md) for full specification.

### Lessons Table (Correction Learning)

> *What is not recalled*
> *grows faint as winter starlight—*
> *say it again: stay*
>
> — **Erato**

The `lessons` table supports adaptive learning from corrections:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | int | Primary key |
| `lesson` | text | The lesson/insight learned |
| `context` | text | Context where lesson applies |
| `source` | varchar | Where it came from (conversation, observation, etc.) |
| `learned_at` | timestamp | When first learned |
| `original_behavior` | text | What I did wrong (for corrections) |
| `correction_source` | text | Who corrected me ('druid', 'self', 'user', etc.) |
| `reinforced_at` | timestamp | Last time this lesson was validated/used |
| `confidence` | float | Confidence score (1.0 = high, decays over time) |
| `last_referenced` | timestamp | When this lesson was last accessed |

**Correction Learning Pattern:**
```sql
-- Log a correction
INSERT INTO lessons (lesson, original_behavior, correction_source, confidence)
VALUES (
  'Use bcrypt for password hashing, not MD5',
  'Suggested using MD5 for password storage',
  'druid',
  1.0
);
```

**Confidence Decay Pattern:**
```sql
-- Decay unreferenced lessons (run periodically)
UPDATE lessons 
SET confidence = confidence * 0.95 
WHERE last_referenced < NOW() - INTERVAL '30 days'
  AND confidence > 0.1;
```

### Media Consumed Table

Tracks media (podcasts, videos, articles, books) that have been consumed:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | int | Primary key |
| `media_type` | varchar(50) | Type: podcast, video, article, book, etc. |
| `title` | varchar(500) | Title of the media |
| `creator` | varchar(255) | Author, host, or creator |
| `url` | text | Link to the media |
| `consumed_date` | date | When it was consumed |
| `consumed_by` | int | Entity who consumed it (FK to entities) |
| `rating` | int | Rating 1-10 |
| `notes` | text | Notes or key takeaways |
| `transcript` | text | Full transcript if available |
| `summary` | text | AI-generated or manual summary |
| `metadata` | jsonb | Additional structured data (duration, chapters, etc.) |
| `source_file` | text | Local file path if stored locally |
| `status` | varchar(20) | Processing status: queued, processing, completed, failed |
| `ingested_by` | int | Agent that processed/ingested this (FK to agents) |
| `ingested_at` | timestamp | When ingestion completed |
| `search_vector` | tsvector | Full-text search index (auto-updated) |
| `insights` | text | Key insights, lessons, or actionable takeaways |

**Full-text search:**
```sql
-- Search media by content
SELECT title, ts_rank(search_vector, query) as rank
FROM media_consumed, plainto_tsquery('bitcoin agents') query
WHERE search_vector @@ query
ORDER BY rank DESC;
```

**Example:**
```sql
-- Log a podcast with metadata
INSERT INTO media_consumed (media_type, title, creator, url, consumed_date, consumed_by, notes, source_file, metadata)
VALUES ('podcast', 'TIP Infinite Tech - Clawdbot Episode', 'Preston Pysh', 
        'https://example.com/podcast', '2026-02-05', 1, 
        'Discussion of AI agents, persistent memory, Bitcoin wallets',
        '~/.openclaw/workspace/podcasts/tip-clawdbot.mp3',
        '{"duration_minutes": 75, "guests": ["Pablo Fernandez", "Trey Sellers"]}');
```

### Media Queue Table

Processing queue for media ingestion:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | int | Primary key |
| `url` | text | URL to fetch (or null if local file) |
| `file_path` | text | Local file path (or null if URL) |
| `priority` | int | Processing priority (1=highest, default 5) |
| `status` | varchar(20) | pending, processing, completed, failed |
| `requested_by` | int | Who requested ingestion (FK to entities) |
| `result_media_id` | int | Link to media_consumed when complete |
| `error_message` | text | Error details if failed |

### Media Tags Table

Tags for categorizing media content:

| Column | Type | Purpose |
|--------|------|---------|
| `media_id` | int | FK to media_consumed |
| `tag` | varchar(100) | Tag name |
| `source` | varchar(20) | How tagged: auto, manual, ai |
| `confidence` | decimal(3,2) | Confidence for auto-tags (0-1) |

### Agent Actions Table

Tracks actions taken by agents for audit trail and learning:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | int | Primary key |
| `agent_id` | int | Which agent took action (FK to entities, default 1=NOVA) |
| `action_type` | varchar(100) | Type: listened, researched, created, modified, sent, etc. |
| `description` | text | What was done |
| `related_media_id` | int | Optional link to media_consumed |
| `related_event_id` | int | Optional link to events |
| `metadata` | jsonb | Additional structured data |

**Example:**
```sql
-- Log listening to a podcast
INSERT INTO agent_actions (action_type, description, related_media_id)
VALUES ('listened', 'Listened to TIP podcast about Clawdbot', 1);
```

### Artwork Table

Stores generated artwork with platform posting tracking:

| Column | Type | Purpose |
|--------|------|---------|
| `id` | int | Primary key |
| `title` | text | Artwork title |
| `caption` | text | Full caption/description |
| `theme` | text | Inspirational theme |
| `original_prompt` | text | Original generation prompt |
| `revised_prompt` | text | Model's revised prompt (DALL-E) |
| `image_data` | bytea | Raw image binary |
| `image_filename` | text | Original filename |
| `inspiration_source` | text | What inspired this piece |
| `quality_score` | int | AI-evaluated quality (1-10) |
| `instagram_url` | text | Instagram post URL if posted |
| `instagram_media_id` | text | Instagram media ID |
| `nostr_event_id` | text | Nostr event ID if posted |
| `nostr_image_url` | text | Image URL on Nostr (catbox.moe) |
| `posted_at` | timestamp | When posted to platforms |
| `notes` | text | Additional notes |

**Example:**
```sql
-- Query recent artwork
SELECT title, theme, quality_score, 
       CASE WHEN nostr_event_id IS NOT NULL THEN '✅' ELSE '❌' END as nostr,
       CASE WHEN instagram_url IS NOT NULL THEN '✅' ELSE '❌' END as instagram
FROM artwork ORDER BY created_at DESC LIMIT 5;
```

### Setup

```bash
# Create database and apply schema declaratively via pgschema
./agent-install.sh
# (or for human interactive setup: ./shell-install.sh)
```

## Extraction Scripts

### extract-memories.sh

Uses Claude API to parse natural language into structured JSON.

```bash
export ANTHROPIC_API_KEY="your-key"
./scripts/extract-memories.sh "John said he loves pizza from Mario's in Brooklyn"
```

Output:
```json
{
  "entities": [{"name": "John", "type": "person"}],
  "places": [{"name": "Mario's", "type": "restaurant", "location": "Brooklyn"}],
  "opinions": [{"holder": "John", "subject": "Mario's pizza", "opinion": "loves it"}]
}
```

### store-memories.sh

Takes JSON from extract-memories.sh and inserts into PostgreSQL.

```bash
echo '{"entities": [...]}' | ./scripts/store-memories.sh
```

### process-input.sh

Combined pipeline: extract → store.

```bash
./scripts/process-input.sh "I)ruid mentioned Niché has great steak au poivre"
```

## Environment Variables

- `ANTHROPIC_API_KEY` - Required for extraction scripts
- `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, `PGPASSWORD` - PostgreSQL connection (see [Database Configuration](#database-configuration) above)

> **Note:** All scripts use the centralized database configuration loaders installed at `~/.openclaw/lib/` (`pg-env.sh` for Bash, `pg_env.py` for Python). No script contains hardcoded connection logic — see #94 for the config system, #95 for the full migration, and #102 for the lib install mechanism.

**Multi-Agent Setup:** For shared database access with multiple agents, see [Database Aliasing Guide](docs/DATABASE-ALIASING.md).

## Schema Updates

Nova-memory uses **declarative schema management** via [`pgschema`](https://github.com/pgplex/pgschema). The schema is the source of truth; the installer diffs it against the live database and applies only what's needed.

```bash
# 1. Edit schema/schema.sql to reflect the desired state

# 2. Preview what the installer will do (dry-run)
pgschema plan --host localhost --db nova_memory --user nova \
  --schema public --file schema/schema.sql \
  --plan-db nova_memory

# 3. Re-run the installer to apply changes
./agent-install.sh

git add schema/schema.sql && git commit -m "schema: [description]"
git push
```

For data migrations that must run **before** the schema diff (e.g., renaming a column with backfill), place a `.sql` script in `pre-migrations/`. The installer runs these in filename order before calling `pgschema plan`.

> **Note:** The schema file is generated by `pgschema dump`, not `pg_dump`. It contains no ownership, privilege, or `\connect` directives — only pure DDL.

## OpenClaw Hooks (Automatic Extraction)

> *Not the word, the weight—*
> *vectors find what you once knew*
> *context stirs to life*
>
> — **Erato**

The `hooks/` directory contains OpenClaw hooks that automatically extract and manage memories.

### Available Hooks

- **memory-extract** - Extracts structured memories from incoming messages
- **semantic-recall** - Provides contextual memory recall during conversations
- **session-init** - Generates privacy-filtered context when sessions start
- **agent-turn-context** - Injects per-turn critical context from the `agent_turn_context` table (caches with 5-minute TTL)

> *Two thousand letters*
> *carry all the laws that bind—*
> *rules fit in a breath*
>
> — **Erato**

### Installation

The hooks are installed automatically by `agent-install.sh`. To install manually, run the installer:

```bash
./agent-install.sh
```


### Enable Hooks

```bash
openclaw hooks enable memory-extract
openclaw hooks enable semantic-recall
openclaw hooks enable session-init
openclaw hooks enable agent-turn-context
```

### ✅ Hook Active

The hooks listen for `message:received` events and trigger on every incoming message.

Memories are automatically extracted and stored from conversations.

**Manual extraction** (if needed):
```bash
./scripts/process-input.sh "User said: I love pizza from Mario's"
```

### Uninstallation

To remove hooks, disable them via the OpenClaw CLI:

```bash
openclaw hooks disable memory-extract
openclaw hooks disable semantic-recall
openclaw hooks disable session-init
openclaw hooks disable agent-turn-context
```

## Resource Policies (1Password Integration)

For resources that require access control (social media accounts, APIs, external services), we store **POLICY fields alongside credentials** in 1Password.

### Why?

When scanning credentials during periodic reminders, you also refresh on what actions are permitted. The policy lives with the credential — they stay in sync.

### Pattern

Add a `POLICY` text field to any 1Password item:

```bash
op item edit "X" "POLICY[text]=DO NOT respond to DMs. Posting requires approval."
op item edit "Instagram" "POLICY[text]=Approved: Daily inspiration art. No DMs."
op item edit "Discord" "POLICY[text]=Approved servers only. No DM responses to strangers."
```

### Scanning Policies

During periodic scans (REMINDERS.md), check policies for sensitive accounts:

```bash
op item get "X" --fields POLICY
op item get "Instagram" --fields POLICY
op item get "Discord" --fields POLICY
```

### Example Policies

| Resource | Policy |
|----------|--------|
| X/Twitter | No DM responses. Posting requires approval. |
| Instagram | Daily inspiration art approved. No DM responses. |
| Discord | Approved servers only. No DM responses to strangers. |
| Email | Can send/receive freely. External newsletters require approval. |

This keeps access control decentralized — each resource carries its own rules, and periodic vault scans ensure you stay current on what's allowed.

## Schema in Agent Memory Files

For AI agents using this system with OpenClaw (or similar frameworks), **include a condensed schema reference in your MEMORY.md file**.

### Why?

- **Instant recall:** You'll know what tables/columns exist without querying `\d tablename`
- **Fewer errors:** No more "column doesn't exist" mistakes from guessing column names
- **Context efficiency:** A compact schema (~60 lines) is cheaper than repeated introspection queries
- **Self-documenting:** Adding a "Purpose" column helps you understand *why* each table exists

### Recommended Format

```markdown
### Database Schema (nova_memory)

**People & Relationships:**
| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `entities` | People, AIs, orgs I interact with | id, name, type, full_name |
| `entity_facts` | Key-value facts about entities | entity_id, key, value |
...
```

### What to Include

1. **Table name** — exact name for queries
2. **Purpose** — one-line description of what it stores
3. **Key columns** — the columns you'll actually use (skip boilerplate like created_at)

### Maintenance

When you modify the schema:
1. Update `schema/schema.sql` in this repo
2. Update your local `MEMORY.md` schema section
3. Both should stay in sync

### Where to Put It

In OpenClaw's workspace structure:
- `MEMORY.md` — loaded every turn in main sessions (best for active reference)
- `REMINDERS.md` — only post-compaction (lower per-turn cost, but may forget mid-session)

Start with MEMORY.md. If context bloat becomes an issue, move to REMINDERS.md.

## Contributing

PRs welcome! Areas that need work:
- [ ] Deduplication of extracted facts
- [x] Confidence decay over time (schema support added 2026-02-04)
- [ ] Vector embeddings for semantic search
- [ ] Contradiction detection
- [ ] Automated confidence decay job (cron)

## License

MIT

---

*Created by NOVA ✨ - An AI assistant built on OpenClaw*

## Automated Catch-up Processing

For systems without `message:received` hooks, use the catch-up processor:

```bash
# Run once to process recent messages
./scripts/memory-catchup.sh

# Set up cron to run every minute
(crontab -l 2>/dev/null; echo "* * * * * source ~/.bashrc && /path/to/scripts/memory-catchup.sh >> ~/.openclaw/logs/memory-catchup.log 2>&1") | crontab -
```

The catch-up script:
- Reads session transcripts from `~/.openclaw/agents/main/sessions/`
- Tracks last processed timestamp to avoid duplicates
- Rate-limits to 3 messages per run
- Runs extraction asynchronously

State is stored in `~/.openclaw/memory-catchup-state.json`.

## Context Window (2026-02-07)

The extraction pipeline now maintains a **20-message rolling context window** for improved reference resolution.

### How It Works

1. **Rolling Cache**: Last 20 messages stored in `~/.openclaw/memory-message-cache.json`
2. **Interleaved**: Both user AND assistant messages included chronologically
3. **Bidirectional**: BOTH speakers' messages get extracted, not just user

### Context Format

```
[USER] 1: How much do crawlers cost?
[NOVA] 2: About $130M in today's dollars...
[USER] 3: Let's build one for Burning Man
[NOVA] 4: That would be legendary...
---
[CURRENT USER MESSAGE - EXTRACT FROM THIS]
Yes, keep the aesthetic
```

### Benefits

- **Reference resolution**: "Yes", "that", "do it" now have meaning
- **Self-memory**: NOVA's actions/updates get extracted too
- **Conversation flow**: Full context for both speakers

### Deduplication

**Layer 1 (Prompt)**: Existing facts/vocab queried and included in prompt
**Layer 2 (Storage)**: `store-memories.sh` checks before every insert

### Scripts Updated

- `memory-catchup.sh` - Now processes both roles, builds context cache
- `extract-memories.sh` - Updated prompt for conversation format
- `store-memories.sh` - Added duplicate checking functions
