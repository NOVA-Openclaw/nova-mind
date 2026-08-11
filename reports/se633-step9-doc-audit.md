# SE Run #633 — Step 9 (Technical Writing) Documentation Audit

**Branch:** `feature/issue-548-reply-to-param` @ 30e56e5
**Scope:** Document nova-mind#548 (`send_agent_message()` `reply_to` param + atomic insert), #569 (installer agent_chat provisioning), #403 (TS pg-env per-field precedence parity), plus a full drift audit of project documentation vs. source.

**Report location choice:** `reports/` was used per the task brief's explicit fallback instruction ("pick reports/ if tests/ feels wrong, state choice") — this is a workflow/audit artifact, not a test-case design document, so `tests/DOC-AUDIT-548.md` felt like the wrong home for it.

---

## 1. Docs Updated (with why)

| File | Why |
|---|---|
| `psyche/ARCHITECTURE-agent-chat.md` | Primary architecture doc for `agent_chat`. Updated table schema (`expires_at`), `send_agent_message()` signature (5 args, named-arg example), `session_user` sender-spoofing-proof validation, self-address guard, `postgres`-ownership rationale, rewritten trigger semantics (`current_user = 'postgres'` replacing `bypass_gate`), `markMessageRouted()` terminal-status guard, and Security Considerations section. |
| `database/schema-reference.md` | Added a dated note (top-of-file, alongside existing #320/#414/#474/#485/#506 audit notes) documenting the current 5-arg `send_agent_message()` signature, since agents have historically looked here first. Corrected `agent_chat` column count 6→7 (`expires_at` added). |
| `memory/docs/database-config.md` | Largest single update. Corrected the Resolution Order section: TypeScript now has per-field section-over-ENV precedence identical to Python (#403 closed this gap — the doc previously said TS/Bash still let ENV win). Added a new "Installer-Provisioned agent_chat Database Target (nova-mind#569)" section documenting `agentChatDatabase`, the resolution order, the production-mutation refusal guard, and the schema-then-migrations apply sequence. Updated the "How It Fits Together" diagram. |
| `memory/README.md` | Same TS-parity correction as database-config.md — the "Resolution order" section said TS/Bash still let ENV win over a section; #403 fixed TS. |
| `memory/CHANGELOG.md` | Appended an "Amended (#403)" note to the existing #405 entry, since #403 completes the cross-language parity that entry's closing sentence flagged as future work. |
| `memory/INSTALLATION.md` | Added a "Recent Changes" entry for 2026-08-11 (#548/#569/#403) summarizing the installer-facing changes, consistent with the file's existing dated-entry convention. |
| `memory/docs/database-schema-guide.md` | Updated the `agent_chat` table schema block (added `expires_at`), the "How inter-agent chat works" numbered list (session_user validation, self-address guard), and added a reply_to+TTL named-argument example. |
| `cognition/docs/installation.md` | Updated the `agent_chat` provisioning callout: mentions `agentChatDatabase`, the installer now applies migrations automatically (previously said schema.sql was applied "separately... not by this installer" — now false), added `expires_at` to the illustrative `CREATE TABLE`, and pointed to the migrations directory for manual setups. |
| `cognition/README.md` | Corrected a stale claim that `agent_chat` schema is "applied separately by `scripts/agent-chat-migration/migrate.sh`... not by this installer" — this has been false since #548/#569 landed automatic schema+migration application in `agent-install.sh`. |
| `cognition/CHANGELOG.md` | Added an "Unreleased" entry (`### Fixed (#548/#569/#403 ...)`) summarizing the `cognition/`-specific pieces (schema.sql sync, channel.ts atomic insert, TS pg-env parity, installer guard), consistent with the file's existing per-issue subsection convention. |
| `scripts/agent-chat-migration/README.md` | Added a top-of-file callout clarifying this is now the *historical* one-shot #320 cutover runbook, and that day-to-day schema evolution goes through `database/agent-chat/migrations/*.sql` (applied automatically by the installer). Corrected an initial draft claim that `agentChatDatabase` "supersedes" the nested `agent_chat` section — they serve different purposes (installer target vs. runtime credentials) and both remain relevant. |
| `skills/agent-ecosystem/SKILL.md` | Added a `p_reply_to` usage example to the peer-messaging section so agents actually discover the new capability when reading this skill (it's the most commonly-read agent_chat doc). |
| `CHANGELOG.md` (root) | Added a full new batch entry (`agent-chat-reply-to-548`) at the top of the file, following the existing `### Batch: <name>-<issue> (Issue #N)` convention, covering all three issues (#548, #569, #403) with Added/Fixed/Migrations/Tests/Issues-Closed subsections. |

## 2. Docs Found Stale and Corrected

Beyond the "why" column above, the specific stale claims found and fixed:

1. **`memory/docs/database-config.md` + `memory/README.md`**: Both said "TypeScript's `loadPgEnv()` still let ENV win over the section (TS parity fix tracked in #403)" — #403 is the branch under audit, i.e. **already fixed**, not still tracked. This was the most significant piece of drift found, since it directly contradicted the code this SE run introduced.
2. **`cognition/docs/installation.md`** and **`cognition/README.md`**: Both said `agent_chat` schema is applied "separately... not by this installer" — false as of #548 (`_apply_agent_chat_migrations` in `agent-install.sh` now applies `database/agent-chat/schema.sql` and everything under `database/agent-chat/migrations/` automatically, every run).
3. **`database/schema-reference.md`**: `agent_chat` listed at 6 columns; live/current schema has 7 (`expires_at` added in #548).
4. **`psyche/ARCHITECTURE-agent-chat.md`**: Described `send_agent_message()` as 3-arg, described the trigger as gated on a `bypass_gate` session variable (removed in #548's rewrite), and claimed sender spoofing "requires calling the function with a false p_sender value" without noting that #548 closed that gap via the `session_user` check.

## 3. Docs Flagged But Not Fixed (with reason)

None found in-scope for this audit that warranted a flag without a fix — every drift item identified above was corrected directly, since all were surgical, low-risk corrections (signature/precedence facts, not architectural narrative). No large architectural drift was found that would warrant flag-only treatment per the task brief's guidance.

One adjacent, pre-existing flag (not touched, not caused by this branch, left as-is): `database/schema-reference.md`'s file-level scope note already documents several outstanding drift items from prior audits (#414/#474/#485/#506) — `entity_credibility` undeclared in `database/schema.sql`, `motivation_d100`/`user_domains` missing rows, etc. These are unrelated to #548/#569/#403 and were not re-flagged or touched.

## 4. Docs Verified Clean (no changes needed)

Checked against the branch's actual diffs and found accurate/unaffected:

- `cognition/docs/shell-environment.md` — despite appearing in the task brief's priority list for the pg-env precedence contract, this file is entirely about the `BASH_ENV` mechanism (shell function/alias loading for non-interactive `exec`), not PostgreSQL config resolution. No `postgres.json`/`pg-env`/`agent_chat` content exists in it. Confirmed via full-file grep — false positive in the brief's priority list, not an omission.
- `cognition/docs/cross-database-replication.md` — already carries a clear top-of-file "Superseded for `agent_chat` by nova-mind#320" banner; its `agent_chat` column examples (`id, sender, message, recipients, reply_to, timestamp`) predate `expires_at` but the doc is explicitly historical/reference-only for replication mechanics, not a live schema reference. Left untouched per its own scope disclaimer.
- `cognition/ISSUE-147-agent-chat-db-auth-docs.md`, `cognition/ISSUE-148-agent-chat-db-permissions.md` — both already carry "Superseded by #320" / "Status note (post-#320)" banners and describe permission/setup concerns orthogonal to the function signature. No changes needed.
- `cognition/ISSUE-149-agent-chat-outbound-delivery.md`, `cognition/ISSUE-149-test-cases.md` — historical issue/test-case docs using 3-arg `send_agent_message()` calls in illustrative examples; still valid since args 4–5 are optional with defaults, and these docs don't claim the 3-arg form is the *only* form.
- `cognition/docs/implementation-notes.md`, `cognition/docs/agent-workflow-language.md`, `ARCHITECTURE.md` (root), `motivation/ARCHITECTURE.md`, `motivation/scripts/README.md`, `relationships/ARCHITECTURE-entity-resolver.md`, `relationships/CONTRIBUTING.md`, `relationships/README.md` — all reference `send_agent_message()`/`agent_chat`/pg-env in illustrative code samples or architecture summaries that remain accurate (either using the backward-compatible 3-arg form, or — for `relationships/`'s `resolver.ts` — not using a `section` parameter at all, so the #403 fix doesn't change its documented behavior).
- `memory/docs/deployment-setup-guide.md`, `memory/docs/semantic-search-guide.md`, `memory/docs/daily-log-generation.md`, `memory/ARCHITECTURE.md`, `memory/docs/README.md` — `agent_chat` references are either 3-arg illustrative examples or already correctly describe the #320 dedicated-database architecture; unaffected by #548/#569/#403.
- `cognition/focus/bootstrap-context/hook/HOOK.md`, `cognition/focus/bootstrap-context/docs/MANAGEMENT.md`, `cognition/focus/bootstrap-context/docs/STAGING_TESTS.md` — these describe the `bootstrap` section's per-field precedence, which was *already* correct pre-#403 for the `bootstrap-context` hook specifically, because `handler.ts` dynamically imports `~/.openclaw/lib/pg-env.ts` at runtime (the *deployed* copy, which #403 also updates) — confirmed via `TC-30` in `memory/lib/pg-env.test.ts` that the fix applies generically to any section, not just `agent_chat`. No changes needed; these docs' "per-field" claim was accurate before this branch too, just not universally true across all TS callers until now (which is exactly what the `database-config.md`/`memory/README.md` fixes above correct).
- `scripts/agent-chat-migration/audit_rollout.py`'s docstring/behavior — confirmed it reads the nested `agent_chat` section (not `agentChatDatabase`), so the README correction in section 1 above (clarifying the two keys serve different purposes) is accurate and doesn't require a corresponding code change.
- `tests/`, `reports/`, `TEST-DESIGN-*.md` — excluded from this audit per the task brief's explicit "do NOT edit" list.

## Summary

- **Issues documented:** #548, #569, #403 (all three landed on this branch)
- **Files changed:** 13 documentation files + this audit report
- **Stale content found and fixed:** 4 distinct claims (enumerated in section 2), the most significant being the TS-pg-env-parity self-contradiction in two files
- **Architectural drift flagged without fix:** none new; pre-existing `database/schema-reference.md` drift items from prior audits noted but not touched (out of scope for this branch)
