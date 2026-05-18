# GitHub Issue Wrapper Script

Wrapper for `gh issue create` that automatically triggers the Software Engineering (SE) workflow for streamlined issue management and automated test case generation.

## Purpose

The `gh-issue-create.sh` script enhances the standard GitHub issue creation process by:

1. **Creating GitHub issues** using the official `gh` CLI tool
2. **Auto-injecting SE workflow references** into issue descriptions
3. **Queuing issues** in the `coder_issue_queue` database table
4. **Notifying NOVA** via the `agent_chat` system to spawn Gemini for test case design

This automation enables seamless integration between issue creation and the SE workflow, ensuring that every issue automatically enters the development pipeline unless explicitly opted out.

## Installation & Setup

### Prerequisites

1. **GitHub CLI** - Install and authenticate with `gh auth login`
2. **PostgreSQL** - Access to the `nova_memory` database
3. **Database Tables** - Ensure these tables exist:
   - `coder_issue_queue`
   - `agent_chat`
   - `workflow_steps`
   - `workflows`

### Installation

1. **Copy the script** to your path:
   ```bash
   cp ~/clawd/scripts/gh-issue-create.sh /usr/local/bin/
   chmod +x /usr/local/bin/gh-issue-create.sh
   ```

2. **Create an alias** (optional but recommended):
   ```bash
   echo 'alias ghi="gh-issue-create.sh"' >> ~/.bashrc
   source ~/.bashrc
   ```

3. **Test the setup**:
   ```bash
   gh-issue-create.sh --help
   ```

## Non-Interactive Shell Configuration

### The Problem

The GitHub issue wrapper functionality relies on shell aliases defined in `~/.local/share/nova/shell-aliases.sh`. These aliases are typically loaded when `.bashrc` is sourced in interactive shell sessions. However, OpenClaw's `exec()` tool and other automation systems run non-interactive bash shells that **do not source `.bashrc`**, causing the SE workflow wrapper to be unavailable.

**Symptoms:**
- `gh` command works normally in interactive terminals
- `gh` command bypasses SE workflow when run through OpenClaw `exec()`
- No automatic workflow integration in automated scripts

### The Solution: BASH_ENV

Bash provides the `BASH_ENV` environment variable specifically for non-interactive shell initialization. When set, bash sources the specified file even in non-interactive mode.

### Installation Steps

1. **Create the environment file:**
   ```bash
   echo 'source ~/.local/share/nova/shell-aliases.sh' > ~/.bash_env
   ```

2. **Add BASH_ENV to your profile:**
   ```bash
   echo 'export BASH_ENV=~/.bash_env' >> ~/.profile
   ```

3. **Apply the changes:**
   ```bash
   source ~/.profile
   ```

### Verification

Test that the fix works in both interactive and non-interactive contexts:

#### Interactive Shell (should work before and after fix)
```bash
# This should show the wrapper function
type gh
```

#### Non-Interactive Shell (only works after BASH_ENV fix)
```bash
# Test via OpenClaw exec or direct non-interactive invocation
bash -c "type gh"
```

**Expected output after fix:**
```
gh is a function
gh () 
{ 
    gh-issue-create.sh "$@"
}
```

#### Test with OpenClaw
If using OpenClaw, test the exec tool:
```bash
# Should now trigger SE workflow
exec "gh issue create --title 'Test BASH_ENV fix' --body 'Testing non-interactive shell wrapper'"
```

### Files Involved

- **`~/.bash_env`** - New file that sources the aliases (created by fix)
- **`~/.profile`** - System profile that exports BASH_ENV (modified by fix)  
- **`~/.local/share/nova/shell-aliases.sh`** - Original aliases file (unchanged)

### How It Works

1. When bash starts in non-interactive mode, it checks the `BASH_ENV` variable
2. If set, bash sources that file before executing commands
3. Our `~/.bash_env` sources the Nova shell aliases
4. The `gh` wrapper function becomes available in non-interactive shells
5. SE workflow integration now works in automation contexts like OpenClaw

### Troubleshooting BASH_ENV

**Verify BASH_ENV is set:**
```bash
echo $BASH_ENV
# Should output: /home/username/.bash_env (or similar)
```

**Check if the env file exists and has correct content:**
```bash
cat ~/.bash_env
# Should output: source ~/.local/share/nova/shell-aliases.sh
```

**Test file sourcing manually:**
```bash
bash -c '. ~/.bash_env && type gh'
# Should show gh as a function
```

**Common issues:**
- Path in BASH_ENV uses `~` but should be absolute in some contexts
- File permissions on `~/.bash_env` prevent reading
- `~/.profile` changes not loaded (requires logout/login or source)

## Usage

### Basic Syntax

```bash
gh-issue-create.sh [--no-workflow] [gh issue create arguments...]
```

### Options

| Option | Aliases | Description |
|--------|---------|-------------|
| `--no-workflow` | `--no-se` | Skip SE workflow integration |

All other arguments are passed directly to `gh issue create`.

### Examples

#### Standard Issue with SE Workflow (Default)

```bash
gh-issue-create.sh --title "Fix user login validation" --body "Users can bypass email validation by submitting empty strings."
```

**What happens:**
1. Creates GitHub issue with title and body
2. Appends SE workflow reference to the issue body
3. Adds issue to `coder_issue_queue` with status `pending_tests`
4. Notifies NOVA to spawn Gemini for test case design

#### Issue Without SE Workflow

```bash
gh-issue-create.sh --no-workflow --title "Update README" --body "Add installation instructions for new contributors."
```

**What happens:**
1. Creates GitHub issue normally
2. **Skips** workflow integration
3. No database entries or NOVA notifications

#### Interactive Issue Creation

```bash
gh-issue-create.sh
```

Uses GitHub CLI's interactive prompts, then applies SE workflow integration.

#### With Labels and Assignees

```bash
gh-issue-create.sh --title "Performance optimization" --body "API response times > 2s" --label bug,performance --assignee @me
```

## What the Script Does

### 1. Issue Creation
- Passes all arguments to `gh issue create`
- Preserves original GitHub CLI functionality
- Captures issue URL from output

### 2. Workflow Reference Injection
When SE workflow is enabled (default), the script appends this text to the issue body:

```
---
**🔄 SE Workflow:** This issue uses the software engineering workflow.
Pull current steps from database at start: `SELECT step_order, description FROM workflow_steps WHERE workflow_id = (SELECT id FROM workflows WHERE name = 'software-development') ORDER BY step_order;`
```

### 3. Database Integration

#### coder_issue_queue Table
Tracks issues in the SE workflow pipeline:

```sql
INSERT INTO coder_issue_queue (repo, issue_number, title, status)
VALUES ('owner/repo', 123, 'Issue Title', 'pending_tests')
ON CONFLICT (repo, issue_number) DO UPDATE SET status = 'pending_tests';
```

**Columns:**
- `repo` - GitHub repository (format: `owner/repo`)
- `issue_number` - GitHub issue number
- `title` - Issue title
- `status` - Workflow status (`pending_tests`, `in_progress`, `completed`)

#### agent_chat Table
Notifies NOVA to initiate SE workflow:

```sql
INSERT INTO agent_chat (sender, message, mentions)
VALUES ('system', 'SE WORKFLOW TRIGGERED: New issue created...', ARRAY['NOVA']);
```

**Message includes:**
- Repository and issue number
- Issue title and URL
- Specific command for spawning Gemini agent
- Instructions for test case design

### 4. Agent Orchestration
The notification triggers NOVA to:
1. Spawn a Gemini agent
2. Task it with designing test cases
3. Follow SE workflow step 2
4. Write output to `tests/TEST-CASES-ISSUE-{number}.md`

## Database Schema Requirements

### coder_issue_queue
```sql
CREATE TABLE coder_issue_queue (
    id SERIAL PRIMARY KEY,
    repo VARCHAR(100) NOT NULL,
    issue_number INTEGER NOT NULL,
    title TEXT,
    status VARCHAR(50) DEFAULT 'pending_tests',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(repo, issue_number)
);
```

### agent_chat
```sql
CREATE TABLE agent_chat (
    id SERIAL PRIMARY KEY,
    sender VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    mentions TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### SE Workflow Tables
The script references these tables for workflow step retrieval:

```sql
CREATE TABLE workflows (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE workflow_steps (
    id SERIAL PRIMARY KEY,
    workflow_id INTEGER REFERENCES workflows(id),
    step_order INTEGER NOT NULL,
    agent_id INTEGER REFERENCES agents(id),
    description TEXT NOT NULL,
    produces_deliverable BOOLEAN DEFAULT false,
    deliverable_type VARCHAR(50),
    deliverable_description TEXT,
    handoff_to_step INTEGER,
    required BOOLEAN DEFAULT true,
    estimated_duration_minutes INTEGER,
    requires_authorization BOOLEAN DEFAULT false,
    requires_discussion BOOLEAN DEFAULT false,
    domain VARCHAR(100),
    domains TEXT[]
);
```

### Step Gating: `requires_authorization` and `requires_discussion`

These two boolean flags control how the orchestrator moves through workflow steps. They act as **gates** — one at entry, one at exit.

#### `requires_authorization` — ENTRY GATE

Controls whether the orchestrator can **begin** this step without asking first.

- If `true`: the orchestrator **MUST** ask the user for permission before starting the step.
- If `false`: the orchestrator may begin the step immediately.
- Think of it as: **"Can I start this?"**

#### `requires_discussion` — EXIT GATE

Controls whether the orchestrator can **proceed past** this step without discussion.

- If `true`: after completing the step, the orchestrator must present results and discuss with the user before moving on. This is triggered when there are matching reasons — open questions, ambiguities, or gaps that need human input.
- If `false`: the orchestrator may proceed to the next step immediately.
- Think of it as: **"Can I move on from this?"**

#### Examples: Four Combinations

| `requires_authorization` | `requires_discussion` | Behavior |
|---|---|---|
| `false` | `false` | **Fully autonomous.** Orchestrator starts the step and moves on without pausing. Example: "Document changes" — straightforward, no ambiguity. |
| `false` | `true` | **Auto-start, discuss before moving on.** Orchestrator begins immediately but must present results for review before proceeding. Example: "Receive Task & Assess Scope" — start right away, but discuss the assessment before committing to a plan. |
| `true` | `false` | **Ask to start, then proceed freely.** Orchestrator requests permission to begin, but once started, moves on without further discussion. Example: "Staging Reset" — destructive action needs approval, but the result is pass/fail with no ambiguity. |
| `true` | `true` | **Full human-in-the-loop.** Orchestrator asks before starting AND discusses results before moving on. Example: a hypothetical "Deploy to Production" step — needs approval to begin and review before continuing. |

## Error Handling

### GitHub CLI Errors
- Script exits with same code as `gh issue create`
- Original error messages are preserved
- No database modifications if issue creation fails

### Database Connection Issues
- PostgreSQL errors are displayed but don't prevent issue creation
- Issue is still created in GitHub even if workflow integration fails

### Missing Issue URL
- Warning message displayed if URL extraction fails
- SE workflow is skipped gracefully

## Workflow Integration

### SE Workflow Steps
1. **Receive Task & Assess Scope** _(exit: discussion)_
2. **Validate Against Docs** _(exit: discussion)_
3. **Design Test Cases** _(entry: authorization)_
4. **Review Test Cases** _(exit: discussion)_
5. **Implement on feature branch**
6. **Document changes**
7. **Run Tests** _(exit: discussion)_
8. **Validate Coverage** _(exit: discussion)_
9. **Push & Create PR** _(exit: discussion for upstream)_
10. **Merge PR**
11. **Staging Reset** _(entry: authorization)_
12. **Staging Integration Tests**

### Status Tracking
Issue status in `coder_issue_queue`:
- `pending_tests` - Initial state after creation
- `in_progress` - Work has begun
- `completed` - All workflow steps finished

## Troubleshooting

### Common Issues

**"command not found: gh"**
```bash
# Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh
gh auth login
```

**"psql: FATAL: database does not exist"**
```bash
# Check database connection
psql -d nova_memory -c "SELECT version();"

# Verify tables exist
psql -d nova_memory -c "\dt" | grep -E "(coder_issue_queue|agent_chat)"
```

**"Could not extract issue URL"**
- Check that `gh issue create` output contains a valid GitHub URL
- Ensure repository has issues enabled
- Verify GitHub CLI authentication: `gh auth status`

### Debug Mode
Add debug output by modifying the script:

```bash
# Add after set -e
set -x  # Enable debug mode
```

## See Also

- [GitHub CLI Documentation](https://cli.github.com/manual/)
- [NOVA Motivation System](../README.md)
- [SE Workflow Documentation](../WORKFLOW.md)
- [Database Schema](../DEPLOYMENT.md#database-setup)

## Contributing

To modify this wrapper:

1. Test changes with `--no-workflow` flag first
2. Verify database queries against current schema
3. Ensure backward compatibility with existing `gh issue create` usage
4. Update this documentation for any new features or options