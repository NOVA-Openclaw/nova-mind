# Test Cases: Issue #182 — Consolidate Turn-Context Hooks into Single Plugin

**Branch:** `feature/issue-182-turn-context-plugin`
**Closes:** nova-openclaw #40, nova-openclaw #41

---

## Overview

This issue replaces two broken fire-and-forget internal hooks (`semantic-recall` and `agent-turn-context`) with a proper OpenClaw Plugin SDK plugin. The plugin lives at `memory/plugins/turn-context/` and registers two hooks:

- **`message_received`** (observation, fire-and-forget) — caches sender info per session key
- **`before_prompt_build`** (awaited, returns result) — runs turn reminders, entity resolution, and semantic recall; injects context into the system prompt via `appendSystemContext`

**Root cause being fixed:** Old hooks registered on `message:received` internal events which are fire-and-forget — context pushed via `event.messages.push()` never reached the LLM. The `spawnSync` workaround froze the event loop.

---

## Test Area 1: Plugin Registration

### TC-001: `definePluginEntry` exports required hooks
**Preconditions:** Plugin installed (`openclaw plugins install ./memory/plugins/turn-context`)
**Input:** Gateway starts; plugin loader initialises the plugin
**Steps:**
1. Call the default export (the `PluginEntry`) produced by `definePluginEntry`
2. Inspect registered hooks via the plugin API
**Expected:**
- Plugin entry registers exactly two hooks: `message_received` and `before_prompt_build`
- Both registrations use `api.on()` (not `event.messages.push()`)
- `before_prompt_build` registration is awaited by the host (prompt-injection hook)
- `message_received` registration is observation-mode (fire-and-forget, no return value expected)

### TC-002: `openclaw.plugin.json` manifest is valid
**Preconditions:** Plugin source present at `memory/plugins/turn-context/`
**Input:** `openclaw plugins install ./memory/plugins/turn-context --dry-run` (or manifest validation)
**Steps:**
1. Parse `openclaw.plugin.json`
2. Validate required fields: `id`, `name`, `version`, `main`, `hooks`
3. Verify `hooks` array contains `"message_received"` and `"before_prompt_build"`
**Expected:**
- Manifest parses without errors
- `main` resolves to `index.ts` (or compiled output)
- Declared hooks match exactly what `index.ts` registers at runtime
- No undeclared hooks are registered at runtime

### TC-003: Plugin `package.json` is valid and buildable
**Preconditions:** Plugin source present
**Input:** `cd memory/plugins/turn-context && npm install && npm run build`
**Expected:**
- `npm install` resolves without errors
- `npm run build` (or `tsc`) completes without TypeScript errors
- Compiled output exists in declared `main` location

---

## Test Area 2: `message_received` — Sender Cache

### TC-004: Sender info cached on first message for a session
**Preconditions:** Empty sender cache (no prior messages on this session key)
**Input:** `message_received` event:
```json
{
  "from": "discord:channel:1492386247862390824",
  "content": "Hello NOVA",
  "senderId": "330189773371080716",
  "sessionKey": "session:discord:abc123",
  "metadata": {
    "senderName": "I)ruid",
    "provider": "discord",
    "senderE164": null
  }
}
```
**Context (`PluginHookMessageContext`):** `{ channelId: "discord:channel:...", sessionKey: "session:discord:abc123" }`
**Expected:**
- Cache entry stored under key `"session:discord:abc123"`
- Cached entry contains: `senderId = "330189773371080716"`, `senderName = "I)ruid"`, `provider = "discord"`, `senderE164 = null`
- No error thrown, handler returns void

### TC-005: Sender cache updated when new message arrives on same session
**Preconditions:** Cache already has entry for `"session:discord:abc123"` from TC-004
**Input:** Second `message_received` event on same session key, but `senderName` changed to `"Druid"` (e.g., display name update)
**Expected:**
- Cache entry for `"session:discord:abc123"` is overwritten with new sender info
- Old entry does not persist alongside new entry (no duplication)

### TC-006: Multiple concurrent session keys cached independently
**Preconditions:** Two simultaneous sessions from different channels
**Input:** `message_received` events for sessions `"session:discord:abc123"` and `"session:signal:xyz789"` (different senders, different providers)
**Implementation note:** The sender cache is a `Map<string, SenderInfo>` singleton (not a generic cache). Verify both isolation and that the same Map instance is used across hook invocations.
**Expected:**
- Cache has two independent entries
- Reading cache for `"session:discord:abc123"` returns Discord sender
- Reading cache for `"session:signal:xyz789"` returns Signal sender
- No cross-contamination between sessions

### TC-007: `message_received` with missing optional fields — partial cache entry
**Preconditions:** Empty cache
**Input:** `message_received` event with no `metadata` field, no `senderId`:
```json
{
  "from": "internal:cron",
  "content": "heartbeat",
  "sessionKey": "session:cron:heartbeat-01"
}
```
**Expected:**
- Cache entry stored with `senderId = undefined`, `senderName = undefined`, `provider = undefined`
- No crash, no error thrown
- Handler returns void

---

## Test Area 3: `before_prompt_build` — Happy Path

### TC-008: All three subsystems return context — full injection
**Preconditions:**
- Sender cache populated for the session key (from prior `message_received`)
- DB returns non-empty turn reminders for the agent
- Entity resolved successfully
- `proactive-recall.py` returns 2 relevant memories
**Input:** `before_prompt_build` event:
```json
{
  "prompt": "What's the status of issue #182?",
  "messages": []
}
```
Context (`PluginHookAgentContext`): `{ agentId: "nova", sessionKey: "session:discord:abc123", sessionId: "...", messageProvider: "discord", channelId: "discord:channel:..." }`
**Expected:**
- Handler returns `{ appendSystemContext: "<combined context string>" }`
- `appendSystemContext` contains all three sections: turn reminders block, entity context block, semantic recall memories block
- Each section is non-empty
- Result is returned (not pushed to `event.messages`) — it reaches the LLM via the prompt-injection path
- `before_prompt_build` hook completes within 8s timeout

### TC-009: Returned `appendSystemContext` reaches the LLM system prompt
**Preconditions:** Same as TC-008; gateway running with plugin installed
**Input:** Full message dispatch triggering an agent LLM call
**Expected (integration):**
- LLM call's system prompt contains the injected context from `appendSystemContext`
- Context is not duplicated in user/assistant message history
- Old `event.messages.push()` pattern is NOT used anywhere in the new plugin

---

## Test Area 4: Sender Cache Miss in `before_prompt_build`

### TC-010: No prior `message_received` — heartbeat/cron turn
**Preconditions:** No cache entry exists for the session key (e.g., cron-triggered turn with no user message)
**Input:** `before_prompt_build` fires for `sessionKey = "session:cron:daily-review"` which has no cache entry
**Expected:**
- Entity resolution is **skipped** (no `senderId` to resolve from)
- Semantic recall is **skipped** (no sender context to build recall query from)
- Turn reminders still run (they only need `agentId`, which comes from `ctx.agentId`)
- Result is `{ appendSystemContext: "<turn reminders only>" }` or `{}` if reminders are also empty
- No crash, no null-pointer errors on missing cache entry

### TC-011: `senderId` present in cache but `senderName` absent — entity resolution proceeds, recall skipped or minimised
**Preconditions:** Cache entry has `senderId` but no `senderName` (e.g., from TC-007 partial cache)
**Input:** `before_prompt_build` fires on the session
**Expected:**
- Entity resolution attempts lookup using `senderId` with channel-aware identifier mapping
- Semantic recall uses `senderId` in payload; if no meaningful query text is available, recall is gracefully skipped
- No crash on absent `senderName`

---

## Test Area 5: Entity Resolution

### TC-012: Discord sender resolved to known entity
**Preconditions:** `entity_facts` table has a row `{ entity_id: 1, key: 'discord_id', value: '330189773371080716' }` for entity "I)ruid"
**Input:** Sender cache entry: `{ senderId: "330189773371080716", provider: "discord" }`
**Steps:** `before_prompt_build` runs entity resolution subsystem
**Expected:**
- `extractIdentifiers("discord", "330189773371080716")` returns `{ discordId: "330189773371080716" }`
- `resolveEntityByIdentifiers({ discordId: "330189773371080716" })` returns `{ ok: true, entity: { id: 1, name: "I)ruid", ... } }`
- Entity context block injected: contains entity name and any known facts (timezone, expertise, etc.)

### TC-013: Signal sender resolved with UUID + phone
**Preconditions:** `entity_facts` has `signal_uuid` and `phone` rows for the same entity
**Input:** Sender cache: `{ senderId: "signal-uuid-abc", provider: "signal", senderE164: "+15551234567" }`
**Expected:**
- `extractIdentifiers("signal", "signal-uuid-abc", "+15551234567")` returns `{ signalUuid: "signal-uuid-abc", phone: "+15551234567" }`
- Entity resolved correctly via either identifier

### TC-014: Telegram sender resolved
**Input:** Sender cache: `{ senderId: "987654321", provider: "telegram" }`
**Expected:**
- `extractIdentifiers("telegram", "987654321")` returns `{ telegramId: "987654321" }`
- Entity lookup uses `entity_facts.key = 'telegram_id'`

### TC-015: Slack sender resolved
**Input:** Sender cache: `{ senderId: "U0123ABCDEF", provider: "slack" }`
**Expected:**
- `extractIdentifiers("slack", "U0123ABCDEF")` returns `{ slackMemberId: "U0123ABCDEF" }`
- Entity lookup uses `entity_facts.key = 'slack_member_id'`

### TC-016: Unknown provider — graceful skip, no crash
**Input:** Sender cache: `{ senderId: "some-id", provider: "matrix" }` (unsupported provider)
**Expected:**
- `extractIdentifiers("matrix", "some-id")` returns `{}` (empty identifiers)
- Entity resolution is skipped (no identifiers to query with)
- `before_prompt_build` continues without entity block
- No error thrown; logged as a skip, not an error

### TC-017: Entity resolution conflict — two entities match, none injected
**Preconditions:** DB has two entities (id=1 and id=2) both with the same `discord_id` value (data integrity issue)
**Input:** `resolveEntityByIdentifiers({ discordId: "ambiguous-id" })` returns `{ ok: false, conflict: true, entities: [...] }`
**Expected:**
- Entity block is NOT injected into the context
- Conflict is logged as a data integrity error (console.error)
- `before_prompt_build` continues; other subsystems still run
- No partial/wrong entity data injected

### TC-018: Entity found but no facts — entity name still injected
**Preconditions:** Entity resolved (id=5, name="Ghost"), but `entity_facts` has no rows for allowed keys (timezone, expertise, etc.)
**Expected:**
- `getEntityProfile(5)` returns `{}`
- Entity context block still injected with at minimum the entity name: `"👤 **Talking with:** Ghost"`
- No crash on empty facts object

### TC-019: Entity resolution timeout (2s guard) — graceful skip
**Preconditions:** DB query hangs
**Input:** `Promise.race([resolveEntityByIdentifiers(...), timeout(2000)])` — timeout wins
**Expected:**
- `resolveResult` is `null`
- Entity block skipped
- Other subsystems still run
- No unhandled promise rejection

---

## Test Area 6: Semantic Recall

### TC-020: Recall returns memories — injected into `appendSystemContext`
**Preconditions:** `proactive-recall.py` available, Ollama running, memories exist in DB
**Input:** Recall invoked with message content `"What are the open GitHub issues?"`, token budget 1000
**Expected:**
- `proactive-recall.py` spawned via `spawn` (async, not `spawnSync`)
- Promise resolves within 8s
- Result parsed as JSON with `memories` array
- Memories formatted and included in `appendSystemContext` output
- Log: `"[turn-context] Found N relevant memories (~X/1000 tokens)"`

### TC-021: Content truncation before recall query
**Preconditions:** Message content is 5000 characters
**Input:** Full message content passed to recall subsystem
**Expected:**
- Content truncated to ≤2000 characters before being passed to `proactive-recall.py` stdin payload
- No error from Python script due to oversized input

### TC-022: Recall timeout — graceful degradation, other subsystems unaffected
**Preconditions:** `proactive-recall.py` hangs (simulated with `sleep 30`)
**Input:** Plugin timeout for `before_prompt_build` handler is 8s; recall subsystem has internal timeout
**Expected:**
- Recall `spawn` promise rejects after configured timeout (≤8s)
- `try/catch` around recall catches the timeout/rejection
- Error logged: `"[turn-context] Recall error: ..."` or similar
- `before_prompt_build` handler still returns; turn reminders and entity context (if available) are still injected
- No LLM call timeout caused by this subsystem

### TC-023: Recall script not found — graceful degradation
**Preconditions:** `proactive-recall.py` path does not exist (e.g., not installed)
**Input:** Spawn attempt on missing script path
**Expected:**
- `spawn` emits an error event (ENOENT)
- Promise rejects; `catch` handles it
- Error logged
- `appendSystemContext` returned without recall block
- No crash

### TC-024: Recall Python process exits non-zero — graceful degradation
**Preconditions:** Script exits with code 1 (e.g., DB connection failure, Ollama not running)
**Input:** Recall subsystem detects non-zero exit
**Expected:**
- Error logged with stderr content
- `recallResult` treated as null/empty
- Recall block absent from `appendSystemContext`
- No crash

### TC-025: Recall returns empty memories array — no recall block injected
**Preconditions:** Script exits 0, stdout is `{"memories": [], "tokens_used": 0}`
**Expected:**
- `appendSystemContext` does not contain a recall/memories section (avoid injecting empty block)
- No formatting artifacts (e.g., empty `🧠 **Relevant Context:**` header without content)

### TC-026: Recall JSON parse failure — graceful degradation
**Preconditions:** `proactive-recall.py` stdout is not valid JSON (e.g., truncated output, Python traceback)
**Expected:**
- `JSON.parse()` throws; `catch` handles it
- Error logged
- Recall block absent from result
- No crash

---

## Test Area 7: Turn Reminders

### TC-027: Turn reminders loaded from DB and injected
**Preconditions:** `get_agent_turn_context('nova')` returns a non-empty `content` string
**Input:** `before_prompt_build` for `agentId = "nova"`
**Expected:**
- `queryTurnContext("nova")` executes `SELECT content, truncated, records_skipped, total_chars FROM get_agent_turn_context($1)`
- Result has `content` with turn reminder text
- Turn reminders block present in `appendSystemContext` with header `📌 **Per-Turn Reminders:**`

### TC-028: Turn reminders cache — no DB query within TTL
**Preconditions:** Cache populated for `"nova"` (timestamp = now)
**Input:** Two calls to `before_prompt_build` within 5 minutes
**Expected:**
- First call: DB query executes (`queryTurnContext` called)
- Second call within TTL: Cache hit, `queryTurnContext` NOT called
- Log reflects cache hit (or absence of "querying DB" log on second call)

### TC-029: Turn reminders cache TTL expiry — stale data refreshed
**Preconditions:** Cache entry for `"nova"` with timestamp = (now - 6 minutes) → stale
**Input:** `before_prompt_build` call
**Expected:**
- Cache miss detected: `Date.now() - cached.timestamp >= CACHE_TTL_MS (300000)`
- DB query executes to refresh cache
- New data populates cache with updated timestamp
- Fresh content returned

### TC-030: Turn reminders DB query failure — graceful degradation
**Preconditions:** PostgreSQL unavailable or function `get_agent_turn_context` throws
**Input:** `queryTurnContext("nova")` rejects
**Expected:**
- `try/catch` in the turn reminders subsystem catches the error
- Error logged: `"[turn-context] Turn reminders error: ..."` or similar
- `before_prompt_build` continues; other subsystems still run
- `appendSystemContext` returned without turn reminders block (or with only remaining subsystem results)

### TC-031: Turn context truncated — warning logged, truncation notice injected
**Preconditions:** `get_agent_turn_context` returns `{ content: "...", truncated: true, records_skipped: 2, total_chars: 2500 }`
**Expected:**
- `console.warn` fired: `"[turn-context] WARNING: turn context truncated for agent 'nova' — 2 record(s) skipped, 2500 chars exceeded 2000 budget"`
- Truncation notice appended to turn reminders content: `"⚠️ Turn context truncated — some critical rules may be missing."`

### TC-032: Turn reminders empty for agent — no reminders block injected
**Preconditions:** `get_agent_turn_context('gem')` returns `{ content: "", truncated: false, records_skipped: 0, total_chars: 0 }`
**Expected:**
- No `📌 **Per-Turn Reminders:**` block in `appendSystemContext`
- No empty string injected
- Other subsystems still run normally

---

## Test Area 8: Shared pg.Pool

### TC-033: `pg-pool.ts` pool is a singleton — reused across subsystems
**Preconditions:** Plugin loaded; both turn-reminders and entity-resolver subsystems active
**Input:** Single `before_prompt_build` invocation that triggers both DB-using subsystems
**Expected:**
- Only one `pg.Pool` instance created (singleton from `shared/pg-pool.ts`)
- Both subsystems share the same pool — verified by checking pool reference equality or connection count
- No "too many connections" error from creating duplicate pools

### TC-034: Pool connection failure — both DB subsystems degrade gracefully
**Preconditions:** PostgreSQL is unreachable; pool connection times out
**Input:** `before_prompt_build` triggers turn reminders (DB) and entity resolution (DB)
**Expected:**
- Both subsystems catch their connection errors independently
- Neither subsystem crashes the plugin handler
- `appendSystemContext` returned with recall-only context (or empty if all subsystems fail)
- Pool remains usable after transient failure (does not permanently poison the singleton)

---

## Test Area 9: Partial Results

### TC-035: One subsystem fails, others still inject
**Preconditions:** Turn reminders DB is down; entity resolution and recall succeed
**Input:** `before_prompt_build`
**Expected:**
- Turn reminders block absent
- Entity block present
- Recall block present
- `appendSystemContext` contains partial results from the two healthy subsystems
- No error thrown to the host

### TC-036: Two subsystems fail, one succeeds
**Preconditions:** Entity resolution returns null (no match); recall times out; only turn reminders succeed
**Expected:**
- `appendSystemContext` contains only turn reminders block
- Function still returns `{ appendSystemContext: "..." }` (non-empty result)

### TC-037: All three subsystems return nothing — no `appendSystemContext`
**Preconditions:**
- Turn reminders: `content = ""`
- Entity resolution: no entity found
- Recall: `memories = []`
**Expected:**
- Handler does NOT return `{ appendSystemContext: "" }` (empty string injection avoided)
- Handler returns `{}` or `undefined` (no-op for the prompt builder)
- Verify: `appendSystemContext` key absent from return value OR value is falsy/undefined

---

## Test Area 10: Integration — Context Lands in LLM

### TC-038: End-to-end — injected context visible in LLM call
**Preconditions:** Full stack running; plugin installed; known entity in DB; turn reminders populated
**Input:** Discord message from known user triggers a full agent run
**Steps:**
1. `message_received` fires → sender cached
2. `before_prompt_build` fires → all three subsystems return data
3. Plugin returns `{ appendSystemContext: "..." }`
4. Agent LLM call proceeds
**Expected:**
- LLM system prompt contains the `appendSystemContext` value
- LLM response demonstrates awareness of injected context (e.g., uses entity name correctly)
- No event-loop freeze or timeout

### TC-039: Plugin hook timeout (8s) — host does not hang
**Preconditions:** All subsystems somehow slow; `before_prompt_build` approaches the per-handler timeout
**Input:** Simulate slow subsystems taking ~7.9s total
**Expected:**
- Handler completes or is killed at 8s by the host
- Host does not hang waiting indefinitely
- LLM call proceeds (possibly with partial or no context)
- System remains responsive to other incoming messages

---

## Test Area 11: Nova-Openclaw Cleanup

### TC-040: `src/hooks/message-hooks.ts` removed from nova-openclaw fork
**Preconditions:** nova-openclaw issue #182 branch
**Input:** `git diff main -- src/hooks/message-hooks.ts`
**Expected:**
- File is deleted (not modified, not moved)
- No references to the old hook registration remain in other files (verify with `grep -r "message-hooks" src/`)
- Build passes without the file

### TC-041: Fork no longer diverges from upstream on hook registration
**Preconditions:** `message-hooks.ts` removed (TC-040)
**Input:** `git diff upstream/main...HEAD -- src/` (fork diff against upstream)
**Expected:**
- The only remaining fork diverges are intentional (e.g., NOVA-specific config, not hook registration)
- No dead `registerHook("message:received", ...)` calls remain in the fork

### TC-042: nova-openclaw issue #40 resolved — old `agent-turn-context` hook no longer installed
**Preconditions:** New plugin deployed; old hook uninstalled
**Input:** `openclaw plugins list` and `openclaw hooks list`
**Expected:**
- `agent-turn-context` does NOT appear in active hooks
- `memory/turn-context` plugin DOES appear as installed and active
- No duplicate context injection (turn reminders not injected twice)

### TC-043: nova-openclaw issue #41 resolved — old `semantic-recall` hook no longer installed
**Preconditions:** New plugin deployed; old hook uninstalled
**Input:** `openclaw plugins list` and `openclaw hooks list`
**Expected:**
- `semantic-recall` does NOT appear in active hooks
- No duplicate recall injection in the system prompt
- Entity resolution runs only once per turn (from the new plugin, not duplicated by old hook)

---

## Test Area 12: Sender Cache Management

### TC-047: Sender cache bounded — oldest entries evicted at capacity
**Preconditions:** Sender cache has reached max capacity (e.g., 1000 entries)
**Input:** New `message_received` event arrives for a session key not yet in cache
**Expected:**
- New entry is added to the cache
- Oldest entry (by insertion/update time) is evicted to make room
- Cache size does not exceed the configured maximum (e.g., 1000)
- No crash or degraded performance from unbounded growth
- Verify with: `senderCache.size <= MAX_SENDER_CACHE_SIZE`

### TC-048: Sender cache entry staleness — entries expire after inactivity TTL
**Preconditions:** Sender cache has an entry for `"session:discord:old-session"` with timestamp = (now - 35 minutes)
**Input:** `before_prompt_build` fires for `"session:discord:old-session"`
**Expected:**
- Stale cache entries (>30 min since last `message_received` update) are treated as expired
- Entity resolution and semantic recall skip or re-derive sender info if the cache entry is stale
- Stale entries are lazily cleaned up (either on read or via periodic sweep)
- Prevents stale sender identity from being injected after a different user takes over a session

**Implementation note:** The `senderCache` is a `Map<string, SenderInfo>` with a `timestamp` field on each entry. Both max-size eviction and TTL-based staleness should be implemented.

---

## Test Area 13: Regression

### TC-049: Turn context injection works across providers (Discord, Signal, Telegram)
**Preconditions:** Known entities in DB for each provider
**Input:** Three separate messages, one per provider, each from a known entity
**Expected:**
- For each: `message_received` caches correct sender with correct provider
- For each: `before_prompt_build` resolves correct entity and injects correct context
- No cross-provider contamination between session caches

### TC-050: Heartbeat/cron turns — plugin does not crash when no `senderId` available
**Preconditions:** Cron-triggered agent run; no user message; no sender cache
**Input:** `before_prompt_build` on a cron session (`sessionKey = "session:cron:..."`)
**Steps:** Only turn reminders subsystem runs; entity and recall subsystems skip gracefully
**Expected:**
- No crash
- `appendSystemContext` contains turn reminders only (or empty result)
- Cron turn completes normally

### TC-051: Per-handler timeout config — override respected
**Preconditions:** Handler registered with `timeoutMs: 8000`
**Input:** `before_prompt_build` hook registration config
**Expected:**
- OpenClaw host uses 8s per-handler timeout (not the default 15s) for this plugin's `before_prompt_build` handler
- `timeoutMs: 8000` is visible in the plugin registration metadata

---

## Pass/Fail Criteria

| # | Criterion | Gate |
|---|---|---|
| 1 | Plugin installs and loads without errors | ✅ Required |
| 2 | Both hooks register correctly (`message_received`, `before_prompt_build`) | ✅ Required |
| 3 | `before_prompt_build` result reaches LLM system prompt | ✅ Required |
| 4 | Each subsystem fails independently without crashing the plugin | ✅ Required |
| 5 | No `event.messages.push()` calls anywhere in the new plugin | ✅ Required |
| 6 | No `spawnSync` usage in the new plugin | ✅ Required |
| 7 | `message-hooks.ts` deleted from nova-openclaw fork | ✅ Required |
| 8 | Old hooks (`semantic-recall`, `agent-turn-context`) no longer active after migration | ✅ Required |
| 9 | `pg.Pool` singleton shared across subsystems | ⚠️ Recommended |
| 10 | Content truncated to ≤2000 chars before recall query | ✅ Required |
| 11 | Cache TTL refresh verified (TC-029) | ⚠️ Recommended |
| 12 | No empty `appendSystemContext` when all subsystems return nothing | ✅ Required |
| 13 | Sender cache bounded — does not grow without limit (TC-047) | ✅ Required |
| 14 | Sender cache entries expire after inactivity TTL (TC-048) | ⚠️ Recommended |

**Quality gate:** All ✅ Required criteria must pass before PR approval. ⚠️ Recommended items should pass; failures require documented justification.
