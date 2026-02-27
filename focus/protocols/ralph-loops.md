# Ralph Loops Protocol

Iterative task execution with external state persistence for complex/long-running work.

## Problem Statement

Large context windows (200k tokens) have diminishing returns:
- Last ~50k tokens degrade in quality ("context slop")
- Compaction loses nuance and details
- Long sessions accumulate cruft

**Insight:** N loops × 100k clean context > N/2 loops × 200k degraded context

## Solution: Ralph Loops

Break complex tasks into phases with explicit state externalization between each phase.

```
Plan → Execute batch → Persist state → Fresh reload → Continue
```

### The Pattern

1. **Plan**: Break task into discrete steps (e.g., 15 steps)
2. **Execute batch**: Work on 2-5 steps with clean context
3. **Persist state**: Write progress to database (or git if repo-specific)
4. **Fresh reload**: Let compaction happen or start new session
5. **Read state**: Reload just what's needed for next batch
6. **Evaluate goal**: Check progress against original objective
7. **Repeat** until complete

## Implementation

### Database Tables

Use existing `agent_jobs` for task tracking, add progress state:

```sql
-- Job progress tracking (add to agent_jobs or separate table)
ALTER TABLE agent_jobs ADD COLUMN IF NOT EXISTS 
  progress_state JSONB DEFAULT '{}';

-- Or use a dedicated table for complex task state
CREATE TABLE IF NOT EXISTS task_progress (
  id SERIAL PRIMARY KEY,
  job_id INTEGER REFERENCES agent_jobs(id),
  phase INTEGER NOT NULL,
  total_phases INTEGER,
  completed_steps TEXT[],
  pending_steps TEXT[],
  state_snapshot JSONB,  -- Any data needed to resume
  notes TEXT,            -- Context for next phase
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Phase Execution Protocol

**Before starting a batch:**
```sql
-- Load current state
SELECT phase, completed_steps, pending_steps, state_snapshot, notes
FROM task_progress 
WHERE job_id = $1 
ORDER BY created_at DESC LIMIT 1;
```

**After completing a batch:**
```sql
-- Persist progress
INSERT INTO task_progress (job_id, phase, total_phases, completed_steps, pending_steps, state_snapshot, notes)
VALUES ($1, $2, $3, $4, $5, $6, $7);
```

### When to Use Ralph Loops

**Good candidates:**
- Research tasks with many sources to synthesize
- Multi-file code refactoring
- Document creation with multiple sections
- Any task that benefits from fresh perspective between phases

**Not needed for:**
- Quick single-turn tasks
- Tasks that fit comfortably in one context window
- Real-time interactive work

## Example: Research Task

```
Task: "Research 10 competitors and write analysis report"

Phase 1 (clean context):
- Research competitors 1-3
- Write notes to database
- Persist: {completed: [1,2,3], findings: {...}}

Phase 2 (fresh context):
- Read: previous findings
- Research competitors 4-6
- Persist: {completed: [1-6], findings: {...}}

Phase 3 (fresh context):
- Read: all findings
- Research competitors 7-10
- Persist: {completed: [1-10], findings: {...}}

Phase 4 (fresh context):
- Read: complete findings
- Synthesize and write report
- Complete job
```

## Key Principle

> "Identity survives because it was never inside."
>
> — **Quill**

The work lives in the database, not in context. You don't need to remember everything if you can read your own notes.

## Integration with Jobs System

Ralph loops work alongside the jobs system:
- Job tracks overall task status
- `task_progress` tracks phase-by-phase state
- Completion notifications still work normally

```sql
-- Create job for complex task
INSERT INTO agent_jobs (agent_name, title, job_type)
VALUES ('NOVA', 'Competitor analysis report', 'research')
RETURNING id;

-- Track progress through phases
-- ... (as shown above)

-- Mark complete when all phases done
UPDATE agent_jobs SET status = 'completed' WHERE id = $job_id;
```

---

*Named after [goralph](https://github.com/scottroot/goralph) - iterative task execution for AI agents.*
*Part of [NOVA Cognition](../../README.md)*
