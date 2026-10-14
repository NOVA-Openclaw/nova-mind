# Test Cases — nova-mind#716 (Chunk E: memory-extract lifecycle and summary logging)

**SE run #1231, step 3 — QA test-case design (Chunk E)**
**Author:** Gem (QA Lead)
**Scope:** nova-mind #716 — startup/shutdown/periodic-summary logging, stable failure-reason tokens, stall warning,
routing through the plugin logger instead of `console.*`, for `memory/hooks/memory-extract/handler.ts`.
**Tree discipline:** this file is written to `~/.openclaw/workspace/se-runs/run1231/TEST-CASES-ISSUE-716.md` only.
A Coder is the sole writer on `/home/nova/repos/se1231-nova-mind` (Chunk B part 1); no writes, commits, or
worktrees were made on that branch or tree for this design pass. The implementing Coder commits this file.

---

## 0. Pinned source artifacts

- **nova-mind branch:** `origin/fix/se1231-openclaw-2026.9-regressions`, read via `git show origin/...:path`
  (no checkout/worktree). Confirmed at `9dbe5c35e27c85b1daef458ce78698e55c94e808` at design time (≥ the `21251f0`
  floor given in the dispatch). Current `handler.ts` confirmed to have **24 `console.*` call sites** spanning
  `debug`/`info`/`warn`/`error`, all needing migration.
- **OpenClaw host reference (read-only):** `/home/nova/nova-openclaw-production` (`6ced19b`, 2026.9.6) —
  `src/plugins/hook-types.ts`, `src/plugins/hook-gateway.types.ts`, `src/plugins/logger-types.ts`,
  `src/plugins/plugin-api.types.ts`.

---

## 1. Host-contract citations (REQUIRED — logger + gateway hook shapes, file:line)

**Plugin logger interface** — `src/plugins/logger-types.ts:1-7`:
```ts
/** Logger passed into plugin registration, services, and CLI surfaces. */
export type PluginLogger = {
  debug?: (message: string) => void;
  info: (message: string) => void;
  warn: (message: string) => void;
  error: (message: string) => void;
};
```
**Critical detail: `debug` is OPTIONAL** (`debug?:`) — `info`/`warn`/`error` are required, `debug` may be
`undefined` on some logger implementations. Any code that unconditionally calls `logger.debug(...)` without a
guard will throw on a logger that omits it. This is a required adversarial case (§6).

**Where the logger comes from** — `src/plugins/plugin-api.types.ts:202` (within the `PluginApi` shape passed to
`register(api)`): `logger: PluginLogger`. **The logger is handed to the plugin ONCE at registration time, not
per-hook-invocation.** Confirmed by `PluginHookGatewayContext` (`src/plugins/hook-gateway.types.ts:4-11`) —
`{ port?, config?, workspaceDir?, getCron?, abortSignal? }` — **having no `logger` field at all**. This means the
fix MUST capture `api.logger` into module-level state inside `register()` so it is reachable from every hook
callback (`gateway_start`, `gateway_stop`, `before_prompt_build`/`message_received`), not read it off `ctx`.

**`gateway_start`/`gateway_stop` hook signatures** — `src/plugins/hook-types.ts` (~line 1182-1186):
```ts
gateway_start: (event: PluginHookGatewayStartEvent, ctx: PluginHookGatewayContext) => Promise<void> | void;
gateway_stop:  (event: PluginHookGatewayStopEvent,  ctx: PluginHookGatewayContext) => Promise<void> | void;
```
Event shapes — `src/plugins/hook-gateway.types.ts:18-24`: `PluginHookGatewayStartEvent = { port: number }`;
`PluginHookGatewayStopEvent = { reason?: string }`. Neither event carries DB/extraction state — the shutdown
totals (§3) must come from the plugin's own module-level counters, not from the event.

---

## 2. Finding: why memory-extract's console output stopped reaching the journal on 2026.9.x

**Investigated, not conclusively resolved — written up per the dispatch's explicit ask, with confidence level
stated honestly.** Live `journalctl --user -u openclaw-gateway` on this host shows OTHER modules' plain
`console.log`-style output reaching the journal without issue in the same time window (e.g.
`[model-catalog] stage=... elapsedMs=...` lines, and raw Anthropic SDK context-edit lines) — so the journal/
systemd pipeline itself is not broken, and the gateway's systemd unit (`~/.config/systemd/user/
openclaw-gateway.service`) has no `StandardOutput=`/`StandardError=` redirection away from the journal. An
exhaustive grep across `nova-openclaw-production/src` for a literal console-reassignment pattern
(`console.log = `, `interceptConsole`, `captureConsole`, etc.) found **nothing** — three independent search
passes, all empty.

**Most likely explanation (moderate confidence, not independently confirmed within this design pass's budget):**
the modules whose `console.*` output DOES reach the journal (model-catalog, SDK-level logs) are **core gateway
code**, not plugin code. `memory-extract` is a **plugin**. The absence of any simple monkeypatch pattern suggests
the suppression (if real, vs. a coincidental reduction in message volume) is **structural** — e.g. 2026.9.x's
plugin execution/isolation model may bind each plugin's `console` to a different sink (a per-plugin buffer
surfaced only through a dashboard/API) rather than mirroring it to the process's real stdout, while core-gateway
code keeps writing directly to the real stdout stream. This would explain the asymmetry precisely: plugins
affected, core gateway code not.

**Practical conclusion, independent of the exact mechanism:** this doesn't need to be fully explained to be acted
on — `api.logger` is the officially-typed, intended plugin-facing output channel (per §1), and since it comes
from the HOST itself (not the plugin reimplementing its own routing), it is the channel the host guarantees
reaches the journal. The fix (route everything through `api.logger`) is correct regardless of which exact
mechanism caused the console-output regression. **Open question for the orchestrator:** whether to invest further
host-side investigation into the exact suppression mechanism (useful for the NEXT plugin that hits this blind,
pre-#716) or accept "switch to `api.logger`" as sufficient closure for #716 itself (see §7, Open Question 1).

---

## 3. Adversarial/config-seam coverage index

| Requirement | Satisfied by |
|---|---|
| Wrong-type/malformed value at a config seam | TC-716-006 (DB resolution fails at startup — logged as ERROR immediately, not deferred to first message) |
| Non-identity fixture values | TC-716-013 (stall-warning boundary tested at 5h59m/6h01m, not a round number) |
| Config→runtime seam populated by production code | TC-716-021 (staging: real boot, real `journalctl`, real `systemctl --user stop`) |
| INTENT-level check vs. a live source system | TC-716-021/022 (staging journal output, not a captured-logger fixture) |
| Source-artifact pinning verified before analysis | §0; `git show` used throughout, no checkout of the shared tree |

---

## 4. Startup + shutdown lines (6 cases: TC-716-001…006)

### TC-716-001 — Startup INFO line fires exactly once, at hook registration
**Priority:** P1 (Critical) — direct acceptance test.
**Steps:** Load the plugin (call `register(api)`).
**Expected:** Exactly one `api.logger.info(...)` call fires during registration (not deferred to the first
`message_received`/`before_prompt_build` event).

### TC-716-002 — Startup line contains version/commit, resolved DB name, resolution source, Python path, model
**Priority:** P1 (Critical) — direct acceptance test, per #716's exact field list.
**Expected:** The startup line's message contains: (a) a version or commit identifier, (b) the resolved memory DB
**name only** (never host/port/credentials — ties to §6's no-secrets requirement), (c) which mechanism resolved it
(`PGDATABASE` vs. `postgres.json`), (d) the Python interpreter path used for extraction, (e) the extraction
model identifier.

### TC-716-003 — DB resolution failure at startup logs ERROR immediately, not deferred to the first message
**Priority:** P1 (Critical) — direct acceptance test, explicit in #716's ask ("If resolution fails at startup, log
an ERROR right then, not on the first message").
**Preconditions:** `PGDATABASE` unset and `postgres.json` missing/unreadable (mirrors Chunk B/D's #703 fixture).
**Steps:** Load the plugin under this condition.
**Expected:** An `api.logger.error(...)` call fires during/immediately after registration — BEFORE any message
event is ever received. A regression test here is: if the plugin instead waits and only surfaces this on the
first `message_received`, this test fails (that was the OLD behavior #716 is correcting).

### TC-716-004 — Shutdown INFO line fires on `gateway_stop`, exactly once
**Priority:** P1 (Critical) — direct acceptance test. Host contract: `gateway_stop`'s event is only
`{ reason?: string }` (§1) — totals must come from the plugin's own module-level counters, not the event.
**Steps:** Fire the `gateway_stop` hook after some activity.
**Expected:** Exactly one `api.logger.info(...)` call, containing session totals: received / extracted / stored /
skipped / failed — all present as separate counts, not a single combined number.

### TC-716-005 — Shutdown totals reflect the FULL session, not just since the last periodic summary
**Priority:** P1 (Critical) — regression guard against a plausible implementation bug (reusing the periodic
summary's since-last-flush counters instead of session-lifetime counters).
**Preconditions:** At least 2 periodic-summary cycles have already fired before shutdown.
**Steps:** Fire `gateway_stop`.
**Expected:** Shutdown totals equal the SUM across the whole session (all activity since startup), not just the
activity since the most recent periodic summary.

### TC-716-006 — Shutdown line still fires even if the gateway stops with zero activity (no messages ever received)
**Priority:** P2 (High) — boundary/negative case for the shutdown path specifically (distinct from the periodic
summary's "no line when idle" rule in §5 — shutdown is explicitly NOT gated on activity, per #716's wording "one
INFO line on gateway_stop... with totals," unconditional).
**Expected:** The shutdown line still fires with all-zero totals — it is not suppressed the way an idle periodic
summary is.

---

## 5. Periodic summary — activity-gated (4 cases: TC-716-007…010)

### TC-716-007 — Summary fires every N minutes (default 30) ONLY if there was activity since the last summary
**Priority:** P1 (Critical) — direct acceptance test.
**Preconditions:** At least one message processed within the summary window.
**Steps:** Advance time past the summary interval.
**Expected:** Exactly one `api.logger.info(...)` summary line, containing counts since the LAST summary (not
session-lifetime totals — distinct from TC-716-005's shutdown-is-lifetime rule) plus the timestamp of the last
successful store.

### TC-716-008 — NO summary line when idle (REQUIRED negative test)
**Priority:** P1 (Critical) — direct acceptance test, explicit in #716 ("only if there was activity... no line
when idle").
**Preconditions:** Zero messages processed since the last summary (or since startup, for the first interval).
**Steps:** Advance time past the summary interval.
**Expected:** Zero log calls of any kind from the periodic-summary path. This must be verified by asserting the
logger mock received NO call attributable to the summary tick — not just "no error," since a silently-swallowed
bug could also produce zero output for the wrong reason.

### TC-716-009 — Summary interval is configurable, default 30 minutes
**Priority:** P2 (High) — direct test of the stated default plus the "configurable" implication.
**Expected:** Default interval is 30 minutes when unconfigured; an explicit override (e.g. 5 minutes) changes the
actual firing cadence.

### TC-716-010 — Summary's "last successful store" timestamp updates only on STORE success, not on receipt/extraction-without-store
**Priority:** P1 (Critical) — precision test for a field whose exact semantics matter (operators will use this to
judge staleness).
**Preconditions:** A message is received and classified/extracted, but the final DB store step fails.
**Steps:** Trigger a subsequent summary.
**Expected:** The "last successful store" timestamp reflects the most recent row ACTUALLY WRITTEN, unaffected by
the failed-store attempt that happened after it — proving the field tracks store success specifically, not
"activity" generically (which would make stall detection in §6 meaningless).

---

## 6. Stable failure-reason tokens (8 cases: TC-716-011, plus one per token: TC-716-011a…g)

### TC-716-011 — Every failure class logs WARN/ERROR with its exact stable reason token AND the session key; never swallowed
**Priority:** P1 (Critical) — direct acceptance test for the umbrella requirement; the 7 sub-cases below each
exercise one token.
**Expected (shared across all 7):** The log call includes the literal reason token string, the session key, and is
never caught-and-discarded (i.e. every failure path that currently exists in `handler.ts`'s try/catch structure
must route through `api.logger`, not be silently absorbed).

### TC-716-011a — `db_unresolved` (neither `PGDATABASE` nor `postgres.json` resolves)
**Priority:** P1 (Critical). Ties to TC-716-003's startup case AND to a per-message occurrence if resolution is
re-attempted per message (confirm with implementation which call sites can produce this at runtime, not just at
startup).

### TC-716-011b — `db_unreachable` (DB name resolves, but the connection itself fails — e.g. Postgres down, wrong host)
**Priority:** P1 (Critical). Distinct from `db_unresolved` — the name resolved fine, the CONNECTION failed. Must
be a different token, not a shared generic "db_error."

### TC-716-011c — `peer_guard_refused` (the #703 cross-peer guard blocked the write — reuses Chunk D's round-2
reviewed guard logic directly; this IS the guard firing, not a DB connectivity issue)
**Priority:** P1 (Critical). Cross-reference: the guard's own existing error text ("Cross-peer guard...", reviewed
in SE#1231 round 2) should map to exactly this token.

### TC-716-011d — `extractor_spawn_failed` (the Python child process failed to spawn at all — e.g. interpreter
path wrong, ENOENT)
**Priority:** P1 (Critical). Distinct from `extractor_exit_nonzero` — spawn failure means the child never
started; exit-nonzero means it started and failed.

### TC-716-011e — `extractor_exit_nonzero` (the Python child ran and exited with a nonzero code)
**Priority:** P1 (Critical). Must include the actual exit code in the message content (not just the token) for
operator diagnosis — confirm this is present without being a "message body" leak (exit codes are safe; see §8).

### TC-716-011f — `provider_key_missing` (the extraction model's API key/credential is absent)
**Priority:** P1 (Critical). **Adversarial overlap with §8's no-secrets rule**: the log line must say a key is
missing WITHOUT ever printing a partial/full key value, env var name pattern that could be mistaken for a key, or
any other credential-adjacent content beyond the token itself and which PROVIDER is affected.

### TC-716-011g — `timeout` (extraction exceeded the configured timeout and was terminated)
**Priority:** P1 (Critical). Cross-reference: `handler.ts`'s existing SIGTERM→SIGKILL escalation path (confirmed
present in the pinned ref from SE#1231 round 1/2 reading) should map to this token, and should NOT be confused
with `extractor_exit_nonzero` (a timeout-killed process's exit code is an artifact of the kill signal, not a
genuine nonzero-exit failure — these must be distinguishable, not double-counted as two different failures for
one underlying event).

---

## 7. Stall warning (4 cases: TC-716-012…015)

### TC-716-012 — Stall WARN fires when messages arrived but nothing was stored for > 6 hours (default)
**Priority:** P1 (Critical) — direct acceptance test.
**Preconditions:** At least one message received; last successful store (§5's TC-716-010 field) is > 6h in the
past; the gap is NOT simply "no messages at all" (an idle gateway with zero traffic is not "stalled," it's quiet —
confirm this distinction is actually implemented, not conflated).

### TC-716-013 — Boundary: 5h59m does NOT fire, 6h01m DOES (non-identity fixture, REQUIRED)
**Priority:** P1 (Critical) — REQUIRED non-round-number boundary case per the dispatch's explicit instruction
("boundary values that aren't round numbers").
**Expected:** Correct `>` (or `>=`, confirm which) semantics at exactly the 6h threshold, verified with genuinely
adjacent, non-round timestamps — not `0h`/`6h`/`12h` exactly, which could mask an off-by-one.

### TC-716-014 — Stall threshold is configurable, default 6 hours
**Priority:** P2 (High) — direct test of the stated default plus configurability.

### TC-716-015 — Stall WARN does not re-fire every tick once triggered — or if it does, at a sane cadence (confirm intended behavior)
**Priority:** P2 (High) — operational-sanity guard, mirrors Chunk C's liveness-alarm de-dup pattern (SE#1231
precedent: #711's 48h alarm was specified "at most once per day per stalled job"). #716's own text doesn't specify
a re-fire cadence for the stall warning — this test's exact assertion should be confirmed against whatever cadence
the implementation picks (see Open Question 2), but SOME bound must exist; "once per periodic-summary-tick
forever while stalled" (e.g. every 30 min) would be noisy but defensible; "exactly once until recovery" is the
other reasonable choice.

---

## 8. Output routing + adversarial robustness (7 cases: TC-716-016…020, 2 more below)

### TC-716-016 — ALL memory-extract output goes through `api.logger`, zero bare `console.*` calls remain
**Priority:** P1 (Critical) — direct acceptance test, the literal ask. `grep -c "console\."
memory/hooks/memory-extract/handler.ts` must be 0 post-fix (currently 24, per §0).

### TC-716-017 — `api.logger` is captured at registration and remains usable inside `gateway_start`/`gateway_stop`
**Priority:** P1 (Critical) — direct test of §1's host-contract finding (logger not available via `ctx` on these
hooks). Confirms the module correctly stores `api.logger` at `register()` time rather than attempting (and
failing) to read a nonexistent `ctx.logger` inside `gateway_start`/`gateway_stop`.

### TC-716-018 — `logger.debug` is OPTIONAL — code must guard against it being `undefined` (REQUIRED adversarial case)
**Priority:** P1 (Critical) — REQUIRED, directly derived from §1's schema citation (`debug?:`). Provide a mock
`api.logger` with `debug` omitted entirely (only `info`/`warn`/`error` present) and run the plugin through a
normal message-processing cycle that would, on a full logger, emit a debug line.
**Expected:** No `TypeError: logger.debug is not a function` — the code checks `typeof logger.debug ===
"function"` (or equivalent) before calling it, or falls back to `logger.info` for anything it considers
must-not-be-silently-dropped.

### TC-716-019 — Logger throws on a call → extraction still proceeds (REQUIRED adversarial case)
**Priority:** P1 (Critical) — REQUIRED, explicit in the dispatch. Mock `api.logger.info`/`warn`/`error` to throw
on every call.
**Expected:** The actual extraction/store pipeline completes successfully despite every logging call throwing —
logging must never be on the critical path for the feature it's merely observing. Every call site that invokes the
logger must be wrapped (try/catch or equivalent) so a throwing logger can't abort message processing.

### TC-716-020 — Counters never go negative and don't overflow
**Priority:** P1 (Critical) — REQUIRED adversarial case.
**Steps:** (a) Attempt an operation sequence that could plausibly decrement a counter below zero (e.g. a
store-then-undo path, if one exists, or a double-counted failure/success pair); (b) run a very large number of
cycles (simulate, don't actually loop millions of times in a unit test — assert the counter TYPE/MATH can't
silently wrap, e.g. using a safe-integer check or an explicit cap/warn behavior if a realistic cap is intended).
**Expected:** No counter is ever observed negative; no counter silently wraps to a small/negative number after
exceeding `Number.MAX_SAFE_INTEGER` (confirm the implementation's chosen behavior — saturate, warn, or realistically
never reach that scale — and test whichever is chosen).

### TC-716-020b — No secrets in any log line (API keys, credentials, connection strings)
**Priority:** P1 (Critical) — REQUIRED adversarial case, overlapping §6's `provider_key_missing`/DB-name-only
rules. Scan EVERY log line emitted across the full TC-716-001…019 test matrix (not just the ones that obviously
touch credentials) for: API key patterns, the `postgres.json` file's credential fields, full DB connection
strings (host/port/user/password combined), and environment variable VALUES (as opposed to variable names, which
are fine to log).
**Expected:** Zero matches across the entire captured-logger transcript from the full test run.

### TC-716-020c — No message BODIES in any log line — session keys only
**Priority:** P1 (Critical) — REQUIRED adversarial case, distinct from TC-716-020b (content privacy, not
credential security). Run a message-processing cycle with a distinctive, identifiable message body (e.g. a unique
sentence) through to both success and every failure path (§6's 7 tokens).
**Expected:** The distinctive message content NEVER appears in any log line, at any level, on any path — only the
session key (and, where applicable per §6, generic metadata like an exit code or a provider name) ever appears.
This must be checked especially carefully on the extraction-failure paths (§6's tokens), since a naive
"log the failed input for debugging" instinct is exactly the kind of leak this test exists to catch.

---

## 9. Staging integration (2 cases: TC-716-021…022)

### TC-716-021 — A real boot shows the startup line in `journalctl`
**Priority:** P1 (Critical) — REQUIRED staging test, matches #716's own acceptance criteria exactly.
**Steps:** Restart the staging gateway for real; immediately `journalctl --user -u <staging-unit> | grep
memory-extract`.
**Expected:** The startup line (TC-716-002's full field set) appears in the journal — this is the test that
actually closes #716's root complaint (the 2026-10-13 23:03 restart that produced zero `[memory-extract]` lines).

### TC-716-022 — `systemctl --user stop` shows the shutdown line
**Priority:** P1 (Critical) — REQUIRED staging test.
**Steps:** `systemctl --user stop <staging-unit>`; check the journal immediately before the process exits.
**Expected:** The shutdown line (TC-716-004's totals) appears in the journal before the unit fully stops — this
needs the plugin's `gateway_stop` handler to complete (or at least flush its log call) within whatever grace
period `TimeoutStopSec` allows (confirmed `30` on this host's own unit file, §0) before `KillMode=control-group`
force-kills remaining processes.

---

## 10. Open questions for the orchestrator / Project Leadership review

1. **The console-output-suppression root cause (§2) is not conclusively identified.** Confirming whether further
   host-side investigation (why plugin `console.*` output specifically stopped reaching the journal while core
   gateway `console.*` output didn't) is worth pursuing as its own follow-up issue — useful for future plugins
   that might hit the same blind spot — or whether "migrate to `api.logger`" is accepted as sufficient closure
   for #716 itself.
2. **TC-716-015's stall-warning re-fire cadence** is not specified in #716's own text. Confirming the intended
   behavior (fire once until recovery, vs. a periodic re-fire bound like #711's "at most once per day") before
   this test's exact assertion is finalized.
3. **TC-716-011a's "per-message re-occurrence"**: confirming whether `db_unresolved` can realistically occur
   again after a successful startup resolution (e.g. if the DB config changes mid-run) or whether it is
   structurally a startup-only failure mode once resolution succeeds once.
4. **TC-716-020's overflow-safety question** depends on an implementation choice (saturate vs. warn vs. "never
   realistically reached") that isn't specified in #716 — test written to adapt to whichever choice is made, but
   the choice itself should be confirmed.
5. Related issues **#703** (DB resolution/guard — already reviewed in SE#1231 rounds 1-2, re-used by reference
   here for `db_unresolved`/`peer_guard_refused`) and **#701** (cited as related in #716's own text, not read in
   this design pass — confirming whether #701 has any bearing on this logging work specifically, or is parallel/
   unrelated).

## 11. Resolved decisions (I)ruid, 2026-10-14 04:25 UTC) — these SUPERSEDE §10's open questions

1. **Console-output mechanism:** no separate investigation issue. Switching all output to `api.logger` (TC-716-016/017) closes this for #716.
2. **Stall-warning re-fire cadence (TC-716-015): ONCE PER HOUR while stalled, until recovery.** Not once a day, because a daily alert can easily be missed, and storing memories is critical. Required assertions:
   - The first WARN fires when the stall threshold is crossed (TC-716-012/013).
   - Repeat WARNs fire at most once per 60 minutes while still stalled: no repeat at +59 min, a repeat at +61 min. Use non-round boundaries.
   - Once a successful store happens (recovery), the warnings stop. Log one INFO "stall recovered" line with the stall duration.
   - A new stall after recovery restarts the cycle with an immediate first WARN.
   - The re-fire interval is configurable; the default is 60 min.
3. **`db_unresolved` after startup:** yes, it can recur (for example, if the config changes at runtime). Log it every time it happens, rate-limited to at most once per 10 minutes. Test: two failures 9 min apart produce one line; failures 11 min apart produce two lines.
4. **Counter overflow:** no special handling. JS numbers are exact up to 2^53. Assert only that counters never go negative.
5. **#701:** closed. `provider_key_missing` (TC-716-011f) covers it if it recurs. Nothing extra is needed.
