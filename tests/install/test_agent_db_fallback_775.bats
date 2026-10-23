#!/usr/bin/env bats
# BATS tests for nova-mind #775: per-agent fallback DB must resolve under the
# runtime user, not via systemd %u specifiers in Environment= lines.

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SERVICE_FILE="$REPO_ROOT/cognition/systemd/agent-spawner.service"
CATCHUP_SCRIPT="$REPO_ROOT/memory/scripts/memory-catchup.sh"

@test "TC-775-001: agent-spawner.service has no %u in Environment= lines" {
    run grep -E '^Environment=.*%u' "$SERVICE_FILE"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "TC-775-002: agent-spawner.service resolves NOVA_DB via User= wrapper" {
    run grep -E '^ExecStart=' "$SERVICE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"resolve_agent_db"* ]]
    [[ "$output" == *"NOVA_DB="* ]]
    [[ "$output" == *"NOVA_DB_USER="* ]]
}

@test "TC-775-003: memory-catchup.sh sources pg-env.sh and resolve_agent_db" {
    run grep -E 'pg-env\.sh|resolve_agent_db' "$CATCHUP_SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pg-env.sh"* ]]
    [[ "$output" == *"resolve_agent_db"* ]]
}

@test "TC-775-004: memory-catchup.sh no longer hardcodes psql nova_memory" {
    run grep -E 'psql[[:space:]]+nova_memory' "$CATCHUP_SCRIPT"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "TC-775-005: agent-spawner.service uses deployed pg-env.sh path" {
    run grep -E '^ExecStart=' "$SERVICE_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/home/nova/.openclaw/lib/pg-env.sh"* ]]
    [[ "$output" != *"/home/nova/workspace/lib/pg-env.sh"* ]]
}

@test "TC-775-006: resolution is not swallowed by || true" {
    run grep -E 'resolve_agent_db.*\|\|[[:space:]]*true' "$SERVICE_FILE"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "TC-775-007: empty NOVA_DB guard exists" {
    run grep -E '\[ -z "\$NOVA_DB" \]' "$SERVICE_FILE"
    [ "$status" -eq 0 ]
}

@test "TC-775-008: ExecStart fails closed when pg-env.sh is missing" {
    tmp_home=$(mktemp -d)
    cmd=$(sed -n "s/^ExecStart=\/bin\/bash -c '//;s/'$//p" "$SERVICE_FILE")
    cmd="${cmd//\/home\/nova\/\.openclaw\/lib\/pg-env\.sh/$tmp_home/.openclaw/lib/pg-env.sh}"
    run env -i HOME="$tmp_home" PATH="/usr/bin:/bin" bash -c "$cmd"
    [ "$status" -eq 1 ]
    [[ "$output" == *"NOVA_DB unresolved"* ]]
    rm -rf "$tmp_home"
}

@test "TC-778-001: resolve_agent_db normalizes hyphens in the runtime user" {
    tmp_bin=$(mktemp -d)
    cat > "$tmp_bin/whoami" <<'EOF'
#!/bin/bash
printf '%s' 'nova-staging'
EOF
    chmod +x "$tmp_bin/whoami"
    run env -i HOME="$HOME" PATH="$tmp_bin:/usr/bin:/bin" bash -c "source '$REPO_ROOT/memory/lib/pg-env.sh'; resolve_agent_db"
    [ "$status" -eq 0 ]
    [ "$output" = "nova_staging_memory" ]
    rm -rf "$tmp_bin"
}

@test "TC-778-002: resolve_agent_db leaves simple usernames unchanged" {
    tmp_bin=$(mktemp -d)
    cat > "$tmp_bin/whoami" <<'EOF'
#!/bin/bash
printf '%s' 'nova'
EOF
    chmod +x "$tmp_bin/whoami"
    run env -i HOME="$HOME" PATH="$tmp_bin:/usr/bin:/bin" bash -c "source '$REPO_ROOT/memory/lib/pg-env.sh'; resolve_agent_db"
    [ "$status" -eq 0 ]
    [ "$output" = "nova_memory" ]
    rm -rf "$tmp_bin"
}

@test "TC-778-003: PGDATABASE wins over resolve_agent_db fallback" {
    run env -i HOME="$HOME" PATH="/usr/bin:/bin" PGDATABASE="explicit_db" bash -c "source '$REPO_ROOT/memory/lib/pg-env.sh'; resolve_agent_db"
    [ "$status" -eq 0 ]
    [ "$output" = "explicit_db" ]
}

@test "TC-778-004: explicit database argument wins over resolve_agent_db fallback" {
    run env -i HOME="$HOME" PATH="/usr/bin:/bin" bash -c "source '$REPO_ROOT/memory/lib/pg-env.sh'; resolve_agent_db 'arg_db'"
    [ "$status" -eq 0 ]
    [ "$output" = "arg_db" ]
}
