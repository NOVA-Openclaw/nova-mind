# Documentation Audit — nova-mind#543 (SE Run #513, Step 9, Technical Writing)

**Scope:** Document the entity-resolver pronouns + relationship-stats feature (commits `8ba578e`
feat + `bfdbe39` fix) and audit all project documentation against current source for staleness
introduced or exposed by this change.

**Branch:** `feature/543-entity-resolver-relationship-stats`.

---

## 1. Source Verified

Read in full before editing any docs:
- `relationships/lib/entity-resolver/resolver.ts` (`mapDbEntity()`, `getEntityProfile()` aggregate
  query, timezone-safe `last_seen`/`created_at` rendering)
- `relationships/lib/entity-resolver/types.ts` (`Entity`, `EntityProfile`,
  `EntityRelationshipStats`)
- `relationships/lib/entity-resolver/index.ts` (exports)
- `memory/plugins/turn-context/src/entity-resolver.ts` (`formatEntityContext()`,
  `resolveEntityContext()` timeout/race behavior, honorific-guard non-interaction)
- `database/schema.sql` (`entities.trust_level` column comment, actual column list)
- Both commit diffs (`git show 8ba578e`, `git show bfdbe39`)

## 2. Files Edited (and why)

| File | Reason |
|------|--------|
| `relationships/lib/entity-resolver/README.md` | Added `deviceId`/`ircUsername` to identifier list; documented `Entity`'s new optional `pronouns`/`trustLevel`/`lastSeen`/`createdAt` fields; rewrote `getEntityProfile()` section for its new `EntityProfile` (`{facts, stats}`) return type (was a bare `EntityFacts` map — breaking signature change); updated Types section with `EntityRelationshipStats`/`EntityProfile`; fixed a stale usage example reading `profile.timezone` directly. |
| `relationships/ARCHITECTURE-entity-resolver.md` | Updated `resolveEntity()`'s documented `Entity` return shape to include the four new optional fields; rewrote `getEntityProfile()` API reference for the new `EntityProfile` shape with full field semantics (`factCount` unfiltered, `lastMessage` nullable); updated the "Query Strategy" SQL example to show the actual `pronouns`/`trust_level`/`last_seen`/`created_at` columns and added a dedicated note explaining the `last_seen` timezone-shift bug and its fix (RS-062); fixed ~10 stale `profile.timezone`/`profile.communication_style`/`profile.expertise` usages across integration examples (now `profile.facts.*`) that would otherwise silently break under the new return type. |
| `relationships/README.md` | Added a relationship-stats/pronouns bullet under the Entity Resolver Library key-component description, pointing to the full API doc. |
| `relationships/CHANGELOG.md` | Added `## Unreleased` entries for #543: pronouns/trust/stats feature (Added), the `last_seen` timezone fix (Fixed), the `trust_level` column-comment change (Changed), and test coverage (Tests). |
| `memory/plugins/turn-context/README.md` | Updated the Entity Resolver subsystem table row to mention pronouns/trust/stats rendering; added a new "Entity Context Formatting" section documenting `formatEntityContext()`'s exact 3-line output format (header/stats/facts), the `'unknown'`-trust suppression rule, the zero-facts-suppression rule for the stats line, and the timeout/data-source split that lets pronouns/trust survive a `getEntityProfile()` timeout while the stats line does not. |
| `memory/docs/semantic-recall.md` | Updated the Entity Resolution section's illustrative output block to show pronouns + the new stats line (was missing both, would otherwise look like #543 was never applied to this integration point), with a pointer to the new turn-context README section for full rules. |
| `psyche/ARCHITECTURE-entities-users.md` | Corrected the `trust_level` column description, which asserted a closed enum of `owner/admin/user/unknown/untrusted` — the live `database/schema.sql` column comment (updated by #543's `8ba578e`) now explicitly documents it as free-text with no CHECK constraint. Clarified that the enum values are only meaningful to `confidence_helper.py`'s scoring table, not an enforced value set, and cross-referenced the new turn-context trust-suffix rendering. |
| `CHANGELOG.md` (root) | Added a full `### Batch: entity-resolver-relationship-stats-543` entry (Added/Fixed/Tests/Issues Closed), following the existing batch-entry convention used for #508/#522/#506, since those precedents document root-level, cross-cutting behavior changes at this granularity. |
| `tests/DOC-AUDIT-543.md` | This file. |

## 3. Files Audited — Already Correct, No Change Needed

| File | Why it's clean |
|------|-----------------|
| `relationships/CONTRIBUTING.md` | No `getEntityProfile()`/`Entity` shape documentation to go stale; general contribution guidance only. |
| `relationships/docs/algorithms.md` | Explicitly marked "design phase — not yet implemented" and unrelated to the resolver's actual shipped API; the design-phase types shown are not `EntityProfile`/`Entity`. |
| `relationships/docs/web-of-trust.md` | Its `trustLevel` field is an unrelated cert-vouch concept (`'full' \| 'limited' \| 'vouch-only'`), not `entities.trust_level`. Verified by reading the surrounding context — no accidental collision. |
| `relationships/docs/integration-guide.md` | Fixed the direct `profile.timezone`-style accesses (see edits above) — after those fixes, remainder of the doc (identifier lists, caching patterns, certificate/CA examples) is accurate. |
| `relationships/lib/entity-resolver/COMPLETED.md` | Dated historical completion snapshot (2025-02-08, Task #38, pre-dates #543 by over a year). Left as a historical record except for the one line reading `profile.timezone` directly, fixed since it would silently break if anyone copy-pasted it today. |
| `relationships/lib/entity-resolver/REFACTORING.md` | Same treatment as COMPLETED.md — historical Task #38 snapshot; fixed the one stale `profile.timezone, profile.communication_style` line for the same reason. |
| `database/schema-reference.md` | `entities` row still correctly lists 22 columns — #543 added no new columns (it only changed a column *comment*), so no count drift. Already-flagged staleness in this auto-generated file (agent_chat, portfolio tables, etc.) predates #543 and is out of scope. |
| `memory/docs/fact-judgement-model.md` | Its `trust_level`/confidence discussion concerns `confidence_helper.py`'s scoring table, not the turn-context rendering behavior #543 changed. Confirmed no reference to the injected-context format. |
| `memory/docs/SOURCE-AUTHORITY.md` | Same as above — `trust_level` confidence-scoring content is orthogonal to #543's display-layer change. Already carries its own (pre-existing, accurate) staleness caveats re: pre-#174 authority pipeline; not touched further here. |
| `memory/docs/memory-extraction-pipeline.md` | Single `trust_level` mention is about `confidence_helper.py` initial-confidence scoring, unrelated to #543. |
| `ARCHITECTURE.md` (root) | Mentions of `turn-context`/`entity-resolver`/`getEntityProfile()` are all high-level architecture pointers that don't assert a specific return shape or rendering format — not made stale by #543. |
| `memory/docs/database-schema-guide.md` | Its `entities` table SQL example was already a simplified/pre-existing illustration (missing `pronouns`, `trust_level`, and most real columns) that predates #543 and was never accurate to the live schema. Not a regression caused by this change — flagged as an out-of-scope pre-existing gap below rather than fixed here. |

## 4. Out-of-Scope Gaps Found (flagged for follow-up, not fixed here)

- **`memory/docs/database-schema-guide.md`'s `entities` table example is stale independent of
  #543** — it shows a minimal illustrative `CREATE TABLE entities` (6 columns: id, name, type,
  full_name, description, created_at/updated_at) that doesn't match the live 22-column schema at
  all (no `pronouns`, `trust_level`, `last_seen`, `nicknames`, etc., and even has columns like
  `description`/`updated_at` that don't exist on the real table). This predates #543 and is a
  general schema-guide accuracy issue, not something #543 introduced or worsened — recommend a
  separate doc-accuracy issue rather than expanding this PR's scope.

## 5. Consistency Check: `trust_level` Free-Text Semantics

Per the task brief's instruction to verify trust_level free-text semantics wherever documented:
confirmed consistent across `database/schema.sql` (column comment, updated by #543's `8ba578e`),
`relationships/ARCHITECTURE-entity-resolver.md` (new `Entity.trustLevel` doc), `memory/plugins/
turn-context/README.md` (new Entity Context Formatting section), and `psyche/
ARCHITECTURE-entities-users.md` (corrected in this pass). `memory/scripts/confidence_helper.py`'s
hardcoded five-value scoring table (`owner`/`admin`/`user`/`unknown`/`untrusted`) is unaffected by
#543 and continues to work as a *scoring* lookup with a default fallback for unrecognized values —
it does not enforce a closed set at the schema level, matching the corrected documentation.

## Conclusion

Documentation is now consistent with the merged `8ba578e`/`bfdbe39` behavior. No blocking gaps
remain in scope for #543. One pre-existing, unrelated staleness item is flagged in §4 for a
separate follow-up issue.
