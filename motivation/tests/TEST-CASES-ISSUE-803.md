# Test Cases for Issue #803: D100 Motivation — Per-Slot `weight` Column & Weighted `roll_d100()`

> **SE #1481 design record.** Per the Step 9 (Technical Writing) QA recommendation to
> archive this file, it is retained here rather than moved — the repo has no
> `archive/`/historical test-cases directory for QA design docs of this kind. Treat it as
> a point-in-time design record of the Step 3/4 test design, not living documentation; the
> current behavior (and the one post-publication correction — see "Retired cases" below,
> where the M7/D3 `GRANT`-on-`weight` cases were retired when #808 dropped the redundant
> grant) is documented in `motivation/README.md`/`motivation/ARCHITECTURE.md`.

**SE Run #1481 — Step 3/4 QA test design, approved by orchestrator Step-4 review (2026-11-14)**

Sources read: `nova-mind#803` (issue body + I)ruid's Step-1 rulings comment,
2026-11-14), fresh clone of `NOVA-Openclaw/nova-mind` main @ `090eb88`
(`memory/migrations/082_blockers_and_d100_roll_history.sql`,
`memory/migrations/084_d100_motivation_refinements.sql`,
`database/schema.sql`), the live `roll_d100()` definition and table shapes via
read-only `psql -U nova -d nova_memory -h localhost` (matches the repo
exactly -- no drift), `memory/scripts/announce-d100-rolls.py`,
`motivation/README.md` (`#d100-roll-mechanics` and `#d100-roll-announcer`
sections) and `motivation/ARCHITECTURE.md` §5 (D100 Motivation Table
component), the existing `motivation/tests/test_roll_d100_migration.py`
suite (extended here, not replaced), and `database/check_schema_manifest.py`
/ `database/.schema-manifest.toml` / `database/schema-reference.md` /
`memory/docs/database-schema-guide.md` / `database/tests/test_check_schema_manifest.py`
for the schema-delivery and manifest mechanism.

**Doc parity check:** `motivation/README.md#d100-roll-mechanics` and
`motivation/ARCHITECTURE.md` §5 both match the current migration-084
behavior exactly -- no drift found. Like `schema-reference.md`/
`database-schema-guide.md` (already flagged in the issue's Step 2 docs
check), these two files will also need a weight section once #803 ships.

**Status:** All open questions from the Step-3 draft (Q1-Q5) and the
follow-up questions raised while drafting (Q6-Q8) were resolved by
orchestrator ruling across two Step-4 review messages (2026-11-14). This is
the final, fully-resolved version. Zero open items remain.

---

## 0. Rulings baked into every test case below

From I)ruid's Step-1 rulings (2026-11-14), the issue's acceptance criteria,
and the Step-4 orchestrator review (both messages):

1. `weight = 0` is a **soft mute**: never drawn, and excluded from the 50%
   cap's `total_pop`/`recent_pop` denominators exactly as if the slot were
   `enabled = false` -- independent of the actual `enabled` value. **(Q2.)**
2. Draw only among **ELIGIBLE** slots:
   - Empty: `task_name IS NULL AND reserved = false AND enabled = true AND
     weight > 0`. **(Q1: `enabled = true` is required, matching today's
     path A exactly.)**
   - Populated: `task_name IS NOT NULL AND enabled = true AND weight > 0`,
     subject to the (weight-0-excluded) anti-repeat window/cap.
   - Must produce the same *results* as today for all weight-1 slots -- it
     only removes wasted re-rolls.
3. `idle-d100.sh` is deleted and out of scope. No tests for it below.
4. `roll #71` gets `weight = 3` after deploy -- not a test-time concern, but
   used as a flavor example in the statistical section.
5. 7-day anti-repeat window and its 50% re-admission cap are preserved
   byte-for-byte in behavior, **except** that weight-0 rows are now excluded
   from the cap's population counts (see item 1).
6. `is_populate_me` and the full return signature of `roll_d100()` are
   unchanged.
7. `idle-d100.sh`, `announce-d100-rolls.py`, and `_trg_log_d100_roll` must
   keep working with zero code changes.
8. Migration is `ADD COLUMN IF NOT EXISTS weight numeric NOT NULL DEFAULT 1
   CHECK (weight >= 0)`, safe on fresh install and upgrade, at
   **`memory/migrations/089_d100_weights.sql`** (089 is the next number
   after 088; confirmed, not a guess, per Q6). `numeric` (fractional) input
   is legal and **required** to work correctly. **(Q5/Q6.)**
9. All-weight-1 behavior must match current behavior exactly.
10. The all-ineligible error path keeps the **exact existing error text**
    from the live function (`roll_d100: no populated+enabled tasks found
    after 20 attempts`), asserted exactly, so any caller that matches on
    that string keeps working. **(Q4.)**
11. The sampling technique (Efraimidis-Spirakis, cumulative-sum, or
    anything else) is an implementation choice; tests assert observable
    behavior only. **(Q3.)**
12. The schema change ships via the live pg-notify-listener schema dumper
    (`cognition/scripts/pg-notify-listener.py`'s `sync_schema_to_github()`).
    Nobody hand-edits `database/schema.sql`. Area I verifies the dump's
    result post-deploy, not in CI.
13. `roll_d100()` is rewritten via a **plain `CREATE OR REPLACE FUNCTION`**
    (no `DROP FUNCTION` first, no manual `GRANT EXECUTE ... TO nova;`
    restoration line like migration 084 needed): the return signature is
    unchanged, so `CREATE OR REPLACE` is legal, simpler, and preserves
    existing grants (including `EXECUTE`) automatically. **(Q8.)**
14. The implementation PR for #803 adds `roll_d100()` (with its
    `SECURITY DEFINER`/`search_path = public` properties) and the
    `motivation_d100.weight` column to `database/.schema-manifest.toml`, so
    the automated schema dumper can never silently clobber them the way
    `append_run_note()` was clobbered in #624. Area I/D4 verifies this.
    **(Q7.)**

---

## 1. Test environment & delivery path (never touch live `nova_memory`, never hand-edit schema.sql)

### 1.1 How the schema change actually ships

`database/schema.sql` is **not** a hand-maintained artifact for structural
DDL. Per `memory/docs/database-schema-guide.md` and
`database/schema-reference.md`:

- The live database is the source of truth. `cognition/scripts/pg-notify-listener.py`
  listens for schema-change notifications, runs `pgschema dump` against the
  live DB, strips a couple of non-portable artifacts
  (`ALTER DEFAULT PRIVILEGES` blocks), checks the dump against
  `database/.schema-manifest.toml` (refuses/reverts the whole dump if any
  manifest-listed object by name would be removed), and commits the result
  to `database/schema.sql` on `nova-mind` main as `sync_schema_to_github()`.
- `database/check_schema_manifest.py` is a second-line, static, repo-only CI
  backstop (no DB connection) that re-asserts the same manifest + the
  `[function_security]` properties against whatever `schema.sql` is
  currently committed.
- `pgschema dump` only emits structural DDL -- it does **not** emit
  column/table-level `GRANT`/`REVOKE` statements. Those are hand-maintained
  directly in `schema.sql` (e.g. the `motivation_d100`/`d100_roll_log`
  grants added for issue #444) and must be added by a human in the same PR
  as the migration.

**Consequence:** no test case assumes a pre-existing, hand-edited
`database/schema.sql` that already contains the `weight` column or the
rewritten `roll_d100()` body -- that artifact does not exist until *after*
the live apply + automated dump round-trips back into the repo. Every
migration/behavior test (Area A) instead applies the **change SQL** (the new
migration file's DDL, at `memory/migrations/089_d100_weights.sql`) directly
to a throwaway database seeded from the *current, already-committed*
`database/schema.sql` baseline. Area I is the one section that genuinely
runs post-deploy, against the real dumped artifact, and is explicitly
marked as such (it runs as a deployment-step check, not a CI gate).

### 1.2 Extend the existing suites, don't start new ones

`motivation/tests/test_roll_d100_migration.py` already exists and already
tests `roll_d100()` end-to-end for nova-mind#444/#453 regressions, using
this pattern:

- `_extract_roll_d100_block(sql)` pulls the `CREATE OR REPLACE FUNCTION
  roll_d100() ... $$;` block straight out of
  `memory/migrations/084_d100_motivation_refinements.sql` (the source of
  truth), rather than trusting a possibly-stale copy baked into test
  fixtures. For #803 this extracts the same block from
  `memory/migrations/089_d100_weights.sql` instead (updated to a plain
  `CREATE OR REPLACE` with no preceding `DROP FUNCTION`, per ruling 13).
- `_connect()` wraps `pg_env`'s loader and defaults to
  `PGDATABASE=nova_memory` if unset, relying on an explicit
  `conn.rollback()` in every test's `finally` block for safety instead of a
  throwaway database.
- Three existing tests (`test_deployed_roll_d100_runs_without_privilege_errors`,
  `test_roll_d100_from_migration_returns_row`,
  `test_roll_d100_from_migration_anti_repeat_no_ambiguous_column`) stay
  **unmodified** -- they test different, already-accepted concerns (deployed-
  function privilege/ambiguity regressions) and predate #803.

`database/tests/test_check_schema_manifest.py` also already exists (static,
repo-only, no DB connection -- it builds synthetic manifest/schema strings
in memory and calls `check_schema_manifest`'s functions directly). Area I's
D4 (manifest coverage) extends **that** file, not
`test_roll_d100_migration.py`, since D4 is a pure text/manifest check with
no DB involved at all -- it belongs next to the other static manifest tests,
following the file's existing `MANIFEST_*`/`SCHEMA_*` synthetic-fixture
convention.

All new #803 Area A-H tests are added to `test_roll_d100_migration.py`,
reusing/extending `_extract_roll_d100_block()`-style extraction against the
new migration file, and adding one new piece of infrastructure the file
doesn't have yet:

```python
import uuid

def _create_throwaway_db() -> str:
    """Create and return a uniquely-named throwaway database, mirroring
    memory/tests/test_migration_083_idempotency.py's pattern. Never touches
    whatever PGDATABASE/_connect() would otherwise resolve to."""
    db_name = f"nova_memory_test_803_{uuid.uuid4().hex[:8]}"
    admin = _connect_admin()  # host=localhost, user=nova, dbname=postgres
    admin.autocommit = True
    with admin.cursor() as cur:
        cur.execute("DROP DATABASE IF EXISTS %s", (psycopg2.extensions.AsIs(db_name),))
        cur.execute("CREATE DATABASE %s", (psycopg2.extensions.AsIs(db_name),))
    admin.close()
    return db_name

def _drop_throwaway_db(db_name: str) -> None:
    admin = _connect_admin()
    admin.autocommit = True
    with admin.cursor() as cur:
        cur.execute("DROP DATABASE IF EXISTS %s", (psycopg2.extensions.AsIs(db_name),))
    admin.close()
```

Every Area A-H test case runs against a database created by
`_create_throwaway_db()`/`_drop_throwaway_db()`, loaded first with the
*current, already-committed* `database/schema.sql` (or the minimal
`workflows`/`motivation_d100`/`d100_roll_log` fixture already used by
`test_migration_083_idempotency.py`, for fast role-free unit tests of the
pure weighted-draw/anti-repeat logic), never the live `nova_memory` and
never a hand-edited copy of `schema.sql`. This must run against the
**nova-staging** Postgres instance (SSH `nova-staging@localhost`) per
standing test policy. No `sudo` is required -- `CREATE DATABASE`/`DROP
DATABASE` as the `nova` role is sufficient.

Area I (post-deploy verification) is the one exception: D1-D3 run against
the real, already-committed `nova-mind` main repo state after deployment
(no throwaway DB, no live-DB connection); D4 is a static manifest check
that can run any time after the manifest entries land, extending
`database/tests/test_check_schema_manifest.py`.

**Fallback harness** -- fully hermetic temp cluster (for CI runners with no
shared Postgres at all): `initdb` into a scratch directory, `pg_ctl` start
on a free port as the current unix user (no sudo), run the same
migration/assertions, `pg_ctl stop` + `rm -rf` the scratch dir afterward.
Roles referenced by `GRANT` statements won't exist here, so either
pre-create the handful needed (`nova`, `cadence`, `graybeard`) with
`CREATE ROLE ... NOLOGIN;` or reuse `database/filter_shadowed_grants.py`/
`strip_destructive.py`-style line stripping to drop `GRANT`/`REVOKE` lines
targeting roles that don't exist in the minimal fixture.

**Hard rule for every Area A-H test case:** no test ever connects to the
production host's `nova_memory`, and no test ever loads a hand-edited
`schema.sql`. The only production contact for this whole design phase was
the read-only `psql`/`pg_get_functiondef` introspection already performed
to confirm the live function matches the repo (it does, byte-for-byte).

---

## 2. Statistical methodology (shared by all Section B cases)

- **In-database batch loop**, not N round-trips from a test runner -- much
  faster and avoids network jitter:
  ```sql
  CREATE TEMP TABLE _sim_results (roll integer);
  DO $$
  DECLARE r record;
  BEGIN
      FOR i IN 1..10000 LOOP
          SELECT * INTO r FROM roll_d100();
          INSERT INTO _sim_results (roll) VALUES (r.roll);
      END LOOP;
  END $$;
  SELECT roll, count(*) FROM _sim_results GROUP BY roll;
  ```
- **Deterministic seed + tolerance band, combined**: call
  `SELECT setseed(0.42);` (and 2-3 other fixed seeds, to catch a
  seed-specific fluke) once per test before the loop. Note: PG's
  `random()` stream is stable within a major version but is **not**
  guaranteed byte-identical across major Postgres versions -- treat the
  seed as an anti-flake aid, not a cross-version golden value.
- **Pass/fail oracle**: for a slot with expected draw probability `p`
  among the eligible pool (`p = weight_i / sum(weight_eligible)`), expected
  count `mu = N*p`, binomial std-dev `sigma = sqrt(N*p*(1-p))`. Accept if
  `|observed - mu| <= max(4*sigma, 0.02*mu)` (4-sigma ~= 1-in-15,000
  false-failure rate per slot; the relative floor keeps small-`p` slots
  from having a vacuously tiny absolute band).
- **Isolating weight from anti-repeat**: there's no function flag for this,
  so the harness neutralizes it the same way the function would see "never
  rolled" -- `UPDATE motivation_d100 SET last_rolled = NULL WHERE task_name
  IS NOT NULL;` run once before the loop (for empty-slot-only tests this is
  unnecessary, since path A -- unreserved empty -- never consults
  anti-repeat at all, which makes empty slots the *cleanest* place to
  isolate pure weight-ratio behavior).

---

## A. Migration tests (9 cases)

All cases below apply the new migration's **change SQL** (at
`memory/migrations/089_d100_weights.sql`) directly -- never a hand-edited
`schema.sql` -- to a throwaway DB seeded from the current, already-committed
`database/schema.sql` baseline (see Section 1.1).

| # | Goal | Pre-conditions | Action | Expected |
|---|------|-----------------|--------|----------|
| M1 | Change SQL applies cleanly on top of the current committed baseline (covers both "fresh install after #803 ships" and "upgrade an existing install," which are the same artifact pre-deploy -- see Section 1.1) | Throwaway DB loaded with today's `database/schema.sql` (as committed on main right now, through migration 088, unmodified) | Apply `089_d100_weights.sql`'s change SQL | `weight` column added: `numeric`, `NOT NULL`, default `1`, `CHECK (weight >= 0)`; every pre-existing row reads `weight = 1`; no other column/data touched (diff `task_name`, `enabled`, etc. row-for-row before/after); no error |
| M2 | Idempotent re-run (fresh) | DB already has `weight` (post-M1) | Apply the same change SQL again | Second run succeeds, no error, no duplicate column, no change to existing `weight` values |
| M3 | Idempotent re-run preserves customized weights | Post-M1, then manually `UPDATE motivation_d100 SET weight = 3 WHERE roll = 71;` | Apply the change SQL again | Roll 71 still reads `weight = 3` -- `ADD COLUMN IF NOT EXISTS` must not re-stamp the column default over existing data |
| M4 | CHECK rejects negative weight | Any seeded row | `UPDATE motivation_d100 SET weight = -1 WHERE roll = X;` | Raises check-constraint-violated error |
| M5 | NOT NULL enforced | Any seeded row | `UPDATE motivation_d100 SET weight = NULL WHERE roll = X;` | Raises not-null violation |
| M6 | `numeric` accepts 0 and fractional values | Any seeded row | `UPDATE ... SET weight = 0`, then `weight = 0.5`, then `weight = 2.5` | All three succeed (no CHECK/type error); column type confirmed `numeric`, not `integer` |
| M7 | GRANT parity for the new column (live-DB side) | Post-migration throwaway DB loaded via full `schema.sql`/role-aware harness | Connect as `nova`, run `UPDATE motivation_d100 SET weight = 2 WHERE roll = X;` | Succeeds -- `weight` is a content column (like `task_name`, `enabled`) and must be directly nova-editable, not a SECURITY-DEFINER-only tracking column; expect a new migration line analogous to migration 084's `GRANT UPDATE (reserved, populated_at) ON TABLE motivation_d100 TO nova;`. Per ruling 13 (Q8), `EXECUTE` on `roll_d100()` does **not** need a manual re-grant this time -- plain `CREATE OR REPLACE` preserves it automatically; only the new `GRANT UPDATE (weight, ...)` content-column line is new. **Note:** this grant line must ALSO be hand-added to `database/schema.sql` directly (not produced by `pgschema dump` -- see Section 1.1); cross-check against Area I/D3 |
| M8 | `roll_d100()` signature is unchanged post-migration, and it was replaced via plain `CREATE OR REPLACE` (ruling 13 / Q8) | Post-migration DB | `SELECT pg_get_function_result('roll_d100'::regproc), pg_get_function_arguments('roll_d100'::regproc);`, and confirm `EXECUTE` grant to `nova` survived without any explicit re-`GRANT` statement in the migration | Exactly the 15 columns in the exact order/types the live function returns today; `nova` can still `SELECT * FROM roll_d100();` with zero added `GRANT EXECUTE` line in the migration |
| M9 | Extraction helper works against the new migration | n/a (infra test for the test suite itself) | Extend `_extract_roll_d100_block()` (or add a sibling `_extract_weight_column_block()`) to pull the `ALTER TABLE ... weight ...` and rewritten `roll_d100()` blocks out of `089_d100_weights.sql` the same way the existing helper does for migration 084; update the extraction's end-marker regex since there's no longer a `-- Restore nova EXECUTE grant after drop/create.` comment to anchor on (ruling 13) | Extraction succeeds and the extracted SQL executes standalone in a throwaway DB without needing the rest of the migration file |

---

## B. Statistical / weighted-distribution tests (7 cases) -- S7 is REQUIRED per Q5

| # | Goal | Setup | Action | Expected (oracle from Section 2) |
|---|------|-------|--------|---------------------------|
| S1 | All-weight-1 uniform baseline, **empty slots** | 4 unreserved, empty, enabled, weight-1 eligible slots; no others eligible | 10k-roll loop | Each slot's count within tolerance of N/4 |
| S2 | All-weight-1 uniform baseline, **populated slots**, anti-repeat neutralized | 5 populated+enabled weight-1 slots; `last_rolled` reset to NULL before the loop | 10k-roll loop | Each slot's count within tolerance of N/5 -- this is the literal acceptance-criteria wording: "matches the current uniform behaviour...anti-repeat disabled in the test" |
| S3 | Weight-3 slot drawn ~3x as often, **empty slots** | 3 eligible empty slots: weights 1, 1, 3 | 10k-roll loop | Weight-3 slot's share ~= 3/5 of draws; weight-1 slots ~= 1/5 each; all within tolerance |
| S4 | Weight-3 slot drawn ~3x as often, **populated slots**, anti-repeat neutralized | 3 eligible populated+enabled slots: weights 1, 1, 3; `last_rolled` reset before loop | 10k-roll loop | Same ratio check as S3 |
| S5 | Weight-0 is never drawn | 1 slot weight 0, N other eligible slots weight >0 (mix of empty+populated) | 10k-roll loop | Weight-0 slot's observed count = 0, exactly, every run |
| S6 | Unified pool: empty and populated slots compete in **one** weighted lottery | 1 empty unreserved enabled slot (weight 1), 1 populated enabled slot (weight 1, `last_rolled` reset), nothing else eligible | 10k-roll loop | Roughly 50/50 split between the two -- proves the draw is a single weighted sample over the full eligible set, not two separate pools gated by some outer coin flip |
| S7 | **Fractional weights are proportional (REQUIRED, per Q5 -- not nice-to-have)** | 2 eligible slots: weights 0.5 and 1.5 | 10k-roll loop | Ratio ~= 1:3, within tolerance -- `numeric` is legal input and must behave correctly with non-integer values, since the acceptance criteria don't restrict `weight` to integers and the column type is deliberately `numeric` |

---

## C. Anti-repeat regression tests (8 cases) -- A7 finalized per Q2

All of these hold `weight` at a neutral value (1, unless stated) so the
anti-repeat machinery is isolated from the weighting feature -- this is
the complementary test to Section B, which isolates weighting from
anti-repeat.

| # | Goal | Setup | Action | Expected |
|---|------|-------|--------|----------|
| A1 | Recently-rolled slot excluded, cap not triggered | 10 populated+enabled slots, 1 rolled 1 day ago, rest NULL; recent_pop=1, total_pop=10 -> admit count = max(1-5,0)=0 | 2000-roll loop | The 1-day-old slot's observed count = 0; the other 9 share draws roughly evenly |
| A2 | 7-day boundary (just past window) | 1 slot `last_rolled = now() - interval '7 days' - interval '1 second'`, rest NULL | Single roll, repeated 100x | The boundary slot IS eligible (its `last_rolled < v_now - interval '7 days'` is true) |
| A2b | 7-day boundary (just inside window) | 1 slot `last_rolled = now() - interval '7 days' + interval '1 second'` | Single roll, repeated 100x (low recent_pop so no cap admission) | The boundary slot is NOT eligible -- matches today's `>=` cutoff treating "recent" inclusively |
| A3 | 50% cap forces oldest-first re-admission | 10 populated+enabled slots: 8 with `last_rolled` inside the 7-day window at staggered ages (1h..8h ago), 2 with `last_rolled = NULL`. recent_pop=8, total_pop=10 -> admit = max(8-5,0)=3 -> the 3 **oldest** of the 8 (6h/7h/8h-ago) must be admitted, tie-break by roll ASC | 5000-roll loop | Eligible set = {2 never-rolled} union {3 oldest-recent}; the other 5 recent slots have observed count = 0; admitted set matches exact precomputed IDs (recency + roll tiebreak), independent of each slot's weight |
| A4 | Admission ordering is weight-blind | Same as A3, but give the 3 would-be-admitted slots weight 0.1 each and the 5 excluded slots weight 100 each | 5000-roll loop | The excluded-by-recency weight-100 slots still draw 0 -- a high weight must never override the recency-based admission decision; this directly tests the ruling's "keep...the 50% re-admit cap...EXACTLY as they are" |
| A5 | `last_rolled IS NULL` always eligible | Mix of old/null `last_rolled` across slots, any weights | Repeated rolls | Never-rolled slots are always in the eligible pool regardless of global recent_pop/total_pop state |
| A6 | Weight=0 recently-admitted-by-recency slot still never drawn | Build the A3 setup, but set `weight = 0` on one of the 3 slots the recency math would otherwise admit | 5000-roll loop | That slot's observed count = 0 despite being "recency-admitted" -- weight-0 muting wins at the final selection layer in every case |
| A7 | **Weight-0 rows are excluded from the 50% cap's total_pop/recent_pop denominators, treated like disabled (Q2, resolved: interpretation A)** | 10 populated+enabled slots, 2 of them `weight = 0`; stagger `last_rolled` so the admission math over the remaining 8 produces a precomputable admit-count | 5000-roll loop | Cap math is computed over the 8 non-zero-weight rows only (`total_pop = 8`, not 10); the 2 weight-0 rows never appear in `pop`/`counts`/`admit` at all, exactly as if they were `enabled = false`; admission count and admitted-roll set match the precomputed expectation for `total_pop = 8` |

---

## D. Populate-me path tests (4 cases)

| # | Goal | Setup | Action | Expected |
|---|------|-------|--------|----------|
| P1 | Unreserved empty enabled slot -> populate-me | 1 eligible empty slot, weight 2, nothing else eligible | Roll | `is_populate_me = true`; `roll` matches the slot; `task_name`/`task_description`/etc. all NULL; `times_rolled` incremented, `last_rolled` set |
| P2 | Reserved empty slot is NEVER returned, at any weight | Universe where the only non-zero-weight row is `reserved = true`, `task_name IS NULL`, weight 5 | Roll | Function raises the all-ineligible error (Area E) -- a reserved slot must never surface as populate-me or otherwise, regardless of how high its weight is |
| P3 | Disabled empty slot is excluded (parity with current path A) -- **confirmed required by Q1: empty-slot eligibility = `enabled=true AND unreserved AND weight>0`** | Universe where the only non-zero-weight row is `enabled = false`, `reserved = false`, `task_name IS NULL`, weight 5 | Roll | Raises all-ineligible -- preserves today's `m.enabled = true` requirement on path A |
| P4 | Weight-0 empty slot is excluded even as the last remaining candidate | Universe where the only unreserved+empty+enabled row has `weight = 0`; no other eligible rows | Roll | Raises all-ineligible, never returns that slot as populate-me |

---

## E. All-ineligible error path (4 cases) -- asserts the exact error text per Q4

| # | Goal | Setup | Action | Expected |
|---|------|-------|--------|----------|
| E1 | All weights are 0 | Every row (populated and empty) has `weight = 0` | Roll | Raises an exception with message **exactly** `roll_d100: no populated+enabled tasks found after 20 attempts` (the existing, unchanged error text, per Q4 -- callers matching on this string keep working); must not return a row, must not silently loop forever |
| E2 | Weight-0 trumps would-be anti-repeat re-admission | Reconstruct an A3-style setup (8/10 recent -> 3 admitted by recency) but set `weight = 0` on literally every populated row, and make all empty rows reserved or disabled or weight-0 | Roll | Raises the same exact error text as E1 -- the 50% cap logic must never "rescue" a weight-0 row into eligibility |
| E3 | Empty table | Throwaway DB with `motivation_d100` schema loaded but zero rows | Roll | Raises the same exact error text as E1, not a crash/hang |
| E4 | No partial side effects on the ineligible path | Any all-ineligible setup; snapshot `times_rolled`/`last_rolled` for every row first | Roll (expect exception), then re-check all rows | No row's `times_rolled`/`last_rolled` changed -- the function must fail before any `UPDATE`, i.e., the failure is transactionally clean |

---

## F. Trigger & roll-history tests (5 cases)

| # | Goal | Setup | Action | Expected |
|---|------|-------|--------|----------|
| T1 | Successful roll logs exactly once | 1 eligible populated slot | Roll | `d100_roll_log` gains exactly one new row: `roll` = returned roll, `rolled_at` = the row's `last_rolled` |
| T2 | No duplicate log row on a true no-op update | n/a (defensive case; normally `v_now` is always distinct per call) | Directly `UPDATE motivation_d100 SET last_rolled = last_rolled WHERE roll = X;` (same value) | `_trg_log_d100_roll`'s `IS DISTINCT FROM` guard means no new `d100_roll_log` row is inserted |
| T3 | Populate-me path also logs | 1 eligible empty slot | Roll | `d100_roll_log` row inserted same as T1, with the empty slot's `roll` value |
| T4 | Weight-only update does not create a log row | Any row | `UPDATE motivation_d100 SET weight = 5 WHERE roll = X;` (not touching `last_rolled`) | No new `d100_roll_log` row -- confirms the trigger (unmodified, per the ruling) only cares about `last_rolled`, and the new column doesn't accidentally interact with it |
| T5 | `_trg_set_populated_at` still works post-migration | Empty, unreserved, enabled, weight>0 slot | Roll (gets populate-me), then `UPDATE motivation_d100 SET task_name = 'x', task_description = 'y' WHERE roll = <that roll>;` (optionally setting `weight` in the same statement) | `populated_at` auto-stamps to NOW() exactly as before; unaffected by whether `weight` is touched in the same `UPDATE` |

---

## G. Caller compatibility: announce script & return signature (5 cases)

| # | Goal | Setup | Action | Expected |
|---|------|-------|--------|----------|
| G1 | `announce-d100-rolls.py`'s read queries still work | Post-migration throwaway DB, env vars pointed at it (`PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER` via the same `pg_env` loader the script uses) | Run `python3 memory/scripts/announce-d100-rolls.py --dry-run` | Exit code 0; its internal `SELECT roll, task_name, estimated_minutes, difficulty, last_rolled, last_completed, reserved FROM motivation_d100 WHERE roll = ANY(%s)` query -- which never references `weight` -- runs unchanged; no "column does not exist" or type errors |
| G2 | End-to-end: roll -> trigger -> announce | Post-migration DB, 1 populated eligible slot | Call `roll_d100()`, then run the announce script's dry-run | The roll lands in `d100_roll_log`; dry-run's `_select_unannounced` reads it and prints a `[DRY-RUN] would send:` line without needing the `openclaw` CLI present (dry-run short-circuits `_send_message` before checking for the binary) |
| G3 | `_format_roll()` doesn't choke on the new column | n/a -- pure Python unit test, no DB | Call `announce-d100-rolls.py`'s `_format_roll()` directly with a plain dict matching its current expected keys (`roll`, `task_name`, `estimated_minutes`, `difficulty`, `last_rolled`, `last_completed`, `reserved`) -- i.e., **no** `weight` key | No KeyError; output matches today's format exactly -- confirms the script genuinely needs zero code changes (it only ever does a column-list SELECT, never SELECT *) |
| G4 | Return signature is byte-for-byte unchanged | Post-migration DB | `SELECT proname, pg_get_function_result(oid) FROM pg_proc WHERE proname = 'roll_d100';` | Matches today's live result exactly: TABLE(roll integer, task_name character varying, task_description text, workflow_id integer, skill_name character varying, tool_name character varying, difficulty character varying, energy_required character varying, estimated_minutes integer, times_rolled integer, times_completed integer, last_rolled timestamp without time zone, last_completed timestamp without time zone, notes text, is_populate_me boolean) -- 15 columns, same names/types/order, `weight` is **not** in the output |
| G5 | `idle-d100.sh` -- confirmed out of scope | n/a | Check the nova-workspace repo (not nova-mind) for the file | Per ruling #3 it has been deleted outright; no test needed here, documented only so it isn't silently assumed still relevant |

---

## H. Weight update takes effect immediately (2 cases)

| # | Goal | Setup | Action | Expected |
|---|------|-------|--------|----------|
| W1 | Live weight bump shifts distribution with no restart/reload | 3 eligible empty slots, all weight 1 | Roll 2000x, record baseline distribution (~1/3 each); then `UPDATE motivation_d100 SET weight = 5 WHERE roll = <one of them>;` in the same open connection/session; roll 2000x more | Second batch's distribution shifts to roughly 5:1:1 immediately -- no caching layer, prepared-statement plan pinning, or materialized state prevents the new weight from taking effect on the very next call |
| W2 | Live weight-to-0 immediately mutes a slot | 1 populated eligible slot among several, weight 1, included in current draws | Roll a few times to confirm it's reachable; then `UPDATE motivation_d100 SET weight = 0 WHERE roll = X;`; roll 2000x more | Zero draws of that slot in the second batch -- the mute takes effect on the very next `roll_d100()` call, no delay |

---

## I. Post-deploy schema-dump & manifest verification (4 cases)

**D1-D3 run post-deploy, as a deployment-step check -- not in CI, and not
against any throwaway database.** They run **after** the live apply has
actually happened against production and
`cognition/scripts/pg-notify-listener.py`'s `sync_schema_to_github()` has
dumped and committed the result to `database/schema.sql` on `nova-mind`
main. Nobody hand-edits `schema.sql`; these cases confirm the automated
dump did its job. **D4 is a static manifest test (extends
`database/tests/test_check_schema_manifest.py`)** and can run any time
after the implementation PR lands the manifest entries, including in CI.

| # | Goal | Pre-conditions | Action | Expected |
|---|------|-----------------|--------|----------|
| D1 | `schema.sql` reflects the live change | `nova-mind` main has been updated by the listener's automated dump after the live apply | Pull `nova-mind` main; inspect `database/schema.sql`'s `motivation_d100` `CREATE TABLE` block and `roll_d100()` `CREATE OR REPLACE FUNCTION` block | `motivation_d100` now includes `weight numeric NOT NULL DEFAULT 1` with the `CHECK (weight >= 0)` constraint; `roll_d100()`'s function body text differs from the pre-#803 body (weighted-draw logic present, and -- per ruling 13 -- there is no preceding `DROP FUNCTION IF EXISTS roll_d100();` statement this time) while its `RETURNS TABLE(...)` clause is still the unchanged 15-column signature (cross-check against G4) |
| D2 | `.schema-manifest.toml` still holds for its pre-existing entries | Same post-dump `schema.sql` | Run `python3 database/check_schema_manifest.py` (default `--manifest database/.schema-manifest.toml --schema database/schema.sql`) | Exit code `0`, output `OK: all N schema manifest check(s) passed against database/schema.sql.` -- the dump must not have silently dropped `append_run_note` or any `[function_security]` property; this also implicitly confirms the listener's veto never had to fire |
| D3 | Hand-maintained GRANT line survived the automated dump | Same post-dump `schema.sql` | Grep `database/schema.sql` for a `GRANT UPDATE (..., weight, ...)` (or equivalent) line scoping `motivation_d100` to `nova` | Present -- per Section 1.1, `pgschema dump` never emits column-level grants, so this line only exists if a human hand-added it to `schema.sql` in the same PR as the migration; if it's missing here, a fresh install from `schema.sql` alone silently loses nova's ability to edit `weight` directly, even though the live DB (which actually ran the migration's own `GRANT`) still has it |
| D4 | **`.schema-manifest.toml` now protects `roll_d100()` and `motivation_d100.weight` too (Q7, new)** | The #803 implementation PR has added entries along the lines of: `[functions] patterns = [..., "roll_d100()"]`, `[function_security] "roll_d100" = ["SECURITY DEFINER", "SET search_path = public"]`, and a new `[columns]` (or equivalent) section with a pattern matching the `weight` column DDL (e.g. `"weight numeric NOT NULL DEFAULT 1"`) | (a) Run `check_schema_manifest.py` against the real post-dump `schema.sql` -- expect exit `0`, now covering 2 manifest-checked functions instead of 1; (b) **mutation test** (static, synthetic fixture, following `test_check_schema_manifest.py`'s existing `MANIFEST_*`/`SCHEMA_*` string-fixture convention): build a synthetic schema string with the `roll_d100` function header present but its `SECURITY DEFINER` line stripped, and separately one with the `weight` column line stripped entirely, and confirm `check_schema_manifest.py`'s checker functions report them as missing/failing in each case | (a) exits `0` on the real, correct post-dump `schema.sql`; (b) each mutated synthetic fixture is correctly flagged as a failure by the checker -- proving the new manifest entries have real teeth (would actually catch a #624-style silent clobber of `roll_d100()` or the `weight` column), not just that they coincidentally pass against today's correct file |

---

## Retired cases (2026-11-14 I)ruid ruling)

| Case | Status | Reason |
|---|---|---|
| M7 | Retired | The `nova` role owns the `nova_memory` database and `motivation_d100` table, so it already has write access to the `weight` column through ownership; no explicit column `GRANT` is needed, and `nova-mind` must not grant to a role by name. |
| D3 | Retired | The hand-maintained `GRANT UPDATE (weight)` line is no longer required because ownership-based access makes it redundant. |

## Case count summary (final, approved)

| Area | Cases |
|---|---|
| A. Migration & schema (change-SQL-only, no hand-edited schema.sql) | 8 (M1-M6, M8-M9) |
| B. Statistical / weighted distribution (S7 required, per Q5) | 7 (S1-S7) |
| C. Anti-repeat regressions (A7 finalized per Q2) | 8 (A1, A2, A2b, A3-A7) |
| D. Populate-me path | 4 (P1-P4) |
| E. All-ineligible error path (exact error text, per Q4) | 4 (E1-E4) |
| F. Trigger & roll history | 5 (T1-T5) |
| G. Caller compatibility (announce script + signature) | 5 (G1-G5) |
| H. Weight update takes effect immediately | 2 (W1-W2) |
| I. Post-deploy schema-dump & manifest verification (D1-D2 post-deploy; D4 static/CI, per Q7) | 3 (D1-D2, D4) |
| **Total** | **46** |

---

## Resolution log (all items closed)

Every open question raised during Step-3 drafting (Q1-Q5) and while
finalizing (Q6-Q8) was resolved by orchestrator ruling across two Step-4
review messages (2026-11-14). None remain open:

- **Q1** (empty-slot `enabled` requirement) -- resolved: required. See
  ruling 2, P3.
- **Q2** (weight-0 vs. the 50% cap's denominators) -- resolved: excluded,
  treated like disabled. See ruling 1, A7.
- **Q3** (sampling technique) -- agreed: behavior-only tests, no change.
  See ruling 11.
- **Q4** (exact error text) -- resolved: assert exactly. See ruling 10,
  E1-E4.
- **Q5** (fractional weights required vs. nice-to-have) -- resolved:
  required. See ruling 8, S7.
- **Q6** (migration filename) -- resolved: `memory/migrations/089_d100_weights.sql`.
  See ruling 8.
- **Q7** (schema-manifest coverage for `roll_d100()`/`weight`) -- resolved:
  add it in the implementation PR, test it. See ruling 14, Area I/D4.
- **Q8** (`DROP FUNCTION`+re-`GRANT` vs. plain `CREATE OR REPLACE`) --
  resolved: plain `CREATE OR REPLACE`. See ruling 13, M7, M8, M9, D1.

---

## Key design decisions and reasoning (recap)

- **Schema-delivery correction:** no test assumes a hand-edited
  `database/schema.sql`. The schema file is a derived artifact produced by
  `pgschema dump` + `pg-notify-listener.py`'s automated commit after the
  live apply; structural-DDL tests (Area A) apply the migration's change
  SQL directly to a throwaway DB seeded from today's already-committed
  `schema.sql`, and Area I verifies the *result* of that automated dump
  (plus the one thing the dump genuinely cannot capture -- hand-maintained
  `GRANT`/`REVOKE` lines) after the fact, as a post-deploy step, not a CI
  gate -- except D4, which is a pure static manifest test and can run in
  CI once the manifest entries exist.
- **Extend, don't fork, the test suites:** Area A-H lands in
  `motivation/tests/test_roll_d100_migration.py` (reusing its existing
  `_extract_roll_d100_block()`-style extraction pattern, updated for the
  plain-`CREATE OR REPLACE` shape per Q8); Area I/D4 lands in
  `database/tests/test_check_schema_manifest.py` (reusing its existing
  synthetic-fixture convention), because that's a pure text/manifest
  concern with zero DB involvement -- the right home for it, not a new
  file and not the motivation suite.
- **Plain `CREATE OR REPLACE`, per Q8:** since the return signature is
  pinned unchanged, migration 084's `DROP FUNCTION` + manual `GRANT
  EXECUTE` restoration dance isn't needed this time -- simpler, and grants
  survive automatically. M7-M9 and D1 are written against this expectation.
- **Manifest hardening, per Q7:** adding `roll_d100()` and the `weight`
  column to `.schema-manifest.toml` in the same PR closes the exact
  failure class #624 already proved can happen (a mechanical re-dump
  silently clobbering a hand-authored object with nobody noticing). D4's
  mutation-test half is what gives this teeth -- a manifest entry that
  passes trivially against today's correct file but was never verified to
  actually *fail* against a broken one isn't proven to protect anything.
- **Weight-0 is cap-math-transparent, per Q2:** weight-0 rows are excluded
  from the cap's denominators entirely, treated exactly like
  `enabled = false` for that purpose. A7 is written against this single,
  now-confirmed interpretation.
- **Exact error-text assertion, per Q4:** E1-E4 assert the literal string
  `roll_d100: no populated+enabled tasks found after 20 attempts` rather
  than a generic "raises an exception" check, since the ruling requires
  byte-for-byte caller compatibility on that message.
- **Fractional weights are a first-class requirement, per Q5:** S7 is
  required coverage, since `numeric` is explicitly legal input and must
  work correctly, not merely fail to error.
- **Isolate weighting from anti-repeat, and vice versa, in separate test
  families** (Section B neutralizes anti-repeat via `last_rolled = NULL`
  resets or by using empty slots where it structurally doesn't apply;
  Section C holds weights neutral/pathological-but-controlled).
- **Use empty slots as the cleanest substrate for pure weight-ratio
  tests** (S1, S3, S5 partially, S6) since path A never consults
  `last_rolled`/anti-repeat at all -- no reset gymnastics needed there.
- **In-database DO loops instead of N round-trips** for the N>=10k
  statistical tests -- this is purely a performance/CI-time decision, not
  a behavioral one; it still exercises the real `roll_d100()` function
  each iteration.
- **Binomial tolerance band (4-sigma + relative floor) instead of a fixed
  +/-X% number** -- gives a principled, N-aware pass/fail line so the
  suite isn't flaky at the boundaries chosen for small vs. large expected
  counts.
- **Admission-ordering tests (A3/A4) deliberately decouple weight from
  recency** by assigning extreme, inverted weights to the
  admitted/excluded sets -- this is the sharpest way to catch an
  implementation bug where someone accidentally lets weight leak into the
  50% cap's admission decision, which the ruling explicitly forbids
  ("keep...the 50% re-admit cap...EXACTLY as they are").
- **Never assume a specific SQL technique for the weighted draw** -- every
  oracle is behavioral (counts, exclusions, signature, side effects), so
  the test suite constrains the *contract*, not the implementation,
  leaving the implementer free to choose Efraimidis-Spirakis, a
  cumulative-sum pick, or anything else that satisfies it.
