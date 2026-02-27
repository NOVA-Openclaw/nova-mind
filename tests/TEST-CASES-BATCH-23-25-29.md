# Test Cases — Issues #23, #24, #25, #29

Generated: 2026-02-12

---

## Issue #23 — Bug: verify_database() checks wrong table names

**Root Cause:** `verify_database()` checks for `agent_messages` and `agent_conversations` but `agent_chat/schema.sql` creates `agent_chat` and `agent_chat_processed`.

### TC-23-01: Verify correct table names are checked (Happy Path)
- **Setup:** Database with `agent_chat` and `agent_chat_processed` tables present
- **Action:** Run `./agent-install.sh --verify-only`
- **Expected:** Both tables reported as ✅ present; no errors
- **Verify:** grep output for `agent_chat` and `agent_chat_processed` (not `agent_messages`/`agent_conversations`)

### TC-23-02: Missing tables detected correctly
- **Setup:** Database exists but tables dropped (`DROP TABLE agent_chat CASCADE; DROP TABLE agent_chat_processed CASCADE;`)
- **Action:** Run `./agent-install.sh --verify-only`
- **Expected:** Both tables reported as missing/warning

### TC-23-03: No false positives from old table names
- **Setup:** Database with correct tables (`agent_chat`, `agent_chat_processed`) but NO `agent_messages`/`agent_conversations`
- **Action:** Run `./agent-install.sh --verify-only`
- **Expected:** No errors or warnings about missing tables
- **Regression check:** Script must NOT contain strings `agent_messages` or `agent_conversations`

### TC-23-04: Schema in non-public schema
- **Setup:** Tables exist but in a custom schema (e.g., `agent_chat` schema), not `public`
- **Action:** Run verify
- **Expected:** Tables not found (verify checks `public` schema — document this or fix)

### Acceptance Criteria
- [ ] `required_tables` array contains `"agent_chat"` and `"agent_chat_processed"`
- [ ] `grep -c 'agent_messages\|agent_conversations' agent-install.sh` returns 0
- [ ] Full install → verify-only passes with no table warnings

---

## Issue #24 — Bug: Schema errors silently swallowed

**Root Cause:** Line `psql -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE" > /dev/null 2>&1` discards both stdout and stderr, and the exit code is never checked. The next line unconditionally prints "Schema applied".

### TC-24-01: Successful schema apply (Happy Path)
- **Setup:** Valid database, valid schema.sql
- **Action:** Run installer (not verify-only)
- **Expected:** "Schema applied" message, exit code 0

### TC-24-02: Failed schema apply detected (Critical)
- **Setup:** Corrupt schema.sql (e.g., append `INVALID SQL GARBAGE;`) or revoke CREATE permissions
- **Action:** Run installer
- **Expected:** Error reported, installer exits non-zero or clearly warns
- **Critical constraint:** Fix must check `psql` exit code (`$?`), NOT grep stderr. PostgreSQL emits `NOTICE` messages to stderr (e.g., "relation already exists, skipping") that are NOT errors. Checking stderr for content would cause false failures on idempotent re-runs.
- **Verify:** `psql -f schema.sql` on already-initialized DB (produces NOTICE on stderr) → must still report success

### TC-24-03: NOTICE messages don't trigger false failure
- **Setup:** Database already has all tables (idempotent re-run)
- **Action:** Run installer again
- **Expected:** "Schema applied" success (NOTICE about `CREATE TABLE IF NOT EXISTS` is fine)
- **Verify:** Exit code 0, no error messages

### TC-24-04: Missing schema file
- **Setup:** Rename/delete `agent_chat/schema.sql`
- **Action:** Run installer
- **Expected:** Warning about missing schema file (already handled — verify it still works)

### TC-24-05: Database connection lost mid-apply
- **Setup:** Stop PostgreSQL after prerequisites pass but before schema apply (race condition)
- **Action:** Run installer
- **Expected:** Error detected and reported

### Acceptance Criteria
- [ ] Schema apply line checks exit code: `if ! psql ...; then` or `psql ... || { error; exit 1; }`
- [ ] Stderr is NOT used to determine success/failure
- [ ] Stdout can be suppressed (cosmetic) but stderr should ideally be shown on failure for debugging
- [ ] Idempotent re-run (NOTICE messages) still succeeds

---

## Issue #25 — Minor: verify-only mode runs full prerequisite checks

**Root Cause:** The prerequisites block (Node.js, npm, TypeScript, PostgreSQL, createdb checks) runs unconditionally before the `--verify-only` branch. Several checks call `exit 1` if tools are missing, meaning `--verify-only` fails if build tools aren't installed — even though verification only needs `psql`.

### TC-25-01: Verify-only without Node.js (Happy Path for fix)
- **Setup:** System with PostgreSQL but no Node.js/npm
- **Action:** Run `./agent-install.sh --verify-only`
- **Expected (after fix):** Verification runs and reports file/DB status; does NOT exit 1 for missing Node.js
- **Expected (current bug):** Exits with "Node.js not found"

### TC-25-02: Verify-only without TypeScript
- **Setup:** Node.js present, no TypeScript
- **Action:** Run `./agent-install.sh --verify-only`
- **Expected:** Runs fine (TypeScript check is already a warning, not fatal — but verify)

### TC-25-03: Verify-only without createdb
- **Setup:** `psql` available but `createdb` missing
- **Action:** Run `./agent-install.sh --verify-only`
- **Expected (after fix):** Verification proceeds (createdb not needed for verify)
- **Expected (current bug):** `exit 1`

### TC-25-04: Verify-only needs psql
- **Setup:** No PostgreSQL tools at all
- **Action:** Run `./agent-install.sh --verify-only`
- **Expected:** Graceful error — psql IS needed for DB verification. Should fail with clear message, not crash.

### TC-25-05: Normal install still checks all prerequisites
- **Setup:** Run without `--verify-only`
- **Action:** Ensure Node.js/npm/tsc/psql/createdb checks all still execute
- **Expected:** No regression — full install still validates everything

### TC-25-06: Verify-only with --database flag
- **Setup:** Custom database name
- **Action:** `./agent-install.sh --verify-only -d custom_db`
- **Expected:** Verifies against `custom_db`, not default

### Acceptance Criteria
- [ ] `--verify-only` skips or gates Node.js, npm, TypeScript, and createdb checks
- [ ] `--verify-only` still checks psql availability (required for DB verify)
- [ ] Normal install path unchanged (no regression)
- [ ] `--verify-only` on a machine with only psql installed: exits 0 or reports only real issues

---

## Issue #29 — Installer: copy skills instead of symlinking

**Root Cause:** Skills installation (Part 5) uses `ln -s` to symlink skills from repo to workspace. Should use `cp -r` to make independent copies.

### TC-29-01: Fresh install copies skills (Happy Path)
- **Setup:** No existing skills in workspace
- **Action:** Run installer
- **Expected:** `$WORKSPACE/skills/agent-chat` and `agent-spawn` are directories (not symlinks)
- **Verify:** `[ -d "$target" ] && [ ! -L "$target" ]`

### TC-29-02: Copied files are independent of repo
- **Setup:** Fresh install
- **Action:** After install, modify a file in `$WORKSPACE/skills/agent-chat/`
- **Expected:** Original in `$SCRIPT_DIR/skills/agent-chat/` is unchanged
- **Verify:** `diff` between repo and workspace shows the edit; proves no symlink

### TC-29-03: --force overwrites existing copy
- **Setup:** Skills already installed (as copies)
- **Action:** Modify a file in workspace skills, then run `./agent-install.sh --force`
- **Expected:** Workspace skills overwritten with fresh copy from repo; local modification gone

### TC-29-04: Existing symlink replaced with copy on --force
- **Setup:** Old-style symlinked skills in workspace
- **Action:** Run `./agent-install.sh --force`
- **Expected:** Symlink removed, replaced with directory copy
- **Verify:** `[ ! -L "$target" ] && [ -d "$target" ]`

### TC-29-05: Existing directory without --force
- **Setup:** Skills already exist as directories (from previous copy-install)
- **Action:** Run installer without --force
- **Expected:** Skills left untouched, message says "already exists (use --force to reinstall)"

### TC-29-06: Existing symlink without --force
- **Setup:** Old symlinked skills
- **Action:** Run installer without --force
- **Expected:** Warning message; does NOT overwrite

### TC-29-07: Skill source directory missing
- **Setup:** Delete `$SCRIPT_DIR/skills/agent-chat`
- **Action:** Run installer
- **Expected:** Warning "Skill not found: agent-chat (skipping)" — no crash

### TC-29-08: verify_files() updated for copies
- **Setup:** Skills installed as copies
- **Action:** Run `--verify-only`
- **Expected:** Skills reported as ✅ present (verify_files currently checks for symlinks specifically — must be updated to accept directories too)

### TC-29-09: File permissions preserved
- **Setup:** Skills with executable scripts
- **Action:** Install
- **Expected:** File permissions match source

### Acceptance Criteria
- [ ] `ln -s` replaced with `cp -r` in skills installation section
- [ ] `--force` removes existing target (symlink or dir) before copying
- [ ] Without `--force`, existing target (symlink or dir) is not modified
- [ ] `verify_files()` accepts both symlinks (legacy) and directories as valid
- [ ] Repo deletion after install does not break workspace skills
- [ ] All file contents match between source and installed copy (verified with `diff -r`)
