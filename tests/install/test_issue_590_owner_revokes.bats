#!/usr/bin/env bats
# Tests for nova-mind#590: owner/DB_USER REVOKEs must be filtered during
# reconciliation, and a post-reconciliation gate must abort on privilege loss.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FILTER="$REPO_ROOT/database/filter_shadowed_grants.py"
GATE="$REPO_ROOT/database/grant_reconcile_gate.py"

@test "TC-590a: REVOKE targeting relation owner is filtered" {
    # agents is owned by nova in nova_memory; revoking FROM nova must be skipped.
    run python3 "$FILTER" --dbname nova_memory --db-user nova <<'SQL'
REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM nova;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED: 1 owner/DB_USER REVOKE statement(s) (DB_USER 'nova')"* ]]
    [[ "$output" != *"REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM nova"* ]]
}

@test "TC-590a-mut: non-base-DML owner REVOKE is kept when owner map is unavailable" {
    run python3 "$FILTER" <<'SQL'
REVOKE TRIGGER ON TABLE agents FROM nova;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kept 1 grant/revoke statement(s)"* ]]
    [[ "$output" == *"REVOKE TRIGGER ON TABLE agents FROM nova"* ]]
    [[ "$output" != *"SKIPPED"* ]]
}

@test "TC-590c: non-owner, non-base-DML REVOKEs are still applied" {
    # agents is owned by nova; revoking TRIGGER FROM gidget is not owner-targeted
    # and does not touch the additive base-DML set, so it is kept.
    run python3 "$FILTER" --dbname nova_memory --db-user nova <<'SQL'
REVOKE TRIGGER ON TABLE agents FROM gidget;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kept 1 grant/revoke statement(s)"* ]]
    [[ "$output" == *"REVOKE TRIGGER ON TABLE agents FROM gidget"* ]]
    [[ "$output" != *"owner/DB_USER"* ]]
}

@test "TC-590c-mut: filtering does not drop non-owner, non-base-DML REVOKEs" {
    run python3 "$FILTER" --dbname nova_memory --db-user nova <<'SQL'
REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM nova;
REVOKE TRIGGER ON TABLE agents FROM gidget;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED: 1 owner/DB_USER REVOKE statement(s) (DB_USER 'nova')"* ]]
    [[ "$output" == *"Kept 1 grant/revoke statement(s)"* ]]
    [[ "$output" == *"REVOKE TRIGGER ON TABLE agents FROM gidget"* ]]
    [[ "$output" != *"REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM nova"* ]]
}

@test "TC-590b: gate aborts when snapshot privileges are lost" {
    TMPDIR_RUN=$(mktemp -d)
    # Craft a snapshot claiming nova has a privilege it does not hold on a fake relation.
    cat >"$TMPDIR_RUN/fake-snapshot.json" <<'JSON'
{
  "public.issue_590_gate_test_seq": {
    "USAGE": true,
    "SELECT": true,
    "UPDATE": true
  }
}
JSON
    run python3 "$GATE" --dbname nova_memory --db-user nova verify "$TMPDIR_RUN/fake-snapshot.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: DB_USER lost privileges after reconciliation:"* ]]
    [[ "$output" == *"public.issue_590_gate_test_seq"* ]]
    rm -rf "$TMPDIR_RUN"
}

@test "TC-590b-mut: gate passes when snapshot matches current privileges" {
    TMPDIR_RUN=$(mktemp -d)
    # Capture a real snapshot for nova_memory/nova and verify it passes.
    python3 "$GATE" --dbname nova_memory --db-user nova snapshot >"$TMPDIR_RUN/real-snapshot.json"
    run python3 "$GATE" --dbname nova_memory --db-user nova verify "$TMPDIR_RUN/real-snapshot.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: DB_USER 'nova' retained all"* ]]
    rm -rf "$TMPDIR_RUN"
}
