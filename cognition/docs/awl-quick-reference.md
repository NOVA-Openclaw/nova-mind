# AWL Quick Reference

**Agent Workflow Language (AWL) - Essential syntax and patterns for rapid development**

## Basic Workflow Structure

```yaml
workflow:
  name: "workflow-name"           # Required: unique identifier
  version: "1.0.0"               # Required: semantic versioning
  description: "What this does"   # Required: human description
  author: "your-name"             # Required: who created this
  tags: ["category", "purpose"]   # Optional: for organization
  
  variables:                      # Optional: default variables
    var_name: "default_value"
    timeout_seconds: 300
  
  steps:                          # Required: workflow steps
    - step: "step-name"
      type: "agent"
      # ... step configuration
  
  on_success:                     # Optional: success handlers
    - type: "log"
      message: "Workflow completed"
  
  on_failure:                     # Optional: failure handlers
    - type: "notify"
      message: "Workflow failed"
```

---

## Step Types Reference

### 1. Agent Task
```yaml
- step: "task-name"
  type: "agent"
  agent: "agent-name"             # Required: which agent to use
  task: "Task description with $variables"  # Required: what to do
  timeout: 300                    # Optional: seconds (default: 300)
  outputs:                        # Optional: extract from result
    - variable_name: "$result.field"
    - another_var: "$result"
  retry:                          # Optional: retry configuration
    max_attempts: 3
    backoff: "exponential"        # exponential, linear, constant
    backoff_base: 2              # base seconds for backoff
  on_error:                       # Optional: error handling
    - step: "fallback"
      type: "notify"
      message: "Task failed"
```

### 2. Human Approval Gate
```yaml
- step: "approval"
  type: "gate"
  gate_type: "approval"           # Required: approval, input
  message: "What needs approval?"  # Required: prompt message
  approvers: ["user1", "user2"]   # Required: who can approve
  timeout: 3600                   # Required: seconds to wait
  on_reject: "fail"               # Optional: fail, continue, skip
  on_timeout: "fail"              # Optional: fail, continue, skip
```

### 3. Database Operation
```yaml
- step: "database-op"
  type: "database"
  operation: "query"              # Required: query, execute, execute_file
  sql: "SELECT * FROM table WHERE id = '$variable'"  # Required for query/execute
  file: "/path/to/file.sql"       # Required for execute_file
  database: "nova_memory"         # Optional: defaults to nova_memory
  outputs:                        # Optional: extract from result
    - count: "$result.row_count"
    - data: "$result.rows"
  assert:                         # Optional: validation
    - condition: "$result.count > 0"
      message: "No rows found"
```

### 4. Shell Command
```yaml
- step: "shell-command"
  type: "shell"
  command: "ls -la /path"         # Required: command to run
  working_dir: "/home/nova"       # Optional: where to run
  timeout: 60                     # Optional: seconds (default: 300)
  env:                           # Optional: environment variables
    PATH: "/usr/local/bin:$PATH"
  on_error: "warn"               # Optional: warn, fail (default: fail)
```

### 5. Notification
```yaml
- step: "notify"
  type: "notify"
  target: "agent_chat"            # Required: agent_chat, alerts, etc.
  message: "Notification text with $variables"  # Required
  mentions: ["user1", "user2"]    # Optional: @ mentions
  priority: "high"                # Optional: high, normal, low
```

### 6. Conditional Branch
```yaml
- step: "conditional"
  type: "conditional"
  condition: "$variable == 'value'"  # Required: boolean expression
  if_true:                        # Required: steps if condition true
    - step: "true-branch"
      type: "agent"
      agent: "newhart"
      task: "Do something"
  if_false:                       # Optional: steps if condition false
    - step: "false-branch"
      type: "notify"
      message: "Condition was false"
```

### 7. Parallel Execution
```yaml
- step: "parallel-tasks"
  type: "parallel"
  branches:                       # Required: list of parallel branches
    - name: "branch-1"            # Required: branch identifier
      steps:                      # Required: steps for this branch
        - step: "task-1"
          type: "agent"
          agent: "scribe"
          task: "First task"
    - name: "branch-2"
      steps:
        - step: "task-2"
          type: "agent"
          agent: "newhart"
          task: "Second task"
  wait_for: "all"                 # Required: all, any, first
```

---

## Variable Reference

### Variable Sources
- **Workflow variables:** Defined in `variables:` section
- **Runtime variables:** Passed with `--var key=value`
- **Step outputs:** From `outputs:` section of previous steps
- **Built-in variables:** System-provided variables

### Variable Syntax
```yaml
# Basic interpolation
task: "Process $variable_name"

# Nested object access
task: "Use $result.data.field"

# Array access  
task: "First item: $array[0]"

# Default values
task: "Value: ${variable_name:-default_value}"

# Conditional in text
message: "Status: ${success ? 'OK' : 'FAILED'}"
```

### Built-in Variables
- `$result` - Output from previous step
- `$error_message` - Error details when step fails
- `$workflow_id` - Current workflow unique ID
- `$workflow_name` - Current workflow name
- `$timestamp` - Current ISO 8601 timestamp
- `$failed_step` - Name of step that failed
- `$execution_time` - Total workflow execution time in seconds

---

## Condition Syntax

### Comparison Operators
```yaml
condition: "$count > 10"          # Greater than
condition: "$status == 'ready'"   # Equals (use quotes for strings)
condition: "$value != null"       # Not equals
condition: "$score >= 80"         # Greater than or equal
condition: "$age <= 65"           # Less than or equal
```

### Logical Operators
```yaml
condition: "$a > 5 && $b < 10"    # AND
condition: "$x == 'yes' || $y == 'ok'"  # OR
condition: "!$is_disabled"        # NOT
```

### String Operations
```yaml
condition: "$status =~ 'success.*'"    # Regex match
condition: "$name != ''"               # Not empty string
condition: "$email =~ '.*@.*\\..*'"    # Email pattern
```

### Existence Checks
```yaml
condition: "$variable"             # True if variable exists and is truthy
condition: "!$optional_field"     # True if variable is falsy or missing
condition: "$result.count > 0"    # Check nested field
```

---

## Error Handling Patterns

### Retry Configuration
```yaml
retry:
  max_attempts: 3                 # Try up to 3 times total
  backoff: "exponential"          # exponential, linear, constant
  backoff_base: 2                 # Start with 2 seconds, then 4, 8, 16...
```

### Error Handling Options
```yaml
on_error: "fail"                  # Fail the entire workflow (default)
on_error: "warn"                  # Log warning but continue
on_error: "skip"                  # Skip to next step
on_error:                         # Custom error handling
  - step: "cleanup"
    type: "shell"
    command: "cleanup.sh"
  rollback:                       # Rollback steps
    - step: "undo-changes"
      type: "database"
      sql: "DELETE FROM table WHERE id = '$created_id'"
```

---

## CLI Commands

### Running Workflows
```bash
# Basic execution
nova-workflow run workflows/my-workflow.awl.yaml

# With variables
nova-workflow run workflows/my-workflow.awl.yaml \
  --var environment="production" \
  --var user_email="nova@example.com"

# Dry run (see what would happen)
nova-workflow run workflows/my-workflow.awl.yaml --dry-run
```

### Managing Workflows
```bash
# List running workflows
nova-workflow list --status running

# Get workflow status
nova-workflow status <workflow-id>

# View workflow logs
nova-workflow logs <workflow-id>

# Approve pending gate
nova-workflow approve <workflow-id> --step approval-step-name

# Cancel running workflow
nova-workflow cancel <workflow-id>
```

### Validation and Testing
```bash
# Validate workflow syntax
nova-workflow validate workflows/my-workflow.awl.yaml

# Test just first 3 steps
nova-workflow run workflows/my-workflow.awl.yaml --steps 1-3

# List all available workflows
nova-workflow list-workflows
```

---

## Common Patterns

### Sequential Agent Tasks
```yaml
steps:
  - step: "research"
    type: "agent"
    agent: "newhart"
    task: "Research topic: $topic"
    outputs:
      - findings: "$result"
  
  - step: "write"
    type: "agent"
    agent: "scribe"
    task: "Write article based on: $findings"
    outputs:
      - article: "$result"
  
  - step: "review"
    type: "agent"
    agent: "editor"
    task: "Review and edit: $article"
```

### Approval with Fallback
```yaml
steps:
  - step: "request-approval"
    type: "gate"
    gate_type: "approval"
    message: "Approve deployment?"
    approvers: ["lead-dev"]
    timeout: 1800
    on_reject: "fail"
    on_timeout: "continue"  # Auto-approve after 30 min
  
  - step: "deploy"
    type: "shell"
    command: "deploy.sh"
```

### Database-Driven Conditional
```yaml
steps:
  - step: "check-environment"
    type: "database"
    operation: "query"
    sql: "SELECT env FROM config LIMIT 1"
    outputs:
      - environment: "$result.env"
  
  - step: "environment-deploy"
    type: "conditional"
    condition: "$environment == 'production'"
    if_true:
      - step: "prod-deploy"
        type: "agent"
        agent: "coder"
        task: "Deploy with production safeguards"
    if_false:
      - step: "staging-deploy"
        type: "shell"
        command: "npm run deploy-staging"
```

### Parallel Analysis with Synthesis
```yaml
steps:
  - step: "parallel-analysis"
    type: "parallel"
    branches:
      - name: "technical"
        steps:
          - step: "tech-analysis"
            type: "agent"
            agent: "engineer"
            task: "Technical analysis of $problem"
            outputs:
              - tech_report: "$result"
      
      - name: "business"
        steps:
          - step: "business-analysis"
            type: "agent"
            agent: "analyst"
            task: "Business impact analysis of $problem"
            outputs:
              - business_report: "$result"
    wait_for: "all"
  
  - step: "synthesize"
    type: "agent"
    agent: "scribe"
    task: |
      Create comprehensive report combining:
      Technical: $tech_report
      Business: $business_report
```

---

## Troubleshooting

### Common Error Messages

**"Agent 'xyz' not found"**
- Check agent name spelling (case-sensitive)
- Verify agent is available: `nova-session list agents`

**"Variable '$var' not defined"**
- Add to `variables:` section or ensure it comes from previous step output
- Check variable name spelling

**"Step timeout after 300 seconds"**
- Increase `timeout:` value for the step
- Check if agent/operation is actually stuck

**"Database operation failed"**
- Test SQL syntax: `psql nova_memory -c "YOUR_SQL"`
- Check database permissions and connection

**"Gate approval timeout"**
- Increase `timeout:` value
- Check approver notifications
- Use `nova-workflow approve` manually if needed

### Debug Commands
```bash
# Check workflow syntax
nova-workflow validate my-workflow.awl.yaml

# See execution details
nova-workflow logs <workflow-id> --verbose

# Test database connectivity
psql nova_memory -c "SELECT 1"

# List available agents
nova-session list agents

# Dry run to see execution plan
nova-workflow run my-workflow.awl.yaml --dry-run
```

---

## File Organization

### Recommended Structure
```
~/workspace/nova-mind/cognition/focus/protocols/workflows/
├── getting-started/          # Learning examples
├── production/              # Live production workflows
├── development/             # Development/testing workflows
├── focus/templates/               # Reusable workflow templates
└── archive/                 # Old/deprecated workflows
```

### Naming Convention
- `kebab-case-names.awl.yaml`
- Include version in filename for major changes: `deploy-v2.awl.yaml`
- Use descriptive names: `daily-system-health-check.awl.yaml`

---

**💡 Pro Tips:**
- Start with simple workflows and add complexity gradually
- Always include timeout values for agent tasks
- Use meaningful step names for easier debugging
- Add approval gates for destructive operations
- Test workflows in development before production use
- Keep workflows focused on a single purpose
- Document complex variable transformations

**📚 See Also:**
- [Getting Started Guide](awl-getting-started.md)
- [Full AWL Specification](agent-workflow-language.md)
- [Example Workflows](../focus/protocols/workflows/)