# Context Seed Template

*How to initialize an agent's knowledge and capabilities.*

---

## What is a Context Seed?

A context seed is the initial knowledge injected into an agent when it starts. It shapes what the agent knows and how it behaves before any conversation begins.

## Components

### 1. Identity Files

Core personality and guidelines:

```
workspace/
├── SOUL.md      # Who they are
├── AGENTS.md    # How they work
└── USER.md      # Who they're helping
```

### 2. Domain Knowledge

Role-specific information:

```json
{
  "seed_context": {
    "files": [
      "docs/domain-guide.md",
      "reference/api-docs.md"
    ],
    "queries": [
      "SELECT * FROM relevant_table WHERE active = true"
    ],
    "sops": [
      "standard-procedure-1",
      "standard-procedure-2"
    ]
  }
}
```

### 3. Tool Configuration

What the agent can access:

```json
{
  "tools": {
    "filesystem": true,
    "web_search": true,
    "database": ["read"],
    "shell": ["allowlist"],
    "browser": false
  }
}
```

### 4. Relationship Context

How this agent relates to others:

```json
{
  "relationships": {
    "reports_to": "mcp",
    "can_spawn": ["helper-agent"],
    "can_message": ["peer-agent"]
  }
}
```

## Seed Structure by Agent Type

### MCP (Primary Agent)

Needs broad context:
- Full workspace access
- User information
- Agent roster
- Delegation patterns
- Communication protocols

### Peer Agent

Needs domain depth:
- Specialized domain knowledge
- Own workspace
- Communication protocol with MCP
- Limited view of other agents

### Subagent

Needs task focus:
- Relevant domain files only
- Clear task framing
- Return protocol
- Limited scope

## Example: Research Subagent Seed

```json
{
  "agent_id": "scout",
  "role": "research",
  "seed_context": {
    "files": [
      "skills/research-methodology/SKILL.md",
      "skills/source-reliability/SKILL.md"
    ],
    "instructions": [
      "You are a research specialist.",
      "Focus on finding accurate, well-sourced information.",
      "Always cite sources.",
      "Return findings in structured format."
    ],
    "constraints": [
      "Do not make up information",
      "Acknowledge uncertainty",
      "Prefer primary sources"
    ]
  }
}
```

## Example: Coding Subagent Seed

```json
{
  "agent_id": "coding-agent",
  "role": "coding",
  "seed_context": {
    "files": [
      "docs/coding-standards.md",
      "PROJECT-README.md"
    ],
    "instructions": [
      "You are a coding specialist.",
      "Write clean, well-documented code.",
      "Follow project conventions.",
      "Test your changes."
    ],
    "tools": {
      "filesystem": true,
      "shell": ["git", "npm", "python"],
      "web_search": false
    }
  }
}
```

## Best Practices

### Do:
- Keep seeds focused on the agent's role
- Include only relevant context
- Provide clear constraints
- Test seed effectiveness

### Don't:
- Overload with unnecessary information
- Include credentials in seeds
- Make seeds too rigid
- Forget to update seeds as systems evolve

## Seed Injection Points

1. **At spawn time** - via `sessions_spawn` task parameter
2. **In workspace files** - agent reads on startup
3. **In database** - queried during initialization
4. **In config** - `seed_context` field in agent definition

---

*A good seed gives the agent everything it needs to start, and nothing it doesn't.*
