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
 * Result from a database bootstrap attempt.
 * - ok=true:  query succeeded (files may be empty if something is wrong)
 * - ok=false: query failed (connection error, missing function, etc.)
 */
interface DbResult {
  ok: boolean;
  files: BootstrapFile[];
}

/**
 * Query database for agent bootstrap context.
 *
 * Returns { ok, files } so the caller can distinguish "DB call succeeded
 * but returned zero rows" from "DB call failed".  The fallback decision
 * is per-call (did the query succeed?), never per-file.
 */
async function loadFromDatabase(agentName: string): Promise<DbResult> {
  let client;
  try {
    client = await pool.connect();
    const result = await client.query(
      'SELECT * FROM get_agent_bootstrap($1)',
      [agentName]
    );
    
    const files = result.rows.map((row: any) => ({
      path: `db:${row.source}/${row.filename}`,
      content: row.content
    }));
    return { ok: true, files };
  } catch (error) {
    // Gracefully handle database unavailability
    if ((error as any).code === 'ECONNREFUSED') {
      console.warn('[bootstrap-context] Database connection refused - falling back to static files');
    } else if ((error as any).code === '42883') {
      console.warn('[bootstrap-context] Function get_agent_bootstrap not found - database schema may need updating');
    } else {
      console.error('[bootstrap-context] Database query failed:', error);
    }
    return { ok: false, files: [] };
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
  
  // Fallback decision is per-call, not per-file: if the DB query succeeds
  // we use exactly what it returns.  Zero rows from a successful call is
  // also treated as failure — every agent should get UNIVERSAL + GLOBAL.
  const dbResult = await loadFromDatabase(agentName);
  let files: BootstrapFile[];
  
  if (dbResult.ok && dbResult.files.length > 0) {
    // DB call succeeded and returned content — use as-is
    files = dbResult.files;
  } else {
    if (dbResult.ok) {
      console.error(`[bootstrap-context] DB query succeeded but returned 0 rows for '${agentName}' — expected at least UNIVERSAL/GLOBAL records. Falling back.`);
    } else {
      console.warn(`[bootstrap-context] DB query failed for '${agentName}', trying fallback files...`);
    }
    files = await loadFallbackFiles(agentName);
    
    if (files.length === 0) {
      console.error('[bootstrap-context] No fallback files, using emergency context');
      files = getEmergencyContext();
    }
  }
  
  // Wholesale replacement — no per-file mixing with workspace files
  event.context.bootstrapFiles = files;
  
  const source = dbResult.ok && dbResult.files.length > 0 ? 'database' : 'fallback';
  console.log(`[bootstrap-context] Loaded ${files.length} context files for ${agentName} (source: ${source})`);
}
