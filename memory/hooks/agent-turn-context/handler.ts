/**
 * Agent Turn Context Hook
 *
 * Fires on every message:received event to inject per-turn context from the
 * agent_turn_context database table into the agent's context window.
 *
 * Context is scoped by type (UNIVERSAL → GLOBAL → DOMAIN → AGENT) and
 * cached per agent with a 5-minute TTL to avoid unnecessary DB queries.
 *
 * See: https://github.com/NOVA-Openclaw/nova-memory/issues/143
 */

import pg from "pg";
import { join } from "path";
import { homedir } from "os";

// Load PG env vars from postgres.json BEFORE creating the Pool.
// Without this, PGPASSWORD may be unset and node-pg falls back to ~/.pgpass.
// See: https://github.com/NOVA-Openclaw/nova-memory/issues/136
const pgEnvPath = join(homedir(), ".openclaw", "lib", "pg-env.ts");
const { loadPgEnv } = await import(pgEnvPath);
loadPgEnv();

const { Pool } = pg;

// Connection pool — reused across hook invocations
const pool = new Pool({
  host: process.env.PGHOST || "localhost",
  port: parseInt(process.env.PGPORT || "5432"),
  database: process.env.PGDATABASE || "nova_memory",
  user: process.env.PGUSER || "nova",
  password: process.env.PGPASSWORD,
  max: 5,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

// ============================================================
// In-memory cache: agent name → { content, timestamp }
// TTL: 5 minutes
// ============================================================

interface CacheEntry {
  content: string;
  truncated: boolean;
  recordsSkipped: number;
  totalChars: number;
  timestamp: number;
}

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes
const contextCache = new Map<string, CacheEntry>();

async function queryTurnContext(agentName: string): Promise<CacheEntry> {
  const client = await pool.connect();
  try {
    const result = await client.query(
      "SELECT content, truncated, records_skipped, total_chars FROM get_agent_turn_context($1)",
      [agentName]
    );
    const row = result.rows[0];
    return {
      content: row?.content ?? "",
      truncated: row?.truncated ?? false,
      recordsSkipped: row?.records_skipped ?? 0,
      totalChars: row?.total_chars ?? 0,
      timestamp: Date.now(),
    };
  } finally {
    client.release();
  }
}

async function getTurnContext(agentName: string): Promise<CacheEntry> {
  const cached = contextCache.get(agentName);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
    return cached;
  }
  // Cache miss or stale — query DB
  const entry = await queryTurnContext(agentName);
  contextCache.set(agentName, entry);
  return entry;
}

// ============================================================
// Hook handler
// ============================================================

const handler = async (event: any) => {
  // Only handle message:received events
  if (event.type !== "message" || event.action !== "received") {
    return;
  }

  try {
    // Resolve agent name from event context (default: 'nova')
    const agentName: string = (event.context as any)?.agentId || "nova";

    const ctx = await getTurnContext(agentName);

    if (ctx.content) {
      let injected = '📌 **Per-Turn Reminders:**\n' + ctx.content;

      if (ctx.truncated) {
        console.warn(
          `[agent-turn-context] WARNING: turn context truncated for agent '${agentName}' — ` +
          `${ctx.recordsSkipped} record(s) skipped, ${ctx.totalChars} chars exceeded 2000 budget`
        );
        injected += "\n\n⚠️ Turn context truncated — some critical rules may be missing. Alert I)ruid.";
      }

      event.messages.push(injected);
    }
  } catch (err) {
    // Fail silently — must not block message processing
    console.error(
      "[agent-turn-context] Error:",
      err instanceof Error ? err.message : String(err)
    );
  }
};

export default handler;
