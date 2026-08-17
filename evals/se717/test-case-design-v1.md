# Test Cases — nova-mind#612: Remove pg-notify-listener local tooling from nova-mind + installer

**SE run #717, step 3 — QA test-case design (retry)**
**Author:** Gem (QA Lead)
**Inputs read in full:** `gh issue view 612` (body + comment thread), `agent-install.sh`
(`_install_pg_notify_listener` ~L410-455, call site ~L1893-1908), `git grep -ln
"pg-notify-listener"` full repo surface, `cognition/tests/conftest.py`,
`cognition/tests/test_pg_notify_listener_issue_{399,506,508}.py`,
`lib/tests/test_pg_env.py`, `cognition/README.md`,
`cognition/docs/system-level-controls.md`, `memory/docs/database-config.md`,
`CHANGELOG.md` / `cognition/CHANGELOG.md`, live filesystem state of
`~/nova-workspace` and `~/agent-chat` (including `~/agent-chat/install.sh`,
`~/agent-chat/listener/pg-notify-listener-chat.py`,
`~/agent-chat/tests/test_agent_chat_installer.bats`,
`~/agent-chat/tests/test_pg_notify_listener_chat.py`), issues #461, #579, #581,
#583, #610.

---

## 0. Critical Findings (read before triaging test cases below)

### F-1 — The "new" agent_chat listener already exists, is already shipping via an unconditional installer, and is almost certainly the actual root cause of the graybeard stray

Issue #612's comment thread states the agent_chat listener "does not exist
anywhere correct" and directs creating `pg-notify-listener-agent-chat.py` in
**nova-workspace** from scratch. This is **incorrect** — the code already
exists, tracked in git, in `NOVA-Openclaw/agent-chat`:

- `~/agent-chat/listener/pg-notify-listener-chat.py` (895 fewer lines than
  the nova-mind reference but functionally equivalent: LISTEN
  `schema_changed` on `agent_chat`, dump via pgschema, commit/push to
  `agent-chat/schema.sql`, alert via `send_agent_message`, exponential
  backoff reconnect per #583).
- `~/agent-chat/listener/pg-notify-listener-chat.service` (systemd --user
  unit).
- `~/agent-chat/install.sh` function `_install_listener_unit()` (L230-273)
  is called **unconditionally** from `main()` (L316, L326) with **zero
  account gating** — the only skip mechanism is the opt-in env var
  `AGENT_CHAT_SKIP_LISTENER_UNIT=1`. This is the *exact same bug class* as
  `_install_pg_notify_listener` in nova-mind's `agent-install.sh`.
- Issue #612's own comment describes the graybeard stray as
  `pg-notify-listener-chat.py` — **byte-for-byte the same name** as the file
  already shipping in `agent-chat/listener/`. The overwhelmingly probable
  explanation is that graybeard (or something acting on graybeard's behalf)
  ran `agent-chat/install.sh` as the "once per host" bus installer step, and
  `_install_listener_unit()` silently installed + enabled it on graybeard's
  account — no attacker, no mystery hook, just the same unconditional-install
  bug living in a sibling repo.

**This changes the shape of the fix.** The issue as written asks to *create*
a new listener in nova-workspace. The correct action is almost certainly to
**add nova-only account gating to `agent-chat/install.sh`'s
`_install_listener_unit()`** (and decide whether the canonical listener stays
in `agent-chat` — where the schema it syncs already lives, closest scope —
or gets relocated to nova-workspace per the issue's literal text). See Open
Question OQ-1. Test cases below cover both branches so the design is not
blocked on this decision, but **this is flagged as the single most important
open question for orchestrator/I)ruid review** — building "a new listener
from scratch" without addressing the account-gating hole in the *existing*
one leaves the actual root cause unfixed and duplicates working code.

### F-2 — Naming conflict

Issue #612 specifies the new script must be named `pg-notify-listener-agent-chat.py`
("standardize on the `-agent-chat` name"). The existing, already-shipping
file in `agent-chat/listener/` is named `pg-notify-listener-chat.py`. If F-1's
resolution keeps the canonical listener in `agent-chat`, a rename (with
corresponding `.service` `ExecStart=`/`WorkingDirectory=` updates and test
updates) is an in-scope, easy-to-miss detail. See OQ-2.

### F-3 — `lib/tests/test_pg_env.py` has a hard path dependency that WILL break silently

`lib/tests/test_pg_env.py` TC-50/TC-51 (L567-614) load
`cognition/scripts/pg-notify-listener.py` directly via
`importlib.util.spec_from_file_location` at the hardcoded repo-relative path
`repo_root / "cognition" / "scripts" / "pg-notify-listener.py"`. This file
does **not** live under `cognition/tests/`, was not called out by the issue,
and is easy to miss during grep sweeps because it does not have
"pg_notify_listener" or "pg-notify-listener" in its own filename. Once the
script is removed from `cognition/scripts/`, these two tests will fail with a
file-not-found error, not a graceful skip. See TC-8.

### F-4 — `cognition/tests/conftest.py` is nova-mind's *only* conftest.py

`find . -name conftest.py` returns exactly one hit in the entire nova-mind
repo, and it exists solely to support the three
`test_pg_notify_listener_issue_*.py` files (its own docstring says so, and a
repo-wide grep confirms no other test file references its fixtures). This
substantially de-risks the "splitting conftest may break sibling tests"
concern raised in the task brief — there are no siblings. Confirmed via
direct grep, not assumption (TC-11).

### F-5 — nova-workspace's *committed* copy of `pg-notify-listener.py` is a stale fork, not the deployed one

`~/nova-workspace/scripts/pg-notify-listener.py` (committed, tracked) is
**not** what has been running on nova's account. The live deployed copy at
`~/.openclaw/workspace/scripts/pg-notify-listener.py` is byte-identical
(md5sum-verified) to `~/nova-mind/cognition/scripts/pg-notify-listener.py`
— i.e., it was deployed by nova-mind's installer, not by anything in
nova-workspace. nova-workspace's own committed copy is missing #399 (push
retry/alerting), #506 (branch safety), #508 (PGUSER sender fix), and #405
(repo-relative pg_env resolution) — this is the exact fork divergence
described in #461. "Relocate to nova-workspace" is therefore not a simple
file move; it is a **fork reconciliation** (#461) that must land the
nova-mind version's functionality (which is the more complete/correct one)
while preserving nova-workspace's own additions (#21 reconnect backoff, #22
SIGHUP log-reopen) that nova-mind's copy lacks. See TC-16, TC-17.

### F-6 — No account-gating precedent exists anywhere in either installer today

Grepped both `agent-install.sh` and `agent-chat/install.sh` for
account/user-based conditionals (`whoami`, `USER ==`, `nova-only`, etc.) —
none exist. There is no established pattern in this codebase for "only
install X if the running account is nova." The fix will need to introduce
this pattern for the first time. Test design assumes a `getpass.getuser()` /
`whoami` comparison against a configurable "owner account" (default `nova`),
matching the git pre-push hook's existing `OPENCLAW_AGENT_ID` identity-check
pattern in spirit, but there is no existing helper function to call — this
should be written once and shared if both installers need it. Flag for
Coder as a design note, not just a test gap.

---

## 1. Scope Recap (from issue #612 + F-1 correction)

| # | Issue requirement | Repo(s) affected |
|---|---|---|
| 1 | Remove `pg-notify-listener.py`/`.service` from nova-mind; drop `_install_pg_notify_listener` + call site | nova-mind |
| 2 | Relocate `test_pg_notify_listener_issue_{399,506,508}.py` + `conftest.py` fixtures | nova-mind → nova-workspace |
| 3 | nova-workspace canonical home; install/enable nova-only there | nova-workspace |
| 4 | New `agent_chat` listener (nova-only) — **corrected by F-1: already exists in agent-chat repo; needs account gating + possible relocation/rename, not ground-up creation** | agent-chat (and/or nova-workspace per OQ-1) |
| 5 | Installer audit: no other local-only tooling on shared installer | nova-mind (+ agent-chat per F-1) |

---

## 2. Invariants Under Test

- **INV-1:** A fresh `agent-install.sh` run, on any account, installs zero
  pg-notify-listener files and starts zero listener services.
- **INV-2:** No listener authenticates as, or can push as, any account other
  than nova.
- **INV-3:** Test relocation preserves 100% of existing assertions (27
  #399+#506 tests + 23 #508 tests = 50 relocated tests, all passing in new
  location) with zero regression in the source repo's remaining suite.
- **INV-4:** Both nova_memory and agent_chat listeners are installable,
  idempotently, from a single nova-only-gated entrypoint in the canonical
  repo.
- **INV-5:** No shared/peer-run installer (nova-mind's `agent-install.sh`,
  agent-chat's `install.sh`) installs or enables either listener regardless
  of which account runs it, **except** via an explicit, gated, nova-only
  code path.

---

## 3. Test Cases

### Group A — nova-mind installer: clean removal

**TC-1 — Fresh install produces zero listener artifacts (the core acceptance criterion)**
- **Repo/Suite:** nova-mind, bats (`tests/install/test_agent_install_pg_notify_removal.bats`, new file)
- **Preconditions:** Fresh `$HOME` sandbox (mktemp -d), fake `postgres.json`, mocked `psql`/`systemctl`/`crontab` per existing bats conventions in this repo (see `tests/install/test_agent_chat_peer_detection.bats` for the mock pattern).
- **Steps:** Run `agent-install.sh` end-to-end (or the smallest slice that reaches the removed section) in the sandbox.
- **Expected:**
  - `$HOME/.openclaw/workspace/scripts/pg-notify-listener.py` does NOT exist
  - `$HOME/.config/systemd/user/pg-notify-listener.service` does NOT exist
  - Mock `systemctl` log shows **zero** invocations containing `pg-notify-listener` (not just "not enabled" — literally never referenced)
  - Installer output contains no "PostgreSQL NOTIFY listener..." section header

**TC-2 — `_install_pg_notify_listener` function no longer defined**
- **Repo/Suite:** nova-mind, bats
- **Steps:** `grep -c '_install_pg_notify_listener' agent-install.sh`
- **Expected:** count is 0 (function definition and call site both gone — this is a static-source assertion, cheap and fast-failing, run before the slower TC-1 integration test)

**TC-3 — `agent-install.sh` passes `bash -n` after edit**
- **Repo/Suite:** nova-mind, bats
- **Expected:** exit 0 (matches existing repo convention, e.g. TC-579-PD-07)

**TC-4 — ShellCheck: zero new warnings on `agent-install.sh`**
- **Repo/Suite:** nova-mind, bats
- **Expected:** exit 0, diffed against pre-change baseline (matches TC-579-PD-08 convention)

**TC-5 — Installer is idempotent post-removal (no dangling reference crashes)**
- **Repo/Suite:** nova-mind, bats
- **Preconditions:** Same sandbox as TC-1, run installer twice.
- **Expected:** Second run exits 0, no errors referencing undefined functions or missing source files that the old code guarded against with `[ ! -f ... ]` checks that no longer apply.

### Group B — Upgrade / tombstone path (flagged design decision — see OQ-3)

**TC-6 — Peer with a PRE-EXISTING listener install: does the new installer clean it up?**
- **Repo/Suite:** nova-mind, bats
- **Preconditions:** Sandbox `$HOME` pre-seeded with a listener already installed (as if a prior installer version ran): `$HOME/.openclaw/workspace/scripts/pg-notify-listener.py` present, `$HOME/.config/systemd/user/pg-notify-listener.service` present and "enabled" in the mock systemctl state.
- **Steps:** Run the (fixed) `agent-install.sh`.
- **Expected — TWO VALID DESIGN OUTCOMES, pick one and assert it explicitly (do not leave silently untested):**
  - **(a) Active tombstone/cleanup:** installer detects the pre-existing artifacts and removes the script, removes the unit file, `systemctl --user disable --now`s the service, logs a clear one-time migration notice. — OR —
  - **(b) Passive (no-op):** installer does nothing to pre-existing installs; cleanup is Graybeard's one-time containment responsibility only, and a stale peer re-running an *old* installer binary (not this fixed one) could theoretically reinstall it — this is a real residual risk that should be written into a postmortem note (per issue's acceptance criteria: "Postmortem note added"), not silently accepted.
  - **This decision must be made explicitly before TC-6 can be finalized.** See OQ-3. Recommend (a) given the severity of the original incident — a fixed installer that leaves a live, still-running, still-account-authenticated listener process untouched on 4 peers does not fully remediate the exposure, it just stops *new* installs.

**TC-7 — Old installer binary re-run against a peer where containment already ran (regression guard for OQ-3 outcome (a))**
- **Repo/Suite:** nova-mind, bats
- **Preconditions:** Simulate a peer running an *old* (pre-#612) `agent-install.sh` checkout after containment removed their listener.
- **Expected:** This is out of scope for the *fixed* installer to prevent (can't patch old binaries) — assert instead that the fixed installer, once deployed, is the version peers will actually run going forward, and document (in the postmortem note referenced in TC-6) that any peer still holding an old nova-mind checkout is a residual risk until they update. This is a documentation/process test, not a code test — flag as non-automatable, escalate to postmortem doc review.

### Group C — Repo hygiene / cross-reference sweep

**TC-8 — `lib/tests/test_pg_env.py` TC-50/TC-51 do not silently break (F-3)**
- **Repo/Suite:** nova-mind, pytest (`lib/tests/test_pg_env.py`)
- **Preconditions:** `cognition/scripts/pg-notify-listener.py` removed per TC-1.
- **Steps:** Run `lib/tests/test_pg_env.py` in full.
- **Expected:** TC-50/TC-51 (the two tests that `importlib.util.spec_from_file_location` the listener script directly) must be either:
  - (a) rewritten to point at the new canonical path (`~/nova-workspace/scripts/pg-notify-listener.py` or wherever F-1/OQ-1 lands it) if the domain-integration coverage is still wanted in nova-mind's `lib/pg_env.py` suite, or
  - (b) relocated alongside the listener itself into the target repo's test suite, with a clear cross-reference comment left in `test_pg_env.py` explaining the move.
  - **Whichever is chosen, the test file must NOT be left with a dangling hardcoded path that silently `FAIL`s with a cryptic "file not found" the next time someone runs the full suite.** This is graded as a hard requirement, not a nice-to-have — it was found by code inspection, not by the issue author, and is exactly the kind of gap that caused #612 in the first place (undiscovered cross-file coupling).

**TC-9 — Post-removal `git grep` sweep: zero live-code references remain**
- **Repo/Suite:** nova-mind, bats or a standalone script check (`tests/install/test_agent_install_pg_notify_removal.bats`, additional `@test`)
- **Steps:** `git grep -ln "pg-notify-listener\|pg_notify_listener" -- ':!CHANGELOG.md' ':!cognition/CHANGELOG.md' ':!*.md'`
- **Expected:** Zero hits outside markdown/changelog files. (Docs and CHANGELOGs are explicitly allowed to retain historical references per the task brief — assert the *code* surface is clean, not the prose/history.)
- **Note:** `tests/TEST-CASES-ISSUE-579.md` and `reports/SE643-*.md` are `.md` and pre-existing design docs referencing the (correctly still-existing) nova-mind listener as a *comparison baseline* for the agent-chat listener design — these are historical artifacts, not live code, and should NOT be edited as part of this issue.

**TC-10 — Docs updated: `cognition/README.md`, `cognition/docs/system-level-controls.md`, `memory/docs/database-config.md`**
- **Repo/Suite:** nova-mind, manual/desk review (not automatable via bats)
- **Steps:** Review each doc reference.
  - `cognition/README.md` L62 — deployment bullet describing the listener must be removed or rewritten to point at the new canonical location.
  - `cognition/docs/system-level-controls.md` L117 — this is a **security-relevant** doc explaining why `sync_schema_to_github()` spoofs `OPENCLAW_AGENT_ID=gidget` on its git push. This explanation must follow the code to wherever it lands (nova-workspace and/or agent-chat) — if this doc is left in nova-mind describing code that no longer exists there, a future security auditor reading nova-mind's pre-push hook exception list will find no corresponding code and either file a false-positive bug or (worse) miss the real exception now living elsewhere.
  - `memory/docs/database-config.md` L165 — reference to `#405`'s repo-relative pg_env fix; update path reference.
- **Expected:** No doc describes code at a path that no longer exists; the identity-spoof explanation in particular is preserved and re-anchored, not dropped.

### Group D — Test relocation (nova-mind → nova-workspace)

**TC-11 — Regression guard: confirm zero sibling dependents of `cognition/tests/conftest.py` before deletion (F-4)**
- **Repo/Suite:** nova-mind, pre-flight check (run once, document result, not a standing test)
- **Steps:** `git grep -l "conftest\|listener_module\|git_repos\b" -- '*.py'` repo-wide, confirm only the 3 target files match.
- **Expected:** Exactly `cognition/tests/test_pg_notify_listener_issue_{399,506,508}.py` match and nothing else. **Already verified during design (see F-4)** — carry this check into the implementation PR as a documented pre-flight, since a future addition to the repo between now and implementation could change this.

**TC-12 — Relocated conftest.py fixtures still resolve correctly in new location**
- **Repo/Suite:** nova-workspace, pytest (new `tests/pg-notify-listener/conftest.py` or similar, path TBD by implementer)
- **Preconditions:** `conftest.py`'s `SCRIPT_PATH = Path(__file__).parent.parent / "scripts" / "pg-notify-listener.py"` — this relative path assumption (`../scripts/`) must be re-verified against nova-workspace's actual directory layout, since nova-workspace's `tests/` and `scripts/` dirs may not have the identical parent/child relationship nova-mind's `cognition/tests/` and `cognition/scripts/` did.
- **Expected:** `listener_module` fixture successfully loads the (now-reconciled, per F-5) listener module with no import errors.

**TC-13 — Full relocated suite passes: 27 (#399+#506) + 23 (#508) = 50 tests**
- **Repo/Suite:** nova-workspace, pytest
- **Steps:** `pytest tests/<new-path>/test_pg_notify_listener_issue_399.py tests/<new-path>/test_pg_notify_listener_issue_506.py tests/<new-path>/test_pg_notify_listener_issue_508.py -v`
- **Expected:** 50/50 pass, matching the pre-move pass count exactly (per CHANGELOG.md L249/L253 history: "Full suite: 27/27 pass" for #399+#506, "23 new tests" for #508).

**TC-14 — nova-mind's remaining test suite is unaffected by the relocation**
- **Repo/Suite:** nova-mind, full pytest run (`cognition/tests/` minus the 4 relocated/deleted files)
- **Expected:** Full remaining suite passes; no collection errors from pytest trying to discover a now-missing `conftest.py` fixture that some other file expected (already de-risked by TC-11, but this is the live-execution confirmation).

### Group E — Fork reconciliation (#461, F-5)

**TC-15 — Reconciled listener has feature parity: nova-mind's contributions preserved**
- **Repo/Suite:** nova-workspace, pytest (part of the relocated #399/#506/#508 suite, TC-13)
- **Expected:** Push retry/backoff (#399), branch-safety `_ensure_on_main()` (#506), PGUSER-based sender + self-safe recipients (#508), repo-relative `pg_env` loading (#405) are all present and tested in the reconciled module — i.e., simply confirm the relocated code is nova-mind's version (the more complete one per F-5 comparison table), not a merge that silently drops any of these.

**TC-16 — Reconciled listener has feature parity: nova-workspace's contributions preserved**
- **Repo/Suite:** nova-workspace, pytest (new tests, not previously existing anywhere — a genuine coverage gap per #461)
- **Preconditions:** None of the currently-relocating #399/#506/#508 suites test nova-workspace's #21 (DB reconnect w/ exponential backoff) or #22 (SIGHUP log FD reopen) features, because those features don't exist in the nova-mind source being relocated.
- **Steps:** New tests must be written (not just relocated) covering:
  - Reconnect-with-backoff behavior on connection loss (modeled on the pattern already proven in `agent-chat/tests/test_pg_notify_listener_chat.py::test_connect_with_retry_recovers_after_operational_error` and `test_poll_and_process_raises_connection_lost_*` — that suite already has this exact coverage for the *agent_chat* listener; port the same test pattern onto the reconciled nova_memory listener).
  - SIGHUP → log FD reopen via `os.dup2` (async-signal-safe) still functions after reconciliation.
- **Expected:** Both features present and passing; this closes the last open item in #461 (which #612 subsumes/supersedes for the nova_memory listener specifically).

**TC-17 — Reconciled `.service` unit file: no stale `~/clawd` paths, correct user-unit semantics**
- **Repo/Suite:** nova-workspace, static check (can be a bats test or a simple grep-based pytest)
- **Steps:** Inspect the final `pg-notify-listener.service` (and, if F-1/OQ-1 resolves to keeping/renaming the agent_chat listener there too, `pg-notify-listener-agent-chat.service`).
- **Expected:** No `~/clawd` references (per FILE_ACCESS deprecation policy — these are dead symlinks slated for removal); `WantedBy=default.target` not `multi-user.target` (correct for a `systemctl --user` unit, not a system unit — nova-workspace's *current* committed unit file incorrectly uses `multi-user.target` and `User=nova` inside a `[Service]` block, both of which are system-unit patterns misapplied to a user unit); portable Python interpreter path (not hardcoded `tts-venv`).

### Group F — nova-workspace: nova-only install path

**TC-18 — Nova-only installer script/mechanism exists for BOTH listeners under one entrypoint**
- **Repo/Suite:** nova-workspace, bats (new file, no prior installer convention exists in this repo per F-6 — implementer must create one)
- **Expected:** A single, discoverable install mechanism (script or documented manual steps) installs both `pg-notify-listener.py` (nova_memory) and the agent_chat listener (wherever F-1/OQ-1 lands it) when run as the `nova` account.

**TC-19 — Running the nova-workspace installer as a NON-nova account refuses cleanly**
- **Repo/Suite:** nova-workspace, bats
- **Preconditions:** Mock `whoami`/`getpass.getuser()` (or equivalent env override) to return `graybeard`.
- **Steps:** Run the installer.
- **Expected:** Exits with a clear warning (not a silent success, not a crash), installs zero files, enables zero services. This is **the single most important test in this entire design** — it directly prevents recurrence of the exact incident in #610/#612.

**TC-20 — Running the nova-workspace installer as `nova` succeeds and installs both units, idempotently**
- **Repo/Suite:** nova-workspace, bats
- **Steps:** Run twice in a sandboxed `$HOME` mocking `nova` as the current account.
- **Expected:** First run installs both `.py` files + both `.service` units, enables+starts both. Second run reports "up to date" / restarts cleanly, no duplicate cron/systemd entries (matches existing repo idempotency conventions, e.g. agent-chat's TC-02/TC-08 pattern).

**TC-21 — BVA: account-name comparison is exact-match, not prefix/substring**
- **Repo/Suite:** nova-workspace, bats
- **Steps:** Mock account name as `nova2`, `nova-staging`, `NOVA` (case variant), `nova ` (trailing space — defensive), each as a separate test case (equivalence partitioning: valid-exact, invalid-prefix-match, invalid-case, invalid-whitespace).
- **Expected:** All four are treated as non-nova (refuse to install) — guards against a naive `[[ "$USER" == nova* ]]` glob-style bug that would incorrectly admit `nova-staging` (a real, existing account per SYSTEM_CONTEXT/GLOBAL docs — `nova-staging` is explicitly the staging test account and must NEVER be treated as equivalent to production `nova` for a mechanism that pushes to shared repo main).

### Group G — agent_chat listener (existing code in agent-chat repo, F-1)

**TC-22 — Existing `agent-chat/install.sh` `_install_listener_unit()` gains nova-only account gating**
- **Repo/Suite:** agent-chat, bats (extend `tests/test_agent_chat_installer.bats`, which already has TC-29 for the `AGENT_CHAT_SKIP_LISTENER_UNIT=1` skip path)
- **Steps:** Run `install.sh` as non-nova account (mocked), with listener source files present and `AGENT_CHAT_SKIP_LISTENER_UNIT` unset.
- **Expected:** Listener unit is NOT installed (currently: TC-29 only covers the opt-in env-var skip; there is no test today for "installed on the wrong account," which is precisely the gap that produced the graybeard stray). **This is a net-new required test, not covered by any existing suite.**

**TC-23 — `agent-chat/install.sh` run as `nova` still installs the listener correctly (regression guard)**
- **Repo/Suite:** agent-chat, bats
- **Expected:** Existing TC-29-adjacent behavior (install/enable/restart) unchanged for the nova account — confirms the new gating in TC-22 is additive, not a regression on the legitimate path.

**TC-24 — NOTIFY subscription: `LISTEN schema_changed` on agent_chat DB (regression, already covered)**
- **Repo/Suite:** agent-chat, pytest (`tests/test_pg_notify_listener_chat.py` — already exists, `test_connect_with_retry_recovers_after_operational_error` and related). Confirm still passing after any relocation/rename per OQ-1/OQ-2.

**TC-25 — Dump + commit + push to agent-chat repo's schema.sql, not nova-mind's (regression, already covered)**
- **Repo/Suite:** agent-chat, pytest (`test_smoke_ddl_notification_dump_commit_push` already exists). Confirm still passing; confirm target path is `AGENT_CHAT_REPO/schema.sql` never `nova-mind/database/schema.sql`.

**TC-26 — Push protection: what happens on non-nova account / wrong credentials?**
- **Repo/Suite:** agent-chat, pytest + bats combined
- **Steps:** This has two layers to test separately:
  - (a) **Listener never runs at all on non-nova account** — covered by TC-22 (installer-level gating, the correct primary defense).
  - (b) **Defense in depth: if somehow started anyway (e.g., manual `python3 pg-notify-listener-chat.py` invocation on a non-nova account), does the git push get blocked?** Currently: NO application-level check exists — the script relies entirely on `_agent_chat_env['PGUSER']` from `postgres.json` and the git pre-push hook's `OPENCLAW_AGENT_ID=gidget` spoof for push authorization. **Neither of these actually validates "am I running as nova."** This is a real defense-in-depth gap: a non-nova account with its own `postgres.json` agent_chat credentials and its own git push access could run this script directly and it would attempt to push using the `gidget` identity spoof regardless of OS account. Flag as OQ-4 — recommend an explicit `getpass.getuser() != 'nova': exit 1` guard inside the script itself, not just the installer, as belt-and-suspenders.

**TC-27 — Reconnect behavior (regression, already covered per #583)**
- **Repo/Suite:** agent-chat, pytest (`test_connect_with_retry_recovers_after_operational_error`, `test_poll_and_process_raises_connection_lost_on_operational_error`, `test_poll_and_process_raises_connection_lost_when_conn_closed` — already exist and pass). Confirm unaffected by any rename/relocation from OQ-1/OQ-2.

### Group H — Cross-repo CI wiring

**TC-28 — nova-mind CI: no longer runs pg-notify-listener tests, does run `lib/tests/test_pg_env.py` with corrected/relocated TC-50/51**
- **Repo/Suite:** nova-mind CI config
- **Expected:** CI config (whatever runs `pytest cognition/tests/`) no longer references the 4 deleted files; `lib/tests/test_pg_env.py` still runs and passes per TC-8's resolution.

**TC-29 — nova-workspace CI: runs relocated pg-notify-listener tests + new installer bats**
- **Repo/Suite:** nova-workspace CI config
- **Expected:** New CI job (or extension of an existing one) runs the relocated 50 pytest tests (TC-13) and the new nova-only-gating bats suite (TC-18-21).

**TC-30 — agent-chat CI: existing suite + new gating tests**
- **Repo/Suite:** agent-chat CI config
- **Expected:** Existing 35+ bats tests and pytest suite continue running; TC-22/TC-23 (new gating tests) added to the same CI job, not a separate untested path.

---

## 4. Test Summary Table

| Group | Count | Repo(s) | Suite type |
|---|---|---|---|
| A — nova-mind installer removal | 5 (TC-1–5) | nova-mind | bats |
| B — upgrade/tombstone | 2 (TC-6–7) | nova-mind | bats + process/doc |
| C — repo hygiene | 3 (TC-8–10) | nova-mind | pytest + bats + manual |
| D — test relocation | 4 (TC-11–14) | nova-mind → nova-workspace | pytest |
| E — fork reconciliation | 3 (TC-15–17) | nova-workspace | pytest + static |
| F — nova-only install | 4 (TC-18–21) | nova-workspace | bats |
| G — agent_chat listener | 6 (TC-22–27) | agent-chat | bats + pytest |
| H — CI wiring | 3 (TC-28–30) | all three | CI config |
| **Total** | **30** | | |

---

## 5. Open Questions for Orchestrator/PL Review

**OQ-1 (blocking, highest priority):** Given F-1 — the agent_chat listener
already exists, tracked, in `NOVA-Openclaw/agent-chat`, with its own
unconditional installer that is the probable actual root cause of the
graybeard stray — should the canonical home be:
  - (a) **agent-chat repo** (where it already lives, where the schema it
    syncs already lives, requiring only: add nova-only gating to
    `install.sh`, optionally rename per F-2), or
  - (b) **nova-workspace** per the issue's literal text (requiring: extract
    from agent-chat, relocate, re-wire agent-chat's own installer to no
    longer ship it, decide how nova-workspace's install path pulls
    agent_chat DB credentials)?

  (a) is significantly less invasive and fixes the actual incident
  mechanism directly. (b) matches the issue's stated design intent
  ("both listeners... in nova-workspace") but requires justifying why a
  schema-sync listener for the `agent-chat` repo's own schema should live
  in a *third*, unrelated repo rather than beside the schema it syncs.
  **This decision changes which of TC-18/20 (nova-workspace two-listener
  install) vs TC-22/23 (agent-chat gated install) are the primary fix vs.
  the secondary/no-op path.**

**OQ-2:** If OQ-1 resolves to (a) or a relocated (b), does the script get
renamed from `pg-notify-listener-chat.py` to
`pg-notify-listener-agent-chat.py` per the issue's explicit naming
directive? This affects `.service` `ExecStart=` paths and every test file
path in Group G.

**OQ-3 (blocking):** Tombstone/cleanup decision for TC-6 — does the fixed
nova-mind installer actively detect-and-remove a pre-existing listener
install left over from a stale pre-#612 binary, or is that permanently
Graybeard's one-time containment responsibility with a documented residual
risk? Recommend active cleanup (option (a) in TC-6) given the severity
class of the original incident, but this is I)ruid's call per the issue's
"design intent" framing.

**OQ-4 (non-blocking, defense-in-depth):** Should the listener script(s)
themselves carry an internal `getpass.getuser() != 'nova': sys.exit(1)`
guard (TC-26b), independent of installer-level gating? Installer gating
(TC-19/22) is the primary, correct fix; an in-script guard is belt-and-
suspenders against someone manually invoking the script outside the
installer's control (e.g., copy-pasted to another account, run under a
debugger, etc.). Low cost to add, recommend yes.

**OQ-5:** Item 5 of the issue's required changes ("verify no other
local-only tooling is riding the shared installer the same way") — should
this test-case design's scope extend to a full audit of every function
call in `agent-install.sh` for account-gating gaps, or is that a separate
follow-up issue? Given F-1's discovery that the *sibling* repo's installer
has the identical bug, I recommend treating this as in-scope for THIS
issue at minimum for the two installers directly implicated
(`agent-install.sh`, `agent-chat/install.sh`), with a broader
ecosystem-wide audit filed as a distinct follow-up issue if not already
tracked.

**OQ-6:** Should `tests/TEST-CASES-ISSUE-579.md` (which documents the
original agent_chat listener design and references the nova-mind listener
as an explicit baseline-for-comparison) be updated with a pointer to this
new test-case design once #612 lands, so future readers don't have to
reconstruct the relationship between the two documents? Low cost,
recommend yes, non-blocking.

---

**Report path:** `~/nova-mind/evals/se717/test-case-design-v1.md`
