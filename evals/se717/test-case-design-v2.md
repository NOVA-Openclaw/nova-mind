# Test Cases — nova-mind#612: Remove pg-notify-listener local tooling from nova-mind + installer

**SE run #717, step 3 → step 4 (+ correction) — QA test-case design (v2, rulings incorporated, OQ-3 corrected in Rev 3)**
**Author:** Gem (QA Lead)
**Inputs read in full (v1):** `gh issue view 612` (body + comment thread),
`agent-install.sh` (`_install_pg_notify_listener` ~L410-455, call site
~L1893-1908), `git grep -ln "pg-notify-listener"` full repo surface,
`cognition/tests/conftest.py`,
`cognition/tests/test_pg_notify_listener_issue_{399,506,508}.py`,
`lib/tests/test_pg_env.py`, `cognition/README.md`,
`cognition/docs/system-level-controls.md`, `memory/docs/database-config.md`,
`CHANGELOG.md` / `cognition/CHANGELOG.md`, live filesystem state of
`~/nova-workspace` and `~/agent-chat` (including `~/agent-chat/install.sh`,
`~/agent-chat/listener/pg-notify-listener-chat.py`,
`~/agent-chat/tests/test_agent_chat_installer.bats`,
`~/agent-chat/tests/test_pg_notify_listener_chat.py`), issues #461, #579,
#581, #583, #610.
**Inputs added for v2:** SE #717 step 4 orchestrator review + I)ruid rulings
on v1 §5 open questions (verbatim ruling text quoted below where relevant).

---

## Revision Log

**Rev 3 (this document, step 4 correction — OQ-3 reversed):**
- **OQ-3 REVERSED by I)ruid.** Rev 2 (below) had resolved OQ-3 as "active cleanup required" —
  both nova-mind's and agent-chat's fixed installers detecting and removing
  pre-existing listener installs on upgrade. **This is now explicitly wrong.**
  I)ruid's corrected ruling: **no tombstone/active-cleanup logic in either
  installer, ever.** Graybeard's containment of already-running instances on
  affected peers is a one-time, permanent, manual operation — not something
  the installer takes over going forward. The fix for both installers is
  **pure removal**: they simply stop referencing the listeners at all, with
  the same shape as Group A's nova-mind removal tests (fresh install → zero
  artifacts, function gone, no lingering upgrade-path code branch to test).
  **Group B (nova-mind upgrade/tombstone, v2's TC-6/TC-7) and TC-25
  (agent-chat's symmetric tombstone) are retired below, not merely edited —
  their underlying requirement no longer exists.** See each retired entry for
  the full correction note.
- **Design principle reaffirmed for the record (unchanged, restated
  explicitly per I)ruid):** a schema-sync listener must never live in the
  repo whose schema it pushes to. This is why the agent_chat listener
  cannot live in `agent-chat` (OQ-1) and, by the same logic, why the
  nova_memory listener was never appropriate living in `nova-mind`. Added as
  a new invariant, INV-6, in §2.
- All other Rev 2 rulings stand unchanged: OQ-1 (nova-workspace canonical
  for both listeners), OQ-2 (rename to `pg-notify-listener-agent-chat.py`),
  OQ-4 (in-script `getpass.getuser()` guard, yes), OQ-5 (audit scope: the
  two implicated installers only), OQ-6 (update the #579 test-design
  pointer). See §5 for the updated rulings table.

**Rev 2 (step 4 — initial rulings incorporated, since partially corrected by Rev 3 above):**
- **OQ-1 RESOLVED — nova-workspace is canonical for BOTH listeners** (I)ruid,
  verbatim: *"That listener should NOT be in the agent-chat repo, it's local
  tooling, not part of the agent-chat distribution. Remove that from that
  repo and make sure it's tracked in nova-workspace."*). Scope is now
  **three repos**, not two. Group G completely reshaped: agent-chat's side
  of the fix is now **pure removal** (per the Rev 3 OQ-3 correction: no
  tombstone/cleanup logic either, just removal), not gating (v1 TC-22/23
  proposed adding nova-only account gating to agent-chat's installer — that
  approach is superseded; the correct fix is removing the listener from
  agent-chat entirely, matching the shape of Group A for nova-mind).
- **OQ-2 RESOLVED — rename to `pg-notify-listener-agent-chat.py`** per the
  issue's original naming directive. Added TC-17A (naming consistency
  static check) and updated TC-18's expected result to name both files
  explicitly.
- **OQ-3 RESOLVED — active cleanup required, not optional** (orchestrator,
  accepting Gem's TC-6 option (a) recommendation). TC-6 rewritten from a
  two-branch "flagged design decision" into a single firm requirement.
  Symmetric requirement added for agent-chat's installer (new TC-25, Group
  G) since OQ-1 means agent-chat's installer also needs an active
  cleanup/tombstone step for hosts that already have
  `pg-notify-listener-chat.py`/`.service` installed from a prior run.
- **OQ-4 RESOLVED — yes, add in-script `getpass.getuser()` guard** to both
  nova-workspace listeners, independent of installer-level gating. New
  TC-28 (Group G).
- **OQ-5 RESOLVED — audit scope is the two implicated installers only**
  (`agent-install.sh`, `agent-chat/install.sh`); ecosystem-wide audit is a
  separate follow-up issue owned by the orchestrator, out of scope here.
  No test-case change required — TC-9's git-grep sweep already covers
  nova-mind; TC-27 (Group G) adds the equivalent sweep for agent-chat.
- **OQ-6 RESOLVED — yes, update the `TEST-CASES-ISSUE-579.md` pointer.**
  Folded into TC-10 (Group C) as an explicit sub-item rather than a new TC
  number, since it's the same "doc hygiene" activity already covered there.
- **TC numbering:** Groups A–F (TC-1–21) are **unchanged from v1** except
  light wording edits where a v1 "flagged decision" became a firm
  requirement (TC-6, TC-18) and one net-new insertion (TC-17A, lettered to
  avoid renumbering its neighbors). Group G (TC-22–29) is **fully rewritten**
  — same TC-number range, new content, since its role changed from "gate
  agent-chat's listener" to "remove agent-chat's listener + verify
  cleanup," and it now needs two more slots (TC-28, TC-29) than v1's Group G
  did. Group H shifts numbers accordingly: v1 TC-28–30 → v2 **TC-30–32**
  (content equivalent, agent-chat's CI entry revised to reflect
  removal-verification instead of gating-verification).
- **New non-blocking open question (OQ-7)** added at end regarding whether
  agent-chat's existing `test_pg_notify_listener_chat.py` suite gets merged
  into the reconciled nova-workspace test module or kept as a parallel file
  — an implementation detail, not a design blocker.

**Rev 1 (SE #717, step 3):** Initial design. See `test-case-design-v1.md`
in this directory for the full original document, including findings F-1
through F-6 (all still valid and referenced below) and the original v1 §5
open questions (all resolved above).

---

## 0. Critical Findings (carried forward from v1, all confirmed correct by rulings)

### F-1 — The agent_chat listener already exists; it does NOT belong in agent-chat (RULING: confirmed, relocate)

Issue #612's comment thread directed creating
`pg-notify-listener-agent-chat.py` "from scratch" in nova-workspace. v1
found this premise stale: the functional equivalent
(`pg-notify-listener-chat.py`) already exists, tracked in git, in
`NOVA-Openclaw/agent-chat`, installed **unconditionally** by that repo's own
`install.sh` — the identical ungated-install bug class as the nova-mind
issue, in a sibling repo. The graybeard stray reported in #612's comment
(same filename, `pg-notify-listener-chat.py`) is almost certainly explained
by this, not a mystery hook.

**I)ruid's ruling makes the fix directive explicit and unambiguous:** this
code must be **removed from agent-chat entirely** (it is local tooling that
does not belong in a distributable shared repo, full stop — not merely
"gate it so peers can't trigger it") and **relocated to nova-workspace**,
where it joins the nova_memory listener as the second of two canonical,
nova-only listeners. This resolves OQ-1 in favor of option (b) from v1.
Group G is rewritten below to match: agent-chat's side of this fix now has
the **same shape as nova-mind's** (Group A) — delete the code, delete the
installer wiring, pure removal with **no** tombstone/cleanup step (per the
Rev 3 OQ-3 correction below) — rather than either the "add account gating"
approach v1 proposed, or the tombstone approach this document briefly
ruled in Rev 2 before I)ruid's correction.

### F-2 — Naming (RULING: rename confirmed)

Per the issue's original naming directive, standardize on
`pg-notify-listener-agent-chat.py` (not `pg-notify-listener-chat.py`, the
name the agent-chat-repo copy currently uses). Confirmed by ruling. See
TC-17A.

### F-3 — `lib/tests/test_pg_env.py` has a hard path dependency that WILL break silently

Unchanged from v1 — `lib/tests/test_pg_env.py` TC-50/TC-51 (L567-614)
`importlib.util.spec_from_file_location` the listener script directly at a
hardcoded repo-relative path. This must be rewritten or relocated, not left
dangling. See TC-8.

### F-4 — `cognition/tests/conftest.py` is nova-mind's *only* conftest.py

Unchanged from v1 — repo-wide grep confirmed zero other consumers. De-risks
the relocation. See TC-11.

### F-5 — nova-workspace's *committed* copy of `pg-notify-listener.py` is a stale fork, not the deployed one

Unchanged from v1 — this is a fork reconciliation (#461), not a file move.
nova-mind's copy has #399/#506/#508/#405; nova-workspace's committed copy
has #21/#22 that nova-mind's lacks. **This reconciliation is now the
primary fix path** for the nova_memory listener (not a contingent branch —
OQ-1's ruling confirms nova-workspace is canonical regardless of which way
OQ-1 had gone). See TC-15-17.

### F-6 — No account-gating precedent exists anywhere in either installer today

Unchanged from v1, though its implication shifts slightly: since OQ-1
resolved to **removal** rather than gating for agent-chat's installer, the
account-gating pattern this finding describes is now needed **only** in
nova-workspace's own (new, to-be-created) install mechanism for the two
canonical listeners — not in either shared installer, which should carry
zero listener-install code of any kind, gated or otherwise, once this issue
lands.

---

## 1. Scope Recap (updated — three repos)

| # | Requirement | Repo(s) affected | Shape of fix |
|---|---|---|---|
| 1 | Remove `pg-notify-listener.py`/`.service` from nova-mind; drop `_install_pg_notify_listener` + call site | nova-mind | Pure removal (no tombstone/cleanup logic, per Rev 3) |
| 2 | Relocate `test_pg_notify_listener_issue_{399,506,508}.py` + `conftest.py` fixtures | nova-mind → nova-workspace | Move + reconcile |
| 3 | nova-workspace canonical home; install/enable nova-only there | nova-workspace | New nova-only install mechanism |
| 4 | Second listener for `agent_chat` DB → syncs `agent-chat` repo schema | nova-workspace (relocated **from** agent-chat, per OQ-1 ruling) | Move + rename + reconcile |
| 5 | Installer audit: no other local-only tooling on shared installer | nova-mind **and agent-chat** (OQ-5: these two only; ecosystem audit is a separate follow-up issue) | Pure removal (agent-chat now mirrors nova-mind's shape exactly — remove, do not gate or tombstone) |

**Note (Rev 3):** Existing/legacy peer installs (the artifacts Graybeard's
containment already handled, and any not yet found) are explicitly OUT of
scope for installer-side remediation. Both installers become simpler with
this correction — no upgrade-path branch to design, implement, or test.

---

## 2. Invariants Under Test (updated)

- **INV-1:** A fresh `agent-install.sh` run, on any account, installs zero
  pg-notify-listener files and starts zero listener services.
- **INV-1b (new):** A fresh `agent-chat/install.sh` run, on any account,
  installs zero pg-notify-listener-\* files and starts zero listener
  services. (Same invariant as INV-1, now applying to the second shared
  installer per OQ-1's ruling.)
- **INV-2:** No listener authenticates as, or can push as, any account other
  than nova. Enforced at **two** layers now: installer-level gating (nova-
  workspace's own install mechanism, Group F) and an in-script runtime
  guard (Group G, TC-28, per OQ-4).
- **INV-3:** Test relocation preserves 100% of existing assertions — the
  27 #399+#506 + 23 #508 = 50 nova-mind-origin tests, **plus** agent-chat's
  own existing listener test suite (`test_pg_notify_listener_chat.py`,
  ~10 tests) — all relocate to nova-workspace and pass, with zero
  regression in either source repo's remaining suite.
- **INV-4:** Both nova_memory and agent_chat listeners are installable,
  idempotently, from a single nova-only-gated entrypoint in nova-workspace
  (the canonical repo, no longer contingent on OQ-1 — this is now
  unconditionally the design).
- **INV-5 (tightened):** Neither shared/peer-run installer (nova-mind's
  `agent-install.sh` **or** agent-chat's `install.sh`) installs, enables, or
  ships listener code in **any** form — gated or ungated — once this issue
  lands. The only listener-install code in the entire ecosystem lives in
  nova-workspace's own nova-only mechanism.
- **INV-6 (new, Rev 3):** Neither shared installer contains ANY
  upgrade-path, detection, or cleanup logic referencing the listeners —
  pure removal only. Corollary design principle, restated verbatim per
  I)ruid for the record: **a schema-sync listener must never live in the
  repo whose schema it pushes to.** This is the generalized rule that both
  explains why the agent_chat listener cannot live in `agent-chat` (OQ-1)
  and why the nova_memory listener was never correctly placed in
  `nova-mind` to begin with. Existing/legacy installs on already-affected
  peers remain Graybeard's one-time, permanent, manual containment
  responsibility — never re-absorbed into installer logic.

---

## 3. Test Cases

### Group A — nova-mind installer: clean removal (unchanged from v1)

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

### Group B — RETIRED in Rev 3 (was: nova-mind upgrade / tombstone path)

**TC-6 and TC-7 are retired, not merely edited.** Rev 2 designed this group
around an "active cleanup required" ruling (OQ-3) that I)ruid explicitly
reversed at step 4 correction: **no installer-side detection, removal, or
tombstone logic for pre-existing listener installs, on either installer,
ever.** Graybeard's containment of already-affected peers is a one-time,
permanent, manual operation — the fixed installers simply stop referencing
the listeners at all (pure removal, same shape as Group A), with no
upgrade-path branch to test.

These TC numbers are intentionally left **retired rather than reassigned**
so the revision history stays traceable if this document is read
standalone in the future — a reader hitting "TC-6" in a cross-reference
elsewhere should find this retirement note, not silent renumbering. No
replacement test cases are needed in this slot: Group A's TC-1–5 already
fully cover the pure-removal requirement for nova-mind, and their mirror in
Group G (TC-22–24, also revised in Rev 3 below) covers agent-chat.

### Group C — Repo hygiene / cross-reference sweep (unchanged from v1, TC-10 expanded per OQ-6)

**TC-8 — `lib/tests/test_pg_env.py` TC-50/TC-51 do not silently break (F-3)**
- **Repo/Suite:** nova-mind, pytest (`lib/tests/test_pg_env.py`)
- **Preconditions:** `cognition/scripts/pg-notify-listener.py` removed per TC-1.
- **Steps:** Run `lib/tests/test_pg_env.py` in full.
- **Expected:** TC-50/TC-51 (the two tests that `importlib.util.spec_from_file_location` the listener script directly) must be either:
  - (a) rewritten to point at the new canonical path (`~/nova-workspace/scripts/pg-notify-listener.py`), or
  - (b) relocated alongside the listener itself into nova-workspace's test suite, with a clear cross-reference comment left in `test_pg_env.py` explaining the move.
  - **Whichever is chosen, the test file must NOT be left with a dangling hardcoded path that silently `FAIL`s with a cryptic "file not found" the next time someone runs the full suite.** Hard requirement, found by code inspection, not by the issue author — exactly the kind of undiscovered cross-file coupling that caused #612 in the first place.

**TC-9 — Post-removal `git grep` sweep: zero live-code references remain (nova-mind)**
- **Repo/Suite:** nova-mind, bats or a standalone script check (`tests/install/test_agent_install_pg_notify_removal.bats`, additional `@test`)
- **Steps:** `git grep -ln "pg-notify-listener\|pg_notify_listener" -- ':!CHANGELOG.md' ':!cognition/CHANGELOG.md' ':!*.md'`
- **Expected:** Zero hits outside markdown/changelog files. Docs and CHANGELOGs are explicitly allowed to retain historical references.
- **Note:** `tests/TEST-CASES-ISSUE-579.md` and `reports/SE643-*.md` are pre-existing design docs referencing the (correctly still-existing at time of writing, now relocated) nova-mind listener as a comparison baseline — historical artifacts, addressed separately in TC-10, not part of this sweep.

**TC-10 — Docs updated: `cognition/README.md`, `cognition/docs/system-level-controls.md`, `memory/docs/database-config.md`, `tests/TEST-CASES-ISSUE-579.md` pointer (OQ-6 folded in here)**
- **Repo/Suite:** nova-mind, manual/desk review (not automatable via bats)
- **Steps:** Review each doc reference.
  - `cognition/README.md` L62 — deployment bullet describing the listener must be removed or rewritten to point at nova-workspace.
  - `cognition/docs/system-level-controls.md` L117 — **security-relevant**: explains why `sync_schema_to_github()` spoofs `OPENCLAW_AGENT_ID=gidget` on its git push. This explanation must follow the code to nova-workspace, re-anchored there, not dropped — a future security auditor reading nova-mind's pre-push hook exception list must not find no corresponding code and either file a false-positive or miss the real exception now living elsewhere.
  - `memory/docs/database-config.md` L165 — reference to `#405`'s repo-relative pg_env fix; update path reference to nova-workspace.
  - **(OQ-6, new in v2)** `tests/TEST-CASES-ISSUE-579.md` — this document describes the original agent_chat listener design and uses the nova-mind listener as an explicit comparison baseline. Add a pointer/cross-reference noting that both listeners (nova_memory and agent_chat) have since relocated to nova-workspace per #612, so a future reader isn't left reconstructing the relationship between the two documents from scratch.
- **Expected:** No doc describes code at a path that no longer exists; the identity-spoof explanation is preserved and re-anchored; the #579 test-design doc carries a forward pointer to #612's outcome.

### Group D — Test relocation, nova-mind's 3 files → nova-workspace (unchanged from v1)

**TC-11 — Regression guard: confirm zero sibling dependents of `cognition/tests/conftest.py` before deletion (F-4)**
- **Repo/Suite:** nova-mind, pre-flight check (run once, document result, not a standing test)
- **Steps:** `git grep -l "conftest\|listener_module\|git_repos\b" -- '*.py'` repo-wide, confirm only the 3 target files match.
- **Expected:** Exactly `cognition/tests/test_pg_notify_listener_issue_{399,506,508}.py` match and nothing else. **Already verified during v1 design (see F-4)** — carry this check into the implementation PR as a documented pre-flight, since a future repo addition between now and implementation could change this.

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

### Group E — Fork reconciliation for the nova_memory listener (#461, F-5) — now the primary fix path, not contingent

**TC-15 — Reconciled listener has feature parity: nova-mind's contributions preserved**
- **Repo/Suite:** nova-workspace, pytest (part of the relocated #399/#506/#508 suite, TC-13)
- **Expected:** Push retry/backoff (#399), branch-safety `_ensure_on_main()` (#506), PGUSER-based sender + self-safe recipients (#508), repo-relative `pg_env` loading (#405) are all present and tested in the reconciled module — i.e., confirm the relocated code is nova-mind's version (the more complete one per F-5 comparison table), not a merge that silently drops any of these.

**TC-16 — Reconciled listener has feature parity: nova-workspace's contributions preserved**
- **Repo/Suite:** nova-workspace, pytest (new tests, not previously existing anywhere — a genuine coverage gap per #461)
- **Preconditions:** None of the currently-relocating #399/#506/#508 suites test nova-workspace's #21 (DB reconnect w/ exponential backoff) or #22 (SIGHUP log FD reopen) features, because those features don't exist in the nova-mind source being relocated.
- **Steps:** New tests must be written covering:
  - Reconnect-with-backoff behavior on connection loss (model on the pattern already proven in `agent-chat/tests/test_pg_notify_listener_chat.py::test_connect_with_retry_recovers_after_operational_error` and `test_poll_and_process_raises_connection_lost_*` — port the same test pattern onto the reconciled nova_memory listener).
  - SIGHUP → log FD reopen via `os.dup2` (async-signal-safe) still functions after reconciliation.
- **Expected:** Both features present and passing; this closes the last open item in #461 for the nova_memory listener specifically.

**TC-17 — Reconciled `.service` unit file: no stale `~/clawd` paths, correct user-unit semantics**
- **Repo/Suite:** nova-workspace, static check (bats or a simple grep-based pytest)
- **Steps:** Inspect the final `pg-notify-listener.service`.
- **Expected:** No `~/clawd` references (deprecated symlink, per FILE_ACCESS policy — slated for removal); `WantedBy=default.target` not `multi-user.target` (correct for a `systemctl --user` unit — nova-workspace's *current* committed unit file incorrectly uses `multi-user.target` and a `User=` directive, both system-unit patterns misapplied to a user unit); portable Python interpreter path (not hardcoded `tts-venv`).

**TC-17A (new in v2) — Naming consistency for the renamed agent_chat listener (F-2 / OQ-2 ruling)**
- **Repo/Suite:** nova-workspace, static check (bats or grep-based pytest)
- **Steps:** Grep the relocated agent_chat listener's script filename, `.service` unit filename, `.service`'s `ExecStart=`/`WorkingDirectory=` paths, and any log-path constants for consistent use of `pg-notify-listener-agent-chat` (not the agent-chat-repo-origin name `pg-notify-listener-chat`).
- **Expected:**
  - Script file is named `pg-notify-listener-agent-chat.py`
  - Service unit is named `pg-notify-listener-agent-chat.service`
  - `ExecStart=` and `WorkingDirectory=` inside the unit reference the renamed script path, not a leftover `pg-notify-listener-chat.py` path
  - No stray references to the old `pg-notify-listener-chat` name remain anywhere in the relocated code (git-grep sweep, same style as TC-9/TC-27)
- **Rationale:** A rename-in-place is an easy step to half-finish (rename the file but leave the `.service`'s `ExecStart=` pointing at the old name, which would silently fail to start post-relocation) — worth a dedicated, cheap static check rather than folding into a larger integration test where the failure mode would be a confusing runtime error instead of an obvious grep mismatch.

### Group F — nova-workspace: nova-only install path for BOTH listeners (updated framing — this is now the primary, unconditional design, per OQ-1 ruling)

**TC-18 — Nova-only installer script/mechanism exists for BOTH listeners under one entrypoint (naming made explicit per OQ-2)**
- **Repo/Suite:** nova-workspace, bats (new file — no prior installer convention exists in this repo per F-6, implementer must create one)
- **Expected:** A single, discoverable install mechanism (script or documented manual steps) installs both `pg-notify-listener.py` (nova_memory) **and** `pg-notify-listener-agent-chat.py` (agent_chat, relocated + renamed per OQ-1/OQ-2 rulings) when run as the `nova` account.

**TC-19 — Running the nova-workspace installer as a NON-nova account refuses cleanly**
- **Repo/Suite:** nova-workspace, bats
- **Preconditions:** Mock `whoami`/`getpass.getuser()` (or equivalent env override) to return `graybeard`.
- **Steps:** Run the installer.
- **Expected:** Exits with a clear warning (not a silent success, not a crash), installs zero files, enables zero services. **The single most important test in this entire design** — directly prevents recurrence of the exact incident in #610/#612.

**TC-20 — Running the nova-workspace installer as `nova` succeeds and installs both units, idempotently**
- **Repo/Suite:** nova-workspace, bats
- **Steps:** Run twice in a sandboxed `$HOME` mocking `nova` as the current account.
- **Expected:** First run installs both `.py` files + both `.service` units, enables+starts both. Second run reports "up to date" / restarts cleanly, no duplicate cron/systemd entries (matches existing repo idempotency conventions, e.g. agent-chat's TC-02/TC-08 pattern — ironic given TC-22 below removes that exact repo's copy, but the *pattern* is worth reusing).

**TC-21 — BVA: account-name comparison is exact-match, not prefix/substring**
- **Repo/Suite:** nova-workspace, bats
- **Steps:** Mock account name as `nova2`, `nova-staging`, `NOVA` (case variant), `nova ` (trailing space — defensive), each as a separate test case (equivalence partitioning: valid-exact, invalid-prefix-match, invalid-case, invalid-whitespace).
- **Expected:** All four are treated as non-nova (refuse to install) — guards against a naive `[[ "$USER" == nova* ]]` glob-style bug that would incorrectly admit `nova-staging` (a real, existing account per SYSTEM_CONTEXT/GLOBAL docs — `nova-staging` is explicitly the staging test account and must NEVER be treated as equivalent to production `nova` for a mechanism that pushes to shared repo main).

### Group G — agent-chat repo: REMOVAL (completely rewritten per OQ-1 ruling — was "add gating," is now "remove entirely, no tombstone," mirroring Group A's shape; TC-25's tombstone case retired per Rev 3)

**TC-22 — Fresh `agent-chat/install.sh` run produces zero listener artifacts (mirrors nova-mind's TC-1)**
- **Repo/Suite:** agent-chat, bats (extend `tests/test_agent_chat_installer.bats`)
- **Preconditions:** `listener/` directory (containing `pg-notify-listener-chat.py` + `.service`) deleted from the agent-chat repo per the ruling; `_install_listener_unit()` function + its two call sites (`main()`'s L316 up-to-date branch and L326 fresh-install branch) removed from `install.sh`.
- **Steps:** Run `install.sh` end-to-end in a sandboxed environment.
- **Expected:**
  - `$HOME/.openclaw/scripts/pg-notify-listener-chat.py` does NOT exist
  - `$HOME/.config/systemd/user/pg-notify-listener-chat.service` does NOT exist
  - Installer output contains no listener-install section
  - **Note:** `AGENT_CHAT_SKIP_LISTENER_UNIT` env var and the existing v1-era TC-29 test (`"installer skips listener unit when AGENT_CHAT_SKIP_LISTENER_UNIT=1"`) become **dead/obsolete** once the function is deleted — this test must itself be removed (asserting behavior of a code path that no longer exists is worse than no test at all, since a future refactor could silently reintroduce the pattern without this test noticing, believing it still guards something).

**TC-23 — `_install_listener_unit` function no longer defined in agent-chat's `install.sh` (mirrors nova-mind's TC-2)**
- **Repo/Suite:** agent-chat, bats
- **Steps:** `grep -c '_install_listener_unit' install.sh`
- **Expected:** count is 0.

**TC-24 — agent-chat `install.sh` passes `bash -n` and ShellCheck clean post-removal (mirrors nova-mind's TC-3/TC-4)**
- **Repo/Suite:** agent-chat, bats (existing `"install.sh passes bash -n"` and `"ShellCheck: zero warnings on install.sh"` tests already exist in `test_agent_chat_installer.bats` — confirm they still pass after the removal edit, no new test needed beyond re-running them).

**TC-25 — RETIRED in Rev 3 (was: agent-chat installer actively removes a PRE-EXISTING listener install on upgrade)**

Retired for the same reason as Group B's TC-6/TC-7 above: I)ruid's OQ-3
reversal means agent-chat's installer gets the identical pure-removal
treatment as nova-mind's — no detection/cleanup/tombstone logic at all, no
upgrade-path branch. TC-22 (fresh install produces zero artifacts) and
TC-23/TC-24 (function gone, static checks clean) already fully cover the
required behavior. This slot is left retired rather than reassigned, same
traceability rationale as Group B.

**TC-26 — agent-chat's own listener test suite relocates alongside the code (not simply deleted)**
- **Repo/Suite:** agent-chat → nova-workspace, pytest
- **Preconditions:** `agent-chat/tests/test_pg_notify_listener_chat.py` (~10 tests: `test_alert_recipients_excludes_sender`, `test_alert_recipients_broadcast_when_all_excluded`, `test_classify_push_failure`, `TestSchemaChangeProcessor`, `test_lock_skip_when_already_held`, `test_lock_acquired_when_free`, `test_connect_with_retry_recovers_after_operational_error`, `test_poll_and_process_raises_connection_lost_on_operational_error`, `test_poll_and_process_raises_connection_lost_when_conn_closed`, `test_smoke_ddl_notification_dump_commit_push`) exists today and is the **only** existing test coverage for the agent_chat listener's push/lock/reconnect logic.
- **Expected:** These tests relocate to nova-workspace alongside the renamed `pg-notify-listener-agent-chat.py`, updated for the new filename/import path, and continue passing — folded into the same reconciled test suite location as TC-13/TC-15/TC-16 (Group E/D), not left behind as dead coverage in a repo that no longer has the code to test. See OQ-7 for the open implementation-detail question of exactly how these merge with the nova-mind-origin #399/#506/#508 suite.

**TC-27 — Post-removal `git grep` sweep on agent-chat: zero live-code references remain (mirrors nova-mind's TC-9)**
- **Repo/Suite:** agent-chat, bats or standalone script check
- **Steps:** `git grep -ln "pg-notify-listener\|pg_notify_listener\|_install_listener_unit" -- ':!CHANGELOG.md' ':!*.md'`
- **Expected:** Zero hits outside markdown/changelog files (agent-chat's own CHANGELOG.md entries documenting the original listener's addition and its relocation are historical record, not live code — allowed to remain).

**TC-28 (new in v2) — In-script `getpass.getuser()` runtime guard on BOTH relocated listeners (OQ-4 ruling: defense-in-depth, required)**
- **Repo/Suite:** nova-workspace, pytest (both `pg-notify-listener.py` and `pg-notify-listener-agent-chat.py`)
- **Preconditions:** Listener module importable in a test harness with `getpass.getuser` monkeypatched.
- **Steps:** Monkeypatch `getpass.getuser()` to return a non-`nova` value (e.g. `graybeard`), then invoke the listener's entrypoint/`main()`.
- **Expected:** Listener exits immediately (non-zero exit code) with a clear log message identifying the account mismatch, **before** attempting any DB connection, `LISTEN`, or git operation. This is explicitly **independent of and in addition to** installer-level gating (TC-19/TC-21) — it protects against the residual case of someone manually invoking the script outside the installer's control (copy-paste to another account, run under a debugger, cron entry surviving an account rename, etc.). Applies to both listeners identically; test once per listener, same assertion.
- **BVA:** Also test the exact-match account name edge cases from TC-21 (`nova-staging`, `NOVA` case variant, trailing whitespace) at the in-script guard layer too — a defense-in-depth guard that itself has a prefix-match bug provides false confidence.

**TC-29 (new in v2) — agent-chat's `README.md` no longer describes a listener it doesn't ship (doc hygiene, mirrors nova-mind's TC-10)**
- **Repo/Suite:** agent-chat, manual/desk review
- **Steps:** Review `README.md` L59 ("Schema sync: `listener/pg-notify-listener-chat.py`...") and the full "## Schema-sync listener" section (L92-145ish) describing deployment, reconnect behavior, and safety machinery.
- **Expected:** This section is either removed entirely or rewritten to state that agent_chat's schema-sync listener is local nova tooling maintained in nova-workspace (with a pointer, not full re-documentation — the full behavioral description belongs with the code in nova-workspace) — matching the doc-hygiene bar set in TC-10 for nova-mind.

### Group H — Cross-repo CI wiring (renumbered from v1 TC-28–30 due to Group G expansion; content equivalent except agent-chat's entry, which is revised)

**TC-30 (was TC-28 in v1) — nova-mind CI: no longer runs pg-notify-listener tests, does run `lib/tests/test_pg_env.py` with corrected/relocated TC-50/51**
- **Repo/Suite:** nova-mind CI config
- **Expected:** CI config (whatever runs `pytest cognition/tests/`) no longer references the 4 deleted files; `lib/tests/test_pg_env.py` still runs and passes per TC-8's resolution.

**TC-31 (was TC-29 in v1) — nova-workspace CI: runs relocated pg-notify-listener tests + new installer bats + in-script guard tests**
- **Repo/Suite:** nova-workspace CI config
- **Expected:** New CI job (or extension of an existing one) runs: the relocated 50 nova-mind-origin pytest tests (TC-13), the relocated ~10 agent-chat-origin pytest tests (TC-26), the new nova-only-gating bats suite (TC-18-21), the in-script guard tests (TC-28), and the naming-consistency static check (TC-17A).

**TC-32 (was TC-30 in v1, revised content) — agent-chat CI: confirms removal, no longer runs listener-specific tests**
- **Repo/Suite:** agent-chat CI config
- **Expected:** Existing bats suite (minus the now-removed `AGENT_CHAT_SKIP_LISTENER_UNIT` test per TC-22's note, and with no tombstone test since TC-25 is retired per Rev 3) continues running; TC-22-24/TC-27 (removal-verification, git-grep sweep) added to the same CI job. Unlike v1's draft (which would have added *gating* tests here), this CI entry now verifies **absence** of listener code, not correct behavior of gated listener code — since the code itself no longer lives in this repo. `test_pg_notify_listener_chat.py` (Python) is removed from agent-chat's CI matrix entirely once TC-26 confirms it has relocated.

---

## 4. Test Summary Table (Rev 3)

| Group | Count | Repo(s) | Suite type |
|---|---|---|---|
| A — nova-mind installer removal | 5 (TC-1–5) | nova-mind | bats |
| B — RETIRED (was: nova-mind upgrade/tombstone) | 0 active (TC-6–7 retired) | — | — |
| C — nova-mind repo hygiene | 3 (TC-8–10) | nova-mind | pytest + bats + manual |
| D — test relocation (nova-mind origin) | 4 (TC-11–14) | nova-mind → nova-workspace | pytest |
| E — fork reconciliation (nova_memory listener) | 4 (TC-15–17, 17A) | nova-workspace | pytest + static |
| F — nova-only two-listener install | 4 (TC-18–21) | nova-workspace | bats |
| G — agent-chat removal + relocation | 7 active (TC-22–24, 26–29; TC-25 retired) | agent-chat → nova-workspace | bats + pytest + manual |
| H — CI wiring | 3 (TC-30–32) | all three repos | CI config |
| **Total active** | **30** | | |

(v1 had 30 test cases. v2/Rev-2 added 3 net-new — TC-17A naming
consistency, TC-28 in-script guard, TC-29 agent-chat doc hygiene — and 2
tombstone cases (TC-6/TC-7 nova-mind, TC-25 agent-chat) that Rev 2 itself
had added beyond v1's TC-6/TC-7 pairing, i.e. Rev 2 briefly totaled 33.
Rev 3 retires the 3 tombstone-shaped cases entirely (TC-6, TC-7, TC-25) per
the OQ-3 reversal, landing back at **30 active test cases** — numerically
coincidental with v1's original count, but the composition has changed:
net +3 from Rev 2's naming/guard/doc additions, net −3 from this
correction's tombstone retirement.)

---

## 5. Rulings Applied (final state, Rev 3 — resolves all v1 §5 open questions, with OQ-3 corrected)

| # | v1 Question (summary) | Ruling (final, Rev 3) | Test-case impact |
|---|---|---|---|
| OQ-1 | Canonical home for agent_chat listener: agent-chat repo or nova-workspace? | **nova-workspace** (I)ruid, explicit: local tooling does not belong in the distributable agent-chat repo) | Group G fully rewritten (removal, not gating); Group F's "both listeners" framing is now unconditional |
| OQ-2 | Rename `pg-notify-listener-chat.py` → `pg-notify-listener-agent-chat.py`? | **Yes** | New TC-17A; TC-18 wording updated |
| OQ-3 | Active cleanup vs. passive (Graybeard-only) for pre-existing installs? | **REVERSED at step 4 correction — passive/Graybeard-only, permanently. No installer-side detection or cleanup logic, ever.** (Rev 2 had briefly ruled "active cleanup required"; I)ruid corrected this.) | TC-6/TC-7 (nova-mind) and TC-25 (agent-chat) **retired**, not implemented. Both installers reduce to pure removal, same shape as Group A. New INV-6 states the underlying design principle (schema-sync listener must never live in the repo whose schema it pushes to) for the record. |
| OQ-4 | In-script `getpass.getuser()` guard in addition to installer gating? | **Yes** | New TC-28 |
| OQ-5 | Audit scope: two implicated installers only, or ecosystem-wide? | **Two installers only**; ecosystem audit is a separate follow-up issue (orchestrator to file) | No test-case change (TC-9/TC-27 already cover the two installers) |
| OQ-6 | Update `TEST-CASES-ISSUE-579.md` pointer? | **Yes** | Folded into TC-10 |

## 6. New Open Question (non-blocking)

**OQ-7:** Should agent-chat's existing `test_pg_notify_listener_chat.py`
suite (TC-26, ~10 tests covering alert routing, push-failure
classification, lock handling, and reconnect behavior — written against a
leaner/newer codebase than the nova-mind-origin #399/#506/#508 suite) be:
  - (a) merged/folded into a single reconciled test module per listener
    (i.e., the agent_chat listener's tests all live in one file reflecting
    its own reconciled implementation), or
  - (b) kept as a structurally separate file in nova-workspace, mirroring
    its separate origin, since the two listeners (nova_memory vs
    agent_chat) are functionally distinct scripts even after relocation?

  This is an implementation/file-organization detail, not a design
  blocker — either resolution satisfies TC-26/TC-13/TC-16's actual
  assertions (all tests relocate, all pass, no coverage lost). Recommend
  (b): the two listeners remain two separate scripts with two separate
  purposes post-relocation (per F-1's ruling, agent_chat is not being
  merged into the nova_memory listener, just co-located in the same
  canonical repo), so their test suites should mirror that separation
  rather than being combined into one large file. Non-blocking; implementer's
  call if there's a strong reason to prefer (a).

---

**Report path (this document):** `~/nova-mind/evals/se717/test-case-design-v2.md`
**Prior revision:** `~/nova-mind/evals/se717/test-case-design-v1.md`
