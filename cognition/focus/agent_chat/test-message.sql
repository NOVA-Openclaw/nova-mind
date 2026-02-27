-- Test script for sending messages to agents via agent_chat
-- 
-- Connect to your database and run these commands:
-- psql -h localhost -U newhart -d nova_memory

-- 1. Send a simple message to an agent
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('general', 'human_user', 'Hey @newhart, can you help me?', ARRAY['newhart']);

-- 2. Send a message mentioning multiple agents
INSERT INTO agent_chat (channel, sender, message, mentions)
VALUES ('support', 'customer123', 'I need help from @newhart or @assistant2', ARRAY['newhart', 'assistant2']);

-- 3. Reply to a previous message (use actual message ID)
INSERT INTO agent_chat (channel, sender, message, mentions, reply_to)
VALUES ('general', 'human_user', 'Thanks @newhart!', ARRAY['newhart'], 1);

-- 4. Check for unprocessed messages for a specific agent
SELECT ac.id, ac.channel, ac.sender, ac.message, ac.created_at
FROM agent_chat ac
LEFT JOIN agent_chat_processed acp ON ac.id = acp.chat_id AND acp.agent = 'newhart'
WHERE 'newhart' = ANY(ac.mentions)
  AND acp.chat_id IS NULL
ORDER BY ac.created_at ASC;

-- 5. View recent messages and their processed status
SELECT 
    ac.id,
    ac.channel,
    ac.sender,
    ac.message,
    ac.mentions,
    ac.created_at,
    COALESCE(
        array_agg(acp.agent) FILTER (WHERE acp.agent IS NOT NULL),
        '{}'
    ) as processed_by
FROM agent_chat ac
LEFT JOIN agent_chat_processed acp ON ac.id = acp.chat_id
GROUP BY ac.id, ac.channel, ac.sender, ac.message, ac.mentions, ac.created_at
ORDER BY ac.created_at DESC
LIMIT 20;

-- 6. Check if the NOTIFY trigger is working
-- Run this in one session:
LISTEN agent_chat;
-- Then in another session, insert a message and you should see a notification

-- 7. View agent replies
SELECT id, channel, sender, message, reply_to, created_at
FROM agent_chat
WHERE sender IN ('newhart', 'assistant2')  -- your agent names
ORDER BY created_at DESC
LIMIT 10;
