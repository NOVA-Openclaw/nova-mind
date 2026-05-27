-- pre-migration 004: Drop deprecated portfolio tables
-- SE Run #27 BUG-1 fix
--
-- These tables were replaced by the new trades/positions/portfolio_snapshots schema.
-- All tables were verified empty (0 rows) before dropping.
--
-- Run as: nova (table owner)
-- Idempotent: IF EXISTS guards prevent errors on repeat runs.

DROP TABLE IF EXISTS portfolio_history;
DROP TABLE IF EXISTS portfolio_updates;
DROP TABLE IF EXISTS ticker_portfolio;
DROP TABLE IF EXISTS pm_domain_portfolio_snapshots;
DROP TABLE IF EXISTS portfolio_metrics;
DROP TABLE IF EXISTS portfolio_positions;
