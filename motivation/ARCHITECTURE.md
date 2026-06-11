# Motivation System Architecture

Architecture reference for NOVA's proactive task management system.

> See `motivation/README.md` for the operational overview and configuration reference.

## Components

### 1. OpenClaw Heartbeat

**Type:** OpenClaw native scheduler
**Config:** `agents.defaults.heartbeat` in `openclaw.json`
**Trigger:** Every 30 minutes
**Role:** Fires a heartbeat session for NOVA. The heartbeat session reads `HEARTBEAT.md`
(from `agent_bootstrap_context`, file_key=`HEARTBEAT`) as its first bootstrap context
record, which instructs NOVA to run the gate check script immediately.

### 2. HEARTBEAT Bootstrap Context

**Type:** Database record (`agent_bootstrap_context`, file_key=`HEARTBEAT`, agent_name=`nova`)
**Role:** Loaded at the start of each heartbeat session. Instructs NOVA to run the
proactive gate check script, interpret its JSON output, and either reply `HEARTBEAT_OK`
(not idle) or work through the `actionable_steps` from the script output (idle).

Source of truth for the file content: `~/nova-mind/HEARTBEAT.md`.

### 3. Proactive Gate Check Script

**Type:** Python script
**Path:** `motivation/scripts/proactive-gate-check.py`
**Installed path:** `~/.openclaw/workspace/scripts/proactive-gate-check.py`
**Role:** Deterministic gate checker. Evaluates all 10 cascade step conditions without LLM
involvement and emits a structured JSON manifest. See [Proactive Gate Check](#proactive-gate-check)
below for full details.

### 4. Proactive Mode Workflow (id=27)

**Type:** Database workflow (`workflows` / `workflow_steps` tables)
**Role:** 9-step priority cascade defining what NOVA does when idle. The gate check script
maps each step to its gate function; the script's `actionable_steps` output tells NOVA
which workflow steps have work to do.

Step numbers in the script output correspond directly to `step_order` in `workflow_steps
WHERE workflow_id = 27`.

### 5. D100 Motivation Table

**Type:** Database table (`motivation_d100`)
**Role:** 100-slot random task roller providing variety in autonomous work. Used by
cascade Step 10, which is the mandatory catch-all when no other steps are actionable.
Managed via `roll_d100()` and `complete_d100(roll)` SECURITY DEFINER functions.

### 6. Unsolved Problems Research Workflow (id=32)

**Type:** Database workflow
**Role:** Structured research workflow delegating data gathering to Scout and reserving
reasoning/synthesis for NOVA. Triggered by cascade Step 8 when `unsolved_problems` with
`status != 'solved'` exist.

---

## Proactive Gate Check

**Script:** `motivation/scripts/proactive-gate-check.py`
**Issue:** [nova-mind#324](https://github.com/NOVA-Openclaw/nova-mind/issues/324)

### Purpose

The gate check script eliminates LLM-driven gate evaluation from the proactive cascade.
Previously, each heartbeat session required NOVA to manually query sessions, check
databases, and reason about whether each cascade step had actionable work. This produced
inconsistent gate decisions and unnecessary token consumption on sessions that would always
result in `HEARTBEAT_OK`.

The script replaces that with a deterministic, pre-LLM evaluation pass: it checks all 10
gate conditions programmatically, then emits a compact JSON manifest so NOVA's heartbeat
session can skip straight to work.

### How It Fits in the Architecture

```
OpenClaw heartbeat fires
  → NOVA heartbeat session starts
  → Bootstrap context loads HEARTBEAT.md
  → NOVA runs proactive-gate-check.py    ← deterministic, no LLM
      → reads sessions.json              ← idle check
      → queries nova_memory DB           ← agent_chat, tasks, entities, unsolved_problems
      → reads state files                ← heartbeat-state.json, memory-maintenance-last-run.json
      → calls gh CLI                     ← open GitHub issues
      → calls openclaw CLI               ← recent active sessions
      → emits JSON manifest
  → idle=false: HEARTBEAT_OK (zero LLM work on gate checks)
  → idle=true: NOVA works only actionable_steps from manifest
```

Previously the LLM performed the gate checks during its reasoning pass. Now the script
owns that role entirely — the LLM only sees the output, never the gate logic.

### Inputs

| Source | What It Checks |
|--------|----------------|
| `~/.openclaw/agents/nova/sessions/sessions.json` | Idle detection (last interaction timestamp across user-facing sessions) |
| PostgreSQL `nova_memory` | `agent_chat` unacknowledged messages, `tasks` (pending/unblocked), `entities` dedup candidates, `unsolved_problems` |
| `~/.openclaw/workspace/memory/heartbeat-state.json` | Introspection state (last run timestamp, daily log line count, session transcript bytes) |
| `~/.openclaw/state/memory-maintenance-last-run.json` | Memory maintenance cooldown state |
| `~/.openclaw/workspace/.last-fs-audit` | Filesystem audit staleness marker |
| `gh` CLI | Open GitHub issues across NOVA-Openclaw repos |
| `openclaw` CLI | Recent active user-facing sessions (for Step 2) |

### Output

Structured JSON manifest. When not idle, only the idle status fields are emitted:

```json
{
  "timestamp": "2026-06-11T10:00:00Z",
  "idle": false,
  "idle_minutes": 12.1,
  "idle_threshold_minutes": 60
}
```

When idle, the full manifest is emitted:

```json
{
  "timestamp": "2026-06-11T10:00:00Z",
  "idle": true,
  "idle_minutes": 95.3,
  "idle_threshold_minutes": 60,
  "steps": {
    "1_agent_chat":    { "actionable": false, "reason": "0 unacknowledged messages" },
    "2_unanswered":    { "actionable": false, "reason": "No recent active user-facing sessions" },
    "3_introspect":    { "actionable": true,  "reason": "8.2h since last introspection (threshold 8h)" },
    "4_memory":        { "actionable": false, "reason": "Cooldown active, 1.8h remaining" },
    "5_entities":      { "actionable": false, "reason": "No entity dedup candidates" },
    "6_tasks":         { "actionable": true,  "reason": "3 pending unblocked task(s)" },
    "7_github":        { "actionable": false, "reason": "0 open GitHub issues" },
    "8_research":      { "actionable": false, "reason": "0 unsolved problems" },
    "9_filesystem":    { "actionable": false, "reason": "Audited 2.1d ago (threshold 7d)" },
    "10_d100":         { "actionable": false, "reason": "Optional — 2 prior step(s) already actionable" }
  },
  "actionable_steps": [3, 6],
  "actionable_count": 2,
  "summary": "2 of 10 steps actionable"
}
```

Each step entry may also include a `data` field with counts, timestamps, or lists for
additional context. Error conditions are embedded as `{ "actionable": false, "error": "..." }`
and never abort the run — the script always exits 0.

### Key Design Decisions

**D100 is a mandatory catch-all (Step 10).** When steps 1–9 produce zero actionable work,
Step 10 is always marked actionable. This guarantees the cascade never produces a no-op
idle session — NOVA always has something to do.

**Exit code is always 0.** Per-step errors (DB unavailable, CLI timeout, missing file) are
embedded in the JSON output rather than surfaced as failures. This prevents a partial outage
from silently suppressing the cascade.

**No LLM in the gate path.** The script uses only deterministic logic: timestamp arithmetic,
row counts, and file existence checks. Gate outcomes are reproducible and auditable without
reasoning through a language model.

**Venv bootstrap is self-contained.** The script adds the nova venv site-packages to
`sys.path` at startup so `psycopg2` is importable even when the script is invoked outside
the venv. No shell wrapper or activation step required.

---

## Operational Flow (with gate check)

```
OpenClaw heartbeat (every 30m)
  → HEARTBEAT bootstrap context
    → Run proactive-gate-check.py
      → idle=false: HEARTBEAT_OK
      → idle=true, actionable_steps=[3,6]:
          Step 3: Introspection
          Step 6: Work on pending tasks
          (all other steps skipped)
```

Compare to the pre-#324 flow, where NOVA evaluated each cascade step gate inline during
its reasoning pass — running sessions queries, DB queries, and GitHub checks as part of the
LLM turn rather than before it.
