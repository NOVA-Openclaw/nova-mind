#!/bin/bash
# nova-relationships agent installer
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
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace-claude-code}"
OPENCLAW_PROJECTS="$HOME/.openclaw/projects"

# Parse arguments
VERIFY_ONLY=0
FORCE_INSTALL=0
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
        --database|-d)
            DB_NAME_OVERRIDE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verify-only         Check installation without modifying anything"
            echo "  --force               Force overwrite existing files (skip file verification)"
            echo "  --database, -d NAME   Override database name (default: \${USER}_memory)"
            echo "  --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Use default database name"
            echo "  $0 --database nova_memory       # Use specific database"
            echo "  $0 -d nova_memory               # Short form"
            echo ""
            echo "Prerequisites:"
            echo "  - Node.js 18+ and npm"
            echo "  - PostgreSQL with nova-memory database already set up"
            echo "  - nova-memory tables: entities, entity_facts, entity_relationships"
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
    echo "ERROR: Required library files missing from $OPENCLAW_LIB:" >&2
    for f in "${MISSING_FILES[@]}"; do
        echo "  - $f" >&2
    done
    echo "" >&2
    echo "These files are installed by nova-memory. Please install nova-memory first:" >&2
    echo "  cd ~/clawd/nova-memory && bash agent-install.sh" >&2
    exit 1
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

# Copy a directory tree excluding node_modules and dist directories
# Usage: copy_excluding <source_dir> <target_dir>
copy_excluding() {
    local source="$1"
    local target="$2"
    mkdir -p "$target"
    (cd "$source" && find . -type f \
        -not -path '*/node_modules/*' \
        -not -path '*/dist/*' \
        -print0 | while IFS= read -r -d '' f; do
        mkdir -p "$target/$(dirname "$f")"
        cp "$f" "$target/$f"
    done)
}

echo ""
echo "═══════════════════════════════════════════"
if [ $VERIFY_ONLY -eq 1 ]; then
    echo "  nova-relationships verification v${VERSION}"
else
    echo "  nova-relationships installer v${VERSION}"
fi
echo "═══════════════════════════════════════════"
echo ""

# ============================================
# Verification Functions
# ============================================

verify_schema() {
    echo "Schema verification..."
    
    # Check if database exists
    if ! psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "  ${CROSS_MARK} Database '$DB_NAME' does not exist"
        echo "      nova-relationships requires nova-memory to be installed first"
        echo "      Run: cd ~/clawd/nova-memory && ./agent-install.sh"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi
    
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' exists"
    
    # Check required tables
    local required_tables=("entities" "entity_facts" "entity_relationships")
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
        echo -e "  ${CROSS_MARK} Missing required tables:"
        for table in "${missing_tables[@]}"; do
            echo "      • $table"
        done
        echo "      Install nova-memory first: cd ~/clawd/nova-memory && ./agent-install.sh"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + ${#missing_tables[@]}))
        return 1
    fi
    
    # Verify key columns in entities table
    ENTITY_COLS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT column_name FROM information_schema.columns WHERE table_name = 'entities' AND column_name IN ('id', 'name', 'type', 'full_name')" | wc -l)
    
    if [ "$ENTITY_COLS" -ge 3 ]; then
        echo -e "  ${CHECK_MARK} entities table schema verified ($ENTITY_COLS key columns)"
    else
        echo -e "  ${WARNING} entities table may be incomplete (found $ENTITY_COLS/4 key columns)"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
    
    # Verify entity_facts table structure
    FACT_COLS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT column_name FROM information_schema.columns WHERE table_name = 'entity_facts' AND column_name IN ('entity_id', 'key', 'value')" | wc -l)
    
    if [ "$FACT_COLS" -ge 3 ]; then
        echo -e "  ${CHECK_MARK} entity_facts table schema verified"
    else
        echo -e "  ${WARNING} entity_facts table may be incomplete"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
    
    return 0
}

verify_files() {
    echo ""
    echo "File verification..."
    
    # Check skill directory
    if [ -d "$WORKSPACE/skills/certificate-authority" ]; then
        if [ -f "$WORKSPACE/skills/certificate-authority/SKILL.md" ]; then
            echo -e "  ${CHECK_MARK} Skill installed: certificate-authority"
        else
            echo -e "  ${WARNING} certificate-authority directory exists but missing SKILL.md"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        fi
    else
        echo -e "  ${CROSS_MARK} Skill not installed: certificate-authority"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
    
    # Check entity-resolver library
    if [ -d "$SCRIPT_DIR/lib/entity-resolver" ]; then
        echo -e "  ${CHECK_MARK} entity-resolver library present"
        
        # Check node_modules
        if [ -d "$SCRIPT_DIR/lib/entity-resolver/node_modules" ]; then
            echo -e "  ${CHECK_MARK} npm dependencies installed"
        else
            echo -e "  ${WARNING} npm dependencies not installed"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        fi
    else
        echo -e "  ${CROSS_MARK} entity-resolver library not found"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
    
    return 0
}

verify_config() {
    echo ""
    echo "Config verification..."
    
    # Check environment variables
    if [ -z "$PGUSER" ]; then
        echo -e "  ${WARNING} PGUSER not set (using current user: $(whoami))"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    else
        echo -e "  ${CHECK_MARK} PGUSER set: $PGUSER"
    fi
    
    # Check database connection
    if psql -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        echo -e "  ${CHECK_MARK} Database connection works"
    else
        echo -e "  ${CROSS_MARK} Database connection failed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi
    
    # Test entity-resolver
    if [ -f "$SCRIPT_DIR/lib/entity-resolver/test.ts" ]; then
        echo "  Testing entity-resolver connection..."
        
        # Set environment for test
        export PGUSER="$DB_USER"
        export PGDATABASE="$DB_NAME"
        
        # Run test with timeout
        cd "$SCRIPT_DIR/lib/entity-resolver"
        if timeout 10s npx tsx test.ts 2>&1 | grep -q "entity-resolver test"; then
            echo -e "  ${CHECK_MARK} entity-resolver can connect and query"
        else
            echo -e "  ${WARNING} entity-resolver test inconclusive (may need entities in database)"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        fi
        cd - > /dev/null
    fi
    
    # Check nova-ca setup
    if [ -d "$SCRIPT_DIR/nova-ca/certs" ]; then
        echo -e "  ${CHECK_MARK} nova-ca directory structure present"
        
        if [ -f "$SCRIPT_DIR/nova-ca/certs/ca.crt" ]; then
            echo -e "  ${CHECK_MARK} CA certificate exists"
        else
            echo -e "  ${INFO} CA certificate not created yet (optional)"
        fi
    else
        echo -e "  ${WARNING} nova-ca directory structure incomplete"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
    
    return 0
}

# ============================================
# Part 1: Prerequisites Check
# ============================================
echo "Checking prerequisites..."

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
    echo -e "  ${CROSS_MARK} PostgreSQL service not running"
    echo ""
    echo "Please start PostgreSQL:"
    echo "  Ubuntu/Debian: sudo systemctl start postgresql"
    echo "  macOS: brew services start postgresql"
    exit 1
fi

# Check nova-memory database exists
if ! psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "  ${CROSS_MARK} Database '$DB_NAME' not found"
    echo ""
    echo "nova-relationships requires nova-memory to be installed first."
    echo ""
    echo "Please run:"
    echo "  cd ~/clawd/nova-memory"
    echo "  ./agent-install.sh"
    echo ""
    exit 1
else
    echo -e "  ${CHECK_MARK} nova-memory database exists"
fi

# ============================================
# Run Verification if --verify-only
# ============================================
if [ $VERIFY_ONLY -eq 1 ]; then
    echo ""
    verify_schema
    verify_files
    verify_config
    
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
# Part 2: NPM Dependencies (entity-resolver)
# ============================================
echo ""
echo "NPM dependencies (entity-resolver)..."

cd "$SCRIPT_DIR/lib/entity-resolver"

if [ -d "node_modules" ] && [ $FORCE_INSTALL -eq 0 ]; then
    echo -e "  ${CHECK_MARK} Dependencies already installed (use --force to reinstall)"
else
    echo "  Running npm install..."
    NPM_LOG=$(mktemp /tmp/npm-install-XXXXXX.log)
    TMPFILES+=("$NPM_LOG")
    if npm install > "$NPM_LOG" 2>&1; then
        echo -e "  ${CHECK_MARK} npm install completed"
    else
        echo -e "  ${CROSS_MARK} npm install failed"
        echo "      Log: $NPM_LOG"
        tail -20 "$NPM_LOG"
        exit 1
    fi
fi

cd "$SCRIPT_DIR"

# Verify key dependencies
REQUIRED_DEPS=("pg" "typescript")
MISSING_DEPS=()

for dep in "${REQUIRED_DEPS[@]}"; do
    if [ -d "$SCRIPT_DIR/lib/entity-resolver/node_modules/$dep" ]; then
        echo -e "  ${CHECK_MARK} $dep installed"
    else
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "  ${CROSS_MARK} Missing dependencies: ${MISSING_DEPS[*]}"
    exit 1
fi

# ============================================
# Part 3: Skills Installation
# ============================================
echo ""
echo "Skills installation..."

SKILLS_DIR="$WORKSPACE/skills"
mkdir -p "$SKILLS_DIR"

# Install certificate-authority skill
SKILL_NAME="certificate-authority"
SKILL_SOURCE="$SCRIPT_DIR/skills/$SKILL_NAME"
SKILL_TARGET="$SKILLS_DIR/$SKILL_NAME"

if [ ! -d "$SKILL_SOURCE" ]; then
    echo -e "  ${WARNING} Skill not found: $SKILL_NAME (skipping)"
else
    # Remove legacy symlink if present
    if [ -L "$SKILL_TARGET" ]; then
        rm "$SKILL_TARGET"
        echo -e "  ${INFO} Removed legacy symlink for $SKILL_NAME"
    fi
    copy_excluding "$SKILL_SOURCE" "$SKILL_TARGET"
    echo -e "  ${CHECK_MARK} Installed skill: $SKILL_NAME"
fi

# ============================================
# Part 4: Certificate Authority Setup
# ============================================
echo ""
echo "Certificate Authority setup..."

CA_DIR="$SCRIPT_DIR/nova-ca"

if [ ! -d "$CA_DIR" ]; then
    echo -e "  ${WARNING} nova-ca directory not found (skipping)"
else
    # Ensure proper permissions on private directory
    if [ -d "$CA_DIR/private" ]; then
        chmod 700 "$CA_DIR/private" 2>/dev/null || true
        echo -e "  ${CHECK_MARK} CA private directory permissions set"
    fi
    
    # Check if CA is already initialized
    if [ -f "$CA_DIR/certs/ca.crt" ] && [ -f "$CA_DIR/private/ca.key" ]; then
        echo -e "  ${CHECK_MARK} CA already initialized"
        
        # Verify CA certificate
        if openssl x509 -in "$CA_DIR/certs/ca.crt" -noout -text > /dev/null 2>&1; then
            EXPIRY=$(openssl x509 -in "$CA_DIR/certs/ca.crt" -noout -enddate | cut -d= -f2)
            echo -e "  ${CHECK_MARK} CA certificate valid (expires: $EXPIRY)"
        else
            echo -e "  ${WARNING} CA certificate may be corrupted"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        fi
    else
        echo -e "  ${INFO} CA not initialized yet (optional)"
        echo "      To create CA: cd $CA_DIR && see skills/certificate-authority/SKILL.md"
    fi
    
    # Check sign-client-csr.sh is executable
    if [ -f "$CA_DIR/sign-client-csr.sh" ]; then
        chmod +x "$CA_DIR/sign-client-csr.sh"
        echo -e "  ${CHECK_MARK} CSR signing script ready"
    fi
fi

# ============================================
# Part 5: Verification
# ============================================
echo ""
verify_schema
verify_files
verify_config

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
echo "  • entity-resolver library (TypeScript)"
echo "  • certificate-authority skill"
echo "  • nova-ca infrastructure"
echo ""

echo "Project location:"
echo "  • Source: $SCRIPT_DIR"
echo ""

echo "Usage examples:"
echo ""
echo "1. Test entity-resolver:"
echo "   cd $SCRIPT_DIR/lib/entity-resolver"
echo "   npx tsx test.ts [phone_or_uuid]"
echo ""
echo "2. Use in your code:"
echo "   import { resolveEntity } from '~/.openclaw/projects/nova-relationships/lib/entity-resolver';"
echo ""
echo "3. Manage certificates:"
echo "   cd $CA_DIR"
echo "   ./sign-client-csr.sh client.csr entity_name"
echo ""
echo "4. Verify installation:"
echo "   $0 --verify-only"
echo ""

if [ $VERIFICATION_WARNINGS -gt 0 ]; then
    echo "⚠️  Warnings detected. Review output above."
    echo ""
fi
