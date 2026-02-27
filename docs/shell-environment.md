# Shell Environment Setup

The NOVA Cognition System includes a shell environment setup feature that enables shell functions and aliases to work correctly in both interactive and non-interactive contexts. This is essential for proper operation of SE workflow commands and git operations within OpenClaw's execution environment.

## What Gets Installed and Why

The shell environment setup creates two key files that work together to provide consistent shell behavior across all contexts:

### Installation Files

1. **`~/.local/share/nova/shell-aliases.sh`** - Shell functions
   - Contains custom shell functions and command wrappers
   - Implements SE (Software Engineering) workflow automation
   - Provides the `gh` wrapper function that enforces PR merge permissions and triggers issue workflows
   - Located in the NOVA shared directory for system-wide access

2. **`~/.bash_env`** - Environment initialization file
   - Sourced via the `BASH_ENV` environment variable
   - Contains environment variable exports and source commands
   - Sources the shell-aliases.sh file to make functions available
   - Runs for both interactive and non-interactive shells

3. **OpenClaw config `env.vars.BASH_ENV`** - Configuration setting
   - Set in `~/.openclaw/openclaw.json` under `env.vars.BASH_ENV`
   - Points to the path of the .bash_env file
   - Enables non-interactive shell support in OpenClaw exec commands

## Why BASH_ENV?

The `BASH_ENV` mechanism is crucial for the proper functioning of the NOVA system:

- **Exec commands run `bash -c`** which doesn't read `.bashrc` by default
- **`BASH_ENV` tells bash which file to source** for non-interactive shells
- **This enables shell functions** (like the SE workflow `gh` wrapper) in exec context
- **Without BASH_ENV**, shell functions would only work in interactive sessions

When OpenClaw executes commands through the `exec` tool, it uses `bash -c "command"`, which creates a non-interactive shell. Non-interactive shells don't automatically source `.bashrc` or `.bash_profile`, so custom functions and aliases wouldn't be available. By setting `BASH_ENV`, we ensure that our shell setup is loaded every time.

## Installation

The shell environment is automatically configured when the NOVA Cognition System is properly installed. The setup process:

1. Creates `~/.local/share/nova/shell-aliases.sh` with SE workflow functions
2. Creates or updates `~/.bash_env` to source the aliases file
3. Configures OpenClaw's `env.vars.BASH_ENV` setting to point to `~/.bash_env`

### Manual Verification

To verify the installation:

```bash
# Check that the shell aliases file exists
ls -la ~/.local/share/nova/shell-aliases.sh

# Check that .bash_env exists and sources the aliases
cat ~/.bash_env

# Check OpenClaw configuration
grep -A5 -B5 "BASH_ENV" ~/.openclaw/openclaw.json
```

## Troubleshooting

### Common Issues

**Problem: `type gh` shows binary instead of function**

This indicates that the shell function wrapper is not being loaded properly.

**Solution:** Check BASH_ENV configuration

1. **Check BASH_ENV is set in OpenClaw config:**
   ```bash
   grep "BASH_ENV" ~/.openclaw/openclaw.json
   ```
   Should show: `"BASH_ENV": "/home/user/.bash_env"`

2. **Verify .bash_env file exists and sources aliases:**
   ```bash
   cat ~/.bash_env
   ```
   Should contain: `source ~/.local/share/nova/shell-aliases.sh`

3. **Test manually with BASH_ENV:**
   ```bash
   BASH_ENV=~/.bash_env bash -c 'type gh'
   ```
   Should show: `gh is a function`

4. **Restart OpenClaw gateway after configuration changes:**
   ```bash
   openclaw gateway restart
   ```

### Verification Commands

Use these commands to verify proper setup:

```bash
# Verify gh function is loaded (should show "gh is a function")
type gh

# Test in non-interactive context (should also show "gh is a function")
BASH_ENV=~/.bash_env bash -c 'type gh'

# Check BASH_ENV environment variable is set
echo $BASH_ENV
```

**Expected Results:**
- `type gh` should show "gh is a function" (not the path to gh binary)
- The non-interactive test should produce the same result
- `$BASH_ENV` should point to your `.bash_env` file path

## Customization

The shell environment setup is designed to be extensible for your specific needs.

### Adding Your Own Functions

To add custom shell functions:

1. **Edit the shell-aliases.sh file:**
   ```bash
   nano ~/.local/share/nova/shell-aliases.sh
   ```

2. **Add your function at the end of the file:**
   ```bash
   # Custom function example
   myfunction() {
     echo "This is my custom function"
     # Your custom logic here
   }
   ```

3. **Test the function:**
   ```bash
   # Source the file to load new functions in current shell
   source ~/.local/share/nova/shell-aliases.sh
   
   # Test your function
   myfunction
   ```

### Adding Environment Variables

To add custom environment variables that will be available in all contexts:

1. **Edit the .bash_env file:**
   ```bash
   nano ~/.bash_env
   ```

2. **Add your variables before the source command:**
   ```bash
   # Custom environment variables
   export MY_CUSTOM_VAR="my_value"
   export PATH="$HOME/my-tools:$PATH"
   
   # Keep this line at the end
   source ~/.local/share/nova/shell-aliases.sh
   ```

3. **Test the variables:**
   ```bash
   # Test in non-interactive context
   BASH_ENV=~/.bash_env bash -c 'echo $MY_CUSTOM_VAR'
   ```

### Best Practices for Customization

- **Always test in non-interactive context** using `BASH_ENV=~/.bash_env bash -c 'command'`
- **Keep the source command at the end** of `.bash_env` to ensure proper loading order
- **Use meaningful function and variable names** to avoid conflicts
- **Document your customizations** with comments for future reference
- **Restart OpenClaw gateway** after making changes to ensure they take effect

## Technical Details

### File Locations and Purposes

| File | Location | Purpose | Context |
|------|----------|---------|---------|
| `shell-aliases.sh` | `~/.local/share/nova/` | Function definitions | Both interactive and non-interactive |
| `.bash_env` | `~/` | Environment setup | Sourced via `BASH_ENV` |
| `openclaw.json` | `~/.openclaw/` | OpenClaw configuration | Gateway process |

### How It Works

1. **OpenClaw starts** and reads `env.vars.BASH_ENV` from configuration
2. **Environment variable set** `BASH_ENV=/home/user/.bash_env`
3. **Exec commands run** `bash -c "command"` with `BASH_ENV` inherited
4. **Bash sources** `.bash_env` automatically for non-interactive shells
5. **Functions become available** in the execution context

This ensures that SE workflow commands like `gh issue create` trigger the proper automation regardless of whether they're run interactively or through OpenClaw's exec system.