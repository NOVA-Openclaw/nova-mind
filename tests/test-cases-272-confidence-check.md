# Test Cases — Issue #272: Response Confidence Scoring & LLM Iteration

**Plugin:** `confidence-check` (nova-mind/cognition/metacognition/confidence-check)  
**QA Lead:** Gem  
**Feature branch:** `feature/issue-272-confidence-check-enhancement`  
**Commits:** 25e5514, 62f7e48, d6d3ea2  
**Total test cases:** 52  
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

---

## Group 1: Heuristic Pre-Screen

### TC-272-01: Auto-pass — zero hedging, zero unsupported assertions
**Description:** A factual, confident response with no hedging phrases and all sentences cited or hedged should auto-pass without calling LLM.  
**Preconditions:** Plugin initialized with default CONFIG.  
**Input:**
```
message: "2 + 2 = 4. According to mathematics, this is definitively true."
event.messages: []
```
**Expected:**
- hedging_count = 0, hedging_density = 0.000
- unsupported_assertions < 3
- Returns `undefined` (auto-pass, no LLM call)
- Log: "[confidence-check] Auto-pass (low hedging, few assertions)"

**Pass criteria:** `undefined` returned; no LLM invocation.

---

### TC-272-02: Auto-pass — hedging density strictly below threshold (BVA lower boundary)
**Description:** BVA on hedging_density_pass_threshold = 0.02. At density 0.0199 → auto-pass.  
**Input:**
```
message: <word sequence with hedging_density ≈ 0.019 AND unsupported_assertions ≤ 2>
```
**Expected:** Returns `undefined` (auto-pass).  
**Note:** Exact density depends on phrase/word distribution. Use a controlled 100-word message with 1 hedging phrase = density 0.01.

---

### TC-272-03: Not auto-pass — hedging density at pass threshold (BVA: at boundary)
**Description:** BVA on hedging_density_pass_threshold = 0.02. At density exactly 0.020 → NOT auto-pass → proceed to LLM.  
**Input:**
```
message: <100-word message with exactly 2 hedging phrase matches>
unsupported_assertions ≥ 3
```
**Expected:** Auto-pass NOT triggered; LLM evaluation called.

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

### TC-272-06: Auto-pass — unsupported_assertions exactly 2 (BVA: below 3)
**Description:** Low hedging AND assertions=2 → auto-pass.  
**Input:** Message where runHeuristicScreen returns unsupported_assertions=2, hedging_density<0.02.  
**Expected:** Returns `undefined`.

---

### TC-272-07: Not auto-pass — unsupported_assertions exactly 3 (BVA: at boundary)
**Description:** assertions=3 means condition `< 3` is false → not auto-pass → proceed to LLM.  
**Input:** Message where unsupported_assertions=3, hedging_density<0.02.  
**Expected:** LLM evaluation called.

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

### TC-272-36: Non-string content assistant messages skipped
**Description:** Assistant message where content is not a string (e.g., content = [{type:"text", text:"..."}]) → skipped.  
**Input:** `{ role: "assistant", content: [{ type: "text", text: "Hello" }] }`.  
**Expected:** Not added to priorAssistantMessages (typeof m.content !== "string").

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

### TC-272-38: JSON in markdown code block parsed correctly
**Description:** LLM wraps JSON in ````json ... ```` block → strip markers, parse.  
**Input LLM response:**
```
```json
{"confidence": 65, "concerns": [], "reasoning_strategies": []}
```
```
**Expected:** { confidence: 65, concerns: [], reasoning_strategies: [] }. No parse error.

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

### TC-272-44: Confidence < threshold → Socratic questioning instruction
**Description:** LLM returns confidence=70 (< 85 threshold) on first attempt → Socratic revision instruction returned.  
**Input:** priorAttempts = 0, LLM returns confidence = 70.  
**Expected:**
- retryAttempts.get(idempotencyKey) = 1 (incremented)
- Returns `{ action: "revise", retry: { instruction: "Your self-assessment scored 70% confidence (threshold: 85%)...\nConcerns:\n...\nWhat assumptions are you making..." } }`
- Log: "FAIL — confidence 70% < threshold 85. Triggering revision (attempt 1/3)"

---

### TC-272-45: Second revision attempt tracked correctly
**Description:** On attempt 2, priorAttempts = 1 → attemptsRemaining = 2.  
**Input:** priorAttempts = 1 (retryAttempts.get() = 1), LLM returns confidence = 60.  
**Expected:**
- retryAttempts.get(idempotencyKey) = 2 after this call
- Instruction mentions "(2 revision attempt(s) available)"
- Log: "Triggering revision (attempt 2/3)"

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

### TC-272-48: Confidence ≥ threshold → PASS, return undefined
**Description:** LLM returns confidence=90 (≥ 85) → PASS, no revision.  
**Input:** priorAttempts = 0, LLM returns confidence = 90.  
**Expected:**
- Returns `undefined`
- retryAttempts NOT modified
- Log: "[confidence-check] PASS — confidence above threshold"

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

## Exit Criteria

All of the following must be true before this feature is approved for merge:

1. TC-272-01, TC-272-08, TC-272-11, TC-272-13, TC-272-20, TC-272-22: PASS (basic auto-pass + citation extraction)
2. TC-272-33: PASS (commit 62f7e48 regression guard — current response filter)
3. TC-272-39: PASS (commit d6d3ea2 regression guard — result.text fix)
4. TC-272-44, TC-272-46, TC-272-47, TC-272-48: PASS (full revision lifecycle)
5. TC-272-52: PASS (error resilience — gateway must not crash)
6. All S1/S2 defects resolved; no open P1/P2 bugs
7. No regression on previously passing integration tests
