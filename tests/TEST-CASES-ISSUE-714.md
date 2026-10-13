# Test Cases — nova-mind#714, #711 + nova-workspace#250, #251 (Chunk C: heartbeat/motivation)

**SE run #1231, step 3/4 — QA test-case design (Chunk C)**
**Author:** Gem (QA Lead)
**Scope:** nova-mind #714 (cadence + session unification), #711 (maintenance/decay/embed catch-up + sweeper
retirement + liveness alarm), nova-workspace #250 (gate-check idle detection), nova-workspace #251 (sweeper bugs,
**superseded by today's retirement decision**). Chunk C of tracking issue #715. Continues in the same pinned
nova-mind clone/branch as Chunks A and B.

**Rev 2 (2026-10-13 19:52 — I)ruid's step-4 corrections to Rev 1):**
- **§5 field-name CORRECTED:** idle field is `lastInteractionAt` (`docs/concepts/session.md:234`), not
  `updatedAt` — the CLI returns both. All TC-250-* rewritten; added TC-250-007 (a cron/bookkeeping `updatedAt`
  bump must NOT count as activity).
- **§3 TC-714-002 REVERSED:** NO session merge. `agent:nova:heartbeat:heartbeat` name AND `isolatedSession: true`
  are KEPT (02:44 ruling supersedes the 01:28 ruling this file's Rev 1 was built on). Only the
  `agent:nova:main:heartbeat` wake path's DELIVERY TARGET changes, to #proactive-mode. Added TC-714-004b: audit
  every agent's effective heartbeat target resolves to #proactive-mode (cites `sync.ts:131-140`'s
  heartbeat_enabled/to inheritance logic).
- **§3 TC-714-001 (cadence 20m) marked PENDING**, written parametrized for both the nova-only and
  `agents.defaults`-wide scope options — scope is explicitly still open per step-4 review.
- **§4 liveness alarm refined:** posts to #proactive-mode, at most once per day per stalled job until recovery
  (closes Rev 1's two open questions on this point).
- **§4 work_queue scope widened:** from "don't orphan the 9 pending rows" to "close the 1 remaining pending row AND
  drop the INSERT requirement entirely going forward." Added TC-711-011/012/013 — VERIFY-ONLY tests confirming the
  two bootstrap records (`SUBAGENT_SPAWNING`, `ORCHESTRATION_PRINCIPLES`, both confirmed live in
  `agent_bootstrap_context`) and the `agent-ecosystem` skill no longer mandate a work_queue INSERT, once NOVA
  edits them herself (these tests do not write the edits).
- Case count: #714 11→12 (TC-714-004b added, TC-714-001 now pending); #711 10→13 (TC-711-011/012/013 added);
  nova-workspace#250 7→8 (TC-250-007 added).

---

## 0. Pinned source artifacts

- **nova-mind:** same clone, `~/repos/se1231-nova-mind`, branch `fix/se1231-openclaw-2026.9-regressions`, base
  `12ecc0b`. Chunks A/B already committed on top (`872add5`, `5052241`, `929a956`, `d23e9db`).
- **nova-workspace:** fresh clone `~/repos/se1231-nova-workspace`, pinned at `da56b303` (per #715 step-2 and this
  dispatch) — reference for #250/#251's own content and (if present) heartbeat/sweeper-adjacent scripts.
- **OpenClaw host behavior reference:** `/home/nova/nova-openclaw-production` at `6ced19b` (2026.9.6),
  `docs/gateway/heartbeat.md` — read-only reference for actual scheduler/defer semantics.
- **wf27 step 2 Phase E** (the orphaned-subagent check replacing the sweeper): read via
  `psql -U gem -d nova_memory -h localhost -Atc "SELECT description FROM workflow_steps WHERE workflow_id=27 AND step_order=2"`,
  full text quoted in §5 below.

---

## 1. Host-contract citations (heartbeat defer/retry semantics — `docs/gateway/heartbeat.md`, 2026.9.6)

- **Line 104 (the core defer rule #714's own comment paraphrases):** "Scheduled heartbeats defer while the main
  queue or automation work is active or queued, while any reply or embedded run for the same agent is active, and
  while the resolved target session has active or queued work. An event-free plain monitor poll that has not begun
  preparation is recorded as skipped and waits for its next persisted cadence tick, instead of keeping a running
  automation open behind busy work. **Wakes carrying queued events or scheduled tasks, and work already admitted or
  retained after execution, still retry.** Immediate and manual wakes bypass the broad same-agent active-run check,
  but still honor the main, automation, and target-session busy guards."  **This is the exact mechanism #711's
  catch-up requirement must exploit**: overdue maintenance/decay/embed work should be scheduled as a wake carrying
  a queued event/task (which retries), not as a plain poll (which is skipped, not retried).
- **Line 21:** heartbeat cadence is owned by the Automations scheduler, one system-owned job per agent, visible via
  `openclaw cron list --all` as `Heartbeat (agent-id)` — **not** a crontab entry (confirmed empirically:
  `crontab -l | grep -i heartbeat` returns zero matches on this host, consistent with the doc).
- **Lines 66-67, 154-155, 278-280 (`isolatedSession`):** `isolatedSession: true` (optional) runs a fresh session
  each run with no conversation history; default is `false`. This is the exact field #714/dispatch requires stay
  `true` for nova's heartbeat config.
- **Line 96-97:** default cadence `30m` (or `1h` under Anthropic OAuth/token auth unless `heartbeat.every` is
  explicitly set); delivery target defaults to `owner`; `target: "last"` follows the most recent conversation.
- **Line 319:** heartbeat turn timeout defaults to cadence capped at 600s unless `agents.defaults.timeoutSeconds`/
  per-agent override is set.

---

## 2. Adversarial/config-seam coverage index

| Requirement | Satisfied by |
|---|---|
| Wrong-type/malformed value at a config seam | TC-714-009 (gate-check CLI returns malformed/partial JSON), TC-714-010 (`isolatedSession` accidentally flipped to `false` by a config merge) |
| Non-identity fixture values | TC-711-005 (48h liveness alarm tested at 47h59m and 48h01m, not exactly 0h/48h/a round number) |
| Config→runtime seam populated by production code | TC-714-011 (session-unification test runs against the REAL automation job / `openclaw cron list --all` output, not a hand-built config fixture) |
| INTENT-level check vs. a live source system | TC-250-003 (regression-replays the actual 2026-10-13 false-idle incident from nova-workspace#250's own evidence, not a synthetic idle/busy fixture) |
| Source-artifact pinning verified before analysis | §0; both repos' `git rev-parse HEAD` checked |

---

## 3. #714 — Delivery to #proactive-mode (session NOT merged — step-4 correction), heartbeat-target audit, cadence PENDING (12 cases: TC-714-001…004, 004b, 005…011; TC-714-002/004 corrected, TC-714-001 marked pending — see Revision Log Rev 2)

### TC-714-001 — Heartbeat cadence 20m: SCOPE STILL OPEN — PENDING, parametrized test
**Priority:** Pending (not yet in the acceptance bar) — per step-4 review: "Cadence 20m: SCOPE IS STILL OPEN
(nova-only override vs. agents.defaults, which would also speed up every subagent's heartbeat)."
**Design (parametrized, both scopes written, exactly one activates once scope is decided):**
- **Scope A (nova-only):** `agents.entries.nova.heartbeat.every` set to `20m`; `agents.defaults.heartbeat.every`
  unchanged (still `30m` or provider-default). Expected: only nova's materialized automation job shows 20m;
  every subagent's own heartbeat job is unaffected.
- **Scope B (agents.defaults):** `agents.defaults.heartbeat.every` set to `20m`. Expected: EVERY agent without its
  own explicit `heartbeat.every` override (i.e. every subagent, since per TC-714-011 below only nova has an
  explicit heartbeat row) now ticks at 20m — a much larger blast radius, deliberately flagged pending or confirmation
  this is actually wanted before it's treated as in-scope.
**Status:** Neither variant is required to pass in this run's acceptance bar until the orchestrator picks a scope.
Both are written now so whichever is chosen can be run immediately without a new design pass.

### TC-714-002 — `agent:nova:main:heartbeat` (webchat) wake output must deliver to #proactive-mode (REWRITTEN per step-4 — NO session merge)
**Priority:** P1 (Critical) — direct acceptance test, CORRECTED per step-4 review: "Heartbeat session: KEEP
`isolatedSession: true` and accept the name `agent:nova:heartbeat:heartbeat`. I)ruid's 02:44 ruling supersedes the
01:28 one. Rewrite TC-714-002: NO merge into `agent:nova:heartbeat`. Instead, the `agent:nova:main:heartbeat` wake
output must deliver to #proactive-mode." This REVERSES Rev-1's TC-714-002 (which required unifying the two session
keys into one `agent:nova:heartbeat` — that design is now wrong and withdrawn).
**Preconditions:** Pre-fix baseline: `agent:nova:main:heartbeat` (webchat-routed event-driven wake session) and
`agent:nova:heartbeat:heartbeat` (correctly #proactive-mode-routed scheduled heartbeat session) remain TWO
DISTINCT session keys — this is accepted, not a bug to fix.
**Steps:** Trigger the event-driven wake path that lands in `agent:nova:main:heartbeat` (e.g. a background-exec
completion notification, per #714's own evidence that the work-queue sweeper's output landed there via webchat).
**Expected:** The session key itself remains `agent:nova:main:heartbeat` (unchanged — no merge); ONLY its delivery
target changes, from webchat to #proactive-mode (`1504054635231445112`).

### TC-714-003 — No heartbeat output of any kind (scheduled OR wake, from EITHER session key) goes to webchat
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED ("No heartbeat output should go to webchat").
Unchanged in intent from Rev 1, but now explicitly spans TWO separate session keys rather than one unified key.
**Steps:** Trigger (a) `agent:nova:heartbeat:heartbeat`'s scheduled cadence tick and (b) `agent:nova:main:
heartbeat`'s event-driven wake.
**Expected:** Both deliver to #proactive-mode; zero deliveries to webchat from either session key.

### TC-714-004 — `isolatedSession: true` is preserved on `agent:nova:heartbeat:heartbeat` (regression guard — simplified, no merge-interaction concern)
**Priority:** P1 (Critical) — explicit regression guard per step-4 review ("KEEP isolatedSession: true").
**Preconditions:** Post-fix config.
**Steps:** Inspect `agents.entries.nova.heartbeat.isolatedSession`.
**Expected:** `true` — unchanged. **Rev 1's "flagged for clarification" tension between isolatedSession and a
unified session key is now MOOT**: since TC-714-002 no longer merges the two session keys, there is no interaction
to reconcile — `agent:nova:heartbeat:heartbeat` keeps its own isolated-per-run behavior exactly as it always has.

### TC-714-004b — NEW: every agent's effective heartbeat delivery target resolves to #proactive-mode, none other
**Priority:** P1 (Critical) — REQUIRED by step-4 review: "ALL heartbeat output (scheduled and wake, NOVA's and
every subagent's) delivers to #proactive-mode... Add a test that no agent's effective heartbeat target is anything
else." Host-contract citation: `cognition/focus/agent-config-sync/src/sync.ts:131-140` (pinned `12ecc0b`) — a
per-agent `heartbeat` key is only emitted into `agents.json` when `heartbeat_enabled===true AND
heartbeat_every` is set on that agent's DB row, and even then `to`/`target` are only included if the DB row has
them explicitly set; otherwise the `heartbeat` key is omitted entirely and the agent inherits
`agents.defaults.heartbeat` wholesale (confirmed: today, per step-4 review, "only nova has an explicit row;
nothing overrides it elsewhere").
**Steps:** For every agent in the live `agents` table (status='active'), resolve its EFFECTIVE heartbeat delivery
target (explicit per-agent override if present, else `agents.defaults.heartbeat.to`).
**Expected:** Every single resolved target is #proactive-mode (`1504054635231445112`) — nova's (if she has an
explicit override) AND every subagent's (via the `agents.defaults` inheritance path) AND confirm the audit itself
catches a planted counter-example (mutation test: temporarily set one subagent's `heartbeat_to` to a different
channel in a test fixture and confirm the audit flags it) — a test that can't actually detect a wrong target isn't
verifying anything.

### TC-714-005 — A genuinely busy tick still defers (NOT a bug — confirms line-104 behavior is unaffected by this fix)
**Priority:** P2 (High) — negative/regression case; the fix must not accidentally force ticks to fire through
busy guards.
**Preconditions:** Main queue/automation work active for nova at the scheduled tick time.
**Steps:** Let a tick land while nova is mid-turn on unrelated work.
**Expected:** The tick still defers/skips per heartbeat.md line 104 — unaffected by the cadence/session-unification
fix. This is the control case for TC-711's catch-up logic (§4): deferring is correct; LOSING the overdue work
forever is the actual bug.

### TC-714-006 — Event-driven wake (background-exec completion) still reaches the unified session under busy conditions where cadence ticks would defer
**Priority:** P2 (High) — per heartbeat.md line 104: "Wakes carrying queued events... still retry" — distinct
guarantee from the plain-poll case in TC-714-005.
**Steps:** Trigger a background-exec completion notification for nova while a cadence tick would otherwise have
deferred.
**Expected:** The event-driven wake still runs (it carries a queued event, so it retries rather than skipping);
it lands in `agent:nova:heartbeat` (TC-714-002) and delivers to #proactive-mode (TC-714-003), not webchat.

### TC-714-007 — Rate limits on event-driven wakes are unaffected by the cadence change
**Priority:** P3 (Low) — regression guard per heartbeat.md line 27 (30s minimum between event turns, flood guard
after 5 starts within 60s) — confirm the 20m cadence change doesn't interact with or loosen this independent limit.
**Expected:** Rate-limit behavior identical pre/post cadence change.

### TC-714-008 — `openclaw doctor --fix` materializes the 20m schedule if the monitor row is stale post-config-change
**Priority:** P2 (High) — direct test of heartbeat.md's own stated remediation path for config/monitor drift.
**Steps:** Change cadence config without restarting the gateway; run `openclaw doctor --fix`.
**Expected:** The persisted automation job's schedule updates to 20m without requiring a full gateway restart.

### TC-714-009 — Gate-check CLI returns malformed/partial JSON mid-tick
**Priority:** P1 (Critical) — adversarial malformed-value case, shared seam with #250 (§5).
**Preconditions:** `openclaw sessions --json ...` (the gate-check's data source, see §5) returns truncated/invalid
JSON (e.g. process killed mid-write, matching #250's own evidence of a SIGTERM'd gate run).
**Expected:** The heartbeat tick does not crash the whole turn; the gate-check failure is handled per #250's
required fail-CLOSED behavior (TC-250-002), not silently treated as "no output = idle."

### TC-714-010 — `isolatedSession` accidentally flipped to `false` by an unrelated config merge (adversarial config-seam case)
**Priority:** P1 (Critical) — REQUIRED adversarial case; direct regression guard for TC-714-004's "stays true"
requirement against a realistic failure mode (a config-sync/installer merge touching the `heartbeat` block
without preserving `isolatedSession`).
**Preconditions:** Simulate a config write (e.g. an agent-config-sync-style merge, per Chunk D's #707 — cross-
reference only, not re-tested here) that writes `agents.entries.nova.heartbeat` without an explicit
`isolatedSession` key.
**Expected:** The merge preserves the existing `true` value (does not silently reset to the schema default
`false`) — this test should be coordinated with whatever Chunk D's #707 test design covers for config-merge
idempotency, since this is the same class of defect as Chunk B's TC-709-002.

### TC-714-011 — Session-unification verified against the REAL automation job, not a hand-built config fixture
**Priority:** P1 (Critical) — REQUIRED config→runtime seam case.
**Steps:** On staging, after the fix lands, run `openclaw cron list --all` and inspect the actual `Heartbeat
(nova)` job's configured delivery/session binding — not a unit test asserting the intended config shape in
isolation.
**Expected:** The live automation job's own metadata shows the unified session key and #proactive-mode target,
proving the host actually reads and applies the fixed config, not just that the config file itself looks correct.

---

## 4. #711 — Maintenance/decay/embed catch-up, sweeper retirement, 48h liveness alarm, work_queue requirement DROPPED (13 cases: TC-711-001…013; TC-711-004/006/010 refined, TC-711-011/012/013 added — see Revision Log Rev 2)

### TC-711-001 — Overdue maintenance/decay/embed work catches up on the next tick that actually fires
**Priority:** P1 (Critical) — direct acceptance test, the core of #711's fix per the dispatch ("overdue maintenance/
decay/embed catch up on the next tick that fires, since 2026.9.x skips busy ticks").
**Preconditions:** Simulate several consecutive skipped ticks (busy agent, per TC-714-005) spanning a window where
maintenance/decay/embed phases were due.
**Steps:** Let a subsequent tick land while the agent is idle.
**Expected:** The overdue phases run on THIS tick (not lost, not requiring a manual catch-up) — implemented via the
line-104 "wakes carrying queued events/scheduled tasks still retry" mechanism (TC-714-006's mechanism, applied
here to maintenance scheduling) rather than a plain poll that would itself be subject to skip-not-retry.

### TC-711-002 — Catch-up does not re-run phases that already completed on an earlier (non-skipped) tick
**Priority:** P1 (Critical) — idempotency guard, mirrors Chunk B's TC-703-004 pattern.
**Preconditions:** A tick fired normally and completed maintenance/decay/embed in full.
**Steps:** The next tick fires normally too (not overdue).
**Expected:** No duplicate maintenance/decay/embed run is triggered by stale "catch-up" state from the prior
successful tick.

### TC-711-003 — Maintenance/decay/embed resume correctly after a LONG busy stretch (multiple cadence periods skipped)
**Priority:** P2 (High) — non-trivial multi-skip case, not just a single skipped tick.
**Preconditions:** Simulate 5+ consecutive skipped ticks (e.g. ~100 minutes busy at 20m cadence).
**Expected:** Catch-up still runs completely on the next idle tick — no partial/truncated catch-up, no silent
drop of phases queued furthest in the past.

### TC-711-004 — Liveness alarm fires when maintenance hasn't run for >48h, posts to #proactive-mode
**Priority:** P1 (Critical) — direct acceptance test; delivery channel and cadence now SPECIFIED (step-4 review
resolves the two open questions Rev 1 had flagged here): "48h liveness alarm: posts to #proactive-mode, at most
once per day per stalled job until it recovers."
**Preconditions:** Simulate a maintenance-run timestamp 49h in the past with no successful run since.
**Steps:** Run the liveness check.
**Expected:** An alarm posts to #proactive-mode (`1504054635231445112`), identifying WHICH phase/job is stale.

### TC-711-005 — Liveness alarm boundary: 47h59m does NOT fire, 48h01m DOES (non-identity fixture)
**Priority:** P1 (Critical) — unchanged from Rev 1; still REQUIRED non-identity-fixture case.
**Expected:** Correct boundary semantics at exactly 48h, verified with genuinely adjacent (not round) timestamps.

### TC-711-006 — Liveness alarm re-fires AT MOST ONCE PER DAY per stalled job, until that job recovers (cadence now SPECIFIED)
**Priority:** P1 (Critical) — direct acceptance test, cadence resolved per step-4 review (no longer an open
question).
**Preconditions:** A job remains stalled across multiple days.
**Steps:** Let the liveness check run every 20m-cadence heartbeat tick across 3+ days while the job stays stalled.
**Expected:** Exactly one alarm post per calendar day per stalled job (not one per tick — would be ~72/day at 20m
cadence) — and once the job recovers (a successful run is observed), alarms for that job stop entirely on the
next check.

### TC-711-007 — Sweeper RETIREMENT: script, payload docs, and all references are deleted (unchanged from Rev 1)
**Priority:** P1 (Critical) — direct acceptance test, per #715's step-2 design and this dispatch's retirement
decision (supersedes nova-workspace#251's own bug-fix proposal).
**Steps:** `grep -rln` both pinned repos for `work_queue_sweeper`, `work-queue-sweeper-payload`,
`wq-sweeper-payload-151`, and the job ids named in #251.
**Expected:** Zero hits post-fix in both repos; the scheduler job is removed from both `crontab -l` and `openclaw
cron list --all`.

### TC-711-008 — wf27 step 2 Phase E fully covers what the sweeper used to catch (unchanged from Rev 1)
**Priority:** P1 (Critical) — direct acceptance test for the replacement mechanism (full Phase E text cited in Rev 1).
**Expected:** An orphaned subagent completion is detected on the next wf27 step-2 run, given a Phase-C disposition,
never silently lost.

### TC-711-009 — wf27 step 2 Phase E reports "nothing orphaned" with no noise in the common case (unchanged from Rev 1)
**Priority:** P2 (High) — negative-space test.
**Expected:** Zero Phase E output/report line when parent-delivery works normally.

### TC-711-010 — work_queue retirement: the 1 remaining pending row is closed in the retirement PR; the INSERT requirement is DROPPED ENTIRELY (REWRITTEN per step-4 review — bigger scope than Rev 1's data-safety framing)
**Priority:** P1 (Critical) — direct acceptance test, CORRECTED per step-4 review: "work_queue: close the 1
remaining pending row in the retirement PR, and DROP the work_queue INSERT requirement entirely." (Rev 1 had cited
#711's original "9 pending items" figure and framed this only as "don't orphan pre-existing rows" — the live count
has since narrowed to 1, and the scope is now explicitly bigger: the INSERT-tracking PRACTICE itself is retired
going forward, not just its backlog.)
**Steps:** (a) Confirm the 1 remaining pending `work_queue` row is closed (processed or explicitly resolved) as
part of the retirement PR. (b) Confirm no code path anywhere in the fixed branch still expects/requires a
`work_queue` INSERT as a precondition for anything (e.g. no remaining consumer reads `work_queue` rows as its
sole/required completion-detection signal — wf27 step 2 Phase E, per TC-711-008, is the full replacement).
**Expected:** Zero pending `work_queue` rows remain unaddressed after the retirement PR; no code requires a NEW
`work_queue` INSERT to function correctly going forward.

### TC-711-011 — Bootstrap record `UNIVERSAL/SUBAGENT_SPAWNING` no longer REQUIRES a work_queue INSERT (VERIFY-ONLY — NOVA edits this herself)
**Priority:** P1 (Critical) — REQUIRED verification, per step-4 review: "Test that the bootstrap records
(UNIVERSAL/SUBAGENT_SPAWNING, DOMAIN ORCHESTRATION_PRINCIPLES) and the agent-ecosystem skill no longer require it.
NOVA edits the bootstrap records herself; your tests only verify them." **This test does NOT write the edit — it
only checks the end state after NOVA's own edit lands.**
**Current content (confirmed live, `agent_bootstrap_context` table, `file_key='SUBAGENT_SPAWNING'`, `agent_name IS
NULL`, 4,569 chars, read-only query at design time):** contains a `## Work Queue Tracking (mandatory)` section
with an explicit `INSERT INTO work_queue (...)` SQL template and the instruction "Whenever you dispatch
fire-and-forget work... INSERT a row into work_queue in the same turn as the dispatch."
**Steps (post-NOVA's-edit):** Query `agent_bootstrap_context` for `file_key='SUBAGENT_SPAWNING'`; grep its content
for `work_queue`/`INSERT INTO work_queue`/the word "mandatory" in proximity to `work_queue`.
**Expected:** No remaining MANDATORY work_queue-INSERT instruction in this record's content — either the whole
section is removed, or it's reframed as historical/optional/superseded-by-wf27-Phase-E, not as a required step in
the spawn sequence.

### TC-711-012 — Bootstrap record `DOMAIN ORCHESTRATION_PRINCIPLES` no longer lists work_queue INSERT as a mandatory spawn-sequence step (VERIFY-ONLY)
**Priority:** P1 (Critical) — same verify-only framing as TC-711-011, distinct bootstrap record.
**Current content (confirmed live, `file_key='ORCHESTRATION_PRINCIPLES'`, `agent_name IS NULL`, 8,907 chars):**
describes `work_queue` + the (now-retired) sweeper as "the primary completion-detection mechanism" and includes a
numbered spawn sequence whose step 3 is "INSERT work_queue row (dispatch-tracking for the sweeper)."
**Steps (post-NOVA's-edit):** Re-query this record; check the spawn-sequence numbering no longer includes a
work_queue INSERT step, and the "primary completion-detection mechanism" framing is updated to reflect wf27 step 2
Phase E (per TC-711-008) as the actual mechanism, not the retired sweeper.
**Expected:** No remaining reference to the sweeper as a live mechanism; no mandatory work_queue INSERT step in the
spawn sequence.

### TC-711-013 — agent-ecosystem skill no longer requires marking/using work_queue rows (VERIFY-ONLY)
**Priority:** P1 (Critical) — same verify-only framing; third of the three sources step-4 review names.
**Current content (confirmed live, `~/.openclaw/skills/agent-ecosystem/SKILL.md`, 7,872 chars):** contains, in its
retry/respawn guidance, the line "Mark the failed work_queue row and respawn; never wait for billing/provider
restore mid-run."
**Steps (post-NOVA's-edit):** Re-read the skill file; grep for `work_queue`.
**Expected:** Zero remaining references to marking/reading/inserting `work_queue` rows as a required step — the
retry/respawn guidance itself (the underlying behavioral advice) may remain, just without the work_queue-specific
mechanic.



---

## 5. nova-workspace#250 — Gate-check idle detection (8 cases: TC-250-001…008)

**Field-name CORRECTION (step-4 review, 2026-10-13 19:52): the idle field is `lastInteractionAt`, not `updatedAt`.**
Per I)ruid: "Idle field = `lastInteractionAt` (`docs/concepts/session.md:234`); `updatedAt` changes on any
bookkeeping write. The CLI returns BOTH fields." This corrects Rev 1's §5 header note, which had flagged
`updatedAt` (from the live #250 2026-10-12 comment) as the likely-correct field — that comment either described a
transitional/incomplete reading, or conflated the two fields; `lastInteractionAt` is the authoritative one per the
session-concept doc. **`updatedAt` bumps on ANY bookkeeping write (including non-user-facing ones), so using it
for idle detection would produce false "not idle" readings whenever routine internal writes touch a session row —
a DIFFERENT failure mode than the original false-idle bug, but just as real.** All TC-250-* cases below are
rewritten against `lastInteractionAt`.

### TC-250-001 — Gate check reads session recency via `openclaw sessions --json`'s `lastInteractionAt` field, not the gone `sessions.json`
**Priority:** P1 (Critical) — direct acceptance test. Old source: `~/.openclaw/agents/nova/sessions/sessions.json`
(confirmed absent per #250's 2026-10-11 comment). New source: `openclaw sessions --agent nova --active <min>
--json`, specifically its `lastInteractionAt` field (per `docs/concepts/session.md:234`) — NOT `updatedAt`,
which the same CLI output also includes but which is NOT idle-detection-safe (see TC-250-007).
**Steps:** Trigger a gate-check run.
**Expected:** Zero reads of the old `sessions.json` path; the gate specifically reads `lastInteractionAt`, not
`updatedAt`, from the CLI's JSON output.

### TC-250-002 — CLI failure (timeout, nonzero exit, malformed output) → fail CLOSED (`idle=false` + error field), never fail-open
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED by #250's own stated fix across all 3 of its
comments. Unchanged by the field-name correction.
**Preconditions:** Simulate (a) CLI timeout, (b) CLI nonzero exit, (c) CLI returns malformed JSON.
**Expected:** All three produce `idle=false` plus a populated error field — never `idle=true`/`idle_minutes=Infinity`
silently treated as "safe to proceed with proactive steps."

### TC-250-003 — Regression replay of the 2026-10-13 false-idle incident, using `lastInteractionAt`
**Priority:** P1 (Critical) — REQUIRED INTENT-level case; replays #250's own newest, highest-severity comment: gate
reported `idle=true (Infinity)` while real Discord activity existed 10-16 min prior plus two I)ruid-triggered
workflow runs.
**Steps:** Reconstruct this exact session-activity fixture with a real, recent `lastInteractionAt` value on a
discord-prefixed key, and run the fixed gate check against it.
**Expected:** The fixed gate correctly reports `idle=false` — the single most important regression test in this
section, reproducing a CONFIRMED wrong-answer incident.

### TC-250-004 — Genuinely idle session (`lastInteractionAt` 5h+ in the past) still reports `idle=true`
**Priority:** P1 (Critical) — positive-case regression guard.
**Steps:** Reconstruct the 2026-10-12 comment's own fixture (last user-facing activity ~5h prior), expressed via
`lastInteractionAt` rather than `updatedAt`.
**Expected:** `idle=true`, no error.

### TC-250-005 — Non-user-facing keys (cron, heartbeat, subagent) are excluded from the idle-activity filter
**Priority:** P1 (Critical) — unchanged by the field-name correction; still tests the `discord|signal|telegram|
slack` key-prefix filter.
**Steps:** Simulate recent `lastInteractionAt` activity ONLY on `agent:nova:heartbeat`/`agent:nova:cron:*`-prefixed
keys, none on any channel-prefixed key.
**Expected:** `idle=true` — heartbeat/cron/subagent activity alone does not suppress idle detection.

### TC-250-006 — Multiple concurrent channel keys with different `lastInteractionAt` recency — the MOST recent wins
**Priority:** P2 (High) — correctness case for aggregating across `.sessions[]` entries.
**Steps:** Fixture with a stale Discord key (`lastInteractionAt` 6h ago) and a fresh Slack key (`lastInteractionAt`
2 min ago).
**Expected:** `idle=false` (driven by the freshest channel-prefixed entry's `lastInteractionAt`).

### TC-250-007 — A cron/bookkeeping write that bumps `updatedAt` does NOT count as activity (REQUIRED new case, step-4 review)
**Priority:** P1 (Critical) — REQUIRED direct test of the `lastInteractionAt` vs. `updatedAt` distinction itself;
this is the test that would have caught a naive implementation reading the wrong field.
**Preconditions:** A session whose `updatedAt` is bumped by a routine internal/bookkeeping write (e.g. a heartbeat
tick touching the row, a cron job's own housekeeping, or any non-user-facing write) while its `lastInteractionAt`
remains stale (hours old, no real user interaction).
**Steps:** Run the gate check against this fixture.
**Expected:** `idle=true` — the fresh `updatedAt` does NOT suppress idle detection; only a fresh
`lastInteractionAt` would. A gate implementation that (incorrectly) reads `updatedAt` instead of
`lastInteractionAt` FAILS this test by reporting `idle=false`.

### TC-250-008 — Gate-check timeout value itself is adversarially tested (too-short timeout on a slow-but-working CLI call)
**Priority:** P2 (High) — adversarial boundary case, unchanged by the field-name correction.
**Steps:** Simulate a CLI call that succeeds but takes longer than the configured timeout.
**Expected:** Treated identically to TC-250-002's timeout case (fail closed).

---

## 6. Open questions for the orchestrator / Project Leadership review

> Rev 2 (2026-10-13 19:52) resolves: the `lastInteractionAt`/`updatedAt` field question (§5, now corrected), the
> session-merge question (§3, now explicitly reversed — no merge), the liveness-alarm channel/cadence questions
> (§4, now #proactive-mode + once/day/job), and the work_queue scope question (§4, now "drop the requirement
> entirely," not just "don't orphan the backlog"). Remaining:

1. **TC-714-001's cadence scope is EXPLICITLY STILL OPEN** (nova-only vs. `agents.defaults`) — this is not a gap in
   this test design, it's a genuine pending decision; the test itself is written parametrized for both outcomes and
   flagged `Pending`, not counted toward this run's pass/fail bar until the scope is chosen.
2. **TC-714-004b's mutation-test counter-example** (temporarily planting a wrong `heartbeat_to` value to prove the
   audit can actually detect it) needs a safe place to run — confirming this is a staging-only exercise, never
   attempted against the live `agents` table's real rows.
3. **TC-250-001/003/004/006/007's exact `lastInteractionAt` semantics** (is it updated on every channel-provider
   message, or only ones classified as "user-facing" by some other filter already, making the `discord|signal|
   telegram|slack` key-prefix filter in TC-250-005 partially redundant with what `lastInteractionAt` itself already
   encodes) — `docs/concepts/session.md:234` wasn't independently re-read in this revision pass (time-boxed); the
   citation is taken from step-4 review as authoritative, but implementation review should confirm the field's
   exact update semantics before TC-250-007 is finalized.
4. **TC-708-012's exact migration mechanics**, **TC-708-014's nova-staging disposition**, **TC-706-003's exact
   owning-table names**, and **TC-710-008's publish-active-sessions.py disposition** are Chunk B open items, carried
   forward unchanged (see `tests/TEST-CASES-ISSUE-708.md`'s own §7).
