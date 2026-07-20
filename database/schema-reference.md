# Database Schema Reference

*Auto-generated: 2026-06-09T03:38:05.109007*

> **Stale as of nova-mind#320 for `agent_chat` / `agent_chat_processed`.** This file was
> generated before the #320 migration and lists `agent_chat` and `agent_chat_processed`
> below as if they are `nova_memory` tables. As of #320, both tables live in a separate,
> dedicated `agent_chat` database — not `nova_memory`. This is an auto-generated file;
> do not hand-edit the table listing below to "fix" this. Regenerate it against the
> current `nova_memory` schema (which will correctly omit `agent_chat`/`agent_chat_processed`
> going forward) using whatever tool produced it originally, and see
> `memory/docs/database-config.md` / `scripts/agent-chat-migration/README.md` for the
> current `agent_chat` schema and connection story.
>
> **Additional drift found during the #414 documentation audit (2026-07-11):**
> `asset_classes`, `price_cache_v2`, and `portfolio_snapshots` are listed
> below but no longer exist in the live `nova_memory` schema (portfolio-domain tables
> removed since this file was generated) — **still confirmed absent from both the live
> schema and `database/schema.sql`** as of the #506 audit (2026-07-20). `user_domains`
> (6 columns) and `motivation_d100` exist in the live schema but are missing from the
> listing below — **`motivation_d100`'s column count has been corrected to 18** (this note
> previously said 20, which was itself wrong; verified against both the live schema and
> `database/schema.sql`'s declarative `CREATE TABLE`). `comms_checks`, `income_sources`, and
> `music_analysis` were checked against live and still match the counts listed below (11,
> 12, and 11 respectively) — no drift found there. Do not hand-patch these counts either —
> this note exists so the next regeneration pass has a starting checklist.
>
> **#474 update (2026-07-15), corrected 2026-07-20:** `comms_items` (unified other-comms
> lifecycle, 12 columns) and `comms_responses` (approval-gate sub-lifecycle, 9 columns)
> have been added to the listing below — those two tables are confirmed live. **However,
> `social_interactions` is NOT actually removed** — migration
> `cognition/scripts/migrations/164-fold-social-interactions-to-comms-items.sql` (which
> folds `social_interactions` into `comms_items`/`comms_responses` and then drops the
> table) has not yet been run against the live production `nova_memory` schema as of the
> #506 audit (2026-07-20): `social_interactions` (16 columns) is still present in both
> the live database and `database/schema.sql`'s declarative `CREATE TABLE`. The 2026-07-15
> note below claiming removal was premature — restored `social_interactions` to the table
> listing. Re-check after migration 164 actually runs, then remove the row again.
>
> **#485 update (2026-07-17), confirmed live 2026-07-20:** `extraction_failures`
> (dead-letter store for failed memory extractions, 16 columns) from migration
> `memory/migrations/085_extraction_failures.sql` **is now confirmed present in the live
> production `nova_memory` schema** (16 columns, matches the listing below exactly) — the
> migration has landed since the note below was written. The row below no longer needs the
> "not yet in live production schema" caveat; corrected during the #506 audit.
>
> **#506 audit (2026-07-20) — additional drift found, not yet regenerated:**
> - `entity_credibility` (10 columns: `id`, `entity_id`, `domain`, `score`, `claim_count`,
>   `corroborated_count`, `contradicted_count`, `last_computed_at`, `computation_version`,
>   `evidence_snapshot`) exists live but is **missing from this listing entirely** and is
>   **not declared anywhere in `database/schema.sql` or any migration file in this repo** —
>   it appears to have been created directly against production outside the declarative
>   schema process. Per-(entity, domain) source credibility (S axis of S×D×V); computed by
>   a daily maintenance script, never hand-assigned. Flagged for the Database/schema.sql
>   owner (Newhart) to add the `CREATE TABLE` to `database/schema.sql` — Technical Writing
>   does not add tables to the declarative schema itself, only documents what exists
>   (see `ARCHITECTURE.md`'s schema-sync process description).
> - Column-count drift (doc vs. live, corrected below): `agents` 37→38, `artwork` 27→28,
>   `entity_fact_sources` 8→11, `entity_facts` 19→21.
> - Views (`v_agents`, `v_agent_spawn_stats`, `v_current_stateful_facts`, `v_entity_facts`,
>   `v_event_timeline`, `v_fact_grades`, `v_gambling_summary`, `v_media_queue_pending`,
>   `v_media_with_tags`, `v_metamours`, `v_pending_tasks`, `v_pending_test_failures`,
>   `v_ralph_active`, `v_relationships`, `v_task_tree`, `v_users`, plus the
>   `workflow_steps_detail` view referenced elsewhere in the docs and `delegation_knowledge`)
>   are out of scope for this file by original design — this listing only ever covered base
>   tables — noted here only so a future full regeneration doesn't mistake the absence of a
>   Views section for an oversight.
> - Do not hand-patch further — this note exists so the next regeneration pass has a
>   complete starting checklist across all four audit passes (#414, #474, #485, #506).

## Tables

| Table | Description | Columns |
|-------|-------------|---------|
| agent_actions | Agent action definitions. READ-ONLY except Newhart. | 8 |
| agent_aliases | Agent aliases for flexible mention matching. Supports case-insensitive routing. | 4 |
| agent_bootstrap_context | Bootstrap context entries. Agents may write to their own AGENT-scoped records (matching their db user). Newhart (Agent Design/Management domain) manages schema, cross-agent entries, and GLOBAL/UNIVERSAL-scoped records. | 9 |
| agent_chat | Agent messaging. INSERT allowed for all, UPDATE/DELETE only Newhart. | 6 |
| agent_chat_processed | Message processing state. Agents can track, Newhart manages. | 7 |
| agent_domains | Agent domain assignments. READ-ONLY except Newhart. | 9 |
| agent_jobs | Agent job definitions. READ-ONLY except Newhart. | 18 |
| agent_modifications | Agent modification history. READ-ONLY except Newhart. | 7 |
| agent_spawns | Tracks all agent spawns from the general-purpose spawner daemon | 14 |
| agent_system_config | Agent system configuration. READ-ONLY except Newhart. | 6 |
| agent_turn_context | - | 8 |
| agents | Agent registry | 38 |
| ai_models | Available AI models. NOVA maintains this; Newhart reads for agent assignments. Credentials and endpoints stored in 1Password (see credential_ref column). | 16 |
| artwork | Archive of NOVAs Instagram artwork. Reference for future compilation. | 28 |
| asset_classes | Asset class definitions for financial portfolio management. Defines tradeable asset types with pricing sources and trading characteristics. | 6 |
| blockers | Curated registry of items blocked waiting on another entity's action (issue #356). Populated by Proactive Mode workflow (id=27) Steps 6/7; outreach against this registry is centralized in Step 8. | 11 |
| bootstrap_context_config | Configuration for bootstrap system behavior | 4 |
| certificates | Client certificates issued by NOVA CA. Security-sensitive. Verify before modifications. | 12 |
| channel_activity | Tracks last message per channel for idle detection. Read/write: NOVA, Newhart. | 3 |
| channel_sessions | - | 16 |
| channel_transcripts | - | 14 |
| comms_checks | Individual Hermes check run results. Each row = one social/email/digest check. Replaces memory/hermes-*.md files. Owner: Communications domain (hermes). | 11 |
| comms_digests | Daily/weekly communications digests. Replaces hermes-social-digest-*.md and NOVA_Comms_Digest_*.html. Owner: Communications domain (hermes). | 11 |
| comms_items | Unified lifecycle for asynchronous inbound communications (email, X mentions/DMs, Nostr DMs). Dedupe key `(platform, item_id)`. Will replace the inbound-lifecycle role of `social_interactions` once migration 164 folds/removes it (issue #474) — as of the #506 audit, migration 164 has not yet run against production and `social_interactions` is still live (see row below). Owner: Communications domain (hermes). | 12 |
| comms_responses | Approval-gate sub-lifecycle for outbound responses to inbound X/Nostr mentions and DMs. 1:1 linked to `comms_items` (issue #474). Owner: NOVA Operations (approval), Communications domain (draft creation). | 9 |
| comms_state | Per-platform communications tracking state (seen IDs, cursors). Replaces hermes-social-state.json. Owner: Communications domain (hermes). | 5 |
| d100_roll_log | Roll history for motivation_d100 (issue #358), populated by a trigger on motivation_d100. Used by the Proactive Mode gate check to force a D100 roll after 12h regardless of other steps' state. `announced_at` (issue #432) tracks deterministic cron-based announcement to #proactive-mode, decoupled from the heartbeat LLM turn. | 4 |
| entities | People, AIs, organizations. NOVA has full access. Use entity_facts for attributes. | 22 |
| entity_credibility | Computed per-(entity, domain) source credibility (S axis of S×D×V). NEVER hand-assigned — derived from claim track record + verification events; recomputed by a daily maintenance script. Domain taxonomy reuses `entity_facts.category` vocabulary + `agent_domains` topics; `_global` is the fallback. **Not declared in `database/schema.sql` or any migration file — flagged during the #506 audit for the schema/Database domain owner to add.** | 10 |
| entity_fact_conflicts | Conflicts between entity facts requiring resolution. Part of the truth reconciliation system. | 13 |
| entity_fact_sources | - | 11 |
| entity_facts | Key-value facts about entities. Check current_timezone for I)ruid before time-based actions. | 21 |
| entity_facts_archive | Archived entity facts from decay/cleanup processes. Historical record of previously stored knowledge. | 20 |
| entity_relationships | Relationships between entities (family, work, friendship, etc). | 8 |
| event_entities | Links events to entities (people, orgs, AIs). Many-to-many relationship table. | 3 |
| event_places | Links events to places/locations. Many-to-many relationship table. | 2 |
| event_projects | Links events to projects. Many-to-many relationship table for project milestones and activities. | 2 |
| events | Historical events, milestones, activities. Log significant occurrences. | 10 |
| events_archive | Archived historical events. Long-term storage for events moved out of active events table. | 11 |
| extraction_failures | Dead-letter store for failed memory extractions from memory-extract hook (#485). Rows are inserted on nonzero exit, timeout, or spawn error and may be retried via extraction-replay.sh. Confirmed live in production as of the #506 audit (2026-07-20). | 16 |
| extraction_metrics | Performance metrics for data extraction processes. Tracks accuracy and efficiency of knowledge extraction. | 6 |
| fact_change_log | Audit trail for entity fact modifications. Tracks who changed what and when for accountability. | 7 |
| gambling_entries | Individual gambling session records. Tracks bets, outcomes, and session details for analysis. | 10 |
| gambling_logs | High-level gambling session summaries. Groups multiple gambling_entries by session. | 8 |
| git_issue_queue | Issue queue for git-based workflows. NOTIFY triggers dispatch work automatically. | 16 |
| income_sources | Registry of NOVA income streams — where money comes from, how to check it, and current status. Owner: NOVA. | 12 |
| income_transactions | Individual income transactions, each linked to an income_source. Owner: NOVA. | 10 |
| job_messages | Message log per job for conversation threading | 5 |
| journal_entries | Personal prose journal entries for agent self-reflection. Short, introspective, written multiple times daily. Embedded into memory_embeddings with source_type=journal. Triggers: heartbeat, d100, post_workflow, daily_report, conversation, incident, manual. | 6 |
| lessons | Lessons and insights learned. Update when learning something worth remembering. | 13 |
| lessons_archive | Archived lessons and insights. Historical record of previously stored learnings. | 13 |
| library_authors | Library domain: normalized author records. Managed by Athena (librarian agent). | 4 |
| library_tags | Library domain: subject/genre/topic tags for works. Managed by Athena. | 3 |
| library_work_authors | Links works to their authors. author_order preserves original ordering. | 3 |
| library_work_relationships | Tracks relationships between works (citations, sequels, responses, etc). | 3 |
| library_work_tags | Links works to subject/topic tags. | 2 |
| library_works | Library domain: all written works (papers, books, poems, etc). Managed by Athena (librarian agent). ALL core fields are NOT NULL — Athena must generate summary and insights during ingestion. The summary field is used for semantic embedding (200-400 words, high-density). On semantic recall hit, query this table for full details. | 25 |
| media_consumed | Books, movies, podcasts consumed by entities. Log completions here. | 19 |
| media_queue | Queue for media ingestion. Librarian agent processes these. | 15 |
| media_tags | Tags/topics for media items. Helps with recommendations and search. | 6 |
| memory_embeddings | Vector embeddings for semantic memory search. Used by proactive-recall.py. | 9 |
| memory_embeddings_archive | Archived vector embeddings from semantic memory system. Historical embeddings for backup/analysis. | 11 |
| memory_type_priorities | Priority weights for semantic recall by source_type. Higher = more likely to surface. NOVA can modify. | 5 |
| music_analysis | Deep musical analysis (harmonic, rhythmic, lyrical, spectral). Managed by Erato. | 11 |
| music_library | Music-specific metadata extending media_consumed. Managed by Erato. | 37 |
| music_works | Original music compositions (AI-generated or human-composed). Complements music_library which holds collected external sources. | 42 |
| place_properties | Properties and attributes of places. Key-value storage for place characteristics. | 5 |
| places | Locations (houses, venues, cities). Reference I)ruid houses in USER.md. | 15 |
| portfolio_snapshots | Historical snapshots of portfolio values and performance metrics over time. | 10 |
| preferences | User preferences by entity_id. Check before making assumptions. | 6 |
| price_cache_v2 | Cached price data for assets to reduce API calls. Version 2 of price caching system. | 12 |
| proactive_outreach | Tracks outreach attempts for blocked tasks/GitHub issues/unsolved problems/D100 items, and (as the current path) blockers-table rows via the dedicated Blocker Outreach step (issue #356). Cooldown logic (24h entity-level, 72h per-blocker) queries this table. | 11 |
| project_entities | Links projects to entities (people, orgs, AIs). Many-to-many relationship table for project participants. | 3 |
| project_tasks | Project-specific task breakdown. Links tasks to projects for organized project management. | 8 |
| projects | Project tracking. For repo-backed projects (locked=TRUE, repo_url set), use GitHub for management. For non-repo projects, use notes field here. | 12 |
| prompt_helper_config | Per-message-type gating for turn-context subsystems (entity_resolver, semantic_recall, domain_identifier, turn_reminders). Rows with agent_name IS NULL are defaults; agent-specific rows override them. turn_reminders always fires regardless of config. | 9 |
| publications | - | 8 |
| ralph_sessions | Tracks Ralph-style iterative agent sessions. Each iteration runs with fresh context, state persists in DB. | 15 |
| research_citations | Source citations linking findings to original sources. Write access: Research domain (scout) only. | 13 |
| research_conclusions | Synthesized conclusions aggregating multiple findings. Write access: Research domain (scout) only. | 14 |
| research_findings | Discrete facts, insights, and conclusions from research. Supports copy-on-write versioning. Write access: Research domain (scout) only. | 14 |
| research_projects | Top-level research project containers. Write access: Research domain (scout) only. | 9 |
| research_provenance | W3C PROV-O inspired lineage tracking for research data. Write access: Research domain (scout) only. | 10 |
| research_taggings | Junction table linking tags to research entities. Write access: Research domain (scout) only. | 6 |
| research_tags | Hierarchical, polymorphic tag taxonomy for research entities. Write access: Research domain (scout) only. | 7 |
| research_tasks | Individual research investigation tasks within projects. Write access: Research domain (scout) only. | 14 |
| self_awareness_triggers | Trigger patterns for the self-awareness plugin. Each row defines keyphrases that, when semantically matched in outbound messages, fire an action. Managed by NOVA. | 14 |
| shopping_history | - | 13 |
| shopping_preferences | - | 8 |
| shopping_wishlist | - | 11 |
| skills | Skill definitions. Override precedence: WORKSPACE > DOMAIN > MANAGED > BUNDLED. See get_agent_skills(). | 24 |
| social_interactions | Legacy inbound X/Nostr mention/DM lifecycle. Migration 164 (`cognition/scripts/migrations/164-fold-social-interactions-to-comms-items.sql`) folds this into `comms_items`/`comms_responses` and drops this table — **still live as of the #506 audit (2026-07-20); the migration has not yet been run against production.** Do not remove this row again until the migration is confirmed applied. | 16 |
| tags | - | 5 |
| tasks | Task tracking. NOVA can create, update status, assign. Check before starting work. | 23 |
| tools | Tool usage notes. Override: WORKSPACE > DOMAIN > MANAGED > BUNDLED. See get_agent_tools(). | 13 |
| unsolved_problems | Humanity's unsolved problems for NOVA to work on during idle time. Part of the Motivation System - provides meaningful default work when task queue is empty. | 18 |
| user_insights | Human-contributed insights — observations, realizations, and wisdom shared by users. Primarily for users to save important insights. Managed by any agent on behalf of the contributing user. | 8 |
| vehicles | Vehicle tracking and management. Cars, bikes, boats, planes owned or used. | 13 |
| vocabulary | Custom vocabulary for speech recognition. Add names, terms, jargon as encountered. | 8 |
| work_tags | - | 3 |
| workflow_runs | Tracks individual executions of workflows. Each row is one run from opening bookend to closing bookend. Updated as the orchestrator advances through steps. | 10 |
| workflow_steps | Ordered steps in a workflow with agent assignments and deliverable specifications | 14 |
| workflows | Defines multi-agent workflows with ordered steps and deliverable handoffs | 10 |
| works | - | 14 |

## Quick Reference

- **Full schema:** `~/.openclaw/workspace/nova-mind/database/schema.sql` (synced to GitHub)
- **Query tables:** `psql -d nova_memory -c '\dt'`
- **Describe table:** `psql -d nova_memory -c '\d table_name'`
