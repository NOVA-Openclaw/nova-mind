# Nova-Memory Documentation

Comprehensive guides for deploying, configuring, and using the nova-memory system.

## Quick Start

New to nova-memory? Start here:

1. **[Deployment and Setup Guide](deployment-setup-guide.md)** - Install from scratch
2. **[Database Schema Guide](database-schema-guide.md)** - Understand the data model
3. **[Memory Extraction Pipeline](memory-extraction-pipeline.md)** - Configure automatic learning
4. **[Semantic Search Guide](semantic-search-guide.md)** - Enable intelligent queries

## Architecture Overview

Nova-memory is a PostgreSQL-based long-term memory system for AI assistants that:

- **Automatically extracts** structured memories from natural language conversations
- **Stores relationships** between entities, events, and facts with confidence tracking
- **Provides semantic search** through vector embeddings and natural language queries
- **Enables inter-agent communication** via database-driven messaging
- **Maintains access control** through innovative table-comment-driven security

```
┌─────────────────────────────────────────────────────────────┐
│                    NOVA-MEMORY SYSTEM                       │
├─────────────────────────────────────────────────────────────┤
│  Natural Language Input                                     │
│       ↓                                                     │
│  Memory Extraction Pipeline (Claude API)                   │
│       ↓                                                     │
│  PostgreSQL Database (Structured Storage)                  │
│       ↓                                                     │
│  Vector Embeddings (Semantic Search)                       │
│       ↓                                                     │
│  Query Interface (SQL, API, Tools)                         │
└─────────────────────────────────────────────────────────────┘
```

## Documentation Sections

### 🚀 Getting Started
- [Deployment and Setup Guide](deployment-setup-guide.md) - Complete installation and configuration
- [Quick Reference](#quick-reference) - Common commands and queries

### 📊 Core Systems  
- [Database Schema Guide](database-schema-guide.md) - Tables, relationships, and access patterns
- [Database Aliasing Guide](DATABASE-ALIASING.md) - pgbouncer setup for multi-agent database sharing
- [Memory Extraction Pipeline](memory-extraction-pipeline.md) - Automated conversation processing
- [Semantic Search Guide](semantic-search-guide.md) - Vector embeddings and intelligent queries

### 🔧 Advanced Topics
- [Librarian Agent Deployment](librarian-agent-deployment.md) - Specialized memory management agent
- [Access Control Implementation](access-control-guide.md) - Multi-agent security patterns  
- [Performance Tuning](performance-tuning.md) - Optimization and scaling

### 🛠 Integration
- [OpenClaw Integration](integration-overview.md) - Hooks, plugins, and tools
- [API Reference](api-reference.md) - REST endpoints and client libraries
- [Agent Communication Protocols](agent-communication.md) - Inter-agent messaging

## Quick Reference

### Common Database Queries

```sql
-- Find an entity and their facts
SELECT e.name, ef.key, ef.value 
FROM entities e 
LEFT JOIN entity_facts ef ON e.id = ef.entity_id 
WHERE e.name ILIKE 'druid';

-- Recent events timeline
SELECT event_date, title FROM events 
WHERE event_date > NOW() - INTERVAL '7 days' 
ORDER BY event_date DESC;

-- Active projects  
SELECT name, status, goal FROM projects 
WHERE status = 'active';

-- Available agents for delegation
SELECT name, role, skills FROM agents 
WHERE status = 'active';
```

### Memory Extraction Commands

```bash
# Process a specific message
./scripts/process-input.sh "John mentioned he loves coffee from Blue Bottle"

# Manual extraction pipeline
echo "Test message" | ./scripts/extract-memories.sh | ./scripts/store-memories.sh

# Check extraction status
tail -f ~/.openclaw/logs/memory-catchup.log

# Health check
./scripts/health-check.sh
```

### Search Operations

```bash
# Semantic search (requires embeddings)
./scripts/search-memories.sh "pizza places in Brooklyn" 10

# SQL full-text search
psql -c "
SELECT content FROM memory_embeddings 
WHERE to_tsvector(content) @@ plainto_tsquery('brooklyn pizza');"
```

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **RAM** | 2GB | 8GB+ (for embeddings) |
| **Storage** | 10GB | 100GB+ (growing database) |
| **PostgreSQL** | v13+ | v16+ (with pgvector) |
| **CPU** | 2 cores | 4+ cores (parallel processing) |

## Key Features

### 🧠 Intelligent Memory Extraction
- Processes natural language conversations automatically
- Extracts 8 categories: entities, facts, events, relationships, preferences, opinions, places, vocabulary
- 20-message rolling context window for reference resolution
- Real-time deduplication prevents data corruption

### 🔍 Semantic Search
- Vector embeddings for natural language queries
- Cross-table search across all memory types
- Temporal decay weighting for relevance
- Hybrid search combining semantic and keyword matching

### 👥 Multi-Agent Architecture
- Inter-agent messaging via PostgreSQL NOTIFY/LISTEN
- Task routing and pipeline coordination
- Access control through table comments and row locking
- Agent registry for capability discovery

### 📈 Performance & Scalability
- Optimized indexes for fast queries
- Batch processing for API efficiency  
- Connection pooling support
- Horizontal scaling patterns

## Common Use Cases

### Personal AI Assistant
```bash
# Set up memory extraction for daily conversations
./scripts/memory-catchup.sh  # Process recent chat history
crontab -e  # Schedule automatic extraction
```

### Team Collaboration
```sql
-- Track team members and their expertise
INSERT INTO entities (name, type) VALUES ('alice', 'person');
INSERT INTO entity_facts (entity_id, key, value) 
SELECT id, 'expertise', 'machine learning' 
FROM entities WHERE name = 'alice';
```

### Project Management
```sql
-- Link projects to repositories
UPDATE projects 
SET repo_url = 'https://github.com/team/project', 
    locked = TRUE,
    git_config = '{"branch_strategy": "gitflow", "pr_required": true}'
WHERE name = 'nova-memory';
```

### Research and Learning
```bash
# Ingest and search research materials
./scripts/ingest-media.sh ~/Documents/research-paper.pdf
./scripts/search-memories.sh "machine learning techniques" 20
```

## Troubleshooting

### Memory Extraction Issues
1. **Check API connectivity:** `echo "test" | ./scripts/extract-memories.sh`
2. **Verify cron job:** `crontab -l | grep memory-catchup`  
3. **Review logs:** `tail -50 ~/.openclaw/logs/memory-catchup.log`
4. **Test database:** `psql -c "SELECT COUNT(*) FROM entities;"`

### Performance Problems
1. **Check indexes:** `ANALYZE; EXPLAIN ANALYZE SELECT ...`
2. **Monitor connections:** `SELECT * FROM pg_stat_activity;`
3. **Update statistics:** `VACUUM ANALYZE;`
4. **Review slow queries:** `SELECT * FROM pg_stat_statements ORDER BY mean_time DESC;`

### Integration Failures
1. **Verify OpenClaw hooks:** `openclaw hooks list`
2. **Test agent communication:** Insert test message in `agent_chat` table
3. **Check environment variables:** `env | grep NOVA_MEMORY`
4. **Review plugin logs:** `tail -f ~/.openclaw/logs/plugin-*.log`

## Development Workflow

### Making Schema Changes
```bash
# 1. Edit the declarative schema file (source of truth)
vim ~/.openclaw/workspace/nova-memory/schema/schema.sql

# 2. Preview the plan against your local database (optional)
pgschema plan --host localhost --db nova_memory --user nova \
  --schema public --file schema/schema.sql \
  --plan-db nova_memory

# 3. Apply via the installer (plans, hazard-checks, and applies)
./agent-install.sh

# 4. Update documentation
vim docs/database-schema-guide.md

# 5. Commit changes
git add schema/schema.sql docs/
git commit -m "feat: add new table for feature X"
```

> **Note:** If the change requires a data migration (e.g., column rename + backfill), add a script to `pre-migrations/` first. See [database-schema-guide.md](database-schema-guide.md) for details.

### Adding New Extraction Categories
```bash
# 1. Update extraction prompt
vim scripts/extract-memories.sh

# 2. Update storage logic  
vim scripts/store-memories.sh

# 3. Add database table if needed
vim schema/schema.sql

# 4. Test end-to-end
./scripts/process-input.sh "Test message for new category"

# 5. Update documentation
vim docs/memory-extraction-pipeline.md
```

## Support and Contributing

### Getting Help
- **Issues:** Report bugs and feature requests on GitHub
- **Discussions:** Join the nova-memory community discussions
- **Documentation:** Submit documentation improvements via PR

### Contributing Guidelines
1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/amazing-feature`
3. **Test** your changes thoroughly
4. **Document** new features and changes
5. **Submit** a pull request with clear description

### Code Standards
- **Shell scripts:** Use `shellcheck` for linting
- **SQL:** Follow PostgreSQL conventions, use lowercase with underscores
- **Documentation:** Use clear headings, code examples, and practical use cases
- **Commit messages:** Follow conventional commits format

## Roadmap

### Near Term (Next 3 months)
- [ ] **Performance monitoring dashboard** - Real-time metrics and alerts
- [ ] **Advanced deduplication** - ML-based duplicate detection  
- [ ] **Multi-modal embeddings** - Support for images and audio
- [ ] **Federated search** - Query across multiple nova-memory instances

### Medium Term (Next 6 months)
- [ ] **Graph relationships** - Visualize entity connections
- [ ] **Temporal queries** - "What did I know about X on date Y?"
- [ ] **Confidence learning** - Adaptive confidence scoring
- [ ] **API authentication** - Secure multi-user access

### Long Term (Next year)
- [ ] **Distributed architecture** - Multi-node deployment
- [ ] **Real-time streaming** - Live memory updates
- [ ] **Advanced analytics** - Pattern detection and insights
- [ ] **Integration ecosystem** - Plugins for popular tools

---

## Quick Navigation

- 📚 **[Core Guides](#documentation-sections)** - Essential reading for all users
- 🔧 **[Setup Instructions](deployment-setup-guide.md)** - Get up and running quickly  
- 🧠 **[Memory Pipeline](memory-extraction-pipeline.md)** - Understand automatic learning
- 🔍 **[Search System](semantic-search-guide.md)** - Master intelligent queries
- 📊 **[Database Schema](database-schema-guide.md)** - Learn the data model

**Built with ❤️ by the NOVA-Openclaw team**

*Last updated: February 27, 2026*