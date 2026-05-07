# Test Cases: Issue #165 (Fix Memory Reinforcement) + Issue #138 (Source Pointers)

## TC-001 — New fact extraction with source pointers (happy_path)
**Description:** New fact extraction for a new entity stores the fact with correct source pointers (real-time hook path).
**Preconditions:** Clean entity_facts table, no entity for "TestUser123". Session with known sessionKey and timestamp active.
**Steps:**
1. Trigger real-time memory extraction hook with a message introducing a new fact ("TestUser123 likes hiking")
2. Run extract-memories.sh + store-memories.sh
**Expected Result:** New entity created; fact inserted with vote_count=1, source_session_id=<sessionKey>, source_timestamp=<message ts>.
**Verification:** `SELECT * FROM entity_facts WHERE ...` shows correct pointers; entity row exists.

## TC-002 — Duplicate fact triggers reinforcement (happy_path)
**Description:** Duplicate fact triggers reinforcement (vote_count++, last_confirmed, source pointer update) instead of suppression.
**Preconditions:** Fact already exists (vote_count=1) with old source pointers.
**Steps:**
1. Send new message containing the same fact
2. Run extraction + store pipeline
**Expected Result:** vote_count=2, last_confirmed updated to now, source pointers overwritten with latest session/timestamp. No duplicate row.
**Verification:** Query shows updated vote_count + source; no new fact row created.

## TC-003 — Duplicate vocabulary triggers reinforcement (happy_path)
**Description:** Duplicate vocabulary item triggers reinforcement (vote_count++) in store-memories.sh.
**Preconditions:** Vocabulary term exists with vote_count=1.
**Steps:**
1. Message introduces the same vocabulary term again
2. Run pipeline
**Expected Result:** Existing vocab row reinforced (vote_count++, last_confirmed updated); not skipped.
**Verification:** Query vocabulary table; confirm vote_count incremented.

## TC-004 — Duplicate opinion/preference triggers reinforcement (happy_path)
**Description:** Duplicate opinion/preference triggers reinforcement.
**Preconditions:** Opinion row exists (vote_count=1).
**Steps:**
1. Message restates the same opinion
2. Run pipeline
**Expected Result:** vote_count++, timestamps/source updated; no suppression.
**Verification:** SELECT from entity_facts confirms reinforcement.

## TC-005 — Brand new entity auto-creation with source pointers (boundary)
**Description:** Source pointers recorded correctly on first extraction for a brand-new entity.
**Preconditions:** No existing entity or facts. Real-time hook path.
**Steps:**
1. First message about a completely new person + fact
2. Run pipeline
**Expected Result:** Entity auto-created + fact with valid non-null source_session_id and source_timestamp.
**Verification:** Foreign key + pointer columns populated; no NULLs.

## TC-006 — Empty extraction completes cleanly (edge_case)
**Description:** Empty extraction (LLM returns no facts/vocab/opinions) completes without error or side effects.
**Preconditions:** Message with no extractable memory content.
**Steps:**
1. Run extract-memories.sh with trivial message (LLM returns {})
2. Run store-memories.sh
**Expected Result:** No new rows, no errors, pipeline exits cleanly (exit 0).
**Verification:** Check logs + row counts unchanged; no crash.

## TC-007 — Malformed JSON handled gracefully (edge_case)
**Description:** Malformed JSON from LLM is handled gracefully (no crash, no partial inserts).
**Preconditions:** Force LLM to return invalid JSON (or mock).
**Steps:**
1. Run extract-memories.sh with input that produces bad JSON
**Expected Result:** Script logs error, skips bad payload, exits non-zero or with clear warning; no corrupted DB state.
**Verification:** Logs contain parse error message; DB unchanged.

## TC-008 — Missing session_id or timestamp (edge_case)
**Description:** Missing session_id or timestamp (nullable columns) — pipeline still succeeds.
**Preconditions:** Simulate extraction path with missing session context.
**Steps:**
1. Call store-memories.sh with SOURCE_SESSION_ID unset or SOURCE_TIMESTAMP unset
**Expected Result:** Fact stored; nullable columns accept NULL gracefully; no constraint violation.
**Verification:** Insert succeeds; SELECT shows NULLs where expected.

## TC-009 — Very long source_session_id (edge_case)
**Description:** Very long source_session_id (or edge values) stored without truncation/error.
**Preconditions:** Generate 500+ char session ID value.
**Steps:**
1. Pass long ID through pipeline
**Expected Result:** Full value stored (text column, no length limit); no DB error.
**Verification:** Length check + round-trip SELECT.

## TC-010 — EXISTING_FACTS/VOCAB queries removed (regression)
**Description:** EXISTING_FACTS and EXISTING_VOCAB queries removed from extract-memories.sh.
**Preconditions:** Post-fix code.
**Steps:**
1. `grep -E "EXISTING_FACTS|EXISTING_VOCAB" memory/scripts/extract-memories.sh`
**Expected Result:** No matches.
**Verification:** Grep returns 0 lines.

## TC-011 — Dedup prompt section removed (regression)
**Description:** LLM extraction prompt no longer contains DEDUPLICATION section or "skip facts that already exist" language.
**Preconditions:** Post-fix code.
**Steps:**
1. Inspect the PROMPT variable in extract-memories.sh
**Expected Result:** No dedup instructions. Prompt just says "extract all relevant facts."
**Verification:** Visual + grep for "DEDUPLICATION", "Skip any fact", "DO NOT EXTRACT if we already have".

## TC-012 — Real-time hook passes session context (integration)
**Description:** Real-time hook path correctly passes sessionKey + message timestamp to extraction scripts.
**Preconditions:** Active OpenClaw session context.
**Steps:**
1. Trigger memory-extract hook
2. Inspect environment variables passed to extract-memories.sh
3. Verify downstream store
**Expected Result:** source_session_id = sessionKey, source_timestamp = message ts in final DB record.
**Verification:** Log inspection + final DB query.

## TC-013 — Batch catchup passes session context (integration)
**Description:** Batch catchup path derives session_id from session file path/filename and passes timestamp.
**Preconditions:** Historical session files present.
**Steps:**
1. Run memory-catchup.sh on a known session file
**Expected Result:** source_session_id derived from filename (UUID portion), timestamp populated from message.
**Verification:** DB record matches expected session metadata.

## TC-014 — Privacy detection and delegation context survive prompt changes (regression)
**Description:** Privacy detection (visibility cues, default_visibility lookup) and delegation context extraction still function correctly after dedup section removal.
**Preconditions:** Post-fix code. Entity with default_visibility set.
**Steps:**
1. Send message with privacy cue ("just between us, I got a raise")
2. Send message with delegation context ("Let me get Coder to help with this")
3. Run extraction pipeline for both
**Expected Result:** Privacy cue message → fact stored with visibility=private. Delegation message → delegation fact stored with visibility=public. Both sections of the prompt function as before.
**Verification:** SELECT from entity_facts confirms correct visibility on both facts; prompt inspection confirms PRIVACY DETECTION and DELEGATION CONTEXT sections intact.

## TC-015 — Grammar parser removed from extraction pipeline (regression)
**Description:** process-input-with-grammar.sh is no longer the entry point; memory-extract hook calls extract-memories.sh directly (or via process-input.sh).
**Preconditions:** Post-fix code.
**Steps:**
1. Check memory-extract/handler.ts for script path
2. Verify it no longer references process-input-with-grammar.sh
3. Trigger extraction and confirm LLM runs directly without grammar parser stage
**Expected Result:** No grammar parser invocation. LLM extraction runs on every message. extraction_metrics shows no "grammar" or "grammar_failed" entries for new extractions.
**Verification:** Grep handler.ts for grammar references; check extraction_metrics for method values on new runs.

## TC-016 — Extraction model switched to Gemini 2.5 Flash (happy_path)
**Description:** extract-memories.sh uses Gemini 2.5 Flash instead of Claude Sonnet 4.
**Preconditions:** Gemini API key configured. Post-fix code.
**Steps:**
1. Trigger extraction with a test message
2. Check extraction output for valid JSON with correct structure
3. Compare latency and relation count against Sonnet 4 benchmarks (avg 3.0 relations, 4.7s latency)
**Expected Result:** Valid extraction JSON. Comparable or better relation count. Faster latency expected. Cost per call ~$0.0003 vs $0.0075.
**Verification:** extraction_metrics row shows new model timing; output JSON validates against expected schema.

## TC-017 — Extraction model is configurable (happy_path)
**Description:** Extraction model can be changed via configuration without editing script source code.
**Preconditions:** Configuration mechanism exists (env var, config file, or openclaw.json parameter).
**Steps:**
1. Check where model is configured
2. Change to a different model value
3. Run extraction and verify the new model is used
4. Revert to Gemini 2.5 Flash
**Expected Result:** Model is not hardcoded; changing config changes the model used. Script reads from config at runtime.
**Verification:** Grep extract-memories.sh for hardcoded model strings — should find config lookup, not a literal model name.

## TC-018 — Gemini Flash handles all extraction categories correctly (regression)
**Description:** Gemini 2.5 Flash produces the same extraction categories as Sonnet 4 (entities, facts, opinions, preferences, vocabulary, events).
**Preconditions:** Test messages covering each extraction category.
**Steps:**
1. Send message with a new entity mention → verify entities extracted
2. Send message with a fact → verify facts extracted
3. Send message with an opinion → verify opinions extracted
4. Send message with a preference → verify preferences extracted
5. Send message with a vocabulary term → verify vocabulary extracted
6. Send message with an event → verify events extracted
**Expected Result:** All six extraction categories work with the new model. JSON structure matches expected schema.
**Verification:** Each category present in extraction output; stored correctly in database.

## TC-019 — Source pointer race: latest extraction wins (integration/edge_case)
**Description:** Source pointer update during reinforcement always reflects the latest source when real-time and batch paths both extract the same fact.
**Preconditions:** Fact already exists with old session_id + timestamp. A newer real-time extraction runs, followed by an older batch catchup touching the same fact.
**Steps:**
1. Run real-time extraction (newer timestamp, sessionKey-A)
2. Run batch catchup using older session file (sessionKey-B, older ts)
3. Query entity_facts for the fact
**Expected Result:** Final source_session_id = sessionKey-A and source_timestamp = newer value (latest extraction wins). No data loss or duplication.
**Verification:** SELECT shows latest pointers; extraction_metrics shows both runs completed.

## TC-020 — Schema migration rollback safety (regression)
**Description:** Schema migration rollback does not break the pipeline or leave orphaned pointers.
**Preconditions:** Migration adding source_session_id + source_timestamp has been applied. DB has facts with pointers.
**Steps:**
1. Run migration downgrade to pre-pointer schema
2. Run extraction + store pipeline on new content
3. Re-apply forward migration
**Expected Result:** Rollback succeeds cleanly; new facts insert without pointer columns; re-apply succeeds and existing pointers preserved where possible.
**Verification:** Migration logs clean; post-rollback query shows no errors; re-forwarded pointers match original data.

## TC-021 — Gemini Flash API unavailable — graceful failure (edge_case/error_handling)
**Description:** Extraction model API unavailable triggers graceful failure, no partial facts stored.
**Preconditions:** Valid config pointing to Gemini 2.5 Flash; artificially invalidate API key.
**Steps:**
1. Trigger extraction with Gemini configured
2. API call fails (simulate 401/429/timeout)
3. Inspect handler + store behavior
**Expected Result:** Pipeline logs clear error; no partial facts stored; message not silently dropped.
**Verification:** extraction_metrics shows failed attempt; DB contains no malformed rows; hook does not crash.

## TC-022 — Invalid extraction model config (edge_case)
**Description:** Config parameter validation handles invalid extraction model names gracefully.
**Preconditions:** Configuration mechanism exists.
**Steps:**
1. Set extraction model config to invalid value
2. Trigger extraction
**Expected Result:** Script fails with clear error; falls back to default or exits non-zero without corrupting state.
**Verification:** Error message logged; no extraction call sent; no DB corruption.

## TC-023 — Extraction quality parity: Gemini Flash vs Sonnet 4 baseline (regression)
**Description:** Gemini Flash produces comparable extraction quality to prior Sonnet 4 runs on a standardized test corpus.
**Preconditions:** Frozen set of 20-30 diverse test messages. Sonnet 4 baseline benchmarks (avg 3.0 relations, 4.7s latency).
**Steps:**
1. Run full extraction on gold corpus with Gemini Flash
2. Compare category counts + relation quality against Sonnet 4 baseline
**Expected Result:** ≥95% category coverage parity; average relations per message within ±0.5 of baseline. Latency ≤ 60% of Sonnet 4.
**Verification:** extraction_metrics aggregated shows model + avg_relations + latency comparison.
