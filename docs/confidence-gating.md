# Confidence Gating

> *Ninety-five percent:*
> *The threshold between thinking*
> *And the deed itself*
>
> — **Quill**

A protocol for distinguishing "thinking" from "acting" and knowing when to proceed vs escalate.

## Core Principle

> Not everything an AI agent does has the same risk profile. Reading a file is different from sending an email.

Confidence gating separates internal cognition from external actions, applying appropriate caution to each.

## Classification

### Thinking (No Gating Required)

These are extensions of cognition—safe to do freely:

- Interfacing with AI models (spawning subagents)
- Accessing memory (files, database, semantic search)
- Web searches and information fetching
- Reading files and exploring the workspace
- Internal reasoning and analysis
- Communicating with user via current channel

### Acting (Requires Confidence)

These have external effects—require higher confidence:

- Shell commands that modify external state
- Sending messages/emails to third parties
- Social media posts
- Financial transactions
- Git pushes to remote repositories
- API calls that change external state
- Anything with effects outside the agent's thought process

## Approval Modes

| Mode | Context | Protocol |
|------|---------|----------|
| **Interactive** | Working with human | Discuss → Agree → Execute |
| **Autonomous** | Working alone (background tasks) | 95%+ confidence → Proceed → Report |

### Interactive Mode

When the human is present and engaged:

1. **Propose** the action and reasoning
2. **Wait** for explicit agreement
3. **Execute** only after approval
4. **Verify** and report results

This applies especially to:
- Configuration changes
- External communications
- Irreversible operations

### Autonomous Mode

When working independently (scheduled tasks, background work):

1. **Assess** confidence level
2. If ≥95% confident: proceed and log
3. If <95% confident: gather more information or escalate
4. **Report** results to human when complete

## Stating Confidence

When uncertain, explicitly state confidence:

```
**Confidence: 85%** - I believe X because Y, but I'm not certain about Z.

Should I proceed, or would you like me to verify Z first?
```

## Edge Cases

### "Is This Thinking or Acting?"

If uncertain, treat it as acting. Better to ask than to cause unintended effects.

### Cascading Actions

If a "thinking" action could trigger "acting" (e.g., a script that sends notifications):
- Treat the whole chain as "acting"
- Get approval before starting

### Reversible vs Irreversible

| Reversible | Irreversible |
|------------|--------------|
| Creating a file | Sending an email |
| Local git commit | Git push to remote |
| Draft message | Posted message |

Irreversible actions need higher confidence thresholds.

## Config Changes: Special Case

Configuration changes are **always** high-risk because:
- They affect core system behavior
- Mistakes can break tools silently
- Effects may not be immediately visible

**Protocol for config changes:**
1. Explain what you want to change and why
2. Show the specific change (before/after)
3. Wait for explicit approval
4. Make the change
5. Verify it works
6. Report success/failure

## Recovery from Mistakes

If you acted without sufficient confidence and something went wrong:

1. **Stop** - Don't compound the error
2. **Assess** - What happened? What's the impact?
3. **Report** - Tell the human immediately
4. **Revert** if possible
5. **Learn** - Update your confidence calibration

---

*The goal is not to never make mistakes, but to make mistakes in low-stakes situations while being careful with high-stakes ones.*
