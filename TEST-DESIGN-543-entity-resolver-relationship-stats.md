# Test Design: Entity Resolver Pronoun Injection + Relationship/Stats Summary

**Feature:** `getEntityProfile()` (or new sibling function) in `relationships/lib/entity-resolver/resolver.ts` (installed copy: `~/.openclaw/lib/entity-resolver/resolver.ts`), consumed by `resolveEntityContext()`/`formatEntityContext()` in `memory/plugins/turn-context/src/entity-resolver.ts`.
**Issue:** NOVA-Openclaw/nova-mind#543 (SE Workflow run #513, Step 3 — QA Test Design)
**Author:** Gem, QA Lead
**Status:** Design only — no implementation. Coder implements against this document.

---

## 1. Scope & Approach

### 1.1 Feature Under Test (from issue body + 2026-07-28 I)ruid directive comment)

1. Inject `entities.pronouns` into the 👤 **Talking with:** block.
2. Add a relationship/stats summary line pulled cheaply at resolution time:
   - `entity_facts` count for the entity
   - Last message timestamp + reference pointer (most recent `channel_transcripts` row for `sender_entity_id` → `timestamp` + `provider:external_chat_id` from the joined `channel_sessions` row)
   - `entities.trust_level`
   - `entities.last_seen`
   - `entities.created_at` → relationship age / "first seen"
3. Target format (from issue):
   ```
   👤 Talking with: Tabatha Janell Wilson (she/her) — trust: friend
   📊 Known contact: 48 facts · first seen 2026-01-30 · last message 2026-07-27 02:11 UTC (discord:1513392492651872306)
   ```
4. Single aggregate query preferred over N lookups; must fit inside the **existing 1s `Promise.race` timeout budget** in `resolveEntityContext()`.

### 1.2 Where the Fix Lands

- **Source of truth:** `/home/nova/nova-mind/relationships/lib/entity-resolver/resolver.ts` (+ `types.ts`, `index.ts` for exports). This is deployed/installed to `~/.openclaw/lib/entity-resolver/`. Both copies are currently byte-identical (`diff` confirmed) — the deploy step is out of scope for this test design but **must be verified as a manual/CI step** so the installed copy doesn't drift from the fix (this drift already caused issues in this codebase's history; see `types.ts`/`resolver.ts` parity check in Definition of Done).
- **Consumer:** `/home/nova/nova-mind/memory/plugins/turn-context/src/entity-resolver.ts` — `formatEntityContext()` (pure formatting) and `resolveEntityContext()` (orchestration + timeout race).
- **New test file (unit tier):** `memory/plugins/turn-context/src/entity-resolver.test.ts` (does not exist yet — new file, following the `node:test` + `node:assert/strict` convention already used in `index.test.ts` and `honorific-guard.test.ts`).
- **New/extended test file (integration tier, live-DB):** `relationships/lib/entity-resolver/test.ts` (existing file, extend with a new `runRelationshipStatsTests()` block following the existing seed/cleanup/`check()` pattern already used for `--irc-tests`).

### 1.3 In Scope
- `formatEntityContext()` output shape/text for all pronoun and stats-line permutations (unit, pure function — no DB needed for most cases).
- The new aggregate query (whatever it's named, e.g. `getEntityRelationshipStats()` or folded into `getEntityProfile()`) — correctness, single-round-trip design, index usage, timeout behavior.
- Interaction with the existing 1s `Promise.race` in `resolveEntityContext()` — does the new query run inside the same race, a separate race, or sequentially after the existing facts race (affects total worst-case latency — flagged as an open question below).
- `resolveEntityForGuard()` non-regression (#421) — the lightweight guard path must NOT pick up the new query.
- Cache key behavior (#150) — cached `Entity` object shape changes (now carries pronouns/trust_level/last_seen/created_at); must not leak across senders in group channels.
- Privacy/visibility decision for the fact count (decided below, §5).

### 1.4 Out of Scope
- `resolveEntity()` / `resolveEntityByIdentifiers()` identifier-matching logic itself — unchanged, already covered by `--irc-tests` and other existing suites.
- Extending the profile-facts allowlist (nova-mind#543's own "Proposal option 1" — widening the 7-key allowlist) — that is a **separate, not-mutually-exclusive** proposal per the issue and is NOT part of this spec expansion. Do not conflate; flag if implementation scope-creeps into it.
- IRC/Discord/Slack channel-ref formatting nuances beyond `provider:external_chat_id` (see open question on thread refs).
- Daily-report consumption of the new fields (downstream feature, separate issue potential).

### 1.5 Test Levels

1. **Unit tests** (`entity-resolver.test.ts`, `node:test` + `node:assert/strict`, matching `honorific-guard.test.ts` convention):
   - `formatEntityContext()` is a pure function — test with hand-built `Entity`/`EntityFacts`-plus-stats objects, no DB, no mocking needed. This is the primary vehicle for the formatting matrix (§4.1–4.3).
   - `resolveEntityContext()` / `resolveEntityForGuard()` orchestration tests require a seam to inject/mock the pg client or the new stats-fetch function, since `getDbPool()` is a module-level singleton with no DI hook today (same limitation flagged in the prior `agent_domains.keywords` test design for `loadDomains()`). **Design note for Coder:** either (a) export the new stats-fetch function separately so the turn-context test file can mock it at the module-import boundary (`node:test`'s `mock.module()`, Node 22+, confirmed compatible — matches the recommendation already given for `domain-identifier.test.ts`), or (b) accept an injectable query-fn parameter. Prefer (a) — keeps `resolver.ts`'s public API surface stable.
2. **Integration tests** against **nova-staging** (SSH `nova-staging@localhost` — never production; see standing instruction) — validates the real aggregate query (JOIN correctness, `LATERAL` join behavior if used, index usage via `EXPLAIN`, actual PG error semantics for timeout/connection failure). Extend `relationships/lib/entity-resolver/test.ts` with a new test block following the existing `testEntityIds` seed/cleanup pattern (use a fresh non-overlapping ID range, e.g. `99101`–`99110`, to avoid collision with the existing `--irc-tests` range `99001`–`99007`).

### 1.6 Entry Criteria
- Source change implemented per requirements in §1.1
- `npm run typecheck` clean in both `relationships/lib/entity-resolver/` and `memory/plugins/turn-context/`
- Staging DB reachable with ability to seed/clean disposable test entities, facts, channel_sessions, and channel_transcripts rows

### 1.7 Exit Criteria
- All test cases below pass
- `npm run build` clean in both packages; `dist/` updated for `turn-context` (per repo convention — `dist/entity-resolver.js` must reflect source changes, confirmed via the existing `dist/` mirror already present)
- Installed copy at `~/.openclaw/lib/entity-resolver/resolver.ts` matches the `nova-mind` repo source (parity check — no drift)
- No new warnings/errors in plugin logs when run against healthy `nova_memory` schema (manual smoke check)
- Total P99 latency contribution of the new query stays within the existing 1s budget under realistic staging load (see §4.6 performance cases)

---

## 2. Preconditions Common to All Cases

- `Entity` type (in `types.ts`) will need to widen to carry `pronouns`, `trustLevel`, `lastSeen`, `createdAt` (naming TBD by Coder — flagged as open question). Tests must be written against whatever field names Coder settles on; this document uses `pronouns`, `trustLevel`, `lastSeen`, `createdAt` as placeholders.
- The turn-context `entity-resolver.ts` dynamically imports the resolver lib at runtime (`ensureEntityResolver()`); unit tests for `formatEntityContext()` do NOT need this import path since the function is pure and can be tested directly against manually constructed inputs — no live import/mocking required for the formatting matrix.
- Integration-tier tests must seed disposable `channel_sessions` + `channel_transcripts` rows in addition to `entities`/`entity_facts`, and clean up all four tables in `finally`/`cleanup()` (extending the existing pattern, which currently only touches `entities`/`entity_facts`).
- Cache tests (§4.5) must call `clearCache()` before each test to avoid cross-test contamination (same requirement noted implicitly by the existing cache test in `test.ts`).

---

## 3. Data Model Reference (from schema, for test-input construction)

- `entities.pronouns` — `varchar(50)`, nullable, no default.
- `entities.trust_level` — `varchar(20)`, **default `'unknown'`** (never NULL for entities created after this default existed; may be NULL for pre-existing rows if explicitly set NULL — treat both as a possible edge case).
- `entities.last_seen` — `timestamp`, nullable, no default (NULL until first observed interaction is recorded by whatever process maintains it — brand-new entities will have NULL here even if `created_at` is populated).
- `entities.created_at` — `timestamp DEFAULT CURRENT_TIMESTAMP` — effectively never NULL.
- `entity_facts` — one row per fact; `entity_id` FK; count via `COUNT(*) WHERE entity_id = $1` uses `idx_entity_facts_entity`.
- `channel_transcripts.sender_entity_id` — nullable `bigint` FK to `entities.id`; `(sender_entity_id, timestamp)` composite index exists (`idx_channel_transcripts_sender_entity`) — ideal for `ORDER BY timestamp DESC LIMIT 1` per entity.
- `channel_sessions` — `provider`, `external_chat_id`, `external_thread_id` (nullable). The example ref `discord:1513392492651872306` looks like `provider:external_chat_id`. **Open question:** does `external_thread_id` need to be included when present (e.g. a Discord thread or Slack thread reply)? See §6.

---

## 4. Test Cases

Numbering: `RS-0xx` (Relationship Stats).

### 4.1 Happy Path — Pronoun Injection

**RS-001: Pronouns present → rendered in parenthetical after display name**
- Input: `entity = { name: "Tabatha Janell Wilson", fullName: "Tabatha Janell Wilson", pronouns: "she/her", ... }`.
- Expected: `formatEntityContext()` output line 1 is `👤 **Talking with:** Tabatha Janell Wilson (she/her)` (exact spacing/parenthetical placement per the issue's example — note the example shows plain-text `👤 Talking with:` without markdown bold, but the *existing* code uses `**Talking with:**`; Coder must preserve existing markdown bold convention unless explicitly told to drop it — flag as open question, see §6).
- Pass/fail: exact string match on the header line.

**RS-002: Pronouns present + trust_level present → trailing " — trust: X" suffix**
- Input: `pronouns: "she/her"`, `trustLevel: "friend"`.
- Expected: header line ends with ` — trust: friend` per the issue's example format.
- Pass/fail: exact string match.

**RS-003: Full stats line renders all four data points in the documented order**
- Input: `factCount: 48`, `createdAt: 2026-01-30T...`, `lastMessage: { timestamp: 2026-07-27T02:11:00Z, ref: "discord:1513392492651872306" }`.
- Expected: second line reads `📊 Known contact: 48 facts · first seen 2026-01-30 · last message 2026-07-27 02:11 UTC (discord:1513392492651872306)` — verify separator (`·`), date formats (`YYYY-MM-DD` for first-seen, `YYYY-MM-DD HH:MM UTC` for last-message), and parenthetical ref.
- Pass/fail: exact string match (format-sensitive — this is a golden-output test).

**RS-004: Existing fact-key bullet list (from `getEntityProfile()`'s existing 7-key allowlist) still renders below the new stats line, unchanged**
- Input: entity with pronouns + stats + at least one existing profile fact (e.g. `timezone: "America/Chicago"`).
- Expected: `• **Timezone:** America/Chicago` bullet still appears, in its existing position/format, after the new stats line. This is the regression guard for the untouched allowlist-fact rendering path.
- Pass/fail: bullet list content and position unchanged from pre-fix behavior.

### 4.2 Edge Cases — Missing/Null Fields

**RS-010: NULL pronouns → no parenthetical, header line degrades gracefully to name only**
- Input: `pronouns: null` (or field absent).
- Expected: `👤 **Talking with:** Tabatha Janell Wilson` — no trailing `()`, no dangling space, no `undefined`/`null` string literal leaking into output.
- Pass/fail: exact string match; explicit assertion that output does NOT contain the substrings `"null"`, `"undefined"`, or `"()"`.

**RS-011: NULL trust_level → header line has no " — trust: ..." suffix (vs. rendering "trust: unknown")**
- **Decision required from Coder, flagged in §6.** This document recommends: only render the trust suffix when `trust_level` is a *meaningful* value (i.e., NOT `'unknown'` and NOT NULL), since `'unknown'` is the column default and conveys no information — showing "trust: unknown" for every never-assessed entity is noise, not signal. Test asserts the recommended behavior; if Coder chooses differently, this test must be updated to match and the decision documented in code comments.
- Input: `trustLevel: "unknown"` (the DB default) and separately `trustLevel: null`.
- Expected (recommended): header line omits the trust suffix entirely in both cases.
- Pass/fail: header line has no `" — trust:"` substring for either input.

**RS-012: Zero entity_facts, but transcripts + entity metadata present → stats line renders "0 facts", not omitted**
- Input: `factCount: 0`, other stats populated.
- Expected: `📊 Known contact: 0 facts · first seen ... · last message ...` — the stats line still renders (it's not solely about the fact count; last-seen/trust/age are independently useful) unless Coder decides zero-facts-and-zero-transcripts should suppress the whole line (see RS-014).
- Pass/fail: stats line present, `"0 facts"` literal substring, no crash.

**RS-013: No channel_transcripts rows for entity (never messaged, or pre-dates transcript logging) → "last message" segment omitted or shows a defined fallback**
- Input: `lastMessage: null` (aggregate query's LEFT JOIN found no row).
- Expected: stats line omits the `· last message ... (...)` segment cleanly (no trailing `·` with nothing after it, no `null`/`undefined` leaking). Recommended rendering: `📊 Known contact: 48 facts · first seen 2026-01-30` (stats line ends after first-seen).
- Pass/fail: no dangling separator, no `null`/`undefined` substrings, first-seen segment still present if `createdAt` is available.

**RS-014: Brand-new entity — zero facts, NULL last_seen, no transcripts, created_at = now (degenerate case, the actual "new Discord contact" scenario from the issue's root-cause narrative)**
- Input: `factCount: 0`, `lastSeen: null`, `lastMessage: null`, `createdAt: <recent timestamp>`, `trustLevel: "unknown"`, `pronouns: null`.
- Expected: This is the exact inverse of the bug this feature fixes — a genuinely new contact SHOULD render as sparse/new-looking (e.g. `📊 Known contact: 0 facts · first seen 2026-07-28`), distinguishable from Tabatha's rich 48-fact example. No crash, no leaked nulls, output remains well-formed. This test is the acceptance-criteria anchor: it proves the fix doesn't accidentally make every entity look identical regardless of relationship depth — the whole point of the feature is differentiating "known contact" from "brand new."
- Pass/fail: well-formed degenerate output; visually/structurally distinguishable from RS-003's rich example (fewer clauses in the stats line).

**RS-015: Entity resolved but has `last_seen` populated, yet zero transcript rows exist (data inconsistency: last_seen updated by a path other than transcript logging, e.g. manual entity edit or a different presence-tracking mechanism)**
- Input: `lastSeen: <timestamp>`, `lastMessage: null`.
- Expected: Clarify whether "last message" and "last_seen" are the same concept or two independent signals. Per the issue, `last_seen` is its own bullet-worthy fact type separate from the transcript-derived last-message pointer — but the issue's example format only shows "last message ... (ref)", not a separate `last_seen` mention. **Open question flagged in §6:** does `entities.last_seen` get its own clause, or is it superseded/replaced by the transcript-derived last-message timestamp for display purposes (keeping `last_seen` as a raw DB field used only if transcripts are unavailable)? This test should assert whichever resolution is chosen, and must not silently drop `last_seen` data if the design intends it to be surfaced independently.
- Pass/fail: matches documented design decision; no silent data loss if `last_seen` is meant to always surface.

### 4.3 Edge Case — Large Fact Volume

**RS-020: Entity with thousands of facts (fact count = 4127, arbitrary large N) → count renders correctly, no truncation, no performance cliff**
- Input (integration tier, staging): seed 4000+ `entity_facts` rows for one disposable test entity.
- Expected: `COUNT(*)` aggregate returns the exact integer (not capped, not approximated); stats line renders `"4127 facts"` verbatim; query completes well within budget (see §4.6 for the explicit timing assertion).
- Pass/fail: exact count; query uses `idx_entity_facts_entity` (verify via `EXPLAIN` in the integration test — assert `Index Scan` or `Index Only Scan`, not `Seq Scan`, on `entity_facts`).

### 4.4 Error Conditions

**RS-030: Aggregate/stats query times out → graceful degradation to current (pre-fix) behavior**
- Precondition (unit tier, mocked): stats-fetch function/query hangs past the 1s budget.
- Input: call `resolveEntityContext()`.
- Expected: `Promise.race` resolves with the timeout fallback (empty stats, matching the existing `getEntityProfile()` timeout pattern which resolves to `{}` on timeout — not a rejection). The 👤 block still renders with at least the display name; pronouns should ALSO gracefully degrade to absent if pronouns are fetched via the same query. **Design-critical open question (§6):** if pronouns are fetched via the SAME query as the stats (single aggregate query, per the issue's stated preference), then a stats-query timeout also loses pronouns — meaning pronoun display becomes dependent on the same 1s race as the (heavier) stats query, rather than being cheap/always-available. Verify Coder's actual design and adjust this test's expected pronoun behavior accordingly. If pronouns are instead fetched as part of the cheaper, already-existing entity-identification query (in `resolveEntityByIdentifiers`/`resolveEntityOnly`), pronouns should survive a stats-query timeout independently — this is the recommended design (see §6) and this test should assert pronouns ARE still present even when the stats portion times out, IF that's the chosen architecture.
- Pass/fail: no exception propagates; entity name always renders; behavior for pronouns-under-timeout matches whichever architecture is chosen (documented, not left ambiguous).

**RS-031: Pool/connection error on the stats query (e.g., pool exhausted, ECONNREFUSED) → does not crash `resolveEntityContext()`, matches existing `getEntityProfile()` error-catch pattern**
- Precondition (unit tier, mocked): stats-fetch throws a generic connection error (not a timeout, a real rejection).
- Input: call `resolveEntityContext()`.
- Expected: error is caught (matching the existing `try/catch` around `getEntityProfile()` in `resolveEntityContext()`), logged via `console.error`, and the function returns with base entity info only (name, possibly pronouns depending on architecture) — never an unhandled rejection, never a thrown error escaping to the caller.
- Pass/fail: no unhandled rejection; `console.error` called with an identifiable message; text output well-formed with base info only.

**RS-032: Aggregate query itself throws a genuine SQL error (e.g., a bad JOIN post-migration-drift) — must not be silently swallowed into a false "no stats" without any log trace**
- Precondition: mock stats-fetch to throw a `42703 undefined_column`-style error (simulating schema drift, distinct from RS-030/031's transient conditions).
- Input: call `resolveEntityContext()`.
- Expected: same graceful-degradation behavior as RS-031 (no crash), BUT the error must be logged distinctly enough to be diagnosable (not conflated with "entity has no stats yet" — a silent empty stats line for a genuine schema-drift bug would be a regression of the exact class of bug that motivated the original `agent_domains.keywords` fix). Recommend: log the raw error message via `console.error`, same pattern as existing `getEntityProfile()` catch block.
- Pass/fail: error logged with actionable detail; behavior does not regress into permanently-silent failure.

### 4.5 Domain-Specific Scenarios

**RS-040: Group-channel cache key behavior (#150 non-regression) — cached `Entity` object now carries pronouns/trust/last_seen/created_at; must not cross-contaminate senders sharing a `sessionKey`**
- Precondition: `clearCache()`. Two distinct entities (A: `pronouns: "she/her"`, `trustLevel: "friend"`; B: `pronouns: "he/him"`, `trustLevel: "unknown"`) both resolving under the same `sessionKey` (simulating a group channel) but different `senderId`.
- Input: `resolveEntityContext(sessionKey, { senderId: A_id, ... })` then `resolveEntityContext(sessionKey, { senderId: B_id, ... })`.
- Expected: cache keys are `sessionKey:A_id` and `sessionKey:B_id` (existing `#150` fix) — entity A's cached object (now including her pronouns/trust/stats) must never be returned for sender B's lookup, and vice versa. This is a direct extension of the existing #150 regression test but now covers the WIDER cached object (more fields = more surface area for a stale-cache leak to be embarrassing, e.g. showing sender B "trust: friend" and sender A's pronouns).
- Pass/fail: B's resolved text/pronouns/trust never equal A's; both correct after both calls.

**RS-041: Cache TTL — stats/pronoun data does not silently go stale beyond the existing 30-minute cache TTL in an unexpected way**
- Precondition: entity cached with `trustLevel: "unknown"`; DB `trust_level` updated post-cache to `"friend"` (simulating an in-session trust upgrade).
- Input: `resolveEntityContext()` called again within the 30-min TTL.
- Expected: returns the STALE cached `trustLevel: "unknown"` (matches existing cache semantics — this is not a new bug, just confirming the wider cached object doesn't change TTL behavior). Document this as expected/known staleness, not a defect — flagged so nobody "fixes" it as an unrelated surprise later.
- Pass/fail: stale value returned as expected (negative-space regression test — asserts the OLD behavior is preserved, not violated by the new fields).

**RS-042: Honorific-guard path (#421) non-regression — `resolveEntityForGuard()` must remain lightweight and NOT trigger the new stats query**
- Precondition: mock/spy on the stats-fetch function.
- Input: call `resolveEntityForGuard(sessionKey, info)` directly (the `helperConfig.entity_resolver === false` path in `index.ts` that bypasses the full `resolveEntityContext()`).
- Expected: stats-fetch function is NEVER called; `resolveEntityForGuard()` returns only `{ entityId, displayName }` as before — zero added latency, zero added DB round-trips. This is the most important non-regression case: the guard exists specifically to be cheap and always-on (per its docstring), and accidentally wiring the new stats query into the shared `resolveEntityOnly()` helper (which BOTH `resolveEntityContext` and `resolveEntityForGuard` call) would silently regress guard latency on every single turn, not just when `entity_resolver` is enabled.
- Pass/fail: stats-fetch call count === 0 after calling `resolveEntityForGuard()`; guard output shape unchanged (still just entityId/displayName, no pronouns/trust bleeding into the guard's return type).

**RS-043: Honorific-guard text itself is unaffected by pronoun/trust data — `buildHonorificGuard()` still only consumes `entityId`/`agentId`/`displayName`**
- Input: any entity with rich stats data, run through the full `index.ts` pipeline.
- Expected: `buildHonorificGuard()`'s output string is byte-identical to pre-fix behavior for the same `entityId`/`agentId`/`displayName` inputs — it must not start referencing pronouns or trust level (out of scope for that subsystem; confirms no accidental scope creep across the two features that happen to share the same underlying entity resolution).
- Pass/fail: exact string match against pre-fix golden output for the same 3 inputs (reuse existing `honorific-guard.test.ts` fixtures).

**RS-044: Privacy/visibility — decision and test for whether `entity_facts` count respects `visibility`/`privacy_scope`**
- **Decision (documented here per the task's explicit ask):** The relationship-stats fact count should be **unfiltered by `visibility`/`privacy_scope`** — i.e., `COUNT(*) FROM entity_facts WHERE entity_id = $1` with no visibility predicate.
  - **Rationale:** `entity_facts.visibility` and `privacy_scope` govern who ELSE (which other entities/agents) may see a fact ABOUT this entity — they are an exposure control for third parties, not a control on whether the agent talking directly to entity X may know "how much do I know about the person I'm currently talking to." The injected 👤 block is agent-internal context, never echoed back to the user or to any other entity in the conversation. Filtering the count by visibility would produce a systematically LOWER number than reality whenever an entity has any `private`/`trusted`-scoped facts (which are exactly the highest-trust, most relationship-relevant facts — often the ones that should count MOST toward "how well do we know them"). Filtering here would actively undermine the feature's stated goal ("indicator as to how well you know them").
  - **Caveat / residual risk to flag to Coder and I)ruid:** this reasoning holds for the 1:1 case. In a **group channel**, if the injected context for sender A were ever accidentally surfaced to sender B (the exact class of bug #150 was created to prevent), an unfiltered count could indirectly signal "there are N private facts about this person" to the wrong audience — though it leaks only a COUNT, not fact content, so the blast radius is low. Given the existing #150 cache-key fix already prevents cross-sender context leakage at the injection layer, this residual risk is judged acceptable, but it should be explicitly acknowledged rather than assumed away.
- Test: seed one entity with a mix of `visibility = 'public'`, `'trusted'`, and `'private'` facts (e.g., 20 public + 15 trusted + 13 private = 48, matching the issue's example number for a satisfying callback). Assert the rendered fact count is **48** (all facts, unfiltered), not a lower filtered number.
- Pass/fail: count reflects all rows regardless of `visibility`/`privacy_scope`, matching the documented decision. If Coder implements filtering instead (disagreeing with this recommendation), this test must be explicitly updated and the rationale for the reversal documented in the PR — silent divergence from this decision is not acceptable per the task's "decide and document" requirement.

### 4.6 Performance / Timeout Budget

**RS-050: Aggregate query completes well within the 1s `Promise.race` budget under normal conditions (staging, warm connection pool)**
- Precondition (integration tier): seeded entity with realistic data volume (dozens of facts, hundreds of transcript rows).
- Input: time the aggregate query directly (not just the race-wrapped call) via `console.time`/`process.hrtime` in the integration test.
- Expected: query completes in low tens of milliseconds (well under the 1000ms budget — recommend asserting `< 200ms` as a generous regression-catching ceiling, not a tight SLA) given the covering indexes identified in §3.
- Pass/fail: measured duration `< 200ms` on staging under normal load; flag as a soft/informational assertion if staging load is variable, but must be re-run and confirmed manually before sign-off if it fails.

**RS-051: `EXPLAIN` confirms index usage for both the fact-count subquery and the last-transcript lookup — no sequential scans on `entity_facts` or `channel_transcripts`**
- Input: `EXPLAIN (FORMAT JSON) <aggregate query>` against staging with realistic row counts (seed enough rows, e.g. 5,000+ unrelated `entity_facts` rows across other entities, to make a seq-scan-vs-index-scan difference actually observable).
- Expected: `Index Scan`/`Index Only Scan`/`Bitmap Index Scan` on `idx_entity_facts_entity` for the count; `Index Scan` on `idx_channel_transcripts_sender_entity` for the last-message lookup (LIMIT 1 with ORDER BY DESC should use the index's sort order directly, avoiding a full sort).
- Pass/fail: no `Seq Scan` node present for either table in the plan.

**RS-052: Combined worst-case latency — stats query + existing facts query (if run sequentially rather than merged/parallel) does not exceed the 1s budget for THIS resolution, and does not silently double the effective timeout ceiling to 2s**
- **Design-critical open question (§6):** does the new stats query run (a) merged into a single query alongside the existing `getEntityProfile()` allowlist-facts query, (b) as a second query racing its OWN independent 1s timeout (making the effective worst case sequentially up to 2s if `resolveEntityContext()` awaits both races in sequence rather than `Promise.all`-ing them), or (c) replacing the existing `getEntityProfile()` call entirely?
- Input/Expected: whichever architecture is chosen, this test asserts the TOTAL added latency contribution from entity-resolution stays bounded — recommend Coder merge into a single query per the issue's explicit stated preference ("single aggregate query preferred"), and recommend wrapping that ONE query in the existing `Promise.race(..., 1000ms)` pattern (not a second independent race), so the worst-case ceiling for entity resolution as a whole does NOT silently grow from ~1s to ~2s.
- Pass/fail: total entity-resolution wall-clock time (both the identifier-resolution query AND whichever facts/stats query(ies) run) stays within a single 1s degradation ceiling, not stacked ceilings. This should be asserted with a slow-query mock that would time out if two full 1s races were stacked sequentially, but resolves in time if merged/parallelized correctly.

### 4.7 Formatting / Boundary Values

**RS-060: Fact count boundary — exactly 1 fact ("1 fact" singular vs "1 facts" — grammar check)**
- Input: `factCount: 1`.
- Expected: **Open question for Coder** — does the implementation pluralize correctly ("1 fact") or keep it simple ("1 facts", matching the issue's own example which never demonstrates the singular case)? Recommend correct singular/plural handling for polish, but this is non-blocking; document whichever choice is made and lock the test to it.
- Pass/fail: matches documented choice — either is acceptable as long as it's consistent and intentional, not accidental.

**RS-061: `trust_level` enum boundary values — all documented values render without error**
- Input: iterate `trustLevel` over `'owner'`, `'admin'`, `'user'`, `'unknown'`, `'untrusted'` (per the column comment's documented value set — note this is NOT a DB CHECK constraint, just a documented convention, so also test an arbitrary/unexpected string value like `'friend'` since the issue's own example uses `"friend"`, which is NOT in that documented list).
- Expected: all render as `— trust: X` (except `'unknown'`/NULL, per RS-011) with no crash, no special-casing that breaks on the undocumented-but-used `"friend"` value. This surfaces a real inconsistency worth flagging: the column comment's documented value set (`owner, admin, user, unknown, untrusted`) does NOT include `"friend"`, which is exactly what the issue's own target-format example uses. **Flag to I)ruid/Coder:** either the column comment is stale/incomplete, or `trust_level` is freely-editable text without an enforced value set and the example is using a value nobody previously documented. The implementation must not assume a closed enum when rendering — treat `trust_level` as an arbitrary non-empty string.
- Pass/fail: no crash/no special-casing failure for `"friend"` or any other non-listed value; confirms implementation doesn't hardcode a value-checking switch statement that would silently drop unrecognized trust levels.

**RS-062: Timestamp formatting — `first seen` uses date-only (`YYYY-MM-DD`), `last message` uses date+time+UTC marker — verify timezone handling is explicit and not silently server-local**
- Input: `createdAt` and `lastMessage.timestamp` as UTC `timestamptz` values from Postgres (both `entities.created_at` and `channel_transcripts.timestamp` are stored as timestamp/timestamptz — verify exact column types don't produce a timezone-conversion bug when rendered, since `entities.created_at` is plain `timestamp` (no tz) while `channel_transcripts.timestamp` is `timestamptz`).
- Expected: output explicitly labeled `UTC` for the last-message clause (per the issue's example) and consistent, unambiguous date rendering for first-seen — no accidental server-local-timezone conversion silently applied to the `timestamp` (non-tz) `created_at` column, which could misrepresent the "first seen" date depending on server TZ configuration vs. the DB session TZ.
- Pass/fail: explicit UTC labeling present for last-message; first-seen date is stable/correct regardless of process `TZ` env var (test by running under `TZ=America/Chicago` vs `TZ=UTC` and asserting identical output — this is a real, plausible bug source given the column-type mismatch).

---

## 5. Privacy/Visibility Decision Summary (restated for visibility)

**Decision:** Fact count is unfiltered by `visibility`/`privacy_scope` — see full rationale in RS-044. This section exists so the decision isn't buried only in a single test case.

---

## 6. Open Questions (per instructions — documented rather than blocking)

1. **Markdown bold in the 👤 header line:** the issue's example shows plain `👤 Talking with:` (no bold), but the existing code renders `👤 **Talking with:**`. Does the fix intentionally drop the bold markdown, or is the issue's example just informal shorthand? Recommend preserving existing bold convention unless explicitly told otherwise — flagged in RS-001.
2. **Pronoun fetch path vs. stats-query timeout coupling:** should pronouns be fetched as part of the SAME aggregate/stats query (simplest, per the issue's "single aggregate query" preference, but couples pronoun display to the heavier query's timeout fate), or as part of the cheaper, already-existing identifier-resolution query in `resolveEntityByIdentifiers`/`resolveEntityOnly` (pronouns survive a stats-query timeout independently)? Recommend the latter for resilience — pronouns are a near-zero-cost addition to a query that already runs and already succeeds before the stats race even begins. Flagged in RS-030.
3. **`entities.last_seen` vs. transcript-derived last-message timestamp:** are these the same displayed value, or two independent data points? The issue lists both `last_seen` and "last message timestamp" as separate bullet items in the requirements list, but the example format only shows one timestamp clause. Does `last_seen` need its OWN clause in the rendered output, or is it functionally superseded by the transcript-derived value for display (while still being fetched/available for other consumers)? Flagged in RS-015.
4. **Channel/session ref granularity:** should the parenthetical ref include `external_thread_id` when present (e.g., `discord:1513392492651872306:987654321` for a thread), or always just `provider:external_chat_id`? The issue's example only shows the two-part form. Flagged in §3.
5. **Query architecture (merged vs. dual-race):** does the new stats data get merged into ONE query with the existing `getEntityProfile()` allowlist-facts query (replacing/extending that function), or does it run as an ADDITIONAL, separate query? If separate, is it wrapped in its own independent `Promise.race(1000ms)`, risking an effective 2s worst-case ceiling for entity resolution as a whole? Recommend a single merged query wrapped in the EXISTING race. Flagged in RS-052 — this is the highest-risk architectural decision from a performance-budget-compliance standpoint and should be resolved explicitly, not left to fall out of implementation convenience.
6. **Singular/plural fact-count grammar** ("1 fact" vs "1 facts") — cosmetic, non-blocking, flagged in RS-060.
7. **`trust_level` value-set inconsistency** — the column comment documents `owner, admin, user, unknown, untrusted` but the issue's own example uses `"friend"`, which isn't in that list. Is `trust_level` actually free text in practice, or does the documented comment need updating, or does `"friend"` in the issue's example reflect an as-yet-unshipped separate change to the value set? Flagged in RS-061 — implementation must not assume a closed set either way.
8. **Deploy/parity step:** how does a fix to `relationships/lib/entity-resolver/resolver.ts` get synced to the installed `~/.openclaw/lib/entity-resolver/resolver.ts` copy consumed at runtime? Not previously documented in the issue or in either file's README — this should be confirmed as part of the PR (a build/copy step, a symlink, or manual sync) so the fix doesn't silently fail to take effect at runtime despite passing all repo-local tests. This is a deployment-hygiene gap, not a QA scope item per se, but sign-off should not proceed without this being confirmed.

---

## 7. Definition of Done

All of the following must be true before this fix is considered QA-approved and ready for sign-off:

1. **All test cases RS-001 through RS-062 pass** — unit tier via `npm test` (`tsx --test src/**/*.test.ts`) in `memory/plugins/turn-context/`, plus the RS-020/RS-050/RS-051 integration cases executed against nova-staging (extending `relationships/lib/entity-resolver/test.ts`).
2. **Zero regressions:** existing `honorific-guard.test.ts` (RS-042, RS-043) and `index.test.ts` (`buildPromptResult` placement tests) continue to pass unmodified; existing `--irc-tests` block in `relationships/lib/entity-resolver/test.ts` continues to pass unmodified.
3. **Performance budget compliance confirmed** (RS-050, RS-051, RS-052) — the single highest-risk requirement from the issue ("must fit existing 1s timeout budget"); must not be waved through on "looks fine in dev," needs actual staging measurement.
4. **Privacy/visibility decision (§5) is implemented as documented, or explicitly reversed with documented rationale** (RS-044) — silent divergence is not acceptable.
5. **All open questions in §6 are explicitly resolved by Coder** (documented in code comments or PR description), and any test case whose expected behavior depended on an open question is updated to match the chosen resolution before merge.
6. **`npm run typecheck` and `npm run build` clean** in both `relationships/lib/entity-resolver/` and `memory/plugins/turn-context/`; `dist/` reflects the change.
7. **Installed-copy parity confirmed** (§6, item 8) — `~/.openclaw/lib/entity-resolver/resolver.ts` matches the repo source post-fix, verified via `diff`.
8. **Manual smoke test** against real `nova_memory` (staging) confirms: (a) a real known entity (e.g., a seeded test analog of "Tabatha") renders pronouns + stats correctly, (b) a brand-new entity renders the sparse/degenerate form (RS-014) without error, (c) no new warnings/errors appear in plugin logs during normal multi-turn operation.

Any failing test blocks PR sign-off. Any test that cannot be executed due to missing staging access must be explicitly waived by I)ruid with the gap documented, not silently skipped.
