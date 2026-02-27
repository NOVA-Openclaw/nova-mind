# Test Cases: Issue #87 - Skills Installation

**Issue:** agent-install.sh should install skills definitions  
**Date Created:** 2026-02-15  
**Status:** Draft

## Test Environment Setup

### Prerequisites
- Fresh Ubuntu/Debian test environment (or equivalent)
- `agent-install.sh` script available
- Source repository with `skills/` directory structure:
  ```
  skills/
  ├── captcha-solver/DESIGN.md
  ├── memory-extraction-pipeline/SKILL.md
  └── semantic-memory/
      ├── SKILL.md
      └── scripts/proactive-recall.py
  ```
- Target OpenClaw skills location: `~/.openclaw/skills/` (or system-defined location)

---

## Test Cases

### TC-87-01: Fresh Installation - Skills Copied Successfully
**Priority:** P0 (Critical)  
**Type:** Happy Path

**Description:** Verify that on a fresh installation, all skills are copied to the OpenClaw skills location correctly.

**Prerequisites:**
- No existing skills directory at target location
- Source `skills/` directory contains all expected files

**Test Steps:**
1. Run `./agent-install.sh`
2. Check target skills directory exists
3. Verify all skill directories are present
4. Verify all files including nested files are copied

**Expected Results:**
- ✅ Installation completes without errors
- ✅ `~/.openclaw/skills/` directory exists
- ✅ All three skill directories present:
  - `captcha-solver/`
  - `memory-extraction-pipeline/`
  - `semantic-memory/`
- ✅ All files copied with correct structure:
  - `captcha-solver/DESIGN.md`
  - `memory-extraction-pipeline/SKILL.md`
  - `semantic-memory/SKILL.md`
  - `semantic-memory/scripts/proactive-recall.py`
- ✅ File permissions preserved (executable scripts remain executable)
- ✅ Installer reports success: "Skills installed successfully to ~/.openclaw/skills/"

---

### TC-87-02: Fresh Installation - Nested Directory Structure
**Priority:** P0 (Critical)  
**Type:** Boundary Condition

**Description:** Verify nested files and directories (like `scripts/proactive-recall.py`) are copied correctly.

**Prerequisites:**
- Clean environment, no existing skills

**Test Steps:**
1. Run `./agent-install.sh`
2. Navigate to `~/.openclaw/skills/semantic-memory/scripts/`
3. Verify `proactive-recall.py` exists
4. Check file is readable and executable (if applicable)
5. Verify file contents match source

**Expected Results:**
- ✅ `semantic-memory/scripts/` subdirectory created
- ✅ `proactive-recall.py` exists at correct path
- ✅ File permissions match source file
- ✅ File contents identical to source (checksum match)

---

### TC-87-03: Existing Skills - Warn Without Overwrite
**Priority:** P0 (Critical)  
**Type:** Edge Case

**Description:** When skills already exist, installer should warn and NOT overwrite by default.

**Prerequisites:**
- Skills directory already exists at target location
- At least one skill has local modifications (add a test marker file)

**Test Steps:**
1. Create `~/.openclaw/skills/` with existing content
2. Add marker file: `echo "LOCAL_MOD" > ~/.openclaw/skills/semantic-memory/LOCAL_CHANGES.txt`
3. Run `./agent-install.sh`
4. Check if warning message is displayed
5. Verify marker file still exists
6. Check installer exit status

**Expected Results:**
- ⚠️ Warning displayed: "Skills directory already exists at ~/.openclaw/skills/"
- ⚠️ Message: "Existing skills with local modifications will not be overwritten."
- ⚠️ Suggestion: "Use --force to overwrite existing skills."
- ✅ Marker file `LOCAL_CHANGES.txt` still exists
- ✅ Installation continues (or exits gracefully with code 0)
- ✅ No files overwritten

---

### TC-87-04: Existing Skills - Force Overwrite
**Priority:** P1 (High)  
**Type:** Edge Case

**Description:** With `--force` flag, existing skills should be overwritten after warning.

**Prerequisites:**
- Skills directory exists with local modifications

**Test Steps:**
1. Create existing skills with marker: `echo "OLD_VERSION" > ~/.openclaw/skills/semantic-memory/SKILL.md`
2. Note original source file content differs from marker
3. Run `./agent-install.sh --force`
4. Check if force warning is displayed
5. Verify marker file is replaced with source version

**Expected Results:**
- ⚠️ Warning: "Force flag detected: overwriting existing skills..."
- ✅ All source files copied over existing files
- ✅ Marker file replaced with source `SKILL.md`
- ✅ File contents match source repository
- ✅ Confirmation message: "Skills forcefully reinstalled."

---

### TC-87-05: Partial Overwrite - New Skills Added
**Priority:** P1 (High)  
**Type:** Edge Case

**Description:** When some skills exist but new ones are added to the source, only new skills should be installed (without --force).

**Prerequisites:**
- Existing skills directory with only `captcha-solver/`
- Source has all three skills

**Test Steps:**
1. Pre-create `~/.openclaw/skills/captcha-solver/DESIGN.md` with custom content
2. Ensure `memory-extraction-pipeline/` and `semantic-memory/` don't exist at target
3. Run `./agent-install.sh`
4. Verify `captcha-solver/` untouched
5. Verify new skills added

**Expected Results:**
- ✅ `captcha-solver/DESIGN.md` remains unchanged
- ✅ `memory-extraction-pipeline/` copied as new
- ✅ `semantic-memory/` copied as new with nested files
- ⚠️ Warning about existing `captcha-solver/`
- ✅ Message: "Added 2 new skill(s), skipped 1 existing."

---

### TC-87-06: Missing Source Directory
**Priority:** P0 (Critical)  
**Type:** Error Condition

**Description:** Installer should fail gracefully if source `skills/` directory is missing.

**Prerequisites:**
- Source repository without `skills/` directory (or renamed/moved)

**Test Steps:**
1. Rename or remove `skills/` from source
2. Run `./agent-install.sh`
3. Check error message
4. Verify installer exit status

**Expected Results:**
- ❌ Error: "Source skills directory not found: ./skills/"
- ❌ Exit code: non-zero (1)
- ✅ No partial installation
- ✅ Helpful message: "Please ensure you're running the installer from the repository root."

---

### TC-87-07: Missing Source Skill Files
**Priority:** P1 (High)  
**Type:** Error Condition

**Description:** If source skills directory exists but is empty or missing expected files, installer should warn but continue.

**Prerequisites:**
- `skills/` directory exists but is empty

**Test Steps:**
1. Create empty `skills/` directory in source
2. Run `./agent-install.sh`
3. Check warning message

**Expected Results:**
- ⚠️ Warning: "Source skills directory is empty"
- ✅ Target directory created anyway
- ✅ Exit code: 0 (success, but with warning)

---

### TC-87-08: Permission Denied - Target Directory
**Priority:** P1 (High)  
**Type:** Error Condition

**Description:** Installer should fail gracefully when lacking write permissions to target location.

**Prerequisites:**
- Target parent directory is write-protected
- Running as non-root user

**Test Steps:**
1. Make parent directory read-only: `chmod 555 ~/.openclaw/`
2. Run `./agent-install.sh`
3. Check error message
4. Restore permissions: `chmod 755 ~/.openclaw/`

**Expected Results:**
- ❌ Error: "Permission denied: cannot create ~/.openclaw/skills/"
- ❌ Exit code: non-zero
- ✅ Helpful suggestion: "Try running with sudo or check directory permissions"
- ✅ No partial files created

---

### TC-87-09: Permission Denied - Source Files
**Priority:** P2 (Medium)  
**Type:** Error Condition

**Description:** Installer should handle unreadable source files gracefully.

**Prerequisites:**
- Source skill files exist but are not readable

**Test Steps:**
1. Remove read permission: `chmod 000 skills/semantic-memory/SKILL.md`
2. Run `./agent-install.sh`
3. Check behavior

**Expected Results:**
- ⚠️ Warning: "Cannot read source file: skills/semantic-memory/SKILL.md"
- ✅ Other files still copied
- ⚠️ Exit code: non-zero or with warning status
- ✅ Summary: "Installed 2 of 3 skills (1 failed)"

---

### TC-87-10: Verification Step - Installation Check
**Priority:** P0 (Critical)  
**Type:** Verification

**Description:** Installer includes post-installation verification step to confirm skills are correctly installed.

**Prerequisites:**
- Fresh installation

**Test Steps:**
1. Run `./agent-install.sh`
2. Observe verification output
3. Verify all expected checks pass

**Expected Results:**
- ✅ Verification section in output: "Verifying skills installation..."
- ✅ Check 1: "Skills directory exists: ✓"
- ✅ Check 2: "Found 3 skill(s)"
- ✅ Check 3: "All SKILL.md files readable: ✓"
- ✅ Final message: "Skills installation verified successfully"

---

### TC-87-11: Verification Step - Missing SKILL.md Detection
**Priority:** P1 (High)  
**Type:** Verification

**Description:** Verification should detect if a skill directory lacks a SKILL.md file.

**Prerequisites:**
- Corrupted installation or source missing SKILL.md in one skill

**Test Steps:**
1. Remove `SKILL.md` from one skill in source
2. Run `./agent-install.sh`
3. Check verification warnings

**Expected Results:**
- ⚠️ Warning: "captcha-solver/ has no SKILL.md file"
- ✅ Other skills verified successfully
- ⚠️ Summary: "2 of 3 skills verified (1 warning)"

---

### TC-87-12: Verification - SKILL.md Readability by OpenClaw
**Priority:** P1 (High)  
**Type:** Domain-Specific Verification

**Description:** Verify that installed SKILL.md files can be parsed/read by OpenClaw.

**Prerequisites:**
- OpenClaw skill loader available (or test script simulating it)

**Test Steps:**
1. Run `./agent-install.sh`
2. Run verification: `openclaw skills validate ~/.openclaw/skills/` (if available)
3. Or: Check SKILL.md files have valid YAML frontmatter

**Expected Results:**
- ✅ All SKILL.md files have valid structure
- ✅ YAML frontmatter (if required) is parseable
- ✅ No syntax errors in skill definitions
- ✅ Message: "All skills are valid OpenClaw skill definitions"

---

### TC-87-13: Symlink Handling
**Priority:** P2 (Medium)  
**Type:** Edge Case

**Description:** Verify installer handles symlinks in source directory correctly.

**Prerequisites:**
- Source skills directory contains symlink to external file

**Test Steps:**
1. Create symlink in source: `ln -s /tmp/external.md skills/semantic-memory/EXTERNAL.md`
2. Run `./agent-install.sh`
3. Check if symlink is copied as file or preserved as symlink

**Expected Results:**
- ✅ Symlink either:
  - Copied as regular file (dereferenced), OR
  - Preserved as symlink with warning: "Symlink detected: EXTERNAL.md"
- ✅ Installation completes successfully
- ✅ Documented behavior matches implementation

---

### TC-87-14: Dry Run Mode (Optional Enhancement)
**Priority:** P3 (Low)  
**Type:** Optional Feature

**Description:** If `--dry-run` flag is implemented, verify it shows what would be done without making changes.

**Prerequisites:**
- `--dry-run` flag supported

**Test Steps:**
1. Run `./agent-install.sh --dry-run`
2. Check output describes planned actions
3. Verify no files actually copied

**Expected Results:**
- ✅ Output: "DRY RUN: Would copy skills/ to ~/.openclaw/skills/"
- ✅ List of files that would be copied
- ✅ No actual filesystem changes
- ✅ Exit code: 0

---

### TC-87-15: Idempotency Test
**Priority:** P1 (High)  
**Type:** Reliability

**Description:** Running installer multiple times should be safe and produce consistent results.

**Prerequisites:**
- None

**Test Steps:**
1. Run `./agent-install.sh` (first time)
2. Run `./agent-install.sh` again (second time)
3. Run `./agent-install.sh` again (third time)
4. Compare results

**Expected Results:**
- ✅ First run: installs successfully
- ✅ Second run: detects existing, skips or warns
- ✅ Third run: same as second
- ✅ All runs exit cleanly
- ✅ No accumulated errors or warnings

---

## Test Execution Matrix

| Test Case | Priority | Automated | Manual | Status |
|-----------|----------|-----------|--------|--------|
| TC-87-01 | P0 | ✓ | ✓ | Pending |
| TC-87-02 | P0 | ✓ | ✓ | Pending |
| TC-87-03 | P0 | ✓ | ✓ | Pending |
| TC-87-04 | P1 | ✓ | ✓ | Pending |
| TC-87-05 | P1 | ✓ | ✓ | Pending |
| TC-87-06 | P0 | ✓ | ✓ | Pending |
| TC-87-07 | P1 | ✓ | - | Pending |
| TC-87-08 | P1 | ✓ | ✓ | Pending |
| TC-87-09 | P2 | ✓ | - | Pending |
| TC-87-10 | P0 | ✓ | ✓ | Pending |
| TC-87-11 | P1 | ✓ | - | Pending |
| TC-87-12 | P1 | - | ✓ | Pending |
| TC-87-13 | P2 | ✓ | - | Pending |
| TC-87-14 | P3 | - | - | Optional |
| TC-87-15 | P1 | ✓ | ✓ | Pending |

## Acceptance Criteria Mapping

| Acceptance Criterion | Test Cases Covering |
|----------------------|---------------------|
| 1. Skills directory copied to appropriate location | TC-87-01, TC-87-02, TC-87-10 |
| 2. Existing skills with local mods handled gracefully | TC-87-03, TC-87-04, TC-87-05 |
| 3. Verification step checks installation | TC-87-10, TC-87-11, TC-87-12 |

---

**Last Updated:** 2026-02-15  
**Owner:** QA Team / nova-memory contributors
