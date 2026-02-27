# Database Aliasing with pgbouncer

## Overview

NOVA and select agents share a single `nova_memory` database. To allow agents to connect using their own logical database names (following the `${USER}_memory` convention), we use pgbouncer as a connection pooler with database aliasing.

## Architecture

```
┌─────────────────┐     ┌───────────────┐     ┌─────────────────┐
│  Agent/Script   │────▶│   pgbouncer   │────▶│   PostgreSQL    │
│ quill_memory    │     │   port 6432   │     │   nova_memory   │
└─────────────────┘     └───────────────┘     └─────────────────┘
```

## Connection Details

| Parameter | Value |
|-----------|-------|
| Host | 127.0.0.1 |
| Port | 6432 (pgbouncer) |
| Direct PostgreSQL Port | 5432 |

## Database Aliases

Only agents that need persistent database access have aliases configured:

| Database Name | Target | Agent | Rationale |
|---------------|--------|-------|-----------|
| `nova_memory` | nova_memory | NOVA | Primary agent, memory owner |
| `newhart_memory` | nova_memory | Newhart | Peer agent, runs persistently |
| `argus_memory` | nova_memory | Argus | Security agent, logs findings |
| `quill_memory` | nova_memory | Quill | Writing agent, needs context |
| `quill_memory` | nova_memory | Quill | Creative agent, needs context |
| `nova_staging_memory` | nova_staging_memory | (testing) | Isolated staging environment |

### Why Not All Agents?

Most subagents (Coder, Gidget, Scout, Scribe, etc.) are **ephemeral**:
- Spawn, complete a task, and exit
- Don't connect to the database directly
- Report back to NOVA who handles memory storage
- Stateless between invocations

Only agents that run persistently or need direct database access for their function should have aliases.

## Usage

### From Scripts
```bash
# Using pgbouncer (recommended)
psql -h 127.0.0.1 -p 6432 -d quill_memory -c "SELECT * FROM entities;"

# Direct PostgreSQL (bypasses aliasing)
psql -d nova_memory -c "SELECT * FROM entities;"
```

### From Python
```python
import psycopg2

conn = psycopg2.connect(
    host="127.0.0.1",
    port=6432,
    dbname="quill_memory",  # Aliases to nova_memory
    user="quill"
)
```

### From nova-memory installer
```bash
# Default: uses ${USER}_memory
./agent-install.sh

# Override for shared database
./agent-install.sh --database nova_memory
```

## Configuration

### pgbouncer config
```
/etc/pgbouncer/pgbouncer.ini
```

### Adding a new alias
1. Edit `/etc/pgbouncer/pgbouncer.ini`
2. Add entry in `[databases]` section:
   ```ini
   new_agent_memory = host=127.0.0.1 port=5432 dbname=nova_memory
   ```
3. Add user to `/etc/pgbouncer/userlist.txt`:
   ```
   "new_agent" ""
   ```
4. Restart pgbouncer:
   ```bash
   sudo systemctl restart pgbouncer
   ```

## Troubleshooting

```bash
# Check status
sudo systemctl status pgbouncer

# View logs
sudo journalctl -u pgbouncer -f

# Test alias
psql -h 127.0.0.1 -p 6432 -d <alias_name> -c "SELECT current_database();"
```
