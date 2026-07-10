# Test Design: `agent_domains.keywords` Missing-Column Tolerance

**Feature:** `loadDomains()` in `memory/plugins/turn-context/src/domain-identifier.ts`
**Issue:** NOVA-Openclaw/nova-mind#384 (SE Run #355)
**Author:** Gem, QA Lead
**Status:** Design only — no implementation. Coder implements against this document.

---

## 1. Scope & Approach

### In Scope
- `loadDomains()` behavior across healthy schema, missing-column schema, and error conditions
- The new `information_schema.columns` detection-and-cache mechanism
- The "log exactly once per process lifetime" warning contract
- Interaction between the new column-check cache and the existing `DOMAIN_CACHE_TTL_MS` domain cache
- Concurrency safety of both caches under simultaneous `loadDomains()` calls
- Regression: zero behavior change on healthy schemas (this touches `identifyDomain()`, `matchKeywords()`, and `formatDomainContext()` transitively — those must not regress)

### Out of Scope
- `matchVectorSimilarity()` / embedding path (unaffected per requirements; only a smoke check needed)
- Part B (installer coverage across ecosystem DBs) — separate workstream, blocked on Victoria-instance access
- Generalizing the tolerance pattern to other columns (explicitly rejected by requirements #4)

### Test Levels
1. **Unit tests** (`src/domain-identifier.test.ts`, `node:test` + `node:assert/strict`, matching the `honorific-guard.test.ts` convention) — the primary vehicle. Requires a seam to inject/mock the pg client, since `getPool()` is a module-level singleton with no DI hook today. **Design note for Coder:** either (a) add a lightweight injectable client/query-fn parameter defaulted to `getPool()`, or (b) mock `./shared/pg-pool.ts` via `node:test`'s `mock.module()` (Node 22+ supports this; runtime here is Node v22.23.1, confirmed compatible). Prefer (b) if it avoids touching the public function signature — requirement #4 demands zero behavior change, and adding a parameter to `loadDomains()` (currently not exported) is safe either way since it's internal, but keep `identifyDomain()`'s public signature untouched.
2. **Integration tests** against a real Postgres instance on **nova-staging** (per standing instruction: staging only, never production) — used to validate the actual `information_schema.columns` query and the real `ALTER TABLE ... DROP COLUMN` schema-drift scenario end-to-end. This is the higher-confidence tier for the missing-column path since it exercises real Postgres error semantics (`42703 undefined_column`) rather than a mocked approximation.

### Entry Criteria
- Source change implemented per requirements #1–#4
- `npm run typecheck` clean
- Test DB fixture available on nova-staging with ability to create/drop the `keywords` column on a throwaway `agent_domains` table (or a dedicated test schema/table)

### Exit Criteria
- All test cases below pass
- `npm run build` clean, `dist/` updated
- No new warnings/errors in plugin logs when run against healthy `nova_memory` schema (manual smoke check)

---

## 2. Preconditions Common to All Cases

- Module state (`domainCache`, and the new column-detection cache/flag) is **module-scoped**, not per-call. Every test that depends on cache state must explicitly reset it. Since `node:test` runs each file in a fresh process by default (no shared state across files) but **shares state across `it()` blocks within the same file**, the test file MUST provide a reset hook.
  - **Design requirement for Coder:** export a test-only reset function (e.g., `__resetDomainCacheForTests()`) or restructure the cache into a small class/object that tests can instantiate fresh. Do not rely on process restarts to isolate `it()` blocks — that breaks the "warn once per process lifetime" test (case DI-013) which specifically needs cross-call persistence within one process, contrasted against tests that need isolation. Recommend: a reset function that clears **both** `domainCache` and the column-detection cache/warned-flag, called in a `beforeEach` for tests that need isolation, and deliberately NOT called for the two "once per lifetime" tests, which should run in their own `describe` block with controlled ordering (or in a dedicated test file so process boundaries do the isolation for free).
- Mock/stub `client.query()` to return controlled result sets or throw controlled errors (PG error code `42703` for undefined column) without a real DB connection, for the unit tier.
- Integration tier uses a real staging Postgres connection; schema mutations must run in a transaction or against a disposable test table and be cleaned up in `afterEach`/`afterAll`.

---

## 3. Test Cases

Numbering: `DI-0xx` (Domain Identifier).

### 3.1 Happy Path — Healthy Schema

**DI-001: Healthy schema, keywords populated → identical behavior to pre-fix code**
- Precondition: `agent_domains.keywords` column exists; mocked query returns rows with populated `TEXT[]` keywords.
- Input: call `loadDomains()` once (cold cache).
- Expected: Returns `DomainRow[]` with `keywords` arrays intact (non-empty, matching mock data). No warning logged. Query used is the **original column-inclusive** query (assert the SQL string sent to `client.query` contains `ad.keywords`).
- Pass/fail: Exact match on returned array shape/values; zero `console.warn` calls; correct query variant selected.

**DI-002: Healthy schema, column-detection query runs exactly once before/alongside the first `loadDomains()` call**
- Precondition: fresh module state.
- Input: call `loadDomains()` once.
- Expected: Exactly one `information_schema.columns` probe query is issued (assert via call-count on the mocked query fn, filtering for the probe SQL), in addition to the domain-fetch query.
- Pass/fail: Probe query call count === 1.

**DI-003: Healthy schema, second `loadDomains()` call within TTL → cache hit, no new queries at all**
- Precondition: DI-001 state (cache populated, `timestamp` fresh).
- Input: call `loadDomains()` again immediately.
- Expected: Returns identical (reference or deep-equal) data. Zero additional `client.query` calls of any kind (neither the probe nor the domain fetch) — matches pre-fix caching behavior.
- Pass/fail: Query call count after 2nd call === count after 1st call.

### 3.2 Missing-Column Path

**DI-010: Missing column detected via `information_schema.columns` → fallback query used, keywords=[] for all rows**
- Precondition: Mock the probe query to return zero rows (column absent) for `agent_domains.keywords`. Mock the fallback domain-fetch query (no `ad.keywords` in SELECT list) to return rows.
- Input: call `loadDomains()` cold.
- Expected: Returns `DomainRow[]` where every `keywords` field is `[]` (not `null`, not `undefined`). The fallback query variant is used — assert the SQL sent does **not** reference `ad.keywords`. `notes` and other fields still populated normally.
- Pass/fail: Every row's `keywords` is a `[]` array (strict equal, not just falsy); fallback SQL variant confirmed.

**DI-011: Missing column — `identifyDomain()` end-to-end still functions, embedding path unaffected**
- Precondition: Same as DI-010, plus a healthy mocked embedding/vector-similarity path.
- Input: call `identifyDomain("some message", undefined)` with the missing-column DB state.
- Expected: `matchKeywords()` returns an empty score map for all domains (since all `keywords` are `[]`), so `matchedBy` for any surfaced match must be `"vector"` only (never `"keyword"` or `"both"`) for this call. Vector-only matches surface normally if above `SIMILARITY_THRESHOLD`. No exception thrown.
- Pass/fail: Response contains no `matchedBy: "keyword"` or `"both"` entries; overall pipeline completes without throwing.

**DI-012: Missing column — real Postgres error `42703 undefined_column` on unguarded query is caught by the *detection* mechanism, not surfaced as a runtime failure per call (integration tier)**
- Precondition (staging DB): create a disposable table mirroring `agent_domains` minus the `keywords` column, or `ALTER TABLE ... DROP COLUMN keywords` on a throwaway copy.
- Input: call `loadDomains()` cold against this real connection.
- Expected: No `column ad.keywords does not exist` error propagates out of `loadDomains()`. Function returns normally with `keywords: []` on all rows.
- Pass/fail: No exception; return shape matches DI-010 expectations. This is the highest-value regression test — it's the literal bug from the issue, reproduced against real Postgres error semantics rather than a mock's approximation of them.

**DI-013: Warning logged exactly once per process lifetime, across multiple `loadDomains()` calls, even across cache-TTL boundaries**
- Precondition: Fresh process/module state (own `describe` block or own file — see §2 note on isolation). Missing-column condition mocked or real (staging).
- Input:
  1. Call `loadDomains()` (cold, missing column) → triggers detection + fallback.
  2. Call `loadDomains()` again after forcing `domainCache.timestamp` back past `DOMAIN_CACHE_TTL_MS` (simulate TTL expiry) → cache miss on domain data, but column-detection cache should **still** report "missing" without re-running the probe query (or if it re-checks, must not re-log).
  3. Call `loadDomains()) a third time similarly.
- Expected: `console.warn` (or whatever logger is used) is called **exactly once** total across all three calls, with a message naming the missing column (`agent_domains.keywords`) and remediation text (per the issue's example: `"[turn-context] agent_domains.keywords missing — keyword matching disabled; apply nova-mind schema migration"` or equivalent — assert on key substrings: `"keywords"`, `"missing"`, and some remediation-pointing phrase, not brittle full-string match).
- Pass/fail: Warn call count === 1 after 3+ `loadDomains()` invocations spanning TTL expiry.

**DI-014: Warning is `console.warn` (or equivalent), not `console.error` and not `console.info` — matches existing log-level conventions in the file**
- Precondition: Missing-column condition triggered.
- Expected: The one-time warning goes to the log level appropriate for a degraded-but-handled condition (warn), consistent with the file's existing use of `console.warn` for the embedding-fallback path in `identifyDomain()`. Do not use `console.error` (reserved for the DB-connection-failure path per DI-020) or `console.info` (reserved for normal successful loads, e.g. line ~92's `loaded N domains from DB`).
- Pass/fail: Assert the specific console method invoked matches `warn`.

### 3.3 Column-Check Cache × Domain Cache Interaction (Boundary/Timing)

**DI-020: Column-detection result is cached independently of (or alongside) `DOMAIN_CACHE_TTL_MS` — verify it does not silently re-probe every call once determined**
- Precondition: Missing-column condition.
- Input: Call `loadDomains()` 5 times in rapid succession, each time forcing the *domain* cache to expire (simulate TTL boundary) but WITHOUT resetting the column-detection cache.
- Expected: The `information_schema.columns` probe query is issued **at most once** (ideally exactly once) across all 5 calls — it should not re-run on every domain-cache refresh. This is the core efficiency/requirement-#1 assertion: "checked once and cached alongside the existing domain cache."
- Pass/fail: Probe query call count === 1 across 5 domain-cache-refresh cycles.

**DI-021: Column-detection cache and domain cache share the same TTL semantics (per requirement #1's "cached alongside")**
- Precondition: fresh state, healthy schema.
- Input: Call `loadDomains()`, wait/simulate exactly `DOMAIN_CACHE_TTL_MS - 1ms` → call again (cache hit expected, no new queries). Then simulate `DOMAIN_CACHE_TTL_MS + 1ms` → call again (cache miss expected, domain data re-fetched).
- Expected: At `TTL - 1ms`, no new queries of any kind. At `TTL + 1ms`, the domain-fetch query re-runs, but — per DI-020 — the column-detection probe does NOT necessarily need to re-run if the design caches the column-existence boolean for the process lifetime rather than tying it to the TTL. **Design ambiguity to flag to Coder:** requirement #1 says "cached alongside the existing domain cache" which could mean (a) same TTL window, re-probed on every domain-cache miss, or (b) determined once for process level and never re-probed. Given requirement #3 says "log exactly ONE warning **per process lifetime**," the more defensible interpretation is that the column-existence fact itself is a process-lifetime constant (schema doesn't change at runtime), and only the *warning* is deduped to one — but the probe query might legitimately re-run each TTL cycle as a cheap idempotent check. **This test should be written to match whatever the implementation decides, but the warning-once assertion (DI-013) must hold regardless of how many times the probe re-runs.** Recommend Coder default to: probe runs once, result cached process-lifetime (simplest, cheapest, matches "schema doesn't change under us" assumption implicit in the whole plugin's 5-minute domain cache design).
- Pass/fail: Warning count stays at 1 regardless of probe re-run frequency; domain data itself correctly refreshes at TTL boundary in both column states.

### 3.4 Error Conditions — Distinguish Missing-Column from Other Failures

**DI-030: DB connection failure (e.g., connection refused, pool exhausted) is NOT mistaken for a missing-column condition**
- Precondition: Mock `pool.connect()` to reject (e.g., `ECONNREFUSED`) or mock `client.query()` to throw a generic connection-level error (not PG code `42703`).
- Input: Call `loadDomains()`.
- Expected: The error propagates out of `loadDomains()` unchanged (existing `identifyDomain()` catch block at the call site already handles this by logging `console.error` and returning `NO_DOMAIN_IDENTIFIED` — that existing behavior must NOT regress). Crucially: NO fallback-to-no-keywords behavior should trigger, and NO "keywords missing" warning should be logged — this is a different failure class entirely.
- Pass/fail: Error is thrown/rejected from `loadDomains()`; no missing-column warning logged; existing `identifyDomain()` error handling still catches it and returns empty result with indicator.

**DI-031: Other missing-column errors (e.g., `ad.notes` hypothetically missing, or an unrelated column) are NOT silently swallowed by the keywords-specific tolerance**
- Precondition: Mock `client.query()` to throw PG error `42703` but with a *different* column name in the error detail (e.g., `column ad.notes does not exist`).
- Input: Call `loadDomains()`.
- Expected: Per requirement #4 ("do not generalize speculatively"), this error must propagate as a genuine failure — NOT be caught by the keywords-specific fallback logic. The detection mechanism should be scoped narrowly to check `agent_domains.keywords` specifically via `information_schema.columns`, not use a generic catch-and-retry-without-column pattern that would mask unrelated schema drift.
- Pass/fail: Error propagates (or is handled by the pre-existing generic error path in `identifyDomain()`, not the new keywords-fallback path). Assert no "keywords missing" warning is logged for this case — a different problem must not produce a misleading log message.

**DI-032: `information_schema.columns` probe query itself fails (e.g., transient connection blip during the probe)**
- Precondition: Mock the probe query specifically to throw.
- Input: Call `loadDomains()`.
- Expected: Defined behavior needed from Coder — recommend: treat probe failure as "assume column exists" (safe default, matches current/legacy behavior) rather than "assume missing," to avoid falsely disabling keyword matching on a transient blip. Document whichever choice is made; test should assert that choice explicitly and that no false "missing" warning fires from a transient probe failure alone (that would violate "exactly one warning ... naming the missing column" — a probe failure is not proof of an actual missing column).
- Pass/fail: Matches documented fallback behavior for probe failure; test asserts no false-positive missing-column warning from a transient probe error alone.

### 3.5 Boundary / Data-Shape Values

**DI-040: Empty `agent_domains` table (zero rows), healthy schema**
- Precondition: Healthy schema, query returns zero rows.
- Input: `loadDomains()`.
- Expected: Returns `[]` (empty array, not null/undefined). No error. `console.info` "loaded 0 domains from DB" (matches existing line ~92 log format — verify it still fires, unchanged).
- Pass/fail: Returns `[]`; existing info log still present; no missing-column warning (schema is healthy, this is a data-volume edge case, unrelated).

**DI-041: Empty `agent_domains` table, missing-column schema (combination boundary)**
- Precondition: Missing-column schema AND zero rows.
- Input: `loadDomains()`.
- Expected: Returns `[]`. The missing-column warning STILL fires once (column absence is a schema fact, independent of row count) — this exercises the intersection of two edge conditions.
- Pass/fail: Returns `[]`; warning fires exactly once; no crash from combining both edge conditions.

**DI-042: `keywords` column present but contains NULL for some/all rows (not literally missing, just null values) — pre-existing `?? []` handling must still work post-fix**
- Precondition: Healthy schema (column exists), but mocked rows have `keywords: null` for one or more rows, `keywords: ['foo','bar']` for others.
- Input: `loadDomains()`.
- Expected: Rows with `null` keywords normalize to `[]` (this is the **existing** `row.keywords ?? []` logic at line ~86 — verify it is preserved and not accidentally altered by the fix). Rows with populated keywords keep their values. This must NOT trigger the missing-column detection/warning path at all — the column exists, it's just nullable per-row.
- Pass/fail: Null-keyword rows → `[]`; populated rows unaffected; zero missing-column warnings (this is a different, pre-existing, already-handled case that must not regress).

**DI-043: `keywords` column present with an empty array `{}` (i.e., `TEXT[]` empty, not null) for some rows**
- Precondition: Healthy schema, mocked row with `keywords: []` explicitly (not null).
- Input: `loadDomains()`.
- Expected: Passes through as `[]` unchanged. `matchKeywords()` correctly skips domains with `!domain.keywords.length` (existing logic, unaffected).
- Pass/fail: `[]` in, `[]` out; no matches contributed by this domain in `matchKeywords()`.

### 3.6 Concurrency

**DI-050: Two simultaneous `loadDomains()` calls with a cold cache (both missing-column detection and domain cache cold) do not double-log the warning or issue redundant probe queries beyond what's acceptable**
- Precondition: Fresh module state, missing-column schema. Fire two `loadDomains()` calls back-to-back without awaiting the first (`Promise.all([loadDomains(), loadDomains()])`).
- Input: as above.
- Expected: This is the highest-risk race in the design — `loadDomains()` has no mutex/in-flight-promise dedup today (confirmed by reading the source: each call independently checks `domainCache` and, if stale/absent, calls `pool.connect()` and runs its own query). Without additional synchronization, **both concurrent calls will likely both detect "missing column" and both may log the warning**, violating requirement #3 ("exactly one warning per process lifetime"). Flag this explicitly to Coder: **the "exactly once" guarantee requires either (a) an in-flight promise/lock so concurrent callers await the same detection-and-log operation, or (b) a synchronous "already warned" flag checked-and-set atomically before the async work begins** (JS is single-threaded, so a simple boolean flag set *before* the first `await` in the detection function is sufficient — check-and-set on the same tick prevents the second concurrent call from re-triggering the warning, since Node has no true parallelism inside a single event-loop turn).
- Expected pass criteria: `console.warn` called exactly once even under concurrent cold-cache calls. Both calls still return correct, complete, non-throwing results (both get `keywords: []` domain rows).
- Pass/fail: Warn count === 1 after two concurrent cold calls; both promises resolve successfully with correct data.

**DI-051: Two simultaneous `loadDomains()` calls with a warm cache (post-detection) — no additional queries, no additional warnings, consistent data returned to both callers**
- Precondition: Cache already warm (column-detection done, domain cache fresh) from a prior call.
- Input: `Promise.all([loadDomains(), loadDomains()])`.
- Expected: Both resolve immediately from cache; zero additional queries; identical data returned to both.
- Pass/fail: Zero new queries; both results deep-equal; warn count unchanged from before this test's calls.

### 3.7 Regression / Zero-Behavior-Change Guard (Healthy Schema)

**DI-060: Full `identifyDomain()` pipeline on healthy schema produces byte-identical output pre-fix vs post-fix for a fixed input fixture**
- Precondition: Healthy schema, deterministic mocked domain rows + deterministic mocked embedding response.
- Input: `identifyDomain("test message with matching keyword", undefined)` run against a snapshot of expected pre-fix output (captured before the fix lands, or derived analytically from current logic).
- Expected: Identical `DomainMatch[]` (domain, agent, similarity, matchedBy) and identical `formatDomainContext()` output string.
- Pass/fail: Deep-equal match against the pre-fix golden output. This is the requirement #4 acceptance gate — run this as a blocking regression test in CI, not just exploratory.

**DI-061: `npm run build` / `npm run typecheck` clean after the change**
- Precondition: Fix implemented.
- Input: `npm run typecheck` and `npm run build` in the plugin directory.
- Expected: Exit code 0, no new TS errors, `dist/` reflects the change (per repo convention noted in the issue's acceptance criteria).
- Pass/fail: Both commands exit 0.

---

## 4. Definition of Done

All of the following must be true before this fix is considered QA-approved and ready for sign-off:

1. **All test cases DI-001 through DI-061 pass**, run via `npm test` (`tsx --test src/**/*.test.ts`) for the unit tier, plus the DI-012 integration case executed manually or via a staging-gated CI job against nova-staging Postgres.
2. **Zero regressions**: DI-060 golden-output comparison passes exactly; existing `honorific-guard.test.ts` suite (unrelated but same file glob) continues to pass unmodified.
3. **Exactly-once warning guarantee holds under concurrency** (DI-050) — this is the highest-risk part of the design and must not be waved through on "looks fine sequentially."
4. **No misclassification of unrelated errors** (DI-030, DI-031) — connection failures and non-keywords schema drift must not be silently absorbed by this fix's fallback path.
5. **`npm run typecheck` and `npm run build` clean** (DI-061).
6. **Manual smoke test** against real `nova_memory` (healthy schema, staging) confirms no new warnings/errors appear in plugin logs during normal operation.
7. **Manual smoke test** against a throwaway staging DB with `keywords` column dropped confirms: (a) plugin does not crash, (b) exactly one warning appears in logs across multiple turns/messages, (c) domain identification still functions via embeddings alone.
8. Design ambiguities flagged in DI-021 and DI-032 above are explicitly resolved by Coder (documented in code comments or PR description) and the corresponding tests updated to match the chosen behavior before merge — QA sign-off is contingent on these being *decided*, not left implicit.

Any failing test blocks PR sign-off. Any test that cannot be executed due to missing staging access (integration tier) must be explicitly waived by I)ruid with the gap documented, not silently skipped.
