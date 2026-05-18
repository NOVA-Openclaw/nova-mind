# Git Hooks for NOVA Motivation System

This directory contains git hooks that enforce the NOVA workflow.

## Installation

These hooks are automatically installed by the `agent-install.sh` script.

Manual installation:
```bash
cp hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

## Hooks

### pre-push

Enforces git workflow rules (Issue #26):

1. **Branch Protection**: Blocks all direct pushes to `main` and `master` branches
   - All changes to main/master must go through Pull Requests
   
2. **Agent Permissions**: Controls which agents can push
   - `claude-code` (Coder) - Can push to feature branches and create PRs
   - `git-agent` (Gidget) - Can push to feature branches and merge PRs
   - Human users (e.g., `newhart`) - Can push to feature branches
   - NOVA main (no agent ID) - Blocked from pushing
   
3. **Separation of Duties**:
   - Coder creates branches and opens PRs
   - Gidget reviews and merges PRs
   - No single agent can both create and merge changes

## Testing

Run the test suite to verify hook functionality:
```bash
./tests/test-issue-26.sh
```
