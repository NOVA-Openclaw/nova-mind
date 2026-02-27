
# Test Cases for Issue #83: Install shell-aliases.sh and .bash_env

**Objective:** Verify the correct installation and configuration of shell initialization files for the OpenClaw exec environment.

## Test Case 1: Fresh Install

**Pre-conditions:**

*   `nova-staging` is in a clean state (no previous installations of `shell-aliases.sh` or `.bash_env`).
*   OpenClaw is running with a default configuration.

**Test Steps:**

1.  Execute the agent-install script on `nova-staging`.
2.  Execute `exec "ls ~/.local/share/nova/shell-aliases.sh"` on `nova-staging`.
3.  Execute `exec "cat ~/.bash_env"` on `nova-staging`.
4.  Read the OpenClaw configuration file (location TBD) and verify the presence of `env.vars.BASH_ENV`.
5.  Execute `exec "type gh"` on `nova-staging`.

**Expected Results:**

1.  The agent-install script completes without errors.
2.  The `shell-aliases.sh` file exists in the specified directory.
3.  The `.bash_env` file contains the expected content (sourcing `shell-aliases.sh`).
4.  The OpenClaw configuration includes the `env.vars.BASH_ENV` variable pointing to `.bash_env`.
5.  The output of `type gh` shows that `gh` is a function, not a binary.

**Edge Cases:**

*   None. This is a fresh install.

## Test Case 2: Re-install

**Pre-conditions:**

*   `nova-staging` has already had the `shell-aliases.sh` and `.bash_env` installed (Test Case 1 has been executed).

**Test Steps:**

1.  Execute the agent-install script on `nova-staging` again.
2.  Execute `exec "cat ~/.bash_env"` on `nova-staging`.
3.  Read the OpenClaw configuration file and verify the contents of `env.vars.BASH_ENV`.
4.  Execute `exec "type gh"` on `nova-staging`.

**Expected Results:**

1.  The agent-install script completes without errors.
2.  The `.bash_env` file remains unchanged (no duplicate entries).
3.  The OpenClaw configuration still includes the `env.vars.BASH_ENV` variable with correct value.
4.  The output of `type gh` shows that `gh` is still a function.

**Edge Cases:**

*   None.

## Test Case 3: Partial State - shell-aliases.sh exists, .bash_env does not

**Pre-conditions:**

*   `~/.local/share/nova/shell-aliases.sh` exists.
*   `~/.bash_env` does not exist.
*   OpenClaw config does not have `env.vars.BASH_ENV`.

**Test Steps:**

1.  Create `~/.local/share/nova/shell-aliases.sh` with some content.
2.  Remove `~/.bash_env` if it exists.
3.  Remove `env.vars.BASH_ENV` from OpenClaw config if it exists.
4.  Execute the agent-install script on `nova-staging`.
5.  Execute `exec "ls ~/.local/share/nova/shell-aliases.sh"` on `nova-staging`.
6.  Execute `exec "cat ~/.bash_env"` on `nova-staging`.
7.  Read the OpenClaw configuration file and verify the presence of `env.vars.BASH_ENV`.
8.  Execute `exec "type gh"` on `nova-staging`.

**Expected Results:**

1.  The agent-install script completes without errors.
2.  The `shell-aliases.sh` file exists in the specified directory.
3.  The `.bash_env` file is created with the expected content.
4.  The OpenClaw configuration includes the `env.vars.BASH_ENV` variable.
5.  The output of `type gh` shows that `gh` is a function.

**Edge Cases:**

*   None

## Test Case 4: Partial State - .bash_env exists, shell-aliases.sh does not

**Pre-conditions:**

*   `~/.bash_env` exists with content: `export FOO=bar`.
*   `~/.local/share/nova/shell-aliases.sh` does not exist.
*    OpenClaw config does not have `env.vars.BASH_ENV`.

**Test Steps:**

1.  Create `~/.bash_env` with content: `export FOO=bar`.
2.  Remove `~/.local/share/nova/shell-aliases.sh` if it exists.
3.  Remove `env.vars.BASH_ENV` from OpenClaw config if it exists.
4.  Execute the agent-install script on `nova-staging`.
5.  Execute `exec "ls ~/.local/share/nova/shell-aliases.sh"` on `nova-staging`.
6.  Execute `exec "cat ~/.bash_env"` on `nova-staging`.
7.  Read the OpenClaw configuration file and verify the presence of `env.vars.BASH_ENV`.
8.  Execute `exec "type gh"` on `nova-staging`.
9.  Execute `exec "grep 'export FOO=bar' ~/.bash_env"` on `nova-staging`.

**Expected Results:**

1.  The agent-install script completes without errors.
2.  The `shell-aliases.sh` file is created in the specified directory.
3.  The `.bash_env` file is updated with the expected content (including sourcing the new shell-aliases.sh) AND preserves the original content (`export FOO=bar`).
4.  The OpenClaw configuration includes the `env.vars.BASH_ENV` variable.
5.  The output of `type gh` shows that `gh` is a function.
6.  The `grep` command confirms that `export FOO=bar` still exists in `~/.bash_env`.

**Edge Cases:**
* None

## Test Case 5: Invalid shell-aliases.sh path in .bash_env

**Pre-conditions:**
* `~/.bash_env` exists and contains an invalid path to `shell-aliases.sh`.
* `~/.local/share/nova/shell-aliases.sh` does not exist.
* OpenClaw config has `env.vars.BASH_ENV` pointing to the existing `.bash_env`.

**Test Steps:**
1. Create `~/.bash_env` with an incorrect path to `shell-aliases.sh` (e.g., `source /tmp/invalid_path/shell-aliases.sh`).
2. Ensure `~/.local/share/nova/shell-aliases.sh` does not exist.
3. Ensure OpenClaw config has `env.vars.BASH_ENV` pointing to `~/.bash_env`.
4. Execute the agent-install script on `nova-staging`.
5. Execute `exec "cat ~/.bash_env"` on `nova-staging`.
6. Read the OpenClaw configuration file and verify the `env.vars.BASH_ENV` value.
7. Execute `exec "type gh"` on `nova-staging`.

**Expected Results:**
1. The agent-install script completes without errors.
2. `~/.local/share/nova/shell-aliases.sh` is created.
3. `~/.bash_env` is updated to include the correct path to `shell-aliases.sh`.
4. The OpenClaw configuration remains unchanged (pointing to `~/.bash_env`).
5. The output of `exec "type gh"` shows that `gh` is a function.

**Edge Cases:**
*  The original `.bash_env` contains other important configurations that must be preserved. The agent-install script should additively update the file without removing existing content.
