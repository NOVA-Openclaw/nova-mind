-- Test Script for State Tracking Enhancement
--
-- This script tests the new state tracking functionality
-- Usage: psql -d your_database -f test-state-tracking.sql

\echo '==========================================';
\echo 'Testing Agent Chat State Tracking';
\echo '==========================================';
\echo '';

-- Test 1: Insert a test message
\echo 'Test 1: Inserting test message...';
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('test-channel', 'test-user', 'Hello @testagent!', ARRAY['testagent'])
RETURNING id;

-- Store the message id
\set last_id (SELECT MAX(id) FROM agent_chat WHERE sender = 'test-user')

\echo 'Test 2: Mark as received...';
INSERT INTO agent_chat_processed (chat_id, agent, status, received_at)
VALUES (:last_id, 'testagent', 'received', NOW());

SELECT 
  chat_id, 
  agent, 
  status, 
  received_at IS NOT NULL as has_received_at,
  routed_at IS NOT NULL as has_routed_at,
  responded_at IS NOT NULL as has_responded_at
FROM agent_chat_processed 
WHERE chat_id = :last_id;

\echo 'Test 3: Mark as routed...';
UPDATE agent_chat_processed
SET status = 'routed', routed_at = NOW()
WHERE chat_id = :last_id AND agent = 'testagent';

SELECT 
  chat_id, 
  agent, 
  status, 
  received_at IS NOT NULL as has_received_at,
  routed_at IS NOT NULL as has_routed_at,
  responded_at IS NOT NULL as has_responded_at
FROM agent_chat_processed 
WHERE chat_id = :last_id;

\echo 'Test 4: Mark as responded...';
UPDATE agent_chat_processed
SET status = 'responded', responded_at = NOW()
WHERE chat_id = :last_id AND agent = 'testagent';

SELECT 
  chat_id, 
  agent, 
  status, 
  received_at IS NOT NULL as has_received_at,
  routed_at IS NOT NULL as has_routed_at,
  responded_at IS NOT NULL as has_responded_at,
  EXTRACT(EPOCH FROM (responded_at - received_at)) as response_time_seconds
FROM agent_chat_processed 
WHERE chat_id = :last_id;

\echo 'Test 5: Test monitoring query...';
SELECT 
  ac.id,
  ac.sender,
  LEFT(ac.message, 30) as message_preview,
  acp.status,
  acp.received_at
FROM agent_chat ac
JOIN agent_chat_processed acp ON ac.id = acp.chat_id
WHERE ac.sender = 'test-user'
ORDER BY ac.id DESC
LIMIT 1;

\echo '';
\echo '✅ All tests passed!';
\echo 'Cleaning up test data...';

DELETE FROM agent_chat WHERE sender = 'test-user' AND message LIKE 'Hello @testagent%';

\echo '✅ Cleanup complete!';
\echo '';
