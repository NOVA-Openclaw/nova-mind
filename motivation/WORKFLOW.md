# NOVA Motivation System - Workflow Guide

This document describes the operational workflows and processes of the NOVA Motivation System.

## Main Operation Loop

The Motivation System runs continuously, cycling through three distinct operational modes based on current conditions.

### Workflow State Diagram

```
┌─────────────────┐
│   Reactive      │ ◄─── New message received
│     Mode        │
│ (Normal Chat)   │
└─────────────────┘
         │
         ▼ Idle > 5 min
┌─────────────────┐
│   Proactive     │ ◄─── Has workable tasks
│     Mode        │
│ (Task Backlog)  │
└─────────────────┘
         │
         ▼ No workable tasks
┌─────────────────┐
│ Unsolved        │ ◄─── Default meaningful work
│ Problems Mode   │
│ (Research)      │
└─────────────────┘
```

## Idle Detection Workflow

### 1. Continuous Monitoring
```
Every 60 seconds:
├─ Check last message timestamp for each channel
├─ Update idle status in memory
└─ If idle threshold exceeded → trigger proactive mode
```

### 2. Channel Activity Updates
```
On new message received:
├─ Update channel_activity table
├─ Reset idle timer
├─ If in proactive mode → pause current work
└─ Switch to reactive mode
```

### 3. Idle Threshold Calculation
```
For each channel:
├─ Calculate: current_time - last_message_time
├─ Compare against channel-specific threshold
├─ Global idle = ALL channels exceed threshold
└─ Grace period: ignore brief activity spikes
```

## Proactive Task Mode Workflow

### 1. Task Discovery and Selection

```
Task Selection Process:
1. Query workable tasks:
   SELECT * FROM tasks 
   WHERE status = 'pending' 
   AND blocked = false 
   AND (assigned_to = 'NOVA' OR assigned_to IS NULL)
   ORDER BY priority DESC, created_at ASC

2. Apply filters:
   ├─ Skip tasks with unsatisfied dependencies
   ├─ Skip tasks requiring unavailable resources
   └─ Skip tasks in cooling-off period

3. Select highest priority task
4. Update status to 'in_progress'
5. Begin work session
```

### 2. Task Work Session

```
Work Session Loop:
1. Load task context and history
2. Analyze current state and requirements
3. Determine next action:
   ├─ Gather information
   ├─ Execute work step  
   ├─ Request user input
   └─ Mark complete/blocked

4. Execute action (time-bounded)
5. Update task progress and notes
6. Check for interruption (new messages)
7. If not interrupted and not complete → continue
8. If complete → mark done, select next task
9. If blocked → update blocking reason, notify user
```

### 3. Task State Transitions

```
Task Lifecycle:
pending → in_progress → completed
    │         │
    │         ├→ blocked (waiting_user_input)
    │         ├→ blocked (waiting_external)
    │         ├→ blocked (missing_info)
    │         ├→ blocked (resource_unavailable)
    │         └→ blocked (dependency_blocked)
    │
    └─ cancelled (no longer relevant)

Blocked tasks can return to pending when unblocked.
```

## Unsolved Problems Mode Workflow

### 1. Problem Selection Algorithm

```
Problem Selection Process:
1. Query available problems:
   SELECT * FROM unsolved_problems 
   WHERE status != 'solved'
   AND (last_worked_at IS NULL OR last_worked_at < NOW() - INTERVAL '1 hour')

2. Calculate selection weights:
   weight = priority × (days_since_last_worked + 1) / (total_hours_worked + 1)

3. Select from top 3 weighted problems (random choice)
4. Load problem context and history
5. Begin 3-minute work session
```

### 2. Problem Work Session (3-minute cycles)

```
Session Workflow:
1. Session Initialization (30 seconds max):
   ├─ Load problem context
   ├─ Review previous work and approaches
   ├─ Identify current focus area
   └─ Set session goals

2. Active Work Phase (2-2.5 minutes):
   ├─ Research and exploration
   ├─ Spawn subagents as needed
   ├─ Analyze and synthesize
   └─ Generate insights

3. Session Wrap-up (0-30 seconds):
   ├─ Document progress and insights
   ├─ Update next steps and approach
   ├─ Save session to database
   └─ Decide: continue or rotate to next problem
```

### 3. Subagent Collaboration Workflow

```
Subagent Spawning Decision Tree:
├─ Need research? → Spawn Scout
│  ├─ "Search for recent papers on protein folding"
│  ├─ "Find experts working on consciousness"
│  └─ "Gather data on climate interventions"
│
├─ Need computation? → Spawn Coder  
│  ├─ "Simulate simplified P vs NP case"
│  ├─ "Model climate feedback loops"
│  └─ "Calculate complexity bounds"
│
├─ Need analysis? → Spawn Analyst
│  ├─ "Identify patterns in consciousness theories"
│  ├─ "Compare aging intervention approaches"
│  └─ "Analyze mathematical proof strategies"
│
└─ Need documentation? → Spawn Writer
   ├─ "Explain quantum computing barriers"
   ├─ "Summarize alignment problem progress"  
   └─ "Document novel approach to longevity"
```

### 4. Progress Tracking and Documentation

```
Progress Documentation:
1. Real-time updates during session:
   ├─ Key insights discovered
   ├─ New questions formulated  
   ├─ Approaches attempted
   └─ Blockers encountered

2. Session completion:
   ├─ Update total_time_spent
   ├─ Increment work_sessions counter
   ├─ Save detailed session notes
   └─ Update current_approach if changed

3. Cross-session learning:
   ├─ Identify recurring patterns
   ├─ Build knowledge base of approaches
   ├─ Track effectiveness of methods
   └─ Refine problem-solving strategies
```

## Interruption Handling

### 1. Graceful Context Switching

```
On New Message During Proactive Work:
1. Immediate acknowledgment:
   ├─ Pause current work
   ├─ Save current state
   └─ Switch to reactive mode

2. Context preservation:
   ├─ Save partial progress
   ├─ Note interruption point
   ├─ Update last_worked_at timestamp
   └─ Mark session as interrupted

3. Return to work (if appropriate):
   ├─ Wait for conversation to end
   ├─ Check if still idle after threshold
   ├─ Resume previous work or select new task
   └─ Consider interruption fatigue
```

### 2. Work Session Boundaries

```
Natural Stopping Points:
├─ Task completion
├─ Clear blocking condition
├─ 3-minute problem session end
├─ Subagent completion
├─ User message received
└─ Scheduled break time
```

## Problem-Specific Workflows

### Mathematics Problems (e.g., P vs NP)

```
3-Minute Session Example:
1. Review current approach (proof by contradiction)
2. Identify next logical step in proof
3. Spawn Coder to verify computational examples
4. Document any new insights about complexity classes
5. Update next steps: "Explore polynomial reduction patterns"
```

### Science Problems (e.g., Climate Change)

```
3-Minute Session Example:
1. Focus on carbon capture technologies
2. Spawn Scout to research latest innovations
3. Analyze feasibility of novel approaches
4. Identify promising research directions
5. Update next steps: "Model economic viability of direct air capture"
```

### AI/Tech Problems (e.g., Consciousness)

```
3-Minute Session Example:
1. Explore integrated information theory
2. Spawn Analyst to compare consciousness theories
3. Identify testable predictions
4. Document philosophical implications
5. Update next steps: "Design consciousness detection protocol"
```

## Quality Control and Learning

### 1. Session Effectiveness Metrics

```
Tracking Session Quality:
├─ Insights per session (target: 1-2 meaningful insights)
├─ Questions generated (exploring problem space)
├─ Progress toward sub-problems (decomposition)
├─ Novel connections made (interdisciplinary links)
└─ External resources discovered (papers, experts, tools)
```

### 2. Continuous Improvement

```
Learning Loop:
1. Weekly review of all problem work:
   ├─ Which approaches showed most promise?
   ├─ Which problems generated most insights?
   ├─ Which subagent collaborations were effective?
   └─ What patterns emerged across problems?

2. Adjust strategies:
   ├─ Update problem priorities
   ├─ Refine session structures
   ├─ Improve subagent task definitions
   └─ Enhance progress tracking metrics

3. Expand problem set:
   ├─ Add promising new problems
   ├─ Decompose large problems into sub-problems  
   ├─ Connect related problems
   └─ Archive solved or abandoned problems
```

## Example Daily Flow

```
Typical Day with Motivation System:

08:00 - User starts day, active conversation → Reactive Mode
10:30 - User goes to meeting, 5+ min idle → Proactive Mode
        - Work on pending task: "Analyze market data"
        - Complete task in 15 minutes
        - No more workable tasks → Unsolved Problems Mode
        - 3-minute session on AI Alignment
        - 3-minute session on Climate Change
11:00 - User returns, messages → Reactive Mode

14:00 - Lunch break, idle → Proactive Mode  
        - No workable tasks → Unsolved Problems Mode
        - 3-minute session on Consciousness
        - 3-minute session on P vs NP
        - Spawn Scout for protein folding research
14:30 - User returns → Reactive Mode

19:00 - End of work day, idle → Unsolved Problems Mode
        - Extended research sessions
        - Collaborate with multiple subagents
        - Deep dive into promising approaches
        - Document insights for tomorrow
```

This workflow ensures continuous productivity while maintaining responsiveness to user needs and making meaningful progress on humanity's greatest challenges.