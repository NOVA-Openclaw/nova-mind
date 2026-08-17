# SE Run #709, Step 9 — Documentation Audit Report

**Scope:** Document the nova-mind#597 batch (dependency-aware pgschema plan reordering, plus the related #447/#392 fixes and the installer exit-code gate) and audit all in-scope project documentation against source at commit `e2367e7` (branch `feature/issue-597-plan-dependency-ordering`).

**Method:** Read every file in the required pre-enumerated scope with the `read` tool (root docs directly; the four subsystem trees — cognition/, memory/, motivation/, psyche/, relationships/ — and skills/agent-ecosystem/SKILL.md via three parallel subagent audits). All factual claims (file paths, script names, table/column names, installer stage behavior, exit codes, function signatures) were checked against the live source in the worktree, not assumed. No file in scope failed to read.

## Files Updated (11)

| File | Why |
|---|---|
| `ARCHITECTURE.md` | Declarative Schema Management section rewritten to describe the new `database/plan_reorder.py` reorder stage (dependency graph, metadata-dependent reassignment, exit codes, known limitations); added a new "Schema-Apply Exit-Code Gate (#597)" bullet describing the installer's fail-fast behavior change. |
| `README.md` | Added a paragraph after the installer invocation describing the `plan → reorder → hazard-check → apply` pipeline and the #597/#447/#392 fix. |
| `CHANGELOG.md` | New top entry, `Batch: plan-dependency-ordering-597 (Issues #597, #447, #392)` — Added/Fixed/Fix-loop-history/Known-limitations/Issues-Closed sections covering `plan_reorder.py` (new file), the CI schema-apply regression job, the exit-code gate fix, the `pkg_import_name()` version-specifier fix, the three original ordering defects (#597/#447/#392), the five-defect fix-loop history from staging (COMMENT/GRANT stranding → schema-qualified names → view→column deps → `groups: null` → CI role provisioning), and the nova-mind#600 known-limitations list. |
| `database/schema-reference.md` | New "Schema Apply Pipeline (nova-mind#597)" section ahead of the Functions section, summarizing the reorder stage and pointing to ARCHITECTURE.md/CHANGELOG.md for detail. Did not touch the existing drift-tracking header notes (out of scope for this run; those track table/column drift, not the #597 batch). |
| `memory/INSTALLATION.md` | New "2026-08-17: Dependency-Aware Schema Plan Reordering" entry under Recent Changes (same structure as prior dated entries in this file); updated the "Schema Management" numbered step list (was 5 steps, now 6 — inserted "Reorders the plan" between plan and hazard-check). |
| `memory/README.md` | Updated the `agent-install.sh` bullet describing schema apply to mention the reorder stage; extended the "Upgrading?" callout to describe the new ordering guarantee and exit-code behavior. |
| `memory/docs/database-schema-guide.md` | Updated the 4-step "Schema Management" list to 5 steps (added plan-reorder step) with a pointer to ARCHITECTURE.md/CHANGELOG.md. |
| `memory/docs/deployment-setup-guide.md` | Added a "Plan reorder (nova-mind#597)" row to the Installer Step Order table, plus an exit-code-behavior callout paragraph. |
| `pre-migrations/README.md` | Corrected the Phase 2 comment block, which described the pgschema plan→apply invocation but predated `plan_reorder.py` — now mentions the reorder stage and corrects a stale reference to `memory/agent-install.sh` (confirmed a stale, uninvoked pre-merge copy per `memory/INSTALLATION.md`'s own Architecture section) to point at the actual live repo-root `agent-install.sh`. |
| `memory/ARCHITECTURE.md` | Non-#597 fix (found during the memory-docs subagent audit): the documented turn-context truncation warning string was missing the `Alert I)ruid.` suffix that the live string in `UNIVERSAL/AUTONOMOUS_FIX_EXECUTION`-adjacent code actually emits — corrected to match. |
| `memory/docs/semantic-recall.md` | Non-#597 fix (found during the memory-docs subagent audit): the `proactive-recall.py` usage examples showed the query as a positional CLI argument (`python proactive-recall.py "search query"`); the live script reads the query from stdin. Corrected all three example invocations to `echo "query" | python proactive-recall.py [...]`. |

## Stale Docs Found and Fixed

Beyond the #597-batch documentation task itself, the parallel subagent audits found exactly **two** pre-existing staleness items, both listed in the table above (memory/ARCHITECTURE.md truncation-message string, memory/docs/semantic-recall.md CLI usage examples). Both were fixed directly since they were small, unambiguous, single-line/single-block corrections with a clear source-of-truth to check against.

## Full Audit Coverage

All 52 files in the required scope were checked (root docs handled directly by the primary session; the remaining 51 subsystem-tree files split across three parallel subagent audits):

- **cognition/ tree (20 files: README, CHANGELOG, 18 docs/*.md + SKILL.md)** — 20/20 clean, no changes needed. No file made a stale claim about `agent-install.sh`'s schema-apply exit-code behavior.
- **memory/ tree (17 files, README.md and database-schema-guide.md handled directly)** — 15/17 clean; 2 fixes applied (see above).
- **motivation/, psyche/, relationships/ trees (15 files)** — 15/15 clean, no changes needed. Corroborates the prior `DOC-AUDIT-RUN333.md` finding that these subsystems' docs were already accurate.

Total: 52/52 files read successfully; 0 read errors; 11 files edited (9 for the #597 batch, 2 for unrelated pre-existing staleness).

## plan_reorder.py Inline Docs

Read the full file (`database/plan_reorder.py`, 700+ lines). The module docstring was verified against the final behavior at `e2367e7`:
- Design-constraints bullets (groups-only mutation, directive/non-transactional isolation, transactional-group merging, DROP reverse-direction ordering, plpgsql body re-parsing, external-schema/missing-object handling) all match the implementation.
- The four hard-failure classes (cycles, top-level parse failure, unknown plan-format version, malformed plan JSON) match `PlanFormatError`/`ParseError`/`CycleError` and the CLI's exit-code mapping (2/3/4) exactly.
- No inline comment or docstring correction was needed — the file's self-documentation was already accurate and current. No edits made to `plan_reorder.py` (docs-only scope; code/comments were correct as-is).

## Flagged Items Needing Human/Follow-up

None beyond what is already tracked in **nova-mind#600** (CTE column dependencies, `ADD COLUMN ... DEFAULT <expr>` references, cross-table index predicates, `DROP TYPE` identity, function-overload disambiguation, `OBJECT_KIND_MAP` missing SCHEMA/DOMAIN/EXTENSION/MATVIEW) — all referenced from the new CHANGELOG.md entry and ARCHITECTURE.md section rather than duplicated as new issues.

No documentation gaps or inaccuracies were found that require escalation beyond the fixes already applied in this pass.
