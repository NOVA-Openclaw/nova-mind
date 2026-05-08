#!/bin/bash
# Bootstrap Context System Installer
#
# Installs:
#   1. Database management functions (idempotent — psql \i)
#   2. Database audit triggers (idempotent — psql \i)
#   3. OpenClaw hook files at ~/.openclaw/hooks/db-bootstrap-context/
#   4. Disk fallback files at ~/.openclaw/bootstrap-fallback/
#
# Hook and fallback files use SHA-256 hash comparison: install if missing,
# replace if different from repo, skip if identical. This matches the
# install_lib_files pattern in nova-mind/memory/agent-install.sh.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="$HOME/.openclaw"
HOOK_DIR="$OPENCLAW_DIR/hooks/db-bootstrap-context"
FALLBACK_DIR="$OPENCLAW_DIR/bootstrap-fallback"
DB_NAME="${DB_NAME:-nova_memory}"

# Color codes (match agent-install.sh conventions)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
CHECK="${GREEN}✅${NC}"
WARN="${YELLOW}⚠️${NC}"
INFO="${BLUE}ℹ️${NC}"
CROSS="${RED}❌${NC}"

echo "=== Bootstrap Context System Installation ==="
echo ""

# ----------------------------------------------------------------------------
# Prerequisites
# ----------------------------------------------------------------------------
if ! command -v psql &> /dev/null; then
    echo -e "  ${CROSS} psql not found. Install PostgreSQL client."
    exit 1
fi

if ! command -v sha256sum &> /dev/null; then
    echo -e "  ${CROSS} sha256sum not found (required for idempotent installs)."
    exit 1
fi

if ! command -v openclaw &> /dev/null; then
    echo -e "  ${WARN} openclaw command not found. Make sure OpenClaw is installed."
fi

# ----------------------------------------------------------------------------
# Database connection check
# ----------------------------------------------------------------------------
echo "Testing database connection..."
if ! psql -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "  ${CROSS} Cannot connect to database '$DB_NAME'"
    exit 1
fi
echo -e "  ${CHECK} Database connection OK"
echo ""

# ----------------------------------------------------------------------------
# SQL: management functions + audit triggers (idempotent CREATE OR REPLACE)
# ----------------------------------------------------------------------------
echo "Installing management functions..."
psql -d "$DB_NAME" -f "$SCRIPT_DIR/sql/management-functions.sql" > /dev/null
echo -e "  ${CHECK} Functions installed"

echo "Installing audit triggers..."
psql -d "$DB_NAME" -f "$SCRIPT_DIR/sql/triggers.sql" > /dev/null
echo -e "  ${CHECK} Triggers installed"
echo ""

# ----------------------------------------------------------------------------
# Hash-compare installer for the hook files at $HOOK_DIR
# ----------------------------------------------------------------------------
# install_file <src> <dst> <label>:
#   - missing dst → copy
#   - dst hash differs from src → copy (warns about overwrite)
#   - dst hash matches src → skip
install_file() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [ ! -f "$src" ]; then
        echo -e "  ${WARN} [$label] source not found: $src — skipping"
        return 0
    fi

    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        echo -e "  ${CHECK} [$label] installed"
        return 0
    fi

    local src_hash dst_hash
    src_hash=$(sha256sum "$src" | awk '{print $1}')
    dst_hash=$(sha256sum "$dst" | awk '{print $1}')
    if [ "$src_hash" != "$dst_hash" ]; then
        cp "$src" "$dst"
        echo -e "  ${CHECK} [$label] updated (hash changed)"
    else
        echo -e "  ${INFO} [$label] up to date"
    fi
}

echo "Installing OpenClaw hook (hash-compared)..."
mkdir -p "$HOOK_DIR"
install_file "$SCRIPT_DIR/hook/handler.ts"   "$HOOK_DIR/handler.ts"   "hook/handler.ts"
install_file "$SCRIPT_DIR/hook/HOOK.md"      "$HOOK_DIR/HOOK.md"      "hook/HOOK.md"
install_file "$SCRIPT_DIR/hook/package.json" "$HOOK_DIR/package.json" "hook/package.json"
echo ""

# ----------------------------------------------------------------------------
# Hash-compare installer for fallback files at $FALLBACK_DIR
# ----------------------------------------------------------------------------
echo "Installing disk fallback files (hash-compared)..."
mkdir -p "$FALLBACK_DIR"
if [ -d "$SCRIPT_DIR/fallback" ]; then
    for src_file in "$SCRIPT_DIR/fallback/"*.md; do
        [ -e "$src_file" ] || continue
        base=$(basename "$src_file")
        install_file "$src_file" "$FALLBACK_DIR/$base" "fallback/$base"
    done
else
    echo -e "  ${WARN} No fallback files found in repo (optional)"
fi
echo ""

# ----------------------------------------------------------------------------
# Verify installation
# ----------------------------------------------------------------------------
echo "Verifying installation..."
FUNCTION_COUNT=$(psql -d "$DB_NAME" -tA -c "SELECT count(*) FROM pg_proc WHERE proname LIKE '%bootstrap%'")
echo -e "  ${CHECK} Database functions matching '%bootstrap%': $FUNCTION_COUNT"

# Confirm get_agent_bootstrap exists with the expected signature
if psql -d "$DB_NAME" -tA -c "SELECT proname FROM pg_proc WHERE proname = 'get_agent_bootstrap'" | grep -q '^get_agent_bootstrap$'; then
    echo -e "  ${CHECK} get_agent_bootstrap() present"
else
    echo -e "  ${WARN} get_agent_bootstrap() not found — hook will fall through to disk"
fi

if [ -f "$HOOK_DIR/handler.ts" ] && [ -f "$HOOK_DIR/HOOK.md" ]; then
    echo -e "  ${CHECK} Hook files verified at $HOOK_DIR"
else
    echo -e "  ${CROSS} Hook files missing at $HOOK_DIR"
    exit 1
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. (One-time) Migrate existing context files into the database:"
echo "     cd $SCRIPT_DIR && psql -d $DB_NAME -f sql/migrate-initial-context.sql"
echo ""
echo "  2. Restart the gateway to load updated hook code:"
echo "     systemctl --user restart openclaw-gateway.service"
echo ""
echo "  3. Smoke-test the database function:"
echo "     psql -d $DB_NAME -c \"SELECT count(*) FROM get_agent_bootstrap('nova');\""
echo ""
echo "Documentation: $SCRIPT_DIR/docs/MANAGEMENT.md"
