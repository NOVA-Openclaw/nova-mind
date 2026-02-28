#!/bin/bash
# Bootstrap Context System Installer
# Installs database schema, hook, and fallback files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_DIR="$HOME/.openclaw"
HOOK_DIR="$OPENCLAW_DIR/hooks/db-bootstrap-context"
FALLBACK_DIR="$OPENCLAW_DIR/bootstrap-fallback"
DB_NAME="${DB_NAME:-nova_memory}"

echo "=== Bootstrap Context System Installation ==="
echo ""

# Check prerequisites
if ! command -v psql &> /dev/null; then
    echo "❌ Error: psql not found. Install PostgreSQL client."
    exit 1
fi

if ! command -v openclaw &> /dev/null; then
    echo "⚠️  Warning: openclaw command not found. Make sure OpenClaw is installed."
fi

# Test database connection
echo "Testing database connection..."
if ! psql -d "$DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
    echo "❌ Error: Cannot connect to database '$DB_NAME'"
    exit 1
fi
echo "✅ Database connection OK"
echo ""

# Install management functions
echo "Installing management functions..."
psql -d "$DB_NAME" -f "$SCRIPT_DIR/sql/management-functions.sql"
echo "✅ Functions installed"
echo ""

# Install audit triggers
echo "Installing audit triggers..."
psql -d "$DB_NAME" -f "$SCRIPT_DIR/sql/triggers.sql"
echo "✅ Triggers installed"
echo ""

# Install OpenClaw hook
echo "Installing OpenClaw hook..."
mkdir -p "$HOOK_DIR"
cp "$SCRIPT_DIR/hook/handler.ts" "$HOOK_DIR/"
cp "$SCRIPT_DIR/hook/HOOK.md" "$HOOK_DIR/"
echo "✅ Hook installed at $HOOK_DIR"
echo ""

# Create fallback directory
echo "Creating fallback directory..."
mkdir -p "$FALLBACK_DIR"
if [ -d "$SCRIPT_DIR/fallback" ]; then
    cp "$SCRIPT_DIR/fallback/"*.md "$FALLBACK_DIR/" 2>/dev/null || true
    echo "✅ Fallback files copied"
else
    echo "⚠️  No fallback files found (optional)"
fi
echo ""

# Verify installation
echo "Verifying installation..."
FUNCTIONS=$(psql -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM pg_proc WHERE proname LIKE '%bootstrap%'")
echo "✅ Database functions: $FUNCTIONS found"

if [ -f "$HOOK_DIR/handler.ts" ] && [ -f "$HOOK_DIR/HOOK.md" ]; then
    echo "✅ Hook files verified"
else
    echo "❌ Error: Hook files not found"
    exit 1
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Migrate existing context files:"
echo "   cd $SCRIPT_DIR && psql -d $DB_NAME -f sql/migrate-initial-context.sql"
echo ""
echo "2. Test the hook:"
echo "   psql -d $DB_NAME -c \"SELECT * FROM get_agent_bootstrap('test');\""
echo ""
echo "3. Restart OpenClaw gateway for hook to take effect"
echo ""
echo "Documentation: $SCRIPT_DIR/docs/MANAGEMENT.md"
