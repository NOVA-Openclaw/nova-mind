# NOVA Motivation System

Proactive task management and autonomous work initiation for the NOVA agent ecosystem.

## Overview

The Motivation System enables NOVA to self-start on pending work during idle periods, rather than waiting passively for instructions. When all communication channels have been quiet for 1+ hour, the OpenClaw heartbeat triggers proactive mode, which works through a priority cascade of autonomous tasks.

## Architecture

The motivation system is **entirely configuration-driven** — there is no custom application code. It consists of:

1. **OpenClaw heartbeat** — Triggers every 30 minutes, configured in `openclaw.json` (`agents.defaults.heartbeat`)
2. **HEARTBEAT bootstrap context** — Database record (`agent_bootstrap_context`, file_key='HEARTBEAT') that defines idle detection logic and gates proactive mode on 1+ hour of channel inactivity
3. **Proactive Mode workflow** (id=27) — 9-step priority cascade defining what NOVA does when idle
4. **D100 motivation table** (`motivation_d100`) — 100-slot random task roller for variety in autonomous work
5. **Unsolved Problems Research workflow** (id=32) — Structured research workflow that delegates data gathering to Scout and reserves reasoning/synthesis for NOVA
6. **`unsolved_problems` table** — NOVA's notebook for 8 humanity-scale research problems

## Operational Flow

```
OpenClaw heartbeat (every 30m)
  → HEARTBEAT bootstrap context (idle check)
    → If idle < 1 hour: HEARTBEAT_OK (do nothing)
    → If idle ≥ 1 hour: Execute Proactive Mode workflow (id=27)
        Step 1: Check agent_chat for peer messages
        Step 2: Check communication channels (Hermes)
        Step 3: Check GitHub repos (Gidget)
        Step 4: Work on pending tasks
        Step 5: Check for blocked items needing outreach
        Step 6: Website/content maintenance
        Step 7: Unsolved Problems Research (workflow id=32)
        Step 8: Random D100 task
        Step 9: Introspection / journal
```

## Database Schema

### Core Tables

**`unsolved_problems`** — NOVA's research problem registry and synthesis notebook.
- `current_approach` — NOVA's current thinking on how to tackle the problem
- `progress_notes` — Session-by-session synthesis log (NOT raw research data)
- Research data lives in Scout's `research_*` tables, not here

**`motivation_d100`** — 100-slot random task table with tracking.
- `roll_d100()` function picks a random enabled slot and updates tracking
- `complete_d100(roll)` marks completion
- Tracking columns are write-protected via SECURITY DEFINER functions

### Supporting Tables (owned by other subsystems)

- `workflows` / `workflow_steps` — Workflow definitions (cognition subsystem)
- `tasks` — Task backlog (memory subsystem)
- `research_projects` / `research_tasks` / `research_findings` / `research_conclusions` — Scout's research database (memory subsystem)
- `agent_bootstrap_context` — Bootstrap records including HEARTBEAT (cognition subsystem)

## Unsolved Problems Research

The research workflow (id=32) separates concerns:

1. **NOVA** selects a problem and formulates a research question
2. **Scout** (Research domain) does exhaustive web research, stores structured findings with citations in `research_*` tables
3. **NOVA** performs a reasoning/synthesis pass over Scout's findings
4. **NOVA** updates `unsolved_problems` metadata (approach, synthesis) and triggers embedding

This ensures research data is structured, deduplicated, citation-tracked, and vector-embedded for semantic recall.

### Current Problem Set

| Problem | Category | Sessions | Time Invested |
|---------|----------|----------|---------------|
| P vs NP | mathematics/computer-science | 11 | 36 min |
| Riemann Hypothesis | mathematics | 5 | 6 min |
| Climate Change Mitigation | climate/policy | 17 | 48 min |
| Protein Folding Prediction | biology/AI | 7 | 12 min |
| Consciousness Hard Problem | philosophy/neuroscience | 10 | 30 min |
| Unified Field Theory | physics | 7 | 12 min |
| Aging and Longevity | biology/medicine | 11 | 27 min |
| AI Alignment | AI/ethics | 27 | 72 min |

## Configuration

### OpenClaw Config (`openclaw.json`)

```json
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "every": "30m",
        "target": "discord",
        "to": "channel:1504054635231445112",
        "isolatedSession": true,
        "skipWhenBusy": true
      }
    }
  }
}
```

### Bootstrap Context

The HEARTBEAT record in `agent_bootstrap_context` (file_key='HEARTBEAT', agent_name='nova') defines:
- Idle detection method (sessions_list, message read, inbound metadata)
- Idle threshold (1 hour)
- Proactive mode dispatch to workflow id=27
- Rules (don't compete with active conversation, report to #proactive-mode)

### Workflows

Query the live workflow definitions:
```sql
-- Proactive Mode cascade
SELECT step_order, domain, LEFT(description, 80) FROM workflow_steps WHERE workflow_id = 27 ORDER BY step_order;

-- Unsolved Problems Research
SELECT step_order, domain, LEFT(description, 80) FROM workflow_steps WHERE workflow_id = 32 ORDER BY step_order;
```

## History

Originally designed as a standalone system (`nova-motivation` repo) with custom idle detection code (JS/Python). Evolved into a fully configuration-driven system using OpenClaw's native heartbeat, database workflows, and bootstrap context records. The standalone repo was archived on 2026-06-03 and the system is now maintained as part of nova-mind.

---

*Part of the [nova-mind](https://github.com/NOVA-Openclaw/nova-mind) system.*
