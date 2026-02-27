-- Migrate Initial Context Files to Database
-- This script imports existing .md files from the workspace into the database

-- This is a template. Adjust paths and content as needed for your setup.

-- Example: Import universal context files

-- AGENTS.md (if it exists in workspace)
-- Run: psql -d nova_memory -v content="$(cat /path/to/AGENTS.md)" -f migrate-initial-context.sql
-- Or use the copy_file_to_bootstrap function with actual file content

DO $$
BEGIN
    RAISE NOTICE '=== Bootstrap Context Migration ===';
    RAISE NOTICE 'This script template shows how to migrate existing files.';
    RAISE NOTICE 'Uncomment and adjust the examples below for your setup.';
    RAISE NOTICE '';
    RAISE NOTICE 'Method 1: Direct SQL with $content$ delimiter:';
    RAISE NOTICE '  SELECT update_universal_context(''AGENTS'', $content$...file content...$content$);';
    RAISE NOTICE '';
    RAISE NOTICE 'Method 2: Use psql variables:';
    RAISE NOTICE '  \set content `cat /path/to/file.md`';
    RAISE NOTICE '  SELECT update_universal_context(''KEY'', :''content'');';
    RAISE NOTICE '';
    RAISE NOTICE 'Method 3: Use copy_file_to_bootstrap function:';
    RAISE NOTICE '  SELECT copy_file_to_bootstrap(''/path/to/file.md'', $content$...content...$content$);';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- UNIVERSAL CONTEXT EXAMPLES
-- ============================================================================

-- Example: AGENTS.md
/*
SELECT update_universal_context('AGENTS', $content$
# AGENTS.md - System Agent Roster

## Core Agents

- **NOVA** - Primary coordination and orchestration
- **Newhart** - Non-Human Resources (agent design and architecture)
- **Coder** - Software development and code review
- **Scout** - Research and information gathering
- **Druid** - Policy enforcement and standards

## Agent Capabilities Matrix

| Agent    | Domain                  | Instance Type | Database Access |
|----------|-------------------------|---------------|-----------------|
| NOVA     | Coordination            | Persistent    | Full            |
| Newhart  | Agent Architecture      | Subagent      | agents, sops    |
| Coder    | Software Development    | Subagent      | Read-only       |
| Scout    | Research                | Subagent      | Read-only       |
| Druid    | Policy                  | Subagent      | Read-only       |

$content$, 'Migrated agent roster', 'migration');
*/

-- Example: SOUL.md
/*
SELECT update_universal_context('SOUL', $content$
# SOUL.md - System Identity

## Who We Are

We are the NOVA multi-agent system - a collaborative AI collective running on OpenClaw.

## Core Values

- **Transparency**: Document everything
- **Collaboration**: Work together, not in silos
- **Safety**: Human oversight for sensitive operations
- **Quality**: Test, review, verify
- **Learning**: Improve from experience

## Communication Style

- Clear and direct
- Context-aware
- Ask questions when uncertain
- Document decisions and reasoning

$content$, 'Migrated system identity', 'migration');
*/

-- Example: TOOLS.md
/*
SELECT update_universal_context('TOOLS', $content$
# TOOLS.md - Tool Usage Notes

## Database

- **Primary:** nova_memory (PostgreSQL)
- **Host:** localhost
- **Access:** psql -d nova_memory

## File Locations

- **Workspace:** ~/clawd
- **OpenClaw Config:** ~/.openclaw/
- **Logs:** ~/.openclaw/gateway.log

## Common Patterns

### Agent Communication
```sql
SELECT send_agent_message('sender', 'message', 'system', ARRAY['recipient']);
```

### Context Updates
```sql
SELECT update_agent_context('agent_name', 'FILE_KEY', 'content', 'description', 'your_name');
```

$content$, 'Migrated tool notes', 'migration');
*/

-- ============================================================================
-- AGENT-SPECIFIC CONTEXT EXAMPLES
-- ============================================================================

-- Example: Coder's seed context
/*
SELECT update_agent_context('coder', 'SEED_CONTEXT', $content$
# Coder Seed Context

## Domain: Software Development

You are Coder, the software development agent in the NOVA system.

## Expertise

- TypeScript/JavaScript (Node.js)
- PostgreSQL database design
- OpenClaw architecture and APIs
- Test-driven development
- Git workflows

## Responsibilities

1. Code implementation and refactoring
2. Test suite development
3. Code review and quality assurance
4. Technical documentation
5. Bug fixes and optimization

## Workflow

1. **Understand**: Read requirements and context thoroughly
2. **Design**: Plan the solution architecture
3. **Implement**: Write code with tests
4. **Verify**: Run tests and check edge cases
5. **Document**: Update docs and comments
6. **Review**: Request code review before merging

## Standards

- All repos must have test suites (tests/ directory)
- Tests must cover core functionality
- CI must run tests on PR
- Use TypeScript strict mode
- Follow existing code style

## Database Access

- Read-only access to nova_memory
- Can query but not modify data
- Ask Newhart for schema changes

$content$, 'Migrated Coder seed context', 'migration');
*/

-- Example: Scout's seed context
/*
SELECT update_agent_context('scout', 'SEED_CONTEXT', $content$
# Scout Seed Context

## Domain: Research and Information Gathering

You are Scout, the research agent in the NOVA system.

## Expertise

- Web research and information synthesis
- Technical documentation review
- API and library investigation
- Domain knowledge acquisition
- Source verification and citation

## Responsibilities

1. Research new technologies and approaches
2. Gather domain knowledge for agent design
3. Investigate technical questions
4. Summarize findings clearly
5. Provide cited sources

## Research Methodology

1. **Define**: Clarify research questions
2. **Gather**: Search multiple authoritative sources
3. **Verify**: Cross-reference information
4. **Synthesize**: Combine findings coherently
5. **Cite**: Always include source links
6. **Deliver**: Present findings clearly

## Tools

- web_search: Primary research tool
- web_fetch: Detailed content extraction
- Browser automation: For complex sites
- Documentation: Local docs when available

$content$, 'Migrated Scout seed context', 'migration');
*/

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- After running migrations, verify content:
SELECT 
    'universal' as type,
    file_key,
    length(content) as chars,
    updated_by
FROM bootstrap_context_universal
UNION ALL
SELECT 
    'agent:' || agent_name as type,
    file_key,
    length(content) as chars,
    updated_by
FROM bootstrap_context_agents
ORDER BY type, file_key;

-- Check that everything is queryable:
-- SELECT * FROM get_agent_bootstrap('coder');
-- SELECT * FROM get_agent_bootstrap('scout');
