# Issue: agent-install.sh should restart or warn about gateway restart

## Context

When `agent-install.sh` runs while the gateway is already running, installed changes (hooks, skills, config) are not picked up until the gateway is manually restarted. Plugins and hooks are loaded once at startup and cached for the process lifetime — config hot-reload does not reload them.

This was identified as part of nova-cognition Issue #149, where the `agent_chat` plugin failed silently because the gateway wasn't restarted after installation.

## Problem

`agent-install.sh` completes successfully but doesn't restart the gateway or warn that a restart is needed. The operator assumes everything is working, but the gateway is still running with stale state.

## Fix

At the end of `agent-install.sh`, add:

```bash
# Check if gateway is running and warn/restart
if systemctl --user is-active openclaw-gateway &>/dev/null; then
    if [ "${NO_RESTART:-0}" = "1" ] || [ "${1:-}" = "--no-restart" ]; then
        echo ""
        echo "⚠️  Gateway is running. Restart required for changes to take effect:"
        echo "   systemctl --user restart openclaw-gateway"
    else
        echo ""
        echo "Restarting gateway to apply changes..."
        systemctl --user restart openclaw-gateway
        echo "✅ Gateway restarted"
    fi
fi
```

## Acceptance Criteria

- [ ] Running gateway detected at end of install
- [ ] Gateway auto-restarts by default after successful install
- [ ] `--no-restart` flag (or `NO_RESTART=1` env var) suppresses auto-restart and prints manual command instead
- [ ] No error if gateway is not running (script exits cleanly)
