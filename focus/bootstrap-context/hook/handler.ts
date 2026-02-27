/**
 * Database Bootstrap Context Hook
 * 
 * Intercepts agent:bootstrap event to load context from database
 * instead of (or in addition to) filesystem files.
 * 
 * Falls back to static files if database unavailable.
 */

import { readFile } from 'fs/promises';
import pg from 'pg';
import { join } from 'path';
import { homedir } from 'os';

// Load PG env vars from postgres.json before creating Pool
// See: https://github.com/NOVA-Openclaw/nova-memory/issues/136
const pgEnvPath = join(homedir(), '.openclaw', 'lib', 'pg-env.ts');
try {
  const { loadPgEnv } = await import(pgEnvPath);
  loadPgEnv();
} catch (e) {
  console.warn('[bootstrap-context] Could not load pg-env.ts:', (e as Error).message);
}

const { Pool } = pg;

// Create connection pool (reused across invocations)
const pool = new Pool({
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432'),
  database: process.env.PGDATABASE || 'nova_memory',
  user: process.env.PGUSER || 'nova',
  password: process.env.PGPASSWORD,
  max: 5,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

interface BootstrapFile {
  path: string;
  content: string;
}

const FALLBACK_DIR = join(homedir(), '.openclaw', 'bootstrap-fallback');

/**
 * Query database for agent bootstrap context
 */
async function loadFromDatabase(agentName: string): Promise<BootstrapFile[]> {
  let client;
  try {
    client = await pool.connect();
    const result = await client.query(
      'SELECT * FROM get_agent_bootstrap($1)',
      [agentName]
    );
    
    return result.rows.map((row: any) => ({
      path: `db:${row.source}/${row.filename}`,
      content: row.content
    }));
  } catch (error) {
    // Gracefully handle database unavailability
    if ((error as any).code === 'ECONNREFUSED') {
      console.warn('[bootstrap-context] Database connection refused - falling back to static files');
    } else if ((error as any).code === '42883') {
      console.warn('[bootstrap-context] Function get_agent_bootstrap not found - database schema may need updating');
    } else {
      console.error('[bootstrap-context] Database query failed:', error);
    }
    return [];
  } finally {
    if (client) {
      client.release();
    }
  }
}

/**
 * Load fallback files from ~/.openclaw/bootstrap-fallback/
 */
async function loadFallbackFiles(agentName: string): Promise<BootstrapFile[]> {
  const fallbackFiles = [
    'UNIVERSAL_SEED.md',
    'AGENTS.md',
    'SOUL.md',
    'TOOLS.md',
    'IDENTITY.md',
    'USER.md',
    'HEARTBEAT.md'
  ];
  
  const files: BootstrapFile[] = [];
  
  for (const filename of fallbackFiles) {
    try {
      const content = await readFile(join(FALLBACK_DIR, filename), 'utf-8');
      files.push({
        path: `fallback:${filename}`,
        content
      });
    } catch (error) {
      // File doesn't exist or can't be read, skip it
      console.warn(`[bootstrap-context] Fallback file not found: ${filename}`);
    }
  }
  
  return files;
}

/**
 * Emergency minimal context if everything else fails
 */
function getEmergencyContext(): BootstrapFile[] {
  return [{
    path: 'emergency:RECOVERY.md',
    content: `# EMERGENCY BOOTSTRAP CONTEXT

⚠️ **System Status: Degraded**

Your bootstrap context system is not functioning properly.

## What Happened

- Database bootstrap query failed
- Fallback files not available
- Loading minimal emergency context

## Recovery Steps

1. Check database connection
2. Verify agent_bootstrap_context table exists:
   \`\`\`sql
   SELECT * FROM get_agent_bootstrap('your_agent_name');
   \`\`\`
3. Check fallback directory: ~/.openclaw/bootstrap-fallback/
4. Contact Newhart (NHR Agent) for assistance

## Temporary Context

You are an AI agent in the NOVA system. Your full context could not be loaded.
Operate in safe mode until context is restored.

**Database:** nova_memory
**Table:** agent_bootstrap_context
**Hook:** ~/.openclaw/hooks/db-bootstrap-context/
`
  }];
}

/**
 * Main hook handler
 * 
 * Receives an InternalHookEvent from OpenClaw with shape:
 *   { type, action, sessionKey, context: { agentId, bootstrapFiles, ... } }
 */
export default async function handler(event: Record<string, any>) {
  const agentName = (event as any).context?.agentId;
  if (!agentName) {
    console.error('[bootstrap-context] No agentId in event.context — cannot look up bootstrap context');
    return;
  }
  
  console.log(`[bootstrap-context] Loading context for agent: ${agentName}`);
  
  // Try database first
  let files = await loadFromDatabase(agentName);
  
  if (files.length === 0) {
    console.warn('[bootstrap-context] No database context, trying fallback files...');
    files = await loadFallbackFiles(agentName);
  }
  
  if (files.length === 0) {
    console.error('[bootstrap-context] No fallback files, using emergency context');
    files = getEmergencyContext();
  }
  
  // Replace the default bootstrapFiles with our database/fallback content
  event.context.bootstrapFiles = files;
  
  console.log(`[bootstrap-context] Loaded ${files.length} context files for ${agentName}`);
}
