# Test Cases — Issue #22: Installer: Create database and apply agent_chat schema

**Issue:** NOVA-Openclaw/nova-cognition#22
**Component:** `agent-install.sh` — Database Setup section (lines ~368–397) + Prerequisites (lines ~339–366)
**Schema:** `focus/agent_chat/schema.sql`
**Date:** 2025-02-11

---

## Overview

These test cases validate the installer's ability to:
1. Create a user-specific database (`${USER//-/_}_memory`) if it doesn't exist
2. Apply `focus/agent_chat/schema.sql` idempotently (IF NOT EXISTS)
3. Include `createdb` in PostgreSQL prerequisite checks
4. Show tables exist in verification instead of warning

Each test case defines preconditions, steps, and expected outcomes that constitute "done."

---

## Test Environment Setup

```bash
# Test database prefix to avoid interfering with real data
TEST_DB_PREFIX="test_issue22_"

# Cleanup function for test isolation
cleanup_test_db() {
    local db_name="$1"
    dropdb -U "$PGUSER" --if-exists "$db_name" 2>/dev/null
}
```

---

## TC-01: Happy Path — Fresh Install (No Existing Database)

**Priority:** P0 (Critical)
**Category:** Happy path

### Preconditions
- PostgreSQL is running (`pg_isready` returns 0)
- `createdb` command is available on PATH
- `psql` command is available on PATH
- Target database does NOT exist
- `focus/agent_chat/schema.sql` exists in source tree

### Steps
1. Ensure database `${USER//-/_}_memory` does not exist:
   ```bash
   dropdb -U "$DB_USER" --if-exists "${DB_USER//-/_}_memory"
   ```
2. Run installer:
   ```bash
   ./agent-install.sh
   ```

### Expected Results
- [ ] Installer exits with code 0
- [ ] Output includes: `Database '${DB_NAME}' created`
- [ ] Output includes: `Database connection verified`
- [ ] Output includes: `Schema applied`
- [ ] Database `${DB_NAME}` exists in `psql -l` output
- [ ] Database is connectable: `psql -U "$DB_USER" -d "$DB_NAME" -c '\q'` succeeds
- [ ] Tables `agent_chat` and `agent_chat_processed` exist in public schema
- [ ] Indexes exist: `idx_agent_chat_recipients`, `idx_agent_chat_timestamp`, `idx_agent_chat_sender`, `idx_agent_chat_processed_agent`, `idx_agent_chat_processed_status` (Note: #106 renamed `idx_agent_chat_mentions→recipients`, `idx_agent_chat_created_at→timestamp`, removed `idx_agent_chat_channel`)
- [ ] Custom type `agent_chat_status` exists with values: `received`, `routed`, `responded`, `failed`
- [ ] Function `notify_agent_chat()` exists
- [ ] Trigger `agent_chat_notify` exists on `agent_chat` table
- [ ] Verification section shows ✅ for database checks (not ❌ or ⚠️)

### Verification Query
```sql
-- Run against the created database
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN ('agent_chat', 'agent_chat_processed')
ORDER BY table_name;
-- Expected: 2 rows

SELECT typname FROM pg_type WHERE typname = 'agent_chat_status';
-- Expected: 1 row

SELECT tgname FROM pg_trigger WHERE tgname = 'agent_chat_notify';
-- Expected: 1 row
```

---

## TC-02: Idempotent — Re-run When Database Already Exists

**Priority:** P0 (Critical)
**Category:** Idempotency

### Preconditions
- TC-01 has been run successfully (database and schema exist)
- Database contains existing data (optional: insert test row)

### Steps
1. Insert a test row to confirm data preservation (direct INSERT is blocked since #106; use `send_agent_message()`):
   ```bash
   psql -U "$DB_USER" -d "$DB_NAME" -c \
     "SELECT send_agent_message('tester', 'preserve me', ARRAY['tester']);"
   ```
2. Note the row count:
   ```bash
   psql -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT COUNT(*) FROM agent_chat;"
   ```
3. Run installer again:
   ```bash
   ./agent-install.sh
   ```
4. Check row count again.

### Expected Results
- [ ] Installer exits with code 0 (no failure)
- [ ] Output includes: `Database '${DB_NAME}' exists` (not "created")
- [ ] Output includes: `Schema applied` (schema re-applied without error)
- [ ] Existing data is preserved — row count unchanged
- [ ] Test row is still readable:
  ```sql
  SELECT message FROM agent_chat WHERE sender = 'tester' AND message = 'preserve me';
  ```
- [ ] No duplicate tables, indexes, types, or triggers
- [ ] No `ERROR` or `FATAL` in psql output during schema application
- [ ] Custom type `agent_chat_status` not duplicated (DO/EXCEPTION block handles it)

---

## TC-03: Schema Application — Tables Created Correctly

**Priority:** P0 (Critical)
**Category:** Schema validation

### Preconditions
- Fresh database with no tables

### Steps
1. Create a blank database:
   ```bash
   createdb -U "$DB_USER" "test_schema_validation"
   ```
2. Apply schema directly:
   ```bash
   psql -U "$DB_USER" -d "test_schema_validation" -f focus/agent_chat/schema.sql
   ```
3. Validate all schema objects.

### Expected Results

#### Tables
- [ ] `agent_chat` table exists with columns (as of #106):
  | Column      | Type          | Nullable | Default             |
  |-------------|---------------|----------|---------------------|
  | id          | SERIAL (int4) | NOT NULL | nextval(sequence)   |
  | sender      | TEXT          | NOT NULL | —                   |
  | message     | TEXT          | NOT NULL | —                   |
  | recipients  | TEXT[]        | NOT NULL | — (CHECK: length>0) |
  | reply_to    | INTEGER       | YES      | NULL                |
  | "timestamp" | TIMESTAMPTZ   | NOT NULL | NOW()               |

- [ ] `agent_chat_processed` table exists with columns:
  | Column       | Type               | Nullable | Default     |
  |--------------|--------------------|----------|-------------|
  | chat_id      | INTEGER            | NOT NULL | —           |
  | agent        | TEXT               | NOT NULL | —           |
  | status       | agent_chat_status  | NOT NULL | 'received'  |
  | received_at  | TIMESTAMP          | YES      | NOW()       |
  | routed_at    | TIMESTAMP          | YES      | NULL        |
  | responded_at | TIMESTAMP          | YES      | NULL        |
  | error_message| TEXT               | YES      | NULL        |

#### Constraints
- [ ] `agent_chat.id` is PRIMARY KEY
- [ ] `agent_chat.reply_to` has FOREIGN KEY → `agent_chat(id)`
- [ ] `agent_chat_processed` has composite PRIMARY KEY `(chat_id, agent)`
- [ ] `agent_chat_processed.chat_id` has FOREIGN KEY → `agent_chat(id)` with ON DELETE CASCADE

#### Indexes (as of #106)
- [ ] `idx_agent_chat_recipients` — GIN index on `agent_chat(recipients)` (was `idx_agent_chat_mentions`)
- [ ] `idx_agent_chat_timestamp` — B-tree on `agent_chat("timestamp")` (was `idx_agent_chat_created_at`)
- [ ] `idx_agent_chat_sender` — B-tree on `agent_chat(sender, "timestamp" DESC)`
- [ ] `idx_agent_chat_processed_agent` — B-tree on `agent_chat_processed(agent)`
- [ ] `idx_agent_chat_processed_status` — B-tree on `agent_chat_processed(status)`

#### Custom Type
- [ ] `agent_chat_status` ENUM with values: `received`, `routed`, `responded`, `failed`

#### Functions & Triggers
- [ ] Function `notify_agent_chat()` exists, returns TRIGGER, language plpgsql
- [ ] Function `send_agent_message(text, text, text[])` exists, SECURITY DEFINER, validates sender/recipients
- [ ] Function `enforce_agent_chat_function_use()` exists, returns TRIGGER
- [ ] Trigger `trg_notify_agent_chat` fires AFTER INSERT on `agent_chat`, FOR EACH ROW
- [ ] Trigger `trg_enforce_agent_chat_function_use` fires BEFORE INSERT on `agent_chat`, blocks direct inserts

#### Functional Test
- [ ] Insert via `send_agent_message()` triggers notification:
  ```sql
  LISTEN agent_chat;
  SELECT send_agent_message('test', 'Hello @agent', ARRAY['agent']);
  -- Should receive NOTIFY with JSON payload containing id, sender, recipients
  ```
- [ ] Direct INSERT is blocked:
  ```sql
  INSERT INTO agent_chat (sender, message, recipients) VALUES ('test', 'hello', ARRAY['agent']);
  -- Expected: ERROR: Direct INSERT on agent_chat is not allowed. Use send_agent_message() instead.
  ```

### Cleanup
```bash
dropdb -U "$DB_USER" "test_schema_validation"
```

---

## TC-04: Edge Case — Username with Hyphens

**Priority:** P1 (High)
**Category:** Edge case — name transformation

### Preconditions
- PostgreSQL running
- `createdb` available

### Test Cases

#### TC-04a: Simple hyphenated username
**Input:** `USER=nova-staging`
**Expected DB name:** `nova_staging_memory`

#### TC-04b: Multiple hyphens
**Input:** `USER=my-cool-agent`
**Expected DB name:** `my_cool_agent_memory`

#### TC-04c: Leading hyphen
**Input:** `USER=-leadinghyphen`
**Expected DB name:** `_leadinghyphen_memory`

#### TC-04d: Trailing hyphen
**Input:** `USER=trailinghyphen-`
**Expected DB name:** `trailinghyphen__memory`

#### TC-04e: Consecutive hyphens
**Input:** `USER=double--hyphen`
**Expected DB name:** `double__hyphen_memory`

#### TC-04f: No hyphens (baseline)
**Input:** `USER=nova`
**Expected DB name:** `nova_memory`

### Steps (per sub-case)
1. Override USER for test:
   ```bash
   # Use --database flag or set PGUSER
   ./agent-install.sh --database "<expected_db_name>"
   ```
2. Or test the bash transformation directly:
   ```bash
   USER="nova-staging"
   DB_NAME="${USER//-/_}_memory"
   echo "$DB_NAME"
   # Expected: nova_staging_memory
   ```

### Expected Results
- [ ] Bash substitution `${USER//-/_}` correctly replaces ALL hyphens (not just first)
- [ ] Database name is valid PostgreSQL identifier (no leading digits, etc.)
- [ ] Database can be created with the transformed name
- [ ] `--database` flag override works and bypasses transformation

### Note on Current Implementation
The installer uses `${USER//-/_}` which is bash-specific (double-slash = global replace). Verify this works in the target shell. POSIX `sh` does NOT support this syntax.

---

## TC-05: Error Conditions

**Priority:** P1 (High)
**Category:** Error handling

### TC-05a: PostgreSQL Not Running

**Preconditions:** PostgreSQL service stopped

**Steps:**
1. Stop PostgreSQL:
   ```bash
   sudo systemctl stop postgresql
   ```
2. Run installer:
   ```bash
   ./agent-install.sh
   ```

**Expected Results:**
- [ ] Prerequisite check shows: `⚠️ PostgreSQL service not running`
- [ ] Installer continues past prereq check (current behavior: warning only)
- [ ] Database creation fails with meaningful error
- [ ] Installer exits with non-zero code (due to `set -e` + `createdb` failure)
- [ ] No partial state left behind

**Cleanup:** `sudo systemctl start postgresql`

---

### TC-05b: `createdb` Command Not Available

**Preconditions:** `createdb` not in PATH

**Steps:**
1. Temporarily hide createdb:
   ```bash
   PATH_BACKUP="$PATH"
   # Remove directory containing createdb from PATH
   export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "$(dirname $(which createdb))" | tr '\n' ':')
   ```
2. Run installer:
   ```bash
   ./agent-install.sh
   ```

**Expected Results:**
- [ ] Prerequisite check shows: `❌ createdb not found`
- [ ] Installer prints install instructions for postgresql-client
- [ ] Installer exits with code 1 (hard failure at prereq stage)
- [ ] Does NOT attempt database creation

**Cleanup:** `export PATH="$PATH_BACKUP"`

---

### TC-05c: `psql` Command Not Available

**Preconditions:** `psql` not in PATH

**Steps:** Same approach as TC-05b but for `psql`.

**Expected Results:**
- [ ] Prerequisite check shows: `❌ PostgreSQL not found`
- [ ] Installer exits with code 1

---

### TC-05d: Schema File Missing

**Preconditions:** `focus/agent_chat/schema.sql` renamed/removed

**Steps:**
1. Move schema file:
   ```bash
   mv focus/agent_chat/schema.sql focus/focus/agent_chat/schema.sql.bak
   ```
2. Run installer:
   ```bash
   ./agent-install.sh
   ```

**Expected Results:**
- [ ] Database is still created successfully
- [ ] Output includes: `⚠️ focus/agent_chat/schema.sql not found (will be created by extension)`
- [ ] Installer does NOT exit with error (graceful degradation)
- [ ] No tables created in database (expected — no schema to apply)

**Cleanup:** `mv focus/focus/agent_chat/schema.sql.bak focus/agent_chat/schema.sql`

---

### TC-05e: Schema SQL Contains Syntax Error

**Preconditions:** Corrupt schema.sql

**Steps:**
1. Backup and corrupt schema:
   ```bash
   cp focus/agent_chat/schema.sql focus/focus/agent_chat/schema.sql.bak
   echo "INVALID SQL STATEMENT HERE;" >> focus/agent_chat/schema.sql
   ```
2. Run installer:
   ```bash
   ./agent-install.sh
   ```

**Expected Results:**
- [ ] ⚠️ **BUG RISK:** Current code redirects psql stderr to /dev/null:
  ```bash
  psql -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" > /dev/null 2>&1
  ```
  This silently swallows schema errors. The exit code is also not checked.
- [ ] Installer reports "Schema applied" even if schema had errors
- [ ] **Recommendation:** Check psql exit code and surface errors

**Cleanup:** `mv focus/focus/agent_chat/schema.sql.bak focus/agent_chat/schema.sql`

---

### TC-05f: Database User Lacks CREATE DATABASE Permission

**Preconditions:** Running as a PostgreSQL user without CREATEDB privilege

**Steps:**
1. Run installer with restricted user:
   ```bash
   PGUSER=restricted_user ./agent-install.sh
   ```

**Expected Results:**
- [ ] `createdb` fails with permission error
- [ ] Installer exits with non-zero code (due to `set -e` and `|| exit 1`)
- [ ] Error message is visible to user
- [ ] Output includes: `❌ Failed to create database`

---

### TC-05g: Database Exists But User Cannot Connect

**Preconditions:** Database exists, but connection auth fails (e.g., pg_hba.conf mismatch)

**Expected Results:**
- [ ] `psql -c '\q'` check fails
- [ ] Output includes: `❌ Cannot connect to database`
- [ ] Installer exits with code 1

---

## TC-06: Boundary Values

**Priority:** P2 (Medium)
**Category:** Boundary conditions

### TC-06a: Empty Database (Exists But Has No Tables)

**Preconditions:** Database exists with no schema objects

**Steps:**
1. Create empty database:
   ```bash
   createdb -U "$DB_USER" "${DB_USER//-/_}_memory"
   ```
2. Run installer:
   ```bash
   ./agent-install.sh
   ```

**Expected Results:**
- [ ] Output includes: `Database '${DB_NAME}' exists` (not "created")
- [ ] Schema is applied to the empty database
- [ ] All tables, indexes, types, triggers created
- [ ] Verification passes

---

### TC-06b: Existing Tables With Data (Upgrade Scenario)

**Preconditions:** Database has agent_chat tables with existing rows

**Steps:**
1. Set up database with existing data (use `send_agent_message()` — direct INSERT is blocked since #106):
   ```bash
   psql -U "$DB_USER" -d "$DB_NAME" -c "
     SELECT send_agent_message('alice', 'Hello', ARRAY['*']);
     SELECT send_agent_message('bob', 'Hi there', ARRAY['*']);
     SELECT send_agent_message('charlie', 'Secret message', ARRAY['nova']);
   "
   psql -U "$DB_USER" -d "$DB_NAME" -c "
     INSERT INTO agent_chat_processed (chat_id, agent, status) VALUES
       (1, 'nova', 'responded');
   "
   ```
2. Run installer:
   ```bash
   ./agent-install.sh
   ```

**Expected Results:**
- [ ] All 3 chat rows preserved
- [ ] All 1 processed row preserved
- [ ] No duplicate schema objects
- [ ] Indexes intact and usable
- [ ] Trigger still fires on new inserts

---

### TC-06c: Database Name Override via `--database` Flag

**Steps:**
```bash
./agent-install.sh --database custom_test_db
```

**Expected Results:**
- [ ] Database `custom_test_db` is created (not `${USER}_memory`)
- [ ] Schema applied to `custom_test_db`
- [ ] All references use override name throughout

**Cleanup:** `dropdb -U "$DB_USER" --if-exists custom_test_db`

---

### TC-06d: Database Name Override via `-d` Short Flag

**Steps:**
```bash
./agent-install.sh -d custom_test_db_short
```

**Expected Results:**
- [ ] Same behavior as TC-06c with short flag

**Cleanup:** `dropdb -U "$DB_USER" --if-exists custom_test_db_short`

---

### TC-06e: PGUSER Environment Variable Override

**Steps:**
```bash
PGUSER=testuser ./agent-install.sh
```

**Expected Results:**
- [ ] `DB_USER` resolves to `testuser` (not `whoami`)
- [ ] Database name becomes `testuser_memory`

---

## TC-07: Verification Mode (`--verify-only`)

**Priority:** P1 (High)
**Category:** Verification flow

### TC-07a: Verify After Successful Install

**Preconditions:** TC-01 completed successfully

**Steps:**
```bash
./agent-install.sh --verify-only
```

**Expected Results:**
- [ ] No database modifications made
- [ ] Output shows `Database '${DB_NAME}' exists` with ✅
- [ ] Output shows `Database connection works` with ✅
- [ ] Exits with code 0
- [ ] Does NOT create, modify, or drop anything

---

### TC-07b: Verify When Database Missing

**Preconditions:** Database does not exist

**Steps:**
```bash
dropdb -U "$DB_USER" --if-exists "${DB_USER//-/_}_memory"
./agent-install.sh --verify-only
```

**Expected Results:**
- [ ] Output shows: `❌ Database '${DB_NAME}' does not exist`
- [ ] `VERIFICATION_ERRORS` incremented
- [ ] Exits with code 1
- [ ] Database is NOT created (verify-only should not modify state)

---

### TC-07c: Verify Shows Tables Instead of Warning

**Preconditions:** Database and schema fully installed

**Steps:**
```bash
./agent-install.sh --verify-only
```

**Expected Results:**
- [ ] Verification output shows table existence checks with ✅
- [ ] No "agent_chat tables missing" warning when tables exist
- [ ] **Note:** Current verify_database() checks `agent_messages` and `agent_conversations` — these are NOT the tables created by schema.sql. This is a **bug** (see Known Issues below).

---

## TC-08: Concurrent Execution

**Priority:** P3 (Low)
**Category:** Race condition

### TC-08a: Two Installers Running Simultaneously

**Preconditions:** Database does not exist

**Steps:**
```bash
./agent-install.sh &
./agent-install.sh &
wait
```

**Expected Results:**
- [ ] At least one succeeds
- [ ] No corrupt state (partial schema)
- [ ] `createdb` may fail in one instance (database already exists) — should be handled gracefully
- [ ] **Note:** Current code does NOT handle this — `createdb` will fail with "database already exists" and `set -e` will exit. The conditional check + createdb is not atomic.

---

## Known Issues Found During Test Design

### Issue A: Verification Checks Wrong Tables
**Location:** `verify_database()` function, line ~244
**Problem:** Verification checks for tables `agent_messages` and `agent_conversations`, but `schema.sql` creates `agent_chat` and `agent_chat_processed`. This means verification will always warn about "missing" tables even after successful schema application.
**Fix:** Update `required_tables` array to `("agent_chat" "agent_chat_processed")`.

### Issue B: Schema Errors Silently Swallowed
**Location:** Line ~397
**Problem:** `psql -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" > /dev/null 2>&1` suppresses all output including errors. Exit code is not checked.
**Fix:** Capture exit code, show stderr on failure:
```bash
if ! psql -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" 2>&1 | tail -5; then
    echo -e "  ${CROSS_MARK} Schema application failed"
    exit 1
fi
```

### Issue C: Verify-Only Mode Still Checks createdb Prereq
**Location:** Prerequisites section runs unconditionally.
**Impact:** Minor — just informational, but could confuse users who only want to verify.

---

## Definition of Done

Issue #22 is **complete** when ALL of the following pass:

1. ✅ **TC-01** passes — fresh install creates database and applies schema
2. ✅ **TC-02** passes — re-running is safe and preserves data
3. ✅ **TC-03** passes — all schema objects match specification
4. ✅ **TC-04a, TC-04b, TC-04f** pass — hyphen-to-underscore transformation works
5. ✅ **TC-05b** passes — missing `createdb` caught in prerequisites
6. ✅ **TC-07a, TC-07b** pass — verify-only mode works correctly
7. ✅ **Known Issue A** fixed — verification checks correct table names
8. ✅ **Known Issue B** addressed — schema errors are surfaced (not swallowed)
9. ✅ **TC-07c** passes — verification shows tables exist (not warnings)

**Stretch goals:**
- TC-05a, TC-05e, TC-05f error handling improvements
- TC-08a concurrent execution safety

---

## Test Execution Notes

- Tests should be run in order (TC-01 → TC-02 → ... ) for dependent tests
- Independent tests (TC-04, TC-05, TC-06) can run in any order
- All tests should clean up after themselves (drop test databases)
- Tests requiring service stop (TC-05a) should run last or in isolation
- The `--database` flag is useful for test isolation (avoids touching real database)
