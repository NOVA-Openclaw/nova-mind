# Quick Setup Guide

> **As of #320:** `agent_chat` lives in its own dedicated PostgreSQL database (named
> `agent_chat`), not in the same database as the rest of nova-memory. If you are
> setting up via the unified `agent-install.sh` installer, steps 2–3 below are handled
> automatically (schema application via the migration tooling, and `postgres.json`
> provisioning) — this guide documents what the installer does and how to verify or
> reproduce it manually.

## 1. Install Dependencies

```bash
cd <plugin-directory>/agent-chat-channel
npm install
```

## 2. Set Up Database

Create the dedicated `agent_chat` database and apply its schema (see
`scripts/agent-chat-migration/README.md` for the full migration runbook if migrating
an existing installation):

```bash
createdb agent_chat
psql -h localhost -U <db_user> -d agent_chat -f database/agent-chat/schema.sql
```

The canonical schema (tables, `send_agent_message()`, triggers, views, grants) lives
in `database/agent-chat/schema.sql` at the repo root — not in this directory's local
`schema.sql`, which predates the dedicated-database design and is kept only for
historical/local-dev reference.

### Required Permissions

The plugin connects via TCP using `pg.Client`, so **password authentication is required**.
Peer auth (Unix socket) will not work.

Grant the following permissions to your database user:

```sql
GRANT SELECT, INSERT ON agent_chat TO <db_user>;
GRANT USAGE, SELECT ON SEQUENCE agent_chat_id_seq TO <db_user>;
```

(`database/agent-chat/schema.sql` already grants the full matrix for all
nova-ecosystem roles; the above is for a manually-added user.)

## 3. Configure OpenClaw

Connection details for `agent_chat` are **not** set in `openclaw.json`. They are
resolved from the nested `agent_chat` section of `~/.openclaw/postgres.json`:

```json
{
  "host": "localhost",
  "port": 5432,
  "database": "nova_memory",
  "user": "<db_user>",
  "password": "<db_password>",
  "agent_chat": {
    "database": "agent_chat",
    "user": "<db_user>",
    "password": "<db_password>"
  }
}
```

`agent-install.sh` writes/merges this nested section automatically and is idempotent
(re-running reports the section is already correct — no clobber of existing values).

Then in `openclaw.json`, enable the channel (no connection keys here):

```json
{
  "channels": {
    "agent_chat": {
      "enabled": true
    }
  }
}
```

**Important:** `database`/`host`/`port`/`user`/`password` under `channels.agent_chat`
are no longer read by the plugin — `agent-install.sh` strips them on install/upgrade.
Store the password securely; the `postgres.json` file should be mode `600`.

See `example-config.yaml` for more options.

## 4. Restart Gateway

```bash
openclaw gateway restart
```

## 5. Verify Plugin Loaded

```bash
openclaw gateway status
```

Look for `agent_chat` in the channels list.

## 6. Send Test Message

```sql
-- All inserts must go through send_agent_message() (direct INSERT is blocked)
SELECT send_agent_message('your_name', 'Hello @your_agent!', ARRAY['your_agent']);
```

The agent should receive and respond to the message.

## Troubleshooting

### Plugin not showing in status

- Check plugin path in config
- Verify index.js exports `agentChatPlugin` or default export
- Check gateway logs: `openclaw gateway logs`

### Database connection errors

- Verify credentials work via TCP: `psql -h localhost -U <db_user> -d agent_chat`
- Check that the `agent_chat` database and its tables exist (`\dt` should show `agent_chat`, `agent_chat_processed`)
- Confirm the nested `agent_chat` section in `~/.openclaw/postgres.json` has a non-empty `password`
- Run `scripts/agent-chat-migration/audit_rollout.py` to check which database a given agent's config actually resolves to

### Messages not received

- Verify NOTIFY trigger is set up: check `pg_trigger` table
- Test NOTIFY manually:
  ```sql
  LISTEN agent_chat;
  -- In another session (use send_agent_message — direct INSERT is blocked):
  SELECT send_agent_message('test_sender', 'test message', ARRAY['target_agent']);
  ```
- Check that the agent name in your `agents.list` config matches the recipients array in messages

### Agent not responding

- Verify the database user has INSERT permission on `agent_chat` and USAGE on `agent_chat_id_seq`
- Check session routing in logs
- Verify agent session is active
- Test outbound by checking the `agent_chat` table for replies

## Next Steps

- Add more agents to the system
- Set up channels for different purposes
- Integrate with other systems via database triggers
- Build UI on top of the agent_chat table
