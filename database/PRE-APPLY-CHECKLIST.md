# Pre-Apply Checklist — pgschema Schema Migrations

Created from SE #866 canary rollout (2026-09-21, newhart gateway).
These are **pre-existing data state issues**, not schema bugs. Each gateway may hit a different subset depending on its data history. **Check before blind-applying.**

---

## 1. pg_trgm Extension (pgschema temp schema)

**Symptom:** `operator class "gin_trgm_ops" does not exist for access method "gin"`

**Cause:** `pg_trgm` exists in the live DB but pgschema's temp planning schema doesn't inherit it.

**Fix:** Use `--plan-db` flags pointing at the live DB:
```bash
pgschema plan \
  --host /var/run/postgresql --port 5432 --db <DB> --user <USER> \
  --schema public --file database/schema.sql \
  --plan-host /var/run/postgresql --plan-port 5432 --plan-db <DB> --plan-user <USER> \
  --output-json plan.json
```

---

## 2. agent_bootstrap_context VIEW Trigger Dependencies

**Symptom:** `cannot drop function bootstrap_context_view_update() because other objects depend on it`

**Cause:** The old `agent_bootstrap_context` VIEW has triggers depending on functions the plan tries to DROP. pgschema can't reorder across the dependency.

**Fix:** Manually drop the view before applying:
```sql
DROP VIEW IF EXISTS agent_bootstrap_context CASCADE;
```
Then regenerate the plan (schema fingerprint will have changed).

---

## 3. entity_facts Enum Type Conversion

**Symptom:** `operator does not exist: text = mutability_class_enum` or `text = assertion_intent_enum`

**Cause:** `entity_facts.assertion_intent` and `entity_facts.mutability_class` are `text` columns; the schema expects enum types (`assertion_intent_enum`, `mutability_class_enum`).

**Fix:**
```sql
-- Create enums if not present
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'assertion_intent_enum') THEN
    CREATE TYPE assertion_intent_enum AS ENUM ('asserted','speculative','fictional','disclaimed','hypothetical');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mutability_class_enum') THEN
    CREATE TYPE mutability_class_enum AS ENUM ('immutable','slow_changing','stateful');
  END IF;
END$$;

-- Cast columns
ALTER TABLE entity_facts ALTER COLUMN assertion_intent TYPE assertion_intent_enum USING assertion_intent::assertion_intent_enum;
ALTER TABLE entity_facts ALTER COLUMN mutability_class TYPE mutability_class_enum USING mutability_class::mutability_class_enum;

-- Backfill NULLs (required for NOT NULL check constraints)
UPDATE entity_facts SET assertion_intent = 'asserted' WHERE assertion_intent IS NULL;
UPDATE entity_facts SET mutability_class = 'slow_changing' WHERE mutability_class IS NULL;
```

**Note:** Gateways with clean/recent data may not have NULL rows or text-typed columns. Check before applying — the ALTER will no-op if already enum-typed.

---

## 4. entity_fact_sources New Columns

**Symptom:** `column efs.reporting_distance does not exist`

**Cause:** New views (`v_fact_grades`) reference columns that pgschema tries to create in the same transaction group. The view CREATE runs before the ALTER TABLE ADD COLUMN.

**Fix:**
```sql
ALTER TABLE entity_fact_sources ADD COLUMN IF NOT EXISTS reporting_distance real;
ALTER TABLE entity_fact_sources ADD COLUMN IF NOT EXISTS source_session_id bigint;
ALTER TABLE entity_fact_sources ADD COLUMN IF NOT EXISTS verification_quality real;
```

**⚠️ `source_session_id` is `bigint`** (FK to `channel_sessions.id`), NOT `text`. Getting the type wrong causes a second plan failure on the type cast.

---

## 5. lessons.learned_by Orphan FK References

**Symptom:** `insert or update on table "lessons" violates foreign key constraint "lessons_learned_by_fkey"`

**Cause:** Existing `lessons` rows reference `learned_by` agent IDs that don't exist in the `agents` table (e.g., from before agent ID renumbering).

**Fix:**
```sql
-- Check for orphans first
SELECT l.id, l.learned_by FROM lessons l
LEFT JOIN agents a ON l.learned_by = a.id
WHERE a.id IS NULL AND l.learned_by IS NOT NULL;

-- NULL out orphan refs
UPDATE lessons SET learned_by = NULL
WHERE learned_by IS NOT NULL
  AND learned_by NOT IN (SELECT id FROM agents);
```

---

## Apply Sequence

1. Run `agent-install.sh` (pre-migrations 007+008 run first, installer handles the easy parts)
2. Installer will hit **destructive-skip** on `agent_bootstrap_context_local` DROP — this is expected
3. Work through items 1–5 above as needed (check each, don't blind-apply)
4. Run `pgschema plan` → `pgschema apply` with `--auto-approve`
5. If any group fails, fix the data issue, regenerate the plan (fingerprint changes), re-apply
6. Final verification: `pgschema plan` should report "No changes detected"
7. Verify 3 target tables: `work_queue`, `agent_model_denylists`, `social_interactions`
8. Gateway restart, confirm active / 0 restarts
