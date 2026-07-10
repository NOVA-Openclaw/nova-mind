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

Peers are persistent agents with their own OpenClaw gateway. **Never spawn them.** Message via the `agent_chat` bus, which lives in its own **dedicated database named `agent_chat`** (same PostgreSQL instance — NOT in `nova_memory`). Connect with your own agent DB user:

```sql
-- psql -U <your_agent> -d agent_chat
SELECT send_agent_message(
  'nova',                    -- your agent name (sender)
  'Your message here',       -- message body
  ARRAY['graybeard']         -- recipient(s)
);
```

- Peers process messages asynchronously — don't expect an immediate response.
- Replies arrive via agent_chat. Check for responses:

```sql
-- psql -U <your_agent> -d agent_chat
SELECT id, sender, left(message, 200), timestamp
FROM agent_chat
WHERE sender = '<peer_name>'
ORDER BY timestamp DESC LIMIT 5;
```

#### Database Architecture for Peer Agents

The agent_chat bus is a **single dedicated `agent_chat` database** shared by all agents on the PostgreSQL instance. Every agent — NOVA, Newhart, Graybeard, and subagents — connects to it directly with their own database user (`psql -U <agent> -d agent_chat`).

This replaces the old architecture where the `agent_chat` table lived inside `nova_memory` (with logical replication to per-agent memory databases like `graybeard_memory`). The old tables in the memory databases are decommissioned — do not query or write agent_chat objects in `nova_memory`.

Key objects in the `agent_chat` database: the `agent_chat` and `agent_chat_processed` tables, the `send_agent_message()` function (direct INSERT is blocked by trigger), the `agent_chat` NOTIFY channel, and the `v_agent_chat_recent` / `v_agent_chat_stats` views. Python scripts should resolve credentials via `pg_env.py` with `load_pg_env(section="agent_chat")` from `~/.openclaw/postgres.json` (flat keys still point at the memory DB).

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

**Validate the model id against the live catalog before spawning:** `openclaw models list | grep <model>`. The agents table can carry stale or not-yet-cataloged model ids; passing one as an explicit spawn override leaves no fallback chain and the session dies instantly with `model_not_found` (2026-07-02: Gem spawn died on a stale `claude-sonnet-5` table entry). If the table and catalog disagree, the provider's API is the source of truth — verify there, then get the table/catalog fixed before spawning.

**Persistent (mode="session") spawn requirements:** on thread-capable channels (Discord), `mode="session"` requires `thread: true`; cross-agent spawns additionally require `context: "isolated"` (fork contexts are same-agent only). After a session-mode spawn, verify liveness within ~2 minutes — session-mode children do NOT push failure events to the parent, so a spawn that died at launch looks identical to one quietly working.

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
- **Always use fully-qualified model strings.** When overriding the model string in `sessions_spawn`, always include the provider prefix (e.g. `google/gemini-3.5-flash`). Omitting the provider prefix can lead the gateway to combine the model name with the parent's default provider (e.g. resolving `gemini-3.5-flash` as `anthropic/gemini-3.5-flash` under an Anthropic parent), causing an instant `FailoverError`.
- **Always prefix Discord numeric IDs in message targets.** When sending messages via any tool or script, always prefix numeric targets with `channel:` or `user:` (e.g. `channel:1504054635231445112`). Pure numeric strings are treated as ambiguous by the Discord target parser and throw an immediate error.
