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
import { homedir } from "os";

const { Pool } = pg;

let pool: pg.Pool | null = null;

export interface PgConnectionConfig {
  host?: string;
  port?: number;
  database?: string;
  user?: string;
  password?: string;
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
  const defaults: PgConnectionConfig = {
    host: "localhost",
    port: 5432,
    database: "nova_memory",
    user: "nova",
    password: undefined,
  };

  try {
    const pgEnvPath = join(homedir(), ".openclaw", "lib", "pg-env.ts");
    const { loadPgEnv } = await import(pgEnvPath);
    const config = loadPgEnv() as PgConnectionConfig;
    return {
      host: config.host || defaults.host,
      port: config.port || defaults.port,
      database: config.database || defaults.database,
      user: config.user || defaults.user,
      password: config.password,
    };
  } catch (err) {
    console.warn("[self-awareness] pg config load failed:", (err as Error).message);
    return defaults;
  }
}

/**
 * Return the singleton pg.Pool, creating it on first call.
 * Passes config directly to Pool constructor — no process.env writes.
 */
export async function getPool(): Promise<pg.Pool> {
  if (!pool) {
    const pgConfig = await loadPgConfig();
    pool = new Pool({
      ...pgConfig,
      max: 3,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
    });

    pool.on("error", (err) => {
      console.error("[self-awareness] pg.Pool error:", err.message);
    });
  }
  return pool;
}
