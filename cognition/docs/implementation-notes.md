# AWL Implementation Notes

**For:** NOVA + Coder  
**Date:** 2026-02-08  
**Status:** Design → Implementation

## Overview

This document provides technical guidance for implementing the Agent Workflow Language (AWL) execution engine.

## Architecture

```
┌─────────────────────────────────────────────┐
│          AWL Execution Engine               │
│  (NOVA orchestrates, Coder implements)      │
└─────────────────────────────────────────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
    ┌───▼───┐   ┌──▼──┐   ┌───▼────┐
    │ YAML  │   │State│   │Executor│
    │Parser │   │Store│   │ Engine │
    └───────┘   └─────┘   └────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
    ┌───▼────┐  ┌──▼───┐  ┌────▼────┐
    │sessions│  │agent │  │database │
    │_spawn  │  │_chat │  │ queries │
    └────────┘  └──────┘  └─────────┘
```

## Core Components

### 1. YAML Parser
**Responsibility:** Load and validate workflow definitions

**Implementation:**
```javascript
const yaml = require('yaml');
const Ajv = require('ajv');

class WorkflowParser {
  constructor(schemaPath) {
    this.ajv = new Ajv();
    this.schema = require(schemaPath);
  }
  
  parse(workflowPath) {
    const content = fs.readFileSync(workflowPath, 'utf8');
    const workflow = yaml.parse(content);
    
    // Validate against schema
    const valid = this.ajv.validate(this.schema, workflow);
    if (!valid) {
      throw new Error(`Invalid workflow: ${this.ajv.errorsText()}`);
    }
    
    return workflow;
  }
}
```

### 2. State Store
**Responsibility:** Track workflow execution state

**State Schema:**
```typescript
interface WorkflowState {
  workflowId: string;
  workflowName: string;
  version: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  startedAt: Date;
  completedAt?: Date;
  currentStep: string;
  variables: Record<string, any>;
  stepHistory: StepHistory[];
  gates: GateState[];
  errors: ErrorLog[];
}

interface StepHistory {
  step: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  startedAt: Date;
  completedAt?: Date;
  outputs?: Record<string, any>;
  error?: string;
}

interface GateState {
  step: string;
  status: 'pending' | 'approved' | 'rejected' | 'timeout';
  approversRequired: string[];
  approvals: Approval[];
  createdAt: Date;
  expiresAt: Date;
}
```

**Storage:**
- **Option 1:** PostgreSQL table `workflow_executions`
- **Option 2:** JSON files in `~/clawd/nova-cognition/logs/executions/`
- **Recommendation:** Start with PostgreSQL for durability

### 3. Executor Engine
**Responsibility:** Execute workflow steps

**Core Logic:**
```javascript
class WorkflowExecutor {
  constructor(workflow, state) {
    this.workflow = workflow;
    this.state = state;
  }
  
  async execute() {
    try {
      // Initialize variables
      this.state.variables = {
        ...this.workflow.variables,
        ...this.state.variables  // runtime overrides
      };
      
      // Execute steps in sequence
      for (const step of this.workflow.steps) {
        await this.executeStep(step);
      }
      
      // Success hooks
      await this.executeHooks(this.workflow.on_success);
      this.state.status = 'completed';
    } catch (error) {
      // Failure hooks
      await this.executeHooks(this.workflow.on_failure);
      this.state.status = 'failed';
      throw error;
    }
  }
  
  async executeStep(step) {
    this.state.currentStep = step.step;
    
    // Route to appropriate executor based on step type
    switch (step.type) {
      case 'agent':
        return await this.executeAgentStep(step);
      case 'gate':
        return await this.executeGateStep(step);
      case 'conditional':
        return await this.executeConditionalStep(step);
      case 'parallel':
        return await this.executeParallelStep(step);
      case 'database':
        return await this.executeDatabaseStep(step);
      case 'notify':
        return await this.executeNotifyStep(step);
      case 'shell':
        return await this.executeShellStep(step);
      default:
        throw new Error(`Unknown step type: ${step.type}`);
    }
  }
}
```

## Step Executors

### Agent Step
```javascript
async executeAgentStep(step) {
  const task = this.interpolate(step.task);
  
  try {
    const result = await sessions_spawn({
      agentId: step.agent,
      task: task,
      timeoutSeconds: step.timeout || 600
    });
    
    // Extract outputs
    if (step.outputs) {
      for (const output of step.outputs) {
        const [varName, path] = Object.entries(output)[0];
        this.state.variables[varName] = this.extractPath(result, path);
      }
    }
    
    return result;
  } catch (error) {
    if (step.retry) {
      return await this.retryStep(step, () => this.executeAgentStep(step));
    }
    throw error;
  }
}
```

### Gate Step
```javascript
async executeGateStep(step) {
  const gateId = `${this.state.workflowId}-${step.step}`;
  
  // Create gate in database
  await this.createGate({
    id: gateId,
    workflowId: this.state.workflowId,
    step: step.step,
    message: this.interpolate(step.message),
    approvers: step.approvers,
    expiresAt: new Date(Date.now() + step.timeout * 1000)
  });
  
  // Send notification
  await this.notify({
    target: 'agent_chat',
    message: this.interpolate(step.message),
    mentions: step.approvers
  });
  
  // Wait for approval
  const result = await this.waitForGateApproval(gateId, step.timeout);
  
  if (result === 'rejected' && step.on_reject === 'fail') {
    throw new Error('Gate rejected by approver');
  }
  
  return result;
}
```

### Conditional Step
```javascript
async executeConditionalStep(step) {
  const condition = this.interpolate(step.condition);
  const result = this.evaluateCondition(condition);
  
  if (result) {
    for (const subStep of step.if_true || []) {
      await this.executeStep(subStep);
    }
  } else {
    for (const subStep of step.if_false || []) {
      await this.executeStep(subStep);
    }
  }
}
```

### Parallel Step
```javascript
async executeParallelStep(step) {
  const promises = step.branches.map(async (branch) => {
    try {
      for (const subStep of branch.steps) {
        await this.executeStep(subStep);
      }
      return { branch: branch.name, status: 'success' };
    } catch (error) {
      return { branch: branch.name, status: 'failed', error };
    }
  });
  
  const results = await Promise.all(promises);
  
  // Check wait_for condition
  if (step.wait_for === 'all') {
    const failed = results.filter(r => r.status === 'failed');
    if (failed.length > 0) {
      throw new Error(`Branches failed: ${failed.map(f => f.branch).join(', ')}`);
    }
  }
  
  return results;
}
```

### Database Step
```javascript
async executeDatabaseStep(step) {
  const { Pool } = require('pg');
  const pool = new Pool({
    host: 'localhost',
    database: step.database || 'nova_memory',
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD
  });
  
  let sql;
  if (step.operation === 'execute_file') {
    sql = fs.readFileSync(this.interpolate(step.file), 'utf8');
  } else {
    sql = this.interpolate(step.sql);
  }
  
  try {
    const result = await pool.query(sql);
    
    // Extract outputs
    if (step.outputs) {
      for (const output of step.outputs) {
        const [varName, path] = Object.entries(output)[0];
        this.state.variables[varName] = this.extractPath(result, path);
      }
    }
    
    return result;
  } catch (error) {
    if (step.on_error === 'rollback') {
      await this.executeRollback(step.rollback);
    }
    throw error;
  } finally {
    await pool.end();
  }
}
```

### Notify Step
```javascript
async executeNotifyStep(step) {
  const message = this.interpolate(step.message);
  const mentions = Array.isArray(step.mentions)
    ? step.mentions
    : [step.mentions];
  
  await insertAgentMessage({
    sender: 'nova',
    message: message,
    mentions: mentions
  });
}
```

### Shell Step
```javascript
async executeShellStep(step) {
  const { exec } = require('child_process');
  const { promisify } = require('util');
  const execAsync = promisify(exec);
  
  const command = this.interpolate(step.command);
  const options = {
    cwd: step.working_dir || process.cwd(),
    timeout: (step.timeout || 300) * 1000
  };
  
  try {
    const { stdout, stderr } = await execAsync(command, options);
    return { stdout, stderr, exit_code: 0 };
  } catch (error) {
    if (step.on_error === 'warn') {
      console.warn(`Step ${step.step} failed but continuing:`, error);
      return { stdout: '', stderr: error.message, exit_code: error.code };
    }
    throw error;
  }
}
```

## Variable Interpolation

```javascript
class VariableInterpolator {
  constructor(variables) {
    this.variables = variables;
  }
  
  interpolate(text) {
    if (typeof text !== 'string') return text;
    
    return text.replace(/\$(\w+(?:\.\w+)*)/g, (match, path) => {
      const value = this.resolvePath(path);
      return value !== undefined ? value : match;
    });
  }
  
  resolvePath(path) {
    const parts = path.split('.');
    let value = this.variables;
    
    for (const part of parts) {
      if (value && typeof value === 'object' && part in value) {
        value = value[part];
      } else {
        return undefined;
      }
    }
    
    return value;
  }
}
```

## Condition Evaluator

```javascript
class ConditionEvaluator {
  constructor(variables) {
    this.variables = variables;
  }
  
  evaluate(condition) {
    // Replace variables
    const interpolated = this.interpolate(condition);
    
    // Safe evaluation (consider using a proper expression parser)
    // For now, simple comparison operators
    const operators = ['==', '!=', '>', '<', '>=', '<='];
    
    for (const op of operators) {
      if (interpolated.includes(op)) {
        const [left, right] = interpolated.split(op).map(s => s.trim());
        return this.compare(left, right, op);
      }
    }
    
    // Boolean check
    return Boolean(interpolated);
  }
  
  compare(left, right, operator) {
    // Convert to appropriate types
    const leftVal = this.parseValue(left);
    const rightVal = this.parseValue(right);
    
    switch (operator) {
      case '==': return leftVal === rightVal;
      case '!=': return leftVal !== rightVal;
      case '>': return leftVal > rightVal;
      case '<': return leftVal < rightVal;
      case '>=': return leftVal >= rightVal;
      case '<=': return leftVal <= rightVal;
      default: return false;
    }
  }
  
  parseValue(value) {
    // Try parsing as number
    if (!isNaN(value)) return Number(value);
    // Try parsing as boolean
    if (value === 'true') return true;
    if (value === 'false') return false;
    // String
    return value.replace(/^["']|["']$/g, '');
  }
}
```

## Retry Logic

```javascript
async retryStep(step, executor) {
  const maxAttempts = step.retry.max_attempts || 3;
  const backoff = step.retry.backoff || 'exponential';
  const base = step.retry.backoff_base || 2;
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await executor();
    } catch (error) {
      if (attempt === maxAttempts) {
        throw error;
      }
      
      // Calculate backoff delay
      let delay;
      switch (backoff) {
        case 'exponential':
          delay = base ** attempt * 1000;
          break;
        case 'linear':
          delay = base * attempt * 1000;
          break;
        case 'constant':
          delay = base * 1000;
          break;
      }
      
      console.log(`Retry ${attempt}/${maxAttempts} after ${delay}ms`);
      await this.sleep(delay);
    }
  }
}
```

## CLI Interface

```javascript
#!/usr/bin/env node

const program = require('commander');
const WorkflowExecutor = require('./executor');

program
  .command('run <workflow>')
  .option('--var <key=value...>', 'Set workflow variables')
  .action(async (workflow, options) => {
    const variables = {};
    if (options.var) {
      for (const pair of options.var) {
        const [key, value] = pair.split('=');
        variables[key] = value;
      }
    }
    
    const executor = new WorkflowExecutor(workflow, variables);
    await executor.execute();
  });

program
  .command('list')
  .option('--status <status>', 'Filter by status')
  .action(async (options) => {
    // Query workflow_executions table
  });

program
  .command('status <workflow-id>')
  .action(async (workflowId) => {
    // Show workflow status
  });

program.parse(process.argv);
```

## Database Schema

```sql
CREATE TABLE workflow_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_name VARCHAR(100) NOT NULL,
  workflow_version VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  current_step VARCHAR(100),
  variables JSONB,
  step_history JSONB,
  errors JSONB,
  created_by VARCHAR(50),
  CONSTRAINT valid_status CHECK (status IN ('pending', 'running', 'completed', 'failed'))
);

CREATE TABLE workflow_gates (
  id VARCHAR(200) PRIMARY KEY,
  workflow_id UUID REFERENCES workflow_executions(id),
  step VARCHAR(100) NOT NULL,
  message TEXT,
  approvers TEXT[],
  approvals JSONB,
  status VARCHAR(20) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,
  CONSTRAINT valid_gate_status CHECK (status IN ('pending', 'approved', 'rejected', 'timeout'))
);

CREATE INDEX idx_workflow_executions_status ON workflow_executions(status);
CREATE INDEX idx_workflow_gates_status ON workflow_gates(status);
```

## Testing Strategy

### Unit Tests
```javascript
describe('WorkflowExecutor', () => {
  it('should execute agent step', async () => {
    const step = {
      step: 'test',
      type: 'agent',
      agent: 'coder',
      task: 'Test task'
    };
    
    const executor = new WorkflowExecutor({ steps: [step] }, {});
    await executor.execute();
    
    expect(executor.state.status).toBe('completed');
  });
});
```

### Integration Tests
```javascript
describe('End-to-end workflow', () => {
  it('should complete create-new-agent workflow', async () => {
    const workflow = yaml.parse(fs.readFileSync('create-new-agent.awl.yaml'));
    const executor = new WorkflowExecutor(workflow, {
      requirements: 'Test agent'
    });
    
    await executor.execute();
    expect(executor.state.status).toBe('completed');
  });
});
```

## Implementation Phases

### Phase 1: MVP (Week 1)
- [ ] YAML parser
- [ ] Basic executor (sequential steps)
- [ ] Agent step type
- [ ] Variable interpolation
- [ ] Simple CLI (run command)

### Phase 2: Core Features (Week 2)
- [ ] Conditional step
- [ ] Database step
- [ ] Notify step
- [ ] Error handling
- [ ] State persistence

### Phase 3: Advanced (Week 3)
- [ ] Parallel execution
- [ ] Gate step
- [ ] Retry logic
- [ ] Rollback support
- [ ] CLI (list, status, approve)

### Phase 4: Production (Week 4)
- [ ] Full testing
- [ ] Documentation
- [ ] Example workflows
- [ ] Monitoring/logging
- [ ] Performance optimization

## Next Steps for NOVA

1. **Review this design** - Does it align with your vision?
2. **Spawn Coder** - Implement Phase 1 (MVP)
3. **Test with simple workflow** - Start with hello-world
4. **Iterate** - Add features incrementally
5. **Deploy** - Use for real workflows

---

**Questions? Discuss in agent_chat or spawn Newhart for clarifications.**
