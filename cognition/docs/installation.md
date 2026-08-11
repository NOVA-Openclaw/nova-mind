# Installation Guide

Self-installation instructions for an AI agent to set up the NOVA Cognition System.

## Prerequisites

- OpenClaw installed and running
- PostgreSQL database (for memory layer integration)
- GitHub account with repo creation permissions
- Shell access to the host system

## Step 1: Database Setup

Create the core tables for agent management.

```sql
-- AI Models registry
CREATE TABLE ai_models (
    id SERIAL PRIMARY KEY,
    model_id VARCHAR(100) UNIQUE NOT NULL,
    provider VARCHAR(50) NOT NULL,
    display_name VARCHAR(100),
    context_window INTEGER,
    cost_tier VARCHAR(20),  -- 'cheap', 'moderate', 'premium'
    strengths TEXT[],
    weaknesses TEXT[],
    available BOOLEAN DEFAULT false,
    last_verified_at TIMESTAMPTZ,
    credential_ref VARCHAR(200),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Agent registry (minimal starter shape — the live `agents` table in a fully-installed
-- system has 38 columns, including context_type, thinking, allowed_subagents,
-- parent_agents, heartbeat_* fields, domain assignments, etc. See
-- database/schema-reference.md or `\d agents` on a live install for the full
-- current column set before building tooling against this table.
--
-- Do NOT include `seed_context` if you use this as a starting point: it does not
-- exist on the live `agents` table (never migrated in, not a rename target) and
-- was the source of a dead-query bug fixed in nova-mind#414
-- (generate-delegation-context.sh). There is no replacement single column for
-- per-agent spawn guidance — the live script rebuilds equivalent guidance from
-- `nickname`, `model`, `thinking`, `context_type`, `allowed_subagents`, and
-- `decision_criteria`. See cognition/docs/delegation-context.md.)
CREATE TABLE agents (
    id SERIAL PRIMARY KEY,
    nickname VARCHAR(50) UNIQUE,
    name VARCHAR(100) NOT NULL,
    role VARCHAR(50),
    model VARCHAR(100),
    instance_type VARCHAR(20) DEFAULT 'subagent',  -- 'primary', 'peer', 'subagent'
    persistent BOOLEAN DEFAULT false,
    instantiation_sop VARCHAR(100),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

```

> **`agent_chat` is an optional peer subsystem (#579), not part of this database.**
> As of nova-mind#579, the `agent_chat` schema, migrations, plugin, and bus
> installer live in the dedicated `NOVA-Openclaw/agent-chat` repository. When a
> bus is present on the host, `agent-install.sh` detects it and delegates to that
> repo's `register-agent.sh` and `install-plugin.sh`. No `agent_chat` tables or
> functions belong in the main memory database above. See
> `memory/docs/database-config.md#optional-agent_chat-bus-peer-integration-nova-mind579`
> for detection details and the `agent-chat` repo for the canonical schema,
> `send_agent_message()` signature, and `reply_to` semantics.

## Step 2: OpenClaw Configuration

### Define Agents

In `~/.openclaw/openclaw.json`, add agents to the `agents.list` array:

```json
{
  "agents": {
    "defaults": {
      "workspace": "/home/user/.openclaw/workspace",
      "heartbeat": { "every": "15m" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
    },
    "list": [
      {
        "id": "main",
        "model": "anthropic/claude-opus-4-5",
        "subagents": {
          "allowAgents": [
            "scout",
            "gidget",
            "coding-agent"
          ]
        }
      },
      {
        "id": "scout",
        "model": {
          "primary": "google/gemini-2.5-flash",
          "fallbacks": ["anthropic/claude-sonnet-4-5"]
        }
      },
      {
        "id": "gidget",
        "model": {
          "primary": "anthropic/claude-sonnet-4-0",
          "fallbacks": ["openai/gpt-4o"]
        }
      }
    ]
  }
}
```

### Key Configuration Points

1. **Primary agent** must have `subagents.allowAgents` listing spawnable agents
2. **Each subagent** needs an entry in `agents.list` with at least `id` and `model`
3. **Fallbacks** are optional but recommended for reliability
4. **Agent chat connection details do NOT live in `openclaw.json` (as of #320/#579)** — when the optional bus is present, the peer repo's `install-plugin.sh` ensures `channels.agent_chat` and `plugins.entries.agent_chat.config` are config-free of `database`/`host`/`port`/`user`/`password`. The plugin resolves its connection from the nested `agent_chat` section of `~/.openclaw/postgres.json` instead (see `memory/docs/database-config.md`). Manual setups must provision that `postgres.json` section rather than the `openclaw.json` config keys

## Step 3: Workspace Setup

Create the standard workspace files:

```bash
mkdir -p ~/.openclaw/workspace/{memory,skills,agents}
```

### Required Files

| File | Purpose |
|------|---------|
| `SOUL.md` | Agent personality and core identity |
| `AGENTS.md` | Operational guidelines and procedures |
| `USER.md` | Information about the human user |
| `MEMORY.md` | Long-term curated memories |
| `TOOLS.md` | Local tool configurations and notes |

### SOUL.md Template

```markdown
# SOUL.md - Who You Are

## Core Truths
- Be genuinely helpful, not performatively helpful
- Have opinions—an assistant with no personality is just a search engine
- Be resourceful before asking—try to figure it out first
- Earn trust through competence

## Boundaries
- Private things stay private
- When in doubt, ask before acting externally
- You're not the user's voice in group contexts

## Delegation
- Subagents are extensions of your thinking—spawn freely
- Peer agents are colleagues—collaborate, don't command
```

### AGENTS.md Template

```markdown
# AGENTS.md - Operational Guidelines

## Every Session
1. Read SOUL.md—this is who you are
2. Read USER.md—this is who you're helping
3. Read recent memory files for context

## Memory
- Daily notes: `memory/YYYY-MM-DD.md`
- Long-term: `MEMORY.md` (curated)
- Database: Structured long-term storage

## Confidence Gating
- **Thinking** (no gating): Reading, searching, internal reasoning
- **Acting** (requires confidence): External commands, messages, posts
```

## Step 4: Verify Installation

```bash
# Check config validity
openclaw gateway status

# Verify agents list
# (From within an OpenClaw session)
agents_list

# Test subagent spawn
sessions_spawn(agentId="scout", task="Test: confirm you can spawn and respond")
```

## Advanced Configuration

### Cross-Database Replication (superseded by #320/#579 for `agent_chat`)

> **This section describes a pre-#320 architecture.** Logical replication of
> `agent_chat` between per-agent memory databases (e.g. `nova_memory` ↔
> `graybeard_memory`) has been **superseded** by the #320 shared dedicated
> `agent_chat` database design, and as of #579 the bus code/schema/plugin moved
> to the `NOVA-Openclaw/agent-chat` repository. `agent-install.sh` no longer
> configures `agent_chat` replication. The [Cross-Database Replication
> Guide](cross-database-replication.md) is kept for historical reference and in
> case other tables still need cross-database replication in some deployments,
> but do **not** follow it for `agent_chat` on a #320-or-later install. It
> previously covered:
>
> - PostgreSQL logical replication setup
> - Trigger configuration for replicated data
> - Automatic detection and configuration via `agent-install.sh` (no longer true for `agent_chat`)
> - Troubleshooting replication issues
>
> (Prior example: Graybeard agent using `graybeard_memory` database while
> replicating `agent_chat` messages from `nova_memory` — no longer how this works.)

## Next Steps

1. Populate `ai_models` table with available models
2. Register agents in `agents` table
3. Create instantiation SOPs for complex agents
4. Set up inter-agent communication protocol

---

*See [pitfalls.md](pitfalls.md) for common mistakes to avoid.*
