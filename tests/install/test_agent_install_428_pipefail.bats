#!/usr/bin/env bats
# BATS tests for nova-mind#428:
# agent-install.sh's schema verification used psql -lqt | cut | grep -qw,
# which fails under set -o pipefail once the database list exceeds the pipe
# buffer (grep -q exits early, psql gets SIGPIPE 141). The fix uses a
# single-row query instead.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

setup() {
    FAKE_HOME="$(mktemp -d)"
    FAKE_REPO="$(mktemp -d)"

    # Copy the installer so we can extract verify_schema for isolated testing.
    cp "$REPO_ROOT/agent-install.sh" "$FAKE_REPO/agent-install.sh"

    # Provide a tiny schema.sql so verify_schema exercises the table loop.
    mkdir -p "$FAKE_REPO/database"
    printf '%s\n' 'CREATE TABLE IF NOT EXISTS public.agents (id serial PRIMARY KEY);' >"$FAKE_REPO/database/schema.sql"

    export HOME="$FAKE_HOME"
    export PGDATABASE="test_memory"
}

teardown() {
    rm -rf "$FAKE_HOME" "$FAKE_REPO"
}

# Build a stub psql that:
#   * answers the single-row database-existence query with "1",
#   * answers information_schema table-existence queries with "1",
#   * and, for any invocation using -lqt, emits more than 64 KiB of database
#     names (simulating the large catalog that triggers SIGPIPE under pipefail).
_install_stub_psql() {
    local stub_dir
    stub_dir="$(mktemp -d)"
    mkdir -p "$stub_dir/bin"

    cat >"$stub_dir/bin/psql" <<'EOF'
#!/usr/bin/env bash
# If called with the old large-list pattern, emit >64 KiB of database names.
for arg in "$@"; do
    if [ "$arg" = "-lqt" ]; then
        # Emit the target DB early, then enough trailing rows to exceed the
        # 64 KiB pipe buffer. When grep -q matches test_memory and exits,
        # psql still has rows to write and gets SIGPIPE under pipefail.
        printf '  test_memory                   | postgres | UTF8     | en_US.utf8 | en_US.utf8 | \n'
        for i in $(seq 1 2000); do
            printf '  db_%08d                       | postgres | UTF8     | en_US.utf8 | en_US.utf8 | \n' "$i"
        done
        exit 0
    fi
done

# Database existence check used by the fixed verify_schema.
if [[ "$*" == *"SELECT 1 FROM pg_database WHERE datname"* ]]; then
    printf '1\n'
    exit 0
fi

# Table existence check used by verify_schema.
if [[ "$*" == *"SELECT COUNT(*) FROM information_schema.tables"* ]]; then
    printf '1\n'
    exit 0
fi

printf '1\n'
exit 0
EOF
    chmod +x "$stub_dir/bin/psql"

    # Prepend stub directory to PATH.
    export PATH="$stub_dir/bin:$PATH"
    printf '%s\n' "$stub_dir"
}

# Source only the verify_schema function plus the minimal globals it needs.
_source_verify_schema() {
    local script="$FAKE_REPO/agent-install.sh"

    # Minimal dependency surface for verify_schema.
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
    CHECK_MARK="${GREEN}✅${NC}"
    CROSS_MARK="${RED}❌${NC}"
    WARNING="${YELLOW}⚠️${NC}"
    VERIFICATION_ERRORS=0
    VERIFICATION_WARNINGS=0
    DB_USER="${PGUSER:-$(whoami)}"
    DB_NAME="${PGDATABASE:-${DB_USER//-/_}_memory}"
    SCRIPT_DIR="$FAKE_REPO"

    # Extract verify_schema from the installer and evaluate it with the same
    # shell options as agent-install.sh so pipefail failures propagate.
    local func
    func=$(awk '/^verify_schema\(\) \{/,/^\}$/' "$script")
    if [ -z "$func" ]; then
        echo "verify_schema not found in installer" >&2
        return 1
    fi
    set -euo pipefail
    eval "$func"
}

@test "TC-428-001: verify_schema passes when psql emits more than 64 KiB" {
    _install_stub_psql >/dev/null
    _source_verify_schema

    run verify_schema

    [ "$status" -eq 0 ]
    [[ "$output" != *"does not exist"* ]]
    [[ "$output" == *"All schema tables present"* ]]
}

@test "TC-428-002: old psql -lqt pipeline would have seen the target database" {
    _install_stub_psql >/dev/null

    run psql -U testuser -lqt
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_memory"* ]]
}

@test "TC-428-003: old psql -lqt pipeline emits more than 64 KiB" {
    _install_stub_psql >/dev/null

    run psql -U testuser -lqt
    [ "$status" -eq 0 ]
    [ "${#output}" -gt 65536 ]
}
