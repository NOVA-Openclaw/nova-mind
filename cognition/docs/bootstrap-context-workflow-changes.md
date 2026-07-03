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

> **Note:** The match criteria and function body below describe the original (#95/#171-era) implementation. `workflow_steps` has never had an `agent_id` column — match has always been domain-based. As of `get_agent_bootstrap()`'s current form (post migration 064), the WORKFLOW section also emits a compact per-workflow summary (name, workflow_id, purpose sentence, and the agent's own step numbers) rather than a single flat `WORKFLOW_CONTEXT.md` per matching row — see `database/schema.sql`'s `get_agent_bootstrap()` definition for the exact current query.

The `get_agent_bootstrap()` function includes workflows in an agent's bootstrap context when:

**Match Criteria (current):**
- Any `workflow_steps.domain` or `workflow_steps.domains` entry overlaps with the agent's assigned domains (via the `agent_domains` table, matched on `agent_id`/`domain_topic`)

There is no `workflow_steps.agent_id` column — step assignment is purely domain-based.

**Output Format (current):**
- **Filename**: `WORKFLOW_<NAME>.md` (uppercased workflow name, hyphens to underscores)
- **Content**: A compact summary — workflow name, `workflow_id`, a purpose sentence extracted from the workflow description, and the agent's own step number(s) with a query hint
- **Source**: `WORKFLOW:<workflow_name>`

### Function Implementation (historical — see note above for current behavior)

```sql
-- Workflow context (dynamic from workflow_steps) — illustrative of the original design;
-- does not match the current get_agent_bootstrap() query verbatim
SELECT 
    'WORKFLOW_CONTEXT.md' as filename,
    'Workflow: ' || w.name || E'\n\n' || w.description as content,
    'WORKFLOW:' || w.name as source,
    4 as priority
FROM workflow_steps ws
JOIN workflows w ON ws.workflow_id = w.id
WHERE EXISTS (
    SELECT 1 FROM agent_domains ad
    WHERE ad.agent_id = v_agent_id AND ad.domain_topic = ws.domain
)
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

-- Verify workflow context works for an agent (there is no verify_workflow_context()
-- helper function — query get_agent_bootstrap() directly instead)
SELECT filename, source FROM get_agent_bootstrap('conductor') WHERE source LIKE 'WORKFLOW%';
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
- `focus/bootstrap-context/sql/management-functions.sql` — Removed in [#171](https://github.com/NOVA-Openclaw/nova-mind/issues/171). Functions now defined in `database/schema.sql` and managed by pgschema.
- `migrations/059_domain_based_bootstrap.sql` - Original domain-based architecture

## Testing

To verify workflow context is working:

```sql
-- List workflow context for an agent (source values are uppercase, e.g. 'WORKFLOW:code-document-commit')
SELECT filename, source 
FROM get_agent_bootstrap('conductor') 
WHERE source LIKE 'WORKFLOW%';
```

There is no `verify_workflow_context()` helper function in the current schema — the query above is the direct way to check.