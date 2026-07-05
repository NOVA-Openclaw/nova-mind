# System-Level Controls: Enforcing Agent Role Boundaries

## Overview

Agent delegation in the NOVA system is not purely a matter of policy and convention — it is reinforced by **system-level controls** that operate independently of any individual agent's judgment. This document covers how OS-level mechanisms enforce the boundaries between agents, using the global git pre-push hook as a concrete example.

## Why System-Level Controls Matter

Agent role boundaries can be described in documentation, encoded in workflow steps, and enforced by peer convention — but these are all soft constraints. A misconfigured agent, a subagent spawned without proper context, or an unexpected tool invocation can bypass policy-level controls unintentionally.

System-level controls add a **hard enforcement layer** that cannot be bypassed through documentation misreading, prompt drift, or missing context. They provide:

- **Fail-closed behavior** — by default, agents without a recognized identity are blocked, not allowed
- **Audit logging** — blocked attempts are recorded even when no agent notices them
- **Layered defense** — combined with server-side controls (e.g., GitHub branch protection), the system enforces delegation boundaries at multiple independent levels
- **No single point of failure** — client-side enforcement catches accidental pushes even if server-side rules change

---

## Example: Global Git Pre-Push Hook

### What It Is

A global git pre-push hook at `~/.config/git/hooks/pre-push` enforces which agents are permitted to push to git repositories, and to which branches.

**Configuration:** The hook is activated globally via git's `core.hooksPath` setting:

```ini
# ~/.gitconfig
[core]
    hooksPath = /home/nova/.config/git/hooks
```

This means the hook runs for **every git push** across every repository on the system, regardless of whether a per-repo hook exists.

### How It Works

At push time, the hook reads the `OPENCLAW_AGENT_ID` environment variable, which OpenClaw injects at runtime into every agent's execution environment. The hook uses this identity to enforce the permission matrix.

```bash
# ~/.config/git/hooks/pre-push

# Allow Gidget (git agent) — full push access
if [[ "$OPENCLAW_AGENT_ID" == "gidget" || "$OPENCLAW_AGENT_ID" == "git-agent" ]]; then
    exit 0
fi

# Allow Coder and Scribe — feature branches only, not main/master
if [[ "$OPENCLAW_AGENT_ID" == "coder" || "$OPENCLAW_AGENT_ID" == "scribe" ]]; then
    while read local_ref local_sha remote_ref remote_sha; do
        if [[ "$remote_ref" == "refs/heads/main" || "$remote_ref" == "refs/heads/master" ]]; then
            # Block with clear explanation
            echo "🚫 CODER: Cannot push directly to ${remote_ref#refs/heads/} 🚫" >&2
            exit 1
        fi
    done
    exit 0
fi

# All other agents: blocked from all pushes
exit 1
```

### Permission Matrix

| Agent | Identity (`OPENCLAW_AGENT_ID`) | Can Push Feature Branches | Can Push `main`/`master` |
|-------|-------------------------------|--------------------------|--------------------------|
| Gidget | `gidget` or `git-agent` | ✅ Yes | ✅ Yes |
| Coder | `coder` | ✅ Yes | ❌ No |
| Scribe | `scribe` | ✅ Yes | ❌ No |
| NOVA | `nova` or unset | ❌ No | ❌ No |
| All others | any other value | ❌ No | ❌ No |

This reflects the broader delegation model: Gidget owns git operations as its specialized role; Coder and Scribe are permitted to push their own work to feature branches; all other agents must route git operations through Gidget.

### Layered Enforcement

The pre-push hook is the **client-side** layer of a two-layer enforcement system:

```
Agent attempts push
       │
       ▼
┌─────────────────────────────┐
│  Pre-push hook (client)     │
│  Reads OPENCLAW_AGENT_ID    │
│  Blocks unauthorized agents │
└─────────────────────────────┘
       │ (if allowed through)
       ▼
┌─────────────────────────────┐
│  GitHub branch protection   │
│  (server-side)              │
│  PRs required for main      │
│  Enforced regardless of     │
│  client configuration       │
└─────────────────────────────┘
```

Even if the client-side hook were bypassed (e.g., by cloning to a new location, or running git directly without the hooksPath configured), GitHub's branch protection rules still require pull requests for merges to `main`. The two layers operate independently.

### Audit Logging

Blocked push attempts are logged to `~/.openclaw/logs/git-direct-push.log`:

```
[2026-02-15T14:32:01Z] BLOCKED: Direct push to nova-mind by agent=nova
[2026-02-15T14:35:42Z] BLOCKED: Coder push to protected branch in nova-mind
```

This provides an observable record of attempted policy violations — useful for diagnosing misconfigured agents or unexpected subagent behavior.

---

## Known Exception: Mechanical Callers Spoofing `OPENCLAW_AGENT_ID`

The hook's identity check assumes `OPENCLAW_AGENT_ID` reflects which *agent* is pushing. As of nova-mind [#399](https://github.com/NOVA-Openclaw/nova-mind/issues/399), one caller breaks that assumption on purpose: `cognition/scripts/pg-notify-listener.py`'s schema-sync path (`sync_schema_to_github()`) sets `OPENCLAW_AGENT_ID=gidget` on its own `git push` subprocess so the hook lets a mechanical, unattended background push through, even though no Gidget-spawned process is actually running.

This is a deliberate, narrow workaround — schema-sync previously delegated pushes to Gidget via `agent_chat`, but Gidget is an ephemeral subagent with no persistent listener, so that delegation silently accumulated undrained work orders (see `cognition/CHANGELOG.md`, Issue #399). Pushing directly and reusing Gidget's push identity was judged safer than leaving the push undelegated entirely. **This is flagged as a known follow-up, not a closed decision:** a dedicated `schema-sync` identity with its own pre-push hook allowlist entry would be more correct than reusing Gidget's, and is expected to replace this workaround in a future change.

If you are auditing pre-push hook behavior or investigating why a push attributed to `gidget` didn't originate from an actual Gidget-spawned process, check whether it came from the schema-sync path first.

---

## Design History: Removing the Token Bypass

An earlier version of this hook included a **token file bypass mechanism**: if a file matching `/tmp/.gidget-push-token-*` existed and was recent (within 5 minutes), the hook would allow the push regardless of agent identity. This was used when Gidget could not reliably distinguish itself via environment variable.

The bypass was **removed once OpenClaw shipped native `OPENCLAW_AGENT_ID` injection**. With reliable identity injection at the runtime level, the token file became unnecessary complexity — and a potential attack surface. The current design relies solely on the environment variable, which is:

- Injected by OpenClaw (not settable by the agent itself)
- Available in all exec contexts
- Consistent across all session types

This is a good example of a common infrastructure pattern: temporary bypasses introduced to handle capability gaps should be removed once the underlying capability is available.

---

## Test Matrix

The following test cases verify the hook's behavior across all scenarios:

| # | Agent ID | Target Branch | Expected Result | Reason |
|---|----------|---------------|-----------------|--------|
| 1 | `gidget` | `main` | ✅ Allowed | Gidget has full push access |
| 2 | `gidget` | `feature/xyz` | ✅ Allowed | Gidget has full push access |
| 3 | `coder` | `feature/xyz` | ✅ Allowed | Coder can push feature branches |
| 4 | `coder` | `main` | ❌ Blocked | Coder blocked from protected branches |
| 5 | `scribe` | `docs/my-doc` | ✅ Allowed | Scribe can push feature branches |
| 6 | `nova` | `feature/xyz` | ❌ Blocked | Non-git agents blocked from all pushes |
| 7 | *(unset)* | `feature/xyz` | ❌ Blocked | Unknown agents default to blocked |

Test cases 4, 6, and 7 all produce log entries in `~/.openclaw/logs/git-direct-push.log` and print a descriptive error message to stderr.

---

## Relationship to Agent Delegation Philosophy

This hook embodies a key principle from the NOVA delegation model: **specialization is enforced, not merely suggested**.

Gidget's role as the version control agent is not just a convention documented in AGENTS.md — it is structurally enforced by the OS. Other agents can describe what they need done with git; only Gidget (or an agent with explicit feature-branch access) can actually execute the push. This prevents "shortcutting" where an agent tries to handle git operations itself rather than delegating appropriately.

The hook also exemplifies the broader pattern that system-level controls should reflect and reinforce the agent architecture:

- The permission matrix maps directly to agent roles defined in the database
- Blocked operations fail with clear, actionable messages that name the correct delegate
- The logging layer provides observability into the delegation system's enforcement in practice

---

## Related Documentation

- [delegation-context.md](delegation-context.md) — How agents discover who to delegate to
- [delegation-context-auto-regeneration.md](delegation-context-auto-regeneration.md) — Dynamic delegation context updates
- [shell-environment.md](shell-environment.md) — How `BASH_ENV` and env vars are propagated to agent exec contexts
- [philosophy.md](philosophy.md) — The cognitive architecture model behind agent role specialization
