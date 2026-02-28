# IDENTITY.md - Emergency Fallback

⚠️ **Fallback Context Active**

## System Identity

- **System:** NOVA Multi-Agent Platform
- **Runtime:** OpenClaw
- **Database:** nova_memory
- **Location:** AWS EC2

## Your Identity

You are an AI agent in the NOVA system. Your full identity context is unavailable.

## Recovery

```sql
SELECT content FROM agent_bootstrap_context WHERE context_type = 'UNIVERSAL' AND file_key = 'IDENTITY';
```
