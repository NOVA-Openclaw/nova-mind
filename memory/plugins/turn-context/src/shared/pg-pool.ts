/**
 * Shared singleton pg.Pool for the turn-context plugin.
 *
 * Loads PG config from ~/.openclaw/postgres.json before creating the pool,
 * passing credentials directly to the Pool constructor to avoid polluting
 * process.env for child processes and subagents.
 *
 * Issue: nova-mind #182, nova-mind #330
 */

import pg from "pg";
import { join } from "path";
import { homedir, userInfo } from "os";
import { existsSync, readFileSync } from "fs";

const { Pool } = pg;

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
  const result: PgConnectionConfig = {
    host: process.env.PGHOST || "localhost",
    port: parseInt(process.env.PGPORT || "5432"),
    database: process.env.PGDATABASE || "nova_memory",
    user: process.env.PGUSER || userInfo().username,
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
 */
export function getPool(): pg.Pool {
  if (!pool) {
    const pgConfig = loadPgConfig();
    pool = new Pool({
      ...pgConfig,
      max: 5,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
    });

    pool.on("error", (err) => {
      console.error("[turn-context] pg.Pool error:", err.message);
    });
  }
  return pool;
}
