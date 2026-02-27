/**
 * Session-aware entity caching
 */

import type { Entity } from "./types.ts";

interface CacheEntry {
  entity: Entity;
  timestamp: number;
}

// Cache storage: sessionId -> entity data
const sessionCache = new Map<string, CacheEntry>();

// Default cache TTL: 30 minutes
const DEFAULT_TTL_MS = 30 * 60 * 1000;

/**
 * Get cached entity for a session
 * @param sessionId - Session identifier
 * @param ttlMs - Time-to-live in milliseconds (default: 30 minutes)
 * @returns Cached entity or null if not found/expired
 */
export function getCachedEntity(sessionId: string, ttlMs: number = DEFAULT_TTL_MS): Entity | null {
  const entry = sessionCache.get(sessionId);
  
  if (!entry) {
    return null;
  }
  
  // Check if expired
  const now = Date.now();
  if (now - entry.timestamp > ttlMs) {
    sessionCache.delete(sessionId);
    return null;
  }
  
  return entry.entity;
}

/**
 * Set cached entity for a session
 * @param sessionId - Session identifier
 * @param entity - Entity to cache
 */
export function setCachedEntity(sessionId: string, entity: Entity): void {
  sessionCache.set(sessionId, {
    entity,
    timestamp: Date.now(),
  });
}

/**
 * Clear cache for a specific session or all sessions
 * @param sessionId - Optional session identifier. If not provided, clears all cache.
 */
export function clearCache(sessionId?: string): void {
  if (sessionId) {
    sessionCache.delete(sessionId);
  } else {
    sessionCache.clear();
  }
}

/**
 * Get cache statistics
 * @returns Object with cache size and session count
 */
export function getCacheStats(): { size: number; sessions: string[] } {
  return {
    size: sessionCache.size,
    sessions: Array.from(sessionCache.keys()),
  };
}
