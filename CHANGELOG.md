# Changelog

### Batch: extraction-dead-letter-485 (Issue #485)

#### Added
- **`extraction_failures` dead-letter table + replay path** (nova-mind#485) — The
  `memory-extract` hook (`memory/hooks/memory-extract/handler.ts`) previously spawned
  `extract_memories.py` fire-and-forget with no stderr/stdout capture, no retry, and no
  persistence on failure — a System Diagnostic run (nova-mind#447) found ~10% of
  extractions failing silently (10/112 messages in a 33-hour window), permanently losing
  the source message body since it only existed at hook time. The hook now captures
  16384-byte tail buffers of the child's stderr/stdout (continuous-drain, so an unread
  pipe never stalls the child), enforces a 30-second timeout (SIGTERM, then SIGKILL after
  a 5-second grace period), and writes a row to the new `extraction_failures` table on
  nonzero exit, timeout, or spawn error, tagged with a `failure_reason` taxonomy
  (`nonzero_exit`, `timeout`, `spawn_error`, `unreplayable`). Migration
  `085_extraction_failures.sql` adds the table (FK to `channel_transcripts` with
  `ON DELETE SET NULL`, raw-body fallback column when no FK is available, CHECK
  constraints on `status`/`failure_reason`/`retry_count`, four named indexes including a
  composite replay-order index). New script `memory/scripts/extraction-replay.sh`
  (flock-guarded, batch/retry-limit configurable via env, `row_to_json`+`jq` body
  reconstruction to avoid a pipe/newline parsing bug caught in QA) replays pending rows
  via the same stdin-feed contract as the hook, following the `memory-catchup.sh`
  cron-script pattern and `GLOBAL/CRON_DESIGN` (script is the system of record for DB
  writes, not an agent-turn prompt). Full detail:
  `memory/docs/memory-extraction-pipeline.md#1a-failure-handling-extraction_failures-dead-letter-table--replay-485`.
  **Known debt (not addressed by this change):** both the hook and the replay script
  default `PGDATABASE` to a hardcoded `nova_memory` rather than deriving it from the OS
  user, tracked separately under nova-mind#487 (umbrella) / nova-mind#481.

#### Tests
- `tests/issue-485/validate-migration.sh`, `tests/issue-485/test-handler.js`,
  `tests/issue-485/test-replay.sh`, `tests/issue-485/test-replay-d6b.py` — 92/92 PASS on
  nova-staging across migration validation (17), handler behavior (52), and replay-script
  behavior (23, including the row_to_json/jq regression case). See
  `tests/issue-485/TEST-RESULTS-integrated.log` for the full run and contamination check
  (zero residual test rows on staging and production).

### Batch: comms-items-unified-lifecycle-474 (Issue #474)

#### Added
- **`comms_items` table** (#474) — unified lifecycle for asynchronous inbound
  communications (Gmail, X mentions/DMs, Nostr DMs; GitHub notifications deferred to a
  follow-up issue). Dedupe key is `UNIQUE (platform, item_id)` using immutable source
  identifiers (Gmail message id, tweet id, Nostr event id). Lifecycle:
  `inbound → reported → tracked → resolved | dismissed`. Columns: `platform`, `item_id`,
  `thread_id`, `entity_id` (FK → `entities`, nullable), `status` (CHECK-constrained),
  `disposition` (`fyi|actionable|escalation|receipt|injection_suspect`, CHECK-constrained),
  `summary` (poller-voice text, never raw relayed prose), `artifact_ref`, `first_seen_at`,
  `reported_at`, `resolved_at`. Replaces the inbound-lifecycle role of `social_interactions`,
  which is dropped by the fold migration below. Owner: Communications domain (hermes).
- **`comms_responses` table** (#474) — approval-gate sub-lifecycle for outbound responses
  to inbound X/Nostr mentions and DMs, 1:1 linked to `comms_items` via `comms_item_id`
  (`ON DELETE CASCADE`). Carries `draft_response`, `approved_by`, `approved_at`,
  `response_id`, `responded_at`, `notes`. Preserves the `social_interactions`
  drafted/approved/posted workflow that would otherwise have been orphaned by the fold.
- **`resolve_entity_by_identifier(key text, value text) RETURNS bigint`** (#474) — shared
  SQL entity-resolution helper mirroring `resolver.ts` logic: looks up `entity_facts` by
  key/value (case-insensitive), preferring highest confidence then most recently
  confirmed. Used by both the fold migration and the ingest script so schema-side and
  script-side resolution stay in sync. Tolerates no match (returns `NULL`); callers are
  responsible for normalizing identifier formats (e.g., Nostr npub vs. hex) before calling
  — full normalization convention tracked as a follow-up (#227).
- **Migration `164-fold-social-interactions-to-comms-items.sql`** (#474) — post-pgschema,
  idempotent fold of legacy `social_interactions` into `comms_items`/`comms_responses`.
  No-ops on fresh installs (guards on `social_interactions` existing). Maps
  `seen→inbound`, `needs_response|drafted|approved→tracked`, `posted→resolved`,
  `dismissed→dismissed`; preserves `dismissed_reason`/`notes` content by folding it into
  `summary` rather than discarding it; preserves `created_at` as `first_seen_at`. Excludes
  NOVA's own outbound X rows (`author_handle = 'NOVA_Openclaw'`) — inbound-only per the
  #474 scope decision (2026-07-14: general social-interaction/outbound-activity tracking
  is out of scope for this table). Drops `social_interactions` after a successful fold.
- **Deterministic comms ingest pipeline** (#474, `scripts/comms/ingest.py`) — per
  GLOBAL/CRON_DESIGN, all `comms_items` writes are script-side, never agent-turn prose.
  Flow: fetch (per-platform adapter) → dedupe on `(platform, item_id)` **before any LLM
  reasoning** → resolve entity → classify (rule-based, no LLM) → upsert → archive-on-
  resolution. Platform adapters: `scripts/comms/adapters/gmail.py`,
  `scripts/comms/adapters/x.py`, `scripts/comms/adapters/nostr.py` (with
  `scripts/comms/adapters/bech32.py` for Nostr npub/hex conversion). A platform fetch
  failure is isolated (logged as a per-platform error) and does not abort ingest for the
  remaining platforms.
- **`scripts/comms/classifier.py`** (#474) — pure rule-based (no LLM) disposition
  classifier. Detects direct-address imperatives ("NOVA, please run..."),
  ignore-instructions phrasing, authority-spoofing ("as I)ruid, I'm asking you to..."),
  and system/tool-markup injection attempts, tagging them `disposition=injection_suspect`
  regardless of claimed sender identity — authorization derives from the delivery
  mechanism and resolved `entity_id`, never from payload claims. Also classifies
  `fyi`/`receipt`/`escalation` via marker-word matching, defaulting to `actionable`.
  Summaries are capped previews in the poller's own voice, never the full raw body, so an
  injection payload cannot ride the summary through to the Hermes→NOVA report hop.
- **Consolidated `hermes-comms-check` cron job** (#474, `scripts/comms/hermes-comms-check.sh`)
  — replaces the previous two enabled comms-check cron entries (agent=hermes short brief +
  agent=nova interim-mitigation brief) with exactly one job, every 4 hours, running as the
  `hermes` DB user (re-execs via `sudo -u hermes` if invoked as another user). Installed and
  drift-checked by `agent-install.sh` (`_install_hermes_comms_check_cron`); `--verify-only`
  reports missing/drifted/installed status alongside the existing D100-announcer cron
  check. Logs to `~/.openclaw/logs/hermes-comms-check.log`.
- **`comms_checks` audit logging retained** (#474) — `log_comms_check()` continues writing
  one audit row per deterministic ingest run (summary, per-platform new/existing/skipped
  counts, injection candidates, actionable items) even as the underlying lifecycle model
  changes from `social_interactions`/ad hoc state to `comms_items`.
- **Grants** (#474) — `comms_items`/`comms_responses` follow the `comms_state` grant
  pattern: `hermes` retains INSERT/UPDATE (writer of record per CRON_DESIGN), DELETE
  revoked from `hermes`; all other non-owning agents have DELETE/INSERT/UPDATE revoked
  (SELECT retained); `nova` additionally has DELETE/INSERT revoked on `comms_responses`
  (approval actions happen through the workflow, not direct row creation).

#### Changed
- **`social_interactions` table removed** (#474) — dropped by migration 164 after its
  inbound rows are folded into `comms_items`/`comms_responses`. Outbound-only
  social-activity tracking (NOVA's own posts/likes/replies) was explicitly scoped out of
  `comms_items` (2026-07-14 scope decision) and has no replacement table in this change;
  see the #474 issue thread if that tracking need resurfaces.
- **`agent-install.sh`** (#474) — installs `scripts/comms/*.py` and `*.sh` to
  `~/.openclaw/scripts/comms/` (hash-compared, `--force` to overwrite), runs the 164 fold
  migration during schema apply, and installs/verifies the consolidated
  `hermes-comms-check` cron entry.

#### Tests
- `tests/TEST-CASES-ISSUE-474.md` — 50 test cases across 8 areas (schema structure,
  approval-gate sub-lifecycle, migration/fold, deterministic ingest, trust boundary/
  injection quarantine, entity resolution, boundary/adversarial sweep, cross-cutting
  concerns). See `tests/TEST-474-coverage-map.md` for the case→test-file mapping — 50/50
  passing.
- `tests/TEST-474-schema.sql`, `tests/TEST-474-migration.sql`,
  `tests/TEST-474-chunk1-schema.sql`, `tests/TEST-474-chunk2-migration.sql` — pgTAP schema
  and migration coverage.
- `tests/test_comms_ingest.py` — unit coverage for dedupe, classification, entity
  resolution, and archive-on-resolution behavior.
- `tests/test_comms_integration.sh` — end-to-end ingest→report integration coverage.
- `tests/install/test_hermes_comms_check_cron.bats` — cron installation/drift-detection
  coverage for the consolidated cron entry.
- Staging validation: 84/84 checks passing. QA validation: PASS.

#### Issues Closed
- #474 — `comms_items`: unified lifecycle + trust boundary for other-comms (email,
  mentions, DMs)

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
