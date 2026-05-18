# HEARTBEAT.md

<!-- PURPOSE: Heartbeat/proactive mode configuration — idle detection and workflow dispatch -->

# HEARTBEAT.MD — Proactive Mode

## Idle Detection

Check if all communication channels have been quiet for 15+ minutes using native OpenClaw data sources:

1. **sessions_list** — Query active sessions and their last activity timestamps:
   ```bash
   openclaw sessions list --json | jq -r '.[] | {name, lastActivityAt}'
   ```

2. **message(action="read")** — Read the most recent message in the channel and compare its timestamp to the current time.

3. **Inbound message metadata** — The OpenClaw gateway provides `last_seen` or equivalent timestamps on inbound messages that can be compared directly.

If the most recent activity across all channels is older than 15 minutes → idle.

If idle < 15 minutes → reply HEARTBEAT_OK (human is active, don't interrupt).

## Proactive Mode (idle ≥ 15 minutes)

Report all Proactive Mode work summaries to Discord #proactive-mode

When idle, execute the **NOVA Proactive Mode** workflow (id=27). Query the workflow steps for the full priority cascade:

```sql
SELECT step_order, description FROM workflow_steps
WHERE workflow_id = 27 ORDER BY step_order;
```

Work through steps in order. Each step describes its own gate conditions — advance to the next step only when the current one has no actionable work.

## Rules
- **Late night (23:00-08:00 UTC):** HEARTBEAT_OK unless something is genuinely urgent
- **Recently checked (<30 min ago):** HEARTBEAT_OK unless new work appeared
- **Human is active:** HEARTBEAT_OK — don't compete with conversation
- **Never announce** proactive work unless you found something the human needs to know about
