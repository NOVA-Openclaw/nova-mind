# NOVA Motivation System - API Reference

This document provides examples and reference for programmatically interacting with the NOVA Motivation System.

## Core API

### MotivationSystem Class

```javascript
const { MotivationSystem } = require('./src/motivation');

const motivation = new MotivationSystem({
  database: {
    connectionString: process.env.DATABASE_URL
  },
  channels: ['signal', 'discord', 'email'],
  config: {
    idleThresholdMinutes: 5,
    problemSessionMinutes: 3,
    maxConcurrentSubagents: 3
  }
});

// Start the system
await motivation.start();

// Stop gracefully
await motivation.stop();
```

### Channel Activity Management

```javascript
// Update activity when message received
motivation.updateChannelActivity('signal', new Date());

// Check if system is idle
const isIdle = await motivation.isIdle();
console.log('System idle:', isIdle);

// Get idle status for all channels
const status = await motivation.getIdleStatus();
/*
{
  signal: { lastActivity: Date, isIdle: false, threshold: 5 },
  discord: { lastActivity: Date, isIdle: true, threshold: 10 },
  overall: false
}
*/
```

### Task Management

```javascript
// Get workable tasks
const tasks = await motivation.getWorkableTasks();

// Start working on a task
const workSession = await motivation.startTaskWork(taskId);

// Mark task as blocked
await motivation.blockTask(taskId, {
  reason: 'waiting_user_input',
  details: 'Need clarification on requirements'
});

// Unblock a task
await motivation.unblockTask(taskId);
```

### Problem Work Management

```javascript
// Get available problems for work
const problems = await motivation.getAvailableProblems();

// Start a problem work session
const session = await motivation.startProblemWork();
/*
{
  sessionId: 'session_123',
  problemId: 42,
  problemName: 'P vs NP Problem',
  maxMinutes: 3,
  startTime: Date
}
*/

// End session with results
await motivation.endProblemSession(session.sessionId, {
  insights: ['New approach to polynomial reductions'],
  questions: ['What about NP-intermediate problems?'],
  nextSteps: 'Explore Ladner\'s theorem implications',
  subagentsUsed: ['scout'],
  workDone: 'Researched recent complexity theory papers'
});
```

### Subagent Collaboration

```javascript
// Register subagent types
motivation.registerSubagent('scout', {
  spawn: async (task, context) => {
    return await openclaw.spawn('scout', {
      task,
      timeout: '5m',
      context: context.problemId
    });
  },
  timeout: 300000 // 5 minutes
});

// Spawn subagent during work session
const scout = await motivation.spawnSubagent('scout', 
  'Research recent papers on protein folding algorithms',
  { problemId: 15 }
);

// Wait for subagent completion
const result = await scout.waitForCompletion();
```

## Database API

### Direct Database Operations

```javascript
const { Database } = require('./src/database');
const db = new Database(process.env.DATABASE_URL);

// Add new problem
const problemId = await db.addProblem({
  name: 'Quantum Gravity',
  category: 'physics',
  description: 'Unifying quantum mechanics with general relativity',
  difficulty: 'speculative',
  priority: 8,
  sourceUrl: 'https://example.com/quantum-gravity'
});

// Update problem progress
await db.updateProblemProgress(problemId, {
  currentApproach: 'Loop quantum gravity',
  progressNotes: 'Exploring discrete spacetime models',
  keyInsights: ['Spacetime might be quantized at Planck scale'],
  blockers: 'Need better mathematical framework'
});

// Get problem work history
const history = await db.getProblemHistory(problemId);
```

### Problem Queries

```javascript
// Get problems by category
const mathProblems = await db.getProblemsBy({ category: 'mathematics' });

// Get problems needing attention (haven't been worked recently)
const staleProblems = await db.getStaleProblems({ 
  hoursThreshold: 24,
  limit: 5 
});

// Get most productive problems (by insights generated)
const productive = await db.getMostProductiveProblems({ limit: 10 });
```

## Event System

### Listening to Events

```javascript
// Listen for work session events
motivation.on('session:start', (session) => {
  console.log(`Started work on: ${session.problemName}`);
});

motivation.on('session:end', (session, results) => {
  console.log(`Completed session: ${results.insights.length} insights`);
});

motivation.on('task:blocked', (task, reason) => {
  console.log(`Task blocked: ${task.title} - ${reason}`);
});

motivation.on('idle:start', (channels) => {
  console.log('Entering proactive mode');
});

motivation.on('idle:end', (channel) => {
  console.log(`Activity detected on ${channel}`);
});
```

### Custom Event Handlers

```javascript
// Custom problem selection logic
motivation.on('problem:select', async (availableProblems) => {
  // Your custom selection algorithm
  const selected = customSelectionAlgorithm(availableProblems);
  return selected;
});

// Custom session timeout handling
motivation.on('session:timeout', async (session) => {
  // Save partial progress before timeout
  await savePartialProgress(session);
});
```

## Configuration API

### Runtime Configuration Updates

```javascript
// Update idle thresholds
await motivation.updateConfig({
  'channels.signal.idleThresholdMinutes': 3,
  'problemWork.sessionMinutes': 5
});

// Get current configuration
const config = motivation.getConfig();
console.log(config.channels.signal.idleThresholdMinutes);

// Reset to defaults
await motivation.resetConfig(['problemWork.sessionMinutes']);
```

### Problem Priority Management

```javascript
// Boost problem priority
await motivation.adjustProblemPriority(problemId, +2);

// Set absolute priority
await motivation.setProblemPriority(problemId, 9);

// Auto-adjust based on recent insights
await motivation.autoAdjustPriorities({
  insightWeight: 0.3,
  timeWeight: 0.2,
  difficultyWeight: 0.5
});
```

## Monitoring API

### System Health

```javascript
// Get system health status
const health = await motivation.getHealthStatus();
/*
{
  status: 'healthy',
  uptime: 3600000,
  activeSession: { problemId: 42, elapsed: 120000 },
  database: { connected: true, latency: 15 },
  subagents: { active: 2, total: 8 },
  lastError: null
}
*/

// Get performance metrics
const metrics = await motivation.getMetrics();
/*
{
  sessionsToday: 15,
  totalTimeToday: 45,
  problemsWorked: 6,
  insightsGenerated: 12,
  subagentsSpawned: 8,
  avgSessionDuration: 3.2
}
*/
```

### Work Analytics

```javascript
// Get productivity trends
const trends = await motivation.getProductivityTrends({ days: 7 });

// Get problem progress summary
const progress = await motivation.getProblemProgressSummary();

// Export work data for analysis
const exportData = await motivation.exportWorkData({
  startDate: '2024-01-01',
  endDate: '2024-01-31',
  format: 'json'
});
```

## Integration Examples

### OpenClaw Integration

```javascript
// Hook into OpenClaw message processing
openclaw.onMessage(async (channel, message, sender) => {
  // Update activity tracking
  motivation.updateChannelActivity(channel, new Date());
  
  // Pause proactive work if active
  if (motivation.isInProactiveMode()) {
    await motivation.pauseProactiveWork();
  }
  
  // Process message normally
  const response = await processMessage(message);
  
  // Resume work after conversation ends
  setTimeout(() => motivation.resumeIfIdle(), 60000);
  
  return response;
});
```

### Custom Subagent Integration

```javascript
// Register custom research agent
motivation.registerSubagent('researcher', {
  spawn: async (task, context) => {
    const agent = await customAgentFramework.create({
      type: 'research',
      capabilities: ['web_search', 'paper_analysis'],
      constraints: {
        maxQueries: 10,
        timeLimit: '10m'
      }
    });
    
    return agent.execute(task);
  }
});

// Register specialized domain experts
motivation.registerSubagent('mathematician', {
  spawn: (task, context) => {
    if (context.problemCategory === 'mathematics') {
      return mathExpertAgent.solve(task);
    }
    throw new Error('Not a mathematics problem');
  }
});
```

### Webhook Integration

```javascript
// External progress notifications
motivation.on('session:end', async (session, results) => {
  if (results.insights.length > 0) {
    await fetch('https://api.slack.com/webhooks/your-hook', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: `🧠 New insights on ${session.problemName}: ${results.insights[0]}`
      })
    });
  }
});

// Integration with external task managers
motivation.on('task:blocked', async (task, reason) => {
  await jiraAPI.createIssue({
    summary: `Blocked: ${task.title}`,
    description: `Task blocked due to: ${reason}`,
    labels: ['motivation-system', 'blocked']
  });
});
```

## Error Handling

### Graceful Error Recovery

```javascript
motivation.on('error', async (error, context) => {
  console.error('Motivation system error:', error);
  
  // Save current state
  await motivation.saveState();
  
  // Attempt recovery based on error type
  switch (error.type) {
    case 'database_connection':
      await motivation.reconnectDatabase();
      break;
    case 'subagent_timeout':
      await motivation.cleanupOrphanedSubagents();
      break;
    case 'session_corruption':
      await motivation.recoverSession(context.sessionId);
      break;
    default:
      await motivation.safeguardRestart();
  }
});
```

### Validation and Constraints

```javascript
// Validate problem data before adding
try {
  await motivation.addProblem({
    name: 'Test Problem',
    category: 'invalid_category' // Will throw validation error
  });
} catch (error) {
  if (error.code === 'VALIDATION_ERROR') {
    console.log('Valid categories:', error.validCategories);
  }
}

// Set resource limits
motivation.setConstraints({
  maxMemoryUsage: '1GB',
  maxConcurrentSessions: 1,
  maxSubagentsPerSession: 5,
  maxDailyWorkHours: 8
});
```

This API provides comprehensive control over the Motivation System while maintaining safety and performance constraints.