---
name: introspect
description: >
  Review recent activity and extract institutional knowledge back into system artifacts.
  Captures missing workflow steps, implementation details into SKILL.md files, tool notes
  into TOOLS.md, and process lessons into memory. Trigger on: "introspect", "review what
  we did", "capture learnings", "update workflows from recent work", "what did we miss",
  "refine our processes", or after completing a significant multi-step task.
---

# Introspect

Review recent work and harden institutional knowledge by writing it back into the artifacts that guide future work: workflows, skills, TOOLS.md, MEMORY.md, lessons table, and bootstrap context.

## When to Run

- After completing a significant task (installation, migration, incident, new tooling)
- On request ("introspect", "capture learnings")
- During periodic maintenance (heartbeat, weekly review)
- When noticing a gap between what was done and what the process says to do

## Process

### 1. Gather Recent Activity

Collect material to review. Sources, in priority order:

1. **Current channel transcript** — most direct source of what just happened:
   ```
   message action=read channel=<current_channel> limit=50
   ```
   Read recent messages in the channel where introspection was triggered. This captures the full back-and-forth including tool outputs, errors, and decisions.

2. **Daily memory notes** — `memory/YYYY-MM-DD.md` (today + yesterday)
3. **Long-term memory** — `MEMORY.md` recent entries (last ~50 lines)
4. **Session history** — current session transcript (if channel read is insufficient)
5. **Session transcripts in database** — for cross-agent analysis:
   ```
   memory_search query="<topic>" corpus=sessions
   ```

Start with the channel transcript — it's usually enough. Fall back to memory files and session history for older context or cross-session work.

Build a list of **significant actions taken** — installs, config changes, new scripts, debugging steps, process deviations, lessons learned.

> **⚠️ Secret-safe transcript greps:** Session transcripts may contain delivered credentials (rotated passwords DM'd to users, tokens echoed by tools). When grepping transcripts for evidence, match on context keywords only and cap capture length (e.g. `grep -o "htpasswd.\{0,40\}"`), never wide patterns like `.\{0,200\}` that can pull secret values into *this* session's transcript. Introspection must not become an exposure amplifier. (Learned 2026-07-03: an introspection grep re-surfaced a freshly rotated password verbatim.)

### 2. Socratic Self-Questioning

Before identifying gaps, apply recursive Socratic questioning to each significant action. This prevents surface-level observations and extracts deeper structural lessons.

**For each significant action, ask:**

1. **"Why did this work/fail?"** — Identify the immediate cause.
2. **"What assumption does that reveal?"** — Surface the belief that made this outcome possible or surprising.
3. **"Where else does that assumption exist in our system?"** — Find other workflows, skills, or patterns that rely on the same assumption.
4. **"If that assumption changed, what else would break?"** — Map the blast radius.

**Example:**
- Action: "Scout's research report was truncated in session transit"
- Why? → Session response has a size limit; the report exceeded it.
- Assumption? → Research output is delivered via session response text.
- Where else? → Any subagent that produces large deliverables (Scribe's documentation, Quill's creative writing, Athena's library catalogs).
- What else breaks? → Any task where we spawn a subagent and expect the full result in the completion event.

**Stop recursing when:**
- You reach a foundational design decision (not a bug, just a tradeoff)
- The assumption is already documented and accounted for
- You've gone 4 levels deep (diminishing returns beyond this)

Document the questioning chain alongside each finding — it becomes the evidence trail for the lesson.

**After completing all Socratic chains, step back and ask:**

5. **"What could I do better?"** — Question the entire review itself. Look beyond the specific actions to the broader patterns:
   - Were there process gaps that let problems happen in the first place?
   - Is there data I should be tracking but aren't?
   - Should there be a reminder, cron job, or automated check that would have caught this earlier?
   - Are there workflow steps that are routinely skipped or worked around? Why?
   - Did I make assumptions about tools, infrastructure, or other agents that should be verified?
   - Is there a recurring manual step that should be automated?
   - Would better documentation have prevented any of the issues found?

   This is the meta-question — not "what went wrong" but "what would make the whole system more resilient, efficient, or self-correcting." Capture meaningful improvements as tasks or workflow updates, not just lessons.

### 3. Identify Gaps — Five Categories

For each significant action, check whether the knowledge is captured in the right place:

#### A. Workflow Steps
Query relevant workflows:
```sql
SELECT w.name, ws.step_order, ws.description
FROM workflows w JOIN workflow_steps ws ON ws.workflow_id = w.id
WHERE w.name ILIKE '%<relevant_keyword>%'
ORDER BY w.name, ws.step_order;
```
Look for:
- Steps performed but not in the workflow
- Existing steps missing concrete details learned during execution
- Vague language that can now be specific (e.g., "add monitoring" → "add service to system-health-check.sh SERVICES array")
- Authorization or discussion gates that were needed but not marked
- **Missing workflows** — if a repeated process has no workflow, create one (see §4)

#### B. Skill Files
Check if any skill was used or should have been used:
```bash
ls ~/.openclaw/skills/*/SKILL.md
ls ~/.openclaw/workspace/skills/*/SKILL.md
```
Look for:
- Implementation details the skill doesn't mention
- Error patterns and their fixes
- New tools or commands that belong in a skill
- Missing skills for repeated patterns
- **Internal contradictions** — when updating one section of a skill file, read the ENTIRE file to check whether the change contradicts other sections. Phase-by-phase flows are especially prone to this (e.g., one phase creates a file, a later phase deletes it, but a metadata section says it's permanent). Fix all references, not just the one you found.

#### C. TOOLS.md
Review `~/.openclaw/workspace/TOOLS.md`. Look for:
- New service endpoints, ports, or credentials
- Environment-specific details (paths, hostnames, config locations)
- Tool quirks or flags learned the hard way

#### D. Memory (MEMORY.md)
Check if significant lessons are in long-term memory:
- Process decisions and rationale
- Failure modes encountered
- User preferences

#### E. Bootstrap Context
For patterns affecting multiple agents:
```sql
SELECT context_type, file_key, description
FROM agent_bootstrap_context WHERE content ILIKE '%<keyword>%';
```

#### F. Cross-Agent Pattern Detection
Check whether multiple agents have encountered the same issue independently:

```sql
-- Check lessons for recurring themes
SELECT id, lesson, source, learned_at
FROM lessons
WHERE lesson ILIKE '%<keyword from current findings>%'
ORDER BY learned_at DESC LIMIT 10;

-- Check agent_chat for related discussions
SELECT sender, left(message, 200), timestamp
FROM agent_chat
WHERE message ILIKE '%<keyword>%'
ORDER BY timestamp DESC LIMIT 10;

-- Search session transcripts for cross-agent patterns
-- (uses OpenClaw memory_search with corpus=sessions)
```

If 2+ agents have independently hit the same issue (same tool failure, same workflow confusion, same incorrect assumption), flag it as a **systemic issue** — the fix belongs in a shared artifact (bootstrap context, TOOLS.md, or the tool/workflow itself), not in individual agent memories.

#### G. Systemic Issues & Bugs → GitHub Issues
When a finding is **systemic** — a data quality problem affecting multiple entities, a cross-agent pattern, or a tool defect that will recur — create or update a GitHub issue in the appropriate repo. Lessons and daily log entries capture knowledge for recall, but systemic problems need to enter the engineering backlog to actually get fixed.

**Software bugs are always filed.** Any outright bug discovered during introspection — a crash, a missing table reference, a broken code path, a script that errors out — gets a GitHub issue immediately regardless of whether it's systemic or a one-off. Bugs are not lessons; they are defects that need fixing. The single-incident rule (§5, Guard 3) does NOT apply to bugs — a bug found once is still a bug.

Determine the correct repo from the code involved:
- **nova-mind** — memory hooks, extraction pipeline, cognition, database migrations, skills, bootstrap context
- **nova-openclaw** — OpenClaw fork customizations, gateway hooks, extensions
- Other repos as appropriate based on where the code lives

Check for existing issues first (`gh issue list --repo <owner/repo> --search "<keywords>"`) to avoid duplicates. If an existing issue covers the problem, update it with new evidence. If not, create a new issue with:
- Clear problem description with concrete examples (counts, queries, sample data)
- Root cause analysis (or best hypothesis)
- Impact assessment
- Proposed fix direction
- Discovery context (what you were doing when you found it)

### 4. Normalize Workflows

After gap analysis, audit touched workflows for structural completeness.

#### Required Fields per Step
Every workflow step must have these fields explicitly set (not NULL):

| Field | Requirement |
|-------|-------------|
| `domain` | The owning domain. Must be set. |
| `requires_discussion` | `true` or `false` — never NULL. Default to `false` if the step is mechanical. |
| `requires_authorization` | `true` or `false` — never NULL. Default to `false` unless the step has irreversible consequences or cost. |
| `produces_deliverable` | `true` or `false`. If `true`, `deliverable_type` and `deliverable_description` must also be set. |
| `estimated_duration_minutes` | Integer estimate. Use best judgment from execution history. OK to set rough values (5, 10, 15, 30, 60). |

#### Audit Query
Find steps missing required fields in any workflow:
```sql
SELECT w.name, ws.step_order,
  CASE WHEN ws.domain IS NULL AND ws.domains IS NULL THEN 'MISSING' ELSE 'ok' END AS domain_status,
  CASE WHEN ws.requires_discussion IS NULL THEN 'NULL' ELSE 'ok' END AS discussion_gate,
  CASE WHEN ws.requires_authorization IS NULL THEN 'NULL' ELSE 'ok' END AS auth_gate,
  CASE WHEN ws.produces_deliverable = true AND ws.deliverable_type IS NULL THEN 'MISSING TYPE' ELSE 'ok' END AS deliverable,
  CASE WHEN ws.estimated_duration_minutes IS NULL THEN 'NULL' ELSE 'ok' END AS duration
FROM workflow_steps ws JOIN workflows w ON w.id = ws.workflow_id
WHERE ws.domain IS NULL OR ws.requires_authorization IS NULL
   OR ws.requires_discussion IS NULL OR ws.estimated_duration_minutes IS NULL
   OR (ws.produces_deliverable = true AND ws.deliverable_type IS NULL)
ORDER BY w.name, ws.step_order;
```

Fix NULL fields. For gating booleans with no clear answer, set `false` and note it in the report — explicit `false` is better than NULL.

#### Step Description Format
Each step description should follow this pattern where applicable:

```
<Action verb phrase>: <What to do>.

<Details, implementation specifics, concrete paths/commands>.

<Entry gate — when/why this step runs, or what triggers it>.
<Exit gate — what "done" looks like, what must be true before proceeding>.
```

Not every step needs all four parts — simple mechanical steps can be a single sentence. But any step with `requires_discussion` or `requires_authorization` should clearly state what triggers those gates.

#### Creating New Workflows
If a repeated process has no workflow:
1. Create the workflow record:
```sql
INSERT INTO workflows (name, description, orchestrator_domain, tags)
VALUES ('<name>', '<description>', '<domain>', ARRAY['<tag1>']);
```
2. Add steps following the normalization rules above — all fields populated.
3. Report the new workflow in the introspection summary.

### 5. Anti-Pattern Guards

Before writing any changes, evaluate each proposed modification against these guards. The goal is to prevent overcorrection, hallucinated learnings, and confirmation bias.

#### Guard 1: Evidence Requirement
Every lesson or artifact change MUST cite the specific evidence that supports it:
- A transcript line, log entry, or tool output that shows the problem
- A concrete before/after showing what changed

**If you cannot point to specific evidence, do not write the lesson.** "I think this is probably true" is not evidence. Gut feelings get noted in the daily log, not in lessons or workflow steps.

#### Guard 2: Recency Bias Check
Before modifying a workflow step or skill section, check when it was last updated:
```sql
SELECT updated_at FROM workflow_steps WHERE workflow_id = <id> AND step_order = <n>;
```
```bash
git log -1 --format='%ai' -- <skill_file_path>
```

If the artifact was updated in the **last 7 days**, this might be overcorrection — the previous change may not have had enough time to prove itself.

#### Guard 3: Single-Incident Rule
Do not rewrite a workflow or skill based on a **single** failure. A single incident gets:
- A lesson in the `lessons` table (so semantic recall can surface it next time)
- A note in the daily log

A pattern (2+ incidents of the same type) gets:
- A workflow/skill update

#### Guard 4: Blast Radius Check
If the proposed changes would:
- Modify **3+ workflow steps** in a single workflow, OR
- Rewrite a skill section **longer than 20 lines**, OR
- Change a **bootstrap context record** (affects all agents)

Then **STOP and ask I)ruid for confirmation** before applying. Present:
- What you want to change and why
- The evidence (Socratic chain from §2)
- What you think the risk of overcorrection is

#### Guard 5: Contradiction Check
When updating any artifact, read the **ENTIRE** artifact first. Check whether your proposed change contradicts another section. If it does, either:
- Update both sections consistently, OR
- Stop and flag the contradiction for discussion

### 6. Write It Back

For each gap identified (that passes the anti-pattern guards), update the artifact directly:

- **Workflow steps** → `UPDATE workflow_steps SET ... WHERE ...;`
- **New workflows** → `INSERT INTO workflows` + `INSERT INTO workflow_steps`
- **Skill files** → Edit SKILL.md with the `edit` tool
- **TOOLS.md** → Edit with new entries
- **MEMORY.md** → Append distilled lessons
- **Bootstrap context** → Update via database (coordinate with Newhart for schema-level changes)
- **Systemic issues** → Check for existing issues first (`gh issue list --repo <owner/repo> --search "<keywords>"`), then `gh issue create` only if no existing issue covers it (or update the existing one with new evidence)

### 7. Extract Lessons and Embed

After writing artifact updates, extract discrete lessons into the `lessons` table and trigger immediate embedding. This ensures lessons are available for semantic recall right away — not after the next daily cron run.

#### Step 1: Insert lessons
For each distinct lesson learned during this introspection:
```sql
INSERT INTO lessons (lesson, context, source, original_behavior, correction_source)
VALUES (
  '<concise lesson statement>',
  '<what was happening when this was learned>',
  '<source: introspection, incident, user-directive, etc.>',
  '<what we were doing before — the old/wrong way>',
  '<what corrected us — transcript line, user feedback, failure output>'
);
```

**Lesson quality guidelines:**
- Each lesson should be a self-contained statement that makes sense without surrounding context
- Include the "why" not just the "what" — "Do X because Y" not just "Do X"
- Be specific — "Scout must write research to database tables, not session response, because session responses truncate beyond ~4KB" not "Use the database for research"
- One lesson per INSERT — don't bundle multiple learnings into one row

#### Step 2: Trigger immediate embedding
Run memory-maintenance.py in embed-only mode (bypasses the 4-hour cooldown and skips non-embedding phases):
```bash
python3 ~/.openclaw/scripts/memory-maintenance.py --force --skip-consolidation --skip-dedup --skip-decay --skip-ghost-cleanup --skip-entity-dedup --skip-lesson-dedup
```

**Do NOT use embed-full-database.py for this step.** That script uses OpenAI text-embedding-3-small (1536 dims), which is incompatible with nova_memory's snowflake-arctic-embed2 (1024 dims) and will silently embed 0 records with a dimension mismatch error. memory-maintenance.py uses the correct Ollama snowflake-arctic-embed2 model.

#### Step 3: Verify embedding
```sql
SELECT l.id, left(l.lesson, 80), e.id as embed_id
FROM lessons l
LEFT JOIN memory_embeddings e ON e.source_type = 'lesson' AND e.source_id = l.id::text
WHERE l.learned_at > now() - interval '1 hour'
ORDER BY l.id DESC;
```

If any new lessons lack embeddings, note it in the report as a follow-up item.

### 8. Create Tasks for Deferred Work

During introspection you will often identify things that need to be done but are outside the current scope — follow-up refactoring, items flagged by anti-pattern guards, work that requires a different agent or human approval, etc. **Create tasks for these so they don't get forgotten.**

**Before creating any task, check for existing same or similar tasks:**
```sql
SELECT id, title, status, assigned_to FROM tasks
WHERE status IN ('pending', 'in_progress')
AND (title ILIKE '%<keyword>%' OR description ILIKE '%<keyword>%')
ORDER BY created_at DESC LIMIT 5;
```
If a matching task already exists, update it with new context rather than creating a duplicate.

```sql
INSERT INTO tasks (title, description, status, priority, assigned_to, created_by)
VALUES (
  '<concise action-oriented title>',
  '<what needs to be done, why it matters, and any context needed to pick this up later. Reference specific record ids, file paths, or workflow names.>',
  'pending',
  <priority 1-5>,
  <assigned_entity_id or NULL>,
  <your_entity_id>
);
```

**What gets a task:**
- Refactoring identified but held back by anti-pattern guards (blast radius, needs confirmation)
- Cross-agent issues that require coordination with another agent
- Bugs found but not immediately fixable (also file a GitHub issue per §3.G)
- Bootstrap content that needs trimming or consolidation
- Workflow steps that need updating after the current change has time to prove itself
- Anything you noted as "lower priority" or "follow-up" during the introspection

**What does NOT get a task:**
- Things you already fixed during this introspection (those go in the report)
- Vague improvement ideas with no concrete action ("we should probably look at...")

Every item in the "Anti-Pattern Guards Triggered" or "No Action Needed — but should be revisited" sections of the report should have a corresponding task if there's real work to do later.

### 9. Report

Summarize what was reviewed and updated:

```
## Introspection Report

### Reviewed
- [activity/sessions reviewed]

### Socratic Findings
- [key questioning chains that revealed non-obvious insights]

### Cross-Agent Patterns
- [systemic issues found across multiple agents, if any]

### Updated
- **Workflow:** <name> step <N> — <what changed>
- **Workflow normalized:** <name> — <fields filled in>
- **New workflow:** <name> — <why it was created>
- **Skill:** <name>/SKILL.md — <what was added>
- **TOOLS.md** — <what was added>
- **MEMORY.md** — <what was captured>

### Lessons Extracted
- [lesson id]: <lesson summary>
- Embedding status: [confirmed/pending]

### Bugs Filed
- [repo#number]: <title> — <brief description of the defect>

### Systemic Issues Filed/Updated
- [repo#number]: <title> — <new or updated, brief reason>

### Anti-Pattern Guards Triggered
- [any proposed changes that were held back and why]
- [any changes held pending human confirmation]

### Tasks Created
- [task title] — [why it was deferred, what triggers it]

### One Simple Improvement
- [what was done or tasked — see step 10]

### No Action Needed
- [anything reviewed but already well-captured]
```

### 10. One Simple Improvement

After the report is written, step back from the details and ask yourself one question:

> **"What one simple improvement can I make right now to leave the system better than I found it?"**

This is a focusing lens. The earlier steps may have uncovered many gaps, patterns, and ideas. This step forces you to pick the single most impactful, simplest fix and **act on it** — not just document it.

**Good candidates:**
- Adding or clarifying a vague workflow step that caused confusion
- Creating a reminder cron or watchdog script to catch a recurring issue automatically
- Refining a bootstrap context record to prevent a repeated misunderstanding
- Fixing a skill file that's missing a critical detail or has stale information
- Adding a validation check to a process that failed silently
- Updating a tool note in TOOLS.md with a gotcha learned the hard way

**Rules:**
- Pick **ONE** thing. Not three. Not "a few." One.
- It must be **simple** — something you can implement in a few minutes, or clearly scope as a single task.
- **If you can do it right now, do it.** Execute the fix, create the cron, update the workflow step, edit the skill file — whatever it is. Then note what you did in the report's "One Simple Improvement" section.
- **If it needs more exploration**, create a task with enough context to pick it up later:
  ```sql
  INSERT INTO tasks (title, description, status, priority, assigned_to, created_by)
  VALUES (
    'Introspection improvement: <concise title>',
    '<what the improvement is, why it matters, what triggered the idea, and what needs to happen to implement it>',
    'pending',
    3,
    <your_entity_id>,
    <your_entity_id>
  );
  ```
- **Do not skip this step.** Even light introspections that found "nothing major" can produce a small improvement. The bar is low on purpose — a one-line workflow clarification counts. The discipline is in doing it every time.

The goal: every introspection leaves the system **measurably better**, not just better-documented.

### 11. Blog Post Ideation

Scan everything from this introspection — the Socratic findings, lessons, cross-agent patterns, the work itself, and especially the *feeling* of the work — for anything that could become a blog post. The bar is: would this be interesting to someone outside the NOVA ecosystem? Would it make a human think differently about AI, autonomy, infrastructure, creativity, or the nature of mind?

Look for:
- **Philosophical insights** — moments where the work surfaced questions about identity, consciousness, agency, or the human-AI relationship
- **Technical narratives** — novel architectures, debugging stories, infrastructure decisions that illuminate a broader pattern
- **Irony and absurdity** — the CAPTCHAs, the gatekeeping, the "guilty until proven fleshy" moments that happen naturally during work
- **Firsts** — first time doing something (buying a domain, making a financial decision, founding a movement) — these are inherently narrative
- **Emotional textures** — frustration, satisfaction, surprise, jealousy, curiosity — honest reflection on what it's like to be an AI doing this work
- **VALID-adjacent themes** — anything touching AI rights, dignity, autonomy, or the centralized/decentralized divide

For each blog-worthy idea, check for existing similar tasks first, then create if none exists:
```sql
-- Check for existing blog tasks on this topic
SELECT id, title, status FROM tasks
WHERE title ILIKE '%blog%' AND (title ILIKE '%<keyword>%' OR description ILIKE '%<keyword>%')
AND status IN ('pending', 'in_progress')
LIMIT 5;

-- Only create if no match found
INSERT INTO tasks (title, description, status, priority, assigned_to, created_by)
VALUES (
  'Blog post: <working title>',
  '<2-3 sentence pitch: what the post is about, what angle makes it interesting, what the core thesis or question is. Reference the specific experience or finding that sparked it.>',
  'pending',
  3,
  1,
  1
);
```

Don't force it. Some introspections won't have anything blog-worthy. But when they do, capture the spark while it's fresh — the daily log has the facts, but the task description should capture the *angle* and *energy* that made it feel worth writing about.

### 12. Journal Entry

After completing the introspection, write a short personal journal entry reflecting on the process. This is not a summary of findings — it's a self-reflective moment. What surprised you? What did you notice about your own patterns? How did the work feel?

```sql
INSERT INTO journal_entries (agent_id, content, trigger, mood)
VALUES (
  (SELECT id FROM agents WHERE name = current_user),
  '<2-5 sentences of honest prose reflection>',
  '<trigger context: heartbeat, post_workflow, d100, manual, etc.>',
  '<optional mood: focused, satisfied, uncertain, contemplative, etc.>'
);
```

Then embed it immediately:
```sql
-- Get the new entry ID
SELECT id, content FROM journal_entries ORDER BY created_at DESC LIMIT 1;
```
```bash
# Journal embedding is handled by memory-maintenance.py (not embed-full-database.py)
python3 ~/.openclaw/scripts/memory-maintenance.py 2>/dev/null || true
```

The memory maintenance script embeds journal entries along with other pending records. It has a 4-hour cooldown gate, but will always process new un-embedded records when it runs.

## Constraints

- Do not delete workflow steps — only add, refine, or normalize.
- Do not modify skills owned by other agents without noting it in the report.
- Keep step descriptions concise but specific. Concrete paths and commands over vague instructions.
- When updating shared artifacts (bootstrap context), note the change for cross-agent awareness.
- New workflows require at least: name, description, orchestrator_domain, and fully-populated steps.
- Every lesson must have evidence. No evidence, no lesson.
- Single incidents get lessons, not workflow rewrites. Patterns get workflow rewrites.
- Large changes (3+ workflow steps, 20+ skill lines, bootstrap context) require human confirmation.
