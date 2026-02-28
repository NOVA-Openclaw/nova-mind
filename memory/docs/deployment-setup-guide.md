# Deployment and Setup Guide

This guide walks through setting up nova-memory from scratch, including database installation, configuration, and integration with OpenClaw.

## Prerequisites

### System Requirements

**Minimum:**
- Ubuntu 20.04+ or similar Linux distribution
- 2GB RAM (4GB recommended)
- 10GB free disk space
- Internet connection for API access

**Recommended for production:**
- 8GB+ RAM for vector embeddings
- SSD storage for database performance
- Separate database server for multi-agent systems

### Required Software

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install core dependencies
sudo apt install -y \
    postgresql postgresql-contrib \
    postgresql-client \
    curl wget git \
    jq bc \
    python3 python3-pip \
    build-essential \
    golang-go        # Required for pgschema install

# Install Node.js (for OpenClaw)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install pgschema (declarative schema management — required by agent-install.sh)
go install github.com/pgplex/pgschema@latest
# Ensure ~/go/bin is in PATH:
export PATH="$PATH:$HOME/go/bin"
```

## Database Setup

### 1. PostgreSQL Installation and Configuration

```bash
# Start and enable PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Set password for postgres user
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'secure_password';"

# Create your OS user's database (database name follows the pattern ${USER}_memory)
DB_USER=$(whoami)
DB_NAME="${DB_USER//-/_}_memory"
sudo -u postgres createuser "$DB_USER" --createdb --login
sudo -u postgres createdb "$DB_NAME" --owner="$DB_USER"
```

### 2. Install pgvector Extension

```bash
# Install pgvector for vector embeddings
sudo apt install -y postgresql-16-pgvector

# Or build from source if not available in package manager
git clone --branch v0.5.1 https://github.com/pgvector/pgvector.git
cd pgvector
make
sudo make install
```

### 3. Database Configuration

Edit PostgreSQL configuration for optimal performance:

```bash
sudo nano /etc/postgresql/16/main/postgresql.conf
```

**Key settings:**
```ini
# Memory settings
shared_buffers = 256MB
work_mem = 4MB
maintenance_work_mem = 64MB

# Connection settings  
max_connections = 100
listen_addresses = 'localhost'

# Enable logging for debugging
log_statement = 'all'  # Remove in production
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
```

Restart PostgreSQL:
```bash
sudo systemctl restart postgresql
```

### 4. Apply Schema

```bash
# Clone nova-memory repository
git clone https://github.com/NOVA-Openclaw/nova-memory.git ~/.openclaw/workspace/nova-memory
cd ~/.openclaw/workspace/nova-memory

# Run the installer (handles schema application, hooks, and config)
./shell-install.sh    # Interactive: prompts for DB details and API keys, then execs agent-install.sh
                      # Exits immediately (non-zero) if config is missing and stdin is not a TTY
# OR
./agent-install.sh    # Non-interactive: reads ~/.openclaw/postgres.json directly (no prompts)
```

### Installer Step Order

The installer runs these steps in order:

| Step | What happens |
|------|-------------|
| Pre-migrations | Runs `*.sql` files in `pre-migrations/` (data transforms before schema diff) |
| **Step 1.5** | Reads `memory/database/renames.json` and applies column/table renames idempotently via `ALTER TABLE … RENAME COLUMN`. Drops listed are whitelisted in the pgschema hazard filter. |
| pgschema plan | Diffs `database/schema.sql` against live DB |
| Hazard check | Blocks destructive operations (DROP TABLE, DROP COLUMN) unless whitelisted in `renames.json` |
| pgschema apply | Applies the approved plan |

**When you update the schema with renames:** Add an entry to `memory/database/renames.json` so Step 1.5 can apply the rename before pgschema sees the diff. Without this, pgschema would interpret a rename as a drop + add, which would be blocked by the hazard check or lose existing data.

## Environment Configuration

### 1. Environment Variables

Create environment configuration:

Database credentials are managed through `~/.openclaw/postgres.json` (created by `shell-install.sh`):

```json
{
  "host": "localhost",
  "port": 5432,
  "database": "nova_memory",
  "user": "nova",
  "password": "your_password"
}
```

See [Database Configuration](database-config.md) for full details on the config file format and resolution order.

API keys go in `~/.openclaw/openclaw.json` (also created by `shell-install.sh`):

```bash
# Or set directly in environment:
export ANTHROPIC_API_KEY=your_anthropic_key_here
export OPENAI_API_KEY=your_openai_key_here  # Required for semantic recall embeddings
```

### 2. Script Permissions

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Test database connectivity
./scripts/process-input.sh "Test setup - Hello world"
```

## OpenClaw Integration

### 1. Install Hooks

```bash
# Run the agent installer (handles hook installation automatically)
cd ~/.openclaw/workspace/nova-memory
./agent-install.sh
```

The installer copies hooks to the OpenClaw hooks directory and enables them automatically.

### 2. Memory Hook Installation (Manual)

```bash
# Copy memory extraction hook
cp -r ~/.openclaw/workspace/nova-memory/hooks/memory-extract ~/.openclaw/workspace/hooks/

# Enable the hook
openclaw hooks enable memory-extract
```

### 3. Agent Configuration

Configure NOVA's memory system in `~/.openclaw/workspace/AGENTS.md`:

```markdown
## Database Priority

**ALWAYS check PostgreSQL database FIRST** before searching files or making assumptions.

### Quick Schema Reference
- `entities` - People, AIs, organizations (id, name, type)
- `entity_facts` - Key-value facts about entities  
- `projects` - Active work (name, status, goal, repo_url)
- `events` - Timeline of what happened
- `agents` - Registry of available AI agents
- `sops` - Standard Operating Procedures

### Common Queries
```sql
-- Find entity
SELECT * FROM entities WHERE name ILIKE 'druid';

-- Get facts about someone  
SELECT ef.key, ef.value FROM entity_facts ef
JOIN entities e ON ef.entity_id = e.id
WHERE e.name = 'druid';

-- Active projects
SELECT name, status, goal FROM projects WHERE status = 'active';
```
```

## Automated Processing Setup

### 1. Cron Job Configuration

```bash
# Create log directory
mkdir -p ~/.openclaw/logs

# Add cron job for memory extraction
(crontab -l 2>/dev/null; echo "* * * * * source ~/.bashrc && $HOME/nova-memory/scripts/memory-catchup.sh >> ~/.openclaw/logs/memory-catchup.log 2>&1") | crontab -

# Verify cron job
crontab -l
```

### 2. Log Rotation

```bash
# Create logrotate configuration
sudo tee /etc/logrotate.d/nova-memory << EOF
$HOME/.openclaw/logs/memory-catchup.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 $(whoami) $(whoami)
}
EOF
```

### 3. Systemd Service (Optional)

For production deployments, create a systemd service:

```bash
# Create service file
sudo tee /etc/systemd/system/nova-memory.service << EOF
[Unit]
Description=NOVA Memory Extraction Service
After=postgresql.service

[Service]
Type=simple
User=$(whoami)
Environment=HOME=$HOME
EnvironmentFile=$HOME/.nova-memory-env
ExecStart=$HOME/nova-memory/scripts/memory-catchup.sh
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

# Enable service
sudo systemctl daemon-reload
sudo systemctl enable nova-memory.service
sudo systemctl start nova-memory.service
```

## Agent Chat Setup

### 1. Install Plugin

```bash
# Clone plugin repository  
git clone https://github.com/NOVA-Openclaw/nova_scripts.git
cp -r nova_scripts/openclaw-plugins/agent-chat-channel ~/.openclaw/workspace/plugins/

# Enable plugin
openclaw plugins enable agent-chat-channel
```

### 2. Configure NOTIFY/LISTEN

PostgreSQL configuration for inter-agent messaging:

```sql
-- Verify NOTIFY works
NOTIFY agent_chat, 'test message';

-- Check for listening connections
SELECT * FROM pg_stat_activity WHERE state = 'idle in transaction';
```

### 3. Test Inter-Agent Communication

```bash
# Terminal 1: Start listener
psql -c "LISTEN agent_chat;"

# Terminal 2: Send message via send_agent_message() (direct INSERT is blocked)
psql -c "SELECT send_agent_message('nova', 'Hello world', ARRAY['test_agent']);"
```

## Performance Optimization

### 1. Database Tuning

```sql
-- Create essential indexes
CREATE INDEX CONCURRENTLY idx_entities_name ON entities(name);
CREATE INDEX CONCURRENTLY idx_entity_facts_entity_id ON entity_facts(entity_id);
CREATE INDEX CONCURRENTLY idx_events_date ON events(date);
CREATE INDEX CONCURRENTLY idx_agent_chat_recipients ON agent_chat USING gin(recipients);

-- Update table statistics
ANALYZE;
```

### 2. Connection Pooling

Install and configure PgBouncer:

```bash
# Install PgBouncer
sudo apt install -y pgbouncer

# Configure
sudo tee /etc/pgbouncer/pgbouncer.ini << EOF
[databases]
nova_memory = host=localhost dbname=nova_memory user=nova

[pgbouncer]
pool_mode = transaction
listen_port = 6432
listen_addr = localhost
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
max_client_conn = 100
default_pool_size = 20
EOF

# Create user list
echo '"nova" "nova_password"' | sudo tee /etc/pgbouncer/userlist.txt

# Start PgBouncer
sudo systemctl start pgbouncer
sudo systemctl enable pgbouncer

# Update connection string to use PgBouncer
export PGPORT=6432
```

### 3. Memory Settings

```bash
# Optimize for memory extraction workload
echo 'vm.overcommit_memory = 2' | sudo tee -a /etc/sysctl.conf
echo 'vm.overcommit_ratio = 80' | sudo tee -a /etc/sysctl.conf

# Apply settings
sudo sysctl -p
```

## Monitoring and Health Checks

### 1. Health Check Script

Create monitoring script:

```bash
HEALTH_CHECK_SCRIPT="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/nova-memory/scripts/health-check.sh" && cat > "$HEALTH_CHECK_SCRIPT" << 'EOF'
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== NOVA Memory System Health Check ==="

# Database connectivity
echo -n "Database connection: "
if psql -c "SELECT 1" >/dev/null 2>&1; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Schema integrity
echo -n "Schema integrity: "
EXPECTED_TABLES=("entities" "entity_facts" "projects" "agents" "agent_chat" "sops" "lessons")
MISSING_TABLES=()

for table in "${EXPECTED_TABLES[@]}"; do
    if ! psql -c "\dt $table" 2>/dev/null | grep -q "$table"; then
        MISSING_TABLES+=("$table")
    fi
done

if [ ${#MISSING_TABLES[@]} -eq 0 ]; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}MISSING TABLES: ${MISSING_TABLES[*]}${NC}"
fi

# API connectivity
echo -n "Anthropic API: "
if [ -n "$ANTHROPIC_API_KEY" ]; then
    if echo "test" | timeout 10 ./extract-memories.sh >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}TIMEOUT/ERROR${NC}"
    fi
else
    echo -e "${RED}NO API KEY${NC}"
fi

# Cron job status  
echo -n "Cron job: "
if crontab -l | grep -q memory-catchup; then
    echo -e "${GREEN}INSTALLED${NC}"
else
    echo -e "${YELLOW}NOT FOUND${NC}"
fi

# Recent extraction activity
echo -n "Recent extractions: "
RECENT_COUNT=$(psql -t -c "SELECT COUNT(*) FROM entities WHERE created_at > NOW() - INTERVAL '1 hour';" 2>/dev/null || echo 0)
if [ "$RECENT_COUNT" -gt 0 ]; then
    echo -e "${GREEN}$RECENT_COUNT in last hour${NC}"
else
    echo -e "${YELLOW}None in last hour${NC}"
fi

# Log file size
if [ -f ~/.openclaw/logs/memory-catchup.log ]; then
    LOG_SIZE=$(du -h ~/.openclaw/logs/memory-catchup.log | cut -f1)
    echo "Log file size: $LOG_SIZE"
fi

echo "=== Health Check Complete ==="
EOF

chmod +x "${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/nova-memory/scripts/health-check.sh"
```

### 2. Monitoring Dashboard

Simple monitoring with SQL queries:

```sql
-- Create monitoring view
CREATE OR REPLACE VIEW system_stats AS
SELECT 
    'entities' as table_name,
    COUNT(*) as total_records,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') as recent_24h,
    COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour') as recent_1h
FROM entities
UNION ALL
SELECT 'events', COUNT(*), 
       COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours'),
       COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '1 hour')
FROM events
UNION ALL  
SELECT 'agent_chat', COUNT(*),
       COUNT(*) FILTER (WHERE "timestamp" > NOW() - INTERVAL '24 hours'),
       COUNT(*) FILTER (WHERE "timestamp" > NOW() - INTERVAL '1 hour')
FROM agent_chat;

-- Query system health
SELECT * FROM system_stats;
-- Or use the built-in view:
SELECT * FROM v_agent_chat_stats;
```

## Security Configuration

### 1. Database Security

```sql
-- Create read-only user for monitoring (replace nova_memory with your actual DB name)
CREATE USER nova_readonly WITH PASSWORD 'readonly_password';
GRANT CONNECT ON DATABASE nova_memory TO nova_readonly;
GRANT USAGE ON SCHEMA public TO nova_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO nova_readonly;

-- Revoke dangerous permissions
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

### 2. File Permissions

```bash
# Secure OpenClaw config directory
chmod 700 ~/.openclaw/
chmod 600 ~/.openclaw/postgres.json
chmod +x ~/.openclaw/workspace/nova-memory/scripts/*.sh

# Secure log directory
mkdir -p ~/.openclaw/logs
chmod 750 ~/.openclaw/logs
```

### 3. API Key Management

```bash
# Use 1Password CLI for secure API key storage
op item create \
    --category "API Credential" \
    --title "Anthropic API - NOVA Memory" \
    --vault "Development" \
    "api_key[password]=$ANTHROPIC_API_KEY"

# Reference from scripts instead of environment
# export ANTHROPIC_API_KEY=$(op read "op://Development/Anthropic API - NOVA Memory/api_key")
```

## Troubleshooting Common Issues

### 1. Database Connection Issues

```bash
# Test basic connectivity
pg_isready -h localhost -p 5432 -U "${PGUSER:-$(whoami)}"

# Check PostgreSQL status
sudo systemctl status postgresql

# View recent logs
sudo tail -f /var/log/postgresql/postgresql-16-main.log
```

### 2. Memory Extraction Not Working

```bash
# Check cron job
crontab -l | grep memory-catchup

# Test manual extraction
./scripts/process-input.sh "Test message from $(whoami)"

# Check logs
tail -f ~/.openclaw/logs/memory-catchup.log

# Verify API key
echo "test" | ./scripts/extract-memories.sh
```

### 3. Performance Issues

```sql
-- Check slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements 
ORDER BY mean_exec_time DESC 
LIMIT 10;

-- Check table sizes
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### 4. Hook Integration Issues

```bash
# Verify hook installation
openclaw hooks list

# Check hook logs
tail -f ~/.openclaw/logs/hook-memory-extract.log

# Test hook manually
openclaw hooks run memory-extract '{"type": "message:received", "message": "test"}'
```

## Backup and Recovery

### 1. Database Backup

```bash
# Create backup script
BACKUP_SCRIPT="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/nova-memory/scripts/backup.sh" && cat > "$BACKUP_SCRIPT" << 'EOF'
#!/bin/bash

BACKUP_DIR="$HOME/nova-memory-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/nova_memory_$DATE.sql"

mkdir -p "$BACKUP_DIR"

# Create backup
pg_dump -f "$BACKUP_FILE"

# Compress
gzip "$BACKUP_FILE"

# Keep only last 7 backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete

echo "Backup created: $BACKUP_FILE.gz"
EOF

chmod +x "${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/nova-memory/scripts/backup.sh"

# Schedule daily backups
(crontab -l 2>/dev/null; echo "0 2 * * * ${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/nova-memory/scripts/backup.sh") | crontab -
```

### 2. Recovery Process

```bash
# Restore from backup
gunzip -c nova_memory_20260208_020000.sql.gz | psql -d "${PGDATABASE:-${USER//-/_}_memory}_restore"

# Verify restoration
psql -d "${PGDATABASE:-${USER//-/_}_memory}_restore" -c "SELECT COUNT(*) FROM entities;"
```

## Production Deployment Checklist

### Pre-Deployment
- [ ] Server meets minimum requirements
- [ ] PostgreSQL installed and configured
- [ ] All dependencies installed
- [ ] Schema applied successfully
- [ ] Environment variables configured
- [ ] API keys stored securely

### Configuration
- [ ] Cron job scheduled for memory extraction
- [ ] Log rotation configured
- [ ] Monitoring scripts installed
- [ ] Backup strategy implemented
- [ ] Security settings applied

### Testing
- [ ] Health check passes
- [ ] Manual extraction works
- [ ] Inter-agent chat functional
- [ ] Performance benchmarks met
- [ ] Backup/restore tested

### Go-Live
- [ ] Services started
- [ ] Monitoring alerts configured
- [ ] Documentation provided to team
- [ ] Runbook created for operations

**Note for Documentation Team:** The deployment architecture combining PostgreSQL, cron jobs, and inter-agent messaging would benefit from **Quill haiku collaboration** to create intuitive explanations of the complex integration points and failure recovery patterns.

## Next Steps

After successful deployment:

1. **Monitor performance** - Watch extraction rates and database growth
2. **Tune configuration** - Adjust batch sizes and API limits based on usage
3. **Set up alerting** - Configure notifications for system failures
4. **Plan scaling** - Design multi-node architecture for growth
5. **Security hardening** - Implement proper authentication and encryption

The nova-memory system is designed to run reliably with minimal maintenance once properly deployed. Regular monitoring and periodic updates will ensure optimal performance as your AI assistant's knowledge grows.