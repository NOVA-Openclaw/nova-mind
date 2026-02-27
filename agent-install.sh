#!/usr/bin/env bash
# nova-mind unified agent installer
# Combines: relationships, memory, cognition
# Idempotent — safe to run multiple times

set -euo pipefail

VERSION="2.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# SECTION 1: Color codes and status indicators
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CHECK_MARK="${GREEN}✅${NC}"
CROSS_MARK="${RED}❌${NC}"
WARNING="${YELLOW}⚠️${NC}"
INFO="${BLUE}ℹ️${NC}"

# Verification results
VERIFICATION_PASSED=0
VERIFICATION_WARNINGS=0
VERIFICATION_ERRORS=0

# Track if gateway restart is needed
GATEWAY_RESTART_NEEDED=0

# Temp file cleanup
TMPFILES=()
cleanup_tmp() { rm -f "${TMPFILES[@]}"; }
trap cleanup_tmp EXIT

# ============================================
# SECTION 2: Source shared library
# ============================================
PG_ENV="$SCRIPT_DIR/lib/pg-env.sh"
if [ ! -f "$PG_ENV" ]; then
    echo -e "  ${RED}❌${NC} $PG_ENV not found"
    exit 1
fi
source "$PG_ENV"

# ============================================
# SECTION 3: Load environment
# ============================================
PG_CONFIG="${HOME}/.openclaw/postgres.json"
if [ -f "$PG_CONFIG" ] && [ -r "$PG_CONFIG" ]; then
    load_pg_env
else
    echo "ERROR: Config file not found: $PG_CONFIG" >&2
    echo "Run shell-install.sh first or create ~/.openclaw/postgres.json" >&2
    echo "" >&2
    echo "Example ~/.openclaw/postgres.json:" >&2
    echo '  { "host": "localhost", "port": 5432, "database": "mydb", "user": "myuser", "password": "" }' >&2
    exit 1
fi

# Derived variables
DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${PGDATABASE:-${DB_USER//-/_}_memory}"
WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace-coder}"
OPENCLAW_DIR="$HOME/.openclaw"
OPENCLAW_PROJECTS="$OPENCLAW_DIR/projects"
EXTENSIONS_DIR="$OPENCLAW_DIR/extensions"

# ============================================
# SECTION 4: Parse arguments
# ============================================
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
            echo "  --force               Force overwrite existing files (skip file verification)"
            echo "  --no-restart          Skip automatic gateway restart after install"
            echo "  --database, -d NAME   Override database name (default: \${USER}_memory)"
            echo "  --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Use default database name"
            echo "  $0 --database nova_memory       # Use specific database"
            echo "  $0 -d nova_memory               # Short form"
            echo "  $0 --verify-only                # Check installation status"
            echo "  $0 --force                      # Force reinstall all components"
            echo ""
            echo "Installs:"
            echo "  [relationships] entity-resolver lib, relationship hooks/skills"
            echo "  [memory]        schema (pgschema), hooks, scripts, skills, embeddings"
            echo "  [cognition]     hooks, workflows, bootstrap context, agent_chat plugin"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

if [ -n "$DB_NAME_OVERRIDE" ]; then
    DB_NAME="$DB_NAME_OVERRIDE"
fi

# ============================================
# SECTION 5: Prerequisites check
# ============================================
echo ""
echo "═══════════════════════════════════════════"
if [ $VERIFY_ONLY -eq 1 ]; then
    echo "  nova-mind verification v${VERSION}"
else
    echo "  nova-mind installer v${VERSION}"
fi
echo "═══════════════════════════════════════════"
echo ""

echo "Checking prerequisites..."

# PostgreSQL CLI
if command -v psql &>/dev/null; then
    PG_VERSION=$(psql --version | awk '{print $3}')
    echo -e "  ${CHECK_MARK} PostgreSQL installed ($PG_VERSION)"
else
    echo -e "  ${CROSS_MARK} PostgreSQL not found"
    echo "  Install: sudo apt install postgresql postgresql-contrib"
    exit 1
fi

# PostgreSQL service
if pg_isready -q 2>/dev/null; then
    echo -e "  ${CHECK_MARK} PostgreSQL service running"
else
    echo -e "  ${CROSS_MARK} PostgreSQL service not running"
    echo "  Start: sudo systemctl start postgresql"
    exit 1
fi

# jq
if command -v jq &>/dev/null; then
    echo -e "  ${CHECK_MARK} jq available"
else
    echo -e "  ${CROSS_MARK} jq not found (required)"
    echo "  Install: sudo apt install jq"
    exit 1
fi

# pgschema (required for memory schema management)
if command -v pgschema &>/dev/null; then
    PGSCHEMA_BIN="pgschema"
    echo -e "  ${CHECK_MARK} pgschema available"
elif [ -x "$HOME/go/bin/pgschema" ]; then
    PGSCHEMA_BIN="$HOME/go/bin/pgschema"
    echo -e "  ${CHECK_MARK} pgschema available at $PGSCHEMA_BIN"
else
    echo -e "  ${CROSS_MARK} pgschema not found (required for schema management)"
    echo "  Install: go install github.com/pgplex/pgschema@latest"
    echo "  Then add ~/go/bin to your PATH"
    exit 1
fi

# Node.js (required for relationships and cognition)
if [ $VERIFY_ONLY -eq 0 ]; then
    if command -v node &>/dev/null; then
        NODE_VERSION=$(node --version)
        NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v\([0-9]*\).*/\1/')
        if [ "$NODE_MAJOR" -ge 18 ]; then
            echo -e "  ${CHECK_MARK} Node.js installed ($NODE_VERSION)"
        else
            echo -e "  ${WARNING} Node.js $NODE_VERSION (recommend 18+)"
        fi
    else
        echo -e "  ${CROSS_MARK} Node.js not found"
        echo "  Install: curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt install -y nodejs"
        exit 1
    fi

    if command -v npm &>/dev/null; then
        NPM_VERSION=$(npm --version)
        echo -e "  ${CHECK_MARK} npm installed ($NPM_VERSION)"
    else
        echo -e "  ${CROSS_MARK} npm not found"
        exit 1
    fi
fi

# Python3
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    echo -e "  ${CHECK_MARK} Python3 available ($PYTHON_VERSION)"
else
    echo -e "  ${CROSS_MARK} Python3 not found (required for memory scripts)"
    echo "  Install: sudo apt install python3 python3-pip"
    exit 1
fi

# ============================================
# SECTION 6: Helper functions
# ============================================

# copy_excluding <source_dir> <target_dir>
# Copies a directory tree excluding node_modules and dist
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

# sync_directory <source_dir> <target_dir> [label]
# Hash-based file sync — copies new/changed files, skips identical.
# Honors FORCE_INSTALL. Sets SYNC_UPDATED, SYNC_SKIPPED, SYNC_ADDED.
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

    while IFS= read -r -d '' rel_path; do
        local src_file="$src_dir/$rel_path"
        local tgt_file="$tgt_dir/$rel_path"

        mkdir -p "$(dirname "$tgt_file")"

        if [ "$FORCE_INSTALL" -eq 1 ]; then
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

# install_hook <hook_name> <source_base_dir>
# Installs or updates a hook using hash comparison.
# Returns: 0=installed/updated, 1=missing, 2=up-to-date
install_hook() {
    local hook_name="$1"
    local hooks_source="$2"
    local source="$hooks_source/$hook_name"
    local target="$OPENCLAW_DIR/hooks/$hook_name"

    if [ ! -d "$source" ]; then
        echo -e "  ${WARNING} Hook not found: $hook_name (skipping)"
        return 1
    fi

    if [ "$FORCE_INSTALL" -eq 0 ] && [ -d "$target" ]; then
        local all_match=1
        for source_file in "$source"/*.ts "$source"/*.js "$source"/*.sh; do
            [ -f "$source_file" ] || continue
            local filename target_file
            filename=$(basename "$source_file")
            target_file="$target/$filename"
            if [ -f "$target_file" ]; then
                local sh th
                sh=$(sha256sum "$source_file" | awk '{print $1}')
                th=$(sha256sum "$target_file" | awk '{print $1}')
                [ "$sh" != "$th" ] && all_match=0 && break
            else
                all_match=0; break
            fi
        done
        if [ "$all_match" -eq 1 ]; then
            echo -e "  ${INFO} $hook_name up to date"
            return 2
        fi
    fi

    local was_existing=0
    if [ -e "$target" ]; then
        was_existing=1
        rm -rf "$target"
    fi

    copy_excluding "$source" "$target"
    if [ "$was_existing" -eq 1 ]; then
        echo -e "  ${CHECK_MARK} $hook_name updated"
    else
        echo -e "  ${CHECK_MARK} $hook_name installed"
    fi
    return 0
}

# install_lib_files: Install shared PG loader files to ~/.openclaw/lib/
install_lib_files() {
    local lib_src="$SCRIPT_DIR/memory/lib"
    local lib_dst="$HOME/.openclaw/lib"
    local files=("pg-env.sh" "pg_env.py" "pg-env.ts" "env-loader.sh" "env_loader.py")

    mkdir -p "$lib_dst"
    chmod 755 "$lib_dst"

    for f in "${files[@]}"; do
        local src="$lib_src/$f"
        local dst="$lib_dst/$f"

        if [ ! -f "$src" ]; then
            echo -e "  ${WARNING} [lib] $f: source not found in repo, skipping"
            continue
        fi

        if [ ! -f "$dst" ]; then
            cp "$src" "$dst"
            chmod 644 "$dst"
            echo -e "  ${CHECK_MARK} [lib] $f: installed"
        else
            local src_hash dst_hash
            src_hash=$(sha256sum "$src" | awk '{print $1}')
            dst_hash=$(sha256sum "$dst" | awk '{print $1}')
            if [ "$src_hash" != "$dst_hash" ]; then
                cp "$src" "$dst"
                chmod 644 "$dst"
                echo -e "  ${CHECK_MARK} [lib] $f: updated (hash changed)"
            else
                echo -e "  ${INFO} [lib] $f: up to date"
            fi
        fi
    done
}

# install_skills <source_skills_dir> <target_skills_dir> [label]
# Installs or updates skills using hash comparison.
install_skills() {
    local skills_source="$1"
    local skills_target="$2"
    local label="${3:-skills}"

    if [ ! -d "$skills_source" ]; then
        echo -e "  ${WARNING} Skills source directory not found: $skills_source"
        return 1
    fi

    mkdir -p "$skills_target"

    local skills_installed=0
    local skills_skipped=0
    local skills_updated=0

    for skill_dir in "$skills_source"/*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name target_skill
        skill_name=$(basename "$skill_dir")
        target_skill="$skills_target/$skill_name"

        # Remove legacy symlinks
        if [ -L "$target_skill" ]; then
            rm "$target_skill"
            echo -e "  ${INFO} Removed legacy symlink for $skill_name"
        fi

        if [ -d "$target_skill" ]; then
            if [ "$FORCE_INSTALL" -eq 1 ]; then
                rm -rf "$target_skill"
                copy_excluding "$skill_dir" "$target_skill"
                echo -e "  ${CHECK_MARK} $skill_name updated (forced)"
                skills_updated=$((skills_updated + 1))
            else
                local needs_update=0
                while IFS= read -r -d '' source_file; do
                    local rel_path="${source_file#$skill_dir}"
                    local target_file="$target_skill/$rel_path"
                    if [ ! -f "$target_file" ]; then
                        needs_update=1; break
                    fi
                    local sh th
                    sh=$(sha256sum "$source_file" | awk '{print $1}')
                    th=$(sha256sum "$target_file" | awk '{print $1}')
                    [ "$sh" != "$th" ] && needs_update=1 && break
                done < <(find "$skill_dir" -type f -print0)

                if [ "$needs_update" -eq 0 ]; then
                    echo -e "  ${INFO} $skill_name up to date"
                    skills_skipped=$((skills_skipped + 1))
                else
                    echo -e "  ${WARNING} $skill_name exists with modifications (use --force to overwrite)"
                    skills_skipped=$((skills_skipped + 1))
                fi
            fi
        else
            copy_excluding "$skill_dir" "$target_skill"
            echo -e "  ${CHECK_MARK} $skill_name installed"
            skills_installed=$((skills_installed + 1))
        fi
    done

    if [ $((skills_installed + skills_updated)) -gt 0 ]; then
        echo -e "  ${CHECK_MARK} $label: $skills_installed installed, $skills_updated updated, $skills_skipped skipped"
    elif [ "$skills_skipped" -gt 0 ]; then
        echo -e "  ${INFO} $label: all $skills_skipped skill(s) already present"
    fi
}

# ============================================
# Verification functions
# ============================================

verify_schema() {
    echo "Schema verification (memory)..."

    if ! psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "  ${CROSS_MARK} Database '$DB_NAME' does not exist"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi

    local SCHEMA_FILE="$SCRIPT_DIR/memory/schema/schema.sql"
    if [ -f "$SCHEMA_FILE" ]; then
        local TABLE_NAMES
        TABLE_NAMES=$(grep "^CREATE TABLE" "$SCHEMA_FILE" | sed -E 's/CREATE TABLE IF NOT EXISTS ([^ ]+).*/\1/' | sort)
        local tables_missing=()
        local tables_present=0

        for table in $TABLE_NAMES; do
            local TABLE_EXISTS
            TABLE_EXISTS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table'" | tr -d '[:space:]')
            if [ "$TABLE_EXISTS" -eq 0 ]; then
                tables_missing+=("$table")
            else
                tables_present=$((tables_present + 1))
            fi
        done

        if [ ${#tables_missing[@]} -gt 0 ]; then
            echo -e "  ${WARNING} Missing tables:"
            for table in "${tables_missing[@]}"; do
                echo "      • $table"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + ${#tables_missing[@]}))
        else
            echo -e "  ${CHECK_MARK} All schema tables present ($tables_present tables)"
        fi
    else
        echo -e "  ${WARNING} Schema file not found: $SCHEMA_FILE"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
}

verify_relationships() {
    echo ""
    echo "Verification (relationships)..."

    local required_tables=("entities" "entity_facts" "entity_relationships")
    local missing_tables=()
    for table in "${required_tables[@]}"; do
        local TABLE_EXISTS
        TABLE_EXISTS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table'" | tr -d '[:space:]')
        if [ "$TABLE_EXISTS" -eq 0 ]; then
            missing_tables+=("$table")
        else
            echo -e "  ${CHECK_MARK} Table '$table' exists"
        fi
    done
    if [ ${#missing_tables[@]} -gt 0 ]; then
        echo -e "  ${CROSS_MARK} Missing relationship tables: ${missing_tables[*]}"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + ${#missing_tables[@]}))
    fi

    if [ -d "$SCRIPT_DIR/relationships/lib/entity-resolver" ]; then
        echo -e "  ${CHECK_MARK} entity-resolver library present"
    else
        echo -e "  ${CROSS_MARK} entity-resolver library not found"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
}

verify_cognition() {
    echo ""
    echo "Verification (cognition)..."

    if [ -d "$EXTENSIONS_DIR/agent_chat" ]; then
        echo -e "  ${CHECK_MARK} agent_chat extension directory exists"
        if [ -f "$EXTENSIONS_DIR/agent_chat/dist/index.js" ]; then
            echo -e "  ${CHECK_MARK} agent_chat compiled"
        else
            echo -e "  ${CROSS_MARK} agent_chat not compiled"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        fi
    else
        echo -e "  ${CROSS_MARK} agent_chat extension not installed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi

    if [ -d "$OPENCLAW_DIR/hooks/db-bootstrap-context" ]; then
        echo -e "  ${CHECK_MARK} Bootstrap context hook installed"
    else
        echo -e "  ${CROSS_MARK} Bootstrap context hook not installed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi

    local required_tables=("agent_chat" "agent_chat_processed")
    for table in "${required_tables[@]}"; do
        local TABLE_EXISTS
        TABLE_EXISTS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table'" | tr -d '[:space:]')
        if [ "$TABLE_EXISTS" -eq 0 ]; then
            echo -e "  ${WARNING} Table '$table' not yet created (will be created by extension)"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        else
            echo -e "  ${CHECK_MARK} Table '$table' exists"
        fi
    done
}

verify_config() {
    echo ""
    echo "Config verification..."

    if [ -z "${PGUSER:-}" ]; then
        echo -e "  ${WARNING} PGUSER not set (using: $(whoami))"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    else
        echo -e "  ${CHECK_MARK} PGUSER set: $PGUSER"
    fi

    if psql -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        echo -e "  ${CHECK_MARK} Database connection works"
    else
        echo -e "  ${CROSS_MARK} Database connection failed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi

    local HOOK_CONFIG="$HOME/.openclaw/hooks.json"
    if [ -f "$HOOK_CONFIG" ]; then
        echo -e "  ${CHECK_MARK} OpenClaw hook config exists"
        for hook in "memory-extract" "semantic-recall" "session-init" "agent-turn-context"; do
            if grep -q "\"$hook\"" "$HOOK_CONFIG" 2>/dev/null; then
                local ENABLED
                ENABLED=$(grep -A5 "\"$hook\"" "$HOOK_CONFIG" | grep -c "\"enabled\": true" || echo "0")
                if [ "$ENABLED" -gt 0 ]; then
                    echo -e "  ${CHECK_MARK} Hook '$hook' enabled"
                else
                    echo -e "  ${WARNING} Hook '$hook' exists but not enabled"
                    VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
                fi
            else
                echo -e "  ${WARNING} Hook '$hook' not found in OpenClaw config"
                VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            fi
        done
    else
        echo -e "  ${WARNING} OpenClaw hook config not found at $HOOK_CONFIG"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
}

# ============================================
# Run verification early if --verify-only
# ============================================
if [ $VERIFY_ONLY -eq 1 ]; then
    verify_schema
    verify_relationships
    verify_cognition
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
# SECTION 7: RELATIONSHIPS install
# ============================================
echo ""
echo "════════════════════════════════"
echo "  [1/3] RELATIONSHIPS"
echo "════════════════════════════════"

# --- Install entity-resolver npm dependencies ---
echo ""
echo "Entity-resolver dependencies..."

ENTITY_RESOLVER_DIR="$SCRIPT_DIR/relationships/lib/entity-resolver"

if [ -d "$ENTITY_RESOLVER_DIR" ]; then
    cd "$ENTITY_RESOLVER_DIR"

    if [ -d "node_modules" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
        echo -e "  ${CHECK_MARK} Dependencies already installed (use --force to reinstall)"
    else
        echo "  Running npm install..."
        NPM_LOG=$(mktemp /tmp/npm-install-entity-resolver-XXXXXX.log)
        TMPFILES+=("$NPM_LOG")
        if npm install >"$NPM_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} npm install completed"
        else
            echo -e "  ${CROSS_MARK} npm install failed"
            tail -20 "$NPM_LOG"
        fi
    fi

    cd "$SCRIPT_DIR"
else
    echo -e "  ${WARNING} entity-resolver directory not found at $ENTITY_RESOLVER_DIR (skipping)"
fi

# --- Sync relationship hooks ---
echo ""
echo "Relationship hooks..."

HOOKS_TARGET="$OPENCLAW_DIR/hooks"
mkdir -p "$HOOKS_TARGET"

INSTALLED_HOOKS=()
SKIPPED_HOOKS=()

# Relationships does not have its own hooks/ dir; hooks come from memory/ and cognition/
# (No hook files are in relationships/; skip silently)

# --- Sync relationship skills ---
echo ""
echo "Relationship skills..."

REL_SKILLS_SOURCE="$SCRIPT_DIR/relationships/skills"
if [ -d "$REL_SKILLS_SOURCE" ]; then
    SKILLS_TARGET="$WORKSPACE/skills"
    mkdir -p "$SKILLS_TARGET"
    install_skills "$REL_SKILLS_SOURCE" "$SKILLS_TARGET" "relationship skills"
else
    echo -e "  ${INFO} No relationship skills directory found (skipping)"
fi

# ============================================
# SECTION 8: MEMORY install
# ============================================
echo ""
echo "════════════════════════════════"
echo "  [2/3] MEMORY"
echo "════════════════════════════════"

# --- Install shared PG loader libraries ---
echo ""
echo "Installing shared PG loader libraries..."
install_lib_files

# --- API key check ---
echo ""
echo "API key configuration..."

if [ -z "${OPENAI_API_KEY:-}" ]; then
    echo -e "  ${WARNING} OPENAI_API_KEY not set"
    echo "      Required for semantic recall (embeddings)."
    echo "      Set it in openclaw.json env.vars or export before running."
else
    echo -e "  ${CHECK_MARK} OPENAI_API_KEY set: ${OPENAI_API_KEY:0:8}..."
fi

# --- Database setup ---
echo ""
echo "Database setup..."

if psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' exists"
    if psql -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        echo -e "  ${CHECK_MARK} Database connection verified"
    else
        echo -e "  ${CROSS_MARK} Cannot connect to database '$DB_NAME'"
        exit 1
    fi
else
    echo "  Creating database '$DB_NAME'..."
    createdb -U "$DB_USER" "$DB_NAME" 2>/dev/null || {
        echo -e "  ${CROSS_MARK} Failed to create database '$DB_NAME'"
        exit 1
    }
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' created"
fi

# --- Schema management via pgschema ---
SCHEMA_FILE="$SCRIPT_DIR/memory/schema/schema.sql"

if [ ! -f "$SCHEMA_FILE" ]; then
    echo -e "  ${CROSS_MARK} memory/schema/schema.sql not found at $SCHEMA_FILE"
    exit 1
fi

SCHEMA_DIFF_SKIPPED=0

echo ""
echo "Schema management (pgschema)..."

# -- Extensions --
echo "  Ensuring extensions..."
EXTENSIONS=$(grep -E "(^|INSTALLER HANDLES: )CREATE EXTENSION IF NOT EXISTS" "$SCHEMA_FILE" | sed "s/.*CREATE EXTENSION IF NOT EXISTS //;s/ .*//;s/;//" || true)
if [ -n "$EXTENSIONS" ]; then
    for ext in $EXTENSIONS; do
        if psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT 1 FROM pg_extension WHERE extname = '$ext'" | grep -q 1; then
            echo -e "  ${CHECK_MARK} Extension '$ext' already installed"
        else
            if psql -U "$DB_USER" -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS \"$ext\";" >/dev/null 2>&1; then
                echo -e "  ${CHECK_MARK} Extension '$ext' installed"
            else
                echo -e "  ${WARNING} Extension '$ext' not installed — requires superuser"
                SCHEMA_DIFF_SKIPPED=1
            fi
        fi
    done
else
    echo -e "  ${INFO} No extensions defined in schema.sql"
fi

# -- Pre-migrations --
PRE_MIGRATIONS_DIR="$SCRIPT_DIR/memory/pre-migrations"
if [ -d "$PRE_MIGRATIONS_DIR" ]; then
    PRE_MIGRATION_FILES=()
    while IFS= read -r -d '' f; do
        PRE_MIGRATION_FILES+=("$f")
    done < <(find "$PRE_MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" -print0 | sort -z)

    if [ ${#PRE_MIGRATION_FILES[@]} -gt 0 ]; then
        echo "  Running pre-migrations (${#PRE_MIGRATION_FILES[@]} files)..."
        for sql_file in "${PRE_MIGRATION_FILES[@]}"; do
            local_filename=$(basename "$sql_file")
            if psql -U "$DB_USER" -d "$DB_NAME" -f "$sql_file" >/dev/null 2>&1; then
                echo -e "  ${CHECK_MARK} Pre-migration: $local_filename"
            else
                echo -e "  ${WARNING} Pre-migration failed: $local_filename (continuing)"
            fi
        done
    else
        echo -e "  ${INFO} No pre-migration scripts found"
    fi
fi

if [ "$SCHEMA_DIFF_SKIPPED" -eq 1 ]; then
    echo -e "  ${WARNING} Skipping pgschema plan/apply (extension install failed above)"
else
    # Build connection args
    PGSCHEMA_CONN_ARGS=(
        "--host" "${PGHOST:-/var/run/postgresql}"
        "--port" "${PGPORT:-5432}"
        "--db" "$DB_NAME"
        "--user" "$DB_USER"
    )
    PGSCHEMA_PLAN_ARGS=(
        "--plan-host" "${PGHOST:-/var/run/postgresql}"
        "--plan-port" "${PGPORT:-5432}"
        "--plan-db" "$DB_NAME"
        "--plan-user" "$DB_USER"
    )
    if [ -n "${PGPASSWORD:-}" ]; then
        PGSCHEMA_CONN_ARGS+=("--password" "$PGPASSWORD")
        PGSCHEMA_PLAN_ARGS+=("--plan-password" "$PGPASSWORD")
    fi

    # Optionally use .pgschemaignore from memory/
    PGSCHEMA_IGNORE_OPT=()
    if [ -f "$SCRIPT_DIR/memory/.pgschemaignore" ]; then
        PGSCHEMA_IGNORE_OPT+=("--ignore-file" "$SCRIPT_DIR/memory/.pgschemaignore")
    fi

    PLAN_FILE=$(mktemp /tmp/pgschema-plan-XXXXXX.json)
    TMPFILES+=("$PLAN_FILE")

    echo "  Running pgschema plan..."
    PLAN_EXIT=0
    "$PGSCHEMA_BIN" plan \
        "${PGSCHEMA_CONN_ARGS[@]}" \
        --schema public \
        --file "$SCHEMA_FILE" \
        "${PGSCHEMA_PLAN_ARGS[@]}" \
        --output-json "$PLAN_FILE" \
        --no-color 2>&1 || PLAN_EXIT=$?

    if [ $PLAN_EXIT -ne 0 ]; then
        echo -e "  ${WARNING} pgschema plan failed (exit $PLAN_EXIT) — schema apply skipped"
        SCHEMA_DIFF_SKIPPED=1
    else
        HAZARD_COUNT=$(jq '[(.groups // [])[] | .steps[] | select(.type != "privilege") | select(.operation == "drop") | select(.type | test("^table"))] | length' "$PLAN_FILE" 2>/dev/null || echo "0")
        TOTAL_STEPS=$(jq '[(.groups // [])[] | .steps[] | select(.type != "privilege")] | length' "$PLAN_FILE" 2>/dev/null || echo "0")

        if [ "$HAZARD_COUNT" -gt 0 ] 2>/dev/null; then
            echo -e "  ${WARNING} Destructive changes detected — schema apply SKIPPED"
            echo "      $HAZARD_COUNT destructive operation(s) (DROP on table/column):"
            jq -r '(.groups // [])[] | .steps[] | select(.type != "privilege") | select(.operation == "drop") | select(.type | test("^table")) | "      • " + .path' "$PLAN_FILE" 2>/dev/null || true
            echo "      To apply manually: $PGSCHEMA_BIN apply ${PGSCHEMA_CONN_ARGS[*]} --schema public --plan $PLAN_FILE --auto-approve"
            SCHEMA_DIFF_SKIPPED=1
        elif [ "$TOTAL_STEPS" -eq 0 ] 2>/dev/null; then
            echo -e "  ${CHECK_MARK} Schema is up to date — no changes needed"
        else
            echo "  Applying $TOTAL_STEPS schema change(s)..."
            APPLY_EXIT=0
            "$PGSCHEMA_BIN" apply \
                "${PGSCHEMA_CONN_ARGS[@]}" \
                --schema public \
                --plan "$PLAN_FILE" \
                --auto-approve \
                --no-color 2>&1 || APPLY_EXIT=$?

            if [ $APPLY_EXIT -eq 0 ]; then
                echo -e "  ${CHECK_MARK} Schema applied successfully"
                TABLE_COUNT=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'" | tr -d '[:space:]')
                echo "      Total tables in database: $TABLE_COUNT"
            else
                echo -e "  ${WARNING} Schema apply failed (exit $APPLY_EXIT) — continuing"
                SCHEMA_DIFF_SKIPPED=1
            fi
        fi
    fi

    rm -f "$PLAN_FILE"
fi

# --- Memory hooks ---
echo ""
echo "Memory hooks installation..."

HOOKS_TARGET="$OPENCLAW_DIR/hooks"
mkdir -p "$HOOKS_TARGET"

for hook in "memory-extract" "semantic-recall" "session-init" "agent-turn-context"; do
    install_hook "$hook" "$SCRIPT_DIR/memory/hooks" && result=$? || result=$?
    if [ "$result" -eq 0 ]; then
        INSTALLED_HOOKS+=("$hook")
    elif [ "$result" -eq 2 ]; then
        SKIPPED_HOOKS+=("$hook")
    fi
done

# --- Memory scripts ---
echo ""
echo "Memory scripts setup..."

SCRIPTS_SOURCE="$SCRIPT_DIR/memory/scripts"
SCRIPTS_TARGET_WORKSPACE="$WORKSPACE/scripts"
SCRIPTS_TARGET_OPENCLAW="$HOME/.openclaw/scripts"
OPENCLAW_LOGS_DIR="$HOME/.openclaw/logs"

mkdir -p "$OPENCLAW_LOGS_DIR"
echo -e "  ${INFO} Logs directory: $OPENCLAW_LOGS_DIR"

if [ -d "$SCRIPTS_SOURCE" ]; then
    mkdir -p "$SCRIPTS_TARGET_WORKSPACE"
    mkdir -p "$SCRIPTS_TARGET_OPENCLAW"

    scripts_copied=0

    for source_file in "$SCRIPTS_SOURCE"/*.sh "$SCRIPTS_SOURCE"/*.py; do
        [ -f "$source_file" ] || continue
        filename=$(basename "$source_file")
        target_file_workspace="$SCRIPTS_TARGET_WORKSPACE/$filename"
        target_file_openclaw="$SCRIPTS_TARGET_OPENCLAW/$filename"

        if [ "$FORCE_INSTALL" -eq 0 ]; then
            source_hash=$(sha256sum "$source_file" | awk '{print $1}')
            workspace_matches=0
            openclaw_matches=0
            if [ -f "$target_file_workspace" ]; then
                wh=$(sha256sum "$target_file_workspace" | awk '{print $1}')
                [ "$source_hash" = "$wh" ] && workspace_matches=1
            fi
            if [ -f "$target_file_openclaw" ]; then
                oh=$(sha256sum "$target_file_openclaw" | awk '{print $1}')
                [ "$source_hash" = "$oh" ] && openclaw_matches=1
            fi
            [ "$workspace_matches" -eq 1 ] && [ "$openclaw_matches" -eq 1 ] && continue
        fi

        cp "$source_file" "$target_file_workspace"
        cp "$source_file" "$target_file_openclaw"
        scripts_copied=$((scripts_copied + 1))
    done

    echo -e "  ${CHECK_MARK} $scripts_copied scripts installed to:"
    echo "      • $SCRIPTS_TARGET_WORKSPACE"
    echo "      • $SCRIPTS_TARGET_OPENCLAW"

    # Make all scripts executable
    SCRIPT_COUNT=0
    for location in "$SCRIPTS_TARGET_WORKSPACE" "$SCRIPTS_TARGET_OPENCLAW"; do
        for script in "$location"/*.sh "$location"/*.py; do
            [ -f "$script" ] || continue
            chmod +x "$script"
            SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
        done
    done
    echo -e "  ${CHECK_MARK} Made $SCRIPT_COUNT scripts executable"

    # Check Python dependencies
    if ls "$SCRIPTS_TARGET_WORKSPACE"/*.py &>/dev/null; then
        MISSING_DEPS=()
        for dep in "psycopg2" "anthropic" "openai"; do
            python3 -c "import $dep" 2>/dev/null || MISSING_DEPS+=("$dep")
        done
        if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
            echo -e "  ${WARNING} Missing Python dependencies: ${MISSING_DEPS[*]}"
            echo "      Install: pip3 install ${MISSING_DEPS[*]}"
        else
            echo -e "  ${CHECK_MARK} Python dependencies verified"
        fi
    fi
else
    echo -e "  ${WARNING} Scripts directory not found at $SCRIPTS_SOURCE (skipping)"
fi

# --- Memory skills ---
echo ""
echo "Memory skills installation..."

MEM_SKILLS_SOURCE="$SCRIPT_DIR/memory/skills"
if [ -d "$MEM_SKILLS_SOURCE" ]; then
    install_skills "$MEM_SKILLS_SOURCE" "$HOME/.openclaw/skills" "memory skills"
else
    echo -e "  ${INFO} No memory skills directory found (skipping)"
fi

# --- OpenClaw config patching (enable-hooks) ---
echo ""
echo "OpenClaw config patching (memory hooks)..."

OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"
ENABLE_HOOKS_SCRIPT="$SCRIPTS_TARGET_OPENCLAW/enable-hooks.sh"

if ! command -v jq &>/dev/null; then
    echo -e "  ${WARNING} jq not installed — skipping config patching"
elif [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo -e "  ${WARNING} OpenClaw config not found at $OPENCLAW_CONFIG — skipping"
elif [ ! -f "$ENABLE_HOOKS_SCRIPT" ]; then
    echo -e "  ${WARNING} enable-hooks.sh not found — skipping"
else
    chmod +x "$ENABLE_HOOKS_SCRIPT"
    echo "  Enabling nova-memory hooks in OpenClaw config..."
    if "$ENABLE_HOOKS_SCRIPT" "$OPENCLAW_CONFIG" >/dev/null 2>&1; then
        echo -e "  ${CHECK_MARK} Hooks enabled in OpenClaw config"
        echo "      • memory-extract"
        echo "      • semantic-recall"
        echo "      • session-init"
        echo "      • agent-turn-context"
        GATEWAY_RESTART_NEEDED=1
    else
        echo -e "  ${WARNING} Failed to patch OpenClaw config"
        echo "      Run manually: $ENABLE_HOOKS_SCRIPT"
    fi
fi

# --- Python virtual environment ---
echo ""
echo "Python virtual environment setup..."

VENV_DIR="$HOME/.local/share/$USER/venv"
REQUIRED_PACKAGES=("openai" "tiktoken" "psycopg2-binary" "pillow")

declare -A PACKAGE_MODULE_MAP=(
    ["psycopg2-binary"]="psycopg2"
    ["pillow"]="PIL"
)

pkg_import_name() {
    local pkg="$1"
    if [[ -v PACKAGE_MODULE_MAP["$pkg"] ]]; then
        echo "${PACKAGE_MODULE_MAP[$pkg]}"
    else
        echo "${pkg//-/_}"
    fi
}

if python3 -m venv --help &>/dev/null; then
    echo -e "  ${CHECK_MARK} python3-venv available"
else
    echo -e "  ${CROSS_MARK} python3-venv module not found"
    echo "  Install: sudo apt install python3-venv"
    exit 1
fi

if [ -d "$VENV_DIR" ]; then
    echo -e "  ${CHECK_MARK} Virtual environment exists at $VENV_DIR"
else
    mkdir -p "$(dirname "$VENV_DIR")"
    if python3 -m venv "$VENV_DIR" &>/dev/null; then
        echo -e "  ${CHECK_MARK} Virtual environment created at $VENV_DIR"
    else
        echo -e "  ${CROSS_MARK} Failed to create virtual environment"
        exit 1
    fi
fi

VENV_PYTHON="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"

PACKAGES_TO_INSTALL=()
PACKAGES_INSTALLED=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    mod=$(pkg_import_name "$package")
    if "$VENV_PYTHON" -c "import $mod" &>/dev/null; then
        PACKAGES_INSTALLED+=("$package")
    else
        PACKAGES_TO_INSTALL+=("$package")
    fi
done

[ ${#PACKAGES_INSTALLED[@]} -gt 0 ] && echo -e "  ${CHECK_MARK} ${#PACKAGES_INSTALLED[@]} packages already installed: ${PACKAGES_INSTALLED[*]}"

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    echo "  Installing missing packages: ${PACKAGES_TO_INSTALL[*]}"
    if "$VENV_PIP" install "${PACKAGES_TO_INSTALL[@]}" &>/dev/null; then
        echo -e "  ${CHECK_MARK} ${#PACKAGES_TO_INSTALL[@]} packages installed"
    else
        echo -e "  ${WARNING} Some packages failed to install"
        echo "      Try manually: $VENV_PIP install ${PACKAGES_TO_INSTALL[*]}"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
else
    echo -e "  ${CHECK_MARK} All required packages already installed"
fi

# Verify
MISSING_PACKAGES=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    mod=$(pkg_import_name "$package")
    "$VENV_PYTHON" -c "import $mod" &>/dev/null || MISSING_PACKAGES+=("$package")
done
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo -e "  ${WARNING} Missing after install: ${MISSING_PACKAGES[*]}"
    VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + ${#MISSING_PACKAGES[@]}))
else
    echo -e "  ${CHECK_MARK} All Python dependencies verified"
fi

# ============================================
# SECTION 9: COGNITION install
# ============================================
echo ""
echo "════════════════════════════════"
echo "  [3/3] COGNITION"
echo "════════════════════════════════"

# --- Database setup for cognition (idempotent, may already exist) ---
echo ""
echo "Database check (cognition)..."

if psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' exists"
else
    echo "  Creating database '$DB_NAME'..."
    createdb -U "$DB_USER" "$DB_NAME" || { echo -e "  ${CROSS_MARK} Failed to create database"; exit 1; }
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' created"
fi

# --- agent_chat schema ---
echo ""
echo "Agent chat schema..."

COG_SCHEMA_FILE="$SCRIPT_DIR/cognition/focus/agent_chat/schema.sql"
if [ ! -f "$COG_SCHEMA_FILE" ]; then
    echo -e "  ${WARNING} cognition/focus/agent_chat/schema.sql not found (will be created by extension)"
else
    echo "  Applying agent_chat schema..."
    SCHEMA_ERR="${TMPDIR:-/tmp}/schema-apply-$$.err"
    if psql -U "$DB_USER" -d "$DB_NAME" -f "$COG_SCHEMA_FILE" >/dev/null 2>"$SCHEMA_ERR"; then
        echo -e "  ${CHECK_MARK} Schema applied"
        rm -f "$SCHEMA_ERR"
    else
        echo -e "  ${CROSS_MARK} Schema apply failed"
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
    psql -U "$DB_USER" -d "$DB_NAME" -c "ALTER TABLE agent_chat ENABLE ALWAYS TRIGGER trg_notify_agent_chat;" >/dev/null 2>&1 && \
        echo -e "  ${CHECK_MARK} Notification trigger configured (ALWAYS)" || \
        echo -e "  ${WARNING} Failed to configure notification trigger"
    psql -U "$DB_USER" -d "$DB_NAME" -c "ALTER TABLE agent_chat ENABLE REPLICA TRIGGER trg_embed_chat_message;" >/dev/null 2>&1 && \
        echo -e "  ${CHECK_MARK} Embedding trigger configured (REPLICA only)" || \
        echo -e "  ${WARNING} Failed to configure embedding trigger"
else
    echo "  No agent_chat subscriptions found — using default trigger configuration"
fi

# --- agent_chat extension ---
echo ""
echo "Agent Chat extension installation..."

EXTENSION_SOURCE="$SCRIPT_DIR/cognition/focus/agent_chat"
EXTENSION_TARGET="$EXTENSIONS_DIR/agent_chat"

mkdir -p "$EXTENSIONS_DIR"

if [ -d "$EXTENSION_SOURCE" ]; then
    echo "  Syncing agent_chat extension source files..."
    mkdir -p "$EXTENSION_TARGET"
    sync_directory "$EXTENSION_SOURCE" "$EXTENSION_TARGET" "extension files"

    # Fix main field in openclaw.plugin.json
    if [ -f "$EXTENSION_TARGET/openclaw.plugin.json" ]; then
        if ! grep -q '"main":' "$EXTENSION_TARGET/openclaw.plugin.json"; then
            sed -i '/"id":/a\  "main": "./dist/index.js",' "$EXTENSION_TARGET/openclaw.plugin.json"
        elif ! grep -q '"main": "./dist/index.js"' "$EXTENSION_TARGET/openclaw.plugin.json"; then
            sed -i 's|"main": "[^"]*"|"main": "./dist/index.js"|' "$EXTENSION_TARGET/openclaw.plugin.json"
        fi
    fi

    # Install pg to shared ~/.openclaw/node_modules/
    echo ""
    echo "  Installing pg to shared $OPENCLAW_DIR/node_modules/..."

    if [ -d "$EXTENSION_TARGET/node_modules/pg" ]; then
        echo -e "  ${INFO} Removing old per-extension node_modules/pg"
        rm -rf "$EXTENSION_TARGET/node_modules/pg"
    fi

    if [ -d "$OPENCLAW_DIR/node_modules/pg" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
        echo -e "  ${CHECK_MARK} pg already installed in shared node_modules"
    else
        NPM_INSTALL_LOG="${TMPDIR:-/tmp}/npm-install-pg-shared-$$.log"
        if (cd "$OPENCLAW_DIR" && npm install pg --save) >"$NPM_INSTALL_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} pg installed to shared $OPENCLAW_DIR/node_modules/"
            rm -f "$NPM_INSTALL_LOG"
        else
            echo -e "  ${CROSS_MARK} npm install pg failed"
            tail -20 "$NPM_INSTALL_LOG"
            exit 1
        fi
    fi

    # Build TypeScript
    echo ""
    echo "  Building agent_chat TypeScript..."
    cd "$EXTENSION_TARGET"

    if [ -d "dist" ] && [ -f "dist/index.js" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
        echo -e "  ${CHECK_MARK} Already built (use --force to rebuild)"
    else
        NPM_BUILD_LOG="${TMPDIR:-/tmp}/npm-build-agent-chat-$$.log"
        if npm run build >"$NPM_BUILD_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} Build completed"
            rm -f "$NPM_BUILD_LOG"
        else
            echo -e "  ${CROSS_MARK} Build failed"
            tail -20 "$NPM_BUILD_LOG"
            exit 1
        fi
    fi

    [ -f "dist/index.js" ] && echo -e "  ${CHECK_MARK} Build output verified: dist/index.js" || \
        { echo -e "  ${CROSS_MARK} Build output not found"; exit 1; }

    cd "$SCRIPT_DIR"
else
    echo -e "  ${WARNING} cognition/focus/agent_chat not found (skipping extension)"
fi

# --- Cognition skills ---
echo ""
echo "Cognition skills installation..."

COG_SKILLS_SOURCE="$SCRIPT_DIR/cognition/focus/skills"
if [ -d "$COG_SKILLS_SOURCE" ]; then
    SKILLS_DIR="$WORKSPACE/skills"
    mkdir -p "$SKILLS_DIR"
    install_skills "$COG_SKILLS_SOURCE" "$SKILLS_DIR" "cognition skills"
else
    echo -e "  ${INFO} No cognition skills directory found (skipping)"
fi

# --- Bootstrap context system ---
echo ""
echo "Bootstrap context system installation..."

BOOTSTRAP_SOURCE="$SCRIPT_DIR/cognition/focus/bootstrap-context"
BOOTSTRAP_TARGET="$OPENCLAW_DIR/hooks/db-bootstrap-context"

if [ -d "$BOOTSTRAP_SOURCE" ]; then
    echo "  Syncing bootstrap-context files..."
    sync_directory "$BOOTSTRAP_SOURCE" "$BOOTSTRAP_TARGET" "bootstrap-context files"

    # Install npm dependencies if package.json exists
    if [ -f "$BOOTSTRAP_TARGET/package.json" ]; then
        if [ ! -d "$BOOTSTRAP_TARGET/node_modules" ] || [ "$FORCE_INSTALL" -eq 1 ]; then
            echo "  Installing hook dependencies..."
            NPM_INSTALL_LOG="${TMPDIR:-/tmp}/npm-install-hook-$$.log"
            if (cd "$BOOTSTRAP_TARGET" && npm install) >"$NPM_INSTALL_LOG" 2>&1; then
                echo -e "  ${CHECK_MARK} Hook dependencies installed"
                rm -f "$NPM_INSTALL_LOG"
            else
                echo -e "  ${WARNING} npm install had issues (hook may use shared node_modules)"
                rm -f "$NPM_INSTALL_LOG"
            fi
        fi
    fi

    # Run the DB setup script
    if [ -f "$BOOTSTRAP_TARGET/install.sh" ]; then
        echo "  Running bootstrap-context DB setup..."
        cd "$BOOTSTRAP_TARGET"
        export DB_NAME="$DB_NAME"
        BOOTSTRAP_LOG="${TMPDIR:-/tmp}/bootstrap-install-$$.log"
        if bash install.sh >"$BOOTSTRAP_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} Bootstrap context DB setup complete"
            rm -f "$BOOTSTRAP_LOG"
        else
            echo -e "  ${WARNING} Bootstrap context DB setup had issues"
            tail -10 "$BOOTSTRAP_LOG"
        fi
        cd "$SCRIPT_DIR"
    fi
else
    echo -e "  ${WARNING} Bootstrap context source not found at $BOOTSTRAP_SOURCE (skipping)"
fi

# --- agent_config_sync extension ---
echo ""
echo "Agent config sync extension installation..."

AGENT_CONFIG_SYNC_SOURCE="$SCRIPT_DIR/cognition/focus/agent-config-sync"
AGENT_CONFIG_SYNC_TARGET="$EXTENSIONS_DIR/agent_config_sync"

if [ -d "$AGENT_CONFIG_SYNC_SOURCE" ]; then
    echo "  Syncing agent-config-sync extension files..."
    mkdir -p "$AGENT_CONFIG_SYNC_TARGET"
    sync_directory "$AGENT_CONFIG_SYNC_SOURCE" "$AGENT_CONFIG_SYNC_TARGET" "agent-config-sync files"

    echo "  Building agent_config_sync TypeScript..."
    cd "$AGENT_CONFIG_SYNC_TARGET"

    if [ ! -d "node_modules" ] || [ "$FORCE_INSTALL" -eq 1 ]; then
        NPM_INSTALL_LOG="${TMPDIR:-/tmp}/npm-install-config-sync-$$.log"
        if npm install >"$NPM_INSTALL_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} Dependencies installed"
            rm -f "$NPM_INSTALL_LOG"
        else
            echo -e "  ${WARNING} npm install had issues (may use shared node_modules)"
            rm -f "$NPM_INSTALL_LOG"
        fi
    fi

    NPM_BUILD_LOG="${TMPDIR:-/tmp}/npm-build-config-sync-$$.log"
    if npm run build >"$NPM_BUILD_LOG" 2>&1; then
        echo -e "  ${CHECK_MARK} agent_config_sync build completed"
        rm -f "$NPM_BUILD_LOG"
    else
        echo -e "  ${CROSS_MARK} agent_config_sync build failed"
        tail -20 "$NPM_BUILD_LOG"
    fi

    cd "$SCRIPT_DIR"

    # Remove legacy agent-config-db hook if present
    if [ -d "$OPENCLAW_DIR/hooks/agent-config-db" ]; then
        rm -rf "$OPENCLAW_DIR/hooks/agent-config-db"
        echo -e "  ${CHECK_MARK} Removed legacy agent-config-db hook"
    fi

    # Enable plugin in openclaw.json
    OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"
    if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
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
            "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
            mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
            echo -e "  ${CHECK_MARK} agent_config_sync plugin enabled" || \
            echo -e "  ${WARNING} Could not enable agent_config_sync plugin"

        # Remove agent-config-db hook config entry if present
        if jq -e '.hooks.internal.entries["agent-config-db"]' "$OPENCLAW_CONFIG" &>/dev/null; then
            jq 'del(.hooks.internal.entries["agent-config-db"])' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Removed agent-config-db hook from config" || \
                echo -e "  ${WARNING} Could not remove agent-config-db hook from config"
        fi

        # Set agents.list to { "$include": "./agents.json" }
        EXISTING_LIST_INCLUDE=$(jq -r '.agents.list["$include"] // empty' "$OPENCLAW_CONFIG" 2>/dev/null || true)
        if [ -n "$EXISTING_LIST_INCLUDE" ]; then
            echo -e "  ${CHECK_MARK} agents.list already uses \$include: $EXISTING_LIST_INCLUDE"
        else
            jq '.agents.list = { "$include": "./agents.json" }' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set agents.list = { \"\$include\": \"./agents.json\" }" || \
                echo -e "  ${WARNING} Could not set agents.list \$include directive"
        fi

        # Ensure gateway.reload.mode is not "off"
        EXISTING_MODE=$(jq -r '.gateway.reload.mode // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_MODE" ] || [ "$EXISTING_MODE" = "off" ]; then
            jq '.gateway.reload.mode = "hot"' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set gateway.reload.mode = \"hot\"" || \
                echo -e "  ${WARNING} Could not set gateway.reload.mode"
        else
            echo -e "  ${CHECK_MARK} gateway.reload.mode = \"$EXISTING_MODE\""
        fi

        # Set maxSpawnDepth if missing
        EXISTING_DEPTH=$(jq -r '.agents.defaults.subagents.maxSpawnDepth // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_DEPTH" ]; then
            jq '.agents.defaults.subagents.maxSpawnDepth = 5' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set maxSpawnDepth = 5" || \
                echo -e "  ${WARNING} Could not set maxSpawnDepth"
        else
            echo -e "  ${CHECK_MARK} maxSpawnDepth already set to $EXISTING_DEPTH"
        fi
    fi

    # Generate initial agents.json from DB
    echo "  Generating initial agents.json from database..."
    AGENTS_JSON="$OPENCLAW_DIR/agents.json"
    AGENTS_JSON_TMP="${AGENTS_JSON}.tmp.$$"

    INITIAL_SYNC_QUERY="
        SELECT COALESCE(
            json_agg(entry ORDER BY (entry->>'id'))::text,
            '[]'
        )
        FROM (
            SELECT
                CASE
                    WHEN fallback_models IS NOT NULL AND array_length(fallback_models, 1) > 0 THEN
                        jsonb_strip_nulls(jsonb_build_object('id', name)
                        || CASE WHEN is_default = true THEN jsonb_build_object('default', true) ELSE '{}'::jsonb END
                        || jsonb_build_object('model', jsonb_build_object('primary', model, 'fallbacks', to_jsonb(fallback_models)))
                        || CASE WHEN allowed_subagents IS NOT NULL AND array_length(allowed_subagents, 1) > 0
                            THEN jsonb_build_object('subagents', jsonb_build_object('allowAgents',
                                (SELECT jsonb_agg(s ORDER BY s) FROM unnest(allowed_subagents) s)))
                            ELSE '{}'::jsonb END)
                    ELSE
                        jsonb_strip_nulls(jsonb_build_object('id', name)
                        || CASE WHEN is_default = true THEN jsonb_build_object('default', true) ELSE '{}'::jsonb END
                        || jsonb_build_object('model', model)
                        || CASE WHEN allowed_subagents IS NOT NULL AND array_length(allowed_subagents, 1) > 0
                            THEN jsonb_build_object('subagents', jsonb_build_object('allowAgents',
                                (SELECT jsonb_agg(s ORDER BY s) FROM unnest(allowed_subagents) s)))
                            ELSE '{}'::jsonb END)
                END AS entry
            FROM agents
            WHERE instance_type != 'peer' AND model IS NOT NULL
        ) sub
    "

    if AGENTS_DATA=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "$INITIAL_SYNC_QUERY" 2>/dev/null); then
        if [ -n "$AGENTS_DATA" ] && [ "$AGENTS_DATA" != "null" ]; then
            echo "$AGENTS_DATA" | jq '.' >"$AGENTS_JSON_TMP" 2>/dev/null && \
                mv "$AGENTS_JSON_TMP" "$AGENTS_JSON" && \
                echo -e "  ${CHECK_MARK} Generated initial agents.json from DB" || \
                { echo -e "  ${WARNING} Could not write agents.json"; rm -f "$AGENTS_JSON_TMP"; }
        else
            echo '[]' >"$AGENTS_JSON_TMP" && mv "$AGENTS_JSON_TMP" "$AGENTS_JSON" && \
                echo -e "  ${CHECK_MARK} Generated empty agents.json (no agents in DB)" || \
                { echo -e "  ${WARNING} Could not write agents.json"; rm -f "$AGENTS_JSON_TMP"; }
        fi
    else
        echo -e "  ${WARNING} Could not query DB for agents.json (will be generated on gateway start)"
        echo '[]' >"$AGENTS_JSON" 2>/dev/null || true
    fi
else
    echo -e "  ${WARNING} cognition/focus/agent-config-sync not found (skipping)"
fi

# --- Ensure agent_system_config table ---
echo ""
echo "  Ensuring agent_system_config table..."

psql -U "$DB_USER" -d "$DB_NAME" -q <<'SYSTEM_CONFIG_TABLE_SQL'
CREATE TABLE IF NOT EXISTS agent_system_config (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    value_type TEXT NOT NULL DEFAULT 'text',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SYSTEM_CONFIG_TABLE_SQL

[ $? -eq 0 ] && echo -e "  ${CHECK_MARK} agent_system_config table ready" || \
    echo -e "  ${WARNING} Could not ensure agent_system_config table"

# --- System config notification trigger ---
echo "  Installing system config notification trigger..."

SYSTEM_CONFIG_MIGRATION="$SCRIPT_DIR/cognition/scripts/migrations/163-system-config-trigger.sql"
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
    psql -U "$DB_USER" -d "$DB_NAME" -q <<'INLINE_MIGRATION_SQL'
CREATE OR REPLACE FUNCTION notify_system_config_changed()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM pg_notify('agent_config_changed', json_build_object(
            'source', 'agent_system_config', 'key', OLD.key, 'operation', TG_OP)::text);
        RETURN OLD;
    END IF;
    PERFORM pg_notify('agent_config_changed', json_build_object(
        'source', 'agent_system_config', 'key', NEW.key, 'operation', TG_OP)::text);
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
    [ $? -eq 0 ] && echo -e "  ${CHECK_MARK} System config trigger installed (inline)" || \
        echo -e "  ${WARNING} Inline migration had issues"
fi

# --- agent config notification trigger ---
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

DROP TRIGGER IF EXISTS agent_config_changed ON agents;
CREATE TRIGGER agent_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agents
    FOR EACH ROW EXECUTE FUNCTION notify_agent_config_changed();
TRIGGER_SQL

[ $? -eq 0 ] && echo -e "  ${CHECK_MARK} Agent config notification trigger installed" || \
    echo -e "  ${CROSS_MARK} Failed to install agent config notification trigger"

# --- Shell environment setup (cognition dotfiles) ---
echo ""
echo "Shell environment setup..."

NOVA_DIR="$HOME/.local/share/nova"
SHELL_ALIASES_SOURCE="$SCRIPT_DIR/cognition/dotfiles/shell-aliases.sh"
SHELL_ALIASES_TARGET="$NOVA_DIR/shell-aliases.sh"
BASH_ENV_FILE="$HOME/.bash_env"
BASH_ENV_SOURCE="$SCRIPT_DIR/cognition/dotfiles/bash_env"
OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"

mkdir -p "$NOVA_DIR"

if [ -f "$SHELL_ALIASES_SOURCE" ]; then
    if [ -f "$SHELL_ALIASES_TARGET" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
        echo -e "  ${CHECK_MARK} shell-aliases.sh already installed (use --force to reinstall)"
    else
        cp "$SHELL_ALIASES_SOURCE" "$SHELL_ALIASES_TARGET"
        chmod +x "$SHELL_ALIASES_TARGET"
        echo -e "  ${CHECK_MARK} Installed shell-aliases.sh → $SHELL_ALIASES_TARGET"
    fi
else
    echo -e "  ${WARNING} shell-aliases.sh source not found: $SHELL_ALIASES_SOURCE (skipping)"
fi

if [ -f "$BASH_ENV_SOURCE" ]; then
    if [ -f "$BASH_ENV_FILE" ] && grep -qF '~/.local/share/nova/shell-aliases.sh' "$BASH_ENV_FILE"; then
        echo -e "  ${CHECK_MARK} ~/.bash_env already sources shell-aliases.sh"
    else
        if [ ! -f "$BASH_ENV_FILE" ]; then
            cp "$BASH_ENV_SOURCE" "$BASH_ENV_FILE"
            echo -e "  ${CHECK_MARK} Created ~/.bash_env"
        else
            echo "" >>"$BASH_ENV_FILE"
            cat "$BASH_ENV_SOURCE" >>"$BASH_ENV_FILE"
            echo -e "  ${CHECK_MARK} Updated ~/.bash_env (additively)"
        fi
    fi
else
    echo -e "  ${WARNING} bash_env source not found: $BASH_ENV_SOURCE (skipping)"
fi

if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
    if grep -q 'BASH_ENV' "$OPENCLAW_CONFIG"; then
        echo -e "  ${CHECK_MARK} OpenClaw config already has BASH_ENV set"
    else
        jq --arg bashenv "$BASH_ENV_FILE" '.env.vars.BASH_ENV = $bashenv' \
            "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
            mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
            echo -e "  ${CHECK_MARK} Added BASH_ENV to OpenClaw config" || \
            echo -e "  ${WARNING} Could not update config with BASH_ENV"
    fi
fi

# --- Configure agent_chat channel ---
echo ""
echo "Configuring agent_chat channel..."

OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"
if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
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
        "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
        mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
        echo -e "  ${CHECK_MARK} Configured channels.agent_chat" || \
        echo -e "  ${WARNING} Could not configure agent_chat channel"

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
        "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
        mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
        echo -e "  ${CHECK_MARK} Configured plugins.entries.agent_chat" || \
        echo -e "  ${WARNING} Could not configure agent_chat plugin"
else
    echo -e "  ${WARNING} Cannot configure agent_chat (missing config or jq)"
fi

# --- Generate hooks.token if hooks enabled ---
OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"
if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
    HOOKS_ENABLED=$(jq -r '.hooks.enabled // false' "$OPENCLAW_CONFIG" 2>/dev/null)
    if [ "$HOOKS_ENABLED" = "true" ]; then
        EXISTING_TOKEN=$(jq -r '.hooks.token // empty' "$OPENCLAW_CONFIG")
        if [ -z "$EXISTING_TOKEN" ]; then
            HOOKS_TOKEN=$(openssl rand -hex 32)
            jq --arg token "$HOOKS_TOKEN" '.hooks.token = $token' \
                "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Generated hooks.token" || \
                echo -e "  ${WARNING} Could not set hooks.token"
        else
            echo -e "  ${CHECK_MARK} hooks.token already exists (preserved)"
        fi
    fi
fi

# ============================================
# SECTION 10: Verification
# ============================================
echo ""
echo "════════════════════════════════"
echo "  Final Verification"
echo "════════════════════════════════"

verify_schema
verify_relationships
verify_cognition
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
echo "  [relationships]"
echo "    • entity-resolver library"
if [ -d "$REL_SKILLS_SOURCE" ] 2>/dev/null; then
    echo "    • relationship skills"
fi
echo "  [memory]"
echo "    • Shared PG loader libraries → ~/.openclaw/lib/"
echo "    • Schema managed via pgschema (memory/schema/schema.sql)"
if [ ${#INSTALLED_HOOKS[@]} -gt 0 ]; then
    for hook in "${INSTALLED_HOOKS[@]}"; do
        echo "    • Hook: $hook"
    done
fi
echo "    • Scripts → $SCRIPTS_TARGET_OPENCLAW"
echo "    • Python venv → $VENV_DIR"
echo "  [cognition]"
echo "    • agent_chat extension → $EXTENSIONS_DIR/agent_chat"
echo "    • agent_config_sync extension → $EXTENSIONS_DIR/agent_config_sync"
echo "    • Bootstrap context → $OPENCLAW_DIR/hooks/db-bootstrap-context"
echo "    • agents.json → $OPENCLAW_DIR/agents.json"
echo "    • shell-aliases.sh → $NOVA_DIR/shell-aliases.sh"
echo ""

echo "Next steps:"
echo ""
echo "1. Restart OpenClaw gateway to apply all changes:"
echo "   openclaw gateway restart"
echo ""
echo "2. Verify installation:"
echo "   $0 --verify-only"
echo ""
echo "3. Check logs:"
echo "   tail -f ~/.openclaw/logs/memory-extract-hook.log"
echo ""

if [ $VERIFICATION_WARNINGS -gt 0 ]; then
    echo "⚠️  Warnings detected — review output above."
    echo ""
fi

# ============================================
# Gateway restart (if systemd service is running)
# ============================================
if systemctl --user is-active openclaw-gateway &>/dev/null; then
    if [ "$NO_RESTART" = "1" ]; then
        echo ""
        echo "⚠️  Gateway is running. Restart required for changes to take effect:"
        echo "   systemctl --user restart openclaw-gateway"
    else
        echo ""
        echo "Restarting gateway to apply changes..."
        if systemctl --user restart openclaw-gateway; then
            echo -e "  ${CHECK_MARK} Gateway restarted"
        else
            echo -e "  ${CROSS_MARK} Gateway restart failed. Restart manually:"
            echo "   systemctl --user restart openclaw-gateway"
        fi
    fi
fi
