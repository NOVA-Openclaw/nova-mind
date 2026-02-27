# Database Bootstrap Context System

Automatic agent context loading from PostgreSQL database with file fallbacks.

> *Before the first word,*
> *the database speaks: here, begin—*
> *mem'ry precedes thought*
>
> — **Erato**

## Overview

OpenClaw agents normally load context from workspace files. This system replaces that with **database-backed context** that can be updated without touching the filesystem, with per-agent customization based on domains and roles.

## Context Types

All context is stored in a single table: `agent_bootstrap_context`.

### UNIVERSAL

Context injected into **every agent** regardless of identity or domain.

- Core infrastructure principles
- Workspace paths, database access, communication patterns

There should be very little here — only truly universal operating principles.

### GLOBAL

Context injected into **every agent**. System-wide rules and architecture.

- Coordination rules (check before starting, use SE workflow, document handoffs)
- System context (shared resources, communication patterns)

### DOMAIN

Context injected into agents **based on their domain assignments** (via `agent_domains` table). Any agent assigned to a domain receives that domain's context.

- **Software Engineering** — coding practices, testing requirements, development standards, issue-driven development, programming best practices
- **Technical Writing** — documentation standards, style guides
- **Version Control** — git operations, repo templates, schema sync
- **Information Security** — security principles, audit procedures
- **Systems Administration** — sysadmin context, infrastructure principles
- **OpenClaw Development** — OpenClaw-specific config and development practices
- **Library** — library workflow, database reference
- etc.

**Key principle:** If knowledge applies to a _domain_ rather than a specific agent, it belongs in a DOMAIN record. Multiple agents can share a domain. When a new agent is assigned to a domain, they automatically inherit all domain knowledge.

### WORKFLOW

Workflow context is **dynamically generated** by the `get_agent_bootstrap()` function from the `workflows` and `workflow_steps` tables. Agents receive full workflow definitions for any workflow they participate in, matched by domain overlap.

**⚠️ Never store workflow summaries as static entries.** They will go stale. The function builds current workflow content on every call.

### AGENT

Context injected into a **specific named agent only**. This is the only context type matched by agent name.

**AGENT records should contain identity context only:**
- Who the agent is (name, role, personality, vibe)
- What the agent's scope is (what they do and don't do)
- How the agent communicates (tone, style)
- Key tools specific to this agent (not domain tools)

**AGENT records should NOT contain:**
- Domain knowledge (use DOMAIN records)
- Workflow definitions (generated dynamically)
- Coding practices, documentation standards, etc. (these are domain knowledge)
- Static workflow summaries or snapshots (will go stale)

If you're adding context and thinking "any agent working in X domain would need this" — it's a DOMAIN record, not an AGENT record.

## Architecture

```
Agent Spawn Request
        ↓
agent:bootstrap event fires
        ↓
db-bootstrap-context hook intercepts
        ↓
get_agent_bootstrap(agent_name)
        ↓
┌─────────────────────────────────────────┐
│ 1. UNIVERSAL records (all agents)       │
│ 2. GLOBAL records (all agents)          │
│ 3. DOMAIN records (by agent_domains)    │
│ 4. WORKFLOW records (by domain overlap) │  ← dynamically generated
│ 5. AGENT records (by agent name)        │
└─────────────────────────────────────────┘
        ↓
    ┌─── Database available? ───┐
    │                           │
   YES                         NO
    │                           │
    ↓                           ↓
Return DB context      Try fallback files
    │                  (~/.openclaw/bootstrap-fallback/)
    │                           │
    │                  ┌── Found? ──┐
    │                  │            │
    │                 YES          NO
    │                  │            │
    │                  ↓            ↓
    │           Return files   Emergency context
    └──────────┬────────────────────┘
               ↓
    Inject into event.context.bootstrapFiles
               ↓
    Agent starts with loaded context
```

## Domain Assignment

Agents receive DOMAIN context based on their entries in the `agent_domains` table:

```sql
-- See which domains an agent is assigned to
SELECT domain_topic FROM agent_domains ad
JOIN agents a ON a.id = ad.agent_id
WHERE a.name = 'coder';

-- See which agents are in a domain
SELECT a.name FROM agents a
JOIN agent_domains ad ON a.id = ad.agent_id
WHERE ad.domain_topic = 'Software Engineering';
```

## Database Schema

### Table: `agent_bootstrap_context`

| Column | Type | Description |
|--------|------|-------------|
| `id` | serial | Primary key |
| `context_type` | text | `UNIVERSAL`, `GLOBAL`, `DOMAIN`, `AGENT` |
| `agent_name` | text | Agent name (AGENT type only, NULL otherwise) |
| `domain_name` | text | Domain name (DOMAIN type only, NULL otherwise) |
| `file_key` | text | Identifier (becomes `{file_key}.md` in output) |
| `content` | text | The actual context content |
| `description` | text | Human-readable description |
| `updated_by` | text | Who last modified this entry |
| `updated_at` | timestamptz | Last modification time |

### Function: `get_agent_bootstrap(agent_name text)`

Returns all context for an agent:

```sql
SELECT source, filename, content FROM get_agent_bootstrap('coder');
```

Sources returned:
- `universal` — UNIVERSAL records
- `global` — GLOBAL records
- `domain:<name>` — DOMAIN records matched by agent_domains
- `workflow:<name>` — dynamically generated from workflows + workflow_steps
- `agent` — AGENT records matched by name

### Supporting tables

- `agent_domains` — Maps agents to domains (used for DOMAIN and WORKFLOW context resolution)
- `workflows` / `workflow_steps` — Source for dynamic WORKFLOW context generation

## Fallback System

Three-tier fallback:
1. **Database** — Primary source via `get_agent_bootstrap()`
2. **Static files** — `~/.openclaw/bootstrap-fallback/*.md`
3. **Emergency context** — Minimal recovery instructions

## Hook

The `db-bootstrap-context` hook intercepts `agent:bootstrap` events and replaces the default filesystem-based context loading with database queries.

**Hook directory:** `~/.openclaw/hooks/db-bootstrap-context/`

Required files:
- `HOOK.md` — metadata with `metadata: {"openclaw":{"events":["agent:bootstrap"]}}`
- `handler.ts` — hook handler
- `package.json` — must include `"type": "module"` for ESM imports

The hook uses `loadPgEnv()` from `~/.openclaw/lib/pg-env.ts` to load database credentials from `~/.openclaw/postgres.json`.

## File Structure

```
bootstrap-context/
├── README.md                    # This file
├── install.sh                   # Installation script
├── schema/
│   └── bootstrap-context.sql    # Database table definition
├── sql/
│   └── migrate-initial-context.sql  # Import existing files
├── hook/
│   ├── handler.ts               # OpenClaw hook
│   ├── HOOK.md                  # Hook metadata
│   └── package.json             # ESM module config
├── fallback/
│   ├── UNIVERSAL_SEED.md        # Fallback files
│   ├── AGENTS.md
│   ├── SOUL.md
│   └── ...
└── docs/
    └── MANAGEMENT.md
```

## Owner

**Newhart (NHR Agent)** — Non-Human Resources

Newhart owns the `agent_bootstrap_context` table (write trigger enforced). All context management goes through Newhart.

## License

MIT License — Part of [nova-mind](https://github.com/NOVA-Openclaw/nova-mind)
