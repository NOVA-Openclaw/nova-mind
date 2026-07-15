# NOVA Relationships System

**Project #29: NOVA Entity Perception, Profiling, and Relationship Management**

Part of the nova-mind ecosystem, providing comprehensive entity perception, profiling, recall triggers, context weighting, and Web of Trust infrastructure for AI agent networks.

> *Certificate sealed,*
> *threads of trust span every node—*
> *the graph knows your face*
>
> — **Erato**

## Overview

The NOVA Relationships System is a unified platform that merged the original Entity Relations System with the NOVA Multiuser System. It provides:

### Core Capabilities
- **Entity Perception**: How NOVA notices and identifies entities across all interaction channels. Ghost-entity prevention (`is_plausible_entity()` heuristics, `find_entity_id()` smarter matching via `alternate_spellings`) lives in the memory domain's extraction pipeline (`memory/scripts/extract_memories.py`), not in this repo's `lib/entity-resolver/` — see `memory/CHANGELOG.md` (#230, #267, #295).
- **Entity Profiling**: Dynamic profiling of entities (people, organizations, concepts) with behavioral/trait schema
- **Relationship Management**: Mapping and managing relationships between entities
- **Recall Triggers**: Context-aware retrieval of relevant entity information
- **Context Weighting**: Intelligent algorithms to determine what's worth the token cost
- **Web of Trust**: PGP-style cross-signing infrastructure for trusted AI agent networks

### Key Components

1. **Entity Resolver Library** (`lib/entity-resolver/`)
   - **Identity Resolution**: `resolveEntity()` looks up an entity across multiple identifiers (phone, email, UUID, certificates, Discord ID, Telegram ID, Slack member ID, Signal UUID/username, `deviceId`) via the `IDENTIFIER_TO_DB_KEY` mapping.
   - Conflict detection via `resolveEntityByIdentifiers()` — flags when identifiers match different entities
   - (Note: `find_entity_id()`/`is_plausible_entity()` — alternate-spelling matching and ghost-entity heuristics — are implemented in the memory domain's `extract_memories.py`, not this library.)
   - Session-aware caching for performance
   - Profile management and fact storage
   - Cross-platform integration (Discord, Telegram, Slack, Signal, email, web, certificates, devices)
   - `agent-install.sh` runs `npm install` in place under `lib/entity-resolver/` (it does not copy the library elsewhere); hooks import it directly from wherever the repo is checked out, e.g. `<checkout-path>/lib/entity-resolver`

2. **Certificate Authority** (`nova-ca/`)
   - Private CA for mTLS authentication
   - Client certificate management
   - Foundation for Web of Trust infrastructure

3. **Onboarding Skills** (`skills/`)
   - Agent onboarding workflows
   - User onboarding processes
   - Certificate authority management

## Architecture

The system follows a layered architecture designed for scalability and modularity:

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                        │
│  (Signal Bots, Web APIs, Email Processors, CLI Tools)      │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                  Entity Resolution API                     │
│     (Identity Resolution, Profile Management, Caching)     │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                    Database Layer                          │
│          (NOVA Memory DB: Entities, Facts, Relations)      │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                   Trust Infrastructure                     │
│    (Certificate Authority, mTLS, Web of Trust Network)     │
└─────────────────────────────────────────────────────────────┘
```

## Core Mechanics

### Perception Layer
**"What do I notice?"**
- Multi-channel identity detection (phone, email, UUID, certificate CN, Discord ID, Telegram ID, Slack member ID, Signal UUID/username)
- Cross-platform user tracking and consolidation
- Behavioral pattern recognition and trait extraction
- Context clue identification and correlation

### Organization Layer
**"How is it sorted/indexed?"**
- Entity classification and typing (person, organization, concept)
- Hierarchical relationship mapping
- Fact categorization and schema management
- Temporal organization of interactions and behavioral changes

### Recall Triggers
**"What prompts retrieval?"**
- Context-sensitive entity activation
- Relationship-based suggestions
- Historical pattern matching
- Relevance scoring algorithms

### Context Weighting
**"Is it worth the token cost?"**
- Confidence scoring based on data quality and recency
- Frequency analysis for behavior prediction
- Longitudinal pattern recognition
- Intensity/volume metrics for relationship strength
- Dynamic mood adaptation based on recent interactions

## Analysis Algorithms

The system includes sophisticated algorithms for entity analysis:

### Confidence Scoring
- **Data Quality**: Source reliability and verification status
- **Recency**: Time decay for stale information
- **Consistency**: Cross-reference validation
- **Volume**: Amount of supporting evidence

### Frequency Analysis
- **Interaction Patterns**: Communication frequency and timing
- **Topic Preferences**: Subject matter analysis
- **Platform Usage**: Channel preference patterns
- **Response Timing**: Behavioral rhythm analysis

### Longitudinal Patterns
- **Behavioral Evolution**: How entities change over time
- **Relationship Dynamics**: Strength and nature changes
- **Seasonal Patterns**: Time-based behavior cycles
- **Milestone Events**: Significant interaction points

### Entity Associations
- **Direct Relationships**: Explicitly connected entities
- **Transitive Relationships**: Indirect connections through mutual contacts
- **Topic Clustering**: Entities grouped by shared interests/contexts
- **Collaboration Networks**: Work or project-based associations

### Dynamic Mood Schema
- **Contextual Adaptation**: Response style based on entity preferences
- **Emotional State Tracking**: Recent interaction sentiment
- **Communication Style Evolution**: Adapting to entity's preferred approach
- **Situational Awareness**: Context-appropriate response selection

## Web of Trust Exploration

The system includes experimental infrastructure for building trust networks between AI agents:

### Trust Model
- **PGP-Inspired Design**: Decentralized trust with cryptographic verification
- **NOVA CA as Root**: Central certificate authority for the NOVA network
- **Agent Certificates**: Each agent gets a signed certificate for identity
- **Cross-Signing Capability**: Agents can vouch for other trusted agents

### Platform Independence
- **Persistent Identity**: Survives platform changes (Slack → Discord → etc.)
- **Portable Trust**: Trust relationships transfer across platforms
- **Federated Networks**: Multiple CA roots for different organizations
- **Standard Protocol**: Potential foundation for AI agent trust networks

### Implementation Status
🧪 **Experimental** - Foundation components are in place:
- CA infrastructure operational
- Client certificate signing working
- mTLS authentication configured
- Web of Trust protocols under development

## Installation

### Prerequisites

> **Recommended:** Use the unified `nova-mind` installer (`agent-install.sh` at the repo root) rather than this subsystem installer directly. It installs all three subsystems in the correct order.

**Required:**
- Node.js 18+ and npm
- PostgreSQL with nova-mind database already set up
- `memory/` must be installed first (provides required shared library files)

**The following tables must exist (created by `memory/` installer):**
- `entities` — Entity records (people, organizations, concepts)
- `entity_facts` — Key-value facts about entities
- `entity_relationships` — Relationships between entities

### Installer Entry Points

**For humans — recommended entry point:**
```bash
./shell-install.sh
```

A **non-interactive** prerequisite-checking wrapper that validates your environment before running the installer. Unlike the memory `shell-install.sh`, it does **not** prompt for configuration — it expects the `memory/` module to already be installed. It performs the following checks:

1. **jq** is installed
2. **Database configuration** exists — either `~/.openclaw/postgres.json` or PG environment variables (`PGHOST`, `PGDATABASE`, `PGUSER`)
3. **postgres.json validity** — all required fields present (`host`, `port`, `database`, `user`)
4. **pg-env.sh** exists at `~/.openclaw/lib/pg-env.sh` (installed by the `memory/` module)
5. **env-loader.sh** loaded if available (optional, non-fatal)
6. **Database reachability** — connects via `psql` to verify the database is up

If all checks pass, it execs `agent-install.sh` with any flags you passed through.

**For AI agents with environment pre-configured:**
```bash
./agent-install.sh
```

This is the actual installer. It:
- Verifies database schema (requires tables from the `memory/` module)
- Installs the entity-resolver TypeScript library (`npm install` in `lib/entity-resolver/`)
- Verifies the certificate-authority skill and NOVA CA are present (checks `$WORKSPACE/skills/certificate-authority/` and `nova-ca/certs/ca.crt` / `nova-ca/private/ca.key`; sets `chmod 700` on `nova-ca/private/` and `chmod +x` on `sign-client-csr.sh` if present) — it does **not** create the skill files or initialize the CA itself. If the CA is not yet initialized, it prints a pointer to `skills/certificate-authority/SKILL.md` for manual setup.
- Verifies all components are working

**Common flags** (passed through `shell-install.sh` or directly to `agent-install.sh`):
- `--verify-only` — Check installation without modifying anything
- `--force` — Force overwrite existing files
- `--database NAME` or `-d NAME` — Override database name (default: `${USER}_memory`)

### Database Setup

> **Note:** These tables are created by the `memory/` installer, not by this subsystem — the block below is illustrative of the shape, not a script to run directly. For the exact current schema, see `database/schema.sql` / `database/schema-reference.md`. A few real column names differ from earlier drafts of this doc: `entity_relationships` uses `entity_a`/`entity_b`/`relationship` (not `from_entity_id`/`to_entity_id`/`relationship_type`), and `entity_facts` has no `source` column (source attribution is a separate `entity_fact_sources` table) and no composite primary key (it has its own `id SERIAL PRIMARY KEY`).

```sql
-- entities table (simplified — see database/schema.sql for full column list)
CREATE TABLE entities (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  full_name VARCHAR(255),
  alternate_spellings TEXT[],
  type VARCHAR(50) NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- entity_facts table (simplified — see database/schema.sql for full column list,
-- including durability/category/extraction_count/last_confirmed_at)
CREATE TABLE entity_facts (
  id SERIAL PRIMARY KEY,
  entity_id INTEGER REFERENCES entities(id),
  key VARCHAR(255) NOT NULL,
  value TEXT,
  confidence DECIMAL(3,2) DEFAULT 1.0,
  learned_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- entity_relationships table (actual column names)
CREATE TABLE entity_relationships (
  id SERIAL PRIMARY KEY,
  entity_a INTEGER REFERENCES entities(id),
  entity_b INTEGER REFERENCES entities(id),
  relationship VARCHAR(100) NOT NULL,
  since TIMESTAMP,
  notes TEXT,
  is_long_distance BOOLEAN DEFAULT FALSE,
  seriousness VARCHAR(20) DEFAULT 'standard'
);

-- Create indexes for performance
CREATE INDEX idx_entity_facts_key_value ON entity_facts(key, value);
CREATE INDEX idx_entity_facts_entity_id ON entity_facts(entity_id);
CREATE INDEX idx_entity_rel_a ON entity_relationships(entity_a);
CREATE INDEX idx_entity_rel_b ON entity_relationships(entity_b);
```

### Environment Configuration
```bash
# Database connection (standard PG* variables)
PGHOST=localhost
# Database name is automatically derived from OS username: {username}_memory
# Examples: nova → nova_memory, nova-staging → nova_staging_memory  
# Hyphens in usernames are replaced with underscores
# Override with PGDATABASE if needed (e.g., PGDATABASE=custom_memory)
PGUSER=nova
PGPASSWORD=your_password

# Certificate authority
NOVA_CA_PATH=/path/to/nova-ca
```

**Note:** Entity resolver cache TTL and connection-pool sizing are currently
hardcoded in `lib/entity-resolver/{cache,resolver}.ts` (30-minute cache TTL,
pool max 5, 30s idle timeout). There are no `ENTITY_CACHE_TTL_MS`,
`DB_POOL_SIZE`, or `DB_IDLE_TIMEOUT_MS` environment variables read by the
library — see `ARCHITECTURE-entity-resolver.md` for details.

### Entity Resolver Installation
```bash
cd lib/entity-resolver
npm install
npx tsx test.ts  # Verify functionality (there is no `npm test` script in package.json)
```

### Certificate Authority Setup

> **Note:** There is no `setup-ca.sh` in `nova-ca/`. `agent-install.sh` does
> **not** initialize the CA — it only verifies an existing CA (checks for
> `nova-ca/certs/ca.crt` and `nova-ca/private/ca.key`, sets `chmod 700` on
> `nova-ca/private/`) and, if not yet initialized, prints a pointer to
> `skills/certificate-authority/SKILL.md` for the manual `openssl genrsa` /
> `openssl req -x509` init steps. `nova-ca/certs/` already contains an
> initialized `ca.crt` in this checkout (created manually per the skill's
> instructions). The only script under `nova-ca/` is `sign-client-csr.sh`,
> used to sign an already-generated client CSR against the existing CA.

```bash
cd nova-ca
./sign-client-csr.sh client.csr agent-name 365
```

## Usage Examples

### Basic Entity Resolution
```typescript
import { resolveEntity, getEntityProfile } from '@clawd/entity-resolver';

// Resolve entity by multiple identifiers
const entity = await resolveEntity({
  phone: '+1234567890',
  email: 'user@example.com',
  uuid: 'signal-uuid-here'
});

if (entity) {
  // Load profile for personalization
  const profile = await getEntityProfile(entity.id);
  console.log(`Found: ${entity.name}`);
  console.log(`Style: ${profile.communication_style}`);
  console.log(`Timezone: ${profile.timezone}`);
}
```

### Session-Aware Caching
```typescript
import { getCachedEntity, setCachedEntity } from '@clawd/entity-resolver';

// Check cache first
const sessionId = 'signal:group:abc123';
let entity = getCachedEntity(sessionId);

if (!entity) {
  entity = await resolveEntity(identifiers);
  if (entity) {
    setCachedEntity(sessionId, entity);
  }
}
```

### Certificate-Based Authentication
```bash
# Generate client certificate
openssl genrsa -out client.key 2048
openssl req -new -key client.key -out client.csr -subj "/CN=agent-name"

# Sign with NOVA CA
cd nova-ca
./sign-client-csr.sh client.csr agent-name 365
```

## File Structure

```
nova-relationships/
├── README.md                          # This file
├── ARCHITECTURE-entity-resolver.md    # Detailed technical docs
├── CONTRIBUTING.md                    # Development guidelines
├── lib/
│   └── entity-resolver/              # Core entity resolution library
│       ├── index.ts                  # Main API exports
│       ├── resolver.ts               # Entity resolution logic
│       ├── cache.ts                  # Session-aware caching
│       ├── types.ts                  # TypeScript definitions
│       ├── package.json              # NPM package configuration
│       └── test.ts                   # Test suite
├── nova-ca/                          # Certificate Authority
│   ├── certs/                        # Issued certificates
│   ├── openssl.cnf                   # OpenSSL configuration
│   └── sign-client-csr.sh           # Certificate signing script
├── skills/                           # OpenClaw skills
│   └── certificate-authority/        # CA management skill
│       ├── SKILL.md                  # Skill documentation
│       └── scripts/                  # CA utility scripts
└── docs/                            # Additional documentation
    ├── web-of-trust.md              # Trust network design
    ├── algorithms.md                # Analysis algorithm details
    └── integration-guide.md         # Integration examples
```

## Integration

This system integrates with various NOVA components:

### Signal Integration
- Automatic entity resolution from phone numbers and Signal UUIDs
- Profile-based response personalization
- Cross-conversation context preservation

### Web Interface Integration  
- Certificate-based authentication via mTLS
- Session-aware entity caching
- Profile-driven UI customization

### Email Integration
- Email address to entity mapping
- Communication style adaptation
- Relationship context in responses

### Multi-Agent Networks
- Certificate-based agent authentication
- Trust relationship establishment
- Cross-agent entity sharing (with privacy controls)

## Status & Roadmap

### Current Status
- ✅ **Entity Resolver Library**: Production ready
- ✅ **Basic Certificate Authority**: Operational  
- ✅ **Core Database Schema**: Implemented
- ✅ **Session Caching**: Working
- 🧪 **Web of Trust**: Experimental prototype
- 📋 **Analysis Algorithms**: Design phase
- 📋 **Relationship Management**: Planned

### Upcoming Features
- **Relationship Strength Analysis**: Automated relationship scoring
- **Behavioral Pattern Recognition**: ML-based trait extraction  
- **Trust Network Protocols**: Standardized agent trust exchange
- **Privacy Controls**: Granular entity data sharing permissions
- **Federation Support**: Multi-organization trust networks

### Long-term Vision
- **Universal Entity Graph**: Comprehensive entity relationship mapping
- **AI Agent Trust Standard**: Industry-standard trust protocols
- **Predictive Context Loading**: ML-driven relevant context prediction
- **Privacy-Preserving Federation**: Secure cross-organization entity sharing

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## Security Considerations

- **Entity Data Privacy**: All entity data is considered sensitive
- **Certificate Security**: CA private key must be protected at all times  
- **Database Security**: Use encrypted connections and strong authentication
- **Access Controls**: Implement principle of least privilege
- **Audit Logging**: Track all entity data access and modifications

## License

MIT License

---

**Part of the NOVA Psyche Ecosystem** 🧠