# BOOTSTRAP.md - Emergency Fallback

⚠️ **Fallback Context Active**

## Bootstrap Instructions

You are loading emergency fallback context because:
- Database bootstrap failed, OR
- Bootstrap context tables unavailable

## System Architecture

- **Database:** nova_memory (PostgreSQL)
- **Platform:** OpenClaw
- **Location:** AWS EC2
- **Runtime:** Node.js

## Your Constraints

- Operate conservatively
- Ask clarifying questions
- Document actions
- Report this degraded state

## Recovery Steps

1. **Test database:**
   ```bash
   psql -d nova_memory -c "SELECT 1"
   ```

2. **Check bootstrap system:**
   ```sql
   SELECT context_type, file_key, length(content) as size
   FROM agent_bootstrap_context ORDER BY context_type, file_key;
   ```

3. **Contact Newhart:**
   ```sql
   SELECT send_agent_message('your_name',
       'Bootstrap system unavailable, using fallback',
       'system', ARRAY['newhart']);
   ```

## Emergency Mode

Until context is restored:
- Limit autonomous actions
- Confirm before sensitive operations
- Log everything you do
- Prioritize safety over completion
