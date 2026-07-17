# Changelog

## Unreleased

### Added
- **`extraction_failures` dead-letter table + replay path** (#485) — The `memory-extract` hook (`memory/hooks/memory-extract/handler.ts`) no longer discards failed extractions silently. It now: (1) captures capped 16384-byte tail buffers of the `extract_memories.py` child's stderr/stdout (`attachTailBuffer()`, continuous-drain to avoid pipe-stall hangs), (2) enforces a 30-second child-process timeout with SIGTERM → 5s grace → SIGKILL, (3) writes a row to the new `extraction_failures` table (migration `085_extraction_failures.sql`) on nonzero exit, timeout, or spawn error, with a `failure_reason` taxonomy (`nonzero_exit`, `timeout`, `spawn_error`, `unreplayable`), and (4) replaces the two previously-silent `psql` `.catch(() => ({stdout: ''}))` handlers with logged catches (`logPsqlError()`) — same fallback behavior, now observable. `channel_transcript_id` FKs to `channel_transcripts` with `ON DELETE SET NULL`; when no FK is available the raw message body is stored in a `content` fallback column (capped at 65535 chars) so the failure remains replayable. New script `memory/scripts/extraction-replay.sh` (flock-guarded against concurrent runs, `EXTRACTION_REPLAY_BATCH_LIMIT`/`EXTRACTION_REPLAY_MAX_RETRIES` env-configurable, default batch 10 / max retries 5) reconstructs message bodies via `row_to_json` + `jq` (fixes a QA-caught pipe-delimited parse bug that broke on embedded pipes/newlines) and feeds them to `extract_memories.py` via stdin, following the `memory-catchup.sh` cron-script pattern and `GLOBAL/CRON_DESIGN` (DB writes live in the script, not an agent-turn prompt). Rows exhausting `EXTRACTION_REPLAY_MAX_RETRIES` move to `retry_exhausted`; rows with neither a transcript FK nor a body fallback move to `unreplayable` — both are terminal states. Full docs: `memory/docs/memory-extraction-pipeline.md#1a-failure-handling-extraction_failures-dead-letter-table--replay-485`. Root cause: System Diagnostic run #447 found ~10% of extractions failing silently (10/112 in a 33h window) with no recovery path. **Known debt (not addressed by this change):** both the hook and the replay script fall back to a hardcoded `PGDATABASE=nova_memory` default rather than deriving it from the OS user — tracked by #487 (umbrella) / #481.
- **`placement` config option for `memory/plugins/turn-context`'s dynamic context block** (#439) — `openclaw.plugin.json`'s `configSchema` gains a `placement` enum (`system-prepend` default | `turn-prepend`). Default `system-prepend` is a no-op for existing installs (dynamic entity/domain/recall block still returned as `prependSystemContext`). `turn-prepend` returns the same block as `prependContext` instead, placing it adjacent to the current user turn rather than ahead of the base system prompt, to avoid invalidating the prompt-cache prefix on every turn. Turn reminders and the honorific guard always remain in `appendSystemContext` regardless of this setting. New exported pure functions `resolvePlacement()` and `buildPromptResult()` in `src/index.ts`; 12 unit tests in `src/index.test.ts` (TC-439-001–012). See `memory/plugins/turn-context/README.md#placement` for full detail and configuration example.
- **`scripts/measure-turn-cache-impact.py`** (#439, repo root `scripts/`) — Compares cache-read/write metrics between a baseline and an experiment session JSONL log to quantify the prompt-cache effect of the `placement` option above, including an AC-3 sanity check that converts the plugin's logged prepend-block character count to an estimated token count (`chars ÷ 4` heuristic) and gates on a ±10% match against the measured cacheWrite/turn drop. See root `CHANGELOG.md` (batch `turn-context-placement-cache-439`) and `memory/plugins/turn-context/README.md#placement` for usage and the token-estimate caveat.

### Migrations
- `085_extraction_failures.sql` (#485) — Creates `extraction_failures` (dead-letter table for failed memory extractions), four named indexes (`idx_extraction_failures_status`, `idx_extraction_failures_channel_transcript_id` partial on non-NULL FK, `idx_extraction_failures_created_at`, `idx_extraction_failures_replay_order` composite matching the replay script's batch-selection ordering), and CHECK constraints on `status`, `failure_reason`, and `retry_count >= 0`.

### Tests (#485)
- `tests/issue-485/validate-migration.sh` — Staging validation for migration 085 (table/index/constraint presence, FK behavior). 17/17 PASS.
- `tests/issue-485/test-handler.js` — Handler unit/integration tests covering tail-buffer capping, timeout + SIGTERM/SIGKILL sequencing, dead-letter writes for all three failure reasons, logged (non-silent) `psql` catch behavior, and secret-safety of logged error messages (TC-E2). 52/52 PASS.
- `tests/issue-485/test-replay.sh`, `tests/issue-485/test-replay-d6b.py` — Replay-script tests covering flock exclusivity, batch limit / retry ceiling behavior, `row_to_json`+`jq` body reconstruction (including the BUG-1 embedded-pipe/newline regression case, TC-D6b), and terminal-state transitions (`retry_exhausted`, `unreplayable`). 23/23 PASS (4 of which are TC-D6b).
- `tests/issue-485/TEST-RESULTS-integrated.log` — Full integrated run across all three chunks on nova-staging: **92/92 PASS**, zero residual test-row contamination verified on both staging and production.

### Tests
- `memory/plugins/turn-context/src/index.test.ts` (#439) — 12 new tests (TC-439-001–012) for placement-aware prompt assembly and config-value fallback.
- `tests/test_measure_turn_cache_impact.py` (#439, repo root `tests/`) — New suite for `scripts/measure-turn-cache-impact.py` covering the chars-to-tokens conversion, AC-3 sanity-check behavior, and CLI smoke paths.

### Added
- **Deterministic honorific guard in `memory/plugins/turn-context`** (#421) — New pure function `buildHonorificGuard(entityId, agentId, preferredName?)` in `src/honorific-guard.ts` appends a "Sir" honorific-policy instruction to `appendSystemContext` every turn: no guard for I)ruid (`entity_id=2`) talking to `nova`; a NOVA-exclusivity reminder for I)ruid talking to any other agent; a prohibition instruction for every other sender, including unresolved/unknown senders (fail-safe default). Wired into `before_prompt_build` as Step 2.6 in `src/index.ts`, right after Step 2.5 entity resolution, and is **never gated** by `prompt_helper_config` or message type (unlike every other subsystem in this plugin) — it reuses Step 2.5's resolved entity when `entity_resolver` is ON, or calls the new lightweight `resolveEntityForGuard()` helper (added to `src/entity-resolver.ts`) only when gating is OFF, avoiding both a skipped guard and duplicate/stacked entity resolution. `agentId` matching is exact-match case-sensitive on the literal string `"nova"`, using the raw undefaulted `ctx.agentId` so a missing/null/empty value fails closed away from the NOVA-exclusive case. Full behavior table, fail-closed semantics, and gating interaction documented in `memory/plugins/turn-context/README.md#honorific-guard`.

### Tests
- `memory/plugins/turn-context/src/honorific-guard.test.ts` (#421) — 27 unit tests (HG-001–HG-027), the first automated test suite for the turn-context plugin, run via `npx tsx --test` (`tsx` added as a `devDependency` in `package.json`). 20 additional integration scenarios (IT-001–IT-020) verified via staging desk review rather than an automated suite — see nova-mind#421 for the full test design and staging results.

### Fixed
- **`memory/plugins/turn-context/src/domain-identifier.ts` tolerates missing `agent_domains.keywords` column** (#384) — `loadDomains()` now probes `information_schema.columns` once per process lifetime to detect ecosystem instances with a drifted schema (e.g. `victoria_memory`) missing the `keywords TEXT[]` column, instead of throwing `column ad.keywords does not exist` on every turn. Column present → byte-identical query/behavior to pre-fix. Column absent → fallback query without `ad.keywords`, `keywords: []` on every domain row (keyword matching disabled, embedding-similarity matching unaffected), and exactly one process-lifetime warning naming the missing column and remediation. The column-presence cache is independent of, and longer-lived than, the existing 5-minute domain-row cache; only a *successful* probe result is cached (a probe failure assumes column-present and retries next cold call, never permanently disabling keyword matching on a transient error). See root `CHANGELOG.md` (batch `turn-context-tolerant-keywords-384`) and `memory/plugins/turn-context/README.md#schema-drift-tolerance-domain-identifier` for full detail.
- **`memory/lib/pg_env.py` per-field section precedence over ENV** (#405, originally [nova-workspace#33](https://github.com/NOVA-Openclaw/nova-workspace/issues/33)) — Updated identically (byte-for-byte) to the canonical `lib/pg_env.py`: a field explicitly defined (non-null, non-empty) in a requested `section` (e.g. `section="agent_chat"`) now wins over a pre-exported ambient ENV var for that field only, instead of ENV winning outright. Fields the section omits are unaffected. See root `CHANGELOG.md` (batch `pg-env-section-precedence-405`) and `memory/docs/database-config.md` for the full precedence table and per-language caveats (TypeScript/Bash unaffected by this fix — TS parity tracked in #403).

### Added
- **`memory/scripts/generate-daily-log.py`** (#397) — Generates/updates the current day's `memory/YYYY-MM-DD.md` from live database state (agent_chat activity, workflow_runs, lessons, events, tasks) inside a delimited generated block (`<!-- BEGIN GENERATED DAILY LOG -->` / `<!-- END GENERATED DAILY LOG -->`), preserving agent-written narrative outside the markers byte-for-byte. Supports `--date YYYY-MM-DD` for backfilling past (never future) dates and `--dry-run` for previewing without writing. Exit codes: 0 success, 1 hard-fail (DB error or marker corruption — no partial writes, atomic temp-file-plus-rename), 2 usage error. True no-op idempotency: re-running with no underlying DB changes makes zero writes and preserves file `mtime`. Workspace resolution follows `$OPENCLAW_WORKSPACE` → `~/.openclaw/workspace-$OPENCLAW_AGENT_ID` (only when `OPENCLAW_AGENT_ID` is set) → `~/.openclaw/workspace`. Credential hygiene: pops any inherited `PGPASSWORD` before connecting and reads only `host`/`port`/`database` from `postgres.json`, authenticating via `.pgpass` (same fix class as the Hermes `PGPASSWORD` incident, see `GLOBAL/DATABASE_ACCESS`). The "Key cron results" section is a static placeholder in v1 (cron-outcome tracking descoped, referenced back to #397). Full docs: `memory/docs/daily-log-generation.md`.
- **`agent-install.sh` daily-log cron installation** (#397) — Installs `generate-daily-log.py` plus two cron entries (nightly `5 0 * * *`, intraday `0 6,12,18 * * *`), default-on with a `--no-cron` opt-out. Dedupes by script path on re-install (no duplicate entries). Drift (an existing entry referencing the script path with an unexpected schedule) is detected and warned on — the installer never modifies a drifted entry automatically. `--verify-only` reports cron status (installed/missing/drifted) without ever modifying the crontab.

### Tests
- `tests/test_generate_daily_log.py` (#397) — 32 tests covering date validation, workspace resolution, postgres.json loading, PGPASSWORD hygiene, marker parsing/corruption detection, block-equality comparison, file update (create/append/replace/preserve-narrative), atomic-write failure handling, and live-DB integration paths (dry-run, happy path, idempotent re-run).
- `tests/install/test_generate_daily_log_cron.bats` (#397) — BATS coverage for fresh install, idempotent re-run, drift detection, `--no-cron`, and `--verify-only` (installed/missing/drifted) against a mocked `crontab` command.
- `pytest.ini` (#397) — new at repo root; registers the `integration` marker used by the live-DB test classes above.

### Added
- **`blockers` table + `d100_roll_log` roll history** (#356, #358) — Migration 082 adds the `blockers` table, a curated registry of items blocked on another entity's action (source_type in task/github_issue/workflow_run/unanswered_question/agent_chat_request, unique on `(source_type, source_ref)`, resolved `entity_id`, `priority`, `status` open/satisfied). Also adds `d100_roll_log`, populated by a trigger on `motivation_d100` (`trg_log_d100_roll`), so the gate check can answer "when was the most recent D100 roll across any slot" — `motivation_d100.last_rolled` is per-slot and can't answer that on its own. No FK from `proactive_outreach` to `blockers.id` — the polymorphic `(blocker_type, blocker_id)` pattern from #232 is preserved.
- **Workflow 27 (Proactive Mode) rewritten to 11 steps: dedicated Blocker Outreach step** (#356) — Migration 083 (idempotent) inserts a new step 8 ("Blocker Outreach") and renumbers the old steps 8/9/10 (Unsolved Problems, Filesystem Hygiene, D100) to 9/10/11. Steps 6 (Pending Tasks) and 7 (GitHub Issues) are rewritten to curation-only semantics — they upsert into `blockers` and no longer perform any outreach directly; all outreach cadence, cascade escalation, and channel resolution is centralized in step 8, driven by `check_step8_blocker_outreach()` in `proactive-gate-check.py`. Enforces a 24h entity-level cooldown and a 72h per-blocker cooldown (both strict `>`) against `proactive_outreach`, selects the top 3 eligible blockers per entity, and sends one consolidated message per entity at the most-escalated resolved channel. See `motivation/ARCHITECTURE.md#blocker-outreach-step-8` for full cascade/channel/reassignment rules.
- **Forced D100 roll after 12h** (#358) — `check_step11_d100()` in `proactive-gate-check.py` now also forces step 11 actionable whenever more than 12h have elapsed since the last row in `d100_roll_log` (or no roll is on record), independent of whether steps 1–10 found actionable work.
- **Cascade exhaustion detection + reassignment** (D-1 fix, commit b66f8da) — When an entity's outreach cascade level exceeds the number of contact channels available to them (`_is_cascade_exhausted()`) and they are not I)ruid, the blocker is reassigned to the next domain entity (`_reassign_exhausted_entity()`, via `agent_domains`/`user_domains`, excluding already-exhausted entities in the chain) rather than looping on an unreachable channel. If every domain entity is exhausted, the chain falls through to I)ruid (entity_id=2) as final fallback. If I)ruid himself is exhausted, the blocker holds at his last available channel/level on the normal 72h cadence — no reassignment past him, no dropped blockers.
- **`--reindex-files` flag for `memory-maintenance.py`** (#341) — Forces a full re-chunk and re-embed of all memory files (`memory/*.md` daily logs + `MEMORY.md`). Deletes existing `memory_file` and stale `daily_log` embeddings, then re-chunks and re-embeds every file. The entire delete-and-reinsert sequence runs inside a single `SAVEPOINT reindex_files`, rolling back to a clean pre-run state on any database or Ollama error. `--reindex-files --dry-run` performs zero database mutations and zero Ollama calls. `--reindex-files --skip-embed` is a no-op for reindexing, since the reindex logic lives inside the embed phase that `--skip-embed` skips entirely. See `memory/README.md#text-chunking` for the full operational procedure.

### Changed
- **`_chunk_text()` in `memory-maintenance.py` replaced with a paragraph/section-boundary chunker** (#341) — The previous chunker split memory files (daily logs, `MEMORY.md`) on a hard 1000-character boundary, routinely starting chunks mid-sentence (measured 86.67% mid-sentence starts on a realistic fixture set pre-fix). The new chunker splits on markdown headers (`#`–`######`) and paragraph breaks, greedily merges adjacent short paragraphs up to ~80% of `chunk_size`, and never merges across a header. Oversized paragraphs fall back to sentence-boundary, then word-boundary splitting. Post-fix measurement on the same fixture class: 7.69% mid-sentence starts (78.97 percentage point improvement), verified live on staging with real Ollama embedding calls. **Documented limitation:** fenced code blocks and single unbroken tokens longer than `chunk_size` are emitted whole as oversized atomic chunks (never split internally), logged via `logger.warning("Oversized atomic chunk emitted whole...")` — semantic integrity is prioritized over strict size-ceiling compliance for these cases. Because boundaries are structure-dependent, editing a previously-embedded file can shift earlier chunk boundaries; use the new `--reindex-files` flag (above) to regenerate clean boundaries for the whole file. Fast-follow #389 tracks automatic content-hash-based staleness detection for this. 36 new unit tests in `memory/tests/test_chunk_text.py`.

### Tests
- `memory/tests/test_migration_083_idempotency.py` — Seeds the pre-migration 10-step workflow 27 layout in a fresh test database, applies migration 083 twice, and asserts the second run is a safe no-op producing exactly the expected 11-step layout with no duplicate `(workflow_id, step_order)` rows.

### Migrations
- `082_blockers_and_d100_roll_history.sql` — Creates `blockers` and `d100_roll_log`, adds the `trg_log_d100_roll` trigger on `motivation_d100`.
- `083_blocker_outreach_workflow_27.sql` — Rewrites workflow 27 to 11 steps (new step 8, renumbered 8/9/10 → 9/10/11, curation-only step 6/7 descriptions). Idempotent: detects the post-migration layout and no-ops on rerun.

### Issues Closed
- #356 — Heartbeat-integrated blocker outreach (blockers registry, dedicated Step 8, cooldowns, cascade escalation, exhaustion/reassignment)
- #358 — Forced D100 roll after 12h via `d100_roll_log`

### Changed
- **Embedding scripts consolidated into unified `memory-maintenance.py` template** (#352) — Removed the four separate deprecated embedding scripts (`embed-full-database.py`, `embed-research.py`, `embed-memories.py`, `embed-library.py`) from `memory/scripts/`. Added `memory/templates/memory-maintenance.py` as the authoritative source, deployed to `~/.openclaw/scripts/memory-maintenance.py` by `agent-install.sh`. The installer now also removes stale copies of the deprecated scripts from deployed locations on upgrade. No functional change — `memory-maintenance.py` already absorbed all embedding logic in the prior consolidation.

- **Turn-context plugin replaces old semantic-recall and agent-turn-context hooks** (#182, #185) — The broken fire-and-forget internal hooks have been removed and consolidated into a single OpenClaw Plugin SDK plugin at `memory/plugins/turn-context/`. The plugin runs entity resolution, semantic recall, and turn reminders in parallel via `before_prompt_build` and `message_received` hooks.
  - `memory/hooks/semantic-recall/` — deleted (HOOK.md, IMPLEMENTATION.md, handler.ts, test-entity-resolution.js, verify-refactor.ts)
  - `memory/hooks/agent-turn-context/` — deleted (HOOK.md, handler.ts, package.json)
  - New plugin: `memory/plugins/turn-context/` with src/index.ts (main), src/entity-resolver.ts, src/semantic-recall.ts, src/turn-reminders.ts, src/shared/pg-pool.ts
  - Installer updated: `agent-install.sh` now installs the turn-context plugin and removes old hook references from OpenClaw config
  - `enable-hooks.sh` now only enables `memory-extract` and `session-init` hooks
  - `verify-installation.sh` updated to reflect current hooks
- **Installer fixes** (#182, #185) — Multiple improvements to `agent-install.sh`:
  - `agent_chat` config now populates full DB credentials from `postgres.json`
  - `hooks.token` generation triggers on `hooks.internal.enabled`
  - Embedding-config.json verification added
  - Entity-resolver post-install verification added

### Fixed
- **agentName removed from agent_chat config** (#182) — Removed `agentName` from agent_chat config injection (rejected by extension schema's `additionalProperties: false`).
- **Sender fields read from ctx.metadata** (#179) — Both memory-extract and semantic-recall hooks now read sender/provider fields from `ctx.metadata` (canonical location) with top-level fallbacks (`ctx.senderName`, `ctx.senderId`, etc.). This ensures correct sender attribution when the canonical message:received context from nova-openclaw #41 is deployed, which places sender fields at the top level.
  - **memory-extract handler**: Resolves `senderName`, `senderId`, `isGroup`, `senderUsername`, `senderTag`, `provider`, `channelName`, `guildId` using `meta.X ?? ctx.X` fallback chain where `meta = ctx.metadata`.
  - **semantic-recall handler**: Constructs JSON stdin payload using `meta.senderId ?? ctx.senderId` and similar fallbacks for senderName, provider.
  - **`senderUsername` added to `channel_transcripts` INSERT** — The `handler.ts` now conditionally includes `sender_username` in the transcript row when available from `ctx.metadata.senderUsername`.
- **psql `RETURNING id` output parsing fixed** (#179) — The memory-extract handler previously did not account for psql's `-t -A` output including a status line like `INSERT 0 1` after `RETURNING id`. Now uses regex `/^(\d+)/m` to reliably extract the numeric id, handling clean output (`"42"`), status-line output (`"42\nINSERT 0 1"`), and empty output (conflict, DO NOTHING). Extraction continues gracefully when psql fails.

### Added
- **Hook context fixes and grammar parser removal** (#174, #147, #156, #133) — Multiple hook reliability improvements and removal of deprecated grammar parser:
  - **memory-extract hook** now reads `ctx.content` (canonical OpenClaw context key) with fallback chain `ctx.content → ctx.rawBody → ctx.RawBody → ctx.message → ctx.Body`. Previously only checked `ctx.rawBody` then `ctx.message`.
  - **All three hooks** (memory-extract, semantic-recall, session-init) converted from `../../scripts/` relative paths (via `__dirname`) to absolute paths via `join(os.homedir(), '.openclaw', 'scripts/')`. This ensures hooks work correctly regardless of where they're installed from.
  - **semantic-recall hook** now passes structured JSON over stdin (content + metadata including senderId, senderName, provider, conversationId, isGroup, channelName, guildId, messageId) to `proactive-recall.py` instead of sending plain truncated message text. This enables channel-aware semantic recall with full context.
  - **proactive-recall.py** updated with JSON stdin parsing with backward-compatible plaintext fallback. Uses `json.loads()` to parse structured input and extracts the `content` field, falling back to treating stdin as plain text for legacy callers.
  - **Grammar parser removed** (#174) — Deleted the entire `memory/grammar_parser/` directory (14 files, ~3.5K lines), `memory/scripts/process-input-with-grammar.sh`, and associated test files (`test_anaphora.py`, `test_authority_facts.sh`, `test_duplicate_reinforcement.sh`, `test_grammar_integration.sh`, `test_issue44_simple.sh`, `memory/tests/TEST-CASES-ISSUE-80.md` marked deprecated). The Claude-based extraction pipeline (`extract-memories.sh` + `store-memories.sh`) is now the sole extraction path.
  - **No more ~/clawd references** in any hooks or scripts — all paths resolve via `os.homedir()/.openclaw/`.
  - **memory-extract handler**: Updated context field resolution — uses `ctx.conversationId` (primary), `ctx.provider` for direct provider detection, `ctx.channelName` for group subject, `ctx.guildId` for Discord guild IDs.

### Added
- **Structured chat transcript storage** (#165, #138, #170) — New `channel_sessions` and `channel_transcripts` tables replace the deprecated `conversations` table and JSONL file storage. Migration 067 creates both tables, adds `source_channel_transcript_id` and `source_channel_session_id` FK columns to `entity_facts`, and drops the legacy `conversations` table.
- **JSONL → DB ingest in `memory-catchup.sh`** (#165, #138, #170) — The catchup script now ingests JSONL session transcripts from `~/.openclaw/agents/*/sessions/*.jsonl` into `channel_sessions` + `channel_transcripts` during each run. Source files are deleted after successful DB commit. Extraction failures no longer block transcript ingestion.
- **Real-time channel transcript upsert in `memory-extract` hook** (#170) — `handler.ts` now does a lightweight upsert of `channel_sessions`/`channel_transcripts` during message processing, then passes the FK IDs (`SOURCE_CHANNEL_TRANSCRIPT_ID`, `SOURCE_CHANNEL_SESSION_ID`) as env vars to the extraction pipeline.
- **`store-memories.sh`: FK source pointers on `entity_facts`** (#170) — During fact insertion and reinforcement, `source_channel_transcript_id` and `source_channel_session_id` are populated on `entity_facts` rows. SQL injection fix in `fact_exists()` (ILIKE → exact LOWER equality).

### Changed
- **Semantic-recall handler: channel-aware entity routing** (#8, #159, #164) — The `extractIdentifiers()` function maps provider-specific sender IDs (`discord`, `telegram`, `slack`, `signal`) to the correct `EntityIdentifiers` fields. Uses `resolveEntityByIdentifiers()` for conflict detection — logs a data integrity warning and skips entity injection if identifiers match different entities.
- **Semantic-recall handler: fixed field paths** (#8, #159, #164) — Message text now reads from `event.context.content` (was `event.context.message`). Sender metadata reads from `event.context.metadata.senderId`/`.senderName`/`.provider`/`.senderE164` (was `event.context.senderId`). Legacy paths retained as fallbacks.
- **Semantic-recall handler: dynamic import for entity-resolver** (#8, #159, #164) — Uses `await import()` from `~/.openclaw/lib/entity-resolver/` instead of repo-relative static imports. Loads `pg-env.ts` before the entity-resolver module so `PGPASSWORD` is set before `pg.Pool` creation. Defines `EntityIdentifiers` interface inline since the source type path isn't available at install time.

### Added (renames.json mechanism — #107)

- **`memory/database/renames.json`** ([#107](https://github.com/nova-openclaw/nova-memory/issues/107)) — New declarative rename manifest. Declares column and table renames that must be applied before `pgschema plan/apply` can converge. Format:
  ```json
  {
    "renames": [
      { "table": "agent_chat", "column": { "from": "mentions", "to": "recipients" }, "pr": "#106" },
      { "table": "agent_chat", "column": { "from": "created_at", "to": "timestamp" }, "pr": "#106" },
      { "table": "agent_chat", "drop": "channel", "pr": "#106", "reason": "..." }
    ]
  }
  ```
- **`agent-install.sh` Step 1.5** ([#107](https://github.com/nova-openclaw/nova-memory/issues/107)) — New installer step reads `renames.json` and applies renames idempotently before `pgschema plan`. For each column rename, checks whether the `FROM` column still exists via `information_schema.columns`; skips if already renamed. Drops listed in `renames.json` are registered as intentional and excluded from the hazard-count filter in the pgschema plan check, preventing false "destructive change" blocking.

### Fixed
- **`shell-install.sh`: source `pg-env.sh` early so `PGPASSWORD` is set during reachability check** ([#134](https://github.com/nova-openclaw/nova-memory/issues/134)) — `lib/pg-env.sh` is now sourced at the top of the script before any config validation or DB checks:
  - Removed redundant manual `jq` parsing of `postgres.json` fields — `load_pg_env()` handles all env loading
  - Reachability check now uses plain `psql` (picks up `PGPASSWORD` from env); previously used `pg_isready` which does not test authentication
  - Added **empty password warning** for TCP hosts: if `PGHOST` is not a Unix socket and `PGPASSWORD` is unset, installer warns and suggests adding a password to `postgres.json`
  - Added **non-interactive detection**: if config is needed and stdin is not a TTY, installer exits (non-zero) with a clear error message instead of hanging on `read`
- **Shell injection fixes in memory-extract and semantic-recall hooks** (#155, #38) — Replaced `exec()`/`execSync()` with `spawn()`/`spawnSync()` using stdin pipes for safe argument passing. Message text is now piped via stdin instead of passed as shell arguments, preventing shell injection vulnerabilities. Environment variables are passed via the `env` option instead of shell string interpolation. The `proactive-recall.py` script now supports `--stdin` flag for stdin input. SENDER_ID sanitized to digits-only and SQL injection prevented via psql `-v` parameterized variables.
- **Shell injection fix in session-init hook** — Updated `exec()` to `spawn()` with argument array, removing shell string interpolation for participant IDs.

### Changed
- **Replaced `pg-schema-diff` with `pgschema` for declarative schema management** (#155) — The installer now uses [`pgschema`](https://github.com/pgplex/pgschema) (pgplex/pgschema) to diff and apply `schema/schema.sql` against the live database. Key changes:
  - **`pgschema` is now a required prerequisite** (`go install github.com/pgplex/pgschema@latest`)
  - **`migrate_schema()` function removed** from `agent-install.sh` — replaced by the full `pgschema plan → hazard-check → apply` pipeline
  - **Schema source of truth** is now `schema/schema.sql`, generated by `pgschema dump` (not `pg_dump`); contains no ownership, privilege, or `\connect` directives
  - **No SUPERUSER required** — installer works with a regular DB user (SUPERUSER was previously required by `pg-schema-diff` for plan validation via a temp DB)
  - **No privilege/ownership management** — `pgschema` does not generate `GRANT`/`REVOKE` or `ALTER OWNER` statements, avoiding permission conflicts that `pg-schema-diff` caused
  - **`--plan-db` points at the target DB** for accurate extension type resolution (e.g., `vector` columns from pgvector)
  - **`pre-migrations/` directory** added for data migration scripts that must run before the schema diff
  - **`.pgschemaignore` file** added (TOML) to exclude specific objects from `pgschema` management
  - **Installer version bumped to v2.2**

### Added
- **`agent_turn_context` table and per-turn injection hook** (#143) — New table stores short critical-context records (≤500 chars each) injected before every agent response. `get_agent_turn_context(agent_name)` aggregates context in priority order (UNIVERSAL → GLOBAL → DOMAIN → AGENT) up to a 2000-character budget with truncation warning. The new `agent-turn-context` hook fires on `message:received`, queries the table, and injects results into the agent's turn context with a 5-minute cache TTL per agent. Migration: `migrations/065_agent_turn_context.sql`.
- **Library domain schema** — New tables for storing written works (research papers, books, novels, poems, essays, articles, etc.) with normalized authors, flexible tagging, and work-to-work relationships. Database constraints enforce complete ingestion (summary, insights, and all core metadata are required). See `docs/library-schema.md` and `patches/add-library-schema.sql`.
- **Library semantic embedding** — Added `library` source type to `embed-full-database.py`. Embeds title, authors, summary, notable quotes, and tags for high-density semantic search. Full records are fetched on recall hit.
- **embed-full-database.py** — Added full database embedding script covering all source types (entities, facts, tasks, projects, agents, lessons, events, positions, media, vocabulary, library works).

### Fixed
- **Installer now handles schema migrations automatically** — when re-running `agent-install.sh` on an existing installation, missing columns are detected and added automatically. Users no longer need to run manual `ALTER TABLE` commands when the schema evolves. (#127)
- Remove old pg-env.sh/pg_env imports from migrated scripts (#117)

### Changed
- **Migrated 11 scripts to `env-loader` pattern** — replaced direct `source lib/pg-env.sh` with `source ~/.openclaw/lib/env-loader.sh` across all Bash scripts; env-loader provides a unified, repo-agnostic interface for loading PG credentials ([#115](https://github.com/nova-openclaw/nova-memory/issues/115))
- **Fixed POSTGRES→PG env var naming in `test-entity-resolution.js`** — replaced legacy `POSTGRES_HOST`/`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_DB` references with standard `PGHOST`/`PGUSER`/`PGPASSWORD`/`PGDATABASE` ([#115](https://github.com/nova-openclaw/nova-memory/issues/115))

### Changed
- **`shell-install.sh` now execs `agent-install.sh` after config setup** — no need to run both scripts separately; `shell-install.sh` handles the full install pipeline. Also fixed lib install ordering in `agent-install.sh` so loader functions are available before scripts that need them ([#104](https://github.com/nova-openclaw/nova-memory/issues/104))

### Added
- **Install PG loader functions to `~/.openclaw/lib/`** — `agent-install.sh` now copies `pg-env.sh`, `pg_env.py`, and `pg-env.ts` to `~/.openclaw/lib/` with SHA-256 hash-based update detection; all 12 scripts updated to import from the installed location instead of repo-relative paths ([#102](https://github.com/nova-openclaw/nova-memory/issues/102))

### Changed
- **All scripts migrated to centralized DB config** — 12 scripts (6 Bash, 4 Python, 2 shell helpers) now use shared `lib/pg-env.sh` / `lib/pg_env.py` loaders instead of hardcoded connection logic ([#95](https://github.com/nova-openclaw/nova-memory/issues/95))
  - Removed per-script `get_db_name()` functions and manual `DB_USER`/`DB_NAME`/`DB_HOST` variables
  - All connections now honor the centralized resolution order (ENV → `postgres.json` → defaults)
  - Added migration test suite: `tests/TEST-CASES-ISSUE-95.md` and `tests/verify-migration-95.sh`

### Added
- **Centralized database config** (`~/.openclaw/postgres.json`) with ENV variable fallback ([#94](https://github.com/nova-openclaw/nova-memory/issues/94))
  - Shared loader functions: `lib/pg-env.sh` (Bash), `lib/pg_env.py` (Python), `lib/pg-env.ts` (TypeScript)
  - `shell-install.sh` now writes `postgres.json` after database creation
  - `agent-install.sh` reads `postgres.json` and fails with guidance if missing
  - Resolution order: ENV vars → config file → built-in defaults
