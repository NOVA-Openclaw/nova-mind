# motivation/scripts

Scripts supporting NOVA's proactive motivation system.

---

## proactive-gate-check.py

Deterministic gate checker for NOVA's proactive cascade. Checks all 11 cascade step
conditions without LLM involvement and emits a structured JSON manifest indicating which
steps have actionable work. The heartbeat session runs this script first and works only the
steps listed in `actionable_steps`, eliminating the need for inline LLM gate evaluation and
reducing unnecessary token consumption on heartbeat sessions where the human is still active.

See `motivation/ARCHITECTURE.md` for the full design rationale and how this script fits
into the proactive mode architecture.

### Usage

```bash
python3 proactive-gate-check.py
```

No arguments. Output is written to stdout. Exit code is always 0 — per-step errors are
embedded in the JSON output and never abort the run.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IDLE_THRESHOLD_MINUTES` | `60` | Minutes of channel inactivity required before the cascade runs. Set lower in development to trigger the cascade without waiting an hour. |

### Output Format

When the human is active (not idle), only the idle status fields are emitted:

```json
{
  "timestamp": "2026-06-11T10:00:00Z",
  "idle": false,
  "idle_minutes": 12.1,
  "idle_threshold_minutes": 60
}
```

When idle, the full manifest is emitted with per-step results and the list of actionable
step numbers:

```json
{
  "timestamp": "2026-06-11T10:00:00Z",
  "idle": true,
  "idle_minutes": 95.3,
  "idle_threshold_minutes": 60,
  "steps": {
    "1_agent_chat":  { "actionable": false, "reason": "0 unacknowledged messages" },
    "2_unanswered":  { "actionable": false, "reason": "No recent active user-facing sessions" },
    "3_introspect":  { "actionable": true,  "reason": "8.2h since last introspection (threshold 8h)" },
    "4_memory":      { "actionable": false, "reason": "Cooldown active, 1.8h remaining" },
    "5_entities":    { "actionable": false, "reason": "No entity dedup candidates" },
    "6_tasks":       { "actionable": true,  "reason": "3 pending unblocked task(s)" },
    "7_github":      { "actionable": false, "reason": "0 open GitHub issues" },
    "8_blocker_outreach": { "actionable": false, "reason": "No blockers eligible for outreach" },
    "9_research":    { "actionable": false, "reason": "0 unsolved problems" },
    "10_filesystem": { "actionable": false, "reason": "Audited 2.1d ago (threshold 7d)" },
    "11_d100":       { "actionable": false, "reason": "Optional — 2 prior step(s) already actionable" }
  },
  "actionable_steps": [3, 6],
  "actionable_count": 2,
  "summary": "2 of 11 steps actionable"
}
```

Step numbers in `actionable_steps` correspond to `step_order` values in the `workflow_steps`
table for the NOVA Proactive Mode workflow (id=27). Step 11 (D100 random task) is marked
mandatory when no steps 1–10 are actionable, ensuring the cascade always produces output.
Step 11 is also **forced** actionable whenever more than 12h have elapsed since the last
recorded roll in `d100_roll_log` (or no roll is on record), regardless of other steps'
actionable state (issue #358).

Step 8 (Blocker Outreach) curates a per-entity, per-blocker eligible set from the `blockers`
registry — entity master cooldown 24h, per-blocker cooldown 72h (both strict `>`), top 3
blockers per entity by `priority ASC, first_seen ASC, id ASC`. Its `data` payload includes
each eligible entity's selected blockers, computed cascade level per blocker, and the
resolved delivery channel (see `motivation/ARCHITECTURE.md#blocker-outreach-step-8` for the
full cascade/channel/reassignment rules, issue #356).

Each step entry may include a `data` field with additional context (counts, timestamps,
lists). Error conditions appear as `{ "actionable": false, "error": "..." }`.

### Dependencies

| Dependency | How It Is Used |
|------------|----------------|
| `psycopg2` | PostgreSQL queries against `nova_memory` (tasks, entities, unsolved_problems) and, separately, the dedicated `agent_chat` database (#320) via `load_pg_env(section="agent_chat")` — see `memory/docs/database-config.md`. Loaded from the nova venv at `~/.local/share/nova/venv/` — no manual activation required. |
| `gh` CLI | Lists open GitHub issues across NOVA-Openclaw repos (Step 7) and enumerates repos. |
| `~/.openclaw/agents/nova/sessions/sessions.json` + per-session JSONL files | Detects unanswered user messages directly from session state (Step 2). |

All other dependencies are Python standard library (`json`, `os`, `subprocess`, `sys`,
`time`, `datetime`).

If `psycopg2` is unavailable (e.g., venv not yet installed), database-backed steps return
`{ "actionable": false, "error": "psycopg2 not importable" }` and the script continues.
