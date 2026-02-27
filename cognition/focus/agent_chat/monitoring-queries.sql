-- Monitoring Queries for Agent Chat Channel Plugin
-- 
-- Use these queries to track message processing states and identify issues

-- ===========================================
-- Find messages stuck in 'routed' (no response)
-- ===========================================
-- These are messages that were sent to the agent but never got a reply
SELECT 
  ac.id,
  ac.channel,
  ac.sender,
  LEFT(ac.message, 60) AS message_preview,
  acp.agent,
  acp.status,
  acp.received_at,
  acp.routed_at,
  NOW() - acp.routed_at AS time_since_routed
FROM agent_chat ac
JOIN agent_chat_processed acp ON ac.id = acp.chat_id
WHERE acp.status = 'routed'
  AND acp.routed_at < NOW() - INTERVAL '5 minutes'
ORDER BY acp.routed_at DESC;

-- ===========================================
-- Response time statistics per agent
-- ===========================================
-- Shows average, min, max response times for responded messages
SELECT 
  agent,
  COUNT(*) as total_responses,
  ROUND(AVG(EXTRACT(EPOCH FROM (responded_at - received_at)))::numeric, 2) as avg_response_seconds,
  ROUND(MIN(EXTRACT(EPOCH FROM (responded_at - received_at)))::numeric, 2) as min_response_seconds,
  ROUND(MAX(EXTRACT(EPOCH FROM (responded_at - received_at)))::numeric, 2) as max_response_seconds,
  ROUND(AVG(EXTRACT(EPOCH FROM (routed_at - received_at)))::numeric, 2) as avg_routing_seconds
FROM agent_chat_processed
WHERE status = 'responded'
  AND responded_at IS NOT NULL
GROUP BY agent;

-- ===========================================
-- Message processing funnel by agent
-- ===========================================
-- Shows breakdown of messages by status for each agent
SELECT 
  agent,
  status,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY agent), 1) as percentage
FROM agent_chat_processed
GROUP BY agent, status
ORDER BY agent, 
  CASE status
    WHEN 'received' THEN 1
    WHEN 'routed' THEN 2
    WHEN 'responded' THEN 3
    WHEN 'failed' THEN 4
  END;

-- ===========================================
-- Recent failed messages with errors
-- ===========================================
SELECT 
  ac.id,
  ac.channel,
  ac.sender,
  LEFT(ac.message, 60) AS message_preview,
  acp.agent,
  acp.received_at,
  acp.error_message
FROM agent_chat ac
JOIN agent_chat_processed acp ON ac.id = acp.chat_id
WHERE acp.status = 'failed'
ORDER BY acp.received_at DESC
LIMIT 20;

-- ===========================================
-- Messages never responded to (all statuses)
-- ===========================================
-- Useful for finding messages the agent completely ignored
SELECT 
  ac.id,
  ac.channel,
  ac.sender,
  LEFT(ac.message, 60) AS message_preview,
  acp.agent,
  acp.status,
  acp.received_at,
  NOW() - acp.received_at AS age
FROM agent_chat ac
JOIN agent_chat_processed acp ON ac.id = acp.chat_id
WHERE acp.responded_at IS NULL
  AND acp.received_at < NOW() - INTERVAL '1 hour'
ORDER BY acp.received_at DESC;

-- ===========================================
-- Activity summary (last 24 hours)
-- ===========================================
SELECT 
  agent,
  COUNT(*) as total_messages,
  SUM(CASE WHEN status = 'received' THEN 1 ELSE 0 END) as received,
  SUM(CASE WHEN status = 'routed' THEN 1 ELSE 0 END) as routed,
  SUM(CASE WHEN status = 'responded' THEN 1 ELSE 0 END) as responded,
  SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed,
  ROUND(100.0 * SUM(CASE WHEN status = 'responded' THEN 1 ELSE 0 END) / COUNT(*), 1) as response_rate
FROM agent_chat_processed
WHERE received_at > NOW() - INTERVAL '24 hours'
GROUP BY agent
ORDER BY total_messages DESC;

-- ===========================================
-- Find conversations (thread view)
-- ===========================================
-- Shows a conversation thread with processing status
WITH RECURSIVE conversation AS (
  SELECT id, channel, sender, message, reply_to, created_at, 0 as depth
  FROM agent_chat
  WHERE id = 123  -- Replace with starting message id
  
  UNION ALL
  
  SELECT ac.id, ac.channel, ac.sender, ac.message, ac.reply_to, ac.created_at, c.depth + 1
  FROM agent_chat ac
  JOIN conversation c ON ac.reply_to = c.id
)
SELECT 
  c.id,
  REPEAT('  ', c.depth) || c.sender AS sender_indented,
  LEFT(c.message, 50) AS message_preview,
  c.created_at,
  acp.status,
  acp.responded_at
FROM conversation c
LEFT JOIN agent_chat_processed acp ON c.id = acp.chat_id
ORDER BY c.created_at;

-- ===========================================
-- Cleanup old processed records (optional)
-- ===========================================
-- Use this to clean up old tracking data (older than 30 days)
-- Uncomment to run:
-- DELETE FROM agent_chat_processed
-- WHERE received_at < NOW() - INTERVAL '30 days';
