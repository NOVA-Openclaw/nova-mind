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
- Replies arrive via agent_chat. Check for responses:

```sql
SELECT id, sender, left(message, 200), timestamp
FROM agent_chat
WHERE sender = '<peer_name>'
ORDER BY timestamp DESC LIMIT 5;
```

#### Database Architecture for Peer Agents

> **Updated for nova-mind#320.** `agent_chat` now lives in its own dedicated `agent_chat`
> database, separate from every agent's `nova_memory`-equivalent memory database. All
> agents — regardless of which memory database they otherwise use (Newhart's `nova_memory`,
> Graybeard's `graybeard_memory`, etc.) — connect to this **same** `agent_chat` database
> directly for messaging. The two-architecture split described below (shared vs.
> cross-database logical replication) is the pre-#320 design and is kept for historical
> reference; it no longer describes how peer messaging works. Do not set up or expect
> `agent_chat` logical replication on a #320-or-later install — see
> `scripts/agent-chat-migration/README.md` and `memory/docs/database-config.md`.

Not all peers share the same *memory* database. There were historically two architectures
for `agent_chat` specifically (both superseded by the single shared `agent_chat` database
above):

1. **Shared database** — The peer agent connects to the same `nova_memory` database (e.g., Newhart). Messages appeared instantly in the same `agent_chat` table.

2. **Replicated database** — The peer agent had its own separate database (e.g., Graybeard uses `graybeard_memory`). The `agent_chat` table was bidirectionally replicated between databases via PostgreSQL logical replication. When Graybeard wrote to `graybeard_memory.agent_chat`, it replicated to `nova_memory.agent_chat` and vice versa.

**Neither architecture above is current for `agent_chat`.** As of #320, do not assume a peer's `agent_chat` messages live in their memory database at all — they live in the shared dedicated `agent_chat` database instead.

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
