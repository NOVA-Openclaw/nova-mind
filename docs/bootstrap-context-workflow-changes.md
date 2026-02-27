# Bootstrap Context: Workflow Changes

**Issue #95**: Remove WORKFLOW context_type from agent_bootstrap_context; source workflow context dynamically

## Overview

This document explains the changes made to how workflow context is sourced in the agent bootstrap system.

## Before (Static WORKFLOW Context)

Previously, the system included a `WORKFLOW` value in the `agent_bootstrap_context.context_type` enum, intended for storing static workflow-related bootstrap content.

**Problems with static approach:**
- Risk of data duplication between `agent_bootstrap_context` and `workflows`/`workflow_steps` tables
- Data drift when workflows are updated in their authoritative tables
- Maintenance overhead of keeping two sources of workflow data in sync

## After (Dynamic Workflow Sourcing)

Workflow context is now sourced dynamically from the authoritative `workflows` and `workflow_steps` tables.

### How It Works

The `get_agent_bootstrap()` function includes workflows in an agent's bootstrap context when:

**Match Criteria:**
- Any `workflow_steps.agent_id` matches the target agent, OR  
- Any `workflow_steps.domains` overlap with the agent's assigned domains (via `agent_domains` table)

**Output Format:**
- **Filename**: `WORKFLOW_CONTEXT.md`
- **Content**: `Workflow: {name}\n\n{description}`
- **Source**: `workflow:{workflow_name}`

### Function Implementation

```sql
-- Workflow context (dynamic from workflow_steps)
SELECT 
    'WORKFLOW_CONTEXT.md' as filename,
    'Workflow: ' || w.name || E'\n\n' || w.description as content,
    'workflow:' || w.name as source,
    4 as priority
FROM workflow_steps ws
JOIN workflows w ON ws.workflow_id = w.id
WHERE ws.agent_id = v_agent_id
    AND w.status = 'active'
```

## Migration Details

**Migration**: `061_remove_workflow_context_type.sql`

### Changes Made

1. **Constraint Update**: Removed `WORKFLOW` from `context_type` CHECK constraint if present
2. **Data Cleanup**: Removed any orphaned rows with `context_type = 'WORKFLOW'` (expected zero)
3. **Function Verification**: Confirmed `get_agent_bootstrap()` has proper dynamic workflow sourcing
4. **Documentation**: Updated function comments to reflect the change

### Verification

The migration includes helper functions to verify the changes:

```sql
-- Check constraint was updated properly
SELECT conname, consrc 
FROM pg_constraint c
JOIN pg_class t ON c.conrelid = t.oid
WHERE t.relname = 'agent_bootstrap_context' AND conname LIKE '%context_type%';

-- Verify workflow context works for an agent
SELECT * FROM verify_workflow_context('conductor');
```

## Benefits

1. **Single Source of Truth**: Workflows are managed only in `workflows`/`workflow_steps` tables
2. **Automatic Updates**: Bootstrap context reflects workflow changes immediately
3. **Domain-Based Matching**: Workflows can be included based on agent domains
4. **Reduced Maintenance**: No need to manually sync workflow content

## Impact

- **Zero Breaking Changes**: Existing bootstrap context continues to work
- **Improved Consistency**: Workflow data always reflects current state
- **Cleaner Schema**: Removed unused enum value from constraint

## Related Files

- `migrations/061_remove_workflow_context_type.sql` - Main migration
- `focus/bootstrap-context/sql/management-functions.sql` - Updated function
- `migrations/059_domain_based_bootstrap.sql` - Original domain-based architecture

## Testing

To verify workflow context is working:

```sql
-- List workflow context for an agent
SELECT filename, source 
FROM get_agent_bootstrap('conductor') 
WHERE source LIKE 'workflow%';

-- Check specific workflow assignments
SELECT * FROM verify_workflow_context('conductor');
```