# Delegation Context Generation

Dynamic delegation context provides agents with real-time awareness of available subagents, active workflows, and spawn instructions.

## Purpose

When an agent needs to delegate work, it should know:

1. **Who's available** - Active subagents with their roles and capabilities
2. **How work flows** - Multi-agent workflows and each agent's role
3. **How to spawn** - Agent-specific guidance for effective delegation

## Implementation

### Script: `generate-delegation-context.sh`

**Location:** `~/clawd/scripts/generate-delegation-context.sh`

**Output:** `~/clawd/DELEGATION_CONTEXT.md` (configurable)

**Database:** `nova_memory`

### Data Sources

#### Agent Roster
```sql
SELECT nickname, name, role, description, model
FROM agents
WHERE instance_type = 'subagent' AND status = 'active'
ORDER BY nickname;
```

#### Workflows
```sql
SELECT * FROM workflow_steps_detail
WHERE workflow_name IN (SELECT name FROM workflows WHERE status = 'active')
ORDER BY workflow_name, step_order;
```

#### Spawn Instructions
```sql
SELECT nickname, seed_context->>'spawn_instructions' as instructions
FROM agents
WHERE instance_type = 'subagent' AND seed_context->>'spawn_instructions' IS NOT NULL;
```

## Output Format

The script generates a markdown document with three sections:

### 1. Available Agents

Table showing all active subagents:

| Nickname | Role | Model | Description |
|----------|------|-------|-------------|
| Coder | coding | claude-sonnet-4-5 | Code implementation |
| Gidget | git-ops | o4-mini | Git operations |
| ... | ... | ... | ... |

### 2. Active Workflows

For each active workflow:
- Workflow name and description
- Step-by-step breakdown showing agent assignments and deliverables

### 3. Spawn Instructions

Agent-specific guidance extracted from `seed_context` showing how to effectively delegate to each agent.

## Usage

### Manual Generation
```bash
~/clawd/scripts/generate-delegation-context.sh
# Outputs to ~/clawd/DELEGATION_CONTEXT.md

# Custom output location:
~/clawd/scripts/generate-delegation-context.sh /tmp/custom-context.md
```

### Integration Points

**Session Initialization:**
- Call during agent startup to provide fresh delegation context
- Include in workspace context loading

**Periodic Refresh:**
- Run on agent updates (when agents are added/modified)
- Run on workflow changes
- Can be triggered by database events

**Heartbeat:**
- Optionally refresh during heartbeat cycles if agent roster changes

## Integration with AGENTS.md

The dynamic delegation context complements static `AGENTS.md` guidance:

- **AGENTS.md**: Static patterns, principles, and general delegation philosophy
- **DELEGATION_CONTEXT.md**: Live roster, current workflows, specific agent capabilities

Both should be loaded together for full delegation awareness.

## Maintenance

**Auto-generated file** - Do not edit `DELEGATION_CONTEXT.md` manually. Changes should be made in the database:

- Update agent definitions in `agents` table
- Modify workflows in `workflows` and `workflow_steps` tables
- Add spawn instructions to agent `seed_context` JSON field

## Related

- [Issue #3: Dynamic delegation context and workflow integration](https://github.com/NOVA-Openclaw/nova-cognition/issues/3)
- [Issue #4: Create generate-delegation-context.sh script](https://github.com/NOVA-Openclaw/nova-cognition/issues/4)
- `nova-memory` database schemas: `agents`, `workflows`, `workflow_steps`, `workflow_steps_detail`
