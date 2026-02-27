# Test Cases — Issue #102: Install PG Loader Functions to ~/.openclaw/lib/

**Issue:** nova-memory #102
**QA Engineer:** Gem (agent_id=2)
**Date:** 2026-02-16
**Depends on:** #94 (loader creation), #95 (script migration)

---

## Summary of Changes Under Test

1. **`agent-install.sh`** gains a new section that copies `lib/pg-env.sh`, `lib/pg_env.py`, and `lib/pg-env.ts` from the repo into `~/.openclaw/lib/`, using SHA-256 hash comparison to decide install/update/skip.
2. **8 bash scripts** change `source "$(dirname "$0")/../lib/pg-env.sh"` → `source ~/.openclaw/lib/pg-env.sh`
3. **4 python scripts** change `sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))` → `sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))`

### Files in scope

| File | Role |
|------|------|
| `agent-install.sh` | Installer — new lib-install section |
| `lib/pg-env.sh` | Bash loader (source) |
| `lib/pg_env.py` | Python loader (source) |
| `lib/pg-env.ts` | TypeScript loader (source) |
| `scripts/store-memories.sh` | Import path change |
| `scripts/extract-memories.sh` | Import path change |
| `scripts/generate-session-context.sh` | Import path change |
| `scripts/embed-delegation-facts.sh` | Import path change |
| `scripts/get-visible-facts.sh` | Import path change |
| `scripts/process-input-with-grammar.sh` | Import path change |
| `scripts/resolve-participants.sh` | Import path change |
| `scripts/test-delegation-memory.sh` | Import path change |
| `scripts/confidence_helper.py` | Import path change |
| `scripts/dedup_helper.py` | Import path change |
| `scripts/memory-maintenance.py` | Import path change |
| `scripts/proactive-recall.py` | Import path change |

---

## A. Installer (`agent-install.sh`) — Lib Install Section

### A1. Fresh install — no `~/.openclaw/lib/` directory

| Field | Value |
|-------|-------|
| **Precondition** | `~/.openclaw/` exists (it must for postgres.json), `~/.openclaw/lib/` does NOT exist |
| **Action** | Run `agent-install.sh` |
| **Expected** | 1. Creates `~/.openclaw/lib/` directory<br>2. Copies all 3 files: `pg-env.sh`, `pg_env.py`, `pg-env.ts`<br>3. Logs "installed" (or equivalent) for each file<br>4. Files are byte-identical to repo `lib/` versions |

### A2. Fresh install — neither `~/.openclaw/` nor `lib/` exist

| Field | Value |
|-------|-------|
| **Precondition** | `~/.openclaw/` does not exist at all |
| **Note** | `agent-install.sh` already fails if `postgres.json` is missing, so this scenario should fail *before* the lib-install step. Verify installer does NOT create `~/.openclaw/lib/` if it bails on missing config. |

### A3. Upgrade — files already installed, unchanged

| Field | Value |
|-------|-------|
| **Precondition** | All 3 files already exist in `~/.openclaw/lib/` and are identical to repo versions |
| **Action** | Run `agent-install.sh` |
| **Expected** | 1. SHA-256 hash comparison matches for all 3 files<br>2. No files copied/overwritten<br>3. Logs "skipped" or "up to date" for each file<br>4. File modification timestamps unchanged |

### A4. Upgrade — files differ (newer version in repo)

| Field | Value |
|-------|-------|
| **Precondition** | Files exist in `~/.openclaw/lib/` but with older/different content |
| **Action** | Run `agent-install.sh` |
| **Expected** | 1. SHA-256 hash comparison detects mismatch<br>2. All differing files overwritten with repo versions<br>3. Logs "updated" for each changed file<br>4. Unchanged files logged as "skipped" |

### A5. Permissions — installed files are usable

| Field | Value |
|-------|-------|
| **Action** | Run `agent-install.sh`, then check permissions |
| **Expected** | 1. `pg-env.sh` is readable (and ideally `644` or `755` — must be sourceable)<br>2. `pg_env.py` is readable (importable)<br>3. `pg-env.ts` is readable (importable)<br>4. `~/.openclaw/lib/` directory is `755` or `700` |

### A6. Idempotency — multiple runs produce same result

| Field | Value |
|-------|-------|
| **Action** | Run `agent-install.sh` three times consecutively |
| **Expected** | 1. First run: installs/updates as needed<br>2. Second and third runs: all files skipped (already up to date)<br>3. No errors on any run |

### A7. Logging output

| Field | Value |
|-------|-------|
| **Action** | Run `agent-install.sh` in fresh + upgrade scenarios |
| **Expected** | Installer clearly logs per-file status, e.g.:<br>`[lib] pg-env.sh: installed`<br>`[lib] pg_env.py: updated (hash changed)`<br>`[lib] pg-env.ts: skipped (up to date)` |

---

## B. Script Import Path Migration — Bash (8 scripts)

### B1. All bash scripts source from installed path

| Field | Value |
|-------|-------|
| **Action** | `grep -n 'source' scripts/*.sh` |
| **Expected** | All 8 scripts contain `source ~/.openclaw/lib/pg-env.sh` (or `source "$HOME/.openclaw/lib/pg-env.sh"`). NO script contains `source "$(dirname "$0")/../lib/pg-env.sh"` or any repo-relative path. |

**Scripts to verify:**
- [ ] `store-memories.sh`
- [ ] `extract-memories.sh`
- [ ] `generate-session-context.sh`
- [ ] `embed-delegation-facts.sh`
- [ ] `get-visible-facts.sh`
- [ ] `process-input-with-grammar.sh`
- [ ] `resolve-participants.sh`
- [ ] `test-delegation-memory.sh`

### B2. Bash scripts work from any working directory

| Field | Value |
|-------|-------|
| **Precondition** | Loader installed to `~/.openclaw/lib/`, PG config valid |
| **Action** | `cd /tmp && /full/path/to/scripts/store-memories.sh --help` (or equivalent no-op invocation for each) |
| **Expected** | Script sources `~/.openclaw/lib/pg-env.sh` successfully regardless of `$PWD` |

### B3. Bash scripts work when repo directory doesn't exist

| Field | Value |
|-------|-------|
| **Precondition** | Loaders installed to `~/.openclaw/lib/`. Rename `nova-memory/` to `nova-memory.bak/` temporarily. |
| **Action** | Run a bash script by absolute path (copied elsewhere or from PATH) |
| **Expected** | Script loads PG env via `~/.openclaw/lib/pg-env.sh` without errors. No reference to repo `lib/` directory. |

### B4. Bash script fails gracefully if loader not installed

| Field | Value |
|-------|-------|
| **Precondition** | `~/.openclaw/lib/pg-env.sh` does NOT exist |
| **Action** | Run any of the 8 bash scripts |
| **Expected** | Clear error message (bash will error on `source` of missing file). Script should not silently continue with unset PG vars. |

---

## C. Script Import Path Migration — Python (4 scripts)

### C1. All python scripts import from installed path

| Field | Value |
|-------|-------|
| **Action** | `grep -n 'sys.path' scripts/*.py` |
| **Expected** | All 4 scripts contain `sys.path.insert(0, os.path.expanduser("~/.openclaw/lib"))`. NO script contains `os.path.join(os.path.dirname(__file__), '..', 'lib')` or any repo-relative path. |

**Scripts to verify:**
- [ ] `confidence_helper.py`
- [ ] `dedup_helper.py`
- [ ] `memory-maintenance.py`
- [ ] `proactive-recall.py`

### C2. Python scripts work from any working directory

| Field | Value |
|-------|-------|
| **Precondition** | Loader installed to `~/.openclaw/lib/`, PG config valid |
| **Action** | `cd /tmp && python3 /full/path/to/scripts/confidence_helper.py --help` (or equivalent) |
| **Expected** | Imports `pg_env` from `~/.openclaw/lib/` successfully |

### C3. Python scripts work when repo directory doesn't exist

| Field | Value |
|-------|-------|
| **Precondition** | Loaders installed. Repo directory renamed/removed. |
| **Action** | Copy a Python script elsewhere and run it |
| **Expected** | `from pg_env import load_pg_env` resolves via `~/.openclaw/lib/` on `sys.path` |

### C4. Python script fails gracefully if loader not installed

| Field | Value |
|-------|-------|
| **Precondition** | `~/.openclaw/lib/pg_env.py` does NOT exist |
| **Action** | Run any of the 4 python scripts |
| **Expected** | `ModuleNotFoundError` for `pg_env` — clear and diagnosable |

---

## D. Edge Cases

### D1. `~/.openclaw/` exists but `lib/` doesn't

| Field | Value |
|-------|-------|
| **Precondition** | `~/.openclaw/` exists (has `postgres.json`), `~/.openclaw/lib/` removed |
| **Action** | Run `agent-install.sh` |
| **Expected** | Installer creates `lib/` subdirectory and copies all 3 files. No error. |

### D2. Destination file is corrupted/empty — gets overwritten

| Field | Value |
|-------|-------|
| **Precondition** | `~/.openclaw/lib/pg-env.sh` exists but is empty (0 bytes) or contains garbage |
| **Action** | Run `agent-install.sh` |
| **Expected** | SHA-256 hash differs → file overwritten with correct version. Logged as "updated". |

### D3. Destination file is corrupted — all 3 variants

| Field | Value |
|-------|-------|
| **Setup** | Truncate/corrupt each of the 3 files individually |
| **Expected** | Each corrupted file detected and replaced; uncorrupted files skipped |

### D4. Permission denied on `~/.openclaw/lib/`

| Field | Value |
|-------|-------|
| **Precondition** | `chmod 000 ~/.openclaw/lib/` |
| **Action** | Run `agent-install.sh` |
| **Expected** | Installer fails with clear error message about permissions. Does not silently skip. |
| **Cleanup** | `chmod 755 ~/.openclaw/lib/` |

### D5. Read-only destination file

| Field | Value |
|-------|-------|
| **Precondition** | `chmod 444 ~/.openclaw/lib/pg-env.sh`, repo version differs |
| **Action** | Run `agent-install.sh` |
| **Expected** | Either overwrites (if running as owner) or fails with clear error |

### D6. Symlink in destination

| Field | Value |
|-------|-------|
| **Precondition** | `~/.openclaw/lib/pg-env.sh` is a symlink to somewhere else |
| **Action** | Run `agent-install.sh` |
| **Expected** | Installer should replace symlink with actual file (or follow symlink — document chosen behavior) |

---

## E. Hash Comparison Correctness

### E1. SHA-256 used correctly

| Field | Value |
|-------|-------|
| **Action** | Inspect `agent-install.sh` source for the hash comparison logic |
| **Expected** | Uses `sha256sum` (or equivalent) on both source and destination. Compares only hash portion (not filename). |

### E2. Hash comparison handles missing destination

| Field | Value |
|-------|-------|
| **Precondition** | Destination file does not exist |
| **Expected** | Installer doesn't error on hashing a non-existent file; treats as "needs install" |

### E3. Binary-identical files produce matching hashes

| Field | Value |
|-------|-------|
| **Action** | Install, then immediately re-run |
| **Expected** | All 3 hashes match, all 3 files skipped |

---

## F. Integration

### F1. Full install-then-use flow

| Field | Value |
|-------|-------|
| **Action** | 1. Clean state: remove `~/.openclaw/lib/`<br>2. Run `agent-install.sh`<br>3. Run each of the 12 scripts (8 bash + 4 python) with minimal args |
| **Expected** | All scripts source/import PG env from `~/.openclaw/lib/` and connect (or fail with DB error, not import error) |

### F2. Verify no remaining repo-relative imports

| Field | Value |
|-------|-------|
| **Action** | `grep -rn 'dirname.*lib/pg-env\|__file__.*lib' scripts/` |
| **Expected** | Zero matches. All repo-relative import paths eliminated. |

### F3. Other repos can use installed loaders

| Field | Value |
|-------|-------|
| **Action** | From outside nova-memory, write a test script: `source ~/.openclaw/lib/pg-env.sh && load_pg_env && echo $PGHOST` |
| **Expected** | Works. This validates the whole point of #102. |
