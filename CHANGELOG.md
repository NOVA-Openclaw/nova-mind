# Changelog

### Batch: d100-motivation-refinements-444 (Issue #444)

#### Added
- **Generative empty slots for `motivation_d100`** (#444) — `roll_d100()`'s return contract
  gains an additive `is_populate_me boolean` column (15-column shape; no sentinel strings).
  A roll landing on a non-reserved empty slot (`task_name IS NULL`, `reserved = false`,
  `enabled = true`) now returns `is_populate_me = true` instead of silently re-rolling:
  NOVA is expected to invent `task_name`/`task_description` for the slot on the spot, do
  the work, then call `complete_d100(roll)`. Populate-me rolls still increment
  `times_rolled`/set `last_rolled` (DQ-1) so the existing `d100_roll_log` trigger and the
  forced-D100 staleness gate (#358) keep working unmodified.
- **`reserved boolean` column on `motivation_d100`** (#444, default `false`) — lets specific
  empty slots opt out of the generative populate-me path (re-roll instead). Migration 084
  reserves 22 of the pre-#444 empty slots.
- **`populated_at timestamptz` column + `trg_set_populated_at` trigger** (#444) —
  auto-stamped by `_trg_set_populated_at()` the first time a slot transitions from
  `task_name IS NULL` to `task_name IS NOT NULL` (INSERT or UPDATE). Not directly writable
  by NOVA (tracking-column protection extends to it). Existing 56 populated slots were
  backfilled to `populated_at = created_at` (NOT NULL — GAP-3 resolution; backfilling NULL
  would have silently defanged completion-rate flagging for all legacy slots).
- **7-day anti-repeat window with dynamic 50%-floor cap for populated-slot rolls** (#444) —
  a populated+enabled roll is accepted if `last_rolled IS NULL`, more than 7 days old, or
  re-admitted by the cap. The cap recomputes every roll: it allows up to
  `floor(total_populated * 0.5)` recently-rolled (≤7d) slots to stay excluded; any excess is
  re-admitted oldest-`last_rolled`-first, statelessly per invocation (DQ-6, cap rounding
  floor per DQ-5). Does not apply to empty-slot draws (DQ-4).
- **`flag_d100_low_completion()`** (#444) — monthly completion-rate audit function. Flags
  populated slots with ≥10 rolls since `populated_at` (time-windowed via `d100_roll_log`
  where `rolled_at >= populated_at`, so pre-population populate-me rolls never inflate the
  denominator — DQ-2) and a completion rate below 60%. The completion side needs no
  `populated_at` filter by construction: `complete_d100()` requires `task_name IS NOT NULL`,
  so every recorded completion is inherently post-population (GAP-1). Disabled populated
  slots remain flag-eligible (DQ-7 — useful retirement signal).
- **Three new populated content slots** (#444, rolls 62–64): Bootstrap token audit,
  Subsystem capability-loss review, Lesson re-validation.
- **Workflow 27 step 11 text updated** (#444) — the D100 step now documents both the
  `is_populate_me = true` (populate-and-execute) and `is_populate_me = false` (normal
  execute) branches with exact SQL for each.
- **`announce-d100-rolls.py` populate-me rendering** (#444) — a roll with `task_name IS
  NULL` now renders as `[ORIGINATION SLOT — populate & execute]` when `reserved = false`
  (a genuine generative-slot roll), distinct from the `task unknown (slot N)` fallback,
  which remains reserved for actual data-integrity errors.

#### Fixed
- **Column-level UPDATE grants for `nova` on `motivation_d100`** (#444) — `reserved`,
  `populated_at`, and the pre-existing tracking columns require explicit column-level
  `GRANT UPDATE` since `nova` operates under column-level privileges, not table-level.
- **`d100_roll_log` privilege correction** (#444, closes remaining gaps from #432) —
  `REVOKE DELETE, INSERT ON TABLE d100_roll_log FROM nova` followed by
  `GRANT SELECT, UPDATE ON TABLE d100_roll_log TO nova` (no `INSERT`: the roll-log trigger
  writes under `roll_d100()`'s own `SECURITY DEFINER` context, not nova's session).
- **Ambiguous `last_rolled`/anti-repeat CTE alias fix** (#444, #453) — the anti-repeat
  eligibility CTE's `roll` output column collided with the outer function's `roll`
  parameter/table-column name inside `roll_d100()`, causing an ambiguous-reference error
  under live PL/pgSQL execution (not caught by mock-based pytest coverage). Aliased the CTE
  column and added a direct-migration-load regression test
  (`motivation/tests/test_roll_d100_migration.py`) that executes `roll_d100()` end-to-end
  against a real database connection (transaction always rolled back) specifically because
  this class of bug is invisible to mocked tests.
- **`agent-install.sh` post-`pgschema`-apply grant reconciliation** (#452) — `pgschema`
  deliberately ignores privilege (GRANT/REVOKE) statements when diffing/applying
  `schema.sql`, so the explicit grants above (and the #448/#449 predecessors) were silently
  lost on fresh installs. The schema-apply step now extracts `GRANT`/`REVOKE` lines from the
  staged schema file after a successful `pgschema apply` and re-applies them via
  `_superuser_psql`, non-fatally logging failure rather than aborting the install.

#### Tests
- `tests/TEST-CASES-ISSUE-444.md` — 74 finalized test cases across 9 sections (schema/
  migration, generative empty slot/reserved semantics, anti-repeat window + dynamic cap,
  `max_attempts` interaction, populate-me interface/contract, `complete_d100()` lifecycle/
  backward-compat, completion-rate flagging, new content slots, adversarial/degenerate
  sweep). Local to `feature/444-d100-refinements`, no PR yet.
- `motivation/tests/test_roll_d100_migration.py` — direct end-to-end `roll_d100()` load-
  and-execute regression test against a real DB connection (the ambiguous-CTE-alias class
  of bug is invisible to mock-based coverage).
- `motivation/tests/test_announce_d100_rolls.py` — extended for populate-me rendering
  (`[ORIGINATION SLOT — populate & execute]` vs. `task unknown (slot N)` fallback) and the
  `reserved` column join.

#### Issues Closed
- #444 — D100 motivation system refinements (generative empty slots, anti-repeat window,
  completion-rate flagging)
- #452 — `agent-install.sh` grant reconciliation after `pgschema apply`
- #453 — Anti-repeat CTE alias / ambiguous `roll` reference in `roll_d100()`

### Batch: turn-context-placement-cache-439 (Issue #439)

#### Added
- **`placement` config option for the turn-context plugin's dynamic context block** (#439) — `memory/plugins/turn-context/openclaw.plugin.json` gains a `configSchema.placement` enum (`system-prepend` default | `turn-prepend`). `system-prepend` preserves the pre-existing behavior (dynamic entity/domain/recall block returned as `prependSystemContext`, ahead of the base system prompt — no behavior change for instances that don't set this option). `turn-prepend` instead returns the same block as `prependContext`, adjacent to the current user turn, so the (comparatively static) base system prompt is no longer preceded by a per-turn-varying block — preserving prompt-cache hits on the system-prompt prefix across turns. Turn reminders and the honorific guard are unaffected by this setting and always land in `appendSystemContext`. New pure helpers `resolvePlacement()` (defaults unknown/malformed values to `system-prepend` rather than throwing) and `buildPromptResult()` in `memory/plugins/turn-context/src/index.ts`, covered by 12 new unit tests in `src/index.test.ts` (TC-439-001–012). Full option documentation: `memory/plugins/turn-context/README.md#placement`.
- **`scripts/measure-turn-cache-impact.py`** (#439) — Compares prompt-cache metrics (cache-read/write token counts, cache-hit ratio, steady-state cacheWrite/turn) between a baseline and an experiment OpenClaw session JSONL log, to quantify the effect of switching `placement` above. Supports a single-session mode (`python3 scripts/measure-turn-cache-impact.py <session.jsonl>`) and a before/after comparison mode (`--before baseline.jsonl --after experiment.jsonl`, optionally with `--turn-context-log <log>` to parse the plugin's own `prepend=<N>chars` log lines). Checks three acceptance criteria: AC-1 (steady-state cacheWrite/turn drops ≥80%), AC-2 (cache-hit ratio improves ≥15 percentage points, or reaches ≥90% from turn 3 on), and AC-3 (the measured cacheWrite/turn drop, in tokens, is within ±10% of the dynamic prepend block's char count converted to an estimated token count via a `chars ÷ 4` English-text heuristic — `CHARS_PER_TOKEN_ESTIMATE = 4`). This AC-3 check is a coarse sanity check, not an exact token count: actual tokenization varies by model and language mix, so use it to catch gross mismatches (e.g. cacheWrite dropping because the block was shrunk rather than moved), not as a precise token accounting tool. Installer wiring for this script is tracked separately and out of scope here — see #445. Usage documentation: `memory/plugins/turn-context/README.md#placement`.

#### Tests
- `memory/plugins/turn-context/src/index.test.ts` (#439) — 12 new unit tests (TC-439-001–012) covering `buildPromptResult()` placement routing (dynamic block to `prependSystemContext` vs `prependContext`, append segments unaffected, empty-segment omission) and `resolvePlacement()` fallback behavior (undefined config, empty object, unknown string, non-string value, both valid values).
- `tests/test_measure_turn_cache_impact.py` (#439) — New suite covering `estimate_tokens_from_chars()` (rounding, zero, heuristic-constant guard), `compare_metrics()` AC-3 behavior (matched/mismatched/missing-log/zero-size), `parse_prepend_block_size()` (plain-log parsing, missing file, non-matching log), and CLI smoke tests against fixture files in `tests/fixtures/measure_turn_cache/` (`baseline.jsonl`, `experiment.jsonl`, `turn-context-matched.log`, `turn-context-mismatched.log`).

#### Issues Closed
- #439 — Turn-context prompt-cache optimization: configurable placement for the dynamic context block + measurement script
