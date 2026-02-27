#!/bin/bash
# nova-cognition agent installer
# Idempotent - safe to run multiple times

set -e

VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load database config from postgres.json if available
PG_CONFIG="$HOME/.openclaw/postgres.json"
if [ -f "$PG_CONFIG" ] && command -v jq &>/dev/null; then
    _pg_val() { jq -r ".$1 // empty" "$PG_CONFIG" 2>/dev/null; }
    val=$(_pg_val host);     [ -z "${PGHOST:-}" ]     && [ -n "$val" ] && export PGHOST="$val"
    val=$(_pg_val port);     [ -z "${PGPORT:-}" ]     && [ -n "$val" ] && export PGPORT="$val"
    val=$(_pg_val database); [ -z "${PGDATABASE:-}" ] && [ -n "$val" ] && export PGDATABASE="$val"
    val=$(_pg_val user);     [ -z "${PGUSER:-}" ]     && [ -n "$val" ] && export PGUSER="$val"
    val=$(_pg_val password); [ -z "${PGPASSWORD:-}" ] && [ -n "$val" ] && export PGPASSWORD="$val"
    export PGHOST="${PGHOST:-localhost}"
    export PGPORT="${PGPORT:-5432}"
    export PGUSER="${PGUSER:-$(whoami)}"
fi

# Now derive DB_USER and DB_NAME from the loaded config
DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${PGDATABASE:-${DB_USER//-/_}_memory}"

# Validate DB connectivity (warning only — some install steps don't need DB)
if psql -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "  \033[0;32m✓\033[0m Database connection verified"
else
    echo "  ⚠ Cannot connect to database '$DB_NAME' as '$DB_USER'" >&2
    echo "      Check credentials in ~/.openclaw/postgres.json" >&2
fi

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace-coder}"
OPENCLAW_DIR="$HOME/.openclaw"
OPENCLAW_PROJECTS="$OPENCLAW_DIR/projects"
EXTENSIONS_DIR="$OPENCLAW_DIR/extensions"

# Parse arguments
VERIFY_ONLY=0
FORCE_INSTALL=0
NO_RESTART=0
DB_NAME_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --verify-only)
            VERIFY_ONLY=1
            shift
            ;;
        --force)
            FORCE_INSTALL=1
            shift
            ;;
        --no-restart)
            NO_RESTART=1
            shift
            ;;
        --database|-d)
            DB_NAME_OVERRIDE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verify-only         Check installation without modifying anything"
            echo "  --force               Force overwrite existing files"
            echo "  --no-restart          Skip automatic gateway restart after install"
            echo "  --database, -d NAME   Override database name (default: \${USER}_memory)"
            echo "  --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Use default database name"
            echo "  $0 --database nova_memory       # Use specific database"
            echo "  $0 -d nova_memory               # Short form"
            echo "  $0 --verify-only                # Check installation status"
            echo "  $0 --force                      # Force reinstall"
            echo "  $0 --no-restart                 # Install without restarting gateway"
            echo ""
            echo "Prerequisites:"
            echo "  - Node.js 18+ and npm"
            echo "  - TypeScript (npm install -g typescript)"
            echo "  - PostgreSQL with nova_memory database"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Apply database name override if provided
if [ -n "$DB_NAME_OVERRIDE" ]; then
    DB_NAME="$DB_NAME_OVERRIDE"
fi

# Temp file cleanup
TMPFILES=()
cleanup_tmp() { rm -f "${TMPFILES[@]}"; }
trap cleanup_tmp EXIT

# === Prerequisite check: nova-memory lib files must exist ===
OPENCLAW_LIB="$HOME/.openclaw/lib"
REQUIRED_LIB_FILES=("pg-env.sh" "pg_env.py" "pg-env.ts" "env-loader.sh" "env_loader.py")
MISSING_FILES=()
for f in "${REQUIRED_LIB_FILES[@]}"; do
    if [ ! -f "$OPENCLAW_LIB/$f" ]; then
        MISSING_FILES+=("$f")
    fi
done
if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    echo "WARNING: Some library files missing from $OPENCLAW_LIB:" >&2
    for f in "${MISSING_FILES[@]}"; do
        echo "  - $f" >&2
    done
    echo "  These are installed by nova-memory. Some features may not work." >&2
    echo "  Install nova-memory: cd ~/.openclaw/workspace/nova-memory && bash agent-install.sh" >&2
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Status indicators
CHECK_MARK="${GREEN}✅${NC}"
CROSS_MARK="${RED}❌${NC}"
WARNING="${YELLOW}⚠️${NC}"
INFO="${BLUE}ℹ️${NC}"

# Verification results
VERIFICATION_PASSED=0
VERIFICATION_WARNINGS=0
VERIFICATION_ERRORS=0

# ============================================
# Helper: sync_directory (hash-based file sync)
# ============================================
# Usage: sync_directory <source_dir> <target_dir> [label]
# Copies only new or changed files (by sha256sum).
# Honors FORCE_INSTALL: if 1, copies all files unconditionally.
# Sets SYNC_UPDATED, SYNC_SKIPPED, SYNC_ADDED counts after return.
SYNC_UPDATED=0
SYNC_SKIPPED=0
SYNC_ADDED=0

sync_directory() {
    local src_dir="$1"
    local tgt_dir="$2"
    local label="${3:-files}"

    SYNC_UPDATED=0
    SYNC_SKIPPED=0
    SYNC_ADDED=0

    if [ ! -d "$src_dir" ]; then
        echo -e "  ${WARNING} Source directory not found: $src_dir"
        return 1
    fi

    mkdir -p "$tgt_dir"

    # Find all files in source (relative paths), excluding node_modules and dist
    while IFS= read -r -d '' rel_path; do
        local src_file="$src_dir/$rel_path"
        local tgt_file="$tgt_dir/$rel_path"

        # Ensure target subdirectory exists
        mkdir -p "$(dirname "$tgt_file")"

        if [ $FORCE_INSTALL -eq 1 ]; then
            cp "$src_file" "$tgt_file"
            echo -e "    ${CHECK_MARK} $rel_path (force-updated)"
            SYNC_UPDATED=$((SYNC_UPDATED + 1))
        elif [ ! -f "$tgt_file" ]; then
            cp "$src_file" "$tgt_file"
            echo -e "    ${CHECK_MARK} $rel_path (added)"
            SYNC_ADDED=$((SYNC_ADDED + 1))
        else
            local src_hash tgt_hash
            src_hash=$(sha256sum "$src_file" | awk '{print $1}')
            tgt_hash=$(sha256sum "$tgt_file" | awk '{print $1}')
            if [ "$src_hash" != "$tgt_hash" ]; then
                cp "$src_file" "$tgt_file"
                echo -e "    ${CHECK_MARK} $rel_path (updated)"
                SYNC_UPDATED=$((SYNC_UPDATED + 1))
            else
                echo -e "    ${INFO} $rel_path (unchanged, skipped)"
                SYNC_SKIPPED=$((SYNC_SKIPPED + 1))
            fi
        fi
    done < <(cd "$src_dir" && find . -type f -not -path '*/node_modules/*' -not -path '*/dist/*' -print0 | sed -z 's|^\./||')

    local total=$((SYNC_UPDATED + SYNC_SKIPPED + SYNC_ADDED))
    echo -e "  Summary: $total $label — $SYNC_ADDED added, $SYNC_UPDATED updated, $SYNC_SKIPPED unchanged"
}

echo ""
echo "═══════════════════════════════════════════"
if [ $VERIFY_ONLY -eq 1 ]; then
    echo "  nova-cognition verification v${VERSION}"
else
    echo "  nova-cognition installer v${VERSION}"
fi
echo "═══════════════════════════════════════════"
echo ""

# ============================================
# Verification Functions
# ============================================

verify_files() {
    echo "File verification..."
    
    # Check agent_chat extension
    if [ -d "$EXTENSIONS_DIR/agent_chat" ]; then
        echo -e "  ${CHECK_MARK} agent_chat extension directory exists"
        
        # Check if TypeScript source files exist
        if [ -f "$EXTENSIONS_DIR/agent_chat/index.ts" ]; then
            echo -e "  ${CHECK_MARK} agent_chat TypeScript source present"
        else
            echo -e "  ${WARNING} agent_chat TypeScript source missing"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        fi
        
        # Check if build output exists
        if [ -f "$EXTENSIONS_DIR/agent_chat/dist/index.js" ]; then
            echo -e "  ${CHECK_MARK} agent_chat compiled (dist/index.js exists)"
        else
            echo -e "  ${CROSS_MARK} agent_chat not compiled"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        fi
        
        # Check openclaw.plugin.json
        if [ -f "$EXTENSIONS_DIR/agent_chat/openclaw.plugin.json" ]; then
            if grep -q '"main": "./dist/index.js"' "$EXTENSIONS_DIR/agent_chat/openclaw.plugin.json"; then
                echo -e "  ${CHECK_MARK} openclaw.plugin.json configured correctly"
            else
                echo -e "  ${WARNING} openclaw.plugin.json may need 'main' field update"
                VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            fi
        else
            echo -e "  ${CROSS_MARK} openclaw.plugin.json not found"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        fi
        
        # Check pg in shared node_modules
        if [ -d "$OPENCLAW_DIR/node_modules/pg" ]; then
            echo -e "  ${CHECK_MARK} pg installed in shared node_modules ($OPENCLAW_DIR/node_modules/)"
        elif [ -d "$EXTENSIONS_DIR/agent_chat/node_modules/pg" ]; then
            echo -e "  ${WARNING} pg installed in per-extension node_modules (should migrate to shared $OPENCLAW_DIR/node_modules/)"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        else
            echo -e "  ${WARNING} pg dependency not installed"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        fi
    else
        echo -e "  ${CROSS_MARK} agent_chat extension not installed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
    
    # Check skills (accepts both directories and legacy symlinks)
    local skills=("agent-chat" "agent-spawn")
    for skill in "${skills[@]}"; do
        if [ -d "$WORKSPACE/skills/$skill" ]; then
            if [ -L "$WORKSPACE/skills/$skill" ]; then
                echo -e "  ${CHECK_MARK} Skill present (legacy symlink): $skill"
            else
                echo -e "  ${CHECK_MARK} Skill present: $skill"
            fi
        else
            echo -e "  ${CROSS_MARK} Skill not installed: $skill"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        fi
    done
    
    # Check bootstrap-context installation
    if [ -d "$OPENCLAW_DIR/hooks/db-bootstrap-context" ]; then
        echo -e "  ${CHECK_MARK} Bootstrap context hook installed"
    else
        echo -e "  ${CROSS_MARK} Bootstrap context hook not installed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
    
    # Check agent-config-sync extension
    if [ -d "$EXTENSIONS_DIR/agent_config_sync" ]; then
        echo -e "  ${CHECK_MARK} agent_config_sync extension directory exists"
        if [ -f "$EXTENSIONS_DIR/agent_config_sync/dist/index.js" ]; then
            echo -e "  ${CHECK_MARK} agent_config_sync compiled (dist/index.js exists)"
        else
            echo -e "  ${CROSS_MARK} agent_config_sync not compiled"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        fi
    else
        echo -e "  ${CROSS_MARK} agent_config_sync extension not installed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
    
    # Check agents.json exists
    if [ -f "$OPENCLAW_DIR/agents.json" ]; then
        echo -e "  ${CHECK_MARK} agents.json exists"
    else
        echo -e "  ${WARNING} agents.json not found (will be generated on gateway start)"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
    
    return 0
}

verify_database() {
    echo ""
    echo "Database verification..."
    
    # Check if database exists
    if ! psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "  ${CROSS_MARK} Database '$DB_NAME' does not exist"
        echo "      nova-cognition requires nova-memory to be installed first"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi
    
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' exists"
    
    # Check database connection
    if psql -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        echo -e "  ${CHECK_MARK} Database connection works"
    else
        echo -e "  ${CROSS_MARK} Database connection failed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi
    
    # Check required tables for agent_chat
    local required_tables=("agent_chat" "agent_chat_processed")
    local missing_tables=()
    
    for table in "${required_tables[@]}"; do
        TABLE_EXISTS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table'" | tr -d '[:space:]')
        
        if [ "$TABLE_EXISTS" -eq 0 ]; then
            missing_tables+=("$table")
        else
            echo -e "  ${CHECK_MARK} Table '$table' exists"
        fi
    done
    
    if [ ${#missing_tables[@]} -gt 0 ]; then
        echo -e "  ${WARNING} Missing optional agent_chat tables:"
        for table in "${missing_tables[@]}"; do
            echo "      • $table (will be created by extension)"
        done
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + ${#missing_tables[@]}))
    fi
    
    # Check agent_bootstrap_context table (canonical bootstrap context)
    BOOTSTRAP_TABLE=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'agent_bootstrap_context'" | tr -d '[:space:]')
    
    if [ "$BOOTSTRAP_TABLE" -ge 1 ]; then
        BOOTSTRAP_ROWS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM agent_bootstrap_context" | tr -d '[:space:]')
        echo -e "  ${CHECK_MARK} Bootstrap context table installed ($BOOTSTRAP_ROWS rows)"
    else
        echo -e "  ${WARNING} agent_bootstrap_context table not found"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
    
    return 0
}

# ============================================
# Part 1: Prerequisites Check
# ============================================
echo "Checking prerequisites..."

# Build tool checks — only needed for full install, not verify-only
if [ $VERIFY_ONLY -eq 0 ]; then
    # Check Node.js installed
    if command -v node &> /dev/null; then
        NODE_VERSION=$(node --version)
        NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v\([0-9]*\).*/\1/')
        if [ "$NODE_MAJOR" -ge 18 ]; then
            echo -e "  ${CHECK_MARK} Node.js installed ($NODE_VERSION)"
        else
            echo -e "  ${WARNING} Node.js version $NODE_VERSION (recommend 18+)"
        fi
    else
        echo -e "  ${CROSS_MARK} Node.js not found"
        echo ""
        echo "Please install Node.js 18+ first:"
        echo "  Ubuntu/Debian: curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt install -y nodejs"
        echo "  macOS: brew install node"
        exit 1
    fi

    # Check npm installed
    if command -v npm &> /dev/null; then
        NPM_VERSION=$(npm --version)
        echo -e "  ${CHECK_MARK} npm installed ($NPM_VERSION)"
    else
        echo -e "  ${CROSS_MARK} npm not found"
        exit 1
    fi

    # Check TypeScript available (can be local or global)
    if command -v tsc &> /dev/null; then
        TSC_VERSION=$(tsc --version)
        echo -e "  ${CHECK_MARK} TypeScript installed ($TSC_VERSION)"
    elif npm list -g typescript &> /dev/null; then
        echo -e "  ${CHECK_MARK} TypeScript installed (global)"
    else
        echo -e "  ${WARNING} TypeScript not installed globally (will use local)"
    fi
fi

# Check PostgreSQL installed
if command -v psql &> /dev/null; then
    PG_VERSION=$(psql --version | awk '{print $3}')
    echo -e "  ${CHECK_MARK} PostgreSQL installed ($PG_VERSION)"
else
    echo -e "  ${CROSS_MARK} PostgreSQL not found"
    echo ""
    echo "Please install PostgreSQL first:"
    echo "  Ubuntu/Debian: sudo apt install postgresql postgresql-contrib"
    echo "  macOS: brew install postgresql"
    exit 1
fi

# Check PostgreSQL service running
if pg_isready -q 2>/dev/null; then
    echo -e "  ${CHECK_MARK} PostgreSQL service running"
else
    echo -e "  ${WARNING} PostgreSQL service not running (required for bootstrap-context)"
fi

# Check createdb command available (only needed for full install)
if [ $VERIFY_ONLY -eq 0 ]; then
    if command -v createdb &> /dev/null; then
        echo -e "  ${CHECK_MARK} createdb installed"
    else
        echo -e "  ${CROSS_MARK} createdb not found"
        echo ""
        echo "Please install PostgreSQL client tools:"
        echo "  Ubuntu/Debian: sudo apt install postgresql-client"
        echo "  macOS: brew install postgresql"
        exit 1
    fi
fi

# Check nova-memory database exists (only if not in verify-only mode)
if [ $VERIFY_ONLY -eq 0 ]; then
    if psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "  ${CHECK_MARK} Database '$DB_NAME' exists"
    else
        echo -e "  ${INFO} Database '$DB_NAME' not found (will create)"
    fi
else
    if psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "  ${CHECK_MARK} nova-memory database exists"
    else
        echo -e "  ${WARNING} Database '$DB_NAME' not found"
        echo "      nova-cognition works best with nova-memory installed first"
    fi
fi

# Check nova-relationships schema exists in database
echo ""
echo "Checking nova-relationships prerequisite..."
if psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1 FROM information_schema.tables WHERE table_name = 'entity_relationships'" 2>/dev/null | grep -q 1; then
    echo -e "  ${CHECK_MARK} nova-relationships schema found (entity_relationships)"
else
    echo -e "  ${CROSS_MARK} nova-relationships schema not found in database '$DB_NAME'"
    if [ $VERIFY_ONLY -eq 1 ]; then
        echo "      Install: https://github.com/NOVA-Openclaw/nova-relationships"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        echo ""
        echo "nova-cognition requires nova-relationships to be installed first."
        echo "The entity_relationships table must exist in the database."
        echo ""
        echo "Install nova-relationships:"
        echo "  git clone https://github.com/NOVA-Openclaw/nova-relationships.git"
        echo "  cd nova-relationships"
        echo "  ./agent-install.sh"
        exit 1
    fi
fi

# ============================================
# Part 1.5: API Key Check and Configuration
# ============================================
GATEWAY_RESTART_NEEDED=0

echo ""
echo "API key configuration..."

# Check API key — openclaw.json is the authoritative source (gateway reads from there)
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
ANTHROPIC_KEY=""

# Check openclaw.json first (authoritative source for the gateway)
if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &> /dev/null; then
    ANTHROPIC_KEY=$(jq -r '.env.vars.ANTHROPIC_API_KEY // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
fi

# Fall back to shell environment variable
if [ -z "$ANTHROPIC_KEY" ]; then
    ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-}"
fi

if [ -n "$ANTHROPIC_KEY" ]; then
    echo -e "  ${CHECK_MARK} ANTHROPIC_API_KEY set: ${ANTHROPIC_KEY:0:8}..."
else
    if [ $VERIFY_ONLY -eq 1 ]; then
        echo -e "  ${CROSS_MARK} ANTHROPIC_API_KEY not configured"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        echo -e "  ${WARNING} ANTHROPIC_API_KEY not set"
        echo ""
        echo "Anthropic API key is required for nova-cognition (Claude)."
        echo "Get your API key from: https://console.anthropic.com/"
        echo ""
        read -p "Enter your Anthropic API key (or press Enter to cancel): " user_api_key

        if [ -z "$user_api_key" ]; then
            echo -e "  ${CROSS_MARK} Installation cancelled - ANTHROPIC_API_KEY is required"
            echo ""
            echo "Please set ANTHROPIC_API_KEY and run the installer again:"
            echo "  export ANTHROPIC_API_KEY='your-key-here'"
            echo "  ./agent-install.sh"
            exit 1
        fi

        if [ ! -f "$OPENCLAW_CONFIG" ]; then
            echo -e "  ${WARNING} OpenClaw config not found at $OPENCLAW_CONFIG"
            echo "      Creating new config file..."
            mkdir -p "$HOME/.openclaw"
            echo '{}' > "$OPENCLAW_CONFIG"
        fi

        # Check if jq is available
        if ! command -v jq &> /dev/null; then
            echo -e "  ${CROSS_MARK} jq not installed (required to configure API key)"
            echo "      Install: sudo apt install jq"
            echo ""
            echo "      After installing jq, you can manually add the key to $OPENCLAW_CONFIG:"
            echo "      Or set it in your environment and restart the gateway"
            exit 1
        fi

        # Backup config before modification
        cp "$OPENCLAW_CONFIG" "$OPENCLAW_CONFIG.backup-$(date +%s)"

        # Add API key to config using jq
        TMP_CONFIG=$(mktemp)
        TMPFILES+=("$TMP_CONFIG")
        jq --arg key "$user_api_key" '.env.vars.ANTHROPIC_API_KEY = $key' "$OPENCLAW_CONFIG" > "$TMP_CONFIG"
        mv "$TMP_CONFIG" "$OPENCLAW_CONFIG"

        echo -e "  ${CHECK_MARK} ANTHROPIC_API_KEY configured in $OPENCLAW_CONFIG"
        GATEWAY_RESTART_NEEDED=1
    fi
fi

# ============================================
# Database Setup (Before verification)
# ============================================
if [ $VERIFY_ONLY -eq 0 ]; then
    echo ""
    echo "Database setup..."
    
    # Check if database exists
    if ! psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo "  Creating database '$DB_NAME'..."
        createdb -U "$DB_USER" "$DB_NAME" || { echo -e "  ${CROSS_MARK} Failed to create database"; exit 1; }
        echo -e "  ${CHECK_MARK} Database '$DB_NAME' created"
    else
        echo -e "  ${CHECK_MARK} Database '$DB_NAME' exists"
    fi
    
    # Verify connection
    if psql -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        echo -e "  ${CHECK_MARK} Database connection verified"
    else
        echo -e "  ${CROSS_MARK} Cannot connect to database '$DB_NAME'"
        exit 1
    fi
    
    # Apply agent_chat schema (idempotent - uses CREATE IF NOT EXISTS)
    SCHEMA_FILE="$SCRIPT_DIR/focus/agent_chat/schema.sql"
    if [ ! -f "$SCHEMA_FILE" ]; then
        echo -e "  ${WARNING} focus/agent_chat/schema.sql not found (will be created by extension)"
    else
        echo "  Applying agent_chat schema..."
        SCHEMA_ERR="${TMPDIR:-/tmp}/schema-apply-$$.err"
        if psql -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" > /dev/null 2>"$SCHEMA_ERR"; then
            echo -e "  ${CHECK_MARK} Schema applied"
            rm -f "$SCHEMA_ERR"
        else
            echo -e "  ${CROSS_MARK} Schema apply failed (exit code $?)"
            cat "$SCHEMA_ERR" >&2
            rm -f "$SCHEMA_ERR"
            exit 1
        fi
    fi
    
    # Configure triggers for logical replication if subscriptions exist
    echo "  Checking for logical replication subscriptions..."
    SUBSCRIPTION_COUNT=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM pg_subscription WHERE subname LIKE '%agent_chat%'" 2>/dev/null || echo "0")
    
    if [ "$SUBSCRIPTION_COUNT" -gt 0 ]; then
        echo -e "  ${CHECK_MARK} Found $SUBSCRIPTION_COUNT agent_chat subscription(s)"
        echo "  Configuring triggers for logical replication..."
        
        # Notification trigger must fire ALWAYS (including replicated rows)
        if psql -U "$DB_USER" -d "$DB_NAME" -c "ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;" > /dev/null 2>&1; then
            echo -e "  ${CHECK_MARK} Notification trigger configured (ALWAYS)"
        else
            echo -e "  ${WARNING} Failed to configure notification trigger"
        fi
        
        # Embedding trigger should only fire on REPLICA (not on replicated rows)
        if psql -U "$DB_USER" -d "$DB_NAME" -c "ALTER TABLE agent_chat ENABLE REPLICA TRIGGER trg_embed_chat_message;" > /dev/null 2>&1; then
            echo -e "  ${CHECK_MARK} Embedding trigger configured (REPLICA only)"
        else
            echo -e "  ${WARNING} Failed to configure embedding trigger"
        fi
        
        echo -e "  ${CHECK_MARK} Logical replication triggers configured"
    else
        echo "  No agent_chat subscriptions found, using default trigger configuration"
    fi
fi

# ============================================
# Run Verification if --verify-only
# ============================================
if [ $VERIFY_ONLY -eq 1 ]; then
    echo ""
    verify_files
    verify_database
    
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  Verification Summary"
    echo "═══════════════════════════════════════════"
    if [ $VERIFICATION_ERRORS -gt 0 ]; then
        echo -e "  ${CROSS_MARK} $VERIFICATION_ERRORS errors found"
        exit 1
    elif [ $VERIFICATION_WARNINGS -gt 0 ]; then
        echo -e "  ${WARNING} $VERIFICATION_WARNINGS warnings found"
        exit 0
    else
        echo -e "  ${CHECK_MARK} All checks passed"
        exit 0
    fi
fi

# ============================================
# Part 2: Agent Chat Extension
# ============================================
echo ""
echo "Agent Chat extension installation..."

EXTENSION_SOURCE="$SCRIPT_DIR/focus/agent_chat"
EXTENSION_TARGET="$EXTENSIONS_DIR/agent_chat"

# Create extensions directory if needed
mkdir -p "$EXTENSIONS_DIR"

# Sync extension source files (hash-based comparison)
echo "  Syncing agent_chat extension source files..."
mkdir -p "$EXTENSION_TARGET"
sync_directory "$EXTENSION_SOURCE" "$EXTENSION_TARGET" "extension files"

# Ensure main field is set correctly in openclaw.plugin.json
if [ -f "$EXTENSION_TARGET/openclaw.plugin.json" ]; then
    if ! grep -q '"main":' "$EXTENSION_TARGET/openclaw.plugin.json"; then
        sed -i '/"id":/a\  "main": "./dist/index.js",' "$EXTENSION_TARGET/openclaw.plugin.json"
    elif ! grep -q '"main": "./dist/index.js"' "$EXTENSION_TARGET/openclaw.plugin.json"; then
        sed -i 's|"main": "[^"]*"|"main": "./dist/index.js"|' "$EXTENSION_TARGET/openclaw.plugin.json"
    fi
fi

# Install pg dependency to shared ~/.openclaw/node_modules/
echo ""
echo "  Installing pg to shared $OPENCLAW_DIR/node_modules/..."

# Clean up old per-extension node_modules/pg if present
if [ -d "$EXTENSION_TARGET/node_modules/pg" ]; then
    echo -e "  ${INFO} Removing old per-extension node_modules/pg (migrating to shared location)"
    rm -rf "$EXTENSION_TARGET/node_modules/pg"
fi

if [ -d "$OPENCLAW_DIR/node_modules/pg" ] && [ $FORCE_INSTALL -eq 0 ]; then
    echo -e "  ${CHECK_MARK} pg already installed in shared node_modules (use --force to reinstall)"
else
    NPM_INSTALL_LOG="${TMPDIR:-/tmp}/npm-install-pg-shared-$$.log"
    echo "    Running npm install pg --save in $OPENCLAW_DIR..."
    if (cd "$OPENCLAW_DIR" && npm install pg --save) > "$NPM_INSTALL_LOG" 2>&1; then
        echo -e "  ${CHECK_MARK} pg installed to shared $OPENCLAW_DIR/node_modules/"
        rm -f "$NPM_INSTALL_LOG"
    else
        echo -e "  ${CROSS_MARK} npm install pg failed"
        echo "      Log: $NPM_INSTALL_LOG"
        tail -20 "$NPM_INSTALL_LOG"
        exit 1
    fi
fi

# Change to extension directory for build (all relative paths below expect this)
cd "$EXTENSION_TARGET"

# Build TypeScript
echo ""
echo "  Building TypeScript..."

if [ -d "dist" ] && [ -f "dist/index.js" ] && [ $FORCE_INSTALL -eq 0 ]; then
    echo -e "  ${CHECK_MARK} Already built (use --force to rebuild)"
else
    NPM_BUILD_LOG="${TMPDIR:-/tmp}/npm-build-agent-chat-$$.log"
    echo "    Running npm run build..."
    if npm run build > "$NPM_BUILD_LOG" 2>&1; then
        echo -e "  ${CHECK_MARK} Build completed"
        rm -f "$NPM_BUILD_LOG"
    else
        echo -e "  ${CROSS_MARK} Build failed"
        echo "      Log: $NPM_BUILD_LOG"
        tail -20 "$NPM_BUILD_LOG"
        exit 1
    fi
fi

# Verify build output
if [ -f "dist/index.js" ]; then
    echo -e "  ${CHECK_MARK} Build output verified: dist/index.js exists"
else
    echo -e "  ${CROSS_MARK} Build output not found: dist/index.js"
    exit 1
fi

# Verify plugin configuration
if [ -f "openclaw.plugin.json" ]; then
    if grep -q '"main": "./dist/index.js"' openclaw.plugin.json; then
        echo -e "  ${CHECK_MARK} openclaw.plugin.json configured correctly"
    else
        echo -e "  ${WARNING} openclaw.plugin.json 'main' field may need updating"
    fi
else
    echo -e "  ${WARNING} openclaw.plugin.json not found"
fi

cd "$SCRIPT_DIR"

# ============================================
# Part 3: Skills Installation
# ============================================
echo ""
echo "Skills installation..."

SKILLS_DIR="$WORKSPACE/skills"
mkdir -p "$SKILLS_DIR"

# Install skills
SKILLS=("agent-chat" "agent-spawn")

for SKILL_NAME in "${SKILLS[@]}"; do
    SKILL_SOURCE="$SCRIPT_DIR/focus/skills/$SKILL_NAME"
    SKILL_TARGET="$SKILLS_DIR/$SKILL_NAME"
    
    if [ ! -d "$SKILL_SOURCE" ]; then
        echo -e "  ${WARNING} Skill not found: $SKILL_NAME (skipping)"
        continue
    fi
    
    # Remove legacy symlinks before syncing
    if [ -L "$SKILL_TARGET" ]; then
        rm "$SKILL_TARGET"
        echo -e "  ${INFO} Removed legacy symlink for $SKILL_NAME"
    fi

    echo -e "  Syncing skill: $SKILL_NAME..."
    sync_directory "$SKILL_SOURCE" "$SKILL_TARGET" "$SKILL_NAME files"
done

# ============================================
# Part 4: Bootstrap Context System
# ============================================
echo ""
echo "Bootstrap context system installation..."

BOOTSTRAP_INSTALLER="$SCRIPT_DIR/focus/bootstrap-context/install.sh"

BOOTSTRAP_SOURCE="$SCRIPT_DIR/focus/bootstrap-context"
BOOTSTRAP_TARGET="$OPENCLAW_DIR/hooks/db-bootstrap-context"

if [ -d "$BOOTSTRAP_SOURCE" ]; then
    echo "  Syncing bootstrap-context files..."
    sync_directory "$BOOTSTRAP_SOURCE" "$BOOTSTRAP_TARGET" "bootstrap-context files"

    # After syncing hook files, install npm dependencies if package.json exists
    if [ -f "$BOOTSTRAP_TARGET/package.json" ]; then
        if [ ! -d "$BOOTSTRAP_TARGET/node_modules" ] || [ $FORCE_INSTALL -eq 1 ]; then
            echo "  Installing hook dependencies..."
            NPM_INSTALL_LOG="${TMPDIR:-/tmp}/npm-install-hook-$$.log"
            if (cd "$BOOTSTRAP_TARGET" && npm install) > "$NPM_INSTALL_LOG" 2>&1; then
                echo -e "  ${CHECK_MARK} Hook dependencies installed"
                rm -f "$NPM_INSTALL_LOG"
            else
                echo -e "  ${WARNING} npm install had issues (hook may use shared node_modules)"
                rm -f "$NPM_INSTALL_LOG"
            fi
        fi
    fi

    # Run the bootstrap-context installer for DB setup (always, it's idempotent)
    if [ -f "$BOOTSTRAP_TARGET/install.sh" ]; then
        echo "  Running bootstrap-context DB setup..."
        cd "$BOOTSTRAP_TARGET"
        export DB_NAME="$DB_NAME"
        BOOTSTRAP_LOG="${TMPDIR:-/tmp}/bootstrap-install-$$.log"
        if bash install.sh > "$BOOTSTRAP_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} Bootstrap context DB setup complete"
            rm -f "$BOOTSTRAP_LOG"
        else
            echo -e "  ${WARNING} Bootstrap context DB setup had issues"
            echo "      Log: $BOOTSTRAP_LOG"
            tail -10 "$BOOTSTRAP_LOG"
        fi
        cd "$SCRIPT_DIR"
    fi
else
    echo -e "  ${WARNING} Bootstrap context source not found (skipping)"
fi

# ============================================
# Part 4.5: Agent Config Sync Extension (DB → agents.json)
# ============================================
echo ""
echo "Agent config sync extension installation..."

AGENT_CONFIG_SYNC_SOURCE="$SCRIPT_DIR/focus/agent-config-sync"
AGENT_CONFIG_SYNC_TARGET="$EXTENSIONS_DIR/agent_config_sync"

if [ -d "$AGENT_CONFIG_SYNC_SOURCE" ]; then
    echo "  Syncing agent-config-sync extension files..."
    mkdir -p "$AGENT_CONFIG_SYNC_TARGET"
    sync_directory "$AGENT_CONFIG_SYNC_SOURCE" "$AGENT_CONFIG_SYNC_TARGET" "agent-config-sync files"

    # Build TypeScript
    echo "  Building agent_config_sync TypeScript..."
    cd "$AGENT_CONFIG_SYNC_TARGET"
    
    # Install dependencies (shares pg with agent_chat from ~/.openclaw/node_modules)
    if [ ! -d "node_modules" ] || [ $FORCE_INSTALL -eq 1 ]; then
        NPM_INSTALL_LOG="${TMPDIR:-/tmp}/npm-install-config-sync-$$.log"
        if npm install > "$NPM_INSTALL_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} Dependencies installed"
            rm -f "$NPM_INSTALL_LOG"
        else
            echo -e "  ${WARNING} npm install had issues (may use shared node_modules)"
            rm -f "$NPM_INSTALL_LOG"
        fi
    fi

    NPM_BUILD_LOG="${TMPDIR:-/tmp}/npm-build-config-sync-$$.log"
    if npm run build > "$NPM_BUILD_LOG" 2>&1; then
        echo -e "  ${CHECK_MARK} agent_config_sync build completed"
        rm -f "$NPM_BUILD_LOG"
    else
        echo -e "  ${CROSS_MARK} agent_config_sync build failed"
        echo "      Log: $NPM_BUILD_LOG"
        tail -20 "$NPM_BUILD_LOG"
    fi
    
    cd "$SCRIPT_DIR"

    # Remove legacy agent-config-db hook if it exists
    if [ -d "$OPENCLAW_DIR/hooks/agent-config-db" ]; then
        echo "  Removing legacy agent-config-db hook..."
        rm -rf "$OPENCLAW_DIR/hooks/agent-config-db"
        echo -e "  ${CHECK_MARK} Removed agent-config-db hook"
    fi

    # Remove agent-config-db hook config entry if present
    if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &> /dev/null; then
        if jq -e '.hooks.internal.entries["agent-config-db"]' "$OPENCLAW_CONFIG" &>/dev/null; then
            jq 'del(.hooks.internal.entries["agent-config-db"])' "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Removed agent-config-db hook from config" || \
                echo -e "  ${WARNING} Could not remove agent-config-db hook from config"
        fi
    fi

    # Enable agent_config_sync plugin in openclaw.json
    if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &> /dev/null; then
        echo "  Enabling agent_config_sync plugin in config..."
        
        jq --arg database "$DB_NAME" \
           --arg user "$DB_USER" \
            '.plugins.entries.agent_config_sync = (.plugins.entries.agent_config_sync // {}) * {
                "enabled": true,
                "config": {
                    "database": $database,
                    "host": "localhost",
                    "port": 5432,
                    "user": $user,
                    "password": ""
                }
            }' \
            "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
            mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
            echo -e "  ${CHECK_MARK} agent_config_sync plugin enabled in config" || \
            echo -e "  ${WARNING} Could not enable agent_config_sync plugin in config"
    else
        echo -e "  ${WARNING} Cannot enable plugin (missing config or jq)"
    fi

    # Set agents.list to { "$include": "./agents.json" } in openclaw.json
    # - If agents.list already has $include, leave it (idempotent)
    # - If agents.list is an inline array, replace it with $include
    # - If agents.list is missing, create it
    # - Preserve all agents.defaults — do NOT touch them
    # - Do NOT add $include at root level or at agents level
    if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &> /dev/null; then
        EXISTING_LIST_INCLUDE=$(jq -r '.agents.list["$include"] // empty' "$OPENCLAW_CONFIG" 2>/dev/null || true)
        if [ -n "$EXISTING_LIST_INCLUDE" ]; then
            echo -e "  ${CHECK_MARK} agents.list already uses \$include: $EXISTING_LIST_INCLUDE"
        else
            echo "  Setting agents.list to { \"\$include\": \"./agents.json\" }..."
            jq '.agents.list = { "$include": "./agents.json" }' "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set agents.list = { \"\$include\": \"./agents.json\" } in openclaw.json" || \
                echo -e "  ${WARNING} Could not set agents.list \$include directive"
        fi
    fi

    # Ensure gateway.reload.mode is NOT "off" — file watching is required for config sync
    if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &> /dev/null; then
        EXISTING_MODE=$(jq -r '.gateway.reload.mode // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_MODE" ]; then
            echo "  Setting gateway.reload.mode = \"hot\" (required for config sync)..."
            jq '.gateway.reload.mode = "hot"' "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set gateway.reload.mode = \"hot\"" || \
                echo -e "  ${WARNING} Could not set gateway.reload.mode"
        elif [ "$EXISTING_MODE" = "off" ]; then
            echo -e "  ${WARNING} gateway.reload.mode is \"off\" — config sync requires file watching!"
            echo "  Changing gateway.reload.mode from \"off\" to \"hot\"..."
            jq '.gateway.reload.mode = "hot"' "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set gateway.reload.mode = \"hot\"" || \
                echo -e "  ${WARNING} Could not set gateway.reload.mode"
        else
            echo -e "  ${CHECK_MARK} gateway.reload.mode = \"$EXISTING_MODE\" (file watching enabled)"
        fi
    fi

    # Set maxSpawnDepth if not already configured (default 1 blocks nested spawn chains)
    if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &> /dev/null; then
        EXISTING_DEPTH=$(jq -r '.agents.defaults.subagents.maxSpawnDepth // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_DEPTH" ]; then
            echo "  Setting agents.defaults.subagents.maxSpawnDepth = 5 (supports nested spawns)..."
            jq '.agents.defaults.subagents.maxSpawnDepth = 5' "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set maxSpawnDepth = 5" || \
                echo -e "  ${WARNING} Could not set maxSpawnDepth"
        else
            echo -e "  ${CHECK_MARK} maxSpawnDepth already set to $EXISTING_DEPTH"
        fi
    fi

    # Generate initial agents.json from current DB state
    echo "  Generating initial agents.json from database..."
    AGENTS_JSON="$OPENCLAW_DIR/agents.json"
    AGENTS_JSON_TMP="${AGENTS_JSON}.tmp.$$"
    
    # Build a bare array: non-peer agents with model set, sorted by name.
    # - is_default = true → include "default": true (omit key otherwise)
    # - fallback_models non-empty → object form; NULL or empty → string form
    # - thinking excluded from output
    # - allowed_subagents non-empty → include subagents.allowAgents (sorted)
    INITIAL_SYNC_QUERY="
        SELECT COALESCE(
            json_agg(entry ORDER BY (entry->>'id'))::text,
            '[]'
        )
        FROM (
            SELECT
                CASE
                    WHEN fallback_models IS NOT NULL AND array_length(fallback_models, 1) > 0 THEN
                        jsonb_strip_nulls(jsonb_build_object(
                            'id', name
                        ) ||
                        CASE WHEN is_default = true THEN jsonb_build_object('default', true) ELSE '{}'::jsonb END
                        || jsonb_build_object(
                            'model', jsonb_build_object(
                                'primary', model,
                                'fallbacks', to_jsonb(fallback_models)
                            )
                        ) ||
                        CASE
                            WHEN allowed_subagents IS NOT NULL AND array_length(allowed_subagents, 1) > 0
                            THEN jsonb_build_object('subagents', jsonb_build_object(
                                'allowAgents', (SELECT jsonb_agg(s ORDER BY s) FROM unnest(allowed_subagents) s)
                            ))
                            ELSE '{}'::jsonb
                        END)
                    ELSE
                        jsonb_strip_nulls(jsonb_build_object(
                            'id', name
                        ) ||
                        CASE WHEN is_default = true THEN jsonb_build_object('default', true) ELSE '{}'::jsonb END
                        || jsonb_build_object('model', model) ||
                        CASE
                            WHEN allowed_subagents IS NOT NULL AND array_length(allowed_subagents, 1) > 0
                            THEN jsonb_build_object('subagents', jsonb_build_object(
                                'allowAgents', (SELECT jsonb_agg(s ORDER BY s) FROM unnest(allowed_subagents) s)
                            ))
                            ELSE '{}'::jsonb
                        END)
                END AS entry
            FROM agents
            WHERE instance_type != 'peer'
              AND model IS NOT NULL
        ) sub
    "

    if AGENTS_DATA=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "$INITIAL_SYNC_QUERY" 2>/dev/null); then
        if [ -n "$AGENTS_DATA" ] && [ "$AGENTS_DATA" != "null" ]; then
            echo "$AGENTS_DATA" | jq '.' > "$AGENTS_JSON_TMP" 2>/dev/null && \
                mv "$AGENTS_JSON_TMP" "$AGENTS_JSON" && \
                echo -e "  ${CHECK_MARK} Generated initial agents.json from DB (bare array)" || \
                { echo -e "  ${WARNING} Could not write agents.json"; rm -f "$AGENTS_JSON_TMP"; }
        else
            # Write empty but valid agents.json (bare array)
            echo '[]' > "$AGENTS_JSON_TMP" && \
                mv "$AGENTS_JSON_TMP" "$AGENTS_JSON" && \
                echo -e "  ${CHECK_MARK} Generated empty agents.json (no agents in DB)" || \
                { echo -e "  ${WARNING} Could not write agents.json"; rm -f "$AGENTS_JSON_TMP"; }
        fi
    else
        echo -e "  ${WARNING} Could not query DB for initial agents.json (will be generated on gateway start)"
        # Write empty but valid agents.json as fallback (bare array)
        echo '[]' > "$AGENTS_JSON" 2>/dev/null || true
    fi
else
    echo -e "  ${WARNING} Agent config sync source not found (skipping)"
fi

# ── Ensure agent_system_config table exists ──
echo ""
echo "  Ensuring agent_system_config table exists..."

psql -U "$DB_USER" -d "$DB_NAME" -q <<'SYSTEM_CONFIG_TABLE_SQL'
CREATE TABLE IF NOT EXISTS agent_system_config (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    value_type TEXT NOT NULL DEFAULT 'text',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SYSTEM_CONFIG_TABLE_SQL

if [ $? -eq 0 ]; then
    echo -e "  ${CHECK_MARK} agent_system_config table ready"
else
    echo -e "  ${WARNING} Could not ensure agent_system_config table exists"
fi

# ── Apply system_config trigger migration ──
echo "  Installing system config notification trigger..."

SYSTEM_CONFIG_MIGRATION="$SCRIPT_DIR/scripts/migrations/163-system-config-trigger.sql"
if [ -f "$SYSTEM_CONFIG_MIGRATION" ]; then
    MIGRATION_ERR="${TMPDIR:-/tmp}/migration-163-$$.err"
    if psql -U "$DB_USER" -d "$DB_NAME" -q -f "$SYSTEM_CONFIG_MIGRATION" 2>"$MIGRATION_ERR"; then
        echo -e "  ${CHECK_MARK} System config trigger installed (163-system-config-trigger.sql)"
        rm -f "$MIGRATION_ERR"
    else
        echo -e "  ${WARNING} System config trigger migration had issues:"
        cat "$MIGRATION_ERR" >&2
        rm -f "$MIGRATION_ERR"
    fi
else
    # Inline fallback if migration file is not present
    echo -e "  ${INFO} Migration file not found, applying inline..."
    psql -U "$DB_USER" -d "$DB_NAME" -q <<'INLINE_MIGRATION_SQL'
CREATE OR REPLACE FUNCTION notify_system_config_changed()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM pg_notify('agent_config_changed', json_build_object(
            'source', 'agent_system_config',
            'key', OLD.key,
            'operation', TG_OP
        )::text);
        RETURN OLD;
    END IF;
    PERFORM pg_notify('agent_config_changed', json_build_object(
        'source', 'agent_system_config',
        'key', NEW.key,
        'operation', TG_OP
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS system_config_changed ON agent_system_config;
CREATE TRIGGER system_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agent_system_config
    FOR EACH ROW EXECUTE FUNCTION notify_system_config_changed();

INSERT INTO agent_system_config (key, value, value_type)
VALUES ('max_spawn_depth', '5', 'integer')
ON CONFLICT (key) DO NOTHING;
INLINE_MIGRATION_SQL
    if [ $? -eq 0 ]; then
        echo -e "  ${CHECK_MARK} System config trigger installed (inline)"
    else
        echo -e "  ${WARNING} Inline migration had issues — check output above"
    fi
fi

# ── Install/update DB trigger for agent_config_sync ──
echo ""
echo "  Installing agent config notification trigger..."

psql -U "$DB_USER" -d "$DB_NAME" -q <<'TRIGGER_SQL'
CREATE OR REPLACE FUNCTION notify_agent_config_changed()
RETURNS trigger AS $$
BEGIN
    PERFORM pg_notify('agent_config_changed', json_build_object(
        'agent_id', COALESCE(NEW.id, OLD.id),
        'agent_name', COALESCE(NEW.name, OLD.name),
        'operation', TG_OP
    )::text);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create trigger if not exists (drop + create for idempotency)
DROP TRIGGER IF EXISTS agent_config_changed ON agents;
CREATE TRIGGER agent_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agents
    FOR EACH ROW EXECUTE FUNCTION notify_agent_config_changed();
TRIGGER_SQL

if [ $? -eq 0 ]; then
    echo -e "  ${CHECK_MARK} Agent config notification trigger installed"
else
    echo -e "  ${CROSS_MARK} Failed to install agent config notification trigger"
fi

# ============================================
# Part 5: Shell Environment Setup
# ============================================
echo ""
echo "Shell environment setup..."

NOVA_DIR="$HOME/.local/share/nova"
SHELL_ALIASES_SOURCE="$SCRIPT_DIR/dotfiles/shell-aliases.sh"
SHELL_ALIASES_TARGET="$NOVA_DIR/shell-aliases.sh"
BASH_ENV_FILE="$HOME/.bash_env"
OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"

# Create nova directory if needed
mkdir -p "$NOVA_DIR"

# Install shell-aliases.sh
if [ -f "$SHELL_ALIASES_SOURCE" ]; then
    if [ -f "$SHELL_ALIASES_TARGET" ] && [ $FORCE_INSTALL -eq 0 ]; then
        echo -e "  ${CHECK_MARK} shell-aliases.sh already installed (use --force to reinstall)"
    else
        cp "$SHELL_ALIASES_SOURCE" "$SHELL_ALIASES_TARGET"
        chmod +x "$SHELL_ALIASES_TARGET"
        echo -e "  ${CHECK_MARK} Installed shell-aliases.sh → $SHELL_ALIASES_TARGET"
    fi
else
    echo -e "  ${WARNING} shell-aliases.sh source not found: $SHELL_ALIASES_SOURCE"
fi

# Update .bash_env additively (idempotent)
BASH_ENV_SOURCE="$SCRIPT_DIR/dotfiles/bash_env"
if [ -f "$BASH_ENV_SOURCE" ]; then
    # Check if the correct source line already exists (not just any reference to shell-aliases.sh)
    if [ -f "$BASH_ENV_FILE" ] && grep -qF '~/.local/share/nova/shell-aliases.sh' "$BASH_ENV_FILE"; then
        echo -e "  ${CHECK_MARK} ~/.bash_env already sources shell-aliases.sh"
    else
        # Create file if doesn't exist or append if it does
        if [ ! -f "$BASH_ENV_FILE" ]; then
            cp "$BASH_ENV_SOURCE" "$BASH_ENV_FILE"
            echo -e "  ${CHECK_MARK} Created ~/.bash_env"
        else
            # Append with a blank line separator
            echo "" >> "$BASH_ENV_FILE"
            cat "$BASH_ENV_SOURCE" >> "$BASH_ENV_FILE"
            echo -e "  ${CHECK_MARK} Updated ~/.bash_env (additively)"
        fi
    fi
else
    echo -e "  ${WARNING} bash_env source not found: $BASH_ENV_SOURCE"
fi

# Patch OpenClaw config with BASH_ENV
if [ -f "$OPENCLAW_CONFIG" ]; then
    # Check if BASH_ENV is already configured
    if grep -q 'BASH_ENV' "$OPENCLAW_CONFIG"; then
        echo -e "  ${CHECK_MARK} OpenClaw config already has BASH_ENV set"
    else
        # Use jq for JSON manipulation
        if command -v jq &> /dev/null; then
            # Merge BASH_ENV into existing env.vars (preserving other entries)
            jq --arg bashenv "$BASH_ENV_FILE" \
                '.env.vars.BASH_ENV = $bashenv' \
                "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Added BASH_ENV to OpenClaw config (using jq)" || \
                echo -e "  ${WARNING} Could not update config with jq"
        else
            echo -e "  ${WARNING} jq not found, cannot patch OpenClaw config automatically"
            echo "      Please manually add: {\"env\": {\"vars\": {\"BASH_ENV\": \"$BASH_ENV_FILE\"}}}"
        fi
    fi
else
    echo -e "  ${WARNING} OpenClaw config not found: $OPENCLAW_CONFIG"
    echo "      You may need to manually add: {\"env\": {\"vars\": {\"BASH_ENV\": \"$BASH_ENV_FILE\"}}}"
fi

# ============================================
# Part 5b: Configure agent_chat channel
# ============================================
echo ""
echo "Configuring agent_chat channel..."

if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &> /dev/null; then
    jq --arg database "$DB_NAME" \
       --arg user "$DB_USER" \
        '.channels.agent_chat = {
            "enabled": true,
            "database": $database,
            "host": "localhost",
            "port": 5432,
            "user": $user,
            "password": ""
        }' \
        "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
        mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
        echo -e "  ${CHECK_MARK} Configured channels.agent_chat in OpenClaw config" || \
        echo -e "  ${WARNING} Could not configure agent_chat channel"

    # Also configure agent_chat plugin with the same connection details
    jq --arg database "$DB_NAME" \
       --arg user "$DB_USER" \
        '.plugins.entries.agent_chat = (.plugins.entries.agent_chat // {}) * {
            "enabled": true,
            "config": {
                "database": $database,
                "host": "localhost",
                "port": 5432,
                "user": $user,
                "password": ""
            }
        }' \
        "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
        mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
        echo -e "  ${CHECK_MARK} Configured plugins.entries.agent_chat in OpenClaw config" || \
        echo -e "  ${WARNING} Could not configure agent_chat plugin"
else
    echo -e "  ${WARNING} Cannot configure agent_chat (missing config or jq)"
fi

# ============================================
# Part 5c: Generate hooks.token if hooks enabled
# ============================================
if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &> /dev/null; then
    HOOKS_ENABLED=$(jq -r '.hooks.enabled // false' "$OPENCLAW_CONFIG" 2>/dev/null)
    if [ "$HOOKS_ENABLED" = "true" ]; then
        # Only generate if no token exists yet (don't overwrite on re-run)
        EXISTING_TOKEN=$(jq -r '.hooks.token // empty' "$OPENCLAW_CONFIG")
        if [ -z "$EXISTING_TOKEN" ]; then
            HOOKS_TOKEN=$(openssl rand -hex 32)
            jq --arg token "$HOOKS_TOKEN" \
                '.hooks.token = $token' \
                "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Generated hooks.token" || \
                echo -e "  ${WARNING} Could not set hooks.token"
        else
            echo -e "  ${CHECK_MARK} hooks.token already exists (preserved)"
        fi
    fi
fi

# ============================================
# Part 6: Verification
# ============================================
echo ""
verify_files
verify_database

# ============================================
# Installation Complete
# ============================================
echo ""
echo "═══════════════════════════════════════════"
if [ $VERIFICATION_ERRORS -gt 0 ]; then
    echo -e "  ${CROSS_MARK} Installation completed with errors"
elif [ $VERIFICATION_WARNINGS -gt 0 ]; then
    echo -e "  ${WARNING} Installation completed with warnings"
else
    echo -e "  ${GREEN}Installation complete!${NC}"
fi
echo "═══════════════════════════════════════════"
echo ""

echo "Installed components:"
echo "  • agent_chat extension (TypeScript) → $EXTENSIONS_DIR/agent_chat"
echo "  • agent_config_sync extension → $EXTENSIONS_DIR/agent_config_sync"
echo "  • agent-chat skill → $WORKSPACE/skills/agent-chat"
echo "  • agent-spawn skill → $WORKSPACE/skills/agent-spawn"
echo "  • bootstrap-context system → $OPENCLAW_DIR/hooks/db-bootstrap-context"
echo "  • agents.json (DB-synced config) → $OPENCLAW_DIR/agents.json"
echo "  • shell-aliases.sh → $NOVA_DIR/shell-aliases.sh"
echo "  • ~/.bash_env configured"
echo ""

echo "Project location:"
echo "  • Source: $SCRIPT_DIR"
echo ""

echo "Usage examples:"
echo ""
echo "1. Configure agent_chat channel in your OpenClaw config:"
echo "   channels:"
echo "     agent_chat:"
echo "       # agentName is resolved automatically from top-level agents.list config"
echo "       database: $DB_NAME"
echo "       host: localhost"
echo "       user: $DB_USER"
echo "       password: YOUR_PASSWORD"
echo ""
echo "2. Test agent-chat skill:"
echo "   📊 agent-chat --help"
echo ""
echo "3. Bootstrap context:"
echo "   psql -d $DB_NAME -c \"SELECT * FROM get_agent_bootstrap('test');\""
echo ""
echo "4. Verify installation:"
echo "   $0 --verify-only"
echo ""
echo "5. Restart OpenClaw gateway to load the extension:"
echo "   openclaw gateway restart"
echo ""

if [ $VERIFICATION_WARNINGS -gt 0 ]; then
    echo "⚠️  Warnings detected. Review output above."
    echo ""
fi

# ============================================
# Part 7: Gateway Restart (if running)
# ============================================
if systemctl --user is-active openclaw-gateway &>/dev/null; then
    if [ "${NO_RESTART}" = "1" ]; then
        echo ""
        echo "⚠️  Gateway is running. Restart required for plugin changes to take effect:"
        echo "   systemctl --user restart openclaw-gateway"
    else
        echo ""
        echo "Restarting gateway to apply changes..."
        if systemctl --user restart openclaw-gateway; then
            echo "✅ Gateway restarted"
        else
            echo "❌ Gateway restart failed. Please restart manually:"
            echo "   systemctl --user restart openclaw-gateway"
        fi
    fi
fi
