# Changelog

## Unreleased

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
