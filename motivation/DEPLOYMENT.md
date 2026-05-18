# NOVA Motivation System - Deployment Guide

This document provides instructions for setting up and deploying the NOVA Motivation System.

## Prerequisites

### System Requirements
- Node.js v18+ or Python 3.9+
- PostgreSQL 13+
- OpenClaw agent framework
- Access to subagent spawning capabilities

### Dependencies
```bash
# Core dependencies
npm install pg uuid date-fns

# Or for Python
pip install psycopg2-binary sqlalchemy fastapi
```

### Database Access
- Existing nova-memory database
- Write permissions for schema modifications
- Connection string: `postgresql://user:pass@host:port/nova_db`

## Database Setup

### 1. Create Tables

Run the following SQL to set up the required tables:

```sql
-- Enhanced task tracking
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS blocked BOOLEAN DEFAULT false;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS blocked_reason TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS blocked_on INTEGER REFERENCES entities(id);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS last_worked_at TIMESTAMPTZ;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS work_notes TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS estimated_minutes INTEGER;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS actual_minutes INTEGER DEFAULT 0;

-- Channel activity tracking
CREATE TABLE IF NOT EXISTS channel_activity (
    channel VARCHAR(50) PRIMARY KEY,
    last_message_at TIMESTAMPTZ DEFAULT NOW(),
    last_message_from VARCHAR(100),
    idle_threshold_minutes INTEGER DEFAULT 5,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unsolved problems tracking
CREATE TABLE IF NOT EXISTS unsolved_problems (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    category VARCHAR(100), -- mathematics, science, philosophy, technology
    description TEXT,
    source_url TEXT,
    difficulty VARCHAR(50), -- tractable, challenging, millennium-prize, speculative
    status VARCHAR(50) DEFAULT 'unexplored',
    
    -- Work tracking
    total_time_spent_minutes INTEGER DEFAULT 0,
    last_worked_at TIMESTAMPTZ,
    work_sessions INTEGER DEFAULT 0,
    
    -- Progress tracking
    current_approach TEXT,
    progress_notes TEXT,
    key_insights TEXT[],
    blockers TEXT,
    next_steps TEXT,
    
    -- Collaboration tracking
    subagents_used TEXT[], -- ['scout', 'coder', 'analyst']
    external_resources TEXT[], -- URLs, papers, tools used
    
    -- Metadata
    added_at TIMESTAMPTZ DEFAULT NOW(),
    added_by VARCHAR(100) DEFAULT 'NOVA',
    priority INTEGER DEFAULT 5 CHECK (priority >= 1 AND priority <= 10),
    last_priority_update TIMESTAMPTZ DEFAULT NOW()
);

-- Detailed work session logs
CREATE TABLE IF NOT EXISTS problem_work_sessions (
    id SERIAL PRIMARY KEY,
    problem_id INTEGER REFERENCES unsolved_problems(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_minutes INTEGER,
    approach_used TEXT,
    work_done TEXT,
    insights_gained TEXT[],
    new_questions TEXT[],
    subagents_spawned TEXT[],
    session_notes TEXT,
    interrupted_by VARCHAR(100) -- 'user_message', 'time_limit', 'completion', etc.
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_tasks_workable ON tasks (status, blocked, priority) WHERE status = 'pending' AND blocked = false;
CREATE INDEX IF NOT EXISTS idx_problems_selection ON unsolved_problems (priority, last_worked_at, status);
CREATE INDEX IF NOT EXISTS idx_work_sessions_problem ON problem_work_sessions (problem_id, started_at);
CREATE INDEX IF NOT EXISTS idx_channel_activity_recent ON channel_activity (last_message_at);
```

### 2. Seed Initial Problems

```sql
-- Insert the initial set of unsolved problems
INSERT INTO unsolved_problems (name, category, description, difficulty, priority, source_url) VALUES
('P vs NP Problem', 'mathematics', 'Whether every problem whose solution can be quickly verified can also be quickly solved', 'millennium-prize', 9, 'https://www.claymath.org/millennium-problems/p-vs-np-problem'),

('AI Alignment Problem', 'technology', 'How to ensure advanced AI systems are aligned with human values and goals', 'challenging', 10, 'https://www.alignmentforum.org/'),

('Climate Change Mitigation', 'science', 'Developing effective strategies to reduce greenhouse gas emissions and limit global warming', 'challenging', 10, 'https://www.ipcc.ch/'),

('Hard Problem of Consciousness', 'philosophy', 'Why and how physical processes give rise to subjective conscious experience', 'speculative', 8, 'https://plato.stanford.edu/entries/consciousness/'),

('Aging and Longevity', 'science', 'Understanding and potentially reversing the biological mechanisms of aging', 'challenging', 9, 'https://www.nia.nih.gov/'),

('Unified Field Theory', 'science', 'A theoretical framework that unifies all fundamental forces in physics', 'speculative', 7, 'https://www.britannica.com/science/unified-field-theory'),

('Riemann Hypothesis', 'mathematics', 'The hypothesis about the zeros of the Riemann zeta function', 'millennium-prize', 6, 'https://www.claymath.org/millennium-problems/riemann-hypothesis'),

('Protein Folding Prediction', 'science', 'Predicting how proteins fold into their three-dimensional structures', 'tractable', 8, 'https://deepmind.com/research/alphafold/')

ON CONFLICT (name) DO UPDATE SET 
    category = EXCLUDED.category,
    description = EXCLUDED.description,
    difficulty = EXCLUDED.difficulty,
    priority = EXCLUDED.priority,
    source_url = EXCLUDED.source_url;
```

### 3. Initialize Channel Tracking

```sql
-- Set up initial channel monitoring (adjust for your channels)
INSERT INTO channel_activity (channel, idle_threshold_minutes) VALUES
('signal', 5),
('discord', 10),
('email', 30),
('internal', 5)
ON CONFLICT (channel) DO NOTHING;
```

## Configuration

### Environment Variables

Create a `.env` file or set environment variables:

```bash
# Database connection
DATABASE_URL=postgresql://username:password@localhost:5432/nova_db

# Motivation system settings
MOTIVATION_ENABLED=true
MOTIVATION_IDLE_THRESHOLD_MINUTES=5
MOTIVATION_PROACTIVE_CHECK_INTERVAL=60
MOTIVATION_PROBLEM_SESSION_MINUTES=3
MOTIVATION_MAX_DAILY_PROBLEM_HOURS=4
MOTIVATION_MAX_CONCURRENT_SUBAGENTS=3

# Problem selection preferences
MOTIVATION_PROBLEM_ROTATION_STRATEGY=weighted_random
MOTIVATION_PRIORITY_DECAY_DAYS=7
MOTIVATION_MIN_BREAK_BETWEEN_SESSIONS=60

# Subagent configuration
SUBAGENT_SCOUT_ENABLED=true
SUBAGENT_CODER_ENABLED=true
SUBAGENT_ANALYST_ENABLED=true
SUBAGENT_WRITER_ENABLED=true

# Logging and debugging
MOTIVATION_LOG_LEVEL=info
MOTIVATION_DEBUG_MODE=false
```

### Configuration File

Create `config/motivation.json`:

```json
{
  "channels": {
    "signal": { 
      "idleThresholdMinutes": 5, 
      "priority": 1,
      "enabled": true
    },
    "discord": { 
      "idleThresholdMinutes": 10, 
      "priority": 2,
      "enabled": true
    },
    "email": { 
      "idleThresholdMinutes": 30, 
      "priority": 3,
      "enabled": true
    }
  },
  "problemWork": {
    "sessionMinutes": 3,
    "maxDailyHours": 4,
    "rotationStrategy": "weighted_random",
    "maxConcurrentSubagents": 3,
    "cooldownMinutes": 60
  },
  "taskWork": {
    "maxSessionMinutes": 30,
    "timeboxed": true,
    "notifyOnBlocked": true
  },
  "priorities": {
    "userTasks": 10,
    "maintenance": 5,
    "unsolvedProblems": 3
  }
}
```

## Integration with OpenClaw

### 1. Hook into Message Processing

```javascript
// In your OpenClaw agent's message handler
const motivationSystem = new MotivationSystem();

async function handleMessage(channel, message, sender) {
  // Update activity tracking
  motivationSystem.updateChannelActivity(channel, new Date());
  
  // Process message normally
  const response = await processMessage(message);
  
  // Check if we should pause proactive work
  if (motivationSystem.isInProactiveMode()) {
    await motivationSystem.pauseProactiveWork();
  }
  
  return response;
}
```

### 2. Start the Motivation Loop

```javascript
// Initialize and start the motivation system
const motivationSystem = new MotivationSystem({
  database: {
    connectionString: process.env.DATABASE_URL
  },
  channels: ['signal', 'discord', 'email'],
  config: require('./config/motivation.json')
});

// Start the main loop
motivationSystem.start();

// Graceful shutdown handling
process.on('SIGTERM', async () => {
  await motivationSystem.stop();
  process.exit(0);
});
```

### 3. Subagent Integration

```javascript
// Configure subagent spawning
motivationSystem.registerSubagent('scout', {
  spawn: async (task) => {
    return await openclawAgent.spawn('scout', {
      task: task,
      timeout: '5m',
      environment: 'research'
    });
  }
});

motivationSystem.registerSubagent('coder', {
  spawn: async (task) => {
    return await openclawAgent.spawn('coder', {
      task: task,
      timeout: '10m',
      environment: 'development'
    });
  }
});
```

## Monitoring and Maintenance

### Health Checks

```bash
#!/bin/bash
# health-check.sh
# Check if motivation system is running properly

echo "Checking motivation system health..."

# Check database connectivity
psql $DATABASE_URL -c "SELECT COUNT(*) FROM unsolved_problems;" > /dev/null
if [ $? -eq 0 ]; then
    echo "✓ Database connection OK"
else
    echo "✗ Database connection failed"
    exit 1
fi

# Check recent activity
RECENT_SESSIONS=$(psql $DATABASE_URL -t -c "SELECT COUNT(*) FROM problem_work_sessions WHERE started_at > NOW() - INTERVAL '24 hours';")
echo "✓ Work sessions in last 24h: $RECENT_SESSIONS"

# Check for stuck sessions
STUCK_SESSIONS=$(psql $DATABASE_URL -t -c "SELECT COUNT(*) FROM problem_work_sessions WHERE ended_at IS NULL AND started_at < NOW() - INTERVAL '1 hour';")
if [ $STUCK_SESSIONS -gt 0 ]; then
    echo "⚠ Found $STUCK_SESSIONS stuck sessions"
else
    echo "✓ No stuck sessions"
fi
```

### Log Monitoring

```bash
# Monitor motivation system logs
tail -f /var/log/nova/motivation.log | grep -E "(ERROR|WARN|SESSION_START|SESSION_END)"

# Alert on errors
tail -f /var/log/nova/motivation.log | grep "ERROR" | \
while read line; do
  echo "ALERT: $line" | mail -s "Motivation System Error" admin@example.com
done
```

### Performance Metrics

```sql
-- Daily work summary
SELECT 
    DATE(started_at) as work_date,
    COUNT(*) as sessions,
    SUM(duration_minutes) as total_minutes,
    COUNT(DISTINCT problem_id) as problems_worked
FROM problem_work_sessions 
WHERE started_at > CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(started_at)
ORDER BY work_date DESC;

-- Top problems by time investment
SELECT 
    p.name,
    p.category,
    p.total_time_spent_minutes,
    p.work_sessions,
    p.status
FROM unsolved_problems p
ORDER BY p.total_time_spent_minutes DESC
LIMIT 10;

-- Subagent usage statistics
SELECT 
    unnest(subagents_spawned) as subagent_type,
    COUNT(*) as spawn_count
FROM problem_work_sessions 
WHERE started_at > CURRENT_DATE - INTERVAL '30 days'
AND subagents_spawned IS NOT NULL
GROUP BY subagent_type
ORDER BY spawn_count DESC;
```

## Troubleshooting

### Common Issues

**Issue**: Motivation system not starting proactive work
```bash
# Check idle detection
psql $DATABASE_URL -c "SELECT * FROM channel_activity ORDER BY last_message_at DESC;"

# Verify configuration
echo $MOTIVATION_IDLE_THRESHOLD_MINUTES
```

**Issue**: Database connection errors
```bash
# Test connection
psql $DATABASE_URL -c "SELECT 1;"

# Check permissions
psql $DATABASE_URL -c "SELECT current_user, session_user;"
```

**Issue**: Stuck work sessions
```sql
-- Clean up stuck sessions
UPDATE problem_work_sessions 
SET ended_at = started_at + INTERVAL '3 minutes',
    duration_minutes = 3,
    interrupted_by = 'cleanup'
WHERE ended_at IS NULL 
AND started_at < NOW() - INTERVAL '1 hour';
```

### Debugging

Enable debug mode:
```bash
export MOTIVATION_DEBUG_MODE=true
export MOTIVATION_LOG_LEVEL=debug
```

Check specific components:
```javascript
// Test idle detection
console.log(await motivationSystem.getIdleStatus());

// Test problem selection
console.log(await motivationSystem.selectNextProblem());

// Test subagent spawning
const scout = await motivationSystem.spawnSubagent('scout', 'Test task');
```

## Security Considerations

- **Database Security**: Use connection pooling and read-only users where possible
- **Subagent Isolation**: Ensure subagents can't access sensitive data
- **Resource Limits**: Set timeouts and memory limits for all work sessions
- **Audit Trail**: Log all activities for security review
- **Network Access**: Restrict external API calls to approved domains

## Backup and Recovery

```bash
#!/bin/bash
# backup-motivation.sh
# Backup motivation system data

DATE=$(date +%Y-%m-%d)
BACKUP_DIR="/backup/motivation/$DATE"

mkdir -p $BACKUP_DIR

# Backup database tables
pg_dump $DATABASE_URL -t unsolved_problems > $BACKUP_DIR/problems.sql
pg_dump $DATABASE_URL -t problem_work_sessions > $BACKUP_DIR/sessions.sql
pg_dump $DATABASE_URL -t channel_activity > $BACKUP_DIR/channels.sql

# Backup configuration
cp config/motivation.json $BACKUP_DIR/
cp .env $BACKUP_DIR/env.backup

# Compress backup
tar -czf /backup/motivation-$DATE.tar.gz $BACKUP_DIR
```

## Next Steps

1. Deploy with monitoring enabled
2. Start with a subset of problems for testing
3. Monitor performance and adjust timeouts
4. Gradually enable more subagent types
5. Collect metrics and optimize problem selection
6. Scale up based on resource availability

The system is designed to be robust and self-managing, but regular monitoring will help optimize performance and catch issues early.
## Automated Deployment with Notifications

The repository includes an automated deployment script that sends notifications to NOVA on deployment events.

### Quick Start

```bash
# Set Signal recipient (NOVA's number)
export SIGNAL_RECIPIENT="+1234567890"

# Run deployment
./scripts/auto-deploy.sh
```

### Features

- **Automatic notifications**: Sends Signal messages on deployment success/failure
- **Wake events**: Triggers OpenClaw wake events as fallback
- **Deployment markers**: Creates JSON markers for heartbeat checks
- **Error handling**: Comprehensive error tracking and reporting

### Configuration

See `scripts/README.md` for detailed configuration options.

### Integration with GitHub Actions

```yaml
name: Auto-Deploy

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Deploy and notify
        env:
          SIGNAL_RECIPIENT: ${{ secrets.NOVA_SIGNAL_NUMBER }}
        run: ./scripts/auto-deploy.sh
```

For more details, see:
- `scripts/auto-deploy.sh` - Main deployment script
- `scripts/README.md` - Complete documentation
- `scripts/deploy-notify.conf` - Configuration file template
- `tests/TEST-CASES-ISSUE-9.md` - Test cases and requirements
