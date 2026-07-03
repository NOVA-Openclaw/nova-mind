# Changelog

### Batch: blocker-outreach-356 (Issues #356, #358)

#### Added
- **`blockers` registry table** — Curated registry of items blocked on another entity's action, with `source_type`/`source_ref` unique constraint (upsert target for Steps 6/7), `entity_id`, `priority`, `status` (open/satisfied), and `satisfied_at`. (#356)
- **`d100_roll_log` table + trigger** — Roll-history table populated by a trigger on `motivation_d100`, used to detect staleness for the forced-D100 check. (#358)
- **Step 8 (Blocker Outreach)** — New dedicated step in the Proactive Mode workflow (id=27) that owns all blocker outreach cadence and channel escalation. Enforces a 24h entity-level cooldown and a 72h per-blocker cooldown (both strict `>`), selects the top 3 eligible blockers per entity (`priority ASC, first_seen ASC, id ASC`), and sends one consolidated message per entity at the most-escalated requested channel among its selected blockers. Cascade channel order: `discord_mention → discord_dm → signal → slack → email`, or `agent_chat` unconditionally for agent entities. (#356)
- **`check_step8_blocker_outreach()`** (`motivation/scripts/proactive-gate-check.py`) — Deterministic gate function driving Step 8: satisfied-blocker reconciliation (reopen clears `satisfied_at`), cooldown-eligible entity/blocker selection, cascade level derivation from prior `proactive_outreach` row counts (not delivered channel), and channel-exhaustion reassignment (next domain entity → I)ruid final fallback → hold-in-place if I)ruid himself is exhausted). (#356)
- **`check_step11_d100()` forced-D100 logic** — Step 11 (D100, renumbered from Step 10) is now forced actionable whenever more than 12h have elapsed since the last roll in `d100_roll_log` (or no roll on record), independent of whether other steps already had actionable work. ≤12h preserves the original mandatory-catch-all/optional behavior. (#358)
- **Tests** — `TestStep8BlockerOutreach` (cooldown boundaries, never-contacted entities, non-blocker-outreach isolation, top-3 tiebreak, empty tables, channel mapping, cascade exhaustion + reassignment) and `TestStep11D100` (forced-D100 cases) in `motivation/tests/test_proactive_gate_check.py`. New `tests/TEST-CASES-ISSUE-356.md` and `memory/tests/test_migration_083_idempotency.py`. 122 passing (was 104 at initial PR open, +18 from the D-1 exhaustion/reassignment fix).

#### Changed
- **Proactive Mode workflow (id=27) renumbered from 10 to 11 steps** — Steps 6 (Pending Tasks) and 7 (GitHub Issues) now only curate blocked items into the `blockers` registry (upsert; entity resolution via `agent_domains` → `user_domains` → fallback entity_id=2); they no longer send outreach directly. Step 7's prior inline cascade + 3-day cooldown text (introduced in #232, see the `batch-se-run-8` entry below) is removed entirely — that responsibility now belongs exclusively to the new Step 8. Old steps 8/9/10 (Unsolved Problems, Filesystem Hygiene, D100) are renumbered to 9/10/11.
- **HEARTBEAT.md, `motivation/ARCHITECTURE.md`, `motivation/scripts/README.md`** updated for the 11-step cascade, D100 now Step 11, and the new Step 8 Blocker Outreach reference section.
- **Cascade exhaustion detection + reassignment** — When an entity's cascade channels are exhausted, the blocker is reassigned to the next domain entity in line, with I)ruid as the final fallback; if I)ruid is also exhausted, the blocker is held in place rather than dropped. The outreach payload carries `exhausted` and `reassigned_from_entity_id` fields so downstream consumers can distinguish a fresh assignment from a reassignment.

#### Fixed
- **24h/72h cooldown off-by-one** — `check_step8_blocker_outreach()`'s cooldown comparisons used `>` against the cutoff instead of the intended "strict greater-than" semantics allowing the exact boundary hour through as eligible; corrected so elapsed == threshold still blocks, per spec.
- **`TestStep2UnansweredSessions` test drift** — Rewritten to match the prior `sessions.json` + per-session JSONL read refactor (predates this branch).
- **`TestStep3IntrospectionDualMirror` hardcoded-date flake** — Pre-existing bug (predates this branch, at `fb7252d`), fixed alongside the above while chasing a green full-suite run.

#### Migrations
- `082_blockers_and_d100_roll_history.sql` — Creates `blockers` registry table and `d100_roll_log` roll-history table + trigger off `motivation_d100`.
- `083_blocker_outreach_workflow_27.sql` — Rewrites workflow 27's `workflow_steps` for the 11-step layout described above. Idempotency-hardened: a PL/pgSQL DO-block guard detects the already-applied 11-step layout and skips re-running the renumbering, and the new Step 8 insert uses `ON CONFLICT (workflow_id, step_order) DO NOTHING`. **Not yet applied to the production database as of this branch** — per the `agent-install.sh` migration-application gap tracked in #355, migrations 082/083 must be applied manually on deploy.

#### Known Caveats
- **#355 caveat carried forward** — `agent-install.sh` does not apply `memory/migrations/`; migrations 082 and 083 in this batch are subject to the same gap already reported for migrations 077–079 and must be applied manually to the production database on deploy.

#### Issues Closed
- #356 — Heartbeat-integrated blocker outreach (dedicated Step 8, curation/outreach split, cascade escalation, reassignment)
- #358 — Forced D100 roll past 12h staleness threshold, independent of other steps' actionable state

---

### Batch: consolidate-embedding-scripts (Issue #352)

#### Changed
- **Embedding scripts consolidated into `memory-maintenance.py` template** (#352) — Removed the four separate deprecated embedding scripts (`embed-full-database.py`, `embed-research.py`, `embed-memories.py`, `embed-library.py`) from `memory/scripts/`. The authoritative source is now `memory/templates/memory-maintenance.py`, deployed to `~/.openclaw/scripts/memory-maintenance.py` by `agent-install.sh`. The installer cleanup block also removes stale copies of these deprecated scripts from both deploy targets (`~/.openclaw/workspace/scripts/` and `~/.openclaw/scripts/`) on upgrade. No functional change — `memory-maintenance.py` already absorbed all embedding logic in the entity-facts-quality batch.

#### Issues Closed
- #352 — Consolidate deprecated embedding scripts; move `memory-maintenance.py` to `memory/templates/`

---

### Batch: installer-bugs-266-315-316 (Issues #266, #315, #316)

#### Bug Fixes

- **#266 — `NOVA_DIR` unbound variable:** `NOVA_DIR="$HOME/.local/share/nova"` is now defined in the path constants block at the top of `agent-install.sh` (line ~71), before any reference to it. Previously the variable was first assigned inside the shell environment setup block (line ~2044), causing an unbound variable error under `set -u` / `bash -o nounset` environments and silently expanding to an empty string otherwise. The nova data directory (`~/.local/share/nova/`) stores `shell-aliases.sh` and the Python venv used by motivation scripts.

- **#315 — `cp -r` directory nesting on reinstall:** `install_metacognition_plugin()` now runs `rm -rf "$plugin_target/$f"` before `cp -r` when the entry being copied is a directory (e.g., `src/`). Previously, a second install would nest the source directory inside the existing target (`src/src/index.ts` etc.) because POSIX `cp -r src/ dest/` appends `src/` as a subdirectory when `dest/src/` already exists rather than replacing it in place.

- **#316 — Plugin config overwrite destroys existing settings:** The `jq` expression in `install_metacognition_plugin()` that writes plugin entries to `openclaw.json` now uses a merge pattern: `.plugins.entries[$name] = (.plugins.entries[$name] // {}) * { ... }` instead of a direct assignment `= { ... }`. This preserves any existing per-plugin settings (custom hooks config, feature flags) set outside the installer, deep-merging only the installer-managed keys (`enabled`, `hooks.allowConversationAccess`) over the existing entry.

---

### Batch: confidence-check-two-phase (Issues #272, #312)

#### Changed
- **Confidence-Check Plugin** (`cognition/metacognition/confidence-check/`) — Substantially rewritten for two-phase architecture:
  - **Two-phase architecture** (#312): Mandatory Phase 1 self-verification pass (priorAttempts=0) always fires before any external evaluation. Phase 1 returns a revision action asking the model to verify truthfulness, sources, assumptions, knowledge boundaries, and self-consistency. No LLM call at Phase 1.
  - **SDK LLM migration** (#272): Replaced raw HTTP Anthropic API calls with `api.runtime.llm.complete()`. No API key management or raw HTTP in plugin code.
  - **Citation verification** (#272): Extracts URLs, file paths, code references, and doc references from the response; cross-references against tool calls in `event.messages`. Unverified citations forwarded to LLM evaluator as negative confidence signals.
  - **Self-contradiction detection** (#272): Extracts prior assistant messages and includes them in the LLM evaluation prompt. User messages are excluded — self-contradictions only.
  - **Confidence threshold raised** (#272): From 70% to 85%.
  - **Auto-pass shortcut removed** (#312): Heuristics (hedging density, unsupported assertions) are signals forwarded to the LLM — no longer used to bypass external evaluation.

#### Bug Fixes (D1–D7, merged with #312)
- **D1 (toggle path + off-by-one):** `self_verification_enabled=false` toggle correctly skips Phase 1; `externalAttempts` and post-framing threshold correctly account for whether Phase 1 ran.
- **D2 (missing runId guard):** Missing `runId` in hook context causes skip to prevent cross-run state contamination.
- **D3 (memory leak):** `retryAttempts.delete(idempotencyKey)` now called on PASS to prevent Map growth.
- **D4 (off-by-one):** `attemptsRemaining` calculation corrected to show remaining future attempts.
- **D5 (framing idempotencyKey):** Framing revision action now includes `idempotencyKey` for consistency with Phase 1 and Phase 2 actions.
- **D6 (robust JSON parsing):** LLM response JSON extraction uses brace-scanning (`indexOf("{")`/`lastIndexOf("}")`) instead of a `^`-anchored regex, handling prose preambles before the JSON object.
- **D7 (Claude content array support):** `extractContradictionContext()` now handles Claude-style assistant message content arrays (`[{type:"text", text:"..."}]`), not just plain strings.

#### State Machine
```
priorAttempts === 0  →  Phase 1: Self-verification (always)
priorAttempts === 1  →  Phase 2: External evaluation; revise if confidence < 85%
priorAttempts === 2  →  Phase 2: External evaluation; revise if confidence < 85%
priorAttempts === 3  →  Phase 3: Framing pass
priorAttempts === 4  →  Post-framing: allow finalization, cleanup
```
Maximum hook invocations per run: 5.

#### Config Requirements
`plugins.entries.confidence-check` in `openclaw.json` now requires:
- `hooks.allowConversationAccess: true` — enables `event.lastAssistantMessage` and `event.messages`
- `llm.allowModelOverride: true` — allows `api.runtime.llm.complete()` model override
- `llm.allowedModels: ["deepseek/deepseek-v4-flash"]` — allowlist for evaluation model

#### Documentation
- Added `cognition/metacognition/confidence-check/README.md` documenting two-phase architecture, state machine, config requirements, citation verification, and known limitations.

#### Issues Closed
- #272 — SDK LLM migration, citation verification, self-contradiction detection, threshold raised to 85%
- #312 — Mandatory self-verification Phase 1 (two-phase architecture)

---

### Batch: domain-routing-tiered-recall (Issues #150, #140, #168)

#### Added
- **Message Type Classifier** (`classifier.ts`) — Rule-based classification of inbound messages into `info_request`, `action`, `conversation`, `continuation`, `command`. Ollama LLM fallback for ambiguous cases. Handles ~60-70% of messages without LLM.
- **Domain Identifier** (`domain-identifier.ts`) — Matches messages to subject-matter domains via keyword matching + embedding similarity against `agent_domains` table. Returns top 1-3 ranked domains with assigned agent names (resolved via JOIN, not hardcoded).
- **`prompt_helper_config` table** — Configurable per-message-type gating for turn-context subsystems. Per-agent overrides supported.
- **`agent_domains.keywords` column** — Keyword arrays for fast domain matching. All 38 domains seeded.
- **Domain embedding seeder** (`seed-domain-embeddings.py`) — Embeds domain descriptions into `memory_embeddings` for vector similarity matching.
- **Visibility filtering** in `proactive-recall.py` — Group channels filter entity_facts to `visibility = 'public'` only via JOIN. DM channels show all facts.
- **Tiered recall** — Domain-scoped search first when domain hints available, full vector search as fallback.

#### Changed
- **`index.ts`** — Classifier-first dispatch architecture. Subsystems gated by `prompt_helper_config` table. Turn reminders always fire regardless of message type.
- **`entity-resolver.ts`** — Cache key changed from `sessionKey` to `sessionKey:senderId` (bugfix for group channels). Now returns `{ text, entityId }` tuple.
- **`semantic-recall.ts`** — Accepts `domainHints`, `entityId`, `isGroup` params. Passes through to `proactive-recall.py`.
- **`proactive-recall.py`** — Accepts `entity_id`, `is_group`, `domain_hints` via stdin JSON. Tiered recall with domain-scoped SQL query. Visibility filtering via LEFT JOIN on entity_facts.

#### Migrations
- `081_prompt_helper_config.sql` — Creates `prompt_helper_config` table, adds `keywords TEXT[]` to `agent_domains`, populates notes/keywords for all 38 domains. **Note:** Must be run split — `agent_domains` changes as newhart (table owner), `prompt_helper_config` as nova.

#### Issues Closed
- #150 — Selective semantic recall + prompt preprocessing for domain routing
- #140 — Tiered recall strategy
- #168 — Visibility filter in semantic-recall hook

---

### Batch: ghost-entity-prevention (Issues #230, #267, #295)

#### Changed
- **Ghost Entity Prevention and Enhanced Entity Resolution** — Implemented new `is_plausible_entity()` function to filter out non-entity strings (e.g., environment variables, file paths, generic roles) from being created as entities.
- **`find_entity_id()` enhancements** — Extended `find_entity_id()` with improved matching logic including `alternate_spellings` column, domain-to-entity normalization, and whole-word substring matching.
- **`entities.alternate_spellings` column** — Added `alternate_spellings TEXT[]` column to the `entities` table with a GIN index to support more flexible entity matching. (Migration 080)
- **`entity_type_map` for type inference** — `extract_memories.py` now uses `entity_type_map` to infer entity types during fact storage, ensuring consistency (e.g., preventing 'VALID' from being both 'person' and 'organization').
- **`ensure_entity()` name-collision guard** — Added logic to `ensure_entity()` to prevent creating new entities with names that collide with existing ones, even if they have different inferred types.
- **`deviceId` added to `EntityIdentifiers`** — The `deviceId` field was added to `EntityIdentifiers` and `IDENTIFIER_TO_DB_KEY` in the entity resolver, improving resolution for device-specific entities.

#### Migrations
- `080_entities_alternate_spellings.sql` — Adds `alternate_spellings` column and GIN index to the `entities` table.

#### Issues Closed
- #230 — Ghost entity filtering
- #267 — `alternate_spellings` column for entities
- #295 — `deviceId` added to entity resolver



### Batch: embeddings-batch (7 issues, see commit for details)

#### Changed
- **Embedding model unified** to `snowflake-arctic-embed2` (was `mxbai-embed-large`).
- **Stale table references removed**: `trading_signals`, `positions`.
- **New tables added** to embedding: `journal_entries`, `music_works`, `workflow_runs`, `income_sources`.
- **Column fixes**: `lessons.content` -> `lessons.lesson`, `library` -> `library_works`, `research_conclusions.content` -> `COALESCE(title, summary)`, `vocabulary.term` -> `vocabulary.word`.
- **New lessons dedup phase** added to `memory-maintenance.py` with `--skip-lesson-dedup` flag.
- **Graceful error handling** — per-table try/except with SAVEPOINT, warning counts, `OllamaConnectionError`.



### Batch: agent-identity-batch (Issues #244 + nova-openclaw#243)

#### Changed
- **Per-gateway agent scoping in `agent-config-sync`** — `cognition/focus/agent-config-sync/src/sync.ts` now reads from the DB function `get_agent_export_rows()` instead of `SELECT ... WHERE instance_type != 'peer'`. Each peer gateway's `agents.json` is now scoped to that gateway's own session_user identity (the connecting peer plus its `parent_agents`-linked subagents). Fixes default-agent confusion on Newhart/Graybeard gateways. (#244)
- **UPPERCASE source labels from `get_agent_bootstrap()`** — `database/schema.sql` now emits `UNIVERSAL`/`GLOBAL`/`DOMAIN:<name>`/`WORKFLOW:<name>`/`AGENT` instead of the lowercase variants. The bootstrap-context hook composes synthetic paths as `db:${source}/${filename}`, so injected file headers now read `db:UNIVERSAL/CORE.md`, `db:DOMAIN:Project Leadership/ORCHESTRATION.md`, etc. Aligns with `agent_bootstrap_context.context_type` column values. (#244)

#### Tests
- `cognition/focus/agent-config-sync/src/sync.test.ts` — 24 new unit assertions covering `buildAgentsList()` against `get_agent_export_rows()` (TC-244-U-01 through U-05): peer-as-default emission, subagent ownership filtering, `is_default` handling, empty-result safety, and absence of cross-peer leakage.
- `tests/TEST-CASES-batch-agent-identity.md` — 1,045-line test design for the coordinated #244 + #243 staging rollout.

#### Cross-repo coordination
- Pairs with nova-openclaw [#243](https://github.com/NOVA-Openclaw/nova-openclaw/issues/243) which preserves the new `db:TIER/...` synthetic path identifiers through the gateway's `sanitizeBootstrapFiles()` sanitizer. Both branches must land together — staging install order is nova-openclaw first, then nova-mind.

#### Issues Closed
- #244 — agent_config_sync per-gateway scoping + UPPERCASE bootstrap source casing

### Batch: batch-se-run-8 (Issues #232, #234, #237)

#### New Features
- **nova-motivation merge** — Merged `nova-motivation` repository into `motivation/` subdirectory. The standalone `nova-motivation` repo is targeted for archival. Includes shell aliases, git pre-push hook, and deployment scripts. (#234)
- **agents.entity_id FK column** — Added nullable `entity_id` column to `agents` table referencing `entities(id)`, populated from name matches for all active agents. (#234)
- **agent_domains priority + constraint refactor** — Added `priority INTEGER DEFAULT 1` column and changed UNIQUE from `(domain_topic)` to `(agent_id, domain_topic)`, allowing multiple agents to share the same domain. (#234)
- **user_domains table + seed data** — New table mapping users to their domains with priority ordering. 17 seed rows across 5 users (I)ruid, Neva, Regan, Tabatha Wilson, Zonk Ruehl). (#232)
- **proactive_outreach table** — Tracks outreach attempts for blocked tasks/problems/D100 items, with cooldown indexing for escalation logic. (#232)
- **Proactive Mode outreach cascade** — Steps 4, 5, 6 of Proactive Mode workflow (id=27) now describe the blocker outreach cascade: domain → user lookup by priority, Discord→Signal→Slack→Email escalation, 3-day cooldown via `proactive_outreach`, I)ruid as final fallback. (#232)
- **Tabby email entity_fact** — Added `yellowsubtab@gmail.com` as entity_fact for entity 3 (Tabatha Wilson). (#232)

#### Removed
- **channel_activity table** — Dropped in favor of native OpenClaw idle detection. HEARTBEAT.md and Proactive Mode workflow updated to use `sessions_list`, `message(action="read")`, and inbound message metadata for idle detection. (#237)

#### Migrations
- `075_agents_entity_id.sql` — Adds `entity_id` FK column and populates from entity matches
- `076_agent_domains_constraint_refactor.sql` — Drops `domain_topic` UNIQUE, adds `priority`, adds `(agent_id, domain_topic)` UNIQUE
- `077_user_domains.sql` — Creates `user_domains` table with 17 seed rows
- `078_proactive_outreach.sql` — Creates `proactive_outreach` table, adds Tabby email entity_fact
- `079_drop_channel_activity.sql` — Drops `channel_activity`, updates workflow step descriptions for outreach cascade

#### Issues Closed
- #234 — Merge nova-motivation + agents.entity_id + agent_domains refactor
- #232 — Proactive mode user prompting with outreach cascade
- #237 — Drop channel_activity, fix idle detection with native OpenClaw data

#### New Features
- **Confidence-Check Plugin** (`cognition/metacognition/confidence-check/`) — Evaluates response confidence via heuristic pre-screen (hedging phrase density, unsupported assertions) and LLM evaluation, triggers revision via Socratic questioning. Hooks into `before_agent_finalize`. Requires `allowConversationAccess: true` in plugin config. (#75)
- **Self-Awareness Plugin** (`cognition/metacognition/self-awareness/`) — Monitors outbound messages for self-awareness triggers via semantic embedding similarity against curated trigger phrases in the `self_awareness_triggers` table. Hooks into `message_sent`. (#221)
- **Psyche Consolidation** — Migrated design documents from standalone `nova-psyche` repo into `psyche/` directory. The `nova-psyche` GitHub repo is now archived. (#222)
- **Entity fact extraction from outbound messages** — `extract_memories.py` now processes agent outbound messages in addition to inbound, enabling fact capture from NOVA's own responses. (#224)
- **agent_id entity_facts for agent resolution** — `turn-context` plugin resolves agent entities via `agent_id` key in entity_facts, enabling proper agent identification in multi-agent conversations. (#225)
- **parent_agent_id column** — Added `parent_agent_id` column to `agents` table with migration and seed data for subagent hierarchy tracking. (#226)

#### Installer Improvements
- **Superuser schema application** — Installer now handles DDL requiring superuser privileges (extensions, ownership changes) via `sudo -u postgres` with configurable `PG_SUPERUSER_HOST` defaulting to `/var/run/postgresql` for Unix socket peer auth. (#217)
- **Metacognition plugin installation** — Installer builds and deploys confidence-check and self-awareness plugins to `~/.openclaw/plugins/`.
- **TypeScript dependency fix** — `@types/node` installed as production dependency for plugins that need it.
- **Schema file accessibility** — Installer copies schema to `/tmp` for pgschema superuser access.

#### Bug Fixes
- Fixed confidence-check infinite framing loop when maxAttempts exhausted
- Fixed migration 074 referencing non-existent `source` column on `entity_facts`
- Removed accidentally committed `node_modules` and `dist` from self-awareness plugin

#### Migrations
- `074_agent_id_entity_facts.sql` — Seeds `agent_id` entity_facts for all active agents

#### Issues Closed
- #75, #217, #221, #222, #224, #225, #226
- #231 (nova-psyche repo archival)

---

## [2026-05-14]

### Batch: entity-facts-quality

#### Changes
- **Unified memory maintenance script** — `memory/scripts/memory-maintenance.py` completely rewritten as a 9-phase pipeline absorbing the separate embedding scripts (`embed-full-database.py`, `embed-memories.py`, `embed-research.py`) and previous maintenance logic.
- **New DB function `merge_entities()`** — Dynamically discovers FK references, handles entity_facts same-key merging via `merge_facts()`, transfers nicknames, and manages memory_embeddings.
- **Unique constraint** — Added `uq_memory_embeddings_source` unique index on `memory_embeddings(source_type, source_id)` to prevent duplicate embeddings.
- **Scheduling change** — Removed from crontab (was `0 4 * * *` for decay and `0 11 * * *` for embedding). Now triggered from HEARTBEAT idle cascade as priority #2 with a 4-hour cooldown gate.
- **CLI flags** — `--dry-run`, `--verbose`, `--force`, `--state-file`, `--skip-embed`, `--skip-consolidation`, `--skip-dedup`, `--skip-decay`, `--skip-ghost-cleanup`, `--skip-entity-dedup`.
- **Deprecated scripts** — `embed-memories-cron.sh` deprecated (absorbed into memory-maintenance.py). `embed-full-database.py`, `embed-memories.py`, `embed-research.py` deprecated in favor of `memory-maintenance.py`.

#### Issues Closed
- #216 — Entity-level deduplication
- #202 — Cross-key (cross-entity) fact consolidation
- #200 — Ghost entity cleanup
- #203 — Confidence decay with archiving
