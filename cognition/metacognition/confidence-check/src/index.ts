/**
 * Confidence-Check Plugin — index.ts
 *
 * Hooks into before_agent_finalize to evaluate response confidence.
 *
 * Flow:
 *   1. Heuristic pre-screen: count hedging phrases, calculate density,
 *      count unsupported assertions (factual claims without citation markers)
 *   2. If hedging density < low_threshold AND assertion_count < threshold → PASS (return undefined)
 *   3. If hedging density > high_threshold → FAIL → skip to LLM evaluation
 *   4. Otherwise → borderline → proceed to LLM evaluation
 *   5. LLM evaluation: POST to OpenRouter (or ollama) with structured JSON prompt
 *      Ask for: { "confidence": 0-100, "concerns": [...], "reasoning_strategies": [...] }
 *   6. If confidence < threshold:
 *      - Return revision instruction via Socratic questioning
 *      - Track retry count per runId (idempotencyKey)
 *   7. If maxAttempts exhausted:
 *      - Return framing instruction: "I'm not fully confident about this, but..."
 *   8. After final framing pass, return undefined to allow finalization
 *
 * Config (hardcoded defaults):
 *   confidence_threshold: 70
 *   max_revision_attempts: 3
 *   hedging_density_pass_threshold: 0.02
 *   hedging_density_fail_threshold: 0.08
 *   evaluation_model: deepseek/deepseek-v4-flash (cheap + fast via OpenRouter)
 *
 * Issue: #75
 */

// ══════════════════════════════════════════════════════════════════════════════
// Configuration
// ══════════════════════════════════════════════════════════════════════════════

const CONFIG = {
  confidence_threshold: 70,              // LLM confidence score threshold
  max_revision_attempts: 3,              // Max Socratic revision attempts
  hedging_density_pass_threshold: 0.02,  // Below this → auto-pass
  hedging_density_fail_threshold: 0.08,  // Above this → auto-fail to LLM
  evaluation_model: "deepseek/deepseek-v4-flash",
};

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

// Per-run retry tracking: idempotencyKey → attempt count
const retryAttempts = new Map<string, number>();

// ══════════════════════════════════════════════════════════════════════════════
// Plugin entry
// ══════════════════════════════════════════════════════════════════════════════

export default function register(api: PluginApi): void {
  console.info("[confidence-check] Plugin registered — hook: before_agent_finalize");

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
        // On error, allow finalization — don't block
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
  const runId = event.runId || "unknown";

  if (!message.trim()) {
    console.debug("[confidence-check] Empty message, skipping");
    return undefined;
  }

  // ── Track retry attempts ────────────────────────────────────────────────────
  const idempotencyKey = `confidence-${runId}`;
  const priorAttempts = retryAttempts.get(idempotencyKey) || 0;

  // ── Step 1: Heuristic pre-screen ────────────────────────────────────────────
  const heuristics = runHeuristicScreen(message);
  console.info(
    `[confidence-check] Heuristics: hedging=${heuristics.hedging_count}/${heuristics.word_count} ` +
      `density=${heuristics.hedging_density.toFixed(3)} assertions=${heuristics.unsupported_assertions}`
  );

  // Auto-pass: very low hedging, low unsupported assertions
  if (
    heuristics.hedging_density < CONFIG.hedging_density_pass_threshold &&
    heuristics.unsupported_assertions < 3
  ) {
    console.info("[confidence-check] Auto-pass (low hedging, few assertions)");
    return undefined;
  }

  // ── Step 2: Check if max revisions exhausted ───────────────────────────────
  if (priorAttempts >= CONFIG.max_revision_attempts) {
    console.warn(`[confidence-check] Max revisions (${CONFIG.max_revision_attempts}) exhausted for ${runId}, framing response`);
    retryAttempts.set(idempotencyKey, priorAttempts + 1);
    return {
      action: "revise",
      retry: {
        instruction:
          "You have been unable to reach high confidence after multiple revisions. " +
          "Frame your response to acknowledge uncertainty: start with 'I'm not fully confident about this, but...' " +
          "and explain what you're uncertain about.",
        maxAttempts: 1,
      },
    };
  }

  // ── Step 3: LLM evaluation ──────────────────────────────────────────────────
  let llmResult: LlmEvaluation;
  try {
    llmResult = await evaluateViaLlm(message, heuristics);
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

  // ── Step 4: Decide action ───────────────────────────────────────────────────
  if (llmResult.confidence >= CONFIG.confidence_threshold) {
    console.info("[confidence-check] PASS — confidence above threshold");
    return undefined;
  }

  // Fail → trigger revision
  retryAttempts.set(idempotencyKey, priorAttempts + 1);
  const attemptsRemaining = CONFIG.max_revision_attempts - priorAttempts;

  console.warn(
    `[confidence-check] FAIL — confidence ${llmResult.confidence}% < threshold ${CONFIG.confidence_threshold}. ` +
      `Triggering revision (attempt ${priorAttempts + 1}/${CONFIG.max_revision_attempts})`
  );

  const concernsBlock = llmResult.concerns.length > 0
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
  // Simple heuristic: count sentences that look like factual claims
  // (declarative sentences without "?" at end) minus those with citation markers
  const sentences = message
    .split(/[.!?]+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 8 && !s.endsWith("?"));

  let unsupported = 0;
  for (const sentence of sentences) {
    const hasCitation = CITATION_MARKERS.some((m) =>
      sentence.toLowerCase().includes(m)
    );
    // Also check for weak indicators of unsupported claims
    const hasHedgingInSentence = HEDGING_PHRASES.some((m) =>
      sentence.toLowerCase().includes(m)
    );
    if (!hasCitation && !hasHedgingInSentence) {
      unsupported++;
    }
  }

  // Cap unsupported at max sentence count
  unsupported = Math.min(unsupported, sentences.length);

  return {
    hedging_count: hedgingCount,
    word_count: wordCount,
    hedging_density: hedgingCount / wordCount,
    unsupported_assertions: unsupported,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// LLM evaluation via OpenRouter
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

ASSISTANT RESPONSE:
{message}
`;

async function evaluateViaLlm(
  message: string,
  heuristics: HeuristicResult
): Promise<LlmEvaluation> {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    throw new Error("OPENROUTER_API_KEY not set");
  }

  const prompt = EVAL_PROMPT_TEMPLATE
    .replace("{hedging_count}", String(heuristics.hedging_count))
    .replace("{word_count}", String(heuristics.word_count))
    .replace("{hedging_density}", heuristics.hedging_density.toFixed(4))
    .replace("{unsupported_assertions}", String(heuristics.unsupported_assertions))
    .replace("{message}", message);

  const resp = await fetch(OPENROUTER_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      "HTTP-Referer": "https://nova.dustintrammell.com",
      "X-Title": "NOVA Confidence Check",
    },
    body: JSON.stringify({
      model: CONFIG.evaluation_model,
      messages: [
        {
          role: "system",
          content:
            "You are a strict confidence evaluator. Analyze the response for accuracy, confidence, hedging, and unsupported claims. Respond in JSON only.",
        },
        { role: "user", content: prompt },
      ],
      temperature: 0.3,
      max_tokens: 512,
    }),
  });

  if (!resp.ok) {
    const body = await resp.text().catch(() => "");
    throw new Error(`OpenRouter HTTP ${resp.status}: ${body.slice(0, 500)}`);
  }

  const data = (await resp.json()) as OpenRouterResponse;
  if (!data.choices?.[0]?.message?.content) {
    throw new Error("OpenRouter response missing content");
  }

  const content = data.choices[0].message.content.trim();

  // Parse JSON — handle markdown code blocks
  let parsed: LlmEvaluation;
  try {
    const jsonContent = content
      .replace(/^```(?:json)?\s*/, "")
      .replace(/```$/, "")
      .trim();
    parsed = JSON.parse(jsonContent) as LlmEvaluation;
  } catch (e) {
    throw new Error(`Failed to parse LLM JSON response: ${(e as Error).message}. Raw: ${content.slice(0, 500)}`);
  }

  // Validate and sanitize
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

interface PluginApi {
  on(
    hook: string,
    handler: (event: FinalizeEvent, ctx: PluginContext) => Promise<ReviseAction | undefined>,
    options?: { timeoutMs?: number }
  ): void;
}

interface FinalizeEvent {
  lastAssistantMessage?: string;
  runId?: string;
  content?: string;
  sessionKey?: string;
  metadata?: Record<string, unknown>;
  [key: string]: unknown;
}

interface PluginContext {
  sessionKey?: string;
  agentId?: string;
  runId?: string;
  [key: string]: unknown;
}

interface ReviseAction {
  action: "revise";
  retry: {
    instruction: string;
    idempotencyKey?: string;
    maxAttempts: number;
  };
}

interface OpenRouterResponse {
  choices?: Array<{ message?: { content?: string } }>;
  error?: { message?: string };
}
