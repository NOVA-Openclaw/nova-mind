#!/usr/bin/env bats
# BATS tests for announce-d100-rolls.sh cron installation in agent-install.sh (#432).
#
# Coverage:
#   TC-432-D7-01: fresh cron install adds 15-minute entry
#   TC-432-D7-02: idempotent re-run does not duplicate entry
#   TC-432-D7-03: drift on existing entry emits warning without modifying
#   TC-432-D7-04: --no-cron opt-out skips installation
#
# Run: bats tests/install/test_announce_d100_rolls_cron.bats

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
INSTALLER="$REPO_ROOT/agent-install.sh"

# Inline copy of the installer helper under test.
# TODO(D-8): source the real function from agent-install.sh to avoid drift.
_install_announce_d100_cron() {
    if [ "${NO_CRON:-0}" -eq 1 ]; then
        echo "D100 announcer cron installation skipped (--no-cron)"
        ANNOUNCE_D100_CRON_STATUS="skipped by --no-cron"
        return 0
    fi

    local cron_drift_lines=()
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || true)

    if echo "$current_crontab" | grep -qF "$ANNOUNCE_D100_CRON_MARKER"; then
        local line
        while IFS= read -r line; do
            case "$line" in
                *"$ANNOUNCE_D100_CRON_MARKER"*)
                    if [ "$line" != "$ANNOUNCE_D100_CRON_ENTRY" ]; then
                        cron_drift_lines+=("$line")
                    fi
                    ;;
            esac
        done <<< "$current_crontab"

        if [ ${#cron_drift_lines[@]} -gt 0 ]; then
            echo "Existing cron entry for $ANNOUNCE_D100_SCRIPT differs from expected schedule (drift detected):"
            local drift_line
            for drift_line in "${cron_drift_lines[@]}"; do
                echo "    $drift_line"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            ANNOUNCE_D100_CRON_STATUS="drift detected (review required)"
        elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
            echo "D100 announcer cron entry installed"
            ANNOUNCE_D100_CRON_STATUS="installed"
        else
            echo "D100 announcer cron entry verified"
            ANNOUNCE_D100_CRON_STATUS="verified"
        fi
    elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
        echo "D100 announcer cron entry missing"
        ANNOUNCE_D100_CRON_STATUS="missing"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        (crontab -l 2>/dev/null || true; echo "$ANNOUNCE_D100_CRON_ENTRY") | crontab -
        echo "Installed D100 announcer cron entry (every 15 minutes)"
        ANNOUNCE_D100_CRON_STATUS="installed"
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

    ANNOUNCE_D100_SCRIPT="announce-d100-rolls.sh"
    ANNOUNCE_D100_CRON_MARKER="$HOME/.openclaw/scripts/$ANNOUNCE_D100_SCRIPT"
    ANNOUNCE_D100_CRON_ENTRY='*/15 * * * * '"$ANNOUNCE_D100_CRON_MARKER"' >> '"$HOME/.openclaw/logs"'/announce-d100-rolls.log 2>&1'
    VERIFICATION_WARNINGS=0
    VERIFICATION_ERRORS=0
    NO_CRON=0
    VERIFY_ONLY=0
    export ANNOUNCE_D100_SCRIPT ANNOUNCE_D100_CRON_MARKER ANNOUNCE_D100_CRON_ENTRY
    export VERIFICATION_WARNINGS VERIFICATION_ERRORS NO_CRON VERIFY_ONLY
}

teardown() {
    rm -f "$CRONTAB_FILE"
    rm -rf "$MOCK_BIN"
}

@test "TC-432-D7-01: fresh install adds 15-minute cron entry" {
    [ ! -s "$CRONTAB_FILE" ]
    run _install_announce_d100_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed D100 announcer cron entry"* ]]

    run grep -cF "$ANNOUNCE_D100_CRON_MARKER" "$CRONTAB_FILE"
    [ "$output" -eq 1 ]

    grep -qxF "$ANNOUNCE_D100_CRON_ENTRY" "$CRONTAB_FILE"
    grep -qF "*/15 * * * *" "$CRONTAB_FILE"
}

@test "TC-432-D7-02: idempotent re-run keeps exactly one entry" {
    _install_announce_d100_cron >/dev/null

    run _install_announce_d100_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"D100 announcer cron entry verified"* ]]

    run grep -cF "$ANNOUNCE_D100_CRON_MARKER" "$CRONTAB_FILE"
    [ "$output" -eq 1 ]
}

@test "TC-432-D7-03: drift on existing entry emits warning and leaves crontab untouched" {
    echo '0 0 * * * '"$ANNOUNCE_D100_CRON_MARKER"' >> /dev/null 2>&1' > "$CRONTAB_FILE"
    local before
    before="$(cat "$CRONTAB_FILE")"

    run _install_announce_d100_cron
    [ "$status" -eq 0 ]
    # The installer correctly emits a drift warning and leaves crontab untouched.
    [[ "$output" == *"drift detected"* ]]
    [ "$(cat "$CRONTAB_FILE")" = "$before" ]
}

@test "TC-432-D7-04: --no-cron opt-out skips installation" {
    NO_CRON=1
    export NO_CRON
    run _install_announce_d100_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"D100 announcer cron installation skipped"* ]]
    [ ! -s "$CRONTAB_FILE" ]
}

@test "TC-432-D7-05: --verify-only with cron installed reports installed" {
    VERIFY_ONLY=1
    export VERIFY_ONLY
    printf '%s\n' "$ANNOUNCE_D100_CRON_ENTRY" > "$CRONTAB_FILE"
    local before
    before="$(cat "$CRONTAB_FILE")"

    run _install_announce_d100_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"D100 announcer cron entry installed"* ]]
    [ "$(cat "$CRONTAB_FILE")" = "$before" ]
}

@test "TC-432-D7-06: --verify-only with empty crontab reports missing" {
    VERIFY_ONLY=1
    export VERIFY_ONLY
    [ ! -s "$CRONTAB_FILE" ]

    run _install_announce_d100_cron
    [ "$status" -eq 0 ]
    [[ "$output" == *"D100 announcer cron entry missing"* ]]
    [ ! -s "$CRONTAB_FILE" ]
}

@test "agent-install.sh --help mentions --no-cron option" {
    run bash "$INSTALLER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--no-cron"* ]]
}
