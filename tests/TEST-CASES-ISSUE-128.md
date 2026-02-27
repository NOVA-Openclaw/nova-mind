# QA Test Design: Declarative Schema Migrations with pg-schema-diff (#128)

> ⚠️ **SUPERSEDED by #155** — `pg-schema-diff` was replaced by `pgschema` (pgplex/pgschema) in issue #155. This document is retained for historical reference only. For current test cases, see [TEST-CASES-ISSUE-155.md](TEST-CASES-ISSUE-155.md).

## Overview
This document outlines the test strategy and test cases for the replacement of manual `migrate_schema()` logic in `agent-install.sh` with `pg-schema-diff`.

**Issue:** [NOVA-Openclaw/nova-memory#128](https://github.com/NOVA-Openclaw/nova-memory/issues/128)

## Test Strategy
The testing will focus on verifying that `agent-install.sh` correctly uses `pg-schema-diff` to manage the database schema, handles destructive changes safely, ensures prerequisites are met, and processes pre-migrations correctly.

Testing will be performed in a controlled environment using temporary PostgreSQL databases.

## Test Cases

### 1. Prerequisite Validation
| ID | Title | Description | Expected Result |
|---|---|---|---|
| PREREQ-01 | Missing `pg-schema-diff` | Run installer on a system where `pg-schema-diff` is not in PATH. | Installer fails early with a clear error message about the missing prerequisite and exit code 1. |
| PREREQ-02 | Found `pg-schema-diff` | Run installer on a system where `pg-schema-diff` is installed. | Prerequisite check passes; installer continues. |

### 2. Happy Path (Fresh & Incremental)
| ID | Title | Description | Expected Result |
|---|---|---|---|
| HAPPY-01 | Fresh Install | Run installer against a non-existent database. | Database is created, extensions are enabled, and full schema is applied. Total table count is correct. |
| HAPPY-02 | Incremental Update (Sync) | Run installer against a database that is already in sync with `schema.sql`. | Installer completes successfully; `pg-schema-diff` reports no changes needed; no errors/warnings. |
| HAPPY-03 | Add Column | Modify `schema.sql` to add a new column. Run installer. | `pg-schema-diff` applies the change. New column exists in the database. |

### 3. Pre-migrations Logic
| ID | Title | Description | Expected Result |
|---|---|---|---|
| PRE-01 | Run Pre-migrations | Create `pre-migrations/001_test.sql`. Run installer. | Script is executed *before* `pg-schema-diff apply`. Logs show execution order. |
| PRE-02 | Order & Success | Create multiple numbered scripts. Run installer. | Scripts run in lexicographical order. Installer proceeds if they exit 0. |

### 4. Hazard & Safety Handling

> **Critical behavior:** `pg-schema-diff` is all-or-nothing. If ANY hazardous statements exist in the plan and aren't allowed, the ENTIRE plan is rejected — safe statements are NOT applied either. The installer must use `plan` first to detect hazards, then only call `apply` if the plan is hazard-free.

| ID | Title | Description | Expected Result |
|---|---|---|---|
| HAZARD-01 | Destructive Change (Rename/Drop) | Modify `schema.sql` by renaming or dropping a table/column. Run installer. | Installer runs `plan` first, detects hazards, prints warning showing the hazardous statements. Schema apply is SKIPPED entirely. Installer continues to next step (hooks, seeds, etc.). |
| HAZARD-02 | Mixed Safe + Hazardous | Modify `schema.sql` to add one column and drop another. Run installer. | Neither change is applied (all-or-nothing). Installer warns about hazards, skips schema apply, continues with rest of install. Database remains unchanged. |
| HAZARD-03 | Hazards resolved via pre-migration | Add a pre-migration script that handles the rename manually. Run installer. | Pre-migration runs first, renames the column. Then `pg-schema-diff plan` detects no hazards, `apply` runs successfully. |

### 5. Plan Validation & Perms
| ID | Title | Description | Expected Result |
|---|---|---|---|
| VAL-01 | Successful Validation | Run installer where user has `CREATEDB`. | `pg-schema-diff` validates the plan using a temporary database. |
| VAL-02 | Missing CREATEDB | Run installer where user lacks `CREATEDB` privilege. | Installer fails during prerequisites with a clear error message and instructions to grant `CREATEDB`. |

### 6. Domain-Specific (nova-memory)
| ID | Title | Description | Expected Result |
|---|---|---|---|
| NOVA-01 | Enum Type Sync | Change the `agent_chat_status` enum in `schema.sql`. Run installer. | `pg-schema-diff` correctly syncs the custom enum type. |
| NOVA-02 | Extension Dependencies | Verify extensions `vector` and `pg_trgm` are correctly handled by the diff tool. | Extensions are created if missing or kept if present. |

### 7. Regression / Cleanup
| ID | Title | Description | Expected Result |
|---|---|---|---|
| REG-01 | migrate_schema removed | Grep `agent-install.sh` for `migrate_schema`, `ALTER TABLE.*ADD COLUMN IF NOT EXISTS`. | No matches found. All manual migration code has been removed. |
| REG-02 | Installer flow order | Run installer with pre-migrations and schema changes on an existing database. | Order is: prerequisites → DB create/check → pre-migrations → plan check → apply (if safe) → hooks → seeds. Logs confirm order. |
| REG-03 | Installer continues after hazard skip | Run installer where schema has hazards. | Hooks installation, seed data, and all subsequent installer steps complete successfully despite schema apply being skipped. |

## Definition of Done (DoD)
- [ ] `agent-install.sh` no longer contains `migrate_schema()` or manual `ALTER TABLE` blocks.
- [ ] Installer successfully uses `pg-schema-diff` for fresh and incremental schema updates.
- [ ] All pre-migration scripts in `pre-migrations/` are executed before the schema diff.
- [ ] Hazardous changes are detected and warned but not auto-applied.
- [ ] CREATEDB prerequisite check fails early with clear instructions when missing.
- [ ] All test cases listed above pass in a staging/test environment.
