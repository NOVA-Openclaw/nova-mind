# Test Cases — nova-mind Issue #352
## Remove Deprecated Individual Embedding Scripts + Update Installer

**SE Run:** #326  
**Issue:** nova-mind#352  
**Related:** nova-workspace#23  
**Author:** Gem (QA Domain)  
**Date:** 2026-06-30  

---

## Overview

These test cases validate the changes in nova-mind: removal of 4 deprecated individual embedding scripts, relocation of `memory-maintenance.py` to `memory/templates/`, and updates to `agent-install.sh` to support install-if-not-exists template logic plus cleanup of stale deployed scripts.

---

## Area 1 — Script Removal from `memory/scripts/`

### TC-352-01: `embed-full-database.py` removed
**Objective:** Confirm the deprecated full-database embedding script no longer exists in `memory/scripts/`.  
**Steps:**
1. Check out the final branch/commit for issue #352.
2. Run: `ls nova-mind/memory/scripts/embed-full-database.py`  
**Expected:** File not found (exit code non-zero).  
**Pass Criteria:** `embed-full-database.py` is absent from `memory/scripts/`.

---

### TC-352-02: `embed-research.py` removed
**Objective:** Confirm the deprecated research embedding script is gone.  
**Steps:**
1. Run: `ls nova-mind/memory/scripts/embed-research.py`  
**Expected:** File not found.  
**Pass Criteria:** `embed-research.py` is absent from `memory/scripts/`.

---

### TC-352-03: `embed-memories.py` removed
**Objective:** Confirm the deprecated memories embedding script is gone.  
**Steps:**
1. Run: `ls nova-mind/memory/scripts/embed-memories.py`  
**Expected:** File not found.  
**Pass Criteria:** `embed-memories.py` is absent from `memory/scripts/`.

---

### TC-352-04: `embed-library.py` removed
**Objective:** Confirm the library embedding script (absorbed into memory-maintenance.py) is removed.  
**Steps:**
1. Run: `ls nova-mind/memory/scripts/embed-library.py`  
**Expected:** File not found.  
**Pass Criteria:** `embed-library.py` is absent from `memory/scripts/`.

---

### TC-352-05: `memory-maintenance.py` removed from `memory/scripts/`
**Objective:** The canonical script should now live in `memory/templates/`, not `memory/scripts/`.  
**Steps:**
1. Run: `ls nova-mind/memory/scripts/memory-maintenance.py`  
**Expected:** File not found.  
**Pass Criteria:** `memory-maintenance.py` is absent from `memory/scripts/`.

---

## Area 2 — Template Relocation

### TC-352-06: `memory/templates/` directory exists
**Objective:** Confirm the templates directory was created.  
**Steps:**
1. Run: `ls -d nova-mind/memory/templates/`  
**Expected:** Directory exists (exit code 0).  
**Pass Criteria:** `memory/templates/` is present.

---

### TC-352-07: `memory-maintenance.py` exists in `memory/templates/`
**Objective:** The canonical script lives in its new home.  
**Steps:**
1. Run: `ls nova-mind/memory/templates/memory-maintenance.py`  
**Expected:** File exists.  
**Pass Criteria:** `memory-maintenance.py` is present in `memory/templates/`.

---

### TC-352-08: Only `memory-maintenance.py` is in `memory/templates/` (no stale scripts)
**Objective:** The templates directory should not contain deprecated scripts or other content that belongs in `memory/scripts/`.  
**Steps:**
1. Run: `ls nova-mind/memory/templates/`  
2. Inspect the file list.  
**Expected:** Only `memory-maintenance.py` (and any legitimate template support files, e.g. a sample config) are present. No `embed-*.py` scripts.  
**Pass Criteria:** No deprecated individual embedding scripts appear in `memory/templates/`.

---

## Area 3 — Installer: Template Logic (Install-If-Not-Exists)

### TC-352-09: Fresh install copies `memory-maintenance.py` to `$WORKSPACE/scripts/`
**Objective:** When target does not exist, the installer deploys the template.  
**Setup:** Remove `$WORKSPACE/scripts/memory-maintenance.py` if present.  
**Steps:**
1. Run `bash agent-install.sh` against the updated repo.
2. Check: `ls $WORKSPACE/scripts/memory-maintenance.py`  
**Expected:** File exists at deploy target.  
**Pass Criteria:** `memory-maintenance.py` is present at `$WORKSPACE/scripts/` after a fresh install.

---

### TC-352-10: Fresh install copies `memory-maintenance.py` to `$HOME/.openclaw/scripts/`
**Objective:** Second deploy target also receives the template on fresh install.  
**Setup:** Remove `$HOME/.openclaw/scripts/memory-maintenance.py` if present.  
**Steps:**
1. Run `bash agent-install.sh`.
2. Check: `ls $HOME/.openclaw/scripts/memory-maintenance.py`  
**Expected:** File exists.  
**Pass Criteria:** Template deployed to `$HOME/.openclaw/scripts/`.

---

### TC-352-11: Existing `memory-maintenance.py` is NOT overwritten (clobber protection)
**Objective:** The install-if-not-exists logic must preserve customized deployed versions.  
**Setup:**
1. Place a customized `memory-maintenance.py` at `$WORKSPACE/scripts/memory-maintenance.py` (e.g. add a comment `# CUSTOMIZED` at the top).
2. Record its checksum: `sha256sum $WORKSPACE/scripts/memory-maintenance.py`  
**Steps:**
1. Run `bash agent-install.sh`.
2. Check checksum: `sha256sum $WORKSPACE/scripts/memory-maintenance.py`  
**Expected:** Checksum is unchanged. The customized version is preserved.  
**Pass Criteria:** Installer does NOT overwrite an existing `memory-maintenance.py` at the deploy target.  
**Note:** This is the critical regression guard — the whole point of moving to `templates/` is to avoid clobber on reinstall.

---

### TC-352-12: `--force` install overwrites existing `memory-maintenance.py`
**Objective:** Verify that force mode still updates the template when explicitly requested.  
**Setup:** Same as TC-352-11 — place a customized version at deploy target.  
**Steps:**
1. Run `bash agent-install.sh --force` (or equivalent FORCE_INSTALL flag).
2. Check that the deployed file matches the template source.  
**Expected:** Template version is now deployed, overwriting the customized one.  
**Pass Criteria:** `--force` bypasses the install-if-not-exists gate.  
**Note:** Force behavior should be documented in the installer output.

---

### TC-352-13: Template installed with executable bit set
**Objective:** Deployed `memory-maintenance.py` must be executable.  
**Steps:**
1. Run `bash agent-install.sh` on a fresh target.
2. Run: `[ -x $WORKSPACE/scripts/memory-maintenance.py ] && echo PASS`  
**Expected:** `PASS`.  
**Pass Criteria:** File is executable after install.

---

## Area 4 — Installer: Cleanup Block (Stale Script Removal)

### TC-352-14: `embed-full-database.py` removed from `$WORKSPACE/scripts/` by cleanup
**Objective:** Installer removes stale scripts from active deploy targets.  
**Setup:** Place a copy of `embed-full-database.py` at `$WORKSPACE/scripts/embed-full-database.py` (simulating a pre-existing installation).  
**Steps:**
1. Run `bash agent-install.sh`.
2. Check: `ls $WORKSPACE/scripts/embed-full-database.py`  
**Expected:** File not found.  
**Pass Criteria:** Stale script removed from `$WORKSPACE/scripts/`.

---

### TC-352-15: `embed-full-database.py` removed from `$HOME/.openclaw/scripts/` by cleanup
**Objective:** Cleanup applies to the second deploy target too.  
**Setup:** Same stale file placed at `$HOME/.openclaw/scripts/embed-full-database.py`.  
**Steps:**
1. Run `bash agent-install.sh`.
2. Check: `ls $HOME/.openclaw/scripts/embed-full-database.py`  
**Expected:** File not found.  
**Pass Criteria:** Stale script removed from `$HOME/.openclaw/scripts/`.

---

### TC-352-16: `embed-memories.py` removed from both deploy targets by cleanup
**Objective:** All four deprecated scripts are cleaned up.  
**Setup:** Place stale `embed-memories.py` at both deploy targets.  
**Steps:**
1. Run `bash agent-install.sh`.
2. Check both targets.  
**Expected:** Neither `$WORKSPACE/scripts/embed-memories.py` nor `$HOME/.openclaw/scripts/embed-memories.py` exists.  
**Pass Criteria:** Both removed.

---

### TC-352-17: `embed-library.py` removed from both deploy targets by cleanup
**Objective:** Library script cleaned up.  
**Setup:** Place stale `embed-library.py` at both deploy targets.  
**Steps:**
1. Run `bash agent-install.sh`.
2. Check both targets.  
**Expected:** Both removed.  
**Pass Criteria:** Neither deploy target contains `embed-library.py`.

---

### TC-352-18: `embed-research.py` removed from both deploy targets by cleanup
**Objective:** Research script cleaned up.  
**Setup:** Place stale `embed-research.py` at both deploy targets.  
**Steps:**
1. Run `bash agent-install.sh`.
2. Check both targets.  
**Expected:** Both removed.  
**Pass Criteria:** Neither deploy target contains `embed-research.py`.

---

### TC-352-19: Legitimate scripts are NOT removed by cleanup block
**Objective:** Cleanup is targeted — it must not remove scripts that should stay.  
**Steps:**
1. After install, check that `memory-maintenance.py`, `extract_memories.py`, `proactive-recall.py` and other legitimate scripts remain at deploy targets.  
**Expected:** All non-deprecated scripts still present.  
**Pass Criteria:** Cleanup block only removes the 4 explicitly listed deprecated scripts.  
**Note:** `embed-blog-posts.py` removal is handled by nova-workspace#23, not by the nova-mind installer. The nova-mind cleanup block should NOT target it — doing so would create a cross-repo dependency. Verify that `embed-blog-posts.py` is absent from the nova-mind cleanup list.

---

### TC-352-20: Cleanup is idempotent (scripts already absent — no error)
**Objective:** Running installer when stale scripts are already absent should not fail.  
**Setup:** Ensure no stale scripts exist at deploy targets.  
**Steps:**
1. Run `bash agent-install.sh` twice.  
**Expected:** Second run exits cleanly with no error about missing files.  
**Pass Criteria:** Exit code 0 on idempotent run.

---

## Area 5 — Template `memory-maintenance.py` Content

### TC-352-21: Model is `snowflake-arctic-embed2` (not OpenAI)
**Objective:** Template uses the correct local Ollama model.  
**Steps:**
1. Open `nova-mind/memory/templates/memory-maintenance.py`.
2. Search for the model name in `load_embedding_config` default and any hardcoded references.  
**Expected:** Model is `snowflake-arctic-embed2` (1024 dims). No references to `text-embedding-3-small` or OpenAI embedding APIs.  
**Pass Criteria:** Correct model throughout.

---

### TC-352-22: Template passes Python syntax check
**Objective:** No syntax errors introduced during relocation/edit.  
**Steps:**
1. Run: `python3 -m py_compile nova-mind/memory/templates/memory-maintenance.py && echo PASS`  
**Expected:** `PASS` (no output, exit code 0).  
**Pass Criteria:** Clean compile.

---

### TC-352-23: Template `--help` flag works without error
**Objective:** argparse interface is intact.  
**Steps:**
1. Run: `python3 nova-mind/memory/templates/memory-maintenance.py --help`  
**Expected:** Help text printed, exit code 0.  
**Pass Criteria:** No exception, clean help output.

---

### TC-352-24: TABLE_EMBED_SPECS covers all 14 core tables
**Objective:** No coverage regressions in the template's embedding scope.  
**Steps:**
1. Inspect `TABLE_EMBED_SPECS` in the template.
2. Verify all of the following source_types are present:
   - `entity_fact`, `entity`, `task`, `project`, `agent`
   - `lesson`, `event`, `media_consumed`, `vocabulary`, `library`
   - `journal_entry`, `music_work`, `workflow_run`, `income_source`  
**Expected:** All 14 source_types found.  
**Pass Criteria:** Complete coverage — no entries dropped during move.

---

### TC-352-25: `library` source_type query references `library_works` table (not deprecated `library`)
**Objective:** The post-#259 rename is correct in the template.  
**Steps:**
1. Find the `"library"` entry in `TABLE_EMBED_SPECS`.
2. Verify the SQL references `FROM library_works`.  
**Expected:** Query uses `library_works`.  
**Pass Criteria:** No reference to deprecated table name.

---

### TC-352-26: `lesson` source_type query uses `.lesson` column (not `.content`)
**Objective:** The post-#245 fix is preserved in the template.  
**Steps:**
1. Find the `"lesson"` entry in `TABLE_EMBED_SPECS`.
2. Verify the SQL selects `lesson AS text` (not `content AS text`).  
**Expected:** `lesson` column referenced.  
**Pass Criteria:** Correct column name.

---

## Area 6 — No Embedding Regressions

### TC-352-27: All tables from deprecated `embed-full-database.py` covered in template TABLE_EMBED_SPECS
**Objective:** Migration to unified script is lossless for table coverage.  
**Steps:**
1. List all `source_type` keys from the deprecated `embed-full-database.py` `TABLES_TO_EMBED` dict (before deletion, from git history or the task description).
2. Verify every one of those keys appears in the template's `TABLE_EMBED_SPECS`.  
**Expected:** 100% overlap — no table dropped.  
**Pass Criteria:** No regressions in covered source types.

---

### TC-352-28: Library embedding logic from `embed-library.py` is covered in template
**Objective:** The richer library query (title + authors + tags + quotes) is preserved.  
**Steps:**
1. Find the `"library"` spec in template `TABLE_EMBED_SPECS`.
2. Verify the SQL joins `library_work_authors`, `library_authors`, `library_work_tags`, `library_tags` for rich text.
   - OR verify the template's library query is at least as rich as what `embed-library.py` produced.  
**Expected:** Library embedding produces comparable rich text (title + authors + work_type + summary + topics) in the template.  
**Pass Criteria:** No regression in library embedding quality vs. the old dedicated script.  
**Note:** The template version uses a simpler query than embed-library.py. If the template intentionally uses a simplified query, this test case should document that decision and verify it is intentional (see nova-workspace#23 TC-23 for the enriched version).

---

### TC-352-29: Research embedding phases are present in template (not just table phases)
**Objective:** `embed-research.py` handled research-specific content; verify it's covered in memory-maintenance.py phases.  
**Steps:**
1. Search the template for research-related phases or TABLE_EMBED_SPECS entries (`research_*` tables).
2. Confirm coverage for any `research_*` tables that existed in nova-mind schema.  
**Expected:** Research content is embedded either via TABLE_EMBED_SPECS entries or a dedicated phase.  
**Pass Criteria:** No research content silently dropped.

---

## Area 7 — Installer Audit

### TC-352-30: Installer references `memory/templates/` for template install block
**Objective:** The new block in `agent-install.sh` reads from the correct source directory.  
**Steps:**
1. Open `agent-install.sh` and locate the new templates install block (added for this issue).
2. Verify the source path is `$SCRIPT_DIR/memory/templates` (or equivalent).  
**Expected:** Templates block references `memory/templates/`, not `memory/scripts/`.  
**Pass Criteria:** Correct source path.

---

### TC-352-31: Installer cleanup block lists exactly the 4 deprecated scripts (no overreach)
**Objective:** Cleanup list is specific — not a wildcard that could delete legitimate scripts.  
**Steps:**
1. Locate the cleanup block in `agent-install.sh`.
2. Verify it explicitly lists: `embed-full-database.py`, `embed-research.py`, `embed-memories.py`, `embed-library.py`.
3. Verify no other scripts appear in the removal list unless intentional.  
**Expected:** Exactly the 4 deprecated scripts are targeted.  
**Pass Criteria:** Cleanup list matches spec.

---

### TC-352-32: Installer produces clear output for template install and cleanup steps
**Objective:** Operators can see what the installer did.  
**Steps:**
1. Run `bash agent-install.sh` with stale scripts present.
2. Capture stdout.  
**Expected:** Installer prints messages indicating:
   - Template files installed (or skipped because already present)
   - Stale scripts removed (listing which ones)  
**Pass Criteria:** Human-readable status messages for both new blocks.

---

## Summary

| Area | Test Cases | Count |
|------|-----------|-------|
| Script Removal | TC-352-01 to TC-352-05 | 5 |
| Template Relocation | TC-352-06 to TC-352-08 | 3 |
| Installer: Template Logic | TC-352-09 to TC-352-13 | 5 |
| Installer: Cleanup Block | TC-352-14 to TC-352-20 | 7 |
| Template Script Content | TC-352-21 to TC-352-26 | 6 |
| No Embedding Regressions | TC-352-27 to TC-352-29 | 3 |
| Installer Audit | TC-352-30 to TC-352-32 | 3 |
| **Total** | | **32** |

### Critical Test Cases
These are the highest-risk validations — prioritize if time is limited:
- **TC-352-11** (clobber protection) — the core correctness guarantee of the template approach
- **TC-352-21** (correct model) — prevents dimension mismatch failures
- **TC-352-27** (coverage regression) — ensures nothing is silently dropped
- **TC-352-14/15** (cleanup removes stale scripts) — prevents old broken scripts from running
