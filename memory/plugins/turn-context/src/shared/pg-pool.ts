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
import { existsSync, readFileSync } from "fs";

const { Pool } = pg;

let pool: pg.Pool | null = null;
let pgEnvLoaded = false;

function ensurePgEnv(): void {
  if (pgEnvLoaded) return;
  pgEnvLoaded = true;
  try {
    const pgConfigPath = join(homedir(), ".openclaw", "postgres.json");
    if (existsSync(pgConfigPath)) {
      const config = JSON.parse(readFileSync(pgConfigPath, "utf-8"));
      if (config.host) process.env.PGHOST = process.env.PGHOST || config.host;
      if (config.port) process.env.PGPORT = process.env.PGPORT || String(config.port);
      if (config.database) process.env.PGDATABASE = process.env.PGDATABASE || config.database;
      if (config.user) process.env.PGUSER = process.env.PGUSER || config.user;
      if (config.password) process.env.PGPASSWORD = process.env.PGPASSWORD || config.password;
    }
  } catch (err) {
    console.warn("[turn-context] pg config load failed:", (err as Error).message);
  }
}

/**
 * Return the singleton pg.Pool, creating it on first call.
 */
export function getPool(): pg.Pool {
  if (!pool) {
    ensurePgEnv();
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
