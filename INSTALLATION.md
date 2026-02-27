# nova-memory Installation Guide

This document describes the installation process and recent changes to make nova-memory portable and easy to install.

## Prerequisites

Before installing nova-memory, ensure you have the following:

### Required

- **PostgreSQL** (version 12 or higher)
  - Install: `sudo apt install postgresql postgresql-contrib` (Ubuntu/Debian)
  - Install: `brew install postgresql` (macOS)

- **pgschema** - Declarative schema management tool (replaces manual migrations)
  - **Required for schema apply** — installer will fail with a clear error if missing
  - Install via Go:
    ```bash
    go install github.com/pgplex/pgschema@latest
    ```
  - Verify: `pgschema --version` (or `~/go/bin/pgschema --version`)
  - [pgschema on GitHub](https://github.com/pgplex/pgschema)

- **jq** - JSON processor for config parsing and patching
  - Install: `sudo apt install jq`
  - Required for config file parsing and automatic OpenClaw config patching

- **OPENAI_API_KEY** - OpenAI API key for embeddings
  - **Required for semantic recall** - generates embeddings using `text-embedding-3-small`
  - Get your API key from: [https://platform.openai.com/api-keys](https://platform.openai.com/api-keys)
  - The installer will prompt you for this if not set in your environment
  - Alternatively, set it before running the installer:
    ```bash
    export OPENAI_API_KEY='your-key-here'
    ```

### Recommended

- **ANTHROPIC_API_KEY** - Claude API key for memory extraction
  - Used by the memory-extract hook to analyze messages
  - Get your API key from: [https://console.anthropic.com/](https://console.anthropic.com/)

- **pgvector extension** - For semantic search performance
  - Install: `sudo apt install postgresql-16-pgvector` (Ubuntu/Debian)
  - Install: `brew install pgvector` (macOS)

## Quick Install

```bash
cd ~/.openclaw/workspace/nova-memory
./shell-install.sh    # Interactive: prompts for DB details and API keys, then calls agent-install.sh
```

The installer is **idempotent** — safe to run multiple times. Use `./agent-install.sh` directly if the environment is already configured (e.g., CI or agent-driven installs).

## Recent Changes

### 2026-02-27: shell-install.sh Reliability Improvements (#134)

`shell-install.sh` was restructured to improve reliability during the database reachability check:

**What Changed:**
- `lib/pg-env.sh` is now sourced at the **top of the script** (before any config checks), so `load_pg_env()` is available throughout
- Removed redundant manual `jq` parsing of `postgres.json` fields — `load_pg_env()` handles all env loading
- Reachability check now uses plain `psql` (which picks up `PGPASSWORD` from the env exported by `load_pg_env()`)
- Added **empty password warning** for TCP hosts: if `PGHOST` is not a Unix socket path and `PGPASSWORD` is unset, the installer prints a warning pointing to `postgres.json`
- Added **non-interactive detection**: if stdin is not a TTY and the config is incomplete, the script exits with a clear error rather than hanging

**Impact:**
- Password-protected databases now work correctly during install without requiring manual env var export
- Automated/agent installs that call `shell-install.sh` will fail fast instead of hanging on `read`
- No change to the prompts or config file format

### 2026-02-11: Automatic Hook Configuration

The installer now **automatically enables hooks** in the OpenClaw config:

**What Changed:**
- Added `scripts/enable-hooks.sh` - Safe JSON patching using jq
- `install.sh` now calls `enable-hooks.sh` after copying hook files
- Hooks are enabled in `~/.openclaw/openclaw.json` automatically
- Creates backup before modifying config
- Handles both new and existing hooks sections

**Before:**
```bash
./install.sh
openclaw hooks enable memory-extract
openclaw hooks enable semantic-recall
openclaw hooks enable session-init
openclaw hooks enable agent-turn-context
openclaw gateway restart
```

**After:**
```bash
./install.sh  # Automatically enables hooks and prompts to restart gateway
openclaw gateway restart
```

**Benefits:**
- ✅ No manual configuration needed
- ✅ Idempotent (safe to run multiple times)
- ✅ Preserves existing hook configurations
- ✅ Creates backups before modifying config
- ✅ Works with or without existing hooks section

**Implementation:**
The `enable-hooks.sh` script uses jq to safely patch the OpenClaw JSON config:
- Creates hooks section if it doesn't exist
- Enables hooks.enabled and hooks.internal.enabled
- Adds all three nova-memory hooks with enabled: true
- Preserves any existing hooks in the config
- Creates timestamped backup of original config

### 2026-02-10: Multi-User Support and Portability

### 1. Dynamic Database Naming (enables multi-user setups)

**All scripts now use OS username for database naming:**

**Before:**
```bash
DB_NAME="nova_memory"
DB_USER="${PGUSER:-nova}"
```

**After:**
```bash
# Use current OS user for both DB user and name
DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${DB_USER//-/_}_memory"  # Replace hyphens with underscores
```

**Why:** PostgreSQL doesn't allow hyphens in identifiers, so usernames like `nova-staging` become `nova_staging_memory`.

**Examples:**
- User `nova` → database `nova_memory`
- User `nova-staging` → database `nova_staging_memory`
- User `argus` → database `argus_memory`

**Files Updated:**
- `install.sh` - Dynamic DB_NAME generation
- `verify-installation.sh` - Uses dynamic database name
- All scripts in `scripts/` directory (both `.sh` and `.py` files)

**Benefits:**
- Multiple users can run nova-memory on the same PostgreSQL instance
- Each user has isolated memory storage
- No hardcoded username assumptions
- Works in staging/development environments

### 2. Hooks Now Use Relative Paths

All hooks have been updated to reference scripts using relative paths instead of hardcoded `~/.openclaw/workspace/scripts/`:

**Before:**
```typescript
const RECALL_SCRIPT = path.join(os.homedir(), ".openclaw/scripts/proactive-recall.py");
```

**After:**
```typescript
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SCRIPTS_DIR = path.join(__dirname, "..", "..", "scripts");
const RECALL_SCRIPT = path.join(SCRIPTS_DIR, "proactive-recall.py");
```

This allows the repo to be installed anywhere, not just at `~/.openclaw/workspace/`.

**Files Updated:**
- `hooks/memory-extract/handler.ts` - now uses relative path for `process-input.sh`
- `hooks/session-init/handler.ts` - now uses relative path for `generate-session-context.sh`
- `hooks/semantic-recall/handler.ts` - now uses relative path for `proactive-recall.py`

### 3. Comprehensive Installer Script

Created `install.sh` - a fully idempotent installer that:

#### Prerequisites Check
- ✅ Verifies PostgreSQL installed and running
- ✅ Checks for `psql` command
- ⚠️ Warns if `ANTHROPIC_API_KEY` not set
- ✅ Checks for pgvector extension availability

#### Database Setup (Idempotent)
- Creates database named `{username}_memory` (e.g., `nova_memory`, `argus_memory`)
- Automatically replaces hyphens with underscores (e.g., `nova-staging` → `nova_staging_memory`)
- Applies schema declaratively via `pgschema` (plan → hazard-check → apply)
- Reports what was created vs what already existed
- Counts total tables in database

#### Hooks Installation
- **Copies** (not symlinks) hooks to workspace hooks directory
- **Copies** scripts directory to workspace (so hooks can find them via relative paths)
- OpenClaw wasn't following symlinks reliably
- Detects workspace from `OPENCLAW_WORKSPACE` env or default
- Installs: `memory-extract`, `semantic-recall`, `session-init`

#### Scripts Setup
- Makes all `.sh` and `.py` files executable
- Verifies Python dependencies (psycopg2, anthropic, openai)
- Reports missing dependencies with install command

#### Verification
- Tests database connection
- Runs a simple query to verify schema
- Lists installed hooks
- Provides next steps

## What the Installer Does

### Output Example

```
═══════════════════════════════════════════
  nova-memory installer v1.0
═══════════════════════════════════════════

Checking prerequisites...
  ✅ PostgreSQL installed (16.11)
  ✅ psql command available
  ✅ PostgreSQL service running
  ⚠️  ANTHROPIC_API_KEY not set (extraction will fail)
  ✅ pgvector extension available

Database setup...
  ✅ Database 'nova_memory' exists  (or 'argus_memory', 'nova_staging_memory', etc.)
  ✅ Database connection verified
  ✅ Schema applied successfully
      Skipped 315 existing objects
      Total tables in database: 55

Hooks installation...
  ✅ memory-extract installed
  ✅ semantic-recall installed
  ✅ session-init installed

Scripts setup...
  ✅ Made 13 scripts executable
  ✅ Python3 available
  ⚠️  Missing Python dependencies: anthropic openai
      Install: pip3 install anthropic openai

Verification...
  ✅ Database connection OK
  ✅ Test query OK (found 55 tables)
  ✅ Installed hooks:
      • memory-extract
      • semantic-recall
      • session-init

═══════════════════════════════════════════
  Installation complete!
═══════════════════════════════════════════
```

## Environment Variables

The installer and hooks use these environment variables:

### Required for Operation
- `ANTHROPIC_API_KEY` - For memory extraction (Claude API)
- `OPENAI_API_KEY` - For embeddings (semantic search)

### Optional Configuration
- `OPENCLAW_WORKSPACE` - Override default workspace path
- `PGUSER` - PostgreSQL user (default: current OS user)
- `PGHOST` - Database host (default: localhost)
- `PGDATABASE` - Database name (default: `${USER//-/_}_memory`, e.g., `nova_memory`)
- `PGPASSWORD` - Database password (optional); set in `~/.openclaw/postgres.json` for persistence

### Hook-Specific Settings
- `SEMANTIC_RECALL_TOKEN_BUDGET` - Max tokens for recall (default: 1000)
- `SEMANTIC_RECALL_HIGH_CONFIDENCE` - Confidence threshold (default: 0.7)

## Post-Installation

After running `shell-install.sh` or `agent-install.sh`, **the hooks are automatically enabled**. Just restart the gateway:

```bash
openclaw gateway restart
```

Verify hooks are enabled:

```bash
openclaw hooks list
```

Monitor logs:

```bash
tail -f ~/.openclaw/workspace/logs/memory-extract-hook.log
```

If automatic configuration failed (e.g., jq not installed), you can manually enable hooks:

```bash
# Option 1: Use the enable-hooks.sh script
~/.openclaw/workspace/nova-memory/scripts/enable-hooks.sh

# Option 2: Use OpenClaw CLI (legacy method)
openclaw hooks enable memory-extract
openclaw hooks enable semantic-recall
openclaw hooks enable session-init
openclaw hooks enable agent-turn-context
```

## Schema Management

Nova-memory uses **declarative schema management** via [`pgschema`](https://github.com/pgplex/pgschema) (pgplex/pgschema). The installer does not run `psql -f schema.sql` directly; instead, it:

1. **Ensures extensions** — attempts `CREATE EXTENSION IF NOT EXISTS` for each extension defined in `schema/schema.sql`
2. **Runs pre-migrations** — executes all `*.sql` files in `pre-migrations/` (in filename order) for any data transformations that must happen before the schema diff
3. **Plans changes** — runs `pgschema plan` to diff `schema/schema.sql` against the live database, using `--plan-db` pointing at the target DB for accurate extension type resolution (e.g., `vector` from pgvector)
4. **Hazard check** — blocks destructive operations (DROP TABLE, DROP COLUMN) automatically; the plan is rejected if any are found
5. **Applies changes** — calls `pgschema apply` with the approved plan

### Key properties

| Property | Details |
|---|---|
| **No SUPERUSER required** | Installer works with a regular database user (superuser only needed to install extensions, and only if they aren't already installed) |
| **No privilege management** | `pgschema` does not generate `GRANT`/`REVOKE` statements — existing permissions are untouched |
| **No ownership management** | No `ALTER TABLE ... OWNER TO` — avoids permission conflicts in multi-user setups |
| **Idempotent** | Re-running on an up-to-date DB is a no-op (`pgschema plan` reports no changes) |
| **Schema file format** | Generated by `pgschema dump`, not `pg_dump` — pure DDL with no `\connect`, `SET ROLE`, or privilege directives |

### Updating the schema

```bash
# 1. Edit schema/schema.sql to reflect desired state

# 2. Preview the plan (optional)
pgschema plan --host localhost --db nova_memory --user nova \
  --schema public --file schema/schema.sql \
  --plan-db nova_memory

# 3. Apply via the installer
./agent-install.sh
```

### Pre-migrations (for data transformations)

If a schema change requires a data migration to run first (e.g., rename a column and backfill), place a `.sql` file in `pre-migrations/`:

```
pre-migrations/
└── 001_rename_foo_to_bar.sql   # Runs before pgschema plan
```

Files are executed in filename order. After the pre-migration completes, `pgschema plan` will see the updated DB state.

### Ignoring objects

The `.pgschemaignore` file (TOML format) lists objects that `pgschema` should ignore — useful for temporary tables or objects managed outside this repo:

```toml
# .pgschemaignore
[tables]
patterns = ["temp_*"]
```

## Manual Installation (Old Method)

The old `install-hooks.sh` script used symlinks, which caused issues with OpenClaw. 
The new `install.sh` copies hooks instead, which is more reliable.

If you previously used symlinks (old method installed to `~/.openclaw/workspace/hooks/`), remove them first:

```bash
rm -rf ~/.openclaw/workspace/hooks/memory-extract
rm -rf ~/.openclaw/workspace/hooks/semantic-recall
rm -rf ~/.openclaw/workspace/hooks/session-init
rm -rf ~/.openclaw/hooks/memory-extract
rm -rf ~/.openclaw/hooks/semantic-recall
rm -rf ~/.openclaw/hooks/session-init
rm -rf ~/.openclaw/hooks/agent-turn-context
```

Then run the new installer:

```bash
./install.sh
```

## Troubleshooting

### PostgreSQL Not Running
```bash
# Ubuntu/Debian
sudo systemctl start postgresql

# macOS
brew services start postgresql
```

### Missing pgvector Extension
```bash
# Ubuntu/Debian (PostgreSQL 16)
sudo apt install postgresql-16-pgvector

# macOS
brew install pgvector
```

### Python Dependencies
```bash
pip3 install psycopg2-binary anthropic openai
```

### Database Connection Issues

Check PostgreSQL is accepting connections:
```bash
psql -c '\conninfo'
```

### Hook Not Working

Check hook is enabled:
```bash
openclaw hooks list
```

Check logs:
```bash
tail -f ~/.openclaw/workspace/logs/memory-extract-hook.log
tail -f ~/.openclaw/workspace/logs/openclaw-hooks.log
```

## Performance Optimization

### Vector Index for Large Datasets

The schema includes **commented-out IVFFlat indexes** for semantic search performance. These are disabled by default because they break queries on new installations with few embeddings.

#### Why Disabled by Default

IVFFlat indexes divide vectors into clusters (lists). The default configuration uses 100 lists:

```sql
-- Currently commented out in schema/schema.sql
-- CREATE INDEX idx_memory_embeddings_vector ON public.memory_embeddings 
--   USING ivfflat (embedding public.vector_cosine_ops) WITH (lists='100');
```

**Problem:** With < 1000 rows and 100 lists, most lists are empty. This causes ORDER BY queries to return 0-1 results instead of the correct results.

**Solution:** Exact search (no index) is fast enough for small datasets. Only enable the index after you have > 1000 embeddings.

#### When to Enable the Index

After you have accumulated **> 1000 embeddings**, you can add the index for better performance:

```sql
-- Connect to your database
psql -U $(whoami) -d $(whoami | tr '-' '_')_memory

-- Add the index
CREATE INDEX idx_memory_embeddings_vector ON memory_embeddings 
  USING ivfflat (embedding vector_cosine_ops) WITH (lists='100');

-- Optional: Add index for archive table if you use it
CREATE INDEX memory_embeddings_archive_embedding_idx ON memory_embeddings_archive 
  USING ivfflat (embedding vector_cosine_ops) WITH (lists='100');
```

#### Check Your Embedding Count

```sql
-- Check how many embeddings you have
SELECT COUNT(*) FROM memory_embeddings;

-- If > 1000, you can safely add the index
```

#### Performance Impact

- **Without index (< 1000 rows):** Queries are fast enough (< 100ms)
- **With index (> 1000 rows):** Significant speedup for semantic search
- **With index (< 100 rows):** Queries break, return wrong results ❌

## Architecture

### Source Repository
```
nova-memory/
├── install.sh              # Comprehensive installer (legacy; prefer agent-install.sh)
├── agent-install.sh        # Primary installer for AI agents (v2.2)
├── shell-install.sh        # Human-facing installer (prompts for config, then execs agent-install.sh)
├── verify-installation.sh  # Verification script
├── .pgschemaignore         # Objects excluded from pgschema management (TOML format)
├── schema/
│   └── schema.sql          # Declarative schema source of truth (generated by pgschema dump)
├── pre-migrations/         # Data migration scripts run before pgschema plan
│   └── (*.sql files)       # Executed in filename order (e.g., rename a column before schema diff)
├── hooks/                  # OpenClaw hooks (source)
│   ├── memory-extract/     # Extracts memories from messages
│   ├── semantic-recall/    # Recalls relevant context
│   ├── session-init/       # Initializes session context
│   └── agent-turn-context/ # Injects per-turn critical context from DB
└── scripts/                # Shell and Python scripts (source)
    ├── process-input.sh    # Entry point for memory extraction
    ├── extract-memories.sh # Memory extraction logic
    ├── proactive-recall.py # Semantic search
    └── ...                 # Other utility scripts
```

### After Installation (Workspace)
```
~/.openclaw/hooks/
├── memory-extract/         # → Uses scripts/process-input.sh
├── semantic-recall/        # → Uses scripts/proactive-recall.py
├── session-init/           # → Uses scripts/generate-session-context.sh
└── agent-turn-context/     # → Queries agent_turn_context table directly via DB
```

All hooks use **relative paths** to find scripts in `../../scripts/` from their location.

This makes the installation **self-contained** - the workspace has everything it needs without external dependencies.

## Portability

The system is now fully portable:
- No hardcoded paths to `~/.openclaw/workspace/`
- Hooks use relative paths to find scripts
- Installer detects workspace automatically
- Database connection via environment variables

You can clone nova-memory anywhere and install it:

```bash
git clone <repo> /opt/nova-memory
cd /opt/nova-memory
./install.sh
```

## Credits

- Original nova-memory system by Nova
- Installation improvements and relative path refactor: 2026-02-10
