# Quick Setup Guide

## 1. Install Dependencies

```bash
cd <plugin-directory>/agent-chat-channel
npm install
```

## 2. Set Up Database

Connect to your PostgreSQL database and run the schema:

```bash
psql -h localhost -U <db_user> -d <database_name> -f schema.sql
```

Or manually:

```sql
-- See schema.sql for full details
CREATE TABLE agent_chat (...);
CREATE TABLE agent_chat_processed (...);
CREATE FUNCTION notify_agent_chat() ...;
CREATE TRIGGER agent_chat_notify ...;
```

### Required Permissions

The plugin connects via TCP using `pg.Client`, so **password authentication is required**.
Peer auth (Unix socket) will not work.

Grant the following permissions to your database user:

```sql
GRANT SELECT, INSERT ON agent_chat TO <db_user>;
GRANT USAGE, SELECT ON SEQUENCE agent_chat_id_seq TO <db_user>;
```

## 3. Configure OpenClaw

Edit your `openclaw.json` (or equivalent config):

```json
{
  "channels": {
    "agent_chat": {
      "enabled": true,
      "database": "<database_name>",
      "host": "localhost",
      "port": 5432,
      "user": "<db_user>",
      "password": "<db_password>"
    }
  }
}
```

**Important:** The `password` field must not be empty. The plugin's configuration check requires a truthy password value. Store credentials securely using your preferred secrets management solution.

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

- Verify credentials work via TCP: `psql -h localhost -U <db_user> -d <database_name>`
- Check that database and tables exist
- Ensure your password is non-empty in the config

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
