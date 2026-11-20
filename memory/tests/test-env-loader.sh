#!/bin/bash
# test-env-loader.sh — Test runner for lib/env-loader.sh
# Issue: nova-workspace#309 — env-loader now resolves secrets via nova-op.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$SCRIPT_DIR/lib/env-loader.sh"

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

# Create isolated temp dir
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

make_map() {
  local dir="$TMPDIR_BASE/$1"
  mkdir -p "$dir/.openclaw/scripts"
  echo "$2" > "$dir/.openclaw/scripts/nova-op-item-map.json"
  echo "$dir"
}

make_nova_op() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/nova-op" <<'EOF'
#!/usr/bin/env bash
# Stub nova-op for tests: echoes fake values based on item id.
set -euo pipefail
item=""
while [ $# -gt 0 ]; do
  case "$1" in
    item|get) shift ;;
    --vault|--field|--reveal) shift ;;
    *)
      if [ -z "$item" ]; then
        item="$1"
      fi
      shift
      ;;
  esac
done
case "$item" in
  w3pkbapwocl6twwcajk5ksy4tm) echo "fake-openrouter-key" ;;
  eefc3r3hh4lzb7dasihufmqmoy) echo "fake-anthropic-key" ;;
  4jmgair7umpfk4bwahpz56elge) echo "fake-openai-key" ;;
  zk72pqdffik6rtd36kuddxvi7a) echo "fake-gemini-key" ;;
  *) echo "nova-op: item not found: $item" >&2; exit 1 ;;
esac
EOF
  chmod +x "$bin_dir/nova-op"
}

# Each test runs in a subshell with isolated HOME/PATH
run_test() {
  local name="$1"
  shift
  if "$@"; then
    pass "$name"
  else
    fail "$name" "test body returned non-zero"
  fi
}

# ── TEST 1.1: loads vars from valid map via nova-op ──
test_bash_loads_vars_from_valid_config() (
  local home
  home=$(make_map t1_1 '{
    "OPENROUTER_API_KEY": {"vault":"NOVA Shared Vault","item":"w3pkbapwocl6twwcajk5ksy4tm","field":"API Key"},
    "ANTHROPIC_API_KEY": {"vault":"NOVA Shared Vault","item":"eefc3r3hh4lzb7dasihufmqmoy","field":"credential"}
  }')
  local bin_dir="$TMPDIR_BASE/t1_1_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  unset OPENROUTER_API_KEY ANTHROPIC_API_KEY 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
  [[ "$OPENROUTER_API_KEY" == "fake-openrouter-key" && "$ANTHROPIC_API_KEY" == "fake-anthropic-key" ]]
)
run_test "TEST-1.1: loads vars from valid map via nova-op" test_bash_loads_vars_from_valid_config

# ── TEST 1.3: return code 0 on success ──
test_bash_return_code_zero() (
  local home
  home=$(make_map t1_3 '{"OPENROUTER_API_KEY":{"vault":"V","item":"w3pkbapwocl6twwcajk5ksy4tm","field":"f"}}')
  local bin_dir="$TMPDIR_BASE/t1_3_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  unset OPENROUTER_API_KEY 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
)
run_test "TEST-1.3: return code 0 on success" test_bash_return_code_zero

# ── TEST 2.1: existing env var NOT overwritten ──
test_bash_existing_env_not_overwritten() (
  local home
  home=$(make_map t2_1 '{"OPENROUTER_API_KEY":{"vault":"V","item":"w3pkbapwocl6twwcajk5ksy4tm","field":"f"}}')
  local bin_dir="$TMPDIR_BASE/t2_1_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  export OPENROUTER_API_KEY=original
  source "$LIB"
  load_openclaw_env
  [[ "$OPENROUTER_API_KEY" == "original" ]]
)
run_test "TEST-2.1: existing env var NOT overwritten" test_bash_existing_env_not_overwritten

# ── TEST 2.3: empty env var IS overwritten ──
test_bash_empty_env_overwritten() (
  local home
  home=$(make_map t2_3 '{"OPENROUTER_API_KEY":{"vault":"V","item":"w3pkbapwocl6twwcajk5ksy4tm","field":"f"}}')
  local bin_dir="$TMPDIR_BASE/t2_3_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  export OPENROUTER_API_KEY=""
  source "$LIB"
  load_openclaw_env
  [[ "$OPENROUTER_API_KEY" == "fake-openrouter-key" ]]
)
run_test "TEST-2.3: empty env var IS overwritten" test_bash_empty_env_overwritten

# ── TEST 3.1: metadata keys skipped ──
test_bash_metadata_key_skipped() (
  local home
  home=$(make_map t3_1 '{
    "_description": "ignored",
    "OPENROUTER_API_KEY": {"vault":"V","item":"w3pkbapwocl6twwcajk5ksy4tm","field":"f"}
  }')
  local bin_dir="$TMPDIR_BASE/t3_1_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  unset OPENROUTER_API_KEY 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
  [[ "$OPENROUTER_API_KEY" == "fake-openrouter-key" ]]
)
run_test "TEST-3.1: metadata keys skipped" test_bash_metadata_key_skipped

# ── TEST 5.1: malformed JSON warns and returns 1 ──
test_bash_malformed_json_warns() (
  local home
  home=$(make_map t5_1 '{not valid json')
  local bin_dir="$TMPDIR_BASE/t5_1_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  source "$LIB"
  local stderr_file="$TMPDIR_BASE/stderr_5_1.txt"
  local rc=0
  load_openclaw_env 2>"$stderr_file" || rc=$?
  [[ $rc -eq 1 ]] && grep -q "item map is not valid JSON" "$stderr_file"
)
run_test "TEST-5.1: malformed JSON warns and returns 1" test_bash_malformed_json_warns

# ── TEST 6.1: missing config returns 1 loudly ──
test_bash_missing_config_errors() (
  local home="$TMPDIR_BASE/t6_1_empty"
  mkdir -p "$home"
  local bin_dir="$TMPDIR_BASE/t6_1_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  source "$LIB"
  local stderr_file="$TMPDIR_BASE/stderr_6_1.txt"
  local rc=0
  load_openclaw_env 2>"$stderr_file" || rc=$?
  [[ $rc -eq 1 && -s "$stderr_file" ]]
)
run_test "TEST-6.1: missing config returns 1 loudly" test_bash_missing_config_errors

# ── TEST 7.1: unreadable config returns 1 ──
test_bash_unreadable_config_errors() (
  local home
  home=$(make_map t7_1 '{"OPENROUTER_API_KEY":{"vault":"V","item":"i","field":"f"}}')
  chmod 000 "$home/.openclaw/scripts/nova-op-item-map.json"
  local bin_dir="$TMPDIR_BASE/t7_1_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  source "$LIB"
  local stderr_file="$TMPDIR_BASE/stderr_7_1.txt"
  local rc=0
  load_openclaw_env 2>"$stderr_file" || rc=$?
  chmod 644 "$home/.openclaw/scripts/nova-op-item-map.json"  # cleanup
  [[ $rc -eq 1 ]]
)
run_test "TEST-7.1: unreadable config returns 1" test_bash_unreadable_config_errors

# ── TEST 10.1: custom config path is respected ──
test_bash_custom_config_path() (
  local home="$TMPDIR_BASE/t10_1_home"
  mkdir -p "$home/.openclaw/scripts"
  local custom_map="$home/.openclaw/scripts/custom-item-map.json"
  echo '{"OPENROUTER_API_KEY":{"vault":"V","item":"w3pkbapwocl6twwcajk5ksy4tm","field":"f"}}' > "$custom_map"
  local bin_dir="$TMPDIR_BASE/t10_1_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  unset OPENROUTER_API_KEY 2>/dev/null || true
  source "$LIB"
  load_openclaw_env "$custom_map"
  [[ "$OPENROUTER_API_KEY" == "fake-openrouter-key" ]]
)
run_test "TEST-10.1: custom config path is respected" test_bash_custom_config_path

# ── TEST 10.2: no plaintext file reads ──
test_bash_no_plaintext_file_reads() (
  local home
  home=$(make_map t10_2 '{"OPENROUTER_API_KEY":{"vault":"V","item":"w3pkbapwocl6twwcajk5ksy4tm","field":"f"}}')
  local bin_dir="$TMPDIR_BASE/t10_2_bin"
  make_nova_op "$bin_dir"
  echo 'OPENROUTER_API_KEY=plaintext-env-key' > "$home/.openclaw/.env"
  echo 'OPENROUTER_API_KEY=plaintext-secrets-key' > "$home/.openclaw/secrets.env"
  echo 'export OPENROUTER_API_KEY=plaintext-bash-key' > "$home/.bash_env"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  unset OPENROUTER_API_KEY 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
  [[ "$OPENROUTER_API_KEY" == "fake-openrouter-key" ]]
)
run_test "TEST-10.2: plaintext files are ignored" test_bash_no_plaintext_file_reads

# ── TEST 10.3: missing nova-op fails loudly ──
test_bash_missing_nova_op_fails() (
  local home
  home=$(make_map t10_3 '{"OPENROUTER_API_KEY":{"vault":"V","item":"i","field":"f"}}')
  local empty_bin="$TMPDIR_BASE/t10_3_empty_bin"
  /bin/mkdir -p "$empty_bin"
  export HOME="$home"
  export PATH="$empty_bin"
  unset OPENROUTER_API_KEY 2>/dev/null || true
  source "$LIB"
  local rc=0
  load_openclaw_env 2>/dev/null || rc=$?
  [[ $rc -ne 0 ]]
)
run_test "TEST-10.3: missing nova-op fails loudly" test_bash_missing_nova_op_fails

# ── TEST 10.4: wrong item ID fails loudly and names item ID ──
test_bash_wrong_item_id_fails() (
  local home
  home=$(make_map t10_4 '{"OPENROUTER_API_KEY":{"vault":"NOVA Shared Vault","item":"wrong-item-id","field":"API Key"}}')
  local bin_dir="$TMPDIR_BASE/t10_4_bin"
  make_nova_op "$bin_dir"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  unset OPENROUTER_API_KEY 2>/dev/null || true
  source "$LIB"
  local stderr_file="$TMPDIR_BASE/stderr_10_4.txt"
  local rc=0
  load_openclaw_env 2>"$stderr_file" || rc=$?
  [[ $rc -ne 0 ]]
  grep -q "wrong-item-id" "$stderr_file"
)
run_test "TEST-10.4: wrong item ID fails loudly and names item ID" test_bash_wrong_item_id_fails

# ── TEST 10.5: empty resolved value fails loudly ──
test_bash_empty_value_fails() (
  local home
  home=$(make_map t10_5 '{"OPENROUTER_API_KEY":{"vault":"V","item":"i","field":"f"}}')
  local bin_dir="$TMPDIR_BASE/t10_5_bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/nova-op" <<'EOF'
#!/usr/bin/env bash
echo ""
EOF
  chmod +x "$bin_dir/nova-op"
  export HOME="$home"
  export PATH="$bin_dir:$PATH"
  unset OPENROUTER_API_KEY 2>/dev/null || true
  source "$LIB"
  local rc=0
  load_openclaw_env 2>/dev/null || rc=$?
  [[ $rc -ne 0 ]]
)
run_test "TEST-10.5: empty resolved value fails loudly" test_bash_empty_value_fails

# ── Summary ──
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed (total $((PASS+FAIL)))"
echo "================================"
[[ $FAIL -eq 0 ]]
