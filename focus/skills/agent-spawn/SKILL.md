---
name: agent-spawn
description: "Framework for spawning subagents with dynamic context and workflow integration"
---

# Agent Spawn Skill

Orchestrate task delegation by spawning subagents with focused context. This skill provides the framework for when, how, and with what context to spawn subagents.

## When to Use

Spawn subagents for:

- **Specialized work** — Coding, research, git operations requiring focused attention
- **Parallel execution** — Multiple concurrent research threads or data processing
- **Isolation** — Tasks needing clean context without main session history
- **Long-running tasks** — Work that takes >5 minutes where you want to continue other activities
- **Focused expertise** — Domain-specific tasks better handled by specialist agents

**Don't spawn when:**
- Task is trivial (<1 min, simple query)
- You need immediate back-and-forth dialogue
- Context from main session is critical and hard to summarize
- Peer agent communication is more appropriate (use agent-chat instead)

## Pre-Spawn Checklist

Before spawning, **always**:

1. **Query agent roster** to identify the right agent for the task
2. **Check agent status** to ensure agent is active
3. **Review spawn_instructions** for agent-specific guidance
4. **Determine if jobs system is needed** (usually no for simple delegation)

### 1. Query Agent Roster

```sql
-- Get all available subagents
SELECT 
    nickname, 
    name, 
    role, 
    description,
    status
FROM agents 
WHERE instance_type = 'subagent' 
ORDER BY nickname;
```

### 2. Check Agent Status

```sql
-- Verify agent is active and get spawn instructions
SELECT 
    nickname,
    status,
    model,
    seed_context->'spawn_instructions' as spawn_instructions,
    seed_context->'scope' as scope,
    description
FROM agents 
WHERE nickname = 'AgentNickname';
```

### 3. Review Spawn Instructions

Spawn instructions (stored in `agents.seed_context`) provide critical guidance:

- Required context to include
- Capabilities and limitations
- Domain boundaries
- Special parameters or settings
- Expected deliverable format

**Always read these before spawning.** They're maintained by the agent architect (Newhart) and may contain important constraints.

### 4. Jobs System Decision

| Use Normal Spawn ✓ | Use Jobs System ✓ |
|---------------------|-------------------|
| Quick task (< few min) | Long-running / async work |
| Single deliverable | Progress tracking needed |
| Will wait for result | Context-switching while waiting |
| Standard complete-and-return | Sub-tasks spawning sub-tasks |

**Default to normal spawning.** Jobs add coordination overhead and are only needed for complex async workflows.

## Spawn Procedure

### Step 1: Generate Delegation Context

**If available,** run the delegation context generator:

```bash
~/clawd/nova-cognition/scripts/generate-delegation-context.sh
```

This generates `DELEGATION_CONTEXT.md` with:
- Current agent roster
- Workflow definitions
- Spawn instructions per agent
- Quick reference tables

**If script doesn't exist yet,** query database directly (see Database Queries below).

### Step 2: Identify Correct Agent

Match your task to agent role:

```sql
-- Search by role or description
SELECT nickname, role, description 
FROM agents 
WHERE instance_type = 'subagent' 
  AND status = 'active'
  AND (role ILIKE '%coding%' OR description ILIKE '%code%');
```

### Step 3: Build Task Description

Craft a clear, focused task description with:

#### Required Elements:
- **Clear goal** — What needs to be accomplished?
- **Context** — Background information, file paths, relevant details
- **Expected deliverable** — What format should the result take?
- **Success criteria** — How to know the task is complete?

#### Optional Elements:
- **Workflow position** — If part of multi-agent workflow, explain role
- **Constraints** — Time limits, scope boundaries, don't-do items
- **Follow-up** — What happens after (e.g., "Gidget will commit your changes")

#### Example Task Description:

```
Project: nova-cognition (~/clawd/nova-cognition)

Work issue #5: https://github.com/NOVA-Openclaw/nova-cognition/issues/5

Create the agent-spawn skill at focus/skills/agent-spawn/SKILL.md

Requirements:
- Document when to use subagent spawning
- Include pre-spawn checklist
- Provide spawn procedure with examples
- Include SQL queries inline
- Document workflow integration patterns
- Create feature branch for changes
- Open PR when complete (don't push to main)

Read the issue for full requirements.
```

### Step 4: Spawn the Agent

```javascript
// Using sessions_spawn (OpenClaw/Clawdbot API)
sessions_spawn({
  agentId: "agent-nickname",  // e.g., "coder", "gidget", "scout"
  task: "Your task description here"
});
```

The subagent receives your task as its initial context and works autonomously until complete.

### Step 5: Handle Result

**Normal spawn:**
- Result returns to your session automatically
- Review deliverable
- Integrate into your workflow
- May spawn another agent for follow-up (e.g., Coder → Gidget)

**Jobs system:**
- Job notification arrives when complete
- Check `deliverable_path` and `deliverable_summary` in jobs table
- May require follow-up based on result status

## Database Queries

### Agent Roster (Full Details)

```sql
-- Complete agent roster with capabilities
SELECT 
    nickname,
    name,
    role,
    description,
    model,
    status,
    instance_type,
    seed_context->'spawn_instructions' as spawn_instructions,
    seed_context->'scope' as scope
FROM agents 
WHERE instance_type = 'subagent'
ORDER BY role, nickname;
```

### Workflow Lookup

```sql
-- Find workflows and their participants
SELECT 
    id,
    name,
    description,
    definition->'steps' as steps
FROM workflows
WHERE status = 'active'
ORDER BY name;
```

### Workflow Agents Lookup

```sql
-- Get agents involved in specific workflow
SELECT 
    w.name as workflow_name,
    a.nickname,
    a.role,
    (definition->'steps'->>(jsonb_array_length(definition->'steps')-1))::jsonb->>'agent' as step_agent
FROM workflows w
CROSS JOIN agents a
WHERE w.definition::text LIKE '%' || a.nickname || '%'
  AND a.instance_type = 'subagent'
ORDER BY w.name, a.nickname;
```

### Spawn Instructions Lookup

```sql
-- Get specific agent's spawn instructions
SELECT 
    nickname,
    seed_context->'spawn_instructions'->>'context_requirements' as context_required,
    seed_context->'spawn_instructions'->>'deliverable_format' as deliverable_format,
    seed_context->'spawn_instructions'->>'scope' as scope_notes,
    seed_context->'spawn_instructions'->>'special_parameters' as special_params
FROM agents 
WHERE nickname = 'TargetAgent';
```

### Recent Spawn History

```sql
-- Check recent subagent spawns (if tracking in database)
SELECT 
    session_id,
    agent_id,
    created_at,
    substring(task, 1, 100) as task_preview,
    status
FROM agent_sessions
WHERE session_type = 'subagent'
  AND created_at > now() - interval '24 hours'
ORDER BY created_at DESC
LIMIT 20;
```

## Workflow Integration

When spawning an agent that's part of a defined workflow:

### 1. Identify Workflow Context

```sql
-- Find relevant workflow
SELECT id, name, description, definition 
FROM workflows 
WHERE name ILIKE '%keyword%'
  AND status = 'active';
```

### 2. Understand Agent's Role

Review the workflow steps to understand:
- What input the agent expects
- What deliverable they produce
- Who consumes their output
- What happens after they complete

### 3. Include Workflow Context in Task

```
You are part of the "create-new-agent" workflow.

Your role: Step 2 - Implement agent code
Previous step: Scout completed requirements analysis
Next step: Gidget will commit and create PR

Your deliverable: Working agent code in focus/agents/subagents/<name>/
Expected format: Agent YAML + context seed files + README

Workflow context: This agent will handle [domain] tasks for NOVA.
```

### 4. Coordinate Handoffs

After agent completes:
- Review their deliverable
- Verify it meets next step's input requirements
- Spawn next agent in workflow with appropriate context

**Example workflow chain:**
```
Scout (research) → Coder (implement) → Gidget (commit/PR) → [manual review] → Gidget (merge)
```

## Issue-Driven Development (for Coder)

When spawning Coder for feature work, follow this pattern:

### 1. Create GitHub Issue First

```bash
# Create detailed issue with requirements
gh issue create --repo NOVA-Openclaw/nova-cognition \
  --title "Create agent-spawn skill" \
  --body "Requirements:
- Location: focus/skills/agent-spawn/SKILL.md
- Include: when to use, checklist, procedures
- Format: Match existing skill structure"
```

### 2. Spawn Coder with Issue Reference

```
Project: nova-cognition (~/clawd/nova-cognition)
Work issue #5: https://github.com/NOVA-Openclaw/nova-cognition/issues/5

[Your requirements here]

Create a feature branch for your changes. When done, open a PR (not direct push to main).

Read the issue for full requirements.
```

### 3. Coder's Workflow

Coder will:
1. Read the issue
2. Create feature branch (`feature/issue-5-agent-spawn-skill`)
3. Implement changes
4. Commit to branch
5. Open PR referencing issue
6. Report completion

### 4. PR Review and Merge

After Coder completes:
- Review the PR
- Request changes if needed
- When ready, spawn Gidget to merge: "Merge PR #XX for nova-cognition"

### Why Issue-Driven?

- **Traceability** — Links code to requirements
- **Collaboration** — Others can see what's being worked on
- **History** — GitHub issue becomes permanent record
- **Review** — PR process ensures quality
- **Safety** — No direct pushes to main

## Agent Quick Reference

### Current Subagent Roster

**Note:** This is a static snapshot. Always query the database for current roster.

| Nickname | Role | When to Use | Model Tier |
|----------|------|-------------|------------|
| Coder | coding | Code changes, scripts, implementation work | Specialized |
| Gidget | git-ops | Commits, PRs, merges, git operations | Moderate |
| Scout | research | Domain research, information gathering | Long-context |
| Quill | creative | Creative writing, storytelling, poetry | Creative |
| Curator | media-curation | Media organization, tagging, description | Multimodal |
| QuickQA | quick-tasks | Simple lookups, fast queries, basic Q&A | Fast/cheap |

### Dynamic Roster Query

```sql
-- Generate current roster table
SELECT 
    nickname as "Nickname",
    role as "Role",
    description as "When to Use",
    CASE 
        WHEN model LIKE '%opus%' OR model LIKE '%gpt-4%' THEN 'Premium'
        WHEN model LIKE '%sonnet%' OR model LIKE '%gpt-3.5-turbo-16k%' THEN 'Moderate'
        WHEN model LIKE '%haiku%' OR model LIKE '%gpt-3.5%' THEN 'Fast'
        ELSE 'Unknown'
    END as "Model Tier"
FROM agents 
WHERE instance_type = 'subagent' 
  AND status = 'active'
ORDER BY role, nickname;
```

## Common Patterns

### Pattern: Sequential Work Chain

```javascript
// Step 1: Research
const research = await sessions_spawn({
  agentId: "scout",
  task: "Research best practices for [topic]. Deliverable: Markdown summary."
});

// Step 2: Implement based on research
const code = await sessions_spawn({
  agentId: "coder",
  task: `Implement [feature] based on these findings:\n${research}\n\nCreate feature branch and open PR.`
});

// Step 3: Merge after review
await sessions_spawn({
  agentId: "gidget",
  task: `Merge PR #${code.prNumber} for project nova-cognition`
});
```

### Pattern: Parallel Research

```javascript
// Spawn multiple research threads
const [docs, competitors, bestPractices] = await Promise.all([
  sessions_spawn({
    agentId: "scout",
    task: "Research official documentation for [technology]"
  }),
  sessions_spawn({
    agentId: "scout",
    task: "Research how competitors implement [feature]"
  }),
  sessions_spawn({
    agentId: "scout",
    task: "Research industry best practices for [domain]"
  })
]);

// Synthesize results in main session
const synthesis = synthesizeResearch(docs, competitors, bestPractices);
```

### Pattern: Delegate-Review-Iterate

```javascript
let iteration = 1;
let result;

do {
  result = await sessions_spawn({
    agentId: "coder",
    task: iteration === 1 
      ? "Implement feature X" 
      : `Revise implementation based on feedback: ${feedback}`
  });
  
  feedback = await reviewCode(result);
  iteration++;
} while (feedback && iteration < 3);
```

## Dependencies

- **generate-delegation-context.sh** — Script to generate comprehensive delegation context (Issue #4)
- **agents table** — Database table with agent definitions and spawn_instructions
- **workflows table** — Database table with workflow definitions
- **sessions_spawn** — OpenClaw/Clawdbot API for spawning subagents

## Related

- **agent-chat skill** — For communicating with peer agents (not subagents)
- **Issue #3** — Dynamic delegation context and workflow integration (parent issue)
- **Issue #4** — generate-delegation-context.sh script
- **nova-skills/agent-spawning/SKILL.md** — Reference implementation

## Best Practices

### ✅ Do

- **Query spawn_instructions** before every spawn
- **Be specific** in task descriptions
- **Include file paths** and context
- **State expected deliverable format**
- **Use feature branches** for code work (via issues)
- **Review results** before next step
- **Update agent definitions** when patterns change

### ❌ Don't

- Spawn without checking agent roster
- Assume agent capabilities without querying
- Provide vague task descriptions
- Skip workflow context when relevant
- Push directly to main (use PRs)
- Spawn subagent when peer agent chat is appropriate
- Use jobs system for simple tasks

## Troubleshooting

### "Agent not found"
- Query roster to verify agent nickname
- Check agent status (may be inactive)
- Ensure spelling matches database exactly

### "Agent doesn't understand task"
- Check spawn_instructions for required context format
- Include more specific details and file paths
- Verify task matches agent's scope

### "Deliverable format wrong"
- Review agent's seed_context for deliverable_format
- Specify format explicitly in task description
- Update spawn_instructions if pattern changes

### "Workflow step failed"
- Check previous step's deliverable meets requirements
- Verify workflow definition is current
- May need to adjust agent's understanding of their role

---

**Note:** This skill provides the framework. Agent-specific instructions and workflows are maintained in the database by the agent architect. Always query for latest information before spawning.
