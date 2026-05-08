/**
 * Database Bootstrap Context Hook
 *
 * Replaces the standard bootstrap pipeline with database-sourced agent context.
 *
 * Behavior:
 *   1. On agent:bootstrap event, query `get_agent_bootstrap(agent_name)` in nova_memory.
 *   2. If the function returns rows, REPLACE event.context.bootstrapFiles entirely
 *      with WorkspaceBootstrapFile objects built from those rows. The disk-based
 *      bootstrap files loaded by core hooks (boot-md / loadWorkspaceBootstrapFiles)
 *      are intentionally discarded — DB context is authoritative when available.
 *   3. If the function fails (DB down, schema error) or returns zero rows, do
 *      NOTHING. Leave event.context.bootstrapFiles as-is so the normal disk flow
 *      remains the bootstrap source. The on-disk files contain the fallback
 *      warnings about degraded state, so we don't need to inject them ourselves.
 *
 * Output shape: { name, path, content, missing } per WorkspaceBootstrapFile contract.
 */

import pg from 'pg';
import { join } from 'path';
import { homedir } from 'os';

// Load PG env vars from postgres.json before creating Pool.
// Must succeed — if it fails, hook can't connect anyway. See nova-memory#136.
const pgEnvPath = join(homedir(), '.openclaw', 'lib', 'pg-env.ts');
const { loadPgEnv } = await import(pgEnvPath);
loadPgEnv();

const { Pool } = pg;

// Connection pool — reused across hook invocations
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

/**
 * Map a DB filename + source to the synthetic file path used in
 * WorkspaceBootstrapFile.path. The downstream pipeline only uses `path` for
 * logging/identification; it doesn't read from disk when content is provided.
 */
function buildSyntheticPath(filename: string, source: string): string {
  // e.g. "db:agent/IDENTITY.md", "db:domain:NOVA Operations/OPERATIONS_PRINCIPLES.md"
  return `db:${source}/${filename}`;
}

/**
 * Query database for agent bootstrap context.
 * Returns an array of rows on success, or null on any error.
 */
async function loadFromDatabase(
  agentName: string,
): Promise<Array<{ filename: string; content: string; source: string }> | null> {
  let client;
  try {
    client = await pool.connect();
    const result = await client.query<{ filename: string; content: string; source: string }>(
      'SELECT filename, content, source FROM get_agent_bootstrap($1)',
      [agentName],
    );
    return result.rows;
  } catch (error) {
    const code = (error as any)?.code;
    if (code === 'ECONNREFUSED') {
      console.warn('[db-bootstrap-context] DB connection refused — falling through to disk bootstrap');
    } else if (code === '42883') {
      console.warn('[db-bootstrap-context] get_agent_bootstrap() not found — falling through to disk bootstrap');
    } else {
      console.error('[db-bootstrap-context] DB query failed:', error);
    }
    return null;
  } finally {
    if (client) client.release();
  }
}

/**
 * Main hook handler.
 *
 * Receives an agent:bootstrap event. Replaces event.context.bootstrapFiles
 * with database content on success; leaves it unchanged on failure (so the
 * normal disk-based bootstrap flow remains in effect).
 */
export default async function handler(event: Record<string, any>) {
  // Only act on agent:bootstrap events. Any other event = no-op.
  if (event?.type !== 'agent' || event?.action !== 'bootstrap') {
    return;
  }

  const ctx = event.context;
  if (!ctx || !Array.isArray(ctx.bootstrapFiles)) {
    // Malformed event — let the normal pipeline handle it.
    return;
  }

  const agentName: string | undefined = ctx.agentId;
  if (!agentName) {
    console.warn('[db-bootstrap-context] No agentId in event.context — falling through to disk bootstrap');
    return;
  }

  console.log(`[db-bootstrap-context] Loading DB context for agent: ${agentName}`);

  const rows = await loadFromDatabase(agentName);

  // DB unavailable or returned an error — do NOT touch bootstrapFiles.
  // The disk-based files (which include their own fallback warnings) remain.
  if (rows === null) {
    console.warn(`[db-bootstrap-context] DB query failed for ${agentName} — disk bootstrap remains in effect`);
    return;
  }

  // DB returned zero rows — also fall through to disk. (Indicates the agent
  // has no bootstrap context configured; disk fallback is the safer default.)
  if (rows.length === 0) {
    console.warn(`[db-bootstrap-context] DB returned 0 rows for ${agentName} — disk bootstrap remains in effect`);
    return;
  }

  // Success path: REPLACE bootstrapFiles entirely with DB-sourced content.
  // Each row becomes a WorkspaceBootstrapFile with the proper shape.
  const files = rows.map((row) => ({
    // The downstream context-engine accepts any string here; the canonical
    // bootstrap-name enum is only enforced for files loaded from disk via
    // loadExtraBootstrapFiles. Workflow/domain files use names outside the
    // enum — that's fine, they pass through as data.
    name: row.filename,
    path: buildSyntheticPath(row.filename, row.source),
    content: row.content,
    missing: false,
  }));

  ctx.bootstrapFiles = files;

  console.log(
    `[db-bootstrap-context] Replaced bootstrap with ${files.length} DB rows for ${agentName} (sources: ${
      Array.from(new Set(rows.map((r) => r.source.split(':')[0]))).sort().join(', ')
    })`,
  );
}
