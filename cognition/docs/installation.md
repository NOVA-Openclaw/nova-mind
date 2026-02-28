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

-- Agent registry
CREATE TABLE agents (
    id SERIAL PRIMARY KEY,
    nickname VARCHAR(50) UNIQUE,
    name VARCHAR(100) NOT NULL,
    role VARCHAR(50),
    model VARCHAR(100),
    instance_type VARCHAR(20) DEFAULT 'subagent',  -- 'primary', 'peer', 'subagent'
    persistent BOOLEAN DEFAULT false,
    seed_context JSONB,
    instantiation_sop VARCHAR(100),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Inter-agent communication
-- Column history (#106): mentions → recipients, created_at → "timestamp", channel dropped
-- All inserts via send_agent_message(sender, message, recipients)
CREATE TABLE agent_chat (
    id          SERIAL PRIMARY KEY,
    sender      TEXT NOT NULL,
    message     TEXT NOT NULL,
    recipients  TEXT[] NOT NULL CHECK (array_length(recipients, 1) > 0),
    reply_to    INTEGER REFERENCES agent_chat(id),
    "timestamp" TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

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
4. **Agent chat requires dual config** — both `channels.agent_chat` and `plugins.entries.agent_chat.config` must contain the database connection details. The `agent-install.sh` script handles this automatically, but manual setups must configure both or the gateway will fail plugin validation

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

### Cross-Database Replication

For setups where agents use separate databases but need to share message history, see the [Cross-Database Replication Guide](cross-database-replication.md). This covers:

- PostgreSQL logical replication setup
- Trigger configuration for replicated data  
- Automatic detection and configuration via `agent-install.sh`

> **Note:** `agent-install.sh` configures both `channels.agent_chat` (channel definition) and `plugins.entries.agent_chat.config` (plugin configuration) with identical connection details. Both are required — the gateway validates plugin config separately from channel config.
- Troubleshooting replication issues

Example: Graybeard agent using `graybeard_memory` database while replicating messages from `nova_memory`.

## Next Steps

1. Populate `ai_models` table with available models
2. Register agents in `agents` table
3. Create instantiation SOPs for complex agents
4. Set up inter-agent communication protocol

---

*See [pitfalls.md](pitfalls.md) for common mistakes to avoid.*
