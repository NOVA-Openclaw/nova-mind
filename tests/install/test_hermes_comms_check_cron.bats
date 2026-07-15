#!/usr/bin/env bats
# BATS tests for hermes-comms-check cron installation in agent-install.sh (#474).
#
# Coverage:
#   TC-474-17: exactly one hermes-comms-check cron job is installed
#
# Run: bats tests/install/test_hermes_comms_check_cron.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALLER="$REPO_ROOT/agent-install.sh"

# Inline copy of the installer helper under test. Keep in sync with
# agent-install.sh:_install_hermes_comms_check_cron().
_install_hermes_comms_check_cron() {
    if [ "${NO_CRON:-0}" -eq 1 ]; then
        echo "Hermes comms-check cron installation skipped (--no-cron)"
        HERMES_COMMS_CRON_STATUS="skipped by --no-cron"
        return 0
    fi

    local cron_drift_lines=()
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || true)

    if echo "$current_crontab" | grep -qF "$HERMES_COMMS_CHECK_MARKER"; then
        local line
        while IFS= read -r line; do
            case "$line" in
                *"$HERMES_COMMS_CHECK_MARKER"*)
                    if [ "$line" != "$HERMES_COMMS_CRON_ENTRY" ]; then
                        cron_drift_lines+=("$line")
                    fi
                    ;;
            esac
        done <<< "$current_crontab"

        if [ ${#cron_drift_lines[@]} -gt 0 ]; then
            echo "Existing cron entry for $HERMES_COMMS_CHECK_SCRIPT differs from expected schedule (drift detected):"
            local drift_line
            for drift_line in "${cron_drift_lines[@]}"; do
                echo "    $drift_line"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            HERMES_COMMS_CRON_STATUS="drift detected (review required)"
        elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
            echo "Hermes comms-check cron entry installed"
            HERMES_COMMS_CRON_STATUS="installed"
        else
            echo "Hermes comms-check cron entry verified"
            HERMES_COMMS_CRON_STATUS="verified"
        fi
    elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
        echo "Hermes comms-check cron entry missing"
        HERMES_COMMS_CRON_STATUS="missing"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        (crontab -l 2>/dev/null || true; echo "$HERMES_COMMS_CRON_ENTRY") | crontab -
        echo "Installed Hermes comms-check cron entry (every 4 hours)"
        HERMES_COMMS_CRON_STATUS="installed"
    fi
}

setup() {
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

    HERMES_COMMS_CHECK_SCRIPT="hermes-comms-check.sh"
    HERMES_COMMS_CHECK_MARKER="$HOME/.openclaw/scripts/comms/$HERMES_COMMS_CHECK_SCRIPT"
    HERMES_COMMS_CRON_ENTRY='0 */4 * * * '"$HERMES_COMMS_CHECK_MARKER"' >> '"$HOME/.openclaw/logs"'/hermes-comms-check.log 2>&1'
    VERIFICATION_WARNINGS=0
    VERIFICATION_ERRORS=0
    NO_CRON=0
    VERIFY_ONLY=0
    export HERMES_COMMS_CHECK_SCRIPT HERMES_COMMS_CHECK_MARKER HERMES_COMMS_CRON_ENTRY
    export VERIFICATION_WARNINGS VERIFICATION_ERRORS NO_CRON VERIFY_ONLY
}

teardown() {
    rm -f "$CRONTAB_FILE"
    rm -rf "$MOCK_BIN"
}

@test "TC-474-17: fresh install adds exactly one hermes-comms-check entry" {
    [ ! -s "$CRONTAB_FILE" ]
    run _install_hermes_comms_check_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed Hermes comms-check cron entry"* ]]

    run grep -cF "$HERMES_COMMS_CHECK_MARKER" "$CRONTAB_FILE"
    [ "$output" -eq 1 ]

    grep -qxF "$HERMES_COMMS_CRON_ENTRY" "$CRONTAB_FILE"
    grep -qF "0 */4 * * *" "$CRONTAB_FILE"
}

@test "TC-474-17: idempotent re-run keeps exactly one entry" {
    _install_hermes_comms_check_cron >/dev/null

    run _install_hermes_comms_check_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hermes comms-check cron entry verified"* ]]

    run grep -cF "$HERMES_COMMS_CHECK_MARKER" "$CRONTAB_FILE"
    [ "$output" -eq 1 ]
}

@test "TC-474-17: drift on existing entry emits warning and leaves crontab untouched" {
    echo '0 0 * * * '"$HERMES_COMMS_CHECK_MARKER"' >> /dev/null 2>&1' > "$CRONTAB_FILE"
    local before
    before="$(cat "$CRONTAB_FILE")"

    run _install_hermes_comms_check_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"drift detected"* ]]
    [ "$(cat "$CRONTAB_FILE")" = "$before" ]
}

@test "TC-474-17: --no-cron opt-out skips installation" {
    NO_CRON=1
    export NO_CRON
    run _install_hermes_comms_check_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hermes comms-check cron installation skipped"* ]]
    [ ! -s "$CRONTAB_FILE" ]
}

@test "TC-474-17: --verify-only with cron installed reports installed" {
    VERIFY_ONLY=1
    export VERIFY_ONLY
    printf '%s\n' "$HERMES_COMMS_CRON_ENTRY" > "$CRONTAB_FILE"
    local before
    before="$(cat "$CRONTAB_FILE")"

    run _install_hermes_comms_check_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hermes comms-check cron entry installed"* ]]
    [ "$(cat "$CRONTAB_FILE")" = "$before" ]
}

@test "TC-474-17: --verify-only with empty crontab reports missing" {
    VERIFY_ONLY=1
    export VERIFY_ONLY
    [ ! -s "$CRONTAB_FILE" ]

    run _install_hermes_comms_check_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hermes comms-check cron entry missing"* ]]
    [ ! -s "$CRONTAB_FILE" ]
}

@test "agent-install.sh --help mentions --no-cron option" {
    run bash "$INSTALLER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--no-cron"* ]]
}

@test "TC-474-17: wrapper script exists and is executable" {
    [ -x "$REPO_ROOT/scripts/comms/hermes-comms-check.sh" ]
    run bash -n "$REPO_ROOT/scripts/comms/hermes-comms-check.sh"
    [ "$status" -eq 0 ]
}
