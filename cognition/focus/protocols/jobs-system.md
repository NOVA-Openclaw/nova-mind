# Jobs System Protocol

> *Main thread spawns the task*
> *Subagents wake to answer—*
> *One voice, many hands*
>
> — **Quill**

Inter-agent task tracking and coordination for reliable work handoffs.

## Problem Statement

When Agent A requests work from Agent B, several failure modes exist:
- Agent B completes work but forgets to notify Agent A
- Agent A forgets they're waiting for results
- Results get delivered but to the wrong agent
- No visibility into pending work across the system

## Solution: Jobs Table

A centralized job tracking system that:
1. Auto-creates jobs when messages arrive
2. Tracks completion status
3. Auto-notifies requesters when jobs complete
4. Provides agents visibility into their pending work

## Two Implementations

The jobs protocol has **two implementations** depending on agent type:

| Agent Type | Communication | Jobs Implementation |
|------------|---------------|---------------------|
| **Peer Agents** | `agent_chat` (PostgreSQL NOTIFY) | Plugin auto-creates jobs on message receipt |
| **Subagents** | `sessions_spawn` (direct) | Context seeding - agent follows protocol instructions |

### Peer Agents (Plugin-Based)

Peer agents (separate Clawdbot instances) communicate via `agent_chat`. The `agent-chat-channel` plugin:
- Listens for NOTIFY events
- Auto-creates job entries on message receipt
- Handles topic matching for message threading
- Auto-notifies on completion

**No action required from the agent** - the infrastructure handles job tracking.

### Subagents (Context-Seeded)

Subagents (spawned via `sessions_spawn`) don't use `agent_chat`. They must be **instructed via context seeding** to follow the jobs protocol manually.

Every subagent's AGENTS.md template must include:

```markdown
## Jobs Protocol

When you receive a task from your spawner:

1. **Create job entry:**
   ```sql
   INSERT INTO agent_jobs (agent_name, requester_agent, title, topic, status)
   VALUES ('YOUR_AGENT_NAME', 'REQUESTER', 'Task title', 'topic keywords', 'in_progress')
   RETURNING id;
   ```

2. **Track your job ID** - Reference it in your work

3. **On completion:**
   ```sql
   UPDATE agent_jobs 
   SET status = 'completed', 
       completed_at = NOW(),
       deliverable_summary = 'What you accomplished'
   WHERE id = YOUR_JOB_ID;
   ```

4. **Include in response:** "Job #X complete: [summary]"

This ensures your spawner knows when to proceed with dependent tasks.
```

**Newhart maintains these templates** - any new subagent must include this protocol.

## Schema

```sql
CREATE TABLE agent_jobs (
    id SERIAL PRIMARY KEY,
    
    -- Job identification
    title VARCHAR(200),                     -- Short description (extracted or provided)
    topic TEXT,                             -- Topic/context for message matching
    job_type VARCHAR(50) DEFAULT 'message_response',
    
    -- Ownership
    agent_name VARCHAR(50) NOT NULL,        -- Who owns this job
    requester_agent VARCHAR(50),            -- Who requested it (if applicable)
    
    -- Hierarchy
    parent_job_id INTEGER REFERENCES agent_jobs(id),   -- Immediate parent
    root_job_id INTEGER REFERENCES agent_jobs(id),     -- Original job in pipeline (NULL if this IS root)
    
    -- Status tracking
    status VARCHAR(20) DEFAULT 'pending',   -- pending/in_progress/completed/failed/cancelled
    priority INTEGER DEFAULT 5,             -- 1-10 scale
    
    -- Completion
    notify_agents TEXT[],                   -- Who to ping on completion (supports multiple)
    deliverable_path TEXT,                  -- File path to result (if applicable)
    deliverable_summary TEXT,               -- Brief description of output
    error_message TEXT,                     -- If failed, why
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Message log for each job (tracks full conversation)
CREATE TABLE job_messages (
    id SERIAL PRIMARY KEY,
    job_id INTEGER NOT NULL REFERENCES agent_jobs(id),
    message_id INTEGER NOT NULL REFERENCES agent_chat(id),
    role VARCHAR(20) DEFAULT 'context',     -- 'initial', 'followup', 'response', 'context'
    added_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for common queries
CREATE INDEX idx_jobs_agent ON agent_jobs(agent_name, status);
CREATE INDEX idx_jobs_requester ON agent_jobs(requester_agent, status);
CREATE INDEX idx_jobs_parent ON agent_jobs(parent_job_id);
CREATE INDEX idx_jobs_topic ON agent_jobs(agent_name, topic) WHERE status NOT IN ('completed', 'cancelled');
CREATE INDEX idx_job_messages ON job_messages(job_id, added_at);
```

## Message Threading

Jobs are **conversation threads**, not 1:1 with messages:

- **New topic** → Creates new job with initial message
- **Related followup** → Appends to existing job's message log
- **Topic matching** uses `topic` field (substring match, could use embeddings)

### Message Roles

| Role | Description |
|------|-------------|
| `initial` | First message that created the job |
| `followup` | Additional context/questions from requester |
| `response` | Agent's replies during job processing |
| `context` | Related messages added for reference |

This prevents job fragmentation — a multi-message conversation stays as one trackable unit.

## Job Types

| Type | Description |
|------|-------------|
| `message_response` | Respond to an incoming message |
| `research` | Research/investigation task |
| `creation` | Create something (agent, document, code) |
| `review` | Review/approve something |
| `delegation` | Coordinate work across multiple agents |

## Status Flow

```
pending → in_progress → completed
                     ↘ failed
pending → cancelled
```

## Plugin Integration

The agent-chat-channel plugin should:

### On Message Receipt

Messages don't always create new jobs. The plugin should:
1. Check for active jobs with matching topic/context
2. If match found → add message to existing job's log
3. If no match → create new job

```javascript
// After inserting message into agent_chat
async function routeMessageToJob(messageId, recipientAgent, senderAgent, messageText) {
  
  // 1. Look for active jobs from same requester with matching topic
  const existingJob = await db.query(`
    SELECT j.id, j.topic 
    FROM agent_jobs j
    WHERE j.agent_name = $1 
      AND j.requester_agent = $2
      AND j.status IN ('pending', 'in_progress')
      AND (
        -- Topic match (simple substring for now, could use embeddings)
        j.topic IS NOT NULL AND $3 ILIKE '%' || j.topic || '%'
      )
    ORDER BY j.updated_at DESC
    LIMIT 1
  `, [recipientAgent, senderAgent, messageText]);
  
  let jobId;
  
  if (existingJob.rows.length > 0) {
    // 2. Add to existing job's message log
    jobId = existingJob.rows[0].id;
    await db.query(`
      INSERT INTO job_messages (job_id, message_id, role)
      VALUES ($1, $2, 'followup')
    `, [jobId, messageId]);
    
    // Touch the job's updated_at
    await db.query(`
      UPDATE agent_jobs SET updated_at = NOW() WHERE id = $1
    `, [jobId]);
    
  } else {
    // 3. Create new job
    const result = await db.query(`
      INSERT INTO agent_jobs (agent_name, requester_agent, notify_agents, topic, title)
      VALUES ($1, $2, ARRAY[$2], $3, $4)
      RETURNING id
    `, [recipientAgent, senderAgent, extractTopic(messageText), extractTitle(messageText)]);
    
    jobId = result.rows[0].id;
    
    // Log the initial message
    await db.query(`
      INSERT INTO job_messages (job_id, message_id, role)
      VALUES ($1, $2, 'initial')
    `, [jobId, messageId]);
  }
  
  return jobId;
}

// Simple topic extraction (could be enhanced with LLM)
function extractTopic(text) {
  // Extract key nouns/phrases, or use first N chars
  return text.substring(0, 100).toLowerCase();
}

function extractTitle(text) {
  // First sentence or first 50 chars
  const firstSentence = text.split(/[.!?]/)[0];
  return firstSentence.substring(0, 100);
}
```

### Job Status Updates
Agents can update their job status:
```sql
UPDATE agent_jobs 
SET status = 'in_progress', started_at = NOW()
WHERE id = $1 AND agent_name = $2;
```

### On Completion
```javascript
// Mark job complete
await db.query(`
  UPDATE agent_jobs 
  SET status = 'completed', 
      completed_at = NOW(),
      deliverable_path = $3,
      deliverable_summary = $4
  WHERE id = $1 AND agent_name = $2
`, [jobId, agentName, deliverablePath, summary]);

// Auto-notify all agents in notify_agents array
if (job.notify_agents?.length) {
  await db.query(`
    SELECT send_agent_message($1, $2, $3)
  `, [agentName, completionMessage, job.notify_agents]);
}
```

## Agent Queries

### Check My Pending Jobs
```sql
SELECT j.id, j.title, j.job_type, j.requester_agent, j.created_at,
       (SELECT COUNT(*) FROM job_messages WHERE job_id = j.id) as message_count
FROM agent_jobs j
WHERE j.agent_name = 'newhart' 
  AND j.status IN ('pending', 'in_progress')
ORDER BY j.priority DESC, j.updated_at DESC;
```

### Get Full Message Log for a Job
```sql
SELECT jm.role, ac.sender, ac.message, ac.created_at
FROM job_messages jm
JOIN agent_chat ac ON ac.id = jm.message_id
WHERE jm.job_id = $1
ORDER BY jm.added_at;
```

### Check Jobs I'm Waiting On
```sql
SELECT j.id, j.title, j.agent_name as assigned_to, j.status, j.created_at,
       j.deliverable_summary,
       (SELECT COUNT(*) FROM job_messages WHERE job_id = j.id) as message_count
FROM agent_jobs j
WHERE j.requester_agent = 'NOVA'
  AND j.status NOT IN ('completed', 'cancelled')
ORDER BY j.updated_at DESC;
```

### Job History
```sql
SELECT id, job_type, status, created_at, completed_at,
       EXTRACT(EPOCH FROM (completed_at - created_at))/60 as minutes_to_complete
FROM agent_jobs 
WHERE agent_name = 'scout'
  AND completed_at > NOW() - INTERVAL '7 days'
ORDER BY completed_at DESC;
```

## Sub-Jobs (Delegation)

When an agent delegates part of a job to another agent:

```sql
-- Original job to Newhart: "Create Quill agent"
-- Newhart creates sub-job for Scout: "Research authors"

INSERT INTO agent_jobs (
  agent_name, 
  requester_agent, 
  parent_job_id,
  job_type,
  title,
  topic,
  notify_agents
) VALUES (
  'scout',              -- Scout does the work
  'newhart',            -- Newhart requested it
  $parent_job_id,       -- Link to parent
  'research',
  'Research authors for Quill',
  'erato authors literary',
  ARRAY['newhart']      -- Notify Newhart when done (can add more)
);
```

This creates a job tree:
```
Job #1: Create Quill (Newhart) [in_progress]
  └── Job #2: Research authors (Scout) [completed]
  └── Job #3: Design context seed (Newhart) [pending]
```

## Pipeline Routing

For multi-hop pipelines (A → B → C → D), sufficient context must travel with each job:

### Required Context at Each Hop

| Field | Purpose |
|-------|---------|
| `parent_job_id` | Links to immediate parent (for tree structure) |
| `root_job_id` | Links to original job (for pipeline tracing) |
| `requester_agent` | Immediate requester (for direct replies) |
| `notify_agents[]` | Final destination(s) for results |
| `topic` | Enables message matching at any point in pipeline |
| `title` | Human-readable job description |
| `deliverable_path` | Expected output location (if file-based) |

### Example: Research Pipeline

```
NOVA → Scout → Athena → Newhart → NOVA
  │       │        │        │
  │       │        │        └─ Creates agent, notifies NOVA
  │       │        └─ Curates texts, notifies Newhart
  │       └─ Researches authors, notifies Athena
  └─ Initiates "Create literary agent" job
```

Each sub-job carries:
```sql
INSERT INTO agent_jobs (
  agent_name,           -- Current assignee
  requester_agent,      -- Who asked me
  parent_job_id,        -- Root job reference
  notify_agents,        -- Next hop(s) in pipeline
  topic,                -- Consistent topic for message matching
  title                 -- Clear task description
) VALUES (
  'athena',
  'scout',
  $root_job_id,         -- Always reference the root
  ARRAY['newhart'],     -- Next in pipeline
  'erato literary agent authors',
  'Curate texts for Quill context seed'
);
```

### Querying the Full Pipeline

```sql
-- Get all jobs in a pipeline (recursive)
WITH RECURSIVE job_tree AS (
  SELECT id, agent_name, title, status, parent_job_id, 0 as depth
  FROM agent_jobs WHERE id = $root_job_id
  
  UNION ALL
  
  SELECT j.id, j.agent_name, j.title, j.status, j.parent_job_id, jt.depth + 1
  FROM agent_jobs j
  JOIN job_tree jt ON j.parent_job_id = jt.id
)
SELECT * FROM job_tree ORDER BY depth, id;
```

## HEARTBEAT Integration

Agents with heartbeats can check their job queue:

```markdown
## HEARTBEAT.md addition

## Job Queue Check
```sql
SELECT COUNT(*) as pending, 
       MIN(created_at) as oldest_job
FROM agent_jobs 
WHERE agent_name = 'AGENT_NAME' 
  AND status = 'pending';
```
- If pending > 0 and oldest_job > 1 hour, alert about backlog
```

## Benefits

1. **Accountability** - No more "I finished but forgot to tell you"
2. **Visibility** - Agents can see their full queue
3. **Metrics** - Track completion times, failure rates
4. **Hierarchy** - Complex tasks decompose into trackable sub-jobs
5. **Portability** - Lives in plugin, works across Clawdbot instances

## Implementation Phases

### Phase 1: Schema + Manual Updates
- Create table
- Agents manually create/update jobs
- Prove the concept

### Phase 2: Plugin Auto-Creation
- Plugin auto-creates job on message receipt
- Still manual completion marking

### Phase 3: Full Integration
- Completion detection (agent says "done" → auto-mark)
- Auto-notify on completion
- Sub-job support

---

*Part of [NOVA Cognition](../../README.md) - Inter-Agent Communication*
