/**
 * Core entity resolution logic
 */

import pg from "pg";
import * as os from "os";
import type { Entity, EntityFacts, EntityIdentifiers, DbEntity, DbEntityFact } from "./types.ts";
import { join } from "path";

const { Pool } = pg;

// Load PG* env vars from ~/.openclaw/postgres.json before any DB connections
const pgEnvPath = join(process.env.HOME || os.homedir(), ".openclaw", "lib", "pg-env.ts");
const { loadPgEnv } = await import(pgEnvPath);
loadPgEnv();

// Database connection pool (singleton)
let dbPool: pg.Pool | null = null;

/**
 * Derive database name from username (same pattern as nova-memory)
 */
function getDatabaseName(): string {
  const user = process.env.PGUSER || os.userInfo().username;
  return process.env.PGDATABASE || `${user.replace(/-/g, '_')}_memory`;
}

/**
 * Get or create database connection pool
 */
function getDbPool(): pg.Pool {
  if (!dbPool) {
    const dbUser = process.env.PGUSER || os.userInfo().username;
    dbPool = new Pool({
      host: process.env.PGHOST || "localhost",
      database: getDatabaseName(),
      user: dbUser,
      password: process.env.PGPASSWORD,
      max: 5,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 5000,
    });
  }
  return dbPool;
}

/**
 * Close the database pool (for cleanup)
 */
export async function closeDbPool(): Promise<void> {
  if (dbPool) {
    await dbPool.end();
    dbPool = null;
  }
}

/**
 * Resolve an entity by various identifiers
 * @param identifiers - Object containing phone, uuid, certCN, or email
 * @returns Entity if found, null otherwise
 */
export async function resolveEntity(identifiers: EntityIdentifiers): Promise<Entity | null> {
  try {
    const pool = getDbPool();
    
    // Build query conditions based on provided identifiers
    const conditions: string[] = [];
    const values: string[] = [];
    let paramIndex = 1;
    
    if (identifiers.phone) {
      conditions.push(`(ef.key = 'phone' AND ef.value = $${paramIndex})`);
      values.push(identifiers.phone);
      paramIndex++;
    }
    
    if (identifiers.uuid) {
      conditions.push(`(ef.key = 'signal_uuid' AND ef.value = $${paramIndex})`);
      values.push(identifiers.uuid);
      paramIndex++;
    }
    
    if (identifiers.certCN) {
      conditions.push(`(ef.key = 'cert_cn' AND ef.value = $${paramIndex})`);
      values.push(identifiers.certCN);
      paramIndex++;
    }
    
    if (identifiers.email) {
      conditions.push(`(ef.key = 'email' AND ef.value = $${paramIndex})`);
      values.push(identifiers.email);
      paramIndex++;
    }
    
    if (conditions.length === 0) {
      return null;
    }
    
    const query = `
      SELECT DISTINCT e.id, e.name, e.full_name, e.type 
      FROM entities e 
      JOIN entity_facts ef ON e.id = ef.entity_id 
      WHERE ${conditions.join(" OR ")}
      LIMIT 1
    `;
    
    const result = await pool.query<DbEntity>(query, values);
    
    if (result.rows.length > 0) {
      const dbEntity = result.rows[0];
      return {
        id: dbEntity.id,
        name: dbEntity.name,
        fullName: dbEntity.full_name || undefined,
        type: dbEntity.type || "unknown",
      };
    }
    
    return null;
  } catch (err) {
    console.error("[entity-resolver] Resolution error:", err instanceof Error ? err.message : String(err));
    return null;
  }
}

/**
 * Get entity profile facts by entity ID
 * @param entityId - Entity database ID
 * @param factKeys - Optional array of specific fact keys to retrieve
 * @returns Object with fact key-value pairs
 */
export async function getEntityProfile(
  entityId: number,
  factKeys?: string[]
): Promise<EntityFacts> {
  try {
    const pool = getDbPool();
    
    // Default fact keys if none provided
    const keysToFetch = factKeys || [
      "timezone",
      "current_timezone",
      "communication_style",
      "expertise",
      "preferences",
      "location",
      "occupation",
    ];
    
    const query = `
      SELECT key, value 
      FROM entity_facts 
      WHERE entity_id = $1 
      AND key = ANY($2)
      LIMIT 20
    `;
    
    const result = await pool.query<DbEntityFact>(query, [entityId, keysToFetch]);
    
    const facts: EntityFacts = {};
    for (const row of result.rows) {
      facts[row.key] = row.value;
    }
    
    return facts;
  } catch (err) {
    console.error("[entity-resolver] Profile loading error:", err instanceof Error ? err.message : String(err));
    return {};
  }
}

/**
 * Get all facts for an entity (including custom facts)
 * @param entityId - Entity database ID
 * @returns Object with all fact key-value pairs
 */
export async function getAllEntityFacts(entityId: number): Promise<EntityFacts> {
  try {
    const pool = getDbPool();
    
    const query = `
      SELECT key, value 
      FROM entity_facts 
      WHERE entity_id = $1
    `;
    
    const result = await pool.query<DbEntityFact>(query, [entityId]);
    
    const facts: EntityFacts = {};
    for (const row of result.rows) {
      facts[row.key] = row.value;
    }
    
    return facts;
  } catch (err) {
    console.error("[entity-resolver] All facts loading error:", err instanceof Error ? err.message : String(err));
    return {};
  }
}
