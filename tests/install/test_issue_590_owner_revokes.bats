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

@test "TC-590a-mut: named-role REVOKE is dropped when owner map is unavailable" {
    # Without --dbname/--db-user the filter cannot look up owners, but #759
    # still drops base REVOKEs from named roles on tables/sequences.
    run python3 "$FILTER" <<'SQL'
REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM nova;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED: 1 named-role REVOKE statement(s) on tables/sequences (named-role REVOKE (nova))"* ]]
    [[ "$output" == *"Kept 0 grant/revoke statement(s)"* ]]
    [[ "$output" != *"REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM nova"* ]]
}

@test "TC-590c: PUBLIC REVOKEs are still applied" {
    # PUBLIC is intentionally exempt from #759 named-role REVOKE filtering.
    run python3 "$FILTER" --dbname nova_memory --db-user nova <<'SQL'
REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM public;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kept 1 grant/revoke statement(s)"* ]]
    [[ "$output" == *"REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM public"* ]]
    [[ "$output" != *"owner/DB_USER"* ]]
    [[ "$output" != *"named-role REVOKE"* ]]
}

@test "TC-590c-mut: filtering does not drop PUBLIC REVOKEs" {
    run python3 "$FILTER" --dbname nova_memory --db-user nova <<'SQL'
REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM nova;
REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM public;
SQL
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIPPED: 1 owner/DB_USER REVOKE statement(s) (DB_USER 'nova')"* ]]
    [[ "$output" == *"Kept 1 grant/revoke statement(s)"* ]]
    [[ "$output" == *"REVOKE DELETE, INSERT, UPDATE ON TABLE agents FROM public"* ]]
    [[ "$output" != *"REVOKE DELETE, INSERT, SELECT, UPDATE ON TABLE agents FROM nova"* ]]
}

@test "TC-590b: gate aborts when snapshot privileges are lost" {
    TMPDIR_RUN=$(mktemp -d)
    # Craft a per-grantee snapshot claiming some_role holds privileges it does not.
    cat >"$TMPDIR_RUN/fake-snapshot.json" <<'JSON'
{
  "some_role": {
    "public.issue_590_gate_test_seq": {
      "USAGE": true,
      "SELECT": true,
      "UPDATE": true
    }
  }
}
JSON
    run python3 "$GATE" --dbname nova_memory --db-user nova verify "$TMPDIR_RUN/fake-snapshot.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR: grantees lost privileges after reconciliation:"* ]]
    [[ "$output" == *"public.issue_590_gate_test_seq"* ]]
    rm -rf "$TMPDIR_RUN"
}

@test "TC-590b-mut: gate passes when snapshot matches current privileges" {
    TMPDIR_RUN=$(mktemp -d)
    # Capture a real per-grantee snapshot for nova_memory/nova and verify it passes.
    python3 "$GATE" --dbname nova_memory --db-user nova snapshot >"$TMPDIR_RUN/real-snapshot.json"
    run python3 "$GATE" --dbname nova_memory --db-user nova verify "$TMPDIR_RUN/real-snapshot.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: all grantees retained privileges on"* ]]
    rm -rf "$TMPDIR_RUN"
}
