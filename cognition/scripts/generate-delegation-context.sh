#!/usr/bin/env bash
# shellcheck disable=SC2129
# generate-delegation-context.sh - Generate dynamic delegation context from database
# Usage: generate-delegation-context.sh [output_file]
# Default output: ~/.openclaw/workspace/DELEGATION_CONTEXT.md
#
# Environment overrides:
#   DELEGATION_CONTEXT_DB_NAME  - target database (default: nova_memory)
#   DELEGATION_CONTEXT_DB_USER  - database user (default: current user)
#   DELEGATION_CONTEXT_DB_HOST  - database host (default: localhost)
#   DELEGATION_CONTEXT_DB_PORT  - database port (default: 5432)

# Deliberately no "set -e". Errors are captured per-section, reported in the
# output, and reflected in the final exit code. This prevents a single failing
# query from silently truncating the document.

OUTPUT_FILE="${1:-$HOME/.openclaw/workspace/DELEGATION_CONTEXT.md}"
DB_NAME="${DELEGATION_CONTEXT_DB_NAME:-nova_memory}"
DB_USER="${DELEGATION_CONTEXT_DB_USER:-$(whoami)}"
DB_HOST="${DELEGATION_CONTEXT_DB_HOST:-localhost}"
DB_PORT="${DELEGATION_CONTEXT_DB_PORT:-5432}"

OVERALL_EXIT=0

# Ensure the target directory exists so redirects don't fail partway through.
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR" || {
        echo "ERROR: cannot create output directory $OUTPUT_DIR" >&2
        exit 1
    }
fi

# Base psql invocation. Authentication is expected via ~/.pgpass; this script
# does not reference the gateway-injected password environment variable.
run_psql() {
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" "$@"
}

# Write the document header, truncating any previous content.
cat > "$OUTPUT_FILE" << 'EOF'
# Delegation Context

Generated from nova_memory database.

EOF

echo "**Generated:** $(date -u +"%Y-%m-%d %H:%M UTC")" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# -----------------------------------------------------------------------------
# Section 1: Agent Roster
# -----------------------------------------------------------------------------
echo "## Available Agents" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

AGENT_DATA=$(run_psql -t -A -F '|' -c "
SELECT nickname, role, model, description
FROM agents
WHERE status = 'active'
ORDER BY nickname;
")
agent_status=$?

if [ "$agent_status" -ne 0 ]; then
    echo "> ⚠️ Failed to generate agent roster: query failed (psql exit $agent_status)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    OVERALL_EXIT=1
elif [ -n "$AGENT_DATA" ]; then
    echo "| Nickname | Role | Model | Description |" >> "$OUTPUT_FILE"
    echo "|----------|------|-------|-------------|" >> "$OUTPUT_FILE"
    while IFS='|' read -r nickname role model description; do
        nickname="${nickname:--}"
        role="${role:--}"
        model="${model:--}"
        description="${description:--}"
        echo "| $nickname | $role | $model | $description |" >> "$OUTPUT_FILE"
    done <<< "$AGENT_DATA"
else
    echo "No active agents found." >> "$OUTPUT_FILE"
fi

echo "" >> "$OUTPUT_FILE"

# -----------------------------------------------------------------------------
# Section 2: Active Workflows
# -----------------------------------------------------------------------------
echo "## Active Workflows" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

WORKFLOWS=$(run_psql -t -A -c "
SELECT name
FROM workflows
WHERE status = 'active'
ORDER BY name;
")
workflow_status=$?

if [ "$workflow_status" -ne 0 ]; then
    echo "> ⚠️ Failed to generate workflow list: query failed (psql exit $workflow_status)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    OVERALL_EXIT=1
elif [ -n "$WORKFLOWS" ]; then
    while IFS= read -r workflow_name; do
        [ -z "$workflow_name" ] && continue

        # Escape single quotes in the workflow name for safe SQL literal use.
        escaped_workflow_name=$(printf '%s' "$workflow_name" | sed "s/'/''/g")
        WORKFLOW_DESC=$(run_psql -t -A -c "
            SELECT description
            FROM workflows
            WHERE name = '$escaped_workflow_name';
        ")
        desc_status=$?

        echo "### $workflow_name" >> "$OUTPUT_FILE"
        if [ "$desc_status" -ne 0 ]; then
            echo "> ⚠️ Failed to retrieve workflow description: query failed (psql exit $desc_status)" >> "$OUTPUT_FILE"
            OVERALL_EXIT=1
        elif [ -n "$WORKFLOW_DESC" ]; then
            # Escape leading '#' characters so embedded headings do not collide
            # with the document's own heading hierarchy.
            printf '%s\n' "$WORKFLOW_DESC" | sed 's/^#/\\#/' >> "$OUTPUT_FILE"
        fi
        echo "" >> "$OUTPUT_FILE"

        escaped_workflow_name=$(printf '%s' "$workflow_name" | sed "s/'/''/g")
        STEP_DATA=$(run_psql -t -A -F '|' -c "
            SELECT step_order,
                   array_to_string(domains, ', ') AS domains,
                   step_description,
                   deliverable_type
            FROM workflow_steps_detail
            WHERE workflow_name = '$escaped_workflow_name'
            ORDER BY step_order;
        ")
        step_status=$?

        if [ "$step_status" -ne 0 ]; then
            echo "> ⚠️ Failed to generate workflow step data: query failed (psql exit $step_status)" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            OVERALL_EXIT=1
        elif [ -n "$STEP_DATA" ]; then
            echo "| Step | Domains | Description | Deliverable |" >> "$OUTPUT_FILE"
            echo "|------|---------|-------------|-------------|" >> "$OUTPUT_FILE"
            while IFS='|' read -r step_order domains step_desc deliverable_type; do
                step_order="${step_order:--}"
                domains="${domains:--}"
                step_desc="${step_desc:--}"
                deliverable_type="${deliverable_type:--}"
                echo "| $step_order | $domains | $step_desc | $deliverable_type |" >> "$OUTPUT_FILE"
            done <<< "$STEP_DATA"
            echo "" >> "$OUTPUT_FILE"
        else
            echo "> No steps defined for this workflow." >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
        fi
    done <<< "$WORKFLOWS"
else
    echo "No active workflows found." >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# -----------------------------------------------------------------------------
# Section 3: Spawn Instructions
# -----------------------------------------------------------------------------
echo "## Spawn Instructions" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

SPAWN_DATA=$(run_psql -t -A -F '|' -c "
SELECT nickname,
       model,
       thinking,
       context_type,
       COALESCE(array_to_string(allowed_subagents, ', '), '') AS allowed_subagents,
       decision_criteria
FROM agents
WHERE status = 'active'
ORDER BY nickname;
")
spawn_status=$?

if [ "$spawn_status" -ne 0 ]; then
    echo "> ⚠️ Failed to generate spawn instructions: query failed (psql exit $spawn_status)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    OVERALL_EXIT=1
elif [ -n "$SPAWN_DATA" ]; then
    while IFS='|' read -r nickname model thinking context_type allowed_subagents decision_criteria; do
        [ -z "$nickname" ] && continue

        echo "### $nickname" >> "$OUTPUT_FILE"
        echo "- **Model:** ${model:--}" >> "$OUTPUT_FILE"
        echo "- **Thinking:** ${thinking:--}" >> "$OUTPUT_FILE"
        echo "- **Context type:** ${context_type:--}" >> "$OUTPUT_FILE"

        if [ -n "$allowed_subagents" ] && [ "$allowed_subagents" != "{}" ]; then
            echo "- **Allowed subagents:** $allowed_subagents" >> "$OUTPUT_FILE"
        else
            echo "- **Allowed subagents:** none" >> "$OUTPUT_FILE"
        fi

        if [ -n "$decision_criteria" ]; then
            echo "- **Decision criteria:** $decision_criteria" >> "$OUTPUT_FILE"
        fi

        echo "" >> "$OUTPUT_FILE"
    done <<< "$SPAWN_DATA"
else
    echo "No active agents found." >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# -----------------------------------------------------------------------------
# Footer
# -----------------------------------------------------------------------------
echo "---" >> "$OUTPUT_FILE"
echo "*Auto-generated from nova_memory database. Do not edit manually.*" >> "$OUTPUT_FILE"

echo "Generated: $OUTPUT_FILE" >&2

exit "$OVERALL_EXIT"
