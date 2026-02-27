## Test Cases for Issue #97: Add orchestrator_agent_id to workflows table

**Goal:** Ensure Conductor (workflow-pm) receives ALL active workflows in her bootstrap context by adding an `orchestrator_agent_id` column to the `workflows` table and updating `get_agent_bootstrap()`.

**Pre-conditions:**
- Access to the nova-cognition database
- The `workflows`, `agents`, `workflow_steps`, and `agent_bootstrap_context` tables exist
- Migration for issue #97 has been applied
- At least one agent exists with name `'conductor'` (the workflow-pm agent)

---

### 1. Schema: `orchestrator_agent_id` Column Exists

- **Test Steps:**
  ```sql
  SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
  WHERE table_name = 'workflows' AND column_name = 'orchestrator_agent_id';
  ```
- **Expected Results:**
  - Column exists with an integer (or uuid, matching `agents.id`) data type
  - `is_nullable` = `YES` (column should be nullable for workflows without an orchestrator)

### 2. Schema: Foreign Key Constraint

- **Test Steps:**
  ```sql
  SELECT tc.constraint_name, kcu.column_name, ccu.table_name AS references_table, ccu.column_name AS references_column
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
  JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
  WHERE tc.table_name = 'workflows' AND tc.constraint_type = 'FOREIGN KEY'
    AND kcu.column_name = 'orchestrator_agent_id';
  ```
- **Expected Results:**
  - A FK constraint exists referencing `agents(id)`

### 3. Schema: FK Prevents Invalid Agent References

- **Test Steps:**
  ```sql
  UPDATE workflows SET orchestrator_agent_id = -99999 WHERE id = (SELECT id FROM workflows LIMIT 1);
  ```
- **Expected Results:**
  - Query fails with a foreign key violation error
  - No rows are updated

### 4. Data Migration: Existing Workflows Have Orchestrator Set

- **Test Steps:**
  ```sql
  SELECT id, name, orchestrator_agent_id FROM workflows WHERE status = 'active';
  ```
- **Expected Results:**
  - All active workflows have `orchestrator_agent_id` set to Conductor's agent ID (non-NULL)
  - Verify: `SELECT id FROM agents WHERE name = 'conductor';` matches the assigned values

### 5. Bootstrap: Conductor Receives All Active Workflows

- **Test Steps:**
  ```sql
  SELECT filename, source
  FROM get_agent_bootstrap('conductor')
  WHERE source LIKE 'workflow%';
  ```
- **Expected Results:**
  - Returns rows for ALL active workflows (expect 12 based on current data)
  - Each row has `source` like `'workflow:<workflow_name>'`
  - Count matches: `SELECT count(*) FROM workflows WHERE status = 'active';`

### 6. Bootstrap: Conductor Workflow Content Is Correct

- **Test Steps:**
  ```sql
  SELECT filename, content, source
  FROM get_agent_bootstrap('conductor')
  WHERE source LIKE 'workflow%'
  LIMIT 1;
  ```
- **Expected Results:**
  - `filename` = `'WORKFLOW_CONTEXT.md'`
  - `content` contains the workflow name and description (format: `'Workflow: <name>\n\n<description>'`)

### 7. Regression: Step-Assigned Agents Still Get Their Workflows

- **Test Steps:**
  1. Identify an agent assigned to workflow steps:
     ```sql
     SELECT DISTINCT a.name
     FROM workflow_steps ws
     JOIN agents a ON ws.agent_id = a.id
     JOIN workflows w ON ws.workflow_id = w.id
     WHERE w.status = 'active'
     LIMIT 1;
     ```
  2. Query bootstrap for that agent:
     ```sql
     SELECT filename, source
     FROM get_agent_bootstrap('<agent_name_from_step_1>')
     WHERE source LIKE 'workflow%';
     ```
- **Expected Results:**
  - Agent still receives workflow context for workflows they're assigned steps in
  - No workflows are missing compared to before the migration

### 8. Regression: Agents With No Workflow Association Get No Workflows

- **Test Steps:**
  1. Find or create an agent that is neither an orchestrator nor assigned to any workflow step:
     ```sql
     SELECT a.name FROM agents a
     WHERE a.id NOT IN (SELECT DISTINCT agent_id FROM workflow_steps)
       AND a.id NOT IN (SELECT DISTINCT orchestrator_agent_id FROM workflows WHERE orchestrator_agent_id IS NOT NULL)
     LIMIT 1;
     ```
  2. Query bootstrap:
     ```sql
     SELECT filename, source
     FROM get_agent_bootstrap('<agent_name>')
     WHERE source LIKE 'workflow%';
     ```
- **Expected Results:**
  - Returns zero rows for workflow sources

### 9. Edge Case: NULL Orchestrator

- **Test Steps:**
  ```sql
  -- Create a test workflow with NULL orchestrator
  INSERT INTO workflows (name, description, status, orchestrator_agent_id)
  VALUES ('test-null-orch', 'Test workflow', 'active', NULL);

  -- Verify Conductor does NOT receive this workflow via orchestrator path
  SELECT source FROM get_agent_bootstrap('conductor') WHERE source = 'workflow:test-null-orch';

  -- Cleanup
  DELETE FROM workflows WHERE name = 'test-null-orch';
  ```
- **Expected Results:**
  - Workflow with NULL orchestrator is NOT returned for Conductor (unless she's assigned via steps)

### 10. Edge Case: Agent Is Both Orchestrator AND Step Agent

- **Test Steps:**
  1. Find a workflow where Conductor is orchestrator, then also assign her to a step:
     ```sql
     SELECT w.id FROM workflows w
     JOIN agents a ON w.orchestrator_agent_id = a.id
     WHERE a.name = 'conductor' AND w.status = 'active'
     LIMIT 1;
     ```
  2. Temporarily add Conductor as a step agent:
     ```sql
     INSERT INTO workflow_steps (workflow_id, agent_id, step_order, name)
     VALUES (<workflow_id>, (SELECT id FROM agents WHERE name = 'conductor'), 99, 'test-step');
     ```
  3. Query bootstrap:
     ```sql
     SELECT source FROM get_agent_bootstrap('conductor') WHERE source LIKE 'workflow%';
     ```
  4. Cleanup:
     ```sql
     DELETE FROM workflow_steps WHERE name = 'test-step' AND agent_id = (SELECT id FROM agents WHERE name = 'conductor');
     ```
- **Expected Results:**
  - No duplicate workflow entries — each workflow appears exactly once
  - The `DISTINCT ON` logic deduplicates correctly

### 11. Edge Case: Deleted/Nonexistent Orchestrator Agent

- **Test Steps:**
  ```sql
  -- Attempt to set orchestrator to a non-existent agent
  UPDATE workflows SET orchestrator_agent_id = -1 WHERE name = (SELECT name FROM workflows WHERE status = 'active' LIMIT 1);
  ```
- **Expected Results:**
  - FK constraint prevents the update (error raised)
  - If using ON DELETE SET NULL: deleting an agent sets `orchestrator_agent_id` to NULL on their workflows (verify cascade behavior)

### 12. Edge Case: Inactive Workflows Not Returned

- **Test Steps:**
  ```sql
  -- Create an inactive workflow with Conductor as orchestrator
  INSERT INTO workflows (name, description, status, orchestrator_agent_id)
  VALUES ('test-inactive', 'Inactive test', 'inactive', (SELECT id FROM agents WHERE name = 'conductor'));

  SELECT source FROM get_agent_bootstrap('conductor') WHERE source = 'workflow:test-inactive';

  -- Cleanup
  DELETE FROM workflows WHERE name = 'test-inactive';
  ```
- **Expected Results:**
  - Inactive workflow is NOT returned in bootstrap context

### 13. File Sync: `management-functions.sql` Matches Live Function

- **Test Steps:**
  1. Extract the live function definition:
     ```sql
     SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'get_agent_bootstrap';
     ```
  2. Compare with the repo file:
     ```bash
     cat ~/workspace/nova-cognition/focus/bootstrap-context/sql/management-functions.sql
     ```
- **Expected Results:**
  - The `get_agent_bootstrap` function in the repo file matches the live database definition
  - The repo version includes the orchestrator query block (e.g., `WHERE w.orchestrator_agent_id = v_agent_id`)
  - No stale/outdated version in the repo

### 14. File Sync: Migration File Exists

- **Test Steps:**
  ```bash
  ls ~/workspace/nova-cognition/migrations/*097* ~/workspace/nova-cognition/migrations/*orchestrator*
  ```
- **Expected Results:**
  - A migration file exists for this change
  - It includes: `ALTER TABLE workflows ADD COLUMN orchestrator_agent_id`, the FK constraint, and the data migration UPDATE
  - It includes the updated `get_agent_bootstrap` function definition
