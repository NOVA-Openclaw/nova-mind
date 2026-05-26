-- pre-migration 003: Remove stale mutable paper_portfolio entity fact
-- Run BEFORE pgschema apply.
-- Purpose: The paper_portfolio entity fact (id=5818) stores a mutable snapshot
--          of portfolio state in entity_facts, which is wrong — portfolio state
--          now lives in portfolio_snapshots and positions tables.
--          Policy/testimony facts (rule 5903, fact 5898, etc.) are preserved.
-- Idempotent: safe to run if already deleted.

BEGIN;

DELETE FROM entity_facts WHERE id = 5818;

COMMIT;
