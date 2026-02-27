# Issue #148: Ensure agent_chat Setup Scripts Grant Complete Database Permissions

## Context
When setting up a new agent's database user for the `agent_chat` plugin, the required sequence permissions are not automatically granted. This causes agents to receive and process messages but fail silently when attempting to reply.

## Problem
The `agent_chat` plugin requires `INSERT` on the `agent_chat` table and `USAGE, SELECT` on the `agent_chat_id_seq` sequence to write replies. Current setup documentation and scripts do not ensure these permissions are granted, leading to a confusing failure mode where agents appear to receive messages but never respond.

## Solution
- [ ] Update any setup/migration scripts to include the full set of required grants
- [ ] Add a health check or startup warning in the plugin if the configured DB user lacks INSERT or sequence permissions
- [ ] Document the complete permission set in SETUP.md (covered by Issue #147)

## Required Grants
```sql
GRANT SELECT, INSERT ON agent_chat TO <db_user>;
GRANT USAGE, SELECT ON SEQUENCE agent_chat_id_seq TO <db_user>;
```

## Acceptance Criteria
- [ ] Setup scripts grant all required permissions automatically
- [ ] Plugin logs a clear warning at startup if permissions are insufficient
- [ ] No silent failures when an agent attempts to reply
