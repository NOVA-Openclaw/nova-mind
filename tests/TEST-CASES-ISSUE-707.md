# Test Cases — nova-mind#707, #570, #183, #670, #594 (Chunk D: agent-config-sync)

**SE run #1231, step 3/4 — QA test-case design (Chunk D, final)**
**Author:** Gem (QA Lead)
**Scope:** nova-mind #707 (agents.entries keyed-object shape + restore `$include`), #570 (empty-table clobber
guard), #183 (thinkingDefault — reopened claim, status disputed, see §4), #670 (installer/plugin parity for
thinkingDefault), #594 (SIGUSR1/NOTIFY-storm restart amplification). Final chunk of tracking issue #715. Continues
in the same pinned nova-mind clone/branch as Chunks A/B/C.

---

## 0. Pinned source artifacts

- **nova-mind:** same clone, `~/repos/se1231-nova-mind`, branch `fix/se1231-openclaw-2026.9-regressions`, base
  `12ecc0b`. Chunks A/B/C already committed on top.
- **OpenClaw host behavior reference:** `/home/nova/nova-openclaw-production` at `6ced19b` (2026.9.6),
  `src/config/zod-schema.agents.ts` — read-only reference for the actual 2026.9.x `agents.entries` schema.
- **Source under test:** `cognition/focus/agent-config-sync/src/sync.ts` (read in full, lines 1-140) — the plugin
  that builds `agents.json` from the live `agents` table.
- **Live DB inventory (read-only, `psql -U gem`, `dt.sh agents` run first per instructions):** `nova_memory.agents`
  on `localhost` — schema and row-level facts below via plain `SELECT`/`COUNT` — no writes performed.
- **Live config inventory (read-only):** `~/.openclaw/openclaw.json` (current inline `agents.entries`),
  `~/.openclaw/agents.json` (current bare-array output), `~/.openclaw/openclaw.json.bak.20261004-214851` (last
  backup with `$include` still present, per #707's own text — confirmed to exist, 23,740 bytes, dated Oct 4 21:48).

---

## 1. Host-contract citation: the 2026.9.x `agents.entries` schema (REQUIRED — "cite the schema file:line")

`src/config/zod-schema.agents.ts` (production fork `6ced19b`), lines 20-39:
```
export const AgentsSchema = z.object({
  ownership: z.literal("explicit").optional(),
  defaults: z.lazy(() => AgentDefaultsSchema).optional(),
  entries: z.record(
    z.string().regex(/^[a-z0-9_][a-z0-9_-]{0,63}$/i, "Invalid agent id"),
    AgentEntryConfigSchema,
  ).optional(),
  ...
```
**Line 35-39 is the exact citation:** `entries` is a `z.record(<agent-id regex>, AgentEntryConfigSchema)` — a
RECORD/OBJECT keyed by a validated agent-id string, NOT an array. `AgentEntryConfigSchema` (lines 10-18) wraps
`AgentEntrySchema` (imported from `./zod-schema.agent-runtime.js`) with a prototype-pollution guard
(`isBlockedObjectKey`) and an `.omit({id:true}).extend({default: z.boolean().optional()})` — i.e. the id is the
OBJECT KEY itself, not a field inside each entry (confirming the bare-array shape, which embeds `id` as a field,
is structurally incompatible with this schema, not just stylistically different). Further validation (lines 44-81,
grepped at design time): rejects an empty `entries: {}` ("must contain at least one configured agent"), rejects
duplicate normalized ids resolving to the same agent, and rejects more than one `default: true` entry.

**Current-code baseline — the literal, reproducible #707 bug, confirmed in the pinned ref:**
`cognition/focus/agent-config-sync/src/sync.ts`'s own file header states it "builds the agents.json config as a
bare JSON array of non-peer agents," and `buildAgentsList(rows: AgentRow[]): AgentListEntry[]` (read in full)
returns an ARRAY type. This is NOT a stale/historical description — it is what the pinned `12ecc0b` ref currently,
actually does.

---

## 2. Adversarial/config-seam coverage index

| Requirement | Satisfied by |
|---|---|
| Wrong-type/malformed value at a config seam | TC-707-008 (`fallback_models` wrong type), TC-707-009 (NULL `model`, 3 live rows confirmed), TC-707-010 (unknown provider prefix) |
| Non-identity fixture values | TC-707-011 (retired/non-active rows use REAL distinguishable content, not a blank placeholder row, so a status-filter bug that lets one non-active row through is actually visible) |
| Config→runtime seam populated by production code | TC-707-012 (shape-validated against the REAL live `agents` table, 31 active rows, not a hand-built fixture) |
| INTENT-level check vs. a live source system | TC-707-013 (the cutover-drift report, run against real `openclaw.json`+`agents` table, not a synthetic diff) |
| Source-artifact pinning verified before analysis | §0; `git rev-parse HEAD` checked; `dt.sh agents` run before any table query |

---

## 3. #707 — `agents.entries` keyed-object shape, restore `$include`, validate-before-write, cutover drift (13 cases: TC-707-001…013)

### TC-707-001 — `buildAgentsList` output changes from a bare array to `{ "<id>": {...} }`
**Priority:** P1 (Critical) — direct acceptance test, the core of #707.
**Steps:** Run the fixed generator against a small fixture (3-4 agents).
**Expected:** Output is a JSON OBJECT, keyed by each agent's `id` (matching the regex in §1's schema citation), with
the `id` field itself OMITTED from each entry's value (per `AgentEntryConfigSchema.omit({id:true})`) — not merely
"an object that happens to also still carry an `id` field inside each value," which would pass a loose shape check
but fail stricter schema validation or waste bytes.

### TC-707-002 — Output round-trips through `openclaw config validate` cleanly
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED by #707's own fix list ("Tests: shape round-trips
through `openclaw config validate`").
**Steps:** Generate `agents.json` from the live (or a staging-mirrored) `agents` table; wire it via `$include`;
run `openclaw config validate`.
**Expected:** Exit 0, no schema errors referencing `agents.entries`.

### TC-707-003 — `"entries": {"$include": "./agents.json"}` is restored in `openclaw.json`
**Priority:** P1 (Critical) — direct acceptance test.
**Expected:** The live `openclaw.json`'s `agents.entries` is the `$include` directive (matching the shape still
present in `openclaw.json.bak.20261004-214851`, confirmed to exist as the last backup with it), not an inline
object — restoring the actual data-flow path from the DB.

### TC-707-004 — VALIDATION happens BEFORE the atomic write, not after (no hot-reload crash-loop)
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED per #707's own stated risk ("If the include is
restored as-is, schema validation fails, which risks a crash-loop under hot reload") and this dispatch's explicit
ask ("validation BEFORE an atomic write... per UNIVERSAL/CONFIG_SAFETY"). `sync.ts`'s own header confirms the
write path is "atomically (tmp + rename)" — this test verifies validation is a gate BEFORE that tmp-file is
promoted via rename, not a check performed on the already-live file after the fact.
**Preconditions:** A fixture that would produce schema-INVALID output (e.g. a malformed agent id from TC-707-010).
**Steps:** Run the generator against this fixture.
**Expected:** The invalid shape is caught and the write is ABORTED before the `rename` step — the previously-live
`agents.json` is left completely untouched (not replaced with a broken file, not left in a half-written tmp
state that a hot-reload watcher could pick up). This is the exact mechanism that prevents #707's own named
crash-loop risk. **(Note: the pinned `sync.ts`, read only through line 140, was not confirmed to already contain
this gate — it most likely needs to be ADDED as part of this fix; flagged in §5 Open Questions if implementation
review finds it's partially present already.)**

### TC-707-005 — Only `status='active'` rows are included in the generated output
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED by dispatch.
**Preconditions:** Live `agents` table confirmed: 31 total rows, 31 `status='active'` (i.e. currently NO non-active
rows exist to naturally exercise this — see TC-707-011 for why a synthetic fixture is required).
**Steps:** Run the generator against the live table (0 non-active rows today) AND against a fixture with at least
one `status != 'active'` row (e.g. `retired`).
**Expected:** Live-table run: all 31 agents appear (trivially passes today, not a strong test on its own). Fixture
run: the non-active row is ABSENT from the output — this is the test that actually exercises the filter.

### TC-707-006 — `get_agent_export_rows()`'s peer-exclusion (via `parent_agents` array overlap) is preserved by the shape change
**Priority:** P2 (High) — regression guard; the shape fix must not accidentally touch the SQL-level peer-scoping
that already exists (`AGENTS_QUERY` calls this Postgres function, which scopes to the connecting role plus
subagents owning that role via `parent_agents` overlap).
**Expected:** A peer agent's own rows (e.g. graybeard's) are still excluded from nova's generated `agents.json`
after the shape change — the fix touches OUTPUT FORMAT, not the SQL scoping.

### TC-707-007 — `_generate_agents_json()` (installer, `agent-install.sh`) is ALSO updated to the keyed-object shape
**Priority:** P1 (Critical) — direct acceptance test; #707 explicitly says "Update `_generate_agents_json()` in the
installer to match (see #670)" — a fix that only touches the plugin's runtime path and leaves the installer's
fresh-install generator on the OLD bare-array shape reintroduces #707's own bug for any environment relying on
installer-generated output before the plugin's first sync.
**Expected:** Both `sync.ts`'s `buildAgentsList()` and the installer's `_generate_agents_json()` emit the
IDENTICAL keyed-object shape.

### TC-707-008 — Adversarial: `fallback_models` is the WRONG TYPE (e.g. a single string instead of `text[]`)
**Priority:** P1 (Critical) — REQUIRED adversarial wrong-type case. DB schema declares `fallback_models text[]`,
but a malformed row (e.g. from a manual `UPDATE`, or a migration that didn't cast correctly) could have it stored
as a scalar.
**Steps:** Run the generator against a fixture row with `fallback_models` as a non-array value.
**Expected:** The generator either normalizes it to a single-element array or REJECTS the row with a loud,
specific error identifying the malformed field — never silently emits a malformed `fallbacks` value into
`agents.json` that would itself fail `AgentEntrySchema` validation downstream (which TC-707-002/004 would then
need to catch anyway — this test is about catching it AT GENERATION TIME with a clear reason, not just eventually
failing validation with a confusing error).

### TC-707-009 — Adversarial: `model` is NULL on an active row (3 such rows confirmed live today)
**Priority:** P1 (Critical) — REQUIRED adversarial case, using REAL live data (not synthetic) — a live, read-only
query at design time confirms **3 active `agents` rows currently have `model IS NULL`**.
**Steps:** Run the generator against the live table (which already contains these 3 rows).
**Expected:** Each NULL-model active agent is handled explicitly — either omitted from the output with a logged
reason, or falls back to `agents.defaults.model` by omitting the `model` key entirely (schema-compliant, since
`AgentEntrySchema`'s `model` field is presumably optional for default-inheriting agents — confirm against the
actual schema) — but NEVER emits a literal `"model": null` or `"model": "null"` string into `agents.json`, which
would fail schema validation and could trigger exactly the crash-loop TC-707-004 exists to prevent.

### TC-707-010 — Adversarial: an agent id or model string contains an unknown/malformed provider prefix
**Priority:** P2 (High) — adversarial malformed-value case.
**Preconditions:** A fixture row with `model` set to a string with no recognizable provider prefix (e.g.
`"totally-unknown-provider/some-model"` or a bare model name with no `/`).
**Steps:** Run the generator.
**Expected:** The generator does not crash; either passes the value through as-is (if the schema doesn't validate
provider prefixes beyond basic string shape — confirm against `AgentEntrySchema`) or rejects/flags it loudly if
the schema does enforce a known-provider allowlist. Either way, this must not be the thing that silently produces
a validation failure caught only at `openclaw config validate` time with no attribution to which agent row caused it.

### TC-707-011 — Non-active rows use REAL, distinguishable content (non-identity fixture)
**Priority:** P1 (Critical) — REQUIRED non-identity-fixture case supporting TC-707-005; a retired-row fixture with
blank/placeholder content wouldn't actually prove the filter works, since an accidentally-included blank row would
be hard to notice.
**Steps:** Seed a fixture retired row with a REAL-looking, non-blank model/subagents/thinkingDefault configuration
distinguishable from every active row's content.
**Expected:** TC-707-005's filter correctly excludes it; if it ever leaked through, its distinctive content would
be immediately obvious in the generated output (not silently blended in).

### TC-707-012 — Config→runtime seam: the generator runs against the REAL `agents` table, not a hand-built fixture, for the final acceptance pass
**Priority:** P1 (Critical) — REQUIRED config→runtime seam case.
**Steps:** On staging, run the fixed generator against the REAL live-shaped `agents` table (31 active rows,
including the 3 real NULL-model rows from TC-707-009); feed the result through `openclaw config validate` for
real.
**Expected:** Succeeds end-to-end against real data, not just against hand-picked fixtures that happen to avoid
every edge case actually present in production.

### TC-707-013 — CUTOVER DRIFT: generated output is diffed against the CURRENT inline `agents.entries` before the `$include` is switched on; drift is reported, not silently applied
**Priority:** P1 (Critical) — REQUIRED by dispatch, the single highest-stakes test in this file: "Before the
`$include` is switched on, the generated file must be diffed against the current inline entries and the drift
reported, so the cutover can't silently revert models." Confirmed live, read-only, at design time — the drift is
REAL, not hypothetical:
- **Agent count:** live inline `agents.entries` has exactly **16 agents** (`athena, cadence, coder, flint, gem,
  gidget, hermes, iris, lex, marcie, mason, nova, pixel, quill, scout, scribe`). The `agents` DB table has **31
  active rows**. Switching on `$include` naively would ADD 15 agents' worth of config the gateway has never seen
  live, with no review step.
- **Model drift (the specific regression this test exists to prevent):** the live, currently-running
  `openclaw.json` has nova's model as `{primary: "openrouter/anthropic/claude-opus-5.5", fallbacks: [...11
  entries, including "anthropic/claude-opus-4-8"...]}`. The DB's `agents.model` column for nova's row is
  `"anthropic/claude-opus-4-8"` — i.e., **the DB has nova's CURRENT FALLBACK as her PRIMARY**, and has no record of
  `openrouter/anthropic/claude-opus-5.5` as primary at all. A naive cutover would silently DOWNGRADE nova from her
  live primary model to a fallback, with no warning.
**Steps:** Before enabling `$include`, generate `agents.json` from the live DB and diff it field-by-field against
the current inline `agents.entries` for every one of the 16 agents present in both. Produce a report listing every
field that differs (not just "16 vs 31 agent count," which is the coarse/obvious half of this test — the MODEL
field diff for nova specifically is the dangerous, easy-to-miss half).
**Expected:** The report explicitly flags nova's model drift (DB says `anthropic/claude-opus-4-8`, live runs
`openrouter/anthropic/claude-opus-5.5`) as a DIFFERENCE requiring a decision — not auto-resolved either way — and
lists all 15 DB-only agents as "new agents this cutover would add, review before enabling." **The cutover must not
proceed (i.e. `$include` must not be switched on) until this report has been reviewed and the drift explicitly
reconciled** (either by updating the DB row to match the live model and THEN cutting over, or by deliberately
accepting the model change) — this test's pass criterion is that the DIFF AND BLOCK behavior exists, not that any
particular reconciliation choice was made (that's an operator decision, out of this test's scope). **Related DB
finding, worth citing for context:** a `protect_peer_models` trigger (`BEFORE UPDATE`, confirmed live via
`dt.sh agents`) already guards against unintended peer-agent model changes at the DB layer — this test's drift
report is the analogous guard for the DB→config direction, which has no existing protection today.

---

## 4. #183 — thinkingDefault: STATUS DISPUTED, test cases confirm/refute against the pinned ref (3 cases: TC-183-001…003)

**Finding (flagged, not silently resolved):** #183's reopening comment claims "sync.ts (line 75-77) still has the
outdated comment explicitly excluding the thinking column... Lex and Cadence are both missing `thinkingDefault` in
their agents.json entries... The fix was never implemented." **This directly contradicts what's actually in the
pinned `12ecc0b` ref**: `sync.ts` lines 102-124 contain a complete, working `thinkingDefault` mapping (from
#660's fix) — it reads the DB's `thinking` column, validates against a 9-value `VALID_THINKING_DEFAULTS` set (the
code's own comment notes "config schema accepts 9 values; DB CHECK only enforces 7" — confirmed: the live DB
`CHECK` constraint on `agents.thinking` is exactly 7 values), and omits the field for null/invalid/wrong-type/
padded values. **Either #183's reopening comment is describing a PRE-#660 state that's now stale, or there's a
separate regression this design pass didn't catch.** Test cases below are written to EMPIRICALLY SETTLE this,
rather than assuming either side of the contradiction.

### TC-183-001 — EMPIRICAL CHECK: does the pinned ref's `buildAgentsList()` actually emit `thinkingDefault` for lex and cadence?
**Priority:** P1 (Critical) — direct resolution test for the §4 contradiction.
**Steps:** Run the pinned `12ecc0b` ref's `sync.ts` `buildAgentsList()` against lex's and cadence's REAL live DB
rows (confirm their `thinking` column values first — #183 claims `lex=medium, cadence=low`).
**Expected (one of two outcomes, both informative):** (a) `thinkingDefault` IS correctly emitted for both — this
PROVES #183's reopening comment is stale/already-resolved, and #183 should be re-closed with this evidence rather
than left open indefinitely; or (b) it is NOT emitted — this means there's a genuine regression this design pass
didn't catch (e.g. something between `buildAgentsList()`'s computation and the final JSON write drops the field),
requiring a NEW root-cause investigation, not just re-applying #660's already-present logic.

### TC-183-002 — `thinkingDefault` omission logic correctly handles the 9-vs-7 enum mismatch (schema allows `max`/`ultra`, DB CHECK doesn't)
**Priority:** P2 (High) — regression guard for the specific mismatch `sync.ts`'s own comment calls out.
**Expected:** Since the DB `CHECK` constraint structurally PREVENTS `thinking` from ever being `max`/`ultra` (only
7 of the 9 schema-valid values are DB-reachable), this gap is currently more theoretical than practical — this
test exists to confirm the omission logic doesn't error on these two values IF a future DB migration ever allows
them, not because today's data can produce them.

### TC-183-003 — Lex/Cadence's Discord channel separation (#lex, #music) no longer leaks thinking/response pairs — per #183's ORIGINAL symptom
**Priority:** P1 (Critical) — the actual user-visible symptom #183 exists to fix, tested directly rather than only
at the config-generation layer (TC-183-001 proves the CONFIG is right; this proves the BEHAVIOR is right).
**Preconditions:** Outcome of TC-183-001 is (a) (thinkingDefault correctly emitted).
**Steps:** Trigger a turn for lex and a turn for cadence on staging; inspect their respective Discord channel
output.
**Expected:** No thinking-block leakage in either channel — this is the end-to-end proof that the config fix (if
confirmed present) actually produces the correct runtime behavior, not just correct JSON.

---

## 5. #670 — Installer/plugin parity for thinkingDefault (3 cases: TC-670-001…003)

### TC-670-001 — `agent-install.sh`'s `_generate_agents_json()` emits `thinkingDefault` with the SAME validation/omission logic as the plugin
**Priority:** P1 (Critical) — direct acceptance test, per #670: "Port `VALID_THINKING_DEFAULTS` enum-validation +
omission logic into `_generate_agents_json()`'s inline SQL query."
**Steps:** Run both the installer's generator AND the plugin's `buildAgentsList()` against the SAME fixture rows
(including edge cases: null, invalid string, valid-but-DB-unreachable `max`/`ultra`, valid `medium`).
**Expected:** Byte-for-byte identical `thinkingDefault` handling between the two generators for every fixture row —
this is literally what `TC-429-P-06` (#670's own cited parity test) should already assert; this test extends it
specifically to the `thinkingDefault` field, since #670's claim is that this ONE field broke parity.

### TC-670-002 — Parity gap window: a fresh install's agents.json (pre-first-gateway-start) correctly has `thinkingDefault`, not just the post-sync version
**Priority:** P1 (Critical) — direct test of #670's "practical impact" note: the gap only surfaces in the narrow
window between installer-generation and the plugin's first startup sync.
**Steps:** Run ONLY the installer's generator (don't let the plugin run yet); inspect the resulting `agents.json`.
**Expected:** `thinkingDefault` is present and correct even in this pre-plugin-sync window — proving the fix closes
the gap at its actual point of impact, not just asserting eventual consistency after the plugin's own sync
overwrites it moments later.

### TC-670-003 — `TC-429-P-06` itself is updated/re-verified to actually catch this class of parity gap going forward
**Priority:** P2 (High) — meta-test: #670 states this existing parity test SHOULD have caught the regression but
evidently didn't (or wasn't run against this specific field). Confirming `TC-429-P-06`'s own field coverage
includes `thinkingDefault` explicitly, not just a coarse "does the output look similar" check.

---

## 6. #594 — SIGUSR1/NOTIFY-storm restart amplification (6 cases: TC-594-001…006)

**Host-contract citations (confirmed live, `dt.sh agents`):** the `agent_config_changed` trigger on
`public.agents` is `AFTER INSERT OR DELETE OR UPDATE FOR EACH ROW`, calling `notify_agent_config_changed()` —
confirms #594's own 2026-09-07 finding exactly (row-level, not statement-level, fan-out). `agents.json` is
`$include`d in `openclaw.json` (restored per #707/TC-707-003), so the gateway's own hot-reload file watcher
ALSO monitors it independently of whatever the `agent_config_sync` plugin does — two independent restart-trigger
paths exist by construction, not by bug.

### TC-594-001 — A single-row `agents` UPDATE produces AT MOST ONE actual gateway restart, not two
**Priority:** P1 (Critical) — direct acceptance test, the core of #594: "Each `agent_config_sync` write
potentially triggers BOTH watcher-driven reload AND the plugin's explicit SIGUSR1."
**Steps:** Update one agent's row (e.g. a model change); observe both the plugin's own signal path and the
file-watcher's reload path.
**Expected:** Exactly one effective restart — either the fix removes the plugin's own `SIGUSR1` call (relying
solely on the watcher) or the two paths are coalesced BEFORE a restart is scheduled, not merely coalesced
after both have already fired (today's "coalescing logic catches duplicates most of the time," per #594's own
2026-08-15 comment — "most of the time" is not "always," and this test's job is to catch the residual cases).

### TC-594-002 — A 23-row bulk UPDATE with identical timestamps produces ONE evaluation, not 23 (or 9) signals
**Priority:** P1 (Critical) — direct acceptance test, reproduces #594's own documented live incident exactly (2026-
09-07, 10:02:53: 23 rows → 9 signals + 8 "coalesced" log lines → one real restart anyway).
**Steps:** Perform a bulk `UPDATE` touching 23 rows in one statement/transaction.
**Expected:** The notification/debounce layer collapses this into ONE evaluation before any restart signal is even
considered — not 9 signals that then get coalesced down to 1 restart after the fact. The distinction matters:
today's approach already prevents 9 restarts from becoming 9 actual restarts, but the 9 signals themselves are
pure noise/log-spam and (per #594's own finding) a measurable amplification vector even when ultimately harmless.

### TC-594-003 — "Config unchanged after notification" case produces ZERO restart signals, not a signal that's merely ignored afterward
**Priority:** P1 (Critical) — direct acceptance test for #594's starkest finding: "of 11 config_sync signals [on
2026-09-07], only 2 produced actual config change... That's 9 gateway restart signals for zero config delta."
**Preconditions:** A DB write that fires the `agent_config_changed` trigger but results in NO actual difference in
the generated `agents.json` (e.g. an `UPDATE` that sets a column to its existing value, or touches an unrelated
column the generator doesn't read).
**Steps:** Perform such a no-op-equivalent write.
**Expected:** Zero `SIGUSR1` signals and zero file-watcher-triggered restarts — the fix must compare GENERATED
OUTPUT, not just "a row changed," before deciding a restart is warranted.

### TC-594-004 — Debounce window itself is adversarially tested: two genuinely-different config changes within the debounce window both get applied (not just the first discarded)
**Priority:** P2 (High) — regression guard; a naive debounce/coalesce fix could accidentally drop a SECOND, real
change that lands milliseconds after a first one, if coalescing isn't done correctly (take-latest, not
take-first-and-ignore-rest).
**Steps:** Two real, different agent updates within the same debounce window (e.g. 500ms).
**Expected:** The FINAL generated `agents.json` reflects BOTH changes (since a single post-debounce regeneration
reads the current DB state, which has both applied) — exactly one restart, with the fully up-to-date config, not
a restart reflecting only the first of the two changes.

### TC-594-005 — Restart deferral still honors in-flight work after the fix (no regression of the existing 5-minute deferral/drain behavior)
**Priority:** P2 (High) — regression guard referencing nova-openclaw#175 (cited in #594's own comments): "each
restart ran full 5-minute deferral then force-killed with 0ms drain, discarding 391/32/525 pending replies." This
fix's scope is reducing SPURIOUS restarts, not touching the deferral/drain mechanism itself — confirm a genuinely
warranted restart (TC-594-001's single real change) still goes through the existing deferral path correctly.

### TC-594-006 — A statement-level (not row-level) trigger alternative is evaluated for the bulk-UPDATE fan-out root cause
**Priority:** P3 (Low) — per #594's own suggested fix ("a statement-level trigger... would address bulk-UPDATE
fan-out at source"). This is a design-alternative evaluation note, not necessarily a pass/fail test: confirm
whether the chosen fix addresses the fan-out at the notification/debounce-consumer layer (sufficient per TC-594-
002) or at the trigger layer itself (`FOR EACH STATEMENT` instead of `FOR EACH ROW`) — either is acceptable, but
the choice should be a documented decision, not an accident of where the first fix was easiest to land.

---

## 7. Open questions for the orchestrator / Project Leadership review

1. **#183's actual status is disputed by live code inspection (§4) — not resolved by this test design, by design.**
   TC-183-001 is written specifically to let implementation/QA execution settle this empirically rather than this
   design pass guessing. Flagging prominently since acting on #183 as if it were still fully broken (without
   running TC-183-001 first) risks duplicate work on an already-fixed path.
2. **TC-707-004's "validate before atomic write" gate was not confirmed to already exist** in the pinned `sync.ts`
   (only lines 1-140 were read in this design pass; the file may be longer). If implementation review finds this
   gate already exists, TC-707-004 becomes a pure regression test rather than a new-feature acceptance test —
   either way the test itself doesn't need to change, just its framing.
3. **`UNIVERSAL/CONFIG_SAFETY`'s exact text** (cited by this dispatch as the source of the "validate before write,
   no crash-loop" principle) was not independently located/read within this design pass's budget — TC-707-004's
   requirements are drawn from #707's own issue text and this dispatch's wording, not independently cross-checked
   against that memory doc's exact language.
4. **TC-707-013's cutover-drift report format and gating mechanism** (a CLI flag, a required manual sign-off step,
   a CI check) is not specified anywhere in the source material — this test's acceptance criterion is "drift is
   computed and surfaced before cutover, cutover is blocked until reconciled," which is implementation-agnostic;
   confirming the actual UX/mechanism once implementation is underway.
5. **TC-594's chosen fix mechanism** (remove the plugin's own SIGUSR1 vs. consumer-side debounce vs. statement-level
   trigger, per TC-594-006) affects exactly how TC-594-001/002 should be executed (what to instrument/observe) —
   this design pass wrote the tests against OBSERVABLE OUTCOMES (restart count, signal count) rather than against
   a specific implementation, so they should run unchanged regardless of which mechanism is chosen, but flagging
   this as worth confirming once a mechanism is picked.
