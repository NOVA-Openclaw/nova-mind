# Bootstrap Context FDW Replication

Architecture for sharing `agent_bootstrap_context` records across peer agent databases using PostgreSQL's Foreign Data Wrapper (FDW), replacing manual copy and write-time sync approaches for `UNIVERSAL` and `GLOBAL` records.

## Problem

Peer agents (Graybeard, Victoria, Newhart) each have their own database (`graybeard_memory`, `victoria_memory`, `newhart_memory`), but they need to share identical `UNIVERSAL` and `GLOBAL` bootstrap context records. Previously these were manually copied between databases, and drift accumulated over time — missing records, stale content, and misclassified entries all crept in undetected.

## Solution: `postgres_fdw`

All peer databases live in the same PostgreSQL instance as `nova_memory`. `postgres_fdw` (Foreign Data Wrapper) gives each peer database zero-lag, live read access to `nova_memory` — the canonical source for `UNIVERSAL` and `GLOBAL` records — without copying data or running a sync job.

## Architecture

`nova_memory` is canonical for `UNIVERSAL` and `GLOBAL` bootstrap context records. Each peer database is configured with:

1. **`postgres_fdw` extension** installed.
2. **Foreign server** `nova_memory_server`, pointing to `nova_memory` on `localhost:5432`.
3. **Foreign table** `nova_bootstrap_context`, mapping to `nova_memory.agent_bootstrap_context`.
4. **Read-only role** `bootstrap_reader`, with `SELECT`-only privilege on `nova_memory.agent_bootstrap_context`. No other privileges are granted, and no credentials are documented here — see your peer's `.pgpass` for connection details.
5. **User mapping** connecting each peer database's own user to `bootstrap_reader`.

The peer database's original local table is renamed to `agent_bootstrap_context_local`. A **view** named `agent_bootstrap_context` replaces it at that name, so application code and queries continue to reference `agent_bootstrap_context` unchanged:

- `UNIVERSAL` and `GLOBAL` rows → read from `nova_bootstrap_context` (the FDW foreign table, live from `nova_memory`)
- `AGENT`, `DOMAIN`, and `SYSTEM` rows → read from `agent_bootstrap_context_local`

### `INSTEAD OF` Triggers

Because `agent_bootstrap_context` is now a view, writes are routed with `INSTEAD OF` triggers:

- `INSERT` / `UPDATE` / `DELETE` targeting `AGENT`, `DOMAIN`, or `SYSTEM` rows → routed to `agent_bootstrap_context_local`.
- `INSERT` / `UPDATE` / `DELETE` targeting `UNIVERSAL` or `GLOBAL` rows → **raises an error** directing the caller to make the change in `nova_memory` instead. This is by design — peer databases no longer hold writable copies of `UNIVERSAL`/`GLOBAL` records.

## Schema Differences Across Peers

Peer databases were built at different times and have diverged slightly in schema shape:

- `nova_memory` and `graybeard_memory` use a `domain_name` column (`text`) — the older schema.
- `victoria_memory` and `newhart_memory` use `domain_names` (`text[]`) — the newer schema.
- `UNIVERSAL`/`GLOBAL` records always have `NULL` in the domain column regardless of schema version, so the view casts `NULL::text[]` for the newer-schema databases when reading from the FDW foreign table. This is a cosmetic cast, not a data problem — no domain information is lost because `UNIVERSAL`/`GLOBAL` records never carry domain data.
- `graybeard_memory`'s local table does not support the `SYSTEM` context type and has no heartbeat trigger. Victoria and Newhart's local tables support both.

## Context Type Hierarchy

| Context Type | Scope |
|---|---|
| `UNIVERSAL` | Mandatory instructions for all agents under our influence, regardless of system. |
| `GLOBAL` | Per-system records. All agents on a given system (e.g. `home.renaissancemachine.ai`) get the same `GLOBAL` records; a different system (e.g. `services.renaissancemachine.ai`) would have its own distinct set. |
| `DOMAIN` | Shared context for groups of agents that share a domain of expertise. |
| `AGENT` | Agent-specific context. |
| `SYSTEM` | System prompts. |

Only `UNIVERSAL` and `GLOBAL` are replicated via FDW. `DOMAIN`, `AGENT`, and `SYSTEM` remain local to each peer database, stored in `agent_bootstrap_context_local`.

## Maintenance

- **Adding or updating a `UNIVERSAL` or `GLOBAL` record:** Edit it in `nova_memory` only. All peer databases see the change immediately — there is no propagation delay and no sync step to run.
- **Adding a new peer database to this architecture:**
  1. Install the `postgres_fdw` extension.
  2. Create the foreign server, user mapping, and foreign table pointing at `nova_memory.agent_bootstrap_context`.
  3. Rename the peer's existing local table to `agent_bootstrap_context_local`.
  4. Create the `agent_bootstrap_context` view and its `INSTEAD OF` triggers as described above.
  5. Delete any old local `UNIVERSAL`/`GLOBAL` rows from the (now-renamed) local table — they are dead weight since the view no longer reads `UNIVERSAL`/`GLOBAL` from it.

  #### Migration Gotchas (from the 2026-07-25 Newhart split)

  1. **Trigger ownership** — verify the bootstrap write-protection trigger passes for the peer's DB user before importing records.
  2. **Per-section postgres.json credentials** — the `bootstrap` section is separate from the primary DB config; each section holding credentials must be updated independently.
  3. **Bootstrap manifest** — `get_agent_bootstrap()` has an implicit table dependency set beyond `agent_bootstrap_context` (see the dependency chain in the sync-mechanisms section); all of it must be local and current.
  4. **Join keys** — domain strings in `workflow_steps.domain` must exactly match `agent_domains.domain_topic`; a mismatched string silently drops the workflow from bootstrap output.
  5. **Consumer predicate ≠ ownership** — migrate workflows by domain routing (what `get_agent_bootstrap()` selects), not by `created_by` provenance; the two sets overlap but are not identical.

  A sixth, process-level lesson from the same split: when a directive supersedes an already-approved plan, the scope change must be explicitly propagated to everyone holding the old plan before execution — stale approvals otherwise cause conflicting enforcement.
- **`bootstrap_reader` role:** Read-only. Grants `SELECT` on `agent_bootstrap_context` in `nova_memory` only — no other tables, no write privileges. Credential values are not documented here; retrieve them through the standard peer credential path.

## Relationship to Per-Peer Sync Mechanisms

On the same day this architecture was implemented (2026-07-25), a separate memory-database-split effort (Newhart) introduced a write-time dual-write mechanism plus a daily checksum sync cron job for `UNIVERSAL`/`GLOBAL` records.

**The FDW view supersedes those mechanisms for `UNIVERSAL`/`GLOBAL` records.** Peers no longer hold local copies of `UNIVERSAL`/`GLOBAL` rows at all — they read live through the foreign table. Any script that attempts to write a `UNIVERSAL` or `GLOBAL` row directly into a peer's `agent_bootstrap_context` view will hit the `INSTEAD OF` trigger error described above, by design.

Practical implication: the dual-write and checksum-sync cron for `UNIVERSAL`/`GLOBAL` records should be retired going forward. Those mechanisms remain relevant only for tables **outside** the scope of this FDW replication — specifically `agents`, `agent_domains`, `workflows`, and `workflow_steps` — these form the **bootstrap resolution dependency chain** for `get_agent_bootstrap()`. The function joins `agents` → `agent_domains` to resolve domain-routed `DOMAIN` records and workflow records. If a peer's local copies of these tables drift from `nova_memory`, the function silently drops records from its output (observed during the Newhart split: an empty local `agents` table produced zero WORKFLOW records with no error).

## Known Drift Resolved During Rollout (2026-07-25)

Before this architecture was in place, the following drift was found and reconciled as part of the migration:

- `graybeard_memory` had 6 stale records (dated February–April 2026) and was missing 14 records present in `nova_memory`.
- `victoria_memory` had 9 diverged records, was missing 5, and had 1 misplaced record (`GLOBAL/TRADING_PIPELINE`, which should have been classified as a `DOMAIN` record).
- A full drift analysis was sent to Newhart for record reconciliation directly in `nova_memory`, since `nova_memory` is now the sole writable source for `UNIVERSAL`/`GLOBAL` content.

## Related

- [`schema-reference.md`](./schema-reference.md) — Complete table reference and access control documentation.
- `ARCHITECTURE.md` (repo root) — See the Database Schema section for `agent_bootstrap_context`.
