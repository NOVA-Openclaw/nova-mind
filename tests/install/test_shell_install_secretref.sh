#!/bin/bash
# Test shell-install.sh API-key SecretRef wiring in an isolated HOME.
# Issue: nova-mind#309 staging fix
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHELL_INSTALL="$REPO_ROOT/shell-install.sh"

# Inherit nothing from the test runner's environment.
unset OPENAI_API_KEY ANTHROPIC_API_KEY
export SHELL_INSTALL_TEST_SKIP_AGENT_INSTALL=1

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Fake openclaw binary that validates JSON and exits rc.
make_fake_openclaw() {
    local home="$1"
    local rc="${2:-0}"
    local bin_dir="$home/.local/bin"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/openclaw" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "config" ] && [ "\$2" = "validate" ]; then
    if [ "\$3" = "--help" ]; then
        echo "Usage: openclaw config validate [options]"
        exit 0
    fi
    if jq empty "\$HOME/.openclaw/openclaw.json" 2>/dev/null; then
        exit $rc
    fi
    exit 1
fi
echo "OpenClaw 9999.0.0"
exit 0
EOF
    chmod +x "$bin_dir/openclaw"
    echo "$bin_dir"
}

# Minimal postgres.json so the DB part of shell-install.sh doesn't prompt.
make_minimal_pg_config() {
    local home="$1"
    mkdir -p "$home/.openclaw"
    cat > "$home/.openclaw/postgres.json" <<'EOF'
{
  "host": "localhost",
  "port": 5432,
  "database": "nova_memory",
  "user": "nova"
}
EOF
}

run_test() { if "$@"; then pass "$1"; else fail "$1" "test body returned non-zero"; fi; }

# ── TEST 1: no 'read' prompts for API keys remain in shell-install.sh ──
test_no_api_key_read_prompts() {
    if grep -nE 'read -rp.*(OpenAI|Anthropic) API key' "$SHELL_INSTALL"; then
        return 1
    fi
}
run_test test_no_api_key_read_prompts

# ── TEST 2: provider present → SecretRef written for both keys ──
test_provider_present_writes_secretrefs() {
    local home="$TMPDIR_BASE/t2"
    mkdir -p "$home/.openclaw"
    make_minimal_pg_config "$home"
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 0)
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "secrets": {
    "providers": {
      "op_openai": {"source": "exec", "command": "echo", "args": ["value"]},
      "op_anthropic": {"source": "exec", "command": "echo", "args": ["value"]}
    }
  }
}
EOF
    HOME="$home" PATH="$bin_dir:$PATH" OPENAI_API_KEY="" ANTHROPIC_API_KEY="" bash "$SHELL_INSTALL" </dev/null
    local openai_provider openai_id anthropic_provider anthropic_id
    openai_provider=$(jq -r '.env.vars.OPENAI_API_KEY.provider' "$home/.openclaw/openclaw.json")
    openai_id=$(jq -r '.env.vars.OPENAI_API_KEY.id' "$home/.openclaw/openclaw.json")
    anthropic_provider=$(jq -r '.env.vars.ANTHROPIC_API_KEY.provider' "$home/.openclaw/openclaw.json")
    anthropic_id=$(jq -r '.env.vars.ANTHROPIC_API_KEY.id' "$home/.openclaw/openclaw.json")
    [[ "$openai_provider" == "op_openai" && "$openai_id" == "value" ]]
    [[ "$anthropic_provider" == "op_anthropic" && "$anthropic_id" == "value" ]]
}
run_test test_provider_present_writes_secretrefs

# ── TEST 3: re-run leaves an existing SecretRef unchanged ──
test_rerun_leaves_secretref_unchanged() {
    local home="$TMPDIR_BASE/t3"
    mkdir -p "$home/.openclaw"
    make_minimal_pg_config "$home"
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 0)
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "env": {
    "vars": {
      "OPENAI_API_KEY": {"source": "exec", "provider": "custom", "id": "existing"},
      "ANTHROPIC_API_KEY": {"source": "exec", "provider": "custom", "id": "existing"}
    }
  },
  "secrets": {
    "providers": {
      "op_openai": {"source": "exec", "command": "echo", "args": ["value"]},
      "op_anthropic": {"source": "exec", "command": "echo", "args": ["value"]}
    }
  }
}
EOF
    HOME="$home" PATH="$bin_dir:$PATH" OPENAI_API_KEY="" ANTHROPIC_API_KEY="" bash "$SHELL_INSTALL" </dev/null
    local openai_provider anthropic_provider
    openai_provider=$(jq -r '.env.vars.OPENAI_API_KEY.provider' "$home/.openclaw/openclaw.json")
    anthropic_provider=$(jq -r '.env.vars.ANTHROPIC_API_KEY.provider' "$home/.openclaw/openclaw.json")
    [[ "$openai_provider" == "custom" ]]
    [[ "$anthropic_provider" == "custom" ]]
}
run_test test_rerun_leaves_secretref_unchanged

# ── TEST 4: missing provider produces a warning and no plaintext ──
test_missing_provider_warns_no_plaintext() {
    local home="$TMPDIR_BASE/t4"
    mkdir -p "$home/.openclaw"
    make_minimal_pg_config "$home"
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 0)
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "secrets": {"providers": {}}
}
EOF
    local output
    output=$(HOME="$home" PATH="$bin_dir:$PATH" OPENAI_API_KEY="" ANTHROPIC_API_KEY="" bash "$SHELL_INSTALL" </dev/null 2>&1)
    echo "$output" | grep -q "OPENAI_API_KEY not wired: provider 'op_openai' is not defined" || { echo "missing OpenAI warning in output"; return 1; }
    echo "$output" | grep -q "ANTHROPIC_API_KEY not wired: provider 'op_anthropic' is not defined" || { echo "missing Anthropic warning in output"; return 1; }
    # Ensure no plaintext string was written.
    local openai_type anthropic_type
    openai_type=$(jq -r '.env.vars.OPENAI_API_KEY | type' "$home/.openclaw/openclaw.json" 2>/dev/null || echo "missing")
    anthropic_type=$(jq -r '.env.vars.ANTHROPIC_API_KEY | type' "$home/.openclaw/openclaw.json" 2>/dev/null || echo "missing")
    [[ "$openai_type" != "string" ]]
    [[ "$anthropic_type" != "string" ]]
}
run_test test_missing_provider_warns_no_plaintext

# ── TEST 5: existing plaintext string is left untouched and warned ──
test_existing_plaintext_left_untouched() {
    local home="$TMPDIR_BASE/t5"
    mkdir -p "$home/.openclaw"
    make_minimal_pg_config "$home"
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 0)
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "env": {"vars": {"OPENAI_API_KEY": "old-plaintext-key"}},
  "secrets": {
    "providers": {"op_openai": {"source": "exec", "command": "echo", "args": ["value"]}}
  }
}
EOF
    local output
    output=$(HOME="$home" PATH="$bin_dir:$PATH" OPENAI_API_KEY="" ANTHROPIC_API_KEY="" bash "$SHELL_INSTALL" </dev/null 2>&1)
    echo "$output" | grep -q "OPENAI_API_KEY is a plaintext string" || { echo "missing plaintext warning in output"; return 1; }
    local openai_value
    openai_value=$(jq -r '.env.vars.OPENAI_API_KEY' "$home/.openclaw/openclaw.json")
    [[ "$openai_value" == "old-plaintext-key" ]]
}
run_test test_existing_plaintext_left_untouched

# ── Summary ──
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed (total $((PASS+FAIL)))"
echo "================================"
[[ $FAIL -eq 0 ]]
