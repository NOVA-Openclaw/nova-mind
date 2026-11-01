# Test Cases — nova-mind#640 (PR #641): pg.Pool 'error' handler in bootstrap-context hook

SE run #1449 (workflow 4). Design of record for the merge of PR #641.
Artifact under test: branch `fix/640-pg-pool-error-handler` @ 911d152, merged locally onto main f38d47e (merge-tree clean).

## Scope
`cognition/focus/bootstrap-context/hook/handler.ts` — `getPool()` attaches a `pool.on('error')` listener
immediately after constructing the singleton pg.Pool. Without it, an idle-client error (e.g. a postgres
restart or `pg_terminate_backend` on a pooled, unused connection) is emitted on the pool with no listener,
Node throws it, and the gateway process exits.

## Test cases

| ID | Type | Scenario | Expected |
|----|------|----------|----------|
| TC-640-01 | unit (handler.test.ts) | FakePool (real EventEmitter) via `__testing.setPoolConstructor`; emit 'error' on the pool | no throw |
| TC-640-02 | kill-check | Same as 01 with the listener disabled in handler.ts | TC-640-01 FAILS with "terminating connection due to administrator command" |
| TC-640-03 | regression | Existing handler.test.ts + bootstrap-pg-config.test.ts suites (TC-19, TC-02, override detection) | all pass |
| TC-640-04 | integration, real Postgres (staging DB nova_staging_memory, nova-staging role) | Real pg.Pool via the hook's own `getPool()`; open a client, release it idle, `pg_terminate_backend(<its pid>)` from a second connection, wait 1.5s | process survives; warn line `[bootstrap-context] pg pool error (non-fatal): terminating connection due to administrator command`; pool drops the dead client (idle=0,total=0) |
| TC-640-05 | integration, recovery | After TC-640-04, call `loadFromDatabase()` again | pool opens a new connection and the query reaches the server (no connection error) |
| TC-640-06 | integration, control | TC-640-04 with `pool.removeAllListeners('error')` first (pre-fix behaviour) | process exits code 1: `Emitted 'error' event on BoundPool instance` — proves TC-640-04 exercises the real crash path |

Adversarial/seam note: TC-640-04..06 use the real config→runtime seam (installed `~/.openclaw/lib/pg-env.ts`,
`postgres.json`, real libpq server-side termination), not a hand-built fixture.

## Results (SE #1449, 2026-11-01)

- TC-640-01, 03: `npx tsx --test handler.test.ts bootstrap-pg-config.test.ts` → tests 17, pass 17, fail 0, exit 0.
- TC-640-02: listener disabled → pass 2, fail 1 (`actual: Error: terminating connection due to administrator command`), exit 1.
- TC-640-04/05: PASS — `terminated=true`, non-fatal warn logged, `survived; pool idle=0 total=0`, second load reached the server, `EXIT mode=fix code=0`.
- TC-640-06: PASS (control crashed as predicted) — `EXIT mode=control code=1`, `Emitted 'error' event on BoundPool instance`.

## Not tested on staging (and why)
- P0 "hook loads in a live gateway" check: not run. This run's hard limit forbids restarting any gateway, and the staging
  gateway currently carries SE #1231's deployed state. The hook was exercised directly from the installed staging layout instead.
  Covered at production deploy (step 11) by the journal "failed to load hook" check.

## Incidental staging observations (not caused by this change)
- Staging `~/.openclaw/lib/pg-env.ts` predates #775 (`resolveAgentDatabase is not a function`); main's handler falls back to the
  hard-coded config in that case. Production's pg-env.ts does export `resolveAgentDatabase`.
- `nova-staging` role lacks SELECT on `agent_bootstrap_context` in nova_staging_memory (grant gap on staging).
