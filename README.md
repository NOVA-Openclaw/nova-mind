# nova-mind

NOVA Agent Mind — unified memory, cognition, and relationships.

> *Memory, thought, trust—*
> *three rivers join, flow as one*
> *mind holds what it meets*
>
> — **Erato**

This repo consolidates the previously separate repos:
- [nova-memory](https://github.com/NOVA-Openclaw/nova-memory) → `memory/`
- [nova-cognition](https://github.com/NOVA-Openclaw/nova-cognition) → `cognition/`
- [nova-relationships](https://github.com/NOVA-Openclaw/nova-relationships) → `relationships/`

## What Is nova-mind?

nova-mind is the complete agent mind stack for NOVA. It provides:

- **Memory** — Persistent PostgreSQL memory with semantic recall, extraction hooks, and a structured schema for entities, facts, relationships, events, and lessons
- **Cognition** — Agent orchestration, inter-agent messaging, bootstrap context seeding, and the agent-config-sync system that keeps model configuration in sync with the database
- **Relationships** — Entity resolution across platforms, session-aware caching, certificate-based agent identity (Web of Trust), and the social graph

All three subsystems share a single PostgreSQL database (`{username}_memory`) and a unified installer.

## Structure

```
nova-mind/
├── memory/          # Database schema, migrations, semantic recall, library
├── cognition/       # Hooks, workflows, agent coordination
├── relationships/   # Entity relationships, social graph
├── database/        # Root-level unified schema (schema.sql, .pgschemaignore)
├── agent-install.sh # Unified installer (for agents with env pre-configured)
├── shell-install.sh # Interactive setup wrapper (for humans or SSH sessions)
└── lib/             # Shared libraries (pg-env.sh, pg_env.py, env-loader.sh, etc.)
```

## Installation

```bash
# Interactive shell (human or agent in an SSH session)
bash shell-install.sh

# OpenClaw agent working within its own environment (env vars already set)
bash agent-install.sh
```

The installer is **idempotent** — safe to run multiple times. It installs all three subsystems in order (relationships → memory → cognition), applying only what has changed.

### Prerequisites

- PostgreSQL 12+ with `pgvector` extension
- Node.js 18+ and npm
- Python 3 with `python3-venv`
- `pgschema` — `go install github.com/pgplex/pgschema@latest`
- `jq`
- OpenAI API key (for semantic recall embeddings)
- Anthropic API key (for memory extraction)

### Flags

| Flag | Description |
|------|-------------|
| `--verify-only` | Check installation without modifying anything |
| `--force` | Force overwrite existing files |
| `--no-restart` | Skip automatic gateway restart |
| `--database NAME` / `-d NAME` | Override database name (default: `${USER}_memory`) |

See subsystem READMEs for detailed documentation:
- [memory/README.md](memory/README.md) — Memory system, schema, hooks, and extraction pipeline
- [cognition/README.md](cognition/README.md) — Agent orchestration, messaging, and configuration sync
- [relationships/README.md](relationships/README.md) — Entity resolution and Web of Trust
