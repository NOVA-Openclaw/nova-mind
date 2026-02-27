# Agent Workflow Language - Getting Started Guide

> *YAML choreographs*
> *Agents branch and merge as one*
> *Complex, made simple*
>
> — **Quill**

**🚀 From zero to your first AWL workflow in 15 minutes**

This guide shows you how to integrate and use the Agent Workflow Language (AWL) in your nova-cognition system. AWL lets you orchestrate complex multi-agent processes using declarative YAML workflows.

## Prerequisites

Before you start, ensure you have:

- [ ] **nova-cognition** installed and running
- [ ] At least **one agent** (like `newhart` or `scribe`) available for tasks
- [ ] **Database access** (PostgreSQL with nova_memory schema)
- [ ] **Agent chat system** configured (for notifications)
- [ ] Basic familiarity with **YAML** syntax

## Quick Setup Verification

Verify your environment is ready:

```bash
# 1. Check agents are available
nova-session list agents

# 2. Verify database connection
psql nova_memory -c "SELECT count(*) FROM agents;"

# 3. Test agent spawning
nova-session spawn newhart "Hello, just testing!"

# 4. Check workflow directory exists
ls ~/clawd/nova-cognition/focus/protocols/workflows/
```

If any of these fail, see the [Troubleshooting](#troubleshooting) section.

---

## Your First Workflow: Hello World

Let's start with the simplest possible workflow - having an agent say hello.

### Step 1: Create the workflow file

Create `~/clawd/nova-cognition/focus/protocols/workflows/getting-started/hello-world.awl.yaml`:

```yaml
workflow:
  name: "hello-world"
  version: "1.0.0"
  description: "Your first AWL workflow - agent says hello"
  author: "you"
  
  variables:
    name: "World"
    agent_name: "newhart"
  
  steps:
    - step: "say-hello"
      type: "agent"
      agent: "$agent_name"
      task: "Say hello to $name in a friendly way"
      timeout: 30
      outputs:
        - greeting: "$result"
    
    - step: "announce-result"
      type: "notify"
      target: "agent_chat"
      message: "🎉 Workflow complete! Agent said: $greeting"
```

### Step 2: Run your first workflow

```bash
# Basic execution
nova-workflow run workflows/getting-started/hello-world.awl.yaml

# With custom variables
nova-workflow run workflows/getting-started/hello-world.awl.yaml \
  --var name="Nova" \
  --var agent_name="scribe"
```

### Step 3: What happened?

1. **NOVA** parsed your workflow YAML
2. **Step 1** spawned the `newhart` agent with task "Say hello to World in a friendly way"
3. **Agent** completed the task and returned a result
4. **Step 2** extracted the result and sent a notification to agent_chat
5. **Workflow** completed successfully

**🎉 Congratulations!** You just ran your first AWL workflow.

---

## Example 2: Multi-Step Task with Approval

Let's build something more realistic - a workflow that gets approval before doing work.

Create `~/clawd/nova-cognition/focus/protocols/workflows/getting-started/write-with-approval.awl.yaml`:

```yaml
workflow:
  name: "write-with-approval"
  version: "1.0.0"
  description: "Write content with human approval gate"
  author: "you"
  
  variables:
    topic: "AI and the future"
    approver: "nova"
  
  steps:
    # Step 1: Create initial draft
    - step: "create-draft"
      type: "agent"
      agent: "scribe"
      task: |
        Write a brief 2-paragraph introduction about: $topic
        
        Make it engaging and informative.
      timeout: 300
      outputs:
        - draft_content: "$result"
    
    # Step 2: Human approval gate
    - step: "review-approval"
      type: "gate"
      gate_type: "approval"
      message: |
        📝 Draft ready for review:
        
        Topic: $topic
        Content: $draft_content
        
        Approve for publication?
      approvers: ["$approver"]
      timeout: 1800  # 30 minutes
      on_reject: "fail"
    
    # Step 3: Finalize (only if approved)
    - step: "finalize-content"
      type: "agent"
      agent: "scribe"
      task: |
        Polish this approved content and format it nicely:
        
        $draft_content
      timeout: 180
      outputs:
        - final_content: "$result"
    
    # Step 4: Success notification
    - step: "notify-completion"
      type: "notify"
      target: "agent_chat"
      message: |
        ✅ Content creation workflow complete!
        
        Topic: $topic
        Final content: $final_content
      mentions: ["$approver"]
  
  # Handle workflow-level events
  on_success:
    - type: "log"
      message: "Content creation successful for topic: $topic"
  
  on_failure:
    - type: "notify"
      target: "agent_chat"
      message: "❌ Content creation failed: $error_message"
      mentions: ["$approver"]
```

### Run it:

```bash
nova-workflow run workflows/getting-started/write-with-approval.awl.yaml \
  --var topic="Machine learning basics" \
  --var approver="your-name"
```

### What's new here?

- **Multiple steps** that build on each other
- **Human approval gate** that pauses workflow
- **Variable passing** between steps using `$result`
- **Conditional execution** (step 3 only runs if approved)
- **Workflow-level error handling** with `on_success` and `on_failure`

---

## Example 3: Parallel Tasks

Real workflows often need to do multiple things at once. Here's how:

Create `~/clawd/nova-cognition/focus/protocols/workflows/getting-started/parallel-research.awl.yaml`:

```yaml
workflow:
  name: "parallel-research"
  version: "1.0.0"
  description: "Research a topic from multiple angles simultaneously"
  author: "you"
  
  variables:
    research_topic: "quantum computing"
  
  steps:
    # Step 1: Parallel research from different angles
    - step: "research-parallel"
      type: "parallel"
      branches:
        - name: "technical-research"
          steps:
            - step: "technical-analysis"
              type: "agent"
              agent: "newhart"
              task: |
                Research the technical aspects of $research_topic.
                Focus on: how it works, current capabilities, limitations.
              timeout: 300
              outputs:
                - tech_findings: "$result"
        
        - name: "business-research"
          steps:
            - step: "business-analysis"
              type: "agent"
              agent: "scribe"
              task: |
                Research the business/commercial aspects of $research_topic.
                Focus on: market size, applications, companies involved.
              timeout: 300
              outputs:
                - business_findings: "$result"
        
        - name: "trend-research"
          steps:
            - step: "trend-analysis"
              type: "agent"
              agent: "newhart"
              task: |
                Research recent trends and future predictions for $research_topic.
                Focus on: what's new, what's coming, expert opinions.
              timeout: 300
              outputs:
                - trend_findings: "$result"
      
      wait_for: "all"  # Wait for ALL branches to complete
    
    # Step 2: Synthesize findings
    - step: "synthesize-research"
      type: "agent"
      agent: "scribe"
      task: |
        Create a comprehensive research summary combining these findings:
        
        Technical: $tech_findings
        Business: $business_findings  
        Trends: $trend_findings
        
        Create a well-structured report with sections for each area.
      timeout: 600
      outputs:
        - final_report: "$result"
    
    # Step 3: Share results
    - step: "share-results"
      type: "notify"
      target: "agent_chat"
      message: |
        🔬 Research complete: $research_topic
        
        $final_report
```

### Run it:

```bash
nova-workflow run workflows/getting-started/parallel-research.awl.yaml \
  --var research_topic="sustainable energy"
```

### Key concepts:

- **Parallel execution** with `type: "parallel"`
- **Multiple branches** running simultaneously  
- **wait_for: "all"** ensures all branches complete before continuing
- **Variable access** from parallel branches in later steps

---

## Common Integration Patterns

### 1. Database Operations

Many workflows need to interact with your database:

```yaml
- step: "check-user-exists"
  type: "database"
  operation: "query"
  sql: "SELECT count(*) as user_count FROM users WHERE email = '$user_email'"
  database: "nova_memory"
  outputs:
    - user_exists: "$result.user_count > 0"

- step: "conditional-user-creation"
  type: "conditional"
  condition: "!$user_exists"
  if_true:
    - step: "create-user"
      type: "database"
      operation: "execute"
      sql: "INSERT INTO users (email, name) VALUES ('$user_email', '$user_name')"
      database: "nova_memory"
```

### 2. Error Handling and Retries

For unreliable operations, add retry logic:

```yaml
- step: "api-call"
  type: "agent"
  agent: "newhart"
  task: "Call external API to get weather data for $city"
  timeout: 60
  retry:
    max_attempts: 3
    backoff: "exponential"
    backoff_base: 2
  on_error:
    - step: "fallback-weather"
      type: "agent"
      agent: "scribe"
      task: "Generate a polite message that weather data is unavailable"
```

### 3. Shell Commands

For system integration:

```yaml
- step: "backup-database"
  type: "shell"
  command: "pg_dump nova_memory > /backups/$(date +%Y%m%d).sql"
  working_dir: "/home/nova"
  timeout: 300
  on_error: "warn"  # Don't fail entire workflow if backup fails
```

### 4. Conditional Logic

Make decisions based on previous results:

```yaml
- step: "check-environment"
  type: "database"
  operation: "query"
  sql: "SELECT environment FROM config LIMIT 1"
  outputs:
    - env: "$result.environment"

- step: "environment-specific-deploy"
  type: "conditional"
  condition: "$env == 'production'"
  if_true:
    - step: "production-deploy"
      type: "agent"
      agent: "coder"
      task: "Deploy with production safeguards"
  if_false:
    - step: "staging-deploy"
      type: "shell"
      command: "npm run deploy-staging"
```

---

## Integration with Your Agent System

### Adding AWL to Existing Agents

Your existing agents can trigger workflows:

```python
# In your agent code
def trigger_workflow(self, workflow_name, variables=None):
    """Trigger an AWL workflow from agent code"""
    import subprocess
    import json
    
    cmd = ["nova-workflow", "run", f"workflows/{workflow_name}.awl.yaml"]
    
    if variables:
        for key, value in variables.items():
            cmd.extend(["--var", f"{key}={value}"])
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stdout

# Example usage
success, output = self.trigger_workflow("create-new-agent", {
    "requirements": "Design a monitoring agent",
    "requester": self.session_id
})
```

### Workflow-Triggered Agent Spawning

AWL can spawn your agents with specific contexts:

```yaml
- step: "specialized-analysis"
  type: "agent"
  agent: "data-analyst"
  task: |
    Analyze this data set: $dataset_path
    
    Context: This is for quarterly review
    Requirements: Focus on trends and anomalies
    Output format: Executive summary + detailed findings
  timeout: 900
  context:
    session_type: "analysis"
    priority: "high"
    department: "finance"
```

### Workflow State Integration

Your agents can query workflow state:

```bash
# Check running workflows
nova-workflow list --status running

# Get specific workflow status
nova-workflow status <workflow-id>

# Approve pending gates
nova-workflow approve <workflow-id> --step approve-design
```

---

## Best Practices for Production Use

### 1. Variable Management

```yaml
variables:
  # Always provide sensible defaults
  environment: "development"
  timeout_seconds: 300
  notification_channel: "general"
  
  # Document what variables are for
  # user_email: "Email of user to create (required)"
  # approval_timeout: "Seconds to wait for approval (default: 1800)"
```

### 2. Error Handling Strategy

```yaml
steps:
  - step: "critical-operation"
    type: "agent"
    agent: "coder"
    task: "Deploy new version"
    
    # Always add retry for flaky operations
    retry:
      max_attempts: 3
      backoff: "exponential"
    
    # Always handle errors
    on_error:
      rollback:
        - step: "rollback-deploy"
          type: "shell"
          command: "git checkout HEAD~1 && npm run deploy"
        
        - step: "notify-failure"
          type: "notify"
          target: "agent_chat"
          message: "🚨 Deployment failed and rolled back"
          mentions: ["oncall-team"]
```

### 3. Approval Gates

```yaml
# Use specific approvers, not generic groups
approvers: ["nova", "druid"]  # ✅ Good

# approvers: ["admin"]         # ❌ Vague

# Set reasonable timeouts
timeout: 3600  # 1 hour for normal approval
timeout: 300   # 5 minutes for urgent decisions

# Always handle rejection
on_reject: "fail"              # ✅ Explicit
on_timeout: "notify_and_fail"  # ✅ Handle timeouts
```

### 4. Monitoring and Logging

```yaml
on_success:
  - type: "log"
    level: "info"
    message: "Workflow $workflow_name completed successfully"
  
  - type: "metric"
    name: "workflow.success"
    value: 1
    tags:
      workflow_name: "$workflow_name"
      duration_seconds: "$execution_time"

on_failure:
  - type: "log"
    level: "error"
    message: "Workflow failed at step $failed_step: $error_message"
  
  - type: "notify"
    target: "alerts"
    message: "🚨 Workflow failure requires attention"
    mentions: ["oncall"]
```

---

## Troubleshooting

### Common Issues

#### 1. "Agent not found" error

```bash
# Check available agents
nova-session list agents

# Ensure agent name matches exactly (case-sensitive)
agent: "newhart"  # ✅
agent: "Newhart"  # ❌
```

#### 2. "Variable not interpolated" 

Variables must be defined in the `variables:` section or come from previous step outputs:

```yaml
variables:
  my_var: "default_value"  # ✅ Defined

steps:
  - step: "use-undefined"
    task: "Process $undefined_var"  # ❌ Not defined
```

#### 3. "Database operation failed"

```bash
# Test database connectivity
psql nova_memory -c "SELECT 1;"

# Check SQL syntax
psql nova_memory -c "EXPLAIN SELECT * FROM agents WHERE name = 'test';"
```

#### 4. "Workflow timeout"

Increase timeouts for long-running operations:

```yaml
- step: "long-task"
  type: "agent"
  agent: "coder"
  task: "Complex analysis"
  timeout: 1800  # 30 minutes instead of default 300
```

#### 5. "Gate approval timeout"

```bash
# Check pending approvals
nova-workflow list --status waiting_approval

# Approve manually
nova-workflow approve <workflow-id> --step gate-step-name

# Or increase timeout in workflow
timeout: 7200  # 2 hours
```

### Getting Help

1. **Check logs:**
   ```bash
   nova-workflow logs <workflow-id>
   tail -f ~/clawd/nova-cognition/logs/executions/$(date +%Y-%m-%d).jsonl
   ```

2. **Validate syntax:**
   ```bash
   nova-workflow validate workflows/your-workflow.awl.yaml
   ```

3. **Test in parts:**
   ```bash
   # Test just the first few steps
   nova-workflow run workflows/test.awl.yaml --steps 1-3
   ```

4. **Dry run:**
   ```bash
   # See what would happen without executing
   nova-workflow run workflows/test.awl.yaml --dry-run
   ```

---

## Next Steps

Now that you understand AWL basics:

1. **Study the examples** in `~/clawd/nova-cognition/focus/protocols/workflows/`
2. **Read the full specification** in `docs/agent-workflow-language.md`
3. **Create your own workflows** for common tasks
4. **Set up monitoring** for production workflows
5. **Integrate workflows** into your agent systems

### Example Integration Ideas

- **Daily reporting workflows** (system status, metrics, summaries)
- **Incident response workflows** (detection, notification, remediation)
- **Content creation workflows** (research, draft, review, publish)
- **Code deployment workflows** (test, review, deploy, verify)
- **Data processing workflows** (ingest, clean, analyze, report)

**🎯 Goal:** Replace manual multi-step processes with reliable, auditable workflows.

---

## AWL Cheat Sheet

### Basic Workflow Structure
```yaml
workflow:
  name: "workflow-name"
  version: "1.0.0"
  variables:
    var_name: "default_value"
  steps:
    - step: "step-name"
      type: "agent"
      agent: "agent-name"
      task: "Task with $variables"
```

### Step Types
- `agent` - Spawn agent with task
- `gate` - Human approval/input
- `database` - SQL operations
- `shell` - Shell commands
- `notify` - Send notifications
- `parallel` - Run steps concurrently
- `conditional` - Branch based on conditions

### Common Variables
- `$result` - Output from previous step
- `$error_message` - Error details on failure
- `$workflow_id` - Current workflow ID
- `$timestamp` - Current timestamp

### CLI Commands
```bash
nova-workflow run workflow.awl.yaml --var key=value
nova-workflow list --status running
nova-workflow status <workflow-id>
nova-workflow approve <workflow-id> --step step-name
nova-workflow logs <workflow-id>
nova-workflow validate workflow.awl.yaml
```

**Happy workflow orchestration! 🚀**

---

*For questions about this guide, contact the documentation team or file an issue in the nova-cognition repository.*