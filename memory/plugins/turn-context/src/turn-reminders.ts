/**
 * Turn Reminders subsystem.
 *
 * Queries get_agent_turn_context() from the nova_memory DB and caches the
 * result per agent name with a 5-minute TTL.
 *
 * Ported from ~/.openclaw/hooks/agent-turn-context/handler.ts
 * Issue: nova-mind #182
 */

import { getPool } from "./shared/pg-pool.ts";

// ── Types ────────────────────────────────────────────────────────────────────

interface CacheEntry {
  content: string;
  truncated: boolean;
  recordsSkipped: number;
  totalChars: number;
  timestamp: number;
}

// ── Cache ────────────────────────────────────────────────────────────────────

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes
const contextCache = new Map<string, CacheEntry>();

// ── DB query ─────────────────────────────────────────────────────────────────

async function queryTurnContext(agentName: string): Promise<CacheEntry> {
  const pool = getPool();
  const client = await pool.connect();
  try {
    const result = await client.query<{
      content: string;
      truncated: boolean;
      records_skipped: number;
      total_chars: number;
    }>(
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

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Return formatted turn-reminders text for the given agent, or null if empty.
 *
 * Uses a 5-minute in-process cache to avoid hammering the DB every message.
 */
export async function getTurnReminders(agentName: string): Promise<string | null> {
  // Check cache
  const cached = contextCache.get(agentName);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
    // Cache hit
    return formatReminders(cached, agentName);
  }

  // Cache miss or stale — query DB
  const entry = await queryTurnContext(agentName);
  contextCache.set(agentName, entry);
  return formatReminders(entry, agentName);
}

function formatReminders(entry: CacheEntry, agentName: string): string | null {
  if (!entry.content) return null;

  let text = `📌 **Per-Turn Reminders:**\n${entry.content}`;

  if (entry.truncated) {
    console.warn(
      `[turn-context] WARNING: turn context truncated for agent '${agentName}' — ` +
      `${entry.recordsSkipped} record(s) skipped, ${entry.totalChars} chars exceeded budget`
    );
    text += "\n\n⚠️ Turn context truncated — some critical rules may be missing. Alert I)ruid.";
  }

  return text;
}
