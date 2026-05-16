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
export default function register(api: PluginApi): void;
interface PluginApi {
    on(hook: string, handler: (event: PluginEvent, ctx: PluginContext) => Promise<void>, options?: {
        timeoutMs?: number;
    }): void;
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
export {};
