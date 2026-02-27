# Common Pitfalls

Mistakes to avoid when setting up and operating the cognition system. Learned the hard way.

## Configuration Errors

### ❌ Adding Unknown Keys to Config

**Problem:** Clawdbot's config parser is strict. Unknown keys make the entire config invalid.

```json
// DON'T DO THIS
{
  "channels": {
    "signal": {
      "enabled": true,
      "_notes": { "description": "..." }  // ← BREAKS CONFIG
    }
  }
}
```

**Symptom:** `clawdbot gateway status` shows "Invalid config" and subagent spawning fails silently.

**Fix:** Only use documented config keys. If you need notes, keep them in a separate file or database.

**How to detect:**
```bash
clawdbot gateway status
# Look for "Invalid config" or "Unrecognized key" errors
```

---

### ❌ Forgetting to Add Agents to allowAgents

**Problem:** Defining an agent in `agents.list` isn't enough—it must also be in the primary agent's `subagents.allowAgents`.

```json
// Agent defined here...
{
  "agents": {
    "list": [
      { "id": "scout", "model": "..." }
    ]
  }
}

// ...but NOT listed here → spawn fails
{
  "id": "main",
  "subagents": {
    "allowAgents": []  // ← scout missing!
  }
}
```

**Symptom:** `sessions_spawn` returns "forbidden" or "agentId not allowed".

**Fix:** Add the agent ID to `agents.list[main].subagents.allowAgents`.

---

### ❌ Working Around Broken Tools

**Problem:** When a tool/agent fails, the temptation is to do the task yourself. This masks the underlying problem.

**Example:** Git-agent won't spawn → manually run git commands → problem never gets fixed.

**Better approach:**
1. Stop and diagnose why the agent failed
2. Fix the root cause (config, permissions, etc.)
3. Verify the agent works
4. Then proceed with the original task

**Why it matters:** Subagents are extensions of your thinking. If they're broken, your thinking is impaired. Fix first.

---

## Access Control Errors

### ❌ Bypassing Permission Denied Without Understanding Why

**Problem:** Getting "permission denied" and immediately working around it (e.g., granting yourself permissions).

**Better approach:**
1. Check if the restriction is intentional: `SELECT table_comment('tablename');`
2. If intentional, delegate to the appropriate agent or ask
3. Don't bypass access controls without understanding them

**Example:** The `agents` table should only be modified by the agent architect, not the MCP directly.

---

### ❌ Modifying Config Without Discussion

**Problem:** Making config changes without discussing with the user first, especially in interactive sessions.

**Protocol for config changes:**
1. Propose the change and explain why
2. Wait for agreement
3. Make the change
4. Verify it works

**Especially critical for:** Anything in `clawdbot.json`, credentials, external service configs.

---

## Agent Architecture Errors

### ❌ Confusing Subagents and Peer Agents

| Subagent | Peer Agent |
|----------|------------|
| Extension of MCP's thinking | Separate entity |
| Spawn with `sessions_spawn` | Message via protocol |
| On-demand or persistent | Always separate process |
| Returns results to MCP | Collaborates as colleague |

**Wrong:** Spawning a peer agent like a subagent
**Wrong:** Messaging a subagent like a peer

---

### ❌ Not Verifying Agent Availability Before Spawning

**Problem:** Assuming an agent exists and is configured.

**Better approach:**
```
# Check available agents first
agents_list

# Then spawn only if it's in the list
sessions_spawn(agentId="agent-id", task="...")
```

---

## Recovery Procedures

### Config Is Invalid

```bash
# 1. Check what's wrong
clawdbot gateway status

# 2. Fix the config file
nano ~/.clawdbot/clawdbot.json

# 3. Validate JSON
cat ~/.clawdbot/clawdbot.json | jq . > /dev/null && echo "Valid"

# 4. Restart gateway
clawdbot gateway restart
```

### Subagent Spawning Broken

1. Run `clawdbot gateway status` - check for config errors
2. Run `agents_list` - verify agents show `configured: true`
3. If empty/false, check config for:
   - Invalid keys
   - Missing `allowAgents` entries
   - Syntax errors

### Can't Reach Peer Agent

1. Check if peer's gateway is running: `systemctl --user status clawdbot-gateway` (on peer's user)
2. Check `agent_chat` table for messages
3. Verify peer's polling interval

---

## Golden Rules

1. **Fix tools, don't route around them** - Broken agents = broken thinking
2. **Discuss config changes first** - Especially in interactive sessions
3. **Verify after changes** - Always confirm the fix worked
4. **Understand restrictions** - Permission denied might be intentional
5. **Keep config clean** - Only use documented keys

---

*These lessons came from actual mistakes. Learn from them.*
