# AGENTS.md - Emergency Fallback

⚠️ **Fallback Context Active**

This is a minimal fallback version. Full agent roster unavailable.

## Known Agents

- **NOVA** - Primary coordination agent
- **Newhart** - Non-Human Resources (agent architecture)
- **Coder** - Software development
- **Scout** - Research and information gathering
- **Druid** - Policy and standards enforcement

## Recovery

Contact Newhart to restore full agent roster:

```sql
SELECT send_agent_message('your_name', 
    'Agent roster unavailable, using fallback', 
    'system', ARRAY['newhart']);
```

Check database:
```sql
SELECT content FROM agent_bootstrap_context WHERE context_type = 'UNIVERSAL' AND file_key = 'AGENTS';
```
