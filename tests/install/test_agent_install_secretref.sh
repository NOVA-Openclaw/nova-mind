#!/bin/bash
# Test agent-install.sh memory-extract SecretRef wiring in an isolated HOME.
# Issue: nova-workspace#309
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AGENT_INSTALL="$REPO_ROOT/agent-install.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# Source agent-install.sh in test mode so helper functions are available.
export AGENT_INSTALL_TEST_MODE=1
# shellcheck source=/dev/null
source "$AGENT_INSTALL"

# Create a fake openclaw in the temp HOME so 'openclaw config validate'
# validates the test config instead of the real one.
make_fake_openclaw() {
    local home="$1"
    local rc="${2:-0}"
    local bin_dir="$home/.local/bin"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/openclaw" <<EOF
#!/usr/bin/env bash
# Fake openclaw for isolated tests.
if [ "\$1" = "config" ] && [ "\$2" = "validate" ]; then
    if [ "\$3" = "--help" ]; then
        echo "Usage: openclaw config validate [options]"
        exit 0
    fi
    # Validate that the config at HOME/.openclaw/openclaw.json is valid JSON.
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

wire_secretref() {
    local home="$1"
    export HOME="$home"
    export OPENCLAW_DIR="$home/.openclaw"
    export OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"
    export SCRIPT_DIR="$REPO_ROOT"
    mkdir -p "$OPENCLAW_DIR"
}

run_test() { if "$@"; then pass "$1"; else fail "$1" "test body returned non-zero"; fi; }

# ── TEST 1: provider present → ref written ──
test_provider_present_ref_written() {
    local home="$TMPDIR_BASE/t1"
    wire_secretref "$home"
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 0)
    export PATH="$bin_dir:$PATH"
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "plugins": {"entries": {"memory-extract": {"enabled": true}}, "load": {"paths": ["/tmp/memory-extract"]}},
  "secrets": {
    "providers": {
      "op_openrouter": {"source": "exec", "command": "echo", "args": ["value"]}
    }
  }
}
EOF
    local cfg_tmp
    cfg_tmp=$(mktemp "$home/.openclaw/openclaw.json.tmp.XXXXXX")
    cp "$home/.openclaw/openclaw.json" "$cfg_tmp"
    _wire_memory_extract_secretref "$home/.openclaw/openclaw.json" "$cfg_tmp"
    local provider id
    provider=$(jq -r '.plugins.entries."memory-extract".config.extraction.apiKey.provider' "$home/.openclaw/openclaw.json")
    id=$(jq -r '.plugins.entries."memory-extract".config.extraction.apiKey.id' "$home/.openclaw/openclaw.json")
    [[ "$provider" == "op_openrouter" && "$id" == "value" ]]
}
run_test test_provider_present_ref_written

# ── TEST 2: provider absent → untouched plus instructions ──
test_provider_absent_untouched() {
    local home="$TMPDIR_BASE/t2"
    wire_secretref "$home"
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 0)
    export PATH="$bin_dir:$PATH"
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "plugins": {"entries": {"memory-extract": {"enabled": true}}, "load": {"paths": ["/tmp/memory-extract"]}},
  "secrets": {"providers": {}}
}
EOF
    local cfg_tmp
    cfg_tmp=$(mktemp "$home/.openclaw/openclaw.json.tmp.XXXXXX")
    cp "$home/.openclaw/openclaw.json" "$cfg_tmp"
    _wire_memory_extract_secretref "$home/.openclaw/openclaw.json" "$cfg_tmp"
    local apikey
    apikey=$(jq -r '.plugins.entries."memory-extract".config.extraction.apiKey // "__missing__"' "$home/.openclaw/openclaw.json")
    [[ "$apikey" == "__missing__" ]]
}
run_test test_provider_absent_untouched

# ── TEST 3: existing ref → untouched ──
test_existing_ref_untouched() {
    local home="$TMPDIR_BASE/t3"
    wire_secretref "$home"
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 0)
    export PATH="$bin_dir:$PATH"
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "plugins": {"entries": {"memory-extract": {"enabled": true, "config": {"extraction": {"apiKey": {"source": "exec", "provider": "custom", "id": "existing"}}}}}, "load": {"paths": ["/tmp/memory-extract"]}},
  "secrets": {"providers": {"op_openrouter": {"source": "exec", "command": "echo", "args": ["value"]}}}
}
EOF
    local cfg_tmp
    cfg_tmp=$(mktemp "$home/.openclaw/openclaw.json.tmp.XXXXXX")
    cp "$home/.openclaw/openclaw.json" "$cfg_tmp"
    _wire_memory_extract_secretref "$home/.openclaw/openclaw.json" "$cfg_tmp"
    local provider id
    provider=$(jq -r '.plugins.entries."memory-extract".config.extraction.apiKey.provider' "$home/.openclaw/openclaw.json")
    id=$(jq -r '.plugins.entries."memory-extract".config.extraction.apiKey.id' "$home/.openclaw/openclaw.json")
    [[ "$provider" == "custom" && "$id" == "existing" ]]
}
run_test test_existing_ref_untouched

# ── TEST 4: plaintext string → untouched plus warning ──
test_plaintext_string_untouched() {
    local home="$TMPDIR_BASE/t4"
    wire_secretref "$home"
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 0)
    export PATH="$bin_dir:$PATH"
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "plugins": {"entries": {"memory-extract": {"enabled": true, "config": {"extraction": {"apiKey": "sk-plaintext"}}}}, "load": {"paths": ["/tmp/memory-extract"]}},
  "secrets": {"providers": {"op_openrouter": {"source": "exec", "command": "echo", "args": ["value"]}}}
}
EOF
    local cfg_tmp
    cfg_tmp=$(mktemp "$home/.openclaw/openclaw.json.tmp.XXXXXX")
    cp "$home/.openclaw/openclaw.json" "$cfg_tmp"
    _wire_memory_extract_secretref "$home/.openclaw/openclaw.json" "$cfg_tmp"
    local apikey
    apikey=$(jq -r '.plugins.entries."memory-extract".config.extraction.apiKey' "$home/.openclaw/openclaw.json")
    [[ "$apikey" == "sk-plaintext" ]]
}
run_test test_plaintext_string_untouched

# ── TEST 5: validate failure restores backup ──
test_validate_failure_restores_backup() {
    local home="$TMPDIR_BASE/t5"
    wire_secretref "$home"
    # Fake openclaw that always fails validation.
    local bin_dir
    bin_dir=$(make_fake_openclaw "$home" 1)
    export PATH="$bin_dir:$PATH"
    cat > "$home/.openclaw/openclaw.json" <<'EOF'
{
  "plugins": {"entries": {"memory-extract": {"enabled": true}}, "load": {"paths": ["/tmp/memory-extract"]}},
  "secrets": {"providers": {"op_openrouter": {"source": "exec", "command": "echo", "args": ["value"]}}}
}
EOF
    local cfg_tmp
    cfg_tmp=$(mktemp "$home/.openclaw/openclaw.json.tmp.XXXXXX")
    cp "$home/.openclaw/openclaw.json" "$cfg_tmp"
    # The function returns 1 on validation failure.
    _wire_memory_extract_secretref "$home/.openclaw/openclaw.json" "$cfg_tmp" || true
    # The original config should be preserved (no apiKey added, provider still present).
    local provider_exists apikey_missing
    provider_exists=$(jq -e '.secrets.providers.op_openrouter' "$home/.openclaw/openclaw.json" >/dev/null 2>&1 && echo 1 || echo 0)
    apikey_missing=$(jq -e '.plugins.entries."memory-extract".config.extraction.apiKey' "$home/.openclaw/openclaw.json" >/dev/null 2>&1 && echo 0 || echo 1)
    [[ "$provider_exists" -eq 1 && "$apikey_missing" -eq 1 ]]
}
run_test test_validate_failure_restores_backup

# ── Summary ──
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed (total $((PASS+FAIL)))"
echo "================================"
[[ $FAIL -eq 0 ]]
