#!/bin/bash
# MIND-24: verify generate-delegation-context.sh moves to ~/.openclaw/scripts
# and the old workspace copy is removed only when byte-identical.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

install_gdc() {
    local home="$1"
    export HOME="$home"
    local source="$REPO_ROOT/cognition/scripts/generate-delegation-context.sh"
    local target="$home/.openclaw/scripts/generate-delegation-context.sh"
    local old_target="$home/.openclaw/workspace/scripts/generate-delegation-context.sh"

    mkdir -p "$(dirname "$target")"
    cp "$source" "$target"
    chmod +x "$target"

    if [ -f "$old_target" ]; then
        local old_hash new_hash
        old_hash=$(sha256sum "$old_target" | awk '{print $1}')
        new_hash=$(sha256sum "$target" | awk '{print $1}')
        if [ "$old_hash" = "$new_hash" ]; then
            rm -f "$old_target"
        fi
    fi
}

run_test() { if "$@"; then pass "$1"; else fail "$1" "test body returned non-zero"; fi; }

# ── TEST MIND-24a: new install path exists ──
test_new_path_exists() {
    local home="$TMPDIR_BASE/a"
    mkdir -p "$home"
    install_gdc "$home"
    [ -x "$home/.openclaw/scripts/generate-delegation-context.sh" ]
}
run_test test_new_path_exists

# ── TEST MIND-24b: old byte-identical copy removed ──
test_old_identical_removed() {
    local home="$TMPDIR_BASE/b"
    mkdir -p "$home/.openclaw/workspace/scripts"
    cp "$REPO_ROOT/cognition/scripts/generate-delegation-context.sh" "$home/.openclaw/workspace/scripts/generate-delegation-context.sh"
    install_gdc "$home"
    [ -x "$home/.openclaw/scripts/generate-delegation-context.sh" ]
    [ ! -f "$home/.openclaw/workspace/scripts/generate-delegation-context.sh" ]
}
run_test test_old_identical_removed

# ── TEST MIND-24c: old differing copy preserved ──
test_old_differing_preserved() {
    local home="$TMPDIR_BASE/c"
    mkdir -p "$home/.openclaw/workspace/scripts"
    cp "$REPO_ROOT/cognition/scripts/generate-delegation-context.sh" "$home/.openclaw/workspace/scripts/generate-delegation-context.sh"
    echo "# local modification" >> "$home/.openclaw/workspace/scripts/generate-delegation-context.sh"
    install_gdc "$home"
    [ -x "$home/.openclaw/scripts/generate-delegation-context.sh" ]
    [ -f "$home/.openclaw/workspace/scripts/generate-delegation-context.sh" ]
}
run_test test_old_differing_preserved

# ── Summary ──
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed (total $((PASS+FAIL)))"
echo "================================"
[[ $FAIL -eq 0 ]]
