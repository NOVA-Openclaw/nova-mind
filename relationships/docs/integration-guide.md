# Integration Guide

## Overview

This guide provides practical examples for integrating the NOVA Relationships system into various applications and services. Each integration pattern includes complete code examples and configuration details.

## Quick Start Integration

### Basic Entity Resolution

```typescript
import { resolveEntity, getEntityProfile } from '@clawd/entity-resolver';

// Simple entity lookup
async function handleUserRequest(userIdentifiers: any) {
  const entity = await resolveEntity(userIdentifiers);
  
  if (entity) {
    const profile = await getEntityProfile(entity.id);
    console.log(`Welcome back, ${entity.name}!`);
    console.log(`Your timezone: ${profile.timezone || 'UTC'}`);
    return { entity, profile };
  } else {
    console.log('New user - consider onboarding');
    return { entity: null, profile: {} };
  }
}
```

## Platform-Specific Integrations

### 1. Signal Bot Integration

Complete integration for Signal messaging platform:

```typescript
// signal-bot.ts
import { SignalAPI, Message } from '@signalapp/mock-server';
import { 
  resolveEntity, 
  getEntityProfile, 
  getCachedEntity, 
  setCachedEntity 
} from '@clawd/entity-resolver';

class NOVASignalBot {
  private signal: SignalAPI;
  
  constructor(phoneNumber: string) {
    this.signal = new SignalAPI(phoneNumber);
    this.signal.on('message', this.handleMessage.bind(this));
  }
  
  async handleMessage(message: Message) {
    const sessionId = message.groupId 
      ? `signal:group:${message.groupId}`
      : `signal:dm:${message.sender.uuid}`;
    
    // Try cache first for performance
    let entity = getCachedEntity(sessionId, 30 * 60 * 1000); // 30 min TTL
    
    if (!entity) {
      // Resolve from multiple identifiers
      entity = await resolveEntity({
        uuid: message.sender.uuid,
        phone: message.sender.phone
      });
      
      if (entity) {
        setCachedEntity(sessionId, entity);
        console.log(`[Signal] Resolved: ${entity.name} (${entity.id})`);
      }
    }
    
    // Load user profile for personalization
    const profile = entity ? await getEntityProfile(entity.id) : {};
    
    // Create response context
    const context = this.createResponseContext(entity, profile, message);
    
    // Generate and send response
    const response = await this.generateResponse(message, context);
    await this.signal.send(response, message.groupId || message.sender.uuid);
  }
  
  private createResponseContext(entity: any, profile: any, message: Message) {
    return {
      entity,
      profile,
      timezone: profile.timezone || 'UTC',
      communicationStyle: profile.communication_style || 'balanced',
      expertise: profile.expertise?.split(',') || [],
      isKnownUser: !!entity,
      platform: 'signal',
      isGroupChat: !!message.groupId
    };
  }
  
  private async generateResponse(message: Message, context: any): Promise<string> {
    // Adapt response based on user profile
    if (context.communicationStyle === 'direct') {
      return this.generateDirectResponse(message, context);
    } else if (context.communicationStyle === 'formal') {
      return this.generateFormalResponse(message, context);
    } else {
      return this.generateBalancedResponse(message, context);
    }
  }
  
  // Style-specific response generators...
}

// Usage
const bot = new NOVASignalBot(process.env.SIGNAL_PHONE!);
bot.start();
```

### 2. Web API Integration

Express.js middleware for web applications:

```typescript
// middleware/entity-resolver.ts
import { Request, Response, NextFunction } from 'express';
import { 
  resolveEntity, 
  getEntityProfile, 
  getCachedEntity, 
  setCachedEntity 
} from '@clawd/entity-resolver';

declare module 'express-serve-static-core' {
  interface Request {
    entity?: Entity;
    entityProfile?: EntityProfile;
  }
}

export async function entityResolverMiddleware(
  req: Request, 
  res: Response, 
  next: NextFunction
) {
  const sessionId = req.session?.id || `ip:${req.ip}`;
  
  // Multiple authentication sources
  const identifiers: any = {};
  
  // Certificate-based authentication (mTLS)
  const certCN = req.get('X-SSL-Client-CN') || req.socket.getPeerCertificate()?.subject?.CN;
  if (certCN) {
    identifiers.certCN = certCN;
  }
  
  // JWT/OAuth authentication  
  if (req.user?.email) {
    identifiers.email = req.user.email;
  }
  
  // API key mapping (custom header)
  const apiKey = req.get('X-API-Key');
  if (apiKey) {
    identifiers.apiKey = apiKey;
  }
  
  // Phone number from verified source
  const phone = req.get('X-Verified-Phone');
  if (phone) {
    identifiers.phone = phone;
  }
  
  // Only proceed if we have at least one identifier
  if (Object.keys(identifiers).length === 0) {
    return next(); // Anonymous request
  }
  
  try {
    // Check cache first
    let entity = getCachedEntity(sessionId);
    
    if (!entity) {
      entity = await resolveEntity(identifiers);
      if (entity) {
        setCachedEntity(sessionId, entity);
      }
    }
    
    if (entity) {
      req.entity = entity;
      req.entityProfile = await getEntityProfile(entity.id);
      
      // Add timezone to request for time-aware responses
      if (req.entityProfile.timezone) {
        req.timezone = req.entityProfile.timezone;
      }
    }
  } catch (error) {
    console.error('[middleware] Entity resolution failed:', error);
    // Continue without entity data - graceful degradation
  }
  
  next();
}

// Usage in Express app
import express from 'express';
import { entityResolverMiddleware } from './middleware/entity-resolver';

const app = express();

// Apply middleware globally
app.use(entityResolverMiddleware);

// Use entity context in routes
app.get('/api/profile', (req, res) => {
  if (!req.entity) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  
  res.json({
    entity: {
      id: req.entity.id,
      name: req.entity.name,
      type: req.entity.type
    },
    profile: req.entityProfile,
    personalization: {
      timezone: req.entityProfile?.timezone || 'UTC',
      communicationStyle: req.entityProfile?.communication_style || 'balanced'
    }
  });
});

app.get('/api/dashboard', (req, res) => {
  const style = req.entityProfile?.communication_style || 'balanced';
  
  if (style === 'direct') {
    res.json({
      summary: 'Key metrics',
      data: getDirectDashboardData()
    });
  } else {
    res.json({
      welcome: `Welcome back, ${req.entity?.name}!`,
      summary: 'Here\'s what\'s happening',
      data: getDetailedDashboardData()
    });
  }
});
```

### 3. Email Processing Integration

IMAP/SMTP email processing with entity resolution:

```typescript
// email-processor.ts
import { ImapFlow } from 'imapflow';
import { SMTPServer } from 'smtp-server';
import { resolveEntity, getEntityProfile, getAllEntityFacts } from '@clawd/entity-resolver';

class NOVAEmailProcessor {
  private imap: ImapFlow;
  private smtpServer: SMTPServer;
  
  constructor() {
    this.setupIMAP();
    this.setupSMTP();
  }
  
  private setupIMAP() {
    this.imap = new ImapFlow({
      host: process.env.IMAP_HOST!,
      port: 993,
      secure: true,
      auth: {
        user: process.env.EMAIL_USER!,
        pass: process.env.EMAIL_PASS!
      }
    });
    
    this.imap.on('message', this.handleIncomingEmail.bind(this));
  }
  
  private setupSMTP() {
    this.smtpServer = new SMTPServer({
      secure: false,
      authOptional: true,
      onData: this.handleIncomingSMTP.bind(this)
    });
  }
  
  async handleIncomingEmail(message: any) {
    const senderEmail = message.from.address;
    
    // Resolve sender entity
    const sender = await resolveEntity({ email: senderEmail });
    
    if (sender) {
      console.log(`Email from known entity: ${sender.name} (${sender.id})`);
      
      // Load full profile
      const profile = await getEntityProfile(sender.id);
      const allFacts = await getAllEntityFacts(sender.id);
      
      // Create processing context
      const context = {
        entity: sender,
        profile,
        facts: allFacts,
        communicationStyle: profile.communication_style || 'formal',
        timezone: profile.timezone || 'UTC',
        expertise: profile.expertise?.split(',') || [],
        lastInteraction: this.getLastEmailInteraction(sender.id)
      };
      
      // Process email with entity context
      const response = await this.generateEmailResponse(message, context);
      
      if (response) {
        await this.sendEmail(response, senderEmail);
      }
      
    } else {
      console.log(`Email from unknown sender: ${senderEmail}`);
      
      // Handle as potential new entity
      await this.handleUnknownSender(message);
    }
    
    // Update interaction history
    await this.recordEmailInteraction(sender?.id, message);
  }
  
  private async generateEmailResponse(email: any, context: EntityContext) {
    const { entity, profile, communicationStyle, timezone } = context;
    
    // Adapt response style
    let greeting: string;
    let tone: 'formal' | 'casual' | 'professional';
    
    if (communicationStyle === 'formal') {
      greeting = `Dear ${entity.full_name || entity.name}`;
      tone = 'formal';
    } else if (communicationStyle === 'direct') {
      greeting = `Hi ${entity.name}`;
      tone = 'professional';
    } else {
      greeting = `Hello ${entity.name}`;
      tone = 'casual';
    }
    
    // Include timezone-aware information
    const localTime = new Date().toLocaleString('en-US', {
      timeZone: timezone,
      weekday: 'long',
      hour: 'numeric',
      minute: '2-digit',
      timeZoneName: 'short'
    });
    
    // Generate response based on email content and entity context
    const responseContent = await this.analyzeAndRespond(email, context);
    
    return {
      to: email.from.address,
      subject: `Re: ${email.subject}`,
      body: this.formatEmailBody(greeting, responseContent, tone, localTime),
      timezone: timezone
    };
  }
  
  private async handleUnknownSender(email: any) {
    // Extract potential entity information from email
    const extractedInfo = {
      email: email.from.address,
      name: email.from.name,
      // Try to extract phone from signature
      phone: this.extractPhoneFromSignature(email.text),
      // Extract organization from domain
      organization: this.extractOrganization(email.from.address)
    };
    
    // Could create new entity or flag for manual review
    console.log('Potential new entity:', extractedInfo);
    
    // Send generic response for unknown senders
    return this.generateGenericResponse(email);
  }
}

// Usage
const emailProcessor = new NOVAEmailProcessor();
emailProcessor.start();
```

### 4. Multi-Agent Network Integration

Integration with other AI agents using certificate-based trust:

```typescript
// agent-network.ts
import https from 'https';
import fs from 'fs';
import { resolveEntity, getEntityProfile } from '@clawd/entity-resolver';

class AgentNetworkClient {
  private clientOptions: https.RequestOptions;
  
  constructor() {
    this.clientOptions = {
      key: fs.readFileSync(process.env.AGENT_CERT_KEY!),
      cert: fs.readFileSync(process.env.AGENT_CERT!),
      ca: fs.readFileSync(process.env.NOVA_CA_CERT!),
      rejectUnauthorized: true
    };
  }
  
  async queryAgent(agentUrl: string, request: AgentRequest): Promise<AgentResponse> {
    return new Promise((resolve, reject) => {
      const req = https.request(agentUrl, {
        ...this.clientOptions,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Agent-ID': process.env.AGENT_ID!
        }
      }, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const response = JSON.parse(data);
            resolve(response);
          } catch (error) {
            reject(error);
          }
        });
      });
      
      req.on('error', reject);
      req.write(JSON.stringify(request));
      req.end();
    });
  }
  
  async shareEntityInfo(targetAgentUrl: string, entityId: number, permissions: string[]) {
    // Only share permitted entity information
    const entity = await resolveEntity({ id: entityId });
    const profile = await getEntityProfile(entityId, permissions);
    
    if (!entity) throw new Error('Entity not found');
    
    // Create signed entity share request
    const request: AgentRequest = {
      type: 'entity-share',
      data: {
        entity: {
          id: entity.id,
          name: entity.name,
          type: entity.type
        },
        profile: profile,
        permissions: permissions,
        timestamp: new Date().toISOString()
      },
      signature: this.signRequest(request.data)
    };
    
    return this.queryAgent(targetAgentUrl, request);
  }
  
  async requestEntityContext(
    targetAgentUrl: string, 
    entityIdentifiers: any, 
    contextType: string
  ): Promise<EntityContext> {
    const request: AgentRequest = {
      type: 'entity-context',
      data: {
        identifiers: entityIdentifiers,
        contextType: contextType,
        requestingAgent: process.env.AGENT_ID!
      }
    };
    
    const response = await this.queryAgent(targetAgentUrl, request);
    
    if (response.success) {
      return response.data as EntityContext;
    } else {
      throw new Error(response.error);
    }
  }
  
  // Server-side: Handle incoming agent requests
  async handleAgentRequest(req: any, res: any) {
    // Verify client certificate
    const clientCert = req.socket.getPeerCertificate();
    if (!clientCert || !this.verifyAgentCertificate(clientCert)) {
      return res.status(401).json({ error: 'Invalid agent certificate' });
    }
    
    const agentId = clientCert.subject.CN;
    console.log(`Request from agent: ${agentId}`);
    
    try {
      const request = req.body as AgentRequest;
      
      switch (request.type) {
        case 'entity-context':
          const context = await this.provideEntityContext(request.data, agentId);
          res.json({ success: true, data: context });
          break;
          
        case 'entity-share':
          await this.receiveEntityInfo(request.data, agentId);
          res.json({ success: true });
          break;
          
        default:
          res.status(400).json({ error: 'Unknown request type' });
      }
    } catch (error) {
      console.error('Agent request failed:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  }
}

// Usage in Express app
import express from 'express';
const app = express();
const agentClient = new AgentNetworkClient();

app.use('/agent-api', agentClient.handleAgentRequest.bind(agentClient));

// Cross-agent entity lookup
app.post('/api/cross-agent-lookup', async (req, res) => {
  const { agentUrl, identifiers, contextType } = req.body;
  
  try {
    const context = await agentClient.requestEntityContext(
      agentUrl, 
      identifiers, 
      contextType
    );
    res.json(context);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
```

## Integration Patterns

### 1. Session-Aware Caching

Efficient caching for high-performance applications:

```typescript
class SessionEntityManager {
  private readonly CACHE_TTL = 30 * 60 * 1000; // 30 minutes
  
  async getEntityForSession(sessionId: string, identifiers: any): Promise<Entity | null> {
    // Try cache first
    let entity = getCachedEntity(sessionId, this.CACHE_TTL);
    
    if (!entity && identifiers) {
      // Resolve from database
      entity = await resolveEntity(identifiers);
      
      if (entity) {
        setCachedEntity(sessionId, entity);
        
        // Preload common profile data
        const profile = await getEntityProfile(entity.id, [
          'timezone', 'communication_style', 'expertise'
        ]);
        
        // Cache profile separately with entity reference
        setCachedEntity(`${sessionId}:profile`, profile);
      }
    }
    
    return entity;
  }
  
  async getProfileForSession(sessionId: string): Promise<EntityProfile> {
    let profile = getCachedEntity(`${sessionId}:profile`, this.CACHE_TTL);
    
    if (!profile) {
      const entity = getCachedEntity(sessionId, this.CACHE_TTL);
      if (entity) {
        profile = await getEntityProfile(entity.id);
        setCachedEntity(`${sessionId}:profile`, profile);
      }
    }
    
    return profile || {};
  }
}
```

### 2. Event-Driven Updates

Real-time entity profile updates:

```typescript
import EventEmitter from 'events';

class EntityEventManager extends EventEmitter {
  async updateEntityFact(
    entityId: number, 
    key: string, 
    value: string, 
    source: string = 'manual'
  ) {
    // Update in database
    await this.updateFactInDatabase(entityId, key, value, source);
    
    // Emit update event
    this.emit('entity-updated', {
      entityId,
      factKey: key,
      newValue: value,
      source,
      timestamp: new Date()
    });
    
    // Invalidate related caches
    this.invalidateEntityCaches(entityId);
  }
  
  private invalidateEntityCaches(entityId: number) {
    // Find all sessions that have this entity cached
    const cacheStats = getCacheStats();
    
    cacheStats.sessions.forEach(sessionId => {
      const cachedEntity = getCachedEntity(sessionId);
      if (cachedEntity?.id === entityId) {
        clearCache(sessionId);
        clearCache(`${sessionId}:profile`);
      }
    });
  }
}

// Usage
const entityEvents = new EntityEventManager();

entityEvents.on('entity-updated', (update) => {
  console.log(`Entity ${update.entityId} updated: ${update.factKey} = ${update.newValue}`);
  
  // Trigger dependent updates
  if (update.factKey === 'timezone') {
    // Recalculate time-dependent facts
    this.updateTimeDependentFacts(update.entityId);
  }
  
  if (update.factKey === 'communication_style') {
    // Update response templates
    this.updateResponseTemplates(update.entityId);
  }
});
```

### 3. Bulk Operations

Efficient processing for large datasets:

```typescript
class BulkEntityProcessor {
  async processBulkInteractions(interactions: Interaction[]): Promise<void> {
    // Group interactions by entity for efficient processing
    const interactionsByEntity = this.groupInteractionsByEntity(interactions);
    
    // Process in batches to avoid overwhelming the database
    const batchSize = 50;
    const entityIds = Object.keys(interactionsByEntity).map(Number);
    
    for (let i = 0; i < entityIds.length; i += batchSize) {
      const batch = entityIds.slice(i, i + batchSize);
      await this.processBatch(batch, interactionsByEntity);
    }
  }
  
  private async processBatch(
    entityIds: number[], 
    interactionsByEntity: Record<number, Interaction[]>
  ) {
    // Load all entities and profiles in one query
    const entities = await this.loadEntitiesBulk(entityIds);
    const profiles = await this.loadProfilesBulk(entityIds);
    
    // Process each entity's interactions
    const updatePromises = entityIds.map(async entityId => {
      const entity = entities.find(e => e.id === entityId);
      const profile = profiles.find(p => p.entityId === entityId);
      const interactions = interactionsByEntity[entityId];
      
      if (entity && interactions) {
        return this.processEntityInteractions(entity, profile, interactions);
      }
    });
    
    await Promise.all(updatePromises);
  }
  
  private async loadEntitiesBulk(entityIds: number[]): Promise<Entity[]> {
    // Single query to load multiple entities
    const placeholders = entityIds.map((_, i) => `$${i + 1}`).join(',');
    const query = `SELECT * FROM entities WHERE id IN (${placeholders})`;
    
    const result = await pool.query(query, entityIds);
    return result.rows;
  }
}
```

## Configuration Examples

### Environment Variables

```bash
# Database configuration
POSTGRES_HOST=localhost
# Database name is automatically derived from OS username: {username}_memory
# Examples: nova → nova_memory, nova-staging → nova_staging_memory
# Hyphens in usernames are replaced with underscores
# Override with POSTGRES_DB if needed (e.g., POSTGRES_DB=custom_memory)
POSTGRES_USER=nova
POSTGRES_PASSWORD=secure_password

# Entity resolver configuration
ENTITY_CACHE_TTL_MS=1800000          # 30 minutes
DB_POOL_SIZE=10                      # Connection pool size
DB_IDLE_TIMEOUT_MS=30000            # 30 seconds

# Certificate configuration
NOVA_CA_CERT=/path/to/nova-ca.crt
AGENT_CERT=/path/to/agent.crt
AGENT_CERT_KEY=/path/to/agent.key
AGENT_ID=nova-main

# Integration-specific
SIGNAL_PHONE=+1234567890
IMAP_HOST=imap.gmail.com
EMAIL_USER=nova@example.com
EMAIL_PASS=app_password

# Web API configuration
SESSION_SECRET=random_session_secret
CORS_ORIGINS=https://app.example.com,https://admin.example.com
```

### Docker Compose

```yaml
version: '3.8'
services:
  nova-db:
    image: postgres:15
    environment:
      # Database name pattern: {username}_memory (hyphens → underscores)
      # This example assumes 'nova' user, adjust for your environment
      POSTGRES_DB: nova_memory  
      POSTGRES_USER: nova
      POSTGRES_PASSWORD: secure_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./schema:/docker-entrypoint-initdb.d
    ports:
      - "5432:5432"
  
  nova-api:
    build: .
    environment:
      POSTGRES_HOST: nova-db
      # Database name automatically derived from OS username or POSTGRES_USER
      # Will use: {POSTGRES_USER}_memory → nova_memory 
      POSTGRES_USER: nova
      POSTGRES_PASSWORD: secure_password
      ENTITY_CACHE_TTL_MS: 1800000
    volumes:
      - ./certs:/app/certs:ro
    ports:
      - "3000:3000"
    depends_on:
      - nova-db
  
  nova-signal:
    build: .
    command: npm run start:signal
    environment:
      POSTGRES_HOST: nova-db
      SIGNAL_PHONE: "+1234567890"
    volumes:
      - ./certs:/app/certs:ro
      - signal_data:/app/signal-data
    depends_on:
      - nova-db

volumes:
  postgres_data:
  signal_data:
```

## Testing Integration

### Integration Test Example

```typescript
import { setupTestDatabase, cleanupTestDatabase } from './test-helpers';

describe('Signal Bot Integration', () => {
  beforeAll(async () => {
    await setupTestDatabase();
  });
  
  afterAll(async () => {
    await cleanupTestDatabase();
  });
  
  it('should resolve entity from Signal message', async () => {
    // Create test entity
    const testEntity = await createTestEntity({
      name: 'John Doe',
      phone: '+1234567890',
      uuid: 'test-signal-uuid'
    });
    
    // Simulate Signal message
    const message = {
      sender: {
        phone: '+1234567890',
        uuid: 'test-signal-uuid'
      },
      text: 'Hello NOVA',
      groupId: null
    };
    
    const bot = new NOVASignalBot();
    const response = await bot.handleMessage(message);
    
    expect(response.entityResolved).toBe(true);
    expect(response.entityId).toBe(testEntity.id);
  });
});
```

---

*This integration guide provides practical examples for implementing the NOVA Relationships system across various platforms and use cases. Each pattern can be adapted to specific requirements while maintaining consistent entity resolution and profiling capabilities.*