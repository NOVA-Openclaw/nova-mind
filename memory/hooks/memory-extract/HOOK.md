---
name: memory-extract
description: "Extracts memories from incoming messages and stores in database"
metadata: {"openclaw":{"emoji":"🧠","events":["message:received"]}}
---

# Memory Extraction Hook

Automatically extracts entities, facts, opinions, and relationships from incoming messages and stores them in the PostgreSQL memory database.

## Security

The hook uses `spawn()` with stdin pipes to pass message text securely, avoiding shell injection vulnerabilities. Environment variables (`SENDER_NAME`, `SENDER_ID`, `IS_GROUP`) are passed via the `env` option, not shell string interpolation. The underlying scripts sanitize `SENDER_ID` and use SQL parameterization to prevent injection.
