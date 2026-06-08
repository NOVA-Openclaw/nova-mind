# Confidence-Check Plugin

> *Confidence is earned,*
> *not assumed — verify, revise,*
> *then speak with assurance.*
>
> — Quill

An OpenClaw plugin that evaluates response confidence before delivery via a mandatory two-phase pipeline: self-verification followed by external LLM evaluation. Hooks into `before_agent_finalize`.

**Issues:** #75 (initial), #272 (SDK migration, citation verification, contradiction detection, 85% threshold), #312 (mandatory Phase 1 self-verification), D1–D7 (QA fixes)

---

## Two-Phase Architecture

### Phase 1 — Self-Verification (priorAttempts === 0, always runs)

The model is asked to verify its own response before any external evaluation. No heuristic pre-screen, no LLM call — the hook immediately returns a revision action that prompts the model to check:

1. **TRUTHFULNESS** — Are all claims factual?
2. **SOURCES** — Are cited sources, file paths, and URLs real and actually verified?
3. **ASSUMPTIONS** — What hidden assumptions haven't been stated?
4. **KNOWLEDGE BOUNDARIES** — What is known vs. inferred vs. guessed?
5. **SELF-CONSISTENCY** — Does the response contradict anything said earlier in the conversation?

Phase 1 fires on **every response**, including trivially correct ones. This is intentional — the cost of self-verification is lower than the cost of occasional undetected errors.

**Toggle:** Phase 1 can be disabled by setting `self_verification_enabled: false` in `CONFIG` (source: `src/index.ts`). When disabled, the plugin starts at Phase 2 for all invocations.

### Phase 2 — External Evaluation (priorAttempts 1+)

After self-verification, an external LLM evaluator scores the revised response:

1. **Heuristic pre-screen** — Count hedging phrases (density), unsupported assertions. These are signals forwarded to the LLM — they are **not** used as auto-pass shortcuts (auto-pass was removed in #312).
2. **Citation verification** — Extract URLs, file paths, code references, and doc references from the response; cross-reference against tool calls in `event.messages`. Unverified citations forwarded to the LLM as negative confidence signals.
3. **Self-contradiction detection** — Extract prior assistant messages (last `max_prior_messages`) and include them in the LLM prompt. User messages are intentionally excluded — we detect self-contradictions only, not disagreements with user statements.
4. **LLM scoring** — Call `api.runtime.llm.complete()` (SDK helper, no raw HTTP, no API key management). Returns `{ confidence: 0–100, concerns: [...], reasoning_strategies: [...] }`.
5. **Decision** — If `confidence ≥ threshold (85%)`: PASS, cleanup state. If below: return Socratic revision instruction.

If the LLM call fails:
- High hedging density (≥ 0.08): fallback confidence = 40 → triggers revision
- Borderline hedging: allow finalization (log warning)

Phase 2 runs up to `max_external_revision_attempts` (default: 2) times before the framing pass.

### Phase 3 — Framing Pass (max_external_revision_attempts exhausted)

When the response still hasn't reached the confidence threshold after all external revision cycles, the hook issues a framing instruction:

> "I'm not fully confident about this, but..."

The following invocation (post-framing) allows finalization and cleans up per-run state from the `retryAttempts` Map.

---

## State Machine

```
priorAttempts === 0  →  Phase 1: Self-verification revise (always fires)
priorAttempts === 1  →  Phase 2: External evaluator; revise if confidence < 85%
priorAttempts === 2  →  Phase 2: External evaluator; revise if confidence < 85%
priorAttempts === 3  →  Phase 3: Framing pass (max_external exhausted)
priorAttempts === 4  →  Post-framing: allow finalization, cleanup
```

**Maximum hook invocations per run:** 5 (1 self-verify + 2 external + 1 framing + 1 post-framing)

Per-run state is tracked in a module-level `Map<string, number>` keyed by `idempotencyKey = "confidence-${runId}"`. The map entry is deleted on PASS (D3 fix) or post-framing cleanup.

---

## Configuration

### Required OpenClaw Config

Add the following to `~/.openclaw/openclaw.json`:

```jsonc
{
  "plugins": {
    "entries": {
      "confidence-check": {
        "hooks": {
          "allowConversationAccess": true
        },
        "llm": {
          "allowModelOverride": true,
          "allowedModels": ["deepseek/deepseek-v4-flash"]
        }
      }
    }
  }
}
```

| Config Key | Required | Effect if missing |
|---|---|---|
| `hooks.allowConversationAccess` | **Required** | `event.lastAssistantMessage` and `event.messages` not populated — hook skips evaluation entirely |
| `llm.allowModelOverride` | **Required** | `api.runtime.llm.complete()` model override blocked — Phase 2 LLM call fails |
| `llm.allowedModels` | **Required** | Must include the evaluation model. Without it, model override is rejected even if `allowModelOverride: true` |

### Hardcoded Defaults (`src/index.ts` — `CONFIG` object)

| Key | Default | Notes |
|---|---|---|
| `confidence_threshold` | `85` | Raised from 70 in #272 |
| `max_external_revision_attempts` | `2` | External evaluation passes only (excludes Phase 1) |
| `self_verification_enabled` | `true` | Set to `false` to skip Phase 1 and go directly to Phase 2 |
| `hedging_density_pass_threshold` | `0.02` | Signal forwarded to LLM — **not** an auto-pass shortcut |
| `hedging_density_fail_threshold` | `0.08` | Above this → heuristic fallback confidence=40 on LLM error |
| `evaluation_model` | `deepseek/deepseek-v4-flash` | Used by `api.runtime.llm.complete()` |
| `max_prior_messages` | `10` | Window for contradiction detection (keeps prompt size bounded) |

---

## Installation

The plugin is built and installed by the `nova-mind` unified installer (`agent-install.sh`):

```bash
# From nova-mind repo root
bash agent-install.sh
```

The installer runs `npm install`, compiles TypeScript, and copies `dist/index.js` to `~/.openclaw/plugins/confidence-check/`.

To build manually:

```bash
cd cognition/metacognition/confidence-check
npm install
npm run build   # npx tsc
```

---

## Citation Verification

The plugin extracts and verifies four citation types from the response text:

| Type | Pattern | Verification method |
|---|---|---|
| `url` | `https?://...` | `web_fetch` or `web_search` tool call with matching URL or domain |
| `file_path` | `/path/...`, `~/path/...`, or `file.ts` (with recognized extension) | `read` tool call, or `exec` using file-reading commands (cat, grep, head, tail, sed, less, awk, wc, diff, find) |
| `code_reference` | `` `path/to/file.ts` `` (backtick-wrapped, file-like) | Same as `file_path` |
| `doc_reference` | "according to...", "based on...", "the docs say..." | `pdf` tool call (strong: any doc), or keyword match against web/read tool calls |

Conversational back-references ("as I mentioned earlier", "as we discussed", "stated above") are filtered out and not captured as citations.

Deduplication is enforced — the same citation value is never extracted twice.

---

## Tool Call Format Support

The plugin parses tool calls from `event.messages` in three formats:

- **Format 1 (OpenClaw):** `{ role: "tool", name: "...", content: "..." }`
- **Format 2 (Claude):** Content array with `{ type: "tool_use", name: "...", input: {...} }` items
- **Format 3 (OpenAI):** Assistant message with `tool_calls` array

Claude-style assistant messages with content arrays (`[{ type: "text", text: "..." }]`) are also handled correctly in contradiction context extraction (D7 fix).

---

## Files

```
confidence-check/
├── src/
│   └── index.ts             # Plugin source (single file, ~550 lines)
├── dist/
│   └── index.js             # Compiled output (loaded by gateway)
├── package.json             # npm metadata and build scripts
├── openclaw.plugin.json     # Plugin manifest (hooks, activation)
├── tsconfig.json            # TypeScript configuration
└── README.md                # This file
```

---

## Known Limitations

- **No unit test suite.** All testing is manual via staging runs. A Jest/vitest harness is tracked as an open gap (GAP-F in `tests/QA-VALIDATION-REPORT-272-312-STEP8.md`).
- **`retryAttempts` Map has no TTL eviction.** If a run is abandoned mid-stream (e.g., session disconnect before post-framing), the entry persists until gateway restart. Low impact — bounded by concurrent session count.
- **Phase 1 fires on every response.** Including trivially correct ones. This adds one extra hook invocation per turn. No performance baseline exists yet.
