# Issue #83 Implementation Summary

**Date:** 2026-02-13 23:57 UTC  
**Issue:** Install shell-aliases.sh and .bash_env for exec environment setup  
**Status:** ✅ Complete (ready for testing)

## Changes Made

### 1. New Files Added to Repository

#### `dotfiles/shell-aliases.sh`
- **Source:** Copied from `~/.local/share/nova/shell-aliases.sh`
- **Purpose:** SE workflow integration and git workflow enforcement
- **Key features:**
  - `gh()` wrapper function for PR merge permission enforcement
  - Auto-triggers SE workflow on issue creation
  - Enforces separation of duties (Coder vs Gidget)

#### `dotfiles/bash_env`
- **Purpose:** Bash environment initialization file
- **Content:** Sources `~/.local/share/nova/shell-aliases.sh`
- **Used via:** `BASH_ENV` environment variable for non-interactive shells

### 2. Updated agent-install.sh

Added new **Part 7: Shell Environment Setup** section that:

#### A. Installs shell-aliases.sh
```bash
~/.local/share/nova/shell-aliases.sh
```
- Creates `~/.local/share/nova/` directory if needed
- Copies from repo's `dotfiles/shell-aliases.sh`
- Sets executable permissions
- **Idempotent:** Checks if file exists before copying (unless `--force`)

#### B. Updates ~/.bash_env Additively
- **Creates** file if it doesn't exist (copies from `dotfiles/bash_env`)
- **Appends** content if file exists but doesn't have the correct source line
- **Preserves** existing content (additive, not destructive)
- **Idempotent:** Uses `grep -qF '~/.local/share/nova/shell-aliases.sh'` to check for exact path
  - Handles Test Case 5: Invalid path scenario (won't match incorrect paths)

#### C. Patches OpenClaw Config (env.vars.BASH_ENV)
- **Config file:** `~/.openclaw/config.yaml`
- **Setting added:** `env.vars.BASH_ENV: "~/.bash_env"`
- **Strategy:**
  1. Prefers `yq` if available for proper YAML merging
  2. Falls back to `sed` for manual insertion
  3. Handles three scenarios:
     - `env.vars` exists → adds BASH_ENV under it
     - `env` exists but no `vars` → adds vars section
     - No `env` section → appends entire structure
- **Idempotent:** Checks if `BASH_ENV` already exists via `grep`
- **Merge-safe:** Does not overwrite other `env.vars` entries

### 3. Updated Installation Summary
Modified the final output to include:
```
• shell-aliases.sh → ~/.local/share/nova/shell-aliases.sh
• ~/.bash_env configured
```

## Implementation Notes

### Idempotency Guarantees
All operations are safe to run multiple times:

1. **shell-aliases.sh installation**
   - Checks file existence before copying
   - Respects `--force` flag for reinstalls

2. **~/.bash_env updates**
   - Uses exact path matching: `grep -qF '~/.local/share/nova/shell-aliases.sh'`
   - Won't duplicate entries on re-run
   - Will fix invalid paths (Test Case 5)
   - Preserves all existing content

3. **OpenClaw config patching**
   - Checks for existing `BASH_ENV` setting
   - Merges into existing structure
   - Won't duplicate or overwrite other env.vars

### Test Case Coverage

| Test Case | Description | Implementation |
|-----------|-------------|----------------|
| TC1 | Fresh install | ✓ All files created, config patched |
| TC2 | Re-install | ✓ Idempotent checks prevent duplication |
| TC3 | shell-aliases exists, bash_env doesn't | ✓ Creates bash_env, updates config |
| TC4 | bash_env exists, shell-aliases doesn't | ✓ Installs shell-aliases, appends to bash_env |
| TC5 | Invalid path in bash_env | ✓ grep -qF checks exact path, appends correct version |

### Error Handling
- Missing source files generate `${WARNING}` messages but don't block installation
- Config file missing generates warning with manual instruction
- All file operations are atomic (copy, then verify)

## File Structure
```
nova-cognition/
├── dotfiles/
│   ├── bash_env              # New: Bash environment setup
│   └── shell-aliases.sh      # New: SE workflow shell functions
└── agent-install.sh          # Modified: Added Part 7 (Shell Environment Setup)
```

## Next Steps (Step 8 - Not Done Yet)
- [ ] Commit changes to branch
- [ ] Push to remote
- [ ] Create PR for review

## Verification Commands

Test the implementation:
```bash
# Run installer
cd ~/workspace/nova-cognition
./agent-install.sh

# Verify files installed
ls -la ~/.local/share/nova/shell-aliases.sh
cat ~/.bash_env

# Check OpenClaw config
grep -A 3 "env:" ~/.openclaw/config.yaml

# Test gh wrapper function
export BASH_ENV=~/.bash_env
bash -c "type gh"
```
