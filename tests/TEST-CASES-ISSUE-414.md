Schema verification complete against live `nova_memory`. Here's the test design document for nova-mind #414.

---

# Test Design Document — `generate-delegation-context.sh` (nova-mind #414)

**QA Lead:** Gem · **Workflow:** SE #408, Step 3 · **Target:** `nova-mind/cognition/scripts/generate-delegation-context.sh`

**Schema verification performed (2026-07-11, read-only, user `gem`):** All step-2 findings confirmed against live `nova_memory`:
- `workflow_steps_detail` has no `agent_name` column (columns: `workflow_name, workflow_description, step_order, domain, domains, step_description, produces_deliverable, deliverable_type, deliverable_description, estimated_duration_minutes`). ✅ matches finding.
- `agents` has no `seed_context` column; has `nickname, model, thinking, context_type, allowed_subagents, decision_criteria` (plus `instance_type`, `status`, `fallback_model(s)`, etc.). ✅ matches finding.
- Live apostrophe hazard is **real, not hypothetical**: workflow `"Neva & Edmund's Edification"` exists today. An unquoted `$workflow_name` interpolation into SQL breaks on this workflow *right now* if the script were re-run.
- Live scale: 33 active workflows (`workflows.status='active'`), 34 distinct workflow names in `workflow_steps_detail` (includes 1 non-active or differently-scoped name — worth noting, not blocking), 188 steps total (close to stated 180 — DB has grown since step 2 findings were captured; not a discrepancy, just drift).
- Active agents: 14 subagent + 1 primary + 1 peer = 16 rows with `status='active'`.
- 15 active agents have `decision_criteria IS NULL`, 1 has it populated. Confirms the NULL case is the *majority* case, not a rare edge — §3 generation must handle NULL gracefully as the default path, not as an exception.
- 2 steps have `domains` array length > 1 (multi-domain steps exist live).
- **No live workflow currently has zero steps** in `workflow_steps_detail` (all 33 active workflows resolve to ≥1 row). This edge case must be tested via a **synthetic DB fixture**, not assumed reproducible against prod data.

---

## 1. Test Approach

This is a ~130-line bash script wrapping 5 psql queries and markdown templating. Proportionate coverage means:

- **Primary vehicle:** a plain-bash test script (`test-generate-delegation-context.bats` or equivalent BATS suite if `bats` is available in the repo's toolchain; otherwise a hand-rolled `test_generate_delegation_context.sh` using assert-style functions) that runs the script against a **disposable test schema/fixture**, not live `nova_memory`.
- **Secondary vehicle:** a manual verification checklist for the one run that must happen against live data (post-deploy smoke test), since fixture-based tests can't fully validate "does this look right against 33 real workflows."
- **No mocking of psql itself** — tests should exercise real `psql` against a seeded test database (staging Postgres, per existing project convention of using `nova-staging` for destructive/test work) so query syntax and column-name regressions are caught for real, not just simulated.

**Test data strategy:** Build a minimal seed fixture (`test/fixtures/delegation_context_seed.sql`) that creates the needed tables (or truncates + inserts into copies) with deliberately chosen rows:
- 1 workflow with a normal name/description
- 1 workflow named `Test's Workflow` (apostrophe)
- 1 workflow with description containing `# Not A Heading` and `## Also Not`
- 1 workflow with **zero** steps (row in `workflows`, no matching rows in `workflow_steps`/`workflow_steps_detail`)
- 1 step with `domains` array of 2+ elements
- Agents: at least one with `decision_criteria` populated, at least one with NULL, one with empty `allowed_subagents` array, one with NULL `allowed_subagents`

Run against **nova-staging** only, per standing instruction — never against production `nova_memory`.

---

## 2. Test Cases

### TC-1 — Happy Path: Full Generation Against Live-Shaped Schema
**Preconditions:** Seeded fixture DB with ≥2 workflows, ≥2 agents, valid `.pgpass` entry for test-runner user.
**Steps:** Run `generate-delegation-context.sh` with no args.
**Expected:**
- Exit code 0.
- Output file created at default path `~/.openclaw/workspace/DELEGATION_CONTEXT.md`.
- File contains, in order: `# Delegation Context` header, `**Generated:** <timestamp>` line, `## ` (or equivalent) §1 Agents table with header `| Nickname | Role | Model | Description |` (or documented equivalent) and one row per active agent, §2 Active Workflows section with one subsection per active workflow each containing a step table, §3 Spawn Instructions section, footer line `*Auto-generated from nova_memory database. Do not edit manually.*`.
- Row counts in §1 match `SELECT count(*) FROM agents WHERE status='active'`; workflow count in §2 matches `SELECT count(*) FROM workflows WHERE status='active'`.
- No stderr output (clean run).

### TC-2 — Error Condition: Query 4 Fails (bad column simulation)
**Preconditions:** Fixture DB where `workflow_steps_detail` is temporarily replaced with a view missing `domain`/`domains` (simulating schema drift), OR run script against a schema snapshot pre-fix to confirm baseline failure mode is *caught*, not silently truncated.
**Steps:** Run script.
**Expected:**
- No silent mid-file truncation (this is the regression the fix targets — historically produced 3,343 B truncated output with no error).
- §2 output contains an explicit degradation marker (e.g. `> ⚠️ Failed to generate workflow step data: <error>`) instead of being cut off.
- Script's **final exit code is non-zero**.
- stderr shows the actual psql error (no `2>/dev/null` swallowing it).
- Other sections (§1, §3) still render completely — one section's failure does not blank the whole document.

### TC-3 — Error Condition: Query 5 Fails (agents query)
Same shape as TC-2 but targeting the agents/spawn-instructions query. Same expectations: degradation marker in §3, non-zero exit, visible stderr, §1/§2 unaffected.

### TC-4 — Error Condition: DB Unreachable
**Steps:** Point script at an invalid host/port or stop the test Postgres instance, run script.
**Expected:** Every section fails gracefully with degradation markers (or script fails fast at the top with a single clear top-level error before attempting any section — either behavior is acceptable, but it must be **one of these two**, not a partial/truncated file with no explanation). Non-zero exit. stderr shows connection error.

### TC-5 — Error Condition: Wrong DB User (permission denied)
**Steps:** Run script as a user with no grants on `nova_memory` tables.
**Expected:** Same as TC-4 — clear failure, non-zero exit, visible permission-denied error, no silent truncation. Confirms error handling isn't just for syntax errors but also auth/permission failures.

### TC-6 — Edge Case: Workflow Name Contains Apostrophe
**Preconditions:** Fixture includes workflow `Test's Workflow` (mirrors live `"Neva & Edmund's Edification"`).
**Steps:** Run script.
**Expected:**
- Script does not error out or produce malformed SQL.
- §2 correctly renders the `Test's Workflow` section with its steps included.
- Confirms the `$workflow_name` unquoted-interpolation defect is fixed (parameterized query, `psql -v`, or properly escaped literal — implementation's choice, but the apostrophe must not break the query or allow SQL injection).
- **This test must also be run against a read-only snapshot/copy including the real "Neva & Edmund's Edification" workflow** as a non-fixture regression check, since it's a live, currently-present hazard.

### TC-7 — Edge Case: Workflow Description Contains `#` Heading Syntax
**Preconditions:** Fixture workflow description = `"# Not A Heading\n## Also Not A Heading\nRegular text."`
**Steps:** Run script.
**Expected:** Output markdown does not have the embedded `#`/`##` lines rendering as actual document headings that collide with the document's own header hierarchy (e.g. via escaping leading `#` characters, or fencing the description in a blockquote/code block). Verify by rendering the output through a markdown parser (or visually inspecting heading levels) — the document's own `#`/`##`/`###` structure must remain unambiguous and distinguishable from embedded content.

### TC-8 — Edge Case: Workflow With Zero Steps
**Preconditions:** Fixture workflow with a row in `workflows` (status active) but zero matching rows in `workflow_steps_detail`.
**Steps:** Run script.
**Expected:** Workflow still appears in §2 (name + description shown), with an explicit "no steps defined" marker instead of an empty/malformed table or a crash. Script does not error or skip the workflow silently.

### TC-9 — Edge Case: Agent With NULL `decision_criteria`
**Preconditions:** Live-representative — 15/16 active agents already have this. Confirmed default case, not exceptional.
**Steps:** Run script.
**Expected:** §3 spawn instructions render cleanly for these agents (omit the decision-criteria line/field entirely, or show a neutral placeholder — must not print literal `NULL`, empty garbage, or error).

### TC-10 — Edge Case: Multi-Domain Step (`domains` array, >1 element)
**Preconditions:** Fixture step with `domains = '{"QA","Engineering"}'`.
**Steps:** Run script.
**Expected:** §2 step table renders the domains joined sensibly (e.g. `QA, Engineering`) rather than raw Postgres array literal syntax (`{QA,Engineering}`) or an error. Matches the documented fix direction (`array_to_string(domains, ', ')`).

### TC-11 — Edge Case: Empty Active-Workflow Set
**Preconditions:** Fixture DB with zero rows where `workflows.status='active'`.
**Steps:** Run script.
**Expected:** §2 renders with an explicit "no active workflows" statement, not an empty/blank section, not a crash, not a truncated file.

### TC-12 — Edge Case: `$1` Output-Path Override
**Steps:** Run `generate-delegation-context.sh /tmp/custom-output-test.md` (or an appropriately permissioned non-`/tmp` path per secrets-hygiene norms — this file has no secrets, so `/tmp` is acceptable here, but confirm no assumption of default path anywhere in the script).
**Expected:** Output written to the specified path; default path is untouched/not also written; exit code 0 on success.

### TC-13 — Boundary/Format: Valid Markdown, No Heading Collisions
**Steps:** Run script against full happy-path fixture; parse output through a markdown linter/parser (e.g. `markdownlint` or a simple heading-level check).
**Expected:** No parse errors; heading hierarchy (`#`, `##`, `###`) is consistent and matches the documented format spec exactly (§1/§2/§3 as same-level headings under the top `#`).

### TC-14 — Boundary/Format: Generated Timestamp Is UTC
**Steps:** Run script; inspect the `**Generated:**` line.
**Expected:** Timestamp is explicitly UTC (either has a `Z`/`UTC` suffix or is verified equal to `date -u` at run time, not local server time). Given the workspace's own current timezone is UTC, this is easy to miss as a bug if the host TZ ever changes — test must assert UTC explicitly, not just "matches current time."

### TC-15 — Domain-Specific/Integration: Runs via `.pgpass`, No `PGPASSWORD` Dependency
**Steps:** Run script in an environment with `PGPASSWORD` explicitly unset (per `GLOBAL/DATABASE_ACCESS` — this should already be the norm via `~/.bash_env`, but this script must not silently depend on it being set). Also run a negative check: confirm the script does **not** set or read `PGPASSWORD` itself anywhere in its source.
**Expected:** Script authenticates successfully via `.pgpass` alone. `grep -c PGPASSWORD generate-delegation-context.sh` returns 0.

### TC-16 — Domain-Specific/Integration: Installer Deploys to Documented Path
**Steps:** Run the installer (or its relevant step) against a clean/test target; check resulting file location and permissions.
**Expected:** Script lands at `nova-mind/cognition/scripts/generate-delegation-context.sh` (repo) and is deployed/symlinked/copied to wherever the installer places runtime scripts, matching whatever path convention the rest of the installer uses (verify by comparing to a sibling script's install target — do not invent a new convention). Executable bit set.

### TC-17 — Domain-Specific/Integration: Idempotent Re-Run
**Steps:** Run script twice in a row against the same fixture/output path.
**Expected:** Second run overwrites the first cleanly — no appended duplicate content, no stale leftover sections from a prior partial-failure run, byte-for-byte reproducible output given identical DB state (modulo the `Generated:` timestamp line).

### TC-18 — Regression Guard: Schema Drift Detection
**Steps:** Add an explicit pre-flight or per-query column-existence check (e.g. `\d workflow_steps_detail` parsed, or an `information_schema.columns` query) asserting that `workflow_steps_detail` has `domain`/`domains` and `agents` has `nickname, model, thinking, context_type, allowed_subagents, decision_criteria` before running the main queries — OR, at minimum, a standalone test (not part of the script itself) that runs on every CI execution:
```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'workflow_steps_detail' AND column_name = 'agent_name';
-- Expected: 0 rows (regression: this column should never reappear un-noticed;
-- if it does, the original bug's *shape* has changed and the fix should be re-reviewed)

SELECT column_name FROM information_schema.columns
WHERE table_name = 'agents' AND column_name = 'seed_context';
-- Expected: 0 rows (same rationale)

SELECT column_name FROM information_schema.columns
WHERE table_name = 'workflow_steps_detail' AND column_name IN ('domain','domains');
-- Expected: 2 rows — these must exist for the fix to be valid
```
**Expected:** This check runs as part of the test suite (not the production script) so that if the schema drifts again in either direction, CI fails loudly instead of the script silently degrading (or silently "working" against a schema that no longer matches the documented format).

---

## 3. Manual Verification Checklist (post-deploy, against live `nova_memory` — read-only)

Run once after merge, before closing the issue:

- [ ] Run script live (as an appropriately-privileged read user, staging first if any doubt, prod only for final smoke test) with no args.
- [ ] Confirm output at `~/.openclaw/workspace/DELEGATION_CONTEXT.md`, exit code 0, no stderr.
- [ ] §1 lists all 16 active agents (14 subagent + 1 primary + 1 peer) with correct nickname/model/etc.
- [ ] §2 lists 33 active workflows, each with a populated step table (188 total step rows should reconcile — expect minor drift if workflows changed since this document was written; verify against live `SELECT count(*) FROM workflows WHERE status='active'` and `SELECT count(*) FROM workflow_steps_detail` at test time, not against this document's numbers).
- [ ] `"Neva & Edmund's Edification"` workflow appears correctly with its apostrophe intact and its steps listed (this is the direct real-world regression check for the SQL-injection-adjacent defect).
- [ ] Any workflow description containing `#`/`##` (confirmed live: "Cognition System Diagnostic", "Daily Inspiration Art", "Daily Music Composition", "Edmund Mentoring", "Full System Diagnostic") renders without heading collisions.
- [ ] The 15 agents with NULL `decision_criteria` render cleanly in §3 (no literal `NULL` strings).
- [ ] The ≥2 multi-domain steps render domains joined as readable text, not raw array syntax.
- [ ] Footer line present and matches documented text exactly.
- [ ] File is valid, well-formed Markdown (spot-check in a renderer).
- [ ] Diff the new output against the previous manually-recovered version (if available) to confirm no unexpected content loss.

---

## 4. Definition of Done

The fix passes QA when:

1. All 18 automated test cases (TC-1 through TC-18) pass against the staging fixture DB.
2. The regression-guard schema check (TC-18) is committed as a permanent CI-runnable test, not a one-time manual check.
3. The manual verification checklist is executed once against live `nova_memory` (read-only) post-deploy with all items checked.
4. `grep -c '2>/dev/null' generate-delegation-context.sh` returns 0 (confirms stderr suppression removed).
5. No `set -e`-induced silent truncation is reproducible — deliberately breaking each of the 5 queries in turn (TC-2/TC-3/TC-4/TC-5 pattern) always yields a degradation marker + non-zero exit, never a truncated file with exit 0.
6. Script is present in the `nova-mind` repo at the documented path and wired into the installer (TC-16), with no stray copy left in `~/.openclaw/workspace/scripts/` (or that copy is a symlink to the repo version, per `UNIVERSAL/FILE_ACCESS` no-deprecated-symlink guidance — confirm which convention the installer uses and match it).
7. Nothing in the script depends on `PGPASSWORD` (TC-15).

I'll hold this session open for the later desk-review and validation steps per the workflow. Flagging one thing for the Coder/implementation step: the "zero-step workflow" and "schema-drift" scenarios have no live equivalent in production today, so those must be tested via synthetic fixtures on staging — they are real risks (the fix should handle them) but not reproducible against current prod data.