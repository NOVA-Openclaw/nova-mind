-- pre-migration 004: Drop deprecated portfolio tables
-- Run BEFORE pgschema apply (pgschema will then create fresh canonical versions).
-- Purpose: Remove legacy/deprecated tables that have been superseded by the
--          canonical schema (trades, positions, portfolio_snapshots).
-- Order matters: drop dependent objects before referenced ones.
-- Idempotent: IF EXISTS on all drops.

BEGIN;

-- Drop deprecated portfolio tables
DROP TABLE IF EXISTS portfolio_history;
DROP TABLE IF EXISTS portfolio_updates;
DROP TABLE IF EXISTS ticker_portfolio;
DROP TABLE IF EXISTS pm_domain_portfolio_snapshots;
DROP TABLE IF EXISTS portfolio_metrics;
DROP TABLE IF EXISTS portfolio_positions;

-- Drop old positions table so pgschema can CREATE the new canonical version.
-- The new positions table has a different schema (asset_class FK, timestamptz, etc.)
-- pgschema cannot safely ALTER this — we drop first, pgschema creates fresh.
-- Data is preserved in portfolio_positions (which we migrate above) and will
-- be reseeded by pre-migration 001 after the new table is created.
DROP TABLE IF EXISTS positions;

COMMIT;
