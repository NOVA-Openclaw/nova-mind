# Test Cases: Issue #397 — Script-Generated Daily Memory Log

**Repo:** NOVA-Openclaw/nova-mind
**Script under test:** `memory/scripts/generate-daily-log.py` (installed to `$WORKSPACE/scripts/` and `$HOME/.openclaw/scripts/` by `agent-install.sh`)
**Related:** task #160, lesson #282, 2026-07-04/05 introspection evidence (repeated same-day daily-log gaps), `GLOBAL/CRON_DESIGN.md` (DB writes/derivation belong in scripts, not agent prompts)
**Workflow:** Software Engineering (workflow_id=4), SE run #346, Step 3 (this document) → Step 6/8 (QA execution/validation)
**QA Lead:** Gem · **QA Executor:** Flint (per QA_DELEGATION.md — this doc defines cases; Flint executes)

**Status:** DRAFT — pending Project Leadership review. Do NOT commit; carried into the implementation branch by Coder.

---

## 0. Scope & Assumptions

This design assumes the solution as described in the issue's design comment (dated 2026-07-05):

- Python 3 script, `psycopg2`, `psycopg2.connect("")` empty-DSN pattern consistent with `memory-maintenance.py` — relies on `PG*` env vars (`PGHOST`, `PGDATABASE`, `PGUSER`) + `~/.pgpass`.
- **Two separate database connections are required**: `nova_memory` (workflow_runs, lessons, events, tasks) and `agent_chat` (agent_chat table) — per `GLOBAL/DATABASE_ACCESS.md`, these are distinct databases, not just distinct tables.
- HTML-comment marker scheme (`<!-- BEGIN GENERATED DAILY LOG ... -->` / `<!-- END GENERATED DAILY LOG -->`), replace-between-markers, atomic write via temp-file+rename.
- `--date YYYY-MM-DD` backfill flag; default target day is "today" — **must be UTC** per multi-agent, multi-timezone posture (existing daily logs are UTC-dated, e.g. `2026-07-05.md`, and all timestamps inside them are UTC).
- Cron entries (nightly + intraday) installed via `agent-install.sh`, idempotent (grep-check before append).
- No hardcoded paths; `$OPENCLAW_WORKSPACE` → `$HOME/.openclaw/workspace-<agent>` → `$HOME/.openclaw/workspace` fallback chain; no symlink traversal (`~/clawd`, `~/workspace` are deprecated per `FILE_ACCESS.md`).
- "Key cron results" section is **descoped in this pass** — no `cron_results` table exists in the schema (confirmed: solution design section 8, item 3). The script must degrade gracefully (log a note / emit an explanatory placeholder / omit the section entirely) rather than error or emit misleading empty-but-labeled content.

Where the solution design leaves an open question, the corresponding test case block states the question and marks the expected behavior as **[NEEDS DECISION]** so Flint can flag divergence during execution rather than silently assume.

---

## 1. Happy Path

### TC-001: Fresh day, no existing file, DB has activity in all sections
**Preconditions:** Target date has no `memory/YYYY-MM-DD.md` file. `nova_memory` has ≥1 row in `workflow_runs`, `lessons`, `events`, `tasks` for the target date. `agent_chat` has ≥1 row for the target date.
**Input:** `generate-daily-log.py` (no args, run on the target date == today UTC)
**Expected:**
- File created at `$OPENCLAW_WORKSPACE/memory/YYYY-MM-DD.md`.
- File starts with `# YYYY-MM-DD` header.
- Generated block present, delimited by `BEGIN`/`END` markers, contains non-empty subsections for agent_chat activity, workflow_runs, lessons, events, tasks.
- `generated_at` timestamp in the BEGIN marker comment is current UTC time, ISO-8601.
- Exit code 0.

### TC-002: Existing file with prior generated block, new DB activity since last run
**Preconditions:** File exists with a valid generated block from an earlier run today. New rows have since been added to `nova_memory`/`agent_chat` for today.
**Input:** Re-run script (no args).
**Expected:** Content between markers is replaced with the updated counts/items reflecting all activity up to run time. Content outside markers (if any) unchanged. `generated_at` updates to new run time.

### TC-003: All sections populated, counts and top-N items match DB state exactly
**Preconditions:** Seed known row counts (e.g., 5 workflow_runs, 3 lessons, 7 tasks, 12 agent_chat messages) for target date in a scratch/staging DB.
**Input:** Run script against staging DB.
**Expected:** Every count in the generated block matches the seeded count exactly. Top-N items (if the design caps display, e.g. "top 5 lessons") match the actual top-N by the documented ordering (see TC-014 for ordering ambiguity).

---

## 2. Edge Cases — File & Content State

### TC-004: Empty day — zero DB activity across all sections
**Preconditions:** Target date has zero rows in all source tables (workflow_runs, lessons, events, tasks, agent_chat).
**Input:** Run script for that date.
**Expected:** Script does NOT error. Generated block is created with each section explicitly showing zero/none (e.g., "No workflow runs recorded" or "0 items") rather than being silently omitted — omission would be indistinguishable from a bug. Exit code 0.

### TC-005: File absent entirely (first-ever run for a date)
**Preconditions:** No file at all for target date (covered lightly in TC-001; this case explicitly tests the "no `# YYYY-MM-DD` header exists yet" path in isolation).
**Input:** Run script.
**Expected:** File created with header + generated block. No crash on "file not found" — this is the expected creation path, not an error path.

### TC-006: File exists with agent narrative ABOVE the markers, no narrative below
**Preconditions:** File has `# YYYY-MM-DD` header, then hand-written narrative sections (e.g., "## Heartbeat 02:18 UTC — ..."), then the generated block at the end.
**Input:** Re-run script.
**Expected:** Narrative above the markers preserved byte-for-byte (including exact whitespace/line endings). Only the marker-delimited region changes.

### TC-007: File exists with agent narrative BELOW the markers
**Preconditions:** Generated block is NOT at the end of the file — narrative sections were appended by an agent after a previous script run (this is a realistic scenario: agents append `## ...` sections after the file already has a generated block, per real 2026-07-04/05 logs which show generated-style and narrative content interleaved).
**Input:** Re-run script.
**Expected:** Content below `END` marker preserved byte-for-byte. Only content between `BEGIN`/`END` is touched. This is the highest-risk case for a naive "truncate everything after BEGIN" implementation — must be explicitly verified.

### TC-008: File exists with narrative both above AND below the markers
**Preconditions:** Combination of TC-006 + TC-007.
**Input:** Re-run script.
**Expected:** Both narrative regions preserved byte-for-byte; only the marker interior changes.

### TC-009: Markers present but malformed — BEGIN without matching END
**Preconditions:** File has a `BEGIN GENERATED DAILY LOG` marker but no corresponding `END GENERATED DAILY LOG` marker anywhere after it (e.g., manually truncated file, or a previous crashed run).
**Input:** Run script.
**Expected:** Script does NOT blindly overwrite to end-of-file (which would risk destroying any narrative that follows an unrelated stray comment matching BEGIN). Script detects the malformed state, **does not write**, and exits non-zero with a clear error message identifying the problem and the file path. This must be a hard-fail, not a silent best-effort guess.

### TC-010: Markers present but malformed — END without matching BEGIN
**Preconditions:** File has an `END GENERATED DAILY LOG` marker with no preceding `BEGIN` marker in the file.
**Input:** Run script.
**Expected:** Same as TC-009 — hard-fail, non-zero exit, clear diagnostic, no write attempted.

### TC-011: Duplicate markers — two BEGIN/END pairs in the same file
**Preconditions:** File has two complete `BEGIN...END` blocks (this is the exact failure mode already observed and manually fixed on 2026-07-05: "blind-lane duplicate write... duplicated the first 16 lines... Deduped (70→54 lines) before tonight's embedding run could ingest duplicates" — see 06:25 UTC introspection entry in `memory/2026-07-05.md`).
**Input:** Run script.
**Expected:** Script detects >1 marker pair and hard-fails with a diagnostic identifying both marker locations (line numbers), rather than silently updating the first/last pair and leaving a duplicate, or silently merging them. Non-zero exit, no write. This is a **regression-class test** — the exact bug class that already occurred once in production must be explicitly guarded against.

### TC-012: Markers entirely absent, file has only narrative content
**Preconditions:** File exists (e.g., manually created before this script existed, or narrative-only day) with no markers at all.
**Input:** Run script.
**Expected:** Per solution design item 3: generated block is appended at the end of the file with a leading blank line, preserving all existing narrative untouched above it. Exit code 0.

### TC-013: File contains only whitespace/empty after header
**Preconditions:** File has `# YYYY-MM-DD` header and nothing else (e.g., zero-byte body).
**Input:** Run script.
**Expected:** Generated block appended cleanly with correct spacing (no double-blank-lines, no missing blank line before the block).

### TC-014: [NEEDS DECISION] Top-N item selection ordering is ambiguous
**Context:** Solution design open question #3 — "notable threads" for agent_chat isn't defined (top-N by count vs. specific agent involvement). This is a design gap, not purely a test gap.
**Test approach once resolved:** Seed agent_chat rows with a clear, deterministic top-N by whatever criterion is chosen (e.g., message count per sender/recipient pair), assert the generated section lists exactly those N in the documented order.
**Flag to Project Leadership:** This must be resolved before Step 6 (test execution) — otherwise TC-014 has no fixed expected-output to assert against.

---

## 3. Error Conditions

### TC-015: `nova_memory` DB unreachable, `agent_chat` DB reachable
**Preconditions:** Simulate `nova_memory` connection failure (wrong host/port, or DB stopped) while `agent_chat` is reachable.
**Input:** Run script.
**Expected:** Script does not crash with an unhandled traceback. Behavior must be one of (documented, and asserted per whichever is chosen):
  (a) full hard-fail, non-zero exit, no partial write, OR
  (b) partial-degrade: agent_chat section populated, nova_memory-sourced sections explicitly marked "unavailable — DB connection failed" rather than silently empty/omitted.
**[NEEDS DECISION]** — solution design does not specify partial-vs-full-fail behavior. Recommend hard-fail (no partial write) to avoid a generated block that silently under-reports activity as if it were a real zero-count day (this directly avoids reproducing the "empty day" vs "DB down" ambiguity called out in TC-004). Flag to Project Leadership for explicit ruling.

### TC-016: `agent_chat` DB unreachable, `nova_memory` reachable
**Preconditions:** Inverse of TC-015 — `agent_chat` connection fails, `nova_memory` succeeds.
**Input:** Run script.
**Expected:** Same policy as TC-015 applied symmetrically. This case is called out explicitly in the task brief because `agent_chat` is a **separate database** from `nova_memory` (post-#320 migration/cutover, per 2026-07-05 log's SE Run #334 mention) — a naive implementation might only handle one connection's failure path and not the other. Both connection attempts must be tested independently, not just "DB down" as a single generic case.

### TC-017: Both databases unreachable
**Preconditions:** Neither `nova_memory` nor `agent_chat` reachable.
**Input:** Run script.
**Expected:** Clean non-zero exit with a clear error identifying both failures. No partial file write, no traceback dump to stdout (should be a caught, logged error — this runs under cron and needs parseable log output per `$HOME/.openclaw/logs/generate-daily-log.log`).

### TC-018: `$OPENCLAW_WORKSPACE` unset, no fallback resolvable
**Preconditions:** `$OPENCLAW_WORKSPACE` env var unset. `$HOME/.openclaw/workspace-<agent>` and `$HOME/.openclaw/workspace` both absent (contrived — but must be tested since it's the terminal fallback failure).
**Input:** Run script.
**Expected:** Clear error identifying that no workspace path could be resolved, listing which paths were tried. Non-zero exit. No attempt to write to a hardcoded `/home/nova/...` path — this would violate multi-tenant path hygiene (`FILE_ACCESS.md`).

### TC-019: `$OPENCLAW_WORKSPACE` unset, fallback to `$HOME/.openclaw/workspace-<agent>` succeeds
**Preconditions:** `$OPENCLAW_WORKSPACE` unset, but `$HOME/.openclaw/workspace-<agent>` exists (matches this very subagent's environment, e.g. `workspace-gem`, `workspace-coder`).
**Input:** Run script.
**Expected:** Script resolves to the fallback path and proceeds normally. Verifies the fallback chain actually works, not just that it's documented.

### TC-020: `$OPENCLAW_WORKSPACE` unset, only `$HOME/.openclaw/workspace` (no per-agent suffix) exists
**Preconditions:** Only the base `$HOME/.openclaw/workspace` exists, no `-<agent>` variant.
**Input:** Run script.
**Expected:** Script resolves to the base path (final fallback tier) and proceeds normally.

### TC-021: Malformed `--date` argument
**Preconditions:** `--date` given a non-ISO value (e.g., `07/05/2026`, `2026-13-45`, `today`, empty string).
**Input:** Run script with each malformed value.
**Expected:** Argparse-level or explicit validation rejects the value with a clear usage error, non-zero exit, no DB connection attempted, no file write.

### TC-022: `--date` in the future
**Preconditions:** `--date` set to a date after "today" (UTC).
**Input:** Run script.
**Expected:** [NEEDS DECISION] — either (a) rejected as invalid (no meaningful DB activity can exist for a future date) or (b) allowed and produces an empty-day-style output per TC-004 rules. Recommend (a): reject with a clear message, since a future-dated generated block risks confusing downstream consumers (daily report, introspection). Flag to Project Leadership.

### TC-023: Permission denied writing to target directory
**Preconditions:** `memory/` directory (or its parent) is not writable by the running user (e.g., wrong ownership, read-only mount in a sandboxed test).
**Input:** Run script.
**Expected:** Clear I/O error surfaced, non-zero exit, no partial/corrupt file left behind (verifies the atomic temp-file+rename never partially applies — if temp-file creation itself fails, nothing changes; if temp-file succeeds but rename fails, the original file is untouched).

---

## 4. Boundary Values — Dates, Timezones, Backfill

### TC-024: Backfill a single known-missing day from the May 14–28 gap window (lesson #282)
**Preconditions:** Target a date within the documented May gap window that has real DB history (workflow_runs/tasks/lessons exist for that date) but no `memory/YYYY-MM-DD.md` file, per the acceptance criterion in the issue body.
**Input:** `generate-daily-log.py --date 2026-05-15` (or whichever specific date from the gap window has verifiable DB rows).
**Expected:** Produces a plausible, well-formed log for that historical date, matching the same structural rules as TC-001. This is an explicit acceptance criterion from the issue — must be run against real historical data, not just synthetic seed data.

### TC-025: Backfill a day that already has a manually-written file (no generated block yet)
**Preconditions:** A historical date has a `memory/YYYY-MM-DD.md` written entirely by hand (pre-dates this script), no markers.
**Input:** `--date` targeting that historical file.
**Expected:** Same append-at-end behavior as TC-012, applied to a backfill target rather than "today." Confirms backfill mode doesn't bypass the marker-detection logic used in the default-day path.

### TC-026: Backfill a day that is today minus exactly one full day boundary (23:59:59 UTC → 00:00:00 UTC transition)
**Preconditions:** Seed a `workflow_runs` row with `started_at` at `YYYY-MM-DD 23:59:59.999 UTC` and another at `(YYYY-MM-DD+1) 00:00:00.000 UTC`.
**Input:** Run for `--date YYYY-MM-DD`.
**Expected:** The 23:59:59.999 row is included; the 00:00:00.000 row of the next day is excluded. Verifies the day-window query uses a half-open interval (`>= day_start AND < day_start + interval '1 day'`) rather than a lossy `::date` cast that could double-count or miscount rows near midnight, especially for timestamp columns with sub-second precision.

### TC-027: Midnight-boundary row exactly at `00:00:00.000 UTC` for the target date
**Preconditions:** Seed a row with a timestamp exactly at `YYYY-MM-DD 00:00:00.000 UTC`.
**Input:** Run for that date.
**Expected:** Row is included in that date's section (inclusive lower bound).

### TC-028: Default (no `--date`) run captures "today" using UTC, not local/server timezone
**Preconditions:** If test host's system timezone is non-UTC (verify via `date` / `timedatectl`), seed rows near a local-midnight-but-not-UTC-midnight boundary.
**Input:** Run script without `--date` at a time where local-day and UTC-day disagree (e.g., host in a negative UTC offset between local midnight and UTC midnight).
**Expected:** Script computes "today" as UTC today (matching existing daily log naming convention, which is UTC-dated per real files like `2026-07-05.md` with UTC timestamps throughout). File is written/updated for the UTC date, not the host's local date. This is a boundary condition worth an explicit test because Python's `datetime.now()` without `tz=timezone.utc` is a classic silent-bug source.

### TC-029: `--date` value with different calendar-month/year boundaries (e.g., last day of a month, Dec 31 → Jan 1, leap-day Feb 29)
**Preconditions:** Seed rows around a month/year boundary.
**Input:** `--date` set to the last day of a month; separately, `--date 2028-02-29` (verify leap-year date parsing doesn't error) if leap year is within reasonable backfill range, otherwise test Python `datetime` module's native rejection of non-leap Feb 29.
**Expected:** Date parsing and window queries behave correctly across month/year/leap-year boundaries — no off-by-one errors from naive string date arithmetic.

---

## 5. Idempotency

### TC-030: Re-run with zero new DB activity since last run — byte-identical output
**Preconditions:** Run script once, capture file checksum. No DB changes occur. Run again.
**Expected:** Second run's file is byte-for-byte identical to the first (including `generated_at` timestamp — this implies the design's "skip write if new block is identical to existing" rule (solution design section 3, rule 5) must diff CONTENT excluding the `generated_at` line, otherwise every run "changes" the file trivially via the timestamp alone and the no-op guarantee is meaningless).
**Expected (clarified):** File mtime is NOT updated on the second run (no write occurs at all) OR, if the timestamp is intentionally always refreshed, this must be a documented exception — **flag as [NEEDS DECISION]**: does "no-op" mean (a) no file write happens at all when content is unchanged sans-timestamp, or (b) the timestamp always updates but section content is identical? Recommend (a) for true idempotency and to avoid needless mtime churn on every cron tick.

### TC-031: Re-run replaces ONLY the marker-delimited region, never touches content outside
**Preconditions:** Covered by TC-006/007/008 individually; this is the consolidated idempotency-specific assertion: run the full cycle — create → add narrative manually (above and below) → re-run three times in a row.
**Expected:** After 3 re-runs, narrative content is still byte-for-byte identical to what was manually added after run 1. Only the generated block content changes (and only if underlying DB data changed between runs).

### TC-032: Atomic write — simulated crash mid-write does not corrupt the file
**Preconditions:** Inject a fault (e.g., kill the process, or mock `os.rename` to raise) after the temp file is written but before/during the rename step.
**Expected:** Original file is left completely intact (untouched) if the crash occurs before rename completes. No `.tmp` file is left in a state where the real file is partially overwritten. Verifies "write to temp file in same directory, fsync, then atomic rename" (solution design rule 4) is actually implemented as a true atomic swap (`os.replace`/`os.rename` on the same filesystem), not a copy-then-truncate.

### TC-033: Temp file is created in the SAME directory as the target (not `/tmp`)
**Preconditions:** Inspect the implementation (or instrument via a filesystem monitor / strace) during a run.
**Expected:** Temp file path is a sibling of the target file (e.g., `memory/.YYYY-MM-DD.md.tmp12345`), guaranteeing the final rename is atomic (same filesystem/device) and never crosses a mount boundary. This also matters for secrets hygiene conventions in this repo (staging files should not land in world-readable `/tmp`) — verify temp file permissions match the final file's expected mode (not world-readable/writable).

### TC-034: Narrative preservation is byte-for-byte, including trailing whitespace, non-ASCII characters, and mixed line endings
**Preconditions:** Manually insert narrative containing trailing spaces on some lines, an emoji or non-ASCII character (e.g., "✅", "→", em-dashes — all of which appear routinely in real daily logs), and confirm the file's existing line-ending convention (should be `\n`, verify no `\r\n` gets introduced).
**Input:** Re-run script.
**Expected:** Every byte of the narrative-preserved region is unchanged, including whitespace and encoding. This directly guards against subtle corruption where a naive line-based reassembly (e.g., `'\n'.join(lines)`) silently normalizes line endings or drops trailing whitespace.

### TC-035: Idempotency across a backfill re-run identical to a default-day re-run
**Preconditions:** Run `--date <yesterday's-date>` twice in a row with no intervening DB changes.
**Expected:** Same no-op behavior as TC-030, confirming backfill mode isn't a separate code path with different idempotency guarantees.

---

## 6. Domain-Specific Scenarios

### TC-036: Multi-tenant path resolution — no symlink traversal
**Preconditions:** Confirm `~/clawd` and `~/workspace` symlinks exist on the test host (per `FILE_ACCESS.md`, these are deprecated but still present for back-compat).
**Input:** Run script normally (with `$OPENCLAW_WORKSPACE` set correctly).
**Expected:** Resolved real path used for all file operations does not traverse either deprecated symlink — verify via `os.path.realpath()` comparison or by checking the script's source does not reference `~/clawd` or `~/workspace` anywhere (static check) AND the actual file write lands at the canonical path, not through the symlink.

### TC-037: Multi-tenant — script run as a different OS user resolves to that user's own `$HOME`-derived paths
**Preconditions:** Run the script under two different agent unix users (or simulate via distinct `$HOME`/`$OPENCLAW_WORKSPACE` env overrides in a subshell) with distinct workspace directories.
**Expected:** Each run writes to its own user's workspace, never cross-writes to another agent's `memory/` directory. No hardcoded `/home/nova` anywhere in the script (static grep check as part of test execution).

### TC-038: PGPASSWORD explicitly dropped from `os.environ` before connecting (regression test for Hermes Jun 10–14 incident)
**Preconditions:** Set `PGPASSWORD` in the test environment to a deliberately WRONG value (simulating the exact failure mode from `DATABASE_ACCESS.md`'s incident history — gateway-inherited PGPASSWORD overriding `.pgpass`).
**Input:** Run script with `PGPASSWORD` set to garbage in the parent environment.
**Expected:** Script connects successfully using `.pgpass`-resolved credentials for the correct per-agent DB user — NOT the garbage `PGPASSWORD` value. This requires explicit assertion that the script actually pops/deletes `PGPASSWORD` from `os.environ` (or equivalently launches `psycopg2.connect()` with an environment dict that excludes it) before any connection attempt. **This must be a dedicated, isolated test — not just inferred from other tests passing** — because a false-positive pass (e.g., test environment happens not to have PGPASSWORD set at all) would hide the exact bug class that caused a 4-day production incident.
**Verification approach:** Instrument via `os.environ` inspection at the point of connection (e.g., monkey-patch `psycopg2.connect` in a unit test to assert `PGPASSWORD not in os.environ` at call time), plus an integration-level test with a real wrong `PGPASSWORD` in the environment confirming successful connection (proving `.pgpass` won).

### TC-039: PGPASSWORD absent from environment entirely — baseline/control case
**Preconditions:** Ensure `PGPASSWORD` is unset (control for TC-038).
**Input:** Run script.
**Expected:** Connects successfully via `.pgpass` as normal. This is the control that TC-038 is differentiated against.

### TC-040: Script never writes/exports PGPASSWORD anywhere (static + runtime check)
**Preconditions:** Static grep of script source for `PGPASSWORD` — should only appear in the explicit-removal logic, never in an assignment/export/subprocess-env-passing context that could leak it further.
**Expected:** No code path sets, exports, or forwards `PGPASSWORD` to child processes or log output.

### TC-041: `agent-install.sh` cron installation — fresh install, no existing entry
**Preconditions:** Test user's crontab has no `generate-daily-log.py` entry.
**Input:** Run `agent-install.sh` (or its relevant cron-install section, if testable in isolation).
**Expected:** `crontab -l` after install shows both the nightly and intraday `generate-daily-log.py` entries, each exactly once, with correct schedule expressions per the solution design (`5 0 * * *` nightly, `0 6,12,18 * * *` intraday).

### TC-042: `agent-install.sh` cron installation — idempotent re-run, entry already present
**Preconditions:** Crontab already contains the `generate-daily-log.py` entries from a prior install.
**Input:** Run `agent-install.sh` again.
**Expected:** `crontab -l` after the second install still shows exactly ONE copy of each entry — no duplication. This is the explicit "duplicate detection" requirement from the task brief; verifies the `grep -F` check documented in solution design section 7 actually prevents re-append.

### TC-043: `agent-install.sh` cron installation — malformed/partial existing entry
**Preconditions:** Crontab has a manually-edited or partial-match line referencing `generate-daily-log.py` that doesn't exactly match the expected entry (e.g., different schedule, or path).
**Input:** Run `agent-install.sh`.
**Expected:** [NEEDS DECISION] — does the installer's `grep -F` match on the full line (risking a duplicate append if any part of the entry changed, e.g., a path update) or just the script name (risking silently leaving a stale/wrong-schedule entry in place)? Flag to Project Leadership: recommend matching on script path/name (coarser) and emitting a warning if the matched line differs from the expected entry, rather than blind duplicate-avoidance that could paper over a schedule drift.

### TC-044: `agent-install.sh` cron installation — verification summary reporting
**Preconditions:** Run installer (fresh or idempotent re-run).
**Expected:** Per solution design section 7 ("Report installed/verified in the existing verification summary"), the installer's final output summary includes a line confirming cron installation/verification status for this script — testable by grepping installer stdout for the expected confirmation line.

### TC-045: "Key cron results" section — no `cron_results` table exists, script degrades gracefully
**Preconditions:** Confirm (via schema check) that no `cron_results` table exists in `nova_memory` (per solution design section 8, item 3 — explicitly confirmed absent).
**Input:** Run script normally.
**Expected:** Script does NOT attempt a query against a nonexistent table (which would throw a DB error and potentially abort the whole run). One of the following, whichever Project Leadership selects — **[NEEDS DECISION]**:
  (a) section omitted entirely from the generated block, OR
  (b) section present with an explicit placeholder note (e.g., "Cron results tracking not yet implemented — see nova-mind#397 discussion"), OR
  (c) section sourced from `agent_jobs`/log-parsing per solution design's fallback suggestion.
Regardless of which option is chosen, the critical assertion is: **no exception is raised, no partial/failed write occurs, and the rest of the generated block (agent_chat, workflow_runs, lessons, events, tasks) completes normally** even though this one subsection is degraded/absent. This must be tested as an isolated failure-containment case — one missing data source must not cascade into a total script failure.

### TC-046: "Key cron results" section — schema drift safety (table added later, script must not break either way)
**Preconditions:** N/A for initial implementation — documented as a forward-looking regression guard. If/when a `cron_results` (or `agent_jobs`-based) implementation lands in a follow-up, this test should be re-run to confirm no double-handling or stale assumptions linger from the "graceful omission" code path.
**Expected:** Flagged for future test-suite maintenance; not blocking for this issue's initial acceptance.

---

## 7. Cross-Cutting / Regression Guards

### TC-047: Script exit codes are consistent and cron-parseable
**Preconditions:** Run each error-condition test case (TC-015 through TC-023) and record exit codes.
**Expected:** All success paths return 0. All hard-fail paths return a non-zero code (consistent value or documented distinct codes per failure class) so cron logging (`>> generate-daily-log.log 2>&1`) and any future monitoring can distinguish success from failure programmatically.

### TC-048: Dry-run mode produces no file write
**Preconditions:** `--dry-run` flag (mentioned in solution design section 2).
**Input:** Run with `--dry-run` against a day with DB activity.
**Expected:** Generated block is printed to stdout, target file is NOT created/modified at all (verify via file absence or unchanged mtime/checksum if it pre-existed).

### TC-049: Concurrent runs (nightly cron + intraday cron overlap, or manual + cron overlap) do not corrupt the file
**Preconditions:** Simulate two script invocations for the same date starting near-simultaneously (e.g., background one process mid-write, launch a second).
**Expected:** Either a file locking mechanism prevents concurrent writes (second process waits or fails cleanly), or the atomic rename guarantees the file always reflects one complete run's output, never an interleaved/corrupted merge of two runs. At minimum: the resulting file must be well-formed (parseable, exactly one marker pair) after both processes complete — this directly guards against a TC-011-style duplicate-marker corruption arising from a race rather than a logic bug.

### TC-050: Generated block content is valid Markdown and renders without breaking the rest of the file
**Preconditions:** Any successful run.
**Expected:** No unescaped Markdown control characters that would break rendering of adjacent narrative sections (e.g., unbalanced code fences, stray `#` headers that could be mistaken for new day-boundary headers). Per `CHANNEL_FORMATTING.md` general principle, no decorative divider rows that could visually or syntactically collide with surrounding content.

---

## 8. Done-Criteria (Explicit, for Step 6/8 Sign-off)

A PR implementing this issue is QA-approved only when **all** of the following hold:

1. **All 50 test cases above executed** by Flint (QA Executor) with recorded pass/fail per `TESTING_STANDARDS.md` reporting conventions (JUnit-style or equivalent structured output).
2. **Zero S1/S2 defects open** per `DEFECT_MANAGEMENT.md` severity taxonomy. (Any file-corruption, DB-credential-leak, or data-loss finding is automatically S1.)
3. **TC-038 (PGPASSWORD drop) passes with an explicit wrong-value-in-environment integration test**, not merely absence-of-PGPASSWORD as a passing control. This is non-negotiable given the Hermes incident history.
4. **TC-011 (duplicate markers) and TC-009/TC-010 (malformed markers) all hard-fail safely** — no silent data loss or duplicate-write regression of the exact class already observed in production on 2026-07-05.
5. **TC-030/TC-031 (idempotency, byte-for-byte narrative preservation) pass** — verified via checksum comparison, not visual diff.
6. **TC-032/TC-033 (atomic write) pass** — verified via fault injection, not just "it worked in the happy path."
7. **TC-024 (real historical backfill from the May gap window) executed against actual DB history**, not synthetic data only — satisfies the issue's literal acceptance criterion.
8. **TC-041/TC-042 (cron install + idempotent re-install) pass against a real crontab** (in an isolated test user or container — never the production/staging crontab of a live agent).
9. **TC-045 (graceful degradation of the descoped cron-results section) passes** — confirmed no exception propagates and the rest of the generated block still completes.
10. **All [NEEDS DECISION] items (TC-014, TC-015/016 partial-fail policy, TC-022 future-date handling, TC-030 timestamp-vs-no-op semantics, TC-043 cron entry match granularity, TC-045 degradation mode) are resolved by Project Leadership BEFORE Step 6 test execution begins**, with the resolution recorded in this document (or an addendum) so Flint has a fixed expected-output to test against rather than executing against an ambiguous spec.
11. **Static checks pass:** no hardcoded `/home/nova` or agent-specific paths in the script; no `~/clawd`/`~/workspace` symlink references; no PGPASSWORD export/forward anywhere in source.
12. **Regression suite added** to the repo's ongoing test infra (not just this one-off design doc) per `COVERAGE_AND_REGRESSION.md` — at minimum, TC-011, TC-030, TC-032, and TC-038 should become permanent automated regression tests given their incident-derived origin.

---

## 9. Open Design Questions / Risks Requiring Project Leadership Ruling

These must be resolved before Step 6 (test execution) to avoid Flint executing against an ambiguous spec:

1. **[TC-014]** Definition of "notable threads" / top-N ordering for the agent_chat section — count-based? agent-specific? (Carried over from solution design's own open question #3.)
2. **[TC-015/TC-016]** Partial-DB-failure policy: hard-fail-everything vs. degrade-per-section. Recommend hard-fail for correctness (avoids silently under-reporting as a false "quiet day").
3. **[TC-022]** Future-dated `--date` handling: reject vs. allow-as-empty. Recommend reject.
4. **[TC-030]** Idempotency semantics for `generated_at`: does true no-op mean no write at all when content-sans-timestamp is unchanged, or does timestamp always refresh? Recommend no write at all for genuine idempotency.
5. **[TC-043]** Cron duplicate-detection granularity: match on script path only (coarse, risks masking schedule drift) vs. full-line match (precise, risks duplicate append on any minor entry change). Recommend script-path match + drift warning.
6. **[TC-045]** Descoped cron-results section: omit vs. placeholder-note vs. `agent_jobs`-sourced partial implementation. Any of these is acceptable but must be a deliberate choice, documented in the PR description, not an accidental side effect of a `try/except: pass`.
7. **Host-config blocker (from solution design item 2):** `.pgpass` currently lacks `agent_chat` entries for non-`nova` OS users. If this script is meant to run under cron as agents other than `nova`, this is a **prerequisite infrastructure fix**, not a code-level test gap — flagging so it isn't mistaken for a test failure when Flint executes TC-016/038 under a non-`nova` test identity. Recommend confirming with Project Leadership which OS user(s) this script will actually run as before finalizing TC-037/TC-038's execution environment.
8. **Cron-as-non-root re-introduction:** solution design item 4 notes `agent-install.sh` currently deliberately avoids installing cron entries; this issue reverses that. Recommend confirming whether this should be gated behind an opt-in flag (e.g., `--install-cron`) so operators without cron-appropriate `.pgpass` setups aren't broken by a default-on install. If gated, TC-041/042/043 need to target the flagged invocation, not a bare install.

---

## 10. Coverage Summary

| Area | TC Range | Count |
|---|---|---|
| Happy path | TC-001–003 | 3 |
| Edge cases (file/marker state) | TC-004–014 | 11 |
| Error conditions | TC-015–023 | 9 |
| Boundary values (dates/timezones) | TC-024–029 | 6 |
| Idempotency | TC-030–035 | 6 |
| Domain-specific (multi-tenant, PGPASSWORD, cron install, descoped section) | TC-036–046 | 11 |
| Cross-cutting/regression guards | TC-047–050 | 4 |
| **Total** | | **50** |

Done-criteria: **12** explicit items (Section 8).
Open design questions flagged: **8** (Section 9), 6 of which are direct [NEEDS DECISION] markers embedded in specific test cases (TC-014, TC-015/016, TC-022, TC-030, TC-043, TC-045).

---

## PL Review Addendum

**Source:** SE Run #346 — Step 4: Project Leadership Review of QA Test Design  
**File:** `~/.openclaw/workspace/se-runs/run-346-step4-pl-review.md`

This addendum contains the binding rulings (R1–R8) and two supplemental test cases (TC-051, TC-052) issued by Project Leadership. These rulings resolve the `[NEEDS DECISION]` items in the test design above and are binding for implementation (Step 5) and test execution (Step 6).

### Binding rulings

| # | Item | Ruling |
|---|---|---|
| R1 | **TC-014** — "notable threads" / top-N ordering for agent_chat | Top-5 senders by message count for the target day, ordered count DESC, sender ASC as tiebreak. Plus a single total-message count. No thread reconstruction in v1. |
| R2 | **TC-015/016** — partial-DB-failure policy | **Hard-fail.** Non-zero exit, no partial write, error identifies which connection failed. |
| R3 | **TC-022** — future-dated `--date` | **Reject** with clear error, non-zero exit, no DB connection. |
| R4 | **TC-030** — idempotency semantics vs `generated_at` | **Option (a): true no-op.** Compare new block vs existing block *excluding the `generated_at` line*; if identical, no write at all (mtime unchanged). |
| R5 | **TC-043** — cron duplicate-detection granularity | Match on **script path/name** (coarse). If a matched line differs from the expected entry, emit a warning in installer output but do not modify or append. |
| R6 | **TC-045** — descoped cron-results section | **Option (b): placeholder note** — section present with explicit text (e.g., "Cron results: not yet tracked — see nova-mind#397"). Must not be an accidental `try/except: pass`. |
| R7 | **§9.7** — `.pgpass` agent_chat entries for non-nova users | Script runs under cron **as the installing user's own crontab** (v1 deployment target: nova). TC-037 executes via env-override simulation; TC-038 executes as the real test user. The missing `.pgpass` agent_chat entries for other agent users is a **host-config prerequisite** for any future non-nova deployment — flagged to orchestrator, NOT a test failure. |
| R8 | **§9.8** — cron install default-on vs opt-in | **Default-on with a `--no-cron` opt-out flag** and a clear installer message when installing. TC-041/042/043 target the default invocation; TC-051 covers the opt-out. |

### Supplemental test cases

**TC-051: `--no-cron` opt-out flag (per ruling R8)**  
Preconditions: crontab has no generate-daily-log entries.  
Input: run `agent-install.sh --no-cron`.  
Expected: scripts still installed; `crontab -l` contains no generate-daily-log entries; installer summary explicitly reports cron installation skipped by flag.

**TC-052: postgres.json credential hygiene (locked design §5)**  
Static: script reads only host/port/database keys from `~/.openclaw/postgres.json`; no code path reads a password/secret field from it.  
Runtime: with a deliberately wrong password planted in a test copy of postgres.json (test fixture, never the live file), connection still succeeds via `.pgpass` — proving the password field is never consumed.

