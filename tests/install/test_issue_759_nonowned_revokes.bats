#!/usr/bin/env bats
# Tests for nova-mind#759: stale owner-ACL REVOKEs must not strip named
# grantees after ownership moves, and the all-grantee gate must catch any
# base-DML privilege loss.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FILTER="$REPO_ROOT/database/filter_shadowed_grants.py"
GATE="$REPO_ROOT/database/grant_reconcile_gate.py"

@test "TC-759a: stale REVOKE from former owner on DB_USER-owned table is skipped" {
    # agents is owned by nova; a REVOKE FROM newhart is owner-ACL residue
    # left over from before the table moved to nova.
    run python3 "$FILTER" --dbname nova_memory --db-user nova <<'SQL'
REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM newhart;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED: 1 additive base-DML REVOKE statement(s)"* ]]
    [[ "$output" != *"REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM newhart"* ]]
}

@test "TC-759b: FROM PUBLIC base-DML REVOKE is still applied" {
    # PUBLIC is not a named grantee; additive policy does not protect it.
    run python3 "$FILTER" --dbname nova_memory --db-user nova <<'SQL'
REVOKE ALL PRIVILEGES ON TABLE agents FROM PUBLIC;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kept 1 grant/revoke statement(s)"* ]]
    [[ "$output" == *"REVOKE ALL PRIVILEGES ON TABLE agents FROM PUBLIC"* ]]
}

@test "TC-759d: all-grantee gate fails when a grantee lost base-DML" {
    TMPDIR_RUN=$(mktemp -d)
    # Claim newhart has INSERT on agents, which it does not currently hold.
    cat >"$TMPDIR_RUN/fake-all-snapshot.json" <<'JSON'
{
  "newhart": {
    "\"public\".\"agents\"": {
      "SELECT": false,
      "INSERT": true,
      "UPDATE": false,
      "DELETE": false
    }
  }
}
JSON
    run python3 "$GATE" --dbname nova_memory --db-user nova verify --all-grantees "$TMPDIR_RUN/fake-all-snapshot.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: grantee(s) lost base-DML privileges after reconciliation:"* ]]
    [[ "$output" == *"newhart"* ]]
    [[ "$output" == *"\"public\".\"agents\""* ]]
    [[ "$output" == *"INSERT"* ]]
    rm -rf "$TMPDIR_RUN"
}

@test "TC-759-shellcheck: bats file passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then skip "shellcheck not installed"; fi
    run shellcheck "$BATS_TEST_FILENAME"
    [ "$status" -eq 0 ]
}
