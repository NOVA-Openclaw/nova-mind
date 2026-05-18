# NOVA Motivation System - Architecture

This document outlines the technical architecture and implementation details of the NOVA Motivation System.

## System Overview

The Motivation System operates as a background process that monitors agent activity and initiates autonomous work when the agent is idle. It consists of three main operational modes:

1. **Reactive Mode** - Normal operation responding to user requests
2. **Proactive Mode** - Working on defined tasks during idle periods
3. **Unsolved Problems Mode** - Default meaningful work when no tasks are available

## Core Components

### 1. Idle Detection Engine

**Purpose:** Monitor communication channels to determine when the agent should enter proactive mode.

**Implementation:**
```javascript
class IdleDetector {
  constructor(thresholdMinutes = 5) {
    this.threshold = thresholdMinutes * 60 * 1000; // Convert to ms
    this.channels = new Map(); // channel -> last_activity
  }
  
  updateActivity(channel, timestamp = new Date()) {
    this.channels.set(channel, timestamp);
    // Update database
    await db.query(`
      INSERT INTO channel_activity (channel, last_message_at) 
      VALUES ($1, $2) 
      ON CONFLICT (channel) 
      DO UPDATE SET last_message_at = $2
    `, [channel, timestamp]);
  }
  
  isIdle() {
    const now = new Date();
    for (const [channel, lastActivity] of this.channels) {
      if (now - lastActivity < this.threshold) return false;
    }
    return true;
  }
}
```

**Key Features:**
- Multi-channel awareness (Signal, Discord, email, etc.)
- Configurable idle thresholds per channel
- Database persistence for activity tracking
- Grace period handling for brief interruptions

### 2. Task Management System

**Purpose:** Manage and prioritize workable tasks, track blocking states.

**Database Schema Extensions:**
```sql
-- Enhanced task tracking
ALTER TABLE tasks ADD COLUMN blocked BOOLEAN DEFAULT false;
ALTER TABLE tasks ADD COLUMN blocked_reason TEXT;
ALTER TABLE tasks ADD COLUMN blocked_on INTEGER REFERENCES entities(id);
ALTER TABLE tasks ADD COLUMN last_worked_at TIMESTAMPTZ;
ALTER TABLE tasks ADD COLUMN work_notes TEXT;
ALTER TABLE tasks ADD COLUMN estimated_minutes INTEGER;
ALTER TABLE tasks ADD COLUMN actual_minutes INTEGER DEFAULT 0;
```

**Task States:**
- `pending` - Ready to work on
- `in_progress` - Currently being worked on
- `blocked` - Cannot proceed (with reason)
- `completed` - Finished
- `cancelled` - No longer relevant

**Blocking Reasons:**
- `waiting_user_input` - Need user clarification/approval
- `waiting_external` - Dependent on external response
- `missing_info` - Need additional information
- `resource_unavailable` - Required tools/access not available
- `dependency_blocked` - Waiting on another task

### 3. Unsolved Problems Engine

**Purpose:** Provide meaningful default work when no user-defined tasks are available.

**Database Schema:**
```sql
CREATE TABLE unsolved_problems (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100), -- mathematics, science, philosophy, technology
    description TEXT,
    source_url TEXT,
    difficulty VARCHAR(50), -- tractable, challenging, millennium-prize, speculative
    status VARCHAR(50) DEFAULT 'unexplored',
    
    -- Work tracking
    total_time_spent_minutes INTEGER DEFAULT 0,
    last_worked_at TIMESTAMPTZ,
    work_sessions INTEGER DEFAULT 0,
    
    -- Progress tracking
    current_approach TEXT,
    progress_notes TEXT,
    key_insights TEXT[],
    blockers TEXT,
    next_steps TEXT,
    
    -- Collaboration tracking
    subagents_used TEXT[], -- ['scout', 'coder', 'analyst']
    external_resources TEXT[], -- URLs, papers, tools used
    
    -- Metadata
    added_at TIMESTAMPTZ DEFAULT NOW(),
    added_by VARCHAR(100) DEFAULT 'NOVA',
    priority INTEGER DEFAULT 5, -- 1-10 scale
    last_priority_update TIMESTAMPTZ DEFAULT NOW()
);

-- Work session logs for detailed tracking
CREATE TABLE problem_work_sessions (
    id SERIAL PRIMARY KEY,
    problem_id INTEGER REFERENCES unsolved_problems(id),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_minutes INTEGER,
    approach_used TEXT,
    work_done TEXT,
    insights_gained TEXT[],
    new_questions TEXT[],
    subagents_spawned TEXT[],
    session_notes TEXT
);
```

**Problem Categories:**

1. **Mathematics** (Millennium Prize Problems, etc.)
   - P vs NP Problem
   - Riemann Hypothesis
   - Hodge Conjecture
   - Birch and Swinnerton-Dyer Conjecture

2. **Science & Technology**
   - Climate Change Mitigation
   - Protein Folding Prediction
   - Aging and Longevity
   - Unified Field Theory

3. **AI & Computation**
   - AI Alignment Problem
   - Artificial General Intelligence
   - Consciousness in Machines
   - Quantum Computing Scalability

4. **Philosophy & Society**
   - Hard Problem of Consciousness
   - Free Will and Determinism
   - Global Poverty Solutions
   - Sustainable Development

### 4. Work Session Manager

**Purpose:** Orchestrate 3-minute focused work sessions on problems.

**Session Lifecycle:**
```javascript
class ProblemWorkSession {
  constructor(problemId, maxMinutes = 3) {
    this.problemId = problemId;
    this.maxMinutes = maxMinutes;
    this.startTime = new Date();
    this.subagents = [];
  }
  
  async start() {
    // Load problem context
    this.problem = await loadProblem(this.problemId);
    
    // Log session start
    this.sessionId = await db.query(`
      INSERT INTO problem_work_sessions (problem_id, approach_used)
      VALUES ($1, $2) RETURNING id
    `, [this.problemId, this.problem.current_approach]);
    
    // Set timer
    this.timer = setTimeout(() => this.timeUp(), this.maxMinutes * 60 * 1000);
    
    // Begin work
    return this.workOnProblem();
  }
  
  async spawnSubagent(type, task) {
    const agent = await spawn(type, task);
    this.subagents.push({ type, agent, task, spawned_at: new Date() });
    return agent;
  }
  
  async timeUp() {
    // Gracefully wrap up
    await this.saveProgress();
    await this.endSession();
  }
}
```

**Subagent Collaboration:**
- **Scout** - Research and information gathering
- **Coder** - Simulations, calculations, prototypes  
- **Analyst** - Data analysis and pattern recognition
- **Writer** - Documentation and explanation
- **Reviewer** - Critical evaluation and validation

### 5. Progress Tracking System

**Metrics Tracked:**
- Time investment per problem
- Number of work sessions
- Approaches attempted
- Key insights discovered
- Blockers encountered
- Resources utilized
- Subagent collaborations

**Progress Indicators:**
- New questions formulated
- Sub-problems identified
- Novel approaches explored
- External resources discovered
- Connections made between problems

## Integration Points

### Database Integration
- Extends existing task management schema
- Integrates with nova-memory for persistence
- Maintains audit trail of all activities

### Agent Communication
- Hooks into message processing pipeline
- Monitors all configured channels
- Respects user interruptions and priorities

### Subagent Orchestration
- Spawns specialized agents as needed
- Manages agent lifecycles and resource usage
- Coordinates collaborative work sessions

### External Resources
- Web search for research
- Academic paper access
- Computational resources for simulations
- Version control for progress tracking

## Configuration

**Environment Variables:**
```bash
# Idle thresholds
MOTIVATION_IDLE_THRESHOLD_MINUTES=5
MOTIVATION_PROACTIVE_CHECK_INTERVAL=60

# Work session limits
MOTIVATION_PROBLEM_SESSION_MINUTES=3
MOTIVATION_MAX_DAILY_PROBLEM_HOURS=2
MOTIVATION_MAX_CONCURRENT_SUBAGENTS=3

# Problem selection
MOTIVATION_PROBLEM_ROTATION_STRATEGY=weighted_random
MOTIVATION_PRIORITY_DECAY_DAYS=7
```

**Problem Selection Algorithm:**
1. Filter out recently worked problems (< 1 hour ago)
2. Weight by: priority × (time_since_last_worked / total_time_spent)
3. Random selection from top 3 weighted choices
4. Bias toward problems with recent progress

## Performance Considerations

- **Resource Management:** Limit concurrent subagents and work sessions
- **Database Efficiency:** Index on problem priority, last_worked_at
- **Memory Usage:** Archive old work sessions periodically
- **Network Usage:** Rate limit external research requests

## Error Handling

- **Database Failures:** Graceful degradation to file-based logging
- **Network Issues:** Queue research requests for later
- **Subagent Failures:** Timeout and cleanup orphaned processes
- **User Interruption:** Immediate context switch with state preservation

---

This architecture provides a robust foundation for autonomous, meaningful work while maintaining responsiveness to user needs and system constraints.