# Delegation Context Generation

Dynamic delegation context provides agents with real-time awareness of available subagents, active workflows, and spawn instructions.

## Purpose

When an agent needs to delegate work, it should know:

1. **Who's available** - Active subagents with their roles and capabilities
2. **How work flows** - Multi-agent workflows and each agent's role
3. **How to spawn** - Agent-specific guidance for effective delegation

## Implementation

### Script: `generate-delegation-context.sh`

**Source (tracked in this repo):** `cognition/scripts/generate-delegation-context.sh`

**Installed location:** `$HOME/.openclaw/workspace/scripts/generate-delegation-context.sh` (copied there by `agent-install.sh`)

**Output:** `~/.openclaw/workspace/DELEGATION_CONTEXT.md` (configurable via first positional argument)

**Database:** `nova_memory` by default, overridable via `DELEGATION_CONTEXT_DB_NAME` (also `DELEGATION_CONTEXT_DB_USER`, `DELEGATION_CONTEXT_DB_HOST`, `DELEGATION_CONTEXT_DB_PORT`). Authentication is via `~/.pgpass` — the script never reads the gateway-injected `PGPASSWORD` variable.

> **History (#414):** This script was deployed and run against the live workspace for some time but was never committed to the repo — the only copy was the deployed one, and it was later deleted, leaving no working generator. It was recreated from an introspection transcript and, in the process, two dead queries (below) and several other defects were fixed: `2>/dev/null` stderr suppression was removed everywhere, `set -e` was replaced with per-section error degradation (see [Output Format](#output-format)), a SQL apostrophe/quoting hazard in workflow names was fixed, and leading `#` in workflow description text is now escaped so it can't collide with the document's own markdown headings. See `cognition/CHANGELOG.md` for the full list.

### Data Sources

The queries below are the actual queries in the current script (`cognition/scripts/generate-delegation-context.sh`), not illustrative examples — keep this section in sync with the script if either changes.

#### Agent Roster
```sql
SELECT nickname, role, model, description
FROM agents
WHERE status = 'active'
ORDER BY nickname;
```

#### Workflows and Steps
```sql
-- List of active workflow names:
SELECT name FROM workflows WHERE status = 'active' ORDER BY name;

-- Per-workflow description:
SELECT description FROM workflows WHERE name = '<workflow_name>';

-- Per-workflow steps (workflow_steps_detail has no agent_name column —
-- the view exposes domain/domains, joined here into a single string):
SELECT step_order,
       array_to_string(domains, ', ') AS domains,
       step_description,
       deliverable_type
FROM workflow_steps_detail
WHERE workflow_name = '<workflow_name>'
ORDER BY step_order;
```

#### Spawn Instructions

> **Fixed (#414):** `agents.seed_context` does not exist on the `agents` table and never has in any schema this script has run against — the original script's query against it was dead code that failed on every invocation. There is no rename/migration path to follow; the Spawn Instructions section is rebuilt directly from live `agents` columns instead.

```sql
SELECT nickname,
       model,
       thinking,
       context_type,
       COALESCE(array_to_string(allowed_subagents, ', '), '') AS allowed_subagents,
       decision_criteria
FROM agents
WHERE status = 'active'
ORDER BY nickname;
```

## Output Format

The script generates a markdown document with three sections: **Available Agents**, **Active Workflows**, and **Spawn Instructions** (in that order), preceded by a header and a `**Generated:** <UTC timestamp>` line, and followed by a footer noting the file is auto-generated.

The script does **not** use `set -e`. Each section runs its query, checks the psql exit status itself, and degrades independently on failure:

- **Success with rows:** section renders normally (table or per-workflow subsections).
- **Success with zero rows:** section renders a plain "No active agents/workflows found." line — this is not an error.
- **Query failure:** the section writes `> ⚠️ Failed to generate <section>: query failed (psql exit N)` in place of its content and the script continues to the next section. The script's own exit code is `1` if any section failed (`OVERALL_EXIT`), even though the document itself is otherwise complete. This means a caller checking only "did the file get written" can be misled — check the script's exit code (or grep the output for `⚠️`) to detect degraded sections.

This replaces the old behavior (silent `2>/dev/null` + `set -e`) where the first query failure killed the script mid-document with no error surfaced and no indication in the output that anything was missing (see the original bug report, [#414](https://github.com/NOVA-Openclaw/nova-mind/issues/414)).

### 1. Available Agents

Table showing all active agents:

| Nickname | Role | Model | Description |
|----------|------|-------|-------------|
| Coder | coding | claude-sonnet-4-5 | Code implementation |
| Gidget | git-ops | o4-mini | Git operations |
| ... | ... | ... | ... |

### 2. Active Workflows

For each active workflow: a `###` heading with the workflow name, the workflow description (leading `#` characters escaped so embedded text can't create stray headings), and a step table with **Step / Domains / Description / Deliverable** columns (or "No steps defined for this workflow." if none).

### 3. Spawn Instructions

Per-agent `###` subsections listing Model, Thinking, Context type, Allowed subagents, and Decision criteria (when non-NULL), rebuilt from live `agents` columns — see [Spawn Instructions](#spawn-instructions) above.

## Usage

### Manual Generation
```bash
$HOME/.openclaw/workspace/scripts/generate-delegation-context.sh
# Outputs to ~/.openclaw/workspace/DELEGATION_CONTEXT.md

# Custom output location:
$HOME/.openclaw/workspace/scripts/generate-delegation-context.sh /tmp/custom-context.md
```

### Integration Points

**Session Initialization:**
- Call during agent startup to provide fresh delegation context
- Include in workspace context loading

**Periodic Refresh:**
- Currently manual-only. Database triggers exist (`agents`, `workflows`, `workflow_steps` all fire a `delegation_changed` NOTIFY on change) but **no listener is registered** to consume them and re-run this script — see [Auto-Regeneration](delegation-context-auto-regeneration.md) for the current state of that gap and [#271](https://github.com/NOVA-Openclaw/nova-mind/issues/271) for the tracking issue.

**Heartbeat:**
- Optionally refresh during heartbeat cycles if agent roster changes

## Integration with AGENTS.md

The dynamic delegation context complements static `AGENTS.md` guidance:

- **AGENTS.md**: Static patterns, principles, and general delegation philosophy
- **DELEGATION_CONTEXT.md**: Live roster, current workflows, specific agent capabilities

Both should be loaded together for full delegation awareness.

## Maintenance

**Auto-generated file** - Do not edit `DELEGATION_CONTEXT.md` manually. Changes should be made in the nova-mind database, then the script re-run manually (see [Periodic Refresh](#usage) — auto-regeneration is not currently wired up):

- Update agent definitions in `agents` table
- Modify workflows in `workflows` and `workflow_steps` tables
- Spawn instructions are rebuilt automatically from `agents` columns (`model`, `thinking`, `context_type`, `allowed_subagents`, `decision_criteria`) — there is no separate table to maintain for this section

## Related

- `nova-mind` database schemas: `agents`, `workflows`, `workflow_steps`, `workflow_steps_detail`
- `cognition/scripts/generate-delegation-context.sh` — the script itself
- `tests/install/test_generate_delegation_context.bats` — 18-case regression suite
- [cognition/docs/delegation-context-auto-regeneration.md](delegation-context-auto-regeneration.md) — auto-regeneration status (currently not implemented — manual-only)
- [cognition/README.md](../README.md) — Overview of the cognition subsystem
- [cognition/docs/models.md](models.md) — AI model reference for agent selection
