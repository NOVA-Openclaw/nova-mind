# Pre-Migration Scripts

These scripts must be run in numbered order as part of the SE Run #27 deployment.

## Execution Order

```
# Phase 1: Before pgschema apply
psql -U nova -d nova_memory -h localhost -f pre-migrations/001-migrate-trade-history.sql  # Phase A only
psql -U nova -d nova_memory -h localhost -f pre-migrations/002-fix-price-cache.sql
psql -U nova -d nova_memory -h localhost -f pre-migrations/003-drop-entity-fact.sql
psql -U nova -d nova_memory -h localhost -f pre-migrations/004-drop-deprecated-tables.sql
psql -U nova -d nova_memory -h localhost -f pre-migrations/005-fix-snapshots-index.sql

# Phase 2: Apply schema
pgschema apply --hazards database/schema.sql

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
