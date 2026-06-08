/**
 * Confidence-Check Plugin — index.ts
 *
 * Hooks into before_agent_finalize to evaluate response confidence.
 *
 * Two-phase evaluation architecture:
 *
 * Phase 1 — Self-verification (priorAttempts === 0, always runs):
 *   Immediately returns a revision action with explicit self-verification questions.
 *   No heuristic pre-screen, no external LLM call — just triggers the model to
 *   verify its own response for truthfulness, sources, assumptions, knowledge
 *   boundaries, and self-consistency.
 *
 * Phase 2 — External evaluation (priorAttempts 1+):
 *   1. Heuristic pre-screen: count hedging phrases, calculate density,
 *      count unsupported assertions (kept as signal for external evaluator —
 *      no longer used as an auto-pass shortcut)
 *   2. Check if max external revisions exhausted → framing/post-framing
 *   3. Citation/reference verification: extract citations from response,
 *      cross-reference against tool calls in event.messages
 *   4. Self-contradiction detection: extract prior assistant messages for
 *      LLM to evaluate (assistant-vs-assistant only, not assistant-vs-user)
 *   5. LLM evaluation: use api.runtime.llm.complete() with structured JSON prompt
 *      Ask for: { "confidence": 0-100, "concerns": [...], "reasoning_strategies": [...] }
 *   6. If confidence < threshold → revision instruction via Socratic questioning
 *
 * Phase 3 — Framing pass (max_external_revision_attempts exhausted):
 *   Return framing instruction: "I'm not fully confident about this, but..."
 *   Post-framing pass allows finalization.
 *
 * State machine:
 *   priorAttempts === 0  →  self-verification revise (always)
 *   priorAttempts === 1  →  run external evaluator; revise if < threshold
 *   priorAttempts === 2  →  run external evaluator; revise if < threshold
 *   priorAttempts === 3  →  framing pass (max_external exhausted)
 *   priorAttempts === 4  →  post-framing, allow finalization, cleanup
 *
 * Config (hardcoded defaults):
 *   confidence_threshold: 85                    (raised from 70 in issue #272)
 *   max_external_revision_attempts: 2
 *   self_verification_enabled: true
 *   hedging_density_pass_threshold: 0.02        (signal only, no longer an auto-pass shortcut)
 *   hedging_density_fail_threshold: 0.08
 *   evaluation_model: deepseek/deepseek-v4-flash
 *
 * Total max hook invocations: 1 (self-verify) + 2 (external) + 1 (framing) + 1 (post-framing) = 5
 *
 * Issues: #75, #272, #312
 */

// REQUIRED CONFIG: openclaw.json must include:
// "plugins": { "entries": { "confidence-check": {
//   "hooks": { "allowConversationAccess": true },
//   "llm": { "allowModelOverride": true, "allowedModels": ["deepseek/deepseek-v4-flash"] }
// } } }
// Without allowConversationAccess, the hook will not receive lastAssistantMessage or messages.
// Without allowModelOverride + allowedModels, api.runtime.llm.complete() model override is blocked.

// ══════════════════════════════════════════════════════════════════════════════
// Configuration
// ══════════════════════════════════════════════════════════════════════════════

const CONFIG = {
  confidence_threshold: 85,                    // LLM confidence score threshold (raised from 70, issue #272)
  max_external_revision_attempts: 2,           // Max external LLM revision attempts (after self-verification)
  self_verification_enabled: true,             // Enable mandatory self-verification pass at attempt 0
  hedging_density_pass_threshold: 0.02,        // Signal only (no longer an auto-pass shortcut)
  hedging_density_fail_threshold: 0.08,        // Above this → auto-fail to LLM
  evaluation_model: "deepseek/deepseek-v4-flash",
  max_prior_messages: 10,                      // Max prior messages to check for contradictions
};

// Per-run retry tracking: idempotencyKey → attempt count
const retryAttempts = new Map<string, number>();

// Module-level reference to api.runtime.llm (set during register(), used in hook handlers)
let pluginLlm: { complete(opts: LlmCompleteOpts): Promise<LlmCompleteResult> } | undefined;

// ══════════════════════════════════════════════════════════════════════════════
// Plugin entry
// ══════════════════════════════════════════════════════════════════════════════

export default function register(api: PluginApi): void {
  console.info("[confidence-check] Plugin registered — hook: before_agent_finalize");

  // Store api.runtime.llm in module scope for use across hook invocations
  pluginLlm = api.runtime.llm;

  api.on(
    "before_agent_finalize",
    async (event: FinalizeEvent, ctx: PluginContext): Promise<ReviseAction | undefined> => {
      try {
        return await evaluateConfidence(event, ctx);
      } catch (err) {
        console.error(
          "[confidence-check] Unhandled error in before_agent_finalize:",
          err instanceof Error ? err.message : String(err)
        );
        // On error, allow finalization — don't block the agent
        return undefined;
      }
    }
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Confidence evaluation pipeline
// ══════════════════════════════════════════════════════════════════════════════

async function evaluateConfidence(
  event: FinalizeEvent,
  _ctx: PluginContext
): Promise<ReviseAction | undefined> {
  const message = event.lastAssistantMessage || "";
  // D2: Missing runId means broken hook context — skip to avoid cross-run state contamination
  const runId = event.runId;
  if (!runId) {
    console.warn("[confidence-check] Missing runId — skipping confidence check to avoid state contamination");
    return undefined;
  }
  const messages = Array.isArray(event.messages) ? event.messages : [];

  if (!message.trim()) {
    console.debug("[confidence-check] Empty message, skipping");
    return undefined;
  }

  // ── Track retry attempts ────────────────────────────────────────────────────
  const idempotencyKey = `confidence-${runId}`;
  const priorAttempts = retryAttempts.get(idempotencyKey) || 0;

  // ── Phase 1: Self-verification (attempt 0, always runs) ───────────────────
  // No heuristic pre-screen, no external LLM call — immediately trigger a
  // revision so the model can verify its own response before external evaluation.
  if (priorAttempts === 0 && CONFIG.self_verification_enabled) {
    console.info("[confidence-check] Phase 1: Mandatory self-verification pass (attempt 0)");
    retryAttempts.set(idempotencyKey, 1);
    return {
      action: "revise",
      retry: {
        instruction:
          "Before finalizing your response, verify the following:\n\n" +
          "1. TRUTHFULNESS: Are all claims in your response truthful and factual? If you stated something as fact, is it actually true to the best of your knowledge?\n" +
          "2. SOURCES: Are all cited sources, file paths, URLs, and references real? Did you actually look them up, or are you assuming they exist?\n" +
          "3. ASSUMPTIONS: What assumptions are you making that you haven't explicitly stated? Surface any hidden assumptions.\n" +
          "4. KNOWLEDGE BOUNDARIES: Distinguish clearly between what you actually know, what you inferred, and what you're guessing. If anything is uncertain, say so explicitly.\n" +
          "5. SELF-CONSISTENCY: Does your response contradict anything you said earlier in this conversation?\n\n" +
          "Revise your response to address any issues found. If everything checks out, you may restate your response with confidence.",
        idempotencyKey,
        maxAttempts: 1,
      },
    };
  }

  // ── Phase 2: External evaluation (priorAttempts >= 1) ─────────────────────

  // ── Step 1: Heuristic pre-screen (signal only — no auto-pass shortcut) ────
  const heuristics = runHeuristicScreen(message);
  console.info(
    `[confidence-check] Heuristics: hedging=${heuristics.hedging_count}/${heuristics.word_count} ` +
      `density=${heuristics.hedging_density.toFixed(3)} assertions=${heuristics.unsupported_assertions}`
  );

  // ── Step 2: Check if max external revisions exhausted ─────────────────────
  // externalAttempts counts invocations since self-verification (priorAttempts 1+).
  // D1: Only subtract 1 for the self-verification pass if it actually ran.
  const externalAttempts = CONFIG.self_verification_enabled ? priorAttempts - 1 : priorAttempts;

  // D1: Post-framing threshold also depends on whether self-verification ran.
  if (priorAttempts > CONFIG.max_external_revision_attempts + (CONFIG.self_verification_enabled ? 1 : 0)) {
    // Post-framing pass: framing revision already issued, allow finalization
    console.info("[confidence-check] Post-framing pass, allowing finalization");
    retryAttempts.delete(idempotencyKey); // cleanup
    return undefined;
  }

  if (externalAttempts >= CONFIG.max_external_revision_attempts) {
    // This IS the framing pass (priorAttempts === max_external_revision_attempts + 1 === 3)
    console.warn(
      `[confidence-check] Max external revisions (${CONFIG.max_external_revision_attempts}) exhausted for ${runId}, framing response`
    );
    retryAttempts.set(idempotencyKey, priorAttempts + 1);
    return {
      action: "revise",
      retry: {
        instruction:
          "You have been unable to reach high confidence after multiple revisions. " +
          "Frame your response to acknowledge uncertainty: start with 'I'm not fully confident about this, but...' " +
          "and explain what you're uncertain about.",
        idempotencyKey, // D5: include idempotencyKey for consistency with Phase 1 & Phase 2
        maxAttempts: 1,
      },
    };
  }

  // ── Step 3: Citation verification ──────────────────────────────────────────
  const citations = extractCitations(message);
  const citationResult = verifyCitations(citations, messages);
  console.info(
    `[confidence-check] Citations: ${citationResult.verified} verified / ${citationResult.total} total ` +
      `(${citationResult.unverified} unverified)`
  );

  // ── Step 4: Extract prior assistant context for contradiction detection ─────
  const contradictionCtx = extractContradictionContext(messages, message);
  if (contradictionCtx.hasContext) {
    console.info(
      `[confidence-check] Contradiction context: ${contradictionCtx.priorAssistantMessages.length} prior assistant message(s) loaded`
    );
  }

  // ── Step 5: LLM evaluation ──────────────────────────────────────────────────
  let llmResult: LlmEvaluation;
  try {
    llmResult = await evaluateViaLlm(message, heuristics, citationResult, contradictionCtx);
  } catch (err) {
    console.warn("[confidence-check] LLM evaluation failed:", (err as Error).message);
    // On LLM failure, use heuristics fallback
    if (heuristics.hedging_density >= CONFIG.hedging_density_fail_threshold) {
      llmResult = {
        confidence: 40,
        concerns: ["High hedging density detected"],
        reasoning_strategies: ["Review claims and verify against sources"],
      };
    } else {
      // Borderline — let it pass but log
      console.info("[confidence-check] Borderline after LLM failure, allowing finalize");
      return undefined;
    }
  }

  console.info(
    `[confidence-check] LLM confidence=${llmResult.confidence}% ` +
      `concerns=[${llmResult.concerns.join("; ")}] ` +
      `strategies=[${llmResult.reasoning_strategies.join("; ")}]`
  );

  // ── Step 6: Decide action ───────────────────────────────────────────────────
  if (llmResult.confidence >= CONFIG.confidence_threshold) {
    console.info("[confidence-check] PASS — confidence above threshold");
    retryAttempts.delete(idempotencyKey); // D3: cleanup on PASS to prevent memory leak
    return undefined;
  }

  // Fail → trigger external revision
  retryAttempts.set(idempotencyKey, priorAttempts + 1);
  // D4: subtract 1 because the current attempt is being consumed; remaining = future attempts
  const attemptsRemaining = CONFIG.max_external_revision_attempts - externalAttempts - 1;

  console.warn(
    `[confidence-check] FAIL — confidence ${llmResult.confidence}% < threshold ${CONFIG.confidence_threshold}. ` +
      `Triggering external revision (external attempt ${externalAttempts + 1}/${CONFIG.max_external_revision_attempts})`
  );

  const concernsBlock =
    llmResult.concerns.length > 0
      ? llmResult.concerns.map((c) => `- ${c}`).join("\n")
      : "- Unspecified concerns identified by evaluator";

  return {
    action: "revise",
    retry: {
      instruction:
        `Your self-assessment scored ${llmResult.confidence}% confidence (threshold: ${CONFIG.confidence_threshold}%).\n\n` +
        `Concerns:\n${concernsBlock}\n\n` +
        `What assumptions are you making in this response? What evidence supports or contradicts your claims?\n\n` +
        `(${attemptsRemaining} revision attempt(s) available)`,
      idempotencyKey,
      maxAttempts: 1,
    },
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// Heuristic pre-screen
// ══════════════════════════════════════════════════════════════════════════════

interface HeuristicResult {
  hedging_count: number;
  word_count: number;
  hedging_density: number;
  unsupported_assertions: number;
}

const HEDGING_PHRASES = [
  "i think", "i believe", "maybe", "probably", "i'm not sure",
  "i am not sure", "might be", "could be wrong", "not certain",
  "i'm not certain", "seems like", "appears to", "as far as i know",
  "i guess", "i suppose", "perhaps", "possibly", "i'm guessing",
  "unclear", "not entirely", "not completely", "partially",
];

const CITATION_MARKERS = [
  "according to", "based on", "the docs say", "the documentation states",
  "as stated", "as mentioned", "per", "source", "in the",
];

function runHeuristicScreen(message: string): HeuristicResult {
  const words = message.split(/\s+/).filter((w) => w.length > 0);
  const wordCount = words.length || 1;

  const lower = message.toLowerCase();

  // Count hedging phrases
  let hedgingCount = 0;
  for (const phrase of HEDGING_PHRASES) {
    const matches = lower.match(new RegExp(phrase, "g"));
    if (matches) hedgingCount += matches.length;
  }

  // Count unsupported assertions (sentences without citation markers)
  // Simple heuristic: declarative sentences that lack citation markers or hedging
  const sentences = message
    .split(/[.!?]+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 8 && !s.endsWith("?"));

  let unsupported = 0;
  for (const sentence of sentences) {
    const hasCitation = CITATION_MARKERS.some((m) =>
      sentence.toLowerCase().includes(m)
    );
    const hasHedgingInSentence = HEDGING_PHRASES.some((m) =>
      sentence.toLowerCase().includes(m)
    );
    if (!hasCitation && !hasHedgingInSentence) {
      unsupported++;
    }
  }

  // Cap unsupported at total sentence count
  unsupported = Math.min(unsupported, sentences.length);

  return {
    hedging_count: hedgingCount,
    word_count: wordCount,
    hedging_density: hedgingCount / wordCount,
    unsupported_assertions: unsupported,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// Citation extraction and verification
// ══════════════════════════════════════════════════════════════════════════════

interface CitationItem {
  type: "url" | "file_path" | "doc_reference" | "code_reference";
  value: string;
}

interface VerifiedCitation extends CitationItem {
  verified: boolean;
}

interface CitationResult {
  total: number;
  verified: number;
  unverified: number;
  citations: VerifiedCitation[];
}

// Phrases that indicate conversational back-references (not external source citations)
const CONVERSATIONAL_BACK_REFS = [
  "mentioned earlier",
  "mentioned above",
  "said before",
  "said earlier",
  "as i said",
  "as i mentioned",
  "as we discussed",
  "as discussed",
  "as noted",
  "stated above",
  "stated before",
  "noted above",
  "noted earlier",
  "previous message",
  "prior message",
  "the conversation",
  "my previous",
  "my prior",
];

function isConversationalReference(phrase: string): boolean {
  const lower = phrase.toLowerCase();
  return CONVERSATIONAL_BACK_REFS.some((ref) => lower.includes(ref));
}

function extractCitations(message: string): CitationItem[] {
  const citations: CitationItem[] = [];
  // Track captured values to avoid duplicates across different citation types
  const capturedValues = new Set<string>();

  function addCitation(item: CitationItem): void {
    // Normalize value for dedup (remove trailing punctuation)
    const val = item.value.replace(/[.,;:!?]+$/, "");
    if (!capturedValues.has(val)) {
      capturedValues.add(val);
      citations.push({ ...item, value: val });
    }
  }

  let match: RegExpExecArray | null;

  // ── 1. URLs (http/https) ──────────────────────────────────────────────────
  const urlRegex = /https?:\/\/[^\s\)'">,;`\]]+/g;
  while ((match = urlRegex.exec(message)) !== null) {
    addCitation({ type: "url", value: match[0] });
  }

  // ── 2. Absolute file paths (/ or ~/) — exclude protocol slashes (://) ─────
  // Lookbehind ensures the leading slash is not part of a URL protocol
  const absPathRegex = /(?<![:/])(?:~\/|\/(?!\/))[^\s,;:'"<>`()[\]{}|\\]+/g;
  while ((match = absPathRegex.exec(message)) !== null) {
    const p = match[0];
    // Skip very short paths (just "/" alone) or paths containing "://"
    if (p.length > 2 && !p.includes("://")) {
      addCitation({ type: "file_path", value: p });
    }
  }

  // ── 3. Relative file paths (must have a recognized file extension) ─────────
  const relPathRegex =
    /\b(?:[\w.-]+\/)*[\w.-]+\.(?:ts|js|tsx|jsx|mjs|cjs|json|md|yaml|yml|py|sh|bash|txt|cfg|conf|env|toml|html|css|scss|sql|go|rs|java|c|cpp|h|xml|ini|log)\b/gi;
  while ((match = relPathRegex.exec(message)) !== null) {
    const p = match[0];
    // Skip if already captured or if it looks like a URL fragment
    if (!capturedValues.has(p) && !p.includes("://") && !p.startsWith("/") && !p.startsWith("~")) {
      addCitation({ type: "file_path", value: p });
    }
  }

  // ── 4. Backtick code references that look like file paths ─────────────────
  const backtickRegex = /`([^`\n]+)`/g;
  while ((match = backtickRegex.exec(message)) !== null) {
    const inner = match[1].trim();
    // Only capture if it looks like a file path: has "/" or recognized extension, no spaces
    const hasExtension =
      /\.(?:ts|js|tsx|jsx|mjs|cjs|json|md|yaml|yml|py|sh|bash|txt|cfg|conf|env|toml|html|css|scss|sql|go|rs|java|c|cpp|h|xml|ini|log)$/i.test(
        inner
      );
    if ((inner.includes("/") || hasExtension) && !inner.includes(" ") && inner.length > 2) {
      // Only add if value not already captured by URL/path extraction
      if (!capturedValues.has(inner)) {
        addCitation({ type: "code_reference", value: inner });
      }
    }
  }

  // ── 5. Doc references — "according to...", "the docs say...", etc. ─────────
  // Must NOT be a conversational back-reference.
  // Must NOT contain an already-captured URL or file path (those take precedence).
  const docRefPatterns: RegExp[] = [
    /according\s+to(?:\s+the)?\s+([^,\.!?\n;]{3,60})/gi,
    /(?:the\s+)?docs?\s+(?:says?|states?|indicates?|mentions?|shows?|confirms?)(?:\s+that)?/gi,
    /(?:the\s+)?documentation\s+(?:says?|states?|indicates?|mentions?|shows?|confirms?)(?:\s+that)?/gi,
    /as\s+stated\s+in(?:\s+the)?\s+([^,\.!?\n;]{3,60})/gi,
    /based\s+on(?:\s+the)?\s+([^,\.!?\n;]{3,60})/gi,
  ];

  for (const regex of docRefPatterns) {
    while ((match = regex.exec(message)) !== null) {
      const phrase = match[0].trim();

      // Skip conversational back-references
      if (isConversationalReference(phrase)) continue;

      // Skip if the captured source group starts with a personal pronoun or vague word
      // (e.g., "based on my understanding", "based on what you said")
      const captured = ((match[1] || "").trim()).toLowerCase();
      if (captured) {
        const firstWord = captured.split(/\s+/)[0];
        const vagueStarters =
          /^(?:my|your|our|their|its|this|that|these|those|what|how|why|which|a|an|above|earlier|previous|prior|nothing|everything|anything)$/;
        if (vagueStarters.test(firstWord)) continue;
      } else {
        // Pattern matched but no capture group with source — still proceed (e.g., "the docs say")
      }

      // Skip if phrase contains an already-captured URL or file path
      // (the more specific citation type takes precedence)
      const phraseContainsCaptured = [...capturedValues].some((v) => phrase.includes(v));
      if (phraseContainsCaptured) continue;

      // Valid doc reference
      if (!capturedValues.has(phrase)) {
        capturedValues.add(phrase);
        citations.push({ type: "doc_reference", value: phrase });
      }
    }
  }

  return citations;
}

// Tool call record parsed from event.messages
interface ToolCallRecord {
  name: string;
  content: string;
}

/**
 * Extract tool call records from event.messages in all supported formats:
 * - Format 1 (OpenClaw): { role: "tool", name: string, content: string }
 * - Format 2 (Claude): content array items with type "tool_use"
 * - Format 3 (OpenAI): assistant message with tool_calls array
 */
function extractToolCalls(messages: unknown[]): ToolCallRecord[] {
  const toolCalls: ToolCallRecord[] = [];

  for (const msg of messages) {
    if (!msg || typeof msg !== "object") continue;
    const m = msg as Record<string, unknown>;

    // Format 1: { role: "tool", name: string, content: string }
    if (m.role === "tool" && typeof m.name === "string" && typeof m.content === "string") {
      toolCalls.push({ name: m.name, content: m.content });
      continue;
    }

    // Format 2: Claude-style content array with tool_use items
    if (Array.isArray(m.content)) {
      for (const item of m.content as unknown[]) {
        if (!item || typeof item !== "object") continue;
        const i = item as Record<string, unknown>;
        if (i.type === "tool_use" && typeof i.name === "string") {
          const inputStr =
            typeof i.input === "object"
              ? JSON.stringify(i.input)
              : String(i.input || "");
          toolCalls.push({ name: i.name, content: inputStr });
        }
      }
    }

    // Format 3: OpenAI-style tool_calls on assistant message
    if (Array.isArray(m.tool_calls)) {
      for (const tc of m.tool_calls as unknown[]) {
        if (!tc || typeof tc !== "object") continue;
        const t = tc as Record<string, unknown>;
        const fn = t.function as Record<string, unknown> | undefined;
        const name =
          typeof t.name === "string"
            ? t.name
            : typeof fn?.name === "string"
            ? (fn.name as string)
            : "";
        const args = t.arguments ?? fn?.arguments ?? "";
        if (name) {
          toolCalls.push({
            name,
            content: typeof args === "string" ? args : JSON.stringify(args),
          });
        }
      }
    }
  }

  return toolCalls;
}

/**
 * Check whether a single citation is backed by a matching tool call.
 *
 * Matching rules:
 *   url          → web_fetch or web_search tool call containing the URL or its domain
 *   file_path    → read tool call, or exec tool call using cat/grep/head/tail/sed/less/awk/wc/diff
 *   code_reference → same as file_path
 *   doc_reference  → pdf tool call (any document); or any tool call whose content shares
 *                     key words from the source name
 */
function verifyCitation(citation: CitationItem, toolCalls: ToolCallRecord[]): boolean {
  for (const tc of toolCalls) {
    const tcName = tc.name.toLowerCase();
    const tcContent = tc.content.toLowerCase();

    if (citation.type === "url") {
      if (tcName === "web_fetch" || tcName === "web_search") {
        const urlLower = citation.value.toLowerCase().replace(/\/$/, "");
        if (tcContent.includes(urlLower)) return true;
        // Also check domain-level match
        try {
          const domain = new URL(citation.value).hostname.toLowerCase();
          if (tcContent.includes(domain)) return true;
        } catch {
          // Not a parseable URL — skip domain check
        }
      }
    }

    if (citation.type === "file_path" || citation.type === "code_reference") {
      // Normalize: strip leading ~/ for home-directory matching
      const pathNorm = citation.value.replace(/^~\//, "").toLowerCase();
      const filename = pathNorm.split("/").pop() || pathNorm;

      if (tcName === "read") {
        if (tcContent.includes(pathNorm) || (filename.length > 3 && tcContent.includes(filename))) {
          return true;
        }
      }

      if (tcName === "exec") {
        // Only count exec tool calls that use file-reading commands
        const fileReadCmds = /\b(?:cat|grep|head|tail|sed|less|awk|wc|diff|find)\b/;
        if (fileReadCmds.test(tcContent)) {
          if (tcContent.includes(pathNorm) || (filename.length > 3 && tcContent.includes(filename))) {
            return true;
          }
        }
      }
    }

    if (citation.type === "doc_reference") {
      // A pdf tool call is strong evidence any document reference was consulted
      if (tcName === "pdf") return true;

      // For web/read: check if key words from the source phrase appear in tool call content
      if (tcName === "web_fetch" || tcName === "web_search" || tcName === "read") {
        // Extract meaningful words from the doc reference (skip common words and meta-words)
        const skipWords = new Set([
          "according", "stated", "based", "documentation", "docs", "doc",
          "says", "say", "states", "indicates", "mentions", "shows", "confirms",
          "the", "a", "an", "to", "in", "on", "of", "and", "or", "that", "this",
        ]);
        const refWords = citation.value
          .toLowerCase()
          .split(/\s+/)
          .filter((w) => w.length > 4 && !skipWords.has(w));
        // If any meaningful word from the reference matches tool call content, consider verified
        if (refWords.length > 0 && refWords.some((w) => tcContent.includes(w))) {
          return true;
        }
      }
    }
  }

  return false;
}

function verifyCitations(citations: CitationItem[], messages: unknown[]): CitationResult {
  if (citations.length === 0) {
    return { total: 0, verified: 0, unverified: 0, citations: [] };
  }

  const toolCalls = extractToolCalls(messages);

  const verifiedCitations: VerifiedCitation[] = citations.map((citation) => ({
    ...citation,
    verified: verifyCitation(citation, toolCalls),
  }));

  const verifiedCount = verifiedCitations.filter((c) => c.verified).length;

  return {
    total: citations.length,
    verified: verifiedCount,
    unverified: citations.length - verifiedCount,
    citations: verifiedCitations,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// Self-contradiction context extraction
// ══════════════════════════════════════════════════════════════════════════════

interface ContradictionContext {
  priorAssistantMessages: string[];
  hasContext: boolean;
}

/**
 * Extract prior assistant messages from event.messages for contradiction detection.
 * Checks only the last CONFIG.max_prior_messages messages for performance.
 * Filters for role === "assistant" only — user messages are intentionally excluded
 * (we detect self-contradictions, not disagreements with user statements).
 */
function extractContradictionContext(messages: unknown[], lastAssistantMessage?: string): ContradictionContext {
  if (!messages || messages.length === 0) {
    return { priorAssistantMessages: [], hasContext: false };
  }

  // Limit to the most recent window to keep prompt size reasonable and avoid O(n²)
  const recentMessages = messages.slice(-CONFIG.max_prior_messages);

  const priorAssistantMessages: string[] = [];
  for (const msg of recentMessages) {
    if (!msg || typeof msg !== "object") continue;
    const m = msg as Record<string, unknown>;
    // Only assistant role messages — never user role (TC-272-24)
    if (m.role === "assistant") {
      // D7: handle both string content and Claude-style content arrays
      let text = "";
      if (typeof m.content === "string") {
        text = m.content.trim();
      } else if (Array.isArray(m.content)) {
        // Claude-style content array: [{type: "text", text: "..."}]
        text = (m.content as any[])
          .filter((b: any) => b && b.type === "text" && typeof b.text === "string")
          .map((b: any) => b.text)
          .join("\n")
          .trim();
      }
      if (text) {
        // Skip the current response to avoid self-comparison
        if (lastAssistantMessage && text === lastAssistantMessage.trim()) continue;
        priorAssistantMessages.push(text);
      }
    }
  }

  return {
    priorAssistantMessages,
    hasContext: priorAssistantMessages.length > 0,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// LLM evaluation via api.runtime.llm.complete()
// ══════════════════════════════════════════════════════════════════════════════

interface LlmEvaluation {
  confidence: number;
  concerns: string[];
  reasoning_strategies: string[];
}

const EVAL_PROMPT_TEMPLATE = `Evaluate the confidence level of the following AI assistant response.

Respond ONLY with valid JSON. No markdown, no explanation outside the JSON.

{
  "confidence": <integer 0-100>,
  "concerns": ["list of specific concerns about accuracy, unsupported claims, or uncertainty"],
  "reasoning_strategies": ["suggested ways to improve confidence"]
}

HEDGING PHRASES FOUND: {hedging_count} in {word_count} words (density: {hedging_density})
UNSUPPORTED ASSERTIONS: {unsupported_assertions}

CITATION VERIFICATION:
{citation_summary}

SELF-CONTRADICTION CHECK:
{contradiction_context}

ASSISTANT RESPONSE TO EVALUATE:
{message}
`;

async function evaluateViaLlm(
  message: string,
  heuristics: HeuristicResult,
  citationResult: CitationResult,
  contradictionCtx: ContradictionContext
): Promise<LlmEvaluation> {
  if (!pluginLlm) {
    throw new Error("api.runtime.llm not available — plugin not initialized");
  }

  // ── Build citation summary section ─────────────────────────────────────────
  let citationSummary: string;
  if (citationResult.total === 0) {
    citationSummary = "No citations found in response.";
  } else {
    citationSummary =
      `${citationResult.total} citation(s) found: ` +
      `${citationResult.verified} verified, ${citationResult.unverified} unverified.`;
    if (citationResult.unverified > 0) {
      const unverifiedList = citationResult.citations
        .filter((c) => !c.verified)
        .map((c) => `  - [${c.type}] ${c.value}`)
        .join("\n");
      citationSummary +=
        `\nUnverified citations (no matching tool call found):\n${unverifiedList}` +
        `\nNote: Unverified citations indicate claims made without verified sources — factor this into confidence score.`;
    }
  }

  // ── Build self-contradiction context section ───────────────────────────────
  let contradictionSection: string;
  if (!contradictionCtx.hasContext) {
    contradictionSection =
      "No prior assistant messages available — self-contradiction check skipped.";
  } else {
    const priorBlock = contradictionCtx.priorAssistantMessages
      .map((msg, i) => `[Prior assistant turn ${i + 1}]:\n${msg.slice(0, 500)}`)
      .join("\n---\n");
    contradictionSection =
      `Check for SELF-CONTRADICTIONS between the current response and prior assistant statements below.\n` +
      `Only flag contradictions with the ASSISTANT's own prior statements (not user messages).\n` +
      `If a contradiction is found, include it in concerns and reduce confidence accordingly.\n\n` +
      priorBlock;
  }

  const prompt = EVAL_PROMPT_TEMPLATE
    .replace("{hedging_count}", String(heuristics.hedging_count))
    .replace("{word_count}", String(heuristics.word_count))
    .replace("{hedging_density}", heuristics.hedging_density.toFixed(4))
    .replace("{unsupported_assertions}", String(heuristics.unsupported_assertions))
    .replace("{citation_summary}", citationSummary)
    .replace("{contradiction_context}", contradictionSection)
    .replace("{message}", message);

  // ── Call SDK LLM helper (no raw HTTP, no API key management) ───────────────
  const result = await pluginLlm.complete({
    messages: [
      {
        role: "system",
        content:
          "You are a strict confidence evaluator. Analyze the response for accuracy, hedging, " +
          "unsupported claims, unverified citations, and self-contradictions with prior assistant statements. " +
          "Respond in JSON only.",
      },
      { role: "user", content: prompt },
    ],
    purpose: "confidence-check.evaluate",
    model: "deepseek/deepseek-v4-flash",
    maxTokens: 512,
    temperature: 0.3,
  });

  // SDK returns result.text (not result.content)
  const rawContent = (result as any).text ?? (result as any).content ?? "";
  if (!rawContent) {
    throw new Error("LLM response missing content");
  }

  const content = rawContent.trim();

  // ── Parse JSON — robust extraction: find first { and last } in content ──────
  // D6: handles prose preamble before JSON and avoids ^-anchored regex that fails on prefixed output
  let parsed: LlmEvaluation;
  try {
    const firstBrace = content.indexOf("{");
    const lastBrace = content.lastIndexOf("}");
    if (firstBrace === -1 || lastBrace === -1 || lastBrace <= firstBrace) {
      throw new Error(`No JSON object found in LLM response. Raw: ${content.slice(0, 500)}`);
    }
    const jsonContent = content.slice(firstBrace, lastBrace + 1);
    parsed = JSON.parse(jsonContent) as LlmEvaluation;
  } catch (e) {
    throw new Error(
      `Failed to parse LLM JSON response: ${(e as Error).message}. Raw: ${content.slice(0, 500)}`
    );
  }

  // ── Validate and sanitize fields ───────────────────────────────────────────
  if (typeof parsed.confidence !== "number" || isNaN(parsed.confidence)) {
    throw new Error("LLM response missing valid confidence field");
  }

  const confidence = Math.max(0, Math.min(100, Math.round(parsed.confidence)));
  const concerns = Array.isArray(parsed.concerns) ? parsed.concerns.map(String) : [];
  const strategies = Array.isArray(parsed.reasoning_strategies)
    ? parsed.reasoning_strategies.map(String)
    : [];

  return {
    confidence,
    concerns,
    reasoning_strategies: strategies,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// Type stubs for Plugin SDK
// ══════════════════════════════════════════════════════════════════════════════

interface LlmCompleteOpts {
  messages: Array<{ role: string; content: string }>;
  purpose: string;
  model?: string;
  maxTokens?: number;
  temperature?: number;
}

interface LlmCompleteResult {
  text?: string;
  content?: string;  // legacy compat
  provider?: string;
  model?: string;
  usage?: Record<string, unknown>;
}

interface PluginApi {
  on(
    hook: string,
    handler: (event: FinalizeEvent, ctx: PluginContext) => Promise<ReviseAction | undefined>,
    options?: { timeoutMs?: number }
  ): void;
  runtime: {
    llm: {
      complete(opts: LlmCompleteOpts): Promise<LlmCompleteResult>;
    };
  };
}

interface FinalizeEvent {
  runId?: string;
  sessionId?: string;
  sessionKey?: string;
  turnId?: string;
  provider?: string;
  model?: string;
  cwd?: string;
  transcriptPath?: string;
  stopHookActive?: boolean;
  lastAssistantMessage?: string;
  messages?: unknown[];
  [key: string]: unknown;
}

interface PluginContext {
  sessionKey?: string;
  agentId?: string;
  runId?: string;
  [key: string]: unknown;
}

interface ReviseAction {
  action?: "continue" | "revise" | "finalize";
  reason?: string;
  retry?: {
    instruction: string;
    idempotencyKey?: string;
    maxAttempts?: number;
  };
}
