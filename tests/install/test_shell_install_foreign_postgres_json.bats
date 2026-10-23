#!/usr/bin/env bats
# Tests for nova-mind#778: shell-install must reject a postgres.json that belongs
# to another peer (wrong database/user), or an inherited PGDATABASE that names
# another agent's DB.
#
# Run: bats tests/install/test_shell_install_foreign_postgres_json.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SHELL_INSTALL="$REPO_ROOT/shell-install.sh"

@test "TC-778-foreign-db: complete postgres.json for another peer is rejected" {
    if ! command -v jq &>/dev/null; then skip "jq not installed"; fi

    local tmp_home
    tmp_home=$(mktemp -d)
    mkdir -p "$tmp_home/.openclaw"
    chmod 700 "$tmp_home/.openclaw"

    local expected_user expected_db foreign_db
    expected_user=$(whoami)
    expected_db="${expected_user//-/_}_memory"
    foreign_db="foreign_${expected_db}"

    # Keep user correct so the check reaches the database mismatch first.
    cat > "$tmp_home/.openclaw/postgres.json" <<EOF
{
  "host": "localhost",
  "port": 5432,
  "database": "$foreign_db",
  "user": "$expected_user",
  "password": "secret"
}
EOF
    chmod 600 "$tmp_home/.openclaw/postgres.json"

    run env HOME="$tmp_home" "$SHELL_INSTALL" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"points to database '$foreign_db'"* ]]
    [[ "$output" == *"agent database for '$expected_user' is '$expected_db'"* ]]
    [[ "$output" == *"Update $tmp_home/.openclaw/postgres.json"* ]]

    rm -rf "$tmp_home"
}

@test "TC-778-foreign-user: postgres.json with wrong user is rejected" {
    if ! command -v jq &>/dev/null; then skip "jq not installed"; fi

    local tmp_home
    tmp_home=$(mktemp -d)
    mkdir -p "$tmp_home/.openclaw"
    chmod 700 "$tmp_home/.openclaw"

    local expected_user expected_db foreign_user
    expected_user=$(whoami)
    expected_db="${expected_user//-/_}_memory"
    foreign_user="foreign_${expected_user}"

    cat > "$tmp_home/.openclaw/postgres.json" <<EOF
{
  "host": "localhost",
  "port": 5432,
  "database": "$expected_db",
  "user": "$foreign_user",
  "password": "secret"
}
EOF
    chmod 600 "$tmp_home/.openclaw/postgres.json"

    run env HOME="$tmp_home" "$SHELL_INSTALL" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"belongs to user '$foreign_user'"* ]]
    [[ "$output" == *"user must be '$expected_user'"* ]]

    rm -rf "$tmp_home"
}

@test "TC-778-shellcheck: bats test file passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ]
}
