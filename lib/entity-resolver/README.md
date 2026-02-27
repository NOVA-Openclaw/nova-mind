# Entity Resolver Library

A reusable TypeScript library for resolving and caching entity information from the NOVA memory database.

## Features

- **Multi-identifier resolution**: Resolve entities by phone, UUID, certificate CN, or email
- **Session-aware caching**: Cache entity lookups per session with configurable TTL
- **Profile loading**: Load entity facts (timezone, preferences, etc.)
- **Connection pooling**: Efficient database connection management

## Installation

This library is part of the clawd monorepo. Import directly:

```typescript
import { resolveEntity, getEntityProfile } from '../../lib/entity-resolver';
// or from within lib/
import { resolveEntity, getEntityProfile } from '../entity-resolver';
```

## Testing

Run the test script to verify functionality:

```bash
cd ~/clawd/lib/entity-resolver
npx tsx test.ts [phone_or_uuid]

# Example:
npx tsx test.ts "+1234567890"
```

## API

### Resolver Functions

#### `resolveEntity(identifiers: EntityIdentifiers): Promise<Entity | null>`

Resolve an entity by one or more identifiers.

```typescript
const entity = await resolveEntity({
  phone: '+1234567890',
  uuid: 'signal-uuid-here'
});

if (entity) {
  console.log(entity.id, entity.name, entity.fullName);
}
```

**Identifiers:**
- `phone` - Phone number (e.g., `+1234567890`)
- `uuid` - Signal UUID or other UUID identifier
- `certCN` - Certificate common name
- `email` - Email address

#### `getEntityProfile(entityId: number, factKeys?: string[]): Promise<EntityFacts>`

Load entity profile facts.

```typescript
const profile = await getEntityProfile(entityId);
// Returns: { timezone: 'America/New_York', communication_style: 'direct', ... }

// Or load specific facts:
const timezone = await getEntityProfile(entityId, ['timezone', 'current_timezone']);
```

**Default fact keys:**
- `timezone`, `current_timezone`
- `communication_style`
- `expertise`
- `preferences`
- `location`
- `occupation`

#### `getAllEntityFacts(entityId: number): Promise<EntityFacts>`

Load all facts for an entity (including custom facts).

```typescript
const allFacts = await getAllEntityFacts(entityId);
```

### Cache Functions

#### `getCachedEntity(sessionId: string, ttlMs?: number): Entity | null`

Get cached entity for a session (default TTL: 30 minutes).

```typescript
const entity = getCachedEntity('session-123');
```

#### `setCachedEntity(sessionId: string, entity: Entity): void`

Cache an entity for a session.

```typescript
setCachedEntity('session-123', entity);
```

#### `clearCache(sessionId?: string): void`

Clear cache for a specific session or all sessions.

```typescript
clearCache('session-123');  // Clear one session
clearCache();               // Clear all
```

#### `getCacheStats(): { size: number; sessions: string[] }`

Get cache statistics.

```typescript
const stats = getCacheStats();
console.log(`Cached sessions: ${stats.size}`);
```

### Utility Functions

#### `closeDbPool(): Promise<void>`

Close the database connection pool (for cleanup).

```typescript
await closeDbPool();
```

## Types

```typescript
interface Entity {
  id: number;
  name: string;
  fullName?: string;
  type: string;
}

interface EntityFacts {
  [key: string]: string;
}

interface EntityIdentifiers {
  phone?: string;
  uuid?: string;
  certCN?: string;
  email?: string;
}
```

## Database

Connects to PostgreSQL database:
- **Database:** Automatically derived from OS username as `{username}_memory` (hyphens → underscores)
  - Examples: `nova` → `nova_memory`, `nova-staging` → `nova_staging_memory`
  - Override with `POSTGRES_DB` environment variable if needed
- **Host:** `localhost` (configurable via `POSTGRES_HOST`)
- **User:** OS username (configurable via `POSTGRES_USER`)
- **Password:** Set via `POSTGRES_PASSWORD` env var

## Usage Example

```typescript
import {
  resolveEntity,
  getEntityProfile,
  getCachedEntity,
  setCachedEntity,
} from '../lib/entity-resolver';

async function handleMessage(sessionId: string, senderId: string) {
  // Try cache first
  let entity = getCachedEntity(sessionId);
  
  if (!entity) {
    // Resolve from database
    entity = await resolveEntity({ uuid: senderId });
    
    if (entity) {
      // Cache for future use
      setCachedEntity(sessionId, entity);
      
      // Load profile
      const profile = await getEntityProfile(entity.id);
      console.log(`User ${entity.name} (${profile.timezone || 'unknown timezone'})`);
    }
  }
  
  return entity;
}
```

## Performance

- **Connection pooling**: Max 5 connections, 30s idle timeout
- **Cache TTL**: 30 minutes default (configurable per-call)
- **Query timeout**: 5s connection timeout

## Error Handling

All functions handle errors gracefully:
- Returns `null` or empty object on error
- Logs errors to console with `[entity-resolver]` prefix
- Does not throw exceptions (safe for hooks and middleware)
