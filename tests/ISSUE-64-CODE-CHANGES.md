# Issue #64: Exact Code Changes

This document shows the exact code changes made to fix issue #64.

---

## File: `~/.openclaw/hooks/db-bootstrap-context/handler.ts`

### Change 1: Remove hardcoded FALLBACK_DIR constant

**Location:** Line ~29 (after imports)

```diff
- const FALLBACK_DIR = join(homedir(), '.openclaw', 'bootstrap-fallback');
-
  /**
   * Query database for agent bootstrap context
   */
```

---

### Change 2: Update loadFallbackFiles function signature and implementation

**Location:** Lines ~71-103

```diff
  /**
-  * Load fallback files from ~/.openclaw/bootstrap-fallback/
+  * Load fallback files from workspace directory
   */
- async function loadFallbackFiles(agentName: string): Promise<BootstrapFile[]> {
+ async function loadFallbackFiles(workspaceDir: string | undefined): Promise<BootstrapFile[]> {
+   // If workspaceDir is undefined or null, return empty array to fall through to emergency context
+   if (!workspaceDir) {
+     console.warn('[bootstrap-context] workspaceDir is undefined, cannot load fallback files');
+     return [];
+   }
+   
    const fallbackFiles = [
      'UNIVERSAL_SEED.md',
      'AGENTS.md',
      'SOUL.md',
      'TOOLS.md',
      'IDENTITY.md',
      'USER.md',
-     'HEARTBEAT.md'
+     'HEARTBEAT.md',
+     'MEMORY.md'
    ];
    
    const files: BootstrapFile[] = [];
    
    for (const filename of fallbackFiles) {
      try {
-       const content = await readFile(join(FALLBACK_DIR, filename), 'utf-8');
+       const content = await readFile(join(workspaceDir, filename), 'utf-8');
        files.push({
          path: `fallback:${filename}`,
          content
        });
      } catch (error) {
        // File doesn't exist or can't be read, skip it
        console.warn(`[bootstrap-context] Fallback file not found: ${filename}`);
      }
    }
    
    return files;
  }
```

---

### Change 3: Update call site

**Location:** Line ~175

```diff
    if (files.length === 0) {
      console.warn('[bootstrap-context] No database context, trying fallback files...');
-     files = await loadFallbackFiles(agentName);
+     files = await loadFallbackFiles(event.context.workspaceDir);
    }
```

---

### Change 4: Update emergency context documentation

**Location:** Lines ~130-140 (inside getEmergencyContext function)

```diff
  ## Recovery Steps
  
  1. Check database connection
  2. Verify bootstrap_context tables exist:
     \`\`\`sql
     SELECT * FROM get_agent_bootstrap('your_agent_name');
     \`\`\`
- 3. Check fallback directory: ~/.openclaw/bootstrap-fallback/
+ 3. Check workspace directory for fallback files (AGENTS.md, SOUL.md, etc.)
  4. Contact Newhart (NHR Agent) for assistance
```

---

## Summary of Changes

| Change | Type | Impact |
|--------|------|--------|
| Remove `FALLBACK_DIR` constant | Deletion | Removes hardcoded path |
| Update function signature | Modification | Now accepts workspace directory |
| Add undefined check | Addition | Graceful error handling |
| Update file reading path | Modification | Uses workspace instead of hardcoded path |
| Update call site | Modification | Passes correct parameter |
| Add `MEMORY.md` to fallback list | Addition | Includes memory file in fallback |
| Update documentation | Modification | Reflects actual behavior |

---

## Lines Changed

- **Lines deleted:** 1 (FALLBACK_DIR constant)
- **Lines added:** 5 (undefined check + MEMORY.md)
- **Lines modified:** 5 (function signature, file path, call site, docs)
- **Total impact:** ~11 lines of code

---

## Verification

To verify these changes are applied:

```bash
# Check the handler file
cat ~/.openclaw/hooks/db-bootstrap-context/handler.ts | grep -A 5 "loadFallbackFiles"

# Should show:
# async function loadFallbackFiles(workspaceDir: string | undefined): Promise<BootstrapFile[]> {
#   // If workspaceDir is undefined or null, return empty array to fall through to emergency context
#   if (!workspaceDir) {
#     console.warn('[bootstrap-context] workspaceDir is undefined, cannot load fallback files');
#     return [];
#   }
```

---

## Testing the Fix

### Manual Test:

1. Create a test workspace with bootstrap files:
   ```bash
   mkdir -p /tmp/test-workspace
   echo "# Test" > /tmp/test-workspace/AGENTS.md
   echo "# Test" > /tmp/test-workspace/SOUL.md
   ```

2. Trigger the hook with database unavailable

3. Check logs - should show files loaded from `/tmp/test-workspace/`, NOT from `~/.openclaw/bootstrap-fallback/`

### Expected Behavior:

✅ **With valid workspace:**
```
[bootstrap-context] No database context, trying fallback files...
[bootstrap-context] Loaded 2 context files for test
```

✅ **With undefined workspace:**
```
[bootstrap-context] No database context, trying fallback files...
[bootstrap-context] workspaceDir is undefined, cannot load fallback files
[bootstrap-context] No fallback files, using emergency context
[bootstrap-context] Loaded 1 context files for test
```

---

## Rollback Instructions

If this change needs to be reverted:

1. Restore the original handler.ts from git:
   ```bash
   cd ~/.openclaw/hooks/db-bootstrap-context/
   git checkout HEAD handler.ts
   ```

2. Or manually revert the changes shown above

---

## Related Documentation

- Test cases: `~/workspace/nova-cognition/tests/TEST-CASES-ISSUE-64.md`
- Fix summary: `~/workspace/nova-cognition/tests/ISSUE-64-FIX-SUMMARY.md`
- Verification script: `~/workspace/nova-cognition/tests/verify-issue-64-fix.sh`

---

**Fix Date:** 2026-02-13  
**Status:** ✅ Complete and Verified
