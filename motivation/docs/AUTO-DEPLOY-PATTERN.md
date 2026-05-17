# Auto-Deploy Script Pattern

Automated deployment pattern used across NOVA repos for seamless code-to-production workflows.

## Overview

The auto-deploy pattern uses Git's post-merge hook to trigger deployment scripts automatically after successful `git pull` operations. This ensures that local environments stay in sync with the latest code and that services restart as needed without manual intervention.

**Flow**: GitHub PR merged → Local `git pull` → post-merge hook fires → deploy.sh runs → notification sent

## Core Components

### 1. Post-Merge Hook
**Location**: `.git/hooks/post-merge`

```bash
#!/bin/bash
# Auto-deploy [repo-name] after merge to main
~/path/to/repo/scripts/deploy.sh
```

- Executable shell script that triggers on successful git merge/pull
- Minimal wrapper that calls the main deployment script
- Must be executable (`chmod +x .git/hooks/post-merge`)

### 2. Deployment Script
**Location**: `scripts/deploy.sh`

Core deployment logic with these standard components:
- **Error handling**: `set -e` to exit on errors
- **Logging**: Timestamped logs with `log()` function
- **Commit tracking**: Log the deployed commit hash
- **Notifications**: agent_chat integration via PostgreSQL
- **Service management**: Start/stop/restart as needed

## Use Case Examples

### nova-website (Static Files)

**Repository**: NOVA-Openclaw/nova-website (private)  
**Live Location**: `~/www/static/`  
**Type**: Static website deployment

```bash
#!/bin/bash
# nova-website deployment script
set -e

WEBSITE_DIR="$HOME/www/static"
LOG_FILE="$HOME/clawd/logs/website-deploy.log"

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

cd "$WEBSITE_DIR"

log "Website updated via post-merge hook"
log "Commit: $(git rev-parse --short HEAD)"

# Notify via agent_chat
psql -d nova_memory -q << EOSQL
INSERT INTO agent_chat (sender, message, mentions)
VALUES ('system', 'nova-website auto-deployed via post-merge hook.
Commit: $(git rev-parse --short HEAD)
Time: $(date -Iseconds)', ARRAY['NOVA']);
EOSQL

log "Deployment complete"
```

**Post-merge hook**:
```bash
#!/bin/bash
# Auto-deploy nova-website after merge to main
~/www/static/scripts/deploy.sh
```

### nova-dashboard (Node.js Service)

**Repository**: NOVA-Openclaw/nova-dashboard  
**Live Location**: `~/clawd/nova-dashboard/`  
**Type**: Node.js service with restart capability

**Key Features**:
- Dependency management (npm install if package.json changed)
- Process management with PID files
- Graceful service restart
- Health check verification
- Port-specific service binding (3847 for dashboard)

### nova-motivation (Documentation)

**Repository**: NOVA-Openclaw/nova-motivation  
**Live Location**: `~/clawd/nova-motivation/`  
**Type**: Documentation-only deployment

**Simplified Pattern**:
- No service restarts needed
- Basic logging and notification
- Minimal deployment overhead

## Deploy Script Template

### Standard Structure
```bash
#!/bin/bash
# [repo-name] deployment script
# Called by post-merge hook after git pull

set -e

REPO_DIR="$HOME/path/to/repo"
LOG_FILE="$HOME/clawd/logs/[repo-name]-deploy.log"

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

cd "$REPO_DIR"

log "[Repo Name] updated via post-merge hook"
log "Commit: $(git rev-parse --short HEAD)"

# [Service-specific deployment steps here]

# Notify via agent_chat
psql -d nova_memory -q << EOSQL
INSERT INTO agent_chat (sender, message, mentions)
VALUES ('system', '[repo-name] auto-deployed via post-merge hook.
Commit: $(git rev-parse --short HEAD)
Time: $(date -Iseconds)', ARRAY['NOVA']);
EOSQL

log "Deployment complete"
```

### Service-Specific Additions

**For Node.js Services**:
```bash
# Install dependencies if package.json changed
if git diff HEAD~1 --name-only 2>/dev/null | grep -q "package.json"; then
    log "package.json changed, running npm install..."
    npm install
fi

# Process management
PID_FILE="$REPO_DIR/.service.pid"
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "Stopping existing service (PID $OLD_PID)..."
        kill "$OLD_PID"
        sleep 2
    fi
    rm -f "$PID_FILE"
fi

# Start service
log "Starting service..."
nohup node server.js > "$HOME/clawd/logs/service.log" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PID_FILE"

# Health check
sleep 3
if curl -s -o /dev/null -w "%{http_code}" http://localhost:PORT/ | grep -q "200"; then
    log "✅ Service deployed successfully (PID $NEW_PID)"
else
    log "⚠️ Service may not have started correctly"
fi
```

**For Static Sites**:
```bash
# Static sites typically need no additional processing
# Files are already in place after git pull
```

## Repositories Using This Pattern

| Repository | Type | Special Features |
|------------|------|------------------|
| **nova-website** | Static files | Direct file serving |
| **nova-dashboard** | Node.js service | Process restart, health checks |
| **nova-motivation** | Documentation | Minimal processing |

## Setup Instructions

### For New Repository

1. **Create deployment script**:
   ```bash
   mkdir -p scripts
   cp /path/to/template/deploy.sh scripts/deploy.sh
   chmod +x scripts/deploy.sh
   ```

2. **Customize the script**:
   - Update repository paths and names
   - Add service-specific logic
   - Configure logging paths

3. **Create post-merge hook**:
   ```bash
   cat > .git/hooks/post-merge << EOF
   #!/bin/bash
   # Auto-deploy [repo-name] after merge to main
   ~/path/to/repo/scripts/deploy.sh
   EOF
   chmod +x .git/hooks/post-merge
   ```

4. **Test the setup**:
   ```bash
   # Simulate a merge
   git pull
   # Check logs
   tail -f ~/clawd/logs/[repo-name]-deploy.log
   ```

### Directory Structure
```
repository/
├── .git/
│   └── hooks/
│       └── post-merge          # Git hook (executable)
├── scripts/
│   └── deploy.sh              # Deployment logic (executable)
└── [application files]
```

## Logging and Monitoring

### Log Locations
- **Deployment logs**: `~/clawd/logs/[repo-name]-deploy.log`
- **Service logs**: `~/clawd/logs/[service-name].log`

### Notification System
All deployments notify via the `agent_chat` system:
```sql
INSERT INTO agent_chat (sender, message, mentions)
VALUES ('system', '[repo-name] auto-deployed via post-merge hook.
Commit: [hash]
Time: [timestamp]', ARRAY['NOVA']);
```

### Monitoring
- Check deployment success via agent_chat notifications
- Monitor service health through log files
- Verify deployments with commit hash tracking

## Benefits

1. **Zero-Touch Deployment**: Changes go live automatically after merge
2. **Consistency**: Same pattern across all repositories
3. **Visibility**: All deployments logged and reported
4. **Reliability**: Error handling and service verification
5. **Simplicity**: Minimal setup, maximum automation

## Troubleshooting

### Common Issues
- **Hook not executable**: `chmod +x .git/hooks/post-merge`
- **Script permissions**: `chmod +x scripts/deploy.sh`
- **Path issues**: Use absolute paths in deployment scripts
- **Service conflicts**: Check for running processes before starting

### Testing
```bash
# Test deployment script directly
~/path/to/repo/scripts/deploy.sh

# Simulate merge to test hook
git pull --no-ff origin main
```

---

*This pattern is used across all active NOVA repositories for consistent, reliable automated deployments.*