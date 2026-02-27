# Issue #147: Document agent_chat Plugin Database Authentication Requirements

## Context
The `agent_chat` extension plugin connects to PostgreSQL via TCP using `pg.Client` (not Unix socket peer auth). This has specific requirements that are not currently documented clearly, and the existing SETUP.md contains environment-specific references (agent names, credential storage locations) that should not be in a public repository.

## Problem
1. The `SETUP.md` for the `agent_chat` plugin references specific agent names and credential storage locations that are deployment-specific and should not appear in a shared/public repository.
2. The requirement for password-based authentication is not explicitly documented — users may attempt to use peer auth or leave the password field empty, which silently prevents the plugin from starting.
3. Required database permissions (specifically `USAGE` on sequences) are not documented, leading to agents that can receive messages but cannot reply.

## Requirements

### Documentation Changes (SETUP.md)
- [ ] Remove all references to specific agent names (e.g., no hardcoded agent identifiers)
- [ ] Remove all references to specific credential storage systems or vault paths
- [ ] Clearly document that **password authentication is mandatory** because the plugin connects via TCP (`host: "localhost"`)
- [ ] Document that the `channels.<plugin_name>.password` config field must be **non-empty** — the plugin's `isConfigured()` check requires `Boolean(password)` to evaluate truthy
- [ ] Provide a generic example configuration block

### Database Permission Requirements
Document that the database user configured for the plugin requires:
- [ ] `SELECT` on the `agent_chat` table (to read incoming messages)
- [ ] `INSERT` on the `agent_chat` table (to write replies)
- [ ] `USAGE, SELECT` on `agent_chat_id_seq` (to auto-generate row IDs for replies)

### Example Generic Setup Section
```markdown
## Database Setup

The agent_chat plugin requires a PostgreSQL user with password authentication.
Peer auth is not supported as the plugin connects via TCP.

### Required Permissions
```sql
GRANT SELECT, INSERT ON agent_chat TO <your_db_user>;
GRANT USAGE, SELECT ON SEQUENCE agent_chat_id_seq TO <your_db_user>;
```

### Configuration
```json
{
  "channels": {
    "agent_chat": {
      "enabled": true,
      "database": "<database_name>",
      "host": "localhost",
      "port": 5432,
      "user": "<db_username>",
      "password": "<db_password>"
    }
  }
}
```

**Note:** The password field must not be empty. Store credentials securely using your preferred secrets management solution.
```

## Acceptance Criteria
- [ ] SETUP.md contains no deployment-specific agent names or credential paths
- [ ] Password auth requirement is clearly documented with explanation (TCP, not peer)
- [ ] Database permission requirements are listed with exact SQL GRANT statements
- [ ] A generic configuration example is provided
