/**
 * Self-Awareness Plugin — index.ts
 *
 * Monitors outbound messages (message_sent hook) for patterns that indicate
 * self-awareness, significant conversation, uncertainty, or memory reinforcement.
 *
 * Flow per outbound message:
 *   1. Load all enabled triggers from self_awareness_triggers
 *   2. Skip triggers on cooldown (NOW() - last_triggered_at < cooldown_minutes)
 *   3. Self-heal: if keyphrase_embeddings is NULL, embed via Ollama and store
 *   4. Embed the outbound message via Ollama
 *   5. Compute cosine similarity between message embedding and each trigger's
 *      keyphrase embeddings
 *   6. If best match exceeds trigger.similarity_threshold, fire action
 *   7. Update last_triggered_at and increment times_triggered
 *
 * All work is fire-and-forget (async, never blocks message delivery).
 * Graceful degradation: catch ollama errors, DB errors — log warning, don't crash.
 *
 * Issue: #221
 */

import { getPool } from "./shared/pg-pool.ts";

// ── Ollama config ─────────────────────────────────────────────────────────────

const OLLAMA_HOST = process.env.OLLAMA_HOST || "http://localhost:11434";
const EMBED_MODEL = "snowflake-arctic-embed2";

// ── Plugin entry ──────────────────────────────────────────────────────────────

interface TriggerRow {
  id: number;
  name: string;
  category: string;
  keyphrases: string[];
  keyphrase_embeddings: number[][] | null;
  similarity_threshold: number;
  action: string;
  action_config: Record<string, unknown> | null;
  cooldown_minutes: number;
  last_triggered_at: Date | null;
  times_triggered: number;
}

export default function register(api: PluginApi): void {
  console.info("[self-awareness] Plugin registered — hook: message_sent");

  api.on(
    "message_sent",
    async (event: PluginEvent, ctx: PluginContext) => {
      // Fire-and-forget: don't await the inner processing
      processMessageSent(event, ctx).catch((err) => {
        console.error(
          "[self-awareness] Unhandled error in message_sent handler:",
          err instanceof Error ? err.message : String(err)
        );
      });
    }
  );
}

async function processMessageSent(
  event: PluginEvent,
  ctx: PluginContext
): Promise<void> {
  const content = event.content || "";
  if (!content.trim()) return;

  const agentId = ctx.agentId ?? "nova";

  let pool: import("pg").Pool | undefined;
  try {
    pool = getPool();
  } catch (e) {
    console.warn("[self-awareness] Could not get pg pool:", (e as Error).message);
    return;
  }

  // ── Load enabled triggers ─────────────────────────────────────────────────
  let triggers: TriggerRow[] = [];
  try {
    const result = await pool.query<TriggerRow>(
      `SELECT id, name, category, keyphrases, keyphrase_embeddings,
              similarity_threshold, action, action_config,
              cooldown_minutes, last_triggered_at, times_triggered
       FROM self_awareness_triggers
       WHERE enabled = true`
    );
    triggers = result.rows;
  } catch (e) {
    console.warn("[self-awareness] DB query failed:", (e as Error).message);
    return;
  }

  if (triggers.length === 0) {
    console.debug("[self-awareness] No enabled triggers");
    return;
  }

  // ── Resolve subagent → parent
  const resolvedAgentId = await resolveSubagentToParent(agentId, pool);
  console.info(`[self-awareness] agentId=${agentId} resolvedSender=${resolvedAgentId}`);

  // ── Embed message content once ────────────────────────────────────────────
  let messageEmbedding: number[] | undefined;
  try {
    messageEmbedding = await embedViaOllama(content);
  } catch (e) {
    console.warn(
      "[self-awareness] Ollama embedding failed for message, skipping:",
      (e as Error).message
    );
    return;
  }

  // ── Evaluate each trigger ─────────────────────────────────────────────────
  for (const trigger of triggers) {
    // Cooldown check
    if (trigger.last_triggered_at) {
      const elapsedMinutes =
        (Date.now() - new Date(trigger.last_triggered_at).getTime()) / 60000;
      if (elapsedMinutes < trigger.cooldown_minutes) {
        console.debug(
          `[self-awareness] Trigger '${trigger.name}' on cooldown (${elapsedMinutes.toFixed(1)} < ${trigger.cooldown_minutes} min)`
        );
        continue;
      }
    }

    // Self-heal: populate keyphrase_embeddings if NULL
    let embeddings = trigger.keyphrase_embeddings;
    if (!embeddings || embeddings.length === 0) {
      try {
        embeddings = await selfHealKeyphrases(trigger.id, trigger.keyphrases, pool);
      } catch (e) {
        console.warn(
          `[self-awareness] Self-heal failed for '${trigger.name}':`,
          (e as Error).message
        );
        continue;
      }
    }

    if (!embeddings || embeddings.length === 0) {
      console.warn(`[self-awareness] No embeddings for '${trigger.name}', skipping`);
      continue;
    }

    // Compute best similarity
    let bestSim = -Infinity;
    for (const ke of embeddings) {
      const sim = cosineSimilarity(messageEmbedding, ke);
      if (sim > bestSim) bestSim = sim;
    }
    console.info(
      `[self-awareness] '${trigger.name}' best similarity=${bestSim.toFixed(3)} threshold=${trigger.similarity_threshold}`
    );

    if (bestSim >= trigger.similarity_threshold) {
      // Fire action
      await fireAction(trigger, content, bestSim, resolvedAgentId, pool);

      // Update trigger stats
      try {
        await pool.query(
          `UPDATE self_awareness_triggers
           SET last_triggered_at = NOW(), times_triggered = times_triggered + 1
           WHERE id = $1`,
          [trigger.id]
        );
      } catch (e) {
        console.warn("[self-awareness] Failed to update trigger stats:", (e as Error).message);
      }
    }
  }
}

// ── Subagent → parent resolution ──────────────────────────────────────────────

async function resolveSubagentToParent(
  agentId: string,
  pool: import("pg").Pool
): Promise<string> {
  try {
    const result = await pool.query<{ parent_id: number | null; parent_name: string | null }>(
      `SELECT p.id AS parent_id, p.name AS parent_name
       FROM agents a
       JOIN agents p ON a.parent_agent_id = p.id
       WHERE a.name = $1 AND a.instance_type = 'subagent'
       LIMIT 1`,
      [agentId]
    );
    if (result.rows.length > 0 && result.rows[0].parent_name) {
      return result.rows[0].parent_name;
    }
  } catch (e) {
    console.warn("[self-awareness] Subagent resolution failed:", (e as Error).message);
  }
  return agentId;
}

// ── Embedding via Ollama ──────────────────────────────────────────────────────

interface OllamaEmbedResponse {
  embedding: number[];
}

async function embedViaOllama(text: string): Promise<number[]> {
  const url = `${OLLAMA_HOST.replace(/\/$/, "")}/api/embeddings`;
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model: EMBED_MODEL, prompt: text }),
  });
  if (!resp.ok) {
    const body = await resp.text().catch(() => "");
    throw new Error(`Ollama embed HTTP ${resp.status}: ${body.slice(0, 200)}`);
  }
  const data = (await resp.json()) as OllamaEmbedResponse;
  if (!Array.isArray(data.embedding)) {
    throw new Error("Ollama embed response missing embedding array");
  }
  return data.embedding;
}

async function selfHealKeyphrases(
  triggerId: number,
  keyphrases: string[],
  pool: import("pg").Pool
): Promise<number[][]> {
  console.info(`[self-awareness] Self-heal: embedding ${keyphrases.length} keyphrases for trigger ${triggerId}`);
  const embeddings: number[][] = [];
  for (const kp of keyphrases) {
    try {
      const emb = await embedViaOllama(kp);
      embeddings.push(emb);
    } catch (e) {
      console.warn(`[self-awareness] Failed to embed keyphrase '${kp}':`, (e as Error).message);
    }
  }

  if (embeddings.length > 0) {
    try {
      await pool.query(
        `UPDATE self_awareness_triggers SET keyphrase_embeddings = $1::jsonb WHERE id = $2`,
        [JSON.stringify(embeddings), triggerId]
      );
    } catch (e) {
      console.warn("[self-awareness] Failed to store healed embeddings:", (e as Error).message);
    }
  }

  return embeddings;
}

// ── Cosine similarity ─────────────────────────────────────────────────────────

function cosineSimilarity(a: number[], b: number[]): number {
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

// ── Action dispatch ───────────────────────────────────────────────────────────

async function fireAction(
  trigger: TriggerRow,
  messageContent: string,
  similarity: number,
  resolvedAgentId: string,
  pool: import("pg").Pool
): Promise<void> {
  const config = trigger.action_config || {};

  console.info(
    `[self-awareness] TRIGGER FIRED: '${trigger.name}' ` +
      `category=${trigger.category} sim=${similarity.toFixed(3)} ` +
      `action=${trigger.action}`
  );

  switch (trigger.action) {
    case "log_only": {
      const logCategory = (config.log_category as string) || trigger.category;
      console.info(`[self-awareness] [${logCategory}] ${trigger.name}: ${messageContent.slice(0, 200)}`);
      if (config.flag_for_review) {
        console.warn(`[self-awareness] FLAG FOR REVIEW: '${trigger.name}' on agent=${resolvedAgentId}`);
      }
      break;
    }

    case "system_event": {
      console.info(`[self-awareness] SYSTEM_EVENT: '${trigger.name}' emitted`);
      break;
    }

    case "database_update": {
      // Handled by extraction pipeline — log intent
      console.info(`[self-awareness] DATABASE_UPDATE: '${trigger.name}' would trigger extraction`);
      break;
    }

    case "context_inject": {
      console.info(`[self-awareness] CONTEXT_INJECT: '${trigger.name}' would inject context`);
      break;
    }

    default: {
      console.warn(`[self-awareness] Unknown action_type '${trigger.action}' for trigger '${trigger.name}', skipping`);
    }
  }
}

// ── Plugin API type stubs ─────────────────────────────────────────────────────
// Minimal type declarations for the Plugin SDK surface we use.
// The actual types come from the OpenClaw plugin loader at runtime.

interface PluginApi {
  on(
    hook: string,
    handler: (event: PluginEvent, ctx: PluginContext) => Promise<void>,
    options?: { timeoutMs?: number }
  ): void;
}

interface PluginEvent {
  content?: string;
  metadata?: Record<string, unknown>;
  runId?: string;
  [key: string]: unknown;
}

interface PluginContext {
  sessionKey?: string;
  agentId?: string;
  messageProvider?: string;
  runId?: string;
  [key: string]: unknown;
}
