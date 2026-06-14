# Test Cases: Issues #266, #315, #316
## `nova-mind/agent-install.sh` — Batch Bug Fix

**File under test:** `nova-mind/agent-install.sh`
**Related issues:** #266 (NOVA_DIR unbound), #315 (cp -r nested dirs), #316 (plugin config overwrite)
**Test case count:** 24

---

## Setup / Teardown Helpers

All tests that exercise `agent-install.sh` should:

1. **Backup** any existing `~/.openclaw/openclaw.json` before the test and restore it after.
2. **Backup** any existing `~/.local/share/nova/` directory and restore after.
3. Use a temporary directory tree as `$HOME` or a stub `OPENCLAW_DIR` via env overrides where possible to avoid clobbering real state.
4. Confirm `jq` is present; skip plugin-config tests with a `SKIP: jq not found` notice if absent.

---

## Issue #266 — `NOVA_DIR` Unbound Variable

### Background

`NOVA_DIR` is referenced on lines around 2042+ (in the shell environment setup block) but was
never defined in the path constants block. This causes an unbound variable error when
`set -u` is active, or silently produces a wrong path (empty/garbage) when `set -u` is not active.

The fix defines `NOVA_DIR="$HOME/.local/share/nova"` in the path constants block (~line 68)
alongside other derived path variables.

---

### TC-266-01 — Happy Path: Variable Defined Before First Use

**Goal:** Confirm `NOVA_DIR` is defined in the constants block and is accessible before any
code that uses it.

**Steps:**
1. Run `bash -n agent-install.sh` (syntax check).
2. Run `bash -c 'set -eu; source agent-install.sh --dry-run 2>&1 | head -5'` (or equivalent
   invocation that sources just the constants section).
3. Alternatively, `grep -n 'NOVA_DIR=' agent-install.sh` and confirm the definition appears
   at a line number **before** any line that reads `$NOVA_DIR`.

**Expected:**
- `grep` returns exactly one definition line (the fix) in the constants block (lines ~65–75).
- That definition line number is lower than any usage line (e.g. 2042).
- No `unbound variable` error on a `set -eu` invocation.

**Pass criteria:** Definition exists; definition line < all usage lines.

---

### TC-266-02 — Correct Expansion Value

**Goal:** Confirm `NOVA_DIR` expands to `$HOME/.local/share/nova`, not an empty string or
an unrelated path.

**Steps:**
1. In a test shell: `source agent-install.sh --dry-run` (or extract just the constants block
   and source it).
2. `echo "$NOVA_DIR"`.

**Expected:** Output is `<actual_home>/.local/share/nova` (e.g. `/home/nova/.local/share/nova`).

**Pass criteria:** Exact path match.

---

### TC-266-03 — `mkdir -p "$NOVA_DIR"` Succeeds

**Goal:** Verify the directory-creation call on line ~2048 (`mkdir -p "$NOVA_DIR"`) works
without error after the fix.

**Steps:**
1. Remove `~/.local/share/nova` if it exists.
2. Run the install script (or the relevant subsection) in a sandboxed `$HOME`.
3. Verify `~/.local/share/nova` now exists.

**Expected:**
- Exit code 0 from `mkdir -p`.
- Directory `~/.local/share/nova` is created.

**Pass criteria:** Directory exists after run; no `unbound variable` or `mkdir` error in output.

---

### TC-266-04 — `SHELL_ALIASES_TARGET` Resolves to Correct Path

**Goal:** Verify `SHELL_ALIASES_TARGET="$NOVA_DIR/shell-aliases.sh"` expands correctly,
meaning `shell-aliases.sh` is copied to `~/.local/share/nova/shell-aliases.sh`.

**Steps:**
1. Ensure `motivation/scripts/shell-aliases.sh` exists in the source tree.
2. Run the install script in a sandboxed environment.
3. Check for the file at `~/.local/share/nova/shell-aliases.sh`.

**Expected:**
- File `~/.local/share/nova/shell-aliases.sh` exists after install.
- File is executable (`chmod +x` was applied).

**Pass criteria:** File exists at the correct path and is executable.

---

### TC-266-05 — `~/.bash_env` References Correct Alias Path

**Goal:** Confirm `~/.bash_env` sources the alias file from `~/.local/share/nova/shell-aliases.sh`
(not a stale or empty path).

**Steps:**
1. Remove `~/.bash_env` so the script creates a fresh one.
2. Run the install script.
3. `grep 'shell-aliases.sh' ~/.bash_env`.

**Expected:** Output contains `~/.local/share/nova/shell-aliases.sh` or the absolute equivalent.

**Pass criteria:** Grep finds the correct path.

---

### TC-266-06 — Edge: `$HOME` Contains Spaces

**Goal:** Confirm the path definition and subsequent mkdir/cp still work when `$HOME`
contains spaces (e.g. `/home/test user/`).

**Steps:**
1. Set `HOME="/tmp/test user dir"` in a subshell.
2. Source the constants block.
3. Assert `NOVA_DIR` equals `/tmp/test user dir/.local/share/nova` (quoted correctly).
4. Run `mkdir -p "$NOVA_DIR"` and confirm success.

**Expected:** No word-splitting errors; directory created at correct path.

**Pass criteria:** Directory exists; no shell errors.

---

### TC-266-07 — Error Condition: `NOVA_DIR` Must Not Be Empty

**Goal:** Guard against a regression where the fix is removed or the variable is accidentally
unset later in the script before use.

**Steps:**
1. After sourcing the constants block, assert `[ -n "$NOVA_DIR" ]`.

**Expected:** Assertion passes (variable is non-empty).

**Pass criteria:** Non-empty value; test exits 0.

---

## Issue #315 — `cp -r` Nested Directory on Re-Install

### Background

When `install_metacognition_plugin` is called and `$plugin_target/src/` already exists from a
prior install, `cp -r "$plugin_source/src" "$plugin_target/src"` does not replace the target
directory — it creates `$plugin_target/src/src/` (nested). The fix adds
`rm -rf "$plugin_target/$f"` before the `cp -r` for directory entries only.

---

### TC-315-01 — Happy Path: Fresh Install (Target Does Not Exist)

**Goal:** Baseline — verify first-time install works correctly without a pre-existing target.

**Setup:**
1. Create a mock `$plugin_source/` with: `src/index.ts`, `package.json`, `tsconfig.json`,
   `openclaw.plugin.json`.
2. Ensure `$plugin_target/` does not exist.

**Steps:**
1. Call `install_metacognition_plugin "test-plugin" "$plugin_source" "$plugin_target"`
   (stub out npm/tsc steps).
2. List `$plugin_target/`.

**Expected:**
- `$plugin_target/src/index.ts` exists.
- `$plugin_target/package.json` exists.
- **No** `$plugin_target/src/src/` subdirectory.

**Pass criteria:** Correct flat layout; no nesting.

---

### TC-315-02 — Happy Path: Re-Install Replaces `src/` Correctly

**Goal:** Core regression test — verify a re-install replaces the existing `src/` directory
rather than nesting it.

**Setup:**
1. First install creates `$plugin_target/src/old-file.ts`.
2. New source has `$plugin_source/src/new-file.ts` but **not** `old-file.ts`.

**Steps:**
1. Run `install_metacognition_plugin` a second time.
2. List `$plugin_target/src/`.

**Expected:**
- `$plugin_target/src/new-file.ts` exists.
- `$plugin_target/src/old-file.ts` **does NOT** exist (old file removed by `rm -rf`).
- **No** `$plugin_target/src/src/` nesting.

**Pass criteria:** New files present; old stale files absent; no nested dirs.

---

### TC-315-03 — Non-Directory Files Still Copy Correctly on Re-Install

**Goal:** Verify that the `rm -rf` guard is only applied to directory entries, and that
non-directory files (`package.json`, `tsconfig.json`, `openclaw.plugin.json`) are still
overwritten correctly.

**Setup:**
1. First install places stale `package.json` with `"version": "1.0.0"`.
2. New source has `package.json` with `"version": "2.0.0"`.

**Steps:**
1. Run `install_metacognition_plugin` a second time.
2. `cat "$plugin_target/package.json"`.

**Expected:**
- `"version": "2.0.0"` is present (new version replaced old).
- No error about `package.json` being a directory.

**Pass criteria:** Correct version in target; exit 0.

---

### TC-315-04 — Only Listed Files Are Copied (Allowlist Respected)

**Goal:** Verify the copy loop only processes `package.json`, `openclaw.plugin.json`,
`tsconfig.json`, and `src` — not arbitrary content in the source directory.

**Setup:**
1. Add an extra file `$plugin_source/secret.key` that is NOT in the allowlist.

**Steps:**
1. Run `install_metacognition_plugin`.
2. Check whether `$plugin_target/secret.key` exists.

**Expected:** `secret.key` does NOT appear in `$plugin_target/`.

**Pass criteria:** Extra file absent from target.

---

### TC-315-05 — Source `src/` Missing (Graceful Skip)

**Goal:** Verify that when `src/` does not exist in the source, the directory-removal branch
is never reached and no error occurs.

**Setup:**
1. `$plugin_source/` contains only `package.json` (no `src/`).

**Steps:**
1. Run `install_metacognition_plugin`.

**Expected:**
- `$plugin_target/package.json` exists.
- No `$plugin_target/src/` directory created.
- Exit 0; no error about missing `src`.

**Pass criteria:** No error; only present files copied.

---

### TC-315-06 — Deep `src/` Subtree Fully Replaced

**Goal:** Confirm `rm -rf` removes the full old subtree, not just the top-level dir.

**Setup:**
1. First install places `$plugin_target/src/components/legacy/old.ts`.
2. New source `src/` has `src/index.ts` only.

**Steps:**
1. Run `install_metacognition_plugin` a second time.
2. Check for `$plugin_target/src/components/`.

**Expected:**
- `$plugin_target/src/components/` does NOT exist.
- `$plugin_target/src/index.ts` exists.

**Pass criteria:** Old deep subtree fully removed; new subtree correct.

---

### TC-315-07 — Source Not Found (Plugin Skipped Gracefully)

**Goal:** When `$plugin_source` does not exist, the function returns 0 without touching
`$plugin_target`.

**Steps:**
1. Set `plugin_source="/nonexistent/path"`.
2. Call `install_metacognition_plugin "test-plugin" "$plugin_source" "$plugin_target"`.
3. Assert exit code is 0 and `$plugin_target` was not created.

**Expected:** Info message printed; no error; `$plugin_target` absent.

**Pass criteria:** Exit 0; no target directory created.

---

## Issue #316 — Plugin Config Overwrites Existing `llm` Section

### Background

The jq expression in `install_metacognition_plugin` (lines 1632-1642) assigns a hardcoded
object to `.plugins.entries[$name]`, completely replacing any existing config under that key
(including a user-configured `llm` section). The fix uses a merge pattern:

```
.plugins.entries[$name] = (.plugins.entries[$name] // {}) * { "enabled": true, "hooks": { ... } }
```

This preserves existing keys (like `llm`) while still setting/overriding `enabled` and `hooks`.

---

### TC-316-01 — Happy Path: Clean Install Creates Correct Plugin Entry

**Goal:** Verify a fresh install with no existing plugin entry creates the expected config
structure.

**Setup:**
1. `openclaw.json` has no `.plugins.entries["self-awareness"]` key (or the key is absent entirely).

**Steps:**
1. Run `install_metacognition_plugin "self-awareness" ...`.
2. `jq '.plugins.entries["self-awareness"]' ~/.openclaw/openclaw.json`.

**Expected:**
```json
{
  "enabled": true,
  "hooks": {
    "allowConversationAccess": true
  }
}
```

**Pass criteria:** JSON matches expected shape; no extra/missing keys.

---

### TC-316-02 — Re-Install Preserves Existing `llm` Config

**Goal:** Core regression test — a re-install must not destroy a user-configured `llm` section.

**Setup:**
1. `openclaw.json` already has:
   ```json
   {
     "plugins": {
       "entries": {
         "self-awareness": {
           "enabled": true,
           "hooks": { "allowConversationAccess": true },
           "llm": { "model": "anthropic/claude-opus-4-6", "temperature": 0.7 }
         }
       }
     }
   }
   ```

**Steps:**
1. Run `install_metacognition_plugin "self-awareness" ...`.
2. `jq '.plugins.entries["self-awareness"].llm' ~/.openclaw/openclaw.json`.

**Expected:**
```json
{ "model": "anthropic/claude-opus-4-6", "temperature": 0.7 }
```

**Pass criteria:** `llm` key intact with original values.

---

### TC-316-03 — Re-Install Updates `enabled` and `hooks` Even When `llm` Present

**Goal:** The merge must write `enabled=true` and `hooks` regardless of existing state, even
when the entry already has other keys.

**Setup:**
1. `openclaw.json` has the plugin entry with `"enabled": false` and `llm` config set.

**Steps:**
1. Run `install_metacognition_plugin "self-awareness" ...`.
2. `jq '.plugins.entries["self-awareness"] | {enabled, hooks}' ~/.openclaw/openclaw.json`.

**Expected:**
```json
{
  "enabled": true,
  "hooks": { "allowConversationAccess": true }
}
```

**Pass criteria:** `enabled` flipped to `true`; `hooks` correct; `llm` still present.

---

### TC-316-04 — Multiple Plugins Don't Cross-Contaminate

**Goal:** Installing `confidence-check` after `self-awareness` must not alter the
`self-awareness` entry (including its `llm` config).

**Setup:**
1. After installing `self-awareness` with an `llm` section, install `confidence-check`.

**Steps:**
1. `jq '.plugins.entries["self-awareness"].llm' openclaw.json` after both installs.

**Expected:** `self-awareness.llm` unchanged.

**Pass criteria:** `llm` values identical before and after second plugin install.

---

### TC-316-05 — `plugins.load.paths` Entry Is Added Without Duplicates

**Goal:** Verify that repeated installs don't accumulate duplicate entries in
`.plugins.load.paths`.

**Steps:**
1. Run `install_metacognition_plugin` twice for the same plugin.
2. `jq '.plugins.load.paths | map(select(. == $target)) | length' --arg target "$plugin_target" openclaw.json`.

**Expected:** Count is exactly `1`.

**Pass criteria:** Path appears exactly once in the array.

---

### TC-316-06 — Edge: Existing Entry Has Unknown Extra Keys (Preserved)

**Goal:** The merge pattern must preserve any arbitrary existing keys, not just `llm`.

**Setup:**
1. Pre-load the plugin entry with keys `llm`, `customSetting`, and `debugLevel`.

**Steps:**
1. Run `install_metacognition_plugin`.
2. `jq '.plugins.entries["self-awareness"] | keys' openclaw.json`.

**Expected:** Output includes `customSetting`, `debugLevel`, `enabled`, `hooks`, `llm` (all five).

**Pass criteria:** No existing key is lost.

---

### TC-316-07 — Edge: `jq` Not Available — Graceful Degradation

**Goal:** If `jq` is not installed, the config update block is skipped without crashing
the install.

**Setup:**
1. `PATH` manipulated so `jq` is not found.

**Steps:**
1. Run `install_metacognition_plugin`.

**Expected:**
- Plugin source files are still copied.
- Warning message indicates config update was skipped.
- Script exits 0.

**Pass criteria:** Exit 0; warning printed; no unhandled error.

---

### TC-316-08 — Edge: `openclaw.json` Does Not Exist

**Goal:** When `openclaw.json` is absent, the config block is skipped gracefully.

**Setup:**
1. Remove/rename `openclaw.json` so `[ -f "$OPENCLAW_CONFIG" ]` evaluates false.

**Steps:**
1. Run `install_metacognition_plugin`.

**Expected:**
- Plugin files copied successfully.
- No error about missing config file.
- Exit 0.

**Pass criteria:** Exit 0; install completes; no crash.

---

### TC-316-09 — Verify Config Atomicity (`.tmp` Swap)

**Goal:** The jq write uses a `.tmp` intermediary and `mv` to avoid partial writes. Confirm
the `.tmp` file is cleaned up after a successful update.

**Steps:**
1. Run `install_metacognition_plugin`.
2. `ls "$OPENCLAW_DIR/openclaw.json.tmp"` after run.

**Expected:** `.tmp` file does NOT exist (it was moved into place, not left behind).

**Pass criteria:** `.tmp` absent after successful install.

---

## Cross-Issue Integration Tests

### TC-INT-01 — Full Install Sequence: All Three Fixes Together

**Goal:** Run a complete install (or the shell-env + plugin sections) with all three fixes
applied, starting from a clean state.

**Steps:**
1. No `NOVA_DIR` directory; no `openclaw.json` plugin entries; no `$plugin_target/src/`.
2. Run `bash agent-install.sh` (stubbed to skip npm/tsc/db steps).
3. Assert:
   - `~/.local/share/nova/shell-aliases.sh` exists.
   - `$plugin_target/src/index.ts` exists (not nested).
   - `.plugins.entries["self-awareness"].enabled` is `true`.

**Pass criteria:** All three post-conditions met; exit 0; no error output.

---

### TC-INT-02 — Re-Install With All Pre-Existing State

**Goal:** Run install twice and verify idempotency across all three bug areas.

**Steps:**
1. After first successful install (TC-INT-01), set `FORCE_INSTALL=1`.
2. Add `llm` config to the plugin entry manually.
3. Run `bash agent-install.sh` again.
4. Assert:
   - `~/.local/share/nova/shell-aliases.sh` still correct (no double-copy error).
   - `$plugin_target/src/` correctly replaced (no nesting).
   - `llm` config preserved in `openclaw.json`.

**Pass criteria:** All three post-conditions met after second run.

---

## Summary

| Test ID       | Area   | Type        | Description                                      |
|---------------|--------|-------------|--------------------------------------------------|
| TC-266-01     | #266   | Happy Path  | NOVA_DIR defined before first use                |
| TC-266-02     | #266   | Happy Path  | Correct expansion value                          |
| TC-266-03     | #266   | Happy Path  | mkdir -p succeeds                                |
| TC-266-04     | #266   | Happy Path  | SHELL_ALIASES_TARGET resolves correctly          |
| TC-266-05     | #266   | Happy Path  | ~/.bash_env references correct alias path        |
| TC-266-06     | #266   | Edge        | HOME with spaces                                 |
| TC-266-07     | #266   | Error Guard | NOVA_DIR must not be empty                       |
| TC-315-01     | #315   | Happy Path  | Fresh install flat layout                        |
| TC-315-02     | #315   | Regression  | Re-install replaces src/ correctly               |
| TC-315-03     | #315   | Happy Path  | Non-directory files overwritten correctly        |
| TC-315-04     | #315   | Boundary    | Only allowlisted files copied                    |
| TC-315-05     | #315   | Edge        | Missing src/ handled gracefully                  |
| TC-315-06     | #315   | Edge        | Deep subtree fully replaced                      |
| TC-315-07     | #315   | Error       | Missing plugin source skipped gracefully         |
| TC-316-01     | #316   | Happy Path  | Clean install creates correct entry              |
| TC-316-02     | #316   | Regression  | Re-install preserves llm config                  |
| TC-316-03     | #316   | Happy Path  | enabled/hooks updated even with llm present      |
| TC-316-04     | #316   | Boundary    | Multiple plugins don't cross-contaminate         |
| TC-316-05     | #316   | Edge        | load.paths has no duplicates                     |
| TC-316-06     | #316   | Edge        | Unknown extra keys preserved on merge            |
| TC-316-07     | #316   | Error       | jq missing — graceful degradation                |
| TC-316-08     | #316   | Error       | openclaw.json missing — graceful skip            |
| TC-316-09     | #316   | Boundary    | Config written atomically (.tmp cleaned up)      |
| TC-INT-01     | All    | Integration | Full clean install with all three fixes          |
| TC-INT-02     | All    | Integration | Re-install idempotency across all bug areas      |

**Total: 25 test cases** (7 for #266, 7 for #315, 9 for #316, 2 integration)

**Coverage areas:**
- Variable definition ordering and shell `-u` safety
- Path resolution and quoting (including spaces in $HOME)
- Directory copy idempotency and nesting regression
- File allowlist enforcement
- jq merge semantics and key preservation
- Config atomicity via tmp-swap pattern
- Graceful degradation when optional tools (jq) or files are absent
- Full-stack integration and re-install idempotency
