#!/usr/bin/env bats
# Bootstrap behavior tests for agent-install.sh (#756).
# These tests run the installer with mocked psql/createdb in PATH.

setup() {
    TEST_TMP="$(mktemp -d)"
    export PATH="$TEST_TMP:$PATH"

    # Minimal postgres.json so the installer picks up DB_USER/PGPASSWORD
    export HOME="$TEST_TMP"
    mkdir -p "$HOME/.openclaw"
    cat > "$HOME/.openclaw/postgres.json" <<'EOF'
{
  "host": "/var/run/postgresql",
  "port": "5432",
  "database": "nova_memory",
  "user": "nova",
  "password": "nova-secret"
}
EOF

    export PSQL_STATE="$TEST_TMP/psql_state"
    export PSQL_LOG="$TEST_TMP/psql.log"
    touch "$PSQL_LOG"

    # Mock psql: records invocations, tracks bootstrap state, and returns
    # canned responses so --verify-only can complete successfully.
    cat > "$TEST_TMP/psql" <<'EOF'
#!/usr/bin/env bash
# psql mock for bootstrap tests
echo "$@" >> "$PSQL_LOG"

# Initialize state files
[ -f "$PSQL_STATE/role_exists" ] || echo "${ROLE_EXISTS:-0}" > "$PSQL_STATE/role_exists"
[ -f "$PSQL_STATE/db_exists" ] || echo "${DB_EXISTS:-0}" > "$PSQL_STATE/db_exists"
[ -f "$PSQL_STATE/connect_ok" ] || echo "${CONNECT_OK:-1}" > "$PSQL_STATE/connect_ok"

_role_exists=$(cat "$PSQL_STATE/role_exists")
_db_exists=$(cat "$PSQL_STATE/db_exists")
_connect_ok=$(cat "$PSQL_STATE/connect_ok")

# Role existence check
if [[ "$*" == *"SELECT 1 FROM pg_roles WHERE rolname = "* ]]; then
    [ "$_role_exists" -eq 1 ] && echo 1
    exit 0
fi

# Database existence check
if [[ "$*" == *"SELECT 1 FROM pg_database WHERE datname = "* ]]; then
    [ "$_db_exists" -eq 1 ] && echo 1
    exit 0
fi

# Credential check / generic SELECT 1
if [[ "$*" == *"SELECT 1"* ]]; then
    [ "$_connect_ok" -eq 1 ] && echo 1
    exit $((1 - _connect_ok))
fi

# Bootstrap mutations update state
if [[ "$*" == *"CREATE ROLE"* ]]; then
    [ "${BOOTSTRAP_MUTATIONS_OK:-1}" -eq 1 ] || exit 1
    echo 1 > "$PSQL_STATE/role_exists"
    exit 0
fi

if [[ "$*" == *"CREATE DATABASE"* ]]; then
    [ "${BOOTSTRAP_MUTATIONS_OK:-1}" -eq 1 ] || exit 1
    echo 1 > "$PSQL_STATE/db_exists"
    exit 0
fi

if [[ "$*" == *"CREATE EXTENSION"* ]]; then
    [ "${BOOTSTRAP_MUTATIONS_OK:-1}" -eq 1 ] || exit 1
    exit 0
fi

# Schema verification queries used by --verify-only
if [[ "$*" == *"SELECT current_database()"* ]]; then
    echo "nova_memory"
    exit 0
fi

if [[ "$*" == *"SELECT COUNT(*) FROM information_schema.tables"* ]]; then
    echo "42"
    exit 0
fi

if [[ "$*" == *" -lqt"* ]]; then
    if [ "$_db_exists" -eq 1 ]; then
        echo " nova_memory  | postgres | UTF8     | en_US.utf8 | en_US.utf8 |"
    fi
    exit 0
fi

exit 0
EOF
    chmod +x "$TEST_TMP/psql"
    mkdir -p "$PSQL_STATE"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "bootstrap creates role, database and extensions with superuser credentials" {
    ROLE_EXISTS=0
    DB_EXISTS=0
    PG_SUPERUSER=postgres
    PG_SUPERUSER_PASSWORD=super-secret
    export ROLE_EXISTS DB_EXISTS PG_SUPERUSER PG_SUPERUSER_PASSWORD

    run bash "$BATS_TEST_DIRNAME/../agent-install.sh" --verify-only

    # Bootstrap output is present even though --verify-only later reports
    # missing plugins/crons.
    grep -q "Bootstrapping agent role and database as 'postgres'" <<< "$output"
    grep -q "Created agent role 'nova'" <<< "$output"
    grep -q "Created database 'nova_memory'" <<< "$output"
    grep -q "Extension 'vector' installed" <<< "$output"

    # Mutations ran as the superuser role.
    grep -qF -- "-U postgres" "$PSQL_LOG"
    grep -qF -- "CREATE ROLE nova LOGIN PASSWORD" "$PSQL_LOG"
    grep -qF -- "CREATE DATABASE nova_memory OWNER nova" "$PSQL_LOG"
    grep -qF -- "CREATE EXTENSION IF NOT EXISTS" "$PSQL_LOG"
}

@test "missing role and database without superuser credentials prints manual instructions and exits 1" {
    ROLE_EXISTS=0
    DB_EXISTS=0
    CONNECT_OK=0
    export ROLE_EXISTS DB_EXISTS CONNECT_OK

    run bash "$BATS_TEST_DIRNAME/../agent-install.sh" --verify-only

    [ "$status" -eq 1 ]
    grep -q "Agent role 'nova' or database 'nova_memory' does not exist" <<< "$output"
    grep -q "CREATE ROLE nova LOGIN PASSWORD" <<< "$output"
    grep -q "CREATE DATABASE nova_memory OWNER nova" <<< "$output"
    grep -q "CREATE EXTENSION IF NOT EXISTS vector" <<< "$output"
}

@test "upgrade with superuser credentials present still runs pre-checks as DB_USER" {
    ROLE_EXISTS=1
    DB_EXISTS=1
    PG_SUPERUSER=postgres
    PG_SUPERUSER_PASSWORD=super-secret
    export ROLE_EXISTS DB_EXISTS PG_SUPERUSER PG_SUPERUSER_PASSWORD

    run bash "$BATS_TEST_DIRNAME/../agent-install.sh" --verify-only

    # No bootstrap happened; precheck passed silently.
    ! grep -qF -- "Bootstrapping agent role" <<< "$output"
    ! grep -qF -- "CREATE ROLE" "$PSQL_LOG"
    ! grep -qF -- "CREATE DATABASE" "$PSQL_LOG"

    # The bootstrap precheck ran as the agent role, not the superuser.
    grep -qF -- "-U nova -d postgres -tAc SELECT 1 FROM pg_roles" "$PSQL_LOG"
    grep -qF -- "-U nova -d postgres -tAc SELECT 1 FROM pg_database" "$PSQL_LOG"
}
