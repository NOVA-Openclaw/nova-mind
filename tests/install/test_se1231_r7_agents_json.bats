#!/usr/bin/env bats
# SE #1231 r7 regression tests for agents.json validation before $include switch.
#
# Verifies that agent-install.sh only switches agents.entries to
# { "$include": "./agents.json" } after agents.json is a valid non-empty
# keyed object.  Covers the staging "[]" failure, the production inline-object
# case, DB failure fallback, the {} fallback, idempotency, and ordering.
#
# Run: bats tests/install/test_se1231_r7_agents_json.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

# ─── helpers ────────────────────────────────────────────────────────────────

setup() {
    SCRATCH="$(mktemp -d)"
    FAKE_REPO="$SCRATCH/repo"
    FAKE_OPENCLAW="$SCRATCH/.openclaw"

    mkdir -p "$FAKE_OPENCLAW"
    mkdir -p "$FAKE_REPO/lib"
    cp "$REPO_ROOT/agent-install.sh" "$FAKE_REPO/agent-install.sh"
    printf '%s\n' 'load_pg_env() { :; }' 'load_pg_superuser_env() { :; }' >"$FAKE_REPO/lib/pg-env.sh"
    printf '%s\n' '# stub' >"$FAKE_REPO/lib/agent-chat-peer-detection.sh"

    export HOME="$SCRATCH"
    export AGENT_INSTALL_TEST_MODE=1
    export SCRIPT_DIR="$FAKE_REPO"
    export OPENCLAW_DIR="$FAKE_OPENCLAW"
    export OPENCLAW_CONFIG="$FAKE_OPENCLAW/openclaw.json"
    export DB_USER="testuser"
    export DB_NAME="test_db"
    export REGENERATE_AGENTS_JSON=0

    # Default config has inline keyed agents.entries (production-shaped).
    cat > "$OPENCLAW_CONFIG" <<'JSON'
{
  "plugins": { "entries": {}, "load": { "paths": [] } },
  "hooks": { "internal": { "enabled": true, "entries": {} } },
  "agents": {
    "defaults": {},
    "entries": {
      "athena": { "model": "openai/gpt-5" },
      "cadence": { "model": "anthropic/claude-sonnet-4" },
      "coder": { "model": "openrouter/moonshotai/kimi-k2.7-code" },
      "gem": { "model": "google/gemini-flash" },
      "nova": { "model": "anthropic/claude-opus-4", "default": true }
    }
  }
}
JSON
}

teardown() {
    rm -rf "$SCRATCH"
}

# Run the helper in a fresh subshell so agent-install.sh's set -e does
# not kill the bats process when an assertion later fails.
run_config_helper() {
    run bash -c '
        set -e
        source "$SCRIPT_DIR/agent-install.sh"
        _configure_agents_entries_include "$OPENCLAW_CONFIG"
    ' 2>&1
}

# Install a stub psql in PATH that returns controlled output.
install_psql_stub() {
    local stub_output="$1"
    mkdir -p "$SCRATCH/bin"
    cat > "$SCRATCH/bin/psql" <<'EOF'
#!/usr/bin/env bash
if [ "$PSQL_STUB_OUTPUT" = "FAIL" ]; then
    exit 1
fi
printf '%s' "$PSQL_STUB_OUTPUT"
exit 0
EOF
    chmod +x "$SCRATCH/bin/psql"
    export PATH="$SCRATCH/bin:$PATH"
    export PSQL_STUB_OUTPUT="$stub_output"
}

# ─── TC-1231-R7-001: staging case (bare [] + 0 DB rows) ─────────────────────

@test "TC-1231-R7-001: staging case bare [] with empty DB becomes valid object" {
    printf '%s\n' '[]' > "$FAKE_OPENCLAW/agents.json"
    install_psql_stub ""

    run_config_helper
    [ "$status" -eq 0 ]

    run jq -e 'type == "object" and length > 0' "$FAKE_OPENCLAW/agents.json"
    [ "$status" -eq 0 ]

    run jq -r 'type' "$FAKE_OPENCLAW/agents.json"
    [ "$output" = "object" ]

    run jq -r '.agents.entries["$include"] // empty' "$OPENCLAW_CONFIG"
    [ "$output" = "./agents.json" ]

    local bak
    bak=$(find "$FAKE_OPENCLAW" -name 'agents.json.bak-*' | head -1)
    [ -n "$bak" ]
    run stat -c '%a' "$bak"
    [ "$output" = "600" ]
}

# ─── TC-1231-R7-002: production inline-object case (16 agents) ──────────────

@test "TC-1231-R7-002: production inline object preserved into agents.json with \$include" {
    local agents='{}'
    for id in alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi; do
        agents=$(printf '%s' "$agents" | jq --arg id "$id" --arg model "provider/${id}-model" '. + {($id): {model: $model}}')
    done
    jq --argjson agents "$agents" '.agents.entries = $agents' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
        mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG"

    install_psql_stub ""

    run_config_helper
    [ "$status" -eq 0 ]

    run jq -r '.agents.entries["$include"] // empty' "$OPENCLAW_CONFIG"
    [ "$output" = "./agents.json" ]

    run jq 'keys | length' "$FAKE_OPENCLAW/agents.json"
    [ "$output" -eq 16 ]

    for id in alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi; do
        run jq -e --arg id "$id" '.[$id].model == "provider/\($id)-model"' "$FAKE_OPENCLAW/agents.json"
        [ "$status" -eq 0 ]
    done
}

# ─── TC-1231-R7-003: DB failure with no existing agents.json ────────────────

@test "TC-1231-R7-003: DB failure writes placeholder and still switches to \$include" {
    install_psql_stub "FAIL"

    run_config_helper
    [ "$status" -eq 0 ]

    run jq -e 'type == "object" and length > 0' "$FAKE_OPENCLAW/agents.json"
    [ "$status" -eq 0 ]

    run jq -r '.agents.entries["$include"] // empty' "$OPENCLAW_CONFIG"
    [ "$output" = "./agents.json" ]
}

# ─── TC-1231-R7-004: existing {} with empty DB becomes placeholder ──────────

@test "TC-1231-R7-004: existing empty object {} is backed up and replaced" {
    printf '%s\n' '{}' > "$FAKE_OPENCLAW/agents.json"
    install_psql_stub ""

    run_config_helper
    [ "$status" -eq 0 ]

    run jq -e 'type == "object" and length > 0' "$FAKE_OPENCLAW/agents.json"
    [ "$status" -eq 0 ]

    run jq -r '.agents.entries["$include"] // empty' "$OPENCLAW_CONFIG"
    [ "$output" = "./agents.json" ]

    local bak
    bak=$(find "$FAKE_OPENCLAW" -name 'agents.json.bak-*' | head -1)
    [ -n "$bak" ]
}

# ─── TC-1231-R7-005: idempotency ────────────────────────────────────────────

@test "TC-1231-R7-005: second run leaves valid keyed agents.json unchanged" {
    install_psql_stub ""

    run_config_helper
    [ "$status" -eq 0 ]

    local first_content
    first_content=$(cat "$FAKE_OPENCLAW/agents.json")

    run_config_helper
    [ "$status" -eq 0 ]

    local second_content
    second_content=$(cat "$FAKE_OPENCLAW/agents.json")

    [ "$first_content" = "$second_content" ]

    run jq -e 'type == "object" and length > 0' "$FAKE_OPENCLAW/agents.json"
    [ "$status" -eq 0 ]
}

# ─── TC-1231-R7-006: legacy array conversion ────────────────────────────────

@test "TC-1231-R7-006: legacy array is converted to keyed object deterministically" {
    # Remove inline entries so the conversion path is exercised in isolation.
    jq '.agents.entries = {}' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
        mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG"

    cat > "$FAKE_OPENCLAW/agents.json" <<'JSON'
[
  { "id": "zebra", "model": "z/model", "thinkingDefault": "high" },
  { "id": "alpha", "model": "a/model", "subagents": { "allowAgents": ["*"] } },
  { "id": "beta",  "model": "b/model" }
]
JSON
    install_psql_stub ""

    run_config_helper
    [ "$status" -eq 0 ]

    run jq -r 'type' "$FAKE_OPENCLAW/agents.json"
    [ "$output" = "object" ]

    run jq -r 'keys | .[]' "$FAKE_OPENCLAW/agents.json"
    [ "$output" = $'alpha\nbeta\nzebra' ]

    run jq -r '.alpha.model' "$FAKE_OPENCLAW/agents.json"
    [ "$output" = "a/model" ]

    run jq -r '.zebra.thinkingDefault' "$FAKE_OPENCLAW/agents.json"
    [ "$output" = "high" ]

    run jq -c '.alpha.subagents.allowAgents' "$FAKE_OPENCLAW/agents.json"
    [ "$output" = '["*"]' ]

    run jq '[.[] | has("id")] | any' "$FAKE_OPENCLAW/agents.json"
    [ "$output" = "false" ]
}

# ─── TC-1231-R7-007: ordering / mutation proof ──────────────────────────────

@test "TC-1231-R7-007: \$include switch only happens after agents.json is verified" {
    printf '%s\n' '[]' > "$FAKE_OPENCLAW/agents.json"
    install_psql_stub ""

    run jq -r 'type' "$FAKE_OPENCLAW/agents.json"
    local before_type="$output"
    [ "$before_type" = "array" ]

    run jq -r '.agents.entries | keys | .[]' "$OPENCLAW_CONFIG"
    local before_keys="$output"
    [[ "$before_keys" == *"nova"* ]]

    run_config_helper
    [ "$status" -eq 0 ]

    run jq -r 'type' "$FAKE_OPENCLAW/agents.json"
    [ "$output" = "object" ]

    run jq -r '.agents.entries["$include"] // empty' "$OPENCLAW_CONFIG"
    [ "$output" = "./agents.json" ]
}

# ─── TC-1231-R7-008: DB result supersedes stale array, inline preserved ─────

@test "TC-1231-R7-008: DB result is merged with inline entries to avoid shrinkage" {
    # Replace default inline entries with a single extra agent so the merge
    # is unambiguous.
    jq '.agents.entries = {inline_only: {model: "inline/model"}}' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
        mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG"

    local db_rows='[{"name":"from_db","model":"db/model","fallback_models":null,"thinking":null,"instance_type":"subagent","is_default":false,"allowed_subagents":null,"heartbeat_enabled":false,"heartbeat_every":null,"heartbeat_target":null,"heartbeat_to":null}]'
    install_psql_stub "$db_rows"

    run_config_helper
    [ "$status" -eq 0 ]

    run jq -e '.from_db' "$FAKE_OPENCLAW/agents.json"
    [ "$status" -eq 0 ]
    run jq -e '.inline_only' "$FAKE_OPENCLAW/agents.json"
    [ "$status" -eq 0 ]

    run jq 'keys | length' "$FAKE_OPENCLAW/agents.json"
    [ "$output" -eq 2 ]
}
