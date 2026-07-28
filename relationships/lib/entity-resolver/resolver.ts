/**
 * Core entity resolution logic
 */

import pg from "pg";
import * as os from "os";
import type { Entity, EntityFacts, EntityIdentifiers, DbEntity, DbEntityFact, ResolveResult, EntityProfile } from "./types.ts";
import { join } from "path";

const { Pool } = pg;

// Load PG config from ~/.openclaw/postgres.json without polluting process.env
// See: https://github.com/NOVA-Openclaw/nova-mind/issues/330
const pgEnvPath = join(process.env.HOME || os.homedir(), ".openclaw", "lib", "pg-env.ts");
let pgConfig: { host?: string; port?: number; database?: string; user?: string; password?: string } = {};
try {
  const { loadPgEnv } = await import(pgEnvPath);
  pgConfig = loadPgEnv();
} catch (e) {
  console.warn('[entity-resolver] Could not load pg-env.ts:', (e as Error).message);
}

// Database connection pool (singleton)
let dbPool: pg.Pool | null = null;

/**
 * Derive database name: use config value or fall back to <user>_memory convention.
 */
function getDatabaseName(): string {
  if (pgConfig.database) return pgConfig.database;
  const user = pgConfig.user || os.userInfo().username;
  return `${user.replace(/-/g, '_')}_memory`;
}

/**
 * Get or create database connection pool
 */
function getDbPool(): pg.Pool {
  if (!dbPool) {
    dbPool = new Pool({
      host: pgConfig.host || "localhost",
      port: pgConfig.port,
      database: getDatabaseName(),
      user: pgConfig.user || os.userInfo().username,
      password: pgConfig.password,
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
  deviceId: 'nova_app_device_id',
  ircUsername: 'irc_username',
};

/**
 * Map a raw database entity row to the public Entity shape.
 */
function mapDbEntity(row: DbEntity): Entity {
  const entity: Entity = {
    id: row.id,
    name: row.name,
    fullName: row.full_name || undefined,
    type: row.type || "unknown",
  };

  if (row.pronouns) entity.pronouns = row.pronouns;
  if (row.trust_level) entity.trustLevel = row.trust_level;
  if (row.last_seen) entity.lastSeen = row.last_seen;
  if (row.created_at) entity.createdAt = row.created_at;

  return entity;
}

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
      SELECT DISTINCT e.id, e.name, e.full_name, e.type,
             e.pronouns, e.trust_level,
             -- entities.last_seen is plain timestamp (naive, no tz); do NOT apply
             -- AT TIME ZONE 'UTC' because that interprets the value in the session
             -- timezone and converts it. See nova-mind#543 / RS-062.
             to_char(e.last_seen, 'YYYY-MM-DD HH24:MI "UTC"') AS last_seen,
             to_char(e.created_at, 'YYYY-MM-DD') AS created_at
      FROM entities e 
      JOIN entity_facts ef ON e.id = ef.entity_id 
      WHERE ${conditions.join(" OR ")}
      LIMIT 1
    `;
    
    const result = await pool.query<DbEntity>(query, values);
    
    if (result.rows.length > 0) {
      return mapDbEntity(result.rows[0]);
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
      SELECT DISTINCT e.id, e.name, e.full_name, e.type,
             e.pronouns, e.trust_level,
             -- entities.last_seen is plain timestamp (naive, no tz); do NOT apply
             -- AT TIME ZONE 'UTC' because that interprets the value in the session
             -- timezone and converts it. See nova-mind#543 / RS-062.
             to_char(e.last_seen, 'YYYY-MM-DD HH24:MI "UTC"') AS last_seen,
             to_char(e.created_at, 'YYYY-MM-DD') AS created_at,
             ef.key AS fact_key, ef.value AS fact_value
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
          entity: mapDbEntity(row),
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
 * Get entity profile facts by entity ID, plus cheap relationship stats.
 * Returns allowlist facts, an unfiltered fact count, and the most recent
 * channel transcript (timestamp + provider:external_chat_id ref) in a single
 * round trip. See nova-mind#543.
 *
 * @param entityId - Entity database ID
 * @param factKeys - Optional array of specific fact keys to retrieve
 * @returns EntityProfile with facts and stats
 */
export async function getEntityProfile(
  entityId: number,
  factKeys?: string[]
): Promise<EntityProfile> {
  const emptyProfile: EntityProfile = { facts: {}, stats: { factCount: 0, lastMessage: null } };

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
    
    // Single aggregate query: fact count (unfiltered), last transcript,
    // and filtered allowlist facts. Designed to stay inside the 1s race
    // budget consumed by turn-context.
    const query = `
      SELECT
        fc.count AS fact_count,
        to_char(lm.timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"') AS last_message_time,
        lm.provider AS last_message_provider,
        lm.external_chat_id AS last_message_external_chat_id,
        facts.facts_json
      FROM (SELECT COUNT(*) AS count FROM entity_facts WHERE entity_id = $1) fc
      LEFT JOIN LATERAL (
        SELECT ct.timestamp, cs.provider, cs.external_chat_id
        FROM channel_transcripts ct
        JOIN channel_sessions cs ON ct.session_id = cs.id
        WHERE ct.sender_entity_id = $1
        ORDER BY ct.timestamp DESC
        LIMIT 1
      ) lm ON true
      LEFT JOIN LATERAL (
        SELECT COALESCE(
          jsonb_agg(jsonb_build_object('key', sub.key, 'value', sub.value)),
          '[]'::jsonb
        ) AS facts_json
        FROM (
          SELECT key, value
          FROM entity_facts
          WHERE entity_id = $1 AND key = ANY($2)
          LIMIT 20
        ) sub
      ) facts ON true
    `;
    
    interface ProfileRow {
      fact_count: string;
      last_message_time: string | null;
      last_message_provider: string | null;
      last_message_external_chat_id: string | null;
      facts_json: Array<{ key: string; value: string }>;
    }

    const result = await pool.query<ProfileRow>(query, [entityId, keysToFetch]);
    
    if (result.rows.length === 0) {
      return emptyProfile;
    }

    const row = result.rows[0];
    const facts: EntityFacts = {};
    for (const fact of row.facts_json || []) {
      facts[fact.key] = fact.value;
    }

    const lastMessage = row.last_message_time
      ? {
          timestamp: row.last_message_time,
          ref: `${row.last_message_provider}:${row.last_message_external_chat_id}`,
        }
      : null;
    
    return {
      facts,
      stats: {
        factCount: parseInt(row.fact_count, 10) || 0,
        lastMessage,
      },
    };
  } catch (err) {
    console.error("[entity-resolver] Profile loading error:", err instanceof Error ? err.message : String(err));
    return emptyProfile;
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
