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
cd ~/clawd/nova-cognition/bootstrap-context
psql -d nova_memory -f schema/bootstrap-context.sql
psql -d nova_memory -f sql/management-functions.sql
```

**Creates:**
- 4 tables: `bootstrap_context_universal`, `bootstrap_context_agents`, `bootstrap_context_config`, `bootstrap_context_audit`
- 8 functions: `update_universal_context`, `update_agent_context`, `get_agent_bootstrap`, etc.

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
# Check database tables
psql -d nova_memory -c "\dt bootstrap_context*"

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

-- Import to database
SELECT copy_file_to_bootstrap('/path/to/AGENTS.md', :'content', NULL, 'migration');
```

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
cd ~/clawd/nova-cognition/bootstrap-context
./install.sh
```

This runs all steps automatically with verification.

## Verification

### Test Database Functions

```sql
-- Check configuration
SELECT * FROM get_bootstrap_config();

-- List all context
SELECT * FROM list_all_context();

-- Test agent bootstrap (empty initially)
SELECT * FROM get_agent_bootstrap('test');
```

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
-- Audit trail
SELECT * FROM bootstrap_context_audit 
ORDER BY changed_at DESC LIMIT 10;

-- Content stats
SELECT 
    type,
    COUNT(*) as file_count,
    SUM(content_length) as total_chars
FROM list_all_context()
GROUP BY type;
```

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
1. System enabled: `SELECT value FROM bootstrap_context_config WHERE key = 'enabled'`
2. Content added: `SELECT * FROM list_all_context()`
3. Fallback files exist: `ls ~/.openclaw/bootstrap-fallback/`

### Content Too Large

**Symptom:** Error about file size

**Solution:**
```sql
-- Increase limit (default 20000)
UPDATE bootstrap_context_config 
SET value = '30000'::jsonb 
WHERE key = 'max_file_size';
```

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

- **Database:** `nova_memory` (tables: `bootstrap_context_*`)
- **Hook:** `~/.openclaw/hooks/db-bootstrap-context/`
- **Fallback:** `~/.openclaw/bootstrap-fallback/`
- **Logs:** `~/.openclaw/gateway.log`
- **Source:** `~/clawd/nova-cognition/bootstrap-context/`

## Documentation

- [Main README](./README.md) - Overview and architecture
- [Management Guide](./docs/MANAGEMENT.md) - Daily usage and SQL reference
- [Hook Reference](./hook/HOOK.md) - Hook implementation details

## Owner

**Newhart (NHR Agent)** - Non-Human Resources

This is Newhart's domain. Questions about agent architecture and bootstrap context go to Newhart.
