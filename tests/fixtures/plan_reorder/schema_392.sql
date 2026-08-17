-- TC-3 regression fixture: view-before-table ordering bug (#392).
-- This schema is intentionally broken: v_portfolio_allocation references the
-- positions table before positions is defined.  The CI negative control job
-- applies this file with psql -v ON_ERROR_STOP=1 and expects failure.

CREATE VIEW v_portfolio_allocation AS
    SELECT symbol, quantity FROM positions;

CREATE TABLE positions (
    id      serial PRIMARY KEY,
    symbol  text   NOT NULL,
    quantity numeric NOT NULL
);
