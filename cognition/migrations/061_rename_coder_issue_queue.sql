-- Migration 061: Rename coder_issue_queue to git_issue_queue
-- Issue: #89
-- Description: Rename table, sequence, and update all referencing objects

BEGIN;

-- 1. Rename table and sequence
ALTER TABLE coder_issue_queue RENAME TO git_issue_queue;
ALTER SEQUENCE coder_issue_queue_id_seq RENAME TO git_issue_queue_id_seq;

-- 2. Update table comment
COMMENT ON TABLE git_issue_queue IS 'Issue queue for git-based workflows. NOTIFY triggers dispatch work automatically.';

-- 3. Recreate view with new table name
CREATE OR REPLACE VIEW v_pending_test_failures AS
  SELECT id,
     repo,
     title,
     error_message,
     created_at
    FROM git_issue_queue
   WHERE source = 'test_failure'::text AND issue_number < 0
   ORDER BY created_at;

-- 4. Recreate all functions that reference the old table name

CREATE OR REPLACE FUNCTION public.queue_test_failure(p_repo text, p_parent_issue integer, p_test_name text, p_error_message text, p_priority integer DEFAULT 7)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_title TEXT;
  v_issue_number INTEGER;
  v_queue_id INTEGER;
BEGIN
  v_title := 'Test failure: ' || p_test_name;

  v_issue_number := -1 * (SELECT COALESCE(MAX(ABS(issue_number)), 0) + 1
                          FROM git_issue_queue
                          WHERE repo = p_repo AND issue_number < 0);

  INSERT INTO git_issue_queue (
    repo, issue_number, title, priority, status, source,
    parent_issue_id, error_message
  ) VALUES (
    p_repo, v_issue_number, v_title, p_priority, 'pending_tests',
    'test_failure',
    (SELECT id FROM git_issue_queue WHERE repo = p_repo AND issue_number = p_parent_issue),
    p_error_message
  )
  RETURNING id INTO v_queue_id;

  PERFORM pg_notify('test_failure', json_build_object(
    'queue_id', v_queue_id,
    'repo', p_repo,
    'parent_issue', p_parent_issue,
    'test_name', p_test_name,
    'error', LEFT(p_error_message, 500)
  )::text);

  RETURN v_queue_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.queue_test_failure(p_repo text, p_parent_issue integer, p_test_name text, p_error_message text, p_test_file text DEFAULT NULL::text, p_code_files text[] DEFAULT NULL::text[], p_context jsonb DEFAULT '{}'::jsonb, p_priority integer DEFAULT 7)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_title TEXT;
  v_issue_number INTEGER;
  v_queue_id INTEGER;
  v_parent_title TEXT;
  v_full_context JSONB;
  v_semantic_context JSONB;
  v_query_text TEXT;
BEGIN
  v_title := 'Test failure: ' || p_test_name;

  SELECT title INTO v_parent_title
  FROM git_issue_queue
  WHERE repo = p_repo AND issue_number = p_parent_issue;

  v_query_text := p_test_name || ' ' || COALESCE(p_test_file, '') || ' ' || p_error_message;

  SELECT jsonb_agg(jsonb_build_object(
    'source_type', source_type,
    'source_id', source_id,
    'content', LEFT(content, 500),
    'relevance', 'high'
  ))
  INTO v_semantic_context
  FROM (
    SELECT source_type, source_id, content
    FROM memory_embeddings
    WHERE content ILIKE '%' || p_test_name || '%'
       OR content ILIKE '%' || COALESCE(p_test_file, 'NOMATCH') || '%'
    LIMIT 5
  ) relevant;

  v_full_context := p_context || jsonb_build_object(
    'parent_title', v_parent_title,
    'test_file', p_test_file,
    'code_files', p_code_files,
    'queued_at', NOW(),
    'semantic_context', COALESCE(v_semantic_context, '[]'::jsonb)
  );

  v_issue_number := -1 * (SELECT COALESCE(MAX(ABS(issue_number)), 0) + 1
                          FROM git_issue_queue
                          WHERE repo = p_repo AND issue_number < 0);

  INSERT INTO git_issue_queue (
    repo, issue_number, title, priority, status, source,
    parent_issue_id, error_message, test_file, code_files, context
  ) VALUES (
    p_repo, v_issue_number, v_title, p_priority, 'pending_tests',
    'test_failure',
    (SELECT id FROM git_issue_queue WHERE repo = p_repo AND issue_number = p_parent_issue),
    p_error_message, p_test_file, p_code_files, v_full_context
  )
  RETURNING id INTO v_queue_id;

  PERFORM pg_notify('test_failure', json_build_object(
    'queue_id', v_queue_id,
    'repo', p_repo,
    'parent_issue', p_parent_issue,
    'parent_title', v_parent_title,
    'test_name', p_test_name,
    'test_file', p_test_file,
    'code_files', p_code_files,
    'error', LEFT(p_error_message, 1000),
    'context', v_full_context
  )::text);

  RETURN v_queue_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.link_github_issue(p_queue_id integer, p_github_issue integer)
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE git_issue_queue
  SET issue_number = p_github_issue
  WHERE id = p_queue_id;
$function$;

CREATE OR REPLACE FUNCTION public.claim_coder_issue(issue_id integer)
 RETURNS boolean
 LANGUAGE sql
AS $function$
  UPDATE git_issue_queue
  SET status = 'implementing', started_at = NOW()
  WHERE id = issue_id AND status = 'tests_approved'
  RETURNING TRUE;
$function$;

CREATE OR REPLACE FUNCTION public.get_next_coder_issue()
 RETURNS TABLE(id integer, repo text, issue_number integer, title text)
 LANGUAGE sql
AS $function$
  SELECT id, repo, issue_number, title
  FROM git_issue_queue
  WHERE status = 'tests_approved'
    AND NOT should_skip_issue(COALESCE(labels, '{}'))
  ORDER BY priority DESC, created_at
  LIMIT 1;
$function$;

-- 5. Update agents.bootstrap_context for workflow-pm
UPDATE agents
SET bootstrap_context = regexp_replace(bootstrap_context::text, 'coder_issue_queue', 'git_issue_queue', 'g')::jsonb
WHERE name = 'workflow-pm';

-- 6. Update workflow_steps description for step 28
UPDATE workflow_steps
SET description = regexp_replace(description, 'coder_issue_queue', 'git_issue_queue', 'g')
WHERE id = 28;

-- Rename indexes (ALTER TABLE RENAME doesn't auto-rename these)
ALTER INDEX coder_issue_queue_pkey RENAME TO git_issue_queue_pkey;
ALTER INDEX coder_issue_queue_repo_issue_number_key RENAME TO git_issue_queue_repo_issue_number_key;
ALTER INDEX idx_coder_queue_status RENAME TO idx_git_queue_status;
ALTER INDEX idx_coder_queue_priority RENAME TO idx_git_queue_priority;

COMMIT;
