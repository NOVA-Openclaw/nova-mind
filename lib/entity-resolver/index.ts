/**
 * Entity Resolver Library
 * 
 * Provides entity resolution and caching for the NOVA system.
 * 
 * @example
 * ```typescript
 * import { resolveEntity, getEntityProfile, getCachedEntity, setCachedEntity } from './lib/entity-resolver';
 * 
 * // Resolve an entity
 * const entity = await resolveEntity({ phone: '+1234567890' });
 * 
 * // Get entity profile
 * if (entity) {
 *   const profile = await getEntityProfile(entity.id);
 *   console.log(profile);
 * }
 * 
 * // Use caching
 * const sessionId = 'session-123';
 * let entity = getCachedEntity(sessionId);
 * if (!entity) {
 *   entity = await resolveEntity({ uuid: 'some-uuid' });
 *   if (entity) {
 *     setCachedEntity(sessionId, entity);
 *   }
 * }
 * ```
 */

// Export resolver functions
export {
  resolveEntity,
  getEntityProfile,
  getAllEntityFacts,
  closeDbPool,
} from "./resolver.ts";

// Export cache functions
export {
  getCachedEntity,
  setCachedEntity,
  clearCache,
  getCacheStats,
} from "./cache.ts";

// Export types
export type {
  Entity,
  EntityFacts,
  EntityIdentifiers,
} from "./types.ts";
