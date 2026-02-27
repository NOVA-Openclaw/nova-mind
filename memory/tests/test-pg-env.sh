#!/bin/bash
# Test suite for lib/pg-env.sh
# Tests: happy path, ENV precedence, missing file, malformed JSON, null values, empty strings
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

source "$LIB_DIR/pg-env.sh"

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected='$expected', got='$actual')"
        FAIL=$((FAIL + 1))
    fi
}

assert_unset() {
    local desc="$1" var="$2"
    if [ -z "${!var+x}" ]; then
        echo "  PASS: $desc ($var is unset)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc ($var should be unset, got='${!var}')"
        FAIL=$((FAIL + 1))
    fi
}

clear_pg_vars() {
    unset PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD 2>/dev/null || true
}

# Override HOME for isolation
REAL_HOME="$HOME"

# ============================================
echo "TC-1.1: Config file with all fields, no ENV"
clear_pg_vars
HOME="$TMPDIR/tc1"
mkdir -p "$HOME/.openclaw"
cat > "$HOME/.openclaw/postgres.json" <<'EOF'
{"host":"dbhost","port":5433,"database":"testdb","user":"testuser","password":"secret123"}
EOF
load_pg_env
assert_eq "PGHOST" "dbhost" "$PGHOST"
assert_eq "PGPORT" "5433" "$PGPORT"
assert_eq "PGDATABASE" "testdb" "$PGDATABASE"
assert_eq "PGUSER" "testuser" "$PGUSER"
assert_eq "PGPASSWORD" "secret123" "$PGPASSWORD"

# ============================================
echo "TC-1.2: All ENV vars set, config exists with different values"
clear_pg_vars
HOME="$TMPDIR/tc1"  # reuse config
export PGHOST=envhost PGPORT=9999 PGDATABASE=envdb PGUSER=envuser PGPASSWORD=envpass
load_pg_env
assert_eq "PGHOST" "envhost" "$PGHOST"
assert_eq "PGPORT" "9999" "$PGPORT"
assert_eq "PGDATABASE" "envdb" "$PGDATABASE"
assert_eq "PGUSER" "envuser" "$PGUSER"
assert_eq "PGPASSWORD" "envpass" "$PGPASSWORD"

# ============================================
echo "TC-1.3: All ENV vars set, no config file"
clear_pg_vars
HOME="$TMPDIR/tc1_3_empty"
mkdir -p "$HOME"
export PGHOST=envhost PGPORT=9999 PGDATABASE=envdb PGUSER=envuser PGPASSWORD=envpass
load_pg_env
assert_eq "PGHOST" "envhost" "$PGHOST"
assert_eq "PGPORT" "9999" "$PGPORT"

# ============================================
echo "TC-1.4: Mixed — some ENV, rest from config"
clear_pg_vars
HOME="$TMPDIR/tc1"
export PGHOST=remotehost PGPORT=9999
load_pg_env
assert_eq "PGHOST" "remotehost" "$PGHOST"
assert_eq "PGPORT" "9999" "$PGPORT"
assert_eq "PGDATABASE" "testdb" "$PGDATABASE"
assert_eq "PGUSER" "testuser" "$PGUSER"
assert_eq "PGPASSWORD" "secret123" "$PGPASSWORD"

# ============================================
echo "TC-2.1: No ENV, no config file — defaults"
clear_pg_vars
HOME="$TMPDIR/tc2_1_empty"
mkdir -p "$HOME"
load_pg_env
assert_eq "PGHOST" "localhost" "$PGHOST"
assert_eq "PGPORT" "5432" "$PGPORT"
assert_eq "PGUSER" "$(whoami)" "$PGUSER"
assert_unset "PGDATABASE unset" "PGDATABASE"
assert_unset "PGPASSWORD unset" "PGPASSWORD"

# ============================================
echo "TC-2.2: Config with only some fields"
clear_pg_vars
HOME="$TMPDIR/tc2_2"
mkdir -p "$HOME/.openclaw"
echo '{"host":"dbserver","port":5433}' > "$HOME/.openclaw/postgres.json"
load_pg_env
assert_eq "PGHOST" "dbserver" "$PGHOST"
assert_eq "PGPORT" "5433" "$PGPORT"
assert_eq "PGUSER" "$(whoami)" "$PGUSER"
assert_unset "PGDATABASE unset" "PGDATABASE"

# ============================================
echo "TC-2.3: Config with empty string values"
clear_pg_vars
HOME="$TMPDIR/tc2_3"
mkdir -p "$HOME/.openclaw"
echo '{"host":"","port":5432,"user":""}' > "$HOME/.openclaw/postgres.json"
load_pg_env
assert_eq "PGHOST defaults" "localhost" "$PGHOST"
assert_eq "PGUSER defaults" "$(whoami)" "$PGUSER"

# ============================================
echo "TC-3.1: Extra unknown fields"
clear_pg_vars
HOME="$TMPDIR/tc3_1"
mkdir -p "$HOME/.openclaw"
echo '{"host":"db","port":5432,"sslmode":"require","extra":true}' > "$HOME/.openclaw/postgres.json"
load_pg_env
assert_eq "PGHOST" "db" "$PGHOST"

# ============================================
echo "TC-3.2: Port as string"
clear_pg_vars
HOME="$TMPDIR/tc3_2"
mkdir -p "$HOME/.openclaw"
echo '{"port":"5433"}' > "$HOME/.openclaw/postgres.json"
load_pg_env
assert_eq "PGPORT string" "5433" "$PGPORT"

# ============================================
echo "TC-3.4: Null values in JSON"
clear_pg_vars
HOME="$TMPDIR/tc3_4"
mkdir -p "$HOME/.openclaw"
echo '{"host":null,"port":5432}' > "$HOME/.openclaw/postgres.json"
load_pg_env
assert_eq "PGHOST null->default" "localhost" "$PGHOST"
assert_eq "PGPORT" "5432" "$PGPORT"

# ============================================
echo "TC-3.5: ENV set to empty string"
clear_pg_vars
HOME="$TMPDIR/tc1"  # has host=dbhost
export PGHOST=""
load_pg_env
assert_eq "PGHOST empty env->config" "dbhost" "$PGHOST"

# ============================================
echo "TC-4.1: Malformed JSON"
clear_pg_vars
HOME="$TMPDIR/tc4_1"
mkdir -p "$HOME/.openclaw"
echo '{invalid json' > "$HOME/.openclaw/postgres.json"
load_pg_env 2>/dev/null
assert_eq "PGHOST malformed->default" "localhost" "$PGHOST"
assert_eq "PGPORT malformed->default" "5432" "$PGPORT"

# ============================================
echo "TC-4.4: No .openclaw directory"
clear_pg_vars
HOME="$TMPDIR/tc4_4_nope"
mkdir -p "$HOME"
load_pg_env
assert_eq "PGHOST no dir->default" "localhost" "$PGHOST"

# Restore HOME
HOME="$REAL_HOME"

echo ""
echo "═══════════════════════════════════════════"
echo "  Bash tests: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════"
[ $FAIL -eq 0 ] && exit 0 || exit 1
