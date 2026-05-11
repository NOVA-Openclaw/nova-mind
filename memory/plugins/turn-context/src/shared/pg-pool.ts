/**
 * Shared singleton pg.Pool for the turn-context plugin.
 *
 * Loads PG env vars from ~/.openclaw/postgres.json before creating the pool,
 * so PGPASSWORD and friends are set correctly for node-pg.
 *
 * Issue: nova-mind #182
 */

import pg from "pg";
import { join } from "path";
import { homedir } from "os";

// Load PG env BEFORE creating pool — must be top-level await so the pool
// constructor sees the env vars when this module is first imported.
const pgEnvPath = join(homedir(), ".openclaw", "lib", "pg-env.ts");
const { loadPgEnv } = await import(pgEnvPath);
loadPgEnv();

const { Pool } = pg;

let pool: pg.Pool | null = null;

/**
 * Return the singleton pg.Pool, creating it on first call.
 */
export function getPool(): pg.Pool {
  if (!pool) {
    pool = new Pool({
      host: process.env.PGHOST || "localhost",
      port: parseInt(process.env.PGPORT || "5432"),
      database: process.env.PGDATABASE || "nova_memory",
      user: process.env.PGUSER || "nova",
      password: process.env.PGPASSWORD,
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
