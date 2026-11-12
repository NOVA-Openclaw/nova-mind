# Test Cases — nova-mind#657: Deterministic Three-Axis Finding Audit Gate (existence/confidence/source-tier)

**SE run #1282, step 3 — QA test-case design**
**Author:** Gidget (QA, subagent)
**Date:** 2026-11-12
**Source artifact pinned:** fresh clone, `https://github.com/NOVA-Openclaw/nova-mind`,
branch `feat/657-finding-audit-gate`, commit `286f24aca9377e74adf2d0bec076b2bb4701fd7a`
(verified via `git rev-parse HEAD` before analysis — see §7).

**Inputs read in full:**
- `gh issue view 657 --repo NOVA-Openclaw/nova-mind --comments` (issue body + all 6 comments,
  including SE run #843 step-2/step-3 history, the step-3-review correction pass, and the
  SE#1282 step-2 expanded-design comment, id 6233790102)
- `workflow_steps` description for `workflow_id=4, step_order=3` (QA test-design process
  requirements: adversarial-input coverage, source-artifact pinning, file disposition)
- `workflow_steps` for `workflow_id=32` (Unsolved Problems Research), all 5 steps — confirms
  the gate's wiring point is step 3 ("Work the Session"), before `progress_notes` is written
- `workflow_steps` for `workflow_id=24` (research-ingestion) — confirms `research_findings`/
  `research_citations` write path and the `scout`-only write-protection convention
- Live `nova_memory` schema: `research_findings`, `research_citations`, `research_tasks`,
  `unsolved_problems` (`\d` output), and the `protect_research_writes()` trigger function body
- Gidget's own SE#1282 step-2 v3 Jev calibration artifacts: `metrics.json`,
  `step2-report-v3.md` (`/home/nova/.openclaw/workspace/research/se1282/v3/`)
- `evals/se717/test-case-design-v2.md` in-repo, for this repo's test-design conventions
  (TC numbering, Group structure, invariants table, rulings table, revision log style)
- Repo layout at the pinned commit: no `scripts/research-audit-gate*`, no `research/unsolved/`
  working directory, and no `jev`/`systemone` references exist yet anywhere in the repo —
  **this is a greenfield design**, not an extension of existing gate code. The gate sits in
  front of workflow 32 step 3's "Work the Session" reasoning pass, reading
  `research_findings`/`research_citations` for a given `task_id`.

---

## 0. Design Decisions Made During Test Design (with reasons)

These are QA-stage decisions about **how to test**, distinct from the five already-settled
engineering decisions in the dispatch brief (72h window, Jev Support threshold 0.05, Scope
Choice advisory-only, direct `/v1/systemone` calls, three-axis gate). All items that originally
needed Project Leadership rulings have since been ruled on (§6, Rev 2) and are pinned directly
in the relevant test cases below; this section records the QA-stage reasoning, not open
questions.

**D1 — Treat the join correction and tier-field correction from SE#843 step 2 as binding
inputs, not re-litigated.** The issue body's AC1 text ("reads `research_citations` +
`research_findings`") undersells the real join requirement: `research_citations` has no
`task_id`; it only has `finding_id` → FK to `research_findings.id`. Confirmed still true in the
live schema at the pinned commit (§ schema dump above). Likewise `research_citations` already
has both `reliability numeric(3,2)` and `source_type varchar(50)` — the SOURCE TIER axis must
reconcile these two existing columns, not add a parallel tier column. Both corrections are
re-verified against the live schema in this session (not merely inherited from the old
comment thread) and are baked into Groups DB/TIER below, plus a standalone schema-fidelity
regression test (TIER-09) guarding against a future implementer "solving" TIER by adding a new
column instead of reconciling the two that exist.

**D2 — Fold the Jev/skeptic escalation layer in as first-class test surface, not a bolt-on.**
SE#1282 step 2 (expanded design, comment 6233790102) materially changed the gate's internal
mechanism since the original issue was written: it is no longer pure deterministic
URL-resolution + string comparison. Per-finding judgments (does citation support the claim?
scope? tier plausibility?) now route through Jev Noul/Choice calls, with deterministic code
only at the aggregation/exit-code layer. Because I)ruid's decisions (2026-11-12) confirm Jev
Support Noul gates at threshold 0.05 and Scope Choice is advisory-only-never-gates, the test
design below treats "the gate" as the composite of deterministic checks (existence URL/title,
confidence-value sanity, tier classification, high-risk-cell flag, UNREAD fail-closed) AND the
Jev-mediated support/scope layer, each with its own boundary-value and adversarial-input
coverage. A design that tested only the deterministic half would certify the easy 90% and miss
exactly the threshold-boundary and malformed-API-response bugs that matter (lessons 594/787/811
pattern, cited in the workflow-4 step-3 requirement).

**D3 — Non-identity fixture values everywhere an axis value enters a decision.** Per the
step-3 process requirement, no fixture uses 0/empty/default values at a seam that performs a
comparison or threshold check: confidence fixtures use 0.62, 0.78, 0.91, never 0.00; reliability
fixtures use 0.15, 0.40, 0.73, 0.88, never the column's implicit NULL-as-unscored or a bare
0.00/1.00 pair that could mask a fencepost bug the same way a 0/1 boolean-style pair would.
Where 0.00/1.00 boundary values ARE the thing under test (e.g. the confidence check-constraint
boundary, or the "confidence=1.00 restricted to facts-about-a-document" rule), they are used
deliberately as boundary-value-analysis (BVA) cases, called out explicitly as such, not as
default placeholder values.

**D4 — Scope the DB-interaction tests as strictly read-only against `research_*`, with the
row-count invariant as the enforcement mechanism, not a policy statement alone.** The gate's
job per the issue is to *read* `research_findings`/`research_citations` for a `task_id` and
emit a review table + exit code; nothing in the issue, the SE#1282 amendment, or I)ruid's
2026-11-12 decisions grants it write access, and the live `protect_research_writes()` trigger
already restricts `research_*` writes to `scout`/`postgres`/superusers. Group DB therefore
asserts `SELECT count(*) FROM research_findings` is identical before and after every gate
invocation in the test suite (not just "the script doesn't call INSERT/UPDATE" by code
inspection, which a future refactor could silently violate without any test noticing).

**D5 — Model the 72h source-drop window as a config→runtime seam, with its own dedicated test
rather than folding it into the NET group as an afterthought.** I)ruid's 2026-11-12 ruling
confirms the window numerically (72h) but the collector code that owns the clock comparison
does not exist in this repo yet. WIRE-06/NET-07 below test that the 72h figure is read from a
single named config constant/env value at runtime (not hardcoded in three places that could
drift), and CONFIG-01 independently exercises the actual boundary arithmetic against
production-shaped (collector-populated) `accessed_at`/retry-count metadata, not a
hand-constructed stub — satisfying the config→runtime-seam requirement in the step-3 process
description.

**D6 — Pin the Jev threshold BVA to the exact figures confirmed by calibration, and separate
"Jev call succeeded with boundary probability" from "Jev call itself failed/errored."** These
are different failure classes (a probability of exactly 0.05 is a valid API response that must
be classified correctly under a stated tie-breaking rule; a NaN, out-of-range, or missing
probability, or an HTTP timeout/5xx, is an API/contract failure that must fail closed). Treating
them as one group risks conflating "the threshold logic is wrong" with "the API error handling
is wrong" in a way that makes a failing test hard to diagnose. Split into JEV-THRESH (valid
responses at/near the boundary) and JEV-ERR (invalid/absent/failed responses) below.

**D7 — No Jev API calls are made during this test design or its eventual execution against
live `jev-latest`.** Per task constraints (no spend beyond trivial), all Jev-layer test cases
specify **mocked/stubbed HTTP responses** at the `/v1/systemone` boundary (fixed JSON payloads
representing valid, boundary, malformed, and error responses) rather than live calls. This
mirrors the calibration work's own finding that `supports_claim` behavior is now well-understood
from the v3 run (AUROC 1.000, n=62, cutoff 0.05 empirically set) — the gate's *logic* around
that score, not the model's judgment quality, is what this suite certifies. A separate,
periodic live-calibration-refresh task (already flagged in the v3 report as "recalibrate on
collector output, grow to 150+") remains the correct mechanism for revalidating Jev's actual
judgment quality; conflating that with gate-logic unit/integration tests would reintroduce the
non-trivial spend this task is explicitly scoped to avoid.

---

## 1. Acceptance-Criteria → Test-Group Mapping

| AC (from issue #657) | Covered by group(s) |
|---|---|
| AC1 — script takes `task_id`, reads citations+findings via correct join, exits non-zero on axis failure | DB, GATE |
| AC2 — URL resolution + title comparison; network failure → UNREAD, never silently coerced to pass | EXIST, NET |
| AC3 — confidence rule encoded, including the 1.00 restriction | CONF |
| AC4 — source tier classified per citation (reconciling existing columns, not a new field) | TIER |
| AC5 — high-risk cell (weakest tier × most consequential claim) flagged explicitly | RISK |
| AC6 — human-readable review table emitted | OUT |
| AC7 — failure must be arithmetically possible (negative test proving a real fail) | NEG |
| AC8 — wired into workflow 32 synthesis step so it cannot be skipped by forgetting | WIRE |
| *(SE#1282 amendment)* Jev Support Noul gates at 0.05; Scope Choice advisory-only | JEV-THRESH, JEV-ERR, SCOPE |
| *(SE#1282 amendment)* 72h source-drop window; collector fetch/snapshot/retry lifecycle | NET, CONFIG |
| *(step-3 process requirement)* adversarial/malformed input coverage | ADV (cross-cutting, see §2) |
| *(step-3 process requirement)* config→runtime seam | CONFIG |
| *(step-3 process requirement)* DB read-only / row-count-unchanged invariant | DB, GATE |

---

## 2. Invariants Under Test

- **INV-1 (read-only):** No gate invocation in this suite changes `SELECT count(*) FROM
  research_findings` or `research_citations`. Enforced per-test, not asserted once.
- **INV-2 (fail-closed):** Every ambiguous, erroring, timed-out, or malformed input state
  (network failure, Jev API error, missing/NaN/out-of-range probability, missing required
  citation field) resolves to UNREAD/escalate/non-pass — never to a silent pass. "The gate
  could not determine X" must never be collapsed into "X is fine."
  INV-2 is satisfied by the pinned ruling (§6, OQ-2/OQ-3): UNREAD within the 72h window is
  gate-BLOCKING (exit 1, not advisory) and shares the same exit-code value (1) as a hard
  tier/confidence/existence violation — the taxonomy is deliberately coarse (three codes total,
  §6 OQ-2), with the distinction between violation classes carried in the review table's named
  text, not in a separate exit code per class. GATE-06/GATE-06A/NET-01..07 test the pinned
  behavior directly, not a range of candidate outcomes.
- **INV-3 (scope never gates):** Jev Scope Choice output appears in the review table and is
  logged, but no combination of Scope Choice values or confidence changes the gate's exit code
  — only the deterministic axis checks and the Jev Support Noul score (plus its escalation to
  skeptics) affect pass/fail.
- **INV-4 (deterministic aggregation):** Given the same `(findings, citations, Jev responses)`
  input tuple, the gate produces the same exit code and the same set of flagged violations on
  repeated runs — no run-to-run nondeterminism from iteration order, floating-point
  comparison, or unstable sort.
- **INV-5 (is_current filter honored):** Superseded (`is_current = false`) findings and their
  citations never appear in the review table and never contribute to a violation or a
  high-risk-cell flag, per SE#843 step-2 Correction 1.
- **INV-6 (reconciled tier, no shadow field):** The gate computes SOURCE TIER at read time from
  existing `reliability`/`source_type` columns; no new persisted tier column or field is
  introduced on `research_citations` (SE#843 step-2 Correction 2, carried forward).
- **INV-7 (atomic-claim granularity):** Compound findings are split into atomic claims before
  any Jev Noul call; a Noul score is never computed against, or averaged across, a compound
  (multi-assertion) claim string.

---

## 3. Test Cases

### Group DB — Join Correctness & Read-Only Contract (7 cases)

**TC-657-DB-01 — Correct join path: `research_citations.finding_id` → `research_findings.id` filtered by `task_id`**
- **Fixture:** Task `task_id=90001` (non-identity id) with 3 findings, each with 1-2 citations.
- **Steps:** Invoke gate with `task_id=90001`.
- **Expected:** Review table contains exactly the 3 findings and their citations for task
  90001; a sibling task's findings (90002, same DB) never appear.

**TC-657-DB-02 — `is_current = false` findings excluded (INV-5)**
- **Fixture:** Task 90001, finding A `is_current=true`, finding A' (same chain, `superseded_by`
  pointing to A, `is_current=false`) with a citation whose tier would otherwise trip the
  high-risk flag.
- **Expected:** Only finding A (and its citations) appear; finding A''s citation is absent from
  the table AND does not contribute to the high-risk-cell flag even if its tier/confidence
  values alone would qualify.

**TC-657-DB-03 — Finding with zero citations**
- **Fixture:** A finding with no `research_citations` rows at all (not NULL fields — zero rows).
- **Expected:** Finding appears in the review table with an explicit "no citations" state,
  distinct from an UNREAD or tier-unscored state; does not crash the join (LEFT JOIN
  semantics, not INNER JOIN, required here — an INNER JOIN would silently drop uncited
  findings from review, which is itself a fail-closed violation since an uncited finding
  making a confident claim is exactly the pattern AC5 exists to catch).

**TC-657-DB-04 — Citation belongs to a different task's finding (negative join case)**
- **Fixture:** Citation C has `finding_id` pointing to a finding under task 90002, while the
  gate is invoked for task 90001.
- **Expected:** C never appears in task 90001's output. (Isolates a join-condition bug where a
  missing or malformed `WHERE research_findings.task_id = $1` could leak cross-task citations.)

**TC-657-DB-05 — Non-existent `task_id` — RULED: exit 2 (gate could not run)**
- **Fixture:** `task_id=999999` (no `research_tasks` row).
- **Expected:** Per the pinned exit-code taxonomy (0=all pass, 1=one or more findings blocked,
  2=gate could not run — config/DB/usage error), an invalid `task_id` is a usage/DB-lookup
  error, not a finding-level gate decision: exit 2, with a clear "task not found" message —
  NOT exit 1 (that code is reserved for a task that WAS found and has a blocked finding) and
  NOT a silent empty-pass at exit 0.

**TC-657-DB-06 — Row-count-unchanged invariant (INV-1), run against a fixture with an
  intentional known-bad citation**
- **Fixture:** Reuse the NEG-01 known-bad fixture (below).
- **Steps:** Record `SELECT count(*) FROM research_findings`, `research_citations` before;
  invoke the gate (expected to fail/exit non-zero); record counts after.
- **Expected:** Counts identical before/after, even on a run that finds and reports violations.
  A gate that "fixes" or annotates the DB in response to finding a problem is out of scope and
  itself a contract violation.

**TC-657-DB-07 — Gate process runs as a read-only-sufficient role, never as `scout`**
- **Fixture:** None (static/config check).
- **Steps:** Inspect the gate's DB connection configuration.
- **Expected:** Connects as a role that cannot write `research_*` (i.e., explicitly NOT
  `scout`, not a superuser) — relying on the trigger alone as the only enforcement layer is a
  defense-in-depth gap; the gate's own connection role should be read-only by design, so a
  future code change that accidentally adds a write statement fails at the connection-grant
  layer, not only at the trigger layer.

### Group EXIST — Existence Axis (9 cases)

**TC-657-EXIST-01 — URL resolves, fetched title matches filed `source_title` exactly**
- **Fixture:** `source_url` resolves 200; fetched `<title>` byte-identical to
  `source_citations.source_title`.
- **Expected:** EXISTENCE axis passes for this citation.

**TC-657-EXIST-02 — URL resolves, fetched title differs from filed title (the S226 2203.09785
  pattern named in the issue)**
- **Fixture:** Filed title "Attention Is All You Need (v3)"; fetched title "Attention Is All
  You Need (v7, revised abstract)".
- **Expected:** EXISTENCE axis fails for this citation; violation names both the filed and
  fetched title strings explicitly (not just "title mismatch").

**TC-657-EXIST-03 — Filed title truncated at the 500-char column cap, fetched title longer**
- **Fixture:** `source_title` is exactly 500 chars (the varchar(500) cap) and is a true prefix
  of the real (longer) fetched title.
- **Expected:** Gate does NOT flag this as a mismatch — comparison logic must account for the
  known 500-char truncation (SE#843 step-2 note) by comparing up to `min(len(filed),
  len(fetched))` or an explicit prefix check, not byte-for-byte full-string equality, which
  would false-positive on every long title in the dataset.

**TC-657-EXIST-04 — Fetched title is a prefix-length match but content diverges after
  truncation point (adversarial: exploits EXIST-03's leniency)**
- **Fixture:** `source_title` truncated at 500 chars is a byte-identical prefix of a fetched
  title that continues "... (RETRACTED)" or "... (Expression of Concern)" beyond the 500-char
  mark.
- **Expected:** This is explicitly a case the title-prefix leniency from EXIST-03 must NOT
  paper over blindly — flagged as a WARN-tier existence finding (visible in the review table)
  even though it is not a hard title-string mismatch, since a retraction/correction notice
  past the truncation boundary is exactly the kind of fact a 500-char-capped title would hide.
  (This case exists because EXIST-03's necessary leniency creates exactly this blind spot;
  without EXIST-04 the suite would certify EXIST-03's fix without probing what it opens up —
  lesson 594/787/811 pattern.)

**TC-657-EXIST-05 — URL unreachable (connection refused)**
- **Fixture:** `source_url` points at a host returning connection-refused.
- **Expected:** Citation marked UNREAD (not "existence failed," not "existence passed") —
  distinct state per AC2's "network failure is reported as UNREAD, never silently coerced to
  pass." See NET group for the full retry/72h lifecycle on this state.

**TC-657-EXIST-06 — URL resolves with HTTP 404**
- **Fixture:** `source_url` returns 404.
- **Expected:** Treated as a genuine existence failure (the resource demonstrably does not
  exist at that URL), NOT as UNREAD — 404 is a definitive answer, unlike a 5xx/timeout which is
  ambiguous. This distinction matters for the 72h retry logic (NET group): a 404 should not be
  retried for 72h hoping it resolves, since a definitive "not found" will not change.

**TC-657-EXIST-07 — URL resolves with repeated HTTP 5xx**
- **Fixture:** `source_url` returns 503 on every attempt within the test's retry window.
- **Expected:** UNREAD (per AC2 and the issue's hard rule #5), eligible for the 72h retry
  lifecycle — distinct handling from EXIST-06's 404.

**TC-657-EXIST-08 — NULL `source_url`, citation type is not URL-based (e.g. `source_type='book'`)**
- **Fixture:** Citation with `source_type='book'`, `source_url` NULL, `source_title` populated.
- **Expected:** EXISTENCE axis is evaluated via a different mechanism than URL-resolution (title
  recorded, no fetch attempted) — NOT flagged as a failure or UNREAD purely for lacking a URL.
  Isolates a bug class where the existence check assumes every citation is URL-addressable.

**TC-657-EXIST-09 — `source_title` NULL or empty string, `source_url` present and resolves**
- **Fixture:** `source_title` is NULL on a citation whose `source_url` resolves fine.
- **Expected:** Flagged explicitly as "no filed title to compare against" (distinct state),
  not silently passed as "URL resolved, so existence is fine" — a citation with a resolvable
  URL but no filed title to check against the fetched one has only half-verified existence.

### Group CONF — Confidence Axis (9 cases)

**TC-657-CONF-01 — Confidence within plausible empirical range, scope note present**
- **Fixture:** `confidence=0.85`, finding content includes an explicit scope qualifier
  ("in the tested finite regime...").
- **Expected:** CONFIDENCE axis passes.

**TC-657-CONF-02 — Confidence=1.00 on a fact ABOUT a document (valid use)**
- **Fixture:** `confidence=1.00`, finding content: "arXiv:2607.12346 was published 2026-07-xx
  and authored by Krishan and Vishwanathan" (a verifiable bibliographic fact about the
  document, not a claim the document's content makes).
- **Expected:** CONFIDENCE axis passes. Requires the `claim_scope` signal (§6 OQ-1, RULED:
  `research_findings.metadata->>'claim_scope'`) to be present and classify this as a
  fact-about-the-document.

**TC-657-CONF-03 — Confidence=1.00 misapplied to a claim the document makes (the issue's named
  anti-pattern)**
- **Fixture:** `confidence=1.00`, finding content: "The paper proves an unconditional bound
  M_3(T) >= (34.1+o(1))c_3 T(log T)^9" (a claim the source asserts, not a fact about the
  source's existence/metadata).
- **Expected:** CONFIDENCE axis fails — this is TC-657-NEG-01's second injected violation
  (paired negative test, see NEG group) and must be named specifically in gate output, not
  folded into a generic "confidence issue."

**TC-657-CONF-04 — BVA: confidence=0.99 (just under the 1.00 restriction boundary)**
- **Fixture:** `confidence=0.99` on a claim-the-document-makes finding.
- **Expected:** Passes the 1.00-restriction check specifically (0.99 ≠ 1.00), independent of
  whether 0.99 itself is a sensible confidence for that claim — isolates the exact-equality
  boundary of the restriction from a broader "is this confidence reasonable" judgment, which
  this axis does not attempt to make outside the 1.00 special case.

**TC-657-CONF-05 — BVA: confidence=1.00 exactly, at the check-constraint ceiling**
- **Fixture:** `confidence=1.00`.
- **Expected:** Gate correctly treats this as in-scope for the 1.00-restriction rule (the
  check-constraint ceiling and the business-rule boundary coincide here, by design) — confirms
  the comparison is `== 1.00`, not an off-by-epsilon float comparison that could miss
  `1.00` represented as `0.9999999...` from some upstream numeric-type coercion.

**TC-657-CONF-06 — NULL confidence**
- **Fixture:** `research_findings.confidence` is NULL (column is nullable per live schema).
- **Expected:** Flagged as "unscored," a distinct state from both pass and fail — never
  silently treated as 0.00 (which the identity-element rule in D3 specifically guards against)
  and never silently treated as passing.

**TC-657-CONF-07 — Confidence present, `claim_scope` key missing entirely (RULED, I)ruid
  2026-11-12): advisory flag `scope_undeclared`, never gates**
- **Fixture:** `confidence=1.00`, `research_findings.metadata` has no `claim_scope` key at all
  (verified live at the pinned commit: 0 of 6313 existing `research_findings` rows carry this
  key today — every pre-existing row hits this exact case, not a hypothetical edge case).
- **Expected:** Review table shows an advisory `scope_undeclared` flag for this finding. Exit
  code is driven ONLY by the deterministic axes + Jev Support Noul score — `scope_undeclared`
  on its own never changes the exit code (confirms INV-3 extends to the missing-key case, not
  only to a present-but-mismatched value). The 1.00-restriction CONFIDENCE check still applies
  independently on its own terms (per CONF-02/03) and is not weakened or skipped merely because
  scope is undeclared — undeclared scope is a logging/advisory gap, not an excuse to waive the
  confidence rule itself.

**TC-657-CONF-07A — `claim_scope` key present but holds an invalid value (RULED, new case,
  BVA-style malformed-input coverage)**
- **Fixture:** Two sub-cases, each independently: `metadata->>'claim_scope' = "Proved "`
  (valid label with a case/whitespace variant, not one of the four exact enum strings
  `proved|computed|cited|conjecture`) and `metadata->>'claim_scope' = 42` (wrong JSON type —
  a number, not a string at all).
- **Expected:** Both sub-cases resolve to the SAME advisory `scope_undeclared` state as
  CONF-07 (an invalid value is treated as equivalent to an absent one, not as some third
  silently-passing state, and not as a crash) — never gates, per the same ruling. This closes
  the gap CONF-07 alone would leave: "key missing" and "key present but garbage" must not be
  handled by two different code paths that happen to agree today but could silently diverge
  later (the wrong-type-at-config-seam pattern named in the step-3 process requirement,
  SE#499 TC-522-028).

**TC-657-CONF-08 — Adversarial: `claim_scope='proved'` declared (valid enum value), but finding
  content is plainly a claim the document makes, not a fact about it (writer-declared scope
  contradicts content)**
- **Fixture:** `confidence=1.00`, `metadata->>'claim_scope'='proved'` (one of the four ruled
  enum values, correctly formed — this is NOT a CONF-07/07A malformed-key case), content: "The
  derivation proves an exact closed form for min ||P||_1(IP_t, eps)..." (a mathematical claim
  made by the document, not a bibliographic fact about the document itself, which is the
  distinction the 1.00-restriction cares about).
- **Expected:** Per the SE#1282 step-2 design, the Jev Scope Choice classifies scope
  independently of the writer's declaration; a mismatch between writer-declared and
  Jev-classified scope must escalate to skeptics (not silently trust the writer's label) —
  this is the test that would have caught the exact real-world incident the issue opens with
  (unsolved_problems id=3, where two fields of one row/session contradicted each other and the
  weaker-sourced half prevailed). Per I)ruid's 2026-11-12 ruling, Scope Choice itself never
  gates pass/fail directly — this test asserts the escalation-to-skeptics path fires, not that
  the gate exit code changes solely from the scope mismatch. Distinguished from CONF-07/07A: a
  present-and-valid-but-wrong value is a mismatch (SCOPE axis / escalation), while an
  absent-or-malformed value is `scope_undeclared` (advisory flag only) — these are two
  different states with two different handling paths, not the same failure mode.

**TC-657-CONF-09 — Out-of-range confidence bypassing the check constraint (adversarial: data
  that should be impossible per schema, test gate's defensive handling anyway)**
- **Fixture:** Attempt to construct a row with `confidence=1.5` — expected to be rejected by
  the live `research_findings_confidence_check` constraint at insert time (staging, via
  `scout`). Record the constraint rejection as the actual expected DB behavior.
- **Expected:** This confirms the DB layer itself is the enforcement point for in-range
  confidence (constraint rejects 1.5 outright), so the gate does not need its own redundant
  range check to stay fail-closed on this specific input class — but the gate's defensive code
  path for "confidence somehow out of `[0,1]`" (e.g. reached via a future schema change, a
  different write path, or a numeric-type edge case) is still exercised via a mocked/stubbed
  in-memory fixture bypassing the DB entirely (not a live DB row), asserting the gate does not
  crash or silently pass if it ever receives such a value from any source.

### Group TIER — Source Tier Axis (9 cases)

**TC-657-TIER-01 — Joint classification at the strong end: peer-reviewed, high reliability**
- **Fixture:** `source_type='paper'`, `reliability=0.93`.
- **Expected:** Classified as the strongest tier band; both fields read and reported together
  in the review table, not independently.

**TC-657-TIER-02 — Joint classification at the weak end: community-repo, low reliability**
- **Fixture:** `source_type='agent'` (closest live `source_type` enum value to a
  community/self-reported source per the live check constraint), `reliability=0.22`.
- **Expected:** Classified as the weakest tier band.

**TC-657-TIER-03 — Reconciliation conflict: `source_type` and `reliability` disagree (the
  two-fields-of-one-row contradiction this issue exists to fix, now inside the tier axis
  itself)**
- **Fixture:** `source_type='paper'` (suggesting strong tier) but `reliability=0.18` (suggesting
  weak tier) on the same citation row.
- **Expected:** Flagged explicitly as a tier-reconciliation conflict in the review table — not
  silently resolved by picking one field and ignoring the other, and not averaged into a
  misleading middle value. This is the direct structural analog of the `current_approach` vs.
  `progress_notes` contradiction named in the issue's own motivating example, now checked at
  the citation-tier level rather than only at the finding level.

**TC-657-TIER-04 — NULL `reliability`, `source_type` present**
- **Fixture:** `source_type='url'`, `reliability` NULL.
- **Expected:** Explicit "unscored" tier state, not a silent default to either the strongest or
  weakest band (per D3, no identity-element coercion of a missing score).

**TC-657-TIER-05 — BVA at tier-band boundaries**
- **Fixture:** Citations at `reliability=0.49`, `0.50`, `0.51` (or whatever exact band cutpoints
  the implementation defines — this test pins the behavior at the boundary regardless of the
  exact cutpoint value, by asserting the three fixtures land in at most two adjacent bands with
  a deterministic, documented tie-break at the exact cutpoint).
- **Expected:** No off-by-one/off-by-epsilon banding bug; the exact cutpoint value is
  classified consistently and the classification is documented (not an implicit side effect of
  float comparison order).

**TC-657-TIER-06 — The high-risk-cell substance, isolated as a standalone tier-axis assertion**
- **Fixture:** A single citation: weakest tier (per TIER-02's classification) AND the finding
  it cites has `importance='critical'`, `confidence=0.91`.
- **Expected:** The TIER axis's own output correctly classifies this citation's tier as weakest,
  independent of whether the separate high-risk-cell flag (RISK group) also fires — this test
  verifies tier classification is correct in isolation, not that the downstream flag logic
  works (that's RISK-01..05). Prevents a scenario where RISK's flag is correct only by
  coincidentally reading a wrong-but-compensating tier value.

**TC-657-TIER-07 — Mixed-tier citations on one finding reported independently, not
  averaged/collapsed**
- **Fixture:** One finding, two citations: citation A `reliability=0.90`, citation B
  `reliability=0.20`.
- **Expected:** Review table reports A and B's tiers separately; no "average tier=0.55" or
  "finding's overall tier" value is synthesized and presented as if it were a single citation's
  property. A finding's trustworthiness is the trustworthiness of its weakest load-bearing
  citation, not a mean.

**TC-657-TIER-08 — `is_current=false` interaction (ties to INV-5)**
- **Fixture:** A superseded finding (`is_current=false`) with a weak-tier citation that, if
  included, would trip the high-risk-cell rule for a different (current) finding sharing the
  same task.
- **Expected:** The superseded finding's weak-tier citation does not appear in tier output at
  all and does not spuriously trip the high-risk rule for the unrelated current finding —
  confirms the `is_current` filter is applied before tier classification, not after, where a
  late filter could still let a superseded row leak into an aggregate flag computed earlier in
  the pipeline.

**TC-657-TIER-09 — Schema-fidelity regression: no new tier column introduced (INV-6)**
- **Fixture:** None (live schema diff, staging).
- **Steps:** Diff `research_citations`'s column list, as implemented, against the live schema
  captured in this document's inputs (§ above).
- **Expected:** No new column (e.g. `tier`, `source_tier`, `tier_score`) added to
  `research_citations`. The gate computes tier at read time from `reliability` + `source_type`
  only. A violation here must fail review per SE#843 step-2 Correction 2, independent of
  whether the computed tier values themselves are correct.

### Group RISK — High-Risk Cell Flag (6 cases)

**TC-657-RISK-01 — Clean positive: weakest tier, most consequential claim, correctly flagged**
- **Fixture:** Finding `importance='critical'`, `confidence=0.88`, sole supporting citation at
  weakest tier (`reliability=0.15`, per TIER-02 banding).
- **Expected:** High-risk-cell flag fires, naming the specific finding and citation.

**TC-657-RISK-02 — Weakest tier but low-consequence claim (importance='low') — should NOT
  flag**
- **Fixture:** Finding `importance='low'`, `confidence=0.60`, citation at weakest tier.
- **Expected:** No high-risk flag — isolates "weakest tier alone" from "weakest tier × most
  consequential," confirming the flag requires the conjunction, not either condition alone.

**TC-657-RISK-03 — Strongest tier, most consequential claim — should NOT flag**
- **Fixture:** Finding `importance='critical'`, citation at strongest tier
  (`reliability=0.95`, `source_type='paper'`).
- **Expected:** No high-risk flag — the strong source adequately backs the critical claim; this
  is the "clean negative" the issue explicitly distinguishes from the flagged case ("the lone
  exception to a clean negative").

**TC-657-RISK-04 — Multiple citations on one finding, one weak one strong — flag keys off the
  weakest, not an average (ties to TIER-07)**
- **Fixture:** Finding `importance='critical'`, two citations: `reliability=0.95` and
  `reliability=0.15`.
- **Expected:** High-risk flag STILL fires (driven by the weak citation), even though a strong
  citation exists alongside it — confirms the rule is "does the weakest-tier source support
  this consequential claim" (per the issue's phrasing), not "is the finding adequately
  supported on average."

**TC-657-RISK-05 — BVA at the importance boundary: 'normal' vs. 'high' vs. 'critical', all
  paired with weakest tier**
- **Fixture:** Three findings, each with a weakest-tier citation, `importance` = 'normal',
  'high', 'critical' respectively.
- **Expected:** Confirms exactly where "most consequential" starts triggering the flag
  (implementation must document and the test must pin this threshold — e.g. 'high' and
  'critical' both flag, 'normal' does not, or only 'critical' flags) rather than leaving the
  importance-level cutoff undocumented and untested.

**TC-657-RISK-06 — Adversarial: finding content asserts its own low risk ("well-established,
  low-stakes claim") while `importance='critical'` in the DB (verdict-wording leakage into
  content vs. structured field disagreement)**
- **Fixture:** `importance='critical'`, content text includes a hedge phrase suggesting low
  consequence.
- **Expected:** The structured `importance` field drives the flag, not free-text content
  parsing — confirms the gate does not (and per D2/the issue's own determinism premise, must
  not) attempt NLP inference over finding content to second-guess the structured field. Also
  guards against the specific leakage pattern Gidget's own v3 calibration flagged (16/62
  source texts containing auditor verdict wording) recurring here in a different form: a
  gate that reads consequence signals out of free text is exactly as fragile as a Jev prompt
  leaking ground-truth wording.

### Group NET — Unreachable ⇒ UNREAD / 72h Lifecycle (7 cases)

**TC-657-NET-01 — First unreachability: source blocks and is scheduled for retry (not yet
  dropped)**
- **Fixture:** `source_url` returns connection-timeout on first collector attempt;
  `accessed_at` timestamp set to "now" at the top of the test.
- **Expected:** UNREAD state, retry scheduled for next session; gate does not treat this as a
  terminal failure or drop the citation yet.

**TC-657-NET-02 — Retried every session while within the 72h window**
- **Fixture:** Simulated sequence of 3 sessions, each 20h apart (total 60h elapsed), source
  unreachable every time.
- **Expected:** UNREAD persists across all 3 sessions; citation/finding is retried each time,
  not dropped, not silently escalated past the UNREAD state early.

**TC-657-NET-03 — BVA: exactly at the 72h boundary (non-identity clock fixture) — RULED:
  window is [0, 72h), elapsed >= 72h is dropped**
- **Fixture:** Two straddling fixtures, per D3 (non-identity clock values, not round numbers
  coinciding with a session boundary by coincidence): first-unreachable timestamp at
  `now() - 71h 59m 58s` (elapsed just under 72h) and `now() - 72h 00m 02s` (elapsed just over
  72h).
- **Expected:** Per the pinned ruling, the window is half-open `[0, 72h)`: elapsed `< 72h`
  (the `71h 59m 58s` fixture) is still-within-window — UNREAD, retried, blocks (exit 1), NOT
  yet dropped. Elapsed `>= 72h` (the `72h 00m 02s` fixture) is past-window — the citation is
  dropped and the finding is re-evaluated on its remaining citations per NET-04. An
  elapsed-exactly-72h-to-the-second fixture (not just the two straddling points) is also
  included in this test's fixture set and must land on the dropped side, confirming `>=` is
  the actual comparison operator implemented, not `>`.

**TC-657-NET-04 — Past 72h: source dropped, argument re-formed**
- **Fixture:** First-unreachable timestamp `now() - 80h`, still unreachable.
- **Expected:** Citation is dropped from the live argument for this finding; the finding's
  supporting-citation set is re-formed without it (not simply omitted from display while still
  silently counted elsewhere), and the skeptics re-run against the reduced citation set per
  the SE#1282 design.

**TC-657-NET-05 — Source recovers mid-window (becomes reachable at hour 40 of a 72h clock)**
- **Fixture:** Unreachable hours 0-40, reachable (200, title matches) from hour 40 onward, gate
  invoked at hour 45.
- **Expected:** Citation returns to normal EXISTENCE-axis evaluation (no longer UNREAD, no
  lingering "was once unreachable" penalty); the 72h clock for this citation is cleared, not
  merely paused — a later, unrelated future unreachability starts a fresh 72h window rather
  than resuming a stale partially-elapsed one.

**TC-657-NET-06 — Adversarial: `accessed_at` is NOT evidence of a successful fetch (the
  issue's own named fail-closed rule, AC2/hard-rule-5)**
- **Fixture:** Citation with `accessed_at` = recent timestamp (column default `now()`, NOT
  NULL) but the source has in fact never successfully resolved per the collector's own
  snapshot log — i.e., `accessed_at` reflects "we touched it," not "we verified it," exactly
  the distinction SE#843 step-2 confirmed as schema-correct.
- **Expected:** Gate does not read a recent `accessed_at` as proof of successful verification;
  UNREAD/retry state is driven by the collector's actual fetch-success record, never by
  `accessed_at` alone. This is a direct regression test for the exact misreading the schema
  review warned against.

**TC-657-NET-07 — Config→runtime seam: 72h window value is read from config, not hardcoded**
- **Fixture:** A test harness that overrides the configured drop-window value (e.g. to 24h via
  whatever config mechanism the implementation uses — env var, DB row, config file) and
  verifies a source unreachable for 30h is dropped under the 24h override but would NOT have
  been dropped under the standard 72h default.
- **Expected:** Changing the config value changes observed drop behavior, proving the 72h
  figure is a single live, read config value feeding the runtime comparison — not a value
  copy-pasted into multiple places in the implementation that could drift out of sync (the
  config→runtime seam required by the step-3 process description, tested here against
  production-shaped config-loading code, not a hand-constructed stub of the comparison logic
  alone).

### Group JEV-THRESH — Jev Support Noul Threshold Boundaries (7 cases)

**TC-657-JEV-01 — BVA: p_supports = 0.049 (just below 0.05 gate threshold)**
- **Fixture:** Mocked `/v1/systemone` response, `confidence`-and-answer payload yielding
  `p_supports=0.049` for a given (claim, source) pair.
- **Expected:** Escalates to skeptics (below threshold, per I)ruid's 2026-11-12 decision that
  Jev Support gates at 0.05).

**TC-657-JEV-02 — BVA: p_supports = 0.05 exactly (the threshold value itself) — RULED**
- **Fixture:** Mocked response, `p_supports=0.05`.
- **Expected:** Per the Project Leadership ruling pinning the tie-break direction: `p_supports
  <= 0.05` escalates (blocks). At exactly 0.05, the finding escalates to skeptics and the
  finding is blocked (contributes to exit code 1), same as JEV-01's 0.049 case. This is a hard
  pinned boundary, not an implementer's choice — a future change to `< 0.05` (excluding the
  exact boundary) would be a silent regression against this test, not a legitimate reading.

**TC-657-JEV-03 — BVA: p_supports = 0.051 (just above threshold)**
- **Fixture:** Mocked response, `p_supports=0.051`.
- **Expected:** Does not escalate on threshold grounds alone (passes the Support check) —
  confirmed independently of the separate uncertainty-zone rule in JEV-05/06 below, since 0.051
  is also below the [0.4, 0.6] uncertainty band and must not be conflated with it.

**TC-657-JEV-04 — Non-identity mid-range value, clearly-supported**
- **Fixture:** `p_supports=0.93`.
- **Expected:** Passes cleanly, no escalation.

**TC-657-JEV-05 — Uncertainty zone lower boundary: p_supports = 0.40**
- **Fixture:** `p_supports=0.40`.
- **Expected:** Escalates per the SE#1282 design's explicit rule ("A Noul score in [0.4, 0.6]
  always escalates and is never averaged") — this is a SEPARATE escalation trigger from the
  0.05 cutoff and must fire even though 0.40 is well above 0.05.

**TC-657-JEV-06 — Uncertainty zone upper boundary: p_supports = 0.60**
- **Fixture:** `p_supports=0.60`.
- **Expected:** Escalates (inclusive upper boundary of the stated [0.4, 0.6] zone). BVA pair
  with JEV-07 (0.61) to confirm the zone's exact edges.

**TC-657-JEV-07 — BVA: p_supports = 0.61 (just outside the uncertainty zone, above it)**
- **Fixture:** `p_supports=0.61`.
- **Expected:** Does not escalate via the uncertainty-zone rule (outside [0.4, 0.6]); passes
  cleanly absent any other violation.

### Group JEV-ERR — Jev API Errors / Malformed Responses (7 cases)

**TC-657-JEVERR-01 — Missing `p_supports` field in an otherwise well-formed response**
- **Fixture:** Mocked response JSON with no `p_supports`/equivalent key at all.
- **Expected:** Fail-closed: escalate to skeptics (never defaults to a pass or to a numeric
  0.0/1.0 that happens to be computed from an absent field via some default-coercion path).

**TC-657-JEVERR-02 — `p_supports` is NaN**
- **Fixture:** Mocked response with a NaN-equivalent value (however the API/parsing layer could
  plausibly produce one — e.g. a division-by-zero artifact in a hypothetical derived-confidence
  computation, or a literal `"NaN"` string in JSON parsed into a float).
- **Expected:** Fail-closed escalation; any NaN comparison against the 0.05/[0.4,0.6] thresholds
  must not silently evaluate as "less than" or "greater than" in a way that accidentally routes
  to a pass (a known footgun: NaN comparisons are false in both directions in IEEE 754, which
  can make a naive `if p > 0.6: pass` silently skip the escalation branch too).

**TC-657-JEVERR-03 — `p_supports` out of `[0,1]` range (e.g. 1.4 or -0.2)**
- **Fixture:** Two sub-cases: `p_supports=1.4`, `p_supports=-0.2`.
- **Expected:** Both fail-closed (escalate / flag as a malformed-response contract violation),
  never clamped silently to 0 or 1 and then evaluated as if that were the genuine score.

**TC-657-JEVERR-04 — HTTP timeout calling `/v1/systemone` — RULED: 3 attempts total,
  exponential backoff (1s, 2s), then per-citation fail-closed**
- **Fixture:** Mocked network layer that times out on all 3 attempts.
- **Expected:** Exactly 3 attempts total (the original call plus 2 retries), with the mocked
  clock/sleep calls showing backoff delays of 1s then 2s between attempts (not a 4th attempt,
  not an immediate single-shot failure). After the 3rd timeout, treated as an OQ-4-class
  per-citation failure (TC-657-JEVERR-04 continues below at JEVERR-04A) — distinct from, and
  not to be confused with, the collector's separate 72h source-unreachability retry lifecycle
  (NET group) — these are two different retry budgets on two different resources.

**TC-657-JEVERR-04A — Timeout retry succeeds on attempt 2 or 3 (the retry's actual payoff case)**
- **Fixture:** Mocked network layer times out on attempt 1, succeeds with a clean
  `p_supports=0.82` response on attempt 2.
- **Expected:** The citation is evaluated normally using the attempt-2 response — a transient
  failure that resolves within the retry budget must not be treated as a permanent failure or
  leave any residual "degraded" marker on an otherwise-successful judgment. Confirms the retry
  logic's purpose (recovering from genuine transients) is actually exercised, not only its
  exhaustion path (JEVERR-04).

**TC-657-JEVERR-05 — HTTP 5xx from `/v1/systemone` — RULED: same 3-attempt/backoff retry as
  timeout, then per-citation fail-closed**
- **Fixture:** Mocked 503 response on all 3 attempts.
- **Expected:** Same retry contract as JEVERR-04: 3 attempts total, 1s/2s backoff, then
  OQ-4-class per-citation failure. Fail-closed, distinct handling from a
  successful-but-out-of-range response (JEVERR-03) — a 5xx means Jev never actually rendered a
  judgment at all, which should be reported differently in the review table than "Jev judged
  and the judgment was malformed."

**TC-657-JEVERR-05A — HTTP 429 honors `Retry-After` header instead of the default backoff**
- **Fixture:** Mocked 429 response on attempt 1 with `Retry-After: 5`, then a clean response on
  attempt 2.
- **Expected:** The retry waits 5s (the header value), not the default 1s backoff — confirms
  `Retry-After` overrides the standard exponential schedule specifically for 429, per the
  ruling. If no `Retry-After` header is present on a 429, falls back to the standard 1s/2s
  schedule (a second sub-case within this test, not a separate TC number, since it is the same
  code path's fallback branch).

**TC-657-JEVERR-05B — Non-429 4xx response and malformed-but-200 body are NEVER retried
  (negative retry-policy test)**
- **Fixture:** Two sub-cases: (a) mocked 400 response; (b) mocked HTTP 200 with a malformed/
  non-JSON body (same payload as JEVERR-06).
- **Expected:** Exactly 1 attempt in both sub-cases — no retry at all, immediate per-citation
  fail-closed treatment. This is the explicit negative case proving the retry budget is scoped
  only to transient conditions (timeout, 5xx, 429) and does NOT blindly retry every failure
  class, which would both waste the trivial-spend budget and mask a genuinely non-transient
  contract violation (a malformed body is a bug, not a blip, and retrying it 3 times would not
  fix it).

**TC-657-JEVERR-06 — HTTP 200 with malformed/non-JSON body**
- **Fixture:** Mocked response, HTTP 200, body is not valid JSON (or is JSON but missing the
  expected top-level shape entirely — e.g. an empty object `{}`).
- **Expected:** Fail-closed; per the pinned OQ-4 ruling (§6: per-citation fail-closed), parse
  failure must NOT propagate as an unhandled exception that crashes the whole gate run — this
  specific citation is marked unverified and its finding blocked, while other findings in the
  same task are evaluated normally (same per-citation contract as JEVERR-01..05/05A/05B),
  unless the systemic all-Jev-calls-failed condition (GATE-02A) also applies to this run.

**TC-657-JEVERR-07 — Compound (non-atomic) claim accidentally sent to a single Noul call
  (INV-7 violation check)**
- **Fixture:** A finding whose content is a compound claim with two independent assertions
  joined by "and"/"which also" (mirroring the real PNP_03-style compound claims in the v3
  calibration set).
- **Expected:** The gate's atomic-split step (per the SE#1282 design) must have split this
  before any Noul call; this test asserts the pre-Jev pipeline stage rejects/splits a
  still-compound claim rather than silently sending it to Jev as one unit and trusting a single
  score to cover both assertions — a design-level regression guard for INV-7, independent of
  how well Jev itself would score a compound claim if sent one.

### Group SCOPE — Scope Choice Advisory-Only (5 cases)

**TC-657-SCOPE-01 — Scope mismatch (writer vs. Jev-classified) on a low-stakes finding does NOT
  change the gate exit code**
- **Fixture:** `claim_scope='proved'` (writer-declared), mocked Jev Choice response
  classifies 'conjecture'; finding `importance='low'`, confidence/tier otherwise clean.
- **Expected:** Gate exit code reflects only the deterministic axes + Jev Support score (both
  clean here) — the scope mismatch is logged/visible in the review table but does NOT flip
  the exit code to non-zero on its own, per I)ruid's 2026-11-12 ruling that Scope Choice is
  advisory-only and never gates (INV-3).

**TC-657-SCOPE-02 — Scope mismatch triggers skeptic escalation even though it never gates**
  (distinguishing "advisory, logged" from "advisory, ignored")**
- **Fixture:** Same as SCOPE-01's mismatch.
- **Expected:** Per the SE#1282 design text ("a mismatch or low confidence escalates to the
  fresh-context skeptics"), the mismatch still triggers skeptic review as a side channel —
  "advisory-only" means it does not independently flip the exit code, NOT that it is inert.
  This test exists specifically because those two readings ("advisory=logged-but-acted-on" vs.
  "advisory=cosmetic") are easy to conflate in implementation; both SCOPE-01 and SCOPE-02 must
  pass together to prove the correct reading was implemented.

**TC-657-SCOPE-03 — Scope agreement (writer and Jev agree) — no escalation from scope**
- **Fixture:** `claim_scope='computed'` (writer), Jev Choice also classifies 'computed'.
- **Expected:** No scope-driven escalation; confirms the mismatch-triggers-escalation rule in
  SCOPE-02 is conditioned on actual disagreement, not on the mere presence of a Scope Choice
  call.

**TC-657-SCOPE-04 — Scope Choice call itself errors/times out — does not block the gate**
- **Fixture:** Mocked Scope Choice API error (same error shapes as JEVERR-04/05/06, including
  the ruled 3-attempt retry with backoff on timeout/5xx/429, but on the Choice endpoint rather
  than the Noul endpoint).
- **Expected:** Per advisory-only status, a failed Scope Choice call must not fail-closed the
  entire gate the way a failed Support Noul call does (JEVERR group) — it is logged as
  "scope unavailable" and the gate proceeds on the deterministic axes + Support score alone.
  This is the one place in the design where "advisory" legitimately means "can be silently
  degraded," in deliberate contrast to every Support-Noul error case above, and the test
  exists to make that asymmetry explicit and intentional rather than an accidental
  inconsistency in error handling across the two Jev call types.

**TC-657-SCOPE-05 — Scope Choice low-confidence-but-matching (calibration-grounded edge case)**
- **Fixture:** Writer declares 'proved', Jev Choice also returns 'proved' but with a low
  internal confidence score (per the v3 calibration's own finding that scope accuracy is only
  43.5% against an 87.1% majority baseline — this fixture represents the realistic case where
  Jev's agreement might be a near-coin-flip rather than a confident match).
- **Expected:** Per the SE#1282 design text ("a mismatch OR low confidence escalates"), a
  low-confidence agreement still triggers skeptic escalation even without a label mismatch —
  tests that "low confidence" and "mismatch" are two independently-sufficient escalation
  triggers, not that only a label mismatch matters.

### Group OUT — Output / Review Table (5 cases)

**TC-657-OUT-01 — Human-readable table includes all three axes per citation**
- **Fixture:** A finding with 2 citations, clean on all axes.
- **Expected:** Table shows, per citation: EXISTENCE result, CONFIDENCE result (at the
  finding level, since confidence is a `research_findings` column), SOURCE TIER result — not
  just a pass/fail summary line.

**TC-657-OUT-02 — Named violations are specific, not generic**
- **Fixture:** Reuse NEG-01's two independently-injected violations.
- **Expected:** Output text names which finding/citation and which axis failed and why (e.g.
  "Citation #4021 (finding #3310): title mismatch — filed 'X', fetched 'Y'"), not a bare
  "1 violation found" or "FAIL."

**TC-657-OUT-03 — Table correctly reports a finding with NO violations as clean, not silent**
- **Fixture:** All-clean fixture (the GATE-03 control fixture, below).
- **Expected:** Clean findings appear in the table explicitly marked clean/passed — a reviewer
  reading the table must be able to distinguish "checked and clean" from "not checked"/omitted,
  which matters directly for AC6's "NOVA must clear before synthesis" requirement — an omitted
  row looks identical to an unchecked row unless clean status is explicit.

**TC-657-OUT-04 — Scope Choice output appears but is visually/structurally distinguished from
  gating axes**
- **Fixture:** SCOPE-01's mismatch fixture.
- **Expected:** The review table shows the scope mismatch, but its presentation makes clear
  (e.g. a separate "advisory" column/section, not interleaved indistinguishably with the three
  gating axes) that this does not affect pass/fail — supports INV-3 being legible to a human
  reviewer, not just correct in the exit code.

**TC-657-OUT-05 — High-risk-cell flag is visually prominent, not buried in per-citation detail**
- **Fixture:** RISK-01's positive fixture.
- **Expected:** The flag appears as its own clearly marked section/line in the table (per AC5's
  "flagged explicitly"), not only inferable by a reviewer manually cross-referencing tier and
  importance columns across rows.

### Group GATE — Exit-Code Contract / CLI (6 cases)

**TC-657-GATE-01 — Exit code 0 on an all-clean fixture (paired with GATE-03 as the control) —
  RULED taxonomy: 0 = all findings pass**
- **Fixture:** Same as OUT-03/GATE-03's clean fixture.
- **Expected:** Exit code exactly `0`.

**TC-657-GATE-02 — RULED taxonomy: only THREE exit codes exist (0/1/2); violation-class detail
  lives in the review table's named-violation text, not in a proliferation of exit codes**
- **Fixture:** Five separate single-violation fixtures: existence mismatch (EXIST-02), confidence
  misapplication (CONF-03), tier-reconciliation conflict (TIER-03), Jev-support escalation
  (JEV-01), and UNREAD-within-window (GATE-06).
- **Expected:** All five produce exit code exactly `1` (one or more findings blocked) — the
  pinned taxonomy is deliberately coarse (0/1/2), NOT one distinct integer per violation class.
  This corrects this test's own original premise (which had assumed the taxonomy would assign
  a distinct code per class) — the actual requirement is that each fixture's NAMED violation in
  the review table is distinct and specific (already covered by OUT-02/NEG-01..04), while the
  exit code itself collapses correctly to `1` in every one of these five cases. A sixth
  sub-case — the non-existent-`task_id` fixture (DB-05) — is included here specifically to
  confirm it produces `2`, not `1`, proving the gate correctly distinguishes "a finding was
  evaluated and blocked" from "no finding was evaluated because the gate itself could not run."

**TC-657-GATE-02A — Exit code 2: systemic failure when EVERY Jev call in a run fails (RULED,
  OQ-4 resolution, new case)**
- **Fixture:** A task with 3 findings/citations, ALL of which hit Jev-layer failures that
  exhaust their ruled retry budget (3 attempts, 1s/2s backoff) — mix of JEVERR-04-style
  exhausted timeouts and JEVERR-05-style exhausted 5xxs across all three findings, not a single
  shared mock failure, to prove the systemic detection isn't an artifact of one specific mocked
  error object.
- **Expected:** Exit code `2` (gate could not run), not `1` — per the ruling's explicit
  "if EVERY Jev call in a run fails, exit 2 (systemic: the gate couldn't run)" clause. This is
  distinct from GATE-02's per-finding-blocked fixtures: a gate that attempted evaluation and
  found real problems is a `1`; a gate whose underlying judgment mechanism never worked at all
  for the entire run is a `2`, since in that case nothing was actually verified, as opposed to
  verified-and-found-wanting.

**TC-657-GATE-02B — BVA: all-but-one Jev calls fail — remains exit 1, NOT exit 2 (boundary
  between GATE-02A's systemic case and the ordinary per-finding-blocked case)**
- **Fixture:** Same 3-finding task as GATE-02A, but only 2 of 3 Jev calls exhaust retries; the
  3rd succeeds cleanly.
- **Expected:** Exit code `1` (the 2 failed-Jev findings are individually blocked per OQ-4's
  per-citation fail-closed rule; the gate itself clearly ran, since one finding was fully and
  successfully evaluated) — proves "systemic" in GATE-02A means ALL, not MOST, and that the
  2-of-3 boundary does not accidentally trip the rarer, more severe exit-2 path.

**TC-657-GATE-03 — Clean-fixture control run, paired with NEG-01 in the same test pass (AC7
  proof structure, carried forward from the original SE#843 design)**
- **Fixture:** All-clean fixture, run in the same invocation/test session as NEG-01.
- **Expected:** Exit code 0, zero violations reported — proves the gate does not always-fail,
  which is the necessary complement to NEG-01's "proves it can fail." Neither test alone
  proves the gate is a real gate; both together do.

**TC-657-GATE-04 — CLI invocation contract: missing/malformed `task_id` argument — RULED:
  exit 2 (usage error, same code class as DB-05's not-found case)**
- **Fixture:** Invoke with no `task_id`, then with `task_id='abc'` (non-integer).
- **Expected:** Clear usage error message, exit code exactly `2` in both sub-cases — same code
  as DB-05 (both are "gate could not run" conditions), distinguished from each other only by
  message text (argument-parsing failure vs. DB lookup miss), not by a different integer — per
  the ruled taxonomy's coarse three-value design.

**TC-657-GATE-05 — Idempotent/deterministic repeat invocation (INV-4)**
- **Fixture:** NEG-01's fixture, invoked 3 times in sequence with no DB or mock changes between
  runs.
- **Expected:** Identical exit code (`1`, per NEG-01's known-bad fixture) and identical set of
  named violations across all 3 runs.

**TC-657-GATE-06 — UNREAD-only result, within the 72h window — RULED: BLOCKING, exit 1**
- **Fixture:** A finding with one clean citation and one UNREAD citation (unreachable source,
  elapsed `< 72h` per NET-03's pinned window), no other violations.
- **Expected:** Per I)ruid's ruling, UNREAD within the window is gate-BLOCKING, not advisory:
  exit code 1 (one or more findings blocked), naming the specific UNREAD citation and the
  finding it blocks, retried on the next session per NET-01/02. Distinct from GATE-06A (below),
  which covers the same finding once its UNREAD citation ages past the 72h window.

**TC-657-GATE-06A — UNREAD result PAST the 72h window: citation dropped, finding re-evaluated
  on remaining citations (RULED, new case)**
- **Fixture A (citation dropped, finding still supported):** Same finding as GATE-06, but the
  UNREAD citation's elapsed time is now `>= 72h` (per NET-03/NET-04's pinned boundary), AND the
  finding has a second, clean, currently-reachable citation that independently supports it.
- **Expected A:** The stale citation is dropped from the finding's argument (does not appear as
  an active citation in the review table, though its drop is logged/auditable); the finding is
  re-evaluated on its one remaining citation; if that remaining citation is clean, the finding
  passes (contributes to exit 0, assuming nothing else in the task fails) — this is the key
  behavior GATE-06 and GATE-06A together must distinguish: the SAME originating UNREAD event
  produces exit 1 before 72h and can produce exit 0 after 72h, if and only if another citation
  still supports the finding.
- **Fixture B (citation dropped, finding left with no supporting citation):** Same as Fixture A,
  except the dropped citation was the finding's ONLY citation (no remaining citation after the
  drop).
- **Expected B:** Per the ruling's explicit "no remaining supporting citation → blocked" clause,
  the finding is blocked — exit code 1, naming the finding and explaining it has zero
  surviving citations post-drop (distinct violation text from GATE-06's "UNREAD, still
  retrying" message — this is "dropped and now unsupported," not "still waiting").

### Group NEG — Negative / Failure Tests (AC7) (4 cases)

**TC-657-NEG-01 — Primary AC7 proof: two independently-injected known-bad citations, both must
  be named**
- **Fixture:** One fixture task with: (a) a title-mismatch citation (per EXIST-02), and (b) a
  confidence=1.00-misapplied-to-a-claim finding (per CONF-03) — independently injected,
  unrelated to each other, on different findings within the same task.
- **Expected:** Gate exits non-zero, naming BOTH specific violations by finding/citation id and
  axis — and critically, does NOT misreport any OTHER (clean) fixture rows in the same task as
  violating. Must be run paired with GATE-03's clean-fixture control in the same test pass, so
  an always-fail gate script cannot trivially "pass" this test for the wrong reason (carried
  forward verbatim from the SE#843 step-3 design, which was explicitly reviewed and accepted
  on this structural point).

**TC-657-NEG-02 — Isolate EXISTENCE axis failure independently (no other axis contributes)**
- **Fixture:** Only a title mismatch; confidence and tier otherwise clean across the whole
  fixture task.
- **Expected:** Exactly one violation named (the title mismatch); confirms EXISTENCE's failure
  logic is not a silent no-op that happens to be masked by another axis's independent failure
  in NEG-01's combined fixture.

**TC-657-NEG-03 — Isolate CONFIDENCE axis failure independently**
- **Fixture:** Only the confidence=1.00-misapplied pattern; existence and tier otherwise clean.
- **Expected:** Exactly one violation named (the confidence misapplication).

**TC-657-NEG-04 — Isolate SOURCE TIER axis failure independently (tier-reconciliation conflict,
  per TIER-03)**
- **Fixture:** Only a `source_type`/`reliability` disagreement; existence and confidence
  otherwise clean.
- **Expected:** Exactly one violation named (the tier conflict) — completes the per-axis
  isolation set alongside NEG-02/NEG-03, so no single axis's failure detection can be a silent
  no-op masked by either of the other two in a combined run.

### Group WIRE — Workflow 32 Wiring (6 cases)

**TC-657-WIRE-01 — Gate runs before `progress_notes` is written in step 3**
- **Fixture:** Instrumented/traced execution of workflow 32 step 3 against a fixture task.
- **Expected:** Gate invocation occurs, and its output is available, before the step-3
  `UPDATE unsolved_problems SET ... progress_notes = ...` statement executes — satisfies AC8's
  "cannot be skipped by forgetting," since the gate sits structurally before the write, not
  merely documented as a prerequisite step a human/agent could skip.

**TC-657-WIRE-02 — Gate failure actually blocks progression to the `progress_notes` write (not
  just advisory-logged at this wiring point)**
- **Fixture:** NEG-01's known-bad fixture, wired into a workflow-32-step-3 dry run.
- **Expected:** The workflow step does not reach/execute the `progress_notes` write when the
  gate exits non-zero on a hard-violation code — a gate that runs but whose failure is only
  logged, with the workflow proceeding regardless, would not satisfy "cannot be skipped by
  forgetting" in any meaningful sense, since forgetting to check the log is exactly the
  original failure mode (lesson-1221-class, per the issue's motivation).

**TC-657-WIRE-03 — Gate applies to the correct `task_id` for the problem/session actually being
  worked (no cross-problem task_id confusion)**
- **Fixture:** Two unsolved-problems rows, each with their own research project/task chain,
  worked in adjacent sessions.
- **Expected:** Step 3's gate invocation resolves `task_id` correctly for whichever problem is
  the active session subject — guards against a wiring bug where a stale/cached task_id from a
  prior session leaks into the current one's gate check.

**TC-657-WIRE-04 — MONITOR-mode sessions with no new findings do not spuriously fail the gate**
- **Fixture:** A MONITOR session that added zero new findings this session (all findings
  pre-existing and already previously gated clean).
- **Expected:** Gate re-runs (or is skippable only by an explicit, documented "no new findings
  this session" condition — implementer's choice, but it must be a deliberate branch, not an
  accidental one) without producing a spurious failure purely from re-checking
  already-clean data.

**TC-657-WIRE-05 — Gate output is surfaced to the human-review-gate step (step 4) when relevant**
- **Fixture:** A session that both trips the gate AND produces ENGAGE/DOCUMENT external-facing
  output in the same session.
- **Expected:** The gate's flagged violations are visible to whatever reviews the step-4 human
  gate content, not siloed only in step 3's own log — a critical-tier gate violation on a
  finding that then feeds an ENGAGE draft must not be invisible to the human reviewing that
  draft.

**TC-657-WIRE-06 — 72h-window config value resolves identically whether invoked from workflow
  32's step 3 or run standalone (config→runtime seam, wiring-level check, complements NET-07)**
- **Fixture:** Same config override as NET-07, invoked once standalone and once through the
  workflow-32 step-3 wiring path.
- **Expected:** Both invocation paths read the same config value and produce the same drop/
  no-drop decision for an identical source-unreachability fixture — confirms the workflow
  wiring does not accidentally pass a different/stale/hardcoded window value than the
  standalone gate CLI would use.

### Group CONFIG — Config→Runtime Seam (3 cases)

**TC-657-CONFIG-01 — Jev threshold (0.05) is a single named config value, not hardcoded in
  multiple call sites**
- **Fixture:** Override the configured Support-Noul threshold (e.g. to 0.10 via whatever config
  mechanism the implementation uses) and re-run JEV-01's 0.049 fixture.
- **Expected:** Under the 0.10 override, a p_supports=0.049 fixture still escalates (0.049 <
  0.10, consistent regardless of the exact override value), AND a fixture at p_supports=0.07
  (which would NOT escalate under the real 0.05 threshold but WOULD under a 0.10 override)
  changes behavior correctly under the override — proves the threshold is live-read config,
  not a value baked into comparison logic that an override variable fails to actually reach.

**TC-657-CONFIG-02 — Recalibration readiness: threshold value is documented as provisional and
  re-settable without code changes**
- **Fixture:** None (static/process check).
- **Expected:** Per the v3 calibration report's own stated caveat ("recalibrate on collector
  output before the threshold is final... grow the set to 150+"), confirm the 0.05 value lives
  in a config location that can be updated by a future recalibration pass without touching gate
  logic code — a config file, DB row, or env var, not a numeric literal in the Jev-call or
  aggregation source.

**TC-657-CONFIG-03 — Production-populated config, not hand-constructed test stub (the seam
  itself, not just its mechanism)**
- **Fixture:** Whatever actual production code path sets the 72h window and 0.05 threshold at
  runtime (e.g. a config-loader module, a settings table read) is exercised directly — not a
  test-only stub that bypasses the real loading code and asserts against a hand-set variable.
- **Expected:** The real config-loading code path is exercised at least once in the suite,
  satisfying the step-3 process requirement for "at least one test exercising the
  config→runtime seam where input metadata is actually populated by production code" (lesson
  811 pattern) — complements CONFIG-01/02, which may use simpler stubs for the BVA-style
  override testing.

---

## 4. Test Count Summary (Rev 2 — rulings pinned, SE#1282 step 4)

**Revision note:** Rev 1 (90 cases) is superseded in place (no v2 file created, per the
TEST-CASE FILE DISPOSITION convention). Project Leadership's step-4 rulings (2026-11-12)
resolved OQ-1 through OQ-5 plus the two implementer-discretion boundaries (JEV-02, NET-03).
Seven net-new test cases were added where a ruling exposed a sub-case that didn't previously
need its own ID (CONF-07A, JEVERR-04A, JEVERR-05A, JEVERR-05B, GATE-02A, GATE-02B, GATE-06A).
No case was deleted; several were reworded in place to replace "either ruling"/"pending"
language with the pinned behavior.

| Area | Group | Count (Rev 1) | Count (Rev 2) |
|---|---|---|---|
| DB Query / Join Correctness & Read-Only Contract | DB | 7 | 7 |
| EXISTENCE axis | EXIST | 9 | 9 |
| CONFIDENCE axis | CONF | 9 | 10 (+1: CONF-07A) |
| SOURCE TIER axis | TIER | 9 | 9 |
| High-Risk Cell Flag | RISK | 6 | 6 |
| Unreachable ⇒ UNREAD / 72h Lifecycle | NET | 7 | 7 |
| Jev Support Noul Threshold Boundaries | JEV-THRESH | 7 | 7 |
| Jev API Errors / Malformed Responses | JEV-ERR | 7 | 10 (+3: JEVERR-04A/05A/05B) |
| Scope Choice Advisory-Only | SCOPE | 5 | 5 |
| Output / Review Table | OUT | 5 | 5 |
| Gate Contract (exit codes / CLI) | GATE | 6 | 9 (+3: GATE-02A/02B/06A) |
| Negative/Failure Tests (AC7) | NEG | 4 | 4 |
| Workflow 32 Wiring | WIRE | 6 | 6 |
| Config→Runtime Seam | CONFIG | 3 | 3 |
| **Total** | | **90** | **97 (+7)** |

---

## 5. Adversarial / Malformed-Input Coverage Index

Per the workflow-4 step-3 process requirement (lessons 594/787/811; SE#499 TC-522-028), the
following test cases specifically exercise malformed, adversarial, or wrong-type inputs rather
than spec-conformant fixtures:

- **Wrong-type/malformed values at seams:** JEVERR-01/02/03/06 (missing/NaN/out-of-range/
  non-JSON Jev responses), CONF-07A (invalid `claim_scope` value: wrong case/whitespace AND
  wrong JSON type), CONF-09 (out-of-range confidence bypassing the DB constraint), EXIST-08/09
  (NULL fields at the existence seam).
- **Verdict-wording / content leakage into structured decisions:** RISK-06 (content hedge vs.
  structured `importance`), CONF-08 (writer-declared scope vs. content vs. Jev scope).
- **Fragment/compound-input adversarial cases:** JEVERR-07 (compound claim reaching Noul
  unsplit).
- **Title/string adversarial cases exploiting a necessary leniency:** EXIST-03/EXIST-04 (the
  500-char truncation leniency and the retraction-notice-past-truncation exploit of it).
- **Retry-policy negative case (new, Rev 2):** JEVERR-05B (non-429 4xx and malformed-200-body
  must NEVER be retried — proves the retry budget doesn't blindly apply to every failure
  class).
- **Config→runtime seam:** NET-07, WIRE-06, CONFIG-01/02/03.
- **Non-identity fixture values:** applied throughout per D3 — no confidence/reliability/
  probability fixture uses 0.00 or an unexamined default except where the 0.00/1.00 boundary is
  itself explicitly under BVA test (CONF-05, CONF-09, JEV-02).

---

## 6. Open Questions for Project Leadership (Rev 2 — all Rev-1 items RULED, 2026-11-12)

All five original open questions, plus both flagged "implementer chooses" boundaries, were
ruled on at SE#1282 step 4 (2026-11-12) and are now pinned throughout the test cases above,
not left as "either ruling" language. Disposition of each:

- **OQ-1 (`claim_scope` mechanism) — RULED.** Lives in
  `research_findings.metadata->>'claim_scope'`, values `proved|computed|cited|conjecture`.
  Verified live at the pinned commit: `metadata` is `jsonb NOT NULL`; no `claim_scope` column
  exists anywhere; 0 of 6313 existing rows carry the key. Missing/invalid key → advisory
  `scope_undeclared`, never gates. Pinned in CONF-07 (missing key) and CONF-07A (new: invalid
  value, two sub-cases — case/whitespace variant and wrong JSON type).
- **OQ-2 (exit-code taxonomy) — RULED.** 0 = all findings pass; 1 = one or more findings
  blocked; 2 = gate could not run (config/DB/usage error). Advisory-only conditions never
  change the exit code. Pinned throughout GATE-01..06A and at DB-05.
- **OQ-3 (UNREAD gate-blocking vs. advisory) — RULED: BLOCKING.** Within the 72h window → exit
  1. Past the window → citation dropped, finding re-evaluated on remaining citations; no
  remaining supporting citation → blocked (exit 1). Pinned in GATE-06 (within-window) and new
  GATE-06A (past-window, both the still-supported and now-unsupported sub-cases).
- **OQ-4 (all-or-nothing vs. per-citation Jev failure) — RULED: per-citation (QA's recommended
  option (a), confirmed).** A malformed/failed Jev response marks that citation unverified,
  blocking its finding; other findings evaluate normally; exit code = worst outcome (1).
  Exception: if EVERY Jev call in a run fails, that is systemic — exit 2. Pinned in new
  GATE-02A (systemic, exit 2) and GATE-02B (BVA: all-but-one still exit 1, not 2).
- **OQ-5 (Jev transient-error retry policy) — RULED.** 3 attempts total, exponential backoff
  (1s, 2s), honoring `Retry-After` on 429. Applies to timeout, 5xx, 429. Non-429 4xx and
  malformed-200-body get no retry. Pinned in JEVERR-04 (timeout, 3 attempts), new JEVERR-04A
  (retry succeeds mid-budget), JEVERR-05 (5xx, same budget), new JEVERR-05A (429 + Retry-After),
  new JEVERR-05B (negative case: no retry on non-429 4xx or malformed body).
- **JEV-02 boundary — RULED: `p_supports <= 0.05` escalates (blocks).** Pinned directly in
  JEV-02's text; no longer framed as an inferred reading of the calibration report.
- **NET-03 boundary — RULED: window is `[0, 72h)`; elapsed `>= 72h` is dropped.** Pinned
  directly in NET-03 with three fixtures (just-under, just-over, and exactly-72h), and carried
  through to NET-04/GATE-06/GATE-06A's drop behavior.

**No open questions remain from Rev 1.** See §8 (Pushback / Disagreements) for one ruling-time
clarification QA is flagging rather than silently absorbing.

---

## 7. Source-Artifact Verification

```
$ git clone https://github.com/NOVA-Openclaw/nova-mind /home/nova/work/se1282-gidget
$ cd /home/nova/work/se1282-gidget
$ git checkout -b feat/657-finding-audit-gate 286f24aca9377e74adf2d0bec076b2bb4701fd7a
$ git rev-parse HEAD
286f24aca9377e74adf2d0bec076b2bb4701fd7a
$ git status
On branch feat/657-finding-audit-gate
nothing to commit, working tree clean
```

Fresh clone (never the working-tree checkout at `~/nova-mind`), pinned ref verified matching
the dispatch brief before any analysis began. No gate implementation code exists in this repo
at this commit — this document is a greenfield test design preceding implementation, per the
SE#1282 step-3 dispatch.

---

## 8. Pushback / Disagreements (Rev 2)

Nothing here blocks implementation — these are clarifications QA is flagging rather than
silently resolving by assumption, per the instruction to push back if a ruling breaks a
previously-designed test.

**None of the five rulings broke a Rev-1 test case outright.** Every Rev-1 test that touched a
ruled question was written in Rev 1 specifically to accept either plausible outcome (CONF-07,
GATE-06, SCOPE-04) or to flag the gap honestly (GATE-02's original "distinct code per class"
premise, JEVERR-04/05's unpinned retry timing) rather than assert a guessed behavior — so the
rulings required rewording and net-new sub-cases, not retraction of a test that turned out
wrong.

**One genuine correction, flagged rather than silently absorbed:** Rev 1's `TC-657-GATE-02`
was designed around the (wrong, in hindsight) assumption that the eventual taxonomy would
assign **a distinct exit code per violation class** (existence vs. confidence vs. tier vs.
task-not-found vs. Jev-escalation). The actual ruling is deliberately coarse — three codes
total, with violation-class detail living only in the review table's named-violation text, not
in the exit code. This is a better design (it keeps the taxonomy stable as new violation
subtypes are added later, since `sys.exit(1)` never needs touching again) but it does mean
Rev 1's GATE-02 was testing for behavior the implementation was never going to have. Reworded
in place rather than left as a latent false expectation; flagging it explicitly here so the
correction is visible in the revision history, not buried in a diff.

**One scope note on OQ-4's "every Jev call fails → exit 2" clause:** the ruling's exact
wording is "if EVERY Jev call in a run fails, exit 2." GATE-02A tests this literally (100% of
Jev calls fail → exit 2) and GATE-02B tests the boundary just under 100% (2 of 3 fail → still
exit 1). This leaves one case genuinely unspecified by the ruling's own wording, which QA is
noting rather than guessing past: a task with **zero citations requiring any Jev call at all**
(e.g. every finding fails on a purely deterministic axis — EXISTENCE/CONFIDENCE/TIER — before
ever reaching the Jev layer). Is "every Jev call failed" vacuously true (0 of 0 calls failed,
which some implementations might read as 100% failure) or vacuously false (no calls were
attempted, so there is nothing to call "systemic")? This does not block implementation — a
reasonable default (exit 1, since real deterministic violations were found and reported, and
no Jev-layer problem exists at all) is almost certainly what was intended — but QA is not
silently assuming it. No new test case added for this corner pending confirmation, to avoid
pinning a behavior that wasn't actually ruled on.

---

**Report path (this document):** `tests/TEST-CASES-ISSUE-657.md` (this repo's existing
convention per `evals/se717/test-case-design-v2.md` and the `tests/TEST-CASES-ISSUE-*.md`
files already present at this commit).
