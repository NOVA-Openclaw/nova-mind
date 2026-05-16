/**
 * Shared singleton pg.Pool for the self-awareness plugin.
 *
 * Loads PG env vars from ~/.openclaw/postgres.json before creating the pool,
 * so PGPASSWORD and friends are set correctly for node-pg.
 */
import pg from "pg";
/**
 * Return the singleton pg.Pool, creating it on first call.
 */
export declare function getPool(): pg.Pool;
