---
name: agent-turn-context
description: "Injects per-turn context from agent_turn_context table"
metadata: {"openclaw":{"events":["message:received"]}}
---

# Agent Turn Context Hook

Injects critical per-turn context from the `agent_turn_context` database table.
Fires on every `message:received` event. Caches results with 5-minute TTL.

## What It Does

1. Receives each incoming message event
2. Looks up per-turn context for the current agent from `agent_turn_context`
3. Injects context into `event.messages` so the agent sees it before responding
4. Caches DB results for 5 minutes per agent to avoid per-turn query overhead

## Context Types (priority order)

| Type | context_key | Scope |
|------|-------------|-------|
| UNIVERSAL | `*` | All agents, always injected |
| GLOBAL | `*` | All agents, always injected |
| DOMAIN | domain name | Agents whose domains match via `agent_domains` |
| AGENT | agent name | Specific agent only |

## Size Limits

- **Per record**: 500 characters max (enforced by CHECK constraint)
- **Per agent total**: 2000 characters max (enforced by `get_agent_turn_context()`)

## Truncation Warning

If the 2000-character budget is exceeded, the hook:
1. Logs a warning to the gateway logs
2. Appends a visible warning to the injected context: `⚠️ Turn context truncated — some critical rules may be missing. Alert I)ruid.`

## Error Handling

Fails silently — database errors are logged but do not block message processing.

## Related

- `agent_bootstrap_context` — session-level bootstrap context (separate concern)
- `semantic-recall` hook — semantic memory injection (separate concern, same event)
- Migration: `migrations/065_agent_turn_context.sql`
- Issue: https://github.com/NOVA-Openclaw/nova-memory/issues/143
