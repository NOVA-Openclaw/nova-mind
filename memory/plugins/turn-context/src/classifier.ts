/**
 * Message Type Classifier
 *
 * Classifies inbound messages into one of:
 *   info_request | action | conversation | continuation | command
 *
 * Strategy:
 *   1. Rule-based fast pass (handles 60-70% of cases)
 *   2. Ollama LLM fallback for ambiguous cases (2000ms timeout)
 *   3. Default to 'conversation' on failure
 *
 * Issues: nova-mind #150
 */

import * as http from "http";

export type MessageType =
  | "info_request"
  | "action"
  | "conversation"
  | "continuation"
  | "command";

export interface ClassifierResult {
  type: MessageType;
  domainHints?: string[];
  method?: "rule" | "ollama" | "default";
}

// ── Configuration ─────────────────────────────────────────────────────────────

const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || "http://localhost:11434";
const OLLAMA_CLASSIFY_MODEL =
  process.env.OLLAMA_CLASSIFY_MODEL || "phi4-mini:latest";
const OLLAMA_TIMEOUT_MS = 2000;

// ── Rule sets ─────────────────────────────────────────────────────────────────

/** Known continuation phrases (short acknowledgments / affirmations) */
const CONTINUATION_PHRASES = new Set([
  "ok",
  "okay",
  "sure",
  "yep",
  "yeah",
  "yes",
  "k",
  "no",
  "nope",
  "got it",
  "cool",
  "great",
  "nice",
  "thanks",
  "thx",
  "ty",
  "np",
  "done",
  "go",
  "next",
  "ack",
  "fine",
  "good",
  "alright",
  "right",
  "noted",
  "understood",
  "roger",
]);

/** Starts with an imperative action verb → action */
const ACTION_VERB_RE =
  /^(create|search|add|delete|update|run|check|deploy|fix|build|show|get|list|find|open|close|start|stop|send|post|push|pull|fetch|make|generate|write|read|review|test|debug|install|configure|setup|set|remove|move|copy|rename|edit|save|load|export|import|download|upload|scan|analyze|monitor|report|summarize|explain|describe|enable|disable|restart|reset|clear|flush|convert|compile|format|lint|validate|seed|migrate|rollback|backup|restore|deploy|launch|kill|exec|execute|query|lookup|compare|benchmark|inspect|dump|extract|parse|transform)\b/i;

/** Interrogative words indicating an info request */
const INTERROGATIVE_RE = /\b(who|what|where|when|why|how)\b/i;

/** Greeting openers → conversation */
const GREETING_RE =
  /^(hi\b|hey\b|hello\b|howdy\b|greetings\b|good\s+(morning|afternoon|evening|day)\b|what'?s\s+up\b|sup\b|yo\b|howzit\b|hiya\b|heya\b)/i;

// ── Rule-based classification ─────────────────────────────────────────────────

/**
 * Attempt to classify the message using deterministic rules.
 * Returns null if the message is ambiguous (needs Ollama fallback).
 */
function classifyByRules(content: string): ClassifierResult | null {
  const trimmed = content.trim();

  // Empty or whitespace-only → continuation
  if (!trimmed || /^\s+$/.test(trimmed)) {
    return { type: "continuation", method: "rule" };
  }

  // Command: starts with / or !
  if (/^[/!]/.test(trimmed)) {
    return { type: "command", method: "rule" };
  }

  // Continuation: single > character (workflow advance signal per GLOBAL/PROCESS_AND_COORDINATION)
  if (trimmed === ">") {
    return { type: "continuation", method: "rule" };
  }

  const lower = trimmed.toLowerCase();

  // Continuation: known acknowledgment phrases (multi-word matches first)
  if (CONTINUATION_PHRASES.has(lower)) {
    return { type: "continuation", method: "rule" };
  }

  // Continuation: ≤5 chars with no spaces (single short word)
  if (trimmed.length <= 5 && !/\s/.test(trimmed)) {
    return { type: "continuation", method: "rule" };
  }

  // Greeting → conversation (check before action verbs, since "hello" could be a verb)
  if (GREETING_RE.test(trimmed)) {
    return { type: "conversation", method: "rule" };
  }

  // Info request: contains a question mark (with or without interrogative word)
  if (trimmed.includes("?")) {
    return { type: "info_request", method: "rule" };
  }

  // Info request: interrogative word even without ?
  if (INTERROGATIVE_RE.test(trimmed)) {
    return { type: "info_request", method: "rule" };
  }

  // Action: starts with an imperative verb
  if (ACTION_VERB_RE.test(trimmed)) {
    return { type: "action", method: "rule" };
  }

  // Ambiguous — needs Ollama fallback
  return null;
}

// ── Ollama LLM fallback ───────────────────────────────────────────────────────

/**
 * Call Ollama for LLM-based message classification.
 * 2000ms hard timeout — on failure, caller should default to 'conversation'.
 */
function callOllamaClassify(content: string): Promise<ClassifierResult> {
  const safeContent = content.substring(0, 500).replace(/\\/g, "\\\\").replace(/"/g, '\\"');

  const prompt = `Classify this message into EXACTLY ONE category:
- info_request: asking for information, facts, status, or explanation
- action: requesting an operation, task, or command to be performed
- conversation: casual chat, social exchange, sharing context
- continuation: brief acknowledgment like "ok", "sure", or follow-up to prior context
- command: starts with / or ! prefix

Message: "${safeContent}"

Respond with ONLY valid JSON (no markdown):
{"type": "<one of the 5 types>", "domainHints": ["<relevant domain keywords, omit if none>"]}`;

  const body = JSON.stringify({
    model: OLLAMA_CLASSIFY_MODEL,
    prompt,
    stream: false,
    format: "json",
    options: { temperature: 0, num_predict: 120 },
  });

  return new Promise((resolve, reject) => {
    let req: http.ClientRequest;

    const timeout = setTimeout(() => {
      req?.destroy();
      reject(new Error(`Ollama classify timeout after ${OLLAMA_TIMEOUT_MS}ms`));
    }, OLLAMA_TIMEOUT_MS);

    try {
      const url = new URL(`${OLLAMA_BASE_URL}/api/generate`);
      const options: http.RequestOptions = {
        hostname: url.hostname,
        port: parseInt(url.port || "80", 10),
        path: url.pathname,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(body),
        },
      };

      req = http.request(options, (res) => {
        let data = "";
        res.on("data", (chunk: Buffer) => {
          data += chunk.toString();
        });
        res.on("end", () => {
          clearTimeout(timeout);
          try {
            const ollamaResp = JSON.parse(data);
            const respText: string = ollamaResp.response || "{}";
            const parsed = JSON.parse(respText);
            const validTypes: MessageType[] = [
              "info_request",
              "action",
              "conversation",
              "continuation",
              "command",
            ];
            const type: MessageType = validTypes.includes(parsed.type as MessageType)
              ? (parsed.type as MessageType)
              : "conversation";
            const rawHints = parsed.domainHints;
            const domainHints: string[] | undefined =
              Array.isArray(rawHints) && rawHints.length > 0
                ? rawHints.filter((h: unknown) => typeof h === "string")
                : undefined;
            resolve({ type, domainHints, method: "ollama" });
          } catch (err) {
            reject(new Error(`Ollama classify parse error: ${err}`));
          }
        });
      });

      req.on("error", (err: Error) => {
        clearTimeout(timeout);
        reject(err);
      });

      req.write(body);
      req.end();
    } catch (err) {
      clearTimeout(timeout);
      reject(err);
    }
  });
}

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Classify a message into one of the five message types.
 *
 * Rule-based classification handles 60-70% of cases without LLM overhead.
 * Ambiguous messages fall back to Ollama (2000ms timeout).
 * On any failure, defaults to 'conversation'.
 *
 * @param content The message content to classify
 * @returns ClassifierResult with type, optional domainHints, and method used
 */
export async function classifyMessage(content: string): Promise<ClassifierResult> {
  // Rule-based first pass — fast, deterministic
  const ruleResult = classifyByRules(content);
  if (ruleResult) {
    return ruleResult;
  }

  // Ollama fallback for ambiguous messages
  try {
    const ollamaResult = await callOllamaClassify(content);
    return ollamaResult;
  } catch (err) {
    console.warn(
      "[turn-context] Classifier Ollama fallback failed:",
      err instanceof Error ? err.message : String(err)
    );
    return { type: "conversation", method: "default" };
  }
}
