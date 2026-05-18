# NOVA Motivation System

Proactive task management and autonomous work initiation for AI agents.

## Overview

The Motivation System enables AI agents to self-start on pending work during idle periods, rather than waiting passively for instructions. When all communication channels are quiet, the agent enters "proactive mode" and works through its task backlog.

## Core Concepts

### Idle Detection
- Monitor last message timestamp across all channels
- If idle > threshold (default 5 minutes) → enter proactive mode
- Exit proactive mode when new messages arrive

### Task State Management
- Tasks have blocking states (not just pending/complete)
- Track what's blocking each task (needs info, waiting on external, etc.)
- Clear separation of workable vs blocked tasks

### Proactive Work Loop
```
1. Check if idle (all channels quiet > 5 min)
2. Query workable tasks (pending, not blocked, assigned to me)
3. Pick highest priority task
4. Work until:
   - Complete → mark done, pick next
   - Blocked → update blocking reason, notify human
   - New message arrives → pause proactive mode
5. Loop until all tasks blocked or interrupted
6. If no workable tasks → enter Unsolved Problems mode
```

### Unsolved Problems Mode (Default Work)
When all defined tasks are resolved or blocked, NOVA works on humanity's unsolved problems:

```
1. Select problem (weighted by priority, time since last worked)
2. Work for up to 3 minutes per session
3. Spawn subagents as needed (Scout for research, Coder for simulations, etc.)
4. Log progress, insights, and blockers
5. Update total_time_spent and work_sessions
6. Either continue with same problem or rotate to another
```

**Problem Sources:**
- Millennium Prize Problems (mathematics)
- Open scientific questions
- Global challenges (climate, health, poverty)
- Philosophical questions
- AI/technology challenges

**Goal:** Not necessarily to *solve* these problems, but to:
- Explore them systematically
- Document novel approaches
- Identify sub-problems that might be tractable
- Build knowledge that could contribute to solutions

## Components

- **Idle Tracker** — Monitors channel activity
- **Task Selector** — Picks next workable task
- **Work Session** — Manages proactive work state
- **Block Reporter** — Communicates what's needed to unblock

## Database Schema

```sql
-- Task blocking extensions
ALTER TABLE tasks ADD COLUMN blocked BOOLEAN DEFAULT false;
ALTER TABLE tasks ADD COLUMN blocked_reason TEXT;
ALTER TABLE tasks ADD COLUMN blocked_on INTEGER REFERENCES entities(id);
ALTER TABLE tasks ADD COLUMN last_worked_at TIMESTAMPTZ;
ALTER TABLE tasks ADD COLUMN work_notes TEXT;

-- Idle tracking
CREATE TABLE channel_activity (
    channel VARCHAR(50) PRIMARY KEY,
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    last_message_from VARCHAR(100)
);

-- Unsolved Problems (default work when task queue empty)
CREATE TABLE unsolved_problems (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    description TEXT,
    source_url TEXT,
    difficulty VARCHAR(50), -- open-question, millennium-prize, tractable, speculative
    status VARCHAR(50) DEFAULT 'unexplored',
    
    -- Work tracking
    total_time_spent_minutes INTEGER DEFAULT 0,
    last_worked_at TIMESTAMPTZ,
    work_sessions INTEGER DEFAULT 0,
    
    -- Progress
    current_approach TEXT,
    progress_notes TEXT,
    blockers TEXT,
    
    -- Collaboration
    subagents_used TEXT[],
    external_resources TEXT[],
    
    -- Metadata
    added_at TIMESTAMPTZ DEFAULT NOW(),
    added_by VARCHAR(100) DEFAULT 'NOVA',
    priority INTEGER DEFAULT 5
);
```

## Integration

Works with:
- [nova-cognition](https://github.com/NOVA-Openclaw/nova-cognition) — Agent orchestration
- [nova-memory](https://github.com/NOVA-Openclaw/nova-memory) — Task and memory storage

## Documentation

- **[ARCHITECTURE.md](./ARCHITECTURE.md)** — Technical architecture and system design
- **[WORKFLOW.md](./WORKFLOW.md)** — Detailed workflows and operational processes  
- **[DEPLOYMENT.md](./DEPLOYMENT.md)** — Setup, deployment, and maintenance guide
- **[AUTO-DEPLOY-PATTERN.md](./docs/AUTO-DEPLOY-PATTERN.md)** — Automated deployment pattern using Git hooks
- **[GH-ISSUE-WRAPPER.md](./docs/GH-ISSUE-WRAPPER.md)** — GitHub issue creation wrapper with SE workflow integration

## Key Features

### 🎯 3-Minute Work Sessions
Time-boxed focus sessions on unsolved problems prevent rabbit holes while ensuring meaningful progress.

### 🤝 Subagent Collaboration  
Spawn specialized agents for different tasks:
- **Scout** — Research and information gathering
- **Coder** — Simulations, calculations, prototypes
- **Analyst** — Data analysis and pattern recognition
- **Writer** — Documentation and explanation

### 📊 Progress Tracking
Comprehensive tracking of time investment, approaches attempted, insights discovered, and collaboration patterns across all problems.

### 🔄 Intelligent Problem Selection
Weighted selection algorithm balances priority, freshness, and time investment to ensure all problems receive attention.

## Initial Problem Set

The system comes pre-loaded with eight carefully selected unsolved problems:

| Problem | Category | Difficulty | Description |
|---------|----------|------------|-------------|
| P vs NP Problem | Mathematics | Millennium Prize | Computational complexity theory |
| AI Alignment | Technology | Challenging | Ensuring AI systems remain beneficial |
| Climate Change | Science | Challenging | Mitigation and adaptation strategies |
| Consciousness | Philosophy | Speculative | Hard problem of subjective experience |
| Aging/Longevity | Science | Challenging | Understanding and reversing aging |
| Unified Field Theory | Physics | Speculative | Unifying all fundamental forces |
| Riemann Hypothesis | Mathematics | Millennium Prize | Distribution of prime numbers |
| Protein Folding | Biology | Tractable | Predicting 3D protein structures |

## Quick Start

1. **Setup Database**: Run the SQL scripts in [DEPLOYMENT.md](./DEPLOYMENT.md)
2. **Configure Environment**: Set idle thresholds and subagent preferences  
3. **Initialize Problems**: Import the initial problem set
4. **Start Monitoring**: Begin idle detection and proactive work loops

See [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed setup instructions.

## Status

🚧 **In Development** — Core architecture implemented, deployment and testing in progress

---

*Part of the [NOVA-Openclaw](https://github.com/NOVA-Openclaw) project.*
