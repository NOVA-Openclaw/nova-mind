# Issue #152: Add "type": "module" to Hook package.json Files

## Problem
Node.js emits `MODULE_TYPELESS_PACKAGE_JSON` warnings on every gateway startup for hooks that use ES module syntax but lack `"type": "module"` in their `package.json`:

```
Warning: Module type of file:///.../.openclaw/hooks/agent-config-db/handler.ts is not specified and it doesn't parse as CommonJS.
Reparsing as ES module because module syntax was detected. This incurs a performance overhead.
To eliminate this warning, add "type": "module" to .../package.json.
```

## Affected Hooks
- [ ] `agent-config-db/package.json`
- [ ] `db-bootstrap-context/package.json`
- [ ] Any other hooks in `nova-cognition` using ES module syntax without the declaration

## Solution
Add `"type": "module"` to each affected hook's `package.json`. Also update the installer to include this field when generating new hook `package.json` files.

## Acceptance Criteria
- [ ] All hook `package.json` files in `nova-cognition` include `"type": "module"` where applicable
- [ ] No `MODULE_TYPELESS_PACKAGE_JSON` warnings on gateway startup
- [ ] Installer generates correct `package.json` for new hook installations
