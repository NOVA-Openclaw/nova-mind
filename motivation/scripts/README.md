# Deployment Scripts

This directory contains automation scripts for the NOVA Motivation System.

## auto-deploy.sh

Automated deployment script that handles deployment and sends notifications to NOVA.

### Features

- **Deployment automation**: Performs deployment steps (tests, build, install)
- **Signal notifications**: Sends deployment status via Signal message
- **Wake events**: Triggers OpenClaw wake events as a fallback notification method
- **Deployment markers**: Creates JSON markers for heartbeat checks
- **Error handling**: Catches failures and sends appropriate notifications

### Usage

Basic usage:
```bash
./scripts/auto-deploy.sh
```

With custom configuration:
```bash
SIGNAL_RECIPIENT="+1234567890" \
WORK_DIR="/path/to/repo" \
./scripts/auto-deploy.sh
```

### Configuration

Configuration can be provided via:

1. **Environment variables** (highest priority)
2. **Configuration file**: `scripts/deploy-notify.conf`
3. **Default values** (lowest priority)

#### Environment Variables

- `SIGNAL_RECIPIENT`: Phone number to send Signal notifications (required)
- `OPENCLAW_BIN`: Path to openclaw binary (default: `openclaw`)
- `DEPLOY_LOG`: Path to deployment log file (default: `/tmp/deploy.log`)
- `WORK_DIR`: Repository working directory (default: current directory)

#### Example Configuration File

Create `scripts/deploy-notify.conf`:

```bash
SIGNAL_RECIPIENT="+1234567890"
OPENCLAW_BIN="/usr/local/bin/openclaw"
DEPLOY_LOG="/var/log/nova-motivation/deploy.log"
```

Then source it in your script:
```bash
source scripts/deploy-notify.conf
./scripts/auto-deploy.sh
```

### Notification Methods

The script attempts multiple notification methods in order:

1. **OpenClaw message tool** (preferred)
   ```bash
   openclaw message send --target "+1234567890" --message "..."
   ```

2. **signal-cli** (fallback)
   ```bash
   signal-cli -u "+1234567890" send -m "..." "+1234567890"
   ```

3. **OpenClaw wake event** (always triggered as backup)
   ```bash
   openclaw cron wake --reason "deployment-success-..."
   ```

4. **Deployment marker file** (for heartbeat checks)
   - Creates: `~/.openclaw/deployments/nova-motivation-latest.json`
   - Contains: repo, status, commit, timestamp, message

### Integration with CI/CD

#### GitHub Actions

```yaml
name: Deploy and Notify

on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run deployment
        env:
          SIGNAL_RECIPIENT: ${{ secrets.NOVA_SIGNAL_NUMBER }}
        run: |
          chmod +x scripts/auto-deploy.sh
          ./scripts/auto-deploy.sh
```

#### GitLab CI

```yaml
deploy:
  stage: deploy
  script:
    - chmod +x scripts/auto-deploy.sh
    - SIGNAL_RECIPIENT="${NOVA_SIGNAL_NUMBER}" ./scripts/auto-deploy.sh
  only:
    - main
```

#### Manual Deployment

For manual deployments:

```bash
# Navigate to repository
cd /path/to/nova-motivation

# Set Signal recipient
export SIGNAL_RECIPIENT="+1234567890"

# Run deployment
./scripts/auto-deploy.sh
```

### Deployment Markers

The script creates deployment markers that can be checked during heartbeats:

```bash
# Check latest deployment
cat ~/.openclaw/deployments/nova-motivation-latest.json
```

Example marker:
```json
{
  "repo": "nova-motivation",
  "status": "SUCCESS",
  "commit": "abc123def456...",
  "timestamp": "2026-02-12T03:30:00Z",
  "message": "Deployment completed successfully\nCommit: Add deployment notifications",
  "notified_at": "2026-02-12T03:30:15Z"
}
```

### Heartbeat Integration

NOVA can check deployment markers during heartbeats:

```javascript
// In HEARTBEAT.md or heartbeat handler
const fs = require('fs');
const markerPath = `${process.env.HOME}/.openclaw/deployments/nova-motivation-latest.json`;

if (fs.existsSync(markerPath)) {
  const deployment = JSON.parse(fs.readFileSync(markerPath, 'utf8'));
  const notifiedAt = new Date(deployment.notified_at);
  const now = new Date();
  
  // If deployment happened in last hour and not yet acknowledged
  if ((now - notifiedAt) < 3600000) {
    console.log(`Recent deployment: ${deployment.status} at ${deployment.timestamp}`);
    console.log(`Commit: ${deployment.commit}`);
  }
}
```

### Testing

Test the notification system without deploying:

```bash
# Test Signal notification
SIGNAL_RECIPIENT="+1234567890" \
bash -c 'source scripts/auto-deploy.sh && send_signal_notification "Test message"'

# Test wake event
bash -c 'source scripts/auto-deploy.sh && trigger_wake_event "test-deployment"'

# Test full notification
SIGNAL_RECIPIENT="+1234567890" \
bash -c 'source scripts/auto-deploy.sh && notify_deployment "TEST" "abc123" "2026-02-12T03:30:00Z" "Test deployment"'
```

### Troubleshooting

#### Signal messages not being delivered

1. Check Signal recipient configuration:
   ```bash
   echo $SIGNAL_RECIPIENT
   ```

2. Test signal-cli manually:
   ```bash
   signal-cli -u "+1234567890" send -m "Test" "+1234567890"
   ```

3. Check OpenClaw message configuration:
   ```bash
   openclaw message send --help
   ```

#### Wake events not triggering

1. Verify OpenClaw is installed:
   ```bash
   which openclaw
   ```

2. Test wake command manually:
   ```bash
   openclaw cron wake --reason "test"
   ```

3. Check OpenClaw logs:
   ```bash
   openclaw logs | grep wake
   ```

#### Deployment failures not notifying

1. Check deployment log:
   ```bash
   tail -f /tmp/deploy.log
   ```

2. Verify error handler is working:
   ```bash
   # This should trigger error handler
   SIGNAL_RECIPIENT="+1234567890" bash -c 'set -e; false' || echo "Error caught"
   ```

### Security Considerations

- **Credentials**: Never commit Signal numbers or API keys to the repository
- **Environment variables**: Use secure methods to inject credentials (secrets management)
- **Log files**: Deployment logs may contain sensitive information
- **Permissions**: Ensure deployment scripts have appropriate file permissions (755)

### Customization

To customize the deployment steps, edit the `deploy()` function in `auto-deploy.sh`:

```bash
deploy() {
    # ... existing code ...
    
    log "Step 3: Custom deployment step..."
    # Add your custom commands here
    make deploy
    systemctl restart my-service
    
    # ... rest of function ...
}
```

## gh-issue-create.sh

GitHub issue creation utility (see existing documentation).
