# Test Cases for Issue #155: Declarative Schema Migrations with pgschema

This document outlines the test cases for verifying the reimplementation of declarative schema migrations using `pgschema` in the `nova-memory` installer.

## Test Environment
- **Host**: `nova-staging@localhost`
- **Tool**: `pgschema` (pgplex/pgschema)
- **Constraint**: No privileges/ownership management; structure-only.

## Test Cases

| ID | Category | Description | Expected Result |
|:---|:---|:---|:---|
| **TC-1.1** | Prerequisites | Run `agent-install.sh` with `pgschema` missing from PATH. | Installer fails early with a clear error message that `pgschema` is required. |
| **TC-1.2** | Prerequisites | Run `agent-install.sh` with `pgschema` installed. | Installer proceeds past dependency check. |
| **TC-2.1** | Fresh Install | Run installer on a completely empty database. | All tables, functions, types, and extensions defined in `schema.sql` are created successfully. |
| **TC-3.1** | Incremental (no-op) | Run installer on a database that is already up-to-date with `schema.sql`. | `pgschema plan` reports no changes; installer exits successfully without applying any SQL. |
| **TC-4.1** | Incremental (add) | Add a new column to a table in `schema.sql` and run installer. | `pgschema` detects the new column; installer applies the change; table now has the new column. |
| **TC-5.1** | Destructive Change | Remove a column or table from `schema.sql` and run installer. | Installer detects destructive changes in the plan JSON, warns the user, and blocks the application. |
| **TC-5.2** | Destructive Change | After generating a plan with a destructive change, verify the JSON output contains identifiable DROP statements. | JSON contains `kind: "drop"` (or equivalent identifiable DROP field). Hazard check identifies these specific patterns. |
| **TC-5.3** | Destructive Change | When destructive changes block the schema apply, verify the rest of the installer still runs (hooks, scripts, config, verification). | Schema sync is skipped, but subsequent install steps (e.g., config generation, verification) complete successfully. |
| **TC-6.1** | Pre-migrations | Place a script in `pre-migrations/` that adds a prerequisite (e.g., a shared type) and run installer. | The pre-migration script executes *before* `pgschema plan` runs. |
| **TC-7.1** | Extension Handling | Remove an extension required by the schema from the DB. | Installer runs `CREATE EXTENSION IF NOT EXISTS` before planning; `pgschema` correctly resolves types dependent on that extension. |
| **TC-7.2** | Extension Handling | Verify `pgschema plan` uses `--plan-db $DB_NAME` and can resolve extension types (e.g., `vector` columns). | The plan command succeeds without "type does not exist" errors for extension-defined types. |
| **TC-8.1** | Privileges | Grant custom permissions to a table, then run installer. | `pgschema` does NOT generate `REVOKE` or `GRANT` statements; existing privileges remain untouched. |
| **TC-9.1** | Functions/Triggers | Modify the body of a PL/pgSQL function in `schema.sql`. | `pgschema` detects the change and updates the function definition declaratively. |
| **TC-10.1** | Regression | Check `agent-install.sh` for old `migrate_schema()` or manual `ALTER TABLE` blocks. | Manual migration logic is removed in favor of the declarative `pgschema` flow. |
| **TC-11.1** | Non-superuser | Run installer (non-superuser) when extensions are **already installed**. | Installer succeeds; `pgschema` works within user's permissions. |
| **TC-11.2** | Non-superuser | Run installer (non-superuser) when extensions are **NOT installed**. | Installer fails with a clear message about needing extension installation by a superuser. |
| **TC-12.1** | pgschemaignore | Add a table to the DB but list it in `.pgschemaignore`, then run installer. | `pgschema` ignores the table and does not attempt to drop it even if it's missing from `schema.sql`. |
| **TC-13.1** | Cleanup | After a successful install, verify temp plan files are removed. | No files matching `/tmp/pgschema-plan-*.json` remain on the system. |
| **TC-14.1** | Schema Dump | Run `pgschema dump` against the live DB. | Output is clean SQL: no `OWNER TO`, no `GRANT/REVOKE`, no `\restrict`, no `SET ROLE`. Includes extensions, functions, triggers, and types. |
| **TC-15.1** | Fingerprint | Generate a plan, manually alter the DB schema, then try to apply the plan. | `pgschema` rejects the application due to a fingerprint mismatch between plan and live schema. |

## Checklist Summary

- [x] `pgschema` binary check works correctly.
- [x] Extensions (`vector`, `pg_trgm`) are ensured before migration.
- [x] Pre-migration scripts execute in the correct order.
- [x] Destructive changes (DROP) are caught and blocked via plan JSON parsing.
- [x] `pgschema plan` uses `--plan-db` for accurate type resolution.
- [x] Database privileges are strictly NOT managed/altered.
- [x] Functions and triggers are updated correctly via declarative sync.
- [x] `.pgschemaignore` is respected.
- [x] Clean cleanup of temp plan files.
- [x] Schema dump output is sanitized (no ownership/grants).
- [x] Fingerprint validation prevents application to altered schemas.
