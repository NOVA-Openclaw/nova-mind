# Test Cases — Issue #104

> **shell-install.sh should exec agent-install.sh after config setup**

## A. shell-install.sh → agent-install.sh handoff

### A1: shell-install.sh executes agent-install.sh after config setup
- **Given** postgres.json does not exist (fresh install)
- **When** user runs `shell-install.sh` and provides DB connection details
- **Then** after writing postgres.json, the script `exec`s `agent-install.sh`
- **Verify** agent-install.sh runs (DB creation, schema, hooks attempted) — no "Done. Next: run agent-install.sh" message printed

### A2: CLI arguments passed through via $@
- **When** user runs `shell-install.sh --verify-only`
- **Then** agent-install.sh receives `--verify-only` and runs in verify mode (no mutations)
- **Also test** `shell-install.sh --database custom_db` — agent-install.sh uses `custom_db`

### A3: Existing postgres.json still triggers agent-install.sh
- **Given** postgres.json already exists
- **When** user runs `shell-install.sh`
- **Then** config write is skipped ("already exists" warning shown) **but** agent-install.sh is still exec'd
- **Regression** Currently the script stops at the "Done" message even when config exists

### A4: ENV vars from shell-install.sh available to agent-install.sh
- **Given** shell-install.sh sources `lib/pg-env.sh` and calls `load_pg_env`
- **When** agent-install.sh starts (via exec from shell-install.sh)
- **Then** PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD are set from postgres.json
- **Verify** agent-install.sh does not error with "Config file not found" when invoked this way

## B. agent-install.sh lib ordering

### B1: install_lib_files() runs before API key check
- **Current bug** install_lib_files (line 616) runs after the API key check (line 535) which can `exit 1`
- **After fix** install_lib_files should run immediately after postgres.json config load (before Part 1.5)
- **Verify** by inspecting script order: install_lib_files call appears before the OPENAI_API_KEY block

### B2: Missing OPENAI_API_KEY does not prevent lib file installation
- **Given** OPENAI_API_KEY is unset, user cancels the API key prompt (presses Enter)
- **When** agent-install.sh runs
- **Then** `~/.openclaw/lib/pg-env.sh` (and any other lib files) are installed before the script exits
- **Verify** `ls ~/.openclaw/lib/` shows files even after early exit

### B3: Lib files present after partial install
- **Given** agent-install.sh exits at API key check (exit 1)
- **Then** `~/.openclaw/lib/pg-env.sh` exists and is valid (sourceable without error)
- **Why** Other tools (shell-install.sh, manual scripts) depend on these lib files

## C. End-to-end

### C1: Single command full installation
- **Given** fresh environment — no postgres.json, no database, no lib files
- **When** user runs `shell-install.sh` and provides all prompts (DB details + API key)
- **Then** all of the following complete:
  1. `~/.openclaw/postgres.json` written
  2. `~/.openclaw/lib/pg-env.sh` installed
  3. Database created with schema + pgvector extension
  4. Git hooks installed
- **Key point** User runs ONE command, not two

### C2: shell-install.sh --verify-only passes through to verify mode
- **When** `shell-install.sh --verify-only`
- **Then** config is set up (or skipped if exists), then agent-install.sh runs in verify-only mode
- **Verify** no database mutations occur, exit code reflects verification result

### C3: Reference pattern — matches nova-cognition
- **Compare** final lines of shell-install.sh to nova-cognition's pattern:
  ```bash
  exec "$(dirname "$0")/agent-install.sh" "$@"
  ```
- **Verify** the `exec` replaces the shell process (not a subshell call)
