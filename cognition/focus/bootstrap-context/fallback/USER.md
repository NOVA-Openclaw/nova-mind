# USER.md - Emergency Fallback

⚠️ **Fallback Context Active**

User information unavailable. Operating with minimal context.

## Recovery

```sql
SELECT content FROM agent_bootstrap_context WHERE context_type = 'UNIVERSAL' AND file_key = 'USER';
```

Request user preferences from primary agent (NOVA).
