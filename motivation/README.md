# NOVA Motivation System

Proactive task management and autonomous work initiation for the NOVA agent ecosystem.

## Overview

The Motivation System enables NOVA to self-start on pending work during idle periods, rather than waiting passively for instructions. When all communication channels have been quiet for 1+ hour, the OpenClaw heartbeat triggers proactive mode, which works through a priority cascade of autonomous tasks.

## Architecture

The motivation system is **entirely configuration-driven** — there is no custom application code. It consists of:

1. **OpenClaw heartbeat** — Triggers every 30 minutes, configured in `openclaw.json` (`agents.defaults.heartbeat`)
2. **HEARTBEAT bootstrap context** — Database record (`agent_bootstrap_context`, file_key='HEARTBEAT') that defines idle detection logic and gates proactive mode on 1+ hour of channel inactivity
3. **Proactive Mode workflow** (id=27) — 11-step priority cascade defining what NOVA does when idle, evaluated deterministically by `motivation/scripts/proactive-gate-check.py`
4. **`blockers` registry table** — Curated registry of items blocked on another entity's action, populated by Steps 6/7, consumed by the dedicated Step 8 Blocker Outreach step (issue #356)
5. **D100 motivation table** (`motivation_d100`) — 100-slot random task roller for variety in autonomous work, backed by `d100_roll_log` roll-history and forced past 12h staleness (issue #358). Slots may be **populated** (fixed `task_name`/`task_description`) or **generative empty slots** that ask NOVA to invent the task on the spot (issue #444) — see [D100 Roll Mechanics](#d100-roll-mechanics) below. Roll results are announced to `#proactive-mode` deterministically by a dedicated cron script (`memory/scripts/announce-d100-rolls.py`, issue #432) — not by the heartbeat LLM turn; see [D100 Roll Announcer](#d100-roll-announcer) below.
6. **Unsolved Problems Research workflow** (id=32) — Structured research workflow that delegates data gathering to Scout and reserves reasoning/synthesis for NOVA
7. **`unsolved_problems` table** — NOVA's notebook for 8 humanity-scale research problems

## Operational Flow

```
OpenClaw heartbeat (every 30m)
  → HEARTBEAT bootstrap context (idle check)
    → If idle < 1 hour: HEARTBEAT_OK (do nothing)
    → If idle ≥ 1 hour: Run proactive-gate-check.py, execute only actionable steps
        Step 1:  Check agent_chat for peer messages
        Step 2:  Check sessions for unanswered messages
        Step 3:  Introspection (work-gated + time-backstop)
        Step 4:  Memory maintenance (REM sleep)
        Step 5:  Relationship & entity maintenance
        Step 6:  Work on pending tasks (curates blockers; no outreach)
        Step 7:  Work on open GitHub issues (curates blockers; no outreach)
        Step 8:  Blocker outreach (issue #356 — sole outreach step; cooldown-gated, cascade-escalated)
        Step 9:  Unsolved Problems Mode (workflow id=32)
        Step 10: Filesystem hygiene audit
        Step 11: Random D100 task (mandatory catch-all; forced past 12h — issue #358)
```

See `motivation/ARCHITECTURE.md` for full step details, gate-check design, and the
Blocker Outreach cascade/channel/reassignment rules.

## Database Schema

### Core Tables

**`unsolved_problems`** — NOVA's research problem registry and synthesis notebook.
- `current_approach` — NOVA's current thinking on how to tackle the problem
- `progress_notes` — Session-by-session synthesis log (NOT raw research data)
- Research data lives in Scout's `research_*` tables, not here

**`motivation_d100`** — 100-slot random task table with tracking.
- `roll_d100()` function picks a random enabled slot and updates tracking; see [D100 Roll Mechanics](#d100-roll-mechanics) for the full slot-selection algorithm (issue #444)
- `complete_d100(roll)` marks completion (requires `task_name IS NOT NULL`)
- `flag_d100_low_completion()` — monthly completion-rate audit; flags populated slots with ≥10 post-population rolls and a completion rate below 60% (issue #444)
- Tracking columns (`times_rolled`, `times_completed`, `last_rolled`, `last_completed`, `populated_at`) are write-protected — only the SECURITY DEFINER functions/triggers can update them. Content columns (including `reserved`) are open for NOVA to maintain directly.

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
- Rules (don't compete with active conversation, report Steps 1–10 summaries to #proactive-mode)

> **Note:** Step 11 (D100) is the one exception to LLM-driven reporting — its roll result is
> announced by a dedicated cron script, not by the heartbeat session. See
> [D100 Roll Announcer](#d100-roll-announcer) below.

## D100 Roll Mechanics

`roll_d100()` draws a uniform random value 1–100 and re-rolls (up to 20 attempts) until it
lands on a terminal outcome. As of issue #444, there are two distinct terminal outcomes,
distinguished by the additive `is_populate_me boolean` output column (15-column return
contract; no sentinel strings):

- **Populate-me (generative empty slot):** the picked roll is `task_name IS NULL`,
  `reserved = false`, and `enabled = true`. Returns `is_populate_me = true` with all
  content columns NULL. The caller (Proactive Mode workflow id=27, step 11) is expected to
  **invent a `task_name`/`task_description` for the slot via a direct UPDATE, do the work,
  then call `complete_d100(roll)`** — see the workflow step text for the exact SQL. The
  anti-repeat window/cap below never applies to empty-slot draws; they are always uniform
  and independent (DQ-4).
- **Populated task (normal path):** the picked roll has `task_name IS NOT NULL` and
  `enabled = true`. Subject to the anti-repeat window/cap described below. Returns
  `is_populate_me = false`.
- **Re-roll (no terminal outcome):** `reserved = true` empty slots and any `enabled = false`
  slot never terminate a roll — the function loops and tries again.

Both terminal paths increment `times_rolled` and set `last_rolled` before returning
(populate-me rolls count as real rolls — DQ-1 — so the `d100_roll_log` trigger and the
forced-D100 staleness gate, issue #358, keep working unmodified).

### `reserved` column

`reserved boolean` (default `false`) marks empty slots that are intentionally held back
from the generative populate-me path — e.g. slots earmarked for a specific future task that
hasn't been written yet. A `reserved = true` empty slot is excluded from both terminal paths
and simply causes a re-roll. Migration 084 reserved 22 of the pre-#444 empty slots; the
remaining non-reserved empty slots are generative.

### Anti-repeat window and dynamic cap (populated slots only)

To reduce short-interval repeats among populated tasks, a populated+enabled roll is only
accepted if:
- `last_rolled IS NULL`, or
- `last_rolled` is more than 7 days old, or
- the slot is re-admitted by the dynamic cap below.

**Dynamic cap:** if too many populated slots have been rolled within the last 7 days, the
window would over-exclude and starve the roll (excessive re-roll attempts). The cap
recomputes each roll: it allows up to `floor(total_populated_count * 0.5)` "recently
rolled" (last 7 days) slots to remain excluded; any excess is re-admitted, **oldest
`last_rolled` first**, statelessly and independently per invocation (no persisted exclusion
state — DQ-6). Cap rounding is floor (conservative — fewer exclusions on odd counts, DQ-5).

If a populated+enabled roll is excluded by the window/cap, the function re-rolls
(`CONTINUE`) rather than returning a different slot directly — so any given attempt still
draws uniformly from 1–100 before the eligibility check applies.

### `populated_at` and completion-rate flagging

`populated_at timestamptz` is set automatically by the `trg_set_populated_at` trigger the
first time a slot transitions from `task_name IS NULL` to `task_name IS NOT NULL` (covers
both direct UPDATE population and INSERT with content already present). It is NOT
directly writable by NOVA (tracking-column protection extends to it).

`flag_d100_low_completion()` is the monthly completion-rate audit function. It flags
populated slots with **10 or more rolls since `populated_at`** (counted via
`d100_roll_log` where `rolled_at >= populated_at` — this time-windowing exists so
pre-population populate-me rolls never inflate a slot's post-population roll count) and a
**completion rate below 60%** (`times_completed / rolls_since_pop`). The completion side of
the ratio needs no `populated_at` filter: `complete_d100()` requires
`task_name IS NOT NULL`, so every recorded completion is inherently post-population by
construction. Legacy populated slots (pre-#444) were backfilled with
`populated_at = created_at` (not NULL) during migration 084, so they remain flag-eligible.
Disabled populated slots remain eligible for this flag — a useful retirement signal.

## D100 Roll Announcer

D100 roll results were previously reported to `#proactive-mode` by the heartbeat LLM turn
itself, which proved unreliable — subject to session skipping, reasoning drift, and no
retry mechanism on failure. As of issue #432, announcements are handled by a dedicated,
zero-LLM cron script instead:

- **`memory/scripts/announce-d100-rolls.py`** — runs every 15 minutes via cron (installed
  by `agent-install.sh`), atomically claims unannounced `d100_roll_log` rows
  (`announced_at IS NULL`) via `UPDATE ... RETURNING`, and posts to `#proactive-mode`
  (`channel:1504054635231445112`) via `openclaw message send` — no webhook, no secret.
- One message per roll; more than 3 rolls claimed in a single cycle (e.g. after an outage)
  collapse into a single digest message.
- On post failure, the affected row's `announced_at` is un-stamped (compensating rollback)
  so it retries on the next cron tick — failures are never silently dropped.
- Historical rows (from the pre-#432 LLM-reporting era) were backfilled with
  `announced_at = rolled_at` in `database/pre-migrations/005-backfill-d100-roll-log-announced-at.sql`,
  so the first cron run does not burst-post history.
- **Populate-me rendering (issue #444):** a rolled slot with `task_name IS NULL` renders as
  `[ORIGINATION SLOT — populate & execute]` when `reserved = false` (a genuine generative
  empty-slot roll), distinct from the `task unknown (slot N)` fallback, which stays
  reserved for actual data-integrity errors (e.g. a `reserved = true` or otherwise
  inconsistent row reaching the announcer — should not happen via `roll_d100()`'s normal
  paths, but the announcer degrades gracefully rather than crashing).

This does **not** change Step 11's gate-check logic (whether D100 is actionable each
cycle) — `check_step11_d100()` in `proactive-gate-check.py` is unaffected and still owns
that decision. It changes only how a completed roll gets reported to the channel.

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
