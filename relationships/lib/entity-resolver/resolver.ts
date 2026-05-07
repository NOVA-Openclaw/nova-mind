/**
 * Core entity resolution logic
 */

import pg from "pg";
import * as os from "os";
import type { Entity, EntityFacts, EntityIdentifiers, DbEntity, DbEntityFact, ResolveResult } from "./types.ts";
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
 * Mapping from camelCase identifier keys to snake_case entity_facts.key values
 */
const IDENTIFIER_TO_DB_KEY: Record<string, string> = {
  discordId: 'discord_id',
  telegramId: 'telegram_id',
  slackMemberId: 'slack_member_id',
  signalUuid: 'signal_uuid',
  signalUsername: 'signal_username',
};

/**
 * Resolve an entity by various identifiers (original single-entity return).
 * Preserves backward compatibility — returns the first matched entity or null.
 * @param identifiers - Object containing phone, uuid, certCN, email, or platform IDs
 * @returns Entity if found, null otherwise
 */
export async function resolveEntity(identifiers: EntityIdentifiers): Promise<Entity | null> {
  try {
    const pool = getDbPool();
    
    // Build query conditions based on provided identifiers
    const conditions: string[] = [];
    const values: string[] = [];
    let paramIndex = 1;
    
    // Legacy identifier paths
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

    // Platform-specific identifier paths
    for (const [camelKey, dbKey] of Object.entries(IDENTIFIER_TO_DB_KEY)) {
      const val = identifiers[camelKey as keyof EntityIdentifiers];
      if (val) {
        conditions.push(`(ef.key = '${dbKey}' AND ef.value = $${paramIndex})`);
        values.push(val);
        paramIndex++;
      }
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
 * Resolve an entity by identifiers with conflict detection.
 * If multiple identifiers resolve to different entities, returns a conflict result
 * instead of silently picking a winner.
 *
 * @param identifiers - Object containing any combination of identifier fields
 * @returns ResolveResult if at least one entity matched, null if none matched
 */
export async function resolveEntityByIdentifiers(
  identifiers: EntityIdentifiers,
): Promise<ResolveResult | null> {
  try {
    const pool = getDbPool();

    // Build query conditions — same logic as resolveEntity but without LIMIT 1
    const conditions: string[] = [];
    const values: string[] = [];
    let paramIndex = 1;

    // Legacy identifier paths
    const legacyMap: Array<[keyof EntityIdentifiers, string]> = [
      ['phone', 'phone'],
      ['uuid', 'signal_uuid'],
      ['certCN', 'cert_cn'],
      ['email', 'email'],
    ];

    for (const [field, dbKey] of legacyMap) {
      const val = identifiers[field];
      if (val) {
        conditions.push(`(ef.key = '${dbKey}' AND ef.value = $${paramIndex})`);
        values.push(val);
        paramIndex++;
      }
    }

    // Platform-specific identifier paths
    for (const [camelKey, dbKey] of Object.entries(IDENTIFIER_TO_DB_KEY)) {
      const val = identifiers[camelKey as keyof EntityIdentifiers];
      if (val) {
        conditions.push(`(ef.key = '${dbKey}' AND ef.value = $${paramIndex})`);
        values.push(val);
        paramIndex++;
      }
    }

    if (conditions.length === 0) {
      return null;
    }

    // Fetch ALL matching entities (no LIMIT) plus their matched facts
    const query = `
      SELECT DISTINCT e.id, e.name, e.full_name, e.type, ef.key AS fact_key, ef.value AS fact_value
      FROM entities e
      JOIN entity_facts ef ON e.id = ef.entity_id
      WHERE ${conditions.join(' OR ')}
    `;

    const result = await pool.query<DbEntity & { fact_key: string; fact_value: string }>(query, values);

    if (result.rows.length === 0) {
      return null;
    }

    // Group by entity id
    const entitiesById = new Map<number, { entity: Entity; facts: DbEntityFact[] }>();
    for (const row of result.rows) {
      if (!entitiesById.has(row.id)) {
        entitiesById.set(row.id, {
          entity: {
            id: row.id,
            name: row.name,
            fullName: row.full_name || undefined,
            type: row.type || 'unknown',
          },
          facts: [],
        });
      }
      entitiesById.get(row.id)!.facts.push({ key: row.fact_key, value: row.fact_value });
    }

    if (entitiesById.size === 1) {
      const [entry] = entitiesById.values();
      return { ok: true, entity: entry.entity, facts: entry.facts };
    }

    // Multiple distinct entities — data integrity conflict
    const allEntities = [...entitiesById.values()].map((e) => e.entity);
    const names = allEntities.map((e) => `${e.name} (id=${e.id})`).join(', ');
    return {
      ok: false,
      conflict: true,
      entities: allEntities,
      message: `Multiple entities matched the supplied identifiers: ${names}. This indicates a data integrity issue — identifiers should resolve to a single entity.`,
    };
  } catch (err) {
    console.error('[entity-resolver] resolveEntityByIdentifiers error:', err instanceof Error ? err.message : String(err));
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
