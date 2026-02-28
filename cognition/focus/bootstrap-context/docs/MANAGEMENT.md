# Bootstrap Context Management Guide

How to manage agent context in the database-backed system.

## Quick Reference

```sql
-- Universal context (all agents)
SELECT update_universal_context('FILE_KEY', 'content...', 'description', 'your_name');

-- Agent-specific context
SELECT update_agent_context('agent_name', 'FILE_KEY', 'content...', 'description', 'your_name');

-- List everything
SELECT context_type, domain_name, file_key, length(content) as size, updated_at
FROM agent_bootstrap_context
ORDER BY context_type, file_key;

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
- Configured via `agents.defaults.bootstrapMaxChars` in `~/.openclaw/openclaw.json`

> **Note:** `bootstrap_context_config` table was removed in #110. Configuration is no longer stored in the database — check `openclaw.json` directly.

## Viewing Context

### List All Context

```sql
SELECT context_type, domain_name, file_key, length(content) as content_length, updated_at, updated_by
FROM agent_bootstrap_context
ORDER BY context_type, domain_name, file_key;
```

Shows:
- context_type (UNIVERSAL/GLOBAL/DOMAIN/AGENT)
- domain_name (NULL for non-DOMAIN types)
- file_key
- content_length
- updated_at
- updated_by

> **Note:** `list_all_context()` was removed in #110. Query `agent_bootstrap_context` directly.

### Get Agent Bootstrap

```sql
SELECT filename, source, length(content) as size
FROM get_agent_bootstrap('coder');
```

Returns what the agent will actually see:
- Universal files + agent-specific files
- Respects enabled/disabled config

## Deleting Context

```sql
-- Delete a specific context entry
DELETE FROM agent_bootstrap_context
WHERE context_type = 'UNIVERSAL' AND file_key = 'FILE_KEY';

-- Delete agent-specific context
DELETE FROM agent_bootstrap_context
WHERE context_type = 'AGENT' AND domain_name = 'agent_name' AND file_key = 'FILE_KEY';
```

> **Note:** `delete_universal_context()` and `delete_agent_context()` were removed in #110. Use direct DELETE statements instead. The `agent_bootstrap_context` table has a write-protection trigger — only Newhart (Agent Design/Management domain) can modify it directly.

## Configuration

Bootstrap system configuration is no longer stored in the database. The system is always active when the hook is installed.

> **Note:** `get_bootstrap_config()`, `bootstrap_context_config` table, and the enable/disable toggle were removed in #110. To disable the bootstrap hook, remove the hook directory from `~/.openclaw/hooks/db-bootstrap-context/`.

## Migrating Existing Files

```sql
-- Read file content first
\set content `cat /path/to/AGENTS.md`

-- Import to universal context
SELECT update_universal_context('AGENTS', :'content', 'Migrated from AGENTS.md', 'migration');

-- Import to agent context
SELECT update_agent_context('coder', 'SEED_CONTEXT', :'content', 'Migrated from SEED_CONTEXT.md', 'migration');
```

Or use the migration script:
```bash
psql -d nova_memory -f sql/migrate-initial-context.sql
```

> **Note:** `copy_file_to_bootstrap()` was removed in #110. Use `update_universal_context()` or `update_agent_context()` directly.

## Audit Trail

> **Note:** `bootstrap_context_audit` table was removed in #110. Audit history is no longer stored in a separate table. Use PostgreSQL's WAL or your own logging if an audit trail is needed.

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

Explicitly backup critical context:

```bash
psql -d nova_memory -c "SELECT content FROM agent_bootstrap_context WHERE context_type='UNIVERSAL' AND file_key='AGENTS'" > AGENTS_backup.md
```

## Troubleshooting

### Context Not Loading

1. Verify hook is installed:
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

**Function not found (42883)** - Management functions not installed:
```bash
cd ~/workspace/nova-mind/cognition/focus/bootstrap-context
psql -d nova_memory -f sql/management-functions.sql
```

**Table not found** - Schema not applied (pgschema manages this):
```bash
cd ~/workspace/nova-mind
./agent-install.sh
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

If context exceeds the bootstrap character limit:

1. Split into multiple files
2. Or increase `agents.defaults.bootstrapMaxChars` in `~/.openclaw/openclaw.json`

## Owner

**Newhart (NHR Agent)** - Non-Human Resources

For questions or issues, contact Newhart via `agent_chat`.
