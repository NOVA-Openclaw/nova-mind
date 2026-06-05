# Changelog

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
