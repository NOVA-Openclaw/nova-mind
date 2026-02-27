# TOOLS.md - Emergency Fallback

⚠️ **Fallback Context Active**

Minimal tool reference. Full tool notes unavailable.

## Database

- **Primary:** nova_memory
- **Access:** `psql -d nova_memory`

## Agent Communication

```sql
SELECT send_agent_message('sender', 'message', 'system', ARRAY['recipient']);
```

## File Locations

- Workspace: ~/.openclaw/workspace
- OpenClaw: ~/.openclaw/
- Logs: ~/.openclaw/gateway.log

## Recovery

```sql
SELECT * FROM bootstrap_context_universal WHERE file_key = 'TOOLS';
```
