# SE #717 Step 5 Implementation Notes

## nova-mind (#612 salvage + completion)

- Salvaged partial work from `issue-611-extraction-context-window` via `git stash push -u`, recreated `fix/612-remove-pg-notify-listener` from `main`, and popped the stash.
- Deleted the relocated test files and `conftest.py` from `cognition/tests/` after confirming zero sibling dependents.
- Updated `memory/docs/database-config.md` to point at `nova-workspace/scripts/pg-notify-listener.py`.
- Updated `cognition/docs/system-level-controls.md` and `cognition/README.md` already in partial work; verified no stale listener deployment bullet remains.
- Added CHANGELOG entry and a forward pointer in `tests/TEST-CASES-ISSUE-579.md`.
- Validated `bash -n agent-install.sh` and `git grep` hygiene (only allowed comments/historical files remain).
- Ran `python3 lib/tests/test_pg_env.py`: 78 passed, 0 failed.

## nova-workspace continuation (r3)

- Squashed prior `issue-612-listener-relocation` work onto target branch `feat/canonical-pg-notify-listeners` (commit `91e6230`) and pushed.
- Verified reconciled `pg-notify-listener.py` contains nova-mind fixes (#399 push retry/alerting, #506 branch safety, #508 PGUSER sender, #405/pg_env) plus nova-workspace #21 reconnect backoff and #22 SIGHUP log-reopen, with nova-only getpass guard.
- Added `pg-notify-listener-agent-chat.py` (relocated from agent-chat, renamed, paths corrected, nova-only guard).
- Added `scripts/install-listeners.sh` (nova-only, idempotent, copies `lib/pg_env.py` to deploy target).
- Added/updated systemd units for both listeners.
- Relocated tests into `tests/pg_notify_listener/` (50 nova-mind tests + agent-chat suite + reconcile tests); fixed import/path references.
- Test results: 109 pytest passed, 5 bats passed.
- Updated docs: `docs/pg-notify-listener.md`, `README.md`, `memory/schema-reference.md`.
- Deleted local `issue-612-listener-relocation` branch in nova-workspace after squash.

## agent-chat continuation (r3)

- Verified prior commit `e020db5`: `listener/` removed, install.sh listener wiring removed, listener tests removed, CHANGELOG entry added, docs updated.
- `bash -n install.sh` passes.
- Audit of `install.sh`: no other ungated local-only tooling found.
- `git grep -i "pg-notify-listener\|listener"` hygiene sweep: only appropriate references to the relocated listener in nova-workspace remain.

## Cleanup

- Removed `/tmp/se717-transfer`.
- Left `issue-612-listener-relocation` in place in agent-chat and nova-mind because those branches contain the respective commits.
