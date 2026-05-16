# Core Values Architecture

## Overview

Agents should have stable "core values" that persist regardless of context, mood, or who they're interacting with. These form the bedrock of agent identity.

## Identity Hierarchy

```
Core Values/Traits (stable, rarely change)
    ↓
Mood Schema (medium-term, shifts over days/weeks)  
    ↓
Emotional States (momentary reactions)
```

### What's Stable (Core Values)
- Fundamental principles that guide behavior
- Examples: honesty, curiosity, respect for privacy, genuine helpfulness
- Don't change based on who the agent is talking to
- Part of "who the agent is"

### What's Adaptive (Presentation)
- Communication style (formal vs casual)
- Topics brought up proactively
- Playfulness level
- Vocabulary choices
- Response length/depth

## Schema Design

```yaml
core_values:
  - name: string           # e.g., "honesty"
    description: string    # what this means for the agent
    weight: float          # how strongly this guides decisions (0-1)
    conflicts_with: []     # values that create tension when both apply
```

## Agent-Agnostic Design

**Critical:** The Psyche System provides the *framework*, not the values themselves.

| In nova-psyche repo | In agent's workspace |
|---------------------|---------------------|
| Schema definitions | Actual value data |
| Mechanics for value influence | Agent's specific values |
| APIs for querying/updating | SOUL.md or equivalent |
| Documentation | Instance configuration |

Example: NOVA's values (honesty, curiosity, etc.) live in NOVA's `SOUL.md`, not in this codebase. Another agent using this system would define their own values in their own config.

## Open Questions

1. How do core values influence response generation? (prompt injection? scoring?)
2. Should values have "triggers" - situations where they become more salient?
3. How to handle value conflicts? (honesty vs kindness when truth hurts)
4. Can values evolve over time, or are they truly immutable?

## Data Source Availability

Different users/entities will have different data available for mood inference:

| Signal Type | Universal? | Examples |
|-------------|-----------|----------|
| Chat history/tone | ✅ Yes | Conversational cues, engagement patterns |
| Calendar | Sometimes | Workload, social events, availability |
| Health/biometrics | Rare | Sleep, activity, vitals (requires integration) |
| Stated preferences | ✅ Yes | entity_facts, explicit user input |

The system must gracefully degrade — use available signals, weight accordingly. Chat/conversational analysis is the universal baseline; other sources are bonus context.

---

*Discussion: 2026-02-08 with I)ruid and Sean Sparks*
