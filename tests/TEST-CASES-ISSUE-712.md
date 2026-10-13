# Test Cases — nova-mind#712 (Chunk A: turn-context sender resolution, #697/#361 classifier degradation, #709 installer permission)

**SE run #1231, step 3 — QA test-case design (Chunk A)**
**Author:** Gem (QA Lead)
**Scope:** nova-mind #712, #697, #361, #709 — Chunk A of tracking issue #715. Chunks B–D (sessions/transcripts,
heartbeat/motivation, config sync) are designed separately later in this run.

---

## 0. Pinned source artifacts (do not use live/hot-fixed checkouts)

- **nova-mind:** fresh clone `~/repos/se1231-nova-mind`, branch `fix/se1231-openclaw-2026.9-regressions`,
  pinned at `git rev-parse HEAD` = `12ecc0b3409a03a1195a923a71d6018d76f72c53` (verified at design time; matches
  `origin/main` 12ecc0b per #715 step-2 comment). Clean working tree (no untracked/modified files) confirmed before
  analysis.
- **OpenClaw host behavior reference:** `/home/nova/nova-openclaw-production` at `6ced19b` (2026.9.6) — production
  install, read-only reference for host hook contracts. NOT used as the artifact under test; used only to establish
  ground truth for what the host actually passes into plugin hooks.
- **Plugin under test:** `memory/plugins/turn-context/` in the pinned nova-mind clone — `src/index.ts`,
  `src/classifier.ts`, `src/entity-resolver.ts`, `src/semantic-recall.ts`, `openclaw.plugin.json`,
  `package.json`.
- **Installer under test (#709):** `agent-install.sh` in the pinned clone, turn-context block
  (~line 1931–2005) and the `install_metacognition_plugin()` helper (~line 2060–2090) used for comparison.

---

## 1. Host-contract answer (REQUIRED — decides whether #712 can drop the cache entirely)

**Answer: (2) — `before_prompt_build` DOES receive `senderId`, `channel`, and `chatId` on 2026.9.6, but they
arrive on the `ctx` (second) parameter, not on the `event` (first) parameter. Message text for semantic recall
is also available on the event, via `currentUserMessage` (and the raw `prompt`). This means #712 can drop the
`message_received` → `before_prompt_build` cross-hook cache entirely for identity — no `(channel, chatId)`-keyed
fallback cache is structurally required for identity resolution. A fallback cache is still warranted defensively for
the case where `ctx.senderId`/`ctx.channel`/`ctx.chatId` are absent (older harness, non-channel run, or a future
host regression) — see TC-712-014.**

Citations (production fork, `6ced19b`, read-only reference — not the artifact under test):

- `src/plugins/hook-before-agent-start.types.ts:22-28` — `PluginHookBeforePromptBuildEvent` is
  `{ prompt: string; currentUserMessage?: string; currentUserMessageId?: string; messages: unknown[] }`. **No**
  `senderId`, `channel`, or `chatId` field exists on the event itself.
- `src/plugins/hook-types.ts:1063` — the `before_prompt_build` entry in `PluginHookHandlerMap` is typed
  `(event: PluginHookBeforePromptBuildEvent, ctx: PluginHookAgentContext) => ...` — confirms `ctx` is
  `PluginHookAgentContext`, not a hook-specific context type.
- `src/plugins/hook-types.ts:319` (`channel?: string`), `:323` (`chatId?: string`), `:325` (`senderId?: string`),
  `:327` (`channelId?: string` — mirrors `chatId` for compatibility), `:345` (`channelContext?:
  PluginHookChannelContext` — richer per-channel sender/chat detail) — all on `PluginHookAgentContext`, all
  **optional**, documented as populated "for channel-originated runs."

**Critical finding that reframes #712's root cause:** the plugin's OWN local type stub for its hook context
(`memory/plugins/turn-context/src/index.ts:655-662`, `interface PluginContext`) declares only `sessionKey?`,
`agentId?`, `messageProvider?`, `accountId?` — it does **not** declare `senderId`, `channel`, or `chatId` at
all, and `before_prompt_build`'s handler (`index.ts:269-584`) never reads `ctx.senderId`/`ctx.channel`/
`ctx.chatId`. The plugin relies exclusively on the `sessionKey`-keyed `senderCache` populated by the
fire-and-forget `message_received` hook (`index.ts:42-81`, `185-247`), which is exactly the mechanism #712's own
evidence shows failing 100% of the time on both reproduction gateways. The fix path is not "patch the cache
key" — it is "stop depending on the cache for identity at all, since the host already hands identity to
`before_prompt_build` directly." Test cases below are written against this target design, with the current
cache-miss behavior retained as an explicit regression baseline (TC-712-001/002).

---

## 2. Adversarial/config-seam coverage index (required by workflow step 3 rules)

| Requirement | Satisfied by |
|---|---|
| Wrong-type/malformed value at a config seam | TC-712-009 (chatId as number), TC-712-010 (senderId undefined), TC-712-011 (empty-string chatId), TC-709-007 (`allowConversationAccess` as string `"true"`) |
| Non-identity fixture values (never 0/empty defaults) | TC-697-006 (similarity exactly at `HIGH_CONFIDENCE_THRESHOLD` boundary, not 0 or 1), TC-712-016 (non-empty, multi-entry `senderCache` under concurrency, not an empty map) |
| Config→runtime seam populated by production code, not hand-constructed | TC-709-008, TC-INT-001 |
| INTENT-level check vs. a live source system (not spec-vs-spec) | TC-712-003 (identity match verified against the live `entity_resolver` identifier scheme in `extractIdentifiers()`, not a hand-asserted mapping table) |
| Source-artifact pinning verified before analysis | §0 above; `git rev-parse HEAD` checked at design time |

---

## 3. #712 — Sender resolution with no cross-hook cache (14 test cases: TC-712-001 … TC-712-014, plus 2 concurrency cases 015–016)

### TC-712-001 — Regression baseline: current cache-miss reproduces on the pinned ref
**Priority:** P1 (Critical) — characterizes the bug being fixed; must FAIL (cache miss) on unpatched 12ecc0b and PASS (no miss / no cache dependency) once #712 lands.
**Preconditions:** Pinned clone at 12ecc0b, plugin loaded in a staging gateway, `allowConversationAccess` already fixed per #709.
**Steps:** Send one inbound channel message. Capture `before_prompt_build` log output.
**Expected (pre-fix):** Log line `Sender cache MISS (no cached sender info)` on the first turn of a session, matching #712's own evidence (newhart: MISS=7/7 turns since restart; nova: MISS=203/204).
**Expected (post-fix):** No "Sender cache" log line should ever be a precondition for entity resolution succeeding — `entity-resolver` must reach a `no entity`/`entityId=N` decision using `ctx`-sourced identity regardless of cache state.

### TC-712-002 — Entity resolution succeeds on literally the first turn of a new session (no warm-up turn required)
**Priority:** P1 (Critical)
**Preconditions:** Brand-new session, no prior `message_received` event has ever fired for this `sessionKey`.
**Steps:** Send one inbound message as a sender with a known entity record. Inspect `before_prompt_build` output.
**Expected:** `entityId` resolves on turn 1. This is the direct fix verification for #712 — today this requires turn 2+ at best (and per the evidence, never resolves even then).

### TC-712-003 — Identity resolves from ANY identifier, including the channel sender_id (Discord 330189773371080716 → entity_id 2)
**Priority:** P1 (Critical) — INTENT-level check against the live identifier scheme, not a hand-asserted mapping.
**Preconditions:** A live (or faithfully mirrored) `entity_resolver` record maps Discord ID `330189773371080716` → entity 2. Verify this against the actual `extractIdentifiers()` mapping (`entity-resolver.ts:222-224`: `case "discord": return { discordId: senderId }`) and the live entity table — do not assert the mapping only against a test's own fixture.
**Steps:** Send an inbound Discord message with `senderId="330189773371080716"`. Inspect resolved entity.
**Expected:** `resolveEntityContext` returns `entityId=2`. Also verify the inverse: a non-Discord provider with the same numeric string as `senderId` must NOT resolve to entity 2 (identifier namespacing by provider, per `extractIdentifiers`'s switch statement — proves the match is provider-scoped, not a bare string match).

### TC-712-004 — Semantic recall actually runs for a real content-bearing message
**Priority:** P1 (Critical)
**Preconditions:** `prompt_helper_config.semantic_recall=true` for the resolved message type; `proactive-recall.py` reachable.
**Steps:** Send a message with content likely to match stored memories. Inspect `before_prompt_build` DONE log.
**Expected:** `runSemanticRecall` is invoked (not skipped as "no content"); `recall=fulfilled(Nchars)` with N>0 in the structured log line (`index.ts:510-511`); the returned text is present in `prependSystemContext`.

### TC-712-005 — Semantic recall results are actually injected into the prompt, not just logged
**Priority:** P1 (Critical) — closes the "extraction works, nothing comes back into prompts" gap from #712's evidence.
**Preconditions:** Same as TC-712-004.
**Steps:** Capture the full `PromptBuildResult` returned by the hook (not just the log line).
**Expected:** `result.prependSystemContext` (or `prependContext` under `turn-prepend` placement, `index.ts:611-632`) contains the `🧠 **Relevant Context:**` block from `semantic-recall.ts:162`. Assert on the returned object, since the log line alone cannot prove injection (a bug could log success and still drop the segment during `buildPromptResult`).

### TC-712-006 — `senderId` is `undefined` → logged warning, before_prompt_build still completes, no crash
**Priority:** P1 (Critical) — adversarial malformed-input case, REQUIRED by step-3 rules.
**Preconditions:** Construct a `ctx` where `senderId` is omitted entirely (not populated by the host — e.g., a non-channel/cron-triggered run).
**Steps:** Invoke `before_prompt_build` with this `ctx`.
**Expected:** A logged warning identifying the missing field (not a generic catch-all); hook resolves to `undefined`/a valid `PromptBuildResult` (possibly empty, e.g. only turn-reminders); no unhandled exception; no silent `return` that produces neither a log line nor a result (step-3 rule: "Never a silent return").

### TC-712-007 — `chatId` is a number instead of a string → no crash, no silent return, logged warning
**Priority:** P1 (Critical) — adversarial wrong-type case, REQUIRED by step-3 rules (mirrors the exact class of bug SE#499/TC-522-028 found: a host field of the wrong type escaping a sync-throw path).
**Preconditions:** Construct `ctx.chatId = 123456789` (number) instead of a string — plausible if a channel adapter passes a native numeric ID (e.g., Telegram chat IDs are numeric) without stringifying it upstream of the hook.
**Steps:** Invoke `before_prompt_build`/the sender-identity resolution path with this `ctx`.
**Expected:** The resolution path performs its own type check before using `chatId` as a cache/map key or string-concatenation operand (e.g. template literal coercion of a number is silently "valid" JS but produces wrong cache keys if ever mixed with string-typed chatIds for the same chat — assert the implementation normalizes/validates type, not that it merely "doesn't throw"). A logged warning is emitted identifying the type mismatch. No synchronous throw escapes the hook handler (would take down the whole `before_prompt_build` dispatch for every plugin, per the SE#499 pattern).

### TC-712-008 — `senderId` is a number instead of a string → no crash, logged warning, entity resolution degrades gracefully
**Priority:** P1 (Critical) — adversarial wrong-type case.
**Preconditions:** `ctx.senderId = 330189773371080716` (number, not string) — plausible since Discord snowflakes are numeric at the API layer before channel-adapter stringification.
**Steps:** Invoke entity resolution with this `ctx`.
**Expected:** `extractIdentifiers()`/the ctx-based identity path explicitly coerces or rejects non-string `senderId` (today's `extractIdentifiers(provider, senderId, ...)` at `entity-resolver.ts:214` types `senderId: string | undefined` — a number silently satisfies JS at runtime but breaks the downstream `discordId: senderId` assignment's implicit string contract against the DB column). Must not crash; must log a warning distinguishing "wrong type" from "missing."

### TC-712-009 — `chatId` is an empty string → treated as absent, not as a valid (but empty) identity key
**Priority:** P1 (Critical) — adversarial boundary/malformed case.
**Preconditions:** `ctx.chatId = ""`.
**Steps:** Invoke the resolution path.
**Expected:** Empty-string `chatId` is NOT used as a cache key or identity discriminator (an empty string is falsy-adjacent but `!== undefined`, a classic "wrong-type/malformed value" class bug — naive `??`-based fallback chains do not catch this). Logged warning. No crash. Falls back to the next available identity source or degrades to "no entity" cleanly.

### TC-712-010 — All three identity fields (`senderId`, `channel`, `chatId`) absent simultaneously
**Priority:** P2 (High) — compound malformed-input case.
**Preconditions:** `ctx` has none of the three fields (fully non-channel-originated run, e.g. a cron/heartbeat-triggered `before_prompt_build`).
**Steps:** Invoke the hook.
**Expected:** One consolidated logged warning (not three redundant ones per missing field, to avoid log-spam on every heartbeat turn); hook still returns turn-reminders content if applicable (turn-reminders is "ALWAYS fires," `index.ts:456-463`); entity/recall sections are cleanly omitted, never throw.

### TC-712-011 — Malformed `ctx` never produces a silent return (explicit negative-space test)
**Priority:** P1 (Critical) — directly enforces the step-3 rule "Never a silent return."
**Preconditions:** Each of TC-712-006 through TC-712-010's malformed `ctx` shapes.
**Steps:** For each, assert on BOTH the log output and the return value in the same test run.
**Expected:** Every malformed-input case produces at least one `console.warn`/`console.error` call AND a defined (possibly empty-content) `PromptBuildResult` or explicit `undefined` with an accompanying "DONE ... no context to inject" log line (`index.ts:562-568`) — never a code path that returns without executing any logging statement first.

### TC-712-012 — `messages` array is empty but `currentUserMessage` is populated
**Priority:** P2 (High) — exercises the actual event-shape contract from §1, since `event.messages` is the historical-session-messages array, not the current turn's text.
**Preconditions:** `event = { prompt: "...", currentUserMessage: "hello", messages: [] }`.
**Steps:** Invoke the hook.
**Expected:** Semantic recall and classification use `event.currentUserMessage` (or `event.prompt`) for content, NOT `event.messages` — confirms the fix reads the correct field per the real `PluginHookBeforePromptBuildEvent` shape (§1), not a field that happens to exist on some other hook's event type.

### TC-712-013 — `currentUserMessage` is undefined but `prompt` is populated (legacy/omission case)
**Priority:** P2 (High) — per the production type's own doc comment: "Empty means no textual request; omission is legacy."
**Steps:** Invoke with `currentUserMessage` omitted, `prompt` populated.
**Expected:** Falls back to `event.prompt` for recall/classification content rather than treating the turn as content-less.

### TC-712-014 — Defensive fallback path when `ctx` identity fields are absent on a channel-originated run
**Priority:** P2 (High) — covers the brief's "(channel, chatId)-keyed fallback" contingency even though §1 shows it's not structurally required for the common case.
**Preconditions:** Simulate a host/harness variant where `ctx.senderId` is absent but `ctx.channel`/`ctx.chatId` ARE present (e.g., a hypothetical older or divergent harness).
**Steps:** Invoke the hook.
**Expected:** If a fallback cache is implemented, it is keyed by `(channel, chatId)` tuple — never by `sessionKey` alone (the exact defect class #712 is fixing) and never by `chatId` alone (collides across channels with numeric chat IDs, e.g. Telegram vs. a hypothetical future channel reusing the same numeric space).

### TC-712-015 — Concurrency: two interleaved sessions from different senders never cross-attribute identity
**Priority:** P1 (Critical) — REQUIRED by dispatch brief.
**Preconditions:** Two sessions/sessionKeys, two distinct senders (e.g., Discord users A and B), both resolve to distinct entities.
**Steps:** Fire `before_prompt_build` for session A and session B with overlapping/interleaved `await` timing (e.g., start A's entity resolution, before it resolves start B's, let both settle out of order).
**Expected:** A's turn injects only A's entity/recall content; B's turn injects only B's. No shared mutable module-level state (e.g., a single in-flight promise or scratch variable keyed by nothing) leaks A's resolved entity into B's result. This directly targets the removal of the current single `senderCache` Map's failure mode — a per-`sessionKey`-and-`senderId` keyed structure (mirroring `entity-resolver.ts`'s existing `${sessionKey}:${senderId}` cache key convention at line 413) must be the only shared state, if any is used at all.

### TC-712-016 — Concurrency: group channel session shared by two senders attributes correctly within one sessionKey
**Priority:** P1 (Critical) — regression guard for the bug #150 already fixed once (cache keyed by sessionKey alone caused User B to see User A's cached entity, `entity-resolver.ts:328-332`); must not be reintroduced by #712's fix.
**Preconditions:** One group `sessionKey` (contains `:channel:` or `:group:`, `index.ts:163-166`), two distinct senders post consecutively, interleaved if possible.
**Steps:** Sender A posts, then sender B posts (same sessionKey) before A's turn fully completes.
**Expected:** Each turn's injected entity context matches the posting sender of THAT turn, never the other sender's — non-identity fixture requirement satisfied by using two senders with genuinely different, non-trivial entity facts (not two blank/empty-fact entities, which would make a cross-attribution bug invisible).

---

## 4. #697 / #361 — Classifier model missing, Ollama timeout/unreachable, or garbage response (10 test cases: TC-697-001 … TC-697-006, TC-361-001 … TC-361-004)

### TC-697-001 — Configured classifier model is not installed in Ollama (404) → logged once per distinct failure, not silently swallowed
**Priority:** P1 (Critical) — direct repro of #697: `OLLAMA_CLASSIFY_MODEL` defaults to `phi4-mini:latest` (`classifier.ts:33-34`), which is not installed; every call 404s.
**Preconditions:** Ollama reachable, but the configured model does not exist.
**Steps:** Send a message ambiguous enough to require the Ollama fallback (fails `classifyByRules`, `classifier.ts:88-140`).
**Expected:** `callOllamaClassify` rejects (its `res.on('end')` handler attempts `JSON.parse` on an Ollama error-shaped body and/or Ollama returns a non-200 that still resolves `res`, so the 404 body is parsed as `ollamaResp.response`). The catch in `classifyMessage` (`classifier.ts:262-267`) logs `"[turn-context] Classifier Ollama fallback failed:"` with a message that distinguishes a 404/model-not-found condition from a timeout — **today it does not**: both collapse into the same generic warning text. This test should FAIL today and is the acceptance test for #697's "log loudly, distinctly" fix.
**Must also assert:** the turn still gets `before_prompt_build` output (classification degrades to `type=conversation method=default`, `classifier.ts:267`, NOT a hook failure) — context injection for entity/recall must not depend on classifier success.

### TC-697-002 — Ollama unreachable (connection refused) → distinct logged reason, turn still injected
**Priority:** P1 (Critical)
**Preconditions:** `OLLAMA_BASE_URL` points at a closed port / Ollama process stopped.
**Steps:** Send an ambiguous message.
**Expected:** `req.on('error')` fires (`classifier.ts:225-228`), rejects with a connection-refused `Error`; `classifyMessage`'s catch logs it; classification defaults to `conversation/default`; entity resolution and semantic recall still run and inject normally (they do not depend on `classification.type` except for domain hints and `prompt_helper_config` gating, which falls back safely — `index.ts:337-349`).

### TC-697-003 — Ollama returns 200 with a non-JSON body ("garbage") → parse-error path, distinctly logged, safe default
**Priority:** P1 (Critical) — adversarial malformed-response case, not covered by #697/#361's own repro notes.
**Preconditions:** Mock/stub Ollama to return `200` with body `not json at all`.
**Steps:** Send an ambiguous message.
**Expected:** `JSON.parse(data)` throws inside the `res.on('end')` handler (`classifier.ts:200`); caught and rejected as `"Ollama classify parse error: ..."` (`classifier.ts:219-221`) — a THIRD distinct failure mode from 404/timeout/connection-refused. Verify the top-level `classifyMessage` warning text actually differs for this case (today it won't — all three funnel into the same `"[turn-context] Classifier Ollama fallback failed:"` prefix with only the inner `Error.message` varying, which is not "logged loudly" per #697's own recommended fix #3).

### TC-697-004 — Ollama returns valid JSON wrapper but `response` field contains a non-JSON or wrong-shaped string
**Priority:** P2 (High) — nested-garbage case: outer Ollama envelope is valid, inner model output is not.
**Preconditions:** Ollama responds `{"response": "I cannot classify this."}` (plain prose, not the requested JSON object).
**Steps:** Send an ambiguous message.
**Expected:** Inner `JSON.parse(respText)` throws (`classifier.ts:202`), same parse-error path as TC-697-003. Confirms the failure mode is reached via the realistic "model ignored format=json" path, not only via a fully malformed outer response.

### TC-697-005 — Ollama returns valid JSON with an invalid `type` enum value → falls back to `"conversation"`, not a crash
**Priority:** P2 (High) — adversarial but spec-conformant-looking input (tests the `validTypes.includes()` guard, `classifier.ts:203-212`).
**Preconditions:** Ollama responds `{"type": "urgent_escalation", "domainHints": ["x"]}` — plausible hallucinated category outside the 5 allowed types.
**Steps:** Send an ambiguous message.
**Expected:** `type` coerces to `"conversation"` per the `includes()` fallback; `domainHints` is still honored if it's a valid string array (classifier.ts:213-217); `method: "ollama"` is still reported (this is a successful call, just with a corrected category) — assert this is logged/attributed differently from a true failure (method=ollama vs. method=default), since conflating "model answered with a bad value" and "model didn't answer at all" would hide a real quality regression from observability.

### TC-697-006 — Similarity/confidence values at non-identity boundary values (NOT 0 or 1)
**Priority:** P1 (Critical) — REQUIRED non-identity-fixture adversarial case (lesson 787 pattern): using `similarity=0` or `1` as fixtures would make an off-by-one in the `>=` boundary comparison invisible.
**Preconditions:** Recall memory fixtures with `similarity` values of exactly `0.7` (the `HIGH_CONFIDENCE_THRESHOLD` default, `semantic-recall.ts:52-54`), `0.699999`, and `0.700001`.
**Steps:** Run `runSemanticRecall` formatting over these three fixtures.
**Expected:** `0.7` and `0.700001` render the 🎯 high-confidence indicator (`>=`, `semantic-recall.ts:149`); `0.699999` renders 📝. Confirms the boundary operator is `>=` not `>`, using fixtures that would actually fail if the operator were flipped — a `similarity=0`-only fixture set could not detect this.

### TC-361-001 — Classifier call times out (model not resident, cold-load exceeds 2000ms) → logged, 2s+ latency tax measured and reported
**Priority:** P1 (Critical) — direct repro of #361.
**Preconditions:** Classifier model not kept warm in Ollama (`keep_alive` not pinned); triggers cold load.
**Steps:** Send an ambiguous message; measure `before_prompt_build` total duration.
**Expected:** `setTimeout` fires at `OLLAMA_TIMEOUT_MS=2000` (`classifier.ts:35,174-177`), `req.destroy()` is called, rejects with `"Ollama classify timeout after 2000ms"`; `classifyMessage`'s catch logs it and returns `conversation/default`; total hook latency reflects the ~2.3s tax (matches #361's own gateway.log evidence: `elapsed=2317ms`, `DONE in 2390ms`). This test's PASS criterion for the fix is that the tax is either eliminated (e.g., a fast `/api/ps` precheck per #361's option 3) or explicitly bounded and reported — not that the symptom disappears unverified.

### TC-361-002 — Precheck/skip-when-cold path (if implemented) does not itself add latency on the happy path (warm model)
**Priority:** P2 (High) — guards against trading one latency bug for another.
**Preconditions:** Classifier model IS resident (warm).
**Steps:** Send an ambiguous message.
**Expected:** Total classify latency stays low (comparable to a successful `/api/generate` round-trip, not 2000ms+); any precheck adds negligible overhead.

### TC-361-003 — Timed-out request's socket is actually destroyed, not leaked
**Priority:** P2 (High) — resource-leak regression guard for the existing `req.destroy()` call (`classifier.ts:175`).
**Steps:** Trigger N consecutive timeouts (N≥20) in one process lifetime; inspect open socket/file-descriptor count.
**Expected:** No monotonic growth in open sockets attributable to the classifier path.

### TC-361-004 — Timeout and 404/model-missing (#697) are distinguishable in logs within the same session
**Priority:** P1 (Critical) — cross-issue integration: #697 and #361 are two DIFFERENT root causes (model missing vs. model not warm) that currently produce the SAME generic log line. Both must become distinguishable, or the "logged reason" requirement (dispatch brief) is not actually met.
**Preconditions:** Run TC-697-001's repro and TC-361-001's repro in the same test session.
**Steps:** Diff the two logged warning strings.
**Expected:** The two warnings differ in a way an operator can act on without reading source (e.g., "model not found" vs. "timed out — model may be cold"), not just in the generic Node error message that happens to differ by failure type.

---

## 5. #709 — Installer `allowConversationAccess` wiring, idempotent merge, config validation (8 test cases: TC-709-001 … TC-709-008)

### TC-709-001 — Fresh install: `plugins.entries.turn-context.hooks.allowConversationAccess` is `true` after `agent-install.sh` runs
**Priority:** P1 (Critical) — direct acceptance test for #709.
**Preconditions:** No prior `openclaw.json` `plugins.entries.turn-context` block (fresh install), staging host.
**Steps:** Run the installer's turn-context block. Inspect `openclaw.json`.
**Expected:** `.plugins.entries."turn-context".hooks.allowConversationAccess === true`.
**Current-code warning (must FAIL today, is the acceptance test for the fix):** the pinned clone's turn-context jq
block (`agent-install.sh`, turn-context section, `.plugins.entries."turn-context" = {"enabled": true}`) sets
ONLY `enabled`, with no `hooks` key at all — unlike the sibling `install_metacognition_plugin()` helper used for
`self-awareness`/`confidence-check`, which merges in `hooks: { allowConversationAccess: true }`. This test must
fail against the pinned 12ecc0b ref and is expected to pass once #709 adds the missing merge to turn-context's own
block.

### TC-709-002 — Existing config with unrelated turn-context keys (e.g. custom `placement`) is preserved, not overwritten
**Priority:** P1 (Critical) — REQUIRED "existing config is merged idempotently" case, and directly targets a second defect found during this design pass: the current turn-context jq block uses a plain `=` assignment (`.plugins.entries."turn-context" = {"enabled": true}`), NOT the `(... // {}) * {...}` recursive-merge pattern the metacognition helper uses. A plain assignment silently DESTROYS any previously-set `hooks`/`placement`/other keys on re-install.
**Preconditions:** `openclaw.json` pre-seeded with `plugins.entries.turn-context = { enabled: true, config: { placement: "turn-prepend" }, hooks: { allowConversationAccess: true } }` before running the installer again.
**Steps:** Re-run the installer's turn-context block.
**Expected:** Post-run, `config.placement` is still `"turn-prepend"` and `hooks.allowConversationAccess` is still `true` — nothing is dropped. This test must FAIL against the pinned 12ecc0b ref (current block overwrites the whole object) and is a required regression guard for the #709 fix, which must switch to a merge, not just add a new key via assignment.

### TC-709-003 — Idempotent re-run with no pre-existing turn-context block is a no-op beyond setting the flag (run twice, diff)
**Priority:** P1 (Critical)
**Steps:** Run installer twice in a row on a fresh config.
**Expected:** Second run produces an identical `openclaw.json` (or a semantically identical one — key order aside) to the first; no duplicate array entries in `plugins.load.paths` (the existing `unique` filter at `agent-install.sh` line ~1990 already guards this for the paths array — confirm it still holds after the fix).

### TC-709-004 — `openclaw config validate` (or equivalent) passes after the installer writes the permission
**Priority:** P1 (Critical) — REQUIRED by #709's own acceptance criteria and the dispatch brief.
**Preconditions:** Fresh install completed (TC-709-001).
**Steps:** Run the host's config validation command against the resulting `openclaw.json` on the staging 2026.9.6 host.
**Expected:** Exit 0 / no validation errors referencing `plugins.entries.turn-context` or `hooks.allowConversationAccess`.

### TC-709-005 — `jq` absent on the target host → installer warns and does not silently skip the permission forever
**Priority:** P2 (High) — adversarial environment case; the existing code already gates on `command -v jq`.
**Preconditions:** `jq` not installed.
**Steps:** Run the installer.
**Expected:** The existing `${WARNING} Could not enable plugin in config`-style message fires (matches current code's `||` fallback branch); installer does not report success for this step; a human-actionable follow-up (manual edit instructions, or a hard failure if `allowConversationAccess` is load-bearing for the plugin to function at all) is surfaced rather than a clean exit implying the plugin is fully configured.

### TC-709-006 — Target `openclaw.json` is malformed JSON before install
**Priority:** P2 (High) — adversarial malformed-config-seam case.
**Preconditions:** `openclaw.json` contains a trailing comma or other syntax error.
**Steps:** Run the installer's turn-context config block.
**Expected:** `jq` fails fast on the malformed input; the installer's existing `&&`-chained `mv` is never reached (so the original malformed file is not silently replaced by a half-written one); a clear failure is reported, not a silent skip.

### TC-709-007 — `allowConversationAccess` set as the string `"true"` instead of boolean `true` (pre-existing or operator-edited config)
**Priority:** P1 (Critical) — adversarial wrong-type config-seam case, REQUIRED by step-3 rules.
**Preconditions:** `openclaw.json` pre-seeded with `hooks: { allowConversationAccess: "true" }` (string).
**Steps:** Run `openclaw config validate` and/or the host's own permission-gate check that decides whether `before_prompt_build` is allowed to run for this plugin.
**Expected:** Either the host's schema validation rejects the string value with an actionable error (preferred), or — if the host coerces truthy strings — this is explicitly documented and tested as intentional, not left as an unverified assumption. This is the exact class of bug SE#499/TC-522-028 found (a host config field of the wrong type escaping validation and reaching a sync-throw path at runtime instead).

### TC-709-008 — Config→runtime seam: the ACTUAL installer-written config is what gates the live hook, not a hand-built test fixture
**Priority:** P1 (Critical) — REQUIRED "config→runtime seam populated by production code" case (lesson 811 / pattern TC-522-036).
**Preconditions:** Run the real `agent-install.sh` turn-context block against a staging `openclaw.json`, producing a real on-disk config file.
**Steps:** Start the staging gateway against THAT installer-produced config (not a hand-written JSON fixture asserting `allowConversationAccess: true`). Send one inbound message.
**Expected:** `before_prompt_build` actually executes for turn-context (proven by its log lines appearing), demonstrating the permission the installer wrote is the SAME permission the host's hook-dispatch gate reads — closes the gap between "the installer wrote the right JSON" (testable in isolation, and already the failure mode of a spec-vs-spec test) and "the host actually honors that JSON for this plugin." This is the one test in this section that must run against a live/staging gateway process, not just `jq`-level JSON assertions.

---

## 6. Integration (staging 2026.9.6, real channel turn) — 1 test case: TC-INT-001

### TC-INT-001 — One real channel turn on staging shows entity facts + recall memories injected, with a log line proving it
**Priority:** P1 (Critical) — REQUIRED by dispatch brief; this is the end-to-end seam test tying #712/#697/#361/#709 together and doubles as the config→runtime seam case for the whole chunk.
**Preconditions:** Staging host rebuilt per workflow 34 (fresh install, not a hot-patched live checkout), OpenClaw 2026.9.6, nova-mind built from the pinned fix branch, turn-context plugin installed via the (fixed) `agent-install.sh`, `openclaw config validate` passing (TC-709-004), a known sender with an existing entity record and at least one semantically-matchable stored memory.
**Steps:**
1. Send one real inbound message on a real channel (e.g., Discord) from the known sender, with content that should trigger both entity resolution and semantic recall.
2. Capture gateway logs for the full `before_prompt_build` lifecycle for that turn.
3. Capture the actual prompt sent to the model (or the plugin's returned `PromptBuildResult`, whichever is externally observable on staging).
**Expected:**
- Log line `[turn-context] Sender cache HIT` is NOT a precondition for success (per §1's fix — may be absent entirely if the cache is removed).
- Log line `[turn-context] entity-resolver: entityId=N elapsed=Xms` (N = the known sender's real entity id).
- Log line `[turn-context] Semantic recall found K memories ... tier=...` with K≥1.
- Log line `[turn-context] before_prompt_build DONE in Xms — ... injecting prepend=Ychars ...` with Y>0.
- The injected prompt block actually contains both the `👤 **Talking with:**` entity segment and the `🧠 **Relevant Context:**` recall segment (not just the log claiming so — matches TC-712-005's "assert on the object, not the log" principle, applied here to the live prompt).
- This is the single test case in the whole suite that is NOT run against hand-constructed fixtures anywhere in its chain — sender, entity, memory, config, and hook dispatch are all the real production path.

---

## 7. Open questions for the orchestrator / Project Leadership review

1. **#709's second defect (plain-overwrite vs. merge, TC-709-002) was not mentioned in the issue or its fix options.**
   Confirming it's in scope for the same PR as the `allowConversationAccess` fix (both live in the same jq block),
   rather than requiring a separate issue.
2. **#697 and #361 are currently indistinguishable in logs (TC-361-004).** The dispatch brief asks for "a logged
   reason" for each; confirming whether the fix is expected to add distinct error-classification (404 vs. timeout vs.
   connection-refused vs. parse-error) in this same PR, or whether a single improved-but-still-generic log message
   satisfies the acceptance bar for Chunk A.
3. **TC-712-014's defensive `(channel, chatId)` fallback** is speculative — the host contract in §1 shows it is not
   needed for the documented 2026.9.6 behavior. Confirming whether to keep it as a "defense in depth" test or drop it
   as out-of-scope speculation about harnesses that don't currently exist.
4. **TC-709-008 and TC-INT-001 both require a live/staging gateway**, not just unit-level assertions. Confirming
   staging availability and the workflow-34 rebuild window for whoever implements/runs these.
5. No design concerns about the pinned refs — `git rev-parse HEAD` matches `12ecc0b` exactly, working tree is clean,
   and the OpenClaw fork production host-contract reference matches the step-2 comment's pinned `6ced19b`.
