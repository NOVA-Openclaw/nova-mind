# HEARTBEAT.md — Proactive Mode

<!-- PURPOSE: Heartbeat/proactive mode configuration — idle detection and workflow dispatch -->

## First Action: Run the Gate Check Script

At the start of every heartbeat session, run the proactive gate check script **before doing
anything else**:

```bash
python3 ~/nova-mind/motivation/scripts/proactive-gate-check.py
# or, if installed to the workspace scripts directory:
python3 ~/.openclaw/workspace/scripts/proactive-gate-check.py
```

Parse the JSON output:

- **`"idle": false`** → Reply `HEARTBEAT_OK` immediately. The human is active; do not
  interrupt. No further action.
- **`"idle": true`** → Proceed to Proactive Mode. Work through **only** the step numbers
  listed in `actionable_steps`. Skip all others.

### Output: not idle

```json
{
  "idle": false,
  "idle_minutes": 12.1,
  "idle_threshold_minutes": 60
}
```

### Output: idle with actionable steps

```json
{
  "idle": true,
  "idle_minutes": 95.3,
  "idle_threshold_minutes": 60,
  "actionable_steps": [3, 6, 11],
  "actionable_count": 3,
  "summary": "3 of 11 steps actionable"
}
```

The `actionable_steps` array lists step numbers (1–11) corresponding to the **NOVA Proactive
Mode** workflow (id=27). The script has already evaluated all gate conditions; do not
re-evaluate them manually.

## Idle Detection

Idle state is determined **deterministically by the gate check script**. It reads
`~/.openclaw/agents/nova/sessions/sessions.json` and finds the most recent interaction
timestamp across all user-facing channels (Discord, Signal, Telegram), excluding heartbeat
and system sessions.

If the most recent activity is older than `IDLE_THRESHOLD_MINUTES` (default: 60 minutes) →
idle. If less → not idle.

> **Note:** The script replaces the previous manual approach of calling `sessions_list`,
> reading channel messages, and comparing timestamps by LLM reasoning. Idle detection is now
> script-owned and LLM-free.

## Proactive Mode (idle ≥ 1 hour)

Report all Proactive Mode work summaries to Discord **#proactive-mode**
(channel `1504054635231445112`).

When the gate check script reports `"idle": true`, work through **only** the steps listed in
`actionable_steps`, in the order given. For step descriptions, query the live workflow:

```sql
SELECT step_order, description FROM workflow_steps
WHERE workflow_id = 27 ORDER BY step_order;
```

**Step 8 (Blocker Outreach) sends outreach for blockers curated by Steps 6 and 7.** Steps 6
and 7 only upsert blocked items into the `blockers` table — they never contact anyone
directly. Step 8 is the sole place outreach is sent: it enforces a 24h entity-level cooldown
and a 72h per-blocker cooldown, selects up to 3 eligible blockers per entity, and sends one
consolidated message per entity at the most-escalated channel among its selected blockers.
See `motivation/ARCHITECTURE.md` for the full cascade/channel/reassignment rules
(issue #356).

**Step 11 (D100 random task) is mandatory when no other steps are actionable, and forced
when more than 12h have elapsed since the last roll.** If `actionable_steps` contains only
`[11]`, that is the work to do — it is the catch-all that ensures the cascade always
produces output. Independently, Step 11 will also appear in `actionable_steps` whenever
`d100_roll_log` shows more than 12h since the last roll (or no roll on record at all), even
if other steps already had actionable work (issue #358).

## Rules

- **Human is active (`"idle": false`):** `HEARTBEAT_OK` — don't compete with an active
  conversation.
- **Recently checked (<30 min ago) with no new work:** `HEARTBEAT_OK`.
- **Script output is authoritative** — do not override idle detection with manual reasoning.
- **Work only the listed steps** — do not run steps absent from `actionable_steps`.
- Proactive mode runs at ALL hours — overnight is prime autonomous work time.
- Report summaries to #proactive-mode; do not post proactive work to other channels unless
  the work itself requires it.
