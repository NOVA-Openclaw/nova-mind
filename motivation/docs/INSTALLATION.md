# Installation Guide

## Overview

The NOVA shell aliases installer sets up GitHub CLI integration with the Software Engineering (SE) workflow. The installer is designed to work across different user environments with relative paths and proper shell configuration.

## Features

- ✅ Uses relative paths (`$HOME`, `$USER`) for portability
- ✅ Database naming pattern: `${USER//-/_}_memory`
- ✅ Support for both bash and zsh shells
- ✅ Non-interactive shell support via `BASH_ENV`
- ✅ Automatic upgrade detection and migration
- ✅ Cleanup on failure with file restoration
- ✅ Idempotent - safe to run multiple times

## Quick Start

```bash
cd /path/to/nova-motivation
./agent-install.sh
```

## Requirements

- **Environment Variables**: `$HOME` and `$USER` must be set
- **Shell**: bash or zsh (fish requires manual setup)
- **GitHub CLI**: `gh` must be installed
- **PostgreSQL**: Database `${USER//-/_}_memory` should exist

## Installation Details

### What Gets Installed

1. **Shell aliases** → `~/.local/share/nova/shell-aliases.sh`
   - Wrapper function for `gh issue create`
   - Automatically triggers SE workflow
   - Inserts tasks into coder queue

2. **Shell RC integration** → `~/.bashrc` or `~/.zshrc`
   - Automatically sources aliases in interactive shells
   - Supports both bash and zsh

3. **BASH_ENV file** → `~/.bash_env`
   - Enables aliases in non-interactive shells
   - Required for OpenClaw `exec()` integration

### Directory Structure

```
$HOME/
├── .bash_env                          # Non-interactive shell config
├── .bashrc                            # Interactive bash config (modified)
├── .zshrc                             # Interactive zsh config (modified if exists)
└── .local/share/nova/
    └── shell-aliases.sh               # Main alias script
```

## Upgrade Process

When running the installer on an existing installation:

1. Detects existing files
2. Creates backups (`.backup` suffix)
3. Updates to new version
4. Removes backups on success
5. Restores backups on failure

**Safe to run multiple times** - the installer is fully idempotent.

## Shell Support

### Bash (✅ Fully Supported)

Aliases work in both interactive and non-interactive contexts when `BASH_ENV` is configured.

```bash
# Test interactive shell
type gh

# Test non-interactive shell
BASH_ENV=~/.bash_env bash -c 'type gh'
```

### Zsh (✅ Fully Supported)

Aliases are automatically added to `~/.zshrc` if it exists.

```bash
type gh
```

### Fish (⚠️ Manual Setup Required)

For fish shell, manually add to `~/.config/fish/config.fish`:

```fish
bass source ~/.local/share/nova/shell-aliases.sh
```

Note: Requires the [bass plugin](https://github.com/edc/bass) for sourcing bash scripts.

## OpenClaw Integration

To enable aliases in OpenClaw `exec()` commands, configure the gateway environment:

### Method 1: Environment Variable (Recommended)

Set `BASH_ENV` in the OpenClaw gateway configuration:

```bash
export BASH_ENV="$HOME/.bash_env"
```

Then restart the OpenClaw gateway.

### Method 2: Profile Configuration

Add to `~/.profile`:

```bash
export BASH_ENV="$HOME/.bash_env"
```

Then logout/login or source the profile:

```bash
source ~/.profile
```

### Verification

Test that OpenClaw can use the aliases:

```bash
# From OpenClaw exec():
gh --version  # Should show gh version
type gh       # Should show gh as a function
```

## Database Configuration

The installer uses a dynamic database naming pattern that handles usernames with special characters:

```bash
${USER//-/_}_memory
```

**Examples:**
- User `john` → Database `john_memory`
- User `john-doe` → Database `john_doe_memory`
- User `admin123` → Database `admin123_memory`

The database must exist before using the SE workflow. The aliases will insert records into:
- `coder_issue_queue` - Issue tracking
- `agent_chat` - Agent notifications

## Testing the Installation

### Test 1: Interactive Shell

```bash
type gh
# Expected: gh is a function
```

### Test 2: Non-Interactive Shell

```bash
BASH_ENV=~/.bash_env bash -c 'type gh'
# Expected: gh is a function
```

### Test 3: Database Name

```bash
echo "Database: ${USER//-/_}_memory"
# Expected: Shows your database name with underscores
```

### Test 4: Alias Functionality

```bash
# This should show the wrapper is active (without actually creating an issue)
type gh | grep "issue.*create"
# Expected: Should show the conditional logic in the function
```

## Troubleshooting

### Environment Variables Not Set

**Error**: `✗ Error: $HOME environment variable is not set`

**Solution**: Ensure you're running in a properly configured shell environment:

```bash
echo $HOME
echo $USER
```

If these are empty, there's a fundamental issue with your shell configuration.

### Aliases Not Working in OpenClaw

**Symptom**: `gh` commands work normally instead of triggering SE workflow

**Solutions**:

1. Check BASH_ENV is set:
   ```bash
   echo $BASH_ENV
   # Should show: /home/username/.bash_env
   ```

2. Verify `.bash_env` exists and has correct content:
   ```bash
   cat ~/.bash_env
   # Should show: source $HOME/.local/share/nova/shell-aliases.sh
   ```

3. Test manually with BASH_ENV:
   ```bash
   BASH_ENV=~/.bash_env bash -c 'type gh'
   ```

4. Restart OpenClaw gateway after setting BASH_ENV

### Installation Fails

The installer automatically cleans up on failure:
- Removes newly created files
- Restores modified files from backups
- Removes empty directories

To retry after fixing the issue:

```bash
./agent-install.sh
```

### Re-installation

To reinstall from scratch:

```bash
# Remove existing installation
rm -rf ~/.local/share/nova
rm ~/.bash_env

# Remove from shell RC files
# Edit ~/.bashrc and remove the NOVA section

# Re-run installer
./agent-install.sh
```

## Uninstallation

Manual uninstall steps:

```bash
# Remove aliases directory
rm -rf ~/.local/share/nova

# Remove BASH_ENV file
rm ~/.bash_env

# Remove from shell RC files
# Edit ~/.bashrc and/or ~/.zshrc
# Remove lines containing "NOVA shell aliases"
```

## Security Considerations

- The installer only modifies files in your home directory
- No system-wide changes are made
- All paths use `$HOME` and `$USER` for isolation
- Backups are created before modifying existing files
- Failed installations are automatically cleaned up

## Environment Variables Used

| Variable | Purpose | Required |
|----------|---------|----------|
| `$HOME` | Base directory for installation | ✅ Yes |
| `$USER` | Database naming and user identification | ✅ Yes |
| `$BASH_ENV` | Non-interactive shell initialization | Recommended for OpenClaw |
| `$ZSH_VERSION` | Shell type detection | Auto-detected |
| `$BASH_VERSION` | Shell type detection | Auto-detected |

## Advanced Configuration

### Custom Installation Directory

To change the installation directory, modify the `NOVA_DIR` variable in the installer:

```bash
NOVA_DIR="$HOME/.local/share/nova"  # Default
# NOVA_DIR="$HOME/.nova"            # Alternative
```

### Multiple Users

Each user gets their own isolated installation:
- Separate aliases in their `$HOME/.local/share/nova/`
- User-specific database: `${USER//-/_}_memory`
- No conflicts between users

## Contributing

When modifying the installer:

1. Maintain idempotency - script should be safe to run multiple times
2. Handle errors gracefully with cleanup
3. Test with different usernames (including special characters)
4. Test both fresh install and upgrade scenarios
5. Verify non-interactive shell support

## Related Documentation

- [GH Issue Wrapper](GH-ISSUE-WRAPPER.md) - Detailed workflow documentation
- [Test Cases](../tests/TEST-CASES-ISSUE-24.md) - Comprehensive test scenarios
- [Architecture](../ARCHITECTURE.md) - System architecture overview
