# Staging Test Notes — nova-mind#488 Bootstrap Override

These integration tests require live PostgreSQL fixtures and are therefore
deferred to the staging phase (run by the QA executor against the staging
environment). Unit tests in the repo cover the config-resolution logic.

## Unit-Covered (no live DB needed)

- `memory/lib/pg-env.test.ts`
  - Bootstrap section precedence and per-field fallback
  - Absent/null/malformed/non-object section handling
  - Whitespace-only values treated as absent
  - ENV vars winning over section values
  - Section isolation (bootstrap does not leak into flat/agent_chat callers)

- `cognition/focus/bootstrap-context/hook/bootstrap-pg-config.test.ts`
  - Detection of configured `bootstrap` section
  - Unknown-key collection and warning formatting
  - Distinct pg-env-unavailable warning when override is configured

## Staging-Deferred (requires live Postgres fixtures)

Create three fixture databases on the staging host:

- `test_primary_db` — schema present, `agent_bootstrap_context` has **zero**
  rows for the test agent (simulates a post-split primary DB).
- `test_bootstrap_db` — has `agent_bootstrap_context` rows for the test agent
  (UNIVERSAL + GLOBAL + AGENT) and a working `get_agent_bootstrap()` function.
- `test_bootstrap_db_no_fn` — schema present but `get_agent_bootstrap()`
  deliberately missing.

Test matrix (from `/tmp/gem-testplan-nova-mind-488.md`):

| TC | Priority | What to exercise |
|----|----------|------------------|
| TC-01 | P0 | No override → queries the primary DB |
| TC-03 | P0 | Override present → queries `test_bootstrap_db`, zero queries hit primary |
| TC-04 | P1 | Full connection override (all five fields diverge) |
| TC-05 | P0 | Override DB unreachable → ECONNREFUSED fallback |
| TC-09 | P0 | Override DB missing function → 42883 fallback |
| TC-10 | P0 | Override DB returns 0 rows → fallback |
| TC-11 | P1 | Partial override (`database` only) |
| TC-12 | P1 | Partial override (`host`+`port` only) |
| TC-13 | P1 | Override equal to primary (no-op) |
| TC-17 | P0 | pg-env import failure + configured override → distinct warning |
| TC-19 | P0 | Pool construction error path (use malformed override host) |
| TC-20/21 | P0 | Secret-leak grep across happy/error logs |
| TC-22 | P0 | Pool lifecycle / no accumulation across repeated events |
| TC-24 | P0 | Backwards-compat diff for nova/graybeard/victoria configs |
| TC-25 | P1 | Missing `postgres.json` behaves like today |
| TC-26 | P1 | `PGDATABASE` env var wins over bootstrap section |

## Backwards-Compatibility Gate

TC-24 is the hard merge gate: capture the hook's output for nova, graybeard,
and victoria using their current (no-override) `postgres.json`, apply the fix,
and diff. The output must be byte-identical for any agent without a `bootstrap`
section.
