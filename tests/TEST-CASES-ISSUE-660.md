# Test Cases — nova-mind#660: `agent_config_sync` drops per-agent `thinking`, must map to `thinkingDefault`

**Author:** Gem (QA Lead) | **Workflow:** SE run #866, Step 3 | **Requester:** NOVA
**Scope:** Test design only — no implementation. Companion source-review by Graybeard/NOVA per issue #660.

---

## 0. Ground Truth Established During Source Review

Confirmed against a fresh clone of `NOVA-Openclaw/nova-mind` (HEAD `0d37ab79aaa245f502a211354cb5393dc112a5b6`) and a fresh clone of `NOVA-Openclaw/nova-openclaw` (HEAD `acdaf7eec785aff763fa1765870433075236c229`). These facts are load-bearing for the test design below — treat them as verified, not assumed.

| # | Fact | Source |
|---|---|---|
| G1 | `AGENTS_QUERY` in `sync.ts` already selects `thinking` from `get_agent_export_rows()`. The column reaches `buildAgentsList()` on every `AgentRow`. | `cognition/focus/agent-config-sync/src/sync.ts:55` |
| G2 | `buildAgentsList()` currently does **nothing** with `row.thinking` — no line writes it into `entry`. The only trace is a comment block (lines ~100-102) asserting `thinking` is "not a valid per-agent config key," which is the root-cause misconception the issue corrects. Reproduced live: `buildAgentsList([{...thinking:"off"...}, {...thinking:"high"...}])` emits **zero** `thinkingDefault` keys today (see §8, reproduction transcript). | `cognition/focus/agent-config-sync/src/sync.ts:80-113`; live repro |
| G3 | The **DB column** `agents.thinking` (`database/schema.sql:524`) has `CHECK (thinking IN ('off','minimal','low','medium','high','xhigh','adaptive'))` — 7 values, case-sensitive exact match, **no `max`/`ultra`**, nullable (no `NOT NULL`). | `database/schema.sql:524,540` |
| G4 | The **config schema** `thinkingDefault` field (nova-openclaw) is `z.enum(["off","minimal","low","medium","high","xhigh","adaptive","max","ultra"])`, `.optional()` — 9 values, superset of G3. The DB can never legally emit a value outside the schema's accepted set, **provided the CHECK constraint is intact and case is preserved exactly**. | `src/config/zod-schema.agent-runtime.ts:1044-1046` (nova-openclaw) |
| G5 | `AgentEntrySchema` is `.strict()` (nova-openclaw). An entry with `thinkingDefault` set to any value **outside** the 9-value enum fails Zod validation at config load — this is the crash mode the issue describes for "emit raw `thinking`" (a raw DB value could theoretically diverge from the enum if the CHECK is ever loosened without a matching generator update, or if a row is written via a path that bypasses the CHECK). | `src/config/zod-schema.agent-runtime.ts:1033-1039` |
| G6 | The **runtime consumer seam**: `get-reply-directives.ts:450-451` calls `normalizeThinkLevel(agentEntry?.thinkingDefault) ?? normalizeThinkLevel(agentCfg?.thinkingDefault)` — i.e., **the per-agent value is read from the generated config file and takes priority over the global default** (`agents.defaults.thinkingDefault`). `agentEntry` is `listAgentEntries(cfg).find(id match)`, sourced straight from the `agents.list[]` array — i.e., straight from the JSON `agent_config_sync` writes. Same pattern repeated in `get-reply.ts:325-326`, `model-selection.ts:556/574`, `directive-handling.levels.ts:31-32`. This is the seam a "string was emitted" test would miss and a "value took effect" test must exercise. | `src/auto-reply/reply/get-reply-directives.ts:450-451` (nova-openclaw) |
| G7 | `normalizeThinkLevel()` (`src/auto-reply/thinking.shared.ts:64-108`, nova-openclaw) is **lenient and case-insensitive** at the runtime-consumption layer: lowercases input, collapses separators, and maps aliases (`"auto"→"adaptive"`, `"enabled"→"low"`, `"ultrathink"→"high"`, etc.) before falling back to `undefined` for anything unrecognized. This is a **different, looser** normalization than the DB CHECK / schema enum. The generator (`buildAgentsList`) sits **between** the DB (strict, 7 values) and the runtime consumer (lenient, aliasing) — it is not obligated to replicate the runtime's alias table, only to safely emit a schema-valid `thinkingDefault` or omit the key. | `src/auto-reply/thinking.shared.ts:64-108` (nova-openclaw) |
| G8 | `buildAgentsList()`'s existing `AgentRow` type (`sync.ts:24-35`) declares `thinking: string \| null` — a **wide** TypeScript type, not a literal union. Nothing at the type level prevents a value outside the 7 CHECK-enforced strings from reaching the function (e.g., stale rows from before the CHECK existed, a future migration widening the CHECK without a matching generator update, or a differently-sourced `AgentRow` in a future caller). The function must not blindly trust DB-layer invariants it cannot verify at its own boundary. | `cognition/focus/agent-config-sync/src/sync.ts:24-35` |
| G9 | Existing unit suite (`sync.test.ts`, 35 describe blocks, TC-244/262/269/273 series) already asserts **today's bug as correct behavior** in TC-244-U-01's `"thinking is not emitted for any entry"` test. That specific assertion will need updating by the implementer as part of the #660 fix (out of scope for this design doc to edit, but flagged so Coder doesn't get a false "existing test broke" signal — see §9 Note 1). | `cognition/focus/agent-config-sync/src/sync.test.ts:130-136` |
| G10 | Running the full existing suite today (`npx tsx --test src/sync.test.ts`) shows 93/104 passing, 11 pre-existing failures **unrelated to #660** — all in the heartbeat-partial-object area (TC-262-U-05/08, TC-273-U-02/03/09/10). These are a pre-existing defect independent of this issue; noted so a post-fix re-run isn't mis-attributed. | live run, `/tmp/nova-mind-660` |
| G11 | Repo test-artifact convention confirmed: root-level `tests/TEST-CASES-ISSUE-<N>.md` files (e.g. `TEST-CASES-ISSUE-133.md`, `-522.md`, `-579.md`) is the established pattern for cross-cutting/design-level test docs; plugin-local `cognition/focus/agent-config-sync/tests/test-cases-273.md` is used for narrower single-plugin docs. This doc follows the root-level convention since #660 spans the plugin (`sync.ts`) and the runtime consumer (nova-openclaw, a separate repo) — matching the precedent set by `TEST-DESIGN-429-installer-agents-json.md`, which also had to reason across `agent-install.sh` and `sync.ts` together. | `tests/` directory listing |

---

## 1. Reproduction — Current Buggy Behavior (baseline for regression guard)

Executed against the pinned checkout, unmodified:

```ts
const rows = [
  { name: "bastion", model: "anthropic/claude-sonnet-4", fallback_models: null,
    thinking: "off", instance_type: "subagent", is_default: false, allowed_subagents: null },
  { name: "newhart", model: "anthropic/claude-opus-4", fallback_models: null,
    thinking: "high", instance_type: "peer", is_default: true, allowed_subagents: null },
];
buildAgentsList(rows);
```

**Actual output today:**
```json
[
  { "id": "bastion", "model": "anthropic/claude-sonnet-4" },
  { "id": "newhart", "model": "anthropic/claude-opus-4", "default": true }
]
```

Neither entry has a `thinkingDefault` key — `bastion`'s explicit `off` is silently lost, exactly as the issue describes. This is the fixture used by TC-660-U-01 (regression guard) below: that test must **FAIL** against this baseline and **PASS** once the mapping fix lands.

---

## 2. Test Design Requirements Coverage Map

| Requirement (from task brief) | Covered by |
|---|---|
| Happy path — non-default value maps through (`off`, `high`) | TC-660-U-01, TC-660-U-02 |
| Domain-specific — config→runtime seam, per-agent tier actually takes effect | TC-660-I-01…04 |
| Adversarial/malformed — NULL, empty string, unknown tier, wrong-type, mixed-case | TC-660-U-05…12 |
| Boundary — empty agent list, single agent, large fleet, unset vs explicit-default | TC-660-U-13…17 |
| Regression guard — fails pre-fix, passes post-fix | TC-660-U-01 (primary), TC-660-U-18 (batch form) |

---

## 3. Unit-Level Test Cases — `buildAgentsList()` (plugin repo: nova-mind)

Layer: Node built-in test runner (`node:test`), same harness as existing `sync.test.ts`. New cases below extend that file (or a new co-located file — implementer's call, but must run under the existing `npm test` script). ID scheme follows repo convention: `TC-660-U-##`.

### 3.1 Happy Path

**TC-660-U-01 — Non-default `off` value maps to `thinkingDefault: "off"` (PRIMARY REGRESSION GUARD)**
- **Input:** `{ name: "bastion", thinking: "off", ... }`
- **Expected:** `entry.thinkingDefault === "off"`; key is present (`hasOwnProperty` true).
- **Regression proof requirement:** Run this exact assertion against the current (pre-fix) `sync.ts` — it must FAIL (property is `undefined`, `hasOwnProperty` false). Run again post-fix — must PASS. Both runs' output must be captured in the QA validation report before sign-off (per DEFECT_MANAGEMENT lifecycle: "Verify" step re-runs the original repro).

**TC-660-U-02 — Non-default `high` value maps to `thinkingDefault: "high"`**
- **Input:** `{ name: "newhart", thinking: "high", ... }`
- **Expected:** `entry.thinkingDefault === "high"`.
- **Note:** Deliberately chosen because `high` also happens to be the *global default* value in the live fleet (per issue's impact section) — this specifically guards against an implementation that only "fixes" values that visibly differ from some hardcoded default, i.e. proves the mapping is unconditional, not defaults-aware. An implementation that special-cases "skip if value equals global default" would incorrectly pass TC-660-U-01 but must still emit `thinkingDefault:"high"` here — it does not get to omit the key just because the value happens to match the fleet's current global default.

**TC-660-U-03 — All 7 DB-legal values map 1:1**
- **Input:** 7 rows, one per legal DB value: `off, minimal, low, medium, high, xhigh, adaptive`.
- **Expected:** Each entry's `thinkingDefault` equals its row's `thinking` value exactly (identity mapping, no aliasing/renaming). Table-driven (`test.each`-equivalent loop) test.

**TC-660-U-04 — Existing fields unaffected by the fix (non-regression on shape)**
- **Input:** An agent row exercising `model` (with fallbacks), `is_default`, `allowed_subagents`, `heartbeat_*`, AND a non-null `thinking` value simultaneously.
- **Expected:** All pre-existing fields (`id`, `model` shape, `default`, `subagents.allowAgents`, `heartbeat`) are byte-identical to what `buildAgentsList` would produce with `thinking` stripped from the row entirely (i.e., diff the two outputs, only difference is the added `thinkingDefault` key). Guards against the fix touching unrelated logic — mirrors the pattern of TC-429-P-01's parity concern but applied within the single function.

### 3.2 Adversarial / Malformed Input

**TC-660-U-05 — `thinking = null` → key omitted**
- **Input:** `{ ..., thinking: null }`
- **Expected:** `thinkingDefault` key **absent** (`hasOwnProperty` false), not `null`, not `undefined`-but-present. Mirrors the established `heartbeat`-omission idiom already used elsewhere in this same function (see TC-273-U-02..08 for precedent pattern this codebase already follows).

**TC-660-U-06 — `thinking = ""` (empty string) → key omitted**
- **Input:** `{ ..., thinking: "" }`
- **Expected:** Key omitted. **Rationale requiring PL confirmation (see §7 Q1):** empty string is falsy in JS but is a distinct value from `null`/`undefined` — an implementation using `row.thinking != null` (not `!row.thinking`) would incorrectly try to emit `thinkingDefault: ""`, which fails the Zod enum at config load (empty string is not one of the 9 accepted literals) — reproducing the exact "raw value crashes gateway" failure mode from the issue. This test exists specifically to catch that implementation mistake.

**TC-660-U-07 — `thinking = "ultra"` (schema-valid-but-DB-illegal enum value) → mapped through**
- **Input:** `{ ..., thinking: "ultra" }` (cannot occur via a live, CHECK-constrained INSERT/UPDATE today per G3, but reachable via direct fixture injection, a stale row from before a stricter CHECK was added, or reuse of `buildAgentsList` with a differently-sourced `AgentRow` — see G8).
- **Expected:** `thinkingDefault: "ultra"` — because `"ultra"` **is** in the schema's accepted enum (G4), this must pass through rather than being treated as invalid. **This is the trap case**: an implementer who copies the DB's 7-value CHECK list as their allow-list (instead of the schema's 9-value list) will incorrectly omit this key. The test's purpose is to force the allow-list to be sourced from the *config schema* contract, not the *DB* contract, since the config schema is the actual consumer boundary.
- **Same test repeated for `"max"`.**

**TC-660-U-08 — `thinking = "notarealvalue"` (genuinely unknown tier) → key omitted, no crash**
- **Input:** `{ ..., thinking: "notarealvalue" }`
- **Expected:** Key omitted (not passed through raw — passing through would produce an invalid enum value and crash the gateway at config load, the exact failure mode #660 documents). No exception thrown by `buildAgentsList` itself — a malformed row must degrade one entry's `thinkingDefault`, not abort the whole sync.

**TC-660-U-09 — `thinking` is a number (wrong type, e.g. `5` or `0`)**
- **Input:** `{ ..., thinking: 5 as unknown as string }` (defensive test — TS type says `string | null`, but the DB driver or a future caller could hand back something else; see G8).
- **Expected:** Key omitted; no thrown exception; `typeof` guard must be present in the implementation (not just a `Set.has()` call, which would `false`-ily reject `5` anyway but could throw if the guard assumes `.toLowerCase()` is callable without a type check first).

**TC-660-U-10 — `thinking` is a boolean (`true`)**
- **Input:** `{ ..., thinking: true as unknown as string }`
- **Expected:** Key omitted; no exception.

**TC-660-U-11 — Mixed-case value, e.g. `"High"`, `"OFF"`, `"AdAptive"`**
- **Input:** Three rows with mixed-case variants of legal lowercase values.
- **Expected behavior REQUIRES PL CONFIRMATION before implementation (see §7 Q2)** — two defensible options exist:
  - **(a) Strict-membership (recommended default):** since the DB CHECK only ever produces exact lowercase matches (G3), mixed case at this boundary indicates either a bypassed constraint or a test artifact; omit the key (treat as invalid) rather than silently coercing case, keeping `buildAgentsList` a strict, narrow mapper.
  - **(b) Normalize-then-map:** lowercase the value before checking membership, mirroring `normalizeThinkLevel`'s leniency (G7) at the generator layer too, so a case anomaly degrades gracefully to the correct value instead of an omitted key.
  - This test case is written to assert **whichever behavior PL selects** — do not implement against an assumed answer; flag to Coder as a blocking design decision, not an oversight to silently pick one.

**TC-660-U-12 — Leading/trailing whitespace, e.g. `" off"`, `"high "`**
- **Input:** Two rows with whitespace-padded legal values.
- **Expected:** Same open question as TC-660-U-11 (trim-then-map vs strict-reject) — same PL confirmation required, same rationale (the DB CHECK constraint does not trim, so a stored value with whitespace already violates the constraint's exact-match semantics and could only exist via a bypass).

### 3.3 Boundary Values

**TC-660-U-13 — Empty agent list**
- **Input:** `buildAgentsList([])`
- **Expected:** Returns `[]`, no exception. (Pre-existing coverage exists for this shape generally — TC-273-U-06 — this variant just confirms the `thinking`-handling code path doesn't add a crash surface for the zero-row case.)

**TC-660-U-14 — Single agent, `thinking` set**
- **Input:** One row, `thinking: "medium"`.
- **Expected:** `result.length === 1`; `result[0].thinkingDefault === "medium"`.

**TC-660-U-15 — Large fleet (30 agents), mixed `thinking` values including some `null`**
- **Input:** 30 synthetic rows: 25 with a valid distinct-ish spread across all 7 legal values (cycling), 5 with `thinking: null`.
- **Expected:** Exactly 25 entries have a `thinkingDefault` key; exactly 5 do not; per-row value correctness spot-checked (not just count) for at least 3 arbitrary indices. Also assert sort order (`a.id.localeCompare(b.id)`) is unaffected by the new field — mirrors existing TC-262-U-06 precedent applied to `thinking`.

**TC-660-U-16 — Agent with `thinking` column entirely absent from the row object (pre-migration-shaped row)**
- **Input:** An `AgentRow` object literal that omits the `thinking` property entirely (`undefined` via absence, not `null` via explicit assignment) — mirrors the existing TC-273-U-07 "legacy pre-migration row" pattern applied to this field.
- **Expected:** Key omitted; no exception. Distinguishes "column never selected" (a query regression) from "column selected but NULL" (TC-660-U-05) — both must degrade identically at the `buildAgentsList` boundary, but they are different input shapes and deserve separate coverage in case a future query change reintroduces this exact class of gap (which is literally what #660 is about, one level up the stack).

**TC-660-U-17 — Agent explicitly configured to the value that also happens to equal the (hypothetical) global default**
- Same intent as TC-660-U-02, restated here as an explicit boundary case per the brief's "unset vs explicitly default" requirement: an agent with `thinking: "high"` (matches typical global default) must still get an **explicit** `thinkingDefault: "high"` key written — this is NOT equivalent to the agent having no per-agent override (`thinking: null`, which correctly omits the key and inherits the global default at runtime). The distinction between "explicitly high" and "unset, inherits high" is invisible in the *current session's resolved behavior* but is NOT invisible in the *generated config file* nor in future-proofing against the global default changing — an explicitly-set agent must not silently start tracking a changed global default. **This is the exact bug class the issue reports in reverse:** today, everyone silently inherits the global default regardless of their own setting; post-fix, only agents with `thinking IS NULL` should inherit it.

### 3.4 Regression Guard (Batch Form)

**TC-660-U-18 — Full fleet-shape regression test using the issue's own reported impact data**
- **Input:** Reconstruct the issue's cited scenario: agents `bastion, ember, flicker, flint, gallan, gidget, grain, hermes` all with `thinking: "off"`; `newhart` with `thinking: "high"`; remaining agents at `low`/`medium`/`adaptive` per the issue's "cross-checked vs the agents table" claim (representative subset is sufficient — does not require literally 15 rows, but should include at least one from each level mentioned in the issue).
- **Expected:** Every "off"-configured agent gets `thinkingDefault: "off"` in the output — **explicitly proving the fleet-wide silent-degradation bug is closed**, not just that some abstract unit test passes. This is the test whose pre-fix/post-fix diff is the most legible artifact for the QA validation report and for NOVA/PL sign-off, since it mirrors the real production data the bug was measured against.

---

## 4. Integration-Level Test Cases — Config→Runtime Seam (nova-openclaw repo consumer)

Layer: exercises the **consuming** side (`get-reply-directives.ts` / `resolveCurrentDirectiveLevels` / `normalizeThinkLevel`) against a config object shaped like what `buildAgentsList()` would emit post-fix. This is the domain-specific requirement from the brief — proving the emitted string is not just present but **actually changes runtime behavior**. ID scheme: `TC-660-I-##` (I = integration/seam).

**Rationale (why this tier is required, not optional):** Per lessons 811/787 (cited in the task brief) — a prior defect class in this codebase involved tests that asserted a config value was *written* without ever asserting the runtime *read* it and acted on it. `buildAgentsList()` unit tests alone (§3) can pass even if the consumer-side key name, casing, or null-handling silently mismatches (e.g., if the fix accidentally emitted `thinking` instead of `thinkingDefault`, or nested it wrong) — since those unit tests only inspect `buildAgentsList`'s own output shape, not whether nova-openclaw's `AgentEntrySchema`/`resolveAgentConfig`/`normalizeThinkLevel` chain actually consumes it.

**TC-660-I-01 — Generated `thinkingDefault:"off"` entry survives `AgentEntrySchema` validation and round-trips through `resolveAgentConfig`**
- **Setup:** Construct a full `OpenClawConfig`-shaped object with `agents.list` containing one entry built by calling the (post-fix) `buildAgentsList()` output directly (not hand-typed — use the real function to avoid divergence), for an agent with `thinking: "off"`.
- **Steps:** Parse the config through nova-openclaw's `AgentEntrySchema.parse()` (or the full config schema, whichever is the smallest reliable validation surface); then call `resolveAgentConfig(cfg, agentId)`.
- **Expected:** Schema parse succeeds (no ZodError); `resolveAgentConfig(...).thinkingDefault === "off"`.

**TC-660-I-02 — `normalizeThinkLevel(agentEntry?.thinkingDefault)` resolves to the per-agent tier, overriding a *different* global default**
- **Setup:** `agents.defaults.thinkingDefault = "high"` (global). One agent entry (built via `buildAgentsList()`) has `thinkingDefault: "off"`.
- **Steps:** Call the actual resolution chain used at `get-reply-directives.ts:450-451`: `normalizeThinkLevel(agentEntry?.thinkingDefault) ?? normalizeThinkLevel(agentCfg?.thinkingDefault)` with `agentCfg = cfg.agents.defaults` and `agentEntry` = the resolved entry for this agent.
- **Expected:** Result is `"off"`, **not** `"high"` — proving the per-agent tier actually takes priority over the global default at the point where a real turn would consult it. **This is the single highest-value test in this document**: it is the concrete, executable proof that the fix closes the fleet-wide silent-degradation bug described in the issue, at the exact call site the issue cites (`get-reply-directives.ts:450`).
- **Regression contrast:** Run the identical setup/steps against **pre-fix** `buildAgentsList()` output (which has no `thinkingDefault` key at all) — the result must be `"high"` (falls through to global default), demonstrating the bug end-to-end through the real consumer, not just at the generator boundary.

**TC-660-I-03 — Agent with no per-agent override (`thinking: null`) correctly inherits the global default through the same chain**
- **Setup:** Same as TC-660-I-02, but this agent's row has `thinking: null` (so `buildAgentsList()` correctly omits `thinkingDefault`).
- **Expected:** Resolution chain result is `"high"` (the global default) — confirming the fix does **not** overcorrect into always forcing a per-agent value; `null`/unset must still legitimately inherit the global, only agents with an *explicit* value should override it. Directly tests the "unset vs explicit-default" distinction from TC-660-U-17 at the consumer layer.

**TC-660-I-04 — Multi-agent config: two agents, two different per-agent tiers, verified independently through the same resolution call**
- **Setup:** `agents.list` built via `buildAgentsList()` from two rows: `agentA` with `thinking:"low"`, `agentB` with `thinking:"xhigh"`. Global default `agents.defaults.thinkingDefault = "medium"`.
- **Steps:** Call the resolution chain once per agent id.
- **Expected:** `agentA` resolves to `"low"`; `agentB` resolves to `"xhigh"`; neither resolves to the shared global `"medium"`. Guards against a cross-contamination bug where `resolveAgentConfig`/`listAgentEntries` might accidentally return the wrong entry or apply the global uniformly despite distinct per-agent overrides being present — the multi-agent fleet is the actual production shape this bug was measured against (15 agents), not a single-agent toy case.

---

## 5. Error Conditions / Safety Guards (consolidated)

| Condition | Test ID | Expected |
|---|---|---|
| `thinking = null` | TC-660-U-05 | Key omitted, no crash |
| `thinking = ""` | TC-660-U-06 | Key omitted, no crash (catches the `!= null` vs truthy-check implementation trap) |
| `thinking` outside DB's 7 but inside schema's 9 (`"ultra"`, `"max"`) | TC-660-U-07 | **Mapped through** — catches the "used the wrong allow-list source" trap |
| `thinking` outside both (`"notarealvalue"`) | TC-660-U-08 | Key omitted, no crash — prevents the "emit raw → gateway crash" failure mode |
| `thinking` wrong JS type (number, boolean) | TC-660-U-09, TC-660-U-10 | Key omitted, no crash — defensive against DB-driver/type assumptions |
| `thinking` property absent from row object | TC-660-U-16 | Key omitted, no crash — distinguishes query regression from NULL data |
| Post-fix output fails to validate against `AgentEntrySchema` | TC-660-I-01 | Must NOT happen for any of the 7 legal DB values — this is the acceptance gate for "neither crashes nor silently degrades" from the issue's own fix description |

---

## 6. Traceability to Issue #660's Stated Fix Description

> "In `buildAgentsList()`: map `row.thinking` → `entry.thinkingDefault`, validated against the thinking enum (`off/minimal/low/medium/high/xhigh/adaptive`), key omitted when null/empty. Neither crashes (raw `thinking`) nor silently degrades (omit). Update the stale comment. Add a test asserting a row with `thinking='off'` produces `thinkingDefault:'off'` in the emitted entry."

- "map row.thinking → entry.thinkingDefault" → §3.1 (TC-660-U-01…04)
- "validated against the thinking enum" → §3.2 raises a genuine ambiguity the issue text doesn't resolve: the issue's own parenthetical lists the **7 DB values**, but the actual schema enum has **9** (`max`/`ultra` included, G4). TC-660-U-07 is written specifically to force this ambiguity into the open before implementation — validating against the issue's literal 7-value list (as written) would be an under-fix relative to the schema (G4/G5), incorrectly rejecting two schema-legal values. Flagged as §7 Q3.
- "key omitted when null/empty" → TC-660-U-05, TC-660-U-06
- "Neither crashes... nor silently degrades" → §5 table, TC-660-I-01
- "Update the stale comment" → not independently testable by an automated case; recommend a manual code-review checklist item at PR review time (the stale comment at `sync.ts:100-102` must be replaced, not left alongside the new mapping code, or it actively misleads the next reader — same principle as `MODEL_PARAM_VALIDATION`'s "update rationale prose" rule).
- "Add a test asserting thinking='off' produces thinkingDefault:'off'" → TC-660-U-01 (elevated to primary regression guard, with an explicit pre/post-fix run requirement, exceeding the issue's minimum ask)

---

## 7. Coverage Questions / Assumptions Needing Project Leadership Confirmation

1. **Empty-string handling implementation trap (TC-660-U-06):** Confirm the fix must use a null-safety check that also excludes `""` (e.g., `typeof row.thinking === "string" && row.thinking.length > 0 && VALID_SET.has(row.thinking)`), not a bare `row.thinking != null` check. Recommend this be called out explicitly in code review, since it's the kind of thing that passes a quick manual test (`thinking: "off"` works) but ships a latent crash for a data condition (`thinking: ""`) that may not exist in current production data but has no schema/DB guarantee against ever occurring.

2. **Case/whitespace normalization policy (TC-660-U-11, TC-660-U-12):** Does `buildAgentsList()` strictly reject non-canonical-cased/whitespace-padded values (treating them as invalid, matching the DB CHECK's exact-match contract), or does it normalize them (trim + lowercase) before the membership check, mirroring the runtime consumer's leniency (`normalizeThinkLevel`, G7)? **This is a real, unresolved design fork — recommend PL/Coder decide before implementation**, since the two behaviors produce different (both individually defensible) outputs for the same malformed-but-recoverable input. My recommendation if forced to pick: strict-reject, because `buildAgentsList` should be a narrow, predictable mapper over a DB contract it does not own the leniency policy for — but this is a recommendation, not a ruling.

3. **Allow-list source: 7 (DB CHECK) vs 9 (schema enum) values (TC-660-U-07, §6):** The issue's own fix description parenthetically lists only the 7 DB-CHECK values as "the thinking enum," but the actual consuming schema accepts 9. Recommend the implementation validate against the **9-value schema enum** (the actual consumer contract), not the 7-value DB CHECK (an internal-only constraint that could change independently) — but flagging explicitly since the issue text, read literally, could lead an implementer to hardcode only 7 values and this test (TC-660-U-07) would then correctly fail against that literal-but-narrower reading. This should be resolved before implementation, not discovered at test-execution time.

4. **Whether the "stale comment" removal is a merge-blocking review item:** Recommend the QA validation pass includes a manual grep for the literal deleted-comment text (`"not a valid per-agent config key"`) in the final diff, and treats its presence as a review finding — since it's explicitly called out in the issue's fix description as required, not optional polish.

5. **No live/staging execution occurred during this design pass** (design-only per task constraints, consistent with the precedent set by TEST-DESIGN-429). Recommend Flint (QA Executor) run TC-660-U-01 and TC-660-I-02 first as the two highest-value regression proofs (they are the ones that most directly demonstrate FAIL→PASS across the fix), followed by the full U-05…U-12 adversarial suite, before broader sign-off. TC-660-I-01…04 require a nova-openclaw checkout alongside the nova-mind checkout (cross-repo) — confirm Flint's execution environment has both available, or scope those four to a follow-up integration pass if not.

---

## 8. Reproduction Transcript (evidence for §1)

```
$ npx tsx /tmp/repro-660.ts
[
  {
    "id": "bastion",
    "model": "anthropic/claude-sonnet-4"
  },
  {
    "id": "newhart",
    "model": "anthropic/claude-opus-4",
    "default": true
  }
]
```
Captured against pinned commit `0d37ab79aaa245f502a211354cb5393dc112a5b6`, unmodified `buildAgentsList()`, confirming the bug as described and establishing the exact baseline TC-660-U-01 and TC-660-I-02 must flip from FAIL to PASS.

---

## 9. Notes for Implementer (Coder)

**Note 1 (existing test conflict):** `sync.test.ts` TC-244-U-01 currently contains the assertion `"thinking is not emitted for any entry"` (line ~130-136), which encodes today's bug as expected behavior. This assertion will fail once the fix lands — that is correct and expected; update/remove that specific `it()` block as part of this fix's PR, do not treat its failure as a regression to work around.

**Note 2 (pre-existing unrelated failures):** 11 of 104 existing tests in `sync.test.ts` fail today on a clean checkout, all in heartbeat-partial-object handling (TC-262-U-05/08, TC-273-U-02/03/09/10) — unrelated to `thinking`/#660. Do not attempt to fix these as part of this PR; they are a separate pre-existing defect (recommend a separate issue if one doesn't already exist — Coder/QA should check before filing per ISSUE_AND_TASK_HYGIENE).

**Note 3 (file placement):** New unit tests (§3) belong in `cognition/focus/agent-config-sync/src/sync.test.ts` (extending the existing file, consistent with its `TC-<issue>-U-##` in-file convention) or a clearly-named sibling file — implementer's call on which, but must be wired into the existing `npm test` script (`npx tsx --test src/sync.test.ts` or an updated glob). New integration tests (§4) require nova-openclaw as a dependency/import source and likely belong in a new test file within this plugin's `src/` given they test the plugin's *output* against the *consumer*, not the consumer's own test suite — recommend `src/sync.integration.test.ts` or equivalent, gated so it doesn't run in CI contexts lacking a nova-openclaw checkout if that's a constraint (confirm with Coder/CI owner).
