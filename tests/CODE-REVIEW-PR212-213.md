# Code Review: PRs #212 & #213 — extraction_memories.py

**Reviewer:** Coder  
**Date:** 2026-05-14  
**Branch reviewed:** `main` (commits `0e2fd9b`..`ee1ad0a`)  
**Fix branch:** `fix/extraction-review-cleanup`

---

## Summary

PRs #212 and #213 successfully implement the unified extraction output and sender-only source attribution. The code is functionally correct. One minor cleanup was identified and fixed.

---

## Verification Checklist

| # | Check | Status | Notes |
|---|-------|--------|-------|
| 1 | Prompt template has no `source_person` | ✅ PASS | Template uses `subject` only. No `source_person` field. |
| 2 | Rules instruct LLM not to include `source_person` | ✅ PASS | Line 573: explicit rule. Line 500: prompt note. |
| 3 | `_store_fact()` doesn't take `source_person` | ✅ PASS | Signature removed in PR #213. |
| 4 | `_store_fact()` always uses pre-resolved `source_entity_id` | ✅ PASS | Resolved once at top of `store_extracted()`. Passed through to `store_or_reinforce_fact()`. |
| 5 | `store_or_reinforce_fact()` upserts `entity_fact_sources` on both paths | ✅ PASS | Reinforce path (line 396) and create path (line 441) both have correct `ON CONFLICT DO UPDATE`. |
| 6 | Facts loop reads `key` (with `predicate` fallback) | ✅ PASS | Line 727: `key = (fact.get("key") or fact.get("predicate") or "").strip()` |
| 7 | No orphaned references to removed sections | ✅ PASS | No loops for `opinions`, `preferences`, `decisions`, `milestones`, `problems`. |
| 8 | Events and vocabulary loops still work | ✅ PASS | Events store to `events` table. Vocabulary stores to `vocabulary` table. Both functional. |
| 9 | No stale `source` column refs on `entity_facts` | ⚠️ FIXED | `store_or_reinforce_fact()` accepted a `source` param but never used it in the INSERT (column was dropped in #207). **Cleaned up in `fix/extraction-review-cleanup`.** |

---

## Bug/Gap Analysis

### Issue Found: Dead `source` parameter (cleanup, not runtime bug)

**Location:** `store_or_reinforce_fact()` line 356, call site line 702

**Problem:** After the `entity_facts.source` column was dropped (#207), PRs #212/#213 removed `source_person` from the LLM output but left a dead `source: str` parameter in `store_or_reinforce_fact()`. The parameter was passed (`source=sender_name or "auto-extracted"`) but never referenced in the function body for `entity_facts` INSERT/UPDATE. This is harmless at runtime but is stale technical debt.

**Fix:** Removed the parameter from the function signature and all call sites.

**Commit:** `2e94a69` on branch `fix/extraction-review-cleanup`

---

## Additional Checks

- **Syntax:** `python3 -m py_compile` passes ✅
- **Source attribution coverage:** No code path misses source attribution. `source_entity_id` is resolved once at the top of `store_extracted()` and passed to every `_store_fact()` call. The only way source attribution is skipped is if `source_entity_id` resolves to `None`, in which case `entity_fact_sources` insertion is guarded by `if source_entity_id is not None`. This is correct behavior for unresolvable senders.
- **Prompt clarity:** The prompt correctly distinguishes `subject` (who the fact is ABOUT) from sender (who said it, handled in code). No contradictions found.
- **Phone privacy hard rule:** Still enforced in the facts loop (`if key == "phone": visibility = "private"`). ✅

---

## Recommendation

Merge `fix/extraction-review-cleanup` (commit `2e94a69`) to remove the dead parameter. Otherwise, the extraction pipeline is clean and correct.
