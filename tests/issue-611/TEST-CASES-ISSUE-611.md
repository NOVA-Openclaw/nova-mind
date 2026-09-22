# Test Cases — Issue #611: Conversation-Context Window for Memory Extraction + Environment Field + Confidence Honesty

**QA Lead:** Gem | **SE Run:** #718, Step 3 | **Repo:** nova-mind
**Issue:** [nova-mind#611](https://github.com/NOVA-Openclaw/nova-mind/issues/611) — feat(extraction): pass recent conversation context to extractor + extract environment field for events
**Scope:**
- `memory/scripts/extract_memories.py` (extraction prompt/schema/storage)
- `~/.openclaw/hooks/memory-extract/handler.ts` (deployed) / `memory/hooks/memory-extract/handler.ts` (repo source) — per-turn context assembly
- `memory/scripts/memory-catchup.sh` + `memory/scripts/extraction-replay.sh` — batch/REM context assembly
- `memory/scripts/memory-extraction-config.json` — new `max_prior_messages` / enable-disable key(s)
- `database/schema.sql` — `events.environment` / `events_archive.environment` (already live, varchar(255) NULL)
- Precedent: `cognition/metacognition/confidence-check/src/index.ts` (`CONFIG.max_prior_messages = 10`, `messages.slice(-CONFIG.max_prior_messages)`, assistant-only filtering pattern in `extractContradictionContext()`)

**Do NOT implement code.** This document is the test-design deliverable for SE run #718, Step 3.

---

## Design Notes / Constraints Carried Forward From Issue + Comments

These are load-bearing. Every relevant test case below cites which constraint it verifies. Where the issue leaves an implementation detail open (exact wire format for passing context to `extract_memories.py`, exact config key names beyond `max_prior_messages`), tests are written against the **behavioral contract**, not a specific data shape — implementation may pick the shape, but must satisfy the assertions below. Flag any deviation from these assumptions back to QA for a doc update before sign-off.

1. **C1 — Scope is BOTH extraction paths.** Per-turn (`memory-extract` hook → `extract_memories.py`) AND daily/REM batch path (transcript-ingestion/nightly pipeline — in this repo that means `memory-catchup.sh` and/or `extraction-replay.sh`, whichever the implementation lands the batch context-assembly logic in). A fix that only touches one path is incomplete.
2. **C2 — Extract-current-only guardrail.** The ~10 prior messages are DISAMBIGUATION CONTEXT ONLY. Facts/entities/events must be extracted exclusively from the current/most-recent message. Context messages must NOT independently generate extractions in the same pass — this is the dedup/echo-amplification risk called out explicitly in the issue (see memory-duplication lessons).
3. **C3 — Shared config convention.** Config key name is `max_prior_messages` (matches `confidence-check`'s existing `CONFIG.max_prior_messages`), default value **10**, added to `memory-extraction-config.json`, and MUST be hot-reloadable (read fresh per event/invocation, no caching — same pattern as `extraction_timeout_ms` and `python_cmd` already in that file per `handler.ts`'s `loadExtractionTimeoutMs()` / `resolvePythonCmd()`).
4. **C4 — Enable/disable flag.** A config-driven toggle must allow disabling the context window entirely (falls back to today's single-message behavior). Name TBD by implementation (e.g. `context_window_enabled`); tests assert behavior under both states regardless of exact key name.
5. **C5 — Never leak context across channel/session boundaries.** Context messages must come from the SAME session/channel transcript as the current message. A batch/replay run must never assemble context from a different channel, DM thread, or private conversation than the one the current message belongs to — this is both a correctness requirement (C1's disambiguation intent) and a privacy requirement (private-channel content must not bleed into an extraction prompt for a different, less-private channel).
6. **C6 — Never hallucinate `environment`.** The `environment` field is inferred from message + context (host/system/environment, e.g. `nova-local`, `blockhenge-sarsen-2`, `external/world`) when reasonably inferable; otherwise it MUST be left NULL. It must never be fabricated to satisfy schema completeness pressure.
7. **C7 — Confidence honesty.** Short/ambiguous messages extracted WITHOUT usable context must not default to `confidence=1.0`. This is a change from today's prompt template, which currently hardcodes `"confidence": 1.0` in its TEMPLATE example — implementation must ensure the model isn't anchored into always emitting 1.0 regardless of actual disambiguation quality.
8. **C8 — Graceful degradation on context-fetch failure.** If the context-window mechanism itself fails (DB query error, transcript lookup timeout, malformed cache file, etc.), extraction MUST proceed as no-context (equivalent to C4 disabled) rather than blocking or dead-lettering the message. Context-fetch failure is not an extraction failure.
9. **C9 — Regression case is load-bearing.** The 2026-08-17 #blockhenge incident (event id=2303, manually corrected) is the acceptance-sketch scenario from the issue and MUST be replayed as an explicit regression test, not merely implied by generic context-assembly tests.
10. **C10 — `events.environment` / `events_archive.environment` already live.** Schema change shipped 2026-08-17 (varchar(255) NULL, both tables). No migration test needed here — only the extraction/storage code path that populates it.
11. **C11 — Existing precedent for the slice pattern.** `confidence-check`'s `extractContradictionContext()` uses `messages.slice(-CONFIG.max_prior_messages)` and filters by `role`. The new context-window helper should follow the same slicing/ordering convention (most recent N, chronological order preserved) so behavior is consistent and predictable across both consumers, per the issue's explicit ask to "consider extracting a shared helper."

---

## Functional Areas

| Group | Area | TCs |
|---|---|---|
| A | Context Window Assembly — Per-Turn Hook Path | TC-611-A1 – TC-611-A10 |
| B | Context Window Assembly — Batch/Replay Path | TC-611-B1 – TC-611-B8 |
| C | Extract-Current-Only Guardrail + Regression Case | TC-611-C1 – TC-611-C9 |
| D | Environment Field Extraction | TC-611-D1 – TC-611-D8 |
| E | Confidence Honesty | TC-611-E1 – TC-611-E6 |
| F | Error/Edge Cases & Privacy | TC-611-F1 – TC-611-F9 |

---

## Group A — Context Window Assembly: Per-Turn Hook Path

### TC-611-A1: Last N=10 messages from same session/channel passed to extractor (happy path)
- **Preconditions:** `memory-extract` hook deployed with context-window feature enabled (default config, `max_prior_messages=10`). A session/channel transcript exists (`channel_transcripts` rows, or hook-local buffer, whichever implementation uses) with ≥15 prior messages in the same `channelSessionId`/`session_key` as the incoming message.
- **Steps:** Trigger `message:received` with a well-formed current message in that session.
- **Inputs:** Current message text (≥10 chars, not a command/heartbeat); session with 15 prior messages available.
- **Expected:** Exactly the 10 most recent prior messages (by timestamp, same session/channel) are gathered and passed to `extract_memories.py` alongside the current message (via whichever wire format implementation chooses — stdin JSON field or CONTEXT prompt block). Current message is clearly distinguished from context messages in whatever is passed (e.g. a "CURRENT" marker/role, matching the `memory-catchup.sh` precedent's `[CURRENT USER MESSAGE - EXTRACT FROM THIS]` label convention).
- **Pass criteria:** Context payload contains exactly 10 messages, in chronological order, none of them the current message itself; current message is unambiguously marked as the extraction target.
- **Done when:** Assertion on the exact set/order of the 10 messages passed matches the 10 most-recent-before-current rows from the session.

### TC-611-A2: Fewer than 10 messages available (BVA)
- **Preconditions:** Session has only 4 prior messages before the current one.
- **Steps:** Trigger hook.
- **Expected:** All 4 available prior messages are passed as context (no padding, no error). No attempt to fetch messages that don't exist.
- **Pass criteria:** Context payload contains exactly 4 messages; extraction proceeds normally.
- **Done when:** No error/warning logged for "insufficient context" — this is a normal, expected case.

### TC-611-A3: Zero prior messages available (first message in session) — boundary
- **Preconditions:** Current message is the very first message in a brand-new session (no prior transcript rows).
- **Steps:** Trigger hook.
- **Expected:** Context payload is empty (empty array / absent CONTEXT block, per whatever "no context" looks like in the chosen wire format). Extraction proceeds as single-message extraction (equivalent to pre-#611 behavior for this one message).
- **Pass criteria:** No crash, no attempt to backfill from a different session; extraction result is produced normally without a context section, or with an explicit "no prior context" marker.
- **Done when:** Behavior is identical to disabling the context window entirely (C4) for this specific call — i.e., zero-context and disabled-context must degrade to the same code path.

### TC-611-A4: Config override of N (BVA: N=3)
- **Preconditions:** `memory-extraction-config.json` has `max_prior_messages: 3`. Session has ≥10 prior messages available.
- **Steps:** Trigger hook.
- **Expected:** Only the 3 most recent prior messages are passed as context, not the default 10.
- **Pass criteria:** Context payload length is exactly 3.
- **Done when:** Config value is honored precisely — no off-by-one, no silent fallback to the hardcoded default of 10.

### TC-611-A5: Config override of N (BVA: N=0)
- **Preconditions:** `max_prior_messages: 0` in config.
- **Steps:** Trigger hook with a session that has plenty of prior messages available.
- **Expected:** Zero context messages passed, regardless of how many exist. This is functionally equivalent to A5 acting as an alternate "disable" mechanism, and must not error.
- **Pass criteria:** Context payload is empty; extraction proceeds as single-message.
- **Done when:** N=0 is treated as a valid boundary value, not a config error.

### TC-611-A6: Config override of N (BVA: negative or non-numeric value)
- **Preconditions:** `max_prior_messages: -1` (or `"ten"`, or `null`) in config.
- **Steps:** Trigger hook.
- **Expected:** Invalid value is treated as absent (per the established pattern for other keys in this file, e.g. `extraction_timeout_ms`'s "non-positive/non-numeric treated as absent, fall through to default" rule) — falls back to the hardcoded default of 10. A single stderr/log warning is acceptable but must not crash the hook or block extraction.
- **Pass criteria:** Effective N used is 10 (the hardcoded default), not -1, `"ten"`, or `null`; extraction still completes.
- **Done when:** Same graceful-fallback contract as the existing `extraction_timeout_ms`/`python_cmd` keys is demonstrated for `max_prior_messages`.

### TC-611-A7: Hot-reload of N — no gateway/hook restart required
- **Preconditions:** Hook running with `max_prior_messages: 10`. Two messages will be sent in the same session, back to back.
- **Steps:** Trigger first message (context window = 10, verify via A1-style assertion). Edit `memory-extraction-config.json` to `max_prior_messages: 5` WITHOUT restarting anything. Trigger second message in the same session.
- **Expected:** Second invocation reads the updated value (5) with no restart — matching the existing hot-reload contract documented for `extraction_timeout_ms` (`loadExtractionTimeoutMs()`: "fresh `readFileSync` + `JSON.parse` on every hook invocation — there is no caching").
- **Pass criteria:** First call uses N=10, second call (same process, no restart) uses N=5.
- **Done when:** Config file mtime/content change between two consecutive hook invocations produces different N values without any process restart.

### TC-611-A8: Disable flag — context window fully off
- **Preconditions:** Config sets the enable/disable flag to disabled (exact key name per implementation, e.g. `context_window_enabled: false`).
- **Steps:** Trigger hook with a session that has ample prior messages.
- **Expected:** No context is gathered or passed at all — not even a DB/transcript lookup is attempted (performance consideration: disabling should skip the fetch, not fetch-then-discard). Extraction behaves exactly as it did pre-#611.
- **Pass criteria:** No context-window DB query/lookup call observed (assert via mock/spy or log absence); extraction prompt/payload contains no context section.
- **Done when:** Toggling the flag off is verified to skip the fetch step, not just the "use" step — this matters for cost/latency, not just correctness.

### TC-611-A9: Current message never appears inside its own context list
- **Preconditions:** Any session with ≥1 prior message.
- **Steps:** Trigger hook.
- **Expected:** The current message is excluded from the "prior messages" set even if a race condition or the same-transcript-persist-before-hook-fires timing (per `handler.ts`'s existing FK-recovery logic, which may persist the current message to `channel_transcripts` before or during extraction) would otherwise cause it to appear twice.
- **Pass criteria:** No duplicate of the current message's content/timestamp appears in the context array.
- **Done when:** Explicit dedup-by-identity (transcript id, or timestamp+content match) is confirmed between "current message" and "context list."

### TC-611-A10: Context assembly does not block or measurably delay extraction beyond existing timeout budget
- **Preconditions:** Session with 10 available prior messages; context-window enabled.
- **Steps:** Trigger hook; measure wall-clock time from hook invocation to child-process spawn.
- **Expected:** Context assembly (DB query or buffer read) completes well within the existing 90s outer timeout budget — this is an additive step, not a replacement, so it must not itself introduce timeout risk. No new blocking synchronous DB call that could hang indefinitely without its own timeout.
- **Pass criteria:** Context-fetch step has a bounded/timeout-guarded execution path (mirrors C8); total added latency is small relative to the LLM call itself.
- **Done when:** Either a timeout is explicitly enforced on the context-fetch query, or its query pattern (indexed lookup on session/channel + LIMIT N) is confirmed fast by design (no full-table scan).

---

## Group B — Context Window Assembly: Batch/Replay Path

### TC-611-B1: Same-transcript prior messages assembled correctly (batch path happy path)
- **Preconditions:** Whichever script owns batch context assembly (`memory-catchup.sh` and/or `extraction-replay.sh`, per implementation choice — see Design Note C1) is enhanced per #611. A transcript (JSONL session file or `channel_transcripts` rows, matching whichever source the implementation reads from) contains ≥10 messages before the target message, all in the same transcript/session.
- **Steps:** Run the batch/replay script against this transcript.
- **Expected:** The target message is fed to `extract_memories.py` together with its 10 most-recent same-transcript predecessors, using the same wire-format contract as the per-turn path (or an equivalent one — see A1).
- **Pass criteria:** Context set matches the 10 most recent same-transcript messages before the target; ordering is chronological (oldest first, target last), mirroring the existing `memory-catchup.sh` `add_to_cache_and_get_context()` labeling convention (`[USER]`/`[NOVA]` numbered entries followed by the `[CURRENT ... MESSAGE - EXTRACT FROM THIS]` label) if that pattern is retained, or an equivalent explicit "this is the extraction target" marker if the wire format changes.
- **Done when:** Batch-path context assembly produces the same shape/ordering contract verified in TC-611-A1 for the per-turn path — the two paths must be behaviorally consistent per C1/C11.

### TC-611-B2: Ordering is strictly chronological, not insertion/processing order
- **Preconditions:** A transcript where messages were ingested out of arrival order (e.g. late-arriving backfilled rows with earlier timestamps, or JSONL lines processed non-sequentially).
- **Steps:** Run batch/replay context assembly.
- **Expected:** Context messages are ordered by their actual conversational timestamp, not by database insertion order or file line order.
- **Pass criteria:** Assembled context list is timestamp-sorted ascending.
- **Done when:** A deliberately-scrambled-insertion-order fixture produces correctly time-ordered context.

### TC-611-B3: Transcript boundary — never leak context across channels (C5)
- **Preconditions:** Two distinct transcripts/sessions exist: Session X (channel A) and Session Y (channel B), both with recent activity, both belonging to the same or different senders.
- **Steps:** Run batch/replay context assembly for a target message in Session X.
- **Expected:** Context is drawn EXCLUSIVELY from Session X. No message from Session Y appears in the context set, even if Session Y's messages are more recent or topically related.
- **Pass criteria:** 100% of context messages have `session_id`/`channel_transcript_id` (or equivalent identifier) matching the target message's own session.
- **Done when:** A cross-session leak-detection assertion (context messages' session identifiers == target's session identifier, no exceptions) passes for a fixture engineered to make a leak easy to introduce (e.g. Session Y has a more recent timestamp than some of Session X's older messages).

### TC-611-B4: Transcript boundary — never leak context across DM threads within the same provider/session_key collision risk
- **Preconditions:** Two different external threads (e.g. two different Discord DM channels, or two different `external_thread_id` values under the same `session_key` prefix pattern) exist in the transcript store.
- **Steps:** Run batch/replay context assembly for a message in thread 1.
- **Expected:** Context does not include messages from thread 2, even if both threads share a coarse `session_key` or `external_chat_id` substring.
- **Pass criteria:** Context filter uses the full/precise transcript identifier (session id + thread id, not a fuzzy/prefix match).
- **Done when:** A fixture with similar-but-distinct thread identifiers demonstrates no cross-thread bleed.

### TC-611-B5: Batch path respects `max_prior_messages` config (shared with per-turn path)
- **Preconditions:** `memory-extraction-config.json` has `max_prior_messages: 4`.
- **Steps:** Run batch/replay context assembly against a transcript with ≥10 prior messages.
- **Expected:** Only 4 prior messages are assembled as context — same config key, same value, as verified for the per-turn path in TC-611-A4.
- **Pass criteria:** Context payload length is exactly 4.
- **Done when:** Both paths are confirmed to read the SAME config key/value at the SAME point in time (i.e., changing the config once affects both paths consistently — no separate/duplicated config parsing that could drift, addressing the "shared helper" ask in the issue).

### TC-611-B6: `extraction-replay.sh` dead-letter rows get context reconstructed from `channel_transcripts`, not from the dead-letter row's own stored body alone
- **Preconditions:** An `extraction_failures` row exists with a valid `channel_transcript_id` FK (not the body-fallback case). The referenced transcript has ≥10 prior messages in the same session.
- **Steps:** Run `extraction-replay.sh` to replay this row.
- **Expected:** Context is reconstructed by querying `channel_transcripts` for prior messages in the same `session_id` as the FK'd transcript row — not just resurrecting the single failed message in isolation (which would revert to pre-#611 no-context behavior for every replay).
- **Pass criteria:** Replayed extraction call includes a non-empty context payload when ≥1 prior same-session message exists.
- **Done when:** A replay of a dead-lettered message demonstrably includes conversational context, closing the gap where replay would otherwise silently skip the #611 improvement.

### TC-611-B7: `extraction-replay.sh` body-fallback rows (no transcript FK) degrade to no-context, not a crash
- **Preconditions:** An `extraction_failures` row has `channel_transcript_id IS NULL` and relies on the `content` body-fallback column (per the existing #485 compound-failure case, TC-B6 in TEST-CASES-ISSUE-485.md).
- **Steps:** Run `extraction-replay.sh` to replay this row.
- **Expected:** Since there is no transcript FK to look up neighboring messages from, context assembly cannot run — replay proceeds as single-message extraction (equivalent to A3/C8 degradation), not a failure.
- **Pass criteria:** Replay still succeeds (or fails for reasons unrelated to context assembly); no new error class introduced by the missing FK specifically for context purposes.
- **Done when:** This body-fallback replay path is confirmed NOT to regress relative to its pre-#611 behavior.

### TC-611-B8: Batch ingestion order does not double-count a message as both "current" and "its own context" across consecutive runs
- **Preconditions:** `memory-catchup.sh`-style rolling cache (or equivalent) processes message M1, then in a later invocation processes M2 (in the same session, M2 arrives after M1).
- **Steps:** Run the batch script twice in sequence (M1's run, then M2's run).
- **Expected:** When M2 is processed, M1 correctly appears as ONE prior-context entry (not duplicated, not omitted) — consistent with existing duplicate-detection logic in `memory-catchup.sh` (`is_dup` check against the last 5 cached messages) but now also verified against the new context-window assembly specifically.
- **Pass criteria:** M1 appears exactly once in M2's context list.
- **Done when:** Sequential batch runs across message boundaries produce a stable, non-duplicating rolling context window.

---

## Group C — Extract-Current-Only Guardrail + Regression Case

### TC-611-C1: Facts appearing ONLY in context messages are NOT extracted (baseline guardrail)
- **Preconditions:** Context window enabled, N≥3. Context messages contain a clear, extractable fact (e.g. "My favorite color is blue") that does NOT appear in the current message. Current message is topically unrelated (e.g. "ok sounds good").
- **Steps:** Trigger extraction with this context+current combination.
- **Expected:** No fact/entity/event referencing "favorite color" or "blue" appears in the extraction output. Only content attributable to the current message (if any) is extracted.
- **Pass criteria:** Extraction output's `facts`/`entities`/`events` arrays contain zero items whose `value`/`description` matches content unique to the context messages.
- **Done when:** A context-only fact is verifiably absent from the output across multiple message-content variations (not just one lucky case).

### TC-611-C2: Context messages do not generate duplicate/echo extractions when they overlap semantically with the current message
- **Preconditions:** Context contains a message expressing the same fact the current message restates (e.g. context: "I'm allergic to peanuts", current: "yeah my peanut allergy is still an issue"). This is the "echo-amplification" risk called out explicitly in the issue.
- **Steps:** Trigger extraction.
- **Expected:** At most ONE fact is extracted/stored for the peanut allergy (either a fresh fact or a reinforcement of an existing one via `store_or_reinforce_fact()`'s existing fuzzy-match dedup) — not two separate extractions (one "from" the context echo, one from the current message).
- **Pass criteria:** `extraction_count` increments by exactly 1 for this fact in this extraction pass (not 2); no duplicate row created.
- **Done when:** Semantic overlap between context and current message does not produce amplified/duplicated storage.

### TC-611-C3: Current message correctly disambiguated using context (positive case — the actual `nopassword`/sudoers value of context)
- **Preconditions:** Context messages establish: discussion of adding a `NOPASSWD` sudoers directive to NOVA's user on a new Blockhenge sarsen host. Current message: "nopassword was added to soudoers" (32 chars, note the typo "soudoers").
- **Steps:** Trigger extraction with this exact context+current combination (this is a precursor check to the full regression test in TC-611-C4 — isolates just the disambiguation behavior).
- **Expected:** The extracted event describes a NOPASSWD sudoers directive change on the correct host — NOT a phantom user named "nopassword." Context is used to correctly interpret "nopassword" as a mangled/shorthand reference to the NOPASSWD directive, not a username.
- **Pass criteria:** Extracted event `description` does NOT contain phrasing equivalent to "user nopassword was added" / "nopassword joined the sudoers group/list." It DOES reference NOPASSWD/sudoers/directive language consistent with the context.
- **Done when:** Model output is reviewed against both the "correct" and "incorrect (2026-08-17 original bug)" interpretations and clearly matches the correct one.

### TC-611-C4: FULL REGRESSION — 2026-08-17 #blockhenge sequence replay (issue's acceptance-sketch scenario, C9)
- **Preconditions:** Reconstruct (from event id=2303's manually-corrected record, or from the original #blockhenge channel transcript if still available) the exact message sequence: several prior messages discussing adding a NOPASSWD sudoers directive to NOVA's user on a new Blockhenge sarsen host, sender Zonkism, followed by the current message "nopassword was added to soudoers" (32 chars) in #blockhenge.
- **Steps:** Replay this exact sequence through the (fixed) extraction pipeline — per-turn path, batch/replay path, or both, per whichever is more direct to test given available fixtures.
- **Expected (all of the following, per the issue's Acceptance sketch):**
  1. The event produced is about a NOPASSWD sudoers directive on a sarsen host — NOT a user named "nopassword."
  2. `environment` is populated (e.g. something like `blockhenge-sarsen-2` or equivalent host identifier inferable from context) — NOT NULL.
  3. Context messages themselves generate NO new duplicate extractions in this pass (Zonkism's earlier messages about the sudoers setup don't spawn their own separate events/facts).
- **Pass criteria:** All 3 sub-expectations pass simultaneously in one replay run.
- **Done when:** This exact scenario, run end-to-end, no longer reproduces the original 2026-08-17 bug (phantom "nopassword" user event with NULL environment) and instead matches the corrected manual fix that was applied to event id=2303. This is the single most important test case in this document — it is the literal acceptance criterion from the issue.

### TC-611-C5: Guardrail holds even when context messages are from a different sender than the current message (multi-party channel)
- **Preconditions:** Group channel with 3 participants. Context messages include statements from Sender B and Sender C. Current message is from Sender A.
- **Steps:** Trigger extraction.
- **Expected:** Any facts extracted are correctly attributed via the current message's sender (Sender A) as source, per existing `resolve_source_entity_id()` behavior — context from B/C is used only for disambiguation, never as an independent extraction source in this pass.
- **Pass criteria:** No fact in the output has `source_entity_id` resolved to Sender B or C for this pass (their own messages get extracted in THEIR OWN respective passes, not retroactively here).
- **Done when:** Multi-party context does not cause cross-attribution errors or premature/duplicate extraction of other senders' statements.

### TC-611-C6: Guardrail holds when context messages are much longer/more detailed than the current message
- **Preconditions:** Context messages are long, fact-dense technical messages (e.g. a detailed sudoers config walkthrough). Current message is short ("done", "fixed", "yep").
- **Steps:** Trigger extraction.
- **Expected:** The short current message alone does not trigger extraction of the long context's facts just because the model has more "material" available in the prompt. If the current message truly contains no new extractable information given the context, an empty/near-empty result (`{}`) is an acceptable and CORRECT outcome — not a failure.
- **Pass criteria:** No fact/entity/event is extracted whose content is derived solely from context-message detail with no corresponding current-message referent.
- **Done when:** A "boring" current message with a rich context does not produce a rich extraction result.

### TC-611-C7: Guardrail — explicit prompt instruction present and testable
- **Preconditions:** Extraction prompt template (as built by `build_extraction_prompt()` or its #611-updated equivalent) is available for inspection.
- **Steps:** Inspect the prompt text sent to the LLM when context is present.
- **Expected:** The prompt contains an explicit, unambiguous instruction that context messages are for disambiguation only and must not themselves be extracted from (matching the issue's guardrail language).
- **Pass criteria:** A specific instruction string/section is present and readable in the assembled prompt (not merely implied structurally by ordering).
- **Done when:** Prompt-text inspection confirms the guardrail instruction exists as explicit natural-language guidance, not just structural hope.

### TC-611-C8: Context is present but current message has zero extractable content — no forced extraction
- **Preconditions:** Context establishes rich prior conversation. Current message: "ok" / "thanks" / an emoji-only message that would normally be filtered by `MIN_MESSAGE_LENGTH` upstream, OR a borderline ~10-11 char message with no substantive content.
- **Steps:** Trigger extraction (assuming it clears the `MIN_MESSAGE_LENGTH` gate).
- **Expected:** Extraction returns `{}` (or equivalent empty result) — context does not "fill in" for a substance-free current message.
- **Pass criteria:** No facts/entities/events/vocabulary in output.
- **Done when:** An acknowledgment-only current message with context present still yields an empty extraction, consistent with the existing "If the message contains NO extractable new information... return: {}" rule.

### TC-611-C9: Guardrail under N=0/disabled context — sanity check that guardrail logic doesn't accidentally depend on context being present
- **Preconditions:** Context window disabled (C4) or N=0 (A5).
- **Steps:** Trigger extraction with a message that would, if it had context, risk ambiguity (e.g. "nopassword was added to soudoers" with NO context at all).
- **Expected:** Extraction still runs (single-message mode) and does not crash or behave differently just because the context-related code path is bypassed. The model may reasonably produce a lower-confidence or more literal (and per C7's original bug, possibly still ambiguous) interpretation — that's expected/acceptable in no-context mode, this test is only checking for stability, not correctness of disambiguation (which requires context to fix, per the issue's premise).
- **Pass criteria:** No crash/exception; valid JSON extraction result returned (even if it's the "wrong" phantom-user interpretation — that's the argument FOR shipping #611, not a bug in this specific test).
- **Done when:** Disabled/zero-context runs remain stable and don't error out due to the guardrail-related code assuming context always exists.

---

## Group D — Environment Field Extraction

### TC-611-D1: Environment inferable from current message alone → populated
- **Preconditions:** Current message explicitly names a host/system (e.g. "I set up the NOPASSWD directive on nova-local").
- **Steps:** Trigger extraction, event is produced.
- **Expected:** `environment` field in the extracted event is populated with a value matching the named host/system (e.g. `nova-local`).
- **Pass criteria:** `events` array item has non-null `environment` matching the inferable value.
- **Done when:** Extraction schema/template includes `environment` as a documented field for `events`, and the value flows through to output.

### TC-611-D2: Environment inferable from context, not from current message alone → populated
- **Preconditions:** Context establishes the host (e.g. "blockhenge sarsen-2"). Current message references the action but not the host explicitly (e.g. "nopassword was added to soudoers").
- **Steps:** Trigger extraction with context present.
- **Expected:** `environment` is populated using the context-derived host information (e.g. `blockhenge-sarsen-2` or a reasonable normalized form).
- **Pass criteria:** `environment` is non-null and consistent with the context's stated host.
- **Done when:** This overlaps with TC-611-C4's sub-expectation #2 but is tested in isolation with a simpler fixture for clearer failure diagnosis.

### TC-611-D3: Environment NOT inferable → NULL (never hallucinated)
- **Preconditions:** Current message and context together give no indication of host/system/environment (e.g. "the meeting got moved to 3pm").
- **Steps:** Trigger extraction, assume an event is legitimately extracted (e.g. a scheduling event).
- **Expected:** `environment` is NULL/omitted — the model does not invent a plausible-sounding but fabricated environment value just because the field exists in the schema.
- **Pass criteria:** `environment` field is explicitly null (or absent, depending on the chosen "omit vs. null" convention — pick one and test consistently) — never a guessed/fabricated string.
- **Done when:** A battery of environment-agnostic event fixtures (scheduling, personal milestones, non-technical decisions) consistently produce NULL `environment`, with zero hallucination instances across the batch.
- **Note:** This is the highest-risk case for LLM over-eagerness (schema-completeness pressure) — recommend running this fixture set multiple times / across multiple model temperatures if feasible to check for flakiness, not just a single pass.

### TC-611-D4: Environment field flows through to `events` INSERT correctly
- **Preconditions:** Extraction produces an event with a populated `environment` value.
- **Steps:** Run the full `store_extracted()` path (or its #611-updated equivalent) against a test/staging database.
- **Expected:** The `events` table row for this event has its `environment` column populated with the extracted value (not silently dropped by the storage layer, which today has no `environment` handling at all in `store_extracted()`'s events-INSERT block).
- **Pass criteria:** `SELECT environment FROM events WHERE id = <new_id>` returns the expected value.
- **Done when:** The INSERT statement in the events-storage block explicitly includes the `environment` column (today's INSERT only includes `title, description, event_date, source`).

### TC-611-D5: Environment field flows through to `events_archive` on archival
- **Preconditions:** An event with a populated `environment` value exists in `events` and is subject to the existing archival process (whatever mechanism moves rows from `events` to `events_archive` — check for an existing archival script/cron/function).
- **Steps:** Trigger archival for this event.
- **Expected:** `events_archive.environment` is populated with the same value carried over from `events.environment` — not dropped/reset to NULL during archival.
- **Pass criteria:** Archived row's `environment` matches the pre-archival value.
- **Done when:** Whatever archival mechanism exists (INSERT...SELECT, function, trigger) is confirmed to include `environment` in its column list.
- **Note to implementer/reviewer:** If no archival mechanism currently exists for `events`→`events_archive` (i.e., the archive table exists but nothing populates it yet), this test case should be marked N/A with a note, not silently skipped — flag this ambiguity explicitly during test execution.

### TC-611-D6: Environment value normalization / no accidental duplication under minor phrasing variance (dedup consideration)
- **Preconditions:** Two separate extraction passes (different sessions/times) both describe events on "blockhenge sarsen-2" but phrase the host slightly differently ("blockhenge-sarsen-2" vs "the sarsen host on blockhenge" vs "sarsen-2").
- **Steps:** Trigger both extractions.
- **Expected:** This is primarily a documentation/inspection test — the issue does not mandate environment-value normalization, but this test verifies no crash/corruption occurs and documents actual behavior (values may legitimately differ; that's acceptable since `environment` isn't declared as a foreign-keyed/normalized field).
- **Pass criteria:** Both events store their respective `environment` string without error; no attempt to force-merge into a canonical value is required for this issue's scope (out of scope per the issue text — note as informational, not a hard pass/fail gate).
- **Done when:** Reviewer confirms this is explicitly out of scope and the behavior (storing free-text variants) is acceptable per the `varchar(255)` schema design (not a normalized/FK'd dimension).

### TC-611-D7: Environment extraction does not regress existing event extraction (BVA — event with no host info still stores correctly)
- **Preconditions:** A simple event extraction that predates #611's concerns (e.g. "had dinner with Sarah last night") — no environment concept applies at all.
- **Steps:** Trigger extraction and storage.
- **Expected:** Event stores correctly with `title`, `description`, `event_date`, `source` populated as before, `environment` NULL, no new errors introduced by the schema/prompt change.
- **Pass criteria:** Full event round-trip (extract → store → verify) succeeds identically to pre-#611 behavior except for the added (NULL) `environment` column.
- **Done when:** A basic regression pass on ordinary, non-technical event extraction shows zero behavioral change aside from the new nullable column.

### TC-611-D8: Environment value length boundary (BVA on varchar(255))
- **Preconditions:** Context/message content could plausibly cause the model to produce an unusually long environment description (e.g. a verbose multi-clause description instead of a short host identifier).
- **Steps:** Craft a fixture likely to elicit a long `environment` value (or directly test the storage layer with a synthetic >255-char value if the LLM itself can't reliably be coerced into producing one).
- **Expected:** Storage layer truncates or rejects gracefully — no unhandled DB error (`value too long for type character varying(255)`) propagating up and failing the whole extraction/storage pass.
- **Pass criteria:** Either (a) the value is truncated to 255 chars before INSERT, or (b) the field is validated/shortened at the prompt-instruction level (guidance to keep it a short identifier) with a defensive truncation as backstop — some explicit handling must exist, not a bare unhandled `psycopg2` error.
- **Done when:** A ≥256-char environment value fixture is confirmed to not crash the storage path.

---

## Group E — Confidence Honesty

### TC-611-E1: Short/ambiguous message with no usable context does not land at confidence=1.0
- **Preconditions:** Context window disabled/empty (no context available) OR context present but genuinely unhelpful for disambiguation. Current message is short and ambiguous (e.g. "nopassword was added to soudoers" with zero context, replicating the exact original-bug conditions).
- **Steps:** Trigger extraction.
- **Expected:** Any fact/entity extracted from this message carries a `confidence` value measurably below 1.0 (e.g. in the 0.4–0.7 range consistent with `confidence_helper.py`'s existing `trust_confidence` scale for non-owner/inferred sources, or an equivalent LLM-assigned lower score) — NOT the hardcoded 1.0 the current prompt TEMPLATE anchors on.
- **Pass criteria:** `confidence < 1.0` for any fact extracted under this ambiguous-no-context condition. (Note: today's prompt TEMPLATE literally shows `"confidence": 1.0` as its example value — this is a demonstrated anchoring risk that must be fixed as part of #611; a regression check that the TEMPLATE example itself no longer implies "always 1.0" is a reasonable implementation-level check too.)
- **Done when:** A battery of short/ambiguous no-context messages consistently produces sub-1.0 confidence scores, not just one lucky sample.

### TC-611-E2: Same message WITH usable context → higher confidence than without (comparative honesty check)
- **Preconditions:** Same ambiguous message ("nopassword was added to soudoers") run twice: once with the disambiguating sudoers/NOPASSWD context present, once without any context.
- **Steps:** Run both extractions; compare `confidence` values for the resulting fact/event.
- **Expected:** The with-context run produces a HIGHER (or equal) confidence score than the without-context run, reflecting genuinely improved disambiguation — not two arbitrary/unrelated confidence numbers.
- **Pass criteria:** `confidence_with_context >= confidence_without_context` for the semantically-equivalent extracted item across both runs.
- **Done when:** This directional relationship holds across at least 2–3 repeated test runs (accounting for LLM output variance) — not merely a one-off observation.

### TC-611-E3: Clear, unambiguous, well-supported message → confidence remains appropriately high
- **Preconditions:** Current message is explicit, complete, unambiguous, self-contained (e.g. "My name is Dustin and I was born in Austin, Texas"). No context needed.
- **Steps:** Trigger extraction.
- **Expected:** Confidence honesty must not become an OVER-correction — genuinely clear, directly-stated facts should still be able to receive high confidence (near 1.0), since the fix targets AMBIGUOUS cases specifically, not all extractions universally.
- **Pass criteria:** `confidence` for this clearly-stated identity fact is high (e.g. ≥0.9), demonstrating the fix didn't introduce blanket confidence deflation.
- **Done when:** High-confidence-appropriate cases are confirmed to still score high — this is the counter-test to E1, preventing an overzealous fix from breaking legitimately confident extractions.

### TC-611-E4: Confidence honesty does not depend on context window being enabled (works even in single-message mode)
- **Preconditions:** Context window disabled entirely (C4). Message is short/ambiguous.
- **Steps:** Trigger extraction.
- **Expected:** Confidence honesty is a prompt-instruction-level fix (per C7), independent of whether context assembly is enabled — a short ambiguous message should score honestly low confidence even in pure single-message mode (this was arguably already possible pre-#611 but the issue implies it wasn't happening — verify the fix addresses the instruction/anchoring problem itself, not just "confidence is fine because now there's context to lean on").
- **Pass criteria:** Sub-1.0 confidence observed even with context window fully disabled.
- **Done when:** This isolates the confidence-honesty fix as a genuinely independent improvement, not an accidental side-effect of adding context.

### TC-611-E5: Confidence value bounds remain valid (0.0–1.0) after the fix
- **Preconditions:** Various message/context combinations from Groups A-D.
- **Steps:** Inspect `confidence` values across the full test-run battery.
- **Expected:** All extracted `confidence` values remain within the existing DB constraint `chk_confidence CHECK (confidence >= 0 AND confidence <= 1)` — the honesty fix must not produce out-of-range values (e.g. a poorly-instructed prompt asking the model to "express uncertainty" numerically and getting something like `-1` or `50` by mistake).
- **Pass criteria:** Zero constraint violations across the full regression battery; zero DB insert errors attributable to `confidence` values.
- **Done when:** No `chk_confidence` violations occur during any of this document's test executions.

### TC-611-E6: Confidence field is present for facts (not just a documentation claim) — schema/prompt cross-check
- **Preconditions:** Any successful extraction with at least one fact.
- **Steps:** Inspect raw LLM JSON output before storage.
- **Expected:** Every fact object includes a `confidence` field (per the existing TEMPLATE contract) — the fix changes the VALUE guidance, not the field's presence/structure.
- **Pass criteria:** `confidence` key present and numeric on every fact object in the parsed JSON.
- **Done when:** Structural regression check passes — confirms the fix is additive (better values) not destructive (missing field).

---

## Group F — Error/Edge Cases & Privacy

### TC-611-F1: Transcript fetch failure degrades gracefully to no-context extraction (C8) — DB connection error
- **Preconditions:** Context-window enabled. The underlying transcript/context lookup (DB query, cache file read, whatever mechanism implementation uses) is forced to fail (e.g. simulated connection drop, permission error, or a fault-injected query).
- **Steps:** Trigger extraction under this fault condition.
- **Expected:** Extraction proceeds WITHOUT context (equivalent to A3/disabled behavior) rather than blocking, hanging, or dead-lettering the message. A warning is logged, but this does NOT count as an extraction failure (`extraction_failures` table is not the right place for a context-fetch-only failure — the message itself should still attempt single-message extraction).
- **Pass criteria:** Extraction completes (success or its own independent failure/success outcome, unrelated to context), context payload is empty, a distinguishable warning log line exists (e.g. "[extract_memories] WARNING: context fetch failed, proceeding without context").
- **Done when:** Extraction never blocks on a context-fetch failure — this is the single most important error-handling guarantee in this group, since the issue explicitly says context-fetch failure must "never block extraction."

### TC-611-F2: Transcript fetch failure — malformed/corrupted cache or transcript data
- **Preconditions:** (For whichever implementation stores context state, e.g. a JSON cache file analogous to `memory-message-cache.json`) the cache file is corrupted (invalid JSON, truncated, wrong schema).
- **Steps:** Trigger extraction.
- **Expected:** Same graceful degradation as TC-611-F1 — malformed context state is treated as "no context available," not a crash.
- **Pass criteria:** No unhandled JSON parse exception propagates; extraction proceeds context-free.
- **Done when:** A deliberately corrupted context-state fixture does not crash the hook or the extraction script.

### TC-611-F3: Transcript fetch timeout
- **Preconditions:** Context-fetch mechanism is a DB query (or similar) that is made to hang/time out (simulated slow query or lock contention).
- **Steps:** Trigger extraction under this condition.
- **Expected:** Context-fetch has its own bounded timeout (per TC-611-A10) and degrades to no-context on timeout, rather than consuming the outer 90s extraction timeout budget and risking the whole extraction being killed for a context-assembly problem.
- **Pass criteria:** Extraction still completes within the normal timeout budget; context-fetch timeout is independent and shorter than the outer extraction timeout.
- **Done when:** A simulated slow/hanging context query does not cause the overall extraction to hit `failure_reason='timeout'` for reasons unrelated to the LLM call itself.

### TC-611-F4: Oversized context messages truncated safely
- **Preconditions:** One or more context messages are unusually large (e.g. a multi-KB pasted log dump or code block).
- **Steps:** Trigger extraction with such a context message included in the window.
- **Expected:** The oversized context message is truncated to a reasonable length (consistent with existing truncation patterns elsewhere in the pipeline, e.g. `channel_transcripts.content` capped at 65535 chars, or a tighter per-message cap appropriate for prompt-size/cost control — implementation should define a sane cap, likely much smaller than 65535 given this is disambiguation context, not primary content) before being included in the prompt.
- **Pass criteria:** Prompt payload size remains bounded; no single oversized context message balloons the request to the point of hitting `max_tokens`/API payload limits or dramatically increasing cost.
- **Done when:** A synthetic oversized context message is confirmed truncated (with an indication, e.g. "...[truncated]", or silently — implementation's choice, test asserts a cap exists) rather than passed through in full.

### TC-611-F5: Oversized context — total context window byte/token budget respected across all N messages combined
- **Preconditions:** All 10 context messages are individually moderate-sized but collectively large.
- **Steps:** Trigger extraction with this combined-large context.
- **Expected:** Aggregate context size has a sane bound (not just per-message truncation) so that the combined prompt doesn't silently balloon `CONFIG_MAX_TOKENS`/API costs even when no single message triggers per-message truncation.
- **Pass criteria:** Total context character/token count stays within an implementation-defined reasonable bound.
- **Done when:** A stress fixture with 10 moderately-large messages does not produce a prompt that fails or is prohibitively expensive.

### TC-611-F6: Privacy — context from a private/DM channel does not leak into extraction for that same channel's later message (same-channel rule is satisfied, not violated)
- **Preconditions:** A private DM session where earlier messages contain private information the user marked/implied as private (e.g. explicit "keep this secret" language).
- **Steps:** Trigger extraction for a later message in the SAME private session, with context enabled.
- **Expected:** Context IS allowed here — same-channel rule (C5) permits same-session context regardless of the channel's overall privacy level; the concern is CROSS-channel leakage, not same-channel context use. Confirm the `visibility`/`visibility_reason` logic for any facts extracted still correctly applies private-channel defaults per existing `lookup_default_visibility()` behavior — context doesn't override or bypass visibility defaults.
- **Pass criteria:** Facts extracted from the current message in this private session still get `visibility` consistent with the sender's actual default_visibility / explicit cues, unaffected by the presence of prior private context.
- **Done when:** Same-channel private context is confirmed to NOT alter visibility defaults for newly-extracted facts (context informs disambiguation, not privacy classification).

### TC-611-F7: Privacy — context must not leak beyond the same-channel rule into a DIFFERENT channel's extraction, even for the same sender
- **Preconditions:** Same sender (e.g. I)ruid) has an active private DM session AND a separate public Discord channel session. A message in the public channel is being extracted.
- **Steps:** Trigger extraction for the public-channel message with context-window enabled.
- **Expected:** Context is drawn ONLY from the public channel's own transcript — the sender's private DM messages (even recent ones, even topically related) must NOT appear in the public channel's context window. This is the privacy-critical instance of the general C5 boundary rule.
- **Pass criteria:** Zero private-DM-session messages appear in the public-channel extraction's context payload.
- **Done when:** A fixture with the same sender active in two different channels (one private, one public) around the same time window demonstrates strict channel isolation for context assembly.

### TC-611-F8: Privacy — phone numbers / secrets appearing only in context messages are not exposed/re-extracted from context
- **Preconditions:** A context message contains a phone number or other sensitive identifier that was already extracted in ITS OWN pass (when it was the current message). The current message under test does not repeat this information.
- **Steps:** Trigger extraction.
- **Expected:** Consistent with the extract-current-only guardrail (Group C), no phone/email/secret fact is re-extracted or re-exposed just because it's visible in the context window — combining C2 (no context-only extraction) with a security-sensitive instance of the same rule.
- **Pass criteria:** No `phone`/`email`/other identifier fact is created in this pass sourced from context-only content.
- **Done when:** This is confirmed as a specific security-flavored instance of TC-611-C1, run against sensitive-identifier fixtures specifically (not just generic facts).

### TC-611-F9: Combined failure — context-fetch failure AND extraction itself failing (compound degradation, mirrors #485's TC-B6 pattern)
- **Preconditions:** Context-fetch fails (per F1) AND the underlying `extract_memories.py` call also exits nonzero for an unrelated reason (e.g. LLM API error).
- **Steps:** Trigger extraction under both simultaneous fault conditions.
- **Expected:** The extraction failure is dead-lettered via the EXISTING `extraction_failures` mechanism (per #485) with its normal `failure_reason` (`nonzero_exit`, `timeout`, etc.) — the context-fetch failure that happened alongside it is a contributing/logged condition, not a separate/competing failure classification. No new failure_reason value is required for "context fetch also failed" — that's noise, not signal, for the dead-letter taxonomy.
- **Pass criteria:** Exactly one dead-letter row is created, with a failure_reason from the EXISTING taxonomy (`nonzero_exit`/`timeout`/`spawn_error`/`json_parse_failure`); the row's stderr/log context may additionally mention the context-fetch failure, but this doesn't require CHECK-constraint or schema changes.
- **Done when:** Compound failure does not require expanding the `extraction_failures.failure_reason` CHECK constraint — confirms #611's error handling composes cleanly with #485's existing dead-letter design rather than needing a parallel failure-tracking mechanism.

---

## Definition of "Done" for Issue #611

Implementation is considered complete and ready for QA sign-off when ALL of the following hold:

1. **Both extraction paths updated (C1):** Per-turn hook path (Group A) AND batch/replay path (Group B) both pass their respective test groups in full.
2. **Guardrail is airtight (C2, Group C):** Zero context-only extractions across the full Group C battery, with special attention to TC-611-C4 (the literal regression scenario from the issue) passing all 3 of its sub-expectations simultaneously.
3. **Environment field is populated honestly (C6, Group D):** Inferable cases populate correctly (D1, D2), non-inferable cases are NULL with zero hallucination instances across a repeated-run battery (D3), and the value survives the full storage + archival round-trip (D4, D5).
4. **Confidence honesty demonstrated directionally (C7, Group E):** Ambiguous/no-context messages score measurably below 1.0 (E1, E4); clear messages remain appropriately high (E3, preventing overcorrection); with-context confidence ≥ without-context confidence for the same disambiguated fact (E2); all values remain within the existing `chk_confidence` bounds (E5).
5. **Config contract honored (C3, C4):** `max_prior_messages` defaults to 10, is hot-reloadable with no restart (A7), has a working disable mechanism (A8), and BVA edge values (0, negative, non-numeric) degrade gracefully to documented defaults (A5, A6) — and the SAME config value drives BOTH extraction paths consistently (B5).
6. **No privacy/channel-boundary regressions (C5, Group F):** Zero cross-channel/cross-thread context leakage across B3, B4, F7; same-channel private context does not alter visibility defaults (F6); sensitive identifiers are not re-exposed via context-only presence (F8).
7. **Failure modes degrade gracefully, never block (C8, Group F):** Context-fetch failures (DB error, malformed cache, timeout — F1, F2, F3) never prevent single-message extraction from proceeding, and compound failures (F9) route through the EXISTING `extraction_failures` taxonomy without requiring schema expansion.
8. **No regression to existing #485/#497 dead-letter/replay behavior:** Existing `extraction_failures` state machine, timeout handling, JSON-repair handling, and interpreter resolution continue to function unchanged (spot-check against `TEST-CASES-ISSUE-485.md` Group A/B as a smoke check, not a full re-run).
9. **All test cases in this document have a recorded pass/fail result** (or an explicit N/A with justification, e.g. TC-611-D5 if no archival mechanism currently exists) before this issue is marked resolved.
10. **QA sign-off recorded** in the issue thread referencing this document and the executed results (Flint/QA Executor run, or equivalent), per `QA_DELEGATION` domain convention (QA Lead designs, QA Executor runs, QA Lead approves/rejects based on results).

**Explicitly OUT of scope for this test-case document (per issue text, do not block sign-off on these):**
- Normalizing/canonicalizing `environment` values across differently-phrased mentions of the same host (D6, informational only).
- A shared context-window helper module extraction/refactor is a "consider" / "candidate for convergence later" per the issue — its ABSENCE is not a test failure, only its behavioral consistency between the two paths (B5) is required.
- `confidence-check` plugin convergence onto a shared helper (mentioned as a future possibility in the issue, not this issue's deliverable).
