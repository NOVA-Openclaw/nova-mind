-- pre-migration 002: Normalize price_cache_v2.asset_class to lowercase 'stock'
-- Run BEFORE pgschema apply.
-- Purpose: Fix inconsistent asset_class values ('STOCK', 'equity') to canonical 'stock'.
-- Idempotent: safe to run multiple times.

BEGIN;

-- Normalize 'STOCK' → 'stock'
UPDATE price_cache_v2
SET asset_class = 'stock'
WHERE asset_class = 'STOCK';

-- Normalize 'equity' → 'stock'
UPDATE price_cache_v2
SET asset_class = 'stock'
WHERE asset_class = 'equity';

COMMIT;
