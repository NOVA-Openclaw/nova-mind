-- Test script to validate PR #9 bug fixes
-- Run this after applying the fixes to verify all issues are resolved

\echo '======================================'
\echo 'PR #9 Bug Fixes Validation Tests'
\echo '======================================'
\echo ''

-- Clean slate for testing
TRUNCATE bootstrap_context_universal, bootstrap_context_agents, bootstrap_context_audit CASCADE;

\echo '1. Testing Bug #5 (LOW): Empty file_key should be rejected'
\echo '-----------------------------------------------------------'
-- This should fail with CHECK constraint violation
DO $$
BEGIN
    PERFORM update_universal_context('', 'test content', 'Should fail', 'tester');
    RAISE EXCEPTION 'BUG: Empty file_key was allowed!';
EXCEPTION 
    WHEN check_violation THEN
        RAISE NOTICE '✓ Empty file_key correctly rejected';
    WHEN OTHERS THEN
        RAISE EXCEPTION 'BUG: Wrong error type: %', SQLERRM;
END;
$$;
\echo ''

\echo '2. Testing Bug #4 (LOW): Type mismatch in delete functions'
\echo '-----------------------------------------------------------'
-- Create a test record
SELECT update_universal_context('DELETE_TEST', 'test content', 'Test', 'tester');
-- This should work without type errors
SELECT CASE 
    WHEN delete_universal_context('DELETE_TEST') THEN '✓ delete_universal_context works correctly'
    ELSE 'BUG: delete_universal_context returned false for existing record'
END;
\echo ''

\echo '3. Testing Bug #2 (MEDIUM): max_file_size enforcement'
\echo '------------------------------------------------------'
-- This should fail because content exceeds max_file_size (20000)
DO $$
BEGIN
    PERFORM update_universal_context('TOO_BIG', repeat('x', 25000), 'Should fail', 'tester');
    RAISE EXCEPTION 'BUG: Content exceeding max_file_size was allowed!';
EXCEPTION 
    WHEN OTHERS THEN
        IF SQLERRM LIKE '%exceeds maximum allowed size%' THEN
            RAISE NOTICE '✓ max_file_size correctly enforced';
        ELSE
            RAISE EXCEPTION 'BUG: Wrong error message: %', SQLERRM;
        END IF;
END;
$$;

-- This should succeed (under limit)
SELECT CASE 
    WHEN update_universal_context('OK_SIZE', repeat('x', 15000), 'Should succeed', 'tester') IS NOT NULL 
    THEN '✓ Content under limit is accepted'
    ELSE 'BUG: Valid content was rejected'
END;
\echo ''

\echo '4. Testing Bug #3 (MEDIUM): Duplicate file_key collision'
\echo '---------------------------------------------------------'
-- Create universal and agent-specific context with same file_key
SELECT update_universal_context('TOOLS', 'Universal TOOLS content', 'Universal', 'tester');
SELECT update_agent_context('test_agent', 'TOOLS', 'Agent-specific TOOLS content', 'Agent-specific', 'tester');

-- Query should return only agent-specific version (not both)
SELECT CASE 
    WHEN COUNT(*) = 1 THEN '✓ No duplicate file_key returned'
    ELSE 'BUG: UNION ALL still returning duplicates! Count: ' || COUNT(*)
END
FROM get_agent_bootstrap('test_agent') 
WHERE filename = 'TOOLS.md';

-- Verify it's the agent-specific version (not universal)
SELECT CASE 
    WHEN content = 'Agent-specific TOOLS content' AND source = 'agent' 
    THEN '✓ Agent-specific version correctly overrides universal'
    WHEN content = 'Universal TOOLS content'
    THEN 'BUG: Universal version was returned instead of agent-specific!'
    ELSE 'BUG: Wrong content returned: ' || substring(content, 1, 50)
END
FROM get_agent_bootstrap('test_agent') 
WHERE filename = 'TOOLS.md';
\echo ''

\echo '5. Testing Bug #1 (HIGH): Audit triggers'
\echo '------------------------------------------'
-- Test INSERT audit
SELECT COUNT(*) AS insert_audit_count FROM bootstrap_context_audit WHERE operation = 'INSERT';
SELECT CASE 
    WHEN COUNT(*) >= 3 THEN '✓ INSERT operations are audited (found ' || COUNT(*) || ' records)'
    ELSE 'BUG: INSERT audit records missing! Expected >= 3, found: ' || COUNT(*)
END
FROM bootstrap_context_audit WHERE operation = 'INSERT';

-- Test UPDATE audit
SELECT update_universal_context('OK_SIZE', 'Updated content v2', 'Updated', 'tester2');
SELECT CASE 
    WHEN COUNT(*) >= 1 THEN '✓ UPDATE operations are audited'
    ELSE 'BUG: UPDATE audit records missing!'
END
FROM bootstrap_context_audit WHERE operation = 'UPDATE';

-- Verify audit content capture
SELECT CASE 
    WHEN old_content IS NOT NULL AND new_content IS NOT NULL AND old_content <> new_content
    THEN '✓ Audit captures both old and new content for UPDATE'
    ELSE 'BUG: Audit not capturing content changes correctly'
END
FROM bootstrap_context_audit 
WHERE operation = 'UPDATE' AND table_name = 'bootstrap_context_universal'
LIMIT 1;

-- Test DELETE audit
SELECT update_universal_context('DELETE_ME', 'temp content', 'Temp', 'tester');
SELECT delete_universal_context('DELETE_ME');
SELECT CASE 
    WHEN COUNT(*) >= 1 THEN '✓ DELETE operations are audited'
    ELSE 'BUG: DELETE audit records missing!'
END
FROM bootstrap_context_audit WHERE operation = 'DELETE';
\echo ''

\echo '======================================'
\echo 'Summary: All Fixes Validated'
\echo '======================================'
\echo 'Run this script after installing the fixes to verify correctness.'
\echo 'All tests should show ✓ marks with no BUG messages.'
\echo ''

-- Show audit trail
\echo 'Audit Trail Sample (last 10 operations):'
SELECT 
    operation,
    table_name,
    changed_by,
    changed_at,
    substring(COALESCE(old_content, '(null)'), 1, 30) as old_snippet,
    substring(COALESCE(new_content, '(null)'), 1, 30) as new_snippet
FROM bootstrap_context_audit 
ORDER BY changed_at DESC 
LIMIT 10;
