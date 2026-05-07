# Entity Resolver Library

A reusable TypeScript library for resolving and caching entity information from the NOVA memory database.

## Features

- **Multi-identifier resolution**: Resolve entities by phone, UUID, certificate CN, email, or platform-specific IDs (Discord, Telegram, Slack, Signal)
- **Conflict detection**: Detect when identifiers resolve to different entities (data integrity issues)
- **Session-aware caching**: Cache entity lookups per session with configurable TTL
- **Profile loading**: Load entity facts (timezone, preferences, etc.)
- **Connection pooling**: Efficient database connection management
- **Dynamic import support**: Installable to `~/.openclaw/lib/` for use by hooks at runtime

## Installation

The library is installed to `~/.openclaw/lib/entity-resolver/` by the `agent-install.sh` installer. Hooks and other runtime consumers use dynamic imports from this installed location:

```typescript
import { resolveEntity, resolveEntityByIdentifiers, getEntityProfile } from '~/.openclaw/lib/entity-resolver';
```

Within the repo, import directly:

```typescript
import { resolveEntity, getEntityProfile } from '../../lib/entity-resolver';
```

## Testing

Run the test script to verify functionality:

```bash
cd ~/workspace/nova-mind/relationships/lib/entity-resolver
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
- `discordId` - Discord user ID
- `telegramId` - Telegram user ID
- `slackMemberId` - Slack member ID
- `signalUuid` - Signal UUID (dedicated field, maps to `signal_uuid` in DB)
- `signalUsername` - Signal username (maps to `signal_username` in DB)

#### `resolveEntityByIdentifiers(identifiers: EntityIdentifiers): Promise<ResolveResult | null>`

Resolve an entity by identifiers **with conflict detection**. If multiple identifiers resolve to different entities, returns a conflict result instead of silently picking a winner. Returns `null` if no entity matched.

```typescript
const result = await resolveEntityByIdentifiers({
  discordId: '123456789',
  phone: '+1234567890'
});

if (result === null) {
  console.log('No entity found');
} else if (result.ok) {
  console.log(result.entity.name, result.facts);
} else {
  // result.ok === false — conflict detected
  console.error(result.message);
  console.log('Conflicting entities:', result.entities);
}
```

**`ResolveResult` type:**
```typescript
type ResolveResult =
  | { ok: true; entity: Entity; facts: DbEntityFact[] }
  | { ok: false; conflict: true; entities: Entity[]; message: string };
```

This function is preferred over `resolveEntity()` when conflict detection matters (e.g., the semantic-recall hook uses it to avoid injecting the wrong entity context).

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
  discordId?: string;
  telegramId?: string;
  slackMemberId?: string;
  signalUuid?: string;
  signalUsername?: string;
}

/**
 * Result of entity resolution with conflict detection.
 * ok: true  → all identifiers resolved to the same entity
 * ok: false → identifiers resolved to different entities (data integrity conflict)
 */
type ResolveResult =
  | { ok: true; entity: Entity; facts: DbEntityFact[] }
  | { ok: false; conflict: true; entities: Entity[]; message: string };

interface DbEntityFact {
  key: string;
  value: string;
}
```

## Database

Connects to PostgreSQL database using credentials from `~/.openclaw/postgres.json` (loaded by `~/.openclaw/lib/pg-env.ts` at module scope). Standard `PG*` environment variables override the config file:

- **Database:** Automatically derived from OS username as `{username}_memory` (hyphens → underscores)
  - Examples: `nova` → `nova_memory`, `nova-staging` → `nova_staging_memory`
  - Override with `PGDATABASE` environment variable
- **Host:** `localhost` (configurable via `PGHOST`)
- **User:** OS username (configurable via `PGUSER`)
- **Password:** Set via `PGPASSWORD` env var

### Identifier to DB Key Mapping

The resolver maps camelCase identifier fields to snake_case `entity_facts.key` values:

| Identifier Field | DB Fact Key |
|-----------------|-------------|
| `discordId` | `discord_id` |
| `telegramId` | `telegram_id` |
| `slackMemberId` | `slack_member_id` |
| `signalUuid` | `signal_uuid` |
| `signalUsername` | `signal_username` |

Legacy identifiers (`phone`, `uuid`, `certCN`, `email`) map to `phone`, `signal_uuid`, `cert_cn`, and `email` respectively.

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
