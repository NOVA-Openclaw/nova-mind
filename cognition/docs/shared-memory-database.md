# Shared Memory Database

> **Optional local tooling — not a core part of nova-mind.** This guide describes a
> pattern for multi-agent systems where **each agent has its own memory database** and a
> handful of tables must be **shared identically** across all of them. The setup script
> (`scripts/shared-memory/setup-shared-memory.sh`) is optional tooling; the nova-mind
> installer does **not** run it. If your deployment uses a single shared database, you do
> not need any of this — see "When to use it" below.

The pattern makes a dedicated database, `shared_memory`, the **single canonical source**
for shared tables (shared bootstrap context, the model registry). Every `<agent>_memory`
database is an **identical consumer**: a `postgres_fdw` foreign server + foreign tables
pointing at `shared_memory`, plus a federation view that unions the shared rows with that
agent's own per-agent rows held locally.

---

## 1. When to use it

Use this pattern when **all** of the following hold:

- You run **several agents**, and **each has its own database** (`<agent>_memory`), for
  isolation, per-agent roles, or independent backup/restore.
- Some records must be **seen identically by every agent** — for example shared
  `UNIVERSAL` / `GLOBAL` / `DOMAIN` bootstrap context, or a model-registry table every
  agent reads.
- You want **one schema shape** across all agent databases, so a single reconcile
  procedure and a single installer path work for all of them.

### When NOT to use it

- **If a single shared database is enough, use that.** That is exactly what `agent_chat`
  does (nova-mind#320): one dedicated database every agent connects to directly, no FDW,
  no federation view. A single shared DB is simpler and has no foreign-table drift. Reach
  for `shared_memory` only when agents genuinely need **their own** databases *and* a
  shared subset of tables — not as a default.
- If the "shared" data is actually per-agent (different rows per agent), it is not shared;
  keep it local. Audit before migrating: compare row counts and content checksums across
  agent databases. A table that differs per agent is local, not shared.

---

## 2. Architecture

```
                         ┌───────────────────────────────┐
                         │        shared_memory          │  ← canonical source
                         │  (base tables, owned here)    │
                         │                               │
                         │  agent_bootstrap_context      │  UNIVERSAL/GLOBAL/DOMAIN/SYSTEM
                         │  ai_models                    │  (+ protection triggers)
                         │  ai_model_param_issues (view) │
                         └───────────────▲───────────────┘
                                         │ postgres_fdw (reads AS a dedicated reader role)
         ┌───────────────────────────────┼───────────────────────────────┐
         │                               │                               │
┌────────┴─────────┐          ┌──────────┴────────┐          ┌───────────┴───────┐
│  agentA_memory   │          │   agentB_memory   │   ...    │   agentN_memory   │
│  (identical consumer shape) │                   │          │                   │
│                  │          │                   │          │                   │
│ shared_agent_bootstrap_context  (FOREIGN)       │          │  (FOREIGN)        │
│ ai_models                       (FOREIGN)       │          │                   │
│ ai_model_param_issues           (FOREIGN)       │          │                   │
│ agent_bootstrap_context_local   (LOCAL TABLE: this agent's own AGENT rows)     │
│ agent_bootstrap_context         (VIEW = shared foreign  UNION  local AGENT)    │
└──────────────────┘          └───────────────────┘          └───────────────────┘
```

Every consumer exposes the **same canonical object name** — the federation **view**
`agent_bootstrap_context` — so application code and hooks bind to one name regardless of
which agent they run as. The view unions:

- shared rows (`UNIVERSAL`, `GLOBAL`, `DOMAIN`, `SYSTEM`) read live from the foreign table
  `shared_agent_bootstrap_context` (which points at `shared_memory`), and
- that agent's own `AGENT` rows from the local table `agent_bootstrap_context_local`.

### Why no agent's database should be the source

A tempting shortcut is to leave one agent's database (say `nova_memory`) holding the real
shared tables and have the others federate from it. **Do not.** That makes one database
asymmetric from the rest and forces every consumer of schema and installer logic to
special-case "the source DB":

- **Schema asymmetry → foreign-table drift (nova-mind#675).** When a shared column
  changes in the source, the foreign-table definitions in every *other* database still
  carry the old column list until re-imported. The non-source databases silently diverge.
  Making one agent the source means that database never has the drift, so it is easy to
  forget the others do — the asymmetry hides the bug.
- **Installer special-casing (nova-mind#608).** Schema-diff / migration tooling that
  treats the source DB differently from consumers accumulates branches ("if this is the
  source DB, the table is real; otherwise it's foreign"), and schema planners propose
  `DROP` of FDW objects they do not understand. A single canonical `shared_memory` that
  **no agent uses as its primary** makes every `<agent>_memory` the *same* consumer shape:
  one reconcile procedure, one installer path, no special cases.

---

## 3. Information boundaries

Which context types are shared vs local is the heart of the design. Keep them straight:

| Context type | Scope | Lives in | Shared? |
|---|---|---|---|
| **UNIVERSAL** | Everything, always — applies to every agent, every host | `shared_memory` | Yes, always |
| **GLOBAL** | The system/host you are running on | `shared_memory` | Yes |
| **DOMAIN** | Subject-matter expertise only (e.g. "systems", "research") — **shared by design** | `shared_memory` | Yes |
| **SYSTEM** | System-prompt-level shared record | `shared_memory` | Yes |
| **AGENT** | Personal, per-agent nuance and identity | `<agent>_memory` (local table) | **No — never shared** |

- **UNIVERSAL is everything, always.** It is the floor every agent stands on.
- **GLOBAL is the system you are running on** — host-level facts shared by all agents on
  that system.
- **DOMAIN is subject matter only.** A domain record is about a field of expertise, not an
  agent. It carries `domain_names` (e.g. `{systems}`) and **no** `agent_name`. DOMAIN is
  **shared by design** (nova-mind#718): the whole point is that every agent sees the same
  domain knowledge and the same expertise directory.
- **AGENT is personal.** Each agent's own identity, self-managed files, and per-agent
  nuance stay in that agent's local table and are **never** federated. One agent must not
  see another's AGENT rows through the shared path.

> **Boundary review:** the DOMAIN/AGENT boundary is owned by the bootstrap-context design
> (Newhart). Keep DOMAIN strictly subject-matter (no agent identity leaking in) and AGENT
> strictly personal (no shared knowledge that belongs in DOMAIN/UNIVERSAL).

---

## 4. Setup walkthrough

All commands use the setup script. It is **idempotent**, never drops or overwrites data,
and authenticates via `.pgpass` only — it never prints or creates credentials.

### 4a. Dry run first

```bash
scripts/shared-memory/setup-shared-memory.sh setup \
  --target-db shared_memory \
  --source-db <source_with_canonical_schema> \
  --consumer-dbs "agentA_memory agentB_memory agentN_memory" \
  --consumer-roles "agentA agentB agentN" \
  --dry-run
```

`--dry-run` prints the full planned SQL and **executes nothing** — no database, no
objects. Review it, confirm the DB names/table list/roles are right.

### 4b. Run setup

Drop `--dry-run`. The script then, in order:

1. **Creates `shared_memory`** (if absent) and clones the **canonical shared schema**
   from `--source-db`: the shared base tables, views, sequences, the **protection trigger
   functions**, and the triggers, with identical constraints and indexes.
2. **Installs grants**: the dedicated **FDW reader role** (default `bootstrap_reader`) and
   each **consumer role** get least-privilege access on the shared objects (see §5).
3. **Wires each consumer**: `CREATE EXTENSION postgres_fdw`; the foreign server; a user
   mapping per local role (authenticating **as the reader role**); the **local AGENT
   table** (`agent_bootstrap_context_local`, cloned from the canonical table's columns);
   the **foreign tables**; and the **federation view** `agent_bootstrap_context`.

> **FDW password is a credential-owner step.** `postgres_fdw` does **not** read `.pgpass`;
> the password must live in the user mapping. The script creates the mapping with
> `user=<reader role>` but **no password**, by design. On a fresh setup the import of
> foreign tables is **deferred** (the script says so and continues), because it cannot
> connect until the credential owner sets the mapping password:
>
> ```sql
> ALTER USER MAPPING FOR <local_role> SERVER shared_memory_server OPTIONS (ADD password '<reader pw>');
> ```
>
> Then run `reconcile` (see §7) to finish the import and build the views.

### 4c. Copy the shared rows (optional)

```bash
scripts/shared-memory/setup-shared-memory.sh setup \
  --target-db shared_memory --source-db <source> \
  --consumer-dbs "..." --consumer-roles "..." \
  --copy-from <source_with_rows>
```

`--copy-from` copies only the **shared** context types into `shared_memory` (AGENT rows
are left behind), using `ON CONFLICT DO NOTHING`, then **verifies counts and checksums
per context_type**. A mismatch aborts with a per-type report.

---

## 5. Roles and grants

**Least privilege per consumer:**

- A dedicated **read-only role** (`bootstrap_reader`) is what the FDW authenticates as. It
  has `SELECT` on the shared objects in `shared_memory` and nothing else. Every consumer's
  foreign reads go through this one role, so there is a single, auditable read path.
- **Consumer roles** get `CONNECT` + schema `USAGE` + `SELECT` on the shared objects (so
  they can read directly if needed) and `INSERT`/`UPDATE` on the writable shared bootstrap
  object. Domain-restricted writes (e.g. `DELETE`, or writes to the model registry) are
  granted only to the designated domain owner.

**Domain write-protection triggers work against shared tables.** The protection trigger
(e.g. `protect_bootstrap_context_writes_v2()`) **moves with the table into `shared_memory`**
and enforces row-level rules there: an agent may write only its own AGENT records with
self-managed file keys; domain/other records require the domain owner.

> **Caveat — superusers bypass triggers.** A protection trigger that early-returns for
> superusers constrains only **non-superuser** connections. If your agent roles are
> cluster superusers, the trigger is advisory for them. Prefer non-superuser roles for
> agents, or enforce writes through the view's `INSTEAD OF` trigger (§6) and reserve
> superuser for administration.

**One credential owner.** Role creation, password rotation, and `.pgpass`/user-mapping
password writes must go through a **single owner**. Parallel credential writes from two
actors race and leave `.pgpass` or the mapping out of sync with the live role, breaking
auth mid-provisioning. The setup script deliberately does none of this — it takes
pre-created roles as input and leaves passwords to the owner.

---

## 6. Writes

Agents write **shared** rows and **local** rows differently:

- **Direct writes.** Shared rows → write to `shared_memory` (through the consumer's
  `SELECT`/`INSERT` grants on the shared objects, subject to the protection trigger).
  Local AGENT rows → write to `agent_bootstrap_context_local`.
- **Transparent writes through the view (optional).** Pass `--instead-of-trigger` at setup
  to install an `INSTEAD OF INSERT/UPDATE/DELETE` trigger on the federation view that
  **routes by `context_type`**: AGENT rows go to the local table; shared types
  (`UNIVERSAL`/`GLOBAL`/`DOMAIN`/`SYSTEM`) go to the foreign shared table. Application code
  then writes to the single canonical name `agent_bootstrap_context` and the trigger puts
  each row where it belongs.

Choose one model and document it; mixing direct writes and view writes is fine as long as
everyone knows the view route exists.

---

## 7. Schema changes and reconcile

**Mandatory after ANY change to a shared table in `shared_memory`.** `postgres_fdw` caches
each foreign table's column list at import time. A column added, dropped, renamed, or
retyped in `shared_memory` is **invisible** to every consumer until its foreign table is
re-imported. This is the recurring nova-mind#675 failure.

### Run reconcile

```bash
scripts/shared-memory/setup-shared-memory.sh reconcile \
  --target-db shared_memory \
  --consumer-dbs "agentA_memory agentB_memory agentN_memory"
```

For each consumer it: drops the federation view, drops and **re-imports** the foreign
tables (picking up the new column set), recreates the federation view, then **verifies
with a real read**.

### Verify with a real read — not DDL success

DDL running without error is **not** proof. The reconcile verifies by actually reading:

- the federation view resolves (query executes; an empty result is still valid),
- a concrete shared read (`WHERE context_type='UNIVERSAL'`) executes end-to-end through
  the foreign server,
- every other shared object reads.

A reconcile that "succeeded" on DDL but errors on a real read has **failed**.

### Worked example: the #675 rename + retype

1. Change the shared table:
   ```sql
   -- in shared_memory
   ALTER TABLE agent_bootstrap_context ADD COLUMN priority integer DEFAULT 0;
   ALTER TABLE ai_models ALTER COLUMN cost_tier TYPE varchar(40);
   ```
2. **Before reconcile**, a consumer cannot see the new column — the drift:
   ```sql
   -- in agentA_memory
   SELECT priority FROM shared_agent_bootstrap_context LIMIT 1;
   -- ERROR: column "priority" does not exist
   ```
3. Run `reconcile` for every consumer.
4. **After reconcile**, the new column reads and the retyped column reads, in every
   consumer. The real-read verification confirms it.

---

## 8. Migrating an existing source-DB setup

If you currently have one agent's database acting as the source (the asymmetric setup §2
warns against), migrate to canonical `shared_memory` **carefully and reversibly**:

1. **Inventory** every shared/federated object: shared tables, views, foreign tables,
   trigger functions, and the hooks/code that read them (the bootstrap-context hook, any
   turn-context or config-sync consumers). Audit for tables that are *copied* per agent but
   should be shared, and for same-named tables that are actually per-agent (do not migrate
   those).
2. **Create `shared_memory`** and copy the canonical shared rows from the current source,
   **leaving the source's AGENT rows behind**. Verify counts + checksums per context_type.
3. **Repoint one consumer at a time**, former source **last**. For each consumer, snapshot
   the bootstrap context a **real session** resolves **before**, repoint its foreign server
   at `shared_memory` and reconcile, then snapshot **after** and confirm the two are
   identical.
4. **Convert the former source DB last** into the same consumer shape (view + local AGENT
   table + foreign tables). This touches that host's live bootstrap path — schedule it with
   the owner present; no unannounced change.
5. **Nothing is dropped** from the former source until **all** consumers are verified on
   `shared_memory`.
6. Update schema-ignore config (nova-mind#608) and the installer to the single consumer
   shape; remove source-DB special-casing.

### Before/after bootstrap-context comparison

For each repointed consumer, compare what a real session resolves:

```sql
SELECT context_type, file_key, md5(content)
FROM agent_bootstrap_context
ORDER BY context_type, file_key, COALESCE(agent_name,'');
```

Run it before and after the repoint; the outputs must match exactly (modulo intentional
changes). Identical output is the acceptance test for that consumer.

---

## 9. Pitfalls

- **Quiet failures: a view that looks valid but breaks on write.** The federation view can
  `SELECT` fine while an `INSERT` through it errors (e.g. missing `INSTEAD OF` trigger, or
  a column the view's `UNION` does not expose). Test writes, not just reads, after any
  change.
- **Schema tools planning DROPs of FDW objects (nova-mind#608).** Schema-diff / migration
  planners that do not understand foreign servers, user mappings, and foreign tables will
  propose dropping them. Configure your schema-ignore (`pgschemaignore` or equivalent) to
  exclude: the FDW server, user mappings, foreign tables (`shared_*`, the shared `ai_*`),
  the federation view, and the local AGENT table — so the planner leaves the federation
  wiring alone.
- **Adding a new shared table.** Add it to `shared_memory` (with any protection trigger),
  grant the reader + consumer roles, add it to the script's `--shared-tables`/`--shared-views`
  list, then run `reconcile` for every consumer and verify with a real read. Do not
  hand-edit one consumer and forget the rest — that recreates the asymmetry.
- **Adding a new agent database.** Run `setup` for the new consumer only
  (`--consumer-dbs "newagent_memory" --consumer-roles "newagent"`), have the credential
  owner set its FDW mapping password, then `reconcile` it. Its shape is identical to every
  other consumer by construction.
- **FDW does not read `.pgpass`.** The mapping password is mandatory and separate from the
  consumer role's own `.pgpass` entry. Forgetting it produces `could not connect to server
  ... no password supplied` at import/read time.
- **Superuser bypass of protection triggers** (see §5) — do not assume the trigger
  constrains superuser agent roles.

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `could not connect to server "shared_memory_server" ... no password supplied` | FDW user mapping has no password (`postgres_fdw` ignores `.pgpass`) | Credential owner: `ALTER USER MAPPING FOR <role> SERVER shared_memory_server OPTIONS (ADD password '<reader pw>');` then `reconcile` |
| `column "<x>" does not exist` on a foreign table, but it exists in `shared_memory` | Foreign-table definition is stale (the #675 drift) | Run `reconcile` for that consumer; verify with a real read |
| `cannot drop foreign table ... because other objects depend on it` | The federation view depends on the foreign table | The reconcile drops the view first then the foreign table; if doing it by hand, drop the view, re-import, recreate the view |
| `permission denied for table agent_bootstrap_context` when the FDW connects | The reader role lacks `SELECT` on the shared objects in `shared_memory` | `GRANT SELECT ON <shared objects> TO <reader role>;` (setup does this; re-run setup or grant manually) |
| `relation "<shared table>" already exists` on re-run | Non-idempotent hand DDL, or a cloned-table name collision | Use the script (idempotent); if hand-editing, guard with `IF NOT EXISTS` / `to_regclass(...)` and rename satellite objects (sequence, pkey, indexes) off the canonical name |
| Reconcile "succeeded" but a session sees wrong/no context | DDL ran but the real read was never checked | Re-run reconcile (it verifies with a real read); manually run the before/after comparison in §8 |
| Agent writes to a shared row silently go nowhere | Writing to the view without an `INSTEAD OF` trigger | Install the routing trigger (`--instead-of-trigger`) or write directly to the correct underlying object |
| Two agents' `.pgpass`/mappings out of sync after a password change | Parallel credential writers raced | Route all credential writes through the single owner; re-sync the stale entry against the live role |

---

## See also

- `scripts/shared-memory/setup-shared-memory.sh` — the idempotent setup + reconcile script.
- `scripts/shared-memory/test-shared-memory.sh` — disposable-instance test harness
  (fresh setup, no-op re-run, the #675 reconcile, dry-run).
- `cognition/docs/cross-database-replication.md` — the older logical-replication approach
  (superseded for `agent_chat`); use **this** doc for sharing tables across agent DBs.
- nova-mind#675 (foreign-table drift), #608 (schema-ignore / FDW DROP plans), #718 (shared
  DOMAIN context), #320 (single shared DB for `agent_chat`).
