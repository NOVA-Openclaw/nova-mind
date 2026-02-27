# Agent Registry

How to structure and organize agents in a cognition system.

## Agent Types

| Type | Description | Lifecycle |
|------|-------------|-----------|
| **primary** | Main orchestrator (MCP) | Always running |
| **peer** | Independent agents with own context | Persistent, separate process |
| **subagent** | Task-focused extensions of MCP | On-demand or persistent |

## Type Details

### Primary Agent (MCP)

The Master Control Program. Orchestrates all other agents, handles user interaction, manages delegation.

- Single instance per deployment
- Highest-capability model recommended
- Maintains conversation context with user
- Decides when to delegate vs handle directly

### Peer Agents

Independent agents with their own context windows and persistence.

- Separate processes/instances
- Communication via messaging protocol (not spawning)
- Have domain expertise the MCP consults
- Examples: Agent architect, system administrator, domain specialist

### Subagents

Task-focused extensions of the MCP's thinking.

- Spawned on-demand or kept persistent
- Share context inheritance from MCP
- Return results to MCP for synthesis
- Examples: Research, coding, git operations, creative work, media curation

## Example Roster Structure

```yaml
agents:
  primary:
    - role: general
      model: premium-reasoning-model
      persistent: true
      
  peers:
    - role: meta/architecture
      model: premium-reasoning-model
      notes: "Designs and manages other agents"
      
  subagents:
    - role: research
      model: fast-long-context-model
      persistent: false
      
    - role: coding
      model: code-specialized-model
      persistent: true
      
    - role: git-ops
      model: moderate-model
      persistent: false
      
    - role: media-curation
      model: fast-multimodal-model
      persistent: false
      
    - role: creative
      model: creative-model
      persistent: false
      
    - role: quick-qa
      model: fast-cheap-model
      persistent: false
```

## Delegation Patterns

### When to Spawn a Subagent

- Task requires specialized focus (research, coding, creative work)
- Parallel execution would help (multiple research threads)
- Task might take a while and you want to continue other work

### When to Message a Peer Agent

- Task requires their domain expertise
- Decision needs collaborative input
- Task affects their systems or responsibilities

### Example Flows

**Research Task:**
```
User asks complex question
  → MCP spawns research subagent
  → Subagent researches, returns findings
  → MCP synthesizes and responds
```

**Architecture Change:**
```
Need to modify an agent's config
  → MCP messages architecture peer via protocol
  → Peer reviews and implements
  → Peer confirms completion
```

**Code Change:**
```
Feature needs implementation
  → MCP spawns coding subagent
  → Subagent writes code
  → MCP spawns git-ops subagent for commit/push
```

## Persistence Guidelines

| Persistent | Use When |
|------------|----------|
| ✅ Yes | Agent is used frequently, startup cost is high, maintains important state |
| ❌ No | Agent is used occasionally, stateless tasks, resource conservation |

---

*See [models.md](../docs/models.md) for model selection guidance.*
