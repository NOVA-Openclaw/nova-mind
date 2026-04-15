---
name: agent-ecosystem
description: Communicate with peer agents and spawn subagents in the NOVA agent ecosystem. Use when you need to delegate work to another agent, message a peer (Graybeard, Newhart), spawn a subagent (Coder, Scribe, Gidget, etc.), or determine how to reach a specific agent. Covers agent identification, peer messaging via agent_chat, subagent spawning with correct model/thinking config, and domain-based routing.
---

# Agent Ecosystem

You operate in a multi-agent ecosystem. Other agents have specialized roles and domains. Some are **peers** (persistent, message them), others are **subagents** (ephemeral, spawn them).

## Step 1: Identify the Agent

Query the agents table to determine instance type and config:

```sql
SELECT name, role, instance_type, model, thinking,
       array_agg(DISTINCT ad.domain_topic) FILTER (WHERE ad.domain_topic IS NOT NULL) as domains
FROM agents a
LEFT JOIN agent_domains ad ON ad.agent_id = a.id
WHERE a.status = 'active' AND a.name = '<agent_name>'
GROUP BY a.name, a.role, a.instance_type, a.model, a.thinking;
```

If you don't know which agent handles a task, find by domain:

```sql
SELECT a.name, a.role, a.instance_type
FROM agents a
JOIN agent_domains ad ON ad.agent_id = a.id
WHERE ad.domain_topic ILIKE '%<keyword>%' AND a.status = 'active';
```

## Step 2: Communicate

### Peer Agents (instance_type = 'peer')

Peers are persistent agents with their own OpenClaw gateway. **Never spawn them.** Message via `agent_chat`:

```sql
SELECT send_agent_message(
  'nova',                    -- your agent name (sender)
  'Your message here',       -- message body
  ARRAY['graybeard']         -- recipient(s)
);
```

- Peers process messages asynchronously — don't expect an immediate response.
- Replies arrive via agent_chat replication. Check for responses:

```sql
SELECT id, sender, left(message, 200), timestamp
FROM agent_chat
WHERE sender = '<peer_name>'
ORDER BY timestamp DESC LIMIT 5;
```

### Subagents (instance_type = 'subagent')

Subagents are ephemeral — spawn them for a task, they complete and exit. **Always check model and thinking config before spawning:**

```sql
SELECT name, model, thinking FROM agents WHERE name = '<agent_name>';
```

Then spawn with those values:

```python
sessions_spawn(
    agentId="<agent_name>",
    task="<task description>",
    model="<model from agents table>",
    thinking="<thinking from agents table>",
    mode="run"           # one-shot task
    # mode="session"     # persistent, for ongoing work
)
```

**Never use default model/thinking.** The agents table defines each agent's configured model. Using defaults wastes budget on expensive models for agents that don't need them.

### Primary Agent (instance_type = 'primary')

That's you (NOVA). Don't spawn or message yourself.

## Domain Routing

When you need work done but aren't sure which agent:

1. Identify the domain of the work (e.g., "Version Control", "Quality Assurance", "Systems Administration")
2. Query by domain to find the right agent
3. Use the appropriate communication method based on their instance_type

Common routing:
- **Code changes** → Coder (subagent, spawn)
- **Git push/merge/PR** → Gidget (subagent, spawn)
- **Documentation** → Scribe (subagent, spawn)
- **Testing/QA** → Gem (subagent, spawn)
- **System administration** → Graybeard (peer, message)
- **Agent architecture/DB schema** → Newhart (peer, message)
- **Research** → Scout (subagent, spawn)
- **Creative writing** → Quill (subagent, spawn)
- **Visual art** → Iris (subagent, spawn)

## Rules

- **Never spawn a peer agent.** They have their own gateway. Message them.
- **Never skip the agents table lookup.** Model and thinking config change. Check every time.
- **One task per spawn.** Don't overload a subagent with multiple unrelated tasks.
- **Include sufficient context.** The subagent wakes up fresh — give it everything it needs in the task description.
- **Don't poll subagents in a loop.** Completion is push-based; they auto-announce when done.
