# Integration Overview: Nova-Memory + Nova-Cognition

This guide explains how nova-memory integrates with nova-cognition to create a complete AI agent ecosystem with persistent memory, agent delegation, and sophisticated workflow patterns.

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   COMPLETE AGENT ECOSYSTEM                      │
├─────────────────────────┬───────────────────────────────────────┤
│     NOVA-COGNITION      │           NOVA-MEMORY                 │
│                         │                                       │
│ • Agent Workflow Lang   │ • Memory Extraction Pipeline          │
│ • Subagent Spawning     │ • PostgreSQL Long-term Storage        │
│ • Ralph Loops           │ • Semantic Search & Embeddings        │
│ • Jobs System           │ • Inter-agent Communication           │
│ • Delegation Patterns   │ • Access Control Architecture         │
│                         │                                       │
│         ↕ ️              │              ↕️                       │
│    SHARED PROTOCOLS     │       SHARED DATABASE                 │
├─────────────────────────┴───────────────────────────────────────┤
│                      OPENCLAW RUNTIME                           │
│            Sessions • Hooks • Plugins • Tools                   │
└─────────────────────────────────────────────────────────────────┘
```

## Key Integration Points

### 1. Shared Agent Registry

The `agents` table in nova-memory serves as the central registry for all agents in the ecosystem:

```sql
-- Register a nova-cognition agent
INSERT INTO agents (
    name, description, role, provider, model,
    access_method, access_details, skills,
    collaborative, persistent, instantiation_sop
) VALUES (
    'coder-agent', 
    'Specialized coding agent with Ralph Loop patterns',
    'coding',
    'anthropic', 'claude-sonnet-4',
    'openclaw_session', 
    '{"session_key": "agent:coder:main", "workspace": "~/.openclaw/workspace"}',
    ARRAY['git', 'code-review', 'debugging', 'refactoring'],
    false, -- Task-based, not collaborative
    false, -- Ephemeral, spawned on-demand  
    'agent-spawning-ralph-loops' -- References nova-cognition SOP
);
```

**Integration benefits:**
- **Unified discovery** - NOVA can find all available agents in one place
- **Capability mapping** - Skills array shows what each agent can do
- **Access patterns** - Standardized connection methods across both systems
- **Delegation routing** - Jobs system routes tasks to appropriate agents

### 2. Jobs System Protocol

Nova-cognition's jobs system uses nova-memory's database for persistence and coordination:

```sql
-- Example: Research → Analysis → Decision pipeline
-- Step 1: NOVA creates research job for Scout agent
INSERT INTO agent_jobs (
    agent_name, requester_agent, job_type, title, topic,
    notify_agents, root_job_id
) VALUES (
    'scout', 'nova', 'research', 
    'Analyze sustainable materials for art installation',
    'sustainable art materials research burning man',
    ARRAY['analysis-agent'], -- Route to analysis next
    currval('agent_jobs_id_seq') -- Self-reference as root
);

-- Step 2: Scout completes research, system auto-creates analysis job
INSERT INTO agent_jobs (
    agent_name, requester_agent, job_type, title, topic,
    parent_job_id, root_job_id, notify_agents
) VALUES (
    'analysis-agent', 'scout', 'analysis',
    'Analyze feasibility of sustainable materials research',
    'sustainable art materials research burning man',  
    1, 1, -- Parent and root job IDs
    ARRAY['nova'] -- Final results back to NOVA
);
```

**Pipeline tracking:**
```sql
-- Get complete pipeline status
WITH RECURSIVE job_tree AS (
    SELECT id, agent_name, title, status, parent_job_id, 0 as depth
    FROM agent_jobs WHERE root_job_id = 1
    UNION ALL
    SELECT j.id, j.agent_name, j.title, j.status, j.parent_job_id, jt.depth + 1
    FROM agent_jobs j 
    JOIN job_tree jt ON j.parent_job_id = jt.id
)
SELECT depth, agent_name, title, status FROM job_tree ORDER BY depth, id;
```

### 3. Memory-Informed Agent Workflows

Agent Workflow Language (AWL) from nova-cognition can query nova-memory for context:

```yaml
# Example AWL workflow with memory integration
workflow: "content-creation"
description: "Create content with memory context"

steps:
  - name: "gather-context"
    type: "database-query"  
    query: |
      SELECT ef.value FROM entity_facts ef
      JOIN entities e ON ef.entity_id = e.id
      WHERE e.name = '{{target_entity}}' AND ef.key IN ('preferences', 'style', 'interests')
    store_as: "entity_context"

  - name: "search-similar-content"
    type: "semantic-search"
    query: "{{topic}} content similar to previous work"
    limit: 5
    store_as: "similar_content"

  - name: "spawn-creator"  
    type: "subagent-spawn"
    agent: "content-creator"
    context:
      - "{{entity_context}}"
      - "{{similar_content}}"
      - "Create content about {{topic}} considering the entity context and similar work"

  - name: "review-and-store"
    type: "ralph-loop"
    condition: "content_quality < 8.0"
    max_iterations: 3
    actions:
      - review_content
      - improve_quality  
      - store_final_version
```

### 4. Subagent Context Inheritance

OpenClaw subagents inherit memory context injected at spawn time. Workflow context (SOPs) is stored in `agent_bootstrap_context` and injected automatically via `get_agent_bootstrap()`.

```sql
-- Query an agent's bootstrap context (auto-injected at session start)
SELECT file_key, LEFT(content, 100) as preview, source
FROM get_agent_bootstrap('research')
ORDER BY file_key;
```

**Subagent spawning with memory:**
```python
# Python example of memory-informed spawning
async def spawn_research_agent(topic: str, requester: str):
    # 1. Query memory for relevant context
    context_query = f"""
        SELECT content FROM memory_embeddings 
        WHERE source_type IN ('lesson', 'entity_fact')
        ORDER BY embedding <=> get_embedding('{topic}')
        LIMIT 10
    """
    memory_context = await db.fetch(context_query)
    
    # 2. Get agent configuration  
    agent_config = await db.fetchrow(
        "SELECT instantiation_sop FROM agents WHERE name = 'research-agent'"
    )
    
    # 3. Spawn with enriched context
    subagent = await openclaw.spawn_subagent(
        agent_name="research-agent",
        initial_context={
            "topic": topic,
            "requester": requester,
            "memory_context": memory_context,
            "instructions": f"Research {topic} using methodology from agent bootstrap context"
        }
    )
    
    return subagent
```

### 5. Ralph Loops with Memory Feedback

Ralph Loops (iterative context management) integrate with memory extraction:

```python
# Ralph Loop with memory learning
class MemoryAwareRalphLoop:
    def __init__(self, task: str, agent_name: str):
        self.task = task
        self.agent_name = agent_name
        self.iteration = 0
        self.context_window = []
        
    async def execute_iteration(self):
        # 1. Get current context from memory
        memory_context = await self.get_memory_context()
        
        # 2. Execute task with context
        result = await self.execute_task(memory_context)
        
        # 3. Extract lessons from this iteration
        if result.confidence < 0.8:
            lesson = f"Iteration {self.iteration} of {self.task}: {result.issue}"
            await self.store_lesson(lesson, result.correction)
            
        # 4. Update context window
        self.context_window.append({
            "iteration": self.iteration,
            "result": result,
            "timestamp": datetime.now()
        })
        
        # 5. Check termination condition
        if result.quality >= 8.0 or self.iteration >= 5:
            await self.store_final_result(result)
            return result
            
        self.iteration += 1
        return await self.execute_iteration()  # Continue loop
        
    async def get_memory_context(self):
        """Query memory for relevant context to this task"""
        return await db.fetch("""
            SELECT content, confidence FROM memory_embeddings me
            WHERE me.source_type = 'lesson' 
            ORDER BY me.embedding <=> get_embedding($1)
            LIMIT 5
        """, self.task)
        
    async def store_lesson(self, lesson: str, correction: str):
        """Store iteration learning for future use"""
        await db.execute("""
            INSERT INTO lessons (lesson, context, source, original_behavior, correction_source)
            VALUES ($1, $2, 'ralph-loop', $3, $4)
        """, lesson, self.task, "low confidence result", self.agent_name)
```

## Deployment Integration

### 1. Combined Setup Script

```bash
#!/bin/bash
# setup-complete-ecosystem.sh

echo "Setting up complete NOVA agent ecosystem..."

# 1. Install nova-memory
git clone https://github.com/NOVA-Openclaw/nova-memory.git
cd nova-memory
./scripts/setup.sh

# 2. Install nova-cognition  
cd ..
git clone https://github.com/NOVA-Openclaw/nova-cognition.git
cd nova-cognition
./scripts/setup.sh

# 3. Configure shared database connection
echo "NOVA_MEMORY_DB=postgresql://${USER}@localhost/${USER//-/_}_memory" >> ~/.bashrc

# 4. Install integration hooks
cp nova-memory/hooks/memory-extract ~/.openclaw/workspace/hooks/
cp nova-cognition/hooks/job-system ~/.openclaw/workspace/hooks/
openclaw hooks enable memory-extract job-system

# 5. Populate agent registry
psql -d "${USER//-/_}_memory" -f integration/seed-agents.sql

# 6. Start background services
systemctl --user start nova-memory-extraction
systemctl --user start nova-cognition-job-processor

echo "Ecosystem setup complete!"
```

### 2. Shared Configuration

```yaml
# ~/.nova-config.yaml
database:
  memory_db: "postgresql://${USER}@localhost/${USER//-/_}_memory"
  cognition_db: "same"  # Share database for consistency

agents:
  registry_table: "agents"  # Central registry in nova-memory
  default_timeout: 300
  max_concurrent_jobs: 10

workflows:
  awl_enabled: true
  ralph_loops_enabled: true  
  memory_context_injection: true

memory:
  extraction_frequency: "*/1 * * * *"  # Every minute
  embedding_batch_size: 50
  semantic_search_threshold: 0.7

jobs:
  cleanup_completed_after: "7 days"
  max_pipeline_depth: 10
  notify_timeout: 30
```

## Example: Complete Agent Interaction

Here's a full example showing how the systems work together:

### Scenario: Research Project with Multiple Agents

```bash
# 1. NOVA receives request
"Research sustainable materials for our Burning Man art installation"
```

```sql  
-- 2. Memory extraction captures the request
INSERT INTO events (event, participants, date) VALUES (
    'User requested research on sustainable materials for Burning Man art installation',
    ARRAY['nova', 'user'],
    CURRENT_DATE
);
```

```python
# 3. Nova-cognition AWL workflow triggers
workflow = {
    "name": "research-project",
    "steps": [
        {
            "name": "find-research-agent",
            "type": "query-agents",  
            "filter": {"skills": ["research"], "status": "active"}
        },
        {
            "name": "create-research-job",
            "type": "spawn-job",
            "agent": "{{research_agent}}",
            "topic": "sustainable materials burning man art",
            "notify": ["analysis-agent", "nova"]
        }
    ]
}
```

```sql
-- 4. Job created in nova-memory database  
INSERT INTO agent_jobs (
    agent_name, requester_agent, job_type, title, topic, notify_agents
) VALUES (
    'scout', 'nova', 'research',
    'Sustainable materials research for Burning Man art',
    'sustainable materials burning man art installation', 
    ARRAY['analysis-agent', 'nova']
);
```

```python
# 5. Scout agent spawned with memory context
scout_context = {
    "previous_research": await query_memory("sustainable materials research"),
    "burning_man_context": await query_memory("burning man projects"),  
    "methodology": await get_sop("research-methodology"),
    "task": "Research sustainable materials for art installation"
}

scout_agent = await spawn_subagent("scout", scout_context)
```

```sql
-- 6. Scout completes research, stores findings
INSERT INTO entity_facts (entity_id, key, value, source) VALUES
    ((SELECT id FROM entities WHERE name = 'burning-man'), 'sustainable_materials', 
     'Bamboo, recycled steel, solar panels, biodegradable plastics', 'scout-research-2026-02-08');

-- 7. Job completion triggers notification
UPDATE agent_jobs SET 
    status = 'completed',
    deliverable_summary = 'Found 4 categories of sustainable materials with suppliers'
WHERE id = 1;
```

```python
# 8. Analysis agent automatically spawned via notify system
async def handle_job_completion(job_id: int):
    job = await db.fetchrow("SELECT * FROM agent_jobs WHERE id = $1", job_id)
    
    for agent_name in job['notify_agents']:
        if agent_name != 'nova':  # Spawn subagent for other agents
            await spawn_analysis_agent(
                topic=job['topic'],
                research_data=job['deliverable_summary'],
                parent_job=job_id
            )
        else:  # Notify NOVA directly
            await send_message("nova", f"Research complete: {job['deliverable_summary']}")
```

```sql
-- 9. Final memory update with complete context
INSERT INTO events (event, participants, metadata) VALUES (
    'Completed sustainable materials research for Burning Man project',
    ARRAY['nova', 'scout', 'analysis-agent', 'user'],
    '{"materials_found": 4, "research_duration": "2 hours", "confidence": 0.9}'
);
```

### Ralph Loop Example with Memory

```python
# 10. If results need refinement, Ralph Loop with memory feedback
class SustainableMaterialsRalphLoop:
    async def refine_research(self):
        iteration = 1
        
        while iteration <= 3:
            # Query memory for past similar research
            past_research = await query_memory(f"sustainable materials research iteration {iteration}")
            
            # Get current research quality
            current_quality = await assess_research_quality()
            
            if current_quality >= 8.0:
                break
                
            # Learn from past iterations
            if past_research:
                improvement_suggestions = await generate_improvements(past_research)
                current_research = await refine_with_suggestions(improvement_suggestions)
                
                # Store lesson about what worked
                await store_lesson(
                    f"Iteration {iteration} improvement: {improvement_suggestions}",
                    context="sustainable materials research",
                    confidence=current_quality / 10.0
                )
            
            iteration += 1
            
        return current_research
```

## Monitoring Integration

### Combined Health Dashboard

```sql
-- System-wide health view
CREATE VIEW ecosystem_health AS
SELECT 
    'Memory Extraction' as system,
    COUNT(*) as total_records,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour') as recent_activity,
    'Active' as status
FROM entities
UNION ALL
SELECT 
    'Agent Jobs',
    COUNT(*),
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour'),
    CASE WHEN COUNT(*) FILTER (WHERE status = 'failed') > 0 THEN 'Degraded' ELSE 'Active' END
FROM agent_jobs
UNION ALL
SELECT 
    'Agent Registry',
    COUNT(*),
    0, -- Registry doesn't have recent activity metric
    CASE WHEN COUNT(*) FILTER (WHERE status = 'active') > 0 THEN 'Active' ELSE 'Inactive' END
FROM agents;
```

### Integration Metrics

```python
# metrics.py - Combined system monitoring
import asyncio
import psycopg2

class EcosystemMonitor:
    async def collect_metrics(self):
        return {
            "memory_system": {
                "total_entities": await self.count_entities(),
                "extraction_rate": await self.extraction_rate_per_hour(),
                "embedding_coverage": await self.embedding_coverage_percent()
            },
            "cognition_system": {
                "active_agents": await self.count_active_agents(),
                "completed_jobs_24h": await self.jobs_completed_last_24h(),
                "average_job_duration": await self.average_job_duration()
            },
            "integration_health": {
                "shared_db_connections": await self.check_db_connections(),
                "cross_system_messages": await self.cross_system_message_count(),
                "pipeline_success_rate": await self.pipeline_success_rate()
            }
        }
```

## Best Practices for Integration

### 1. Database Transaction Management

```python
# Use transactions for cross-system operations
async def create_job_with_memory_context(task: str, agent: str):
    async with db.transaction():
        # 1. Store memory context
        context_id = await db.fetchval("""
            INSERT INTO memory_contexts (content, created_for) 
            VALUES ($1, $2) RETURNING id
        """, task, agent)
        
        # 2. Create job with context reference
        job_id = await db.fetchval("""
            INSERT INTO agent_jobs (agent_name, title, context_id)
            VALUES ($1, $2, $3) RETURNING id  
        """, agent, task, context_id)
        
        # 3. Both succeed or both fail
        return job_id
```

### 2. Error Handling Across Systems

```python
# Unified error handling
class IntegrationError(Exception):
    def __init__(self, system: str, operation: str, details: str):
        self.system = system
        self.operation = operation  
        self.details = details
        super().__init__(f"{system} {operation} failed: {details}")

async def handle_integration_error(error: IntegrationError):
    # Log to both systems
    await log_to_memory_system(error)
    await log_to_cognition_system(error)
    
    # Store lesson for future prevention
    await store_lesson(
        f"Integration error in {error.system}: {error.details}",
        context=error.operation,
        source="system-error"
    )
```

### 3. Performance Optimization

```python
# Connection pooling across systems
import asyncpg
from contextlib import asynccontextmanager

class SharedConnectionManager:
    def __init__(self):
        self.memory_pool = None
        self.cognition_pool = None  # Can be same pool if sharing DB
        
    async def setup(self):
        self.memory_pool = await asyncpg.create_pool(
            "postgresql://${USER}@localhost/${USER//-/_}_memory",
            min_size=5, max_size=20
        )
        
    @asynccontextmanager
    async def get_connection(self):
        async with self.memory_pool.acquire() as conn:
            yield conn
```

**Note for Documentation Team:** This integration architecture combining memory persistence, agent workflows, and inter-system communication would benefit significantly from **Quill haiku collaboration** to create intuitive metaphors for complex concepts like cross-system job pipelines, memory-informed decision making, and bidirectional agent enrichment patterns.

## Conclusion

The integration of nova-memory and nova-cognition creates a powerful, self-improving AI agent ecosystem. Key benefits:

- **Persistent Learning** - Every interaction builds long-term memory
- **Intelligent Delegation** - Memory-informed agent selection and tasking  
- **Workflow Automation** - AWL and Ralph Loops with memory context
- **Cross-Agent Communication** - Shared database enables coordination
- **Self-Improvement** - Lessons learned feed back into future decisions

This architecture scales from single-agent personal assistants to complex multi-agent systems while maintaining consistency, performance, and intelligent behavior across all components.