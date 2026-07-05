#!/usr/bin/env bats
# BATS tests for generate-daily-log.py cron installation in agent-install.sh (#397).
#
# Coverage:
#   TC-041: fresh cron install adds nightly + intraday entries
#   TC-042: idempotent re-run does not duplicate entries
#   TC-043: drift on existing entry emits warning without modifying
#   TC-051: --no-cron opt-out skips installation
#
# Run: bats tests/install/test_generate_daily_log_cron.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALLER="$REPO_ROOT/agent-install.sh"

# Inline copy of the installer helper under test. Keep in sync with
# agent-install.sh:_install_daily_log_cron().
_install_daily_log_cron() {
    if [ "${NO_CRON:-0}" -eq 1 ]; then
        echo "Cron installation skipped (--no-cron)"
        DAILY_LOG_CRON_STATUS="skipped by --no-cron"
        return 0
    fi

    local cron_drift_lines=()
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || true)

    if echo "$current_crontab" | grep -qF "$DAILY_LOG_CRON_MARKER"; then
        local line
        while IFS= read -r line; do
            case "$line" in
                *"$DAILY_LOG_CRON_MARKER"*)
                    if [ "$line" != "$DAILY_LOG_CRON_NIGHTLY" ] && [ "$line" != "$DAILY_LOG_CRON_INTRADAY" ]; then
                        cron_drift_lines+=("$line")
                    fi
                    ;;
            esac
        done <<< "$current_crontab"

        if [ ${#cron_drift_lines[@]} -gt 0 ]; then
            echo "Existing cron entry for $DAILY_LOG_SCRIPT differs from expected schedule (drift detected):"
            local drift_line
            for drift_line in "${cron_drift_lines[@]}"; do
                echo "    $drift_line"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            DAILY_LOG_CRON_STATUS="drift detected (review required)"
        elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
            echo "Daily memory log cron entries installed"
            DAILY_LOG_CRON_STATUS="installed"
        else
            echo "Daily memory log cron entries verified"
            DAILY_LOG_CRON_STATUS="verified"
        fi
    elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
        echo "Daily memory log cron entries missing"
        DAILY_LOG_CRON_STATUS="missing"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        (crontab -l 2>/dev/null || true; echo "$DAILY_LOG_CRON_NIGHTLY"; echo "$DAILY_LOG_CRON_INTRADAY") | crontab -
        echo "Installed daily memory log cron entries (nightly + intraday)"
        DAILY_LOG_CRON_STATUS="installed"
    fi
}

setup() {
    # Isolate crontab state in a temp file and provide a mock crontab command.
    CRONTAB_FILE="$(mktemp)"
    export CRONTAB_FILE
    MOCK_BIN="$(mktemp -d)"
    export MOCK_BIN

    cat >"$MOCK_BIN/crontab" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-l" ]; then
    cat "$CRONTAB_FILE" 2>/dev/null || true
elif [ "$1" = "-" ]; then
    cat > "$CRONTAB_FILE"
else
    echo "mock crontab: unsupported args: $*" >&2
    exit 1
fi
SCRIPT
    chmod +x "$MOCK_BIN/crontab"
    PATH="$MOCK_BIN:$PATH"
    export PATH

    # Common cron variables used by the helper.
    DAILY_LOG_SCRIPT="generate-daily-log.py"
    DAILY_LOG_CRON_MARKER="$HOME/.openclaw/scripts/$DAILY_LOG_SCRIPT"
    DAILY_LOG_CRON_NIGHTLY='5 0 * * *    '"$DAILY_LOG_CRON_MARKER"' >> '"$HOME/.openclaw/logs"'/generate-daily-log.log 2>&1'
    DAILY_LOG_CRON_INTRADAY='0 6,12,18 * * * '"$DAILY_LOG_CRON_MARKER"' >> '"$HOME/.openclaw/logs"'/generate-daily-log.log 2>&1'
    VERIFICATION_WARNINGS=0
    NO_CRON=0
    VERIFY_ONLY=0
    export DAILY_LOG_SCRIPT DAILY_LOG_CRON_MARKER DAILY_LOG_CRON_NIGHTLY DAILY_LOG_CRON_INTRADAY
    export VERIFICATION_WARNINGS NO_CRON VERIFY_ONLY
}

teardown() {
    rm -f "$CRONTAB_FILE"
    rm -rf "$MOCK_BIN"
}

@test "TC-041: fresh install adds nightly and intraday entries" {
    [ ! -s "$CRONTAB_FILE" ]
    run _install_daily_log_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed daily memory log cron entries"* ]]

    run grep -cF "$DAILY_LOG_CRON_MARKER" "$CRONTAB_FILE"
    [ "$output" -eq 2 ]

    grep -qxF "$DAILY_LOG_CRON_NIGHTLY" "$CRONTAB_FILE"
    grep -qxF "$DAILY_LOG_CRON_INTRADAY" "$CRONTAB_FILE"
}

@test "TC-042: idempotent re-run keeps exactly one copy of each entry" {
    _install_daily_log_cron >/dev/null

    run _install_daily_log_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Daily memory log cron entries verified"* ]]

    run grep -cF "$DAILY_LOG_CRON_MARKER" "$CRONTAB_FILE"
    [ "$output" -eq 2 ]
}

@test "TC-043: drift on existing entry emits warning and leaves crontab untouched" {
    # Seed a crontab with a line referencing the script but wrong schedule.
    echo '0 0 * * * '"$DAILY_LOG_CRON_MARKER"' >> /dev/null 2>&1' > "$CRONTAB_FILE"
    local before
    before="$(cat "$CRONTAB_FILE")"

    run _install_daily_log_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"drift detected"* ]]

    # Crontab must remain unchanged.
    [ "$(cat "$CRONTAB_FILE")" = "$before" ]
}

@test "TC-051: --no-cron opt-out skips installation and reports status" {
    NO_CRON=1
    export NO_CRON
    run _install_daily_log_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cron installation skipped (--no-cron)"* ]]
    [ ! -s "$CRONTAB_FILE" ]
}

@test "TC-052: --verify-only with cron installed reports installed and does not modify crontab" {
    VERIFY_ONLY=1
    export VERIFY_ONLY

    # Seed expected cron entries.
    printf '%s\n%s\n' "$DAILY_LOG_CRON_NIGHTLY" "$DAILY_LOG_CRON_INTRADAY" > "$CRONTAB_FILE"
    local before
    before="$(cat "$CRONTAB_FILE")"

    run _install_daily_log_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Daily memory log cron entries installed"* ]]
    [ "$(cat "$CRONTAB_FILE")" = "$before" ]
}

@test "TC-053: --verify-only with empty crontab reports missing and does not modify crontab" {
    VERIFY_ONLY=1
    export VERIFY_ONLY

    [ ! -s "$CRONTAB_FILE" ]
    run _install_daily_log_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Daily memory log cron entries missing"* ]]
    [ ! -s "$CRONTAB_FILE" ]
}

@test "TC-054: --verify-only with drifted schedule reports drifted and does not modify crontab" {
    VERIFY_ONLY=1
    export VERIFY_ONLY

    # Seed a crontab with a line referencing the script but wrong schedule.
    echo '0 0 * * * '"$DAILY_LOG_CRON_MARKER"' >> /dev/null 2>&1' > "$CRONTAB_FILE"
    local before
    before="$(cat "$CRONTAB_FILE")"

    run _install_daily_log_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"drift detected"* ]]
    [ "$(cat "$CRONTAB_FILE")" = "$before" ]
}

@test "agent-install.sh --help mentions --no-cron option" {
    run bash "$INSTALLER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--no-cron"* ]]
}
