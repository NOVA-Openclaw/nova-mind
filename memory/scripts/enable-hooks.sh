#!/bin/bash
# enable-hooks.sh - Safely enable nova-memory hooks in OpenClaw config
# Uses jq for safe JSON patching

set -e

CONFIG_FILE="${1:-$HOME/.openclaw/openclaw.json}"
HOOKS_TO_ENABLE=("memory-extract" "semantic-recall" "session-init" "agent-turn-context")
DRY_RUN="${DRY_RUN:-0}"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "Nova-Memory Hook Configuration Tool"
echo "===================================="
echo ""
echo "Config file: $CONFIG_FILE"
echo "Hooks to enable: ${HOOKS_TO_ENABLE[*]}"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    echo "Install: sudo apt install jq"
    exit 1
fi

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi

# Validate JSON
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON in config file${NC}"
    exit 1
fi

# Create backup
BACKUP_FILE="${CONFIG_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
if [ "$DRY_RUN" -eq 0 ]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✓${NC} Created backup: $BACKUP_FILE"
else
    echo -e "${BLUE}[DRY-RUN]${NC} Would create backup: $BACKUP_FILE"
fi

# Build jq filter to enable hooks
# This handles multiple cases:
# 1. No hooks section at all
# 2. Hooks section exists but no internal section
# 3. Internal section exists but no entries
# 4. Entries exist but our hooks are missing or disabled

JQ_FILTER='
# Ensure hooks section exists
if has("hooks") | not then
  .hooks = {
    "enabled": true,
    "internal": {
      "enabled": true,
      "entries": {}
    }
  }
else . end |

# Ensure hooks.enabled is true
.hooks.enabled = true |

# Ensure internal section exists
if .hooks | has("internal") | not then
  .hooks.internal = {
    "enabled": true,
    "entries": {}
  }
else . end |

# Ensure internal.enabled is true
.hooks.internal.enabled = true |

# Ensure entries object exists
if .hooks.internal | has("entries") | not then
  .hooks.internal.entries = {}
else . end |

# Enable each hook
.hooks.internal.entries["memory-extract"] = {"enabled": true} |
.hooks.internal.entries["semantic-recall"] = {"enabled": true} |
.hooks.internal.entries["session-init"] = {"enabled": true} |
.hooks.internal.entries["agent-turn-context"] = {"enabled": true}
'

# Apply the filter
if [ "$DRY_RUN" -eq 0 ]; then
    TEMP_FILE=$(mktemp)
    if jq "$JQ_FILTER" "$CONFIG_FILE" > "$TEMP_FILE"; then
        mv "$TEMP_FILE" "$CONFIG_FILE"
        echo -e "${GREEN}✓${NC} Config updated successfully"
    else
        echo -e "${RED}Error: Failed to update config${NC}"
        rm -f "$TEMP_FILE"
        exit 1
    fi
else
    echo -e "${BLUE}[DRY-RUN]${NC} Would apply this configuration:"
    echo ""
    jq "$JQ_FILTER" "$CONFIG_FILE" | jq '.hooks'
fi

echo ""
echo "Enabled hooks:"
for hook in "${HOOKS_TO_ENABLE[@]}"; do
    STATUS=$(jq -r ".hooks.internal.entries.\"$hook\".enabled // false" "$CONFIG_FILE")
    if [ "$STATUS" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} $hook"
    else
        echo -e "  ${YELLOW}⚠${NC} $hook (status: $STATUS)"
    fi
done

echo ""
if [ "$DRY_RUN" -eq 0 ]; then
    echo -e "${GREEN}Done!${NC} Restart OpenClaw gateway for changes to take effect:"
    echo "  openclaw gateway restart"
else
    echo -e "${BLUE}[DRY-RUN]${NC} No changes made. Run without DRY_RUN=1 to apply."
fi
echo ""
