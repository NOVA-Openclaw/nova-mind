-- pre-migration 001: Prepare trade history data and seed canonical tables
-- EXECUTION ORDER:
--   Phase A (before pgschema apply):
--     - Add 'cash' to asset_classes
--     - Dedupe portfolio_positions (drop duplicate SMCI exit row 7 if present)
--   Phase B (after pgschema apply):
--     - Seed trades table from reconstructed history
--     - Populate canonical positions table
--
-- This script is idempotent. Run it before AND after pgschema apply.
-- The INSERT INTO trades/positions sections skip safely if tables don't exist yet.
--
-- SE Run #27, nova-workspace issues #6 and #7.

BEGIN;

-- ===================================================================
-- PHASE A: Pre-pgschema work (safe to run on existing DB)
-- ===================================================================

-- 1. Add 'cash' asset class if not present
INSERT INTO asset_classes (code, name, description, price_source, trading_hours, typical_unit)
VALUES (
    'cash',
    'Cash',
    'Cash and cash equivalents. Used for deposit and withdrawal tracking.',
    NULL,
    'N/A',
    'dollars'
)
ON CONFLICT (code) DO NOTHING;

-- 2. Dedupe portfolio_positions: remove duplicate SMCI exit (row ~7 in old data)
--    The old portfolio_positions table had two rows representing the same SMCI sell.
--    Keep the first occurrence (lowest id), delete the duplicate.
DO $$
DECLARE
    v_exists boolean;
BEGIN
    -- Check if portfolio_positions table exists (may already be dropped by 004)
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'portfolio_positions'
    ) INTO v_exists;

    IF v_exists THEN
        -- Delete duplicate SMCI sell rows, keeping only the earliest id
        DELETE FROM portfolio_positions
        WHERE symbol = 'SMCI' AND sold_at IS NOT NULL
          AND id NOT IN (
              SELECT MIN(id)
              FROM portfolio_positions
              WHERE symbol = 'SMCI' AND sold_at IS NOT NULL
          );
        RAISE NOTICE 'Deduped SMCI exit rows in portfolio_positions';
    ELSE
        RAISE NOTICE 'portfolio_positions not found — dedup already done or table dropped';
    END IF;
END $$;

-- ===================================================================
-- PHASE B: Post-pgschema work (requires trades and positions tables)
-- ===================================================================

DO $$
DECLARE
    v_trades_exist boolean;
    v_positions_exist boolean;
BEGIN
    -- Check if new canonical tables exist (created by pgschema)
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'trades'
    ) INTO v_trades_exist;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'positions'
          -- Distinguish new canonical positions from old: check for asset_class FK
          AND EXISTS (
              SELECT 1 FROM information_schema.table_constraints
              WHERE table_name = 'positions' AND constraint_name = 'positions_asset_class_fkey'
          )
    ) INTO v_positions_exist;

    IF NOT v_trades_exist THEN
        RAISE NOTICE 'trades table not yet created — run pgschema first, then re-run this script';
        RETURN;
    END IF;

    -- ---------------------------------------------------------------
    -- Seed trades table (9 reconstructed trades, source='migration')
    -- ---------------------------------------------------------------

    -- Trade 1: Initial cash deposit 2026-02-02
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-02-02 14:30:00+00', 'CASH', 'cash', 'deposit', 10000, 1.00, 0, 'Initial paper trading deposit', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'CASH' AND side = 'deposit'
          AND executed_at = '2026-02-02 14:30:00+00'
    );

    -- Trade 2: AMD buy 2026-02-02
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-02-02 14:30:00+00', 'AMD', 'stock', 'buy', 8, 245.40, 0, 'Initial position', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'AMD' AND side = 'buy'
          AND executed_at = '2026-02-02 14:30:00+00'
    );

    -- Trade 3: NVDA buy 2026-02-02
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-02-02 14:30:00+00', 'NVDA', 'stock', 'buy', 10, 190.84, 0, 'Initial position', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'NVDA' AND side = 'buy'
          AND executed_at = '2026-02-02 14:30:00+00'
    );

    -- Trade 4: META buy 2026-02-02
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-02-02 14:30:00+00', 'META', 'stock', 'buy', 3, 716.85, 0, 'Initial position', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'META' AND side = 'buy'
          AND executed_at = '2026-02-02 14:30:00+00'
    );

    -- Trade 5: SMCI buy 2026-02-02
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-02-02 14:30:00+00', 'SMCI', 'stock', 'buy', 69, 29.10, 0, 'Initial position', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'SMCI' AND side = 'buy'
          AND executed_at = '2026-02-02 14:30:00+00'
    );

    -- Trade 6: CRWD buy 2026-02-02
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-02-02 14:30:00+00', 'CRWD', 'stock', 'buy', 4, 441.50, 0, 'Initial position', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'CRWD' AND side = 'buy'
          AND executed_at = '2026-02-02 14:30:00+00'
    );

    -- Trade 7: META sell 2026-05-15 (exit full position)
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-05-15 14:31:00+00', 'META', 'stock', 'sell', 3, 618.43, 0, 'Full position exit', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'META' AND side = 'sell'
          AND executed_at = '2026-05-15 14:31:00+00'
    );

    -- Trade 8: NVDA add 2026-05-15
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-05-15 14:31:00+00', 'NVDA', 'stock', 'buy', 5, 235.74, 0, 'Add to position', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'NVDA' AND side = 'buy'
          AND executed_at = '2026-05-15 14:31:00+00'
    );

    -- Trade 9: SMCI sell 2026-05-18 (exit full position; deduped — exactly one SMCI sell)
    INSERT INTO trades (executed_at, symbol, asset_class, side, quantity, price, fees, notes, source)
    SELECT '2026-05-18 14:31:00+00', 'SMCI', 'stock', 'sell', 69, 31.04, 0, 'Full position exit', 'migration'
    WHERE NOT EXISTS (
        SELECT 1 FROM trades
        WHERE source = 'migration' AND symbol = 'SMCI' AND side = 'sell'
          AND executed_at = '2026-05-18 14:31:00+00'
    );

    RAISE NOTICE 'Trade history seeded successfully';

    -- ---------------------------------------------------------------
    -- Populate canonical positions table from trade history
    -- (Only if positions table exists with new schema)
    -- ---------------------------------------------------------------

    IF NOT v_positions_exist THEN
        RAISE NOTICE 'New canonical positions table not ready — re-run after pgschema apply';
        RETURN;
    END IF;

    -- AMD: 8 shares, cost_basis $1,963.20 (open)
    INSERT INTO positions (symbol, asset_class, quantity, cost_basis, purchased_at, notes)
    SELECT 'AMD', 'stock', 8, 1963.20, '2026-02-02 14:30:00+00', 'Migrated from trade history'
    WHERE NOT EXISTS (SELECT 1 FROM positions WHERE symbol = 'AMD' AND sold_at IS NULL);

    -- NVDA: 15 shares (10 + 5), cost_basis $3,087.10 (open)
    INSERT INTO positions (symbol, asset_class, quantity, cost_basis, purchased_at, notes)
    SELECT 'NVDA', 'stock', 15, 3087.10, '2026-02-02 14:30:00+00',
           'Migrated from trade history (10 initial @ 190.84 + 5 added 2026-05-15 @ 235.74)'
    WHERE NOT EXISTS (SELECT 1 FROM positions WHERE symbol = 'NVDA' AND sold_at IS NULL);

    -- CRWD: 4 shares, cost_basis $1,766.00 (open)
    INSERT INTO positions (symbol, asset_class, quantity, cost_basis, purchased_at, notes)
    SELECT 'CRWD', 'stock', 4, 1766.00, '2026-02-02 14:30:00+00', 'Migrated from trade history'
    WHERE NOT EXISTS (SELECT 1 FROM positions WHERE symbol = 'CRWD' AND sold_at IS NULL);

    -- CASH: $3,022.30 remaining (open)
    -- Calculation: $10,000 - $9,796.05 (initial buys) + $1,855.29 (META sale)
    --              - $1,178.70 (NVDA add) + $2,141.76 (SMCI sale) = $3,022.30
    INSERT INTO positions (symbol, asset_class, quantity, cost_basis, purchased_at, notes)
    SELECT 'CASH', 'cash', 3022.30, 3022.30, '2026-02-02 14:30:00+00',
           'Migrated cash balance after all trades'
    WHERE NOT EXISTS (SELECT 1 FROM positions WHERE symbol = 'CASH' AND sold_at IS NULL);

    -- META: fully closed (3 bought @ 716.85, 3 sold @ 618.43)
    INSERT INTO positions (symbol, asset_class, quantity, cost_basis, purchased_at, sold_at, sale_proceeds, notes)
    SELECT 'META', 'stock', 3, 2150.55, '2026-02-02 14:30:00+00',
           '2026-05-15 14:31:00+00', 1855.29, 'Migrated closed position'
    WHERE NOT EXISTS (SELECT 1 FROM positions WHERE symbol = 'META' AND sold_at IS NOT NULL);

    -- SMCI: fully closed (69 bought @ 29.10, 69 sold @ 31.04, deduped)
    INSERT INTO positions (symbol, asset_class, quantity, cost_basis, purchased_at, sold_at, sale_proceeds, notes)
    SELECT 'SMCI', 'stock', 69, 2007.90, '2026-02-02 14:30:00+00',
           '2026-05-18 14:31:00+00', 2141.76, 'Migrated closed position'
    WHERE NOT EXISTS (SELECT 1 FROM positions WHERE symbol = 'SMCI' AND sold_at IS NOT NULL);

    RAISE NOTICE 'Canonical positions populated successfully';
END $$;

COMMIT;
