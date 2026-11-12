/**
 * Shared singleton pg.Pool for the turn-context plugin.
 *
 * Loads PG config from ~/.openclaw/postgres.json before creating the pool,
 * passing credentials directly to the Pool constructor to avoid polluting
 * process.env for child processes and subagents.
 *
 * Issue: nova-mind #182, nova-mind #330
 */

import type pg from "pg";
import { join } from "path";
import { homedir, userInfo } from "os";
import { existsSync, readFileSync } from "fs";

let pool: pg.Pool | null = null;

interface PgConnectionConfig {
  host?: string;
  port?: number;
  database?: string;
  user?: string;
  password?: string;
}

/**
 * Read PostgreSQL config from ~/.openclaw/postgres.json.
 * Returns a config object without touching process.env.
 */
function loadPgConfig(): PgConnectionConfig {
  // Canonical fallback DB is <os_user>_memory (nova-mind #775, #778). This file
  // inlines the rule because loadPgConfig is synchronous; lib/pg-env.ts
  // resolveAgentDatabase() is the shared source of truth for async TS code.
  const osUser = userInfo().username;
  const result: PgConnectionConfig = {
    host: process.env.PGHOST || "localhost",
    port: parseInt(process.env.PGPORT || "5432"),
    database: process.env.PGDATABASE || `${osUser.replace(/-/g, "_")}_memory`,
    user: process.env.PGUSER || osUser,
    password: process.env.PGPASSWORD,
  };

  try {
    const pgConfigPath = join(homedir(), ".openclaw", "postgres.json");
    if (existsSync(pgConfigPath)) {
      const config = JSON.parse(readFileSync(pgConfigPath, "utf-8"));
      // Config file values only applied when ENV vars are absent (empty = unset)
      if (!process.env.PGHOST && config.host) result.host = config.host;
      if (!process.env.PGPORT && config.port) result.port = Number(config.port);
      if (!process.env.PGDATABASE && config.database) result.database = config.database;
      if (!process.env.PGUSER && config.user) result.user = config.user;
      if (!process.env.PGPASSWORD && config.password) result.password = config.password;
    }
  } catch (err) {
    console.warn("[turn-context] pg config load failed:", (err as Error).message);
  }

  return result;
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
    const pgConfig = loadPgConfig();
    pool = new Pool({
      ...pgConfig,
      max: 5,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
      query_timeout: 8000,
      statement_timeout: 10000,
    });

    pool.on("error", (err) => {
      console.error("[turn-context] pg.Pool error:", err.message);
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
      "[turn-context] Error force-closing pool:",
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
      console.warn("[turn-context] Pool close error:", (err as Error).message);
    }
  }
}
