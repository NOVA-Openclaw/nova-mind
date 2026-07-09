-- Migration 084: D100 motivation system refinements
-- Issue #444
--
-- Changes:
--   1. Add `reserved boolean` and `populated_at timestamptz` to motivation_d100.
--   2. Backfill `populated_at` for existing 56 populated slots to `created_at`.
--   3. Reserve 22 of the 44 current empty slots (idempotent; never touches
--      populated slots).
--   4. Populate three new pipeline-feeding content slots.
--   5. Rewrite `roll_d100()`:
--        - non-reserved empty + enabled slots return a populate-me row
--          (additive `is_populate_me boolean` output column);
--        - reserved empty / disabled slots keep the re-roll behavior;
--        - populated+enabled slots use a 7-day anti-repeat window with a
--          dynamic 50%-floor cap; when over cap, oldest `last_rolled` slots
--          are re-admitted first, statelessly per invocation.
--   6. Add `flag_d100_low_completion()` for the monthly completion-rate audit.
--   7. Add `_trg_set_populated_at()` so `populated_at` auto-sets when a slot
--      transitions from empty to real content.
--   8. Update workflow 27 step 11 text to branch on `is_populate_me`.

-- ---------------------------------------------------------------------------
-- 1. Schema additions
-- ---------------------------------------------------------------------------
ALTER TABLE motivation_d100
    ADD COLUMN IF NOT EXISTS reserved boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS populated_at timestamptz;

-- nova is the table owner but operates under column-level UPDATE grants.
-- Ensure the new columns are updatable before the backfill runs.
GRANT UPDATE (reserved, populated_at) ON TABLE motivation_d100 TO nova;

-- ---------------------------------------------------------------------------
-- 2. Backfill populated_at for existing populated slots to created_at.
--    GAP-3 resolution: backfill to created_at, not NULL, so legacy slots
--    (e.g. roll 96, 9/19) remain flag-eligible.
-- ---------------------------------------------------------------------------
UPDATE motivation_d100
SET populated_at = created_at
WHERE task_name IS NOT NULL
  AND populated_at IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Reserve 22 empty slots (idempotent; only empty, non-reserved rows).
-- ---------------------------------------------------------------------------
UPDATE motivation_d100
SET reserved = true
WHERE task_name IS NULL
  AND reserved = false
  AND roll IN (
      51, 52, 53, 54, 55, 56, 57,
      59, 60,
      84, 85, 86, 87, 88, 89, 90, 91, 92,
      94, 95, 97, 99
  );

-- ---------------------------------------------------------------------------
-- 4. Populate three new non-reserved empty slots with pipeline tasks.
-- ---------------------------------------------------------------------------
UPDATE motivation_d100
SET task_name        = 'Bootstrap token audit',
    task_description = E'Pick one random record from agent_bootstrap_context. Assess whether it still earns its per-session token cost. If the context is redundant, stale, or no longer load-bearing, propose a trim/merge/retire action and record it as a lesson or task.',
    difficulty       = 'medium',
    energy_required  = 'low',
    estimated_minutes = 30,
    populated_at     = COALESCE(populated_at, NOW())
WHERE roll = 62
  AND task_name IS NULL
  AND reserved = false;

UPDATE motivation_d100
SET task_name        = 'Subsystem capability-loss review',
    task_description = E'Pick one random subsystem (cron job, watchdog, plugin, workflow, or integration). Run the capability-loss checklist: what would break if it disappeared? Is there a cheaper or merged replacement? File a deprecation/merge proposal if warranted.',
    difficulty       = 'medium',
    energy_required  = 'low',
    estimated_minutes = 30,
    populated_at     = COALESCE(populated_at, NOW())
WHERE roll = 63
  AND task_name IS NULL
  AND reserved = false;

UPDATE motivation_d100
SET task_name        = 'Lesson re-validation',
    task_description = E'Select 5 random lessons older than 30 days. Re-check their confidence and continued accuracy using the same spot-check procedure as the introspect skill\'s Recent Lessons Review. Lower confidence for stale lessons and flag archive candidates.',
    difficulty       = 'medium',
    energy_required  = 'low',
    estimated_minutes = 30,
    populated_at     = COALESCE(populated_at, NOW())
WHERE roll = 64
  AND task_name IS NULL
  AND reserved = false;

-- ---------------------------------------------------------------------------
-- 5. Trigger: auto-set populated_at on empty -> real-content transition.
--    SECURITY DEFINER so the column stays protected from direct nova edits.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _trg_set_populated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.task_name IS NOT NULL AND NEW.populated_at IS NULL THEN
            NEW.populated_at := NOW();
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.task_name IS NULL AND NEW.task_name IS NOT NULL AND NEW.populated_at IS NULL THEN
            NEW.populated_at := NOW();
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_populated_at ON motivation_d100;
CREATE TRIGGER trg_set_populated_at
    BEFORE INSERT OR UPDATE ON motivation_d100
    FOR EACH ROW
    EXECUTE FUNCTION _trg_set_populated_at();

-- ---------------------------------------------------------------------------
-- 6. roll_d100() — generative empty slots, anti-repeat window, dynamic cap.
-- ---------------------------------------------------------------------------
-- Return type changes from the legacy 14-column shape to the 15-column shape
-- that includes is_populate_me. PostgreSQL refuses to CREATE OR REPLACE across
-- a return-type change, so drop first and restore the EXECUTE grant.
DROP FUNCTION IF EXISTS roll_d100();

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
SET search_path = public
AS $$
DECLARE
    picked_roll    integer;
    attempts       integer := 0;
    max_attempts   integer := 20;
    v_now          timestamp := CURRENT_TIMESTAMP::timestamp;
BEGIN
    LOOP
        attempts := attempts + 1;
        IF attempts > max_attempts THEN
            RAISE EXCEPTION 'roll_d100: no populated+enabled tasks found after % attempts', max_attempts;
        END IF;

        -- Pure random 1-100.
        picked_roll := floor(random() * 100 + 1)::integer;

        -- ---------------------------------------------------------------
        -- Terminal path A: non-reserved empty + enabled => populate-me.
        -- Anti-repeat window/cap never applies to empty-slot draws.
        -- ---------------------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM motivation_d100 m
            WHERE m.roll = picked_roll
              AND m.task_name IS NULL
              AND m.reserved = false
              AND m.enabled = true
        ) THEN
            UPDATE motivation_d100 m
            SET times_rolled = COALESCE(m.times_rolled, 0) + 1,
                last_rolled  = v_now
            WHERE m.roll = picked_roll;

            RETURN QUERY
            SELECT m.roll, m.task_name, m.task_description, m.workflow_id,
                   m.skill_name, m.tool_name, m.difficulty, m.energy_required,
                   m.estimated_minutes, m.times_rolled, m.times_completed,
                   m.last_rolled, m.last_completed, m.notes,
                   true
            FROM motivation_d100 m
            WHERE m.roll = picked_roll;
            RETURN;
        END IF;

        -- ---------------------------------------------------------------
        -- Terminal path B: populated + enabled => apply anti-repeat rules.
        -- ---------------------------------------------------------------
        IF EXISTS (
            SELECT 1 FROM motivation_d100 m
            WHERE m.roll = picked_roll
              AND m.task_name IS NOT NULL
              AND m.enabled = true
        ) THEN
            -- Eligibility: not rolled in last 7 days, unless the cap forces
            -- re-admission of the oldest recently-rolled slots.
            IF EXISTS (
                WITH pop AS (
                    SELECT m.roll, m.last_rolled
                    FROM motivation_d100 m
                    WHERE m.task_name IS NOT NULL
                      AND m.enabled = true
                ),
                counts AS (
                    SELECT
                        (SELECT count(*) FROM pop) AS total_pop,
                        (SELECT count(*) FROM pop WHERE last_rolled >= v_now - interval '7 days') AS recent_pop
                ),
                admit AS (
                    SELECT p.roll
                    FROM pop p, counts c
                    WHERE p.last_rolled >= v_now - interval '7 days'
                    ORDER BY p.last_rolled ASC, p.roll ASC
                    LIMIT GREATEST(c.recent_pop - (floor(c.total_pop * 0.5))::integer, 0)
                )
                SELECT 1
                FROM pop p
                WHERE p.roll = picked_roll
                  AND (
                      p.last_rolled IS NULL
                      OR p.last_rolled < v_now - interval '7 days'
                      OR p.roll IN (SELECT roll FROM admit)
                  )
            ) THEN
                UPDATE motivation_d100 m
                SET times_rolled = COALESCE(m.times_rolled, 0) + 1,
                    last_rolled  = v_now
                WHERE m.roll = picked_roll;

                RETURN QUERY
                SELECT m.roll, m.task_name, m.task_description, m.workflow_id,
                       m.skill_name, m.tool_name, m.difficulty, m.energy_required,
                       m.estimated_minutes, m.times_rolled, m.times_completed,
                       m.last_rolled, m.last_completed, m.notes,
                       false
                FROM motivation_d100 m
                WHERE m.roll = picked_roll;
                RETURN;
            END IF;

            -- Excluded by anti-repeat window/cap; try again.
            CONTINUE;
        END IF;

        -- All other draws (reserved empty, disabled) => re-roll.
        CONTINUE;
    END LOOP;
END;
$$;

-- Restore nova EXECUTE grant after drop/create.
GRANT EXECUTE ON FUNCTION roll_d100() TO nova;

-- ---------------------------------------------------------------------------
-- 7. Monthly completion-rate flagging.
--    Rolls are counted only after populated_at (via d100_roll_log).
--    Completions need no populated_at filter: complete_d100() requires
--    task_name IS NOT NULL, so every recorded completion is post-population
--    by construction (GAP-1 resolution).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION flag_d100_low_completion()
RETURNS TABLE(
    roll integer,
    task_name varchar,
    rolls_since_pop bigint,
    times_completed integer,
    completion_rate numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    WITH rolls_since AS (
        SELECT m.roll, count(*) AS cnt
        FROM motivation_d100 m
        JOIN d100_roll_log r
             ON r.roll = m.roll
            AND r.rolled_at >= m.populated_at
        WHERE m.task_name IS NOT NULL
          AND m.populated_at IS NOT NULL
        GROUP BY m.roll
    )
    SELECT m.roll,
           m.task_name,
           rs.cnt,
           m.times_completed,
           round((m.times_completed::numeric / rs.cnt) * 100, 2)
    FROM motivation_d100 m
    JOIN rolls_since rs ON rs.roll = m.roll
    WHERE rs.cnt >= 10
      AND (m.times_completed::numeric / rs.cnt) < 0.6
    ORDER BY m.roll;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Update workflow 27 step 11 text to branch on is_populate_me.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM workflow_steps
        WHERE workflow_id = 27
          AND step_order = 11
          AND description NOT LIKE '%is_populate_me%'
    ) THEN
        UPDATE workflow_steps
        SET description = E'## Random D100 Task\n\n**Gate:** Review whether this proactive session accomplished meaningful work in the preceding steps. If substantive work was completed (maintenance runs with real cleanup, task progress, entity merges, research, etc.), this step may be skipped. If the session was mostly skipped gates and cooldowns with no real output, roll the D100 — it exists to guarantee something creative or productive happens even when everything else is blocked.\n\nUse the `roll_d100()` database function to get a random task:\n\n```sql\nSELECT * FROM roll_d100();\n```\n\nThe result includes an `is_populate_me boolean` column. Branch on it:\n\n- **If `is_populate_me = true`**: the rolled slot is empty and unreserved. The task is to **invent new content for this slot and execute it**. Populate the slot with a clear `task_name` and `task_description` via a direct UPDATE, then do the work, and finally mark it complete:\n  ```sql\n  UPDATE motivation_d100 SET task_name = ''My new task'', task_description = ''...'' WHERE roll = <roll_number>;\n  -- execute the task --\n  SELECT complete_d100(<roll_number>);\n  ```\n\n- **If `is_populate_me = false`**: a normal populated+enabled task was rolled. Execute it, then mark it complete:\n  ```sql\n  SELECT complete_d100(<roll_number>);\n  ```\n\nBoth functions are SECURITY DEFINER — they are the only way to update tracking columns (`times_rolled`, `times_completed`, `last_rolled`, `last_completed`). Content columns remain directly editable for maintenance.\n\nTrack activity in `memory/heartbeat-state.json` to avoid redundant tasks.\n\n---\n\n**Step reporting requirement:** After completing this step (whether work was performed or the step was skipped via gate check), post a concise summary of the step''s outcome to Discord <#1504054635231445112> (#proactive-mode). Include: step number/name, action taken or reason skipped, and any notable findings. Keep it brief — one short paragraph or a few bullets.'
        WHERE workflow_id = 27 AND step_order = 11;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 9. Grant nova direct SELECT/UPDATE on d100_roll_log for the announcer.
--    This closes a pre-existing privilege gap from issue #432; the announcer
--    script runs as nova and needs to claim/unstamp rows directly.
-- ---------------------------------------------------------------------------
REVOKE DELETE, INSERT ON TABLE d100_roll_log FROM nova;
GRANT SELECT, UPDATE ON TABLE d100_roll_log TO nova;
