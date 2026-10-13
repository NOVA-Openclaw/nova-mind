# Test Cases — nova-mind#714, #711 + nova-workspace#250, #251 (Chunk C: heartbeat/motivation)

**SE run #1231, step 3/4 — QA test-case design (Chunk C)**
**Author:** Gem (QA Lead)
**Scope:** nova-mind #714 (cadence + session unification), #711 (maintenance/decay/embed catch-up + sweeper
retirement + liveness alarm), nova-workspace #250 (gate-check idle detection), nova-workspace #251 (sweeper bugs,
**superseded by today's retirement decision**). Chunk C of tracking issue #715. Continues in the same pinned
nova-mind clone/branch as Chunks A and B.

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

## 3. #714 — Cadence 20m, single heartbeat session, delivery to #proactive-mode (11 cases: TC-714-001…011)

### TC-714-001 — Heartbeat cadence is 20m, not 30m
**Priority:** P1 (Critical) — direct acceptance test, per I)ruid's scope addition: "Shorten the heartbeat cadence
from 30m to 20m. In 2026.9.x a scheduled poll is skipped, not retried, whenever the agent is busy, so the old
cadence fires much less often in practice."
**Steps:** Inspect `agents.entries.nova.heartbeat.every` (or `agents.defaults.heartbeat.every`) post-fix; confirm
via `openclaw cron list --all` that the materialized `Heartbeat (nova)` automation job's persisted schedule
reflects 20m, not just the desired-state config (per heartbeat.md line 21: config is desired-state input, the
persisted monitor schedule owns the actual tick — a config-only change without the monitor row refreshing would
silently not take effect; `openclaw doctor --fix` materializes stale rows per the same doc section).
**Expected:** Both the config value AND the live automation job's schedule show 20m.

### TC-714-002 — `agent:nova:main:heartbeat` (webchat) and `agent:nova:heartbeat:heartbeat` become ONE session, `agent:nova:heartbeat`
**Priority:** P1 (Critical) — direct acceptance test, per I)ruid's scope addition #2.
**Preconditions:** Pre-fix baseline: two distinct session keys exist/are used for heartbeat-triggered work (per
#714's own evidence — the work-queue sweeper's output landed in `agent:nova:main:heartbeat` via webchat, while
the correctly-routed scheduled heartbeat used `agent:nova:heartbeat:heartbeat` → #proactive-mode).
**Steps:** Trigger (a) a scheduled cadence tick and (b) an event-driven wake (e.g. a background-exec completion
notification) for nova.
**Expected:** Both route into the SAME session key, `agent:nova:heartbeat` — no second, differently-named session
is created or written to for either trigger path.

### TC-714-003 — No heartbeat output of any kind goes to webchat
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED by dispatch ("No heartbeat output should go to
webchat").
**Preconditions:** Same two trigger paths as TC-714-002.
**Steps:** Inspect delivery target/channel for both.
**Expected:** Both deliver to #proactive-mode (Discord channel `1504054635231445112`); zero deliveries to webchat
under any trigger path, including the event-driven background-work-completion path that #714's evidence shows was
previously leaking into webchat via the `agent:nova:main:heartbeat` session.

### TC-714-004 — `isolatedSession: true` is preserved (regression guard — NOT touched by the cadence/session-unification fix)
**Priority:** P1 (Critical) — explicit regression guard per dispatch ("isolatedSession stays true").
**Preconditions:** Post-fix config.
**Steps:** Inspect `agents.entries.nova.heartbeat.isolatedSession`.
**Expected:** `true` — each heartbeat run still gets a fresh session with no conversation history (per
heartbeat.md lines 66-67/278-280), even though all heartbeat-triggered work now shares the single SESSION KEY
`agent:nova:heartbeat` from TC-714-002. **Flagged for clarification in §6**: "one session key" + "isolated/fresh
session each run" is not self-contradictory in OpenClaw's model (isolatedSession governs conversation-history
continuity within runs under that key, not the key's uniqueness), but this interaction should be explicitly
confirmed against the real automation-job behavior, not just assumed compatible.

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

## 4. #711 — Maintenance/decay/embed catch-up, sweeper retirement, 48h liveness alarm (10 cases: TC-711-001…010)

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

### TC-711-004 — Liveness alarm fires when maintenance hasn't run for >48h
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED by #711's own fix list ("Add a liveness check that
alarms when maintenance hasn't run for more than 48h").
**Preconditions:** Simulate a maintenance-run timestamp 49h in the past with no successful run since.
**Steps:** Run the liveness check.
**Expected:** An alarm fires (delivery channel TBD — see Open Question §6); the alarm identifies WHICH phase
(maintenance/decay/embed) is stale, not just "something is wrong."

### TC-711-005 — Liveness alarm boundary: 47h59m does NOT fire, 48h01m DOES (non-identity fixture, not a round-number boundary)
**Priority:** P1 (Critical) — REQUIRED non-identity-fixture adversarial case (lesson-787 pattern): testing only at
0h/24h/48h exactly would make an off-by-one in the boundary comparison invisible.
**Steps:** Run the check at both boundary points.
**Expected:** Correct `>`/`>=` semantics at exactly the 48h threshold, verified with genuinely adjacent
(not round) timestamps.

### TC-711-006 — Liveness alarm does not fire repeatedly/spam once triggered (de-duplication)
**Priority:** P2 (High) — operational sanity guard; an alarm re-firing every 20m cadence tick once past 48h would
be noise, not signal.
**Expected:** One alarm per stale-incident (or a sane re-notify cadence, e.g. daily) — confirm the intended
behavior and test it, rather than assuming either "fire once" or "fire every tick" without checking.

### TC-711-007 — Sweeper RETIREMENT: script, payload docs, and all references are deleted (NOT fixed — supersedes nova-workspace#251's own bug list)
**Priority:** P1 (Critical) — direct acceptance test. Per #715's step-2 design comment AND this dispatch: "retire
the sweeper (job removed 2026-10-13): delete the script, payload docs and references." **This supersedes
nova-workspace#251's own comment**, which (as of 2026-10-12) was proposing to FIX the sweeper's bugs (subagent-error
misclassification, stale job-id refs in 3 docs, an audit crash, a backfill count mismatch) rather than delete it —
that comment is now stale; none of its 4 listed bugs need fixing since the code they're in is being removed
entirely.
**Steps:** `grep -rln` both pinned repos (nova-mind `12ecc0b`+Chunks A/B/C, nova-workspace `da56b303`) for
`work_queue_sweeper`, `work-queue-sweeper-payload`, `wq-sweeper-payload-151`, and the specific job ids named in
#251 (`7b7da93b-e486-437a-982f-66939093d0b7`, `bbbb0c43-...`).
**Expected:** Zero hits post-fix in both repos (for the script/payload-doc files themselves — historical mentions
in issue trackers/changelogs are out of scope for this grep). The scheduler job itself is removed from both
`crontab -l` and `openclaw cron list --all`.

### TC-711-008 — wf27 step 2 Phase E fully covers what the sweeper used to catch (orphaned/undelivered subagent completions)
**Priority:** P1 (Critical) — direct acceptance test for the REPLACEMENT mechanism, cited in full from the live
`workflow_steps` row (`workflow_id=27, step_order=2`): "OpenClaw 2026.9.x announces subagent completions to the
parent session on its own. The rare gap is a subagent that finishes after the parent session died, so the
completion lands nowhere." Phase E's 4-step procedure: (1) list subagent runs ended in the last 24h
(`subagents(action="list")` or `openclaw sessions list --json` filtered to `agent:*:subagent:*`); (2) for each,
check whether completion was delivered to a LIVE parent (parent session still exists, has a turn after the child
ended); (3) undelivered/orphaned → read the child's final output via `sessions_history`, give it a Phase-C-table
disposition (finish the implied work, report in originating channel or #proactive-mode, or track); (4) nothing
orphaned → no output, no report line.
**Steps:** Simulate a subagent that completes AFTER its parent session has ended/died.
**Expected:** The orphan is detected on the next wf27 step-2 run, given a disposition per Phase C, and is NOT
silently lost (which the retired sweeper previously existed to catch via a different mechanism).

### TC-711-009 — wf27 step 2 Phase E correctly reports "nothing orphaned" with no noise when the parent-delivery path (OpenClaw's own announcement) works normally
**Priority:** P2 (High) — negative-space test, prevents Phase E from becoming spammy for the common case.
**Expected:** A subagent that completes while its parent is still alive produces zero Phase E output/report line —
distinguishes "nothing to catch" from "the check itself silently failed to run."

### TC-711-010 — Work-queue sweeper's own 9 pending items (oldest 2026-10-04, per #711's evidence) are not silently orphaned by the retirement
**Priority:** P1 (Critical) — data-safety regression guard; retiring the sweeper code must not abandon whatever
real work_queue rows it was responsible for processing.
**Preconditions:** The 9 pending `work_queue` items cited in #711's problem statement (oldest from 2026-10-04).
**Steps:** Confirm the disposition of these specific rows as part of the retirement work — processed, migrated to
a different mechanism, or explicitly and visibly marked as abandoned-with-reason.
**Expected:** None of the 9 rows is silently left in a `pending`/`stale` state forever with no owner and no
visible record of the retirement decision covering them.

---

## 5. nova-workspace#250 — Gate-check idle detection (7 cases: TC-250-001…007)

**Field-name citation note (from the live issue investigation, not the dispatch brief — flagged as a discrepancy,
see §6):** nova-workspace#250's 2026-10-12 comment documents the actual supported data source as
`openclaw sessions --agent nova --active <min> --json` returning **`.sessions[].updatedAt`** (epoch ms) and
**`.key`**, filtered on `discord|signal|telegram|slack` key prefixes for user-facing activity. This dispatch's own
wording names the field **`lastInteractionAt`** instead — these may be the same field under different names in
different CLI output shapes, or one of the two sources is stale. Test cases below are written against the
field name empirically documented in the issue (`updatedAt`), with the discrepancy flagged for confirmation.

### TC-250-001 — Gate check reads session recency via `openclaw sessions --json`, not the gone `sessions.json`
**Priority:** P1 (Critical) — direct acceptance test. Old source: `~/.openclaw/agents/nova/sessions/sessions.json`
(confirmed absent per #250's 2026-10-11 comment; the SQLite store `~/.openclaw/agents/nova/nova.sqlite` replaced
it). New source: `openclaw sessions --agent nova --active <min> --json`.
**Steps:** Trigger a gate-check run.
**Expected:** Zero reads of the old `sessions.json` path; the CLI invocation above (or its functional equivalent)
is the sole data source.

### TC-250-002 — CLI failure (timeout, nonzero exit, malformed output) → fail CLOSED (`idle=false` + error field), never fail-open
**Priority:** P1 (Critical) — direct acceptance test, REQUIRED by #250's own stated fix across all 3 of its
comments ("fail CLOSED (idle=false + error) when the source is missing" / "...if the CLI fails"). This is the
exact inverse of the pre-fix bug (fail-open `idle_minutes=Infinity` on a broken sensor, confirmed by #250's
2026-10-11 SIGTERM'd-gate-run evidence AND its 2026-10-13 false-idle incident, TC-250-003).
**Preconditions:** Simulate (a) CLI timeout, (b) CLI nonzero exit, (c) CLI returns malformed JSON.
**Expected:** All three produce `idle=false` plus a populated error field — never `idle=true`/`idle_minutes=Infinity`
silently treated as "safe to proceed with proactive steps."

### TC-250-003 — Regression replay of the 2026-10-13 false-idle incident (INTENT-level check against the live/documented event, not a synthetic fixture)
**Priority:** P1 (Critical) — REQUIRED INTENT-level case per workflow-step-3 rules; replays #250's own newest,
highest-severity comment: gate reported `idle=true (Infinity)` while `openclaw sessions --agent nova --active 240
--json` showed real Discord activity at 09:12 and 09:06 UTC (10-16 min prior) plus two I)ruid-triggered workflow
runs at 08:28/08:55 — running the 10 "actionable" steps would have interrupted an active human; a manual override
was required.
**Steps:** Reconstruct this exact session-activity fixture (real recent `updatedAt`/activity on a
discord-prefixed key) and run the fixed gate check against it.
**Expected:** The fixed gate correctly reports `idle=false` — this is the single most important regression test in
this file's #250 section, since it is reproducing a CONFIRMED wrong-answer incident, not a hypothetical.

### TC-250-004 — Genuinely idle session (last activity 5h+ ago, matching the 2026-10-12 comment's own correctly-idle case) still reports `idle=true`
**Priority:** P1 (Critical) — positive-case regression guard, so fail-CLOSED doesn't overcorrect into always-busy.
**Steps:** Reconstruct the 2026-10-12 comment's own fixture (last user-facing activity 06:43 UTC, ~5h prior).
**Expected:** `idle=true`, no error — matches the "gate got the right answer" outcome already observed, confirming
the new mechanism doesn't regress the true-idle case while fixing the false-idle one.

### TC-250-005 — Non-user-facing keys (cron, heartbeat, subagent) are excluded from the idle-activity filter
**Priority:** P1 (Critical) — direct test of the `discord|signal|telegram|slack` key-prefix filter described in
the 2026-10-12 comment; a heartbeat's OWN tick activity must not count as "recent user activity" and falsely mark
the agent as non-idle forever (a different failure mode than the documented false-idle bug, but a plausible
regression of the same fix).
**Steps:** Simulate recent activity ONLY on `agent:nova:heartbeat`/`agent:nova:cron:*`-prefixed keys, none on any
channel-prefixed key.
**Expected:** `idle=true` — heartbeat/cron/subagent activity alone does not suppress idle detection.

### TC-250-006 — Multiple concurrent channel keys with different recency — the MOST recent wins, not an arbitrary one
**Priority:** P2 (High) — correctness case for aggregating across `.sessions[]` entries.
**Steps:** Fixture with a stale Discord key (last activity 6h ago) and a fresh Slack key (last activity 2 min ago).
**Expected:** `idle=false` (driven by the freshest channel-prefixed entry, not the first one encountered or a
single hardcoded channel).

### TC-250-007 — Gate-check timeout value itself is adversarially tested (too-short timeout on a slow-but-working CLI call)
**Priority:** P2 (High) — adversarial boundary case for the "with a timeout" fix detail in the 2026-10-12 comment.
**Steps:** Simulate a CLI call that succeeds but takes longer than the configured timeout.
**Expected:** Treated identically to TC-250-002's timeout case (fail closed), not left ambiguous between "slow
success" and "hung failure" — confirm the implementation can't tell the difference and is this correctly
conservative, not more permissive than intended.

---

## 6. Open questions for the orchestrator / Project Leadership review

1. **Field-name discrepancy (§5 header note, blocks TC-250-001/003/004/006 from being written against a confirmed
   field name):** this dispatch says the gate-check field is `lastInteractionAt`; the live nova-workspace#250
   investigation comment (2026-10-12, empirically found) documents `.sessions[].updatedAt`. Confirming which is
   the actual 2026.9.x `openclaw sessions --json` field name (or whether both exist for different purposes)
   before implementation proceeds — test cases above use `updatedAt` per the empirically-documented source, but
   should be corrected if `lastInteractionAt` is in fact correct and `updatedAt` was a transitional/different field.
2. **TC-714-004's isolatedSession + single-session-key interaction:** flagged as plausible-but-unconfirmed — would
   benefit from an explicit design note (not just a passing test) on how OpenClaw's automation/session model
   reconciles "one session KEY for all heartbeat-triggered work" with "isolatedSession: true = fresh session each
   run, no history," since these sound like they could be in tension depending on what "session" means at the
   implementation layer (session key vs. session generation/instance).
3. **TC-711-004's liveness alarm delivery channel** is not specified in #711's own text ("add a liveness check that
   alarms") — confirming whether this goes to #proactive-mode (consistent with #714's unification) or a distinct
   ops/alerting channel.
4. **TC-711-006's de-duplication cadence** (once vs. daily vs. every-tick-until-resolved) is a judgment call not
   specified in #711 — confirming intended behavior before finalizing that test's exact assertion.
5. **TC-711-010's disposition for the 9 pre-existing pending work_queue rows** is not addressed in either #711 or
   #251's text — confirming whether this is explicitly in scope for the sweeper-retirement PR or a separate,
   already-tracked cleanup.
