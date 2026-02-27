# Issue #151: Install Script Overwrites Existing Config Values

## Problem
Running `shell-install.sh` (via `agent-install.sh`) overwrites existing values in `~/.openclaw/openclaw.json` instead of preserving them. Specifically observed: the `channels.agent_chat.password` field was reset to an empty string `""` after running the installer, wiping out a previously configured strong password.

## Expected Behavior
The installer should **never overwrite config values that are already set**. It should only:
- Add keys/sections that don't exist yet
- Leave existing values untouched
- Warn the user if a default differs from the existing value (optional)

## Actual Behavior
The installer blindly writes default config blocks, overwriting any user-customized values (passwords, credentials, custom settings) with empty defaults.

## Impact
- **Security risk:** Strong passwords replaced with empty strings
- **Service disruption:** Agent loses database connectivity after reinstall
- **Trust erosion:** Users can't safely re-run the installer to update without risking config loss

## Scope
This was observed in `nova-cognition`'s installer but the same pattern likely exists in:
- [ ] `nova-cognition/agent-install.sh` (confirmed)
- [ ] `nova-memory/agent-install.sh` (needs audit)
- [ ] `nova-relationships/agent-install.sh` (needs audit, if applicable)
- [ ] Any other repo with a `shell-install.sh` / `agent-install.sh`

## Solution
The config-patching logic in all installers should use a **merge strategy** that:
1. Reads the existing config file first
2. Only writes keys that are missing or have no value
3. Preserves any non-empty existing values
4. Logs what was added vs what was preserved

Example pseudocode:
```javascript
// WRONG (current behavior)
config.channels.agent_chat.password = "";

// RIGHT (merge behavior)
if (!config.channels?.agent_chat?.password) {
  config.channels.agent_chat.password = "";
  console.log("Set default empty password — update with real credentials");
}
```

## Acceptance Criteria
- [ ] Installer preserves all existing non-empty config values
- [ ] Installer only adds missing keys/sections
- [ ] All repo installers audited for the same pattern (`nova-cognition`, `nova-memory`, others)
- [ ] Running the installer twice in a row produces no config changes on the second run
