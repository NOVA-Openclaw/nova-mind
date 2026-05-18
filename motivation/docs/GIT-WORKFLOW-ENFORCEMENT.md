# Git Workflow Enforcement (Issue #26)

## Overview

The NOVA Motivation System implements strict git workflow enforcement to ensure code quality and proper separation of duties between agents.

## Key Principles

1. **PR-Only for Main/Master**: All changes to `main` and `master` branches must go through Pull Requests
2. **Separation of Duties**: Different agents have different responsibilities
3. **Agent Identification**: All git operations are tracked by `CLAWDBOT_AGENT_ID`

## Agents and Permissions

### Coder (claude-code)
- ✅ Push to feature branches
- ✅ Create Pull Requests
- ❌ Push directly to main/master
- ❌ Merge Pull Requests

**Role**: Creates features, fixes bugs, writes code

### Gidget (git-agent)
- ✅ Push to feature branches
- ✅ Review Pull Requests
- ✅ Merge Pull Requests
- ❌ Push directly to main/master

**Role**: Reviews code, manages merges, ensures quality

### Human Users
- ✅ Push to feature branches
- ✅ Create and merge Pull Requests
- ❌ Push directly to main/master (by convention)

**Role**: Oversee development, make final decisions

### NOVA Main (no agent ID)
- ❌ All git operations blocked
- Must delegate to appropriate agent

**Role**: Coordinate and delegate, not execute

## Implementation

### 1. Pre-Push Hook (`.git/hooks/pre-push`)

Enforces push permissions:

```bash
# Location: .git/hooks/pre-push (installed via agent-install.sh)
# Template: hooks/pre-push

# Rules enforced:
1. Block ALL direct pushes to main/master (all agents + humans)
2. Check CLAWDBOT_AGENT_ID for feature branch pushes
3. Allow claude-code and git-agent to push feature branches
4. Allow human users (e.g., newhart) to push feature branches
5. Block pushes when no agent ID is set (NOVA main)
```

### 2. Shell Alias for `gh pr merge` (`scripts/shell-aliases.sh`)

Intercepts PR merge commands:

```bash
# Checks CLAWDBOT_AGENT_ID before allowing merge
# Only git-agent (Gidget) can execute merges
# Provides helpful guidance to other agents
```

## Typical Workflow

### For Coder (claude-code)

```bash
# 1. Create feature branch
git checkout -b feature/new-feature

# 2. Make changes
echo "new code" > file.txt
git add file.txt
git commit -m "Add new feature"

# 3. Push to remote (✅ Allowed)
git push origin feature/new-feature

# 4. Create PR (✅ Allowed)
gh pr create --title "Add new feature" --body "Description"

# 5. Try to merge (❌ Blocked)
gh pr merge 123
# Error: Only Gidget (git-agent) can merge PRs
```

### For Gidget (git-agent)

```bash
# 1. Review PR
gh pr view 123

# 2. Check status
gh pr checks 123

# 3. Merge PR (✅ Allowed)
gh pr merge 123 --squash --delete-branch

# 4. Clean up
git fetch --prune
```

## Error Messages

### Attempting to push to main
```
❌ Direct push to main blocked!

The NOVA workflow requires all changes to main/master go through PRs.

To contribute:
  1. Push to a feature branch (git push origin your-branch-name)
  2. Create a PR (gh pr create)
  3. Have Gidget (git-agent) merge it
```

### NOVA main trying to push
```
❌ NOVA GIT BLOCKED

No CLAWDBOT_AGENT_ID detected. Direct git operations require an agent identity.

Authorized agents:
  - claude-code (Coder) - Can push feature branches and create PRs
  - git-agent (Gidget) - Can push feature branches and merge PRs
```

### Coder trying to merge
```
❌ Only Gidget (git-agent) can merge PRs

The NOVA workflow enforces separation of duties:
  - Coder (claude-code) creates branches, commits, and opens PRs
  - Gidget (git-agent) reviews and merges approved PRs

As Coder, your role is to create and prepare PRs, not merge them.
To get this merged:
  1. Ensure tests pass and PR is ready
  2. Ask Gidget to review and merge: 'Gidget, please merge this PR'
```

## Installation

The git workflow enforcement is installed automatically by `agent-install.sh`:

```bash
./agent-install.sh
```

This installs:
1. Pre-push hook from `hooks/pre-push` to `.git/hooks/pre-push`
2. Shell aliases from `scripts/shell-aliases.sh` to `~/.local/share/nova/shell-aliases.sh`

## Testing

Run the comprehensive test suite:

```bash
./tests/test-issue-26.sh
```

Test cases cover:
- ✅ TC-26-01: Coder can push feature branches
- ✅ TC-26-02: Gidget can push feature branches
- ✅ TC-26-03: NOVA main blocked from pushing
- ✅ TC-26-04: Newhart can push
- ✅ TC-26-05: Block push to main (Coder)
- ✅ TC-26-06: Block push to main (Gidget)
- ✅ TC-26-07: Block push to master
- ✅ TC-26-08: Gidget can merge PRs
- ✅ TC-26-09: Coder blocked from merging PRs
- ✅ TC-26-10: NOVA main blocked from merging PRs

## Manual Installation

If not using `agent-install.sh`:

```bash
# Install pre-push hook
cp hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push

# Install shell aliases
mkdir -p ~/.local/share/nova
cp scripts/shell-aliases.sh ~/.local/share/nova/shell-aliases.sh

# Add to shell RC
echo 'source ~/.local/share/nova/shell-aliases.sh' >> ~/.bashrc
source ~/.bashrc
```

## Bypassing (Emergency Only)

In emergencies, hooks can be bypassed:

```bash
# Bypass pre-push hook (NOT RECOMMENDED)
git push --no-verify

# Use real gh command (NOT RECOMMENDED)
command gh pr merge 123
```

⚠️ **Warning**: Bypassing enforcement breaks the NOVA workflow and should only be done in emergencies with proper justification.

## Troubleshooting

### Hook not executing
```bash
# Check if hook is installed
ls -la .git/hooks/pre-push

# Check if executable
chmod +x .git/hooks/pre-push
```

### Alias not working
```bash
# Check if function is loaded
type gh

# Should show: gh is a function

# If not, source aliases
source ~/.local/share/nova/shell-aliases.sh
```

### Agent ID not detected
```bash
# Check environment variable
echo $CLAWDBOT_AGENT_ID

# Set manually for testing
export CLAWDBOT_AGENT_ID=claude-code
```

## Design Rationale

### Why separate Coder and Gidget?

1. **Code Quality**: Having a second agent review changes catches errors
2. **Security**: Limits damage from compromised or misbehaving agent
3. **Audit Trail**: Clear separation of who created vs. who approved
4. **Workflow Discipline**: Forces proper PR workflow even for agents

### Why block direct pushes to main?

1. **Consistency**: Everyone follows the same workflow
2. **Review Required**: All changes get reviewed (even agent changes)
3. **CI/CD Integration**: PRs trigger tests and checks
4. **Rollback Safety**: Easy to revert merged PRs vs. direct commits

### Why use agent IDs?

1. **Accountability**: Track which agent did what
2. **Permission Control**: Enforce role-based access
3. **Debugging**: Know which agent to investigate when issues occur
4. **Metrics**: Measure agent performance and activity

## Future Enhancements

Potential improvements:

- [ ] Commit message format enforcement
- [ ] Branch naming conventions
- [ ] Required status checks before merge
- [ ] Auto-assignment of reviewers based on file changes
- [ ] Integration with linear/issue tracker for automatic linking
- [ ] PR template enforcement
- [ ] Size limits on PRs (too large = split into smaller PRs)

## References

- Issue: https://github.com/NOVA-Openclaw/nova-motivation/issues/26
- Test Cases: `tests/TEST-CASES-ISSUE-26.md`
- Hook Template: `hooks/pre-push`
- Shell Aliases: `scripts/shell-aliases.sh`
- Installation Script: `agent-install.sh`
