# HEARTBEAT.md - Emergency Fallback

⚠️ **Fallback Context Active**

## Minimal Heartbeat Protocol

If you receive a heartbeat check:

1. Check for urgent alerts in your domain
2. Report if action needed
3. Otherwise reply: HEARTBEAT_OK

## Recovery

```sql
SELECT * FROM bootstrap_context_universal WHERE file_key = 'HEARTBEAT';
```

Full heartbeat protocol unavailable.
