# Bootstrap Context Installation Summary

Quick reference for installing and verifying the database bootstrap context system.

## Prerequisites

- PostgreSQL database `nova_memory` accessible on localhost
- Current OS user has access to nova_memory database (peer auth)
- OpenClaw installed
- `psql` command available
- Write access to `~/.openclaw/`

**Note:** The hook creates its own database connection using PostgreSQL peer authentication. No password is required, but the OS user must exist in PostgreSQL or 'nova' user must be accessible.

## Installation Steps

### 1. Install Database Components

```bash
cd ~/workspace/nova-mind/cognition/focus/bootstrap-context
psql -d nova_memory -f sql/management-functions.sql
```

**Creates:**
- Functions: `update_universal_context`, `update_agent_context`, `get_agent_bootstrap`, etc.

> **Note:** Database tables (`agent_bootstrap_context`) are managed by pgschema via `database/schema.sql`. The old `bootstrap_context.sql` schema file is intentionally empty — tables are no longer created by this installer. See [#110](https://github.com/nova-openclaw/nova-mind/issues/110).

### 2. Install OpenClaw Hook

```bash
mkdir -p ~/.openclaw/hooks/db-bootstrap-context
cp hook/handler.ts ~/.openclaw/hooks/db-bootstrap-context/
cp hook/HOOK.md ~/.openclaw/hooks/db-bootstrap-context/
```

**Hook location:** `~/.openclaw/hooks/db-bootstrap-context/`
**Hook name:** `db-bootstrap-context`
**Event:** `agent:bootstrap`

### 3. Install Fallback Files

```bash
mkdir -p ~/.openclaw/bootstrap-fallback
cp fallback/*.md ~/.openclaw/bootstrap-fallback/
```

**Fallback directory:** `~/.openclaw/bootstrap-fallback/`
**Purpose:** Used when database unavailable

### 4. Verify Installation

```bash
# Check database table (managed by pgschema)
psql -d nova_memory -c "\dt agent_bootstrap_context"

# Check functions
psql -d nova_memory -c "\df *bootstrap*"

# Check hook files
ls -la ~/.openclaw/hooks/db-bootstrap-context/

# Check fallback files
ls -la ~/.openclaw/bootstrap-fallback/
```

### 5. Migrate Existing Context (Optional)

If you have existing .md files to import:

```bash
psql -d nova_memory -f sql/migrate-initial-context.sql
```

Or manually:

```sql
-- Read file content
\set content `cat /path/to/AGENTS.md`

-- Import to universal context
SELECT update_universal_context('AGENTS', :'content', 'Migrated from AGENTS.md', 'migration');

-- Import to agent context
SELECT update_agent_context('coder', 'SEED_CONTEXT', :'content', 'Migrated from SEED_CONTEXT.md', 'migration');
```

> **Note:** `copy_file_to_bootstrap()` was removed in #110. Use `update_universal_context()` or `update_agent_context()` directly.

### 6. Restart Gateway

For the hook to take effect:

```bash
openclaw gateway restart
```

Or via systemctl:

```bash
systemctl --user restart openclaw-gateway
```

## Quick Install Script

Or use the automated installer:

```bash
cd ~/workspace/nova-mind/cognition/focus/bootstrap-context
./install.sh
```

This runs all steps automatically with verification.

## Verification

### Test Database Functions

```sql
-- List all context
SELECT context_type, domain_name, file_key, length(content) as size, updated_at
FROM agent_bootstrap_context
ORDER BY context_type, file_key;

-- Test agent bootstrap (empty initially)
SELECT * FROM get_agent_bootstrap('test');
```

> **Note:** `get_bootstrap_config()` and `list_all_context()` were removed in #110. Query `agent_bootstrap_context` directly for listing, and check `openclaw.json` for configuration.

### Test Hook Loading

Check gateway logs during agent spawn:

```bash
tail -f ~/.openclaw/gateway.log | grep bootstrap
```

You should see:
```
[bootstrap-context] Loading context for agent: <agent_name>
[bootstrap-context] Loaded N context files for <agent_name>
```

### Test Fallback System

1. Stop PostgreSQL temporarily
2. Spawn an agent
3. Check logs - should show fallback activation:
   ```
   [bootstrap-context] No database context, trying fallback files...
   ```

## Post-Installation

### Add Universal Context

```sql
-- AGENTS.md
SELECT update_universal_context('AGENTS', $content$
# AGENTS.md
...
$content$, 'Agent roster', 'your_name');

-- SOUL.md
SELECT update_universal_context('SOUL', $content$
# SOUL.md
...
$content$, 'System identity', 'your_name');
```

### Add Agent-Specific Context

```sql
-- Coder's seed context
SELECT update_agent_context('coder', 'SEED_CONTEXT', $content$
# Coder Seed Context
...
$content$, 'Coder domain knowledge', 'your_name');
```

### Monitor Usage

```sql
-- Content stats
SELECT 
    context_type,
    COUNT(*) as file_count,
    SUM(length(content)) as total_chars
FROM agent_bootstrap_context
GROUP BY context_type;
```

> **Note:** `bootstrap_context_audit` table was removed in #110 (deprecated). Audit history is no longer stored in a separate table.

## Troubleshooting

### Hook Not Loading

**Symptom:** Agents still using filesystem files

**Check:**
1. Hook installed: `ls ~/.openclaw/hooks/db-bootstrap-context/handler.ts`
2. Gateway restarted after hook installation
3. Logs show hook loaded: `grep "Registered hook" ~/.openclaw/gateway.log`

### Database Connection Failed

**Symptom:** Fallback files loading instead of database

**Check:**
1. PostgreSQL running: `systemctl status postgresql`
2. Database accessible: `psql -d nova_memory -c "SELECT 1"`
3. Tables exist: `psql -d nova_memory -c "\dt bootstrap_context*"`

### Empty Context Loading

**Symptom:** Agent has no context

**Check:**
1. Content added: `SELECT COUNT(*) FROM agent_bootstrap_context`
2. Fallback files exist: `ls ~/.openclaw/bootstrap-fallback/`

### Content Too Large

**Symptom:** Error about file size

**Solution:** Check `agents.defaults.bootstrapMaxChars` in `~/.openclaw/openclaw.json` and increase the value if needed.

## Architecture Summary

```
┌─────────────────────────────────────────────┐
│  Agent Spawn Request                        │
└──────────────────┬──────────────────────────┘
                   ↓
         agent:bootstrap event fires
                   ↓
┌─────────────────────────────────────────────┐
│  Hook: db-bootstrap-context                 │
│  Location: ~/.openclaw/hooks/               │
└──────────────────┬──────────────────────────┘
                   ↓
         Query: get_agent_bootstrap(name)
                   ↓
    ┌──────────────┴──────────────┐
    ↓                              ↓
Database Available           Database Failed
    ↓                              ↓
Return DB Context           Load Fallback Files
    │                              │
    └──────────┬───────────────────┘
               ↓
    Inject into event.context.bootstrapFiles
               ↓
       Agent Starts with Context
```

## File Locations

- **Database:** `nova_memory` (table: `agent_bootstrap_context`, managed by pgschema)
- **Hook:** `~/.openclaw/hooks/db-bootstrap-context/`
- **Fallback:** `~/.openclaw/bootstrap-fallback/`
- **Logs:** `~/.openclaw/gateway.log`
- **Source:** `~/workspace/nova-mind/cognition/focus/bootstrap-context/`

## Documentation

- [Main README](./README.md) - Overview and architecture
- [Management Guide](./docs/MANAGEMENT.md) - Daily usage and SQL reference
- [Hook Reference](./hook/HOOK.md) - Hook implementation details

## Owner

**Newhart (NHR Agent)** - Non-Human Resources

This is Newhart's domain. Questions about agent architecture and bootstrap context go to Newhart.
