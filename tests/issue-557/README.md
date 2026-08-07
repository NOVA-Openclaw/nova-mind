# Issue 557 — `append_run_note()` Test Suite

## Automated tests

Run the automated suite against a staging database:

```bash
cd /home/nova/nova-mind
./tests/issue-557/test-append-run-note.sh
```

Environment variables (all optional):

| Variable | Default | Purpose |
|----------|---------|---------|
| `TEST_PGDATABASE` | `nova_staging` | Target database |
| `TEST_PGUSER` | `nova` | Privileged user for DDL and test orchestration |
| `TEST_PGHOST` | `localhost` | Database host |
| `TEST_PGPASSWORD` | *(unset)* | Password for optional end-to-end role connection probes |

The script implements TC-1 through TC-16 from the Step 3 test design. It creates
`workflow_runs` in the target database if absent, applies the
`append_run_note(integer, text)` function extracted from `database/schema.sql`,
runs the cases, and removes only the test rows it inserted.

The script refuses to run against `nova_memory` or `postgres` as a safety guard.

## Manual staging steps: TC-17 / TC-18 (pgschema apply idempotency)

TC-17 and TC-18 verify that `database/schema.sql` applies cleanly and
idempotently via pgschema. These are manual because pgschema's planning phase
validates the desired state in a temporary schema; applying the full
`schema.sql` (including default-privilege statements that reference the
production role set) against an embedded or empty plan database can fail with
role or privilege errors. Run these on a staging database that already mirrors
production roles and object ownership.

> **Superuser required.** `database/schema.sql` contains `ALTER DEFAULT
> PRIVILEGES FOR ROLE postgres` statements that only a PostgreSQL superuser can
> execute. Run the pgschema commands below as the superuser for your environment
> (the installer uses `$PG_SUPERUSER` via `_superuser_pgschema`; replace
> `<superuser>` in the examples with that role name).
>
> **Two-step plan → apply.** `pgschema 1.7.2` mutates the target database's
> `source_fingerprint` on the first plan run when `--plan-db` points at the
> target DB. Single-shot `pgschema apply --file ...` therefore fails with a
> schema fingerprint mismatch. Use the installer's two-step flow: plan to JSON,
> then apply the saved plan.

### TC-17: pgschema apply when `append_run_note` does not yet exist

1. Ensure the staging database is at a schema state from before this change
   (no `append_run_note` function).
2. From the repo root, plan to JSON and then apply the saved plan:

   ```bash
   cd /home/nova/nova-mind

   pgschema plan \
     --db nova_staging \
     --user <superuser> \
     --host localhost \
     --plan-db nova_staging \
     --plan-user <superuser> \
     --plan-host localhost \
     --file database/schema.sql \
     --output-json /tmp/append-run-note-plan.json

   pgschema apply \
     --db nova_staging \
     --user <superuser> \
     --host localhost \
     --plan /tmp/append-run-note-plan.json \
     --auto-approve
   ```

   The `--plan-*` flags point pgschema at the real target database for its
   planning/validation phase. This matches the standard invocation used by
   `agent-install.sh` and avoids failures caused by applying the full
   `schema.sql` against an embedded or empty plan database. The two-step
   plan-to-JSON → apply flow is the same flow the installer uses.

3. Verify the function exists and has the expected properties:

   ```sql
   \df append_run_note
   SELECT prosecdef, proconfig
   FROM pg_proc
   WHERE proname = 'append_run_note';
   ```

4. Re-plan to confirm zero pending changes:

   ```bash
   pgschema plan \
     --db nova_staging \
     --user <superuser> \
     --host localhost \
     --plan-db nova_staging \
     --plan-user <superuser> \
     --plan-host localhost \
     --file database/schema.sql
   ```

### TC-18: pgschema re-apply idempotency

1. With `append_run_note` already applied from TC-17, re-run the same two-step
   plan → apply:

   ```bash
   pgschema plan \
     --db nova_staging \
     --user <superuser> \
     --host localhost \
     --plan-db nova_staging \
     --plan-user <superuser> \
     --plan-host localhost \
     --file database/schema.sql \
     --output-json /tmp/append-run-note-plan.json

   pgschema apply \
     --db nova_staging \
     --user <superuser> \
     --host localhost \
     --plan /tmp/append-run-note-plan.json \
     --auto-approve
   ```

2. Confirm the apply exits cleanly with no destructive side effects.
3. Re-run the automated test suite to confirm the function is still callable:

   ```bash
   ./tests/issue-557/test-append-run-note.sh
   ```

4. Re-plan to confirm zero pending changes:

   ```bash
   pgschema plan \
     --db nova_staging \
     --user <superuser> \
     --host localhost \
     --plan-db nova_staging \
     --plan-user <superuser> \
     --plan-host localhost \
     --file database/schema.sql
   ```

## Notes

- The automated suite uses catalog privileges (`has_function_privilege`,
  `has_table_privilege`) to verify that SELECT-only agent roles can execute
  `append_run_note` but cannot `UPDATE workflow_runs` directly. An optional
  end-to-end connection as `gem` is performed when `TEST_PGPASSWORD` is set.
- Empty-string notes are intentionally accepted; only `NULL` notes raise an
  exception, as documented in the function's `COMMENT ON FUNCTION`.
