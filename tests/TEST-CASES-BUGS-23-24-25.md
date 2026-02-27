# Test Cases — Bug Fixes #23, #24, #25

**Issues:**
- NOVA-Openclaw/nova-cognition#23 — `verify_database()` checks wrong table names
- NOVA-Openclaw/nova-cognition#24 — Schema errors silently swallowed
- NOVA-Openclaw/nova-cognition#25 — Verify-only mode runs full prerequisite checks

**Component:** `agent-install.sh`
**Date:** 2025-02-11

---

## Relationship to TEST-CASES-ISSUE-22.md

These bugs were discovered during Issue #22 test design and documented as "Known Issues A, B, C" in that file. The existing test cases provide **partial** coverage:

| Bug   | Existing Coverage | Gap |
|-------|------------------|-----|
| #23   | TC-07c notes the wrong-table bug | No test that **passes** when fix is applied |
| #24   | TC-05e documents the silent-swallow behavior | No test that **verifies errors are surfaced** post-fix |
| #25   | TC-07a/b run verify-only but don't check prereq behavior | No test that checks prereq output is reduced |

This file adds **targeted regression tests** for each fix.

---

## Issue #23: `verify_database()` Checks Wrong Table Names

### Bug Description

`verify_database()` (line ~244) contains:
```bash
local required_tables=("agent_messages" "agent_conversations")
```
But `focus/agent_chat/schema.sql` creates tables `agent_chat` and `agent_chat_processed`. Verification always reports these as "missing optional tables" even after successful schema application.

### Fix Expected

Change to:
```bash
local required_tables=("agent_chat" "agent_chat_processed")
```

---

### TC-23-01: Verification Reports Correct Tables After Fresh Install (Regression)

**Priority:** P0 (Critical)
**Category:** Regression — correct table name validation

**Preconditions:**
- PostgreSQL running
- Database `${DB_NAME}` exists with schema applied (TC-01 from Issue #22 completed)
- Tables `agent_chat` and `agent_chat_processed` exist in database

**Steps:**
1. Confirm schema tables exist:
   ```bash
   psql -U "$DB_USER" -d "$DB_NAME" -tAc \
     "SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public'
      AND table_name IN ('agent_chat', 'agent_chat_processed')
      ORDER BY table_name;"
   ```
   Expected output: `agent_chat` and `agent_chat_processed` (2 rows).

2. Run verify-only:
   ```bash
   ./agent-install.sh --verify-only 2>&1 | tee /tmp/verify-23-01.log
   ```

3. Check verification output for table checks.

**Expected Results:**
- [ ] Output contains: `✅ Table 'agent_chat' exists`
- [ ] Output contains: `✅ Table 'agent_chat_processed' exists`
- [ ] Output does **NOT** contain `agent_messages`
- [ ] Output does **NOT** contain `agent_conversations`
- [ ] No "Missing optional agent_chat tables" warning
- [ ] `VERIFICATION_WARNINGS` is 0 for table checks (may have other warnings)
- [ ] Exit code 0 (assuming no other errors)

**Verification Command (one-liner):**
```bash
./agent-install.sh --verify-only 2>&1 | grep -E "agent_messages|agent_conversations" && echo "FAIL: old table names still present" || echo "PASS: old table names removed"
```

---

### TC-23-02: Verification Detects Missing `agent_chat` Table

**Priority:** P0 (Critical)
**Category:** Negative test — tables genuinely missing

**Preconditions:**
- Database exists but `agent_chat` table does NOT exist (empty database)

**Steps:**
1. Create a fresh test database with no tables:
   ```bash
   createdb -U "$DB_USER" "test_issue23"
   ```
2. Run verify against the empty database:
   ```bash
   ./agent-install.sh --verify-only --database test_issue23 2>&1 | tee /tmp/verify-23-02.log
   ```

**Expected Results:**
- [ ] Output shows `agent_chat` as missing (warning or error)
- [ ] Output shows `agent_chat_processed` as missing
- [ ] Warning count incremented by 2 (for both missing tables)
- [ ] Does NOT reference `agent_messages` or `agent_conversations`

**Cleanup:**
```bash
dropdb -U "$DB_USER" --if-exists "test_issue23"
```

---

### TC-23-03: Full Install → Verify Round-Trip (Integration)

**Priority:** P1 (High)
**Category:** Integration — install then verify finds no issues

**Preconditions:**
- No existing test database

**Steps:**
1. Clean slate:
   ```bash
   dropdb -U "$DB_USER" --if-exists "test_roundtrip_23"
   ```
2. Run full install with test database:
   ```bash
   ./agent-install.sh --database test_roundtrip_23 2>&1 | tee /tmp/install-23-03.log
   ```
3. Run verify-only against same database:
   ```bash
   ./agent-install.sh --verify-only --database test_roundtrip_23 2>&1 | tee /tmp/verify-23-03.log
   ```

**Expected Results:**
- [ ] Install succeeds (exit 0)
- [ ] Verify reports both `agent_chat` and `agent_chat_processed` as ✅
- [ ] Zero table-related warnings in verify output
- [ ] No mention of `agent_messages` or `agent_conversations` in either log

**Cleanup:**
```bash
dropdb -U "$DB_USER" --if-exists "test_roundtrip_23"
```

---

## Issue #24: Schema Errors Silently Swallowed

### Bug Description

Line ~397 of `agent-install.sh`:
```bash
psql -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" > /dev/null 2>&1
echo -e "  ${CHECK_MARK} Schema applied"
```

Two problems:
1. All stderr (error messages) redirected to `/dev/null` — errors invisible
2. `psql` exit code not checked — installer always reports "Schema applied" even on failure

### Fix Expected

Check exit code and surface errors. Example:
```bash
if ! psql -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" 2>&1; then
    echo -e "  ${CROSS_MARK} Schema application failed"
    exit 1
fi
echo -e "  ${CHECK_MARK} Schema applied"
```

Or capture output to a log and check exit code:
```bash
SCHEMA_LOG=$(psql -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" 2>&1)
SCHEMA_EXIT=$?
if [ $SCHEMA_EXIT -ne 0 ]; then
    echo -e "  ${CROSS_MARK} Schema application failed:"
    echo "$SCHEMA_LOG" | tail -10
    exit 1
fi
```

---

### TC-24-01: Schema Syntax Error Detected and Reported

**Priority:** P0 (Critical)
**Category:** Error handling — schema failure surfaces

**Preconditions:**
- PostgreSQL running
- Test database exists (empty)
- Backup of original `schema.sql`

**Steps:**
1. Setup:
   ```bash
   createdb -U "$DB_USER" "test_issue24"
   cp focus/agent_chat/schema.sql focus/focus/agent_chat/schema.sql.bak
   ```
2. Inject a syntax error into schema:
   ```bash
   echo "THIS IS NOT VALID SQL;" >> focus/agent_chat/schema.sql
   ```
3. Run installer:
   ```bash
   ./agent-install.sh --database test_issue24 2>&1 | tee /tmp/install-24-01.log
   EXIT_CODE=$?
   ```

**Expected Results (post-fix):**
- [ ] Installer exits with non-zero code (`EXIT_CODE != 0`)
- [ ] Output contains `❌` or "Schema application failed" (not just `✅ Schema applied`)
- [ ] Error details are visible in output (not swallowed to /dev/null)
- [ ] The specific SQL error is shown or referenced

**Pre-fix behavior (for reference):**
- Installer exits 0 and shows "✅ Schema applied" despite error
- No error message visible

**Cleanup:**
```bash
mv focus/focus/agent_chat/schema.sql.bak focus/agent_chat/schema.sql
dropdb -U "$DB_USER" --if-exists "test_issue24"
```

---

### TC-24-02: Schema With Warning-Level Issues Still Succeeds

**Priority:** P1 (High)
**Category:** Positive — non-fatal psql output doesn't cause false failure

**Preconditions:**
- Database with schema already applied (idempotent re-run scenario)

**Steps:**
1. Setup:
   ```bash
   createdb -U "$DB_USER" "test_issue24_idempotent"
   ```
2. Apply schema first time (creates everything):
   ```bash
   psql -U "$DB_USER" -d "test_issue24_idempotent" -f focus/agent_chat/schema.sql
   ```
3. Run installer (schema re-applied — `IF NOT EXISTS` should prevent errors):
   ```bash
   ./agent-install.sh --database test_issue24_idempotent 2>&1 | tee /tmp/install-24-02.log
   EXIT_CODE=$?
   ```

**Expected Results:**
- [ ] Exit code is 0
- [ ] Output shows `✅ Schema applied`
- [ ] No false `❌` or failure message
- [ ] psql NOTICE messages (e.g., "relation already exists, skipping") do NOT trigger failure
- [ ] The `DO $$ ... EXCEPTION` block for enum type handled gracefully

**Note:** This verifies the fix doesn't over-correct — `NOTICE` level output from idempotent DDL should not be treated as errors. The fix should check **exit code**, not just presence of output on stderr (psql sends NOTICE to stderr).

**Cleanup:**
```bash
dropdb -U "$DB_USER" --if-exists "test_issue24_idempotent"
```

---

### TC-24-03: Schema With Permission Error Detected

**Priority:** P1 (High)
**Category:** Error handling — auth/permission failure

**Preconditions:**
- Test database exists
- A restricted PostgreSQL role with CONNECT but no CREATE privilege on schema

**Steps:**
1. Create restricted role and database:
   ```bash
   psql -U "$DB_USER" -c "CREATE ROLE test_restricted LOGIN;"
   createdb -U "$DB_USER" "test_issue24_perms"
   psql -U "$DB_USER" -d "test_issue24_perms" -c "REVOKE CREATE ON SCHEMA public FROM test_restricted;"
   ```
2. Run installer as restricted user:
   ```bash
   PGUSER=test_restricted ./agent-install.sh --database test_issue24_perms 2>&1 | tee /tmp/install-24-03.log
   EXIT_CODE=$?
   ```

**Expected Results (post-fix):**
- [ ] Exit code is non-zero
- [ ] Output shows schema application failed
- [ ] Permission error message is visible (not swallowed)

**Cleanup:**
```bash
dropdb -U "$DB_USER" --if-exists "test_issue24_perms"
psql -U "$DB_USER" -c "DROP ROLE IF EXISTS test_restricted;"
```

---

### TC-24-04: Completely Invalid Schema File (Non-SQL Content)

**Priority:** P2 (Medium)
**Category:** Edge case — garbage input

**Preconditions:**
- Test database exists

**Steps:**
1. Setup:
   ```bash
   createdb -U "$DB_USER" "test_issue24_garbage"
   cp focus/agent_chat/schema.sql focus/focus/agent_chat/schema.sql.bak
   echo "This is not SQL at all. Just random text. 🎉" > focus/agent_chat/schema.sql
   ```
2. Run installer:
   ```bash
   ./agent-install.sh --database test_issue24_garbage 2>&1 | tee /tmp/install-24-04.log
   EXIT_CODE=$?
   ```

**Expected Results:**
- [ ] Exit code is non-zero
- [ ] Error is visible in output
- [ ] Installer does NOT report `✅ Schema applied`

**Cleanup:**
```bash
mv focus/focus/agent_chat/schema.sql.bak focus/agent_chat/schema.sql
dropdb -U "$DB_USER" --if-exists "test_issue24_garbage"
```

---

## Issue #25: Verify-Only Mode Runs Full Prerequisite Checks

### Bug Description

When `--verify-only` is passed, the prerequisites section (lines ~339–366) still runs all checks including:
- Node.js version check
- npm check
- TypeScript check
- PostgreSQL + pg_isready
- createdb check (with `exit 1` on missing!)
- Database existence check

Some of these are irrelevant or misleading for verification:
- `createdb` is not needed just to verify (only `psql` is needed)
- Node.js/npm/TypeScript checks are noise if user only wants to check database/files
- Missing `createdb` causes hard `exit 1` even in verify-only mode

### Fix Expected

Either:
- **A)** Skip non-essential prerequisites in verify-only mode (only check `psql`)
- **B)** Make `createdb` check a warning instead of hard fail in verify-only mode
- **C)** Move the prerequisites block inside the `if [ $VERIFY_ONLY -eq 0 ]` guard and have verify-only do its own minimal check

---

### TC-25-01: Verify-Only Succeeds Without `createdb` on PATH

**Priority:** P1 (High)
**Category:** Regression — verify-only should not require createdb

**Preconditions:**
- PostgreSQL running
- Database exists with schema applied
- `createdb` temporarily removed from PATH

**Steps:**
1. Hide `createdb` from PATH:
   ```bash
   CREATEDB_PATH=$(which createdb)
   CREATEDB_DIR=$(dirname "$CREATEDB_PATH")
   # Create a temporary PATH without the createdb directory
   RESTRICTED_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$CREATEDB_DIR" | tr '\n' ':' | sed 's/:$//')
   ```
2. Run verify-only with restricted PATH:
   ```bash
   PATH="$RESTRICTED_PATH" ./agent-install.sh --verify-only 2>&1 | tee /tmp/verify-25-01.log
   EXIT_CODE=$?
   ```

**Expected Results (post-fix):**
- [ ] Exit code is 0 (verification passes, assuming DB/files are fine)
- [ ] Does NOT exit with `❌ createdb not found` + exit 1
- [ ] Verification results are shown normally
- [ ] `psql` availability IS still checked (needed for DB verification)

**Pre-fix behavior:**
- Installer exits 1 with "❌ createdb not found" before verification runs

---

### TC-25-02: Verify-Only Skips Irrelevant Prerequisites

**Priority:** P2 (Medium)
**Category:** UX — verify output is clean

**Preconditions:**
- Full installation completed
- All tools available

**Steps:**
1. Run verify-only and capture output:
   ```bash
   ./agent-install.sh --verify-only 2>&1 | tee /tmp/verify-25-02.log
   ```
2. Analyze prerequisites section of output.

**Expected Results (post-fix, option A/C):**
- [ ] Output does NOT check for Node.js in verify-only mode (or shows minimal check)
- [ ] Output does NOT check for npm in verify-only mode
- [ ] Output does NOT check for TypeScript in verify-only mode
- [ ] Output does NOT check for `createdb` in verify-only mode
- [ ] Output DOES check for `psql` (needed for DB verification)
- [ ] Output DOES check for PostgreSQL service running

**Alternative Expected Results (option B — softer fix):**
- [ ] All prerequisites still checked but as warnings, not hard failures
- [ ] Missing `createdb` shows ⚠️ not ❌, and does not `exit 1`

---

### TC-25-03: Verify-Only Still Requires psql

**Priority:** P1 (High)
**Category:** Negative test — psql is genuinely needed for verify

**Preconditions:**
- `psql` temporarily removed from PATH

**Steps:**
1. Hide `psql` from PATH (same approach as TC-25-01).
2. Run verify-only:
   ```bash
   PATH="$RESTRICTED_PATH" ./agent-install.sh --verify-only 2>&1 | tee /tmp/verify-25-03.log
   EXIT_CODE=$?
   ```

**Expected Results:**
- [ ] Exit code is non-zero (1)
- [ ] Output indicates `psql` is required
- [ ] Verification cannot proceed without `psql`

---

### TC-25-04: Verify-Only Without Node.js Still Works

**Priority:** P2 (Medium)
**Category:** Edge case — verify on minimal system

**Preconditions:**
- Database and files installed
- Node.js temporarily removed from PATH

**Steps:**
1. Hide `node` from PATH.
2. Run verify-only:
   ```bash
   PATH="$RESTRICTED_PATH" ./agent-install.sh --verify-only 2>&1 | tee /tmp/verify-25-04.log
   EXIT_CODE=$?
   ```

**Expected Results (post-fix):**
- [ ] Verification completes (does not `exit 1` for missing Node.js)
- [ ] File and database verification results shown
- [ ] At most a warning about Node.js, not a hard failure

**Pre-fix behavior:**
- Installer exits 1 with "❌ Node.js not found" before verification runs

---

## Test Coverage Matrix

| Test Case  | Issue | Category         | Priority | Pre-fix Behavior | Post-fix Behavior |
|-----------|-------|------------------|----------|-------------------|-------------------|
| TC-23-01  | #23   | Regression       | P0       | Reports wrong table names as missing | Reports correct tables as ✅ |
| TC-23-02  | #23   | Negative         | P0       | Warns about `agent_messages` missing | Warns about `agent_chat` missing |
| TC-23-03  | #23   | Integration      | P1       | Install ✅ → Verify shows missing tables ❌ | Install ✅ → Verify ✅ |
| TC-24-01  | #24   | Error handling   | P0       | Silent success despite SQL error | Reports failure with details |
| TC-24-02  | #24   | Idempotency      | P1       | N/A (already "works" by hiding all) | Still succeeds, NOTICE not treated as error |
| TC-24-03  | #24   | Error handling   | P1       | Silent success despite permission error | Reports failure with details |
| TC-24-04  | #24   | Edge case        | P2       | Silent success with garbage SQL | Reports failure |
| TC-25-01  | #25   | Regression       | P1       | Hard exit 1 (createdb not found) | Verify succeeds without createdb |
| TC-25-02  | #25   | UX               | P2       | All prereqs checked + noise | Only relevant prereqs checked |
| TC-25-03  | #25   | Negative         | P1       | Hard exit 1 (psql not found) | Still hard exit 1 (psql needed) |
| TC-25-04  | #25   | Edge case        | P2       | Hard exit 1 (node not found) | Verify succeeds without node |

---

## Definition of Done

### Issue #23
- [ ] TC-23-01 passes — correct table names checked
- [ ] TC-23-02 passes — missing tables correctly identified
- [ ] TC-23-03 passes — install→verify round-trip clean

### Issue #24
- [ ] TC-24-01 passes — SQL errors detected and reported
- [ ] TC-24-02 passes — idempotent re-runs still succeed (no false failures)
- [ ] TC-24-03 passes — permission errors surfaced

### Issue #25
- [ ] TC-25-01 passes — verify-only works without createdb
- [ ] TC-25-03 passes — verify-only still requires psql

### Stretch Goals
- [ ] TC-24-04 — garbage SQL handled
- [ ] TC-25-02 — clean verify-only output
- [ ] TC-25-04 — verify-only works without Node.js

---

## Notes

- **TC-24-02 is critical** — any fix for #24 must not break idempotency. PostgreSQL sends `NOTICE` messages to stderr for `IF NOT EXISTS` DDL and `DO $$ EXCEPTION` blocks. The fix must distinguish between exit code != 0 (real error) and stderr having NOTICE output (benign).
- **Issue #25 fix scope is flexible** — could be as minimal as changing `exit 1` to a warning for `createdb` in verify-only mode, or as thorough as restructuring the prerequisites section.
- These test cases complement, not replace, the Issue #22 test cases. Run the #22 suite first to establish baseline, then these for regression.
