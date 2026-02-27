# Simplified Commit Workflow

**Version:** 1.2.0 (Simplified)  
**Date:** 2026-02-08  
**Status:** Active

## Core Pattern

**Gidget spawns Scribe internally before committing** - No external orchestration needed.

## Workflow

```
Coder completes work
    ↓
NOVA delegates commit to Gidget
    ↓
Gidget spawns Scribe: "Review for doc needs"
    ↓
Scribe reviews/updates docs
    ↓
Gidget commits everything (code + docs)
    ↓
NOVA receives completion confirmation
```

## Step-by-Step

### 1. Coder Completes Work
**Agent:** Coder (coder)

- Implements feature
- Writes initial docs (rough)
- Reports to NOVA: "Feature complete, ready to commit"

### 2. NOVA Delegates to Gidget
**Orchestrator:** NOVA

```
NOVA → Gidget: "Commit the changes from Coder in {repo}"
```

### 3. Gidget Spawns Scribe
**Agent:** gidget (Gidget)

**Before committing, Gidget spawns Scribe:**

```javascript
sessions_spawn({
  agent: 'scribe',
  task: `Review changes in ${repo} for documentation needs. 
         Files changed: ${changed_files}. 
         Update docs if needed, then report completion.`,
  timeout: 600
});
```

**Gidget waits for Scribe to complete.**

### 4. Scribe Reviews & Updates
**Agent:** Scribe

**Actions:**
1. Review code changes (git diff)
2. Check if docs need updates:
   - README files
   - API documentation
   - Architecture docs
   - Examples
3. Update docs if needed
4. For major features: Request haiku from Quill
5. Report to Gidget: "Doc review complete. Updated {files}" or "No doc updates needed"

### 5. Gidget Commits Everything
**Agent:** gidget (Gidget)

**After Scribe reports completion:**

```bash
git add .
git commit -m "feat: {feature description}

{detailed commit message}

Co-authored-by: Scribe (documentation)"
git push origin main
```

**Report to NOVA:** "Changes committed to {repo}:{branch}"

## Gidget Seed Context

```json
{
  "workflow_handoff": {
    "pre_commit_review": {
      "enabled": true,
      "action": "Before committing changes, spawn Scribe to review for documentation needs",
      "process": [
        "1. Receive code changes from Coder (via NOVA delegation)",
        "2. Spawn Scribe: Review these changes for documentation needs",
        "3. Wait for Scribe to complete review and any doc updates",
        "4. Commit everything together (code + doc updates)",
        "5. Report completion to NOVA"
      ],
      "scribe_task_template": "Review changes in {repo} for documentation needs. Files changed: {changed_files}. Update docs if needed, then report completion."
    }
  }
}
```

## Scribe Seed Context

```json
{
  "collaboration": {
    "with_gidget": "Spawned by gidget (Gidget) for pre-commit documentation review. Review code changes, update docs if needed, report completion. Gidget will commit everything together."
  }
}
```

## Example Execution

### Scenario: Add Conditional Branching to AWL

**Step 1: Coder implements**
- Adds conditional step type
- Updates docs (rough draft)
- Reports to NOVA: "Conditional branching complete, ready to commit"

**Step 2: NOVA delegates**
```
NOVA → Gidget: "Commit AWL conditional branching to nova-cognition"
```

**Step 3: Gidget spawns Scribe**
```
Gidget → sessions_spawn(scribe, "Review nova-cognition changes for doc needs. 
Files: executor.js, docs/agent-workflow-language.md, examples/conditional.yaml")
```

**Step 4: Scribe reviews**
- Reads git diff
- Reviews docs/agent-workflow-language.md
- Cleans up formatting
- Adds missing examples
- Requests haiku from Quill (major feature)
- Reports: "Doc review complete. Updated agent-workflow-language.md with cleaned examples and haiku epigraph"

**Step 5: Gidget commits**
```bash
git add executor.js docs/agent-workflow-language.md examples/conditional.yaml
git commit -m "feat(awl): add conditional branching support

Adds conditional step type for branch workflows.

Co-authored-by: Scribe (documentation)
Co-authored-by: Quill (haiku)"
git push origin main
```

**Step 6: Report**
```
Gidget → NOVA: "Changes committed to nova-cognition:main"
```

## Benefits

1. **Simple coordination** - Gidget handles Scribe internally, NOVA just delegates once
2. **Clean commits** - Documentation reviewed before commit, not after
3. **Atomic commits** - Code + docs together in single commit
4. **No external dependencies** - Pure agent-to-agent spawning
5. **Clear responsibilities** - Gidget owns the commit process, spawns help as needed

## When Scribe Is Skipped

Gidget can skip spawning Scribe if:
- No code changes (e.g., merge-only operations)
- Changes explicitly marked `[skip-docs]`
- Emergency hotfix requiring immediate commit
- No documentation files in the repository

In these cases, Gidget commits directly without review.

## Workflow Diagram

```
┌─────────────────────────────────────────────────┐
│  NOVA: "Gidget, commit the changes"             │
└──────────────────┬──────────────────────────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │      GIDGET          │
        │  (gidget)         │
        └──────────┬───────────┘
                   │
       ┌───────────┴───────────┐
       │                       │
       ▼                       │
  sessions_spawn(scribe)       │
       │                       │
       ▼                       │
┌─────────────┐                │
│   SCRIBE    │                │
│  (reviews)  │                │
└──────┬──────┘                │
       │                       │
       └───► reports back ─────┘
                   │
                   ▼
          git commit + push
                   │
                   ▼
          Report to NOVA
```

## Error Handling

### If Scribe fails
- Gidget logs the error
- Gidget asks NOVA: "Scribe review failed. Commit anyway or abort?"
- NOVA decides based on urgency

### If commit fails
- Gidget reports error to NOVA
- Does not retry automatically (could cause merge conflicts)
- NOVA investigates and decides next steps

## Metrics

Track:
- **Scribe spawn rate** - How often Gidget spawns Scribe
- **Doc update rate** - How often Scribe makes changes
- **Commit cleanliness** - Are follow-up "fix docs" commits reduced?
- **Review time** - Time from Gidget spawn to Scribe completion

## Related

- **Scribe agent design**
- **Scribe + Quill collaboration** (haiku epigraphs)
- **git-commit-conventions SOP**

---

**Version History:**
- v1.0: Initial (post-push review) - INCORRECT
- v1.1: Corrected (Coder → Scribe → Gidget handoff)
- v1.2: Simplified (Gidget spawns Scribe internally) - CURRENT

**Key insight:** Keep orchestration simple. Gidget owns the commit, spawns help as needed.
