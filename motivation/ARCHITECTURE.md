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
**Role:** Deterministic gate checker. Evaluates all 11 cascade step conditions without LLM
involvement and emits a structured JSON manifest. See [Proactive Gate Check](#proactive-gate-check)
below for full details.

### 4. Proactive Mode Workflow (id=27)

**Type:** Database workflow (`workflows` / `workflow_steps` tables)
**Role:** 11-step priority cascade defining what NOVA does when idle. The gate check script
maps each step to its gate function; the script's `actionable_steps` output tells NOVA
which workflow steps have work to do.

Step numbers in the script output correspond directly to `step_order` in `workflow_steps
WHERE workflow_id = 27`.

### 5. D100 Motivation Table

**Type:** Database table (`motivation_d100`)
**Role:** 100-slot random task roller providing variety in autonomous work. Used by
cascade Step 11, which is the mandatory catch-all when no other steps are actionable —
and additionally **forced** actionable whenever more than 12h have elapsed since the last
recorded roll, regardless of other steps' state (issue #358). Managed via `roll_d100()` and
`complete_d100(roll)` SECURITY DEFINER functions. Roll history (used for the forced-D100
check) is tracked in `d100_roll_log`, populated by a trigger on `motivation_d100` (migration
082). Roll announcements to `#proactive-mode` are handled by a dedicated cron script
(`memory/scripts/announce-d100-rolls.py`, issue #432), not by the heartbeat LLM turn — see
`motivation/README.md#d100-roll-announcer` for details. This is independent of the gate
check logic below, which is unaffected.

### 6. Unsolved Problems Research Workflow (id=32)

**Type:** Database workflow
**Role:** Structured research workflow delegating data gathering to Scout and reserving
reasoning/synthesis for NOVA. Triggered by cascade Step 9 when `unsolved_problems` with
`status != 'solved'` exist.

### 7. Blocker Registry & Outreach (Step 8)

**Type:** Database table (`blockers`) + cascade Step 8 (workflow_id=27)
**Role:** Curated registry of items blocked on another entity's action (issue #356).
Steps 6 (Pending Tasks) and 7 (GitHub Issues) upsert blocked items into `blockers`
(`ON CONFLICT (source_type, source_ref) DO UPDATE ... last_seen`) but perform **no**
outreach themselves — outreach is centralized in the dedicated Step 8, which is driven by
`check_step8_blocker_outreach()` in the gate check script. See
[Blocker Outreach](#blocker-outreach-step-8) below for cooldown, cascade, and channel
escalation details.

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

The script replaces that with a deterministic, pre-LLM evaluation pass: it checks all 11
gate conditions programmatically, then emits a compact JSON manifest so NOVA's heartbeat
session can skip straight to work.

### How It Fits in the Architecture

```
OpenClaw heartbeat fires
  → NOVA heartbeat session starts
  → Bootstrap context loads HEARTBEAT.md
  → NOVA runs proactive-gate-check.py    ← deterministic, no LLM
      → reads sessions.json              ← idle check
      → queries nova_memory + agent_chat DBs ← agent_chat (own DB, #320), tasks, entities, unsolved_problems
      → reads state files                ← heartbeat-state.json, memory-maintenance-last-run.json
      → calls gh CLI                     ← open GitHub issues
      → reads sessions.json + JSONL      ← unanswered user messages
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
| PostgreSQL `nova_memory` | `tasks` (pending/unblocked), `entities` dedup candidates, `unsolved_problems` |
| PostgreSQL `agent_chat` (dedicated DB, #320) | `agent_chat` unacknowledged messages — `proactive-gate-check.py` resolves this connection via `load_pg_env(section="agent_chat")` (see `memory/docs/database-config.md`), separately from the `nova_memory` connection above |
| `~/.openclaw/workspace/memory/heartbeat-state.json` | Introspection state (last run timestamp, daily log line count, session transcript bytes) |
| `~/.openclaw/state/memory-maintenance-last-run.json` | Memory maintenance cooldown state |
| `~/.openclaw/workspace/.last-fs-audit` | Filesystem audit staleness marker |
| `gh` CLI | Open GitHub issues across NOVA-Openclaw repos |
| PostgreSQL `blockers` / `proactive_outreach` / `entity_facts` / `agents` | Blocker outreach eligibility, cascade level, and channel resolution (Step 8) |
| PostgreSQL `d100_roll_log` | Forced D100 staleness check (Step 11, issue #358) |

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
    "8_blocker_outreach": { "actionable": false, "reason": "No blockers eligible for outreach" },
    "9_research":      { "actionable": false, "reason": "0 unsolved problems" },
    "10_filesystem":   { "actionable": false, "reason": "Audited 2.1d ago (threshold 7d)" },
    "11_d100":         { "actionable": false, "reason": "Optional — 2 prior step(s) already actionable" }
  },
  "actionable_steps": [3, 6],
  "actionable_count": 2,
  "summary": "2 of 11 steps actionable"
}
```

Each step entry may also include a `data` field with counts, timestamps, or lists for
additional context. Error conditions are embedded as `{ "actionable": false, "error": "..." }`
and never abort the run — the script always exits 0.

### Key Design Decisions

**D100 is a mandatory catch-all, and forced past 12h (Step 11).** When steps 1–10 produce
zero actionable work, Step 11 is always marked actionable. Independently of that,
Step 11 is **forced** actionable whenever more than 12h have elapsed since the last
recorded roll in `d100_roll_log` (or no roll is on record at all) — even if other steps
had actionable work, per issue #358. This guarantees both that the cascade never produces
a no-op idle session, and that D100 itself doesn't go stale for extended periods.

**Blocker outreach is centralized and cooldown-gated (Step 8).** Steps 6 and 7 only curate
blocked items into the `blockers` registry — they never contact anyone directly. Step 8
owns all outreach: it enforces a 24h entity-level cooldown (no more than one message to a
given entity per 24h, across all of their blockers) and a 72h per-blocker cooldown (a given
blocker cannot be re-raised with the same entity more often than every 72h), selects the
top 3 eligible blockers per entity, and sends one consolidated message per entity at the
most-escalated channel among its selected blockers. See
[Blocker Outreach](#blocker-outreach-step-8) for the full cascade/channel/reassignment
rules.

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

---

## Blocker Outreach (Step 8)

**Issues:** [nova-mind#356](https://github.com/NOVA-Openclaw/nova-mind/issues/356),
[nova-mind#358](https://github.com/NOVA-Openclaw/nova-mind/issues/358)

### Curation vs. Outreach

Before this feature, Steps 6 (Pending Tasks) and 7 (GitHub Issues) each contained inline
outreach cascade logic — contacting a domain owner directly the moment a blocker was found,
with an ad hoc 3-day cooldown. That logic is now split into two distinct concerns:

- **Curation (Steps 6 and 7):** when a task or issue is blocked, upsert a row into the
  `blockers` table (`ON CONFLICT (source_type, source_ref) DO UPDATE SET last_seen = NOW(), ...`).
  The responsible entity is resolved via `agent_domains` first, then `user_domains`
  (lower priority number wins, tiebreak random among ties), falling back to entity_id=2
  (I)ruid) if no domain match exists. **No outreach happens in these steps.**
- **Outreach (Step 8):** a dedicated step that reads the curated `blockers` registry (via
  `check_step8_blocker_outreach()` in the gate check script) and owns all cooldown
  enforcement, cascade escalation, and message dispatch.

### Eligibility Rules

| Rule | Threshold | Boundary behavior |
|------|-----------|--------------------|
| Entity master cooldown | 24h since ANY `proactive_outreach` row for the entity | Strict `>`; exactly 24h elapsed still blocks |
| Per-blocker cooldown | 72h since a `proactive_outreach` row for `(entity_id, 'blocker', blocker_id)` | Strict `>`; exactly 72h elapsed still blocks |
| Selection | Top 3 blockers per eligible entity | `ORDER BY priority ASC, first_seen ASC, id ASC` |

### Cascade Level & Channel Mapping

Cascade level for a given blocker = count of prior `proactive_outreach` rows for
`(entity_id, 'blocker', blocker_id)` + 1. Levels map onto that entity's available contact
channels, in escalation order: `discord_mention → discord_dm → signal → slack → email`,
skipping any channel missing from `entity_facts`. Entities that are agents (a row exists in
`agents` with a matching `entity_id`) always use `agent_chat` instead, regardless of level.

### One Message, Multiple Logged Attempts

An entity may have up to 3 selected blockers in a single cycle, but receives **exactly one
message**, sent at the most-escalated requested channel among those blockers. Despite only
one message being sent, **one `proactive_outreach` row is logged per blocker**, each
recording the actual channel used to deliver that consolidated message — not the
theoretical channel implied by that individual blocker's own cascade level.

**Cascade position is derived from attempt-row count, not delivered channel** (TC-D09).
Because every attempt is logged with the actual delivery channel rather than the
requested one, a blocker's next cascade level is always `COUNT(proactive_outreach rows for
this blocker) + 1` — independent of which channel any given attempt actually used.

### Channel Exhaustion & Reassignment

If an entity's cascade level exceeds the number of channels available to them (channel
exhaustion) and they are not I)ruid, the blocker is reassigned to the next domain entity
(re-resolved via `agent_domains`/`user_domains`, excluding the exhausted entity). If
reassignment exhausts every domain entity, escalation falls through to **I)ruid
(entity_id=2) as the final fallback**. If I)ruid himself is exhausted, the blocker holds at
his last available channel/level and continues on the normal 72h cadence — it is never
dropped or looped past him.

This is enforced deterministically in `check_step8_blocker_outreach()`, not left as
agent-turn inference: `_is_cascade_exhausted()` detects the condition,
`_entity_domain_topics()` + `_next_domain_entity()` resolve the next candidate, and
`_reassign_exhausted_entity()` drives the chain (next domain entity → I)ruid final
fallback → hold-in-place if I)ruid himself is exhausted). Each entry in the returned
`eligible_entities` payload carries `exhausted` (true only for the I)ruid hold-in-place
case) and, when reassignment occurred, `reassigned_from_entity_id`.

### Satisfied Blocker Reconciliation

Before selecting outreach targets each cycle, Step 8 marks any blocker whose underlying
condition has cleared as `status = 'satisfied'`, `satisfied_at = NOW()`. If a
previously-satisfied blocker's condition recurs, it is **reopened**: `status` reverts to
`'open'` and `satisfied_at` is cleared back to `NULL` — the existing row is reused (the
`(source_type, source_ref)` unique constraint prevents duplicates) rather than a new one
being created.
