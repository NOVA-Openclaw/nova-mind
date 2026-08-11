#!/usr/bin/env bash
# Optional agent_chat message-bus peer detection for the nova-mind installer.
# Sourced by agent-install.sh. Does not run standalone.
#
# Implements nova-mind#579: nova-mind no longer owns the agent_chat schema,
# migrations, or plugin. If a dedicated agent_chat bus is present on the host,
# the installer optionally delegates registration/plugin setup to the
# NOVA-Openclaw/agent-chat repo checkout.

# Schema-version handshake constant. Bump when nova-mind requires a newer
# agent_chat schema than the one currently installed.
KNOWN_COMPATIBLE_AGENT_CHAT_SCHEMA_VERSION=1

# Resolve the agent-chat repo checkout path.
_agent_chat_repo_path() {
    printf '%s' "${AGENT_CHAT_REPO:-$HOME/agent-chat}"
}

# Detect whether an agent_chat bus is present.
# Prints one of: present | absent | unreachable
# Uses only jq -e projections against postgres.json (never prints values) and
# a read-only psql probe against the literal database name "agent_chat" using
# the memory-DB connection params already loaded by agent-install.sh.
_agent_chat_detect_bus() {
    local pg_config="${1:-${PG_CONFIG:-$HOME/.openclaw/postgres.json}}"
    local configured=0

    if [ -f "$pg_config" ] && command -v jq &>/dev/null; then
        if jq -e '.agent_chat' "$pg_config" >/dev/null 2>&1; then
            configured=1
        fi
    fi

    # Probe reachability using the memory-DB connection params (PGHOST/PGPORT/PGUSER).
    if psql -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -U "${PGUSER:-$(whoami)}" -d "agent_chat" -c '\q' >/dev/null 2>&1; then
        echo "present"
        return 0
    fi

    if [ "$configured" -eq 1 ]; then
        echo "unreachable"
        return 2
    fi
    echo "absent"
    return 1
}

# Read the max schema_version from the bus DB (read-only probe).
_agent_chat_schema_version() {
    psql -h "${PGHOST:-localhost}" -p "${PGPORT:-5432}" -U "${PGUSER:-$(whoami)}" -d "agent_chat" -At -c "SELECT COALESCE(MAX(version), 0) FROM schema_version" 2>/dev/null || echo ""
}

# Register the current agent with the bus and install the OpenClaw plugin.
# All failures are warnings; the overall nova-mind install continues.
_agent_chat_register_peer() {
    local repo_path="$1"
    local agent_name="$2"

    local reg_script="$repo_path/register-agent.sh"
    local plugin_script="$repo_path/install-plugin.sh"

    if [ ! -f "$reg_script" ] || [ ! -f "$plugin_script" ]; then
        echo -e "${WARNING} agent-chat repo checkout not found at ${repo_path}; registration skipped. Set AGENT_CHAT_REPO or clone https://github.com/NOVA-Openclaw/agent-chat" >&2
        return 0
    fi

    echo "  Registering agent on agent_chat bus..."
    if ! bash "$reg_script" "$agent_name"; then
        echo -e "  ${WARNING} agent_chat registration failed for ${agent_name}" >&2
        return 0
    fi

    echo "  Installing agent_chat plugin..."
    if ! bash "$plugin_script" --agent-name "$agent_name"; then
        echo -e "  ${WARNING} agent_chat plugin installation failed" >&2
        return 0
    fi

    local installed_version
    installed_version=$(_agent_chat_schema_version)
    case "$installed_version" in
        ''|*[!0-9]*)
            # schema_version table missing or non-numeric — no handshake possible.
            ;;
        *)
            if [ "$installed_version" -ne "$KNOWN_COMPATIBLE_AGENT_CHAT_SCHEMA_VERSION" ]; then
                echo -e "  ${WARNING} agent_chat bus schema version ${installed_version} may be incompatible (expected ${KNOWN_COMPATIBLE_AGENT_CHAT_SCHEMA_VERSION})" >&2
            fi
            ;;
    esac
}

# Main entry point called by agent-install.sh.
_agent_chat_integrate_peer() {
    local pg_config="${PG_CONFIG:-$HOME/.openclaw/postgres.json}"

    echo ""
    echo "agent_chat bus (optional peer detection)..."

    local status
    status=$(_agent_chat_detect_bus "$pg_config")

    case "$status" in
        absent)
            echo -e "  ${INFO} agent_chat bus not detected; skipping optional peer integration"
            return 0
            ;;
        unreachable)
            echo -e "  ${WARNING} agent_chat bus is configured but unreachable; skipping registration" >&2
            return 0
            ;;
    esac

    local repo_path
    repo_path=$(_agent_chat_repo_path)
    _agent_chat_register_peer "$repo_path" "$DB_USER"
}
