#!/usr/bin/env bats
# Tests for nova-mind#780:
#   - semantic-memory SKILL.md uses the unified Ollama snowflake-arctic-embed2 standard
#   - SKILL.md references only the per-peer install path

BATS_TEST_DIRNAME="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SKILL_MD="$REPO_ROOT/memory/skills/semantic-memory/SKILL.md"
AGENT_INSTALL="$REPO_ROOT/agent-install.sh"

@test "TC-780a: SKILL.md exists" {
    [ -f "$SKILL_MD" ]
}

@test "TC-780b: SKILL.md uses the unified Ollama embedding model" {
    run grep -q "snowflake-arctic-embed2" "$SKILL_MD"
    [ "$status" -eq 0 ]
}

@test "TC-780c: SKILL.md does not reference the old OpenAI embedding model" {
    run grep -q "text-embedding-3-small" "$SKILL_MD"
    [ "$status" -ne 0 ]
}

@test "TC-780d: SKILL.md does not reference the old 1536 dimension" {
    run grep -q "1536" "$SKILL_MD"
    [ "$status" -ne 0 ]
}

@test "TC-780e: SKILL.md does not reference the shared-skills copy" {
    run grep -q "/opt/agents/shared-skills" "$SKILL_MD"
    [ "$status" -ne 0 ]
}

@test "TC-780f: SKILL.md does not reference the deprecated workspace scripts path" {
    run grep -q "workspace/scripts/proactive-recall" "$SKILL_MD"
    [ "$status" -ne 0 ]
}

@test "TC-780g: SKILL.md points at the per-peer installed script" {
    run grep -q "~/.openclaw/scripts/proactive-recall.py" "$SKILL_MD"
    [ "$status" -eq 0 ]
}

@test "TC-780h: agent-install.sh installs proactive-recall.py to ~/.openclaw/scripts" {
    run grep -q "SCRIPTS_TARGET_OPENCLAW=\"\$HOME/.openclaw/scripts\"" "$AGENT_INSTALL"
    [ "$status" -eq 0 ]
    run grep -q "for source_file in \"\$SCRIPTS_SOURCE\"/\*.sh \"\$SCRIPTS_SOURCE\"/\*.py \"\$SCRIPTS_SOURCE\"/\*.json" "$AGENT_INSTALL"
    [ "$status" -eq 0 ]
}

@test "TC-780i: agent-install.sh installs memory skills to ~/.openclaw/skills" {
    run grep -q "install_skills \"\$MEM_SKILLS_SOURCE\" \"\$HOME/.openclaw/skills\" \"memory skills\"" "$AGENT_INSTALL"
    [ "$status" -eq 0 ]
}
