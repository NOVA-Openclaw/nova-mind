-- Migration 089: D100 motivation — per-slot weight column and weighted roll_d100().
-- Issue #803
--
-- Changes:
--   1. Add `weight numeric NOT NULL DEFAULT 1` to motivation_d100, with a
--      CHECK (weight >= 0) constraint added only if missing.
--   2. Rewrite roll_d100() to draw once from the weighted eligible pool:
--        - empty slots are eligible when unreserved, enabled, and weight > 0;
--        - populated slots are eligible when enabled, weight > 0, and they
--          pass the existing 7-day anti-repeat window / 50% cap;
--        - weight-0 rows are excluded from the cap's denominators;
--        - the return signature, error text, tracking updates, and
--          is_populate_me semantics are unchanged.

-- ---------------------------------------------------------------------------
-- 1. Schema addition
-- ---------------------------------------------------------------------------
ALTER TABLE motivation_d100
    ADD COLUMN IF NOT EXISTS weight numeric NOT NULL DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'motivation_d100_weight_check'
          AND conrelid = 'motivation_d100'::regclass
    ) THEN
        ALTER TABLE motivation_d100
            ADD CONSTRAINT motivation_d100_weight_check
            CHECK (weight >= 0);
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. roll_d100() — weighted draw over the currently eligible pool.
--
-- Implementation notes:
--   * CREATE OR REPLACE is used because the 15-column return signature is
--     unchanged; existing grants (including EXECUTE to nova) survive.
--   * Eligibility and the weighted sample are computed in CTEs. The draw
--     target is materialized once per loop so random() is not re-evaluated
--     per row of the cumulative sum.
--   * No temporary tables are used: a caller cannot pre-create a temp table
--     and shadow the function's internal state (SECURITY DEFINER hardening).
--   * Fractional weights are supported because the column is numeric and the
--     cumulative sum is computed in numeric.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION roll_d100()
RETURNS TABLE(
    roll integer,
    task_name varchar,
    task_description text,
    workflow_id integer,
    skill_name varchar,
    tool_name varchar,
    difficulty varchar,
    energy_required varchar,
    estimated_minutes integer,
    times_rolled integer,
    times_completed integer,
    last_rolled timestamp,
    last_completed timestamp,
    notes text,
    is_populate_me boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    picked_roll    integer;
    picked_is_pop  boolean;
    attempts       integer := 0;
    max_attempts   integer := 20;
    v_now          timestamp := CURRENT_TIMESTAMP::timestamp;
BEGIN
    LOOP
        attempts := attempts + 1;
        IF attempts > max_attempts THEN
            RAISE EXCEPTION 'roll_d100: no populated+enabled tasks found after % attempts', max_attempts;
        END IF;

        WITH pop AS MATERIALIZED (
            SELECT m.roll, m.last_rolled, m.weight
            FROM motivation_d100 m
            WHERE m.task_name IS NOT NULL
              AND m.enabled = true
              AND m.weight > 0
        ),
        counts AS MATERIALIZED (
            SELECT
                (SELECT count(*) FROM pop) AS total_pop,
                (SELECT count(*) FROM pop WHERE pop.last_rolled >= v_now - interval '7 days') AS recent_pop
        ),
        admit AS MATERIALIZED (
            SELECT ranked.roll
            FROM (
                SELECT p.roll,
                       row_number() OVER (ORDER BY p.last_rolled ASC, p.roll ASC) AS rn
                FROM pop p
                WHERE p.last_rolled >= v_now - interval '7 days'
            ) ranked
            WHERE rn <= (
                SELECT GREATEST(c.recent_pop - (floor(c.total_pop * 0.5))::integer, 0)
                FROM counts c
            )
        ),
        eligible AS MATERIALIZED (
            -- Terminal path A: non-reserved empty + enabled => populate-me.
            SELECT m.roll, m.weight, true AS is_populate_me
            FROM motivation_d100 m
            WHERE m.task_name IS NULL
              AND m.reserved = false
              AND m.enabled = true
              AND m.weight > 0
            UNION ALL
            -- Terminal path B: populated + enabled => apply anti-repeat rules.
            SELECT p.roll, p.weight, false AS is_populate_me
            FROM pop p
            WHERE p.last_rolled IS NULL
               OR p.last_rolled < v_now - interval '7 days'
               OR p.roll IN (SELECT a.roll FROM admit a)
        ),
        target AS MATERIALIZED (
            SELECT random()::numeric * COALESCE((SELECT SUM(weight) FROM eligible), 0) AS t
        )
        SELECT e.roll, e.is_populate_me
        INTO picked_roll, picked_is_pop
        FROM (
            SELECT t.roll, t.is_populate_me,
                   sum(t.weight) OVER (ORDER BY t.roll) AS cum_weight
            FROM eligible t
        ) e,
        target tg
        WHERE e.cum_weight > tg.t
        ORDER BY e.cum_weight
        LIMIT 1;

        IF picked_roll IS NULL THEN
            CONTINUE;
        END IF;

        UPDATE motivation_d100 m
        SET times_rolled = COALESCE(m.times_rolled, 0) + 1,
            last_rolled  = v_now
        WHERE m.roll = picked_roll;

        RETURN QUERY
        SELECT m.roll, m.task_name, m.task_description, m.workflow_id,
               m.skill_name, m.tool_name, m.difficulty, m.energy_required,
               m.estimated_minutes, m.times_rolled, m.times_completed,
               m.last_rolled, m.last_completed, m.notes,
               picked_is_pop
        FROM motivation_d100 m
        WHERE m.roll = picked_roll;
        RETURN;
    END LOOP;
END;
$$;
