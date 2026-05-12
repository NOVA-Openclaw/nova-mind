# Phase 1 Code Review — Issue #182: Turn Context Plugin
**Reviewer:** Gem (QA Lead)
**Branch:** `feature/issue-182-turn-context-plugin`
**Date:** 2026-05-11
**Commit reviewed:** a0b071a (fix: Revise turn-context plugin per Step 2/4 review (#182))
**Test cases reference:** `tests/TEST-CASES-ISSUE-182.md` (51 test cases)

---

## Summary Table

| TC | Area | Status | Notes |
|----|------|--------|-------|
| TC-001 | Plugin Registration | ✅ PASS | Both hooks registered via api.on(); before_prompt_build has timeoutMs:8000; message_received returns void |
| TC-002 | Plugin Registration | ⚠️ PARTIAL | Manifest fields correct; main=./src/index.ts; hooks match. Gap: index.ts exports plain `export default function register(api)` — not wrapped in `definePluginEntry()`. Runtime compatibility depends on loader accepting module.default(api). |
| TC-003 | Plugin Registration | ⚠️ PARTIAL | package.json valid. `build` script runs `tsc --noEmit` (typecheck only, no compiled output). If loader requires pre-compiled JS at dist/, this will fail at install time. |
| TC-004 | Sender Cache | ✅ PASS | senderId extracted from event.senderId first, then metadata. senderCache.set() called correctly. All fields cached. |
| TC-005 | Sender Cache | ✅ PASS | Map.set() overwrites existing key for same sessionKey. No duplication. |
| TC-006 | Sender Cache | ✅ PASS | Module-level Map singleton. Independent keys per sessionKey. No cross-contamination. |
| TC-007 | Sender Cache | ❌ FAIL | Event has no senderId at any path → senderId=undefined → `if (!senderId) return` fires early → NO cache entry created. TC-007 expects cache entry with undefined fields. Actual: no entry written. |
| TC-008 | before_prompt_build Happy Path | ✅ PASS | Promise.allSettled runs all three subsystems. Returns {prependSystemContext, appendSystemContext}. Uses return (not event.messages.push()). timeoutMs:8000. |
| TC-009 | before_prompt_build Happy Path | 🔲 UNTESTABLE | Requires full gateway integration test; cannot verify composition order from code review. |
| TC-010 | Cache Miss — Cron/Heartbeat | ⚠️ PARTIAL | Entity/recall correctly skipped (no senderId, no cached content). Turn reminders run. prependSystemContext absent. Return is `{appendSystemContext: "..."}` or `{}`. Correct behavior. PARTIAL: `resolveEntityContext` is still called with null senderId but gracefully returns null immediately — minor unnecessary call but not broken. |
| TC-011 | Cache Miss Variants | ✅ PASS | senderId present but no senderName → extractIdentifiers still returns identifiers. Recall runs if cached.content truthy. No crash on absent senderName. |
| TC-012 | Entity Resolution — Discord | ✅ PASS | extractIdentifiers('discord', senderId) → {discordId: senderId}. resolveEntityByIdentifiers called. 👤 block formatted. |
| TC-013 | Entity Resolution — Signal | ✅ PASS | extractIdentifiers('signal', senderId, senderE164) → {signalUuid, phone}. Both identifiers included. |
| TC-014 | Entity Resolution — Telegram | ✅ PASS | extractIdentifiers('telegram', senderId) → {telegramId: senderId}. Correct switch case. |
| TC-015 | Entity Resolution — Slack | ✅ PASS | extractIdentifiers('slack', senderId) → {slackMemberId: senderId}. Correct switch case. |
| TC-016 | Unknown Provider | ✅ PASS | Returns {} → Object.keys check fails → console.log + return null. No crash. Graceful skip. |
| TC-017 | Entity Conflict | ✅ PASS | resolveResult.ok=false → console.error + return null. Entity block not injected. Other subsystems continue via Promise.allSettled. |
| TC-018 | Entity Found, No Facts | ✅ PASS | getEntityProfile returns {} → formatEntityContext still outputs `👤 **Talking with:** name`. No crash. |
| TC-019 | Entity Resolution Timeout | ✅ PASS | Promise.race with setTimeout(2000ms). Timeout → resolveResult=null → no entity block. Other subsystems continue. |
| TC-020 | Recall — Happy Path | ✅ PASS | Uses child_process.spawn (async). 5s internal timeout. JSON parsed. 🧠 header with memories. Logged correctly. |
| TC-021 | Recall Content Truncation | ✅ PASS | `input.content.substring(0, 2000)` before building stdinPayload. Content capped at 2000 chars. |
| TC-022 | Recall Timeout | ✅ PASS | setTimeout(SIGTERM, 5000ms). Rejects → caught in runSemanticRecall catch → returns null. Handler continues with other results. |
| TC-023 | Recall Script Not Found | ✅ PASS | spawn emits 'error' (ENOENT) → child.on('error') clears timer and rejects → caught → error logged → returns null. No crash. |
| TC-024 | Recall Non-Zero Exit | ✅ PASS | close event with code!=0 → else branch rejects with code+stderr. Caught → logged → returns null. |
| TC-025 | Recall Empty Memories | ✅ PASS | `result.memories.length === 0` → returns null → no 🧠 block. No empty header artifact. |
| TC-026 | Recall JSON Parse Failure | ✅ PASS | JSON.parse throws in spawnWithTimeout → rejects → caught in runSemanticRecall → logged → returns null. No crash. |
| TC-027 | Turn Reminders DB Query | ✅ PASS | queryTurnContext executes correct SQL. formatReminders builds `📌 **Per-Turn Reminders:**\n{content}`. Goes to appendSystemContext. |
| TC-028 | Turn Reminders Cache Hit | ✅ PASS | Cache hit when `Date.now() - cached.timestamp < CACHE_TTL_MS`. DB not queried on second call within TTL. |
| TC-029 | Turn Reminders Cache TTL Expiry | ✅ PASS | Stale entry (6min > 5min) → cache miss → queryTurnContext called → contextCache.set() with new timestamp. |
| TC-030 | Turn Reminders DB Failure | ✅ PASS | .catch() in before_prompt_build call to getTurnReminders → returns null. Promise.allSettled handles. appendSegments empty. No crash. |
| TC-031 | Turn Reminders Truncation Warning | ⚠️ PARTIAL | console.warn fires; truncation notice appended to content. Gap: warning message template is `"turn context truncated — N record(s) skipped, X chars exceeded budget"` — agent name is **not** included in the warning string. TC-031 expects `"for agent 'nova'"` in the warning. Minor deviation; functionality is correct, log clarity is reduced. |
| TC-032 | Turn Reminders Empty | ✅ PASS | `!entry.content` → formatReminders returns null → not added to appendSegments → no 📌 block. |
| TC-033 | pg.Pool Singleton | ✅ PASS | `if (!pool)` guard in getPool(). Single Pool instance returned for all callers. Both subsystems import from shared/pg-pool.ts. |
| TC-034 | pg.Pool Failure | ✅ PASS | Both subsystems have independent .catch() handlers. Promise.allSettled means one failure doesn't cancel others. Pool error event handled. |
| TC-035 | Partial Results — One Subsystem Fails | ✅ PASS | appendSegments empty if reminders fail; prependSegments populated from entity+recall. Returns {prependSystemContext: '...'}. |
| TC-036 | Partial Results — Two Subsystems Fail | ✅ PASS | prependSegments empty; appendSegments populated. Returns {appendSystemContext: '...'}. |
| TC-037 | Partial Results — All Subsystems Fail | ✅ PASS | result={}. Object.keys({}).length===0 → return undefined. Neither key present. No empty string injection. |
| TC-038 | Integration E2E | 🔲 UNTESTABLE | Requires full stack. Cannot verify from code review. |
| TC-039 | Plugin Timeout (Host) | 🔲 UNTESTABLE | Requires runtime simulation of slow subsystems. |
| TC-040 | nova-openclaw: message-hooks.ts removed | 🔲 UNTESTABLE | Different repo (nova-openclaw). Not reviewable from nova-mind source. |
| TC-041 | nova-openclaw: No old hook registrations | 🔲 UNTESTABLE | Different repo (nova-openclaw). |
| TC-042 | nova-openclaw: agent-turn-context gone | 🔲 UNTESTABLE | Requires deployment check on nova-openclaw fork. |
| TC-043 | nova-openclaw: semantic-recall gone | 🔲 UNTESTABLE | Requires deployment check on nova-openclaw fork. |
| TC-044 | Cache Write Synchronous (First Op) | ❌ FAIL | **CRITICAL.** The code comment says `CRITICAL: Cache write MUST be synchronous and FIRST` but the implementation places `evictOldestIfFull()`, `evictStaleCacheEntries()`, and four field extraction statements **before** `senderCache.set()`. Strictly, the cache write is not the first operation. The evict calls are synchronous and complete before any await, so there is no await-race. However, the eviction calls themselves involve iterating the entire Map — if `evictStaleCacheEntries()` were ever to be made async, this would become a race. More importantly, the TC-044 criterion is explicit and this is a Required gate item (criterion #17). See detailed findings below. |
| TC-045 | No `--stdin` Flag in Spawn Args | ✅ PASS | Args: `[RECALL_SCRIPT, '--max-tokens', ..., '--high-confidence', ...]`. No `--stdin` present. JSON written to stdin directly. |
| TC-046 | Recall JSON Payload Fields | ⚠️ PARTIAL | Payload includes content, senderId, senderName, provider. Gap: when sender fields are absent, the code sets `senderId: input.senderId ?? ''` — empty strings, not omitted fields. TC-046 states absent fields should be omitted from JSON (not set to null/empty unless intentional). Low severity but deviates from spec. |
| TC-047 | Cache Bounded (Max 1000) | ✅ PASS | CACHE_MAX_SIZE=1000. evictOldestIfFull() runs before set(). Finds oldest by timestamp scan, deletes it. Size never exceeds 1000. |
| TC-048 | Cache Staleness TTL | ⚠️ PARTIAL | CACHE_STALE_MS=30min defined. evictStaleCacheEntries() called in **message_received** (write path). Gap: **before_prompt_build** does NOT check entry timestamp before using cached data. If 35 minutes pass between message_received events (e.g., long cron gap then manual message), stale data is served on the read path. Stale entries are only swept on next message_received write. TC-048 expects stale entries to be "treated as expired" when before_prompt_build reads them. |
| TC-049 | Regression — Multi-Provider | 🔲 UNTESTABLE | Requires runtime with DB entities across all three providers. |
| TC-050 | Regression — Cron Turns | ✅ PASS | No senderId → entity/recall skipped. Turn reminders run. No crash. Matches TC-010 analysis. |
| TC-051 | Timeout Config | ✅ PASS | `api.on('before_prompt_build', handler, {timeoutMs: 8000})`. 8s timeout registered. |

---

## Status Counts

| Status | Count |
|--------|-------|
| ✅ PASS | 35 |
| ⚠️ PARTIAL | 7 |
| ❌ FAIL | 2 |
| 🔲 UNTESTABLE | 7 |
| **Total** | **51** |

---

## Detailed Findings

### ❌ TC-007: Sender Cache — No Entry for `senderId`-less Events

**Severity:** S3 Minor | **Priority:** P2 Next Sprint

**Location:** `src/index.ts`, `message_received` handler, lines checking `!senderId`.

**Expected:** Cache entry stored for heartbeat/cron events even when senderId is absent (fields stored as `undefined`).

**Actual:** The handler returns early with `if (!senderId) return` before any cache write. Sessions that trigger `message_received` without a `senderId` (e.g., internal heartbeat turns with `from: "internal:cron"`) get no cache entry. When `before_prompt_build` fires for these sessions, `senderCache.get(sessionKey)` correctly returns `undefined` (consistent with TC-010 behavior), but the test's explicit expectation of a stored partial entry is violated.

**Impact:** Functionally, TC-010 (heartbeat/cron in `before_prompt_build`) still works correctly because missing cache entry → subsystems gracefully skip. The FAIL is against TC-007's literal assertion of a stored partial entry.

**Recommendation:** For `sessionKey` to be useful even for cron/heartbeat sessions, the early-return guard could be relaxed: write a cache entry with available fields even when `senderId` is absent. Change `if (!senderId) return` to write a minimal entry before returning — or remove the guard and let the cache entry be written with `senderId: undefined`.

```typescript
// Proposed fix: write partial entry even without senderId
senderCache.set(sessionKey, {
  senderId: senderId ?? '',
  senderName: senderName ?? '',
  provider: provider ?? '',
  senderE164,
  content: content ?? '',
  timestamp: Date.now(),
});
// Then return if no senderId (no point running entity resolution)
if (!senderId) return;
```

---

### ❌ TC-044: Synchronous Cache Write — NOT the First Operation (REQUIRED Gate Item #17)

**Severity:** S2 Major (Required quality gate) | **Priority:** P1 Immediate

**Location:** `src/index.ts`, `message_received` handler body.

**Code comment says:**
```typescript
// CRITICAL: Cache write MUST be synchronous and FIRST.
// message_received is fire-and-forget — if an await precedes this,
// before_prompt_build may fire before the cache is populated.
```

**What the code actually does:**
```typescript
api.on("message_received", async (event, ctx) => {
  try {
    const sessionKey = ctx.sessionKey;
    if (!sessionKey) return;                    // statement 1 — guard
    const senderId = event.senderId ?? ...;     // statement 2 — extraction
    if (!senderId) return;                      // statement 3 — guard
    evictOldestIfFull();                        // statement 4 — eviction (sync)
    evictStaleCacheEntries();                   // statement 5 — eviction (sync, iterates Map)
    const senderName = ...;                     // statement 6 — extraction
    const provider = ...;                       // statement 7 — extraction
    const senderE164 = ...;                     // statement 8 — extraction
    const content = ...;                        // statement 9 — extraction
    senderCache.set(sessionKey, { ... });       // statement 10 — CACHE WRITE
  }
});
```

**Why this matters:** The eviction calls (`evictOldestIfFull`, `evictStaleCacheEntries`) are currently synchronous, so there is no actual `await`-race in the current implementation. However:

1. **The test criterion is explicit**: "senderCache.set() is the very first operation in the handler — no await precedes it." The current code has 9 statements before the cache write, violating the letter of the requirement.
2. **`evictStaleCacheEntries()` is O(n)**: At 1000 entries it iterates the entire Map. This could become non-trivial.
3. **Refactoring risk**: If either eviction function is ever made async (e.g., batch DB cleanup), this becomes a real race condition.

**Recommendation:** Move eviction calls AFTER the cache write, and move all field extraction above the cache write to be inlined:

```typescript
api.on("message_received", async (event, ctx) => {
  try {
    const sessionKey = ctx.sessionKey;
    if (!sessionKey) return;

    // Extract all fields synchronously
    const senderId = event.senderId ?? (event.metadata as any)?.senderId;
    const senderName = event.senderName ?? (event.metadata as any)?.senderName;
    const provider = ctx.messageProvider ?? (event.metadata as any)?.provider;
    const senderE164 = (event.metadata as any)?.senderE164;
    const content = event.content ?? '';

    // CACHE WRITE FIRST — before any eviction or other logic
    senderCache.set(sessionKey, {
      senderId: senderId ?? '',
      senderName: senderName ?? '',
      provider: provider ?? '',
      senderE164,
      content,
      timestamp: Date.now(),
    });

    // Eviction AFTER the write — order does not matter for correctness here
    evictOldestIfFull();
    evictStaleCacheEntries();
  } catch (err) { ... }
});
```

This strictly satisfies TC-044 and makes the code robust against future async refactoring.

---

### ⚠️ TC-002: `definePluginEntry` Wrapper Missing

**Severity:** S3 Minor | **Priority:** P2

**Location:** `src/index.ts`, export.

TC-001 specifies the plugin entry is produced by `definePluginEntry`. The manifest (`openclaw.plugin.json`) implies Plugin SDK usage, but `index.ts` exports a plain function:

```typescript
export default function register(api: PluginApi): void { ... }
```

If the OpenClaw plugin loader expects `module.default` to be the raw registration function (not a `definePluginEntry` wrapper), this is fine. If it expects `definePluginEntry(register)` or similar, the plugin will fail to load. This should be verified against the Plugin SDK docs/loader source. **Low risk if loader accepts plain `module.default(api)` pattern.**

---

### ⚠️ TC-003: No Compiled Output from Build Script

**Severity:** S3 Minor | **Priority:** P2

**Location:** `package.json`, `scripts.build`.

```json
"build": "tsc --noEmit"
```

`--noEmit` performs typecheck only. No compiled JS is produced. `openclaw.plugin.json` declares `main: "./src/index.ts"` (source, not dist). This works only if the OpenClaw plugin loader supports tsx/ts-node loading from source. If the loader requires a `dist/` artifact, installation will fail silently or loudly. Should be verified; if loader is ts-native, this is acceptable.

---

### ⚠️ TC-031: Agent Name Missing from Truncation Warning

**Severity:** S4 Cosmetic | **Priority:** P3

**Location:** `src/turn-reminders.ts`, `formatReminders()`.

Current warning:
```
[turn-context] WARNING: turn context truncated — 2 record(s) skipped, 2500 chars exceeded budget
```

Expected per TC-031:
```
[turn-context] WARNING: turn context truncated for agent 'nova' — 2 record(s) skipped, 2500 chars exceeded budget
```

The agent name is not included in the warning string. Operationally minor but makes debugging multi-agent setups harder.

---

### ⚠️ TC-046: Empty Strings vs. Omitted Fields in Recall JSON Payload

**Severity:** S4 Cosmetic | **Priority:** P3

**Location:** `src/semantic-recall.ts`, `runSemanticRecall()`.

When sender fields are absent, the code defaults to empty strings:
```typescript
senderId: input.senderId ?? '',
senderName: input.senderName ?? '',
```

TC-046 specifies absent fields should be omitted from JSON (not set to empty strings). The Python script's behavior with empty strings vs missing keys may differ. This is low risk if `proactive-recall.py` handles empty strings gracefully (likely it does), but deviates from the spec.

---

### ⚠️ TC-048: Staleness Not Checked on Cache Read (before_prompt_build)

**Severity:** S3 Minor | **Priority:** P2

**Location:** `src/index.ts`, `before_prompt_build` handler.

The staleness sweep (`evictStaleCacheEntries`) runs only in `message_received`. If 35+ minutes elapse between user messages (e.g., after a long gap), the next `before_prompt_build` call reads the stale entry without any timestamp check:

```typescript
const cached = sessionKey ? senderCache.get(sessionKey) : undefined;
```

No timestamp validation here. The stale identity data (potentially from a previous user who occupied the session) is passed to entity resolution. TC-048 requires stale entries to be "treated as expired" on read.

**Recommendation:** Add a staleness check in `before_prompt_build`:
```typescript
const raw = sessionKey ? senderCache.get(sessionKey) : undefined;
const cached = raw && (Date.now() - raw.timestamp < CACHE_STALE_MS) ? raw : undefined;
```

---

## Pass/Fail Criteria Assessment

| # | Criterion | Gate | Status |
|---|-----------|------|--------|
| 1 | Plugin installs and loads without errors | ✅ Required | ⚠️ PARTIAL (TC-002, TC-003 — depends on loader behavior) |
| 2 | Both hooks register correctly | ✅ Required | ✅ PASS |
| 3 | `before_prompt_build` result reaches LLM system prompt | ✅ Required | 🔲 UNTESTABLE (TC-009) |
| 4 | Each subsystem fails independently without crashing | ✅ Required | ✅ PASS |
| 5 | No `event.messages.push()` calls in new plugin | ✅ Required | ✅ PASS |
| 6 | No `spawnSync` usage in new plugin | ✅ Required | ✅ PASS |
| 7 | `message-hooks.ts` deleted from nova-openclaw fork | ✅ Required | 🔲 UNTESTABLE |
| 8 | Old hooks no longer active after migration | ✅ Required | 🔲 UNTESTABLE |
| 9 | `pg.Pool` singleton shared across subsystems | ⚠️ Recommended | ✅ PASS |
| 10 | Content truncated to ≤2000 chars before recall | ✅ Required | ✅ PASS |
| 11 | Cache TTL refresh verified | ⚠️ Recommended | ✅ PASS |
| 12 | No empty prependSystemContext/appendSystemContext when nothing returned | ✅ Required | ✅ PASS |
| 13 | Sender cache bounded (TC-047) | ✅ Required | ✅ PASS |
| 14 | Sender cache entries expire after inactivity TTL (TC-048) | ⚠️ Recommended | ⚠️ PARTIAL (read path not checked) |
| 15 | `prependSystemContext` for entity + recall | ✅ Required | ✅ PASS |
| 16 | `appendSystemContext` for turn reminders only | ✅ Required | ✅ PASS |
| 17 | Synchronous cache write is FIRST operation in message_received (TC-044) | ✅ Required | ❌ FAIL |
| 18 | No `--stdin` flag in proactive-recall.py spawn args (TC-045) | ✅ Required | ✅ PASS |

**Required criteria failed:** #17 (TC-044 — cache write order)

**Required criteria untestable (Phase 2):** #3, #7, #8 — these require runtime/deployment verification

---

## Final Verdict

### ❌ FAIL — Loop back to Step 5 for fixes before Phase 2 staging deployment

**Blocker (Required gate):**
- **TC-044 / Criterion #17**: The `senderCache.set()` call is not the first operation in the `message_received` handler. 9 statements precede it. While no actual `await` causes a race in the current code, this violates the explicit Required quality gate and the stated design intent. The fix is straightforward (see recommendation above).

**Non-blocking issues to address alongside the fix:**
- **TC-007**: Consider writing a partial cache entry for senderId-less events rather than early-returning. Not a required gate but affects TC-007 literal assertion.
- **TC-048**: Add a staleness timestamp check in `before_prompt_build` read path (⚠️ Recommended).
- **TC-031**: Add agent name to truncation warning string (cosmetic, P3).
- **TC-046**: Omit empty-string sender fields from recall JSON payload rather than serializing empty strings (cosmetic, P3).

**Overall code quality is high.** The architecture is sound, all three subsystems are correctly isolated, error handling is thorough, the singleton pool pattern is correct, and all critical functional behaviors (no spawnSync, no event.messages.push(), correct prompt segment placement, timeout guards) are properly implemented. The Required FAIL is a structural/ordering issue in the message_received handler, not a fundamental design flaw — a two-minute fix will resolve it.

Once the blocker fix is applied, Phase 2 (staging deployment + runtime validation of TC-009, TC-038, TC-039, TC-040–043) can proceed.

---

## Re-review — Phase 1 Fixes Verification

**Reviewer:** Gem (QA Lead)  
**Date:** 2026-05-11  
**Commit re-reviewed:** `198c4a8` (fix: Address Phase 1 QA findings (#182))  
**Scope:** Re-verification of previously failing/partial TCs only.

---

### TC-044 — Cache Write Synchronous (First Op) ✅ PASS

**Previous status:** ❌ FAIL (Required gate #17)

**Fix verified:**

The `message_received` handler body (lines 86–130, `index.ts`) now shows:

1. `const sessionKey = ctx.sessionKey;` — guard (no await, no side-effect)
2. `if (!sessionKey) return;` — early exit for keyless events
3. All five field extractions (senderId, senderName, provider, senderE164, content) — synchronous variable assignments, no awaits
4. **`senderCache.set(sessionKey, { ... });`** — **cache write**
5. `evictOldestIfFull();` — deferred
6. `evictStaleCacheEntries();` — deferred

The old `if (!senderId) return` guard that previously appeared between the sessionKey check and the cache write is **gone**. The eviction calls now appear **after** `senderCache.set()`. No `await` precedes the cache write. The comment was updated accordingly: `// CRITICAL: Cache write MUST happen before any await or async work.`

**Verdict:** ✅ PASS — Required gate #17 satisfied. The cache write is the first substantive state-mutating operation. Field extractions are synchronous assignments; evictions are deferred post-write. Race-condition risk eliminated.

---

### TC-007 — Sender Cache Entry for `senderId`-less Events ✅ PASS

**Previous status:** ❌ FAIL

**Fix verified:**

`grep -n "if (!senderId) return" index.ts` returns **no matches**. The early-return guard on absent senderId has been removed. The code now proceeds to `senderCache.set()` regardless of whether `senderId` is present, storing `senderId: senderId ?? ""` (empty string when absent).

A heartbeat/cron event with no senderId at any path will now produce a cache entry with `senderId: ""`, `senderName: ""`, `provider: ""`, `content: ""`. This satisfies TC-007's expectation that a cache entry is written even without a senderId.

**Note:** The stored value is `""` (empty string) rather than `undefined` for absent fields. The TC-007 spec says "fields stored as `undefined`". Empty string is functionally equivalent here — all downstream consumers either check truthiness (`if (cached.senderId)`) or pass through to the entity resolver which skips on falsy senderId. This is an acceptable implementation-level detail; the behavioral contract (cache entry present) is met.

**Verdict:** ✅ PASS

---

### TC-048 — Cache Staleness TTL on `before_prompt_build` Read Path ✅ PASS

**Previous status:** ⚠️ PARTIAL

**Fix verified:**

Line 153–154 of `index.ts`:
```typescript
const raw = sessionKey ? senderCache.get(sessionKey) : undefined;
const cached = raw && (Date.now() - raw.timestamp < CACHE_STALE_MS) ? raw : undefined;
```

This is exactly the pattern TC-048 requires. A cache entry older than `CACHE_STALE_MS` (30 minutes) now evaluates to `undefined` on the read path in `before_prompt_build`, even if the entry is still present in the Map (it will be swept on the next `message_received` call). Stale identity data will no longer be passed to entity resolution or recall when the read is stale.

**Verdict:** ✅ PASS

---

### TC-031 — Agent Name in Truncation Warning ✅ PASS

**Previous status:** ⚠️ PARTIAL

**Fix verified:**

`formatReminders()` in `turn-reminders.ts` now accepts `agentName: string` as a second parameter. Both call sites (`getTurnReminders` cache-hit and cache-miss paths) pass `agentName`. The warning string:
```typescript
`[turn-context] WARNING: turn context truncated for agent '${agentName}' — ` +
`${entry.recordsSkipped} record(s) skipped, ${entry.totalChars} chars exceeded budget`
```
includes the agent name as specified in TC-031.

**Verdict:** ✅ PASS

---

### TC-046 — Empty Sender Fields Omitted from Recall JSON Payload ✅ PASS

**Previous status:** ⚠️ PARTIAL

**Fix verified:**

`semantic-recall.ts` now builds the `stdinPayload` as a `Record<string, unknown>` and conditionally inserts fields:
```typescript
const stdinPayload: Record<string, unknown> = { content: messageText };
if (input.senderId) stdinPayload.senderId = input.senderId;
if (input.senderName) stdinPayload.senderName = input.senderName;
if (input.provider) stdinPayload.provider = input.provider;
// ... other fields similarly conditional
```
Absent/empty sender fields are omitted from the JSON payload rather than serialized as empty strings. The `JSON.stringify(stdinPayload)` call in `spawnWithTimeout()` correctly receives the object (not a pre-serialized string — this was also fixed in the diff; previously `stdinPayload` was `JSON.stringify(...)` and was written directly, now `JSON.stringify(stdinPayload)` is called in `spawnWithTimeout`).

**Verdict:** ✅ PASS

---

### TC-002 — `definePluginEntry` Wrapper ⚠️ PARTIAL (unchanged)

**Previous status:** ⚠️ PARTIAL

**Fix verified:** No change. `index.ts` still exports `export default function register(api: PluginApi): void { ... }` with no `definePluginEntry` wrapper. `openclaw.plugin.json` still declares `main: "./src/index.ts"`. No change to the plugin entry pattern.

This remains acceptable if the OpenClaw plugin loader invokes `module.default(api)` directly (which the presence of the `openclaw.extensions` field in `package.json` suggests). The risk is loader-compatibility — this will be verifiable in Phase 2 staging deployment. Not a blocker for Phase 2 entry.

**Verdict:** ⚠️ PARTIAL (no change; deferred to Phase 2 runtime verification)

---

### TC-003 — Build Script / Compiled Output ⚠️ PARTIAL (unchanged)

**Previous status:** ⚠️ PARTIAL

**Fix verified:** `package.json` still has `"build": "tsc --noEmit"`. The `openclaw.plugin.json` still lists `main: "./src/index.ts"` (source path). No change.

However, `package.json` now includes an `openclaw.runtimeExtensions` field pointing to `"./dist/index.js"`, alongside `openclaw.extensions: ["./src/index.ts"]`. This suggests the plugin system supports a dual-path: TypeScript source for development, compiled dist for production. Whether this loader distinction is respected at runtime is still a Phase 2 verification item.

**Verdict:** ⚠️ PARTIAL (no change; deferred to Phase 2 runtime verification)

---

### TC-010 — Unnecessary `resolveEntityContext` Call with Null senderId ⚠️ PARTIAL (no change)

**Previous status:** ⚠️ PARTIAL

**Fix verified:** `resolveEntityContext` is still called whenever `sessionKey` is truthy, regardless of whether `senderInfo.senderId` is present. The call is:
```typescript
sessionKey
  ? resolveEntityContext(sessionKey, senderInfo).catch(...)
  : Promise.resolve(null)
```

For cron/heartbeat events (no senderId), `senderInfo.senderId` will be `undefined` (since `cached?.senderId` is empty string from TC-007 fix, which is falsy). `resolveEntityContext` will still be called with an empty-string senderId, which is expected to return `null` gracefully inside that function. The unnecessary call is still present.

This was classified as a minor finding (PARTIAL, not FAIL) in Phase 1 and is not a quality gate item. It remains.

**Verdict:** ⚠️ PARTIAL (unchanged — acceptable, not a gate)

---

### Re-review Summary Table

| TC | Area | Previous | Re-review | Change |
|----|------|----------|-----------|--------|
| TC-044 | Cache Write Order (Required gate #17) | ❌ FAIL | ✅ PASS | **Fixed** |
| TC-007 | Sender Cache — Partial Entry | ❌ FAIL | ✅ PASS | **Fixed** |
| TC-048 | Staleness TTL on Read Path | ⚠️ PARTIAL | ✅ PASS | **Fixed** |
| TC-031 | Agent Name in Truncation Warning | ⚠️ PARTIAL | ✅ PASS | **Fixed** |
| TC-046 | Empty Fields Omitted from Recall Payload | ⚠️ PARTIAL | ✅ PASS | **Fixed** |
| TC-002 | `definePluginEntry` Wrapper | ⚠️ PARTIAL | ⚠️ PARTIAL | No change — Phase 2 |
| TC-003 | Build Script / Compiled Output | ⚠️ PARTIAL | ⚠️ PARTIAL | No change — Phase 2 |
| TC-010 | Unnecessary `resolveEntityContext` Call | ⚠️ PARTIAL | ⚠️ PARTIAL | No change — acceptable |

**Required gate failures resolved:** 1 of 1 (TC-044 / Criterion #17)

---

### Final Verdict — Phase 1 Re-review

## ✅ PASS — Proceed to Phase 2 (Staging Deployment)

All previously-failing Required gate items have been resolved. The two original ❌ FAILs (TC-044, TC-007) are now ✅ PASS. The three previously-partial items that were addressed (TC-048, TC-031, TC-046) are now ✅ PASS.

Remaining ⚠️ PARTIAL items (TC-002, TC-003, TC-010) are non-blocking: TC-002 and TC-003 require runtime/deployment verification (Phase 2 scope); TC-010 is cosmetic with no functional impact.

**Phase 2 entry criteria met.** The codebase is ready for staging deployment and runtime validation of: TC-009, TC-038, TC-039, TC-040 through TC-043, and the TC-002/TC-003 loader compatibility questions.
