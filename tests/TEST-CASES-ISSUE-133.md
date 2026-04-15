# Test Cases — Issue #133: Semantic Recall Hook Path Fixes

## Scope

Three fix areas:
1. Entity-resolver install location and handler import path
2. Handler path resolution (all paths dynamic via ENV vars)
3. Cron entry management in the installer

---

## 1. Entity-Resolver Installation

### TC-1.1: Fresh install places entity-resolver in lib/
**Precondition:** `~/.openclaw/lib/entity-resolver/` does not exist
**Action:** Run `bash agent-install.sh`
**Expected:** `~/.openclaw/lib/entity-resolver/index.ts` exists and contains the entity-resolver module
**Verify:** `ls ~/.openclaw/lib/entity-resolver/index.ts` succeeds

### TC-1.2: Reinstall is idempotent
**Precondition:** TC-1.1 completed (entity-resolver already installed)
**Action:** Run `bash agent-install.sh` again
**Expected:** No errors, entity-resolver still in place, file content unchanged (sha256 match)

### TC-1.3: Entity-resolver node_modules present
**Precondition:** TC-1.1 completed
**Action:** Check for `node_modules/pg` in entity-resolver dir
**Expected:** `~/.openclaw/lib/entity-resolver/node_modules/` exists with pg dependency installed

---

## 2. Handler Path Resolution

### TC-2.1: semantic-recall handler uses OPENCLAW_STATE_DIR for scripts
**Action:** Grep repo source `memory/hooks/semantic-recall/handler.ts` for path patterns
**Expected:**
- `RECALL_SCRIPT` derived from `OPENCLAW_STATE_DIR` or `os.homedir() + '.openclaw'`
- No `__dirname` relative paths for scripts
- No hardcoded `/home/nova/`, `~/clawd/`, or `~/workspace/` paths
**Verify:** `grep -c "__dirname" handler.ts` returns 0, `grep -c "OPENCLAW_STATE_DIR\|\.openclaw" handler.ts` returns > 0

### TC-2.2: semantic-recall handler uses absolute import for entity-resolver
**Action:** Grep handler.ts for entity-resolver import
**Expected:**
- Import uses dynamic `join(LIB_DIR, 'entity-resolver', 'index.ts')` pattern
- No relative `../../../` import paths
**Verify:** `grep -c "\.\./\.\./\.\." handler.ts` returns 0

### TC-2.3: semantic-recall handler uses standard venv path
**Action:** Grep handler.ts for python venv path
**Expected:**
- Venv path derived from `os.homedir() + '.local/share/' + username + '/venv/bin/python'`
- Falls back to `OPENCLAW_STATE_DIR + '/scripts/tts-venv/bin/python'` for backward compat
- No hardcoded `~/clawd/` venv references
**Verify:** `grep "clawd" handler.ts` returns no matches

### TC-2.4: No hardcoded paths in ANY handler
**Action:** Grep all handlers in `memory/hooks/*/handler.ts` for hardcoded paths
**Expected:** Zero matches for:
- `/home/nova/`
- `~/clawd`
- `~/workspace`
- Any hardcoded username in paths
**Verify:** `grep -rn "clawd\|/home/nova\|~/workspace" memory/hooks/*/handler.ts` returns empty

### TC-2.5: pg-env import uses STATE_DIR
**Action:** Grep handler.ts for pg-env path
**Expected:** `join(STATE_DIR, 'lib', 'pg-env.ts')` or equivalent using OPENCLAW_STATE_DIR
**Verify:** Consistent with entity-resolver pattern (both under LIB_DIR)

### TC-2.6: memory-extract handler uses dynamic paths
**Action:** Grep `memory/hooks/memory-extract/handler.ts` for path patterns
**Expected:** Same dynamic path pattern as semantic-recall — no relative paths, no hardcoded paths

### TC-2.7: session-init handler uses dynamic paths
**Action:** Grep `memory/hooks/session-init/handler.ts` for path patterns
**Expected:** Same dynamic path pattern — no relative paths, no hardcoded paths

### TC-2.8: Handler respects overridden OPENCLAW_STATE_DIR
**Precondition:** Set `OPENCLAW_STATE_DIR` to `/tmp/custom-openclaw`
**Action:** Run gateway, trigger semantic-recall, then inspect logs for resolved paths
**Expected:** All resolved script, lib, and log paths start with `/tmp/custom-openclaw`
**Verify:** `grep "tmp/custom-openclaw" gateway.log` shows correct paths

### TC-5.4: Missing entity-resolver library (graceful error)
**Precondition:** Remove `~/.openclaw/lib/entity-resolver/`
**Action:** Trigger semantic-recall
**Expected:** Hook logs a clear error about missing entity-resolver and falls back gracefully (no entity enrichment but no crash)

---

## 3. Cron Entry Management

### TC-3.1: Fresh install creates cron entries
**Precondition:** No nova-mind-related cron entries exist (`crontab -l | grep -c embed-memories` returns 0)
**Action:** Run `bash agent-install.sh`
**Expected:** `crontab -l` contains:
- `embed-memories-cron.sh` entry pointing to `$HOME/.openclaw/scripts/`
- `memory-maintenance.py` entry using `$HOME/.local/share/$USER/venv/`
- `expire_old_chat` entry with correct database name
- All log paths use `$HOME/.openclaw/logs/`

### TC-3.2: Existing correct entries are not duplicated
**Precondition:** TC-3.1 completed (correct entries exist)
**Action:** Run `bash agent-install.sh` again
**Expected:** Same cron entries, no duplicates. `crontab -l | grep -c embed-memories` returns 1 (not 2)

### TC-3.3: Stale cron entries are fixed
**Precondition:** Manually add a stale entry: `0 11 * * * /home/nova/clawd/scripts/embed-memories-cron.sh`
**Action:** Run `bash agent-install.sh`
**Expected:** Stale `~/clawd/` path replaced with `~/.openclaw/scripts/` path. Old entry removed, correct entry present.

### TC-3.4: Non-nova-mind cron entries are preserved
**Precondition:** Other unrelated cron entries exist (e.g., gdrive-sync)
**Action:** Run `bash agent-install.sh`
**Expected:** Unrelated cron entries are untouched. Only nova-mind entries are managed.

### TC-3.5: Cron entries use dynamic database name
**Action:** Check expire_old_chat cron entry
**Expected:** Database name derived from `$USER` (e.g., `nova_memory`, `nova_staging_memory`), not hardcoded

### TC-3.6: Installer respects existing correct cron entries (idempotent)
**Precondition:** Cron entry for embed-memories already present with correct path
**Action:** Run `bash agent-install.sh`
**Expected:** No changes to that entry; count remains 1

---

## 4. Integration Tests (Staging)

### TC-4.1: Gateway loads semantic-recall from managed path after install
**Precondition:** Fresh install on staging
**Action:** Start gateway, run `openclaw hooks info semantic-recall`
**Expected:**
- Source: `openclaw-managed`
- Handler: `~/.openclaw/hooks/semantic-recall/handler.ts`
- Status: `✓ ready`

### TC-4.2: Semantic recall successfully injects memories
**Precondition:** TC-4.1 passes, embeddings exist in database
**Action:** Send a message to trigger `message:received` event
**Expected:** Gateway logs show:
- `[semantic-recall] Found N relevant memories`
- `[semantic-recall] Loaded entity context for: ...`
- No errors

### TC-4.3: Semantic recall handles missing OPENCLAW_STATE_DIR gracefully
**Precondition:** `OPENCLAW_STATE_DIR` is NOT set in environment
**Action:** Start gateway, send a message
**Expected:** Handler falls back to `~/.openclaw` and functions normally

### TC-4.4: No stale workspace hooks interfere
**Precondition:** `~/.openclaw/workspace/hooks/` does NOT exist
**Action:** Run `openclaw hooks list`
**Expected:** No hooks with source `openclaw-workspace` for our hooks (semantic-recall, memory-extract, session-init should all be `openclaw-managed`)

### TC-4.5: Logs use paths derived from OPENCLAW_STATE_DIR
**Precondition:** Set `OPENCLAW_STATE_DIR` to `/tmp/custom-openclaw`
**Action:** Trigger semantic-recall
**Expected:** Log entries for script execution, cron, etc., reference `/tmp/custom-openclaw/logs/`

---

## 5. Edge Cases

### TC-5.1: Username with hyphens
**Precondition:** User is `nova-staging` (contains hyphen)
**Action:** Run installer
**Expected:** 
- Database name: `nova_staging_memory` (hyphens replaced with underscores)
- Venv path: `~/.local/share/nova-staging/venv/bin/python` (raw username)
- Cron entries use correct paths for this user

### TC-5.2: Username with underscore
**Precondition:** User is `john_doe`
**Action:** Run installer
**Expected:** Database name `john_doe_memory` (underscores preserved) and venv path `~/.local/share/john_doe/venv/bin/python`

### TC-5.3: Missing python venv
**Precondition:** Standard venv at `~/.local/share/$USER/venv/` does not exist
**Action:** Gateway starts, message received triggers semantic-recall
**Expected:** Hook logs a clear error about missing venv, does not crash the gateway


---

## Definition of Done

All test cases pass on staging (`nova-staging@localhost`). No hardcoded paths, no relative imports, no `~/clawd` references anywhere in the codebase. Installer is idempotent for hooks, libraries, and cron entries.
