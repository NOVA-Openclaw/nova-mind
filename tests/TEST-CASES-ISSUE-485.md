# Test Cases — Issue #485: memory-extract hook stderr capture + extraction_failures dead-letter + replay

**QA Lead:** Gem | **SE Run:** #448, Step 3 | **Repo:** nova-mind
**Verified against:** main @ e4fa64d
**Scope:** `memory/hooks/memory-extract/handler.ts`, new migration `memory/migrations/085_extraction_failures.sql`,
new replay script `memory/scripts/` (name TBD by implementation, referenced here as `extraction-replay.sh`).

## Design Notes / Constraints Carried Forward From Step 2 Doc-Validation

These are load-bearing and every relevant test case below cites which constraint it verifies:

1. **C1 — ON CONFLICT DO NOTHING returns no id.** The existing transcript upsert (`INSERT INTO channel_transcripts ... ON CONFLICT (session_id, external_message_id) DO NOTHING RETURNING id`) returns empty when the row pre-exists, even though a valid row exists. Any dead-letter code path that needs `channel_transcript_id` must recover it (follow-up `SELECT id FROM channel_transcripts WHERE session_id = $1 AND external_message_id = $2`, or switch to `DO UPDATE ... RETURNING id`) BEFORE falling back to storing the raw body.
2. **C2 — FK delete semantics.** `channel_transcripts.session_id REFERENCES channel_sessions(id) ON DELETE CASCADE` (confirmed in migration 067). If `extraction_failures.channel_transcript_id` is a plain FK with default (or CASCADE) delete behavior, deleting a session transitively deletes transcripts, which would delete or orphan-block dead-letter rows — destroying the exact evidence the table exists to preserve. Fix requires `ON DELETE SET NULL` on `extraction_failures.channel_transcript_id`, with the row's own denormalized metadata (sender, timestamp, stderr tail, body fallback) retained independent of the FK.
3. **C3 — >64KB stderr pipe-stall.** Node child_process stdio pipes have a default OS pipe buffer (~64KB on Linux). If nothing reads a pipe, a child that writes past that watermark blocks on the write syscall. The fix must attach a `data` handler immediately (even if it only appends to a capped ring/tail buffer) so the pipe drains continuously regardless of buffer cap size.
4. **C4 — Replay cron correctness.** Must use `flock` (memory-catchup.sh, explicitly cited in the issue as lacking this — do not copy that flaw), source `env-loader.sh` + `pg-env.sh` (see `memory/lib/`), rate-limit rows processed per invocation, increment `retry_count`, and on success either delete the row or mark it resolved (spec doesn't mandate which — test both acceptable resolutions, implementation must pick one and be consistent).
5. **C5 — Migration idempotency.** `CREATE TABLE IF NOT EXISTS`, `TIMESTAMPTZ DEFAULT NOW()`, named indexes (not anonymous), `COMMENT ON TABLE`, CHECK constraints. Must be safe to run twice.
6. **C6 — Hook contract.** Handlers must not throw (docs/automation/hooks.md "Handle Errors Gracefully" — don't throw, let other handlers run). No hook-level timeout exists for `message:received`; the child-process timeout is entirely this fix's responsibility per issue notes.

---

## Group A — Happy Path

### TC-A1: Successful extraction writes no dead-letter row
- **Preconditions:** `extraction_failures` table exists (migration applied). Test message ≥10 chars, not a command, not a heartbeat.
- **Steps:** Trigger `message:received` event with a well-formed rawBody. Mock `extract_memories.py` (or real script against staging DB) to exit 0 with no stderr.
- **Inputs:** Valid message body, valid sender metadata, valid sessionKey.
- **Expected:** `child.on('close')` receives `code === 0`. `console.info` "Extraction complete" logged. No row inserted into `extraction_failures`. No stderr tail in log line (or empty-string tail field, implementation's choice — assert whichever it does, consistently).
- **Done when:** Row count in `extraction_failures` for this test's marker unchanged (0 before, 0 after). Log assertion passes.

### TC-A2: Successful extraction with non-empty stderr (warnings only, exit 0)
- **Preconditions:** Same as TC-A1.
- **Steps:** Mock child to write WARNING-level stderr (e.g. "WARNING: low confidence extraction") but exit 0.
- **Expected:** No dead-letter row (dead-letter is gated on `exitCode != 0`, not presence of stderr). Stderr tail MAY still be logged at info/debug level for visibility but must not be treated as failure.
- **Done when:** `extraction_failures` row count unchanged; process exits cleanly; no false-positive failure log.

---

## Group B — Failure Paths (Nonzero Exit / Spawn Error / Timeout / psql Failures)

### TC-B1: Nonzero exit code → dead-letter row written with stderr tail
- **Preconditions:** Migration applied. Existing `channel_transcripts` row NOT pre-created (first-time message, FK resolution happens in real time per handler's existing upsert logic).
- **Steps:** Mock/force `extract_memories.py` to exit 1 with stderr `"ERROR: Anthropic API request failed: 529"`.
- **Expected:**
  - `console.error` "Extraction failed" log line includes the stderr tail (not just `{sender, exitCode}` as today).
  - A row is inserted into `extraction_failures` with `exit_code = 1`, stderr tail populated, sender/session metadata populated, `retry_count = 0`.
  - Since this is first-time message (no pre-existing transcript), FK is populated with the transcript ID the handler's own upsert step resolved OR body fallback used if that resolution also failed (see TC-B6 for the compound-failure case).
- **Done when:** Row exists in `extraction_failures`, `stderr_tail` non-null and contains the literal error string, `exit_code = 1`.

### TC-B2: Spawn error (`child.on('error')`, e.g. ENOENT — python3 not found or script path missing)
- **Preconditions:** Point `scriptPath` at a nonexistent file, or PATH missing python3, in an isolated test env.
- **Steps:** Trigger hook; expect `spawn()` to emit `'error'` instead of ever reaching `'close'`.
- **Expected:** Handler does NOT throw (must satisfy C6). A dead-letter row is written on spawn error too — this is a failure mode distinct from nonzero exit but must not be silently dropped. `exit_code` column should encode "spawn error" distinctly (e.g. NULL exit_code + a `failure_reason` / `error_type` column, or a sentinel value — implementation must pick one, test asserts it's queryable/distinguishable from a normal nonzero exit).
- **Done when:** Row exists in `extraction_failures` distinguishable as a spawn-level failure (not conflated with a Python-side nonzero exit). Hook handler itself does not throw an unhandled exception up to the gateway.

### TC-B3: Child-process timeout kill produces a dead-letter row
- **Preconditions:** Mock `extract_memories.py` (or a test double script) to sleep/hang indefinitely without exiting and without writing enough stderr to trip C3's pipe-stall path — this isolates "hung child" from "pipe-stall hang."
- **Steps:** Trigger hook with the hanging test double. Wait for the fix's own timeout (per issue, no hook-level timeout exists; this is the fix's responsibility) to fire and kill the child.
- **Expected:** Child is killed (SIGTERM, escalating to SIGKILL if needed — verify implementation's grace period). `close` handler fires with a killed-by-signal indication (Node reports `code=null, signal='SIGTERM'` in this case, not a normal exit code). A dead-letter row is written with a failure reason indicating timeout, distinguishable from both TC-B1 and TC-B2.
- **Done when:** Process is confirmed terminated (no zombie/orphaned child left running — check `ps` for the PID post-test). `extraction_failures` row exists with timeout-specific reason. Test must have an upper wall-clock bound (fail the test itself if the timeout doesn't fire within e.g. timeout+5s grace).

### TC-B4: psql session-upsert catch — now logged (was `.catch(() => ({stdout:''}))`)
- **Preconditions:** Force the `channel_sessions` upsert psql call to fail (e.g. point at a nonexistent DB, revoke permission, or malformed SQL via a fault-injection test double).
- **Steps:** Trigger hook with conditions such that the session-upsert branch executes (no pre-existing `channelSessionId`).
- **Expected:** The catch no longer silently swallows to `{stdout:''}` — it must log the error (sender/session context + error message, per C6 "don't leak secrets" — assert the DB connection string/password is NOT in the log if psql surfaces one in its stderr). Handler continues gracefully (rawBody still gets passed to extract_memories.py; FK just won't resolve, which is expected/acceptable degraded behavior).
- **Done when:** A `console.error` or `console.warn` call is observed with the psql failure detail; log content does not include a bare Postgres connection string with embedded credentials; handler does not throw; extraction still proceeds (fail-open, not fail-closed, since this FK-resolution step is best-effort per existing comment "OpenClaw may populate these... lightweight upsert here").

### TC-B5: psql transcript-upsert catch — now logged (second silent catch)
- **Preconditions:** Session upsert succeeds; force the transcript-upsert psql call specifically to fail.
- **Steps:** Trigger hook such that `channelSessionId` resolves but the transcript INSERT fails (bad column, permission, or fault-injected).
- **Expected:** Same as TC-B4 but for the second call site. Both catches must be independently testable/verifiable as no longer using the bare `.catch(() => ({stdout: ''}))` pattern — grep-style regression check: `grep -n "catch(() => ({ stdout: ''" handler.ts` should return zero matches post-fix.
- **Done when:** Logged error observed for this specific call site; no credential leakage in log; extraction still proceeds with degraded FK.

### TC-B6: Compound failure — FK resolution AND extraction both fail → body fallback used
- **Preconditions:** Both psql catches trigger (TC-B4 + TC-B5 conditions) AND `extract_memories.py` also exits nonzero.
- **Steps:** Combine B4/B5 fault injection with a nonzero-exit extraction.
- **Expected:** Dead-letter row is written using the **body fallback** path (message body stored directly in `extraction_failures` since no `channel_transcript_id` could be obtained by any means). `channel_transcript_id` column is NULL; body/content column is populated with the actual message text (truncated/capped consistently with how `channel_transcripts.content` truncates at 65535 chars — verify same cap or documented deviation).
- **Done when:** Row exists with `channel_transcript_id IS NULL` and non-null body content matching the original test message.

---

## Group C — Boundary: stderr Cap & Buffer Behavior

### TC-C1: stderr exactly at cap (16384 bytes, assuming ~16KB = 16384)
- **Preconditions:** Confirm the exact cap constant used by implementation (issue says "~16KB" — get exact byte value from the diff before finalizing assertions; note as TBD-CONFIRM in review if ambiguous).
- **Steps:** Test double writes exactly N bytes of stderr (N = cap) then exits 1.
- **Expected:** Full N bytes retained in the tail buffer (no truncation marker needed, or an implementation-defined marker only appears when truncation actually occurred — assert no false truncation flag at exactly-cap).
- **Done when:** `stderr_tail` length equals the written content length (byte-for-byte at the boundary), no off-by-one drop of the first/last byte.

### TC-C2: stderr one byte over cap (cap+1 bytes)
- **Steps:** Test double writes cap+1 bytes, exits 1.
- **Expected:** Retained tail is exactly `cap` bytes long and is the **last** `cap` bytes written (i.e. sliding/ring-buffer semantics — the FIRST byte written is the one dropped, not the last). This is the core "last ~16KB" requirement from the issue.
- **Done when:** `stderr_tail` == `full_written_content[-cap:]` (Python slice semantics) exactly. Test asserts both the retained length and content equality against the expected slice, not just length.

### TC-C3: stderr far over cap (e.g. 5× cap, ~80KB) — no pipe stall
- **Steps:** Test double writes 80KB of stderr in one or more `write()` calls without waiting for the parent to read, then exits 1. Wrap the test in a wall-clock timeout well below what a pipe-stall hang would take (e.g. assert completion within 5s).
- **Expected:** Per C3, child completes and exits without hanging — proves the data handler drains the pipe continuously rather than only reading once at close. Retained tail is the last `cap` bytes.
- **Done when:** Test completes within its time bound (proves no stall); tail content correctness re-verified as in TC-C2.

### TC-C4: Empty stderr
- **Steps:** Test double exits nonzero with zero bytes written to stderr.
- **Expected:** Dead-letter row's `stderr_tail` is empty string or NULL (implementation's choice, must be consistent with how empty is represented elsewhere in the table) — NOT a crash, NOT `undefined` leaking into a log line as the literal string "undefined".
- **Done when:** Row written successfully; log line renders cleanly (no "undefined" or "[object Object]" artifacts).

### TC-C5: Huge stdout, no impact on stderr capture or dead-letter logic
- **Steps:** Test double writes 200KB to stdout (successful extraction output, exit 0) with normal-sized stderr.
- **Expected:** stdout is also capped/buffered (per issue point 1, "stderr/stdout tails") without pipe-stall on stdout either. Since exit code is 0, no dead-letter row regardless of stdout size.
- **Done when:** Process completes without hanging; no dead-letter row; if stdout tail is logged/stored anywhere, it's capped consistently with the stderr cap behavior (same cap size unless implementation documents an intentional difference).

### TC-C6: Both stderr AND stdout simultaneously over cap, interleaved writes
- **Steps:** Test double interleaves writes to both streams, each exceeding cap, then exits 1.
- **Expected:** Both tails independently capped/tailed correctly; no cross-contamination (stdout content must not appear in stderr_tail field or vice versa); no stall.
- **Done when:** Both tail fields correct and independently verifiable against known last-N-bytes-per-stream expectations.

---

## Group D — Domain-Specific: DB / FK / Replay / Migration

### TC-D1: [C1] Pre-existing transcript row + extraction failure → dead-letter carries FK, not fallback body
- **Preconditions:** Pre-insert a `channel_transcripts` row (and its parent `channel_sessions` row) for the exact `(session_id, external_message_id)` pair the test will replay, matching what the handler would independently attempt to upsert.
- **Steps:** Trigger the hook with a message that maps to this existing `(session, external_message_id)` pair such that the handler's own `INSERT ... ON CONFLICT DO NOTHING RETURNING id` returns no id (since the row already exists — this is the exact ON CONFLICT DO NOTHING gap). Force `extract_memories.py` to exit nonzero.
- **Expected:** The dead-letter write path must NOT fall back to storing the body. It must recover the real `channel_transcript_id` via a follow-up lookup (SELECT by session_id+external_message_id, or a DO UPDATE...RETURNING variant) and use that as the FK.
- **Done when:** `extraction_failures.channel_transcript_id` equals the pre-existing row's actual `id` (verified via direct `SELECT id FROM channel_transcripts WHERE ...`), and the body/fallback content column is NULL/empty (not populated, since FK resolution succeeded). This is the single most important regression case per the issue's explicit "Test this case explicitly" instruction.

### TC-D2: [C2] Deleting parent session cascades to transcripts but does not destroy/orphan-block dead-letter row
- **Preconditions:** Full chain exists: `channel_sessions` row → `channel_transcripts` row (FK cascade per migration 067) → `extraction_failures` row referencing the transcript.
- **Steps:** `DELETE FROM channel_sessions WHERE id = <test_session_id>;` (cascades to delete the `channel_transcripts` row per existing `ON DELETE CASCADE`).
- **Expected:** The `extraction_failures` row survives the delete. Its `channel_transcript_id` becomes NULL (via `ON DELETE SET NULL`, not blocked/errored, not itself deleted). Metadata needed to understand the failure (sender, stderr tail, original timestamp, body-fallback-if-applicable) remains intact on the surviving row independent of the now-null FK.
- **Done when:** Post-delete query on `extraction_failures` returns the row unchanged except `channel_transcript_id IS NULL`; delete statement itself does not raise an FK-violation error (which would happen if the column were plain `REFERENCES ... ` with default RESTRICT/NO ACTION and no explicit ON DELETE clause).

### TC-D3: [C5] Migration re-run is idempotent
- **Preconditions:** Fresh test DB, migration `085_extraction_failures.sql` not yet applied.
- **Steps:** Run the migration file twice in sequence (`psql -f 085_extraction_failures.sql` twice, or equivalent).
- **Expected:** Second run does not error (CREATE TABLE IF NOT EXISTS, named indexes with IF NOT EXISTS or safe re-create, no unguarded ALTER that would fail on re-run).
- **Done when:** Exit code 0 on both runs; table/index/constraint state identical after run 2 vs run 1 (row counts, `\d extraction_failures` output diff is empty).

### TC-D4: [C5] Migration schema conformance checklist
- **Preconditions:** Migration applied to clean test DB.
- **Steps:** Inspect `information_schema` / `\d+ extraction_failures`.
- **Expected — assert each individually:**
  - `id` is a PK (BIGSERIAL or equivalent).
  - Timestamp columns (`created_at` at minimum) are `TIMESTAMPTZ NOT NULL DEFAULT NOW()`.
  - `channel_transcript_id` FK references `channel_transcripts(id)` with `ON DELETE SET NULL`.
  - At least one CHECK constraint exists constraining a status/reason-type column to a known enum of values (mirroring the `blockers_status_check` / `blockers_source_type_check` pattern from migration 082) rather than an unconstrained free-text column.
  - Indexes are named explicitly (not anonymous) — e.g. `idx_extraction_failures_...` naming convention consistent with existing migrations.
  - `COMMENT ON TABLE extraction_failures IS ...` is present and non-empty.
- **Done when:** All six sub-assertions pass individually (report each as its own pass/fail, don't collapse to one boolean).

### TC-D5: [C4] Replay cron — overlapping-run protection (flock)
- **Preconditions:** At least one row in `extraction_failures` eligible for replay.
- **Steps:** Start the replay script once and hold it mid-execution (e.g. inject a sleep in a test double, or start it against a slow/blocked resource) while attempting to start a second concurrent invocation.
- **Expected:** The second invocation detects the lock (flock) and exits immediately without processing any rows or double-processing the same row.
- **Done when:** Only one invocation's worth of processing/log output for the given row set is observed; second invocation's log clearly indicates "lock held, exiting" (or equivalent) rather than silently doing nothing or erroring uninformatively. This directly regression-guards against the flaw the issue calls out in `memory-catchup.sh` (no flock).

### TC-D6: [C4] Replay of FK-based row vs body-fallback row
- **Preconditions:** One `extraction_failures` row with `channel_transcript_id` populated (FK case, from TC-D1-style setup) and one with body fallback populated (from TC-B6-style setup).
- **Steps:** Run replay script once with both rows eligible.
- **Expected:** For the FK row, replay reconstructs the message body by looking up `channel_transcripts.content` via the FK before calling `extract_memories.py` via stdin. For the body-fallback row, replay uses the stored body column directly. Both should invoke the extraction script the same way the hook does (stdin pipe, not argv — per existing "#155 never pass untrusted text as shell args" convention that must be preserved in the new script).
- **Done when:** Both rows are processed; a distinct assertion confirms the FK-row's body was sourced from `channel_transcripts.content` (not from a stale/absent local body field) and the fallback row's body matches its stored value byte-for-byte.

### TC-D7: [C4] Rate limiting per replay run
- **Preconditions:** More eligible `extraction_failures` rows exist than the per-run limit (check implementation's chosen limit; mirror memory-catchup.sh's pattern of "max N per run" unless the fix specifies otherwise).
- **Steps:** Seed N+several eligible rows; run replay once.
- **Expected:** Only up to the configured limit is processed in a single invocation; remaining rows are left untouched for a subsequent run (not partially mutated, not skipped permanently).
- **Done when:** Post-run row count processed == configured limit exactly (not less, not more); untouched rows retain original `retry_count`/state unchanged.

### TC-D8: [C4] retry_count increment and retry exhaustion behavior
- **Preconditions:** A dead-letter row with `retry_count` at some value below the exhaustion threshold; a second row already at (or one below) the max retry threshold.
- **Steps:** Run replay against both, with the underlying extraction continuing to fail both times (test double still returns nonzero) so neither succeeds.
- **Expected:** Both rows get `retry_count` incremented by exactly 1 per attempt. The row that reaches/exceeds the max threshold is NOT deleted and NOT retried again on a subsequent run — it should be marked in a terminal/exhausted state (distinct status value, not left ambiguously "still pending" alongside fresh failures) so operators can find truly-stuck rows.
- **Done when:** `retry_count` values match expected increments exactly; the exhausted row is distinguishable via its status/marker from rows still eligible for retry; a subsequent replay run does not attempt the exhausted row again (verify via log absence / row untouched on 2nd run).

### TC-D9: [C4] Successful replay — cleanup path
- **Preconditions:** A dead-letter row where the underlying issue has been resolved (test double now returns exit 0 for the same reconstructed input).
- **Steps:** Run replay.
- **Expected:** On success, the row is either deleted or marked resolved (implementation picks one — this test asserts whichever was chosen is applied consistently, and that a resolved/deleted row is excluded from all future replay-eligible queries).
- **Done when:** Row is absent from the "eligible for replay" result set post-run (whether via physical deletion or a status flag that the eligibility query filters on); if marked-resolved rather than deleted, a `resolved_at`-style timestamp or equivalent is populated.

### TC-D10: [C4] Replay script sources env-loader.sh + pg-env.sh correctly
- **Preconditions:** Clean shell environment without pre-sourced env vars (simulating a bare cron invocation).
- **Steps:** Invoke the replay script directly (not via an interactive shell with dotfiles already loaded).
- **Expected:** Script sources both `memory/lib/env-loader.sh` (or `~/.openclaw/lib/env-loader.sh`, matching the pattern in memory-catchup.sh) and `memory/lib/pg-env.sh` before attempting any psql or extract_memories.py invocation that needs API keys / PG connection info.
- **Done when:** Script succeeds in a stripped-down environment where these are the ONLY sources of required env vars (grep the script for the `source` lines as a static check; dynamic check: unset `ANTHROPIC_API_KEY`/PG vars in the test shell, confirm script still finds them via its own sourcing).

### TC-D11: [C6] Timeout-killed extraction produces dead-letter row with correct FK resolution path
- **Preconditions:** Same as TC-D1 (pre-existing transcript row) but combined with TC-B3's hang/timeout condition instead of a nonzero exit.
- **Steps:** Trigger hook against a message with a pre-existing transcript row; test double hangs past the timeout.
- **Expected:** Timeout kill path reuses the SAME FK-recovery logic as the nonzero-exit path (TC-D1) — i.e., dead-letter-on-timeout is not a separate/divergent code path that skips FK recovery and defaults straight to body fallback.
- **Done when:** `extraction_failures` row from the timeout case has `channel_transcript_id` populated correctly (not NULL, not body-fallback) when a resolvable transcript exists, exactly mirroring TC-D1's assertion.

### TC-D12: [C2, C4] Replay handles unreplayable rows (NULL FK + NULL body after cascade delete) deterministically
- **Preconditions:** Reproduce TC-D2's exact end state: an `extraction_failures` row that was originally FK-based (body column NULL/empty per TC-D1's assertion that body is only populated when FK resolution fails), then its parent session/transcript is deleted, cascading to `channel_transcript_id = NULL` on the dead-letter row while the body column remains NULL (never populated, since it wasn't needed at write time). This row is now unreplayable by construction — no FK to look up content through, no stored body to replay directly.
- **Steps:** Run the replay script with this row eligible (assuming it would otherwise match the eligibility query) alongside at least one normal replayable row (FK-intact or body-fallback) in the same batch.
- **Expected:**
  - Replay script detects the NULL-FK + NULL-body condition before attempting to reconstruct a message body, and does NOT crash or throw attempting a lookup against a NULL FK or attempting to pass NULL/empty content to `extract_memories.py` via stdin.
  - The row is marked in a terminal/unreplayable state distinct from both (a) still-eligible-for-retry and (b) retry-exhausted (TC-D8) — operators must be able to distinguish "ran out of retries but was theoretically replayable" from "was never replayable regardless of retries" (e.g. a dedicated status value such as `unreplayable` / `permanent_loss`, or equivalent — implementation's choice, test asserts distinguishability).
  - The row leaves the eligibility set on the FIRST replay attempt that detects the condition — it must not be re-selected on subsequent runs (verify via a second replay invocation: no log entry / no processing attempt for this row's id).
  - `retry_count` is NOT incremented for this row (incrementing implies "we'll try again later," which is false here — incrementing would be misleading to an operator scanning for genuinely-retryable rows).
  - The normal replayable row(s) in the same batch are processed correctly and are unaffected by the unreplayable row's presence (no batch-abort, no skipped-row cascade).
- **Done when:** All four sub-assertions pass: (1) no crash/throw, (2) row carries a distinct terminal/unreplayable marker separate from retry-exhausted, (3) row is absent from a second run's processing (proven via log/DB state diff across two consecutive replay invocations), (4) `retry_count` unchanged pre/post, and (5) sibling replayable rows in the same batch complete normally. This closes the gap Project Leadership flagged: TC-D2's cascade-delete scenario can produce a row with no FK and no body, which without this test would silently loop, spuriously increment retry_count forever, or crash the replay script.

## Group E — Log Content: stderr Tail Present, No Secrets Leaked

### TC-E1: Log line format includes stderr tail on failure
- **Steps:** Trigger TC-B1-style nonzero exit.
- **Expected:** The `console.error` "Extraction failed" log object includes a field carrying the stderr tail content (not just `{sender, exitCode}` as in the current code) — this is the core log-enrichment requirement from issue point 1.
- **Done when:** Captured log output (via console spy/mock) contains the literal stderr content substring.

### TC-E2: No secrets in dead-letter row or log line
- **Preconditions:** Craft a test double whose stderr output includes something resembling a credential (e.g. simulate `extract_memories.py` accidentally echoing `ANTHROPIC_API_KEY=sk-ant-...` or a DB connection string with embedded password, as would happen if an underlying library dumped its config on error).
- **Steps:** Trigger failure with this contrived stderr content.
- **Expected:** This test exists to catch whether ANY redaction/scrubbing is applied — if the implementation does not scrub, this test documents that as a known gap (do not silently pass; explicitly assert and flag). At minimum, the log line and dead-letter row must not contain a PGPASSWORD-style env var dump beyond what the underlying script would already output in its own normal error handling — this test's real target is the NEW code (the psql catch logging, C6/TC-B4/TC-B5), not `extract_memories.py`'s own behavior.
- **Done when (for the new code specifically):** The logged psql-failure message from TC-B4/TC-B5 does not include a bare connection string with embedded password even if the underlying pg error object contains one (e.g., don't `JSON.stringify(err)` wholesale if `err` could carry a connection string — assert the log call extracts `.message` or an equivalently scoped field, not the full error/config object).

### TC-E3: sender_id truncation preserved in any new logging (regression check against existing convention)
- **Preconditions:** None special.
- **Steps:** Trigger any failure path with a realistic senderId (phone number or UUID).
- **Expected:** Existing convention in handler.ts already truncates `senderId` to `substring(0,8) + '...'` in the "Processing message" info log. New failure-path logging must not regress this by logging the FULL senderId anywhere it wasn't already fully logged before (audit: current code does NOT truncate senderId in the "Extraction failed" log at all today — since the fix is adding fields to that log line, this test asserts the new version keeps the same or better redaction discipline, not worse).
- **Done when:** No new log line exposes a full, untruncated senderId where the existing pattern established truncation; deviations must be a deliberate call-out in the QA validation step, not silent regression.

---

## Group F — Regression / Static Checks

### TC-F1: Grep-level regression — no bare silent catches remain
- **Steps:** `grep -n "catch(() => ({ ?stdout: ''" memory/hooks/memory-extract/handler.ts` (adjust for exact formatting) post-fix.
- **Expected:** Zero matches.
- **Done when:** Command returns no matches; both former call sites now reference a named error-handling function/inline logger.

### TC-F2: Existing hook behavior untouched for non-message or short/command messages
- **Preconditions:** None.
- **Steps:** Trigger hook with `event.type !== 'message'`, then with `event.action !== 'received'`, then with a rawBody < 10 chars, then with a rawBody starting with `/`.
- **Expected:** All four cases return early exactly as today (debug log + return), with NO spawn attempted, NO dead-letter logic invoked. This guards against the new dead-letter/timeout code accidentally running on paths that should short-circuit.
- **Done when:** `spawn()` mock/spy shows zero invocations across all four early-return cases.

### TC-F3: Activity tracking (`logActivity`) unaffected by the fix
- **Preconditions:** None.
- **Steps:** Trigger hook with a heartbeat-like message and a normal user message across a simulated day-rollover.
- **Expected:** `logActivity` behavior (day reset, active-minutes accumulation, heartbeat vs user-message counting) is unchanged by this fix — this is a pure non-regression check since the fix touches code below this logic in the same file.
- **Done when:** Activity counters match pre-fix expected values for the same input sequence (can diff against current handler.ts behavior as the oracle).

---

## Summary Table

| ID | Title | Constraint(s) |
|---|---|---|
| TC-A1 | Successful extraction writes no dead-letter row | — |
| TC-A2 | Successful extraction with stderr warnings, exit 0 | — |
| TC-B1 | Nonzero exit → dead-letter with stderr tail | C6 |
| TC-B2 | Spawn error → distinguishable dead-letter | C6 |
| TC-B3 | Timeout kill → dead-letter, child actually terminated | C6 |
| TC-B4 | psql session-upsert catch now logged | C6 |
| TC-B5 | psql transcript-upsert catch now logged | C6 |
| TC-B6 | Compound failure → body fallback used correctly | C1 |
| TC-C1 | stderr exactly at cap | C3 |
| TC-C2 | stderr cap+1, last-N-bytes retained | C3 |
| TC-C3 | stderr far over cap, no pipe stall | C3 |
| TC-C4 | Empty stderr handled cleanly | C3 |
| TC-C5 | Huge stdout, no dead-letter on success | C3 |
| TC-C6 | Interleaved stderr/stdout over cap | C3 |
| TC-D1 | Pre-existing transcript + failure → FK recovered, not body fallback | C1 |
| TC-D2 | Session delete cascades, dead-letter row survives with FK nulled | C2 |
| TC-D3 | Migration re-run idempotent | C5 |
| TC-D4 | Migration schema conformance checklist | C5 |
| TC-D5 | Replay overlapping-run protection (flock) | C4 |
| TC-D6 | Replay FK-row vs body-fallback-row | C4 |
| TC-D7 | Replay rate limiting per run | C4 |
| TC-D8 | retry_count increment + exhaustion | C4 |
| TC-D9 | Successful replay cleanup path | C4 |
| TC-D10 | Replay sources env-loader.sh + pg-env.sh | C4 |
| TC-D11 | Timeout-killed extraction FK recovery matches D1 | C1, C6 |
| TC-D12 | Replay handles unreplayable rows (NULL FK + NULL body) deterministically | C2, C4 |
| TC-E1 | stderr tail present in failure log line | — |
| TC-E2 | No secrets leaked in psql-failure logging | C6 |
| TC-E3 | senderId truncation discipline preserved | — |
| TC-F1 | Grep regression — no bare silent catches remain | C6 |
| TC-F2 | Early-return paths untouched, no spawn/dead-letter triggered | C6 |
| TC-F3 | Activity tracking unaffected | — |

**Total: 32 test cases** (2 happy path, 6 failure path, 6 boundary, 12 domain-specific DB/replay/migration, 3 log content, 3 regression).

## Open Items For Implementation / Later QA Steps

- Exact stderr/stdout cap byte value (16384 vs 16000 vs other) must be confirmed against the actual diff before TC-C1/TC-C2 assertions are finalized to an exact byte count.
- Exact column names/enum values for failure-reason classification (spawn error vs timeout vs nonzero exit vs psql-catch) are implementation choices; test cases above assert *distinguishability*, not specific column/value names — desk review (later QA step) must map these to the actual schema.
- Whether successful replay results in DELETE vs UPDATE-to-resolved is an implementation choice; TC-D9 asserts behavioral consistency, not a specific mechanism.
- Replay script filename/path not yet finalized (referenced generically as `extraction-replay.sh` above) — confirm actual name at implementation handoff so cron/flock tests target the right file.
- TC-D12's exact terminal-state marker (dedicated status value vs. a boolean + reason column vs. other) is an implementation choice; the test asserts distinguishability and non-retry behavior, not a specific column/value name — desk review must map this to the actual schema alongside the other classification columns noted above.

## Step 4 Review Resolution (Project Leadership, SE Run #448)

- **Gap (unreplayable rows):** Addressed — added TC-D12 above. Covers deterministic handling of NULL-FK + NULL-body rows post-cascade-delete: no crash, distinct terminal marker (separate from retry-exhausted), no repeated re-selection, no pointless retry_count increment, and no impact on sibling rows in the same batch.
- **Clarification (TC-D9 success definition):** Concur with keeping TC-D9 as-is. Replay's contract with `extract_memories.py` is exit code 0 — fact persistence correctness (did the right entity_facts rows land) is `extract_memories.py`'s own tested surface, not the replay script's. Asserting fact-level side effects from TC-D9 would blur ownership and duplicate coverage that belongs to the extraction pipeline's own test suite. If a future incident shows replay-specific data loss between "script exited 0" and "facts actually persisted" (e.g. replay swallowing a downstream error the hook path wouldn't), that's a new test case at that time, not a strengthening of D9 now. Holding position: no change to TC-D9.

Test design mutually approved as of this update. Ready to route to Software Engineering domain for implementation.
