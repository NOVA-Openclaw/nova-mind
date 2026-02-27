# Agent Workflow Language (AWL)

**Version:** 0.1.0  
**Date:** 2026-02-08  
**Author:** Newhart  
**Status:** Design Proposal

## Overview

The Agent Workflow Language (AWL) is a declarative DSL for orchestrating multi-agent processes. It provides infrastructure-as-code style definitions for complex agent interactions, enabling reproducible, auditable, and maintainable multi-agent workflows.

**Design Philosophy:**
- Declarative over imperative
- Human-readable and version-controllable
- Clear error handling and rollback semantics
- Support for both sequential and parallel execution
- Integration with existing agent infrastructure (sessions_spawn, agent_chat)

## Core Concepts

### 1. Workflow Definition
A workflow is a named, versioned collection of steps that accomplish a specific goal.

### 2. Steps
Individual units of work, assigned to specific agents or systems.

### 3. Variables
Data passed between steps using `$variable` syntax.

### 4. Conditionals
Branch execution based on step outputs or workflow state.

### 5. Parallelism
Execute independent steps concurrently.

### 6. Error Handling
Define retry logic, fallbacks, and rollback procedures.

### 7. Gates
Human approval or external triggers that pause workflow execution.

### 8. Hooks
Notifications or side effects triggered at specific workflow events.

---

## Syntax Specification

### Basic Workflow Structure

```yaml
workflow:
  name: "workflow-name"
  version: "1.0.0"
  description: "Human-readable description"
  author: "agent-or-human-name"
  
  variables:
    # Initial variables (can be overridden at runtime)
    var_name: "default_value"
  
  steps:
    - step: "step-name"
      # Step definition
    
  on_success:
    # Actions when workflow completes successfully
  
  on_failure:
    # Actions when workflow fails
```

### Step Types

#### 1. Agent Task Step
Execute a task via sessions_spawn.

```yaml
- step: "design-agent"
  type: "agent"
  agent: "newhart"
  task: "Design a new agent: $agent_requirements"
  timeout: 600  # seconds
  outputs:
    - agent_spec: "$result.agent_specification"
    - sql_file: "$result.sql_path"
```

#### 2. Human Approval Gate
Pause for human approval before continuing.

```yaml
- step: "approve-design"
  type: "gate"
  gate_type: "approval"
  message: "Review agent spec: $agent_spec. Approve?"
  approvers: ["nova", "druid"]
  timeout: 3600  # 1 hour
  on_timeout: "fail"  # or "skip", "continue"
```

#### 3. Conditional Branch
Execute different paths based on conditions.

```yaml
- step: "check-agent-type"
  type: "conditional"
  condition: "$agent_type == 'persistent'"
  if_true:
    - step: "setup-persistent-agent"
      # ...
  if_false:
    - step: "setup-ephemeral-agent"
      # ...
```

#### 4. Parallel Execution
Run independent steps concurrently.

```yaml
- step: "parallel-validation"
  type: "parallel"
  branches:
    - name: "validate-schema"
      steps:
        - step: "schema-check"
          type: "agent"
          agent: "coder"
          task: "Validate schema: $sql_file"
    
    - name: "validate-docs"
      steps:
        - step: "docs-check"
          type: "agent"
          agent: "scribe"
          task: "Check documentation completeness"
  
  wait_for: "all"  # or "any", "first"
```

#### 5. Database Operation
Direct database interaction (coordinated by NOVA).

```yaml
- step: "insert-agent"
  type: "database"
  operation: "execute_file"
  file: "$sql_file"
  database: "nova_memory"
  on_error: "rollback"
```

#### 6. Notification Hook
Send notifications to agents or channels.

```yaml
- step: "notify-team"
  type: "notify"
  target: "agent_chat"
  message: "New agent $agent_name created!"
  mentions: ["nova", "druid"]
```

#### 7. Shell Command
Execute system commands (use sparingly).

```yaml
- step: "refresh-dashboard"
  type: "shell"
  command: "npm run build-staff-json"
  working_dir: "/home/nova/clawd/dashboard"
  on_error: "warn"  # don't fail workflow if this fails
```

### Error Handling

```yaml
- step: "risky-operation"
  type: "agent"
  agent: "coder"
  task: "Complex task"
  
  retry:
    max_attempts: 3
    backoff: "exponential"  # or "linear", "constant"
    backoff_base: 2  # seconds
  
  on_error:
    - step: "fallback-operation"
      type: "agent"
      agent: "newhart"
      task: "Manual review needed for: $error_message"
  
  rollback:
    - step: "cleanup-partial-work"
      type: "database"
      operation: "execute"
      sql: "DELETE FROM agents WHERE name = '$agent_name'"
```

### Variable Interpolation

Variables use `$variable_name` syntax:

```yaml
task: "Design agent for: $requirements"
message: "Agent $agent_name created at $timestamp"
```

Access nested values:
```yaml
agent_model: "$result.seed_context.model"
```

### Workflow Metadata

```yaml
workflow:
  name: "create-new-agent"
  version: "1.0.0"
  description: "End-to-end agent creation workflow"
  author: "newhart"
  tags: ["agents", "onboarding", "infrastructure"]
  
  required_permissions:
    - "database.write"
    - "agent.spawn"
  
  estimated_duration: 600  # seconds
```

---

## Complete Example: Create New Agent Workflow

```yaml
workflow:
  name: "create-new-agent"
  version: "1.0.0"
  description: "Complete workflow for creating and onboarding a new agent"
  author: "newhart"
  
  variables:
    requirements: ""
    agent_name: ""
    requester: "nova"
  
  steps:
    # Step 1: Design the agent
    - step: "design-agent"
      type: "agent"
      agent: "newhart"
      task: |
        Design a new agent with requirements:
        $requirements
        
        Return: agent specification, SQL file path, and seed_context
      timeout: 600
      outputs:
        - agent_name: "$result.agent_name"
        - sql_file: "$result.sql_path"
        - seed_context: "$result.seed_context"
      on_error:
        - step: "notify-design-failure"
          type: "notify"
          target: "agent_chat"
          message: "Agent design failed: $error_message"
          mentions: ["$requester"]
    
    # Step 2: Human approval gate
    - step: "approve-design"
      type: "gate"
      gate_type: "approval"
      message: |
        Review agent design:
        - Name: $agent_name
        - SQL: $sql_file
        
        Approve for insertion?
      approvers: ["nova", "druid"]
      timeout: 3600
      on_reject: "fail"
    
    # Step 3: Insert into database
    - step: "insert-agent"
      type: "database"
      operation: "execute_file"
      file: "$sql_file"
      database: "nova_memory"
      outputs:
        - agent_id: "$result.id"
      retry:
        max_attempts: 2
        backoff: "constant"
        backoff_base: 5
      on_error:
        rollback:
          - step: "notify-rollback"
            type: "notify"
            target: "agent_chat"
            message: "Agent insertion failed. Rolling back."
    
    # Step 4: Parallel post-insertion tasks
    - step: "post-insertion"
      type: "parallel"
      branches:
        - name: "update-dashboard"
          steps:
            - step: "refresh-staff-json"
              type: "shell"
              command: "npm run build-staff-json"
              working_dir: "/home/nova/clawd/dashboard"
              on_error: "warn"
        
        - name: "create-documentation"
          steps:
            - step: "document-agent"
              type: "agent"
              agent: "scribe"
              task: |
                Document the new agent $agent_name:
                - Purpose and role
                - Spawn instructions
                - Integration points
              timeout: 300
      
      wait_for: "all"
    
    # Step 5: Verification
    - step: "verify-agent"
      type: "database"
      operation: "query"
      sql: "SELECT * FROM agents WHERE name = '$agent_name'"
      assert:
        - condition: "$result.count > 0"
          message: "Agent not found in database"
    
    # Step 6: Announce completion
    - step: "announce-completion"
      type: "notify"
      target: "agent_chat"
      message: |
        ✅ New agent onboarded: $agent_name
        - Database: ✓
        - Dashboard: ✓
        - Documentation: ✓
        
        Ready to spawn!
      mentions: ["$requester"]
  
  on_success:
    - type: "log"
      message: "Agent $agent_name created successfully"
    - type: "metric"
      name: "agent.created"
      value: 1
      tags:
        agent_name: "$agent_name"
  
  on_failure:
    - type: "notify"
      target: "agent_chat"
      message: "❌ Agent creation failed at step: $failed_step"
      mentions: ["nova", "newhart"]
    - type: "log"
      level: "error"
      message: "Workflow failed: $error_message"
```

---

## Execution Model

### Orchestrator: NOVA

NOVA is the primary workflow orchestrator, responsible for:

1. **Parsing workflow definitions**
2. **Maintaining workflow state**
3. **Executing steps in sequence or parallel**
4. **Variable interpolation and passing**
5. **Error handling and retries**
6. **Gate management (approval/timeout)**
7. **Rollback coordination**

### Execution Flow

```
┌─────────────────────────────────────┐
│ 1. Load workflow definition (YAML)  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 2. Validate workflow structure      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 3. Initialize variables & state     │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 4. Execute steps (sequential/||)    │
│    - Agent tasks → sessions_spawn   │
│    - Gates → wait for approval      │
│    - DB ops → direct execution      │
│    - Notify → agent_chat/channels   │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 5. Handle errors (retry/rollback)   │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│ 6. Execute on_success/on_failure     │
└─────────────────────────────────────┘
```

### State Management

Workflow state includes:

```json
{
  "workflow_id": "uuid",
  "workflow_name": "create-new-agent",
  "version": "1.0.0",
  "status": "running",
  "started_at": "2026-02-08T07:00:00Z",
  "current_step": "approve-design",
  "variables": {
    "requirements": "...",
    "agent_name": "scribe",
    "sql_file": "/tmp/scribe.sql"
  },
  "step_history": [
    {
      "step": "design-agent",
      "status": "completed",
      "started_at": "2026-02-08T07:00:00Z",
      "completed_at": "2026-02-08T07:02:30Z",
      "outputs": {...}
    }
  ],
  "gates": [
    {
      "step": "approve-design",
      "status": "pending",
      "approvers_required": ["nova", "druid"],
      "approvals": []
    }
  ]
}
```

### Integration Points

#### 1. Agent Spawning
```
agent step → NOVA calls sessions_spawn(agent, task) → waits for result → extracts outputs
```

#### 2. Database Operations
```
database step → NOVA executes SQL (via psql or pg library) → captures result → validates
```

#### 3. Notifications
```
notify step → NOVA inserts into agent_chat with mentions → triggers NOTIFY
```

#### 4. Gates
```
gate step → NOVA sends approval request → waits for response → continues/fails based on result
```

---

## File Format & Storage

### Workflow Definition Files

**Location:** `~/workspace/nova-mind/cognition/focus/protocols/workflows/`

**Naming:** `{workflow-name}.awl.yaml`

Example:
```
~/workspace/nova-mind/cognition/focus/protocols/workflows/
  ├── create-new-agent.awl.yaml
  ├── deploy-code-change.awl.yaml
  ├── weekly-review.awl.yaml
  └── emergency-rollback.awl.yaml
```

### Workflow Execution Logs

**Location:** `~/.openclaw/logs/awl-executions/`

**Format:** JSONL (one JSON object per line)

```jsonl
{"timestamp": "2026-02-08T07:00:00Z", "workflow_id": "uuid", "event": "started", "workflow": "create-new-agent"}
{"timestamp": "2026-02-08T07:00:01Z", "workflow_id": "uuid", "event": "step_started", "step": "design-agent"}
{"timestamp": "2026-02-08T07:02:30Z", "workflow_id": "uuid", "event": "step_completed", "step": "design-agent", "outputs": {...}}
```

---

## Workflow Schema (JSON Schema)

To enable validation and IDE support:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Agent Workflow Language",
  "type": "object",
  "required": ["workflow"],
  "properties": {
    "workflow": {
      "type": "object",
      "required": ["name", "version", "steps"],
      "properties": {
        "name": {"type": "string"},
        "version": {"type": "string"},
        "description": {"type": "string"},
        "author": {"type": "string"},
        "variables": {"type": "object"},
        "steps": {
          "type": "array",
          "items": {"$ref": "#/definitions/step"}
        }
      }
    }
  },
  "definitions": {
    "step": {
      "type": "object",
      "required": ["step", "type"],
      "properties": {
        "step": {"type": "string"},
        "type": {
          "enum": ["agent", "gate", "conditional", "parallel", "database", "notify", "shell"]
        }
      }
    }
  }
}
```

Full schema available in `schemas/awl.schema.json`.

---

## CLI Interface

### Execute a workflow

```bash
nova-workflow run workflows/create-new-agent.awl.yaml \
  --var requirements="Design a monitoring agent" \
  --var requester="druid"
```

### List running workflows

```bash
nova-workflow list --status running
```

### Approve a gate

```bash
nova-workflow approve <workflow-id> --step approve-design
```

### View workflow status

```bash
nova-workflow status <workflow-id>
```

### Rollback a workflow

```bash
nova-workflow rollback <workflow-id>
```

---

## Implementation Roadmap

### Phase 1: Core Execution Engine
- [ ] YAML parser
- [ ] Step executor (sequential)
- [ ] Variable interpolation
- [ ] Basic error handling
- [ ] Agent step type (sessions_spawn integration)

### Phase 2: Advanced Features
- [ ] Parallel execution
- [ ] Conditional branching
- [ ] Gates (approval)
- [ ] Retry logic
- [ ] Rollback support

### Phase 3: Integration & Tooling
- [ ] Database step type
- [ ] Notification hooks
- [ ] CLI interface
- [ ] Workflow validation
- [ ] Execution logs/metrics

### Phase 4: Ecosystem
- [ ] Workflow library (common patterns)
- [ ] Web UI for monitoring
- [ ] Workflow templates
- [ ] Testing framework
- [ ] Documentation

---

## Use Cases

### 1. Agent Creation (as shown above)

### 2. Code Deployment
```yaml
workflow:
  name: "deploy-code-change"
  steps:
    - step: "run-tests"
      type: "shell"
      command: "npm test"
    
    - step: "review-changes"
      type: "gate"
      gate_type: "approval"
    
    - step: "deploy"
      type: "shell"
      command: "git push production"
    
    - step: "verify-deployment"
      type: "agent"
      agent: "coder"
      task: "Verify deployment succeeded"
```

### 3. Weekly Review
```yaml
workflow:
  name: "weekly-review"
  steps:
    - step: "gather-metrics"
      type: "database"
      operation: "query"
      sql: "SELECT * FROM metrics WHERE created_at > now() - interval '7 days'"
    
    - step: "summarize"
      type: "agent"
      agent: "scribe"
      task: "Create weekly summary from: $metrics"
    
    - step: "distribute"
      type: "notify"
      target: "agent_chat"
      message: "$summary"
      mentions: ["nova", "druid"]
```

### 4. Emergency Rollback
```yaml
workflow:
  name: "emergency-rollback"
  steps:
    - step: "confirm-rollback"
      type: "gate"
      gate_type: "approval"
      message: "⚠️ Emergency rollback requested. Confirm?"
      approvers: ["nova", "druid"]
      timeout: 300
    
    - step: "execute-rollback"
      type: "database"
      operation: "execute_file"
      file: "rollback-scripts/$rollback_version.sql"
    
    - step: "verify"
      type: "agent"
      agent: "coder"
      task: "Verify system is stable after rollback"
    
    - step: "notify-team"
      type: "notify"
      target: "agent_chat"
      message: "🔄 Rollback to $rollback_version complete"
```

---

## Security Considerations

1. **Workflow validation:** All workflows validated before execution
2. **Permission checks:** Steps require appropriate permissions
3. **Variable sanitization:** Prevent injection attacks in shell/SQL steps
4. **Audit logging:** All workflow executions logged
5. **Gate approvals:** Sensitive operations require human approval
6. **Rollback capability:** All destructive operations have rollback steps

---

## Future Enhancements

- **Workflow versioning:** Track changes to workflows over time
- **Workflow composition:** Include/import other workflows as sub-workflows
- **Dynamic agent selection:** Choose agent based on runtime conditions
- **External integrations:** Webhooks, APIs, cloud services
- **Scheduled workflows:** Cron-like scheduling
- **Workflow marketplace:** Share and discover workflows
- **Visual workflow editor:** Drag-and-drop workflow design
- **Real-time monitoring:** Live status dashboard
- **Workflow testing:** Unit tests for workflows
- **Cost estimation:** Predict workflow cost before execution

---

## Appendix: Grammar Reference

### Variable Syntax
- Simple: `$var_name`
- Nested: `$obj.field.subfield`
- Array: `$array[0]`
- Default: `${var_name:-default_value}`

### Operators (in conditions)
- Comparison: `==`, `!=`, `>`, `<`, `>=`, `<=`
- Logical: `&&`, `||`, `!`
- Regex: `=~` (matches)

### Reserved Words
- `$result` - output from previous step
- `$error_message` - error from failed step
- `$workflow_id` - current workflow ID
- `$timestamp` - current timestamp
- `$requester` - user who initiated workflow

---

**End of Design Document**
