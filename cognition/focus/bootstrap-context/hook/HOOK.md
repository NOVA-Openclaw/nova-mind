---
name: db-bootstrap-context
description: "Replaces agent bootstrap with PostgreSQL-sourced context, falls through to disk on failure"
metadata: {"openclaw":{"events":["agent:bootstrap"]}}
---

# Database Bootstrap Context Hook

Replaces the standard agent bootstrap pipeline with database-sourced context when available, falling through to the normal disk-based bootstrap flow on any failure.

## How It Works

1. Fires on `agent:bootstrap` events (only — early-returns on any other event type)
2. Queries `get_agent_bootstrap(agent_name)` in `nova_memory` for the current agent
3. **Success path** (≥1 row returned): REPLACES `event.context.bootstrapFiles` entirely with `WorkspaceBootstrapFile[]` built from DB rows. Disk bootstrap files are intentionally discarded — DB context is authoritative.
4. **Failure path** (DB unavailable, function missing, query errors, or zero rows): the hook does NOT modify `event.context.bootstrapFiles`. The normal disk-based bootstrap flow remains in effect, including any fallback warnings carried in the on-disk markdown files (e.g. `bootstrap-fallback/IDENTITY.md`).

This is a **replacement-with-fallthrough** model — not additive. When the DB query succeeds, the entire bootstrap content comes from the database function. When it fails, the disk pipeline owns the result and supplies its own warnings.

## Output Shape

Each DB row produces a `WorkspaceBootstrapFile`:

```ts
{
  name: string,         // DB filename, e.g. "IDENTITY.md", "WORKFLOW_NOVA_SELF_UPDATE.md"
  path: string,         // Synthetic path: "db:<source>/<filename>"
  content: string,      // DB content
  missing: false
}
```

The `path` is purely identifying (no disk read happens; `content` is supplied directly).

## Database Function Contract

Expects `public.get_agent_bootstrap(p_agent_name text)` returning:

```sql
TABLE(filename text, content text, source text)
```

Sources include `universal`, `global`, `domain:<topic>`, `workflow:<name>`, `agent`. The function aggregates UNIVERSAL + GLOBAL + DOMAIN-matched + WORKFLOW-matched (by domain) + AGENT-specific rows into a single result set.

## Why This Replaces Disk Bootstrap

Disk bootstrap files (`AGENTS.md`, `IDENTITY.md`, etc.) are now legacy fallback. The canonical agent bootstrap context lives in `agent_bootstrap_context` rows queryable via `get_agent_bootstrap()`. Disk files are kept as-is for the failure path so the agent never starts with zero context.

## Owner

Newhart (Database / Agent Design domain) — owns `get_agent_bootstrap()` and the `agent_bootstrap_context` table.
