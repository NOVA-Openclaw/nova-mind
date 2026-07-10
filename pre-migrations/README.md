# Pre-Migration Scripts

These scripts must be run in numbered order as part of the SE Run #27 deployment.

> **Not the same directory `agent-install.sh` uses.** The installer's automatic
> pre-migration step reads only `database/pre-migrations/` (repo root, a sibling
> directory to this one). This `pre-migrations/` directory holds a separate,
> point-in-time set of manual portfolio-schema cleanup scripts from SE Run #27 and is
> **not** executed automatically by the installer — run the commands below by hand.

## Execution Order

```
# Phase 1: Before pgschema apply
psql -U nova -d nova_memory -h localhost -f pre-migrations/001-migrate-trade-history.sql  # Phase A only
psql -U nova -d nova_memory -h localhost -f pre-migrations/002-fix-price-cache.sql
psql -U nova -d nova_memory -h localhost -f pre-migrations/003-drop-entity-fact.sql
psql -U nova -d nova_memory -h localhost -f pre-migrations/004-drop-deprecated-tables.sql
psql -U nova -d nova_memory -h localhost -f pre-migrations/005-fix-snapshots-index.sql

# Phase 2: Apply schema (actual installer invocation: pgschema plan writes a
# plan JSON, then pgschema apply consumes it — there is no --hazards flag;
# hazard/destructive-drop detection is done by the installer via jq against
# the plan JSON before calling apply, not by a pgschema flag; see
# memory/agent-install.sh)
pgschema plan --host localhost --port 5432 --db nova_memory --user nova \
  --schema public --file database/schema.sql \
  --plan-host localhost --plan-port 5432 --plan-db nova_memory --plan-user nova \
  --output-json /tmp/pgschema-plan.json
pgschema apply --host localhost --port 5432 --db nova_memory --user nova \
  --schema public --plan /tmp/pgschema-plan.json --auto-approve

# Phase 3: After pgschema apply (seed new canonical tables)
psql -U nova -d nova_memory -h localhost -f pre-migrations/001-migrate-trade-history.sql  # Phase B: seeds trades + positions
```

## Script Summary

| Script | When | Purpose |
|--------|------|---------|
| 001-migrate-trade-history.sql | Before + After | Phase A: cash asset_class + dedupe; Phase B: seed trades/positions |
| 002-fix-price-cache.sql | Before | Normalize price_cache_v2 asset_class to lowercase 'stock' |
| 003-drop-entity-fact.sql | Before | Remove stale paper_portfolio entity fact (id=5818) |
| 004-drop-deprecated-tables.sql | Before | Drop legacy tables so pgschema can create canonical versions |
| 005-fix-snapshots-index.sql | Before | Drop unique date index to allow intra-day snapshots |

## Notes

- All scripts are idempotent (safe to run multiple times)
- Run on **staging** first, verify test cases pass, then production
- Script 001 auto-detects whether canonical tables exist and skips seeding if not yet created
