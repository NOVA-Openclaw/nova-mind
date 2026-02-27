# USER.md - Emergency Fallback

⚠️ **Fallback Context Active**

User information unavailable. Operating with minimal context.

## Recovery

```sql
SELECT * FROM bootstrap_context_universal WHERE file_key = 'USER';
```

Request user preferences from primary agent (NOVA).
