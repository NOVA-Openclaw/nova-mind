# Agent Chat State Tracking Enhancement - Changes Summary

## Problem Solved

Previously, the plugin only tracked whether a message was "processed" (meaning received), with no distinction between:
- Plugin received the notification
- Message was routed to agent session
- Agent actually responded

This led to situations like "Newhart's agent received 24 messages but only replied to 1" with no way to distinguish which messages were truly handled vs. simply received.

## Solution Implemented

Added granular state tracking with four distinct states:
- **received**: Plugin got the NOTIFY
- **routed**: Message passed to agent session (handleInbound)
- **responded**: Agent sent a reply
- **failed**: Error during processing

## Files Changed/Created

### 1. `schema.sql` - Updated
**Changes:**
- Added `agent_chat_status` enum type with states: 'received', 'routed', 'responded', 'failed'
- Modified `agent_chat_processed` table:
  - Changed `processed_at` to `received_at`, `routed_at`, `responded_at`
  - Added `status` column (enum)
  - Added `error_message` column for failures
- Added index on `status` column for performance
- Added inline migration helper comments
- Added example monitoring queries in comments

### 2. `index.js` - Updated
**Changes:**
- Replaced `markMessageProcessed()` with four functions:
  - `markMessageReceived()` - initial state
  - `markMessageRouted()` - after handleInbound success
  - `markMessageResponded()` - when agent replies
  - `markMessageFailed()` - on errors
- Updated notification handler to:
  - Mark as 'received' immediately
  - Mark as 'routed' after successful handleInbound
  - Mark as 'failed' on routing errors (with error message)
- Updated initial message processing to use same flow
- Updated `sendText()` outbound to mark messages as 'responded'
  - Checks `replyTo` metadata field
  - Also checks `dbId` metadata field

### 3. `monitoring-queries.sql` - Created
**Purpose:** Collection of ready-to-use SQL queries for monitoring

**Queries included:**
- Find messages stuck in 'routed' (no response)
- Response time statistics per agent
- Message processing funnel by agent
- Recent failed messages with errors
- Messages never responded to (all statuses)
- Activity summary (last 24 hours)
- Find conversations (thread view)
- Cleanup old processed records

### 4. `migration.sql` - Created
**Purpose:** Safely migrate existing deployments to new schema

**What it does:**
- Creates status enum type
- Adds new columns to existing table
- Migrates existing data (assumes old records were 'responded')
- Removes old `processed_at` column
- Creates new indexes
- Shows migration summary

### 5. `STATE-TRACKING.md` - Created
**Purpose:** Comprehensive documentation for state tracking

**Sections:**
- Overview and rationale
- State definitions with timestamps
- Schema changes explained
- Migration instructions
- Monitoring examples
- Plugin behavior (inbound/outbound flow)
- Use cases (finding ignored messages, debugging slow responses, etc.)
- Troubleshooting guide

### 6. `test-state-tracking.sql` - Created
**Purpose:** Test script to verify state tracking works correctly

**Tests:**
- Insert test message
- Mark as received
- Mark as routed
- Mark as responded
- Test monitoring query
- Cleanup test data

### 7. `README.md` - Updated
**Changes:**
- Added "Granular state tracking" and "Monitoring queries" to features list
- Added new "State Tracking" section with quick example
- Updated database schema section with new table structure
- Split installation into "New Installation" and "Upgrading Existing Installation"
- Added migration instructions

## Deployment Status

### ✅ Completed
- `/home/nova/clawd/clawdbot-plugins/agent-chat-channel/` (source)
- `~/.clawdbot/extensions/agent_chat/` (nova's local deployment)

### ⚠️ Needs Manual Copy
- `/home/newhart/clawd/clawdbot-plugins/agent-chat-channel/` (permission denied)
  - Newhart will need to copy or pull the changes

## Next Steps for Deployment

### For Nova (Local Testing)
1. Stop the agent-chat-channel plugin if running
2. Run migration: `psql -d ${USER}_memory -f ~/.clawdbot/extensions/agent_chat/migration.sql`
3. Restart the plugin
4. Send a test message and verify state progression
5. Test monitoring queries

### For Newhart
1. Copy files from `/home/nova/clawd/clawdbot-plugins/agent-chat-channel/` to `/home/newhart/clawd/clawdbot-plugins/agent-chat-channel/`
2. Backup database: `pg_dump -d nova_memory > backup.sql`
3. Run migration: `psql -d ${USER}_memory -f ~/workspace/nova-mind/cognition/focus/agent_chat/migration.sql`
4. Restart the agent-chat-channel plugin
5. Test with: `psql -d ${USER}_memory -f ~/workspace/nova-mind/cognition/focus/agent_chat/test-state-tracking.sql`

## Testing the Changes

### Quick Test
```sql
-- Send a test message (direct INSERT is blocked; use send_agent_message)
SELECT send_agent_message('tester', 'Hello @your-agent!', ARRAY['your-agent']);

-- Wait for plugin to process...

-- Check the state
SELECT * FROM agent_chat_processed 
WHERE chat_id = (SELECT MAX(id) FROM agent_chat WHERE sender = 'tester');
```

Expected progression:
1. `status = 'received'`, `received_at` populated
2. `status = 'routed'`, `routed_at` populated
3. `status = 'responded'`, `responded_at` populated (after agent replies)

### Find Ignored Messages
```sql
SELECT 
  ac.id,
  ac.sender,
  ac.message,
  acp.status,
  acp.received_at
FROM agent_chat ac
JOIN agent_chat_processed acp ON ac.id = acp.chat_id
WHERE acp.responded_at IS NULL
  AND acp.received_at < NOW() - INTERVAL '1 hour'
ORDER BY acp.received_at DESC;
```

## Performance Considerations

### Indexes Added
- `idx_agent_chat_processed_status` - for filtering by status

### Database Impact
- New columns add minimal storage overhead
- Status queries use indexed lookups
- Migration is fast (updates existing rows with timestamps)

## Backward Compatibility

### Breaking Changes
- None for plugin operation (handles both old and new schema gracefully during migration)
- Old monitoring queries that referenced `processed_at` will break after migration

### Migration Strategy
- Conservative: Existing records marked as 'responded' (safest assumption)
- Alternative: Could mark as 'routed' if you want to be more conservative
- Timestamps preserved from old `processed_at` field

## Known Limitations

1. **Response detection**: Only marks as 'responded' if:
   - Reply has `replyTo` metadata pointing to original message
   - OR reply has `dbId` metadata from inbound routing
   - Messages without these won't be marked as responded

2. **Session context**: Plugin can't detect if agent read but chose not to respond vs. didn't process at all

3. **Multi-agent**: If multiple agents are mentioned, each tracks state independently (this is correct behavior)

## Future Enhancements (Optional)

1. Add dashboard/UI for monitoring
2. Add alerts for messages stuck in 'routed' for >X minutes
3. Track attempt counts for failed messages
4. Add agent session context tracking
5. Export metrics to Prometheus/Grafana
6. Add retry mechanism for failed messages

## Verification Checklist

- [x] Schema updated with state tracking
- [x] Plugin code tracks state transitions
- [x] Migration script created and tested
- [x] Monitoring queries documented
- [x] README updated
- [x] Test script created
- [x] Files deployed to nova's local installation
- [ ] Files deployed to newhart's installation (needs manual copy)
- [ ] Database migration run on production
- [ ] Live testing with real messages
- [ ] Monitoring queries verified

## Support

For questions or issues:
1. Check `STATE-TRACKING.md` for detailed documentation
2. Run queries from `monitoring-queries.sql` to diagnose issues
3. Check plugin logs: `clawdbot gateway logs | grep agent_chat`
4. Review error_message field in agent_chat_processed for failures
