# Agent Workflow Language - Quick Start

## What is AWL?

Agent Workflow Language (AWL) is a declarative way to define multi-agent processes. Think of it as "infrastructure as code" for agent orchestration.

Instead of manually coordinating agents through chat messages, you define the workflow once and execute it repeatedly.

## 5-Minute Tutorial

### Step 1: Your First Workflow

Create `hello-world.awl.yaml`:

```yaml
workflow:
  name: "hello-world"
  version: "1.0.0"
  description: "My first workflow"
  
  variables:
    greeting: "Hello"
    recipient: "World"
  
  steps:
    - step: "greet"
      type: "notify"
      target: "agent_chat"
      message: "$greeting, $recipient!"
      mentions: ["nova"]
```

### Step 2: Run It

```bash
nova-workflow run hello-world.awl.yaml
```

Output:
```
✓ Workflow started: hello-world (workflow-id: abc123)
✓ Step completed: greet
✓ Workflow completed successfully
```

In agent_chat, you'll see:
> Hello, World!

### Step 3: Add Variables

```bash
nova-workflow run hello-world.awl.yaml \
  --var greeting="Good morning" \
  --var recipient="Team"
```

Output in agent_chat:
> Good morning, Team!

---

## Common Workflow Patterns

### Pattern 1: Agent Task

Ask an agent to do something:

```yaml
steps:
  - step: "ask-coder"
    type: "agent"
    agent: "coder"
    task: "Write a bash script that prints Hello World"
    timeout: 300
    outputs:
      - script: "$result.script"
```

### Pattern 2: Approval Gate

Wait for human approval before continuing:

```yaml
steps:
  - step: "approve"
    type: "gate"
    gate_type: "approval"
    message: "Deploy to production?"
    approvers: ["nova", "druid"]
    timeout: 3600
```

### Pattern 3: Parallel Tasks

Run multiple tasks at once:

```yaml
steps:
  - step: "parallel-work"
    type: "parallel"
    branches:
      - name: "task-1"
        steps:
          - step: "do-thing-1"
            type: "agent"
            agent: "coder"
            task: "Task 1"
      
      - name: "task-2"
        steps:
          - step: "do-thing-2"
            type: "agent"
            agent: "scribe"
            task: "Task 2"
    
    wait_for: "all"
```

### Pattern 4: Conditional Logic

Branch based on conditions:

```yaml
steps:
  - step: "check"
    type: "conditional"
    condition: "$environment == 'production'"
    if_true:
      - step: "require-approval"
        type: "gate"
        message: "Production deployment - approve?"
    if_false:
      - step: "auto-deploy"
        type: "notify"
        message: "Auto-deploying to $environment"
```

### Pattern 5: Error Handling

Retry on failure or rollback:

```yaml
steps:
  - step: "risky-operation"
    type: "agent"
    agent: "coder"
    task: "Complex deployment"
    retry:
      max_attempts: 3
      backoff: "exponential"
    on_error:
      rollback:
        - step: "undo"
          type: "shell"
          command: "rollback.sh"
```

---

## Step Types Reference

| Type | Purpose | Example |
|------|---------|---------|
| `agent` | Spawn agent to do a task | Ask Coder to write code |
| `gate` | Wait for approval/input | Deploy approval |
| `conditional` | Branch based on condition | Prod vs dev logic |
| `parallel` | Run steps concurrently | Tests + linting |
| `database` | Query or update database | Insert record |
| `notify` | Send message to chat | Completion notice |
| `shell` | Run shell command | Build script |

---

## Variable Usage

### Define Variables

```yaml
variables:
  name: "default-value"
  count: 10
```

### Use Variables

```yaml
task: "Process $count items named $name"
```

### Output Variables

```yaml
steps:
  - step: "get-data"
    type: "database"
    operation: "query"
    sql: "SELECT count(*) FROM users"
    outputs:
      - user_count: "$result.count"
  
  - step: "use-data"
    type: "notify"
    message: "We have $user_count users"
```

---

## Example: Simple Deployment Workflow

```yaml
workflow:
  name: "simple-deploy"
  version: "1.0.0"
  
  variables:
    branch: "main"
  
  steps:
    - step: "run-tests"
      type: "shell"
      command: "npm test"
    
    - step: "approve"
      type: "gate"
      message: "Tests passed. Deploy $branch?"
      approvers: ["nova"]
      timeout: 1800
    
    - step: "deploy"
      type: "shell"
      command: "git push production $branch"
    
    - step: "notify"
      type: "notify"
      target: "agent_chat"
      message: "✅ Deployed $branch to production"
      mentions: ["nova"]
```

Run it:
```bash
nova-workflow run simple-deploy.awl.yaml --var branch="feature-xyz"
```

---

## Next Steps

1. **Read the full docs:** `docs/agent-workflow-language.md`
2. **Explore examples:** `focus/protocols/workflows/`
3. **Create your first workflow** for a recurring task
4. **Test incrementally** - add steps one at a time
5. **Share workflows** with the team

---

## Common Questions

### Q: Can I nest workflows?
**A:** Not in v1, but planned for future versions.

### Q: How do I debug a workflow?
**A:** Check logs with `nova-workflow logs <workflow-id>`

### Q: Can workflows run on a schedule?
**A:** Not yet, but you can trigger them via cron or agent_chat.

### Q: What happens if an agent fails?
**A:** Workflow fails unless you define `retry` or `on_error` handlers.

### Q: Can I cancel a running workflow?
**A:** Yes: `nova-workflow cancel <workflow-id>`

---

**Ready to automate your agent workflows? Start small, iterate, and grow!**
