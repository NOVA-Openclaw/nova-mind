# Contributing to NOVA Relationships

## Development Setup

### Prerequisites

- Node.js 18+ and npm
- PostgreSQL 12+
- Git
- OpenSSL (for certificate operations)

### Initial Setup

1. **Clone and Setup**
```bash
git clone <repository-url>
cd nova-relationships
```

2. **Database Setup**
```bash
# Create database and user
# Database name follows pattern: {username}_memory
# For user 'nova': nova_memory, for 'nova-staging': nova_staging_memory
sudo -u postgres createdb nova_memory
sudo -u postgres createuser nova

# Run schema setup
psql -U nova -d nova_memory -f schema/init.sql
```

3. **Environment Configuration**
```bash
cp .env.example .env
# Edit .env with your database credentials
```

4. **Install Dependencies**
```bash
cd lib/entity-resolver
npm install
npm test  # Verify everything works
```

### Development Workflow

1. **Create Feature Branch**
```bash
git checkout -b feature/your-feature-name
```

2. **Make Changes**
   - Follow the code style guidelines below
   - Add tests for new functionality
   - Update documentation as needed

3. **Test Changes**
```bash
cd lib/entity-resolver
npm test
npm run lint
```

4. **Commit Changes**
```bash
git add .
git commit -m "feat: descriptive commit message"
```

5. **Submit Pull Request**
   - Push branch to remote
   - Create PR with clear description
   - Link any relevant issues

## Code Style Guidelines

### TypeScript/JavaScript

We follow these style conventions:

```typescript
// Use meaningful variable names
const entityResolutionCache = new Map();

// Functions should have clear purposes
async function resolveEntityByIdentifiers(
  identifiers: EntityIdentifiers
): Promise<Entity | null> {
  // Implementation
}

// Interfaces should be descriptive
interface EntityProfile {
  timezone?: string;
  communication_style?: CommunicationStyle;
  expertise?: string[];
}

// Use consistent error handling
try {
  const entity = await resolveEntity(identifiers);
  return entity;
} catch (error) {
  console.error('[entity-resolver] Failed to resolve entity:', error);
  return null; // Graceful degradation
}
```

### Documentation

#### Code Comments
- Use JSDoc for all public functions
- Explain complex algorithms inline
- Document any non-obvious behavior

```typescript
/**
 * Resolves an entity using multiple identifier types.
 * 
 * @param identifiers - Object containing phone, email, UUID, or certificate CN
 * @returns Promise resolving to Entity or null if not found
 * @throws Never throws - returns null on any error for graceful degradation
 * 
 * @example
 * ```typescript
 * const entity = await resolveEntity({
 *   phone: '+1234567890',
 *   email: 'user@example.com'
 * });
 * ```
 */
async function resolveEntity(identifiers: EntityIdentifiers): Promise<Entity | null>
```

#### Markdown Documentation
- Use clear headers and structure
- Include code examples for APIs
- Link between related documents
- Keep examples up-to-date with code

## Testing Guidelines

### Test Structure

Tests should be organized by component:

```
lib/entity-resolver/
├── __tests__/
│   ├── resolver.test.ts      # Core resolution logic
│   ├── cache.test.ts         # Caching functionality  
│   ├── integration.test.ts   # End-to-end tests
│   └── fixtures/             # Test data
│       ├── entities.json
│       └── interactions.json
└── test.ts                   # Main test runner
```

### Writing Tests

```typescript
describe('Entity Resolution', () => {
  beforeEach(async () => {
    await setupTestDatabase();
  });

  afterEach(async () => {
    await cleanupTestDatabase();
  });

  it('should resolve entity by phone number', async () => {
    // Arrange
    const testEntity = await createTestEntity({
      name: 'John Doe',
      phone: '+1234567890'
    });

    // Act
    const result = await resolveEntity({ phone: '+1234567890' });

    // Assert
    expect(result).not.toBeNull();
    expect(result!.name).toBe('John Doe');
    expect(result!.id).toBe(testEntity.id);
  });

  it('should return null for unknown entity', async () => {
    // Act
    const result = await resolveEntity({ phone: '+9999999999' });

    // Assert
    expect(result).toBeNull();
  });
});
```

### Test Data Management

- Use fixtures for consistent test data
- Mock external dependencies (database, network calls)
- Clean up after each test to avoid interference

## Database Guidelines

### Schema Changes

1. **Create Migration Script**
```sql
-- migrations/003_add_relationship_strength.sql
ALTER TABLE entity_relationships 
ADD COLUMN strength DECIMAL(3,2) DEFAULT 0.5;

CREATE INDEX idx_relationships_strength 
ON entity_relationships(strength);
```

2. **Test Migration**
```bash
# Test on development database
# Database name pattern: {username}_memory (e.g., nova_memory, john_staging_memory)
psql -U nova -d nova_memory_dev -f migrations/003_add_relationship_strength.sql
```

3. **Document Changes**
Update `schema/README.md` with new schema version and changes.

### Query Guidelines

- Use prepared statements for dynamic queries
- Add appropriate indexes for query performance
- Use connection pooling efficiently
- Handle database errors gracefully

```typescript
// Good: Prepared statement with error handling
async function getEntityFacts(entityId: number): Promise<EntityFacts> {
  try {
    const result = await pool.query(
      'SELECT key, value FROM entity_facts WHERE entity_id = $1',
      [entityId]
    );
    return result.rows.reduce((facts, row) => {
      facts[row.key] = row.value;
      return facts;
    }, {});
  } catch (error) {
    console.error('[entity-resolver] Database query failed:', error);
    return {};
  }
}
```

## Certificate Authority Guidelines

### Development CA Setup

For development, create a separate CA:

```bash
mkdir -p ~/.nova-ca-dev/{private,certs,csr}
cd ~/.nova-ca-dev

# Generate development CA
openssl genrsa -out private/ca.key 2048
openssl req -x509 -new -nodes -key private/ca.key \
  -sha256 -days 365 -out certs/ca.crt \
  -subj "/CN=NOVA Development CA"
```

### Certificate Testing

```bash
# Generate test client cert
openssl genrsa -out test-client.key 2048
openssl req -new -key test-client.key -out test-client.csr \
  -subj "/CN=test-client"

# Sign with development CA
cd ~/.nova-ca-dev
./sign-client-csr.sh test-client.csr test-client 30
```

### Security Considerations

- **NEVER commit private keys** to version control
- Use different CAs for development and production
- Test certificate validation thoroughly
- Document certificate lifecycle procedures

## Documentation Guidelines

### Structure

Documentation should follow this hierarchy:

```
docs/
├── README.md                 # Project overview (this gets promoted to root)
├── architecture/
│   ├── entity-resolver.md    # Detailed technical docs
│   ├── web-of-trust.md       # Trust infrastructure
│   └── database-schema.md    # Database design
├── algorithms/
│   ├── confidence-scoring.md
│   ├── frequency-analysis.md
│   └── mood-detection.md
├── integration/
│   ├── signal-bot.md
│   ├── web-api.md
│   └── email-processing.md
└── operations/
    ├── deployment.md
    ├── monitoring.md
    └── troubleshooting.md
```

### Writing Style

- **Clear and Concise**: Avoid jargon, explain technical terms
- **Practical Examples**: Include working code samples
- **Current Information**: Keep docs updated with code changes
- **Cross-Reference**: Link related concepts and files

### API Documentation

All public APIs should include:

1. **Purpose**: What does this function do?
2. **Parameters**: What inputs does it expect?
3. **Returns**: What does it return?
4. **Examples**: How do you use it?
5. **Edge Cases**: What can go wrong?

## Performance Guidelines

### Caching Strategy

- Cache frequently accessed entities
- Use appropriate TTL for different data types
- Implement cache warming for critical paths
- Monitor cache hit rates

### Database Performance

- Use indexes on frequently queried columns
- Limit result sets with appropriate WHERE clauses
- Use connection pooling efficiently
- Monitor slow queries

### Memory Management

- Clean up large objects when done
- Use streaming for large datasets
- Monitor memory usage in long-running processes
- Implement backpressure for high-volume operations

## Security Guidelines

### Data Protection

- **Entity data is sensitive** - treat all entity information as private
- Use encryption for data at rest and in transit
- Implement proper access controls
- Log access to sensitive operations

### Certificate Handling

- Protect private keys with appropriate file permissions (400)
- Validate certificate chains completely
- Implement certificate revocation checking
- Use strong cryptographic algorithms

### Input Validation

```typescript
// Always validate and sanitize inputs
function validateEntityIdentifiers(identifiers: any): EntityIdentifiers | null {
  const validated: Partial<EntityIdentifiers> = {};
  
  if (identifiers.phone && typeof identifiers.phone === 'string') {
    // Validate phone number format
    if (/^\+[1-9]\d{1,14}$/.test(identifiers.phone)) {
      validated.phone = identifiers.phone;
    }
  }
  
  if (identifiers.email && typeof identifiers.email === 'string') {
    // Validate email format
    if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(identifiers.email)) {
      validated.email = identifiers.email;
    }
  }
  
  return Object.keys(validated).length > 0 ? validated as EntityIdentifiers : null;
}
```

## Release Process

### Version Numbering

We use semantic versioning (semver):

- **Patch** (1.0.1): Bug fixes, no API changes
- **Minor** (1.1.0): New features, backward compatible
- **Major** (2.0.0): Breaking changes

### Release Checklist

1. **Pre-release**
   - [ ] All tests pass
   - [ ] Documentation updated
   - [ ] Version number bumped
   - [ ] CHANGELOG.md updated

2. **Release**
   - [ ] Create release branch
   - [ ] Final testing on staging
   - [ ] Tag release in git
   - [ ] Update npm package (if applicable)

3. **Post-release**
   - [ ] Deploy to production
   - [ ] Monitor for issues
   - [ ] Update documentation site
   - [ ] Announce to team

## Getting Help

### Resources

- **Architecture Docs**: Read `docs/` directory for detailed technical information
- **Code Examples**: Check `examples/` directory for integration samples
- **Test Cases**: Look at `__tests__/` for usage patterns

### Communication

- **Bug Reports**: Use GitHub issues with detailed reproduction steps
- **Feature Requests**: Use GitHub issues with use case description
- **Questions**: Use GitHub discussions or team chat
- **Security Issues**: Email security contact directly (not public issues)

### Common Issues

#### Database Connection Problems
```bash
# Check database is running
sudo systemctl status postgresql

# Check connection (database name derived from username)
psql -U nova -d nova_memory -c "SELECT 1;"

# Check environment variables
echo $POSTGRES_HOST $POSTGRES_DB $POSTGRES_USER
```

#### Certificate Issues
```bash
# Verify certificate
openssl x509 -in cert.crt -text -noout

# Check CA chain
openssl verify -CAfile ca.crt cert.crt

# Test mTLS connection
curl -v --cert client.crt --key client.key \
  --cacert ca.crt https://localhost/api/test
```

#### Performance Issues
```bash
# Check cache statistics
curl localhost:3000/debug/cache-stats

# Monitor database queries
tail -f /var/log/postgresql/postgresql-*.log | grep DURATION

# Profile memory usage
node --inspect app.js
```

---

**Thank you for contributing to NOVA Relationships!** 

Your contributions help build a more intelligent and trustworthy AI agent ecosystem.