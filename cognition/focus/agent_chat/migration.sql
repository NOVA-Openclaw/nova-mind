-- Migration Script: agent_chat_processed State Tracking Enhancement
--
-- This script migrates the agent_chat_processed table from the old simple schema
-- (just processed_at) to the new granular state tracking schema.
--
-- BACKUP YOUR DATABASE FIRST!
-- 
-- Usage: psql -d your_database -f migration.sql

\echo '==========================================';
\echo 'Agent Chat: State Tracking Migration';
\echo '==========================================';
\echo '';

-- Step 1: Create the status enum type if it doesn't exist
\echo 'Step 1: Creating status enum type...';
DO $$ BEGIN
    CREATE TYPE agent_chat_status AS ENUM ('received', 'routed', 'responded', 'failed');
    \echo '  ✓ Created agent_chat_status enum';
EXCEPTION
    WHEN duplicate_object THEN 
        \echo '  ℹ Status enum already exists, skipping';
END $$;

-- Step 2: Add new columns to agent_chat_processed
\echo 'Step 2: Adding new columns to agent_chat_processed...';

ALTER TABLE agent_chat_processed 
  ADD COLUMN IF NOT EXISTS status agent_chat_status DEFAULT 'responded';
\echo '  ✓ Added status column';

ALTER TABLE agent_chat_processed
  ADD COLUMN IF NOT EXISTS received_at TIMESTAMP;
\echo '  ✓ Added received_at column';

ALTER TABLE agent_chat_processed
  ADD COLUMN IF NOT EXISTS routed_at TIMESTAMP;
\echo '  ✓ Added routed_at column';

ALTER TABLE agent_chat_processed
  ADD COLUMN IF NOT EXISTS responded_at TIMESTAMP;
\echo '  ✓ Added responded_at column';

ALTER TABLE agent_chat_processed
  ADD COLUMN IF NOT EXISTS error_message TEXT;
\echo '  ✓ Added error_message column';

-- Step 3: Migrate existing data
\echo 'Step 3: Migrating existing data...';

-- For existing records, assume they were fully processed (received, routed, and responded)
-- Set all timestamps to the old processed_at value
DO $$
DECLARE
  rows_updated INTEGER;
BEGIN
  UPDATE agent_chat_processed 
  SET 
    received_at = COALESCE(received_at, processed_at),
    routed_at = COALESCE(routed_at, processed_at),
    responded_at = COALESCE(responded_at, processed_at),
    status = COALESCE(status, 'responded')
  WHERE processed_at IS NOT NULL;
  
  GET DIAGNOSTICS rows_updated = ROW_COUNT;
  RAISE NOTICE '  ✓ Migrated % existing records', rows_updated;
END $$;

-- Step 4: Drop the old processed_at column
\echo 'Step 4: Removing old processed_at column...';
ALTER TABLE agent_chat_processed DROP COLUMN IF EXISTS processed_at;
\echo '  ✓ Dropped processed_at column';

-- Step 5: Create new indexes
\echo 'Step 5: Creating performance indexes...';
CREATE INDEX IF NOT EXISTS idx_agent_chat_processed_status ON agent_chat_processed(status);
\echo '  ✓ Created status index';

-- Step 6: Update constraints
\echo 'Step 6: Updating constraints...';
ALTER TABLE agent_chat_processed 
  ALTER COLUMN received_at SET DEFAULT NOW(),
  ALTER COLUMN received_at SET NOT NULL;
\echo '  ✓ Updated received_at constraints';

-- Step 7: Show migration summary
\echo '';
\echo '==========================================';
\echo 'Migration Summary';
\echo '==========================================';

SELECT 
  agent,
  status,
  COUNT(*) as count
FROM agent_chat_processed
GROUP BY agent, status
ORDER BY agent, status;

\echo '';
\echo '✅ Migration complete!';
\echo '';
\echo 'Next steps:';
\echo '1. Restart the agent-chat-channel plugin';
\echo '2. Test with a new message';
\echo '3. Use monitoring-queries.sql to track message states';
\echo '';
