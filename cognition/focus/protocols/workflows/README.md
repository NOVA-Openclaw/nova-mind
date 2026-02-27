# Agent Workflow Language - Example Workflows

This directory contains example workflows demonstrating various AWL features and patterns.

## Available Workflows

### 1. create-new-agent.awl.yaml
**Purpose:** Complete agent onboarding process

**Demonstrates:**
- Sequential steps with agent spawning
- Human approval gates
- Database operations
- Parallel execution (dashboard + docs)
- Variable interpolation
- Error handling and rollback
- Success/failure hooks

**Workflow:**
1. Design agent (Newhart)
2. Human approval gate
3. Insert into database
4. Parallel: Update dashboard + Create docs
5. Verify insertion
6. Announce completion

**Usage:**
```bash
nova-workflow run workflows/create-new-agent.awl.yaml \
  --var requirements="Design a monitoring agent for system health" \
  --var requester="druid"
```

---

### 2. code-review-deploy.awl.yaml
**Purpose:** Automated code review and deployment pipeline

**Demonstrates:**
- Shell command execution
- Conditional branching (test pass/fail)
- Parallel security + quality checks
- Agent code review
- Retry logic with backoff
- Deployment rollback on failure
- Multi-stage approval process

**Workflow:**
1. Run automated tests
2. If tests fail → notify and exit
3. Parallel: Security scan + Linter
4. Agent code review (Coder)
5. Human approval gate
6. Deploy to production (with rollback)
7. Post-deployment verification
8. Success notification

**Usage:**
```bash
nova-workflow run workflows/code-review-deploy.awl.yaml \
  --var branch="feature/new-api" \
  --var pr_number="142" \
  --var requester="nova"
```

---

### 3. weekly-system-review.awl.yaml
**Purpose:** Automated weekly system health and performance review

**Demonstrates:**
- Multiple database queries
- Parallel agent analysis
- Report generation and distribution
- Conditional alerts based on thresholds
- Database logging of results

**Workflow:**
1. Gather system metrics (sessions, tokens, etc.)
2. Check agent activity
3. Identify pending tasks
4. Check error logs
5. Parallel analysis: Performance + Tasks + Errors
6. Generate comprehensive report (Scribe)
7. Distribute report via agent_chat
8. Create alerts if thresholds exceeded

**Usage:**
```bash
nova-workflow run workflows/weekly-system-review.awl.yaml \
  --var review_period_days=7 \
  --var report_recipients="nova,druid"
```

---

## Common Patterns

### Agent Task Pattern
```yaml
- step: "task-name"
  type: "agent"
  agent: "agent-name"
  task: "Description of task with $variables"
  timeout: 300
  outputs:
    - result_var: "$result.field"
```

### Approval Gate Pattern
```yaml
- step: "approval"
  type: "gate"
  gate_type: "approval"
  message: "What needs approval?"
  approvers: ["nova", "druid"]
  timeout: 3600
  on_reject: "fail"
```

### Parallel Execution Pattern
```yaml
- step: "parallel-tasks"
  type: "parallel"
  branches:
    - name: "branch-1"
      steps: [...]
    - name: "branch-2"
      steps: [...]
  wait_for: "all"
```

### Conditional Pattern
```yaml
- step: "check-condition"
  type: "conditional"
  condition: "$variable == 'value'"
  if_true: [...]
  if_false: [...]
```

### Error Handling Pattern
```yaml
- step: "risky-operation"
  type: "agent"
  retry:
    max_attempts: 3
    backoff: "exponential"
  on_error:
    rollback: [...]
```

---

## Creating New Workflows

1. **Start with a template** or copy an existing workflow
2. **Define variables** that will be passed at runtime
3. **Design steps** in logical sequence
4. **Add error handling** for critical steps
5. **Include notifications** for completion/failure
6. **Test incrementally** before deploying

---

## Validation

Validate workflow syntax before execution:

```bash
nova-workflow validate workflows/your-workflow.awl.yaml
```

---

## Best Practices

1. **Name steps clearly** - Use descriptive step names
2. **Use variables** - Avoid hardcoding values
3. **Add timeouts** - Prevent workflows from hanging
4. **Handle errors** - Always define error handling for critical steps
5. **Document variables** - Explain what each variable is for
6. **Version workflows** - Increment version on breaking changes
7. **Test in isolation** - Test each step independently first
8. **Monitor executions** - Review logs regularly
9. **Keep workflows focused** - One workflow, one purpose
10. **Use approval gates wisely** - Not every step needs human approval

---

## Troubleshooting

### Workflow fails at step X
Check execution logs:
```bash
nova-workflow logs <workflow-id>
```

### Variable not interpolated
Ensure variable is defined in `variables:` section or output from previous step.

### Gate timeout
Increase gate timeout or notify approvers earlier in workflow.

### Parallel steps blocking
Check `wait_for` setting - use "any" or "first" if not all branches critical.

---

For full documentation, see: `~/clawd/nova-cognition/docs/agent-workflow-language.md`
