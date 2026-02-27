#!/bin/bash
# Verify nova-memory installation

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace-claude-code}"

# Use dynamic database name based on OS user
DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${DB_USER//-/_}_memory"

# Parse arguments
DB_NAME_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --database|-d)
            DB_NAME_OVERRIDE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --database, -d NAME   Override database name (default: \${USER}_memory)"
            echo "  --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Use default database name"
            echo "  $0 --database nova_memory       # Use specific database"
            echo "  $0 -d nova_memory               # Short form"
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

echo ""
echo "═══════════════════════════════════════════"
echo "  nova-memory Installation Verification"
echo "═══════════════════════════════════════════"
echo ""

# Check hooks directory
echo "Checking hooks installation..."
for hook in "memory-extract" "semantic-recall" "session-init"; do
    if [ -d "$WORKSPACE/hooks/$hook" ]; then
        echo -e "  ${GREEN}✅${NC} Hook directory exists: $hook"
        
        # Check for handler.ts
        if [ -f "$WORKSPACE/hooks/$hook/handler.ts" ]; then
            echo -e "      ${GREEN}✓${NC} handler.ts found"
            
            # Check for relative path usage
            if grep -q "dirname" "$WORKSPACE/hooks/$hook/handler.ts" && grep -q "scripts" "$WORKSPACE/hooks/$hook/handler.ts"; then
                echo -e "      ${GREEN}✓${NC} Uses relative paths"
            else
                echo -e "      ${YELLOW}⚠${NC} May not use relative paths"
            fi
        else
            echo -e "      ${RED}✗${NC} handler.ts not found"
        fi
    else
        echo -e "  ${RED}❌${NC} Hook directory missing: $hook"
    fi
done

echo ""
echo "Checking scripts installation..."
if [ -d "$WORKSPACE/scripts" ]; then
    SCRIPT_COUNT=$(find "$WORKSPACE/scripts" -name "*.sh" -o -name "*.py" | wc -l)
    echo -e "  ${GREEN}✅${NC} Scripts directory exists"
    echo "      Found $SCRIPT_COUNT script files"
    
    # Check for key scripts
    for script in "process-input.sh" "proactive-recall.py" "generate-session-context.sh"; do
        if [ -f "$WORKSPACE/scripts/$script" ]; then
            if [ -x "$WORKSPACE/scripts/$script" ]; then
                echo -e "      ${GREEN}✓${NC} $script (executable)"
            else
                echo -e "      ${YELLOW}⚠${NC} $script (not executable)"
            fi
        else
            echo -e "      ${RED}✗${NC} $script (missing)"
        fi
    done
else
    echo -e "  ${RED}❌${NC} Scripts directory missing"
fi

echo ""
echo "Checking database..."
if command -v psql &> /dev/null; then
    if psql -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        echo -e "  ${GREEN}✅${NC} Database '$DB_NAME' accessible"
        
        # Check for key tables
        TABLES=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'" 2>/dev/null | tr -d '[:space:]')
        echo "      Tables: $TABLES"
        
        # Check for pgvector
        if psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1 FROM pg_extension WHERE extname='vector'" 2>/dev/null | grep -q 1; then
            echo -e "      ${GREEN}✓${NC} pgvector extension installed"
        else
            echo -e "      ${YELLOW}⚠${NC} pgvector extension not installed"
        fi
    else
        echo -e "  ${RED}❌${NC} Cannot connect to database '$DB_NAME'"
    fi
else
    echo -e "  ${RED}❌${NC} psql command not found"
fi

echo ""
echo "Checking environment variables..."
if [ -n "$ANTHROPIC_API_KEY" ]; then
    echo -e "  ${GREEN}✅${NC} ANTHROPIC_API_KEY is set"
else
    echo -e "  ${YELLOW}⚠${NC} ANTHROPIC_API_KEY not set"
fi

if [ -n "$OPENAI_API_KEY" ]; then
    echo -e "  ${GREEN}✅${NC} OPENAI_API_KEY is set"
else
    echo -e "  ${YELLOW}⚠${NC} OPENAI_API_KEY not set"
fi

echo ""
echo "Checking Python dependencies..."
if command -v python3 &> /dev/null; then
    echo -e "  ${GREEN}✅${NC} Python3 available"
    
    for dep in "psycopg2" "anthropic" "openai"; do
        if python3 -c "import $dep" 2>/dev/null; then
            echo -e "      ${GREEN}✓${NC} $dep"
        else
            echo -e "      ${RED}✗${NC} $dep (missing)"
        fi
    done
else
    echo -e "  ${RED}❌${NC} Python3 not found"
fi

echo ""
echo "═══════════════════════════════════════════"
echo ""
