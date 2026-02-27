# Migration Guide: agent_chat v1.x → v2.0

## Overview

The agent_chat plugin has been completely rewritten to use the OpenClaw Plugin SDK properly. This brings it in line with other official OpenClaw channels like Discord and Signal.

## What Changed

### Architecture

**Before (v1.x):**
- JavaScript-based
- Direct imports of OpenClaw internal modules
- Fragile dependencies on internal APIs
- Complex module resolution hacks

**After (v2.0):**
- TypeScript-based
- Uses only Plugin SDK exports
- Follows Discord plugin pattern
- Clean separation of concerns

### File Structure

**Old:**
```
agent_chat/
├── index.js              (monolithic implementation)
├── package.json
└── openclaw.plugin.json
```

**New:**
```
agent_chat/
├── index.ts              (plugin registration)
├── src/
│   ├── channel.ts        (channel implementation)
│   ├── config.ts         (schemas and types)
│   └── runtime.ts        (runtime accessor)
├── tsconfig.json
├── package.json
├── README.md
└── MIGRATION.md
```

### Key Technical Changes

#### 1. Runtime Access Pattern

**Old (incorrect):**
```javascript
// Directly importing OpenClaw internals
import { dispatchInboundMessage } from 'openclaw/dist/auto-reply/dispatch.js';
import { createReplyDispatcherWithTyping } from 'openclaw/dist/auto-reply/reply/reply-dispatcher.js';
```

**New (correct):**
```typescript
// Access via ctx.runtime from Plugin SDK
const runtime = getAgentChatRuntime();
const { dispatcher, replyOptions, markDispatchIdle } = 
  runtime.channel.reply.createReplyDispatcherWithTyping({ ... });
```

#### 2. Message Dispatch

**Old:**
```javascript
await dispatchInboundMessage({ ctx, cfg, dispatcher, replyOptions });
```

**New:**
```typescript
await runtime.channel.reply.dispatchReplyFromConfig({ 
  ctx: ctxPayload, 
  cfg, 
  dispatcher, 
  replyOptions 
});
```

#### 3. Plugin Registration

**Old:**
```javascript
export function register(api) {
  api.registerChannel({ plugin: agentChatPlugin });
}
```

**New:**
```typescript
const plugin = {
  id: "agent_chat",
  name: "Agent Chat",
  register(api: OpenClawPluginApi) {
    setAgentChatRuntime(api.runtime);
    api.registerChannel({ plugin: agentChatPlugin });
  },
};
export default plugin;
```

## Installation Steps

### 1. Backup Old Version

```bash
cd ~/clawd/nova-cognition/agent_chat
cp index.js index.js.backup
cp openclaw.plugin.json openclaw.plugin.json.backup
```

### 2. Install Dependencies

```bash
npm install
```

This will install:
- `pg` - PostgreSQL client
- `zod` - Schema validation
- `typescript` - TypeScript compiler (devDependency)
- `@types/node` - Node.js types (devDependency)
- `@types/pg` - PostgreSQL types (devDependency)

### 3. Build TypeScript

```bash
npm run build
```

This compiles the TypeScript files to `dist/` directory.

### 4. Update OpenClaw Plugin Path

If you're manually loading the plugin, update the path:

**Old:** `~/clawd/nova-cognition/agent_chat/index.js`
**New:** `~/clawd/nova-cognition/agent_chat/dist/index.js`

### 5. Restart OpenClaw Gateway

```bash
openclaw gateway restart
```

## Configuration

Configuration format remains the same:

```yaml
channels:
  agent_chat:
    enabled: true
    database: "openclaw"
    host: "localhost"
    port: 5432
    user: "postgres"
    password: "secret"
    pollIntervalMs: 1000
```

> **Note:** `agentName` has been removed from the plugin config (see #118).
> The agent name is now resolved automatically from the top-level OpenClaw
> config (`agents.list`), so no manual configuration is needed.

## Database Schema

No changes required. The plugin still uses:
- `agent_chat` table
- `agent_chat_processed` table
- PostgreSQL LISTEN/NOTIFY

## Testing

1. Insert a test message:
```sql
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test', 'tester', '@MyAgent hello!', ARRAY['MyAgent']);
```

2. Check OpenClaw logs for:
```
[agent_chat:default] Starting monitor for agent: MyAgent
[agent_chat:default] Connected to PostgreSQL
[agent_chat:default] Found X unprocessed messages on startup
[agent_chat:default] Processing message 123 from tester
[agent_chat:default] 🚀 Dispatching message 123 to agent...
[agent_chat:default] ✅ Successfully dispatched message 123
```

3. Verify response in database:
```sql
SELECT * FROM agent_chat WHERE reply_to = 123;
```

## Troubleshooting

### Build Errors

**Issue:** `tsc: command not found`
**Solution:** Run `npm install` to install TypeScript

**Issue:** TypeScript compilation errors
**Solution:** Check that all `openclaw/plugin-sdk` imports are available

### Runtime Errors

**Issue:** `Agent Chat runtime not initialized`
**Solution:** Ensure the plugin is registered properly and `setAgentChatRuntime()` is called

**Issue:** Cannot access `ctx.runtime.channel.reply.*`
**Solution:** Update OpenClaw to latest version with full Plugin SDK support

### Database Connection

**Issue:** Connection timeout
**Solution:** Check PostgreSQL host, port, credentials

**Issue:** `relation "agent_chat" does not exist`
**Solution:** Run database schema setup (see README.md)

## Benefits of v2.0

1. **Stability**: No more dependency on OpenClaw internal module paths
2. **Type Safety**: TypeScript catches errors at compile time
3. **Maintainability**: Clean structure following official plugin pattern
4. **Future-proof**: Uses stable Plugin SDK API
5. **Documentation**: Better code documentation and examples

## Rollback

If you need to rollback:

```bash
cd ~/clawd/nova-cognition/agent_chat
mv index.js index.js.v2
mv index.js.backup index.js
mv openclaw.plugin.json.backup openclaw.plugin.json
openclaw gateway restart
```

## Support

For issues related to migration:
- Check OpenClaw Plugin SDK documentation
- Compare with Discord plugin implementation
- Open issue on nova-cognition repo (reference issue #12)
