#!/bin/bash
# auto-deploy.sh - Automated deployment script with notifications
# This script handles deployment and sends alerts to NOVA via Signal and OpenClaw wake events

set -euo pipefail

# Configuration
REPO_NAME="nova-motivation"
SIGNAL_RECIPIENT="${SIGNAL_RECIPIENT:-+1234567890}"  # Override with env var or config
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
DEPLOY_LOG="${DEPLOY_LOG:-/tmp/deploy.log}"
WORK_DIR="${WORK_DIR:-$(pwd)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$DEPLOY_LOG"
}

# Function to get commit hash
get_commit_hash() {
    cd "$WORK_DIR" && git rev-parse HEAD 2>/dev/null || echo "unknown"
}

# Function to get commit message
get_commit_message() {
    cd "$WORK_DIR" && git log -1 --pretty=%B 2>/dev/null || echo "No commit message"
}

# Function to send Signal message
send_signal_notification() {
    local message="$1"
    local success=false
    
    # Try multiple Signal sending methods
    # Method 1: OpenClaw message tool (preferred)
    if command -v "$OPENCLAW_BIN" &> /dev/null; then
        log "Attempting to send Signal via OpenClaw..."
        if timeout 30s "$OPENCLAW_BIN" message send --target "$SIGNAL_RECIPIENT" --message "$message" 2>&1 | tee -a "$DEPLOY_LOG"; then
            log "${GREEN}✓${NC} Signal message sent via OpenClaw"
            success=true
        else
            log "${YELLOW}⚠${NC} Failed to send via OpenClaw message tool"
        fi
    fi
    
    # Method 2: signal-cli (fallback)
    if ! $success && command -v signal-cli &> /dev/null; then
        log "Attempting to send Signal via signal-cli..."
        if timeout 30s signal-cli -u "$SIGNAL_RECIPIENT" send -m "$message" "$SIGNAL_RECIPIENT" 2>&1 | tee -a "$DEPLOY_LOG"; then
            log "${GREEN}✓${NC} Signal message sent via signal-cli"
            success=true
        else
            log "${YELLOW}⚠${NC} Failed to send via signal-cli"
        fi
    fi
    
    if ! $success; then
        log "${YELLOW}⚠${NC} All Signal delivery methods failed"
    fi
    
    return $([ "$success" = true ] && echo 0 || echo 1)
}

# Function to trigger OpenClaw wake event
trigger_wake_event() {
    local reason="$1"
    
    log "Triggering OpenClaw wake event..."
    
    if command -v "$OPENCLAW_BIN" &> /dev/null; then
        if "$OPENCLAW_BIN" cron wake --reason "$reason" 2>&1 | tee -a "$DEPLOY_LOG"; then
            log "${GREEN}✓${NC} OpenClaw wake event triggered"
            return 0
        else
            log "${RED}✗${NC} Failed to trigger wake event"
            return 1
        fi
    else
        log "${YELLOW}⚠${NC} OpenClaw binary not found, cannot trigger wake event"
        return 1
    fi
}

# Function to send notification (Signal + wake event)
notify_deployment() {
    local status="$1"
    local commit_hash="$2"
    local timestamp="$3"
    local extra_info="$4"
    
    # Format message
    local message="🚀 Deployment Alert

Repository: $REPO_NAME
Status: $status
Commit: $commit_hash
Time: $timestamp

$extra_info"
    
    log "Sending deployment notification..."
    log "Status: $status"
    log "Commit: $commit_hash"
    
    # Send Signal message (best effort)
    send_signal_notification "$message" || true
    
    # Always trigger wake event as backup/fallback
    local wake_reason="deployment-${status,,}-${REPO_NAME}-${commit_hash:0:7}"
    trigger_wake_event "$wake_reason" || true
    
    # Create a deployment marker file for heartbeat checks
    local marker_dir="$HOME/.openclaw/deployments"
    mkdir -p "$marker_dir"
    local marker_file="$marker_dir/${REPO_NAME}-latest.json"
    
    cat > "$marker_file" <<EOF
{
  "repo": "$REPO_NAME",
  "status": "$status",
  "commit": "$commit_hash",
  "timestamp": "$timestamp",
  "message": $(echo "$extra_info" | jq -Rs .),
  "notified_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Deployment marker created at $marker_file"
}

# Function to perform deployment
deploy() {
    local commit_hash
    local timestamp
    local commit_message
    
    log "${GREEN}Starting deployment for $REPO_NAME${NC}"
    
    # Get deployment metadata
    commit_hash=$(get_commit_hash)
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    commit_message=$(get_commit_message)
    
    log "Commit hash: $commit_hash"
    log "Commit message: $commit_message"
    
    # Simulate/perform actual deployment steps
    # In a real deployment, replace these with actual deployment commands
    
    log "Step 1: Checking repository status..."
    cd "$WORK_DIR"
    
    if ! git status &> /dev/null; then
        log "${RED}✗${NC} Not a git repository!"
        notify_deployment "FAILED" "$commit_hash" "$timestamp" "Error: Not a git repository"
        return 1
    fi
    
    log "Step 2: Running tests..."
    # Example: npm test || python -m pytest
    # For now, we'll just check if there are any test files
    if [ -d "tests" ]; then
        log "Tests directory found"
        # Add actual test commands here
    fi
    
    log "Step 3: Building/Installing..."
    # Example: npm install && npm run build
    # Or: pip install -e .
    if [ -f "package.json" ]; then
        log "Node.js project detected"
        # npm install && npm run build
    elif [ -f "requirements.txt" ]; then
        log "Python project detected"
        # pip install -r requirements.txt
    fi
    
    log "Step 4: Deployment complete"
    
    # Success notification
    notify_deployment "SUCCESS" "$commit_hash" "$timestamp" "Deployment completed successfully
Commit: $commit_message"
    
    log "${GREEN}✓ Deployment successful${NC}"
    return 0
}

# Main function
main() {
    local exit_code=0
    
    log "=== Auto-Deploy Script Started ==="
    
    # Trap errors to send failure notifications
    trap 'handle_error $? $LINENO' ERR
    
    # Run deployment
    if deploy; then
        log "Deployment completed successfully"
        exit_code=0
    else
        log "Deployment failed"
        exit_code=1
    fi
    
    log "=== Auto-Deploy Script Finished ==="
    
    return $exit_code
}

# Error handler
handle_error() {
    local exit_code=$1
    local line_number=$2
    local commit_hash
    local timestamp
    
    commit_hash=$(get_commit_hash)
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    log "${RED}✗ Deployment failed at line $line_number with exit code $exit_code${NC}"
    
    # Get error context
    local error_msg="Deployment failed at line $line_number
Exit code: $exit_code
See deployment log for details"
    
    # Send failure notification
    notify_deployment "FAILED" "$commit_hash" "$timestamp" "$error_msg"
    
    exit $exit_code
}

# Run main function
main "$@"
