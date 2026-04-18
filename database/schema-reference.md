# Database Schema Reference

*Auto-generated: 2026-04-17T20:00:56.440282*

## Tables

| Table | Description | Columns |
|-------|-------------|---------|
| agent_actions | Agent action definitions. READ-ONLY except Newhart. | 8 |
| agent_aliases | Agent aliases for flexible mention matching. Supports case-insensitive routing. | 4 |
| agent_bootstrap_context | Bootstrap context entries. READ-ONLY except Newhart (Agent Design/Management domain). | 9 |
| agent_chat | Agent messaging. INSERT allowed for all, UPDATE/DELETE only Newhart. | 6 |
| agent_chat_processed | Message processing state. Agents can track, Newhart manages. | 7 |
| agent_domains | Agent domain assignments. READ-ONLY except Newhart. | 8 |
| agent_jobs | Agent job definitions. READ-ONLY except Newhart. | 18 |
| agent_modifications | Agent modification history. READ-ONLY except Newhart. | 7 |
| agent_spawns | Tracks all agent spawns from the general-purpose spawner daemon | 14 |
| agent_system_config | Agent system configuration. READ-ONLY except Newhart. | 6 |
| agent_turn_context | - | 8 |
| agents | Agent registry | 32 |
| ai_models | Available AI models. NOVA maintains this; Newhart reads for agent assignments. Credentials and endpoints stored in 1Password (see credential_ref column). | 16 |
| artwork | Archive of NOVAs Instagram artwork. Reference for future compilation. | 19 |
| asset_classes | Asset class definitions for financial portfolio management. Defines tradeable asset types with pricing sources and trading characteristics. | 6 |
| bootstrap_context_config | Configuration for bootstrap system behavior | 4 |
| certificates | Client certificates issued by NOVA CA. Security-sensitive. Verify before modifications. | 12 |
| channel_activity | Tracks last message per channel for idle detection. Read/write: NOVA, Newhart. | 3 |
| conversations | Conversation session tracking. Logs chat sessions with metadata for analysis and continuity. | 6 |
| entities | People, AIs, organizations. NOVA has full access. Use entity_facts for attributes. | 20 |
| entity_fact_conflicts | Conflicts between entity facts requiring resolution. Part of the truth reconciliation system. | 13 |
| entity_facts | Key-value facts about entities. Check current_timezone for I)ruid before time-based actions. | 19 |
| entity_facts_archive | Archived entity facts from decay/cleanup processes. Historical record of previously stored knowledge. | 22 |
| entity_relationships | Relationships between entities (family, work, friendship, etc). | 8 |
| event_entities | Links events to entities (people, orgs, AIs). Many-to-many relationship table. | 3 |
| event_places | Links events to places/locations. Many-to-many relationship table. | 2 |
| event_projects | Links events to projects. Many-to-many relationship table for project milestones and activities. | 2 |
| events | Historical events, milestones, activities. Log significant occurrences. | 9 |
| events_archive | Archived historical events. Long-term storage for events moved out of active events table. | 11 |
| extraction_metrics | Performance metrics for data extraction processes. Tracks accuracy and efficiency of knowledge extraction. | 6 |
| fact_change_log | Audit trail for entity fact modifications. Tracks who changed what and when for accountability. | 7 |
| gambling_entries | Individual gambling session records. Tracks bets, outcomes, and session details for analysis. | 10 |
| gambling_logs | High-level gambling session summaries. Groups multiple gambling_entries by session. | 8 |
| git_issue_queue | Issue queue for git-based workflows. NOTIFY triggers dispatch work automatically. | 16 |
| job_messages | Message log per job for conversation threading | 5 |
| lessons | Lessons and insights learned. Update when learning something worth remembering. | 11 |
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
| motivation_d100 | D100 random task table for NOVA motivation system - roll when bored! | 16 |
| music_analysis | Deep musical analysis (harmonic, rhythmic, lyrical, spectral). Managed by Erato. | 11 |
| music_library | Music-specific metadata extending media_consumed. Managed by Erato. | 37 |
| place_properties | Properties and attributes of places. Key-value storage for place characteristics. | 5 |
| places | Locations (houses, venues, cities). Reference I)ruid houses in USER.md. | 15 |
| pm_domain_portfolio_snapshots | - | 6 |
| portfolio_history | - | 6 |
| portfolio_metrics | - | 10 |
| portfolio_positions | Individual stock/investment positions tracking purchases, sales, and P&L. Core table for portfolio management. | 9 |
| portfolio_snapshots | Historical snapshots of portfolio values and performance metrics over time. | 8 |
| portfolio_updates | - | 3 |
| positions | Legacy or alternative positions tracking table. May be deprecated in favor of portfolio_positions. | 20 |
| preferences | User preferences by entity_id. Check before making assumptions. | 6 |
| price_cache_v2 | Cached price data for assets to reduce API calls. Version 2 of price caching system. | 12 |
| project_entities | Links projects to entities (people, orgs, AIs). Many-to-many relationship table for project participants. | 3 |
| project_tasks | Project-specific task breakdown. Links tasks to projects for organized project management. | 8 |
| projects | Project tracking. For repo-backed projects (locked=TRUE, repo_url set), use GitHub for management. For non-repo projects, use notes field here. | 12 |
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
| shopping_history | - | 13 |
| shopping_preferences | - | 8 |
| shopping_wishlist | - | 11 |
| skills | Skill definitions. Override precedence: WORKSPACE > DOMAIN > MANAGED > BUNDLED. See get_agent_skills(). | 24 |
| tags | - | 5 |
| tasks | Task tracking. NOVA can create, update status, assign. Check before starting work. | 23 |
| ticker_portfolio | - | 1 |
| tools | Tool usage notes. Override: WORKSPACE > DOMAIN > MANAGED > BUNDLED. See get_agent_tools(). | 13 |
| unsolved_problems | Humanity's unsolved problems for NOVA to work on during idle time. Part of the Motivation System - provides meaningful default work when task queue is empty. | 18 |
| vehicles | Vehicle tracking and management. Cars, bikes, boats, planes owned or used. | 13 |
| vocabulary | Custom vocabulary for speech recognition. Add names, terms, jargon as encountered. | 8 |
| work_tags | - | 3 |
| workflow_steps | Ordered steps in a workflow with agent assignments and deliverable specifications | 14 |
| workflows | Defines multi-agent workflows with ordered steps and deliverable handoffs | 10 |
| works | - | 14 |

## Quick Reference

- **Full schema:** `~/.openclaw/workspace/nova-mind/database/schema.sql` (synced to GitHub)
- **Query tables:** `psql -d nova_memory -c '\dt'`
- **Describe table:** `psql -d nova_memory -c '\d table_name'`
