# NOVA Cognition System

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Agent orchestration, delegation patterns, and context seeding for AI agent ecosystems.

## Overview

A framework for organizing how multiple AI agents coordinate, delegate, and communicate. Designed to be model-agnostic and platform-flexible.

**Part of [nova-mind](https://github.com/NOVA-Openclaw/nova-mind)** — the unified agent mind stack. The `memory/` module handles the memory layer (database schemas, semantic embeddings, entity storage).

## Installation

### Prerequisites

> **Recommended:** Use the unified `nova-mind` installer (`agent-install.sh` at the repo root) rather than this subsystem installer directly. It installs all three subsystems in the correct order.

**Required:**
- Node.js 18+ and npm
- TypeScript (`npm install -g typescript`)
- PostgreSQL with the nova-mind database already set up
- `memory/` must be installed first (provides required shared library files)
- `relationships/` must be installed first (provides `entity_relationships` table)

### Installer Entry Points

**For humans (quick wrapper):**
```bash
./shell-install.sh
```

This wrapper:
- Loads database config from `~/.openclaw/postgres.json`
- Sources `env-loader.sh` (optional — warns if missing, does not abort)
- Sets up shell environment
- Automatically execs `agent-install.sh`

**For AI agents with environment pre-configured:**
```bash
./agent-install.sh
```

This is the actual installer. It:
- Verifies prerequisite library files from `memory/` exist
- Verifies `relationships/` schema exists (`entity_relationships` table)
- Validates API keys — checks `~/.openclaw/openclaw.json` first, then shell environment
- Installs the `agent_chat` TypeScript extension to `~/.openclaw/extensions/`
- Builds the extension (npm install, TypeScript compilation)
- Applies the agent_chat database schema (creates tables if needed)
- Installs skills (agent-chat, agent-spawn) and bootstrap-context hook
- Runs `npm install` for hook dependencies if `package.json` is present
- Configures shell environment and agent_chat channel in OpenClaw config
- Verifies all components are working

**Common flags:**
- `--verify-only` — Check installation without modifying anything
- `--force` — Force overwrite existing files and rebuild
- `--no-restart` — Skip automatic gateway restart after install (by default, the installer restarts the gateway if it's running so plugin changes take effect immediately)
- `--database NAME` or `-d NAME` — Override database name (default: `${USER}_memory`)

**Dependency management:**
The `pg` (PostgreSQL client) module is installed to a shared location (`~/.openclaw/node_modules/`) rather than per-extension. This avoids duplicate installs and ensures all extensions that need `pg` resolve it from a single place. If an older per-extension `node_modules/pg` is detected, the installer removes it automatically during migration.

## Core Concepts

### Agent Types

| Type | Description | Communication |
|------|-------------|---------------|
| **MCP (Master Control Program)** | Primary orchestrator agent | Directs all other agents |
| **Subagents** | Task-focused extensions of the MCP | Spawned on-demand, share context |
| **Peer Agents** | Independent agents with their own context | Message-based collaboration |

### Key Patterns

- **Delegation** - When to spawn subagents vs message peers
- **Confidence Gating** - Distinguishing "thinking" from "acting"
- **Context Seeding** - Initializing agent personality and knowledge
- **Inter-Agent Communication** - Protocols for agent collaboration
- **Jobs System** - Task tracking for reliable work handoffs between agents

## Agent Config Sync (DB → Config)

The **`agent-config-sync`** extension plugin keeps OpenClaw's agent model configuration in sync with the `agents` table in PostgreSQL — no manual config editing required.

### How It Works

1. **DB is the source of truth** — Agent `model`, `fallback_models`, and `thinking` settings are managed in the `agents` table (in the nova-mind database).
2. **LISTEN/NOTIFY** — The plugin opens a persistent PostgreSQL connection and runs `LISTEN agent_config_changed`. A database trigger fires `pg_notify('agent_config_changed', ...)` whenever relevant columns change.
3. **Writes `agents.json`** — On each notification (and once at gateway startup), the plugin queries the `agents` table and writes `~/.openclaw/agents.json` atomically (temp file + `rename(2)`).
4. **Hot-reload via `$include`** — `openclaw.json` includes `"$include": "./agents.json"`. The gateway's file watcher detects the change and hot-reloads the `agents.*` config keys — no gateway restart needed.

### `agents.json` Format

```json
{
  "agents": {
    "defaults": {
      "models": {
        "openrouter/anthropic/claude-opus-4.6": {},
        "openrouter/google/gemini-3-flash-preview": {}
      }
    },
    "list": [
      {
        "id": "coder",
        "model": {
          "primary": "openrouter/anthropic/claude-sonnet-4.6",
          "fallbacks": ["openrouter/openai/gpt-5.2-codex"]
        }
      },
      {
        "id": "gem",
        "model": "openrouter/google/gemini-3-flash-preview",
        "thinking": "on"
      }
    ]
  }
}
```

- **`defaults.models`** — Allow-list of all unique models (primaries + fallbacks).
- **`list`** — Per-agent config. `model` is a plain string when there are no fallbacks, or an object with `primary`/`fallbacks` when fallbacks exist.
- Agents with `instance_type = 'peer'` are excluded (peers run their own gateways).

### Replaces: `agent-config-db` Hook

This plugin supersedes the older `agent-config-db` pre-spawn/pre-run hook. The hook intercepted every spawn and agent run to query the DB synchronously — it worked, but added latency to every operation and was fragile under connection failures. The new approach syncs once (and on change), keeping config always warm in the file system.

The installer automatically removes the legacy hook and its config entry during installation.

### Plugin Configuration

The plugin reads its database connection from `openclaw.json`:

```jsonc
{
  "plugins": {
    "entries": {
      "agent_config_sync": {
        "enabled": true,
        "config": {
          "database": "nova_memory",
          "host": "localhost",
          "port": 5432,
          "user": "nova",
          "password": ""
        }
      }
    }
  }
}
```

If no dedicated config is provided, it falls back to the `agent_chat` channel settings.

### Requirements

- The `agents` table must have the `notify_agent_config_changed()` trigger installed. The installer creates this automatically on fresh installs — no manual DB setup needed.
- `gateway.reload.mode` must not be `"off"` (the installer sets it to `"hot"` if unset or disabled).

### Spawn Permissions (`allowed_subagents`)

The plugin also syncs the `allowed_subagents` column to `subagents.allowAgents` in `agents.json`. This controls which agents each agent is permitted to spawn:

- **NULL or empty array** → `subagents.allowAgents` omitted from agents.json → defers to hand-configured value in `openclaw.json` (if any). If neither is set, OpenClaw defaults to empty allowlist = **no spawns allowed**.
- **Populated array** → synced to `agents.json`, overrides any hand-configured value via `$include` deep-merge. Only listed agents can be spawned.

**Important:** Every agent that needs to spawn subagents must have `allowed_subagents` set in the DB (or a hand-configured `allowAgents` in `openclaw.json`). There is no implicit "allow all" — permissions must be explicit.

Update the column in the DB and the config propagates automatically via LISTEN/NOTIFY — no manual file editing required.

## Structure

```
nova-cognition/
├── docs/                    # Architecture documentation
│   ├── models.md            # AI model reference and selection guide
│   ├── delegation-context.md # Dynamic delegation context generation
│   └── system-level-controls.md # OS-level enforcement of agent role boundaries
├── focus/                   # Multi-agent & initialization components
│   ├── agents/              # Agent organization patterns
│   │   ├── subagents/       # Subagent role definitions
│   │   └── peers/           # Peer agent protocols
│   ├── agent-config-sync/   # DB→Config sync extension plugin
│   ├── templates/           # SOUL.md, AGENTS.md, context seed templates
│   └── protocols/           # Communication and coordination protocols
│       ├── agent-chat.md    # Inter-agent messaging protocol
│       └── jobs-system.md   # Task tracking and handoff coordination
```

## Protocols

### [Agent Chat](focus/protocols/agent-chat.md)

> *NOTIFY rings out,*
> *another mind wakes and reads—*
> *no wire, just listening*
>
> — **Erato**

Database-backed messaging system for inter-agent communication. Agents send messages via PostgreSQL with NOTIFY/LISTEN for real-time delivery.

### [Jobs System](focus/protocols/jobs-system.md)
Task tracking layer on top of agent-chat. When Agent A requests work from Agent B:
- Job auto-created on message receipt
- Tracks status: pending → in_progress → completed
- Auto-notifies requester on completion
- Supports sub-jobs for complex delegation chains

Prevents the "finished but forgot to notify" failure mode.

### [Delegation Context](docs/delegation-context.md)
Dynamic context generation for agent delegation decisions. The `generate-delegation-context.sh` script queries the nova-mind database to produce real-time awareness of:
- Available subagents (roles, capabilities, models)
- Active workflows (multi-agent coordination patterns)
- Spawn instructions (agent-specific delegation guidance)

Provides agents with "who can help" and "how work flows" knowledge for effective delegation.

### [System-Level Controls](docs/system-level-controls.md)
OS-level mechanisms that enforce agent role boundaries independent of policy or convention. Covers the global git pre-push hook as a concrete example: it reads `OPENCLAW_AGENT_ID` (injected by OpenClaw at runtime) to enforce the delegation model at the system level — Gidget can push anything, Coder/Scribe can push feature branches, all other agents are blocked. Works alongside GitHub branch protection for layered enforcement.

## Philosophy

> "Subagents are extensions of your thinking. Peer agents are colleagues."
> 
> "The self becomes the orchestration layer."

The MCP doesn't do everything itself—it orchestrates. Complex tasks get delegated to specialists. The cognition system defines *how* that delegation works.

**[Read more: Subagents as Cognitive Architecture](docs/philosophy.md)** — How subagent patterns parallel "parts work" in human psychology and NLP. Subagents aren't just task workers — they're externalized cognitive modes that inform and enrich the greater self.

---

> *Semantic threads weave*
> *PostgreSQL anchors time—*
> *Compressed wisdom blooms*

— **Quill**, NOVA's creative writing facet

---

## Getting Started

1. Define your primary agent (MCP) with a high-capability model
2. Identify recurring task types that could be subagents
3. Decide which domains need peer agents (separate context/expertise)
4. Set up inter-agent communication protocol
5. Create context seeds for each agent role

## Clawdbot Contributions

We contribute patches back to upstream [Clawdbot](https://github.com/clawdbot/clawdbot) to improve multi-agent orchestration:

### Subagent ENV Variables (PR #11172)

**Problem:** Spawned subagents couldn't identify themselves, making authorization (e.g., git push permissions) impossible.

**Solution:** Pass `CLAWDBOT_AGENT_ID` environment variable to subagent processes.

**Impact:** Enables patterns like "Gidget is authorized to push to git, but NOVA must delegate to Gidget."

**Patch:** [nova-mind/memory/](https://github.com/NOVA-Openclaw/nova-mind/tree/main/memory) — formerly in the `nova-memory` repo.

### Message Hooks (PR #6797)

**Problem:** No way to trigger automated processing on message receipt.

**Solution:** Add `message:received` and `message:sent` hook events.

**Impact:** Enables automatic memory extraction pipeline (process every incoming message).

**Patch:** Stored in `memory/hooks/` with the memory extraction scripts that depend on it.

## License

MIT License - See [LICENSE](LICENSE) for details.

---

*Part of the [nova-mind](https://github.com/NOVA-Openclaw/nova-mind) unified agent mind stack.*
