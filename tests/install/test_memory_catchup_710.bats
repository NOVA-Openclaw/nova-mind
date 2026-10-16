#!/usr/bin/env bats
# BATS tests for nova-mind #710: retire JSONL ingest and remove OpenClaw
# session-file / SQLite readers from the repo.
#
# Run: bats tests/install/test_memory_catchup_710.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
CATCHUP_SCRIPT="$REPO_ROOT/memory/scripts/memory-catchup.sh"

# ─── helpers ────────────────────────────────────────────────────────────────

@test "TC-710-001: memory-catchup.sh JSONL ingest block is completely removed" {
    # The exact ingest header and the variable names tied to it must be gone.
    run grep -E 'Ingest JSONL session files|ALL_SESSIONS_DIR|INGEST_COUNT|INGEST_ERRORS' "$CATCHUP_SCRIPT"
    [ "$status" -ne 0 ]
    [ -z "$output" ]

    # The find/rm pair that discovered and deleted JSONL files must also be gone.
    run grep -E 'find.*sessions.*\.jsonl|rm -f.*jsonl_file' "$CATCHUP_SCRIPT"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "TC-710-002: nothing in nova-mind reads OpenClaw agent SQLite" {
    run grep -rlnE 'sqlite3|better-sqlite3|\.sqlite' "$REPO_ROOT" \
        --include='*.sh' --include='*.py' --include='*.ts' --include='*.js' --include='*.json'
    # Filter out documentation / test-case design files that mention sqlite
    # conceptually but are not live code paths.
    # Also exclude source_anchor.py and its test: they contain legacy-anchor
    # *detection* regexes (e.g. '\.sqlite') and matching test fixtures used
    # to flag broken embeddings, not a live SQLite reader. Genuine readers
    # are still caught.
    # motivation/tests/test_proactive_gate_check.py contains '/tmp/openclaw/sessions.sqlite'
    # only as a mock-fixture string inside tests for the proactive gate, not as a live reader.
    hits="$(echo "$output" | grep -v 'tests/TEST-CASES' | grep -v 'node_modules' | grep -v 'memory/lib/source_anchor.py' | grep -v 'memory/tests/test_source_anchor_coverage.py' | grep -v 'motivation/tests/test_proactive_gate_check.py' || true)"
    [ -z "$hits" ]
}

@test "TC-710-003: nothing in nova-mind deletes from OpenClaw session files or agent SQLite" {
    # Match rm -f/rm -rf/unlink/os.remove/fs.unlink inside code that touches
    # OpenClaw session paths or jsonl/sqlite files.
    run grep -rlnE 'rm -f.*sessions|rm -rf.*sessions|rm -f.*\.jsonl|rm -rf.*\.jsonl|rm -f.*\.sqlite|rm -rf.*\.sqlite|os\.remove|fs\.unlink' "$REPO_ROOT" \
        --include='*.sh' --include='*.py' --include='*.ts' --include='*.js'
    # Test files may delete their own temp fixtures; we only care about
    # production code paths that delete OpenClaw session/SQLite files.
    hits="$(echo "$output" | grep -v 'tests/TEST-CASES' | grep -v 'node_modules' | grep -vE '\.(test|spec)\.(ts|js)$' | grep -v 'test-handler\.js' || true)"
    [ -z "$hits" ]
}

@test "TC-710-005: inventory confirms no sessions/*.jsonl readers remain in code" {
    run grep -rlnE 'sessions/\*\.jsonl|\.openclaw/agents.*\.jsonl|\.openclaw/agents.*sessions\.json|find.*sessions.*jsonl' "$REPO_ROOT" \
        --include='*.sh' --include='*.py' --include='*.ts' --include='*.js' --include='*.json'
    # Exclude source_anchor.py and its test: their legacy-anchor detection
    # regexes / docstrings / test fixtures mention OpenClaw session paths,
    # but they do not read them. This keeps the test focused on genuine
    # file readers.
    hits="$(echo "$output" | grep -v 'tests/TEST-CASES' | grep -v 'node_modules' | grep -v 'memory/lib/source_anchor.py' | grep -v 'memory/tests/test_source_anchor_coverage.py' || true)"
    [ -z "$hits" ]
}

@test "TC-710-007: memory-catchup.sh no longer hardcodes agents/main/sessions" {
    run grep -E 'agents/main/sessions' "$CATCHUP_SCRIPT"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "TC-710-SHELLCHECK: memory-catchup.sh passes shellcheck" {
    if ! command -v shellcheck &>/dev/null; then
        skip "shellcheck not installed"
    fi
    run shellcheck "$CATCHUP_SCRIPT"
    [ "$status" -eq 0 ]
}
