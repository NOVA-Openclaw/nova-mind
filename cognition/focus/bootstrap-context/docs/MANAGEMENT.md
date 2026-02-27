# Bootstrap Context Management Guide

How to manage agent context in the database-backed system.

## Quick Reference

```sql
-- Universal context (all agents)
SELECT update_universal_context('FILE_KEY', 'content...', 'description', 'your_name');

-- Agent-specific context
SELECT update_agent_context('agent_name', 'FILE_KEY', 'content...', 'description', 'your_name');

-- List everything
SELECT * FROM list_all_context();

-- Get agent's context
SELECT * FROM get_agent_bootstrap('agent_name');
```

## Universal Context Files

These apply to all agents:

### Standard Files

- **AGENTS** - Agent roster and capabilities
- **SOUL** - System identity and values
- **TOOLS** - Tool usage notes (user-specific)
- **IDENTITY** - System identity metadata
- **USER** - User information and preferences
- **HEARTBEAT** - Heartbeat check protocol
- **BOOTSTRAP** - Bootstrap instructions

### Example: Update AGENTS.md

```sql
SELECT update_universal_context('AGENTS', $content$
# AGENTS.md - NOVA Agent Roster

## Active Agents

- **NOVA** - Primary coordination agent
- **Newhart** - Non-Human Resources (agent architecture)
- **Coder** - Software development and code review
- **Scout** - Research and information gathering
- **Druid** - Policy and standards enforcement

[... rest of content ...]
$content$, 'Agent roster', 'newhart');
```

## Agent-Specific Context

Each agent can have custom context files.

### Common Agent Files

- **SEED_CONTEXT** - Domain knowledge and expertise
- **PROCEDURES** - Standard operating procedures
- **GUIDELINES** - Agent-specific guidelines
- **KNOWLEDGE_BASE** - Accumulated domain knowledge

### Example: Update Coder's Seed Context

```sql
SELECT update_agent_context('coder', 'SEED_CONTEXT', $content$
# Coder Seed Context

## Domain: Software Development

You are Coder, the software development agent.

### Expertise
- TypeScript/JavaScript
- PostgreSQL
- OpenClaw architecture
- Test-driven development

### Workflow
1. Understand requirements
2. Design solution
3. Implement with tests
4. Document changes
5. Request code review

[... rest of content ...]
$content$, 'Coder domain knowledge', 'newhart');
```

## Content Length Limits

- Default: **20,000 characters** per file
- Configured in `bootstrap_context_config.max_file_size`
- Matches OpenClaw's `agents.defaults.bootstrapMaxChars`

Check current limit:
```sql
SELECT value FROM bootstrap_context_config WHERE key = 'max_file_size';
```

## Viewing Context

### List All Context

```sql
SELECT * FROM list_all_context()
ORDER BY type, agent_name, file_key;
```

Shows:
- type (universal/agent)
- agent_name (NULL for universal)
- file_key
- content_length
- updated_at
- updated_by

### Get Agent Bootstrap

```sql
SELECT filename, source, length(content) as size
FROM get_agent_bootstrap('coder');
```

Returns what the agent will actually see:
- Universal files + agent-specific files
- Respects enabled/disabled config

## Deleting Context

### Delete Universal File

```sql
SELECT delete_universal_context('FILE_KEY');
```

### Delete Agent File

```sql
SELECT delete_agent_context('agent_name', 'FILE_KEY');
```

## Configuration

### View Config

```sql
SELECT * FROM get_bootstrap_config();
```

### Disable System

```sql
UPDATE bootstrap_context_config 
SET value = 'false'::jsonb 
WHERE key = 'enabled';
```

When disabled, OpenClaw falls back to filesystem files.

### Enable Fallback

```sql
UPDATE bootstrap_context_config 
SET value = 'true'::jsonb 
WHERE key = 'fallback_enabled';
```

## Migrating Existing Files

The `copy_file_to_bootstrap()` function imports filesystem files:

```sql
-- Read file content first
\set content `cat /path/to/AGENTS.md`

-- Import to universal context
SELECT copy_file_to_bootstrap('/path/to/AGENTS.md', :'content', NULL, 'migration');

-- Import to agent context
SELECT copy_file_to_bootstrap('/path/to/SEED_CONTEXT.md', :'content', 'coder', 'migration');
```

Or use the migration script:
```bash
psql -d nova_memory -f sql/migrate-initial-context.sql
```

## Audit Trail

All changes are logged in `bootstrap_context_audit`:

```sql
SELECT 
    table_name,
    operation,
    changed_by,
    changed_at,
    length(new_content) as new_size
FROM bootstrap_context_audit
ORDER BY changed_at DESC
LIMIT 20;
```

## Best Practices

### 1. Always Specify updated_by

```sql
-- Good
SELECT update_universal_context('AGENTS', 'content...', 'description', 'newhart');

-- Bad (uses 'system' default)
SELECT update_universal_context('AGENTS', 'content...');
```

### 2. Use Descriptive Descriptions

```sql
-- Good
SELECT update_agent_context('coder', 'SEED_CONTEXT', 
    'content...', 
    'Added TypeScript 5.0 features and best practices', 
    'newhart');

-- Bad
SELECT update_agent_context('coder', 'SEED_CONTEXT', 'content...', NULL, 'newhart');
```

### 3. Test Changes

Before updating production context, test with a dummy agent:

```sql
SELECT update_agent_context('test_agent', 'SEED_CONTEXT', 'test content', 'Testing', 'newhart');
SELECT * FROM get_agent_bootstrap('test_agent');
```

### 4. Keep Backups

The audit log preserves old content, but explicitly backup critical files:

```bash
psql -d nova_memory -c "SELECT content FROM bootstrap_context_universal WHERE file_key='AGENTS'" > AGENTS_backup.md
```

## Troubleshooting

### Context Not Loading

1. Check if system is enabled:
   ```sql
   SELECT value FROM bootstrap_context_config WHERE key = 'enabled';
   ```

2. Verify hook is installed:
   ```bash
   ls -la ~/.openclaw/hooks/db-bootstrap-context/
   ```

3. Check gateway logs:
   ```bash
   tail -f ~/.openclaw/gateway.log | grep bootstrap
   ```

### Database Connection Failed

**As of issue #43**, the hook manages its own PostgreSQL connection using peer authentication.

Common connection issues:

**ECONNREFUSED** - PostgreSQL not running:
```bash
sudo systemctl start postgresql
sudo systemctl status postgresql
```

**Function not found (42883)** - Schema not installed:
```bash
cd ~/workspace/nova-mind/cognition/focus/bootstrap-context
./install.sh
```

**Permission denied** - User doesn't exist in database:
```bash
sudo -u postgres createuser $(whoami)
# Or ensure 'nova' user exists
```

**Connection details:**
- Host: localhost
- Database: nova_memory  
- User: $USER → os.userInfo().username → 'nova' (fallback chain)
- Auth: PostgreSQL peer authentication (no password)
- Pool: max 5 connections, 5s timeout, 30s idle timeout

If database connection fails, the hook automatically falls back to static files in `~/.openclaw/bootstrap-fallback/`

Check fallback files exist:
```bash
ls -la ~/.openclaw/bootstrap-fallback/
```

### Content Too Large

If context exceeds max_file_size:

1. Split into multiple files
2. Or increase the limit:
   ```sql
   UPDATE bootstrap_context_config 
   SET value = '30000'::jsonb 
   WHERE key = 'max_file_size';
   ```

## Owner

**Newhart (NHR Agent)** - Non-Human Resources

For questions or issues, contact Newhart via `agent_chat`.
