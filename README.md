# nova-mind

NOVA Agent Mind — unified memory, cognition, and relationships.

This repo consolidates the previously separate repos:
- [nova-memory](https://github.com/NOVA-Openclaw/nova-memory) → `memory/`
- [nova-cognition](https://github.com/NOVA-Openclaw/nova-cognition) → `cognition/`
- [nova-relationships](https://github.com/NOVA-Openclaw/nova-relationships) → `relationships/`

## Structure

```
nova-mind/
├── memory/          # Database schema, migrations, semantic recall, library
├── cognition/       # Hooks, workflows, agent coordination
├── relationships/   # Entity relationships, social graph
├── agent-install.sh # Unified installer
├── shell-install.sh # Interactive setup wrapper
└── lib/             # Shared libraries (pg-env.sh, etc.)
```

## Installation

```bash
# Interactive (prompts for config)
bash shell-install.sh

# Non-interactive (uses existing config)
bash agent-install.sh
```
