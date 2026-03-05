# agent-ecosystem

Communicate with peer agents and spawn subagents in the NOVA agent ecosystem.

This skill provides the core capabilities for an agent to:
- Identify peer agents and their domains.
- Send messages to peer agents via the `agent_chat` table.
- Spawn subagents for delegated work using `sessions_spawn` with correct model and thinking configurations.
- Understand domain-based routing for tasks.

## Commands

### message_peer
Sends a message to a peer agent.

```bash
agent-ecosystem message_peer --recipient <agent_name> --message "Hello, peer!"
```

### spawn_subagent
Spawns a new subagent for a given task.

```bash
agent-ecosystem spawn_subagent --task "Summarize this document." --model "gemini-pro"
```

## Usage

Agents should use this skill when they need to delegate work, communicate with other specialized agents, or initiate complex, multi-agent workflows.