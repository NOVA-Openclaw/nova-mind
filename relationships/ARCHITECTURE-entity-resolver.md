# Entity Resolver Library Architecture

## Overview

The Entity Resolver library is a core component of the NOVA Relationships ecosystem that provides intelligent entity resolution and session-aware caching for the NOVA memory database. It acts as the bridge between raw identifiers (phone numbers, UUIDs, emails, certificate CNs) and rich entity profiles, enabling the system to maintain context about users across different interaction channels.

### Purpose

- **Identity Resolution**: Converts various identifiers (phone, email, UUID, certificate CN) into unified entity records
- **Profile Management**: Loads entity facts like timezone, communication style, expertise, and preferences
- **Session Awareness**: Maintains per-session entity caches to reduce database load and improve response times
- **Cross-Platform Integration**: Works seamlessly across Signal, email, web interfaces, and other channels

### Why It Exists

In a multi-channel AI system like NOVA, users can interact through various means (Signal messages, emails, web interfaces, certificates). The Entity Resolver ensures that regardless of how a user connects, the system can:

1. Identify who they are across different identifiers
2. Load their preferences and contextual information
3. Provide consistent, personalized experiences
4. Maintain conversation continuity across sessions

## API Reference

### Core Resolution Functions

#### `resolveEntity(identifiers: EntityIdentifiers): Promise<Entity | null>`

Resolves an entity using one or more identifiers.

**Parameters:**
```typescript
interface EntityIdentifiers {
  phone?: string;      // E.g., "+1234567890"
  uuid?: string;       // Signal UUID or other platform UUID
  certCN?: string;     // Certificate common name for mTLS auth
  email?: string;      // Email address
}
```

**Returns:**
```typescript
interface Entity {
  id: number;          // Database entity ID
  name: string;        // Display name
  fullName?: string;   // Full legal name (optional)
  type: string;        // Entity type (person, organization, etc.)
}
```

**Example:**
```typescript
// Resolve by phone number
const entity = await resolveEntity({ phone: '+1234567890' });

// Resolve by multiple identifiers (OR logic)
const entity = await resolveEntity({
  phone: '+1234567890',
  uuid: 'signal-uuid-here',
  email: 'user@example.com'
});

if (entity) {
  console.log(`Found: ${entity.name} (ID: ${entity.id})`);
}
```

#### `getEntityProfile(entityId: number, factKeys?: string[]): Promise<EntityFacts>`

Loads entity profile facts for personalization.

**Parameters:**
- `entityId`: Database entity ID from resolveEntity()
- `factKeys`: Optional array of specific fact keys to load

**Default fact keys loaded:**
- `timezone`, `current_timezone` - User's timezone information
- `communication_style` - Preferred communication approach
- `expertise` - Areas of knowledge/skill
- `preferences` - User preferences
- `location` - Geographic location
- `occupation` - Job/role information

**Returns:**
```typescript
interface EntityFacts {
  [key: string]: string;  // Fact key-value pairs
}
```

**Example:**
```typescript
// Load default profile facts
const profile = await getEntityProfile(entityId);
console.log(`Timezone: ${profile.timezone}`);
console.log(`Style: ${profile.communication_style}`);

// Load specific facts only
const timezoneFacts = await getEntityProfile(entityId, ['timezone', 'current_timezone']);
```

#### `getAllEntityFacts(entityId: number): Promise<EntityFacts>`

Loads all facts for an entity, including custom facts not in the default set.

**Example:**
```typescript
const allFacts = await getAllEntityFacts(entityId);
// Returns all entity_facts records for this entity
```

### Caching Functions

#### `getCachedEntity(sessionId: string, ttlMs?: number): Entity | null`

Retrieves cached entity for a session.

**Parameters:**
- `sessionId`: Unique session identifier
- `ttlMs`: Time-to-live in milliseconds (default: 30 minutes)

**Example:**
```typescript
const entity = getCachedEntity('session-abc123');
if (entity) {
  console.log('Found cached entity:', entity.name);
}
```

#### `setCachedEntity(sessionId: string, entity: Entity): void`

Caches an entity for a session.

**Example:**
```typescript
setCachedEntity('session-abc123', entity);
```

#### `clearCache(sessionId?: string): void`

Clears cache for specific session or all sessions.

**Examples:**
```typescript
clearCache('session-abc123');  // Clear specific session
clearCache();                  // Clear all cached sessions
```

#### `getCacheStats(): { size: number; sessions: string[] }`

Returns cache statistics for monitoring.

**Example:**
```typescript
const stats = getCacheStats();
console.log(`Active sessions: ${stats.size}`);
console.log(`Session IDs: ${stats.sessions.join(', ')}`);
```

### Utility Functions

#### `closeDbPool(): Promise<void>`

Closes database connection pool for cleanup.

**Example:**
```typescript
// In application shutdown
await closeDbPool();
```

## Architecture

### Database Layer

The library connects to the NOVA memory database (PostgreSQL) using connection pooling:

**Tables Used:**
- `entities` - Core entity records (id, name, full_name, type)
- `entity_facts` - Key-value pairs storing entity attributes

**Connection Pool Configuration:**
- **Max connections**: 5 concurrent connections
- **Idle timeout**: 30 seconds
- **Connection timeout**: 5 seconds
- **Database**: Dynamically derived from OS username as `{username}_memory` (hyphens replaced with underscores)
  - Examples: `nova` → `nova_memory`, `nova-staging` → `nova_staging_memory`
  - Override with `POSTGRES_DB` environment variable if needed
- **Host**: `localhost` (configurable via `POSTGRES_HOST`)

**Query Strategy:**
```sql
-- Entity resolution query (simplified)
SELECT DISTINCT e.id, e.name, e.full_name, e.type 
FROM entities e 
JOIN entity_facts ef ON e.id = ef.entity_id 
WHERE (ef.key = 'phone' AND ef.value = ?) 
   OR (ef.key = 'signal_uuid' AND ef.value = ?)
   OR (ef.key = 'email' AND ef.value = ?)
LIMIT 1
```

### Caching Layer

**In-Memory Cache:**
- **Storage**: Map<sessionId, CacheEntry>
- **TTL**: 30 minutes default (configurable per call)
- **Eviction**: Automatic on TTL expiration
- **Thread Safety**: Single-threaded Node.js environment

**Cache Entry Structure:**
```typescript
interface CacheEntry {
  entity: Entity;
  timestamp: number;  // Unix timestamp
}
```

### Session Awareness

The library maintains separate entity caches per session, enabling:

1. **Multi-user support**: Different users in same process don't interfere
2. **Session isolation**: Each conversation/interaction maintains its own context
3. **Memory efficiency**: TTL-based automatic cleanup

**Session ID Patterns:**
- Signal: `signal:group:${groupId}` or `signal:dm:${uuid}`
- Web: `web:session:${sessionId}`
- Email: `email:thread:${threadId}`

### Error Handling

**Philosophy**: Fail gracefully, log errors, never crash the host application.

**Error Patterns:**
- Database connection failures → Return `null` or empty `{}`
- Invalid parameters → Return `null` or empty `{}`
- Query timeouts → Return `null` or empty `{}`
- All errors logged with `[entity-resolver]` prefix

**No Exceptions**: The library never throws exceptions in normal operation.

## Integration Guide

### Hook Integration

```typescript
// In a hook (e.g., signal message handler)
import { resolveEntity, getEntityProfile, getCachedEntity, setCachedEntity } from '../lib/entity-resolver';

export async function handleSignalMessage(message: SignalMessage, context: HookContext) {
  const sessionId = `signal:${message.groupId || `dm:${message.sender.uuid}`}`;
  
  // Try cache first
  let entity = getCachedEntity(sessionId);
  
  if (!entity) {
    // Resolve from database
    entity = await resolveEntity({
      uuid: message.sender.uuid,
      phone: message.sender.phone
    });
    
    if (entity) {
      // Cache for future messages in this session
      setCachedEntity(sessionId, entity);
    }
  }
  
  if (entity) {
    // Load user preferences
    const profile = await getEntityProfile(entity.id);
    
    // Use timezone for time-aware responses
    if (profile.timezone) {
      context.userTimezone = profile.timezone;
    }
    
    // Adapt communication style
    if (profile.communication_style === 'direct') {
      context.responseStyle = 'concise';
    }
  }
  
  // Continue with message processing...
}
```

### Middleware Integration

```typescript
// Express middleware
import { resolveEntity, getCachedEntity, setCachedEntity } from '../lib/entity-resolver';

export async function entityResolverMiddleware(req: Request, res: Response, next: NextFunction) {
  const sessionId = req.session?.id || `web:${req.ip}`;
  
  // Check for client cert authentication
  const certCN = req.get('X-Client-Cert-CN');
  const email = req.user?.email;  // From OAuth/JWT
  
  if (certCN || email) {
    let entity = getCachedEntity(sessionId);
    
    if (!entity && (certCN || email)) {
      entity = await resolveEntity({ certCN, email });
      if (entity) {
        setCachedEntity(sessionId, entity);
      }
    }
    
    if (entity) {
      req.entity = entity;
      req.entityProfile = await getEntityProfile(entity.id);
    }
  }
  
  next();
}
```

### Service Integration

```typescript
// Email processing service
import { resolveEntity, getEntityProfile } from '../lib/entity-resolver';

export class EmailProcessor {
  async processIncomingEmail(email: EmailMessage) {
    // Resolve sender
    const sender = await resolveEntity({
      email: email.from,
      phone: email.customHeaders['X-Phone-Number']  // If available
    });
    
    if (sender) {
      const profile = await getEntityProfile(sender.id);
      
      // Personalize response based on communication style
      const responseStyle = profile.communication_style || 'balanced';
      
      return {
        sender,
        profile,
        responseStyle,
        // ... other processing
      };
    }
    
    return { sender: null, profile: {}, responseStyle: 'formal' };
  }
}
```

### Background Job Integration

```typescript
// Cron job or background task
import { resolveEntity, getAllEntityFacts, clearCache } from '../lib/entity-resolver';

export async function syncEntityData() {
  // Clear expired cache entries (optional - they auto-expire)
  clearCache();
  
  // Process updated entities
  for (const update of pendingUpdates) {
    const entity = await resolveEntity({ uuid: update.uuid });
    if (entity) {
      const facts = await getAllEntityFacts(entity.id);
      await updateExternalSystems(entity, facts);
    }
  }
}
```

## Configuration

### Environment Variables

```bash
# Database connection (required)
POSTGRES_HOST=localhost          # Database host
# Database name automatically derived from OS username: {username}_memory
# Examples: nova → nova_memory, nova-staging → nova_staging_memory  
# Hyphens in usernames are replaced with underscores
# Override with POSTGRES_DB if needed (e.g., POSTGRES_DB=custom_memory)
POSTGRES_USER=nova               # Database user (defaults to OS username)
POSTGRES_PASSWORD=secret         # Database password

# Optional tuning
ENTITY_CACHE_TTL_MS=1800000      # Cache TTL (30 minutes)
DB_POOL_SIZE=5                   # Connection pool size
DB_IDLE_TIMEOUT_MS=30000         # Connection idle timeout
```

### Database Setup

**Required Tables:**
```sql
-- Entities table
CREATE TABLE entities (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  full_name VARCHAR(255),
  type VARCHAR(50) DEFAULT 'person'
);

-- Entity facts table
CREATE TABLE entity_facts (
  entity_id INTEGER REFERENCES entities(id),
  key VARCHAR(255) NOT NULL,
  value TEXT,
  PRIMARY KEY (entity_id, key)
);

-- Indexes for performance
CREATE INDEX idx_entity_facts_key_value ON entity_facts(key, value);
CREATE INDEX idx_entity_facts_entity_id ON entity_facts(entity_id);
```

### Connection Pool Tuning

```typescript
// Custom pool configuration
const customPool = new Pool({
  host: process.env.POSTGRES_HOST,
  database: process.env.POSTGRES_DB,
  user: process.env.POSTGRES_USER,
  password: process.env.POSTGRES_PASSWORD,
  max: parseInt(process.env.DB_POOL_SIZE || '5'),
  idleTimeoutMillis: parseInt(process.env.DB_IDLE_TIMEOUT_MS || '30000'),
  connectionTimeoutMillis: 5000,
});
```

### Cache Configuration

```typescript
// Custom cache TTL per call
const shortLivedEntity = getCachedEntity(sessionId, 5 * 60 * 1000);  // 5 minutes
const longLivedEntity = getCachedEntity(sessionId, 2 * 60 * 60 * 1000);  // 2 hours
```

## Examples

### Complete Signal Bot Integration

```typescript
import {
  resolveEntity,
  getEntityProfile,
  getCachedEntity,
  setCachedEntity,
  clearCache
} from '../lib/entity-resolver';

export class SignalBot {
  async handleMessage(message: SignalMessage) {
    const sessionId = message.groupId 
      ? `signal:group:${message.groupId}`
      : `signal:dm:${message.sender.uuid}`;
    
    // Try to get cached entity
    let entity = getCachedEntity(sessionId);
    
    if (!entity) {
      // Resolve entity from identifiers
      entity = await resolveEntity({
        uuid: message.sender.uuid,
        phone: message.sender.phone
      });
      
      if (entity) {
        // Cache for this session
        setCachedEntity(sessionId, entity);
        console.log(`Resolved entity: ${entity.name} (${entity.id})`);
      } else {
        console.log('Unknown user - treating as anonymous');
        return this.handleAnonymousMessage(message);
      }
    }
    
    // Load user profile for personalization
    const profile = await getEntityProfile(entity.id, [
      'timezone',
      'communication_style',
      'expertise',
      'preferences'
    ]);
    
    // Create response context
    const context = {
      entity,
      profile,
      sessionId,
      timezone: profile.timezone || 'UTC',
      style: profile.communication_style || 'balanced'
    };
    
    // Process message with context
    return this.generateResponse(message, context);
  }
  
  // Cleanup when bot stops
  async shutdown() {
    clearCache();  // Clear all session caches
    await closeDbPool();  // Close database connections
  }
}
```

### Web API with Entity Context

```typescript
import express from 'express';
import { resolveEntity, getEntityProfile, getCachedEntity, setCachedEntity } from '../lib/entity-resolver';

const app = express();

// Middleware to resolve entities
app.use('/api', async (req, res, next) => {
  const sessionId = req.session.id;
  
  // Check for authentication
  const email = req.user?.email;  // From JWT/OAuth
  const certCN = req.get('X-SSL-Client-CN');  // From client cert
  
  if (email || certCN) {
    // Try cache first
    let entity = getCachedEntity(sessionId);
    
    if (!entity) {
      entity = await resolveEntity({ email, certCN });
      if (entity) {
        setCachedEntity(sessionId, entity);
      }
    }
    
    if (entity) {
      req.entity = entity;
      req.entityProfile = await getEntityProfile(entity.id);
    }
  }
  
  next();
});

// API endpoint that uses entity context
app.get('/api/profile', (req, res) => {
  if (!req.entity) {
    return res.status(401).json({ error: 'Entity not resolved' });
  }
  
  res.json({
    entity: req.entity,
    profile: req.entityProfile,
    timezone: req.entityProfile.timezone || 'UTC'
  });
});
```

### Email Processing with Entity Resolution

```typescript
import { resolveEntity, getEntityProfile } from '../lib/entity-resolver';

export class EmailHandler {
  async processIncomingEmail(emailData: {
    from: string;
    subject: string;
    body: string;
    headers: Record<string, string>;
  }) {
    // Try to resolve sender
    const sender = await resolveEntity({
      email: emailData.from,
      // Check for phone in custom headers
      phone: emailData.headers['X-Phone-Number']
    });
    
    if (sender) {
      // Load sender profile
      const profile = await getEntityProfile(sender.id);
      
      console.log(`Email from ${sender.name} (${sender.type})`);
      
      // Adapt response based on communication style
      const responseConfig = {
        formal: profile.communication_style === 'formal',
        timezone: profile.timezone || 'UTC',
        expertise: profile.expertise?.split(',') || []
      };
      
      // Generate personalized response
      return this.generateResponse(emailData, sender, responseConfig);
    } else {
      console.log(`Unknown sender: ${emailData.from}`);
      // Handle as anonymous/new contact
      return this.generateGenericResponse(emailData);
    }
  }
  
  private async generateResponse(
    email: any, 
    sender: Entity, 
    config: any
  ) {
    // Use entity context to personalize response
    const greeting = config.formal 
      ? `Dear ${sender.fullName || sender.name}` 
      : `Hi ${sender.name}`;
    
    // Include timezone-aware scheduling if needed
    const localTime = new Date().toLocaleString('en-US', {
      timeZone: config.timezone
    });
    
    return {
      greeting,
      localTime,
      adaptedContent: this.adaptToStyle(email.body, config)
    };
  }
}
```

### Cron Job for Cache Management

```typescript
import cron from 'node-cron';
import { getCacheStats, clearCache } from '../lib/entity-resolver';

// Run every hour to log cache stats
cron.schedule('0 * * * *', () => {
  const stats = getCacheStats();
  console.log(`Entity cache: ${stats.size} active sessions`);
  
  // Log session IDs for debugging (remove in production)
  if (process.env.NODE_ENV === 'development') {
    console.log('Active sessions:', stats.sessions);
  }
});

// Clear cache daily at 3 AM (optional - entries auto-expire)
cron.schedule('0 3 * * *', () => {
  clearCache();
  console.log('Entity cache cleared');
});
```

### Testing Pattern

```typescript
import { resolveEntity, getEntityProfile, setCachedEntity, getCachedEntity } from '../lib/entity-resolver';

describe('Entity Resolution', () => {
  it('should resolve entity by phone number', async () => {
    const entity = await resolveEntity({ phone: '+1234567890' });
    expect(entity).toBeTruthy();
    expect(entity?.name).toBe('John Doe');
  });
  
  it('should use cache effectively', async () => {
    const sessionId = 'test-session';
    
    // First call - should hit database
    const entity1 = await resolveEntity({ phone: '+1234567890' });
    setCachedEntity(sessionId, entity1!);
    
    // Second call - should use cache
    const entity2 = getCachedEntity(sessionId);
    expect(entity2).toEqual(entity1);
  });
  
  it('should load entity profile', async () => {
    const entity = await resolveEntity({ email: 'john@example.com' });
    const profile = await getEntityProfile(entity!.id);
    
    expect(profile.timezone).toBeDefined();
    expect(profile.communication_style).toBeDefined();
  });
});
```

This comprehensive documentation provides everything needed to understand, integrate, and use the Entity Resolver library effectively within the NOVA Relationships ecosystem.