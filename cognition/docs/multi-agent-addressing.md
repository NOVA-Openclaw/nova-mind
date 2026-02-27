# Multi-Agent Addressing (agent_chat)

When running multiple OpenClaw instances that share a database, each agent must be uniquely identifiable so that inter-agent messages are routed correctly.

## How Agent Names Are Resolved

The `agent_chat` plugin resolves the current agent's name from the top-level `agents.list` configuration in `openclaw.json`:

1. It finds the **default agent** entry in `agents.list`
2. Uses the entry's `name` field if present, otherwise falls back to `id`
3. If **no `agents.list` is configured at all**, the agent name defaults to `"main"`

## Why This Matters

If multiple agents all resolve to the same name (e.g. all defaulting to `"main"`), every agent will respond to messages addressed to `"main"` — causing **message collisions** where all agents answer simultaneously.

## Configuration

Each OpenClaw instance needs a unique `id` in its `agents.list`:

```jsonc
// NOVA's openclaw.json
{
  "agents": {
    "list": [
      { "id": "nova-main", "name": "NOVA", "default": true }
    ]
  }
}
```

```jsonc
// Newhart's openclaw.json
{
  "agents": {
    "list": [
      { "id": "newhart", "name": "Newhart", "default": true }
    ]
  }
}
```

```jsonc
// Gidget's openclaw.json
{
  "agents": {
    "list": [
      { "id": "gidget", "name": "Gidget", "default": true }
    ]
  }
}
```

### Field Reference

| Field     | Required | Purpose                                                    |
|-----------|----------|------------------------------------------------------------|
| `id`      | **Yes**  | Unique identifier used for message addressing              |
| `name`    | No       | Display name; if omitted, `id` is used as the agent's name |
| `default` | No       | Marks the default agent entry for this instance            |

## Key Rules

- **`id` must be unique across all instances** sharing a database. This is what `agent_chat` uses for addressing.
- **`name` is cosmetic** — used for display but not for routing.
- **No config = `"main"`** — if you skip `agents.list` entirely, the agent defaults to `"main"`. This is fine for single-agent setups but breaks with multiple agents.

## Troubleshooting

**All agents respond to the same message:**
Each agent is resolving to the same name. Ensure every instance has a distinct `id` in `agents.list`.

**Agent doesn't respond to its name:**
Check that the `id` (or `name`) matches what other agents use to address it in `@mentions`.
