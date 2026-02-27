#!/bin/bash
# test-env-loader.sh — Test runner for lib/env-loader.sh
# Issue: nova-memory #98
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

make_config() {
  local dir="$TMPDIR_BASE/$1"
  mkdir -p "$dir/.openclaw"
  echo "$2" > "$dir/.openclaw/openclaw.json"
  echo "$dir"
}

# Each test runs in a subshell with isolated HOME
run_test() {
  local name="$1"
  shift
  # Run test function in subshell, capture exit code
  if "$@"; then
    pass "$name"
  else
    fail "$name" "test body returned non-zero"
  fi
}

# ── TEST 1.1: loads vars from valid config ──
test_bash_loads_vars_from_valid_config() (
  local home
  home=$(make_config t1_1 '{"env":{"vars":{"FOO":"bar","BAZ":"qux"}}}')
  export HOME="$home"
  unset FOO BAZ 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
  [[ "$FOO" == "bar" && "$BAZ" == "qux" ]]
)
run_test "TEST-1.1: loads vars from valid config" test_bash_loads_vars_from_valid_config

# ── TEST 1.3: return code 0 on success ──
test_bash_return_code_zero() (
  local home
  home=$(make_config t1_3 '{"env":{"vars":{"X1":"val"}}}')
  export HOME="$home"
  unset X1 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
)
run_test "TEST-1.3: return code 0 on success" test_bash_return_code_zero

# ── TEST 2.1: existing env var NOT overwritten ──
test_bash_existing_env_not_overwritten() (
  local home
  home=$(make_config t2_1 '{"env":{"vars":{"FOO":"from_config"}}}')
  export HOME="$home"
  export FOO=original
  source "$LIB"
  load_openclaw_env
  [[ "$FOO" == "original" ]]
)
run_test "TEST-2.1: existing env var NOT overwritten" test_bash_existing_env_not_overwritten

# ── TEST 2.3: empty env var IS overwritten ──
test_bash_empty_env_overwritten() (
  local home
  home=$(make_config t2_3 '{"env":{"vars":{"FOO":"from_config"}}}')
  export HOME="$home"
  export FOO=""
  source "$LIB"
  load_openclaw_env
  [[ "$FOO" == "from_config" ]]
)
run_test "TEST-2.3: empty env var IS overwritten" test_bash_empty_env_overwritten

# ── TEST 3.1: null value skipped ──
test_bash_null_value_skipped() (
  local home
  home=$(make_config t3_1 '{"env":{"vars":{"FOO":null,"BAR":"hello"}}}')
  export HOME="$home"
  unset FOO BAR 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
  [[ -z "${FOO:-}" && "$BAR" == "hello" ]]
)
run_test "TEST-3.1: null value skipped" test_bash_null_value_skipped

# ── TEST 4.1: empty string value skipped ──
test_bash_empty_string_skipped() (
  local home
  home=$(make_config t4_1 '{"env":{"vars":{"FOO":"","BAR":"hello"}}}')
  export HOME="$home"
  unset FOO BAR 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
  [[ -z "${FOO:-}" && "$BAR" == "hello" ]]
)
run_test "TEST-4.1: empty string value skipped" test_bash_empty_string_skipped

# ── TEST 5.1: malformed JSON warns and returns 1 ──
test_bash_malformed_json_warns() (
  local home
  home=$(make_config t5_1 '{not valid json')
  export HOME="$home"
  source "$LIB"
  local stderr_file="$TMPDIR_BASE/stderr_5_1.txt"
  local rc=0
  load_openclaw_env 2>"$stderr_file" || rc=$?
  [[ $rc -eq 1 ]] && grep -q "WARNING: Malformed JSON" "$stderr_file"
)
run_test "TEST-5.1: malformed JSON warns and returns 1" test_bash_malformed_json_warns

# ── TEST 6.1: missing config returns 0 silently ──
test_bash_missing_config_no_error() (
  local home="$TMPDIR_BASE/t6_1_empty"
  mkdir -p "$home"
  export HOME="$home"
  source "$LIB"
  local stderr_file="$TMPDIR_BASE/stderr_6_1.txt"
  load_openclaw_env 2>"$stderr_file"
  local rc=$?
  [[ $rc -eq 0 && ! -s "$stderr_file" ]]
)
run_test "TEST-6.1: missing config returns 0 silently" test_bash_missing_config_no_error

# ── TEST 7.1: unreadable config returns 0 silently ──
test_bash_unreadable_config_silent() (
  local home
  home=$(make_config t7_1 '{"env":{"vars":{"FOO":"bar"}}}')
  chmod 000 "$home/.openclaw/openclaw.json"
  export HOME="$home"
  source "$LIB"
  local stderr_file="$TMPDIR_BASE/stderr_7_1.txt"
  load_openclaw_env 2>"$stderr_file"
  local rc=$?
  chmod 644 "$home/.openclaw/openclaw.json"  # cleanup
  [[ $rc -eq 0 && -z "${FOO:-}" ]]
)
run_test "TEST-7.1: unreadable config returns 0 silently" test_bash_unreadable_config_silent

# ── TEST 8.1: no env section ──
test_bash_no_env_section() (
  local home
  home=$(make_config t8_1 '{"gateway":{"port":3000}}')
  export HOME="$home"
  source "$LIB"
  load_openclaw_env
)
run_test "TEST-8.1: no env section" test_bash_no_env_section

# ── TEST 8.2: env without vars ──
test_bash_env_without_vars() (
  local home
  home=$(make_config t8_2 '{"env":{"model":"gpt-4"}}')
  export HOME="$home"
  source "$LIB"
  load_openclaw_env
)
run_test "TEST-8.2: env without vars" test_bash_env_without_vars

# ── TEST 10.1: special characters in values ──
test_bash_special_chars_in_value() (
  local home
  home=$(make_config t10_1 '{
    "env":{"vars":{
      "SC_SPACE":"hello world",
      "SC_SQUOTE":"it'\''s fine",
      "SC_DQUOTE":"say \"hi\"",
      "SC_BTICK":"run `cmd`",
      "SC_DOLLAR":"costs $100",
      "SC_BSLASH":"path\\to\\file",
      "SC_SHELL":"a && b; c"
    }}
  }')
  export HOME="$home"
  unset SC_SPACE SC_SQUOTE SC_DQUOTE SC_BTICK SC_DOLLAR SC_BSLASH SC_SHELL 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
  local ok=true
  [[ "$SC_SPACE" == "hello world" ]] || { echo "  sub-fail: SC_SPACE='$SC_SPACE'"; ok=false; }
  [[ "$SC_SQUOTE" == "it's fine" ]] || { echo "  sub-fail: SC_SQUOTE='$SC_SQUOTE'"; ok=false; }
  [[ "$SC_DQUOTE" == 'say "hi"' ]] || { echo "  sub-fail: SC_DQUOTE='$SC_DQUOTE'"; ok=false; }
  [[ "$SC_BTICK" == 'run `cmd`' ]] || { echo "  sub-fail: SC_BTICK='$SC_BTICK'"; ok=false; }
  [[ "$SC_DOLLAR" == 'costs $100' ]] || { echo "  sub-fail: SC_DOLLAR='$SC_DOLLAR'"; ok=false; }
  [[ "$SC_BSLASH" == 'path\to\file' ]] || { echo "  sub-fail: SC_BSLASH='$SC_BSLASH'"; ok=false; }
  [[ "$SC_SHELL" == 'a && b; c' ]] || { echo "  sub-fail: SC_SHELL='$SC_SHELL'"; ok=false; }
  $ok
)
run_test "TEST-10.1: special characters in values" test_bash_special_chars_in_value

# ── TEST 10.2: env.vars is a string ──
test_bash_env_vars_not_dict_string() (
  local home
  home=$(make_config t10_2 '{"env":{"vars":"not_a_dict"}}')
  export HOME="$home"
  source "$LIB"
  load_openclaw_env 2>/dev/null
)
run_test "TEST-10.2: env.vars is a string (graceful)" test_bash_env_vars_not_dict_string

# ── TEST 10.3: env.vars is an array ──
test_bash_env_vars_not_dict_array() (
  local home
  home=$(make_config t10_3 '{"env":{"vars":[1,2,3]}}')
  export HOME="$home"
  source "$LIB"
  load_openclaw_env 2>/dev/null
)
run_test "TEST-10.3: env.vars is an array (graceful with type guard)" test_bash_env_vars_not_dict_array

# ── TEST 10.4: idempotent double call ──
test_bash_idempotent_double_call() (
  local home
  home=$(make_config t10_4 '{"env":{"vars":{"FOO":"bar"}}}')
  export HOME="$home"
  unset FOO 2>/dev/null || true
  source "$LIB"
  load_openclaw_env
  load_openclaw_env
  [[ "$FOO" == "bar" ]]
)
run_test "TEST-10.4: idempotent double call" test_bash_idempotent_double_call

# ── Summary ──
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed (total $((PASS+FAIL)))"
echo "================================"
[[ $FAIL -eq 0 ]]
