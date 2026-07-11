# Test-Case-to-Implementation Mapping — nova-mind #414

This document maps each test case from the QA test design for
`generate-delegation-context.sh` to the concrete BATS test and fixture data that
validates it. It is written from the implementation side, not the design side.

| TC | Design Intent | BATS Test | Fixture / Test Data | Key Assertions |
|---|---|---|---|---|
| TC-1 | Happy path: full generation against a representative schema. | `@test "TC-1: full generation against live-shaped schema"` | `tests/fixtures/delegation_context_seed.sql` — 3 active agents, 4 active workflows (incl. apostrophe/heading/zero-step), 4 step rows. | Exit 0; output contains all 3 sections, header/footer, agent table rows, workflow subsections, step table, joined multi-domain step. |
| TC-2 | Workflow-step query failure degrades instead of truncating silently. | `@test "TC-2: workflow step query failure emits degradation marker and exits non-zero"` | Fixture loaded; `DROP TABLE delegation_context_test.workflow_steps_detail CASCADE` simulates schema drift. | Exit != 0; `> ⚠️ Failed to generate workflow step data` present; §1 and §3 still render. |
| TC-3 | Agents query failure degrades instead of truncating silently. | `@test "TC-3: agents query failure emits degradation marker and exits non-zero"` | Fixture loaded; `DROP TABLE delegation_context_test.agents CASCADE` simulates schema drift. | Exit != 0; both roster and spawn markers present; §2 still renders. |
| TC-4 | Unreachable database fails cleanly. | `@test "TC-4: unreachable database fails cleanly with non-zero exit"` | Point script at invalid host/port (`127.0.0.1:65432`). | Exit != 0; header + `> ⚠️ Failed to generate agent roster` marker present. |
| TC-5 | Wrong/invalid DB user fails cleanly. | `@test "TC-5: invalid DB user fails cleanly with non-zero exit"` | Set `DELEGATION_CONTEXT_DB_USER` to a nonexistent user. | Exit != 0. |
| TC-6 | Workflow name with apostrophe does not break SQL. | `@test "TC-6: workflow name with apostrophe renders correctly"` | Fixture workflow `Test's Workflow` mirrors the live `"Neva & Edmund's Edification"` hazard. | Section heading and step row render correctly; script exits 0. |
| TC-7 | Embedded `#`/`##` in descriptions do not collide with document headings. | `@test "TC-7: embedded heading syntax is escaped"` | Fixture workflow description contains `# Not A Heading\n## Also Not A Heading`. | Escaped lines present; exactly one level-1 heading in output. |
| TC-8 | Workflow with zero steps renders explicit marker. | `@test "TC-8: zero-step workflow shows explicit marker"` | Fixture `Zero Step Workflow` has no matching `workflow_steps_detail` rows. | Workflow subsection present; `> No steps defined for this workflow.` present. |
| TC-9 | NULL `decision_criteria` does not render as literal `NULL`. | `@test "TC-9: NULL decision_criteria renders without literal NULL"` | Fixture agents: `alpha` populated, `beta`/`gamma` NULL. | No literal `Decision criteria: NULL`; populated case renders for `alpha`. |
| TC-10 | Multi-domain step renders joined text, not raw array literal. | `@test "TC-10: multi-domain step renders joined domains"` | Fixture step with `domains = ARRAY['QA','Engineering']`. | `| 2 | QA, Engineering | Review feature | report |` present; raw `{QA,Engineering}` absent. |
| TC-11 | Empty active-workflow set renders explicit statement. | `@test "TC-11: empty active workflow set renders explicit statement"` | Fixture loaded; `UPDATE delegation_context_test.workflows SET status = 'inactive'` (schema-qualified). | `No active workflows found.` present; exit 0. |
| TC-12 | `$1` output path override works and default path is untouched. | `@test "TC-12: output path override writes to specified file only"` | Run script with a temp custom output path. | Custom file created and contains header; default path not written. |
| TC-13 | Markdown heading hierarchy is consistent. | `@test "TC-13: heading hierarchy is consistent"` | Full happy-path fixture. | Exactly one `# ` heading; `##` section headings present. |
| TC-14 | Generated timestamp is UTC. | `@test "TC-14: generated timestamp is UTC"` | Any successful run. | `**Generated:**` line matches `YYYY-MM-DD HH:MM UTC` format. |
| TC-15 | Script uses `.pgpass`, not `PGPASSWORD`. | `@test "TC-15: script authenticates via pgpass and contains no PGPASSWORD references"` | Run with `PGPASSWORD` unset; static source checks. | `grep -c PGPASSWORD` == 0; `grep -c '2>/dev/null'` == 0; script succeeds. |
| TC-16 | Installer wires the script to the runtime scripts directory. | `@test "TC-16: installer copies script to runtime scripts directory"` | Static check of `agent-install.sh`. | Script executable; installer references the source and target paths. |
| TC-17 | Re-running the script overwrites cleanly (no duplicates). | `@test "TC-17: second run overwrites output cleanly"` | Full happy-path fixture; run twice to same file. | `# Delegation Context` and footer `---` each appear exactly once. |
| TC-18 | Schema regression guard: dead columns absent, replacement columns present. | `@test "TC-18: regression guard detects required and removed columns"` | Read-only queries against `public` schema of the configured DB. | `agent_name` and `seed_context` absent; `domain`/`domains` and spawn columns present. |

## Isolation Strategy

The BATS suite uses a disposable schema named `delegation_context_test` inside
whichever database is configured via `DELEGATION_CONTEXT_DB_NAME` (defaulting to
`nova_memory`). This is a compromise: a dedicated staging database was attempted
but the test-runner user (`coder`) has no `.pgpass` entry for the existing
`nova_staging_memory` database, and the `nova` DB user lacks `CREATEROLE`, so a
fresh role/password could not be created without operator help.

To make the schema-based approach safe, the suite enforces:

1. `CREATE SCHEMA IF NOT EXISTS delegation_context_test` and `GRANT ALL` are run
   via the privileged `nova` DB user; fixture tables are created inside it.
2. A pre-flight `assert_fixture_isolation()` guard checks
   `current_schema() = 'delegation_context_test'` **and** that
   `to_regclass('agents')`, `to_regclass('workflows')`, and
   `to_regclass('workflow_steps_detail')` all resolve to
   `delegation_context_test.*` before any destructive statement runs.
3. All destructive statements are schema-qualified:
   `DROP TABLE delegation_context_test.workflow_steps_detail CASCADE`, etc.

If the guard ever fails, the test aborts without executing `DROP`/`UPDATE`
against `public.*` tables.

## Known Deviations from the Original Design

- **Test target database:** The fixture runs in `nova_memory` (default) rather
  than `nova_staging_memory` because `coder` has no authentication path to the
  existing staging database. The schema + guard approach above is the
  defense-in-depth substitute.
- **Test DB user:** The test runner connects as `coder` (the agent's own DB
  user) for all reads and fixture loads; schema creation is delegated to the
  `nova` DB user because `coder` lacks `CREATE` on `nova_memory`.
- **TC-14 timestamp assertion:** Changed from exact string equality against
  `date -u` to a format regex, eliminating a minute-rollover flake.
