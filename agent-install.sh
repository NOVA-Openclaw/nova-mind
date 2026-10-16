#!/usr/bin/env bash
# nova-mind unified agent installer
# Combines: relationships, memory, cognition
# Idempotent — safe to run multiple times

set -euo pipefail

VERSION="2.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================
# SECTION 1: Color codes and status indicators
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CHECK_MARK="${GREEN}✅${NC}"
CROSS_MARK="${RED}❌${NC}"
WARNING="${YELLOW}⚠️${NC}"
INFO="${BLUE}ℹ️${NC}"

# Verification results
# shellcheck disable=SC2034
VERIFICATION_PASSED=0
VERIFICATION_WARNINGS=0
VERIFICATION_ERRORS=0

# Cron install status tracking
# shellcheck disable=SC2034
ANNOUNCE_D100_CRON_STATUS="not installed"
# shellcheck disable=SC2034
HERMES_COMMS_CRON_STATUS="not installed"
# shellcheck disable=SC2034
COMPLETION_LOG_RECONCILE_CRON_STATUS="not installed"

# Track if gateway restart is needed
# shellcheck disable=SC2034
GATEWAY_RESTART_NEEDED=0

# Temp file/directory cleanup
TMPFILES=()
TMPDIRS=()
cleanup_tmp() { rm -f "${TMPFILES[@]}"; rm -rf "${TMPDIRS[@]}"; }
trap cleanup_tmp EXIT

# Helper: install the memory-extract plugin.  Builds in the source tree,
# copies dist/ to the target, installs only runtime dependencies (#598/#724),
# and enables the plugin in OpenClaw config.
_install_memory_extract_plugin() {
    local MEMORY_EXTRACT_SOURCE="${1:-$SCRIPT_DIR/memory/plugins/memory-extract}"
    local MEMORY_EXTRACT_TARGET="${2:-$EXTENSIONS_DIR/memory-extract}"
    local cfg="${OPENCLAW_CONFIG:-$OPENCLAW_DIR/openclaw.json}"

    if [ ! -d "$MEMORY_EXTRACT_SOURCE" ]; then
        echo -e "  ${CROSS_MARK} memory-extract plugin source not found at $MEMORY_EXTRACT_SOURCE"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi

    mkdir -p "$MEMORY_EXTRACT_TARGET/dist"

    # Copy source and config files
    for f in package.json package-lock.json openclaw.plugin.json tsconfig.json; do
        if [ -f "$MEMORY_EXTRACT_SOURCE/$f" ]; then
            cp "$MEMORY_EXTRACT_SOURCE/$f" "$MEMORY_EXTRACT_TARGET/$f"
        fi
    done
    echo -e "  ${CHECK_MARK} memory-extract plugin config files copied"

    # Build TypeScript in the source directory so the target only receives
    # runtime dependencies (#598, #724).
    if [ -d "$MEMORY_EXTRACT_SOURCE/src" ]; then
        _install_plugin_build_dependencies "$MEMORY_EXTRACT_SOURCE" "memory-extract" || return 1

        echo "  Building memory-extract TypeScript..."
        local BUILD_LOG
        BUILD_LOG=$(mktemp /tmp/memory-extract-build-XXXXXX.log)
        TMPFILES+=("$BUILD_LOG")
        if (cd "$MEMORY_EXTRACT_SOURCE" && "$MEMORY_EXTRACT_SOURCE/node_modules/.bin/tsc") >"$BUILD_LOG" 2>&1; then
            cp -r "$MEMORY_EXTRACT_SOURCE/dist/"* "$MEMORY_EXTRACT_TARGET/dist/"
            echo -e "  ${CHECK_MARK} memory-extract plugin built"
            rm -f "$BUILD_LOG"
        else
            echo -e "  ${CROSS_MARK} memory-extract plugin build failed"
            tail -10 "$BUILD_LOG"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
            cd "$SCRIPT_DIR"
            return 1
        fi
    fi

    # Install runtime dependencies in the target directory (#598)
    _install_runtime_dependencies "$MEMORY_EXTRACT_TARGET" "memory-extract" || return 1
    cd "$SCRIPT_DIR"

    # Enable plugin in openclaw.json. Do this BEFORE removing the legacy hook
    # directory or config entries so a failure here cannot leave the system
    # with zero memory-extract (#1231).
    if [ -f "$cfg" ] && command -v jq &>/dev/null; then
        local cfg_tmp
        cfg_tmp=$(mktemp "${cfg}.tmp.XXXXXX")
        TMPFILES+=("$cfg_tmp")

        if jq --arg path "$MEMORY_EXTRACT_TARGET" '
            .plugins.load.paths = ((.plugins.load.paths // []) + [$path] | unique)
            | .plugins.entries."memory-extract" = (.plugins.entries."memory-extract" // {}) * {
                "enabled": true,
                "hooks": {
                  "allowConversationAccess": true
                }
              }
        ' "$cfg" >"$cfg_tmp" && \
            jq -e '(.plugins.entries."memory-extract".enabled == true) and ((.plugins.load.paths // []) | index($path) != null)' --arg path "$MEMORY_EXTRACT_TARGET" "$cfg_tmp" >/dev/null 2>&1 && \
            mv "$cfg_tmp" "$cfg"; then
            echo -e "  ${CHECK_MARK} memory-extract plugin enabled in OpenClaw config"
        else
            echo -e "  ${CROSS_MARK} Could not enable memory-extract plugin in config"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
            rm -f "$cfg_tmp"
            return 1
        fi

        # Remove the legacy internal hook config entry if present. The r4
        # installer and the restored staging config both use
        # .hooks.internal.entries["memory-extract"].enabled. Delete the whole
        # object, but only after the plugin entry has been verified (#1231).
        if jq -e '.hooks.internal.entries["memory-extract"]' "$cfg" &>/dev/null; then
            if jq 'del(.hooks.internal.entries["memory-extract"])' "$cfg" >"$cfg_tmp" && mv "$cfg_tmp" "$cfg"; then
                echo -e "  ${CHECK_MARK} Removed memory-extract hook entry from config"
            else
                echo -e "  ${CROSS_MARK} Could not remove memory-extract hook entry from config"
                VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
                rm -f "$cfg_tmp"
                return 1
            fi
        fi
        rm -f "$cfg_tmp"
    fi

    # Remove legacy memory-extract hook directory ONLY after the plugin config
    # edit has been verified (#1231).
    if [ -d "$OPENCLAW_DIR/hooks/memory-extract" ]; then
        rm -rf "$OPENCLAW_DIR/hooks/memory-extract"
        echo -e "  ${CHECK_MARK} Removed legacy memory-extract hook directory"
    fi

    # Verify installation
    if [ -f "$MEMORY_EXTRACT_TARGET/dist/index.js" ] && [ -f "$MEMORY_EXTRACT_TARGET/openclaw.plugin.json" ]; then
        echo -e "  ${CHECK_MARK} memory-extract plugin installed to $MEMORY_EXTRACT_TARGET"
    else
        echo -e "  ${CROSS_MARK} memory-extract plugin installation incomplete"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi
}

# Helper: install the turn-context plugin's TypeScript build dependency.
# Captures npm output so a peer-dependency failure is visible instead of
# swallowed by >/dev/null 2>&1.  Exits non-zero on failure (#722).
_install_turn_context_typescript_deps() {
    local target_dir="$1"
    local npm_log
    npm_log=$(mktemp /tmp/agent-install-npm-XXXXXX.log)
    TMPFILES+=("$npm_log")

    echo "  Installing build dependencies..."
    if (cd "$target_dir" && npm install --save-dev --legacy-peer-deps typescript) >"$npm_log" 2>&1; then
        return 0
    fi

    echo -e "  ${CROSS_MARK} Failed to install TypeScript build dependencies"
    echo "  npm output:"
    sed 's/^/    /' "$npm_log" >&2
    echo "  Hint: the installer already uses --legacy-peer-deps." >&2
    echo "        Check the npm output above for the underlying cause." >&2
    return 1
}

# Helper: install only runtime npm dependencies for a deployed plugin or
# extension.  Uses npm ci --omit=dev when a lockfile is present, falling back
# to npm install --omit=dev otherwise.  Output is captured so a dependency
# resolution failure is visible instead of swallowed.  Exits non-zero on
# failure (see #598 and #722).
_install_runtime_dependencies() {
    local target_dir="$1"
    local label="$2"
    local npm_log
    npm_log=$(mktemp /tmp/agent-install-runtime-deps-XXXXXX.log)
    TMPFILES+=("$npm_log")

    # Idempotency: skip when the installed tree already satisfies the lockfile.
    if [ "${FORCE_INSTALL:-0}" -eq 0 ] && \
       [ -d "$target_dir/node_modules" ] && \
       [ -f "$target_dir/package-lock.json" ] && \
       [ "$target_dir/node_modules" -nt "$target_dir/package-lock.json" ]; then
        echo -e "  ${CHECK_MARK} $label runtime dependencies already installed (use --force to reinstall)"
        return 0
    fi

    echo "  Installing $label runtime dependencies..."
    if [ -f "$target_dir/package-lock.json" ]; then
        if (cd "$target_dir" && npm ci --omit=dev --legacy-peer-deps) >"$npm_log" 2>&1; then
            echo -e "  ${CHECK_MARK} $label runtime dependencies installed"
            return 0
        fi
    else
        if (cd "$target_dir" && npm install --omit=dev --legacy-peer-deps) >"$npm_log" 2>&1; then
            echo -e "  ${CHECK_MARK} $label runtime dependencies installed"
            return 0
        fi
    fi

    echo -e "  ${CROSS_MARK} Failed to install $label runtime dependencies"
    echo "  npm output:"
    sed 's/^/    /' "$npm_log" >&2
    echo "  Hint: the installer already uses --legacy-peer-deps." >&2
    echo "        Check the npm output above for the underlying cause." >&2
    return 1
}

# Helper: install build dependencies (devDependencies) for a plugin in its
# source directory.  We build in the source tree and then copy dist/ to the
# deployed target so that the target only contains runtime dependencies (#598,
# #724).
_install_plugin_build_dependencies() {
    local source_dir="$1"
    local label="$2"
    local npm_log
    npm_log=$(mktemp /tmp/agent-install-build-deps-XXXXXX.log)
    TMPFILES+=("$npm_log")

    # Idempotency: skip when the installed tree already satisfies the lockfile.
    if [ "${FORCE_INSTALL:-0}" -eq 0 ] && \
       [ -d "$source_dir/node_modules" ] && \
       [ -f "$source_dir/package-lock.json" ] && \
       [ "$source_dir/node_modules" -nt "$source_dir/package-lock.json" ]; then
        echo -e "  ${CHECK_MARK} $label build dependencies already installed (use --force to reinstall)"
        return 0
    fi

    echo "  Installing $label build dependencies..."
    if [ -f "$source_dir/package-lock.json" ]; then
        if (cd "$source_dir" && npm ci --legacy-peer-deps) >"$npm_log" 2>&1; then
            echo -e "  ${CHECK_MARK} $label build dependencies installed"
            return 0
        fi
    else
        if (cd "$source_dir" && npm install --legacy-peer-deps) >"$npm_log" 2>&1; then
            echo -e "  ${CHECK_MARK} $label build dependencies installed"
            return 0
        fi
    fi

    echo -e "  ${CROSS_MARK} Failed to install $label build dependencies"
    echo "  npm output:"
    sed 's/^/    /' "$npm_log" >&2
    echo "  Hint: the installer already uses --legacy-peer-deps." >&2
    echo "        Check the npm output above for the underlying cause." >&2
    return 1
}

# Helper: install the turn-context plugin.  Accepts optional source and
# target directories so bats tests can run the install section into a
# scratch HOME (#598).
_install_turn_context_plugin() {
    local TURN_CONTEXT_SOURCE="${1:-$SCRIPT_DIR/memory/plugins/turn-context}"
    local TURN_CONTEXT_TARGET="${2:-$OPENCLAW_DIR/plugins/turn-context}"

    if [ ! -d "$TURN_CONTEXT_SOURCE" ]; then
        echo -e "  ${CROSS_MARK} turn-context plugin source not found at $TURN_CONTEXT_SOURCE"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi

    mkdir -p "$TURN_CONTEXT_TARGET/dist"

    # Copy source and config files
    for f in package.json package-lock.json openclaw.plugin.json tsconfig.json; do
        if [ -f "$TURN_CONTEXT_SOURCE/$f" ]; then
            cp "$TURN_CONTEXT_SOURCE/$f" "$TURN_CONTEXT_TARGET/$f"
        fi
    done
    echo -e "  ${CHECK_MARK} Plugin config files copied"

    # Install runtime dependencies in the target directory (#598)
    _install_runtime_dependencies "$TURN_CONTEXT_TARGET" "turn-context" || return 1

    # Build TypeScript if source exists
    if [ -d "$TURN_CONTEXT_SOURCE/src" ]; then
        local NEEDS_BUILD=0
        if [ -f "$TURN_CONTEXT_TARGET/dist/index.js" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
            # Check if source is newer than dist
            local NEWEST_SRC
            NEWEST_SRC=$(find "$TURN_CONTEXT_SOURCE/src" -name '*.ts' -newer "$TURN_CONTEXT_TARGET/dist/index.js" 2>/dev/null | head -1)
            if [ -z "$NEWEST_SRC" ]; then
                echo -e "  ${CHECK_MARK} Plugin dist is up to date (use --force to rebuild)"
            else
                echo "  Source changed, rebuilding..."
                NEEDS_BUILD=1
            fi
        else
            NEEDS_BUILD=1
        fi

        if [ "$NEEDS_BUILD" -eq 1 ]; then
            # Ensure typescript is available
            if [ ! -d "$TURN_CONTEXT_SOURCE/node_modules/typescript" ]; then
                _install_turn_context_typescript_deps "$TURN_CONTEXT_SOURCE" || return 1
            fi
            echo "  Building turn-context plugin..."
            local BUILD_LOG
            BUILD_LOG=$(mktemp /tmp/turn-context-build-XXXXXX.log)
            TMPFILES+=("$BUILD_LOG")
            if (cd "$TURN_CONTEXT_SOURCE" && "$TURN_CONTEXT_SOURCE/node_modules/.bin/tsc") >"$BUILD_LOG" 2>&1; then
                # Copy built dist to target
                cp -r "$TURN_CONTEXT_SOURCE/dist/"* "$TURN_CONTEXT_TARGET/dist/"
                echo -e "  ${CHECK_MARK} Plugin built and installed"
            else
                echo -e "  ${CROSS_MARK} Plugin build failed"
                tail -10 "$BUILD_LOG"
                VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
                return 1
            fi
        fi
    fi

    # Enable in OpenClaw config
    if [ -f "${OPENCLAW_CONFIG:-}" ] && command -v jq &>/dev/null; then
        local PLUGIN_PATH
        PLUGIN_PATH="$TURN_CONTEXT_TARGET"
        jq --arg path "$PLUGIN_PATH" '
            .plugins.load.paths = ((.plugins.load.paths // []) + [$path] | unique)
            | .plugins.entries."turn-context" = (.plugins.entries."turn-context" // {}) * {
                "enabled": true,
                "hooks": {
                  "allowConversationAccess": true
                }
              }
        ' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
            mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
            echo -e "  ${CHECK_MARK} Plugin enabled in OpenClaw config" || \
            echo -e "  ${WARNING} Could not enable plugin in config"
    fi

    # Verify installation
    if [ -f "$TURN_CONTEXT_TARGET/dist/index.js" ] && [ -f "$TURN_CONTEXT_TARGET/openclaw.plugin.json" ]; then
        echo -e "  ${CHECK_MARK} turn-context plugin installed to $TURN_CONTEXT_TARGET"
    else
        echo -e "  ${CROSS_MARK} turn-context plugin installation incomplete"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi
}

# Helper: keep gateway.reload.mode valid for OpenClaw 2026.9.x.
# Valid values are "off" and "hybrid"; never overwrite an existing valid
# value, and never write the obsolete "hot" value (#723).
_configure_gateway_reload_mode() {
    local config_file="$1"
    local existing_mode
    existing_mode=$(jq -r '.gateway.reload.mode // empty' "$config_file" 2>/dev/null || true)

    if [ "$existing_mode" = "off" ] || [ "$existing_mode" = "hybrid" ]; then
        echo -e "  ${CHECK_MARK} gateway.reload.mode = \"$existing_mode\" (valid, left unchanged)"
        return 0
    fi

    jq '.gateway.reload.mode = "hybrid"' "$config_file" >"$config_file.tmp" && \
        mv "$config_file.tmp" "$config_file" && \
        echo -e "  ${CHECK_MARK} Set gateway.reload.mode = \"hybrid\"" || \
        echo -e "  ${WARNING} Could not set gateway.reload.mode"
}

# Helper: convert a pre-#707 agents.json array into the OpenClaw 2026.9.x
# keyed object shape.  Each element must have an .id field; the id becomes
# the object key and is removed from the value.
_convert_legacy_agents_array() {
    local input_file="$1"
    local output_file="$2"
    jq '
        if type != "array" then error("not an array") else
            map(select(.id != null))
            | map({ key: .id, value: del(.id) })
            | sort_by(.key)
            | from_entries
        end
    ' "$input_file" >"$output_file" 2>/dev/null
}

# Helper: timestamped backup of agents.json with mode 600.
_backup_agents_json() {
    local src="$1"
    local bak
    bak="${src}.bak-$(date +%Y%m%d-%H%M%S)"
    if cp "$src" "$bak" && chmod 600 "$bak"; then
        printf '%s\n' "$bak"
    fi
}

# Helper: generate agents.json from DB into $AGENTS_JSON.
# Output matches the agent_config_sync plugin's JSON.stringify(data, null, 2) + "\n".
_generate_agents_json() {
    # Query get_agent_export_rows(), which scopes results to the connecting
    # role (own row + subagents that list session_user in parent_agents) and
    # filters to active, modeled agents. Shape logic mirrors sync.ts's
    # buildAgentsList(); final serialization uses the same
    # JSON.stringify(data, null, 2) + "\n" the agent_config_sync plugin uses.
    #
    # Output is the OpenClaw 2026.9.x agents.entries shape: a keyed object
    # { "<id>": { model, default?, thinkingDefault?, subagents?, heartbeat? } }
    # with the id itself as the object key, NOT a field inside the value.
    local INITIAL_SYNC_QUERY="
        SELECT COALESCE(json_agg(row_to_json(sub)), NULL)::text
        FROM (
            SELECT
                name,
                model,
                fallback_models,
                thinking,
                instance_type,
                is_default,
                allowed_subagents,
                heartbeat_enabled,
                heartbeat_every,
                heartbeat_target,
                heartbeat_to,
                heartbeat_isolated_session
            FROM get_agent_export_rows()
        ) sub
    "
    local AGENTS_DATA
    if AGENTS_DATA=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "$INITIAL_SYNC_QUERY" 2>/dev/null); then
        if [ -n "$AGENTS_DATA" ] && [ "$AGENTS_DATA" != "null" ] && [ "$AGENTS_DATA" != "" ]; then
            # Duplicate-name guard: two rows with the same literal name would
            # silently collapse in the keyed output. Detect this on raw DB
            # data before serialization and fail loudly.
            local DUP_NAMES
            DUP_NAMES=$(echo "$AGENTS_DATA" | jq -r '
                [group_by(.name)[] | select(length > 1 and .[0].name != null) | .[0].name]
                | join(", ")
            ' 2>/dev/null)
            if [ -n "$DUP_NAMES" ]; then
                echo -e "  ${WARNING} Duplicate agent names detected: $DUP_NAMES — not writing agents.json"
                rm -f "$AGENTS_JSON_TMP"
                return 1
            fi

            local FORMAT_OK=0
            if command -v node &>/dev/null; then
                # Preferred: byte-match the plugin's JSON.stringify(data, null, 2) + "\n"
                # Build a keyed object, omitting the id from each value, applying
                # the same thinkingDefault validation and heartbeat shape as sync.ts.
                # shellcheck disable=SC2154,SC2086,SC2016
                if echo "$AGENTS_DATA" | node -e '
                    let input = "";
                    process.stdin.setEncoding("utf8");
                    process.stdin.on("data", c => input += c);
                    process.stdin.on("end", () => {
                        const fs = require("fs");
                        const VALID_THINKING_DEFAULTS = new Set([
                            "off", "minimal", "low", "medium", "high",
                            "xhigh", "adaptive", "max", "ultra",
                        ]);
                        const AGENT_ID_REGEX = /^[a-z0-9_][a-z0-9_-]{0,63}$/i;
                        const PROVIDER_REGISTRY_PATH = "/opt/agents/shared-config/models-providers.json";

                        function loadKnownProviders() {
                            try {
                                const data = JSON.parse(fs.readFileSync(PROVIDER_REGISTRY_PATH, "utf8"));
                                return new Set(Object.keys(data));
                            } catch {
                                return new Set();
                            }
                        }
                        const KNOWN_PROVIDERS = loadKnownProviders();

                        function extractProviderPrefix(model) {
                            const idx = model.indexOf("/");
                            if (idx === -1) return null;
                            return model.slice(0, idx);
                        }

                        function warnIfUnknownProviderPrefix(id, model) {
                            if (KNOWN_PROVIDERS.size === 0) return;
                            const prefix = extractProviderPrefix(model);
                            if (prefix == null) {
                                console.warn("agent_config_sync: agent '" + id + "' model '" + model + "' has no provider prefix");
                            } else if (!KNOWN_PROVIDERS.has(prefix)) {
                                console.warn("agent_config_sync: agent '" + id + "' model '" + model + "' has unrecognized provider prefix '" + prefix + "'");
                            }
                        }

                        function warnIfUnknownProviderPrefixes(id, model) {
                            if (typeof model === "string") {
                                warnIfUnknownProviderPrefix(id, model);
                            } else {
                                warnIfUnknownProviderPrefix(id, model.primary);
                                for (const fallback of model.fallbacks) {
                                    warnIfUnknownProviderPrefix(id, fallback);
                                }
                            }
                        }

                        const rows = JSON.parse(input);

                        // Duplicate-name guard (defensive, also checked in bash above).
                        const seen = new Map();
                        for (let i = 0; i < rows.length; i++) {
                            const name = rows[i].name;
                            if (typeof name !== "string") continue;
                            if (seen.has(name)) {
                                throw new Error("Duplicate agent name '" + name + "' at rows " + seen.get(name) + " and " + i + "; each agent id must appear exactly once");
                            }
                            seen.set(name, i);
                        }

                        const entries = {};
                        for (const row of rows) {
                            // Defensive: get_agent_export_rows() already filters
                            // status=active and model IS NOT NULL, but we re-apply
                            // here so a fixture or future function change cannot emit
                            // invalid entries.
                            if (row.status != null && row.status !== "active") continue;
                            if (row.model == null) continue;
                            if (typeof row.name !== "string" || !AGENT_ID_REGEX.test(row.name)) continue;

                            const hasFallbacks = Array.isArray(row.fallback_models) && row.fallback_models.length > 0;
                            const entry = { model: hasFallbacks
                                ? { primary: row.model, fallbacks: [...row.fallback_models] }
                                : row.model };

                            if (row.is_default === true) entry.default = true;

                            if (typeof row.thinking === "string" && row.thinking.length > 0 &&
                                VALID_THINKING_DEFAULTS.has(row.thinking)) {
                                entry.thinkingDefault = row.thinking;
                            }

                            if (Array.isArray(row.allowed_subagents) && row.allowed_subagents.length > 0) {
                                entry.subagents = { allowAgents: [...row.allowed_subagents].sort() };
                            }

                            if (row.heartbeat_enabled === true) {
                                const hb = {};
                                if (row.heartbeat_every != null) hb.every = row.heartbeat_every;
                                if (row.heartbeat_target != null) hb.target = row.heartbeat_target;
                                if (row.heartbeat_to != null) hb.to = row.heartbeat_to;
                                // #714 — isolatedSession must be explicit when the row has a value.
                                // true → true, false → false, null/undefined → omitted.
                                if (row.heartbeat_isolated_session === true) {
                                    hb.isolatedSession = true;
                                } else if (row.heartbeat_isolated_session === false) {
                                    hb.isolatedSession = false;
                                }
                                entry.heartbeat = hb;
                            }

                            warnIfUnknownProviderPrefixes(row.name, entry.model);

                            entries[row.name] = entry;
                        }
                        const sorted = {};
                        for (const key of Object.keys(entries).sort((a, b) => a.localeCompare(b))) {
                            sorted[key] = entries[key];
                        }
                        process.stdout.write(JSON.stringify(sorted, null, 2) + "\n");
                    });
                ' >"$AGENTS_JSON_TMP"; then
                    FORMAT_OK=1
                fi
            else
                # Fallback if node is unavailable: best-effort keyed object via jq.
                # thinkingDefault is not validated here (node is preferred);
                # the resulting file is still structurally a keyed object.
                if echo "$AGENTS_DATA" | jq '
                    map({
                        key: .name,
                        value: (
                            {model: (
                                if (.fallback_models | type) == "array" and (.fallback_models | length) > 0
                                then {primary: .model, fallbacks: .fallback_models}
                                else .model
                                end
                            )}
                            + (if .is_default == true then {default: true} else {} end)
                            + (if (.allowed_subagents | type) == "array" and (.allowed_subagents | length) > 0
                                then {subagents: {allowAgents: (.allowed_subagents | sort)}}
                                else {} end)
                            + (if .heartbeat_enabled == true
                                then {heartbeat: (
                                    (if .heartbeat_every != null then {every: .heartbeat_every} else {} end)
                                    + (if .heartbeat_target != null then {target: .heartbeat_target} else {} end)
                                    + (if .heartbeat_to != null then {to: .heartbeat_to} else {} end)
                                    + (if .heartbeat_isolated_session == true then {isolatedSession: true}
                               elif .heartbeat_isolated_session == false then {isolatedSession: false}
                               else {} end)
                                )}
                                else {} end)
                        )
                    })
                    | sort_by(.key)
                    | from_entries
                ' >"$AGENTS_JSON_TMP" 2>/dev/null; then
                    if [ -s "$AGENTS_JSON_TMP" ] && [ "$(tail -c 1 "$AGENTS_JSON_TMP" | wc -l)" -eq 0 ]; then
                        echo >> "$AGENTS_JSON_TMP"
                    fi
                    FORMAT_OK=1
                fi
            fi

            if [ "$FORMAT_OK" -eq 1 ]; then
                if mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"; then
                    echo -e "  ${CHECK_MARK} Generated agents.json from DB"
                    return 0
                else
                    echo -e "  ${WARNING} Could not write agents.json"
                    rm -f "$AGENTS_JSON_TMP"
                    return 1
                fi
            else
                echo -e "  ${WARNING} Could not serialize agents.json from DB data — not writing"
                rm -f "$AGENTS_JSON_TMP"
                return 1
            fi
        else
            # DB returned NULL or empty — no agents in scope, but psql succeeded.
            # Write a valid placeholder so the openclaw.json agents.entries $include
            # stays valid and the gateway can boot; agent_config_sync will populate
            # real data on startup. Failure paths (psql error / non-JSON) still write nothing.
            printf '{"main": {}}\n' > "$AGENTS_JSON_TMP"
            if mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"; then
                echo -e "  ${INFO} no agents in scope — wrote placeholder agents.json; agent_config_sync will populate on startup"
                return 0
            else
                echo -e "  ${WARNING} Could not write empty agents.json placeholder"
                rm -f "$AGENTS_JSON_TMP"
                return 1
            fi
        fi
    else
        # psql failed — NEVER write placeholder
        echo -e "  ${WARNING} Could not query DB for agents.json — agents.json not written"
        echo -e "  ${INFO} agent_config_sync will generate agents.json when gateway starts"
        rm -f "$AGENTS_JSON_TMP"
        return 1
    fi
}

# Helper: ensure agents.json is a valid non-empty keyed object, then switch
# agents.entries to { "$include": "./agents.json" } (#707, #1231 r7).
# Never switches to $include unless agents.json passes final validation.
# Honors --regenerate-agents-json.  Preserves inline keyed agents.entries so
# the agent set never shrinks.
_configure_agents_entries_include() {
    local OPENCLAW_CONFIG="${1:-$OPENCLAW_DIR/openclaw.json}"
    local AGENTS_JSON="$OPENCLAW_DIR/agents.json"
    local AGENTS_JSON_TMP="${AGENTS_JSON}.tmp.$$"

    if [ ! -f "$OPENCLAW_CONFIG" ]; then
        echo -e "  ${WARNING} OpenClaw config not found; cannot configure agents.entries"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi

    TMPFILES+=("$AGENTS_JSON_TMP")

    _ensure_agents_json_valid() {
        # Already a valid non-empty keyed object and not forcing regeneration.
        if [ "$REGENERATE_AGENTS_JSON" -eq 0 ] && [ -f "$AGENTS_JSON" ] && \
           jq -e 'type == "object" and length > 0' "$AGENTS_JSON" >/dev/null 2>&1; then
            echo -e "  ${CHECK_MARK} agents.json is valid (keyed object)"
            return 0
        fi

        # Not valid (or forced regeneration). Backup existing file if any.
        local AGENTS_JSON_BAK=""
        if [ -f "$AGENTS_JSON" ]; then
            AGENTS_JSON_BAK=$(_backup_agents_json "$AGENTS_JSON")
            if [ -n "$AGENTS_JSON_BAK" ]; then
                echo -e "  ${INFO} Backed up existing agents.json to $AGENTS_JSON_BAK"
            fi
            rm -f "$AGENTS_JSON"
        fi

        # (a) Prefer DB generation.
        local DB_GENERATED=0
        if _generate_agents_json; then
            DB_GENERATED=1
        fi

        # If DB produced only the placeholder, prefer legacy array conversion.
        if [ "$DB_GENERATED" -eq 1 ] && \
           jq -e 'type == "object" and length == 1 and has("main") and .main == {}' "$AGENTS_JSON" >/dev/null 2>&1; then
            if [ -n "$AGENTS_JSON_BAK" ] && \
               jq -e 'type == "array" and length > 0' "$AGENTS_JSON_BAK" >/dev/null 2>&1; then
                if _convert_legacy_agents_array "$AGENTS_JSON_BAK" "$AGENTS_JSON_TMP"; then
                    if jq -e 'type == "object" and length > 0' "$AGENTS_JSON_TMP" >/dev/null 2>&1; then
                        mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"
                        echo -e "  ${CHECK_MARK} Converted legacy agents.json array to keyed object"
                    fi
                fi
            fi
        fi

        # If DB failed or we still only have the placeholder, use inline entries.
        if { [ "$DB_GENERATED" -eq 0 ] || \
             jq -e 'type == "object" and length == 1 and has("main") and .main == {}' "$AGENTS_JSON" >/dev/null 2>&1; } && \
           [ -n "$INLINE_AGENTS_ENTRIES" ]; then
            printf '%s\n' "$INLINE_AGENTS_ENTRIES" > "$AGENTS_JSON_TMP" && \
                mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"
        fi

        # If still not a valid non-empty object, write placeholder.
        if ! jq -e 'type == "object" and length > 0' "$AGENTS_JSON" >/dev/null 2>&1; then
            printf '{"main": {}}\n' > "$AGENTS_JSON_TMP"
            if mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"; then
                echo -e "  ${INFO} Wrote placeholder agents.json"
            fi
        fi

        # Final sanity check.
        if jq -e 'type == "object" and length > 0' "$AGENTS_JSON" >/dev/null 2>&1; then
            return 0
        fi
        return 1
    }

    # Capture inline keyed agents.entries before we overwrite it (production case).
    local INLINE_AGENTS_ENTRIES=""
    if jq -e '(.agents.entries | type == "object") and (.agents.entries | has("$include") | not) and (.agents.entries | length > 0)' "$OPENCLAW_CONFIG" >/dev/null 2>&1; then
        INLINE_AGENTS_ENTRIES=$(jq '.agents.entries' "$OPENCLAW_CONFIG")
    fi

    echo "  Checking agents.json status..."
    if _ensure_agents_json_valid; then
        # Merge inline entries back so the agent set does not shrink.
        if [ -n "$INLINE_AGENTS_ENTRIES" ]; then
            local BEFORE_KEYS=""
            local AFTER_KEYS=""
            BEFORE_KEYS=$(jq -r 'keys | .[]' "$AGENTS_JSON" 2>/dev/null | sort | tr '\n' ' ' || true)
            if jq -s '.[0] * .[1]' "$AGENTS_JSON" <(printf '%s\n' "$INLINE_AGENTS_ENTRIES") >"$AGENTS_JSON_TMP" 2>/dev/null && \
               mv "$AGENTS_JSON_TMP" "$AGENTS_JSON"; then
                AFTER_KEYS=$(jq -r 'keys | .[]' "$AGENTS_JSON" 2>/dev/null | sort | tr '\n' ' ' || true)
                if [ "$BEFORE_KEYS" != "$AFTER_KEYS" ]; then
                    echo -e "  ${CHECK_MARK} Merged inline agents.entries to preserve agent set"
                fi
            fi
        fi

        # Final validation before touching agents.entries.
        if jq -e 'type == "object" and length > 0' "$AGENTS_JSON" >/dev/null 2>&1; then
            # No-shrink assertion for the production inline-object case.
            if [ -n "$INLINE_AGENTS_ENTRIES" ]; then
                local MISSING=""
                MISSING=$(jq -s '.[1] - .[0] | keys | .[]' "$AGENTS_JSON" <(printf '%s\n' "$INLINE_AGENTS_ENTRIES") 2>/dev/null || true)
                if [ -n "$MISSING" ]; then
                    echo -e "  ${CROSS_MARK} Agent set shrunk after migration; missing: $MISSING"
                    VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
                else
                    echo -e "  ${CHECK_MARK} Agent set preserved (no shrinkage)"
                fi
            fi

            local EXISTING_ENTRIES_INCLUDE
            EXISTING_ENTRIES_INCLUDE=$(jq -r '.agents.entries["$include"] // empty' "$OPENCLAW_CONFIG" 2>/dev/null || true)
            if [ -n "$EXISTING_ENTRIES_INCLUDE" ]; then
                echo -e "  ${CHECK_MARK} agents.entries already uses \$include: $EXISTING_ENTRIES_INCLUDE"
            else
                if jq 'del(.agents.list) | .agents.entries = { "$include": "./agents.json" }' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                   mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG"; then
                    echo -e "  ${CHECK_MARK} Set agents.entries = { \"\$include\": \"./agents.json\" }"
                else
                    echo -e "  ${WARNING} Could not set agents.entries \$include directive"
                    VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
                fi
            fi
        else
            echo -e "  ${WARNING} agents.json final validation failed; leaving agents.entries unchanged"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        fi
    else
        echo -e "  ${WARNING} Could not make agents.json valid; leaving agents.entries unchanged"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
}


# Helper: install a metacognition plugin
install_metacognition_plugin() {
    local plugin_name="$1"
    local plugin_source="$2"
    local plugin_target="$3"

    if [ ! -d "$plugin_source" ]; then
        echo -e "  ${INFO} $plugin_name source not found at $plugin_source (skipping)"
        return 0
    fi

    echo "  Installing $plugin_name..."
    mkdir -p "$plugin_target"

    # Copy source and config files
    for f in package.json package-lock.json openclaw.plugin.json tsconfig.json src; do
        if [ -e "$plugin_source/$f" ]; then
            if [ -d "$plugin_source/$f" ]; then
                rm -rf "${plugin_target:?}/$f"
                cp -r "$plugin_source/$f" "$plugin_target/$f"
            else
                cp "$plugin_source/$f" "$plugin_target/$f"
            fi
        fi
    done
    echo -e "    ${CHECK_MARK} Source files copied"

    # Build TypeScript in the source directory so the target only receives
    # runtime dependencies (#598, #724).
    if [ -d "$plugin_source/src" ]; then
        _install_plugin_build_dependencies "$plugin_source" "$plugin_name" || return 1

        echo "    Building TypeScript..."
        BUILD_LOG=$(mktemp "/tmp/build-${plugin_name}-XXXXXX.log")
        TMPFILES+=("$BUILD_LOG")
        mkdir -p "$plugin_target/dist"
        if (cd "$plugin_source" && "$plugin_source/node_modules/.bin/tsc") >"$BUILD_LOG" 2>&1; then
            cp -r "$plugin_source/dist/"* "$plugin_target/dist/"
            echo -e "    ${CHECK_MARK} Build completed"
            rm -f "$BUILD_LOG"
        else
            echo -e "    ${CROSS_MARK} Build failed"
            tail -10 "$BUILD_LOG"
            VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
            cd "$SCRIPT_DIR"
            return 1
        fi
    fi

    # Install runtime dependencies in the target directory (#598)
    _install_runtime_dependencies "$plugin_target" "$plugin_name" || return 1
    cd "$SCRIPT_DIR"

    # Enable in OpenClaw config
    if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
        jq --arg path "$plugin_target" --arg name "$plugin_name" '
            .plugins.load.paths = ((.plugins.load.paths // []) + [$path] | unique)
            | .plugins.entries[$name] = (.plugins.entries[$name] // {}) * {
                "enabled": true,
                "hooks": {
                  "allowConversationAccess": true
                }
              }
        ' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
            mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
            echo -e "    ${CHECK_MARK} $plugin_name enabled in OpenClaw config" || \
            echo -e "    ${WARNING} Could not enable $plugin_name in config"
    fi

    # Verify installation
    if [ -f "$plugin_target/dist/index.js" ] && [ -f "$plugin_target/openclaw.plugin.json" ]; then
        echo -e "  ${CHECK_MARK} $plugin_name installed to $plugin_target"
    else
        echo -e "  ${CROSS_MARK} $plugin_name installation incomplete"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi

    # Run any plugin migrations
    local plugin_migrations="$plugin_source/database/migrations"
    if [ -d "$plugin_migrations" ]; then
        echo "    Running $plugin_name migrations..."
        local mig_files=()
        while IFS= read -r -d '' f; do
            mig_files+=("$f")
        done < <(find "$plugin_migrations" -maxdepth 1 -name "*.sql" -print0 | sort -z)

        for sql_file in "${mig_files[@]}"; do
            local mig_name
            mig_name=$(basename "$sql_file")
            if _superuser_psql "$DB_NAME" -v ON_ERROR_STOP=1 -f - <"$sql_file" >/dev/null 2>&1; then
                echo -e "    ${CHECK_MARK} Migration: $mig_name"
            else
                echo -e "    ${WARNING} Migration failed: $mig_name"
            fi
        done
    fi
}

verify_config() {
    echo ""
    echo "Config verification..."

    if [ -z "${PGUSER:-}" ]; then
        echo -e "  ${WARNING} PGUSER not set (using: $(whoami))"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    else
        echo -e "  ${CHECK_MARK} PGUSER set: $PGUSER"
    fi

    if psql -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        echo -e "  ${CHECK_MARK} Database connection works"
    else
        echo -e "  ${CROSS_MARK} Database connection failed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi

    # memory-extract is a plugin after #726.
    if [ -f "$OPENCLAW_CONFIG" ]; then
        if command -v jq &>/dev/null; then
            if jq -e '.plugins.entries["memory-extract"]' "$OPENCLAW_CONFIG" &>/dev/null; then
                echo -e "  ${CHECK_MARK} memory-extract plugin configured"
            else
                echo -e "  ${WARNING} memory-extract plugin not found in OpenClaw config"
                VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            fi

            # Legacy hook config entry must not remain. The r4 installer uses
            # .hooks.internal.entries["memory-extract"].enabled (#1231).
            if jq -e '.hooks.internal.entries["memory-extract"]' "$OPENCLAW_CONFIG" &>/dev/null; then
                echo -e "  ${WARNING} Legacy memory-extract hook entry still present in OpenClaw config"
                VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            fi
        else
            echo -e "  ${WARNING} jq not available; cannot verify memory-extract plugin configuration"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        fi
    else
        echo -e "  ${WARNING} OpenClaw config not found at $OPENCLAW_CONFIG"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi

    # Legacy hook directory must not remain.
    if [ -d "$OPENCLAW_DIR/hooks/memory-extract" ]; then
        echo -e "  ${WARNING} Legacy memory-extract hook directory still present at $OPENCLAW_DIR/hooks/memory-extract"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi

    # session-init remains a hook.
    local HOOK_CONFIG="$HOME/.openclaw/hooks.json"
    if [ -f "$HOOK_CONFIG" ]; then
        echo -e "  ${CHECK_MARK} OpenClaw hook config exists"
        if grep -q '"session-init"' "$HOOK_CONFIG" 2>/dev/null; then
            local ENABLED
            ENABLED=$(grep -A5 '"session-init"' "$HOOK_CONFIG" | grep -cE '"enabled"\s*:\s*true' || echo "0")
            if [ "$ENABLED" -gt 0 ]; then
                echo -e "  ${CHECK_MARK} Hook 'session-init' enabled"
            else
                echo -e "  ${WARNING} Hook 'session-init' exists but not enabled"
                VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            fi
        else
            echo -e "  ${WARNING} Hook 'session-init' not found in OpenClaw config"
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
        fi
    else
        echo -e "  ${WARNING} OpenClaw hook config not found at $HOOK_CONFIG"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
}

# Detect peer-shadowed relations for the target database and configure the
# pgschema ignore base file / peer mode accordingly.
# Sets globals: PGSCHEMA_PEER_MODE, PGSCHEMA_IGNORE_BASE,
# PEER_SHADOWED_NAMES, PEER_SHADOWED_RELKINDS, PEER_SHADOWED_KINDS.
# Fails closed: returns non-zero when detection cannot be queried, so the
# caller skips the schema-apply stage instead of planning with zero exclusions.
_resolve_peer_shadowed_relations() {
    local shadowed_json detect_rc stderr_tmp
    stderr_tmp=$(mktemp /tmp/peer-shadowed-stderr-XXXXXX)
    TMPFILES+=("$stderr_tmp")
    detect_rc=0
    shadowed_json=$("$VENV_PYTHON" "$SCRIPT_DIR/database/detect_peer_shadowed.py" \
        --schema-file "$SCHEMA_FILE" \
        --dsn "host=/var/run/postgresql port=${PGPORT:-5432} dbname=$DB_NAME user=$DB_USER" 2>"$stderr_tmp") || detect_rc=$?

    if [ "$detect_rc" -ne 0 ]; then
        echo -e "  ${CROSS_MARK} Peer-shadowed relation detection failed (exit $detect_rc) — schema apply skipped"
        if [ -s "$stderr_tmp" ]; then
            cat "$stderr_tmp" >&2
        fi
        if [ -n "$shadowed_json" ]; then
            printf '%s\n' "$shadowed_json" >&2
        fi
        return "$detect_rc"
    fi

    # Log informational stderr (detection summary) on success.
    if [ -s "$stderr_tmp" ]; then
        cat "$stderr_tmp" >&2
    fi

    PEER_SHADOWED_NAMES=()
    PEER_SHADOWED_RELKINDS=()
    PEER_SHADOWED_KINDS=()
    while IFS= read -r line; do
        local name relkind kind
        name=$(printf '%s' "$line" | jq -r '.name // empty')
        relkind=$(printf '%s' "$line" | jq -r '.relkind // empty')
        kind=$(printf '%s' "$line" | jq -r '.kind // empty')
        if [ -n "$name" ]; then
            PEER_SHADOWED_NAMES+=("$name")
            PEER_SHADOWED_RELKINDS+=("$relkind")
            PEER_SHADOWED_KINDS+=("$name ($kind)")
        fi
    done <<< "$shadowed_json"

    if [ "${#PEER_SHADOWED_NAMES[@]}" -gt 0 ]; then
        PGSCHEMA_PEER_MODE=1
        PGSCHEMA_IGNORE_BASE="$SCRIPT_DIR/database/.pgschemaignore-peer"
        echo -e "  ${INFO} Peer-shadowed relations detected: ${PEER_SHADOWED_KINDS[*]}"
    else
        PGSCHEMA_PEER_MODE=0
        PGSCHEMA_IGNORE_BASE="$SCRIPT_DIR/database/.pgschemaignore"
    fi
    return 0
}

# When the installer is sourced by unit tests, stop here so tests can call
# the helper functions above without running the full installer.  This guard
# is NOT used in normal execution.
if [ "${AGENT_INSTALL_TEST_MODE:-}" = "1" ] && [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    return 0
fi

# ============================================
# SECTION 2: Source shared library
# ============================================
PG_ENV="$SCRIPT_DIR/lib/pg-env.sh"
if [ ! -f "$PG_ENV" ]; then
    echo -e "  ${RED}❌${NC} $PG_ENV not found"
    exit 1
fi
# shellcheck disable=SC1090,SC1091
source "$PG_ENV"

# ============================================
# SECTION 3: Load environment
# ============================================
PG_CONFIG="${HOME}/.openclaw/postgres.json"
if [ -f "$PG_CONFIG" ] && [ -r "$PG_CONFIG" ]; then
    load_pg_env
    load_pg_superuser_env
else
    echo "ERROR: Config file not found: $PG_CONFIG" >&2
    echo "Run shell-install.sh first or create ~/.openclaw/postgres.json" >&2
    echo "" >&2
    echo "Example ~/.openclaw/postgres.json:" >&2
    echo '  { "host": "localhost", "port": 5432, "database": "mydb", "user": "myuser", "password": "" }' >&2
    exit 1
fi

# Derived variables
DB_USER="${PGUSER:-$(whoami)}"
DB_NAME="${PGDATABASE:-${DB_USER//-/_}_memory}"

# Optional agent_chat message-bus peer detection (nova-mind#579).
# shellcheck disable=SC1090,SC1091
source "$SCRIPT_DIR/lib/agent-chat-peer-detection.sh"

# PostgreSQL password file path
PGPASS_FILE="${HOME}/.pgpass"

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace-coder}"
OPENCLAW_DIR="$HOME/.openclaw"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_DIR/openclaw.json}"
# shellcheck disable=SC2034
OPENCLAW_PROJECTS="$OPENCLAW_DIR/projects"
EXTENSIONS_DIR="$OPENCLAW_DIR/extensions"
# shellcheck disable=SC2034
NOVA_DIR="$HOME/.local/share/nova"
OPENCLAW_LOGS_DIR="$HOME/.openclaw/logs"

# Daily memory log cron configuration
DAILY_LOG_SCRIPT="generate-daily-log.py"
DAILY_LOG_CRON_MARKER="$HOME/.openclaw/scripts/$DAILY_LOG_SCRIPT"
DAILY_LOG_CRON_NIGHTLY='5 0 * * *    '"$DAILY_LOG_CRON_MARKER"' >> '"$OPENCLAW_LOGS_DIR"'/generate-daily-log.log 2>&1'
DAILY_LOG_CRON_INTRADAY='0 6,12,18 * * * '"$DAILY_LOG_CRON_MARKER"' >> '"$OPENCLAW_LOGS_DIR"'/generate-daily-log.log 2>&1'

# D100 roll announcer cron configuration
ANNOUNCE_D100_SCRIPT="announce-d100-rolls.sh"
ANNOUNCE_D100_CRON_MARKER="$HOME/.openclaw/scripts/$ANNOUNCE_D100_SCRIPT"
ANNOUNCE_D100_CRON_ENTRY='*/15 * * * * '"$ANNOUNCE_D100_CRON_MARKER"' >> '"$OPENCLAW_LOGS_DIR"'/announce-d100-rolls.log 2>&1'

# Hermes comms check cron configuration (issue #474)
HERMES_COMMS_CHECK_SCRIPT="hermes-comms-check.sh"
HERMES_COMMS_CHECK_MARKER="$HOME/.openclaw/scripts/comms/$HERMES_COMMS_CHECK_SCRIPT"
HERMES_COMMS_CRON_ENTRY='0 */4 * * * '"$HERMES_COMMS_CHECK_MARKER"' >> '"$OPENCLAW_LOGS_DIR"'/hermes-comms-check.log 2>&1'

# Completion log reconcile cron configuration (issue #562)
COMPLETION_LOG_RECONCILE_SCRIPT="completion-log-reconcile.py"
COMPLETION_LOG_RECONCILE_CRON_MARKER="$HOME/.openclaw/scripts/$COMPLETION_LOG_RECONCILE_SCRIPT"
COMPLETION_LOG_RECONCILE_CRON_ENTRY='*/5 * * * * '"$COMPLETION_LOG_RECONCILE_CRON_MARKER"' >> '"$OPENCLAW_LOGS_DIR"'/completion-log-reconcile.log 2>&1'

# Superuser connection helper for DDL operations
PG_SUPERUSER="${PG_SUPERUSER:-$DB_USER}"
PG_SUPERUSER_PASSWORD="${PG_SUPERUSER_PASSWORD:-${PGPASSWORD:-}}"
PG_SUPERUSER_HOST="${PG_SUPERUSER_HOST:-/var/run/postgresql}"

_superuser_psql() {
    # Runs psql as the superuser for DDL operations.
    # Falls back to regular DB_USER if superuser is the same.
    local db="${1:-$DB_NAME}"
    shift || true
    if [ "$PG_SUPERUSER" = "$DB_USER" ]; then
        psql -U "$DB_USER" -d "$db" "$@"
    else
        sudo -u "$PG_SUPERUSER" psql -d "$db" "$@"
    fi
}

_superuser_createdb() {
    # Runs createdb as the superuser.
    if [ "$PG_SUPERUSER" = "$DB_USER" ]; then
        createdb -U "$DB_USER" "$@"
    else
        sudo -u "$PG_SUPERUSER" createdb "$@"
    fi
}

_superuser_pgschema() {
    # Runs pgschema as the superuser for plan/apply.
    if [ "$PG_SUPERUSER" = "$DB_USER" ]; then
        "$PGSCHEMA_BIN" "$@"
    else
        sudo -u "$PG_SUPERUSER" "$PGSCHEMA_BIN" "$@"
    fi
}

# Ensure a ~/.pgpass entry exists for a given connection.
# Removes any existing entry with the same host:port:database:user prefix
# and appends the current password, so re-runs are idempotent and password
# rotations are picked up.
_ensure_pgpass_entry() {
    local host="$1"
    local port="$2"
    local database="$3"
    local user="$4"
    local password="$5"
    local pgpass="$PGPASS_FILE"
    local prefix="${host}:${port}:${database}:${user}:"
    local line="${prefix}${password}"

    if [ ! -f "$pgpass" ]; then
        touch "$pgpass"
        chmod 600 "$pgpass"
    fi

    # Already correct? Nothing to do.
    if grep -qxF "$line" "$pgpass" 2>/dev/null; then
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp)
    TMPFILES+=("$tmpfile")
    chmod 600 "$tmpfile"
    # Drop any stale entry with the same prefix, then append the new one.
    if [ -s "$pgpass" ]; then
        grep -vF "$prefix" "$pgpass" >"$tmpfile" 2>/dev/null || cat "$pgpass" >"$tmpfile"
    fi
    printf '%s\n' "$line" >>"$tmpfile"
    mv "$tmpfile" "$pgpass"
    chmod 600 "$pgpass"
    return 0
}

# Install or verify daily memory log cron entries into the current user's crontab.
# In install mode missing entries are appended. In --verify-only mode the crontab
# is never modified; the function reports installed / missing / drifted status.
# Uses globals: DAILY_LOG_CRON_MARKER, DAILY_LOG_CRON_NIGHTLY, DAILY_LOG_CRON_INTRADAY,
#               DAILY_LOG_SCRIPT, VERIFICATION_WARNINGS, VERIFICATION_ERRORS, VERIFY_ONLY
# Sets global: DAILY_LOG_CRON_STATUS
_install_daily_log_cron() {
    if [ "${NO_CRON:-0}" -eq 1 ]; then
        echo -e "  ${INFO} Cron installation skipped (--no-cron)"
        DAILY_LOG_CRON_STATUS="skipped by --no-cron"
        return 0
    fi

    local cron_drift_lines=()
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || true)

    if echo "$current_crontab" | grep -qF "$DAILY_LOG_CRON_MARKER"; then
        # Script path is present; check for drift from expected entries.
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
            echo -e "  ${WARNING} Existing cron entry for $DAILY_LOG_SCRIPT differs from expected schedule (drift detected):"
            local drift_line
            for drift_line in "${cron_drift_lines[@]}"; do
                echo "      $drift_line"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            DAILY_LOG_CRON_STATUS="drift detected (review required)"
        elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
            echo -e "  ${CHECK_MARK} Daily memory log cron entries installed"
            DAILY_LOG_CRON_STATUS="installed"
        else
            echo -e "  ${CHECK_MARK} Daily memory log cron entries verified"
            DAILY_LOG_CRON_STATUS="verified"
        fi
    elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
        echo -e "  ${CROSS_MARK} Daily memory log cron entries missing"
        DAILY_LOG_CRON_STATUS="missing"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        (crontab -l 2>/dev/null || true; echo "$DAILY_LOG_CRON_NIGHTLY"; echo "$DAILY_LOG_CRON_INTRADAY") | crontab -
        echo -e "  ${CHECK_MARK} Installed daily memory log cron entries (nightly + intraday)"
        DAILY_LOG_CRON_STATUS="installed"
    fi
}

# Install or verify the D100 roll announcer cron entry.
# Uses globals: ANNOUNCE_D100_CRON_MARKER, ANNOUNCE_D100_CRON_ENTRY,
#               ANNOUNCE_D100_SCRIPT, VERIFICATION_WARNINGS, VERIFICATION_ERRORS,
#               VERIFY_ONLY, NO_CRON
# Sets global: ANNOUNCE_D100_CRON_STATUS
_install_announce_d100_cron() {
    if [ "${NO_CRON:-0}" -eq 1 ]; then
        echo -e "  ${INFO} D100 announcer cron installation skipped (--no-cron)"
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
            echo -e "  ${WARNING} Existing cron entry for $ANNOUNCE_D100_SCRIPT differs from expected schedule (drift detected):"
            local drift_line
            for drift_line in "${cron_drift_lines[@]}"; do
                echo "      $drift_line"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            ANNOUNCE_D100_CRON_STATUS="drift detected (review required)"
        elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
            echo -e "  ${CHECK_MARK} D100 announcer cron entry installed"
            ANNOUNCE_D100_CRON_STATUS="installed"
        else
            echo -e "  ${CHECK_MARK} D100 announcer cron entry verified"
            ANNOUNCE_D100_CRON_STATUS="verified"
        fi
    elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
        echo -e "  ${CROSS_MARK} D100 announcer cron entry missing"
        ANNOUNCE_D100_CRON_STATUS="missing"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        (crontab -l 2>/dev/null || true; echo "$ANNOUNCE_D100_CRON_ENTRY") | crontab -
        echo -e "  ${CHECK_MARK} Installed D100 announcer cron entry (every 15 minutes)"
        ANNOUNCE_D100_CRON_STATUS="installed"
    fi
}

# Install or verify the consolidated Hermes comms-check cron entry.
# This replaces the previous pair of scheduler jobs (56618ee3 agent=hermes,
# 9169c40e agent=nova) with exactly one job that runs the deterministic ingest
# and report composer as the hermes DB user.
# Uses globals: HERMES_COMMS_CHECK_SCRIPT, HERMES_COMMS_CHECK_MARKER,
#               HERMES_COMMS_CRON_ENTRY, VERIFY_ONLY, NO_CRON
# Sets global: HERMES_COMMS_CRON_STATUS
_install_hermes_comms_check_cron() {
    if [ "${NO_CRON:-0}" -eq 1 ]; then
        echo -e "  ${INFO} Hermes comms-check cron installation skipped (--no-cron)"
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
            echo -e "  ${WARNING} Existing cron entry for $HERMES_COMMS_CHECK_SCRIPT differs from expected schedule (drift detected):"
            local drift_line
            for drift_line in "${cron_drift_lines[@]}"; do
                echo "      $drift_line"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            HERMES_COMMS_CRON_STATUS="drift detected (review required)"
        elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
            echo -e "  ${CHECK_MARK} Hermes comms-check cron entry installed"
            HERMES_COMMS_CRON_STATUS="installed"
        else
            echo -e "  ${CHECK_MARK} Hermes comms-check cron entry verified"
            HERMES_COMMS_CRON_STATUS="verified"
        fi
    elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
        echo -e "  ${CROSS_MARK} Hermes comms-check cron entry missing"
        HERMES_COMMS_CRON_STATUS="missing"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        (crontab -l 2>/dev/null || true; echo "$HERMES_COMMS_CRON_ENTRY") | crontab -
        echo -e "  ${CHECK_MARK} Installed Hermes comms-check cron entry (every 4 hours)"
        HERMES_COMMS_CRON_STATUS="installed"
    fi
}

# Install or verify the completion log reconcile cron entry.
# Uses globals: COMPLETION_LOG_RECONCILE_SCRIPT, COMPLETION_LOG_RECONCILE_CRON_MARKER,
#               COMPLETION_LOG_RECONCILE_CRON_ENTRY, VERIFY_ONLY, NO_CRON
# Sets global: COMPLETION_LOG_RECONCILE_CRON_STATUS
_install_completion_log_reconcile_cron() {
    if [ "${NO_CRON:-0}" -eq 1 ]; then
        echo -e "  ${INFO} Completion log reconcile cron installation skipped (--no-cron)"
        COMPLETION_LOG_RECONCILE_CRON_STATUS="skipped by --no-cron"
        return 0
    fi

    local cron_drift_lines=()
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || true)

    if echo "$current_crontab" | grep -qF "$COMPLETION_LOG_RECONCILE_CRON_MARKER"; then
        local line
        while IFS= read -r line; do
            case "$line" in
                *"$COMPLETION_LOG_RECONCILE_CRON_MARKER"*)
                    if [ "$line" != "$COMPLETION_LOG_RECONCILE_CRON_ENTRY" ]; then
                        cron_drift_lines+=("$line")
                    fi
                    ;;
            esac
        done <<< "$current_crontab"

        if [ ${#cron_drift_lines[@]} -gt 0 ]; then
            echo -e "  ${WARNING} Existing cron entry for $COMPLETION_LOG_RECONCILE_SCRIPT differs from expected schedule (drift detected):"
            local drift_line
            for drift_line in "${cron_drift_lines[@]}"; do
                echo "      $drift_line"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
            COMPLETION_LOG_RECONCILE_CRON_STATUS="drift detected (review required)"
        elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
            echo -e "  ${CHECK_MARK} Completion log reconcile cron entry installed"
            COMPLETION_LOG_RECONCILE_CRON_STATUS="installed"
        else
            echo -e "  ${CHECK_MARK} Completion log reconcile cron entry verified"
            COMPLETION_LOG_RECONCILE_CRON_STATUS="verified"
        fi
    elif [ "${VERIFY_ONLY:-0}" -eq 1 ]; then
        echo -e "  ${CROSS_MARK} Completion log reconcile cron entry missing"
        COMPLETION_LOG_RECONCILE_CRON_STATUS="missing"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    else
        (crontab -l 2>/dev/null || true; echo "$COMPLETION_LOG_RECONCILE_CRON_ENTRY") | crontab -
        echo -e "  ${CHECK_MARK} Installed completion log reconcile cron entry (every 5 minutes)"
        COMPLETION_LOG_RECONCILE_CRON_STATUS="installed"
    fi
}


if [ "$PG_SUPERUSER" != "$DB_USER" ]; then
    echo "  Superuser:     $PG_SUPERUSER (for DDL operations)"
fi

# ============================================
# SECTION 4: Parse arguments
# ============================================
VERIFY_ONLY=0
FORCE_INSTALL=0
NO_RESTART=0
NO_CRON=0
DB_NAME_OVERRIDE=""
REGENERATE_AGENTS_JSON=0
DAILY_LOG_CRON_STATUS="not installed"
ANNOUNCE_D100_CRON_STATUS="not installed"
HERMES_COMMS_CRON_STATUS="not installed"
COMPLETION_LOG_RECONCILE_CRON_STATUS="not installed"

while [[ $# -gt 0 ]]; do
    case $1 in
        --verify-only)
            VERIFY_ONLY=1
            shift
            ;;
        --force)
            FORCE_INSTALL=1
            shift
            ;;
        --regenerate-agents-json)
            REGENERATE_AGENTS_JSON=1
            shift
            ;;
        --no-restart)
            NO_RESTART=1
            shift
            ;;
        --no-cron)
            NO_CRON=1
            shift
            ;;
        --database|-d)
            DB_NAME_OVERRIDE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verify-only              Check installation without modifying anything"
            echo "  --force                    Force overwrite existing files (skip file verification)"
            echo "  --no-restart               Skip automatic gateway restart after install"
            echo "  --no-cron                  Skip installation of the daily-log cron entries"
            echo "  --database, -d NAME        Override database name (default: \${USER}_memory)"
            echo "  --regenerate-agents-json   Backup and regenerate ~/.openclaw/agents.json from DB"
            echo "  --help                     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Use default database name"
            echo "  $0 --database nova_memory       # Use specific database"
            echo "  $0 -d nova_memory               # Short form"
            echo "  $0 --verify-only                # Check installation status"
            echo "  $0 --force                      # Force reinstall all components"
            echo ""
            echo "Installs:"
            echo "  [relationships] entity-resolver lib, relationship skills"
            echo "  [memory]        schema (pgschema), shared PG libs, hooks, scripts, skills, venv, embeddings"
            echo "  [cognition]     hooks, workflows, bootstrap context, agent_config_sync plugin,"
            echo "                  turn-context plugin, shell aliases (agent_chat plugin is optional peer repo)"
            echo ""
            echo "Components get installed to:"
            echo "  ~/.openclaw/hooks/           — memory-extract, session-init, db-bootstrap-context"
            echo "  ~/.openclaw/plugins/         — turn-context"
            echo "  ~/.openclaw/extensions/      — agent_config_sync"
            echo "  ~/.openclaw/lib/             — PG loader libraries, entity-resolver"
            echo "  ~/.local/share/nova/         — shell-aliases.sh"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

if [ -n "$DB_NAME_OVERRIDE" ]; then
    DB_NAME="$DB_NAME_OVERRIDE"
fi

# ============================================
# SECTION 5: Prerequisites check
# ============================================
echo ""
echo "═══════════════════════════════════════════"
if [ $VERIFY_ONLY -eq 1 ]; then
    echo "  nova-mind verification v${VERSION}"
else
    echo "  nova-mind installer v${VERSION}"
fi
echo "═══════════════════════════════════════════"
echo ""

echo "Checking prerequisites..."

# PostgreSQL CLI
if command -v psql &>/dev/null; then
    PG_VERSION=$(psql --version | awk '{print $3}')
    echo -e "  ${CHECK_MARK} PostgreSQL installed ($PG_VERSION)"
else
    echo -e "  ${CROSS_MARK} PostgreSQL not found"
    echo "  Install: sudo apt install postgresql postgresql-contrib"
    exit 1
fi

# PostgreSQL service
if pg_isready -q 2>/dev/null; then
    echo -e "  ${CHECK_MARK} PostgreSQL service running"
else
    echo -e "  ${CROSS_MARK} PostgreSQL service not running"
    echo "  Start: sudo systemctl start postgresql"
    exit 1
fi

# Superuser DDL capability check (#661): agent-install.sh run standalone
# (skipping shell-install.sh's interactive prompt) leaves PG_SUPERUSER
# unset, and load_pg_superuser_env's fallback resolves it to the agent's
# own DB_USER (see lib/pg-env.sh). schema.sql previously contained
# ALTER DEFAULT PRIVILEGES FOR ROLE nova statements requiring the
# executing role to be a superuser or a member of role nova; #659 phase 1
# strips those at dump time, which removes THAT specific requirement.
# But other DDL in the schema/pre-migration path can still require a real
# superuser on some hosts (e.g. CREATE EXTENSION, if the schema ever
# declares one -- see the extensions step at line ~1370 below). Warn
# loudly HERE -- before database creation, not buried at a DDL failure
# many stages later -- whenever PG_SUPERUSER resolves to a role that is
# not an actual superuser. This is a warning, not a hard abort: #659
# phase 1 means most fresh installs now succeed even without a real
# superuser, so failing closed here would block installs that no longer
# need superuser privilege at all.
if [ "$PG_SUPERUSER" = "$DB_USER" ]; then
    SUPERUSER_CHECK_ROLE="$DB_USER"
else
    SUPERUSER_CHECK_ROLE="$PG_SUPERUSER"
fi
SUPERUSER_CHECK=$(psql -U "$DB_USER" -d postgres -tAc \
    "SELECT CASE WHEN EXISTS(SELECT 1 FROM pg_roles WHERE rolname = '$SUPERUSER_CHECK_ROLE')
         THEN (SELECT rolsuper FROM pg_roles WHERE rolname = '$SUPERUSER_CHECK_ROLE')
         ELSE NULL
     END" \
    2>/dev/null | tr -d '[:space:]')
if [ "$SUPERUSER_CHECK" = "f" ]; then
    echo -e "  ${WARNING} PG_SUPERUSER=$SUPERUSER_CHECK_ROLE is not a PostgreSQL superuser"
    echo "      DDL requiring superuser (e.g. CREATE EXTENSION) will fail if the schema requires it."
    echo "      Export PG_SUPERUSER=postgres (or run via shell-install.sh) if installation fails later"
    echo "      at a DDL step."
elif [ -z "$SUPERUSER_CHECK" ]; then
    echo -e "  ${WARNING} Could not verify PG_SUPERUSER role privileges (role '$SUPERUSER_CHECK_ROLE' may not exist yet)"
else
    echo -e "  ${CHECK_MARK} PG_SUPERUSER=$SUPERUSER_CHECK_ROLE is a PostgreSQL superuser"
fi

# jq
if command -v jq &>/dev/null; then
    echo -e "  ${CHECK_MARK} jq available"
else
    echo -e "  ${CROSS_MARK} jq not found (required)"
    echo "  Install: sudo apt install jq"
    exit 1
fi

# pgschema (required for memory schema management)
if command -v pgschema &>/dev/null; then
    PGSCHEMA_BIN="pgschema"
    echo -e "  ${CHECK_MARK} pgschema available"
elif [ -x "$HOME/go/bin/pgschema" ]; then
    PGSCHEMA_BIN="$HOME/go/bin/pgschema"
    echo -e "  ${CHECK_MARK} pgschema available at $PGSCHEMA_BIN"
else
    echo -e "  ${CROSS_MARK} pgschema not found (required for schema management)"
    echo "  Install: go install github.com/pgplex/pgschema@latest"
    echo "  Then add ~/go/bin to your PATH"
    exit 1
fi

# Node.js (required for relationships and cognition)
if [ $VERIFY_ONLY -eq 0 ]; then
    if command -v node &>/dev/null; then
        NODE_VERSION=$(node --version)
        NODE_VERSION_NO_V="${NODE_VERSION#v}"
        NODE_MAJOR="${NODE_VERSION_NO_V%%.*}"
        if [ "$NODE_MAJOR" -ge 18 ]; then
            echo -e "  ${CHECK_MARK} Node.js installed ($NODE_VERSION)"
        else
            echo -e "  ${WARNING} Node.js $NODE_VERSION (recommend 18+)"
        fi
    else
        echo -e "  ${CROSS_MARK} Node.js not found"
        echo "  Install: curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - && sudo apt install -y nodejs"
        exit 1
    fi

    if command -v npm &>/dev/null; then
        NPM_VERSION=$(npm --version)
        echo -e "  ${CHECK_MARK} npm installed ($NPM_VERSION)"
    else
        echo -e "  ${CROSS_MARK} npm not found"
        exit 1
    fi
fi

# Python3
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    echo -e "  ${CHECK_MARK} Python3 available ($PYTHON_VERSION)"
else
    echo -e "  ${CROSS_MARK} Python3 not found (required for memory scripts)"
    echo "  Install: sudo apt install python3 python3-pip"
    exit 1
fi

# ============================================
# SECTION 6: Helper functions
# ============================================

# copy_excluding <source_dir> <target_dir>
# Copies a directory tree excluding node_modules and dist
copy_excluding() {
    local source="$1"
    local target="$2"
    mkdir -p "$target"
    (cd "$source" && find . -type f \
        -not -path '*/node_modules/*' \
        -not -path '*/dist/*' \
        -print0 | while IFS= read -r -d '' f; do
        mkdir -p "$target/$(dirname "$f")"
        cp "$f" "$target/$f"
    done)
}

# sync_directory <source_dir> <target_dir> [label]
# Hash-based file sync — copies new/changed files, skips identical.
# Honors FORCE_INSTALL. Sets SYNC_UPDATED, SYNC_SKIPPED, SYNC_ADDED.
SYNC_UPDATED=0
SYNC_SKIPPED=0
SYNC_ADDED=0

sync_directory() {
    local src_dir="$1"
    local tgt_dir="$2"
    local label="${3:-files}"

    SYNC_UPDATED=0
    SYNC_SKIPPED=0
    SYNC_ADDED=0

    if [ ! -d "$src_dir" ]; then
        echo -e "  ${WARNING} Source directory not found: $src_dir"
        return 1
    fi

    mkdir -p "$tgt_dir"

    while IFS= read -r -d '' rel_path; do
        local src_file="$src_dir/$rel_path"
        local tgt_file="$tgt_dir/$rel_path"

        mkdir -p "$(dirname "$tgt_file")"

        if [ "$FORCE_INSTALL" -eq 1 ]; then
            cp "$src_file" "$tgt_file"
            echo -e "    ${CHECK_MARK} $rel_path (force-updated)"
            SYNC_UPDATED=$((SYNC_UPDATED + 1))
        elif [ ! -f "$tgt_file" ]; then
            cp "$src_file" "$tgt_file"
            echo -e "    ${CHECK_MARK} $rel_path (added)"
            SYNC_ADDED=$((SYNC_ADDED + 1))
        else
            local src_hash tgt_hash
            src_hash=$(sha256sum "$src_file" | awk '{print $1}')
            tgt_hash=$(sha256sum "$tgt_file" | awk '{print $1}')
            if [ "$src_hash" != "$tgt_hash" ]; then
                cp "$src_file" "$tgt_file"
                echo -e "    ${CHECK_MARK} $rel_path (updated)"
                SYNC_UPDATED=$((SYNC_UPDATED + 1))
            else
                echo -e "    ${INFO} $rel_path (unchanged, skipped)"
                SYNC_SKIPPED=$((SYNC_SKIPPED + 1))
            fi
        fi
    done < <(cd "$src_dir" && find . -type f -not -path '*/node_modules/*' -not -path '*/dist/*' -print0 | sed -z 's|^\./||')

    local total=$((SYNC_UPDATED + SYNC_SKIPPED + SYNC_ADDED))
    echo -e "  Summary: $total $label — $SYNC_ADDED added, $SYNC_UPDATED updated, $SYNC_SKIPPED unchanged"
}

# install_hook <hook_name> <source_base_dir>
# Installs or updates a hook using hash comparison.
# Returns: 0=installed/updated, 1=missing, 2=up-to-date
install_hook() {
    local hook_name="$1"
    local hooks_source="$2"
    local source="$hooks_source/$hook_name"
    local target="$OPENCLAW_DIR/hooks/$hook_name"

    if [ ! -d "$source" ]; then
        echo -e "  ${WARNING} Hook not found: $hook_name (skipping)"
        return 1
    fi

    if [ "$FORCE_INSTALL" -eq 0 ] && [ -d "$target" ]; then
        local all_match=1
        for source_file in "$source"/*.ts "$source"/*.js "$source"/*.sh; do
            [ -f "$source_file" ] || continue
            local filename target_file
            filename=$(basename "$source_file")
            target_file="$target/$filename"
            if [ -f "$target_file" ]; then
                local sh th
                sh=$(sha256sum "$source_file" | awk '{print $1}')
                th=$(sha256sum "$target_file" | awk '{print $1}')
                [ "$sh" != "$th" ] && all_match=0 && break
            else
                all_match=0; break
            fi
        done
        if [ "$all_match" -eq 1 ]; then
            echo -e "  ${INFO} $hook_name up to date"
            return 2
        fi
    fi

    local was_existing=0
    if [ -e "$target" ]; then
        was_existing=1
        rm -rf "$target"
    fi

    copy_excluding "$source" "$target"
    if [ "$was_existing" -eq 1 ]; then
        echo -e "  ${CHECK_MARK} $hook_name updated"
    else
        echo -e "  ${CHECK_MARK} $hook_name installed"
    fi
    return 0
}

# install_lib_files: Install shared PG loader files to ~/.openclaw/lib/
install_lib_files() {
    local lib_src="$SCRIPT_DIR/memory/lib"
    local lib_dst="$HOME/.openclaw/lib"
    local files=("pg-env.sh" "pg_env.py" "pg-env.ts" "env-loader.sh" "env_loader.py")

    mkdir -p "$lib_dst"
    chmod 755 "$lib_dst"

    for f in "${files[@]}"; do
        local src="$lib_src/$f"
        local dst="$lib_dst/$f"

        if [ ! -f "$src" ]; then
            echo -e "  ${WARNING} [lib] $f: source not found in repo, skipping"
            continue
        fi

        if [ ! -f "$dst" ]; then
            cp "$src" "$dst"
            chmod 644 "$dst"
            echo -e "  ${CHECK_MARK} [lib] $f: installed"
        else
            local src_hash dst_hash
            src_hash=$(sha256sum "$src" | awk '{print $1}')
            dst_hash=$(sha256sum "$dst" | awk '{print $1}')
            if [ "$src_hash" != "$dst_hash" ]; then
                cp "$src" "$dst"
                chmod 644 "$dst"
                echo -e "  ${CHECK_MARK} [lib] $f: updated (hash changed)"
            else
                echo -e "  ${INFO} [lib] $f: up to date"
            fi
        fi
    done
}

# install_skills <source_skills_dir> <target_skills_dir> [label]
# Installs or updates skills using hash comparison.
install_skills() {
    local skills_source="$1"
    local skills_target="$2"
    local label="${3:-skills}"

    if [ ! -d "$skills_source" ]; then
        echo -e "  ${WARNING} Skills source directory not found: $skills_source"
        return 1
    fi

    mkdir -p "$skills_target"

    local skills_installed=0
    local skills_skipped=0
    local skills_updated=0

    for skill_dir in "$skills_source"/*/; do
        [ -d "$skill_dir" ] || continue
        local skill_name target_skill
        skill_name=$(basename "$skill_dir")
        target_skill="$skills_target/$skill_name"

        # Remove legacy symlinks
        if [ -L "$target_skill" ]; then
            rm "$target_skill"
            echo -e "  ${INFO} Removed legacy symlink for $skill_name"
        fi

        if [ -d "$target_skill" ]; then
            if [ "$FORCE_INSTALL" -eq 1 ]; then
                rm -rf "$target_skill"
                copy_excluding "$skill_dir" "$target_skill"
                echo -e "  ${CHECK_MARK} $skill_name updated (forced)"
                skills_updated=$((skills_updated + 1))
            else
                local needs_update=0
                while IFS= read -r -d '' source_file; do
                    local rel_path="${source_file#"$skill_dir"}"
                    local target_file="$target_skill/$rel_path"
                    if [ ! -f "$target_file" ]; then
                        needs_update=1; break
                    fi
                    local sh th
                    sh=$(sha256sum "$source_file" | awk '{print $1}')
                    th=$(sha256sum "$target_file" | awk '{print $1}')
                    [ "$sh" != "$th" ] && needs_update=1 && break
                done < <(find "$skill_dir" -type f -print0)

                if [ "$needs_update" -eq 0 ]; then
                    echo -e "  ${INFO} $skill_name up to date"
                    skills_skipped=$((skills_skipped + 1))
                else
                    echo -e "  ${WARNING} $skill_name exists with modifications (use --force to overwrite)"
                    skills_skipped=$((skills_skipped + 1))
                fi
            fi
        else
            copy_excluding "$skill_dir" "$target_skill"
            echo -e "  ${CHECK_MARK} $skill_name installed"
            skills_installed=$((skills_installed + 1))
        fi
    done

    if [ $((skills_installed + skills_updated)) -gt 0 ]; then
        echo -e "  ${CHECK_MARK} $label: $skills_installed installed, $skills_updated updated, $skills_skipped skipped"
    elif [ "$skills_skipped" -gt 0 ]; then
        echo -e "  ${INFO} $label: all $skills_skipped skill(s) already present"
    fi
}

# ============================================
# Verification functions
# ============================================

verify_schema() {
    echo "Schema verification (memory)..."

    if ! psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo -e "  ${CROSS_MARK} Database '$DB_NAME' does not exist"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
        return 1
    fi

    local SCHEMA_FILE="$SCRIPT_DIR/database/schema.sql"
    if [ -f "$SCHEMA_FILE" ]; then
        local TABLE_NAMES
        TABLE_NAMES=$(grep "^CREATE TABLE" "$SCHEMA_FILE" | sed -E 's/CREATE TABLE IF NOT EXISTS ([^ ]+).*/\1/' | sort)
        local tables_missing=()
        local tables_present=0

        for table in $TABLE_NAMES; do
            local TABLE_EXISTS
            TABLE_EXISTS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table'" | tr -d '[:space:]')
            if [ "$TABLE_EXISTS" -eq 0 ]; then
                tables_missing+=("$table")
            else
                tables_present=$((tables_present + 1))
            fi
        done

        if [ ${#tables_missing[@]} -gt 0 ]; then
            echo -e "  ${WARNING} Missing tables:"
            for table in "${tables_missing[@]}"; do
                echo "      • $table"
            done
            VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + ${#tables_missing[@]}))
        else
            echo -e "  ${CHECK_MARK} All schema tables present ($tables_present tables)"
        fi
    else
        echo -e "  ${WARNING} Schema file not found: $SCHEMA_FILE"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
}

verify_relationships() {
    echo ""
    echo "Verification (relationships)..."

    local required_tables=("entities" "entity_facts" "entity_relationships")
    local missing_tables=()
    for table in "${required_tables[@]}"; do
        local TABLE_EXISTS
        TABLE_EXISTS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '$table'" | tr -d '[:space:]')
        if [ "$TABLE_EXISTS" -eq 0 ]; then
            missing_tables+=("$table")
        else
            echo -e "  ${CHECK_MARK} Table '$table' exists"
        fi
    done
    if [ ${#missing_tables[@]} -gt 0 ]; then
        echo -e "  ${CROSS_MARK} Missing relationship tables: ${missing_tables[*]}"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + ${#missing_tables[@]}))
    fi

    if [ -d "$SCRIPT_DIR/relationships/lib/entity-resolver" ]; then
        echo -e "  ${CHECK_MARK} entity-resolver library present"
    else
        echo -e "  ${CROSS_MARK} entity-resolver library not found"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
}

verify_cognition() {
    echo ""
    echo "Verification (cognition)..."

    if [ -f "$OPENCLAW_DIR/plugins/turn-context/dist/index.js" ]; then
        echo -e "  ${CHECK_MARK} turn-context plugin installed"
    else
        echo -e "  ${CROSS_MARK} turn-context plugin not installed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi

    if [ -f "$OPENCLAW_DIR/plugins/self-awareness/dist/index.js" ]; then
        echo -e "  ${CHECK_MARK} self-awareness plugin installed"
    else
        echo -e "  ${INFO} self-awareness plugin not installed"
    fi

    # confidence-check plugin intentionally disabled (see nova-mind #342)
    if [ -f "$OPENCLAW_DIR/plugins/confidence-check/dist/index.js" ]; then
        echo -e "  ${WARNING} confidence-check plugin found but should be DISABLED (see #342)"
    else
        echo -e "  ${CHECK_MARK} confidence-check plugin not installed (disabled per #342)"
    fi

    if [ -d "$OPENCLAW_DIR/hooks/db-bootstrap-context" ]; then
        echo -e "  ${CHECK_MARK} Bootstrap context hook installed"
    else
        echo -e "  ${CROSS_MARK} Bootstrap context hook not installed"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi

}

# ============================================
# Run verification early if --verify-only
# ============================================
if [ $VERIFY_ONLY -eq 1 ]; then
    verify_schema
    verify_relationships
    verify_cognition
    verify_config

    echo ""
    echo "Memory scripts verification..."
    _install_daily_log_cron
    _install_announce_d100_cron
    _install_completion_log_reconcile_cron

    echo ""
    echo "═══════════════════════════════════════════"
    echo "  Verification Summary"
    echo "═══════════════════════════════════════════"

    cron_symbol="$CHECK_MARK"
    if [[ "$DAILY_LOG_CRON_STATUS" == missing* ]]; then
        cron_symbol="$CROSS_MARK"
    elif [[ "$DAILY_LOG_CRON_STATUS" == drift* ]]; then
        cron_symbol="$WARNING"
    fi
    echo -e "  ${cron_symbol} Daily memory log cron: $DAILY_LOG_CRON_STATUS"

    announce_symbol="$CHECK_MARK"
    if [[ "$ANNOUNCE_D100_CRON_STATUS" == missing* ]]; then
        announce_symbol="$CROSS_MARK"
    elif [[ "$ANNOUNCE_D100_CRON_STATUS" == drift* ]]; then
        announce_symbol="$WARNING"
    fi
    echo -e "  ${announce_symbol} D100 announcer cron: $ANNOUNCE_D100_CRON_STATUS"

    comms_symbol="$CHECK_MARK"
    if [[ "$HERMES_COMMS_CRON_STATUS" == missing* ]]; then
        comms_symbol="$CROSS_MARK"
    elif [[ "$HERMES_COMMS_CRON_STATUS" == drift* ]]; then
        comms_symbol="$WARNING"
    fi
    echo -e "  ${comms_symbol} Hermes comms-check cron: $HERMES_COMMS_CRON_STATUS"

    completion_symbol="$CHECK_MARK"
    if [[ "$COMPLETION_LOG_RECONCILE_CRON_STATUS" == missing* ]]; then
        completion_symbol="$CROSS_MARK"
    elif [[ "$COMPLETION_LOG_RECONCILE_CRON_STATUS" == drift* ]]; then
        completion_symbol="$WARNING"
    fi
    echo -e "  ${completion_symbol} Completion log reconcile cron: $COMPLETION_LOG_RECONCILE_CRON_STATUS"

    if [ $VERIFICATION_ERRORS -gt 0 ]; then
        echo -e "  ${CROSS_MARK} $VERIFICATION_ERRORS errors found"
        exit 1
    elif [ $VERIFICATION_WARNINGS -gt 0 ]; then
        echo -e "  ${WARNING} $VERIFICATION_WARNINGS warnings found"
        exit 0
    else
        echo -e "  ${CHECK_MARK} All checks passed"
        exit 0
    fi
fi

# ============================================
# SECTION 7: RELATIONSHIPS install
# ============================================
echo ""
echo "════════════════════════════════"
echo "  [1/3] RELATIONSHIPS"
echo "════════════════════════════════"

# --- Install entity-resolver npm dependencies ---
echo ""
echo "Entity-resolver dependencies..."

ENTITY_RESOLVER_DIR="$SCRIPT_DIR/relationships/lib/entity-resolver"

if [ -d "$ENTITY_RESOLVER_DIR" ]; then
    cd "$ENTITY_RESOLVER_DIR"

    if [ -d "node_modules" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
        echo -e "  ${CHECK_MARK} Dependencies already installed (use --force to reinstall)"
    else
        echo "  Running npm install..."
        NPM_LOG=$(mktemp /tmp/npm-install-entity-resolver-XXXXXX.log)
        TMPFILES+=("$NPM_LOG")
        if npm install >"$NPM_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} npm install completed"
        else
            echo -e "  ${CROSS_MARK} npm install failed"
            tail -20 "$NPM_LOG"
        fi
    fi

    cd "$SCRIPT_DIR"
else
    echo -e "  ${WARNING} entity-resolver directory not found at $ENTITY_RESOLVER_DIR (skipping)"
fi

# --- Install entity-resolver to ~/.openclaw/lib/entity-resolver/ ---
# The semantic-recall hook dynamically imports entity-resolver from this location
# at runtime, since hooks are copied to ~/.openclaw/hooks/ where repo-relative
# paths don't exist.
echo ""
echo "Installing entity-resolver to ~/.openclaw/lib/entity-resolver/..."

ENTITY_RESOLVER_SRC="$SCRIPT_DIR/relationships/lib/entity-resolver"
ENTITY_RESOLVER_DST="$HOME/.openclaw/lib/entity-resolver"

if [ -d "$ENTITY_RESOLVER_SRC" ]; then
    mkdir -p "$ENTITY_RESOLVER_DST"

    # Copy source files (excluding node_modules and dist)
    copy_excluding "$ENTITY_RESOLVER_SRC" "$ENTITY_RESOLVER_DST"
    echo -e "  ${CHECK_MARK} entity-resolver source files copied"

    # Install npm dependencies in the target location
    if [ -f "$ENTITY_RESOLVER_DST/package.json" ]; then
        cd "$ENTITY_RESOLVER_DST"
        if [ -d "node_modules" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
            echo -e "  ${CHECK_MARK} Dependencies already installed at target (use --force to reinstall)"
        else
            echo "  Running npm install in target location..."
            NPM_LOG=$(mktemp /tmp/npm-install-entity-resolver-dst-XXXXXX.log)
            TMPFILES+=("$NPM_LOG")
            if npm install >"$NPM_LOG" 2>&1; then
                echo -e "  ${CHECK_MARK} npm install completed at $ENTITY_RESOLVER_DST"
            else
                echo -e "  ${CROSS_MARK} npm install failed at target"
                tail -20 "$NPM_LOG"
            fi
        fi
        cd "$SCRIPT_DIR"
    fi

    # Verify critical files exist at destination
    if [ -f "$ENTITY_RESOLVER_DST/index.ts" ] && [ -d "$ENTITY_RESOLVER_DST/node_modules" ]; then
        echo -e "  ${CHECK_MARK} entity-resolver installed to $ENTITY_RESOLVER_DST"
    elif [ -f "$ENTITY_RESOLVER_DST/index.ts" ]; then
        echo -e "  ${WARNING} entity-resolver files present but node_modules missing at $ENTITY_RESOLVER_DST"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    else
        echo -e "  ${CROSS_MARK} entity-resolver installation incomplete at $ENTITY_RESOLVER_DST"
        VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
    fi
else
    echo -e "  ${CROSS_MARK} entity-resolver source not found at $ENTITY_RESOLVER_SRC"
    echo -e "      This is required for the turn-context plugin's entity resolution."
    VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
fi

# --- Sync relationship hooks ---
echo ""
echo "Relationship hooks..."

HOOKS_TARGET="$OPENCLAW_DIR/hooks"
mkdir -p "$HOOKS_TARGET"

INSTALLED_HOOKS=()
SKIPPED_HOOKS=()

# Relationships does not have its own hooks/ dir; hooks come from memory/ and cognition/
# (No hook files are in relationships/; skip silently)

# --- Sync relationship skills ---
echo ""
echo "Relationship skills..."

REL_SKILLS_SOURCE="$SCRIPT_DIR/relationships/skills"
if [ -d "$REL_SKILLS_SOURCE" ]; then
    SKILLS_TARGET="$WORKSPACE/skills"
    mkdir -p "$SKILLS_TARGET"
    install_skills "$REL_SKILLS_SOURCE" "$SKILLS_TARGET" "relationship skills"
else
    echo -e "  ${INFO} No relationship skills directory found (skipping)"
fi

# ============================================
# SECTION 8: MEMORY install
# ============================================
echo ""
echo "════════════════════════════════"
echo "  [2/3] MEMORY"
echo "════════════════════════════════"

# --- Install shared PG loader libraries ---
echo ""
echo "Installing shared PG loader libraries..."
install_lib_files

# --- API key check ---
echo ""
echo "API key configuration..."

if [ -z "${OPENAI_API_KEY:-}" ]; then
    echo -e "  ${WARNING} OPENAI_API_KEY not set"
    echo "      Required for semantic recall (embeddings)."
    echo "      Set it in openclaw.json env.vars or export before running."
else
    echo -e "  ${CHECK_MARK} OPENAI_API_KEY set: ${OPENAI_API_KEY:0:8}..."
fi

# --- Database setup ---
echo ""
echo "Database setup..."

if psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' exists"
    if psql -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; then
        echo -e "  ${CHECK_MARK} Database connection verified"
    else
        echo -e "  ${CROSS_MARK} Cannot connect to database '$DB_NAME'"
        exit 1
    fi
else
    echo "  Creating database '$DB_NAME'..."
    _superuser_createdb "$DB_NAME" 2>/dev/null || {
        echo -e "  ${CROSS_MARK} Failed to create database '$DB_NAME'"
        exit 1
    }
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' created"
fi

# --- Python virtual environment ---
echo ""
echo "Python virtual environment setup..."

VENV_DIR="$HOME/.local/share/$USER/venv"
REQUIRED_PACKAGES=("openai" "tiktoken" "psycopg2-binary" "pillow" "json_repair" "pglast==6.16")

declare -A PACKAGE_MODULE_MAP=(
    ["psycopg2-binary"]="psycopg2"
    ["pillow"]="PIL"
)

pkg_import_name() {
    local pkg="$1"
    # Strip PEP 440 version specifiers (e.g. pglast==6.16) before mapping to
    # the importable module name.  Without this, "import pglast==6.16" is a
    # syntax error and the installer falsely reports the package missing.
    pkg="${pkg%%[<>=!~]*}"
    if [[ -v PACKAGE_MODULE_MAP["$pkg"] ]]; then
        echo "${PACKAGE_MODULE_MAP[$pkg]}"
    else
        echo "${pkg//-/_}"
    fi
}

if python3 -m venv --help &>/dev/null; then
    echo -e "  ${CHECK_MARK} python3-venv available"
else
    echo -e "  ${CROSS_MARK} python3-venv module not found"
    echo "  Install: sudo apt install python3-venv"
    exit 1
fi

if [ -d "$VENV_DIR" ]; then
    echo -e "  ${CHECK_MARK} Virtual environment exists at $VENV_DIR"
else
    mkdir -p "$(dirname "$VENV_DIR")"
    if python3 -m venv "$VENV_DIR" &>/dev/null; then
        echo -e "  ${CHECK_MARK} Virtual environment created at $VENV_DIR"
    else
        echo -e "  ${CROSS_MARK} Failed to create virtual environment"
        exit 1
    fi
fi

VENV_PYTHON="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"

PACKAGES_TO_INSTALL=()
PACKAGES_INSTALLED=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    mod=$(pkg_import_name "$package")
    if "$VENV_PYTHON" -c "import $mod" &>/dev/null; then
        PACKAGES_INSTALLED+=("$package")
    else
        PACKAGES_TO_INSTALL+=("$package")
    fi
done

[ ${#PACKAGES_INSTALLED[@]} -gt 0 ] && echo -e "  ${CHECK_MARK} ${#PACKAGES_INSTALLED[@]} packages already installed: ${PACKAGES_INSTALLED[*]}"

if [ ${#PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
    echo "  Installing missing packages: ${PACKAGES_TO_INSTALL[*]}"
    if "$VENV_PIP" install "${PACKAGES_TO_INSTALL[@]}" &>/dev/null; then
        echo -e "  ${CHECK_MARK} ${#PACKAGES_TO_INSTALL[@]} packages installed"
    else
        echo -e "  ${WARNING} Some packages failed to install"
        echo "      Try manually: $VENV_PIP install ${PACKAGES_TO_INSTALL[*]}"
        VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + 1))
    fi
else
    echo -e "  ${CHECK_MARK} All required packages already installed"
fi

# Verify
MISSING_PACKAGES=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    mod=$(pkg_import_name "$package")
    "$VENV_PYTHON" -c "import $mod" &>/dev/null || MISSING_PACKAGES+=("$package")
done
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo -e "  ${WARNING} Missing after install: ${MISSING_PACKAGES[*]}"
    VERIFICATION_WARNINGS=$((VERIFICATION_WARNINGS + ${#MISSING_PACKAGES[@]}))
else
    echo -e "  ${CHECK_MARK} All Python dependencies verified"
fi


# --- Schema management via pgschema ---
SCHEMA_FILE="$SCRIPT_DIR/database/schema.sql"

if [ ! -f "$SCHEMA_FILE" ]; then
    echo -e "  ${CROSS_MARK} database/schema.sql not found at $SCHEMA_FILE"
    exit 1
fi

SCHEMA_DIFF_SKIPPED=0

echo ""
echo "Schema management (pgschema)..."

# -- Extensions (use superuser for CREATE EXTENSION) --
echo "  Ensuring extensions..."
EXTENSIONS=$(grep -E "(^|INSTALLER HANDLES: )CREATE EXTENSION IF NOT EXISTS" "$SCHEMA_FILE" | sed "s/.*CREATE EXTENSION IF NOT EXISTS //;s/ .*//;s/;//" || true)
if [ -n "$EXTENSIONS" ]; then
    for ext in $EXTENSIONS; do
        if _superuser_psql "$DB_NAME" -tAc "SELECT 1 FROM pg_extension WHERE extname = '$ext'" | grep -q 1; then
            echo -e "  ${CHECK_MARK} Extension '$ext' already installed"
        else
            if _superuser_psql "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS \"$ext\";" >/dev/null 2>&1; then
                echo -e "  ${CHECK_MARK} Extension '$ext' installed"
            else
                echo -e "  ${CROSS_MARK} Extension '$ext' not installed — requires superuser"
                SCHEMA_DIFF_SKIPPED=1
            fi
        fi
    done
else
    echo -e "  ${INFO} No extensions defined in schema.sql"
fi

# -- Pre-migrations (use superuser for DDL) --
PRE_MIGRATIONS_DIR="$SCRIPT_DIR/database/pre-migrations"
if [ -d "$PRE_MIGRATIONS_DIR" ]; then
    PRE_MIGRATION_FILES=()
    while IFS= read -r -d '' f; do
        PRE_MIGRATION_FILES+=("$f")
    done < <(find "$PRE_MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" -print0 | sort -z)

    if [ ${#PRE_MIGRATION_FILES[@]} -gt 0 ]; then
        echo "  Running pre-migrations (${#PRE_MIGRATION_FILES[@]} files)..."
        for sql_file in "${PRE_MIGRATION_FILES[@]}"; do
            local_filename=$(basename "$sql_file")
            # Copy to /tmp so the superuser process can read it (nova-mind#663):
            # pre-migration files live under the agent's $HOME, which is mode
            # 0750 -- a distinct superuser unix user (PG_SUPERUSER != DB_USER)
            # cannot traverse into it. Mirrors the schema step's existing
            # /tmp-copy + chmod 644 pattern (see SCHEMA_FILE_TMP below).
            PRE_MIGRATION_FILE_TMP=$(mktemp /tmp/pgschema-premigration-XXXXXX.sql)
            TMPFILES+=("$PRE_MIGRATION_FILE_TMP")
            cp "$sql_file" "$PRE_MIGRATION_FILE_TMP"
            chmod 644 "$PRE_MIGRATION_FILE_TMP"
            if _superuser_psql "$DB_NAME" -f "$PRE_MIGRATION_FILE_TMP" >/dev/null 2>&1; then
                echo -e "  ${CHECK_MARK} Pre-migration: $local_filename"
            else
                echo -e "  ${CROSS_MARK} Pre-migration failed: $local_filename"
                SCHEMA_DIFF_SKIPPED=1
            fi
        done
    else
        echo -e "  ${INFO} No pre-migration scripts found"
    fi
fi

# -- Step 1.5: Apply declarative renames from renames.json before pgschema --
RENAMES_FILE="$SCRIPT_DIR/memory/database/renames.json"
if [ -f "$RENAMES_FILE" ]; then
    echo "  Processing renames.json (Step 1.5)..."
    # shellcheck disable=SC2034
    RENAME_COUNT=$(jq '[.renames[] | select(.column.from? != null)] | length' "$RENAMES_FILE" 2>/dev/null || echo "0")
    APPLIED=0
    SKIPPED=0

    # Process column renames
    while IFS= read -r entry; do
        table=$(echo "$entry" | jq -r '.table')
        col_from=$(echo "$entry" | jq -r '.column.from')
        col_to=$(echo "$entry" | jq -r '.column.to')
        pr=$(echo "$entry" | jq -r '.pr // "unknown"')

        # Check if the FROM column still exists (use DB_USER for reads)
        EXISTS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc \
            "SELECT COUNT(*) FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = '$table' AND column_name = '$col_from'" \
            2>/dev/null | tr -d '[:space:]')

        if [ "${EXISTS:-0}" -eq 1 ]; then
            # Use superuser for ALTER TABLE DDL
            if _superuser_psql "$DB_NAME" -c \
                "ALTER TABLE \"$table\" RENAME COLUMN \"$col_from\" TO \"$col_to\";" >/dev/null 2>&1; then
                echo -e "  ${CHECK_MARK} Renamed $table.$col_from → $col_to ($pr)"
                APPLIED=$((APPLIED + 1))
            else
                echo -e "  ${CROSS_MARK} Failed to rename $table.$col_from → $col_to"
                SCHEMA_DIFF_SKIPPED=1
            fi
        else
            echo -e "  ${INFO} $table.$col_from already renamed (skipping)"
            SKIPPED=$((SKIPPED + 1))
        fi
    done < <(jq -c '.renames[] | select(.column.from? != null)' "$RENAMES_FILE" 2>/dev/null)

    # Process table renames
    while IFS= read -r entry; do
        tbl_from=$(echo "$entry" | jq -r '.table.from')
        tbl_to=$(echo "$entry" | jq -r '.table.to')
        pr=$(echo "$entry" | jq -r '.pr // "unknown"')

        EXISTS=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc \
            "SELECT COUNT(*) FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = '$tbl_from'" \
            2>/dev/null | tr -d '[:space:]')

        if [ "${EXISTS:-0}" -eq 1 ]; then
            # Use superuser for ALTER TABLE DDL
            if _superuser_psql "$DB_NAME" -c \
                "ALTER TABLE \"$tbl_from\" RENAME TO \"$tbl_to\";" >/dev/null 2>&1; then
                echo -e "  ${CHECK_MARK} Renamed table $tbl_from → $tbl_to ($pr)"
                APPLIED=$((APPLIED + 1))
            else
                echo -e "  ${CROSS_MARK} Failed to rename table $tbl_from → $tbl_to"
                SCHEMA_DIFF_SKIPPED=1
            fi
        else
            echo -e "  ${INFO} Table $tbl_from already renamed (skipping)"
            SKIPPED=$((SKIPPED + 1))
        fi
    done < <(jq -c '.renames[] | select(.table | type == "object")' "$RENAMES_FILE" 2>/dev/null)

    echo -e "  ${INFO} Renames: $APPLIED applied, $SKIPPED skipped"
else
    echo -e "  ${INFO} No renames.json found — skipping Step 1.5"
fi

# Peer-shadowed relation detection must run before pgschema plans; it queries
# the target DB to find foreign tables/views that shadow tables declared by
# schema.sql. On failure the installer fails closed and skips the apply stage.
PEER_SHADOWED_NAMES=()
PEER_SHADOWED_RELKINDS=()
PEER_SHADOWED_KINDS=()
PGSCHEMA_PEER_MODE=0
PGSCHEMA_IGNORE_BASE="$SCRIPT_DIR/database/.pgschemaignore"

if [ "$SCHEMA_DIFF_SKIPPED" -eq 0 ]; then
    if ! _resolve_peer_shadowed_relations; then
        SCHEMA_DIFF_SKIPPED=1
    fi
fi

if [ "$SCHEMA_DIFF_SKIPPED" -eq 1 ]; then
    echo -e "  ${WARNING} Skipping pgschema plan/apply (pre-schema step failed above)"
else
    # Build connection args for DDL operations.
    # When superuser differs from DB_USER, _superuser_pgschema runs via sudo -u,
    # so peer auth works with the unix socket — no password needed.
    PGSCHEMA_CONN_ARGS=(
        "--host" "/var/run/postgresql"
        "--port" "${PGPORT:-5432}"
        "--db" "$DB_NAME"
        "--user" "$PG_SUPERUSER"
    )
    PGSCHEMA_PLAN_ARGS=(
        "--plan-host" "/var/run/postgresql"
        "--plan-port" "${PGPORT:-5432}"
        "--plan-db" "$DB_NAME"
        "--plan-user" "$PG_SUPERUSER"
    )

    # Use a dedicated non-sticky scratch directory for the plan/reorder/apply
    # cycle (nova-mind#664). /tmp has the sticky bit (1777), which blocks the
    # agent user from renaming a file over a file owned by the postgres user.
    # A fresh mktemp -d directory has no sticky bit and, with mode 777, lets
    # both the agent user and postgres create and rename files inside it.
    PGSCHEMA_SCRATCH_DIR=$(mktemp -d /tmp/pgschema-scratch-XXXXXX)
    TMPDIRS+=("$PGSCHEMA_SCRATCH_DIR")
    chmod 777 "$PGSCHEMA_SCRATCH_DIR"

    # pgschema discovers .pgschemaignore from cwd, so copy the selected ignore
    # file into the scratch directory and plan from there. This also fixes the
    # prior discovery gap where the file lived in database/ but planning ran
    # from the repo root.
    # In peer mode, dynamically inject the detected shadowed relations into the
    # [tables] and [views] sections so pgschema itself ignores them during
    # planning.  Everything else stays in .pgschemaignore-peer for objects that
    # cannot be derived from relkind f/v (functions, triggers, etc.).
    cp "$PGSCHEMA_IGNORE_BASE" "$PGSCHEMA_SCRATCH_DIR/.pgschemaignore"
    chmod 644 "$PGSCHEMA_SCRATCH_DIR/.pgschemaignore"
    if [ "${#PEER_SHADOWED_NAMES[@]}" -gt 0 ]; then
        names_csv=$(IFS=,; echo "${PEER_SHADOWED_NAMES[*]}")
        relkinds_csv=$(IFS=,; echo "${PEER_SHADOWED_RELKINDS[*]}")
        "$VENV_PYTHON" "$SCRIPT_DIR/database/inject_peer_shadowed_ignores.py" \
            --ignore-file "$PGSCHEMA_SCRATCH_DIR/.pgschemaignore" \
            --names "$names_csv" \
            --relkinds "$relkinds_csv"
    fi
    pushd "$PGSCHEMA_SCRATCH_DIR" >/dev/null || exit 1

    # PLAN_FILE is written by pgschema running as the superuser, so do not
    # pre-create it; let the superuser create the inode fresh.
    PLAN_FILE="$PGSCHEMA_SCRATCH_DIR/plan.json"

    # Copy schema file into the scratch dir so the superuser process can read it
    # (the agent's home directory may not be traversable by the superuser unix user)
    SCHEMA_FILE_TMP=$(mktemp "$PGSCHEMA_SCRATCH_DIR/schema-XXXXXX.sql")
    cp "$SCHEMA_FILE" "$SCHEMA_FILE_TMP"
    chmod 644 "$SCHEMA_FILE_TMP"

    echo "  Running pgschema plan (as superuser $PG_SUPERUSER)..."
    PLAN_EXIT=0
    _superuser_pgschema plan \
        "${PGSCHEMA_CONN_ARGS[@]}" \
        --schema public \
        --file "$SCHEMA_FILE_TMP" \
        "${PGSCHEMA_PLAN_ARGS[@]}" \
        --output-json "$PLAN_FILE" \
        --no-color 2>&1 || PLAN_EXIT=$?

    if [ $PLAN_EXIT -ne 0 ]; then
        echo -e "  ${CROSS_MARK} pgschema plan failed (exit $PLAN_EXIT) — schema apply skipped"
        SCHEMA_DIFF_SKIPPED=1
    else
        # REORDERED_PLAN_FILE is written by plan_reorder.py (agent user) and
        # then moved over the superuser-owned plan file, so keep it in the
        # scratch directory with no sticky bit.
        REORDERED_PLAN_FILE="$PGSCHEMA_SCRATCH_DIR/reordered.json"
        echo "  Reordering plan by dependencies..."
        REORDER_EXIT=0
        "$VENV_PYTHON" "$SCRIPT_DIR/database/plan_reorder.py" \
            --plan "$PLAN_FILE" \
            --output "$REORDERED_PLAN_FILE" 2>&1 || REORDER_EXIT=$?
        DO_APPLY=1
        if [ $REORDER_EXIT -eq 0 ]; then
            mv "$REORDERED_PLAN_FILE" "$PLAN_FILE"
            chmod 644 "$PLAN_FILE"
            echo -e "  ${CHECK_MARK} Plan reordered by dependencies"
        else
            echo -e "  ${CROSS_MARK} Plan reorder failed (exit $REORDER_EXIT) — schema apply skipped"
            SCHEMA_DIFF_SKIPPED=1
            DO_APPLY=0
        fi

        if [ "$DO_APPLY" -eq 1 ]; then
            # Strip all destructive (DROP) operations from the plan.
            # Additive-by-construction: unknown/local tables live untouched;
            # only CREATE/ALTER ADD/etc. steps are applied (#498).
            FILTERED_PLAN_FILE="$PGSCHEMA_SCRATCH_DIR/filtered.json"
            echo "  Stripping destructive operations from plan..."
            STRIP_EXIT=0
            STRIP_ARGS=(
                --plan "$PLAN_FILE"
                --output "$FILTERED_PLAN_FILE"
            )
            if [ "$PGSCHEMA_PEER_MODE" -eq 1 ]; then
                # Peer-shadowed relations (VIEW / foreign table + sequence +
                # triggers + privileges + comments + constraints + indexes) are
                # owned by the FDW setup (#520), not schema.sql. Strip every plan
                # step that refers to them (#608 / #1231).
                ignored_csv=$(IFS=,; echo "${PEER_SHADOWED_NAMES[*]}")
                STRIP_ARGS+=(--ignore-objects "$ignored_csv" --log-exclusions)
            fi
            DESTRUCTIVE_COUNT=$("$VENV_PYTHON" "$SCRIPT_DIR/database/strip_destructive.py" "${STRIP_ARGS[@]}" 2>&1) || STRIP_EXIT=$?

            if [ $STRIP_EXIT -ne 0 ]; then
                echo -e "  ${CROSS_MARK} Failed to strip destructive operations from plan"
                SCHEMA_DIFF_SKIPPED=1
            else
                mv "$FILTERED_PLAN_FILE" "$PLAN_FILE"
                chmod 644 "$PLAN_FILE"
                if [ "${DESTRUCTIVE_COUNT:-0}" -gt 0 ] 2>/dev/null; then
                    echo -e "  ${INFO} Stripped $DESTRUCTIVE_COUNT destructive operation(s) (DROP skipped; #498)"
                fi

                TOTAL_STEPS=$(jq '[(.groups // [])[] | .steps[] | select(.type != "privilege")] | length' "$PLAN_FILE" 2>/dev/null || echo "0")

                if [ "$TOTAL_STEPS" -eq 0 ] 2>/dev/null; then
                    echo -e "  ${CHECK_MARK} Schema is up to date — no changes needed"
                else
                    echo "  Applying $TOTAL_STEPS schema change(s)..."
                    APPLY_EXIT=0
                    _superuser_pgschema apply \
                        "${PGSCHEMA_CONN_ARGS[@]}" \
                        --schema public \
                        --plan "$PLAN_FILE" \
                        --auto-approve \
                        --no-color 2>&1 || APPLY_EXIT=$?

                    if [ $APPLY_EXIT -eq 0 ]; then
                        echo -e "  ${CHECK_MARK} Schema applied successfully"
                        TABLE_COUNT=$(psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'" | tr -d '[:space:]')
                        echo "      Total tables in database: $TABLE_COUNT"

                        # Reassign ownership of all objects to the agent user
                        if [ "$PG_SUPERUSER" != "$DB_USER" ]; then
                            echo "  Reassigning ownership to '$DB_USER'..."
                            if _superuser_psql "$DB_NAME" -c "REASSIGN OWNED BY \"$PG_SUPERUSER\" TO \"$DB_USER\";" >/dev/null 2>&1; then
                                echo -e "  ${CHECK_MARK} Ownership reassigned to '$DB_USER'"
                            else
                                echo -e "  ${WARNING} Could not reassign ownership (objects may be owned by $PG_SUPERUSER)"
                            fi
                        fi

                        # Post-schema grant reconciliation (#452): pgschema deliberately
                        # ignores privilege steps, so explicit GRANT/REVOKE lines in
                        # schema.sql must be applied separately to survive fresh installs.
                        # Peer-shadowed relations (foreign tables/views managed by the
                        # peer FDW setup, #520) and their default <name>_id_seq sequences
                        # do not exist locally, so skip any GRANT/REVOKE that targets them.
                        echo "  Reconciling explicit schema grants..."
                        GRANT_ALL_COUNT=$(grep -cE '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$SCHEMA_FILE_TMP" 2>/dev/null || echo 0)
                        if [ "$GRANT_ALL_COUNT" -gt 0 ] 2>/dev/null; then
                            GRANT_EXTRACT_FILE=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-extract-XXXXXX.sql")
                            GRANT_FILTERED_FILE=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-filtered-XXXXXX.sql")
                            TMPFILES+=("$GRANT_EXTRACT_FILE" "$GRANT_FILTERED_FILE")
                            grep -E '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$SCHEMA_FILE_TMP" >"$GRANT_EXTRACT_FILE"
                            GRANT_FILTER_ARGS=()
                            if [ "${#PEER_SHADOWED_NAMES[@]}" -gt 0 ]; then
                                shadowed_csv=$(IFS=,; echo "${PEER_SHADOWED_NAMES[*]}")
                                GRANT_FILTER_ARGS+=(--shadowed-names "$shadowed_csv")
                            fi
                            if "$VENV_PYTHON" "$SCRIPT_DIR/database/filter_shadowed_grants.py" "${GRANT_FILTER_ARGS[@]}" <"$GRANT_EXTRACT_FILE" >"$GRANT_FILTERED_FILE" 2>"$GRANT_FILTERED_FILE.stderr"; then
                                if [ -s "$GRANT_FILTERED_FILE.stderr" ]; then
                                    while IFS= read -r line; do
                                        echo -e "  ${INFO} $line"
                                    done < "$GRANT_FILTERED_FILE.stderr"
                                fi
                                GRANT_COUNT=$(grep -cE '^[[:space:]]*(GRANT|REVOKE)[[:space:]]+' "$GRANT_FILTERED_FILE" 2>/dev/null || echo 0)
                                if [ "$GRANT_COUNT" -gt 0 ] 2>/dev/null; then
                                    GRANT_PSQL_ERR=$(mktemp "$PGSCHEMA_SCRATCH_DIR/grants-psqlerr-XXXXXX")
                                    TMPFILES+=("$GRANT_PSQL_ERR")
                                    if _superuser_psql "$DB_NAME" -v ON_ERROR_STOP=1 -f - >/dev/null 2>"$GRANT_PSQL_ERR" <"$GRANT_FILTERED_FILE"; then
                                        echo -e "  ${CHECK_MARK} Applied $GRANT_COUNT explicit grant/revoke statement(s)"
                                    else
                                        echo -e "  ${CROSS_MARK} Grant reconciliation failed"
                                        if [ -s "$GRANT_PSQL_ERR" ]; then
                                            echo "  psql errors (first ~20 ERROR lines):"
                                            grep -E '^ERROR:' "$GRANT_PSQL_ERR" | head -20 | sed 's/^/    /'
                                        fi
                                        SCHEMA_DIFF_SKIPPED=1
                                    fi
                                else
                                    echo -e "  ${INFO} No explicit grant/revoke statements remain after peer-shadowed filtering"
                                fi
                            else
                                echo -e "  ${CROSS_MARK} Failed to filter peer-shadowed grant statements"
                                SCHEMA_DIFF_SKIPPED=1
                            fi
                        else
                            echo -e "  ${INFO} No explicit grant/revoke statements found"
                        fi
                    else
                        echo -e "  ${CROSS_MARK} Schema apply failed (exit $APPLY_EXIT)"
                        SCHEMA_DIFF_SKIPPED=1
                    fi
                fi
            fi
        fi
    fi

    popd >/dev/null || true
    rm -f "$PLAN_FILE"
fi

# --- Schema apply exit-code gate (#597 / #498) ---
if [ "$SCHEMA_DIFF_SKIPPED" -eq 1 ]; then
    echo ""
    echo -e "  ${CROSS_MARK} Schema apply stage failed — installation aborting"
    exit 1
fi

# --- Memory hooks ---
echo ""
echo "Memory hooks installation..."

HOOKS_TARGET="$OPENCLAW_DIR/hooks"
mkdir -p "$HOOKS_TARGET"

# Note: semantic-recall and agent-turn-context were replaced by turn-context plugin (#182).
# Note: memory-extract was migrated to a plugin (#726) and is no longer installed as a hook.
install_hook "session-init" "$SCRIPT_DIR/memory/hooks" && result=$? || result=$?
if [ "$result" -eq 0 ]; then
    INSTALLED_HOOKS+=("session-init")
elif [ "$result" -eq 2 ]; then
    SKIPPED_HOOKS+=("session-init")
fi

# --- Memory-extract plugin (replaces the legacy memory-extract hook) ---
echo ""
echo "Memory-extract plugin installation..."

_install_memory_extract_plugin "$SCRIPT_DIR/memory/plugins/memory-extract" "$EXTENSIONS_DIR/memory-extract" || exit 1

# --- Memory scripts ---
echo ""
echo "Memory scripts setup..."

SCRIPTS_SOURCE="$SCRIPT_DIR/memory/scripts"
SCRIPTS_TARGET_WORKSPACE="$WORKSPACE/scripts"
SCRIPTS_TARGET_OPENCLAW="$HOME/.openclaw/scripts"

mkdir -p "$OPENCLAW_LOGS_DIR"
echo -e "  ${INFO} Logs directory: $OPENCLAW_LOGS_DIR"

if [ -d "$SCRIPTS_SOURCE" ]; then
    mkdir -p "$SCRIPTS_TARGET_WORKSPACE"
    mkdir -p "$SCRIPTS_TARGET_OPENCLAW"

    scripts_copied=0

    for source_file in "$SCRIPTS_SOURCE"/*.sh "$SCRIPTS_SOURCE"/*.py "$SCRIPTS_SOURCE"/*.json; do
        [ -f "$source_file" ] || continue
        filename=$(basename "$source_file")
        target_file_workspace="$SCRIPTS_TARGET_WORKSPACE/$filename"
        target_file_openclaw="$SCRIPTS_TARGET_OPENCLAW/$filename"

        if [ "$FORCE_INSTALL" -eq 0 ]; then
            source_hash=$(sha256sum "$source_file" | awk '{print $1}')
            workspace_matches=0
            openclaw_matches=0
            if [ -f "$target_file_workspace" ]; then
                wh=$(sha256sum "$target_file_workspace" | awk '{print $1}')
                [ "$source_hash" = "$wh" ] && workspace_matches=1
            fi
            if [ -f "$target_file_openclaw" ]; then
                oh=$(sha256sum "$target_file_openclaw" | awk '{print $1}')
                [ "$source_hash" = "$oh" ] && openclaw_matches=1
            fi
            [ "$workspace_matches" -eq 1 ] && [ "$openclaw_matches" -eq 1 ] && continue
        fi

        cp "$source_file" "$target_file_workspace"
        cp "$source_file" "$target_file_openclaw"
        scripts_copied=$((scripts_copied + 1))
    done

    echo -e "  ${CHECK_MARK} $scripts_copied scripts installed to:"
    echo "      • $SCRIPTS_TARGET_WORKSPACE"
    echo "      • $SCRIPTS_TARGET_OPENCLAW"

    # Make all scripts executable
    SCRIPT_COUNT=0
    for location in "$SCRIPTS_TARGET_WORKSPACE" "$SCRIPTS_TARGET_OPENCLAW"; do
        for script in "$location"/*.sh "$location"/*.py; do
            [ -f "$script" ] || continue
            chmod +x "$script"
            SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
        done
    done
    echo -e "  ${CHECK_MARK} Made $SCRIPT_COUNT scripts executable"

    # Verify critical config files were deployed
    CRITICAL_CONFIGS=("embedding-config.json" "memory-extraction-config.json")
    for cfg in "${CRITICAL_CONFIGS[@]}"; do
        if [ ! -f "$SCRIPTS_TARGET_OPENCLAW/$cfg" ]; then
            if [ -f "$SCRIPTS_SOURCE/$cfg" ]; then
                cp "$SCRIPTS_SOURCE/$cfg" "$SCRIPTS_TARGET_OPENCLAW/$cfg"
                cp "$SCRIPTS_SOURCE/$cfg" "$SCRIPTS_TARGET_WORKSPACE/$cfg" 2>/dev/null || true
                echo -e "  ${CHECK_MARK} $cfg deployed (missed by glob, copied explicitly)"
            else
                echo -e "  ${CROSS_MARK} Critical config $cfg not found in source ($SCRIPTS_SOURCE)"
                VERIFICATION_ERRORS=$((VERIFICATION_ERRORS + 1))
            fi
        else
            echo -e "  ${CHECK_MARK} $cfg present"
        fi
    done

    # --- Template scripts (install-if-not-exists) ---
    TEMPLATES_SOURCE="$SCRIPT_DIR/memory/templates"
    if [ -d "$TEMPLATES_SOURCE" ]; then
        templates_installed=0
        templates_skipped=0
        for source_file in "$TEMPLATES_SOURCE"/*.py "$TEMPLATES_SOURCE"/*.sh; do
            [ -f "$source_file" ] || continue
            filename=$(basename "$source_file")
            for target_dir in "$SCRIPTS_TARGET_WORKSPACE" "$SCRIPTS_TARGET_OPENCLAW"; do
                if [ "$FORCE_INSTALL" -eq 1 ] || [ ! -f "$target_dir/$filename" ]; then
                    cp "$source_file" "$target_dir/$filename"
                    chmod +x "$target_dir/$filename"
                    templates_installed=$((templates_installed + 1))
                else
                    templates_skipped=$((templates_skipped + 1))
                fi
            done
        done
        if [ "$templates_installed" -gt 0 ]; then
            echo -e "  ${CHECK_MARK} $templates_installed template(s) installed"
        fi
        if [ "$templates_skipped" -gt 0 ]; then
            echo -e "  ${INFO} $templates_skipped template(s) skipped (local copy exists)"
        fi
    fi

    # --- Cleanup deprecated individual embedding scripts ---
    DEPRECATED_SCRIPTS=("embed-full-database.py" "embed-research.py" "embed-memories.py" "embed-library.py")
    deprecated_removed=0
    for script_name in "${DEPRECATED_SCRIPTS[@]}"; do
        for target_dir in "$SCRIPTS_TARGET_WORKSPACE" "$SCRIPTS_TARGET_OPENCLAW"; do
            if [ -f "$target_dir/$script_name" ]; then
                rm "$target_dir/$script_name"
                deprecated_removed=$((deprecated_removed + 1))
            fi
        done
    done
    if [ "$deprecated_removed" -gt 0 ]; then
        echo -e "  ${CHECK_MARK} Removed $deprecated_removed deprecated embedding script(s)"
    fi

    # Check Python dependencies
    if ls "$SCRIPTS_TARGET_WORKSPACE"/*.py &>/dev/null; then
        MISSING_DEPS=()
        for dep in "psycopg2" "anthropic" "openai"; do
            python3 -c "import $dep" 2>/dev/null || MISSING_DEPS+=("$dep")
        done
        if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
            echo -e "  ${WARNING} Missing Python dependencies: ${MISSING_DEPS[*]}"
            echo "      Install: pip3 install ${MISSING_DEPS[*]}"
        else
            echo -e "  ${CHECK_MARK} Python dependencies verified"
        fi
    fi

    # --- Daily memory log cron entries ---
    _install_daily_log_cron

    # --- D100 roll announcer cron entry ---
    _install_announce_d100_cron

    # --- Completion log reconcile cron entry (issue #562) ---
    _install_completion_log_reconcile_cron
else
    echo -e "  ${WARNING} Scripts directory not found at $SCRIPTS_SOURCE (skipping)"
fi

# --- Comms scripts (issue #474) ---
echo ""
echo "Comms scripts setup..."

COMMS_SCRIPTS_SOURCE="$SCRIPT_DIR/scripts/comms"
COMMS_SCRIPTS_TARGET="$HOME/.openclaw/scripts/comms"
if [ -d "$COMMS_SCRIPTS_SOURCE" ]; then
    mkdir -p "$COMMS_SCRIPTS_TARGET"
    comms_copied=0
    for source_file in "$COMMS_SCRIPTS_SOURCE"/*.py "$COMMS_SCRIPTS_SOURCE"/*.sh; do
        [ -f "$source_file" ] || continue
        filename=$(basename "$source_file")
        target_file="$COMMS_SCRIPTS_TARGET/$filename"
        if [ "$FORCE_INSTALL" -eq 1 ] || [ ! -f "$target_file" ] || \
           [ "$(sha256sum "$source_file" | awk '{print $1}')" != "$(sha256sum "$target_file" | awk '{print $1}')" ]; then
            cp "$source_file" "$target_file"
            chmod +x "$target_file"
            comms_copied=$((comms_copied + 1))
        fi
    done
    echo -e "  ${CHECK_MARK} $comms_copied comms script(s) installed to $COMMS_SCRIPTS_TARGET"

    # --- Consolidated Hermes comms-check cron entry ---
    _install_hermes_comms_check_cron
else
    echo -e "  ${WARNING} Comms scripts directory not found at $COMMS_SCRIPTS_SOURCE (skipping)"
fi

# --- Memory skills ---
echo ""
echo "Memory skills installation..."

MEM_SKILLS_SOURCE="$SCRIPT_DIR/memory/skills"
if [ -d "$MEM_SKILLS_SOURCE" ]; then
    install_skills "$MEM_SKILLS_SOURCE" "$HOME/.openclaw/skills" "memory skills"
else
    echo -e "  ${INFO} No memory skills directory found (skipping)"
fi

# --- OpenClaw config patching (enable-hooks) ---
echo ""
echo "OpenClaw config patching (memory hooks)..."

OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"
ENABLE_HOOKS_SCRIPT="$SCRIPTS_TARGET_OPENCLAW/enable-hooks.sh"

if ! command -v jq &>/dev/null; then
    echo -e "  ${WARNING} jq not installed — skipping config patching"
elif [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo -e "  ${WARNING} OpenClaw config not found at $OPENCLAW_CONFIG — skipping"
elif [ ! -f "$ENABLE_HOOKS_SCRIPT" ]; then
    echo -e "  ${WARNING} enable-hooks.sh not found — skipping"
else
    chmod +x "$ENABLE_HOOKS_SCRIPT"
    echo "  Enabling nova-memory hooks in OpenClaw config..."
    if "$ENABLE_HOOKS_SCRIPT" "$OPENCLAW_CONFIG" >/dev/null 2>&1; then
        echo -e "  ${CHECK_MARK} Hooks enabled in OpenClaw config"
        echo "      • memory-extract"
        echo "      • session-init"
        GATEWAY_RESTART_NEEDED=1
    else
        echo -e "  ${WARNING} Failed to patch OpenClaw config"
        echo "      Run manually: $ENABLE_HOOKS_SCRIPT"
    fi
fi

# ============================================
# SECTION 9: COGNITION install
# ============================================
echo ""
echo "════════════════════════════════"
echo "  [3/3] COGNITION"
echo "════════════════════════════════"

# --- Database setup for cognition (idempotent, may already exist) ---
echo ""
echo "Database check (cognition)..."

if psql -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' exists"
else
    echo "  Creating database '$DB_NAME'..."
    _superuser_createdb "$DB_NAME" || { echo -e "  ${CROSS_MARK} Failed to create database"; exit 1; }
    echo -e "  ${CHECK_MARK} Database '$DB_NAME' created"
fi

# --- Configure PostgreSQL password file (memory DB only) ---
echo ""
echo "PostgreSQL password file..."

if [ -n "${PGPASSWORD:-}" ]; then
    pgpass_changed=0
    _ensure_pgpass_entry "localhost" "5432" "$DB_NAME" "$DB_USER" "$PGPASSWORD" && pgpass_changed=1
    _ensure_pgpass_entry "127.0.0.1" "5432" "$DB_NAME" "$DB_USER" "$PGPASSWORD" && pgpass_changed=1
    if [ "$pgpass_changed" -eq 1 ]; then
        echo -e "  ${CHECK_MARK} Updated ~/.pgpass with memory DB entries"
    else
        echo -e "  ${CHECK_MARK} ~/.pgpass entries already correct"
    fi
else
    echo -e "  ${WARNING} PGPASSWORD not set — skipping ~/.pgpass provisioning"
fi

# --- Optional agent_chat peer integration (nova-mind#579) ---
_agent_chat_integrate_peer

# --- generate-delegation-context.sh ---
echo ""
echo "generate-delegation-context.sh..."

GENERATE_DELEGATION_SOURCE="$SCRIPT_DIR/cognition/scripts/generate-delegation-context.sh"
GENERATE_DELEGATION_TARGET="$HOME/.openclaw/workspace/scripts/generate-delegation-context.sh"

if [ ! -f "$GENERATE_DELEGATION_SOURCE" ]; then
    echo -e "  ${WARNING} generate-delegation-context.sh source not found (skipping)"
else
    mkdir -p "$(dirname "$GENERATE_DELEGATION_TARGET")"
    cp "$GENERATE_DELEGATION_SOURCE" "$GENERATE_DELEGATION_TARGET"
    chmod +x "$GENERATE_DELEGATION_TARGET"
    echo -e "  ${CHECK_MARK} Installed generate-delegation-context.sh → $GENERATE_DELEGATION_TARGET"
fi

# --- agent_chat extension (moved to NOVA-Openclaw/agent-chat, nova-mind#579) ---
# If a bus is detected, _agent_chat_integrate_peer() already invoked the peer
# repo's install-plugin.sh to build/sync the extension. Nothing to do here.

# --- Cognition focus skills (managed tier — all sessions) ---
echo ""
echo "Cognition focus skills installation..."

COG_SKILLS_SOURCE="$SCRIPT_DIR/cognition/focus/skills"
if [ -d "$COG_SKILLS_SOURCE" ]; then
    install_skills "$COG_SKILLS_SOURCE" "$HOME/.openclaw/skills" "cognition skills"
else
    echo -e "  ${INFO} No cognition focus skills directory found (skipping)"
fi

# --- Remove old hooks replaced by turn-context plugin ---
echo ""
echo "Cleaning up old hooks replaced by turn-context plugin..."

for old_hook in "semantic-recall" "agent-turn-context"; do
    OLD_HOOK_DIR="$OPENCLAW_DIR/hooks/$old_hook"
    if [ -d "$OLD_HOOK_DIR" ]; then
        rm -rf "$OLD_HOOK_DIR"
        echo -e "  ${CHECK_MARK} Removed old hook: $old_hook"
        # shellcheck disable=SC2034
        GATEWAY_RESTART_NEEDED=1
    fi
done

# --- Turn-context plugin (replaces old semantic-recall + agent-turn-context hooks) ---
echo ""
echo "Turn-context plugin installation..."

_install_turn_context_plugin "$SCRIPT_DIR/memory/plugins/turn-context" "$OPENCLAW_DIR/plugins/turn-context" || exit 1

# --- Metacognition plugins (self-awareness, confidence-check) ---
echo ""
echo "Metacognition plugins installation..."


install_metacognition_plugin "self-awareness" \
    "$SCRIPT_DIR/cognition/metacognition/self-awareness" \
    "$OPENCLAW_DIR/plugins/self-awareness"

# confidence-check plugin DISABLED — do NOT install.
# The plugin's Phase 1 self-verification forces a revision turn that is
# incompatible with group-chat NO_REPLY behavior, causing real responses
# to be swallowed. See nova-mind issue #342 for the upstream fix.
# Re-enable ONLY after #342 is resolved and the plugin is group-chat-safe.
#
# install_metacognition_plugin "confidence-check" \
#     "$SCRIPT_DIR/cognition/metacognition/confidence-check" \
#     "$OPENCLAW_DIR/plugins/confidence-check"

# --- Bootstrap context system ---
echo ""
echo "Bootstrap context system installation..."

BOOTSTRAP_SOURCE="$SCRIPT_DIR/cognition/focus/bootstrap-context"
BOOTSTRAP_TARGET="$OPENCLAW_DIR/hooks/db-bootstrap-context"

if [ -d "$BOOTSTRAP_SOURCE" ]; then
    echo "  Syncing bootstrap-context files..."
    sync_directory "$BOOTSTRAP_SOURCE" "$BOOTSTRAP_TARGET" "bootstrap-context files"

    # Install runtime dependencies if package.json exists (#598)
    if [ -f "$BOOTSTRAP_TARGET/package.json" ]; then
        _install_runtime_dependencies "$BOOTSTRAP_TARGET" "bootstrap-context" || true
    fi

    # Run the DB setup script
    if [ -f "$BOOTSTRAP_TARGET/install.sh" ]; then
        echo "  Running bootstrap-context DB setup..."
        cd "$BOOTSTRAP_TARGET"
        export DB_NAME="$DB_NAME"
        BOOTSTRAP_LOG="${TMPDIR:-/tmp}/bootstrap-install-$$.log"
        if bash install.sh >"$BOOTSTRAP_LOG" 2>&1; then
            echo -e "  ${CHECK_MARK} Bootstrap context DB setup complete"
            rm -f "$BOOTSTRAP_LOG"
        else
            echo -e "  ${WARNING} Bootstrap context DB setup had issues"
            tail -10 "$BOOTSTRAP_LOG"
        fi
        cd "$SCRIPT_DIR"
    fi
else
    echo -e "  ${WARNING} Bootstrap context source not found at $BOOTSTRAP_SOURCE (skipping)"
fi

# --- agent_config_sync extension ---
echo ""
echo "Agent config sync extension installation..."

AGENT_CONFIG_SYNC_SOURCE="$SCRIPT_DIR/cognition/focus/agent-config-sync"
AGENT_CONFIG_SYNC_TARGET="$EXTENSIONS_DIR/agent_config_sync"

if [ -d "$AGENT_CONFIG_SYNC_SOURCE" ]; then
    echo "  Syncing agent-config-sync extension files..."
    mkdir -p "$AGENT_CONFIG_SYNC_TARGET"
    sync_directory "$AGENT_CONFIG_SYNC_SOURCE" "$AGENT_CONFIG_SYNC_TARGET" "agent-config-sync files"

    # Build in the source directory and copy dist/ to the target so the target
    # only contains runtime dependencies (#598, #724).
    echo "  Building agent_config_sync TypeScript..."
    _install_plugin_build_dependencies "$AGENT_CONFIG_SYNC_SOURCE" "agent_config_sync" || true

    NPM_BUILD_LOG="${TMPDIR:-/tmp}/npm-build-config-sync-$$.log"
    if (cd "$AGENT_CONFIG_SYNC_SOURCE" && "$AGENT_CONFIG_SYNC_SOURCE/node_modules/.bin/tsc") >"$NPM_BUILD_LOG" 2>&1; then
        mkdir -p "$AGENT_CONFIG_SYNC_TARGET/dist"
        cp -r "$AGENT_CONFIG_SYNC_SOURCE/dist/"* "$AGENT_CONFIG_SYNC_TARGET/dist/"
        echo -e "  ${CHECK_MARK} agent_config_sync build completed"
        rm -f "$NPM_BUILD_LOG"
    else
        echo -e "  ${CROSS_MARK} agent_config_sync build failed"
        tail -20 "$NPM_BUILD_LOG"
    fi

    # Install runtime dependencies in the target directory (#598)
    _install_runtime_dependencies "$AGENT_CONFIG_SYNC_TARGET" "agent_config_sync" || true

    cd "$SCRIPT_DIR"

    # Remove legacy agent-config-db hook if present
    if [ -d "$OPENCLAW_DIR/hooks/agent-config-db" ]; then
        rm -rf "$OPENCLAW_DIR/hooks/agent-config-db"
        echo -e "  ${CHECK_MARK} Removed legacy agent-config-db hook"
    fi

    # Enable plugin in openclaw.json
    OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"
    if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
        echo "  Enabling agent_config_sync plugin in config..."

        jq --arg database "$DB_NAME" \
           --arg user "$DB_USER" \
            '.plugins.entries.agent_config_sync = (.plugins.entries.agent_config_sync // {}) * {
                "enabled": true,
                "config": {
                    "database": $database,
                    "host": "localhost",
                    "port": 5432,
                    "user": $user,
                    "password": ""
                }
            }' \
            "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
            mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
            echo -e "  ${CHECK_MARK} agent_config_sync plugin enabled" || \
            echo -e "  ${WARNING} Could not enable agent_config_sync plugin"

        # Remove agent-config-db hook config entry if present
        if jq -e '.hooks.internal.entries["agent-config-db"]' "$OPENCLAW_CONFIG" &>/dev/null; then
            jq 'del(.hooks.internal.entries["agent-config-db"])' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Removed agent-config-db hook from config" || \
                echo -e "  ${WARNING} Could not remove agent-config-db hook from config"
        fi

        # Ensure agents.json is a valid keyed object BEFORE switching
        # agents.entries to $include (#1231 r7). The gateway schema rejects
        # arrays and empty objects, and retiring agent_config_sync before it
        # can rewrite a stale array leaves the gateway unbootable.
        _configure_agents_entries_include "$OPENCLAW_CONFIG"

        # Keep gateway.reload.mode valid for OpenClaw 2026.9.x (#723)
        _configure_gateway_reload_mode "$OPENCLAW_CONFIG"

        # Set maxSpawnDepth if missing
        EXISTING_DEPTH=$(jq -r '.agents.defaults.subagents.maxSpawnDepth // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_DEPTH" ]; then
            jq '.agents.defaults.subagents.maxSpawnDepth = 5' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set maxSpawnDepth = 5" || \
                echo -e "  ${WARNING} Could not set maxSpawnDepth"
        else
            echo -e "  ${CHECK_MARK} maxSpawnDepth already set to $EXISTING_DEPTH"
        fi

        # Configure agents.defaults.heartbeat so every heartbeat run/wake routes
        # to #proactive-mode (Discord channel 1504054635231445112) and runs in
        # an isolated session. Cadence defaults to 30m; TC-714-001 is pending so
        # the live cadence is NOT changed to 20m yet (#714 Rev 2).
        # Derivation: HEARTBEAT.md:66-67, motivation/README.md Configuration,
        # OpenClaw 2026.9.6 HeartbeatSchema.isolatedSession (fork
        # src/config/zod-schema.agent-runtime.ts:61).
        EXISTING_HB_EVERY=$(jq -r '.agents.defaults.heartbeat.every // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_HB_EVERY" ]; then
            jq '.agents.defaults.heartbeat.every = "30m"' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set agents.defaults.heartbeat.every = 30m" || \
                echo -e "  ${WARNING} Could not set heartbeat cadence"
        else
            echo -e "  ${CHECK_MARK} agents.defaults.heartbeat.every already set to $EXISTING_HB_EVERY"
        fi

        EXISTING_HB_TARGET=$(jq -r '.agents.defaults.heartbeat.target // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_HB_TARGET" ]; then
            jq '.agents.defaults.heartbeat.target = "discord"' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set agents.defaults.heartbeat.target = discord" || \
                echo -e "  ${WARNING} Could not set heartbeat target"
        else
            echo -e "  ${CHECK_MARK} agents.defaults.heartbeat.target already set to $EXISTING_HB_TARGET"
        fi

        EXISTING_HB_TO=$(jq -r '.agents.defaults.heartbeat.to // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_HB_TO" ]; then
            jq '.agents.defaults.heartbeat.to = "channel:1504054635231445112"' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set agents.defaults.heartbeat.to = channel:1504054635231445112 (#proactive-mode)" || \
                echo -e "  ${WARNING} Could not set heartbeat destination"
        else
            echo -e "  ${CHECK_MARK} agents.defaults.heartbeat.to already set to $EXISTING_HB_TO"
        fi

        EXISTING_HB_ISO=$(jq -r '.agents.defaults.heartbeat.isolatedSession // empty' "$OPENCLAW_CONFIG" 2>/dev/null)
        if [ -z "$EXISTING_HB_ISO" ]; then
            jq '.agents.defaults.heartbeat.isolatedSession = true' "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
                echo -e "  ${CHECK_MARK} Set agents.defaults.heartbeat.isolatedSession = true" || \
                echo -e "  ${WARNING} Could not set heartbeat isolatedSession"
        else
            echo -e "  ${CHECK_MARK} agents.defaults.heartbeat.isolatedSession already set to $EXISTING_HB_ISO"
        fi
    fi

else
    echo -e "  ${WARNING} cognition/focus/agent-config-sync not found (skipping)"
fi

# --- Ensure agent_system_config table ---
echo ""
echo "  Ensuring agent_system_config table..."

if psql -U "$DB_USER" -d "$DB_NAME" -q <<'SYSTEM_CONFIG_TABLE_SQL'
CREATE TABLE IF NOT EXISTS agent_system_config (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    value_type TEXT NOT NULL DEFAULT 'text',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
SYSTEM_CONFIG_TABLE_SQL
then
    echo -e "  ${CHECK_MARK} agent_system_config table ready"
else
    echo -e "  ${WARNING} Could not ensure agent_system_config table"
fi

# --- System config notification trigger ---
echo "  Installing system config notification trigger..."

SYSTEM_CONFIG_MIGRATION="$SCRIPT_DIR/cognition/scripts/migrations/163-system-config-trigger.sql"
if [ -f "$SYSTEM_CONFIG_MIGRATION" ]; then
    MIGRATION_ERR="${TMPDIR:-/tmp}/migration-163-$$.err"
    if psql -U "$DB_USER" -d "$DB_NAME" -q -f "$SYSTEM_CONFIG_MIGRATION" 2>"$MIGRATION_ERR"; then
        echo -e "  ${CHECK_MARK} System config trigger installed (163-system-config-trigger.sql)"
        rm -f "$MIGRATION_ERR"
    else
        echo -e "  ${WARNING} System config trigger migration had issues:"
        cat "$MIGRATION_ERR" >&2
        rm -f "$MIGRATION_ERR"
    fi
else
    if psql -U "$DB_USER" -d "$DB_NAME" -q <<'INLINE_MIGRATION_SQL'
CREATE OR REPLACE FUNCTION notify_system_config_changed()
RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM pg_notify('agent_config_changed', json_build_object(
            'source', 'agent_system_config', 'key', OLD.key, 'operation', TG_OP)::text);
        RETURN OLD;
    END IF;
    PERFORM pg_notify('agent_config_changed', json_build_object(
        'source', 'agent_system_config', 'key', NEW.key, 'operation', TG_OP)::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS system_config_changed ON agent_system_config;
CREATE TRIGGER system_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agent_system_config
    FOR EACH ROW EXECUTE FUNCTION notify_system_config_changed();

INSERT INTO agent_system_config (key, value, value_type)
VALUES ('max_spawn_depth', '5', 'integer')
ON CONFLICT (key) DO NOTHING;
INLINE_MIGRATION_SQL
    then
        echo -e "  ${CHECK_MARK} System config trigger installed (inline)"
    else
        echo -e "  ${WARNING} Inline migration had issues"
    fi
fi

# --- Fold legacy social_interactions into comms_items/comms_responses ---
echo "  Folding social_interactions into comms_items..."

SOCIAL_FOLD_MIGRATION="$SCRIPT_DIR/cognition/scripts/migrations/164-fold-social-interactions-to-comms-items.sql"
if [ -f "$SOCIAL_FOLD_MIGRATION" ]; then
    MIGRATION_ERR="${TMPDIR:-/tmp}/migration-164-$$.err"
    if psql -U "$DB_USER" -d "$DB_NAME" -q -f "$SOCIAL_FOLD_MIGRATION" 2>"$MIGRATION_ERR"; then
        echo -e "  ${CHECK_MARK} social_interactions fold migration installed (164-fold-social-interactions-to-comms-items.sql)"
        rm -f "$MIGRATION_ERR"
    else
        echo -e "  ${WARNING} social_interactions fold migration had issues:"
        cat "$MIGRATION_ERR" >&2
        rm -f "$MIGRATION_ERR"
    fi
else
    echo -e "  ${WARNING} social_interactions fold migration not found: $SOCIAL_FOLD_MIGRATION"
fi

# --- agent config notification trigger ---
echo "  Installing agent config notification trigger..."

if psql -U "$DB_USER" -d "$DB_NAME" -q <<'TRIGGER_SQL'
CREATE OR REPLACE FUNCTION notify_agent_config_changed()
RETURNS trigger AS $$
BEGIN
    PERFORM pg_notify('agent_config_changed', json_build_object(
        'agent_id', COALESCE(NEW.id, OLD.id),
        'agent_name', COALESCE(NEW.name, OLD.name),
        'operation', TG_OP
    )::text);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS agent_config_changed ON agents;
CREATE TRIGGER agent_config_changed
    AFTER INSERT OR UPDATE OR DELETE ON agents
    FOR EACH ROW EXECUTE FUNCTION notify_agent_config_changed();
TRIGGER_SQL
then
    echo -e "  ${CHECK_MARK} Agent config notification trigger installed"
else
    echo -e "  ${CROSS_MARK} Failed to install agent config notification trigger"
fi

# --- Shell environment setup (cognition dotfiles) ---
echo ""
echo "Shell environment setup..."

# Motivation system components
MOTIVATION_DIR="$SCRIPT_DIR/motivation"
MOTIVATION_ALIASES_SOURCE="$MOTIVATION_DIR/scripts/shell-aliases.sh"
MOTIVATION_HOOK_SOURCE="$MOTIVATION_DIR/hooks/pre-push"

# Prefer motivation/ shell-aliases.sh (newer canonical version)
if [ -f "$MOTIVATION_ALIASES_SOURCE" ]; then
    SHELL_ALIASES_SOURCE="$MOTIVATION_ALIASES_SOURCE"
else
    SHELL_ALIASES_SOURCE="$SCRIPT_DIR/cognition/dotfiles/shell-aliases.sh"
fi
SHELL_ALIASES_TARGET="$NOVA_DIR/shell-aliases.sh"
BASH_ENV_FILE="$HOME/.bash_env"
BASH_ENV_SOURCE="$SCRIPT_DIR/cognition/dotfiles/bash_env"
OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"

mkdir -p "$NOVA_DIR"

if [ -f "$SHELL_ALIASES_SOURCE" ]; then
    if [ -f "$SHELL_ALIASES_TARGET" ] && [ "$FORCE_INSTALL" -eq 0 ]; then
        echo -e "  ${CHECK_MARK} shell-aliases.sh already installed (use --force to reinstall)"
    else
        cp "$SHELL_ALIASES_SOURCE" "$SHELL_ALIASES_TARGET"
        chmod +x "$SHELL_ALIASES_TARGET"
        echo -e "  ${CHECK_MARK} Installed shell-aliases.sh → $SHELL_ALIASES_TARGET"
    fi
else
    echo -e "  ${WARNING} shell-aliases.sh source not found: $SHELL_ALIASES_SOURCE (skipping)"
fi

if [ -f "$BASH_ENV_SOURCE" ]; then
    # shellcheck disable=SC2088
    if [ -f "$BASH_ENV_FILE" ] && grep -qF '~/.local/share/nova/shell-aliases.sh' "$BASH_ENV_FILE"; then
        echo -e "  ${CHECK_MARK} ~/.bash_env already sources shell-aliases.sh"
    else
        if [ ! -f "$BASH_ENV_FILE" ]; then
            cp "$BASH_ENV_SOURCE" "$BASH_ENV_FILE"
            echo -e "  ${CHECK_MARK} Created ~/.bash_env"
        else
            echo "" >>"$BASH_ENV_FILE"
            cat "$BASH_ENV_SOURCE" >>"$BASH_ENV_FILE"
            echo -e "  ${CHECK_MARK} Updated ~/.bash_env (additively)"
        fi
    fi
else
    echo -e "  ${WARNING} bash_env source not found: $BASH_ENV_SOURCE (skipping)"
fi

if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
    if grep -q 'BASH_ENV' "$OPENCLAW_CONFIG"; then
        echo -e "  ${CHECK_MARK} OpenClaw config already has BASH_ENV set"
    else
        jq --arg bashenv "$BASH_ENV_FILE" '.env.vars.BASH_ENV = $bashenv' \
            "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
            mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG" && \
            echo -e "  ${CHECK_MARK} Added BASH_ENV to OpenClaw config" || \
            echo -e "  ${WARNING} Could not update config with BASH_ENV"
    fi
fi

# --- agent_chat OpenClaw config is managed by the optional peer repo (nova-mind#579) ---

# --- Generate hooks.token if hooks are enabled or internal hooks are enabled ---
echo ""
echo "Hooks token configuration..."

OPENCLAW_CONFIG="$OPENCLAW_DIR/openclaw.json"
if [ -f "$OPENCLAW_CONFIG" ] && command -v jq &>/dev/null; then
    HOOKS_ENABLED=$(jq -r '.hooks.enabled // false' "$OPENCLAW_CONFIG" 2>/dev/null)
    INTERNAL_HOOKS_ENABLED=$(jq -r '.hooks.internal.enabled // false' "$OPENCLAW_CONFIG" 2>/dev/null)
    if [ "$HOOKS_ENABLED" = "true" ] || [ "$INTERNAL_HOOKS_ENABLED" = "true" ]; then
        EXISTING_TOKEN=$(jq -r '.hooks.token // empty' "$OPENCLAW_CONFIG")
        if [ -z "$EXISTING_TOKEN" ]; then
            if ! command -v openssl &>/dev/null; then
                echo -e "  ${CROSS_MARK} openssl is required to generate hooks.token"
                exit 1
            fi
            HOOKS_TOKEN=$(openssl rand -hex 32)
            if jq --arg token "$HOOKS_TOKEN" '.hooks.token = $token' \
                    "$OPENCLAW_CONFIG" >"$OPENCLAW_CONFIG.tmp" && \
                    mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG"; then
                echo -e "  ${CHECK_MARK} Generated hooks.token"
            else
                echo -e "  ${CROSS_MARK} Could not set hooks.token"
                exit 1
            fi
        else
            echo -e "  ${CHECK_MARK} hooks.token already exists (preserved)"
        fi
    else
        echo -e "  ${INFO} Hooks not enabled — skipping token generation"
    fi
else
    echo -e "  ${WARNING} Cannot check hooks config (missing config or jq)"
fi

# ============================================
# SECTION 10: Verification
# ============================================
echo ""
echo "════════════════════════════════"
echo "  Final Verification"
echo "════════════════════════════════"

verify_schema
verify_relationships
verify_cognition
verify_config

# ============================================
# Installation Complete
# ============================================
echo ""
echo "═══════════════════════════════════════════"
if [ $VERIFICATION_ERRORS -gt 0 ]; then
    echo -e "  ${CROSS_MARK} Installation completed with errors"
elif [ $VERIFICATION_WARNINGS -gt 0 ]; then
    echo -e "  ${WARNING} Installation completed with warnings"
else
    echo -e "  ${GREEN}Installation complete!${NC}"
fi
echo "═══════════════════════════════════════════"
echo ""

echo "Installed components:"
echo "  [relationships]"
echo "    • entity-resolver library"
if [ -d "$REL_SKILLS_SOURCE" ] 2>/dev/null; then
    echo "    • relationship skills"
fi
echo "  [memory]"
echo "    • Shared PG loader libraries → ~/.openclaw/lib/"
echo "    • Schema managed via pgschema (database/schema.sql)"
echo "    • Daily memory log cron → $DAILY_LOG_CRON_STATUS"
echo "    • D100 announcer cron → $ANNOUNCE_D100_CRON_STATUS"
echo "    • Hermes comms-check cron → $HERMES_COMMS_CRON_STATUS"
echo "    • Completion log reconcile cron → $COMPLETION_LOG_RECONCILE_CRON_STATUS"
if [ ${#INSTALLED_HOOKS[@]} -gt 0 ]; then
    for hook in "${INSTALLED_HOOKS[@]}"; do
        echo "    • Hook: $hook"
    done
fi
echo "    • Scripts → $SCRIPTS_TARGET_OPENCLAW"
echo "    • Python venv → $VENV_DIR"
echo "  [cognition]"
echo "    • memory-extract extension → $EXTENSIONS_DIR/memory-extract"
echo "    • agent_config_sync extension → $EXTENSIONS_DIR/agent_config_sync"
echo "    • turn-context plugin → $OPENCLAW_DIR/plugins/turn-context"
echo "    • Motivation system → $MOTIVATION_DIR"
echo "    • shell-aliases.sh → $NOVA_DIR/shell-aliases.sh"
if [ -f "$MOTIVATION_HOOK_SOURCE" ]; then
    echo "    • pre-push hook (motivation) → available in $MOTIVATION_DIR/hooks/pre-push"
fi
if [ -f "$OPENCLAW_DIR/plugins/self-awareness/dist/index.js" ]; then
    echo "    • self-awareness plugin → $OPENCLAW_DIR/plugins/self-awareness"
fi
# confidence-check plugin disabled (see #342)
# if [ -f "$OPENCLAW_DIR/plugins/confidence-check/dist/index.js" ]; then
#     echo "    • confidence-check plugin → $OPENCLAW_DIR/plugins/confidence-check"
# fi
echo "    • Bootstrap context → $OPENCLAW_DIR/hooks/db-bootstrap-context"
echo "    • agents.json → $OPENCLAW_DIR/agents.json"
echo "    • shell-aliases.sh → $NOVA_DIR/shell-aliases.sh"
echo ""

echo "Next steps:"
echo ""
echo "1. Restart OpenClaw gateway to apply all changes:"
echo "   openclaw gateway restart"
echo ""
echo "2. Verify installation:"
echo "   $0 --verify-only"
echo ""
echo "3. Check logs:"
echo "   tail -f ~/.openclaw/logs/memory-extract-hook.log"
echo ""

if [ $VERIFICATION_WARNINGS -gt 0 ]; then
    echo "⚠️  Warnings detected — review output above."
    echo ""
fi

# ============================================
# Run local post-install overrides if present
# ============================================
POST_INSTALL="$HOME/.openclaw/post-install.sh"
if [ -x "$POST_INSTALL" ]; then
  echo ""
  echo "Running post-install hook: $POST_INSTALL"
  bash "$POST_INSTALL"
fi

# ============================================
# Gateway restart (if systemd service is running)
# ============================================
if systemctl --user is-active openclaw-gateway &>/dev/null; then
    if [ "$NO_RESTART" = "1" ]; then
        echo ""
        echo "⚠️  Gateway is running. Restart required for changes to take effect:"
        echo "   systemctl --user restart openclaw-gateway"
    else
        echo ""
        echo "Restarting gateway to apply changes..."
        if systemctl --user restart openclaw-gateway; then
            echo -e "  ${CHECK_MARK} Gateway restarted"
        else
            echo -e "  ${CROSS_MARK} Gateway restart failed. Restart manually:"
            echo "   systemctl --user restart openclaw-gateway"
        fi
    fi
fi
