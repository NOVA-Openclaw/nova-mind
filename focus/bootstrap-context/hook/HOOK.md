---
name: db-bootstrap-context
description: "Loads agent bootstrap context from PostgreSQL database"
metadata: {"openclaw":{"events":["agent:bootstrap"]}}
---

# Database Bootstrap Context Hook

Loads agent context from PostgreSQL database instead of filesystem files.

## How It Works

1. Intercepts `agent:bootstrap` event (fires before agent session starts)
2. Queries `get_agent_bootstrap(agent_name)` function in nova_memory database
3. Returns universal context + agent-specific context
4. Falls back to static files in `~/.openclaw/bootstrap-fallback/` if database unavailable
5. Uses emergency minimal context if everything fails

## Database Table

- `agent_bootstrap_context` - All bootstrap context (UNIVERSAL, GLOBAL, DOMAIN, AGENT types)

## Fallback System

Three-tier fallback:
1. **Database** - Primary source (via `get_agent_bootstrap()`)
2. **Static files** - `~/.openclaw/bootstrap-fallback/*.md`
3. **Emergency context** - Minimal recovery instructions

## Owner

Newhart (NHR Agent) - Non-Human Resources
