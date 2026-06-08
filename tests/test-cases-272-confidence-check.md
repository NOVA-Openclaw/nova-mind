# Test Cases — Issue #272: Response Confidence Scoring & LLM Iteration

**Plugin:** `confidence-check` (nova-mind/cognition/metacognition/confidence-check)  
**QA Lead:** Gem  
**Feature branch:** `feature/issue-272-confidence-check-enhancement`  
**Commits:** 25e5514, 62f7e48, d6d3ea2  
**Total test cases:** 62  
**Design patterns:** BVA, equivalence partitioning, state transition, decision table

---

## Functional Areas

| Group | Area | TCs |
|---|---|---|
| 1 | Heuristic Pre-Screen | TC-272-01 – TC-272-12 |
| 2 | Citation Extraction | TC-272-13 – TC-272-22 |
| 3 | Citation Verification | TC-272-23 – TC-272-30 |
| 4 | Contradiction Context Extraction | TC-272-31 – TC-272-36 |
| 5 | LLM Evaluation | TC-272-37 – TC-272-43 |
| 6 | Retry & Revision Logic | TC-272-44 – TC-272-49 |
| 7 | Error Resilience & Edge Cases | TC-272-50 – TC-272-52 |
| 8 | Phase 1 Self-Verification | TC-272-53 – TC-272-58 |
| 9 | State Machine & Regression | TC-272-59 – TC-272-62 |

---

## Group 1: Heuristic Pre-Screen

### TC-272-01: Phase 1 fires for factual response; Phase 2 LLM called even with zero hedging *(updated for #312)*
**Description:** A factual, confident response with zero hedging should still trigger Phase 1 self-verification (priorAttempts=0), then Phase 2 LLM evaluation. There is no auto-pass shortcut in #312 — heuristics are signals only.  
**Preconditions:** Plugin initialized with default CONFIG (`self_verification_enabled: true`).  
**Input:**
```
message: "2 + 2 = 4. According to mathematics, this is definitively true."
event.messages: []
event.runId: "run-tc01"
```
**Phase 1 invocation (priorAttempts=0):**
- Returns `{ action: "revise", retry: { instruction: "Before finalizing your response, verify..." } }`
- retryAttempts.set("confidence-run-tc01", 1)
- Log: "[confidence-check] Phase 1: Mandatory self-verification pass (attempt 0)"

**Phase 2 invocation (priorAttempts=1):**
- hedging_count = 0, hedging_density = 0.000
- unsupported_assertions = value based on sentence detection (signal only)
- LLM evaluation IS called (no auto-pass path exists)
- Log: "[confidence-check] Heuristics: hedging=0/... density=0.000..."

**Pass criteria:** Phase 1 returns ReviseAction at attempt 0; Phase 2 calls LLM (no auto-pass). `undefined` NOT returned at attempt 0.

---

### TC-272-02: Phase 2 LLM called regardless of density below pass threshold (BVA — #312 updated) *(updated for #312)*
**Description:** BVA on hedging_density_pass_threshold = 0.02. Even at density 0.0199 (strictly below the old auto-pass boundary), the LLM is still called in #312 — density is a signal only, not a routing decision.  
**Input:**
```
message: <100-word message with 1 hedging phrase, hedging_density ≈ 0.01>
event.runId: "run-tc02"
```
**Expected (Phase 2 invocation, priorAttempts=1):**
- hedging_count ≥ 1, hedging_density ≈ 0.01 (below 0.02)
- LLM evaluation IS called (no auto-pass at density 0.01 in #312)
- Heuristics logged but do not gate LLM call

**Pass criteria:** LLM invoked at Phase 2 even with sub-0.02 density. `undefined` not returned without LLM call.

---

### TC-272-03: Phase 2 LLM called at density boundary — no auto-pass path exists (#312) *(updated for #312)*
**Description:** BVA on hedging_density_pass_threshold = 0.02. At density exactly 0.020, LLM is called. The density threshold is now a signal forwarded to the LLM — no auto-pass exists at any density value. The distinction between below/at the threshold is irrelevant for routing.  
**Input:**
```
message: <100-word message with exactly 2 hedging phrase matches, hedging_density = 0.02>
event.runId: "run-tc03"
```
**Expected (Phase 2 invocation, priorAttempts=1):**
- hedging_density = 0.02 (at threshold)
- LLM evaluation IS called (threshold is a signal, not a gate)
- Heuristic density included in LLM prompt context

**Pass criteria:** LLM invoked. No special behavior at the density boundary.

---

### TC-272-04: Borderline hedging — below fail threshold
**Description:** BVA on hedging_density_fail_threshold = 0.08. density = 0.079 → goes to LLM but NOT auto-fail heuristic path.  
**Input:** 100-word message with 7 hedging phrase occurrences.  
**Expected:** LLM evaluation called (not skipped to fail). LLM failure fallback uses borderline path.

---

### TC-272-05: LLM failure + high hedging — heuristic fallback
**Description:** density ≥ 0.08 AND LLM throws → heuristic fallback assigns confidence=40, triggers revision.  
**Input:**
```
message: <dense hedging, density ≥ 0.08>
LLM: throws error
```
**Expected:** `{ action: "revise", retry: { instruction: "...", ... } }` returned via heuristic fallback path.

---

### TC-272-06: assertions=2 does NOT auto-pass; Phase 2 LLM still called (#312) *(updated for #312)*
**Description:** Low hedging AND assertions=2 no longer auto-passes in #312. The LLM is called regardless of assertion count — heuristic values are signals only.  
**Input:** Message where runHeuristicScreen returns unsupported_assertions=2, hedging_density<0.02. priorAttempts=1 (Phase 2).  
**Expected:**
- LLM evaluation IS called (assertion count does not gate the call)
- Assertion count included in LLM prompt context
- Result depends on LLM response (pass or revise)

**Pass criteria:** LLM invoked at Phase 2 with assertions=2. No auto-pass.

---

### TC-272-07: assertions=3 → Phase 2 LLM called (signal only, no routing decision) *(updated for #312)*
**Description:** In #312, the "not auto-pass" concept is obsolete — there is no auto-pass to gate on. assertions=3 is a signal forwarded to the LLM evaluator. The assertion count boundary (< 3 vs. ≥ 3) has no routing significance.  
**Input:** Message where unsupported_assertions=3, hedging_density<0.02. priorAttempts=1 (Phase 2).  
**Expected:**
- LLM evaluation IS called (same as assertions=2; assertion count does not gate the call)
- Assertion count included in LLM prompt context
- Routing is identical at assertions=2 and assertions=3

**Pass criteria:** LLM invoked. Behavior identical to TC-272-06.

---

### TC-272-08: Hedging phrase case-insensitivity
**Description:** "I Think", "MAYBE", "Perhaps" (mixed case) should match hedging phrases (lowercased internally).  
**Input:** `message: "I Think this might work. MAYBE it will. Perhaps not."`  
**Expected:** hedging_count ≥ 3 (matches "i think", "maybe", "perhaps").

---

### TC-272-09: Multiple instances of same hedging phrase counted
**Description:** "maybe" appearing 3 times should count as hedging_count += 3.  
**Input:** `message: "maybe yes, maybe no, maybe so, and that's that."` (single sentence, ~10 words)  
**Expected:** hedging_count = 3 (three matches of "maybe").

---

### TC-272-10: Word count excludes empty tokens
**Description:** Leading/trailing whitespace, multiple spaces → split/filter correctly.  
**Input:** `message: "  Hello   world  "` → words = ["Hello", "world"] → word_count = 2.  
**Expected:** word_count = 2; hedging_density calculated over 2.

---

### TC-272-11: Empty message — skip immediately
**Description:** event.lastAssistantMessage is empty string → return undefined immediately without any processing.  
**Input:** `message: "   "` (whitespace only)  
**Expected:** Returns `undefined`; logs "[confidence-check] Empty message, skipping".  
**Note:** Condition is `!message.trim()`.

---

### TC-272-12: Unsupported assertion count capped at total sentence count
**Description:** Implementation caps `unsupported = Math.min(unsupported, sentences.length)`. If sentence detection and assertion counting diverge, cap applies.  
**Input:** Edge case where filtering produces more unsupported than total sentences.  
**Expected:** unsupported_assertions ≤ total sentence count.

---

## Group 2: Citation Extraction

### TC-272-13: HTTPS URL extraction
**Description:** Standard https:// URL captured as `{ type: "url", value: "https://..." }`.  
**Input:** `message: "See https://openai.com/api for details."`  
**Expected:** citations includes `{ type: "url", value: "https://openai.com/api" }`.

---

### TC-272-14: HTTP URL extraction
**Description:** http:// URL extracted; trailing punctuation stripped.  
**Input:** `message: "See http://example.com/docs."`  
**Expected:** citations includes `{ type: "url", value: "http://example.com/docs" }` (period stripped).

---

### TC-272-15: Absolute file path extraction
**Description:** `/path/to/file.ts` extracted as `file_path`.  
**Input:** `message: "Edit /home/nova/nova-mind/cognition/metacognition/confidence-check/src/index.ts"` 
**Expected:** citations includes `{ type: "file_path", value: "/home/nova/nova-mind/cognition/metacognition/confidence-check/src/index.ts" }`.

---

### TC-272-16: Home-relative path extraction
**Description:** `~/path/to/file` extracted as `file_path`.  
**Input:** `message: "See ~/nova-mind/schema.sql for schema."`  
**Expected:** citations includes `{ type: "file_path", value: "~/nova-mind/schema.sql" }`.

---

### TC-272-17: Relative path with recognized extension
**Description:** `src/index.ts` (relative path with `.ts` extension) extracted as `file_path`.  
**Input:** `message: "Check src/index.ts and tests/test-cases-272.md."`  
**Expected:** Two file_path citations extracted with matching file names.

---

### TC-272-18: Backtick code reference with file-like content
**Description:** Backtick-wrapped string with `/` or recognized extension extracted as `code_reference`.  
**Input:** `` message: "The function in `cognition/metacognition/confidence-check/src/index.ts` handles this." ``  
**Expected:** citations includes `{ type: "code_reference", value: "cognition/metacognition/confidence-check/src/index.ts" }`.

---

### TC-272-19: Doc reference — "according to" pattern
**Description:** "according to the docs" captured as `doc_reference`.  
**Input:** `message: "According to the OpenClaw documentation, plugins run in sandboxed contexts."`  
**Expected:** citations includes `{ type: "doc_reference", ... }` for the "according to" match.

---

### TC-272-20: Conversational back-reference NOT extracted
**Description:** "as I mentioned earlier" should NOT be captured as a doc reference (isConversationalReference filter).  
**Input:** `message: "As I mentioned earlier, this should work. Based on what you said, it makes sense."`  
**Expected:** No citations extracted (both are conversational; vague starters "what" filtered).

---

### TC-272-21: Deduplication — same path not added twice
**Description:** Same URL appearing twice in message → only one citation entry.  
**Input:** `message: "See https://docs.example.com/api and also https://docs.example.com/api for details."`  
**Expected:** citations.length = 1 (deduplicated by capturedValues set).

---

### TC-272-22: Clean message — no citations
**Description:** Response with no URLs, file paths, or doc references → empty citation array.  
**Input:** `message: "2 + 2 = 4. This is a mathematical fact."`  
**Expected:** citations = []; citationResult = { total: 0, verified: 0, unverified: 0, citations: [] }.

---

## Group 3: Citation Verification

### TC-272-23: URL verified against web_fetch tool call
**Description:** URL citation matches web_fetch tool call content (exact URL in content).  
**Preconditions:** messages contains `{ role: "tool", name: "web_fetch", content: "...https://docs.example.com/api..." }`.  
**Input:** citation = `{ type: "url", value: "https://docs.example.com/api" }`.  
**Expected:** verified = true.

---

### TC-272-24: URL verified via domain-level match
**Description:** If full URL path not in tool call content, domain match triggers verification.  
**Input:** citation value = "https://docs.example.com/api/v2/endpoints/complicated", tool call content contains "docs.example.com".  
**Expected:** verified = true (domain match).

---

### TC-272-25: File path verified against read tool call
**Description:** file_path citation matched against read tool call content.  
**Preconditions:** messages contains `{ role: "tool", name: "read", content: "{\"path\":\"/home/nova/schema.sql\"}" }`.  
**Input:** citation = `{ type: "file_path", value: "/home/nova/schema.sql" }`.  
**Expected:** verified = true.

---

### TC-272-26: File path verified against exec tool call with cat
**Description:** exec tool call using `cat` on a file path → verifies file_path citation.  
**Preconditions:** messages contains exec tool call with content containing "cat /home/nova/schema.sql".  
**Input:** citation = `{ type: "file_path", value: "/home/nova/schema.sql" }`.  
**Expected:** verified = true.

---

### TC-272-27: Exec with non-file-reading command does NOT verify file citation
**Description:** exec tool call without cat/grep/head/tail/sed/less/awk/wc/diff/find → does NOT verify file_path.  
**Preconditions:** exec tool call content = "npm install /home/nova/schema.sql".  
**Input:** citation = `{ type: "file_path", value: "/home/nova/schema.sql" }`.  
**Expected:** verified = false (exec without file-reading command not counted).

---

### TC-272-28: Doc reference verified against pdf tool call
**Description:** Any `pdf` tool call verifies any doc_reference citation (strong evidence).  
**Preconditions:** messages contains `{ role: "tool", name: "pdf", content: "..." }`.  
**Input:** citation = `{ type: "doc_reference", value: "according to the OpenClaw manual" }`.  
**Expected:** verified = true.

---

### TC-272-29: Doc reference unverified — no matching tool call
**Description:** doc_reference with no pdf/web/read tool call in messages → unverified.  
**Preconditions:** messages = [].  
**Input:** citation = `{ type: "doc_reference", value: "according to OpenClaw docs" }`.  
**Expected:** verified = false; citationResult.unverified = 1.

---

### TC-272-30: Multi-format tool call message parsing
**Description:** All 3 tool call formats extracted correctly:  
- Format 1: `{ role: "tool", name: "...", content: "..." }`
- Format 2: Claude content array with `{ type: "tool_use", name: "...", input: {...} }`
- Format 3: OpenAI `tool_calls` array on assistant message  
**Expected:** extractToolCalls returns records from all three formats.

---

## Group 4: Contradiction Context Extraction

### TC-272-31: Prior assistant messages extracted correctly
**Description:** messages array with assistant role entries → all extracted as priorAssistantMessages.  
**Preconditions:** messages = [{ role: "assistant", content: "Answer A" }, { role: "user", content: "Q" }, { role: "assistant", content: "Answer B" }].  
**Expected:** priorAssistantMessages = ["Answer A", "Answer B"]; hasContext = true.

---

### TC-272-32: User messages excluded from contradiction context
**Description:** User-role messages must NOT appear in priorAssistantMessages (only assistant self-contradictions).  
**Preconditions:** messages = [{ role: "user", content: "You said X" }, { role: "assistant", content: "A" }].  
**Expected:** priorAssistantMessages = ["A"] (user message excluded).

---

### TC-272-33: Current response filtered from prior messages (commit 62f7e48)
**Description:** The current lastAssistantMessage must NOT appear in priorAssistantMessages (prevents self-comparison false positives).  
**Preconditions:** messages includes an entry whose content equals the current message verbatim.  
**Expected:** That entry excluded from priorAssistantMessages.

---

### TC-272-34: max_prior_messages limit enforced
**Description:** Only the last 10 messages examined (CONFIG.max_prior_messages). Messages beyond index -10 are ignored.  
**Preconditions:** messages array with 20 entries; oldest 10 contain assistant messages.  
**Expected:** Only the last 10 messages scanned; older assistant messages NOT in priorAssistantMessages.

---

### TC-272-35: Empty messages array → hasContext=false
**Description:** event.messages = [] or missing → ContradictionContext returns hasContext=false.  
**Input:** messages = [].  
**Expected:** { priorAssistantMessages: [], hasContext: false }.

---

### TC-272-36: Claude-style content arrays in assistant messages extracted correctly (D7 fix) *(updated for #312 D7)*
**Description:** D7 changed the behavior: assistant messages with Claude-style content arrays (`[{type:"text", text:"..."}]`) are now **parsed and extracted**, not skipped. Text blocks are concatenated and added to `priorAssistantMessages`.  
**Input:** `{ role: "assistant", content: [{ type: "text", text: "Hello" }, { type: "text", text: " world" }] }`.  
**Expected:**
- Extracted text = "Hello\n world" (blocks joined with newline)
- Entry added to priorAssistantMessages: `["Hello\n world"]`
- hasContext = true

**Note:** Non-text block types (e.g., `{ type: "tool_use", ... }`) are filtered out during concatenation — only `type === "text"` blocks contribute.  
**Pass criteria:** priorAssistantMessages.length = 1; content extracted from array (not skipped).

---

## Group 5: LLM Evaluation

### TC-272-37: Valid JSON response parsed correctly
**Description:** LLM returns clean JSON → parsed into LlmEvaluation.  
**Input LLM response:**
```json
{"confidence": 72, "concerns": ["Hedging detected"], "reasoning_strategies": ["Add sources"]}
```
**Expected:** { confidence: 72, concerns: ["Hedging detected"], reasoning_strategies: ["Add sources"] }.

---

### TC-272-38: JSON in prose preamble or markdown code block parsed correctly (D6 fix) *(updated for #312 D6)*
**Description:** D6 replaced regex-based JSON extraction with brace-scanning (`content.indexOf("{")` / `content.lastIndexOf("}")`) which handles both markdown code fences and prose preambles before the JSON object.  
**Input LLM response A (markdown code block):**
```
```json
{"confidence": 65, "concerns": [], "reasoning_strategies": []}
```
```
**Input LLM response B (prose preamble, D6-specific):**
```
Here is my evaluation:
{"confidence": 65, "concerns": [], "reasoning_strategies": []}
```
**Expected for both:** `{ confidence: 65, concerns: [], reasoning_strategies: [] }`. No parse error.  
**Implementation note:** D6 extracts JSON by scanning for first `{` and last `}` in the response content, then parsing the substring. This handles both code fence wrappers and prose preambles.  
**Pass criteria:** Both input variants parsed correctly; no "Failed to parse LLM JSON response" error.

---

### TC-272-39: result.text used, not result.content (commit d6d3ea2)
**Description:** SDK returns `{ text: "...", content: undefined }` → must read `result.text`. Bug fix validation.  
**Input:** LLM response = `{ text: "{\"confidence\":80,\"concerns\":[],\"reasoning_strategies\":[]}", content: undefined }`.  
**Expected:** Parsed successfully from `result.text`; no "missing content" error.

---

### TC-272-40: Confidence value clamped to 0–100
**Description:** LLM returns confidence=150 or confidence=-10 → clamped to 100 or 0 respectively.  
**Input:** `{"confidence": 150, "concerns": [], "reasoning_strategies": []}`.  
**Expected:** returned confidence = 100.

---

### TC-272-41: Missing confidence field → error thrown
**Description:** LLM response missing "confidence" → evaluateViaLlm throws.  
**Input:** `{"concerns": [], "reasoning_strategies": []}`.  
**Expected:** throws `"LLM response missing valid confidence field"`.

---

### TC-272-42: Invalid JSON response → parse error thrown
**Description:** LLM returns non-JSON text → throw on JSON.parse.  
**Input LLM response:** `"I cannot evaluate this."`  
**Expected:** throws `"Failed to parse LLM JSON response: ..."`.

---

### TC-272-43: Empty LLM response → error thrown
**Description:** result.text = "" and result.content = undefined → throw "LLM response missing content".  
**Input:** `{ text: "", content: undefined }`.  
**Expected:** throws `"LLM response missing content"`.

---

## Group 6: Retry & Revision Logic

### TC-272-44: Confidence < threshold → Socratic questioning instruction (Phase 2, external attempt 1/2) *(updated for #312)*
**Description:** LLM returns confidence=70 (< 85 threshold) at Phase 2 first external evaluation (priorAttempts=1). priorAttempts=0 now fires Phase 1 self-verification, not external LLM — external evaluation starts at priorAttempts=1.  
**Input:** priorAttempts = 1 (retryAttempts.get() = 1, set by Phase 1), LLM returns confidence = 70.  
**Expected:**
- externalAttempts = priorAttempts - 1 = 0 (first external attempt)
- attemptsRemaining = max_external_revision_attempts - externalAttempts - 1 = 2 - 0 - 1 = 1
- retryAttempts.get(idempotencyKey) = 2 after this call
- Returns `{ action: "revise", retry: { instruction: "Your self-assessment scored 70% confidence (threshold: 85%)...\nConcerns:\n...\n(1 revision attempt(s) available)" } }`
- Log: "[confidence-check] FAIL — confidence 70% < threshold 85. Triggering external revision (external attempt 1/2)"

---

### TC-272-45: Second external revision attempt tracked correctly (Phase 2, external attempt 2/2) *(updated for #312)*
**Description:** On Phase 2 second external evaluation (priorAttempts=2), attemptsRemaining = 0. This is the last external revision before framing.  
**Input:** priorAttempts = 2 (retryAttempts.get() = 2, set after Phase 1 + external attempt 1), LLM returns confidence = 60.  
**Expected:**
- externalAttempts = priorAttempts - 1 = 1 (second external attempt)
- attemptsRemaining = max_external_revision_attempts - externalAttempts - 1 = 2 - 1 - 1 = 0
- retryAttempts.get(idempotencyKey) = 3 after this call
- Instruction mentions "(0 revision attempt(s) available)"
- Log: "[confidence-check] FAIL — confidence 60% < threshold 85. Triggering external revision (external attempt 2/2)"

---

### TC-272-46: Max revisions exhausted → framing instruction
**Description:** priorAttempts = 3 (= max_revision_attempts) → framing instruction returned.  
**Input:** priorAttempts = 3, LLM call skipped.  
**Expected:**
- retryAttempts.get(idempotencyKey) = 4
- Returns `{ action: "revise", retry: { instruction: "You have been unable to reach high confidence... Frame your response... 'I'm not fully confident about this, but...'" } }`
- Log: "Max revisions (3) exhausted for ..., framing response"

---

### TC-272-47: Post-framing pass → allow finalization + map cleanup
**Description:** priorAttempts = 4 (> max_revision_attempts) → skip evaluation, return undefined, delete from retryAttempts.  
**Input:** priorAttempts = 4.  
**Expected:**
- Returns `undefined`
- retryAttempts.delete(idempotencyKey) called
- Log: "[confidence-check] Post-framing pass, allowing finalization"

---

### TC-272-48: Confidence ≥ threshold → PASS, return undefined, retryAttempts cleaned up (D3) *(updated for D3)*
**Description:** LLM returns confidence=90 (≥ 85) → PASS, no revision. D3 fix: `retryAttempts.delete(idempotencyKey)` IS called on PASS to prevent Map accumulation.  
**Input:** priorAttempts = 1 (Phase 2 external eval), LLM returns confidence = 90.  
**Expected:**
- Returns `undefined`
- `retryAttempts.delete(idempotencyKey)` called (D3 fix — Map entry removed)
- Log: "[confidence-check] PASS — confidence above threshold"  

**Note:** Prior to D3, retryAttempts was NOT modified on PASS, causing Map growth on successful runs. This behavior is now fixed.

---

### TC-272-49: Different runIds maintain independent retry counts
**Description:** Two concurrent runIds must not share retry state.  
**Input:** runId "run-A" at attempt 2, runId "run-B" at attempt 0.  
**Expected:** retryAttempts.get("confidence-run-A") = 2; retryAttempts.get("confidence-run-B") = 0. No cross-contamination.

---

## Group 7: Error Resilience & Edge Cases

### TC-272-50: LLM failure + high hedging → heuristic fallback triggers revision
**Description:** LLM throws AND hedging_density ≥ 0.08 → assigns confidence=40 via heuristic fallback → triggers revision (40 < 85 threshold).  
**Input:** high-hedging message (density ≥ 0.08), LLM throws error.  
**Expected:**
- llmResult = { confidence: 40, concerns: ["High hedging density detected"], reasoning_strategies: ["Review claims..."] }
- Returns revision action (40 < 85)
- Log: "[confidence-check] LLM evaluation failed: <error message>"

---

### TC-272-51: LLM failure + borderline hedging → graceful finalization
**Description:** LLM throws AND hedging_density < 0.08 (borderline) → allow finalization.  
**Input:** borderline message (density between 0.02 and 0.08), LLM throws error.  
**Expected:**
- Returns `undefined`
- Log: "[confidence-check] Borderline after LLM failure, allowing finalize"

---

### TC-272-52: Unhandled plugin error → outer catch → allow finalization
**Description:** Any unhandled exception from evaluateConfidence → caught by outer try/catch in on() handler → returns undefined (agent not blocked).  
**Input:** Trigger scenario where evaluateConfidence throws an unexpected error (e.g., malformed event object).  
**Expected:**
- Returns `undefined`
- Log: "[confidence-check] Unhandled error in before_agent_finalize: <message>"
- Gateway continues running

---

---

## Group 8: Phase 1 Self-Verification *(new for #312)*

### TC-272-53: Phase 1 fires at priorAttempts=0 and returns self-verification ReviseAction
**Description:** At priorAttempts=0, the hook must always return a ReviseAction with the self-verification instruction, regardless of message content or heuristics.  
**Preconditions:** Plugin initialized with `self_verification_enabled: true` (default). `runId` present.  
**Input:**
```
message: "The capital of France is Paris."
event.runId: "run-p1-01"
```
**Expected:**
- Returns `{ action: "revise", retry: { instruction: "Before finalizing your response, verify the following:\n\n1. TRUTHFULNESS...", idempotencyKey: "confidence-run-p1-01", maxAttempts: 1 } }`
- retryAttempts.set("confidence-run-p1-01", 1)
- Log: "[confidence-check] Phase 1: Mandatory self-verification pass (attempt 0)"
- `pluginLlm.complete()` NOT called

**Pass criteria:** ReviseAction returned at attempt 0; LLM not invoked; state advanced to 1.

---

### TC-272-54: self_verification_enabled=false → Phase 1 skipped, LLM called at priorAttempts=0
**Description:** When `self_verification_enabled=false`, the Phase 1 block is skipped and Phase 2 external evaluation runs immediately at priorAttempts=0.  
**Preconditions:** CONFIG.self_verification_enabled = false.  
**Input:** priorAttempts = 0, message with borderline confidence.  
**Expected:**
- Phase 1 block (`if (priorAttempts === 0 && CONFIG.self_verification_enabled)`) evaluates false—skipped
- Phase 2 runs: heuristics computed, LLM called
- `externalAttempts = priorAttempts - 0 = 0` (no self-verify offset)
- Framing threshold: `priorAttempts > max_external_revision_attempts + 0 = 2`

**Pass criteria:** LLM called at priorAttempts=0; no self-verification ReviseAction returned.

---

### TC-272-55: Phase 1 instruction contains all 5 verification categories
**Description:** The self-verification instruction must contain all 5 required categories: TRUTHFULNESS, SOURCES, ASSUMPTIONS, KNOWLEDGE BOUNDARIES, SELF-CONSISTENCY.  
**Input:** Any non-empty message, priorAttempts=0.  
**Expected:** Returned instruction string contains all 5 numbered categories verbatim.  
**Pass criteria:** `instruction.includes("TRUTHFULNESS")`, `instruction.includes("SOURCES")`, `instruction.includes("ASSUMPTIONS")`, `instruction.includes("KNOWLEDGE BOUNDARIES")`, `instruction.includes("SELF-CONSISTENCY")` — all true.

---

### TC-272-56: Phase 1 sets retryAttempts.set(key, 1) → state machine initialized correctly
**Description:** After Phase 1, retryAttempts must be set to 1 so Phase 2 (at priorAttempts=1) proceeds correctly.  
**Input:** priorAttempts=0 (Map empty for this key), message non-empty.  
**Expected:**
- Before: retryAttempts.get("confidence-${runId}") = undefined (or 0)
- After Phase 1 invocation: retryAttempts.get("confidence-${runId}") = 1

**Pass criteria:** Map entry = 1 after Phase 1 fires.

---

### TC-272-57: Phase 1 does NOT call pluginLlm.complete (no LLM at attempt 0)
**Description:** Phase 1 must return a ReviseAction without making any LLM call. The LLM is reserved for Phase 2 external evaluation.  
**Input:** priorAttempts=0, `self_verification_enabled=true`.  
**Expected:** `pluginLlm.complete` not invoked during Phase 1 handler execution.  
**Pass criteria:** Zero LLM calls at attempt 0. (Verify by spy/mock on pluginLlm.complete.)

---

### TC-272-58: Phase 1 does not fire when priorAttempts > 0 (correct Phase 1/2 gating)
**Description:** Phase 1 fires ONLY at priorAttempts=0. At priorAttempts=1 or higher, the Phase 1 block is skipped and Phase 2 runs.  
**Input:** priorAttempts=1, `self_verification_enabled=true`.  
**Expected:**
- Phase 1 block (`if (priorAttempts === 0 && ...)`) evaluates false — skipped
- Phase 2 heuristics and LLM evaluation run normally
- No self-verification instruction returned

**Pass criteria:** Phase 2 (heuristics + LLM) runs at priorAttempts=1; no Phase 1 ReviseAction.

---

## Group 9: State Machine & Regression *(new for #312)*

### TC-272-59: Full state machine traversal 0→1→2→3→4
**Description:** End-to-end state machine: Phase 1 (attempt 0) → Phase 2 external 1/2 (attempt 1, LLM fails) → Phase 2 external 2/2 (attempt 2, LLM fails) → Framing (attempt 3) → Post-framing (attempt 4).  
**Preconditions:** LLM returns confidence < 85 for both Phase 2 invocations.  
**Sequence:**
1. Invocation 1 (priorAttempts=0): Phase 1 self-verify → ReviseAction; retryAttempts=1
2. Invocation 2 (priorAttempts=1): Phase 2 external 1/2; LLM → 60% → ReviseAction; retryAttempts=2
3. Invocation 3 (priorAttempts=2): Phase 2 external 2/2; LLM → 60% → ReviseAction; retryAttempts=3
4. Invocation 4 (priorAttempts=3): Framing → ReviseAction ("I'm not fully confident..."); retryAttempts=4
5. Invocation 5 (priorAttempts=4): Post-framing → `undefined`; retryAttempts.delete() called

**Expected:** Exact sequence above; no infinite loop; Map entry cleaned up after invocation 5.  
**Pass criteria:** 5 invocations, correct action at each step, Map empty after step 5.

---

### TC-272-60: PASS path → retryAttempts.delete() called (D3 regression guard)
**Description:** When Phase 2 LLM returns confidence ≥ 85%, `retryAttempts.delete(idempotencyKey)` must be called to prevent Map accumulation across successful runs.  
**Input:** priorAttempts=1, LLM returns confidence=95.  
**Expected:**
- `retryAttempts.delete("confidence-${runId}")` called
- Returns `undefined`
- Map entry no longer exists for this runId  
**Pass criteria:** Map entry absent after PASS; no memory leak on successful responses.

---

### TC-272-61: Claude-style content array in assistant message → extracted into contradiction context (D7)
**Description:** D7 added support for Claude-style `content` arrays in assistant messages within `extractContradictionContext()`. Text blocks should be concatenated and added to `priorAssistantMessages`.  
**Input:**
```
messages: [
  { role: "assistant", content: [
    { type: "text", text: "The answer is 42." },
    { type: "tool_use", name: "web_search", input: {} },
    { type: "text", text: " This is confirmed." }
  ]}
]
```
**Expected:**
- Non-text blocks (`tool_use`) filtered out
- Text blocks joined: `"The answer is 42.\n This is confirmed."`
- priorAssistantMessages = ["The answer is 42.\n This is confirmed."]
- hasContext = true  
**Pass criteria:** Text extracted from content array; tool_use block not included.

---

### TC-272-62: Prose preamble before LLM JSON response → brace extraction succeeds (D6)
**Description:** D6 replaced `^`-anchored regex with `indexOf("{")`/`lastIndexOf("}")` brace scanning. This handles LLM responses where prose precedes the JSON object.  
**Input LLM response:**
```
I have evaluated the response carefully. Here is my assessment:
{"confidence": 72, "concerns": ["Uncertain claim"], "reasoning_strategies": ["Add sources"]}
```
**Expected:** Parsed successfully: `{ confidence: 72, concerns: ["Uncertain claim"], reasoning_strategies: ["Add sources"] }`. No parse error despite prose preamble.  
**Pass criteria:** `evaluateViaLlm()` returns parsed result; no "Failed to parse LLM JSON response" error.

---

## Exit Criteria

All of the following must be true before this feature is considered QA-complete:

1. TC-272-53: PASS (Phase 1 baseline — fires at attempt 0, returns self-verification action)
2. TC-272-01, TC-272-08, TC-272-11, TC-272-13, TC-272-20, TC-272-22: PASS (basic Phase 1/2 flow + citation extraction)
3. TC-272-33: PASS (commit 62f7e48 regression guard — current response filter)
4. TC-272-39: PASS (commit d6d3ea2 regression guard — result.text fix)
5. TC-272-44, TC-272-46, TC-272-47, TC-272-48: PASS (full revision lifecycle with updated priorAttempts model)
6. TC-272-59: PASS (full state machine 0→4 end-to-end)
7. TC-272-60: PASS (D3 regression guard — retryAttempts.delete on PASS)
8. TC-272-52: PASS (error resilience — gateway must not crash)
9. All S1/S2 defects resolved; no open P1/P2 bugs
10. No regression on previously passing integration tests

*Test case update history: TCs 01–03, 06–07, 36, 38, 44, 45, 48 updated for #312 two-phase architecture and D1–D7 fixes. Groups 8–9 (TCs 53–62) added to cover Phase 1 self-verification, full state machine, and D-series regression guards.*
