# Test Cases — nova-mind Issue #561
## `completion-log-reconcile.py`: deterministic completion-side daily-log reconciliation for `work_queue` + `workflow_runs`

**SE Run:** #608, Step 3 (revised Step 4 — design-gate rulings incorporated)
**Issue:** nova-mind#561
**Design record:** nova-workspace#123 (Step-2 validation + design-gate decisions)
**Tracking task:** nova_memory #571
**Author:** Gem (QA Domain)
**Date:** 2026-08-08 (revised 2026-08-08 per Step-4 rulings)

---

## Overview

This document defines test cases for `completion-log-reconcile.py`: a deterministic,
LLM-free reconcile script that scans `work_queue` rows reaching `done`/`failed`/`stale`/
`cancelled` and `workflow_runs` rows reaching `completed`/`failed`/`cancelled`, and appends
exactly one completion line per row to the correct day's file under
`~/.openclaw/workspace/memory/YYYY-MM-DD.md`. Idempotency is enforced via a new
`completion_logged_at timestamptz` column on both tables (migration, pre-seeded at deploy
time for all already-closed rows), plus a two-phase append/commit sequence (file-grep
pre-check → append → set watermark) since a file write and a Postgres transaction cannot
share one atomic unit.

Issue #561 is pre-implementation. These test cases define what "done" looks like for
Coder's implementation and are written to be executable once the script/migration land
(pytest for script logic with a live/staging DB fixture per the `generate-daily-log.py`
precedent, plus pgTAP-style catalog checks for the migration and manual crontab/installer
verification steps).

**Step-4 design-gate note:** `generate-daily-log.py` is also modified as part of #561
(small, surgical, in scope) to take the same shared advisory lock
(`flock` on `~/.openclaw/workspace/memory/.daily-log.lock`) around its own
read/modify/rename critical section, so the two scripts cannot race on the same file.
All ambiguities raised in the original (Step 3) version of this document were resolved at
the Step 4 design gate; see the **Design-Gate Rulings** section (formerly "Ambiguities")
for the authoritative decisions each affected test case below now encodes.

## Definition of Done

The feature is done when:

1. `completion_logged_at timestamptz` exists on both `work_queue` and `workflow_runs`
   (migration file in `memory/migrations/`, `IF NOT EXISTS`, named/no anonymous
   constraints, `COMMENT ON COLUMN` documenting idempotency semantics), and the same
   migration pre-seeds `completion_logged_at = COALESCE(completed_at, now())` for every
   already-closed row so the historical backlog is never re-scanned.
2. `completion-log-reconcile.py` lives in `memory/scripts/` and is deployed by
   `agent-install.sh`'s existing `SCRIPTS_SOURCE` copy loop (no new installer surface).
3. Every `work_queue` row reaching `done`/`failed`/`stale`/`cancelled` AND every
   `workflow_runs` row reaching `completed`/`failed`/`cancelled` produces exactly one
   completion line, dated by the row's own completion timestamp (UTC) — not by
   script-run time.
4. Re-running the script produces zero duplicate lines under any interleaving of
   crashes, midnight boundaries, or concurrent invocations — enforced by a two-phase
   append/commit sequence (grep pre-check → append → set watermark) plus a shared
   `flock` against `generate-daily-log.py`.
5. Rows in `pending`/`running`/`paused` never produce a line.
6. Sanitization collapses all whitespace runs (including embedded newlines) in
   `description`/`trigger_context` to single spaces and truncates to a fixed length cap
   (120 chars + `…` for `work_queue`/`workflow_runs` description text; ~80 chars where
   `trigger_context` is separately specified) so no single row can produce a multi-line
   or unbounded-length completion entry. No Markdown-character escaping is performed
   (out of scope per design-gate ruling).
7. The migration's initial deploy does not flood the log with years of historical
   completions — enforced by the migration-seeded watermark in item 1 (no lookback
   window needed).
8. Failure modes (missing log directory, permission errors, unreachable DB, concurrent
   writer collision with `generate-daily-log.py`'s 00:05/06:00/12:00/18:00 cron) degrade
   safely: no partial line writes, no silently-lost completions, clear non-zero exit +
   logged error. Concurrent-writer collision is prevented deterministically by both
   scripts holding a shared `flock` on `~/.openclaw/workspace/memory/.daily-log.lock`
   around their read/write/rename critical sections.

---

## Area 1 — Happy Path (Format & Correctness)

### TC-561-01: Single closed `work_queue` row produces exactly one correctly formatted line
**Objective:** Confirm baseline format matches the issue spec:
`- HH:MM wq#<id> closed (<kind>): <description> — <status>`.
**Preconditions:** Fresh test DB row: `work_queue` id=N, kind='subagent_session',
status='done', description='Dispatched voice-profile drafter', completed_at='2026-08-08
14:32:07+00', `completion_logged_at IS NULL`. Target daily-log file for 2026-08-08 does
not yet contain this line.
**Steps:** Run `completion-log-reconcile.py` (or its `reconcile` mode/entry point) against
the test DB with a lookback window covering this row.
**Expected:** Exactly one new line appended:
`- 14:32 wq#N closed (subagent_session): Dispatched voice-profile drafter — done`
in `~/.openclaw/workspace/memory/2026-08-08.md`. `work_queue.completion_logged_at` is now
set to a non-null timestamp (script-run time, not row-completion time — see TC-561-02 for
the distinction this implies).
**Pass Criteria:** Line content byte-for-byte matches the format string with real values
substituted; exactly one row in `work_queue` has `completion_logged_at` newly populated;
no other daily-log file was touched.

### TC-561-02: Single completed `workflow_runs` row produces exactly one correctly formatted line
**Objective:** Confirm the second line format:
`- HH:MM workflow run #<id> <status> (workflow <workflow_id>): <trigger_context first ~80 chars>`.
**Preconditions:** `workflow_runs` id=M, workflow_id=30, status='completed',
trigger_context='Weekly Music Publication run, promoting Old Carbon (doom jazz) through
release pipeline end to end', completed_at='2026-08-08 22:18:03+00',
`completion_logged_at IS NULL`.
**Steps:** Run reconcile.
**Expected:** Exactly one new line in `2026-08-08.md`:
`- 22:18 workflow run #M completed (workflow 30): Weekly Music Publication run, promoting
Old Carbon (doom jazz) through re…` — per design-gate ruling 4, `trigger_context` uses its
separately-specified ~80-char cut (hard cut, no word-boundary respect required) with a
trailing `…` appended when truncated.
**Pass Criteria:** Line present; `trigger_context` truncated to exactly 80 chars of
content followed by `…` when the source exceeds 80 chars, verbatim (no truncation marker)
when the source is ≤80 chars; `completion_logged_at` set.

### TC-561-03: `completion_logged_at` is set to append-decision time, not row-completion time [clarify semantics]
**Objective:** Distinguish the *dating* of the log line (row's `completed_at`, UTC) from
the *idempotency watermark* (`completion_logged_at`, set when the script runs).
**Steps:** Seed a row with `completed_at` = 3 days before the script run. Run reconcile.
**Expected:** The log line lands in the file for the date matching `completed_at` (3 days
ago), NOT today's file. `completion_logged_at` is set to today (run time).
**Pass Criteria:** Line appears in the historically-correct file; watermark column reflects
processing time. This test also validates the reconcile script can append to a
**non-current** day's file (backfill-safe write path), which is load-bearing for
midnight-boundary and outage-recovery scenarios below.

### TC-561-04: Multiple rows across both tables in one run — correct grouping and ordering
**Objective:** Confirm a single invocation handles N `work_queue` + M `workflow_runs` rows
without cross-contamination, and that lines within a day are ordered by completion time
(matching existing daily-log bullet convention of chronological entries).
**Preconditions:** 3 `work_queue` rows and 2 `workflow_runs` rows, all completing on the
same UTC date at different times, none previously logged.
**Steps:** Run reconcile once.
**Expected:** 5 new lines total, one per row, each with the correct id/table-specific
format, chronologically ordered by completion timestamp within the file (ordering was not
ruled on explicitly at the Step 4 design gate; treat append-order == chronological-order
as the expected behavior since a single reconcile pass naturally processes rows in
timestamp order per its SELECT ... ORDER BY completion-watermark — flag to Coder if the
implementation instead appends in id-order or table-order, which would violate this).
**Pass Criteria:** 5 lines, no duplicates, no cross-table field bleed (e.g. a `wq#`
formatted line never shows `workflow_id`).

---

## Area 2 — Idempotency

### TC-561-05: Re-run with no new closures is a true no-op
**Objective:** Confirm a second invocation with zero newly-closed rows makes zero writes.
**Steps:** Run reconcile once (TC-561-01 state), assert file mtime/content. Run reconcile
again immediately with no new closures.
**Expected:** File content and mtime unchanged after the second run (matches the
`generate-daily-log.py` `test_idempotent_noop` precedent — no-op writes must not touch the
file at all, not just "produce identical content via rewrite").
**Pass Criteria:** File mtime identical before/after second run; zero new DB writes
(`completion_logged_at` values for already-logged rows unchanged).

### TC-561-06: Re-run after a row is already logged does not duplicate
**Objective:** The core idempotency guarantee: `completion_logged_at IS NOT NULL` rows are
excluded from the scan, full stop.
**Steps:** Log a row (TC-561-01). Manually re-trigger reconcile 5 times in immediate
succession.
**Expected:** Exactly one line for that row exists in the file after all 5 runs.
**Pass Criteria:** `grep -c "wq#N closed"` on the target file == 1 after 5 reruns.

### TC-561-07: Two-phase append/commit — normal path (grep pre-check → append → set watermark)
**Objective:** Verify the design-gate-ruled two-phase sequence (ruling 1) on the normal,
no-fault path: (a) grep the target date's file (current day file; see TC-561-07b for the
adjacent-day check) for the row's marker (`wq#<id> closed` / `run#<id> <status>`) BEFORE
appending, (b) append the line, (c) set `completion_logged_at` only AFTER the append
succeeds.
**Preconditions:** Row is closed and eligible; target file does not yet contain the row's
marker.
**Steps:** Run reconcile with instrumentation/mocks confirming call order: grep-check
fires before the file write, and the DB `UPDATE ... SET completion_logged_at` fires only
after the file write returns successfully (not before, not concurrently).
**Expected:** Call order is exactly grep → append → commit. Line appears exactly once.
`completion_logged_at` is set only after the append is confirmed durable.
**Pass Criteria:** Instrumented call order matches grep→append→commit; `completion_logged_at`
non-null after a successful run; line count 1.

### TC-561-07b: Two-phase pre-check greps both the current AND adjacent day's file
**Objective:** Ruling 1's pre-check must cover the midnight-boundary case — a crash-
recovered retry of a row whose completion date sits right at a day boundary must grep
both the target day's file and the adjacent day's file (whichever direction the boundary
could have pushed a previous attempt), not just the currently-computed target file.
**Preconditions:** Row's completion timestamp is `23:59:50 UTC`; a prior (crashed) run
already appended the marker line into that day's file but crashed before setting
`completion_logged_at`; script is now re-run at `00:00:05 UTC` the next day (a naive
re-computation of "today's file" could target the wrong day if the implementation
recomputes the target date from current wall-clock rather than the row's own
`completed_at`).
**Steps:** Run reconcile.
**Expected:** Pre-check greps the file keyed by the row's OWN `completed_at` date (not
wall-clock "today"), finds the existing marker, and skips appending — proceeds directly to
setting `completion_logged_at`.
**Pass Criteria:** No duplicate line is appended; `completion_logged_at` becomes non-null;
exactly one marker line exists for the row across both candidate files.

### TC-561-08: Interrupted run — crash between append and watermark commit is recovered by the pre-check
**Objective:** Verify ruling 1's stated recovery property directly: "crash between (b) and
(c) is recovered by the pre-check on the next run — the residual risk is zero duplicate
lines, at worst one redundant grep."
**Preconditions:** Fault-inject a process kill/exception immediately after the file append
succeeds (line durably written) but before the `UPDATE ... SET completion_logged_at`
commits.
**Steps:** Run reconcile once (crashes mid-way per the fault injection). Confirm the line
exists in the file but `completion_logged_at IS NULL`. Run reconcile again (normal,
un-faulted second invocation).
**Expected:** Second run's grep pre-check finds the existing marker line for this row,
concludes it was already appended, and sets `completion_logged_at` WITHOUT appending a
second line.
**Pass Criteria:** Exactly one line for the row exists in the file after both runs;
`completion_logged_at` is non-null after the second run; the second run's redundant grep
is the only "cost" of the crash (no duplicate append, no lost completion). This closes
what was previously flagged as an open ambiguity — ruling 1 makes this deterministic, not
empirical.

### TC-561-09: Concurrent invocations (two reconcile processes racing on the same row)
**Objective:** Guard against double-append from overlapping cron/manual invocations
(e.g. a manual run overlapping the scheduled sweeper-triggered run), using the same shared
advisory lock mandated by design-gate ruling 8 for the `generate-daily-log.py` race.
**Steps:** Launch two reconcile processes simultaneously against the same DB state with
overlapping eligible rows (inject an artificial delay in one process between its grep
pre-check and its append to widen the race window).
**Expected:** Both processes contend for the same `flock` on
`~/.openclaw/workspace/memory/.daily-log.lock`; one blocks until the other releases,
so grep-check/append/commit critical sections never interleave. The two-phase
pre-check/append/commit sequence (TC-561-07/08) additionally means even a lock-free
second attempt (e.g. if flock acquisition itself has a bug) would self-correct via the
grep pre-check — defense in depth, not a substitute for the lock.
**Pass Criteria:** Exactly one line per row after both processes complete; no interleaved/
corrupted file content (no half-written lines); a flock-contention probe (e.g. attempt a
non-blocking `flock` on the same lock file while a reconcile run holds it) confirms the
lock is actually held during the critical section, not merely intended.

---

## Area 3 — Midnight Boundary

### TC-561-10: Row completes 23:59 UTC, script runs 00:02 next day → line lands in the completion-date file
**Objective:** Exact scenario from the task brief.
**Preconditions:** `work_queue` row, `completed_at = '2026-08-08 23:59:30+00'`. Script
invoked at `2026-08-09 00:02:15+00` (simulate wall-clock via mock/injectable clock, not
real sleep).
**Expected:** Line appended to `2026-08-08.md` (the row's completion date), NOT
`2026-08-09.md`.
**Pass Criteria:** `2026-08-08.md` contains the line; `2026-08-09.md` either does not exist
yet or does not contain this line.

### TC-561-11: Row completes 00:00:00 UTC exactly (midnight instant, BVA boundary)
**Objective:** Boundary Value Analysis on the exact midnight instant.
**Preconditions:** `completed_at = '2026-08-09 00:00:00.000000+00'` exactly.
**Steps:** Run reconcile.
**Expected:** Line lands in `2026-08-09.md` (the date component of an exact-midnight
timestamp is that day, not the prior day — standard `date()` truncation semantics, but
worth an explicit boundary test since off-by-one date arithmetic is a classic bug here).
**Pass Criteria:** Line in `2026-08-09.md`; absent from `2026-08-08.md`.

### TC-561-12: Row completes 23:59:59.999999 UTC (one microsecond before midnight)
**Objective:** Complementary BVA boundary at the other edge.
**Steps:** `completed_at = '2026-08-08 23:59:59.999999+00'`. Run reconcile at any later
time.
**Expected:** Line lands in `2026-08-08.md`.
**Pass Criteria:** Line present in `2026-08-08.md`, absent from `2026-08-09.md`.

### TC-561-13: Script never runs until 2 days after a midnight-boundary completion — backfill still lands correctly
**Objective:** Confirm no time-decay/lookback-window logic accidentally drops old rows or
misdates them once the "current day" concept has moved on twice.
**Preconditions:** Row completes 2026-08-08 23:58 UTC; reconcile does not run again until
2026-08-10 (simulate an outage/cron gap).
**Steps:** Run reconcile once on 2026-08-10.
**Expected:** Line correctly appended to `2026-08-08.md` (creating the file if needed, per
Area 8), not `2026-08-10.md`.
**Pass Criteria:** Correct historical file gets the line; no line in the run-date's file
for this row.

---

## Area 4 — Missing `completed_at` (Watermark Fallback)

### TC-561-14: `work_queue` failed row with NULL `completed_at`, non-NULL `last_checked_at` uses COALESCE fallback
**Objective:** Verify the documented watermark: `COALESCE(completed_at, last_checked_at)`.
**Preconditions:** `work_queue` row id, status='failed', `completed_at IS NULL`,
`last_checked_at = '2026-08-07 12:20:10+00'` (matches real production shape confirmed in
live data — e.g. row #485).
**Steps:** Run reconcile.
**Expected:** Row is scanned (eligible) using `last_checked_at` as the effective
completion timestamp; line dated 2026-08-07, using that timestamp for both the file
selection AND the `HH:MM` in the line text.
**Pass Criteria:** Line appears in `2026-08-07.md` with `12:20` as the time; row's
`completion_logged_at` gets set.

### TC-561-15: `work_queue` row with `completed_at` AND `last_checked_at` NULL falls back to `created_at`
**Objective:** Confirmed live-data case: row id=175, status='failed', both timestamp
columns NULL (`created_at` is the only populated time value). Per design-gate ruling 2,
the watermark chain is now `COALESCE(completed_at, last_checked_at, created_at)`.
**Preconditions:** Seed exactly this shape (`completed_at IS NULL`, `last_checked_at IS
NULL`, `created_at = '2026-07-30 00:59:29+00'`, matching live row #175).
**Steps:** Run reconcile.
**Expected:** Row is scanned (eligible) using `created_at` as the effective completion
timestamp; line dated 2026-07-30 with `00:59` as the `HH:MM`.
**Pass Criteria:** Line appears in `2026-07-30.md` with `00:59` as the time;
`completion_logged_at` gets set.

### TC-561-15b: `work_queue` row with ALL THREE of `completed_at`/`last_checked_at`/`created_at` NULL is skipped with a stderr warning
**Objective:** Verify the terminal fallback behavior from ruling 2: "If somehow all three
are NULL, skip the row and emit a stderr warning (do not crash, do not append)." Note
`created_at` has a `NOT NULL DEFAULT now()` constraint in the live schema, so this case is
unreachable via normal inserts — test it as a defensive/negative-space guard (e.g. via
direct fault injection at the Python layer bypassing the DB constraint, or a mocked row
object) rather than a real seedable DB row.
**Steps:** Simulate a row object with all three timestamp fields NULL passed through the
reconcile logic (unit-test level, not integration).
**Expected:** No line is appended for this row. No exception propagates (script does not
crash). A warning is written to stderr identifying the row (table + id).
**Pass Criteria:** Zero lines appended for the row; script continues processing remaining
rows in the batch; stderr contains an identifiable warning; script's overall exit code
reflects that a row was skipped (non-zero, or zero with the warning surfaced — whichever
the implementation documents, but silence is not acceptable).

### TC-561-16: `workflow_runs` row without `completed_at` falls back to `started_at` (live data: run #80)
**Objective:** Per design-gate ruling 3, `workflow_runs` uses
`COALESCE(completed_at, started_at)` (accepted as originally recommended — `started_at`
is `NOT NULL` on this table, so no further fallback tier is needed and no all-NULL
skip case is reachable for `workflow_runs`).
**Preconditions:** Reproduce the exact live anomaly: `workflow_runs` id=80,
status='completed', `completed_at IS NULL`, `started_at = '2026-06-11 07:04:28+00'`.
**Steps:** Run reconcile.
**Expected:** Row is scanned (eligible) using `started_at` as the effective completion
timestamp; line dated 2026-06-11 with `07:04` as the `HH:MM`.
**Pass Criteria:** Line appears in `2026-06-11.md` with `07:04` as the time;
`completion_logged_at` gets set. Since `started_at` is `NOT NULL`, no skip/warning path
is reachable or needs testing for this table.

### TC-561-17: `workflow_runs` paused/running rows are correctly excluded even with old `started_at`
**Objective:** Negative-space check against BVA neighbor of TC-561-16 — confirm the
NULL-completed_at fallback logic does NOT accidentally make `paused`/`running` rows
eligible (they have NULL `completed_at` too, but must never log).
**Preconditions:** `workflow_runs` id, status='paused', `started_at` = 3 weeks ago,
`completed_at IS NULL`.
**Steps:** Run reconcile.
**Expected:** Zero lines produced for this row under any circumstance.
**Pass Criteria:** No line in any file referencing this row's id; `completion_logged_at`
remains NULL (correctly — it is not eligible, not "eligible but failed to log").

---

## Area 5 — Description / `trigger_context` Sanitization

**Design-gate ruling 5 scope note:** Sanitization is minimal — collapse all whitespace
runs (including embedded newlines) to single spaces. No Markdown-character escaping is
performed; pipes, backticks, and `#` characters inside the bullet's description text are
accepted as harmless in the daily log (they render as inline formatting or literal
characters within a `- ` bullet line, not as document-structure-breaking tokens, since
they do not appear at column 0 of the line once the fixed `- HH:MM ...` prefix precedes
them). TC-561-20 below is retargeted to test only the whitespace-collapse behavior;
markdown-escaping assertions from the original design are removed as out of scope.

### TC-561-18: Embedded newlines in `description` are collapsed to a single space
**Objective:** Confirm one DB row never produces a multi-line (structure-breaking)
completion entry, per ruling 5's "collapse all whitespace runs to single spaces."
**Preconditions:** `work_queue.description = "Dispatched subagent.\nExpect report at
tmp/foo.md.\n\nAlso check X."`.
**Steps:** Run reconcile.
**Expected:** Output line renders as:
`...: Dispatched subagent. Expect report at tmp/foo.md. Also check X. — <status>` — every
run of whitespace (single newline, double newline/blank-line, tabs if present) collapses
to exactly one space, producing exactly one line in the Markdown file.
**Pass Criteria:** The written line, when read back, is a single logical line (no
embedded `\n` inside the bullet); no double-spaces or stray blank-bullet lines from the
collapsed `\n\n`; no adjacent stray blank lines created in the file.

### TC-561-19: Very long description is truncated to 120 chars with a trailing `…`
**Objective:** Confirm the fixed length cap from ruling 4: 120 chars + trailing `…` for
both `work_queue.description` and `workflow_runs`-line description-equivalent text (the
separately-specified ~80-char `trigger_context` rule from TC-561-02 is unaffected by this
ruling and stays as-is).
**Preconditions:** `description` = 500 repeated 'x' characters.
**Steps:** Run reconcile.
**Expected:** Output line's description segment is exactly 120 characters of source
content followed by a single `…` character (121 total for the segment).
**Pass Criteria:** Description segment length is exactly 120 chars + `…` when source
exceeds 120 chars after whitespace-collapse; verbatim (no `…`) when source is ≤120 chars.
Add a BVA pair: source of exactly 120 chars (no `…`) and exactly 121 chars (120 chars +
`…`, one char dropped) to pin the exact boundary.

### TC-561-20: Markdown-structural characters (pipes, asterisks, backticks, `#`) are preserved verbatim, not escaped
**Objective:** Per ruling 5, confirm the sanitizer does NOT attempt Markdown-character
escaping — only whitespace-collapse (TC-561-18) and length-truncation (TC-561-19) are
applied. A description containing `#`, `|`, `` ` ``, or `*` mid-string is left untouched
aside from those two transforms.
**Preconditions:** `description = "Fixed # 42 | ran \`script.sh\` with **flag** set"`
(no leading `#`/`-` at the start of the string, since the fixed `- HH:MM wq#<id> closed
(<kind>): ` prefix always precedes the description text, making column-0 heading
injection structurally impossible regardless of description content).
**Steps:** Run reconcile.
**Expected:** The description segment in the output line is byte-for-byte identical to
the (whitespace-collapsed, length-permitting) source: `Fixed # 42 | ran \`script.sh\` with
**flag** set`. No characters are escaped, quoted, or stripped.
**Pass Criteria:** Exact substring match for the Markdown-structural characters in the
output line; test explicitly asserts these characters are NOT escaped (e.g. not converted
to `\#`, `\|`, etc.), confirming the minimal-sanitization ruling rather than the original
heading-injection hard-gate (superseded — the fixed line prefix makes that gate
unnecessary, since no description content can ever land at column 0 of a bullet line).

### TC-561-21: Non-ASCII / emoji in description are preserved (do not treat as hostile)
**Objective:** Confirm the sanitizer is targeted (structure-breaking chars only), not
overly aggressive (matches `generate-daily-log.py`'s `test_preserves_non_ascii_and_
whitespace` precedent — the ecosystem's existing convention is to preserve unicode
content in daily logs).
**Preconditions:** `description = "✅ Deploy complete → renaissancemachine.ai/music/"`.
**Steps:** Run reconcile.
**Expected:** Emoji and arrow characters preserved verbatim in the output line.
**Pass Criteria:** Byte-for-byte preservation of the unicode content (minus any
newline/length/heading sanitization applied elsewhere).

### TC-561-22: Empty-string description
**Objective:** BVA — `description` is NOT NULL per schema but could theoretically be
empty string (schema has no length check).
**Preconditions:** `description = ''`.
**Steps:** Run reconcile.
**Expected:** Line still produced with an empty (or clearly marked, e.g. `(no
description)`) description segment — does not crash, does not produce a malformed line
missing the ` — <status>` suffix.
**Pass Criteria:** Line present and well-formed; script exits 0.

---

## Area 6 — Status Coverage

### TC-561-23: `work_queue` — every terminal status logs; every non-terminal status does not [Decision Table]

| status | Expected in log? |
|---|---|
| `pending` | No |
| `done` | Yes |
| `failed` | Yes |
| `stale` | Yes — `— stale` |
| `cancelled` | Yes |

**Objective:** Per design-gate ruling 6: "In scope. Reconcile logs it as a closure:
`— stale`. The issue's status list was incomplete; the schema CHECK is authoritative."
**Steps:** One row per status value; run reconcile once.
**Expected:** `pending` produces no line. `done`/`failed`/`cancelled`/`stale` all produce
lines. The `stale` row's line uses the same format as the other statuses, e.g.
`- HH:MM wq#<id> closed (<kind>): <description> — stale`.
**Pass Criteria:** All four terminal statuses (`done`, `failed`, `stale`, `cancelled`)
each produce exactly one line with the correct status word in the ` — <status>` suffix;
`pending` produces zero lines. This decision table is now fully resolved — no cell is
left as "unresolved."

### TC-561-24: `workflow_runs` — every terminal status logs; `running`/`paused` do not [Decision Table]

| status | Expected in log? |
|---|---|
| `running` | No |
| `paused` | No |
| `completed` | Yes |
| `failed` | Yes |
| `cancelled` | Yes |

**Objective:** Confirm the full `workflow_runs_status_check` enum is covered, including
the `paused` value which live data confirms is a long-lived non-terminal state (16 rows,
all with NULL `completed_at`, per production sample) that must never log — including SE
runs paused for extended deploy-discussion escalation (e.g. SE #606, cited in the
2026-08-07 daily log as "correctly paused... workflow_runs status matches log").
**Steps:** One row per status; run reconcile once; separately confirm a `paused` row that
later transitions to `completed` (simulate the transition, re-run reconcile) DOES log
exactly once, at the point of transition, not at the pause point.
**Pass Criteria:** `running`/`paused` never appear in any log file at any point while in
that state; the eventual terminal transition produces exactly one line, dated by that
transition's `completed_at`.

### TC-561-25: Status transition mid-lookback-window (row was `pending` at last scan, `done` at this scan)
**Objective:** Confirm the scan correctly picks up newly-terminal rows without requiring
them to have been "seen" in a prior pending state — this is inherent to the watermark
design but worth an explicit regression test since it's the exact gap class the issue
exists to close (manual/non-sweeper closes that a purely event-driven design would miss).
**Steps:** Row created `pending`. Run reconcile (no line, as expected). Transition row to
`done` with `completed_at` set. Run reconcile again.
**Expected:** Exactly one line now appears.
**Pass Criteria:** Line count 0 after first run, 1 after second run, for this row.

---

## Area 7 — Migration & Backfill Guard

### TC-561-26: Migration adds `completion_logged_at` to both tables AND seeds the backfill watermark, idempotently
**Objective:** Standard migration hygiene per `TESTING_STANDARDS`/prior migration
precedent (`085_extraction_failures.sql` pattern: `IF NOT EXISTS`, named constraints,
`COMMENT ON COLUMN`) PLUS the design-gate ruling-7 backfill seed: the migration itself
sets `completion_logged_at = COALESCE(completed_at, now())` for every already-closed row
at deploy time.
**Steps:** Apply migration to a fresh copy of staging schema seeded with the real
production backlog shape (hundreds of historical closed rows, `completion_logged_at`
column not yet existing). Re-apply the same migration file a second time.
**Expected:** First apply: (a) adds `completion_logged_at timestamptz` (nullable, no
default — the column itself must have no `DEFAULT` clause, since the seeding is done via
a one-time `UPDATE` statement in the migration body, not a column default, which is the
only way to distinguish "seeded at deploy" rows from "never touched" rows going forward);
(b) seeds `completion_logged_at = COALESCE(completed_at, now())` for every row already in
a terminal status (`done`/`failed`/`stale`/`cancelled` for `work_queue`;
`completed`/`failed`/`cancelled` for `workflow_runs`) at migration time. Second apply is a
no-op for the column-add (already exists) AND must not re-run the seed `UPDATE` against
rows that already have `completion_logged_at` set (i.e. the seed `UPDATE` must include a
`WHERE completion_logged_at IS NULL` guard, or it would overwrite legitimately-NULL rows
that closed between the two migration applies with a stale re-seed value).
**Pass Criteria:** Column exists on both tables after first apply with `is_nullable='YES'`
and `column_default IS NULL`; every pre-existing terminal-status row has
`completion_logged_at` non-null immediately after first apply; second apply exits 0 with
no schema change and does not alter `completion_logged_at` on rows already seeded; a row
that transitions to terminal status BETWEEN the two migration applies still has
`completion_logged_at IS NULL` after the second apply (proving the guard works, not just
the happy path).

### TC-561-27: Backfill guard — migration-seeded watermark means zero new lines on first reconcile run
**Objective:** Per design-gate ruling 7: "Migration-seeded watermark — the migration sets
`completion_logged_at = COALESCE(completed_at, now())` for ALL already-closed rows at
deploy time, so reconcile only ever sees post-deploy closes. No lookback window needed."
Live data confirms 456 `work_queue` `done` rows and 537 `workflow_runs` `completed` rows
exist pre-migration — this test proves the seed neutralizes that entire backlog.
**Preconditions:** Apply the migration (TC-561-26) against the real production-shaped
backlog.
**Steps:** Immediately run reconcile in its normal (only) mode — there is no separate
backfill mode/flag per this ruling.
**Expected:** Reconcile's scan finds zero eligible rows (every terminal-status row already
has `completion_logged_at` set by the migration seed). Zero lines appended to any
daily-log file.
**Pass Criteria:** Zero new lines in any file post-migration-and-first-reconcile-run
against the ~1000-row backlog; reconcile exits 0 (a zero-eligible-rows run is a normal
successful no-op, not an error).

### TC-561-28: A row that closes AFTER migration deploy is NOT swept up by the seed and IS logged normally
**Objective:** Confirm the seed's `WHERE completion_logged_at IS NULL` boundary correctly
distinguishes pre-deploy backlog (seeded, skip) from post-deploy closures (unseeded,
eligible) — the BVA companion to TC-561-27, replacing the now-moot lookback-window
boundary test (ruling 7 eliminates the lookback-window design entirely).
**Preconditions:** Apply the migration. Immediately after, close a `work_queue` row
(`status='done'`, `completed_at = now()`) — this row did not exist in terminal status at
migration time, so the seed `UPDATE` never touched it and its `completion_logged_at`
remains NULL.
**Steps:** Run reconcile.
**Expected:** This row IS logged (exactly one line, correct format); the pre-existing
backlog remains untouched (zero additional lines, confirming TC-561-27 still holds
alongside a genuinely-new closure in the same run).
**Pass Criteria:** Exactly one new line (for the post-deploy row); zero lines for any
backlog row; the total line count added by this run equals 1, not 1 + backlog size.

---

## Area 8 — Domain Interactions & Failure Modes

### TC-561-29: Target daily-log file does not exist — script creates it
**Objective:** Confirm reconcile can create a new day's file (not just append to an
existing one) — needed for backfill/midnight-boundary/outage-recovery scenarios where the
target date's file was never generated (e.g. `generate-daily-log.py`'s own cron hasn't run
yet for that day, or ran before this completion existed).
**Preconditions:** Row completes on a date with no existing `YYYY-MM-DD.md` file.
**Steps:** Run reconcile.
**Expected:** File is created with, at minimum, a title line (`# YYYY-MM-DD`) and the
completion bullet — matching `generate-daily-log.py`'s `update_file` "creates new file"
convention (title + content), so the two scripts produce mutually-compatible file shapes.
**Pass Criteria:** New file exists, starts with `# YYYY-MM-DD\n`, contains the line.

### TC-561-30: Target directory does not exist at all (fresh install, no `memory/` dir yet)
**Objective:** BVA one level up from TC-561-29 — the whole workspace memory directory is
absent.
**Preconditions:** `~/.openclaw/workspace/memory/` does not exist.
**Steps:** Run reconcile with an eligible row.
**Expected:** Directory is created (matching `resolve_workspace()`/directory-creation
conventions elsewhere in the memory/scripts ecosystem) OR the script fails loudly with a
clear error if directory auto-creation is intentionally out of scope — **either is
acceptable, but silent failure (exit 0, no file, no error) is not.**
**Pass Criteria:** Either the file is created (directory included) or a non-zero exit
with a clear logged error occurs; no silent no-op.

### TC-561-31: File permission error on write
**Objective:** Confirm a permission-denied write fails safe (no partial file corruption,
clear error), consistent with the atomic-write pattern (write to temp, `os.replace`) that
means a failed write never touches the original file at all.
**Preconditions:** Target file exists and is read-only (chmod 444) or its parent
directory denies write.
**Steps:** Run reconcile.
**Expected:** Script exits non-zero, logs a clear permission error including the target
path. Original file content is byte-for-byte unchanged (verifiable since the atomic
temp-write-then-rename never got to modify the original). `completion_logged_at` for the
affected row(s) remains NULL — consistent with the append-first, commit-second ordering
required in TC-561-07.
**Pass Criteria:** Non-zero exit; original file untouched; no watermark set for
unprocessed rows; no leftover `.tmp` file in the directory (cleanup on failure, matching
`generate-daily-log.py`'s `test_atomic_write_does_not_corrupt_on_rename_fault` precedent).

### TC-561-32: Concurrent append vs. the nightly `generate-daily-log.py` embed pipeline — shared flock verification
**Objective:** Per design-gate ruling 8, the race between `completion-log-reconcile.py`'s
append and `generate-daily-log.py`'s 00:05/06:00/12:00/18:00 UTC marker-block
read-modify-rename cycle is closed deterministically, not probabilistically: both scripts
take a shared advisory lock (`flock` on
`~/.openclaw/workspace/memory/.daily-log.lock`) around their entire read/write/rename
critical section. Adding this `flock` call to `generate-daily-log.py` is in scope for
#561 (small, surgical addition alongside the reconcile script itself). This retargets the
test from empirical race-probing to deterministic lock-contention verification.
**Preconditions:** Both scripts' lock-acquisition code paths are in place
(`generate-daily-log.py` modified per this issue to also take the lock).
**Steps:**
1. **Lock-held verification:** Start a reconcile run with an injected delay while it holds
   the lock mid-critical-section. From a second process, attempt a non-blocking `flock`
   (`flock -n`) on the same lock file. Assert the second attempt fails to acquire (proving
   the lock is genuinely held, not just present-but-unused).
2. **Mutual exclusion verification:** Launch `completion-log-reconcile.py` and
   `generate-daily-log.py` simultaneously against the same target file, each with an
   injected delay inside its critical section. Assert (via timestamps/instrumentation)
   that the two critical sections never overlap in wall-clock time — one fully completes
   (including its atomic rename) before the other's critical section begins.
3. **Content-correctness after serialized execution:** After both scripts complete (having
   waited on each other via the lock), verify the resulting file contains BOTH the
   generated marker block's expected content AND the completion line(s) reconcile
   appended — with lock-enforced serialization, this is now a deterministic outcome of
   ordering, not a race.
4. **Stale-lock handling:** Kill a process while it holds the lock (simulate a crash mid
   critical-section, before releasing). Confirm a subsequent invocation of either script
   does not deadlock forever — either the OS releases the flock automatically on process
   death (standard `flock` semantics: the lock is tied to the file descriptor / process
   lifetime, so this should self-resolve) and the next invocation proceeds normally, or
   (if the implementation uses a different lock primitive) a documented staleness/timeout
   mechanism exists.
**Expected:** Lock genuinely enforces mutual exclusion (step 1 fails to acquire while
held); critical sections never overlap (step 2); content is correct post-serialization
(step 3); a crashed lock-holder does not permanently wedge the other script (step 4).
**Pass Criteria:** All four sub-checks pass. This closes what was previously flagged as an
open ambiguity requiring empirical race-probing — ruling 8 makes correctness a property of
the lock, verified by contention/ordering tests rather than by running many trials and
hoping to observe (or fail to observe) a race.

### TC-561-33: Database unreachable — fail safe, no partial writes
**Objective:** Confirm a DB connectivity failure at scan time never leaves the log file in
a half-written state and never marks rows as logged that weren't.
**Preconditions:** Point the script at an unreachable host/wrong port (matching the
`generate-daily-log.py` `DailyLogError` pattern for config/connection failures).
**Steps:** Run reconcile.
**Expected:** Script exits non-zero before touching any file (scan happens before any
write, so a DB failure at the scan stage means zero file writes attempted). If DB becomes
unreachable mid-run (after some rows already processed), already-written lines/watermarks
for prior rows in the same run remain correct (partial progress is acceptable; corrupted
state is not) and the run exits non-zero to signal incomplete work for the next cron tick.
**Pass Criteria:** No file corruption; no `completion_logged_at` set for rows that were
never actually appended; clear non-zero exit and logged connection error (respecting the
`PGPASSWORD`-drop convention from `GLOBAL/DATABASE_ACCESS` / the `generate-daily-log.py`
`TestConnectPGPASSWORD` precedent — this script must equally drop `PGPASSWORD` before
connecting).

### TC-561-34: DB reachable but write-permission denied on `completion_logged_at` column (wrong DB role)
**Objective:** Domain-ownership check — confirm the script runs as the correct DB role
(matching `work_queue`'s existing per-agent-write conventions) and fails clearly rather
than silently if invoked with insufficient grants.
**Steps:** Run the script's UPDATE step as a role without UPDATE grant on `work_queue`/
`workflow_runs`.
**Expected:** Clear permission-denied error surfaced; no file append occurs for that row
(the file-append-then-commit ordering from TC-561-07 means a failed commit must also mean
no durable append was allowed to "count" — though note this conflicts with pure
append-first ordering if the append already landed; this is exactly the TC-561-08 race
surface, and this test doubles as a real-world trigger for it).
**Pass Criteria:** Non-zero exit, clear error naming the permission issue; no duplicate or
orphaned state after a subsequent successful run with correct grants.

---

## Design-Gate Rulings (SE #608, Step 4 — 2026-08-08)

All 8 ambiguities flagged in the Step 3 version of this document were resolved at the
Step 4 design gate. Rulings below are authoritative; every affected test case in this
document has been revised to encode the ruling directly rather than describing an open
question.

1. **Append/commit ordering (affects TC-561-07/07b/08/09).** No atomic file+DB unit
   exists. Adopted the standard two-phase pattern: (a) file-grep pre-check for
   `wq#<id> closed` / `run#<id> completed`-style marker (current + adjacent day), (b)
   append, (c) set `completion_logged_at` only AFTER a successful append. A crash between
   (b) and (c) is recovered by the pre-check on the next run — residual risk is zero
   duplicate lines, at worst one redundant grep.

2. **`work_queue` triple-fallback watermark (affects TC-561-15/15b).** Fall back to
   `created_at` as a third COALESCE arm:
   `COALESCE(completed_at, last_checked_at, created_at)`. If somehow all three are NULL
   (structurally unreachable given `created_at NOT NULL DEFAULT now()`, but guarded
   defensively), skip the row and emit a stderr warning — do not crash, do not append.

3. **`workflow_runs` fallback (affects TC-561-16).**
   `COALESCE(completed_at, started_at)` — QA's original recommendation accepted as-is.
   `started_at` is `NOT NULL`, so no further fallback tier or skip path is reachable.

4. **Description length cap (affects TC-561-02/19).** Truncate to 120 chars with a
   trailing `…` for both tables' description text. `trigger_context`'s separately-
   specified ~80-char rule (TC-561-02) is unaffected and stays as its own cut.

5. **Sanitization scope (affects TC-561-18/19/20).** Minimal: collapse all whitespace
   runs (including newlines) to single spaces. No Markdown escaping — pipes, backticks,
   `#` inside a bullet line are harmless in the daily log given the fixed `- HH:MM ...`
   line prefix makes column-0 heading injection structurally impossible. Only the
   newline-collapse behavior is tested.

6. **`stale` status (affects TC-561-23).** In scope. Reconcile logs it as a closure:
   `— stale`. The issue's status list was incomplete; the schema CHECK constraint is
   authoritative (all 4 terminal `work_queue` statuses — `done`/`failed`/`stale`/
   `cancelled` — now log).

7. **Backfill flood-guard (affects TC-561-26/27/28).** Migration-seeded watermark: the
   migration sets `completion_logged_at = COALESCE(completed_at, now())` for ALL
   already-closed rows at deploy time (guarded by `WHERE completion_logged_at IS NULL` on
   re-apply), so reconcile only ever sees post-deploy closes. No lookback-window design is
   needed; the previously-planned TC-561-28 lookback-boundary test is replaced with a
   pre-deploy-vs-post-deploy boundary test instead.

8. **Concurrency race with `generate-daily-log.py` (affects TC-561-32).** Confirmed real
   (QA's finding that `generate-daily-log.py`'s actual code uses read-modify-atomic-rename,
   not the "O_APPEND is sufficient" assumption from the original nova-workspace#123
   discussion, was accepted as correct and load-bearing). Resolution is deterministic
   closure, not empirical probing: both writers take a shared advisory lock (`flock` on
   `~/.openclaw/workspace/memory/.daily-log.lock`) around their read/write/rename critical
   sections. Adding the `flock` call to `generate-daily-log.py` is in scope for #561 as a
   small, surgical change. TC-561-32 is retargeted to verify lock contention/mutual
   exclusion rather than probing for the race empirically.

---

## Test Execution Notes for Coder / Flint

- Follow the `tests/test_generate_daily_log.py` precedent for harness shape: pytest,
  `importlib.util.spec_from_file_location` to load the script as a module without
  requiring it to be installed, `@pytest.mark.integration` for live-DB tests, `tmp_path`
  + `monkeypatch.setenv("OPENCLAW_WORKSPACE", ...)` for filesystem isolation.
- Live-DB integration tests MUST run against `nova_staging`, never production
  `nova_memory` (per global testing convention — see `test-append-run-note.sh`'s explicit
  refusal guard as the pattern to copy: refuse to run if the target DB name is
  `nova_memory` or `postgres`).
- Concurrency tests (TC-561-09, TC-561-32) require real subprocess/thread races with
  injected timing delays plus `flock -n` contention probes from a second process — a
  mocked test cannot verify a genuine advisory-lock/rename interaction.
- `generate-daily-log.py`'s test suite (`tests/test_generate_daily_log.py`) will need a
  companion update (new test class, e.g. `TestFlockAcquisition`) once the `flock` call
  (ruling 8) is added to that script — flag this to Coder as an in-scope, adjacent-file
  change for #561, not a separate issue.
- Case count: **36 test cases** (TC-561-01 through TC-561-34, plus TC-561-07b and
  TC-561-15b added during Step 4 revision) across 8 areas. All 8 spec ambiguities raised
  at Step 3 were resolved at the Step 4 design gate (see **Design-Gate Rulings** above);
  every affected test case now encodes a single unambiguous expected outcome rather than
  a "recommended default." No case in this document is currently blocked on an open
  design question.
