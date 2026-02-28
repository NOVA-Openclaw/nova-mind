# DELEGATION_CONTEXT Auto-Regeneration System

This document describes the auto-regeneration system that keeps `~/.openclaw/workspace/DELEGATION_CONTEXT.md` synchronized with database changes to agents, workflows, and workflow steps.

## Overview

The DELEGATION_CONTEXT file provides agents with real-time awareness of available subagents and active workflows. Two solutions exist:

1. **Short-Term Solution** (Currently Active): PostgreSQL NOTIFY triggers + Python listener
2. **Long-Term Solution** (Issue #10, after PR #9): Bootstrap context system integration

## Architecture Diagram

```
Short-Term Architecture (Current):

┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│ Database Tables │    │ PostgreSQL      │    │ Python Listener  │
│                 │    │ Triggers        │    │                  │
│ • agents        │───►│ • notify_       │───►│ delegation-      │
│ • workflows     │    │   delegation_   │    │ listener.py      │
│ • workflow_steps│    │   change()      │    │                  │
└─────────────────┘    └─────────────────┘    └──────────────────┘
                                                        │
                                                        ▼
                                              ┌──────────────────┐
                                              │ Regenerate       │
                                              │ DELEGATION_      │
                                              │ CONTEXT.md       │
                                              └──────────────────┘

Long-Term Architecture (Issue #10):

┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│ Database Tables │    │ PostgreSQL      │    │ Bootstrap Context│
│                 │    │ Triggers        │    │ System           │
│ • agents        │───►│ • generate_     │───►│ • universal ctx  │
│ • workflows     │    │   delegation_   │    │ • auto-loading   │
│ • workflow_steps│    │   context()     │    │ • audit trail    │
└─────────────────┘    │ • update_       │    └──────────────────┘
                       │   universal_    │
                       │   context()     │
                       └─────────────────┘
```

## Short-Term Solution (Currently Active)

### Components

#### 1. PostgreSQL Notify Function

**Location:** `nova_memory` database  
**Function:** `notify_delegation_change()`

```sql
CREATE OR REPLACE FUNCTION notify_delegation_change()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM pg_notify('delegation_changed', TG_TABLE_NAME);
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION notify_delegation_change IS 
'SHORT-TERM: Triggers DELEGATION_CONTEXT.md regeneration. Remove when PR #9 long-term solution is active.';
```

#### 2. Database Triggers

**Tables with triggers:** `agents`, `workflows`, `workflow_steps`  
**Trigger type:** AFTER INSERT OR UPDATE OR DELETE

```sql
-- Trigger on agents table
CREATE TRIGGER agents_delegation_notify
AFTER INSERT OR UPDATE OR DELETE ON agents
FOR EACH ROW EXECUTE FUNCTION notify_delegation_change();

-- Trigger on workflows table  
CREATE TRIGGER workflows_delegation_notify
AFTER INSERT OR UPDATE OR DELETE ON workflows
FOR EACH ROW EXECUTE FUNCTION notify_delegation_change();

-- Trigger on workflow_steps table
CREATE TRIGGER workflow_steps_delegation_notify
AFTER INSERT OR UPDATE OR DELETE ON workflow_steps
FOR EACH ROW EXECUTE FUNCTION notify_delegation_change();
```

#### 3. Python Listener

**Location:** `~/.openclaw/scripts/delegation-listener.py`  
**Purpose:** Listens for `delegation_changed` notifications and triggers regeneration

**Key Features:**
- Debouncing (2-second wait) for rapid changes
- Error handling and logging
- Timeout protection for regeneration script
- Auto-restart capability via systemd

```python
def main():
    conn = psycopg2.connect(dbname="nova_memory")
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    
    cur = conn.cursor()
    cur.execute("LISTEN delegation_changed;")
    
    # ... polling loop with debouncing logic
```

#### 4. Systemd Service

**Location:** `~/.config/systemd/user/delegation-listener.service`  
**Type:** User service (not system-wide)

```ini
[Unit]
Description=Delegation Context Change Listener (SHORT-TERM)
After=postgresql.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 ~/.openclaw/scripts/delegation-listener.py
Restart=always
RestartSec=5
Environment=PGHOST=localhost

[Install]
WantedBy=default.target
```

#### 5. Regeneration Script

**Location:** `~/.openclaw/scripts/generate-delegation-context.sh`  
**Output:** `~/.openclaw/workspace/DELEGATION_CONTEXT.md`

The listener calls this existing script to perform the actual regeneration.

### Service Management Commands

```bash
# Enable and start the service
systemctl --user enable delegation-listener.service
systemctl --user start delegation-listener.service

# Check status
systemctl --user status delegation-listener.service

# View logs
journalctl --user -u delegation-listener.service -f

# Stop and disable
systemctl --user stop delegation-listener.service
systemctl --user disable delegation-listener.service

# Restart after code changes
systemctl --user restart delegation-listener.service

# Reload systemd configuration
systemctl --user daemon-reload
```

### Testing the System

#### 1. Manual Trigger Test

```bash
# Make a change to trigger regeneration
psql -d nova_memory -c "UPDATE agents SET description = description WHERE id = 1;"

# Check if notification was sent
journalctl --user -u delegation-listener.service -n 10

# Verify DELEGATION_CONTEXT.md was updated
ls -la ~/.openclaw/workspace/DELEGATION_CONTEXT.md
```

#### 2. Direct Notification Test

```bash
# Send notification directly
psql -d nova_memory -c "SELECT pg_notify('delegation_changed', 'test');"

# Should see regeneration in logs
journalctl --user -u delegation-listener.service -n 5
```

#### 3. Service Health Check

```bash
# Verify service is running
systemctl --user is-active delegation-listener.service

# Check database connection
psql -d nova_memory -c "SELECT 1;"

# Test regeneration script directly  
~/.openclaw/scripts/generate-delegation-context.sh
```

#### 4. End-to-End Test

```bash
# Create a test change
psql -d nova_memory -c "
INSERT INTO agents (name, nickname, role, description, model, instance_type, status)
VALUES ('test-agent', 'tester', 'testing', 'Test agent for delegation', 'test-model', 'subagent', 'active');
"

# Wait 3 seconds for debouncing
sleep 3

# Check if DELEGATION_CONTEXT.md contains the new agent
grep -i "test-agent\|tester" ~/.openclaw/workspace/DELEGATION_CONTEXT.md

# Clean up
psql -d nova_memory -c "DELETE FROM agents WHERE nickname = 'tester';"
```

### Troubleshooting

#### Common Issues

1. **Service not starting:**
   - Check PostgreSQL is running: `sudo systemctl status postgresql`
   - Verify database exists: `psql -d nova_memory -c "SELECT 1;"`
   - Check service logs: `journalctl --user -u delegation-listener.service`

2. **No regeneration after changes:**
   - Verify triggers exist: `psql -d nova_memory -c "SELECT tgname FROM pg_trigger WHERE tgfoid = (SELECT oid FROM pg_proc WHERE proname = 'notify_delegation_change');"`
   - Check listener is receiving notifications: `journalctl --user -u delegation-listener.service -f`
   - Test regeneration script manually: `~/.openclaw/scripts/generate-delegation-context.sh`

3. **Script execution failures:**
   - Check script permissions: `ls -la ~/.openclaw/scripts/generate-delegation-context.sh`
   - Test script output: `~/.openclaw/scripts/generate-delegation-context.sh && echo "Success"`

## Long-Term Solution (Issue #10)

### Overview

After PR #9 merges, DELEGATION_CONTEXT will be integrated into the bootstrap context system, eliminating the need for the external listener service.

### Components

#### 1. Bootstrap Context Integration

**Table:** `agent_bootstrap_context`  
**Key:** `DELEGATION_CONTEXT`  
**Management:** Through `update_universal_context()` function

```sql
-- DELEGATION_CONTEXT becomes a database row (via update_universal_context)
SELECT update_universal_context(
    'DELEGATION_CONTEXT',
    '[generated content]',
    'Auto-generated delegation context',
    'system'
);
```

> **Note:** As of #110, context is stored in `agent_bootstrap_context` (unified table), not `bootstrap_context_universal`. Use `update_universal_context()` — the function writes to the correct table.

#### 2. PostgreSQL Generation Function

**Function:** `generate_delegation_context()`  
**Purpose:** Generate markdown content directly in PostgreSQL

```sql
CREATE OR REPLACE FUNCTION generate_delegation_context()
RETURNS TEXT AS $$
DECLARE
    context_content TEXT := '';
    -- ... variables for building markdown
BEGIN
    -- Build markdown content from agents, workflows tables
    -- Similar logic to current generate-delegation-context.sh
    -- but implemented in SQL/PL/pgSQL
    
    RETURN context_content;
END;
$$ LANGUAGE plpgsql;
```

#### 3. Updated Triggers

**New trigger function:**
```sql
CREATE OR REPLACE FUNCTION trigger_delegation_context_update()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM update_universal_context(
        'DELEGATION_CONTEXT',
        generate_delegation_context(),
        'Auto-updated delegation context',
        'trigger-system'
    );
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
```

#### 4. Auto-Loading

OpenClaw agents will automatically load `DELEGATION_CONTEXT.md` from the bootstrap context system during session initialization, no manual regeneration needed.

### Migration Path

When Issue #10 is implemented:

1. **Deploy new system:**
   - Add `generate_delegation_context()` function
   - Update trigger functions to call `update_universal_context()`
   - Migrate current `DELEGATION_CONTEXT.md` to database

2. **Test new system:**
   - Verify auto-generation works
   - Test agent loading of context
   - Validate trigger behavior

3. **Cleanup old system:**
   - Stop and disable `delegation-listener.service`  
   - Remove `delegation-listener.py`
   - Drop old `notify_delegation_change()` function
   - Drop old triggers (see cleanup checklist)

## Cleanup Checklist (For Long-Term Migration)

When transitioning from short-term to long-term solution:

### 1. Stop Short-Term Services

```bash
# Stop and disable systemd service
systemctl --user stop delegation-listener.service
systemctl --user disable delegation-listener.service

# Verify stopped
systemctl --user is-active delegation-listener.service
```

### 2. Remove Short-Term Files

```bash
# Remove Python listener script
rm ~/.openclaw/scripts/delegation-listener.py

# Remove systemd service file
rm ~/.config/systemd/user/delegation-listener.service

# Reload systemd
systemctl --user daemon-reload
```

### 3. Remove Short-Term Database Objects

```sql
-- Drop old triggers
DROP TRIGGER IF EXISTS agents_delegation_notify ON agents;
DROP TRIGGER IF EXISTS workflows_delegation_notify ON workflows;
DROP TRIGGER IF EXISTS workflow_steps_delegation_notify ON workflow_steps;

-- Drop old function
DROP FUNCTION IF EXISTS notify_delegation_change();

-- Verify cleanup
SELECT tgname FROM pg_trigger WHERE tgfoid = (SELECT oid FROM pg_proc WHERE proname = 'notify_delegation_change');
-- Should return 0 rows
```

### 4. Migrate Data

```sql
-- Copy current DELEGATION_CONTEXT.md to database via update_universal_context()
SELECT update_universal_context(
    'DELEGATION_CONTEXT',
    '[content from ~/.openclaw/workspace/DELEGATION_CONTEXT.md]',
    'Migrated from file-based system',
    'migration'
);
-- Stored in agent_bootstrap_context table (context_type = 'UNIVERSAL')
```

### 5. Verify New System

```bash
# Test that agents load DELEGATION_CONTEXT automatically
# (This depends on OpenClaw bootstrap context integration)

# Verify triggers update database context
psql -d nova_memory -c "UPDATE agents SET description = description WHERE id = 1;"
psql -d nova_memory -c "SELECT updated_at FROM agent_bootstrap_context WHERE file_key = 'DELEGATION_CONTEXT';"
```

### 6. Update Documentation

- Update existing `delegation-context.md` to reference new system
- Remove references to manual regeneration script
- Update agent guidance to expect auto-loaded context

## Security Considerations

### Short-Term Solution

- Python listener runs as user service (not system-wide)
- Database access limited to `nova_memory` database
- Script execution timeout prevents hanging processes
- Service auto-restart prevents permanent failures

### Long-Term Solution

- All operations contained within database
- Bootstrap context audit trail tracks all changes
- Function-based updates provide transaction safety
- Size limits prevent excessive content

## Performance Impact

### Short-Term Solution

- **Trigger overhead:** Minimal - simple NOTIFY call
- **Debouncing:** Reduces unnecessary regenerations during bulk changes
- **Script execution:** ~1-3 seconds for typical delegation contexts
- **File I/O:** Single file write to `~/.openclaw/workspace/DELEGATION_CONTEXT.md`

### Long-Term Solution

- **Database overhead:** Slightly higher due to content generation in PostgreSQL
- **Memory usage:** Content stored in database memory during generation
- **Network impact:** Eliminated (no external processes)
- **Consistency:** Better transaction-level consistency

## Monitoring

### Health Checks

```bash
# Short-term system health
systemctl --user is-active delegation-listener.service
stat ~/.openclaw/workspace/DELEGATION_CONTEXT.md
journalctl --user -u delegation-listener.service --since "1 hour ago" | grep -c "Regeneration complete"

# Long-term system health
psql -d nova_memory -c "SELECT file_key, updated_at FROM agent_bootstrap_context WHERE file_key = 'DELEGATION_CONTEXT';"
```

### Performance Monitoring

```bash
# Monitor regeneration frequency
journalctl --user -u delegation-listener.service --since "24 hours ago" | grep "Regeneration complete" | wc -l
```

## Related Documentation

- [Delegation Context Generation](delegation-context.md) - Current manual system
- [Issue #10: Bootstrap Context Integration](https://github.com/NOVA-Openclaw/nova-cognition/issues/10)
- [PR #9: Bootstrap Context System](https://github.com/NOVA-Openclaw/nova-cognition/pull/9)
- [Bootstrap Context Management](../focus/bootstrap-context/README.md)

## Support

For issues with the delegation context auto-regeneration system:

1. **Check service status:** `systemctl --user status delegation-listener.service`
2. **Review logs:** `journalctl --user -u delegation-listener.service`  
3. **Test database triggers:** See testing section above
4. **Verify file generation:** Run `~/.openclaw/scripts/generate-delegation-context.sh` manually

For long-term solution planning, reference Issue #10 in nova-cognition repository.