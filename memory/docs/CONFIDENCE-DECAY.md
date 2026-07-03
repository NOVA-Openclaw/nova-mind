# Confidence Decay System

## Overview

The confidence decay system is designed to fade learned facts over time, prioritizing recent and reinforced knowledge in the nova-memory system. This ensures that the agent's memory naturally evolves, giving more weight to current information while allowing older, unconfirmed knowledge to gradually diminish in importance.

### Key Components

- **Script:** `memory/templates/memory-maintenance.py`, deployed to `~/.openclaw/scripts/memory-maintenance.py` by `agent-install.sh` (Phase 5 of its 9-phase pipeline)
- **Trigger:** Runs from the HEARTBEAT idle cascade (Proactive Mode workflow, Step 4 — "Memory Maintenance (REM Sleep)"), **not cron**. There is no separate `decay-confidence.sh` script.
- **Cooldown:** A 24-hour cooldown (`DECAY_COOLDOWN_HOURS`) gates decay specifically, on top of the overall 4-hour maintenance-run cooldown (`COOLDOWN_HOURS`)
- **Purpose:** Automatically reduce confidence scores for facts that haven't been recently referenced or reconfirmed

## Decay Formula (Exponential, Not a Daily Multiplier)

Decay is calculated as continuous exponential decay based on days since last confirmation, not a fixed daily multiplier:

```
decay_factor = exp(-rate * days_since_last_confirmed)
new_confidence = decay_factor
```

Where `rate` comes from the fact's `durability` level (or a per-row `decay_rate` override if set):

| `durability` | Rate | Notes |
|--------------|------|-------|
| `permanent` | `0` | Never decays — excluded from the decay query entirely (`WHERE durability != 'permanent'`) |
| `long_term` | `0.005` | Slow decay — core identity/preference facts |
| `short_term` | `0.02` | Moderate decay — current states/moods |
| `ephemeral` | `0.1` | Fast decay — transient/temporary facts |

If a fact's `expires` timestamp (on `entity_facts`) has passed, its decay factor is forced to `0.0` regardless of durability.

## Tables Covered

| Table | Decay basis | Rate | Notes |
|-------|------------|------|-------|
| `entity_facts` | `durability`-based rate table above, keyed on `last_confirmed_at` | see table above | Excludes `durability = 'permanent'` and rows already below `ARCHIVE_THRESHOLD` (0.1) |
| `events` | Flat table-level rate, keyed on age | `0.001` | Via `TABLE_DECAY_RATES['events']` |
| `lessons` | Flat table-level rate, keyed on age | `0.001` | Via `TABLE_DECAY_RATES['lessons']` |
| `memory_embeddings` | Flat table-level rate, keyed on age | `0.01` | Via `TABLE_DECAY_RATES['memory_embeddings']` |

`media_tags` is **not** part of the current decay pipeline (`TABLE_DECAY_RATES` only covers `events`, `lessons`, `memory_embeddings`).

### Archive Threshold

`ARCHIVE_THRESHOLD = 0.1` — `entity_facts` rows already at or below this confidence are excluded from further decay processing (they're candidates for archival/cleanup in a later maintenance phase instead).

## Excluded from Decay

- **`entity_facts` where `durability = 'permanent'`** — Facts marked as permanent knowledge (rate = 0, and excluded from the decay query's `WHERE` clause entirely)
- **All `*_archive` tables** — Historical records preserved for audit/reference, not touched by the live decay pass

## Reinforcement Mechanism

The system includes mechanisms to prevent decay of actively used knowledge:

- **`extraction_count` increments** — When facts are reconfirmed through extraction or reinforcement
- **`last_confirmed_at` updates** — Reset the decay clock when knowledge is actively verified (this is the field decay math reads from for `entity_facts`)

## Implementation Details

### Timing Logic

- For `entity_facts`: eligibility and the decay exponent are both based on `days_since = now() - last_confirmed_at`. If `last_confirmed_at` is `NULL` or `days_since <= 0`, the row is skipped this run.
- For `events`/`lessons`/`memory_embeddings`: eligibility and decay use the table's own age-tracking column (see `apply_decay_to_table()` in `memory-maintenance.py` for the exact column per table).
- Runs whenever the Proactive Mode heartbeat cascade triggers Step 4 and the 24h decay cooldown has elapsed — not on a fixed daily schedule.

### Safety Measures

- The `ARCHIVE_THRESHOLD` floor keeps already-decayed facts out of repeated processing.
- Permanent data exclusions protect critical system knowledge.
- Archive tables remain untouched for historical integrity.
- `--dry-run` and `--skip-decay` flags on `memory-maintenance.py` let you preview or skip this phase.

## Monitoring

Running `memory-maintenance.py --verbose` logs the count of `entity_facts` rows decayed this run (and similarly for the table-level passes). See `memory/README.md`'s "Memory Maintenance" section for the full CLI flag reference.

## Configuration

`DECAY_RATES`, `TABLE_DECAY_RATES`, `DECAY_COOLDOWN_HOURS`, and `ARCHIVE_THRESHOLD` are module-level constants at the top of `memory/templates/memory-maintenance.py`. Changing them requires editing the template and redeploying (`agent-install.sh` re-copies it to `~/.openclaw/scripts/`).

This system ensures that nova-memory maintains relevant, current knowledge while gracefully aging out outdated information that is no longer actively used or confirmed.
