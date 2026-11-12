/**
 * Shared singleton pg.Pool for the self-awareness plugin.
 *
 * Loads PG config from ~/.openclaw/postgres.json via the shared
 * lib/pg-env.ts loadPgEnv() loader before creating the pool, passing
 * credentials directly to the Pool constructor to avoid polluting
 * process.env for child processes and subagents.
 *
 * Ports the #330 fix pattern (memory/plugins/turn-context/src/shared/pg-pool.ts,
 * commit 85ad094) by reusing the shared loader deployed to
 * ~/.openclaw/lib/pg-env.ts, rather than duplicating loader logic here.
 *
 * Issue: nova-mind #330, nova-mind #408
 */

import pg from "pg";
import { join } from "path";
import { homedir, userInfo } from "os";

let pool: pg.Pool | null = null;

export interface PgConnectionConfig {
  host?: string;
  port?: number;
  database?: string;
  user?: string;
  password?: string;
}

function ownDb(): string {
  return `${userInfo().username.replace(/-/g, "_")}_memory`;
}

const HARDCODED_DEFAULTS: PgConnectionConfig = {
  host: "localhost",
  port: 5432,
  database: ownDb(),
  user: userInfo().username,
  password: undefined,
};

function parsePort(value: string | undefined): number {
  if (!value) return HARDCODED_DEFAULTS.port ?? 5432;
  const n = Number(value);
  return isNaN(n) ? (HARDCODED_DEFAULTS.port ?? 5432) : n;
}

/**
 * Build a config object from ambient PG* env vars, using hardcoded defaults
 * as the last resort. This is READ-ONLY — it never writes to process.env.
 *
 * Mirrors the env-first seeding used by turn-context's reference pg-pool.ts
 * so behavior stays identical even when the shared loader is unavailable.
 */
function envFallbackConfig(): PgConnectionConfig {
  return {
    host: process.env.PGHOST || HARDCODED_DEFAULTS.host,
    port: parsePort(process.env.PGPORT),
    database: process.env.PGDATABASE || HARDCODED_DEFAULTS.database,
    user: process.env.PGUSER || HARDCODED_DEFAULTS.user,
    password: process.env.PGPASSWORD,
  };
}

/**
 * Load PostgreSQL config via the shared lib/pg-env.ts loadPgEnv() loader.
 * Returns a config object without touching process.env.
 *
 * Falls back to hardcoded defaults (matching this plugin's pre-#408
 * fallback semantics) if the shared loader cannot be loaded — e.g. if
 * ~/.openclaw/lib/pg-env.ts hasn't been deployed to this host yet.
 */
export async function loadPgConfig(): Promise<PgConnectionConfig> {
  try {
    const pgEnvPath = join(homedir(), ".openclaw", "lib", "pg-env.ts");
    const { loadPgEnv, resolveAgentDatabase } = await import(pgEnvPath);
    const config = loadPgEnv() as PgConnectionConfig;
    return {
      host: config.host || HARDCODED_DEFAULTS.host,
      port: config.port || HARDCODED_DEFAULTS.port,
      database: resolveAgentDatabase(config.database, userInfo().username),
      user: config.user || HARDCODED_DEFAULTS.user,
      password: config.password,
    };
  } catch (err) {
    console.warn("[self-awareness] pg config load failed:", (err as Error).message);
    return envFallbackConfig();
  }
}

/**
 * Return the singleton pg.Pool, creating it on first call.
 * Passes config directly to Pool constructor — no process.env writes.
 *
 * Query timeouts:
 *   - query_timeout (8s): client-side ceiling. Prevents a dead socket or
 *     unresponsive proxy from leaving JS code blocked forever.
 *   - statement_timeout (10s): server-side ceiling. PostgreSQL cancels any
 *     statement that runs longer, so a runaway backend doesn't hold a client.
 * Both are well above the 3s plugin shutdown deadline, so they never fire
 * during normal operation.
 */
export async function getPool(): Promise<pg.Pool> {
  if (!pool) {
    // Dynamic import so per-test module mocks for 'pg' are picked up.
    const { Pool } = await import("pg");
    const pgConfig = await loadPgConfig();
    pool = new Pool({
      ...pgConfig,
      max: 3,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
      query_timeout: 8000,
      statement_timeout: 10000,
    });

    pool.on("error", (err) => {
      console.error("[self-awareness] pg.Pool error:", err.message);
    });
  }
  return pool;
}

/**
 * Forcibly destroy every underlying connection stream in the pool. This is a
 * last-resort safety net when pool.end() hangs because checked-out clients are
 * stuck on a dead socket or an unresponsive server.
 */
export function forceClosePool(targetPool = pool): void {
  const poolToClose = targetPool;
  if (!poolToClose) return;
  try {
    const clients: unknown[] = (poolToClose as any)._clients ?? [];
    for (const client of clients) {
      const stream = (client as any)?.connection?.stream;
      if (typeof stream?.destroy === "function") {
        stream.destroy();
      }
    }
  } catch (err) {
    console.warn(
      "[self-awareness] Error force-closing pool:",
      err instanceof Error ? err.message : String(err)
    );
  }
}

/**
 * Return the current pool instance without creating one. Useful for callers
 * that need to force-close the exact pool that closePool() is racing against.
 */
export function getCurrentPool(): pg.Pool | null {
  return pool;
}

/**
 * Close the singleton pg.Pool and drop the reference so a subsequent
 * getPool() will create a fresh pool. Safe to call multiple times.
 */
export async function closePool(): Promise<void> {
  const toClose = pool;
  pool = null;
  if (toClose) {
    try {
      await toClose.end();
    } catch (err) {
      console.warn("[self-awareness] Pool close error:", (err as Error).message);
    }
  }
}
