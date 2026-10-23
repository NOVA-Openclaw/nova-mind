# Test Cases: nova-mind#792 — remove Victoria tables from shipped .pgschemaignore; document additive contract

**SE run:** #1385, Step 3 (Quality Assurance)
**Worktree:** `~/nova-mind-wt-792` (branch `fix/792-shipped-pgschemaignore`, base `cc33935e6b41dd4b0d74aab993777f72ac8f1dea`)
**Issue:** https://github.com/NOVA-Openclaw/nova-mind/issues/792
**Scope ruling (Step 2):** Option A (additive-only, never drop/destructively-alter). Remove Victoria trading-table names from `database/.pgschemaignore` and `database/.pgschemaignore-peer`; keep `*_local`. Keep `nova_bootstrap_context`, `bootstrap_context_view_*`, `protect_bootstrap_context_writes_v2` in the peer file (nova-mind's own federation design, not a customer table). Requirement 3 (host-local ignore file) is deferred unless testing proves plan noise is a real problem — not built here.

This document designs test cases only. It does not assert pass/fail for code that does not yet exist on this branch (the Victoria entries are still present as of the pinned commit). Tests marked **(new)** must be authored during implementation (Step 5/6); tests marked **(existing)** already exist in `tests/` and are listed here to show what #792 must not regress.

---

## 1. Acceptance-criteria coverage map

| # | Acceptance criterion (issue #792) | Test IDs |
|---|---|---|
| AC1 | `git grep -nE 'trades\|cash_ledger\|portfolios\|positions\|instruments' database/.pgschemaignore*` returns nothing | TC-792-001, TC-792-002 |
| AC2 | Fresh install on empty DB: all schema.sql objects created, exit 0, zero destructive ops | TC-792-010, TC-792-011 |
| AC3 | Drift-seeded peer install (Victoria-shaped): exit 0, additive objects land, row counts unchanged, no 42809 | TC-792-020, TC-792-021, TC-792-022, TC-792-023 |
| AC4 | Existing managed table missing a column gets the column added (ruling A) | TC-792-030, TC-792-031 |
| AC5 | Docs describe the additive contract; reconciled with #693 | TC-792-040, TC-792-041 |

Additional requested coverage (Step 2 edge cases + task brief) not tied to a single AC bullet but required for the PR to merge:

| Area | Test IDs |
|---|---|
| Adversarial: malformed TOML ignore file | TC-792-050, TC-792-051 |
| Adversarial: ignore pattern matching nothing | TC-792-052 |
| Adversarial: local table name collides with a schema.sql table (ordinary table, not view/FDW) | TC-792-053 |
| Adversarial: plan step with unexpected `operation` value | TC-792-054, TC-792-055 |
| Adversarial: plan step with unexpected `type` value | TC-792-056 |
| Config-to-runtime seam (real installer schema stage against a real Postgres DB) | TC-792-020, TC-792-021, TC-792-060, TC-792-070 |
| Non-drop lossy alters (ALTER COLUMN TYPE narrowing, SET NOT NULL) — known-gap investigation | TC-792-060, TC-792-061, TC-792-062 |
| #686 phantom CHECK drop+recreate after strip | TC-792-070, TC-792-071 |
| Dependent objects (indexes, sequences, triggers, FKs) of newly un-ignored tables | TC-792-080, TC-792-081 |
| Regression: existing peer/FDW and additive-apply suites must still pass unmodified | TC-792-090 |

---

## 2. Static ignore-file tests (AC1)

### TC-792-001 — Victoria table names absent from both ignore files (new, bats)
**Type:** shell assertion, no DB needed.
**Steps:**
1. Run `git grep -nE 'trades|cash_ledger|portfolios|positions|instruments' database/.pgschemaignore database/.pgschemaignore-peer`.
**Expected:** exit code 1 (no matches). This is the issue's own AC1 command verbatim — reuse it directly as the test body rather than re-deriving the regex, so the test cannot silently drift from the acceptance criterion.
**Also assert** the fuller name list from the issue problem statement is gone: `portfolio_snapshots`, `portfolio_asset_classes`, `strategies`, `strategy_notes`, `asset_classes`, `open_orders`, `order_adjustments`, `price_cache_v2`, `cash_ledger`. (AC1's regex is a subset; the full Victoria list in `.pgschemaignore` today has more entries, and a partial fix that only satisfies the literal grep would still leak some names.)

### TC-792-002 — Generic patterns preserved (new, bats)
**Steps:** `grep -F '"*_local"' database/.pgschemaignore database/.pgschemaignore-peer`.
**Expected:** present in both files (the generic agent-local convention must survive the Victoria-specific cleanup).

### TC-792-003 — Peer-only federation objects preserved in `.pgschemaignore-peer` (new, bats)
**Steps:** grep for `nova_bootstrap_context`, `bootstrap_context_view_*`, `protect_bootstrap_context_writes_v2` in `.pgschemaignore-peer` only.
**Expected:** all three present in `.pgschemaignore-peer`; absent from the base `.pgschemaignore` (they are peer-only by Step 2's decision — base file should not reference them since standalone installs never see them).
**Decision note:** this test encodes the Step-2 scope ruling that the peer file's federation-only entries are *not* in scope for removal, so a future contributor doesn't "fix" them by accident while chasing AC1.

### TC-792-004 — Both ignore files still parse as valid TOML after edit (new, bats)
**Steps:** Use `python3 -c "import tomllib; tomllib.load(open(p,'rb'))"` (py3.11+) or the repo's existing TOML parsing path, against both files post-edit.
**Expected:** no exception. Catches a hand-edit that leaves a dangling comma, unclosed bracket, or orphaned section header after deleting the Victoria array entries.

### TC-792-005 — `.pgschemaignore-peer` stays in sync with the base file's non-Victoria, non-federation entries (new, bats)
**Rationale:** the peer file's header comment says "Keep this file in sync with database/.pgschemaignore". Diff the `[tables]` arrays of both files after removal, excluding the peer-only federation names, and assert they're identical (currently both start from the same Victoria+`*_local` list; after this fix both should reduce to just `*_local` on the `[tables]` side, modulo the peer file's extra federation entries).

---

## 3. Fresh-install happy path (AC2)

### TC-792-010 — Fresh empty DB: full pipeline exit 0, zero destructive ops (new, bats, live PG)
**Setup:** `createdb` a throwaway scratch DB, PID-suffixed (e.g. `nova_mind_792_fresh_<pid>`), matching `tests/install/*.bats` conventions. No pre-existing tables.
**Steps:** Run the installer's real plan → reorder → strip-destructive → apply chain (not hand-built JSON) using `database/schema.sql` as source, exactly as `_run_schema_management` does (reuse the `_run_installer_filter_pipeline`-style helper from `tests/install/test_608_peer_fdw_bootstrap_context.bats` as a base, extended to also run `pgschema apply`).
**Expected:**
- `pgschema plan` exit 0, `pgschema apply` exit 0.
- `strip_destructive.py`'s reported stripped count is 0 — a fresh DB has nothing to drop, so if the count is nonzero something is wrong (e.g. the ignore file still has stale Victoria patterns tripping a spurious diff, or the schema has a self-referential ordering bug).
- Table count via `information_schema.tables` matches schema.sql's `CREATE TABLE` count (103 as of the pinned commit — assert the number is reasonable/matches a live `grep -c 'CREATE TABLE' database/schema.sql`, not a hardcoded literal, so the test doesn't bit-rot).
- No Victoria-named relations exist afterward (schema.sql never declares them) — confirms removing the ignore entries didn't somehow cause them to be materialized.

### TC-792-011 — Fresh install is idempotent on second run (new, bats, live PG)
**Steps:** Run TC-792-010's pipeline twice against the same DB.
**Expected:** second `pgschema plan` reports zero steps (schema already matches); second apply is a no-op; exit 0 both times. Guards against the ignore-file edit accidentally making some object perpetually "diff and reapply."

---

## 4. Drift-seeded peer (Victoria-shaped) install — config-to-runtime seam + INTENT check (AC3)

These are the most important tests in this set: they run the **real** installer schema stage against a **real** Postgres DB, not hand-built plan JSON, per the task brief's explicit requirement. They extend the existing `tests/install/test_608_peer_fdw_bootstrap_context.bats` fixture helpers (`_seed_peer_fixture`, `_run_installer_filter_pipeline`) rather than reinventing them, and add the apply step plus row-count/object-inventory assertions that the existing #608 suite does not do (it only inspects the filtered *plan*, it never applies and never seeds trading-shaped tables with rows).

### TC-792-020 — Victoria-shaped peer DB: full apply succeeds, zero row loss, no 42809 (new, bats, live PG)
**Setup ("Victoria-shaped" fixture):**
1. Seed the federated bootstrap-context stack via the existing `_seed_peer_fixture` helper with both function and trigger flags on (VIEW + FOREIGN TABLE + `bootstrap_context_view_*` functions/triggers — same shape #608 already uses).
2. Additionally seed a representative subset of Victoria's agent-local trading tables **with non-zero, non-trivial row counts** (not just schema shape — this is the task brief's explicit requirement): e.g.
   ```sql
   CREATE TABLE portfolios (id serial PRIMARY KEY, name text NOT NULL, created_at timestamptz DEFAULT now());
   CREATE TABLE instruments (id serial PRIMARY KEY, symbol text UNIQUE NOT NULL);
   CREATE TABLE positions (id serial PRIMARY KEY, portfolio_id int REFERENCES portfolios(id), instrument_id int REFERENCES instruments(id), quantity numeric NOT NULL);
   CREATE TABLE trades (id serial PRIMARY KEY, position_id int REFERENCES positions(id), side text NOT NULL, qty numeric NOT NULL, price numeric NOT NULL, traded_at timestamptz DEFAULT now());
   CREATE TABLE cash_ledger (id serial PRIMARY KEY, portfolio_id int REFERENCES portfolios(id), amount numeric NOT NULL, entry_type text NOT NULL, posted_at timestamptz DEFAULT now());
   CREATE INDEX idx_positions_portfolio ON positions(portfolio_id);
   CREATE INDEX idx_trades_position ON trades(position_id);
   ```
   Insert at least 25 rows per table (e.g. 3 portfolios, 5 instruments, 10 positions, 30 trades, 15 cash_ledger entries) with realistic FK linkage — "non-trivial" means enough rows that a naive `TRUNCATE`/`DROP CASCADE` would be obviously destructive, not a single throwaway row.
3. Capture **before** snapshot: `SELECT count(*) FROM <table>` for every seeded Victoria table, plus `SELECT relname, relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' ORDER BY relname` (full object inventory: tables, views, foreign tables, indexes, sequences).
**Steps:** Run the real pipeline end-to-end against this DB: `detect_peer_shadowed.py` → peer-mode ignore selection → `inject_peer_shadowed_ignores.py` → `pgschema plan` → `plan_reorder.py` → `strip_destructive.py --ignore-objects <detected> --log-exclusions` → `pgschema apply --auto-approve`.
**Expected:**
- `pgschema apply` exit code 0 (no SQLSTATE 42809 "cannot alter type of a column used by a view or rule" / wrong-object-type error, which is the exact failure mode #608 was filed for).
- **After** snapshot: every Victoria table's row count is byte-identical to the **before** snapshot (this is the "row counts unchanged" AC3 bullet, verified with real counts, not inferred from plan contents).
- Object inventory diff: the only *new* relations are ones schema.sql declares (additive tables/indexes/etc. if schema.sql added any since the fixture was seeded) — the existing Victoria tables/indexes/sequences/FKs are present, unmodified, in both before/after inventories. No Victoria relation is missing from the "after" inventory (would indicate a drop slipped through) and none have a different column signature unless it's a column *addition* permitted by ruling A.
- `agent_bootstrap_context` (VIEW) and `nova_bootstrap_context` (FOREIGN TABLE) are untouched — reuse `_assert_no_bootstrap_refs` from #608.
**Why this matters for #792 specifically (not just a #608 repeat):** before this fix, the static `.pgschemaignore` made pgschema skip Victoria tables at *plan* time entirely — strip_destructive never even saw them. After removing the Victoria entries, pgschema *will* plan DROPs for them (they're not in schema.sql), and the only thing protecting them is the universal `operation == "drop"` strip. This test is the one that actually exercises that path for Victoria-shaped tables; the #608 suite only exercises it for the bootstrap-context VIEW/FDW stack.

### TC-792-021 — Same as TC-792-020 run in standalone (non-peer) mode (new, bats, live PG)
**Setup:** Same Victoria-shaped trading tables, but *without* the federated bootstrap-context VIEW/FDW stack (so `detect_peer_shadowed.py` finds nothing and the installer picks the base `.pgschemaignore`, not `-peer`).
**Expected:** same row-count/inventory invariants as TC-792-020. This isolates "does the base ignore file change break a plain agent-local install" from "does peer detection interact correctly," since most non-Victoria consumers never hit the peer path at all.

### TC-792-022 — INTENT-level object inventory diff is itself asserted, not just row counts (new, bats, live PG)
**Rationale:** row counts alone can't catch a table being dropped and silently recreated empty-then-reseeded by something else, or a dependent object (sequence, index, FK, trigger) vanishing while the table survives. This test is the explicit "take row counts and object inventory before and after and compare them" deliverable from the task brief, as its own standalone assertion rather than folded into TC-792-020's happy path.
**Steps:** Reuse the TC-792-020 fixture. Before/after, capture three separate catalog snapshots:
1. Tables: `information_schema.tables` (name, type).
2. Columns: `information_schema.columns` (table, column, data_type, is_nullable) for every Victoria table — catches a silently narrowed/widened column.
3. Dependent objects: `pg_indexes`, `pg_constraint` (for FKs/PKs/checks), `pg_trigger`, and sequences via `pg_class WHERE relkind='S'`, scoped to the Victoria tables.
**Expected:** all three snapshots are set-equal before/after except for additive deltas explicitly introduced by schema.sql (which in this fixture should be none, since none of the seeded table names appear in schema.sql).

### TC-792-023 — Peer install with zero rows (boundary case) (new, bats, live PG)
**Setup:** Same as TC-792-020 but all Victoria tables created with zero rows.
**Expected:** same invariants hold. Exists to make sure the "non-zero row count" emphasis in TC-792-020 isn't hiding a bug that only manifests when COUNT(*) is nonzero (e.g. an accidental `DELETE` instead of a true structural no-op) — this is the inverse boundary probe.

---

## 5. Ruling A: missing column gets added (AC4)

### TC-792-030 — Existing managed table missing a column: column is added, data survives (new, bats, live PG)
**Setup:** Pick a real schema.sql table (not a throwaway fixture table, to prove this against the actual shipped schema — e.g. `agent_bootstrap_context`, which is also exercised elsewhere in the peer suite so a regression here is doubly visible). Create it manually via a copy of its `CREATE TABLE` from schema.sql with one column removed (e.g. drop `description`), insert a handful of rows into the remaining columns.
**Steps:** Run the real plan→reorder→strip→apply chain with the full, unmodified schema.sql as the desired state.
**Expected:**
- Plan contains an `operation: "alter"`, `type: "table.column"` step adding the missing column (not `"drop"`).
- Strip step does **not** remove it (only drops are stripped).
- Apply succeeds; `information_schema.columns` shows the column present afterward; pre-existing rows' other columns are untouched and the new column is NULL (or its schema.sql default) for existing rows.
**This is the literal text of AC4** — kept as its own dedicated test rather than folded into TC-792-020, because AC4 is independently checkable and should have a traceable pass/fail of its own in the PR.

### TC-792-031 — Missing column with a NOT NULL + DEFAULT in schema.sql (new, bats, live PG)
**Setup:** Same as TC-792-030, but the missing column in schema.sql is declared `NOT NULL DEFAULT <value>`.
**Expected:** apply succeeds (Postgres backfills the default for existing rows in a single-pass `ADD COLUMN ... NOT NULL DEFAULT ...`, which is additive, not destructive); existing rows get the default value. Distinguishes "missing column, trivially additive" from "missing column whose constraint could theoretically fail on existing data" (it can't fail here because DEFAULT backfills it, but the step 2 "never destructively alter" framing makes this worth confirming explicitly rather than assuming).

---

## 6. Documentation (AC5)

### TC-792-040 — Additive contract documented (new, manual/doc-lint)
**Steps:** Locate wherever the installer docs land (likely `cognition/docs/installation.md`, consistent with the existing docs tree found in this worktree, or a new `database/README.md` / section in `database/schema-reference.md`). Confirm it explicitly states:
- What gets applied to an existing install: new tables, new columns/indexes/functions/constraints on existing managed tables (additive only).
- What never gets applied: any DROP, and (per the Step 2 known-gap finding — see section 7) that non-drop lossy alters are a currently-unguarded edge case, if that gap is still open when this ships.
- That agent-local tables (anything not in schema.sql, plus the `*_local` convention) are never touched, and why the Victoria-specific ignore-list entries were removed (redundant given additive-by-construction, not a policy change).
**Expected:** a reviewer can read this section alone and correctly predict the outcome of any of TC-792-010/020/030 without reading code.

### TC-792-041 — Docs reconcile with #693, don't contradict it (new, manual review)
**Steps:** Read #693's content (fetch via `gh issue view 693`) alongside the new docs section.
**Expected:** no direct contradiction; if #693 already documents a related contract, the new text cross-references it rather than duplicating/diverging. *(Flag to the implementer: this needs a human/Step-4 reviewer judgment call, not a scriptable assertion — listed here so it isn't dropped from the PR checklist.)*

---

## 7. Non-drop lossy alters — known-gap investigation (Step 2 edge case)

Ruling A says "never destructively alter." The code only strips steps where `operation == "drop"` (see `strip_destructive.py::strip_destructive`, the `if step.get("operation") == "drop":` branch). Nothing inspects `ALTER COLUMN ... TYPE` (narrowing) or `ALTER COLUMN ... SET NOT NULL` steps, which pgschema plans with `operation: "alter"`, not `"drop"`. These tests exist to **empirically confirm** whether such steps can appear and whether anything downstream (pgschema's own apply, a Postgres-side failure, or some other gate) incidentally stops them — per the Step 2 instruction, if nothing does, this is reported as a known gap with a follow-up recommendation, not folded into #792's scope.

### TC-792-060 — Column type narrowing is planned as `operation: "alter"`, not stripped (new, bats, live PG)
**Setup:** Create a local copy of a simple table with a `text` column holding short values (e.g. `CREATE TABLE t (id serial PRIMARY KEY, code text); INSERT ... VALUES ('AB'), ('CD');`). Desired schema (a throwaway schema.sql-like file, not the real one, to keep this isolated) declares the same column as `varchar(1)` — narrower than the existing data in a way Postgres would normally reject if any row didn't fit, but accept if it does (so the test proves the *mechanism*, independent of whether a given narrowing happens to be safe for the current data).
**Steps:** `pgschema plan` → inspect the raw plan JSON for the step touching `t.code`.
**Expected finding:** the step's `operation` is `"alter"` (confirm by direct inspection — do not assume), and `strip_destructive.py` does not remove it (confirm by running the stripper and checking the step survives).
**If confirmed:** mark as **KNOWN GAP** (see section 7 gap summary below) — do not attempt to fix within #792.

### TC-792-061 — SET NOT NULL on a column with existing NULLs (new, bats, live PG)
**Setup:** Table with a nullable column containing at least one actual `NULL` row. Desired schema declares that column `NOT NULL`.
**Steps:** run plan → reorder → strip → apply.
**Expected finding (two possible outcomes, both worth recording):**
- (a) `pgschema apply` fails at the Postgres level (`SET NOT NULL` on a column with existing NULLs always raises `23502`) — in which case the *apply* fails loudly rather than silently corrupting data, which is a soft mitigation (errors are visible) but still means collateral blocking of the rest of that apply batch, not a clean stop.
- (b) if the column has no NULLs currently but gets one later, or if `pgschema` sequences the `SET NOT NULL` step such that it is evaluated on a value distribution the test didn't anticipate, confirm whether it's the row data or the step filtering that is the actual backstop.
**Record the observed outcome in the implementation notes** — this determines whether the known-gap writeup should say "data-loss risk" (type narrowing, which can silently truncate/round without error if the cast happens to succeed) vs. "this specific case loudly fails but still isn't *filtered*" (NOT NULL against incompatible data).

### TC-792-062 — Column type narrowing that silently succeeds and loses precision (new, bats, live PG)
**Setup:** `numeric(10,4)` column with a value like `123.4567`; desired schema narrows to `numeric(10,2)`.
**Steps:** run the full pipeline.
**Expected finding:** if `pgschema apply` succeeds, confirm the value was silently rounded/truncated (`123.46` or similar) — this is the concrete "silent data loss, nothing stops it" case Step 2 asked about. **This is the strongest evidence for the follow-up issue**, since (unlike TC-792-061) there is no Postgres-side error to rely on as an incidental backstop.

**Section 7 gap summary (to carry into the run log / PR description, per the task brief's "mark as known gap, propose follow-up" instruction):**
> Non-drop lossy alters (`ALTER COLUMN TYPE` narrowing, `SET NOT NULL` against data that happens to already satisfy it) are not filtered by `strip_destructive.py` — only `operation == "drop"` steps are stripped. Ruling A's "never destructively alter" is enforced for drops but not for this class of alter. Recommend a follow-up issue (e.g. "installer: strip or flag non-drop lossy ALTER COLUMN steps, not just drops") rather than expanding #792, since #792's own changes (removing Victoria ignore entries) do not introduce this gap — it predates #792 and applies to any managed table, Victoria-shaped or not.

---

## 8. #686 phantom CHECK drop+recreate after strip (Step 2 edge case)

Background: #686 documents that pgschema fails to canonicalize `CHECK (col IN (...))` vs. the Postgres-stored `CHECK (col = ANY (ARRAY[...]))` form, manufacturing a phantom DROP+CREATE for semantically-identical constraints. Pre-migration `008-drop-stale-extraction-failures-check.sql` already works around this for `extraction_failures` specifically by dropping the stale constraint *before* pgschema plans, so by plan time the constraint is simply missing and pgschema emits a clean `operation: "create"` (ADD CONSTRAINT), no drop+recreate collision. Step 2 asks us to confirm the general case (no pre-migration guard present) still applies cleanly once `strip_destructive` strips the DROP half.

### TC-792-070 — Reproduce #686 shape on a fresh constraint with no pre-migration guard (new, bats, live PG)
**Setup:** Create a table with a CHECK constraint in the Postgres-canonicalized `= ANY (ARRAY[...])` form (to force pgschema to see a diff against an `IN (...)`-authored desired schema), e.g.:
```sql
CREATE TABLE t792 (id serial PRIMARY KEY, status text);
ALTER TABLE t792 ADD CONSTRAINT t792_status_check CHECK (status::text = ANY (ARRAY['a','b','c']::text[]));
```
Desired schema (throwaway, isolated schema.sql fragment) declares: `CONSTRAINT t792_status_check CHECK (status::text IN ('a','b','c'))`.
**Steps:**
1. `pgschema plan` — confirm it emits the phantom diff (a `operation: "drop", type: "table.constraint"` step for `t792_status_check` plus an `operation: "create"` step re-adding the "same" constraint by the same name) — i.e. confirm the #686 bug still reproduces on an unguarded constraint, as a precondition for the rest of the test.
2. Run `plan_reorder.py` then `strip_destructive.py` (standard pipeline) — the drop step is stripped (universal drop-stripping), the create (ADD CONSTRAINT) step survives.
3. `pgschema apply` the filtered plan.
**Expected / confirm-and-record (per the task brief: "confirm the apply still succeeds"):**
- If apply **succeeds**: record why — e.g. pgschema may detect at apply time that an equivalent constraint already exists and treat the ADD as a no-op, or may use `ADD CONSTRAINT ... NOT VALID`-then-skip semantics, or some other accommodation. Capture the exact apply output.
- If apply **fails** (expected naive outcome: Postgres `42710 duplicate_object`, "constraint `t792_status_check` for relation `t792` already exists"): this is a genuine collision. Since it's not unique to Victoria tables and not introduced by #792's ignore-list change, **do not expand #792's scope to fix it**; record as a second known gap distinct from section 7, cross-reference #686, and recommend the follow-up there explicitly cover "post-strip ADD CONSTRAINT collision when the matching DROP was stripped," since #686's own suggested fixes (canonicalize CHECK exprs, or author schema.sql in canonical form) don't mention this specific collision mode.
**Why this belongs in #792's test design even though the fix lives in #686:** removing the Victoria ignore entries means more tables are now planned (not skipped wholesale), which statistically increases the chance of hitting a phantom-CHECK-diff on some currently-ignored Victoria constraint that nova-mind doesn't control the DDL for. This test's job is to make sure #792 doesn't make a *latent* #686 collision newly reachable on a real peer. See TC-792-071.

### TC-792-071 — #686 collision specifically on a (formerly-ignored) Victoria-shaped constraint (new, bats, live PG)
**Setup:** Extend the TC-792-020 Victoria fixture: add a CHECK constraint on one of the seeded trading tables (e.g. `trades.side`) authored in the DB in canonicalized `= ANY(ARRAY[...])` form, while schema.sql (hypothetically, if it ever grows a managed table with an overlapping name — this is a defensive/forward-looking test) would author it as `IN (...)`. Since schema.sql does **not** currently declare any Victoria table, the realistic version of this test is: confirm that because Victoria tables are *not* in schema.sql, pgschema's diff for them is purely "exists but undeclared" (→ DROP TABLE, universally stripped), **not** a column/constraint-level diff — so the #686 collision mode cannot actually trigger on tables schema.sql doesn't declare at all, only on tables schema.sql *does* declare with a phantom CHECK mismatch (i.e., TC-792-070's scenario, which is about any managed table in general, not Victoria specifically).
**Expected:** confirms the #686 collision risk is orthogonal to #792 — it can occur on any schema.sql-managed table with a phantom-diffing CHECK constraint, Victoria-related or not, and #792 removing the ignore entries does not newly expose Victoria tables to it (because Victoria tables remain entirely outside schema.sql). **This narrows TC-792-070's finding down to "pre-existing general risk, not a #792 regression," which is the key fact for the run log.**

---

## 9. Dependent objects of newly un-ignored tables (Step 2 edge case)

### TC-792-080 — Indexes, sequences, triggers, FKs on Victoria tables all come through as stripped drops (new, bats, live PG)
**Setup:** Reuse the TC-792-020 fixture (it already includes a serial PK sequence per table, two explicit indexes, and FK constraints between `positions`→`portfolios`/`instruments` and `trades`→`positions` and `cash_ledger`→`portfolios`). Add one more dependent-object type not yet covered: a trigger, e.g. an `updated_at` touch trigger on `portfolios`.
**Steps:** Run the real plan → reorder → strip pipeline (inspect the *filtered* plan JSON directly, before apply, as its own assertion — this is the "nothing non-drop references them" half of Step 2's instruction).
**Expected:**
1. The **raw** (pre-strip) plan contains explicit `operation: "drop"` steps for: each Victoria table, each of its indexes (`table.index`), its PK/FK constraints (`table.constraint`), its trigger (`table.trigger`), and its `id`-sequence steps if pgschema emits them separately (check both `type: "table"`-cascaded and any sequence-specific step — confirm empirically which shape pgschema actually uses, since this determines whether the universal drop-strip is sufficient or whether the sequence's drop is implicit in the table's CASCADE and never surfaces as its own JSON step).
2. The **filtered** plan contains **zero** steps whose path references any Victoria table, its indexes, its constraints, its trigger, or its sequence — i.e. re-run an assertion in the shape of `_assert_no_shadow_refs` from `test_608_peer_fdw_bootstrap_context.bats`, parameterized over each Victoria table name, rather than inventing a new one from scratch.
3. Apply succeeds; post-apply, every dependent object still exists and is functionally intact (index still used by `EXPLAIN`, FK still enforced by attempting — and expecting rejection of — an invalid insert, trigger still fires on an UPDATE).

### TC-792-081 — FK pointing *from* a schema.sql-managed table *to* a Victoria table (adversarial cross-boundary case) (new, bats, live PG)
**Setup:** Hypothetical/defensive case — if any schema.sql table were ever to reference a Victoria table by FK (not expected today, but not structurally prevented), confirm the behavior is at least *diagnosable*: pgschema would either refuse to plan (FK target doesn't match expected shape) or plan an orphaned FK add that fails loudly.
**Expected:** since this does not occur in the current schema.sql, this test can realistically only confirm the *absence* of such a reference (`grep -n 'REFERENCES' database/schema.sql` cross-checked against the known Victoria table name list from TC-792-001) and should be written as a guard/invariant test, not a live-apply test: **"schema.sql has no FK referencing a Victoria/agent-local table name."** This stops a future schema.sql change from silently creating a cross-boundary dependency that none of the other tests here would catch.

---

## 10. Adversarial inputs at the ignore-file and plan-JSON seams

### TC-792-050 — Malformed TOML ignore file: pgschema's own behavior (new, bats, live PG — config-to-runtime seam)
**Setup:** Copy `.pgschemaignore` to a scratch dir, corrupt it (unterminated string: `"portfolios` with no closing quote, or an unclosed `[tables]` array missing `]`).
**Steps:** Run `pgschema plan` directly from that scratch dir (cwd-based auto-discovery, matching the installer's own mechanism) against any live DB.
**Expected / confirm-and-record (this is a third-party tool behavior question, must be verified empirically, not assumed):**
- If pgschema **fails fast** (nonzero exit, stderr parse error): safe — the installer's existing plan-exit-code handling already sets `SCHEMA_DIFF_SKIPPED=1` and skips apply. No code change needed; just confirm this is in fact what happens.
- If pgschema **silently ignores the malformed file and plans with zero exclusions**: this is the dangerous fail-open case — it would mean a broken ignore file (whether Victoria-related or not) results in cheerfully planning DROPs for every pattern that should have been excluded, with no error surfaced anywhere. If observed, this is a **known gap** to report (likely the single most important finding in this document if true), independent of #792's specific changes, since it affects the ignore-file mechanism in general. Recommend validating the ignore file's TOML syntax explicitly (e.g. with the same `tomllib`-based check as TC-792-004) *before* handing it to pgschema, failing closed if invalid.

### TC-792-051 — Malformed TOML produced by `inject_peer_shadowed_ignores.py`'s own output (new, pytest, no DB)
**Setup:** Call `_inject_section` (or the CLI) against a `.pgschemaignore`-style file with a `[tables]` section opened but never closed (`patterns = [` with no matching `]` anywhere in the file).
**Expected:** reuses the already-implemented guard — `print(f"ERROR: malformed [{section}] section...")`, `sys.exit(2)`. **This behavior exists today but has no unit test** (confirmed: `grep -rl inject_peer_shadowed_ignores tests/` only finds it referenced from the #608 bats integration fixtures, never a dedicated `test_inject_peer_shadowed_ignores.py`). Add one. Also cover: mismatched `--names`/`--relkinds` lengths (CLI already errors with exit 2 — add a unit test), and an unknown relkind value (already errors — add a unit test for that branch too).

### TC-792-052 — Ignore pattern matches nothing (new, pytest, no DB)
**Setup:** `.pgschemaignore` with `patterns = ["definitely_not_a_real_table_xyz"]` and no other entries.
**Steps:** Run `pgschema plan` against a DB with no such table.
**Expected:** no error, no effect — the pattern is simply unused. Confirms that over-conservative leftover patterns (e.g. if a future cleanup forgets to remove a stale name) degrade gracefully rather than erroring, which also means **silent pattern drift is undetectable without an explicit test** — recommend (not scope-expanding, just a note for the follow-up docs) that TC-792-001-style "every pattern in the ignore file actually matches something in the fixture/live schema" could be a useful CI check later, since this test demonstrates the opposite is cheap to introduce accidentally.

### TC-792-053 — Local table name collides with a schema.sql table (ordinary table, not view/FDW) (new, bats, live PG)
**Important distinction from the peer-shadowed tests (#608):** `detect_peer_shadowed.py` only detects relkind `f` (foreign table) and `v` (view) collisions. An ordinary local table (relkind `r`) that happens to share a name with a schema.sql table is **not** detected by that mechanism at all — pgschema just diffs it directly against the desired shape, for better or worse.
**Setup:** Create a local table named identically to a real schema.sql table (e.g. `memory_embeddings`) but with a deliberately incompatible column (e.g. a column schema.sql doesn't have, and one schema.sql has but typed differently/narrower here — reuse the TC-792-060 narrowing setup, applied to a *colliding name* instead of a throwaway table name).
**Steps:** Run the real pipeline.
**Expected / confirm-and-record:**
- Columns schema.sql has that the local table lacks: additive `ADD COLUMN` steps, survive stripping, apply cleanly (same mechanism as TC-792-030, just on an organically-colliding table rather than a deliberately-truncated one).
- Columns the local table has that schema.sql doesn't declare: pgschema would plan a `DROP COLUMN` — confirm it is stripped (universal drop-stripping) and the extra column survives.
- Any column present in both with an incompatible type: this is exactly the section 7 lossy-alter gap, now in a "collides with a real managed table" setting rather than an isolated throwaway table — if the earlier section 7 tests confirmed the gap exists, this test demonstrates its real-world trigger condition (an operator's local table organically named the same as a future schema.sql table) rather than a synthetic one, which matters for severity assessment in the follow-up issue.

### TC-792-054 — Plan step with an unexpected `operation` value: case mismatch (new, pytest, no DB)
**Setup:** Hand-craft a plan JSON step with `"operation": "DROP"` (uppercase) instead of `"drop"`.
**Steps:** Run `strip_destructive()` (direct Python call, following `tests/test_strip_destructive.py`'s existing pattern) against this plan.
**Expected / confirm-and-record:** since `strip_destructive.py` does `step.get("operation") == "drop"` as an exact, case-sensitive string compare, a `"DROP"`-cased step is **not** matched and would be kept. Confirm this is indeed the observed behavior (it should be, by code inspection, but per the task's adversarial-input requirement this must be demonstrated by a passing/failing test, not just read off the source). **If pgschema itself only ever emits lowercase `"drop"`** (verify against a real plan JSON sample captured from any other live test in this document), this is a defense-in-depth gap rather than an exploitable one today — record as a minor known gap (case-insensitive compare would be a one-line, low-risk hardening, but is out of #792's stated scope unless the implementer judges it trivial enough to bundle; if so, note it as an opportunistic fix, not a scope expansion).

### TC-792-055 — Plan step with an unrecognized `operation` value entirely (new, pytest, no DB)
**Setup:** Step with `"operation": "truncate"` or `"operation": null` or the key omitted entirely, carrying a destructive-looking `sql` field (e.g. `"sql": "DROP TABLE public.x;"`) that disagrees with its own `operation` metadata.
**Steps:** Run `strip_destructive()`.
**Expected / confirm-and-record:** the function only inspects the `operation` field, never the `sql` text — so a step whose `operation` doesn't literally equal `"drop"` is kept regardless of what its `sql` actually does. This is the **most significant** adversarial finding in this category: it means `strip_destructive.py` trusts pgschema's own `operation` labeling completely, with zero independent verification against the SQL text. Record as a **known gap**: "strip_destructive.py has no defense against a plan step whose declared `operation` disagrees with its `sql` payload (e.g. a future pgschema bug, a hand-edited plan file, or plan-file tampering between `plan` and `apply`)." Recommend as a follow-up (not #792 scope): a lightweight SQL-text sanity check (e.g. regex for leading `DROP`/`TRUNCATE`/`ALTER ... DROP`/`ALTER ... TYPE` keywords) cross-validated against the declared `operation`, failing closed (treat as a drop) on disagreement. This is a generic plan-JSON trust-boundary gap, not something #792's ignore-list change introduces — same "don't grow #792's scope" logic as section 7.

### TC-792-056 — Plan step with an unexpected `type` value (new, pytest, no DB)
**Setup:** Step with `"operation": "create"`, a valid-looking `path`, but `"type": "materialized_view_refresh"` (not a key in `_NONOWNED_TYPE_CATEGORY`), combined with `db_user`+`resolver` supplied (so the non-owned-object check path is exercised).
**Steps:** Run `strip_destructive(plan, db_user="nova", resolver=<stub>)`.
**Expected:** `_resolve_step_owners` returns `None` for the unrecognized type (falls through `_NONOWNED_TYPE_CATEGORY.get(stype, (None, ()))` → `category is None` → `return None`), so the non-owned-object gate is silently skipped for this step — it is kept regardless of actual ownership. Confirm this is observed behavior. **Known gap, same category as TC-792-055:** an unrecognized `type` bypasses both the drop-strip's type-sensitivity (N/A here since drop-strip doesn't key on type at all) and the ownership gate. Since this requires `db_user`+`resolver` to even be reachable, and #792's own ignore-list change doesn't touch `_NONOWNED_TYPE_CATEGORY` or introduce new step types, this is pre-existing and out of #792's scope — fold into the same follow-up recommendation as TC-792-055 rather than filing a third, overlapping issue.

---

## 11. Regression guard for existing suites

### TC-792-090 — Existing peer/FDW and additive-apply bats suites pass unmodified (existing, bats, live PG)
**Run:** `bats tests/install/test_608_peer_fdw_bootstrap_context.bats tests/install/test_additive_schema_apply.bats tests/install/test_peer_shadowed_fail_closed.bats tests/install/test_peer_shadowed_grant_reconciliation.bats tests/install/test_peer_shadowed_grant_stdin.bats tests/install/test_installer_ownership_666.bats tests/install/test_issue_759_nonowned_revokes.bats tests/install/test_issue_590_owner_revokes.bats` plus `python3 -m pytest tests/test_strip_destructive.py -v`.
**Expected:** all pass unchanged. Since #792's change is scoped to two static TOML files (and possibly docs), none of these suites should need updates — they don't assert on the *content* of `.pgschemaignore`/`-peer`, only on behavior (peer detection, grant reconciliation, ownership gating). If any of them break, that's a signal the "redundant and can go" claim in Step 2 was wrong for some case these tests exercise, and the implementer should stop and re-examine the scope ruling rather than patch the test to match.
**Also confirm:** none of these existing bats files hard-code a Victoria table name as part of their *test infrastructure* (as opposed to the fixture data under test) in a way that would silently stop testing anything once the ignore-list entries are gone — spot check by grepping these files for `portfolios\|trades\|cash_ledger` outside of fixture-seeding SQL.

---

## 12. Test environment notes for the implementer

- All live-PG bats tests above follow the existing `tests/install/*.bats` conventions already in this repo: a `_pg_available` guard (skip if `psql`/`pgschema`/`pg_isready` unavailable), `_make_test_db`/`_drop_test_db` helpers with a unique scratch DB name per test (PID- and random-suffixed, matching the naming shape already used by `_make_test_db` in `test_608_peer_fdw_bootstrap_context.bats` and `test_additive_schema_apply.bats`), `VENV_PYTHON` resolved the same way the existing suite does, and a skip on missing `pglast`.
- Per the task's safety constraints: all live tests run against a throwaway `createdb`-provisioned scratch database, never `nova_memory`/`victoria_memory`/`newhart_memory`/`graybeard_memory`. On this host, run them on `nova-staging` if a scratch DB on the primary PG instance is not preferred; this worktree's `pgschema`/`psql` are present locally (confirmed: `/usr/local/bin/pgschema`) so scratch-DB-on-primary-instance (matching the existing `tests/install/*.bats` pattern, which already does exactly this) is consistent with how every other installer test in this repo runs today.
- pytest-only tests (section 10's TC-792-051, TC-792-054 through TC-792-056, plus section 2's TC-792-004) need no DB at all and should live in `tests/test_strip_destructive.py` (extend the existing file, following its `_plan()` helper pattern) or a new `tests/test_inject_peer_shadowed_ignores.py` for the TOML-injection-specific cases.
- Counts in this document use **TC-792-0NN** numbering reserved for this issue; final bats `@test` names should keep this prefix (matching the repo's existing `TC-498x`/`TC-608x`/`TC-1231x` convention) so Step 8 validation can trace pass/fail back to this design doc by ID.
