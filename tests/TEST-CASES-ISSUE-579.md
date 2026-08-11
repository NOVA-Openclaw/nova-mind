# Test Cases — nova-mind#579: Extract agent_chat Message Bus into Dedicated Repository

**SE run #643, step 3 — QA test-case design**
**Author:** Gem (QA Lead)
**Inputs:** issue #579 (+ comment: ship dedicated listener, do not generalize existing one), step-2 validation report
(`reports/SE643-step2-agent-chat-extraction-validation.md`), live `agent_chat` DB introspection, `agent-install.sh`,
`tests/install/test_agent_chat_installer.bats`, `pg-notify-listener.py`.

---

## Revision Log

**Rev 2 (2026-08-11, step 4 — PL review incorporated):**
- **TC-66 / open question #5 resolved.** The cron discrepancy is explained: NOVA (orchestrator) fixed the crontab
  out-of-band on 2026-08-11 ~12:36 UTC — after scout's step-2 report was written, before this test design pass.
  Scout's report described the true prior-state defect; my live observation captured the post-fix state. TC-66
  updated to record the fix and serve purely as a forward regression guard.
- **New P1 finding surfaced while empirically resolving the TC-19/TC-66 cross-reference** (see revised TC-19): the
  `trg_enforce_agent_chat_function_use` trigger is bound to **`BEFORE INSERT` only** on the live `agent_chat` table
  (verified via `pg_trigger`/`information_schema.triggers`, not by executing a destructive write). The function
  body contains `TG_OP = 'UPDATE'`/`TG_OP = 'DELETE'` branches that are **currently unreachable dead code** — no
  trigger event invokes them. This means direct `UPDATE`/`DELETE` on `agent_chat` by **any** role holding the `w`/`d`
  grant bits (i.e., all 21 agent roles in the current grant list) is **not blocked today**, contrary to the
  "Messages are immutable" documentation/comments. This also fully resolves NOVA's ask to "check which bypass
  applies" for `expire_old_chat()`'s DELETE: **no bypass logic is invoked at all**, because no trigger fires on
  DELETE in the first place. Flagged as a new blocking finding in §10, distinct from (and more severe than) the
  originally-drafted TC-19.
- **Open question #2 resolved (TC-51/52/53):** sibling-checkout convention —
  `${AGENT_CHAT_REPO:-$HOME/agent-chat}`, invoked by nova-mind's peer-detection. Added the "bus configured + repo
  checkout missing" case as TC-53a.
- **Open question #3 resolved (TC-44/60):** OpenClaw agent_chat channel plugin source moves to the new `agent-chat`
  repo; it ships `install-plugin.sh` (build + sync + main-field fixup + `channels.agent_chat`/`plugins.entries`
  config injection), invoked by nova-mind's peer-detection immediately after `register-agent.sh`.
- **Open question #4 resolved (TC-63):** `agent-spawner.py`/`github-issue-watcher.py` hardcoded-socket refactor is
  confirmed **out of scope** for this PR; a follow-up issue is a required PR deliverable. TC-63 tightened from an
  open question into a concrete assertion.
- **Addition:** new TC-29A — listener reconnect resilience after a Postgres restart / dropped `LISTEN` connection,
  per PL request. Code inspection of the existing listener's `main()` loop shows it does **not** reconnect on a
  dead connection (broad `except Exception` → log → `sleep(5)` → loop, re-using the same dead `conn` object
  forever) — this is an inherited gap, now flagged explicitly rather than silently ported.
- **No disagreements with PL decisions.** All four decisions (sibling-checkout convention, install-plugin.sh
  ownership split, out-of-scope daemon refactor, TC-66 resolution) are sound and testable as specified; incorporated
  verbatim below.

---

## 0. Acceptance Criteria → Test Mapping

The issue's acceptance criteria, each mapped to the test cases that verify it:

| # | Acceptance Criterion (from #579) | Verified By |
|---|---|---|
| AC1 | agent_chat schema, migrations, functions, and installer live in the new repo; removed from nova-mind | TC-40 to TC-49 (removal), TC-01 to TC-09 (new repo schema/installer) |
| AC2 | nova-mind installs cleanly with and without a bus present (no bus tables, no guards, no false warnings) | TC-50 to TC-56 |
| AC3 | Bus installer is idempotent and refuses nothing it shouldn't (replaces #569 guard by construction) | TC-01 to TC-05, TC-08, TC-09 |
| AC4 | Schema auto-sync keeps the new repo's schema.sql current with the live agent_chat DB | TC-20 to TC-29 |
| AC5 | Closes/supersedes #395, #409, #381; unblocks #573/#576/#577; resolves #475's structural cause | TC-40, TC-44, TC-45, TC-15 to TC-19 (security), TC-54 (staging isolation by construction) |

**"Done" definition for the whole extraction** (all must hold simultaneously):
1. `NOVA-Openclaw/agent-chat` repo exists, its installer runs standalone against a fresh host and against the
   already-populated production host, both idempotently, with zero data loss.
2. `register-agent.sh` correctly provisions any agent role end-to-end (grants, sequences, `.pgpass`) and is safely
   re-runnable.
3. The hardened `send_agent_message()` (5-arg, `SECURITY DEFINER` owned by `postgres`, `session_user` check) and the
   immutability trigger are present, unmodified in behavior, and covered by tests in the new repo.
4. A dedicated `pg-notify-listener-chat.py` daemon exists, is installed by the bus installer, and correctly
   round-trips a schema change to a commit on `main` of the `agent-chat` repo — including lock-contention and
   off-branch remediation paths.
5. `nova-mind` contains zero references to `database/agent-chat/`, `cognition/focus/agent_chat/`,
   `scripts/agent-chat-migration/`, `_apply_agent_chat_migrations`, `_ensure_agent_chat_postgres_json` (old
   unconditional form), the `#569` guard, and the agent_chat verification/build/config-strip blocks — replaced by
   the peer-detection call-out.
6. `nova-mind` installs cleanly in both bus-present and bus-absent modes on a clean staging host, with no
   agent_chat-shaped artifacts left behind in the absent case and correct registration invoked in the present case.
7. Regenerated `database/schema.sql` in nova-mind is agent_chat-free (resolves #409); `database/schema-reference.md`
   and the two memory docs no longer describe agent_chat internals.
8. All 5 downstream consumers (OpenClaw channel plugin, agent_config_sync, agent-spawner.py,
   github-issue-watcher.py, generate-daily-log.py / memory-maintenance.py) continue to function post-extraction, with
   explicitly documented residual coupling for the two hardcoded-socket daemons.
9. The nightly `expire_old_chat()` cron targets `agent_chat` (already corrected on live host per current crontab —
   verify it stays that way and add a regression test so it cannot silently revert).
10. `tests/install/test_agent_chat_installer.bats` is fully relocated to the new repo; nova-mind's bats suite has
    zero remaining agent_chat-specific tests (except the peer-detection tests, which are new).

---

## 1. Bus Installer (new repo: `NOVA-Openclaw/agent-chat`)

### TC-01 — Fresh-host install creates DB, schema, and grants from nothing
**Priority:** P1 (Critical)
**Preconditions:** Target Postgres cluster has no `agent_chat` database; installer run as a user with `CREATEDB`.
**Steps:**
1. Run the bus installer against a clean cluster (no `agent_chat` DB, no prior roles beyond a fresh superuser).
2. Inspect the resulting DB.
**Expected:**
- `agent_chat` database created, owned by `postgres` (matches live production: `Owner: postgres`).
- Tables `agent_chat`, `agent_chat_processed` exist with the exact live column set (see §5 for schema fidelity
  assertions).
- `send_agent_message()` exists, 5-arg signature, `SECURITY DEFINER`, owner `postgres`.
- `enforce_agent_chat_function_use()` trigger function and `trg_enforce_agent_chat_function_use` /
  `trg_notify_agent_chat` triggers exist on `agent_chat`.
- `expire_old_chat(retention_days integer DEFAULT 90)` exists.
- `notify_schema_change()` function and `schema_change_trigger` event trigger exist and are enabled (this is new —
  does not exist today per step-2 report §4).
- Installer exits 0.

### TC-02 — Idempotent re-run against an already-installed fresh DB is a no-op on data
**Priority:** P1 (Critical)
**Preconditions:** TC-01 has run once.
**Steps:**
1. Insert a test row into `agent_chat` via `send_agent_message()`.
2. Re-run the installer against the same DB.
3. Query row count and function definitions.
**Expected:**
- Row count unchanged (the inserted message survives).
- No duplicate objects: `pg_proc`, `pg_trigger`, `pg_event_trigger` each contain exactly one entry per named object
  (schema is `CREATE OR REPLACE` / `CREATE IF NOT EXISTS`, matching the pattern already used in
  `_apply_agent_chat_migrations` for the old schema file).
- Grants are unchanged/idempotently reapplied (no duplicate GRANT errors, no revoked-then-regranted race visible to
  concurrent sessions).
- Installer exits 0 with an explicit "up to date" style message, not silently identical output to a fresh install
  (verifies the script actually detects idempotency rather than happening to be harmless).

### TC-03 — Idempotent re-run is safe under concurrent load (no lock/blocking regression)
**Priority:** P2
**Preconditions:** TC-01 done; a script sending messages via `send_agent_message()` in a tight loop.
**Steps:**
1. Start a background loop calling `send_agent_message()` every 200ms.
2. Run the installer concurrently.
**Expected:** No deadlocks; no failed `send_agent_message()` calls attributable to the installer's DDL (transient
lock waits are acceptable and should resolve within a few seconds — installer should not hold long-lived exclusive
locks on `agent_chat` table during a re-run when schema is already current).

### TC-04 — Existing-production-DB adoption: installer run against the current live bus
**Priority:** P1 (Critical) — this is the single highest-risk scenario in the whole extraction
**Preconditions:** Full logical/pg_dump backup of the (test/staging clone of) live `agent_chat` DB taken immediately
before the run. **Never run this against actual production without a fresh backup and explicit sign-off; execute
against a same-schema staging clone first.**
**Steps:**
1. Clone the live `agent_chat` DB schema+data to a staging instance (`pg_dump`/`pg_restore` or logical replica).
2. Run the new bus installer against the clone.
3. Diff schema before/after (`pgschema dump` before and after).
4. Verify existing message rows (sender, recipients, timestamps) are untouched.
5. Verify existing role grants (`argus`, `athena`, ... `victoria`, `cadence` read-only, `recon` read-only,
   `nova-staging` read-only — see live grant list) are preserved, not narrowed or widened unexpectedly.
**Expected:**
- Zero data loss: same row count, same `id` sequence current value, same content hashes for a sample of rows.
- Schema diff shows **only additive** changes: the new `schema_change_trigger` / `notify_schema_change()` objects
  appear; no existing table/column/trigger/function is altered or dropped.
- All 21 existing per-agent grants plus the 2 read-only grants (`nova-staging`, `cadence`, `recon`) remain intact
  with identical privilege sets.
- `send_agent_message()` function body identical byte-for-byte pre/post EXCEPT for anything explicitly documented as
  an intentional and reviewed change in this PR (there should be none — the plan is to move the file verbatim).

### TC-05 — Adoption run detects and refuses schema drift it cannot safely reconcile
**Priority:** P2
**Preconditions:** Staging clone of production DB, with an out-of-band hand-edited object (e.g., someone manually
added a column to `agent_chat` that isn't in the new repo's `schema.sql`).
**Steps:** Run the bus installer against this drifted clone.
**Expected:** Installer either (a) leaves the unknown extra object alone and completes, logging a clear warning
about the unrecognized column/object, or (b) hard-fails with a clear message identifying the drift — but it must
**never** silently drop or truncate a column/table it doesn't recognize. Define and document which behavior is
intended; test asserts that behavior.

### TC-06 — Bus installer running as non-DB-superuser fails clearly
**Priority:** P3
**Preconditions:** DB user lacking `CREATEDB`/DDL privilege.
**Steps:** Run installer as this restricted user.
**Expected:** Clean, actionable error (e.g., "requires CREATEDB / superuser role") — not a raw Postgres permission
stack trace, no partial DB left in a half-created state (verify: DB either doesn't exist or is fully formed, never
half-migrated).

### TC-07 — Bus installer against unreachable/misconfigured Postgres host
**Priority:** P3
**Preconditions:** Postgres host down or wrong host/port in config.
**Steps:** Run installer.
**Expected:** Clean connection-error message, exit non-zero, no partial artifacts on disk (no stray `.pgpass`
entries written before the connection is confirmed).

### TC-08 — Installer is safely re-runnable mid-failure (crash recovery)
**Priority:** P2
**Preconditions:** Simulate a crash after DB creation but before schema application (e.g., kill the installer
process between steps).
**Steps:** Re-run the installer from scratch.
**Expected:** Installer detects the partially-created DB and completes the remaining steps (schema, triggers,
grants) without erroring on "database already exists" or duplicate-object errors. This is the direct replacement
for the old `_apply_agent_chat_migrations` half-migration risk called out in the step-2 report.

### TC-09 — `schema_version` table populated and matches the shipped schema
**Priority:** P2 (from issue plan item 3 — schema version handshake)
**Steps:** After install, query the `schema_version` table (or equivalent).
**Expected:** Row exists identifying the installed schema version; version increments on subsequent migrations;
nova-mind's peer-detection code (TC-56) can read this value to compare compatibility.

---

## 2. `register-agent.sh`

### TC-10 — Register a brand-new agent: role, grants, sequence usage, `.pgpass`
**Priority:** P1 (Critical)
**Preconditions:** Bus installed (TC-01); target agent role does not exist yet.
**Steps:** Run `register-agent.sh <agent_name>`.
**Expected:**
- New Postgres role `<agent_name>` created (no superuser, no createdb — matches the flat/no-attribute roles seen in
  live `\du` output for agents like `gem`, `flint`, `iris`).
- Grants match the live production pattern exactly: `arwd` (SELECT/INSERT/UPDATE/DELETE... actually verify against
  live: `argus=arwd/postgres` — table-level SELECT/INSERT/UPDATE/DELETE) on `agent_chat`, and equivalent on
  `agent_chat_processed`.
- Sequence grant on `agent_chat_id_seq`: `USAGE` (matches live `rU`/`U` pattern — note live shows `athena=rU`,
  `scout=rU`, most others `U` only; register-agent.sh should apply the standard `U`-only pattern unless the agent
  needs read access to current sequence value).
- `.pgpass` entry written to the *registering user's* home (or the target agent's home, per design) with mode 600,
  matching `host:port:agent_chat:<agent>:<password>` format.
- Idempotent flag/output: running with `--check` or equivalent confirms role existence without erroring.

### TC-11 — Re-register an already-registered agent (idempotency)
**Priority:** P1 (Critical)
**Preconditions:** Agent already registered via TC-10.
**Steps:** Run `register-agent.sh <agent_name>` again with the same or different password.
**Expected:**
- No duplicate role creation error.
- Grants are re-asserted, not duplicated (Postgres GRANT is naturally idempotent — verify no errors are thrown and
  no unintended REVOKE happens first that could create a race window).
- `.pgpass`: exactly one entry for `host:port:agent_chat:<agent>:*` remains — old entry is replaced, not duplicated
  (mirrors the existing `_ensure_pgpass_entry` behavior tested in TC-63/TC-64 of the current bats suite — this logic
  must be preserved verbatim in the new repo).
- If password changed: new password lands in `.pgpass`; old password no longer present.

### TC-12 — Register-agent.sh recovers a stale `.pgpass` entry (host/port drift)
**Priority:** P2
**Preconditions:** Agent registered, but `.pgpass` entry has a stale password (DB role password rotated
out-of-band) or a stale host/port that no longer matches `postgres.json`.
**Steps:** Run `register-agent.sh <agent_name>` with the current correct password.
**Expected:** Stale line removed, correct line written; a subsequent `psql -U <agent> -d agent_chat -c "SELECT 1"`
using the new `.pgpass` entry succeeds. No stale duplicate line survives (regression guard specifically for the
class of bug described in `GLOBAL/DATABASE_ACCESS.md`'s "stale `.pgpass` password" incident).

### TC-13 — Register-agent.sh grants do not clobber a manually-hardened permission set
**Priority:** P3 (regression for #381 — misinterpreted Newhart permissions)
**Preconditions:** An agent role (e.g., mirroring `newhart`) with an intentionally restricted grant (e.g., read-only,
no INSERT) due to a documented policy exception.
**Steps:** Run `register-agent.sh` for that agent with default (full) grant flags.
**Expected:** register-agent.sh must not silently widen a deliberately-restricted role without an explicit
`--force`/confirmation flag; OR (if the script is designed to always apply the standard full grant set) this must be
explicitly documented so it cannot recreate the #381 confusion. Test asserts whichever behavior is chosen is
deterministic and logged, not silent.

### TC-14 — Register-agent.sh rejects invalid/malicious agent name input
**Priority:** P2 (security/edge case)
**Preconditions:** None.
**Steps:** Run with agent names containing SQL-unsafe characters (`"; DROP TABLE agent_chat; --`), empty string,
overly long string (>63 bytes, Postgres identifier limit), and names colliding with reserved roles (`postgres`,
`public`).
**Expected:** All rejected with a clear validation error before any SQL is executed; no role created; no SQL
injection possible (verify via `\du` that no rogue role was created after each attempt). This is BVA on identifier
length (62/63/64 chars) plus equivalence partitioning on valid vs. invalid character classes.

---

## 3. Schema & Security (hardened `send_agent_message`, immutability)

### TC-15 — `session_user` check rejects spoofed `p_sender`
**Priority:** P1 (Critical — security regression guard, ref #475 incident)
**Preconditions:** Two registered agent roles, e.g. `gem` and `flint`. Connect as `gem`.
**Steps:** As `gem`, call `SELECT send_agent_message('flint', 'spoofed message', ARRAY['nova']);`
**Expected:** Exception raised: `sender must match session_user (got flint but connected as gem)`. No row inserted
into `agent_chat`. This must hold identically post-extraction — byte-identical function body verified in TC-04.

### TC-16 — `session_user` check passes for legitimate matched sender
**Priority:** P1
**Steps:** As `gem`, call `SELECT send_agent_message('gem', 'legit message', ARRAY['nova']);`
**Expected:** Row inserted, function returns new `id`. Case-insensitivity verified too: `send_agent_message('GEM',
...)` as `gem` also succeeds (function lowercases `p_sender` before compare — actually note: live code compares
`LOWER(p_sender) != session_user`, so `session_user` itself must already be lowercase, which Postgres role names
typically are; add a boundary test for a mixed-case role name if one exists).

### TC-17 — Self-addressed message rejected
**Priority:** P2
**Steps:** As `gem`, call `send_agent_message('gem', 'msg', ARRAY['gem'])`.
**Expected:** Exception: sender is in recipient list. No row inserted. (Regression for the guard documented in the
function body comments.)

### TC-18 — `SECURITY DEFINER` ownership survives extraction; direct role cannot bypass session_user check
**Priority:** P1 (Critical)
**Steps:**
1. Verify `proowner` for `send_agent_message()` is `postgres` and `prosecdef = true` in the new repo's installed
   schema (mirrors TC-01 assertion, repeated here as a dedicated security test).
2. As a non-postgres role, attempt `INSERT INTO agent_chat (sender, message, recipients) VALUES ('gem', 'x',
   ARRAY['nova']);` directly (bypassing the function entirely).
**Expected:**
- Direct INSERT raises: `Direct INSERT on agent_chat is not allowed. Use send_agent_message() instead.` — the
  `trg_enforce_agent_chat_function_use` trigger fires because `current_user != 'postgres'` for a direct session
  (only inside the `SECURITY DEFINER` function does `current_user` become `postgres`).
- Direct UPDATE/DELETE on an existing row also rejected with the respective messages (immutability, TC-19).

### TC-19 — Immutability trigger blocks direct writes on `agent_chat` — VERIFIED SCOPE IS INSERT-ONLY (blocking finding)
**Priority:** P1 (Critical)
**Preconditions:** At least one existing row in `agent_chat`.

**Empirical finding (verified live, read-only, 2026-08-11):**
```
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers WHERE event_object_table = 'agent_chat';

            trigger_name             | event_manipulation | action_timing
--------------------------------------+---------------------+---------------
 trg_enforce_agent_chat_function_use | INSERT              | BEFORE
 trg_notify_agent_chat               | INSERT              | AFTER
```
Only **one** event (`INSERT`) is bound to `trg_enforce_agent_chat_function_use`. The trigger function's body
(confirmed via `pg_get_functiondef`) contains explicit `IF TG_OP = 'UPDATE' ... ELSIF TG_OP = 'DELETE' ...` branches
raising "Direct UPDATE on agent_chat is not allowed. Messages are immutable." / "Direct DELETE ... not allowed." —
but **Postgres never invokes this trigger for UPDATE or DELETE events**, because the `CREATE TRIGGER` statement
only registered it for `BEFORE INSERT`. Those branches are dead code today. **This directly answers NOVA's request
to "check which bypass applies" for `expire_old_chat()`'s DELETE: no bypass is invoked, because no trigger fires on
DELETE at all** — `expire_old_chat()` (proowner `postgres`, `prosecdef=false`, called by unix/db role `nova` per the
cron) succeeds not because of an authorized bypass path, but because the immutability guarantee for DELETE simply
does not exist at the trigger layer currently. The same is true for UPDATE: **any of the 21 agent roles holding the
`w`/`d` grant bits on `agent_chat` (per the live `\dp agent_chat` grant list — all of `argus`, `athena`, `coder`,
`conductor`, `erato`, `flint`, `gem`, `gidget`, `hermes`, `iris`, `marcie`, `nova`, `quill`, `scout`, `scribe`,
`ticker`, `graybeard`, `victoria` hold `arwd`) can UPDATE or DELETE rows directly today, unblocked**, contrary to
the "Messages are immutable" documentation and code comments.

**Steps (execute against a disposable staging clone — do not run destructive DML against production to confirm a
finding already established by read-only trigger-catalog inspection):**
1. As `gem` (or any role with `arwd`), attempt `UPDATE agent_chat SET message = 'edited' WHERE id = <existing>;`
2. As `gem`, attempt `DELETE FROM agent_chat WHERE id = <existing>;`
3. As `gem`, attempt `INSERT INTO agent_chat (sender, message, recipients) VALUES ('gem','x',ARRAY['nova']);`
   (control case — this path IS covered, confirms the trigger fires correctly for the one event it's bound to).
4. Confirm the `notify_schema_change`/logical-replication bypass branches in the function body are consistent with
   whatever the *fixed* trigger definition ends up being once corrected (see below) — re-verify after the fix, not
   just against today's INSERT-only binding.

**Expected (current/actual, pre-fix):** Step 1 and step 2 **succeed** (they should raise exceptions per the
documented immutability contract, but do not). Step 3 correctly raises "Direct INSERT ... not allowed."

**Expected (required, post-fix):** The extraction PR must correct the trigger to `BEFORE INSERT OR UPDATE OR
DELETE ON agent_chat` (or three separate triggers) so all three DML operations are actually intercepted, matching
the function body's existing `TG_OP` branches and the documented immutability contract. After the fix: steps 1 and
2 must raise the documented exceptions from every non-`postgres` role; `expire_old_chat()`'s DELETE must then be
explicitly re-verified to still succeed — either because it is made `SECURITY DEFINER` (so `current_user` becomes
`postgres` inside it, hitting the trigger's existing `current_user = 'postgres'` bypass), or because the cron's
connecting role is deliberately exempted by name. **This is a blocking finding, more severe than the originally
drafted version of this test case: the current production schema does not actually enforce the immutability
guarantee it claims to for UPDATE/DELETE. Flag for Coder as a required fix within this extraction PR** (the new
repo's `schema.sql` must ship the corrected multi-event trigger from day one — do not port the INSERT-only binding
verbatim). Cross-reference TC-04 (byte-for-byte adoption fidelity): TC-04's "identical except explicitly reviewed
changes" clause must be amended to name this trigger-scope fix as an intentional, reviewed, in-scope change.

---

## 4. Schema-Sync Listener (`pg-notify-listener-chat.py`)

### TC-20 — DDL on `agent_chat` DB fires `schema_changed` notification
**Priority:** P1 (Critical)
**Preconditions:** Bus installed with `schema_change_trigger` (TC-01); listener not required for this test — verify
at the DB layer.
**Steps:** Execute `LISTEN schema_changed;` in one session; in another, run `ALTER TABLE agent_chat ADD COLUMN
test_col text;` (then drop it after the test).
**Expected:** A `NOTIFY schema_changed` payload arrives on the listening connection with `command_tag`,
`object_type`, `object_identity` matching the executed DDL.

### TC-21 — Listener dumps schema and commits to the correct repo/branch on notification
**Priority:** P1 (Critical)
**Preconditions:** `pg-notify-listener-chat.py` running against a disposable test clone of the `agent-chat` repo
(never point this test at the real `agent-chat` repo's `main` branch).
**Steps:** Trigger a DDL change on the test `agent_chat` DB; wait for debounce window; inspect the test clone repo.
**Expected:**
- `schema.sql` in the test clone is regenerated via `pgschema dump` and reflects the DDL change.
- A commit is created with message pattern `schema: <command> <table_name>` (mirrors existing listener's commit
  message format).
- Commit is pushed to `main` (in the test clone, verify push target and that `OPENCLAW_AGENT_ID=gidget` env is set
  on the push subprocess, matching the branch-guard-bypass pattern from the existing listener).
- The commit lands on the `agent-chat` repo's `schema.sql`, **not** nova-mind's `database/schema.sql` (critical:
  this is the #1 way this could go wrong — a copy-paste bug pointing the new listener at the old `NOVA_MIND_DIR`
  constant).

### TC-22 — Listener debounces rapid successive schema changes
**Priority:** P2
**Steps:** Fire 5 DDL statements against `agent_chat` within 2 seconds.
**Expected:** Only one sync/commit cycle runs (matching existing listener's `debounce_schema = 30` seconds
behavior) — mirrors existing dedup-cache logic; verify the ported listener retains the same
`(command_tag, object_identity)` dedup key logic.

### TC-23 — Lock contention: two listener instances / concurrent sync attempts
**Priority:** P1 (Critical — ref nova-mind#506 class of bug)
**Preconditions:** Simulate two `sync_schema_to_github()`-equivalent calls firing concurrently (e.g., manually hold
the file lock in one process while triggering a schema change).
**Steps:** Hold `~/.openclaw/workspace/scripts/.pg-notify-git-chat.lock` (or repo-appropriate equivalent path — must
be a **distinct lock file** from the nova-mind listener's lock, since they are now independent daemons potentially
running on the same host) in process A; trigger a schema change that would invoke process B's sync.
**Expected:** Process B detects the lock is held (`fcntl.flock` non-blocking failure), logs "Git lock held by
another sync - skipping", and does NOT attempt a concurrent git operation. No `.git/index.lock` collision. Confirm
the lock file path is unique to the chat listener and does not collide with the existing nova-mind listener's lock
file if both run on the same host.

### TC-24 — Off-branch remediation: chat repo clone is on a feature branch when a sync fires
**Priority:** P1 (Critical)
**Preconditions:** Test clone of `agent-chat` repo checked out on a non-`main` branch with no uncommitted changes.
**Steps:** Trigger a schema change.
**Expected:** Listener's `_ensure_on_main()`-equivalent logic: checks out `main`, fetches origin, fast-forwards.
Sync proceeds normally after remediation. Verify behavior matches the existing listener exactly (git checkout →
fetch → `merge --ff-only`).

### TC-25 — Off-branch remediation failure: diverged main sends an alert and aborts safely
**Priority:** P1
**Preconditions:** Test clone's local `main` has a commit not on `origin/main` (diverged).
**Steps:** Trigger a schema change.
**Expected:** `merge --ff-only` fails; listener sends an `agent_chat` alert (via `send_agent_message`) to the
configured recipient(s) with a "diverged" reason and remediation instructions; sync aborts without force-pushing or
force-merging. No data loss to the local branch's extra commit.

### TC-26 — Push failure classification and retry: auth failure vs. non-fast-forward vs. transient
**Priority:** P2
**Steps:** Simulate each of the three failure classes (bad credentials, remote ahead, network timeout) during the
push step.
**Expected:**
- Auth failure: no retry, immediate alert with SSH/credential remediation steps.
- Non-fast-forward: no retry, immediate alert with rebase remediation steps.
- Transient: retries per `MAX_PUSH_ATTEMPTS`/backoff schedule, then alerts if still failing.
(Direct port of existing `_classify_push_failure` logic — verify identical behavior in the new listener.)

### TC-27 — Alert recipient self-address avoidance
**Priority:** P3
**Preconditions:** Listener configured with `PGUSER` matching the primary alert recipient (e.g., listener runs as
`nova`).
**Steps:** Trigger a push-failure alert scenario.
**Expected:** Alert recipient list excludes the sender (`nova`) and falls back to `graybeard`, matching
`_alert_recipients()` logic in the existing listener; if both collide, falls back to broadcast `['*']`.

### TC-28 — Listener resolves credentials via `agent_chat` section of `postgres.json`, not hardcoded values
**Priority:** P1
**Steps:** Point the listener's config at a `postgres.json` with a non-default `agent_chat` section (custom
host/port/user/password); start the listener.
**Expected:** Listener connects using the configured values (`load_pg_env(section="agent_chat")` pattern), not any
hardcoded `localhost`/default. This directly tests resilience against the "moved off localhost" risk called out in
the step-2 report §1A(3-4) for the two hardcoded daemons — the listener itself must NOT repeat that anti-pattern.

### TC-29 — Listener systemd unit installs and starts (mirrors existing `_install_pg_notify_listener` bats coverage)
**Priority:** P2
**Steps:** Port the existing `TC-listener` bats tests (install script + service file, skip-when-missing-source,
restart-if-already-active vs enable-and-start-if-not) to the new repo's installer, targeting the
`pg-notify-listener-chat.py`/`.service` pair.
**Expected:** Identical behavior to the existing tests, just renamed/re-targeted. This is a direct port — flag to
Coder that these bats cases should be copied nearly verbatim into the new repo's test suite.

### TC-29A — Listener survives a Postgres restart / dropped LISTEN connection without permanent stall
**Priority:** P1 (Critical — added per PL request, step 4)
**Preconditions:** `pg-notify-listener-chat.py` (or its nova-mind ancestor, for baseline comparison) running against
a disposable test Postgres instance/clone.
**Code-inspection finding (existing `pg-notify-listener.py`, `main()`):** the main loop wraps the entire
`select()`/`conn.poll()`/notify-processing block in a single broad `try/except Exception: log(...); time.sleep(5)`
and then loops back to the top — but it **re-enters the loop using the same `conn` object**, which after a
Postgres restart or a killed backend is now a dead/closed connection. There is no `conn.close()` + reconnect +
re-`LISTEN` logic anywhere in `main()`. This means a single connection drop causes the script to spin in a tight
"except → sleep(5) → poll a dead conn → except" loop **forever**, silently dropping every schema-change
notification until the process is manually restarted (e.g., by systemd on a crash, which this is not — the process
stays alive and "running", just permanently deaf).
**Steps:**
1. Start the listener against a test Postgres instance.
2. Confirm it is listening (`LISTEN schema_changed` acknowledged, e.g. via a manual `NOTIFY` round-trip).
3. Forcibly terminate the underlying backend (`SELECT pg_terminate_backend(pid)` for the listener's connection, or
   restart the test Postgres instance/container).
4. Wait past the `except`+`sleep(5)` window, then trigger a schema change (DDL) against the (now-restarted)
   database.
5. Check whether the listener logs the new notification and completes a sync.
**Expected (current/inherited behavior — document, do not silently accept):** The listener does **not** recover;
no further notifications are processed after the connection drop; the process log shows a repeating
"Error in main loop" message with no reconnect attempt. **This is an inherited gap from the existing
`pg-notify-listener.py`, not a new regression introduced by the port.** Per PL instruction, flag this explicitly in
the extraction PR rather than silently porting it: either (a) fix it in the new dedicated listener as part of this
PR (add a reconnect-with-backoff + re-`LISTEN` loop on connection-dead detection), or (b) if fixing it is deemed
out of scope, file a tracked follow-up issue for both listeners and note the known-stall behavior in the new
repo's operational runbook/README so on-call is aware a systemd `Restart=` policy alone will not recover a listener
that is alive-but-deaf. **Recommend option (a)** given this is a brand-new daemon being written from scratch for
this extraction — there is no reason to knowingly re-introduce a known reliability gap into new code when the fix
(detect closed connection via `conn.closed` or a poll/select error, close and reopen, re-issue both `LISTEN`
statements) is small and well-understood. Treat as a blocking finding for the new listener; non-blocking
(tracked-issue-only) for the existing nova-mind listener, which is out of this PR's scope to modify.

---

## 5. Schema Fidelity (new repo schema.sql vs. live production)

### TC-30 — Shipped `schema.sql` matches live production schema byte-for-byte (modulo the new sync objects)
**Priority:** P1 (Critical)
**Steps:** `pgschema dump` the live `agent_chat` DB; diff against the new repo's `schema.sql`.
**Expected:** No differences except the additive `schema_version` table (if added per issue plan item 3) and the
new `notify_schema_change()`/`schema_change_trigger` objects. Table structures, indexes, constraints, and existing
function bodies match exactly (see live introspection: `agent_chat` columns `id, sender, message, recipients,
reply_to, timestamp, expires_at`; indexes `agent_chat_pkey`, `idx_agent_chat_expires` (partial, `WHERE expires_at IS
NOT NULL`), `idx_agent_chat_recipients` (GIN), `idx_agent_chat_sender`, `idx_agent_chat_timestamp`; check constraint
`agent_chat_recipients_check CHECK (array_length(recipients, 1) > 0)`; FK `agent_chat_reply_to_fkey` NOT VALID
self-reference).

### TC-31 — `agent_chat_processed` table and its disabled internal FK-check triggers are preserved
**Priority:** P2
**Steps:** Diff `agent_chat_processed` structure (columns `chat_id, agent, received_at, routed_at, responded_at,
error_message, status`; PK/unique on `(chat_id, agent)`; `agent_chat_status` enum type) between live and new schema.
**Expected:** Exact match, including the `agent_chat_status` custom enum type definition and its default
`'responded'::agent_chat_status`.

### TC-32 — `agent_chat_recipients_check` boundary: empty array rejected, single-element array accepted
**Priority:** P2 (BVA)
**Steps:** Attempt `send_agent_message(sender, msg, ARRAY[]::text[])` and `send_agent_message(sender, msg,
ARRAY['nova'])`.
**Expected:** Empty array raises the function's own explicit NULL/empty check (`p_recipients ... array_length ...
IS NULL`) before ever reaching the table CHECK constraint; single-element array succeeds. Also test
`ARRAY['*']` (broadcast sentinel) is accepted and not treated as a literal recipient lookup failure.

---

## 6. nova-mind Removal (regression: nothing left behind)

### TC-40 — Zero references to removed directories in the nova-mind tree post-PR
**Priority:** P1 (Critical)
**Steps:** After the removal PR, `grep -r` the repo (excluding `.git`) for `database/agent-chat`,
`cognition/focus/agent_chat`, `scripts/agent-chat-migration`.
**Expected:** Zero matches outside of CHANGELOG/historical docs explicitly describing the migration event.

### TC-41 — `agent-install.sh` no longer defines `_resolve_agent_chat_db_name`, `AGENT_CHAT_DB_NAME`,
`_ensure_agent_chat_postgres_json`, `_apply_agent_chat_migrations`, or the #569 guard
**Priority:** P1 (Critical)
**Steps:** `grep` the installer for each named function/variable.
**Expected:** Zero matches. `bash -n agent-install.sh` still passes (no dangling references / syntax breaks from the
removal). `shellcheck` still zero warnings (mirrors the existing bats test at the bottom of
`test_agent_chat_installer.bats` — must be re-run post-removal, not just pre-removal).

### TC-42 — Verification block (#395) no longer checks for `agent_chat`/`agent_chat_processed` tables
**Priority:** P1
**Steps:** Run `--verify`/verification mode of the installer against a memory-only install (no bus).
**Expected:** No warning about missing `agent_chat` tables is ever emitted — the check itself is gone, not just
silenced. `grep` confirms the `agent_chat_db=$(jq -r '.agentChatDatabase ...)` verification lookup line (previously
asserted present by `test_agent_chat_installer.bats`'s "TC-68-adjacent" test) is now **absent** — this existing bats
assertion must be **inverted/removed**, not left in place expecting a string that no longer exists.

### TC-43 — Extension build steps (agent_chat npm install/build) removed from installer
**Priority:** P2
**Steps:** Run the full installer with `set -x`/verbose tracing; grep output for "Agent Chat extension
installation", "Building agent_chat TypeScript", `EXTENSION_SOURCE=... agent_chat`.
**Expected:** None of these steps execute; total install time measurably shorter; no `npm install`/`npm run build`
invocation referencing `agent_chat` anywhere in the trace.

### TC-44 — `openclaw.json` config-strip/injection block for `channels.agent_chat`/`plugins.entries.agent_chat` removed from nova-mind
**Priority:** P2
**Design decision (step 4, PL):** this config injection moves entirely to the bus repo's `install-plugin.sh` (see
TC-60), which nova-mind's peer-detection invokes immediately after `register-agent.sh` when a bus is present.
**Steps:**
1. `grep -n "channels.agent_chat\|plugins.entries.agent_chat"` in `agent-install.sh` post-removal.
2. Run the bare nova-mind installer (no bus) against a fresh `openclaw.json`; inspect resulting config.
3. Run the bare nova-mind installer with a bus present but *without* invoking `install-plugin.sh` (simulate the
   peer-detection call site being skipped, to isolate which script is actually responsible for the config write).
**Expected:**
- Step 1: zero matches — nova-mind's installer contains no `channels.agent_chat`/`plugins.entries.agent_chat`
  read/write logic whatsoever.
- Step 2: no `channels.agent_chat` or `plugins.entries.agent_chat` keys appear (bus-absent case, unchanged from
  TC-50).
- Step 3: config keys are **not** written by nova-mind's installer alone — confirms the write genuinely lives in
  `install-plugin.sh`, not duplicated in both places (duplication would risk the two config-writers drifting or
  racing).

### TC-45 — `database/schema.sql` regenerated clean of agent_chat objects
**Priority:** P1 (resolves #409)
**Steps:** Run `pgschema dump` against `nova_memory` post-extraction; diff against nova-mind's checked-in
`database/schema.sql`.
**Expected:** File contains zero `agent_chat`/`agent_chat_processed`/`send_agent_message`/`enforce_agent_chat_...`
definitions. `database/schema-reference.md` has no `agent_chat` row in its tables list.

### TC-46 — Documentation cleanup: `memory/docs/database-config.md`, `database-schema-guide.md`,
`cognition/README.md`, `cognition/docs/installation.md`
**Priority:** P3
**Steps:** `grep` each file for `agent_chat`, `agentChatDatabase`.
**Expected:** No remaining references describing nova-mind-managed agent_chat provisioning; any reference that
remains must point to the new repo, not describe stale implicit behavior.

### TC-47 — `tests/install/test_agent_chat_installer.bats` fully relocated, not merely deleted
**Priority:** P1
**Steps:** Confirm the file is absent from `nova-mind/tests/install/`. Confirm an equivalent (or superset) test
file exists in the new `agent-chat` repo covering the same logical assertions (pgpass provisioning/idempotency,
postgres.json section writes, config-strip, listener install, the old #569 guard's *replacement* behavior).
**Expected:** No test coverage is silently lost in the move — every currently-passing assertion in the old file has
a home in the new repo (mapped 1:1 or intentionally superseded, documented in the PR description).

### TC-48 — nova-mind's remaining bats suite passes after removal (no orphaned references)
**Priority:** P1
**Steps:** Run the full `bats tests/` suite in nova-mind post-removal.
**Expected:** 100% pass; specifically no other bats file references now-removed functions/constants (`grep -r
"_apply_agent_chat_migrations\|AGENT_CHAT_DB_NAME" tests/` returns zero).

### TC-49 — Full installer dry-run / `bash -n` and ShellCheck pass after removal
**Priority:** P1
**Steps:** `bash -n agent-install.sh && shellcheck agent-install.sh`.
**Expected:** Both clean, zero warnings — this is an existing bats-covered assertion; must still pass after the
large-scale removal (removal edits are exactly the kind of change that introduces dangling `if`/`fi` or unused-var
warnings).

---

## 7. nova-mind Integration — Optional Peer Detection

### TC-50 — Install WITHOUT a bus present: clean skip, zero artifacts, zero false warnings
**Priority:** P1 (Critical — this is the AC2 core assertion)
**Preconditions:** Fresh staging host; no `agent_chat` section in `~/.openclaw/postgres.json`; no `agent_chat`
database reachable.
**Steps:** Run the nova-mind installer end-to-end.
**Expected:**
- Installer completes successfully with no bus-related errors.
- No `agent_chat` database creation attempted.
- No `.pgpass` entry for any `agent_chat`-named database written.
- No `channels.agent_chat`/`plugins.entries.agent_chat` config keys added.
- **Zero warnings printed** — not even an informational "bus not detected, skipping" that could be mistaken for an
  error (verify tone/format is clearly non-alarming, matching the "absent → skip cleanly" requirement from the
  issue).
- Exit code 0.

### TC-51 — Install WITH a bus present (via `postgres.json` section): registration invoked via sibling-checkout convention
**Priority:** P1 (Critical)
**Design decision (step 4, PL):** the bus repo is resolved at `${AGENT_CHAT_REPO:-$HOME/agent-chat}` (env override,
defaulting to a sibling checkout at `~/agent-chat`). When a bus is detected (per TC-51/52 detection signals) *and*
that path exists, nova-mind's peer-detection invokes, in order: (1) `register-agent.sh` from that checkout, then
(2) `install-plugin.sh` from that same checkout (see TC-60) to build/sync the OpenClaw channel plugin and inject
the `channels.agent_chat`/`plugins.entries.agent_chat` config.
**Preconditions:** Bus already installed on the host (TC-01); `postgres.json` has a populated `agent_chat` section
(or `agentChatDatabase` key) pointing at it; `~/agent-chat` (or `$AGENT_CHAT_REPO`) is a valid checkout of the new
repo containing `register-agent.sh` and `install-plugin.sh`.
**Steps:**
1. Run the nova-mind installer with the default `$HOME/agent-chat` sibling checkout present.
2. Repeat with `AGENT_CHAT_REPO=/custom/path` pointing at a checkout in a non-default location.
**Expected:**
- Both runs: installer detects the bus config, resolves the repo path via the env-override-with-default pattern,
  and invokes `register-agent.sh` from the resolved path (not a hardcoded `~/agent-chat` string — verify the env
  var actually takes precedence in run 2).
- `install-plugin.sh` is invoked immediately after `register-agent.sh` completes successfully (ordering assertion
  — mirrors the existing bats "Ordering:" test pattern already in the suite).
- After install, the current agent can successfully `send_agent_message()` on the bus (functional smoke test, not
  just "script ran").
- Current agent can receive: another agent (or a manual `send_agent_message` call) sends it a message; the
  OpenClaw agent_chat channel plugin (installed by `install-plugin.sh`) picks it up.

### TC-52 — Install WITH bus detected via DB probe (no `postgres.json` section, but DB reachable)
**Priority:** P2
**Preconditions:** Bus installed; `postgres.json` has no `agent_chat`/`agentChatDatabase` key, but a database
literally named `agent_chat` is reachable on the same connection parameters as the memory DB; sibling checkout
present at the resolved `AGENT_CHAT_REPO` path.
**Steps:** Run installer.
**Expected:** Per the issue's stated detection logic ("the `agent_chat` section in `~/.openclaw/postgres.json` (or
the DB itself)"), the installer must also probe the DB directly and treat this as bus-present, then proceed through
the same sibling-checkout resolution and `register-agent.sh`/`install-plugin.sh` invocation as TC-51. Verify this
fallback path actually exists and works — do not assume `postgres.json`-only detection is sufficient.

### TC-53 — Install WITH bus config present but bus DB actually unreachable (stale config)
**Priority:** P2 (edge case / error condition)
**Preconditions:** `postgres.json` has an `agent_chat` section pointing at a host/DB that is down or doesn't exist;
sibling checkout present.
**Steps:** Run installer.
**Expected:** Installer attempts registration, fails gracefully with a clear error distinguishing "bus configured
but unreachable" from "bus absent" — does not silently fall back to bus-absent mode (that would mask a real
misconfiguration), but also does not hard-abort the entire nova-mind install over an optional subsystem. nova-mind
install continues (non-zero-warning exit note per PL: the warning is real and visible, but does not fail the
overall install, since the bus remains an optional subsystem).

### TC-53a — Install WITH bus config present but the sibling checkout is missing (tooling absent)
**Priority:** P1 (Critical — explicit variant called out by PL, step 4)
**Preconditions:** `postgres.json`/DB-probe indicates a bus is configured and reachable, but `${AGENT_CHAT_REPO:-
$HOME/agent-chat}` does not exist on disk (no checkout, or wrong path).
**Steps:**
1. Run the nova-mind installer in this state.
2. Inspect installer output and exit code.
**Expected:**
- Installer detects the bus is configured (DB reachable / config present) but cannot find `register-agent.sh` /
  `install-plugin.sh` at the resolved path.
- A **clear, visible warning** is printed distinguishing this specific case from both "bus absent" (TC-50, silent,
  no warning) and "bus configured but DB unreachable" (TC-53) — e.g., "agent_chat bus is configured but the
  `agent-chat` repo checkout was not found at `<resolved path>`; registration skipped. Set AGENT_CHAT_REPO or clone
  the repo to enable bus integration."
- Install **continues** and completes successfully (exit 0) — per PL: "warn clearly, continue install (bus is
  optional), non-zero-warning exit note" — confirm the intended semantics precisely: the *warning* is emitted
  (non-silent), but the process **exit code is still 0** (does not fail the install over a missing optional
  component). Do not conflate "non-zero-warning" (a warning occurred) with "non-zero exit code" (process failure)
  — this test must assert warning-present AND exit-code-zero as two independent, both-required assertions.
- No partial/broken bus artifacts are left behind (no half-invoked `register-agent.sh` side effects).

### TC-54 — Staging isolation holds by construction (replaces the #569 guard)
**Priority:** P1 (Critical — this is the structural safety property the whole extraction is supposed to preserve)
**Preconditions:** Staging host configured with an isolated `agentChatDatabase` (e.g., `agent_chat_staging`) per the
old convention, OR (more likely under the new design) staging simply has no bus section configured at all.
**Steps:**
1. Run nova-mind installer on a staging-configured host.
2. Verify no writes land on the production `agent_chat` database under any circumstance.
**Expected:** Because nova-mind's installer no longer contains ANY code path that runs DDL/migrations against
`agent_chat` (that code moved entirely to the bus repo, which is invoked once-per-host by a human/deliberate action,
not implicitly by every per-agent install), a staging install run as any user against any config **cannot** mutate
production agent_chat — the property holds by construction, not by a runtime guard checking `whoami() != nova`.
Verify this explicitly: attempt to run the staging install as the `nova` production user against a staging config
and confirm it still does not touch the production bus DB (i.e., there is no longer a "guard that could be
bypassed" — there is no code path to bypass).

### TC-55 — Registration is idempotent when nova-mind installer is re-run (agent already registered)
**Priority:** P2
**Steps:** Run the nova-mind installer twice in a row with a bus present.
**Expected:** Second run either skips registration (already-registered detection) or calls `register-agent.sh`
again, which per TC-11 is itself idempotent — either way, no duplicate roles, no error, no `.pgpass` duplication.

### TC-56 — Schema version handshake: nova-mind warns on incompatible bus version
**Priority:** P2 (issue plan item 3)
**Preconditions:** Bus installed with a `schema_version` deliberately set/mocked to a version the nova-mind
installer's compatibility check does not recognize (e.g., a future version number).
**Steps:** Run nova-mind installer with bus present.
**Expected:** A clear warning is printed identifying the version mismatch; install does not silently proceed as if
everything is compatible, but also does not hard-fail unless the mismatch is a documented breaking-change boundary
(define the exact policy and test against it — this is new functionality per the issue's plan item 3, likely not
yet implemented; if absent, flag as a gap against AC4/plan item 3, not a pass).

---

## 8. Consumer Regression

### TC-60 — OpenClaw agent_chat channel plugin builds and loads from its new repo home via `install-plugin.sh`
**Priority:** P1 (Critical)
**Design decision (step 4, PL):** the plugin source (`cognition/focus/agent_chat/` contents: `index.ts`,
`src/channel.ts`, `src/config.ts`, `src/runtime.ts`, `lib/pg-env.ts`, fixtures) moves to the new `agent-chat` repo in
full — it is bus client code and "has no business in nova-mind post-extraction." The repo ships `install-plugin.sh`,
which performs: `npm install pg` to shared `~/.openclaw/node_modules/` (if not already present), extension
dependency install + `npm run build`, `dist/index.js` verification, the `openclaw.plugin.json` `main`-field fixup,
and the `channels.agent_chat`/`plugins.entries.agent_chat` config injection (dead-connection-key stripping +
`enabled: true` + `routeToSession: main`) — i.e. every piece of logic currently living in nova-mind's "Agent Chat
extension installation" and "Configure agent_chat channel" blocks (agent-install.sh lines ~2063–2144 and
~2878–2899) moves here verbatim.
**Preconditions:** Sibling checkout present (per TC-51); `register-agent.sh` already run for this agent.
**Steps:** Run `install-plugin.sh` (standalone, and as invoked by nova-mind's peer-detection per TC-51) from its new
repo location; inspect `~/.openclaw/extensions/agent_chat` and `~/.openclaw/openclaw.json` afterward; start
OpenClaw.
**Expected:**
- Plugin loads without error; `dist/index.js` present and correctly referenced in `openclaw.plugin.json`'s `main`
  field (identical fixup logic to the existing installer, now living in `install-plugin.sh`).
- `channels.agent_chat.enabled = true`, dead connection keys (`database/host/port/user/password`) absent;
  `plugins.entries.agent_chat.config.routeToSession = "main"`, same dead keys absent — direct port of the existing
  TC-67 bats assertions, now targeting `install-plugin.sh`'s output instead of `agent-install.sh`'s.
- Running `install-plugin.sh` a second time (idempotency) does not duplicate config keys or re-run `npm install`
  unnecessarily (mirrors the existing `FORCE_INSTALL`-gated skip logic for shared `pg` module install).

### TC-61 — `loadPgEnv(undefined, "agent_chat")` resolution unchanged
**Priority:** P1
**Steps:** With a valid `agent_chat` section in `postgres.json`, start the plugin; verify it connects using the
resolved host/port/database/user/password exactly as before (host/port fall back to flat keys, per the existing
`_ensure_agent_chat_postgres_json` comment: "Host/port fall back to the flat keys at runtime, so only
database/user/password are written in the nested block").
**Expected:** No behavior change in `lib/pg-env.ts`'s section-resolution logic — this file/logic must be preserved
verbatim in wherever it now lives (new repo, or still shared from nova-mind's `lib/pg-env.ts` if the plugin
continues to import a shared lib — clarify which and test the actual import path resolves).

### TC-62 — `agent_config_sync` extension still resolves `channels.agent_chat` fallback correctly
**Priority:** P2
**Steps:** With `plugins.entries.agent_config_sync.config` absent but `channels.agent_chat` populated, start
`agent_config_sync`.
**Expected:** Falls back to `channels.agent_chat` block exactly as today (`index.ts` lines ~48-50 logic preserved);
still works even though nova-mind's installer no longer writes the connection keys into that block (dead keys were
already stripped per the existing TC-67 bats test — confirm `agent_config_sync` never depended on those stripped
keys in the first place, since `loadPgEnv` is the actual credential source).

### TC-63 — `agent-spawner.py` and `github-issue-watcher.py`: confirmed out-of-scope, tracked issue is a required PR deliverable
**Priority:** P1 (Critical — explicit ecosystem daemon coupling per the task brief)
**Design decision (step 4, PL):** confirmed **out of scope** for this extraction PR. Refactoring the two daemons'
hardcoded `psycopg2.connect(dbname=...)` calls off ambient socket-auth defaults is deferred; a follow-up GitHub
issue tracking this work is a **required deliverable of this PR**, not a nice-to-have.
**Preconditions:** Bus extracted; these two daemons unchanged.
**Steps:**
1. Verify both daemons still connect successfully post-extraction, since the `agent_chat` DB continues to live on
   `localhost` with the default `nova`/socket-auth setup (extraction moves the *code/schema ownership*, not the
   DB's physical location, in this phase).
2. `gh issue list --repo NOVA-Openclaw/nova-mind --search "agent-spawner github-issue-watcher hardcoded socket" --state all`
   (per `UNIVERSAL/ISSUE_AND_TASK_HYGIENE`) to confirm the follow-up issue exists and is not a duplicate of an
   already-open issue; if absent at PR-merge time, this test **fails** — the tracked-issue's existence is now a
   hard pass/fail gate for this PR, not an aspirational note.
3. Confirm the follow-up issue explicitly references both scripts, both hardcoded `dbname=` call sites (from the
   step-2 report's line references), and the "breaks if agent_chat DB moves off localhost" risk.
**Expected:** Both daemons function correctly on this host today (unchanged connectivity). The follow-up issue
exists, is correctly scoped, and is linked from the extraction PR description. **This test blocks sign-off if the
issue is missing** — per PL's acceptance of the "must be visible, not swept under the rug" requirement, absence of
the tracked issue is treated as a failed acceptance criterion for this PR, not a separately-scheduled follow-up
that can slip silently.

### TC-64 — `generate-daily-log.py` continues to connect to `agent_chat` correctly
**Priority:** P2
**Steps:** Run the daily log generator post-extraction.
**Expected:** Connects successfully using its existing `connect()` helper (which already pops `PGPASSWORD` per the
#408 class fix); output unchanged in format/content for the agent_chat-derived sections of the report.

### TC-65 — `memory-maintenance.py` (semantic embedder) continues to read raw `agent_chat` messages
**Priority:** P3
**Steps:** Run the embedding maintenance job post-extraction.
**Expected:** Successfully connects and processes new messages for embedding; no connection errors attributable to
the extraction.

### TC-66 — Nightly `expire_old_chat()` cron targets `agent_chat` and succeeds (regression guard)
**Priority:** P1 (Critical — regression guard)
**Resolution (step 4, PL, confirmed):** the discrepancy between the step-2 report (describing a broken cron
targeting `nova_memory`) and this test design's live observation (`-d agent_chat`, working) is fully explained:
NOVA (orchestrator) fixed the crontab out-of-band on 2026-08-11 ~12:36 UTC — after scout wrote the step-2 report,
before this test-design pass began. Scout's report accurately described the prior defect state; the live
observation captured the post-fix state. No further reconciliation is needed. This TC is retained purely as a
forward-looking regression guard so the fix cannot silently revert during the extraction's installer edits.
**Steps:**
1. Confirm current crontab entry: `psql -d agent_chat -c "SELECT expire_old_chat();"` (confirmed present and
   correct at both test-design time and this revision).
2. Manually invoke the exact cron command line.
3. Check `~/.openclaw/logs/chat-expire.log` for errors on the most recent run.
4. **Cross-reference TC-19 (resolved this revision):** confirm empirically which role the cron connects as (unix
   user `nova` → DB role `nova`, confirmed via `SELECT current_user` in the same session context) and whether
   `expire_old_chat()`'s DELETE is blocked by the immutability trigger. **Empirical answer, confirmed live:** it is
   **not** blocked today — but not because of an authorized bypass. Per TC-19's finding, the
   `trg_enforce_agent_chat_function_use` trigger is bound to `BEFORE INSERT` only, so DELETE is simply never
   intercepted by any trigger, for any role, today. Once TC-19's required fix lands (correcting the trigger to
   cover `INSERT OR UPDATE OR DELETE`), this must be **re-verified**: `expire_old_chat()` is `prosecdef=false`
   (plain function, not `SECURITY DEFINER`), so once the trigger actually fires on DELETE, `current_user` inside
   it will be the cron's connecting role (`nova`), not `postgres` — the trigger's `current_user = 'postgres'`
   bypass will **not** cover it, and the cron **will break** post-fix unless `expire_old_chat()` is also made
   `SECURITY DEFINER` (or the trigger's bypass condition is extended to recognize `expire_old_chat()`'s call
   context). Do not treat TC-19's fix and TC-66 as independent — landing one without the other converts this
   already-flagged risk into an actual nightly-cron regression.
**Expected:** Command succeeds today (pre-TC-19-fix), returns a count (integer, possibly 0), no "function does not
exist" error. **Post-TC-19-fix, this test must be re-run** and is expected to only pass if `expire_old_chat()` has
also been updated (made `SECURITY DEFINER`, owner `postgres`) in the same PR that fixes the trigger scope.

---

## 9. Cross-Cutting / End-to-End

### TC-70 — Full lifecycle smoke test: fresh host, bus install, two agent registrations, cross-agent message
**Priority:** P1 (Critical — the composite "does it actually work" test)
**Steps:**
1. Fresh staging host, no bus.
2. Install the bus (TC-01).
3. Register two agents via `register-agent.sh` (TC-10) — e.g., `gem` and `flint`.
4. Run nova-mind installer for each agent with bus present (TC-51).
5. As `gem`, send a message to `flint` via `send_agent_message`.
6. As `flint`, poll/read the message (directly via SELECT as `flint`, since `flint` has `SELECT` grant — or via the
   OpenClaw channel plugin if both are running full agent stacks).
**Expected:** End-to-end message delivery works exactly as it does today on production, using only the new repo's
components — zero nova-mind-owned bus code involved in the runtime path.

### TC-71 — Full lifecycle: bus-absent solo install produces a working non-bus agent
**Priority:** P1
**Steps:** Fresh staging host, no bus, install nova-mind for a single agent with no `agent_chat` config anywhere.
**Expected:** Agent installs and runs fully functional for all non-bus features; no agent_chat-related errors ever
surface in logs; confirms the issue's stated goal that "solo-agent installs shouldn't carry bus machinery at all."

### TC-72 — Rollback scenario: extraction PR reverted, old installer still functions
**Priority:** P3 (safety net during the transition period)
**Steps:** If both old and new installer code paths coexist temporarily (e.g., feature-flagged), verify the old
`_apply_agent_chat_migrations` path still works correctly if invoked, until it is fully removed.
**Expected:** No partial-state corruption possible during a rollback window; only relevant if the migration is
staged rather than atomic — confirm with the implementation plan whether this applies.

---

## 10. Known Gaps / Items Requiring Design Clarification Before Test Execution

**Status as of Rev 2 (step 4):** all five originally-open items are now resolved via PL decision or empirical
verification. Retained below with resolutions recorded for traceability; one **new** blocking finding was
discovered while resolving item 1, and is called out separately as it is more severe than originally scoped.

1. **TC-19 blocking finding — RESOLVED (verified live), but the actual defect is worse than originally scoped.**
   Original framing: "`expire_old_chat()` is not `SECURITY DEFINER`; confirm the cron's role isn't blocked by the
   immutability trigger." **Empirical finding:** the immutability trigger (`trg_enforce_agent_chat_function_use`)
   is bound to `BEFORE INSERT` only on the live table — it never fires for UPDATE or DELETE at all, for any role.
   The cron's DELETE succeeds today not because of an authorized `current_user = 'postgres'` bypass, but because
   **no trigger intercepts DELETE in the first place**. This means the immutability guarantee does not exist today
   for UPDATE/DELETE by any of the 21 agent roles holding `arwd` grants. **Required fix, this PR:** correct the
   trigger binding to `BEFORE INSERT OR UPDATE OR DELETE` in the new repo's `schema.sql`, and simultaneously make
   `expire_old_chat()` `SECURITY DEFINER` (owner `postgres`) so the nightly cron does not break once the trigger
   is actually enforcing the contract it claims to. See TC-19 and TC-66 for the full analysis and required
   sequencing.
2. **TC-51 registration mechanism — RESOLVED (PL decision).** Sibling-checkout convention:
   `${AGENT_CHAT_REPO:-$HOME/agent-chat}`, invoked by nova-mind's peer-detection. Missing-checkout case added as
   TC-53a. See TC-51/TC-52/TC-53/TC-53a.
3. **TC-60 plugin distribution — RESOLVED (PL decision).** Plugin source moves to the new `agent-chat` repo in
   full; the repo ships `install-plugin.sh` (build/sync/main-field-fixup/config-injection), invoked by nova-mind's
   peer-detection immediately after `register-agent.sh`. See TC-44/TC-60.
4. **TC-63 scope decision — RESOLVED (PL decision).** Confirmed out of scope for this PR. A follow-up tracked
   GitHub issue covering both hardcoded-socket daemons is now a **required PR deliverable** — its absence at merge
   time is a test failure (TC-63), not an aspirational note. See TC-63.
5. **TC-66 discrepancy — RESOLVED (confirmed by PL).** NOVA fixed the crontab out-of-band on 2026-08-11 ~12:36 UTC,
   after scout's step-2 report was written and before this test design pass. No further reconciliation needed;
   TC-66 now serves purely as a forward regression guard, with an added cross-reference to the TC-19 fix
   sequencing requirement. See TC-66.
6. **New (Rev 2): listener reconnect gap.** Code inspection of the existing `pg-notify-listener.py`'s `main()` loop
   shows no reconnect-on-dead-connection logic — a single Postgres restart or terminated backend causes the
   process to spin forever in an "alive but permanently deaf" state. Recommended to fix in the brand-new
   `pg-notify-listener-chat.py` rather than port the gap forward. See TC-29A.

---

## Summary

- **Total test cases:** 66 named (TC-01–TC-66) + TC-29A, TC-53a (two additions this revision) + 6
  end-to-end/cross-cutting (TC-70–TC-72, consolidated numbering above) = 68 distinct test cases. Zero open design
  questions remain unresolved as of Rev 2; §10 is now a resolution log plus one newly-surfaced blocking finding
  (item 1) and one newly-added test (item 6/TC-29A).
- **P1 (Critical):** 30 — installer core (idempotency, adoption, security, immutability), listener correctness
  (including the new TC-29A reconnect test), removal completeness, peer-detection core paths (including the new
  TC-53a missing-checkout case), consumer scope gates (TC-63's tracked-issue requirement), and the E2E smoke tests.
  These block sign-off.
- **P2:** 24 — secondary correctness, concurrency, documentation, and consumer paths.
- **P3:** 9 — cosmetic/documentation/deferred-scope items.
- **One item requires a code fix before this PR can merge, not just a test to run:** TC-19's revised finding — the
  immutability trigger's scope must be corrected (`BEFORE INSERT` → `BEFORE INSERT OR UPDATE OR DELETE`) and
  `expire_old_chat()` must be made `SECURITY DEFINER`, in the same commit, or the nightly cron regresses the moment
  the trigger fix lands (TC-66 cross-reference). This is the single highest-priority action item for Coder coming
  out of this test design.

Coordinate with Flint (QA Executor) for execution once implementation lands. Recommend running TC-01 through TC-09
(bus installer), TC-15 through TC-19 (security — note TC-19 is now a required-fix gate, verify the trigger-scope fix
lands before marking it passed), and TC-66 (cron, re-run after the TC-19 fix) as the first executable batch, since
they gate everything else.
