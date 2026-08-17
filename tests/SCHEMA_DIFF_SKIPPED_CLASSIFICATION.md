# SCHEMA_DIFF_SKIPPED Classification (issue-597 chunk 3)

Audit of every `SCHEMA_DIFF_SKIPPED=1` / `SCHEMA_DIFF_HAZARD=1` call site in
`agent-install.sh` after chunk 3.

| Line | Call site | Flag | Classification | Rationale |
|------|-----------|------|----------------|-----------|
| ~1355 | CREATE EXTENSION failure | `SCHEMA_DIFF_SKIPPED=1` | **Unrecoverable → fatal** | Schema requires the extension (e.g. `vector`); limp install is broken. |
| ~1379 | Pre-migration failure | `SCHEMA_DIFF_SKIPPED=1` | **Unrecoverable → fatal** | Pre-migrations are required DDL; "continuing" removed. |
| ~1417 | renames.json column rename failure | `SCHEMA_DIFF_SKIPPED=1` | **Unrecoverable → fatal** | Declared rename must land before pgschema diff. |
| ~1444 | renames.json table rename failure | `SCHEMA_DIFF_SKIPPED=1` | **Unrecoverable → fatal** | Declared rename must land before pgschema diff. |
| ~1502 | pgschema plan failure | `SCHEMA_DIFF_SKIPPED=1` | **Unrecoverable → fatal** | No plan means no safe apply path. |
| ~1517 | Plan reorderer hard-fail | `SCHEMA_DIFF_SKIPPED=1` | **Unrecoverable → fatal** | Cycle / parse failure / malformed plan requires human resolution. |
| ~1561 | Destructive-changes hazard gate | `SCHEMA_DIFF_HAZARD=1` | **Recoverable/intentional → non-fatal** | Protective gate; blocks auto-apply of DROPs by design. |
| ~1599 | GRANT reconciliation failure | `SCHEMA_DIFF_SKIPPED=1` | **Unrecoverable → fatal** | Privilege state did not land; this is an apply error. |
| ~1606 | pgschema apply failure | `SCHEMA_DIFF_SKIPPED=1` | **Unrecoverable → fatal** | Schema changes did not commit. |

Final exit gate (after schema management block):

```bash
if [ "$SCHEMA_DIFF_SKIPPED" -eq 1 ] && [ "$SCHEMA_DIFF_HAZARD" -eq 0 ]; then
    exit 1
fi
```

A `SCHEMA_DIFF_HAZARD=1` skip does **not** produce a nonzero exit because the
installer intentionally refused to apply destructive changes; all other skips
abort the installation.
