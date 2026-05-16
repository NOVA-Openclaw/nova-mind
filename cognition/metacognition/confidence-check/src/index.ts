/**
 * Confidence Check Plugin — index.ts
 *
 * Registers a `before_agent_finalize` hook that evaluates the confidence
 * of the assistant's last response before it is delivered.
 *
 * Flow:
 *   1. Heuristic pre-screen on lastAssistantMessage
 *      - Count hedging phrases
 *      - hedging_density = hedging_count / total_words
 *      - < 0.02 → auto-pass (return undefined)
 *      - > 0.08 → auto-fail (skip to LLM eval)
 *      - Otherwise → borderline, proceed to LLM eval
 *   2. LLM evaluation via OpenRouter (deepseek/deepseek-v4-flash)
 *      - Ask for JSON: { confidence, concerns, reasoning_strategies }
 *      - Parse response, clamp confidence to [0,100]
 *      - Errors → log warning, return undefined
 *   3. If confidence < 70 → return revision instruction
 *      - Socratic questioning prompt
 *      - Idempotency key keyed by runId
 *      - maxAttempts = 3
 *   4. After maxAttempts exhausted → one final revision to frame as uncertain,
 *      then allow finalization.
 *
 * Issue: #75
 */

// ── Constants ───────────────────────────────────────────────────────────────

const OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions";
const EVAL_MODEL = "deepseek/deepseek-v4-flash";

const HEDGING_PHRASES: readonly string[] = [
  "I think",
  "maybe",
  "probably",
  "I'm not sure",
  "I believe",
  "might be",
  "could be wrong",
  "not certain",
];

// Track retry counts per idempotency key
const retryTracker = new Map<string, number>();

// ── Plugin entry ─────────────────────────────────────────────────────────────

type BeforeAgentFinalizeEvent = {
  runId?: string;
  sessionId: string;
  sessionKey?: string;
  lastAssistantMessage?: string;
  messages?: unknown[];
  provider?: string;
  model?: string;
};

type RevisionResult = {
  action: "revise";
  retry: {
    instruction: string;
    idempotencyKey: string;
    maxAttempts: number;
  };
};

export default function register(api: PluginApi): void {
  console.info("[confidence-check] Plugin registered — hook: before_agent_finalize");

  api.on(
    "before_agent_finalize",
    async (event: BeforeAgentFinalizeEvent, _ctx: PluginContext) => {
      const result = await evaluateConfidence(event);
      if (result) return result;
    }
  );
}

// ── Confidence evaluation ───────────────────────────────────────────────────

async function evaluateConfidence(
  event: BeforeAgentFinalizeEvent
): Promise<RevisionResult | undefined> {
  const message = event.lastAssistantMessage || "";
  if (!message.trim()) return undefined;

  // ── Heuristic pre-screen ──────────────────────────────────────────────
  const hedgingDensity = computeHedgingDensity(message);

  if (hedgingDensity < 0.02) {
    console.debug(
      `[confidence-check] Auto-pass (density=${hedgingDensity.toFixed(3)})`
    );
    return undefined;
  }

  // auto-fail (> 0.08) continues straight to LLM eval
  const skipHeuristic = hedgingDensity > 0.08;
  if (skipHeuristic) {
    console.debug(
      `[confidence-check] Auto-fail heuristic (density=${hedgingDensity.toFixed(3)}), proceeding to LLM eval`
    );
  }

  // ── LLM evaluation ────────────────────────────────────────────────────
  let evalResult: EvalResult | undefined;
  try {
    evalResult = await llmEvaluateConfidence(message);
  } catch (e) {
    console.warn(
      "[confidence-check] LLM evaluation failed:",
      e instanceof Error ? e.message : String(e)
    );
    return undefined;
  }

  if (!evalResult) return undefined;

  const confidence = Math.max(0, Math.min(100, evalResult.confidence));
  console.info(
    `[confidence-check] LLM confidence=${confidence}, concerns=[${evalResult.concerns.join(", ")}]`
  );

  if (confidence >= 70) {
    return undefined;
  }

  // ── Revision ──────────────────────────────────────────────────────────
  const runId = event.runId ?? "unknown";
  const idempotencyKey = `confidence-${runId}`;
  const maxAttempts = 3;

  const currentRetries = retryTracker.get(idempotencyKey) ?? 0;

  if (currentRetries >= maxAttempts) {
    // Final attempt: frame as uncertain, then allow finalization
    console.info(
      `[confidence-check] Max retries (${maxAttempts}) reached — framing as uncertain`
    );

    retryTracker.delete(idempotencyKey);

    return {
      action: "revise" as const,
      retry: {
        instruction:
          "Your previous response has repeatedly scored low confidence. Please restate your answer clearly framing it as uncertain or incomplete. Acknowledge what you do and do not know, and indicate where the user should seek additional verification.",
        idempotencyKey: `${idempotencyKey}-final`,
        maxAttempts: 1,
      },
    };
  }

  retryTracker.set(idempotencyKey, currentRetries + 1);

  return {
    action: "revise" as const,
    retry: {
      instruction: `Your self-assessment scored ${confidence}% confidence. Concerns: ${evalResult.concerns.join(
        "; "
      )}. What assumptions are you making in this response? What evidence supports or contradicts your claims?`,
      idempotencyKey,
      maxAttempts,
    },
  };
}

// ── Hedging heuristic ───────────────────────────────────────────────────────

function computeHedgingDensity(text: string): number {
  const words = text.trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return 0;

  let hedgingCount = 0;
  const lower = text.toLowerCase();

  for (const phrase of HEDGING_PHRASES) {
    const escaped = phrase.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp(escaped, "g");
    const matches = lower.match(re);
    if (matches) hedgingCount += matches.length;
  }

  return hedgingCount / words.length;
}

// ── LLM evaluation ──────────────────────────────────────────────────────────

interface EvalResult {
  confidence: number;
  concerns: string[];
  reasoning_strategies: string[];
}

async function llmEvaluateConfidence(message: string): Promise<EvalResult | undefined> {
  const apiKey = process.env.OPENROUTER_API_KEY?.trim();
  if (!apiKey) {
    console.warn("[confidence-check] OPENROUTER_API_KEY not set, skipping LLM eval");
    return undefined;
  }

  const prompt = `Evaluate the confidence of the following assistant response. Respond ONLY with a JSON object matching this exact schema:

{
  "confidence": <number 0-100>,
  "concerns": [<concern 1>, <concern 2>, ...],
  "reasoning_strategies": [<strategy 1>, <strategy 2>, ...]
}

Rules:
- confidence: 0 = completely uncertain/speculative, 100 = fully confident with clear evidence
- concerns: list specific weaknesses (e.g., "relies on assumption", "lacks source citation", "overgeneralizes")
- reasoning_strategies: suggest how the response could be improved (e.g., "cite specific source", "qualify scope", "provide concrete example")

ASSISTANT RESPONSE:
${message}

Return ONLY valid JSON. No markdown fences. No extra text.`;

  const resp = await fetch(OPENROUTER_API_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: EVAL_MODEL,
      max_tokens: 2048,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  if (!resp.ok) {
    const body = await resp.text().catch(() => "");
    throw new Error(`OpenRouter HTTP ${resp.status}: ${body.slice(0, 200)}`);
  }

  const data = (await resp.json()) as {
    choices?: { message?: { content?: string } }[];
  };

  const content = data.choices?.[0]?.message?.content?.trim() ?? "";
  if (!content) return undefined;

  // Strip markdown fences if present
  let jsonText = content;
  if (jsonText.startsWith("```")) {
    jsonText = jsonText.replace(/^```[a-zA-Z]*\n?/, "").replace(/\n?```$/, "").trim();
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonText);
  } catch (e) {
    throw new Error(`Failed to parse JSON: ${(e as Error).message}. Raw: ${jsonText.slice(0, 200)}`);
  }

  if (!isEvalResult(parsed)) {
    throw new Error(`Parsed JSON does not match expected shape: ${jsonText.slice(0, 200)}`);
  }

  return parsed;
}

function isEvalResult(v: unknown): v is EvalResult {
  if (typeof v !== "object" || v === null) return false;
  const o = v as Record<string, unknown>;
  return (
    typeof o.confidence === "number" &&
    Array.isArray(o.concerns) &&
    o.concerns.every((c) => typeof c === "string") &&
    Array.isArray(o.reasoning_strategies) &&
    o.reasoning_strategies.every((s) => typeof s === "string")
  );
}

// ── Plugin API type stubs ───────────────────────────────────────────────────
// Minimal type declarations for the Plugin SDK surface we use.

interface PluginApi {
  on(
    hook: string,
    handler: (event: unknown, ctx: PluginContext) => Promise<unknown | void>,
    options?: { timeoutMs?: number }
  ): void;
}

interface PluginContext {
  sessionKey?: string;
  agentId?: string;
  messageProvider?: string;
  runId?: string;
  [key: string]: unknown;
}
