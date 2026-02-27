# Issue #149: agent_chat Plugin Reliability Improvements

## Status: MERGED (PR #149, 2026-02-23). Staging test pending via Graybeard.

## Background

After installing `nova-cognition` on Graybeard via `shell-install.sh`, the `agent_chat` extension plugin could receive inbound messages but outbound replies failed with:

```
Outbound not configured for channel: agent_chat
```

**Root cause:** The gateway was already running when `shell-install.sh` executed. Plugins are loaded once at gateway startup and cached in a module-level `registryCache` (`loader.ts`). Config hot-reload does NOT reload plugins — only channel configs and hooks. So even though `npm install` successfully installed `pg` into the extension's `node_modules/`, the plugin had already failed to load (missing `pg` at startup time) and the error state was cached for the lifetime of the process.

**Resolution:** A gateway restart after `shell-install.sh` completed resolved the issue. Graybeard now sends and receives agent_chat messages correctly.

## Improvements

### 1. shell-install.sh should restart the gateway after installation

**Problem:** `shell-install.sh` installs/updates extension source files, runs `npm install`, and compiles TypeScript — but never restarts the gateway. If the gateway was running during install, the old (possibly broken) plugin state persists until manual restart.

**Why a full restart (not hot-reload)?** OpenClaw's default reload mode is `hybrid` (watches config file, applies config-only changes like channel settings, hooks, cron without restart). However, hot-reload does NOT reload **plugins** — plugins are loaded once at gateway startup via `loadOpenClawPlugins()` and cached in `registryCache` for the process lifetime. Since our installer modifies plugin source files, npm dependencies, and extension code (not just config), a full gateway restart is required.

**Fix:** At the end of `agent-install.sh`, detect if the gateway is running and either:
- Automatically restart it (with a flag like `--no-restart` to opt out), or
- Print a clear warning: "⚠️ Gateway is running. Restart required for plugin changes to take effect: `systemctl --user restart openclaw-gateway`"

**File:** `nova-cognition/agent-install.sh` (end of script, after all installation steps)

**Note:** This same fix applies to all repos with `agent-install.sh` scripts. Separate issues have been created in: nova-dashboard, nova-memory, nova-motivation, nova-relationships, nova-scripts, nova-security, nova-software-engineering.

**Acceptance criteria:**
- [ ] If gateway is running after install, script either restarts it or prints a restart warning
- [ ] `--no-restart` flag suppresses automatic restart if we go that route
- [ ] Warning includes the exact command to run

### 2. agent_chat plugin self-validates dependency and registration integrity

**Problem:** Two failure modes are not caught at the plugin level:

**a) Missing dependency:** When `pg` is not installed, the plugin fails with a generic jiti import error. The error doesn't clearly indicate what's wrong or how to fix it.

**b) Asymmetric registration:** If the plugin's `register()` partially succeeds (e.g., inbound LISTEN/NOTIFY starts but outbound adapter isn't registered due to a load error), the agent processes messages then silently drops replies. The plugin should verify its own registration integrity.

**Fix:** In the plugin's `register()` function:

1. **Pre-flight dependency check** — Verify `pg` is resolvable before attempting registration:
```typescript
register(api: OpenClawPluginApi) {
  try {
    require.resolve('pg');
  } catch {
    throw new Error(
      'agent_chat: missing required dependency "pg". ' +
      'Run "npm install" in ~/.openclaw/extensions/agent_chat/'
    );
  }
  // ... registration
}
```

2. **Post-registration self-check** — After registering the channel, verify that both inbound and outbound capabilities are present. If the plugin defines an outbound adapter but it didn't register properly, log a clear warning:
```typescript
// After api.registerChannel(...)
if (!agentChatPlugin.outbound?.sendText) {
  api.log.error('agent_chat: outbound adapter missing — replies will fail. Check plugin load errors.');
}
if (!agentChatPlugin.gateway?.startAccount) {
  api.log.error('agent_chat: inbound gateway handler missing — messages will not be received.');
}
```

This keeps the validation inside our plugin rather than modifying nova-openclaw core. The upcoming open channel duplex feature in nova-openclaw will handle this at the framework level — until then, our plugin protects itself.

**File:** `nova-cognition/focus/agent_chat/index.ts`

**Acceptance criteria:**
- [ ] Missing `pg` produces a clear error message with the fix command
- [ ] Plugin self-validates that both inbound and outbound are registered
- [ ] Clear log messages when either capability is missing
- [ ] Plugin still loads normally when everything is present

### 3. Install `pg` to shared `~/.openclaw/node_modules/` instead of per-extension

**Problem:** Currently, `agent-install.sh` runs `npm install` inside the extension directory (`~/.openclaw/extensions/agent_chat/`), which installs `pg` to `~/.openclaw/extensions/agent_chat/node_modules/pg`. This means every extension that needs `pg` must install its own copy, and if a new extension is added that also needs `pg`, the installer must handle it again.

**How Node module resolution works:** When the plugin source at `~/.openclaw/extensions/agent_chat/src/channel.ts` does `import pg from "pg"`, Node walks up the directory tree looking for `node_modules/pg`:

```
~/.openclaw/extensions/agent_chat/src/node_modules/    (no)
~/.openclaw/extensions/agent_chat/node_modules/        ← current (per-extension)
~/.openclaw/extensions/node_modules/                   (no)
~/.openclaw/node_modules/                              ← proposed (shared)
~/node_modules/                                        (no)
```

**Fix:** Change the installer to install `pg` (and any other shared Node dependencies) at `~/.openclaw/node_modules/` instead of inside each extension's directory:

```bash
# Instead of:
cd "$EXTENSION_TARGET" && npm install

# Do:
cd ~/.openclaw && npm install pg
```

This works because `~/.openclaw/` is the OpenClaw config root — it's the natural location for shared dependencies that any extension, hook, or plugin under that tree might need. The `pg` dependency in the extension's `package.json` stays for documentation/versioning purposes, but the actual installation happens at the shared level.

**File:** `nova-cognition/agent-install.sh` (extension installation section, ~line 655)

**Acceptance criteria:**
- [ ] `pg` installed at `~/.openclaw/node_modules/pg` (not per-extension)
- [ ] `agent_chat` plugin resolves `pg` from the shared location
- [ ] Extension's `package.json` still lists `pg` as a dependency (for documentation)
- [ ] Installer skips per-extension `npm install` if shared deps are already present (or runs it only for non-shared deps if any exist)
- [ ] Works on fresh install (no prior `node_modules` anywhere)

## Scope

All three improvements are in `nova-cognition` (our repo). No nova-openclaw core changes needed.

## Dependencies

None — both improvements are independent and can be implemented separately.

## Step 2: Documentation Validation

**Docs consulted:** `docs/plugins/manifest.md`, `docs/tools/plugin.md`, `docs/cli/plugins.md`, `src/plugins/types.ts`, `src/plugins/loader.ts`, `src/plugins/discovery.ts`, `src/channels/plugins/registry-loader.ts`, `src/gateway/config-reload.ts`

**Findings:**
1. **Gateway restart (Improvement #1):** Docs state config changes require restart, but actual default is `hybrid` mode (hot-reload for config). However, hot-reload only covers config changes — plugin code/dependency changes always need full restart. Our installer modifies plugin code, so full restart is correct.
2. **Self-validation (Improvement #2):** `api.logger` is available in `register()` per `OpenClawPluginApi` type. Pre-flight checks and post-registration validation are valid within the `register()` pattern.
3. **Shared pg (Improvement #3):** Docs say "install npm deps in that directory so `node_modules` is available." Node resolution walks up the directory tree, so `~/.openclaw/node_modules/` also works. Docs don't forbid it. Note: `openclaw plugins install` uses `--ignore-scripts` for security, but we control our installer and `pg` is trusted.

**No contradictions.** Plan confirmed.

## Related Issues

- Gateway restart issues created in: nova-dashboard, nova-memory, nova-motivation, nova-relationships, nova-scripts, nova-security, nova-software-engineering
- nova-openclaw open channel duplex issue (will supersede improvement #2 at the framework level)
