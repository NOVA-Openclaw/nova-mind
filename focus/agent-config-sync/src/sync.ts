/**
 * Agent Config Sync — core logic
 *
 * Queries the `agents` table and builds the agents.json config as a bare JSON
 * array of non-peer agents. Writes atomically (tmp + rename) to prevent
 * partial reads.
 */

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import type pg from "pg";

// ── Types ───────────────────────────────────────────────────────────────────

export type AgentRow = {
  name: string;
  model: string;
  fallback_models: string[] | null;
  thinking: string | null;
  instance_type: string;
  is_default: boolean | null;
  allowed_subagents: string[] | null;
};

type AgentListEntry = {
  id: string;
  default?: true;
  model: string | { primary: string; fallbacks: string[] };
  subagents?: { allowAgents: string[] };
};

// ── SQL ─────────────────────────────────────────────────────────────────────

const AGENTS_QUERY = `
  SELECT name, model, fallback_models, thinking, instance_type, is_default, allowed_subagents
  FROM agents
  WHERE instance_type != 'peer'
    AND model IS NOT NULL
  ORDER BY name;
`;

// ── Build ───────────────────────────────────────────────────────────────────

/**
 * Build the agents list as a bare array from raw DB rows.
 *
 * - Peer agents are already excluded by the SQL query
 * - `default: true` included ONLY when is_default = true (key omitted otherwise)
 * - Empty or NULL fallback_models → string model form (not object)
 * - thinking column excluded from output (set at spawn time, not in agent definitions)
 * - subagents.allowAgents included when allowed_subagents is non-empty, sorted
 * - Output sorted by agent name (id)
 */
export function buildAgentsList(rows: AgentRow[]): AgentListEntry[] {
  const list: AgentListEntry[] = [];

  for (const row of rows) {
    const hasFallbacks =
      Array.isArray(row.fallback_models) && row.fallback_models.length > 0;

    // Build list entry
    const entry: AgentListEntry = {
      id: row.name,
      model: hasFallbacks
        ? { primary: row.model, fallbacks: [...row.fallback_models!] }
        : row.model,
    };

    // Include `"default": true` ONLY when is_default is explicitly true
    if (row.is_default === true) {
      entry.default = true;
    }

    // Note: 'thinking' is not a valid per-agent config key in OpenClaw's schema.
    // Thinking level is set at spawn time via sessions_spawn(thinking=...), not in agent definitions.
    // The DB 'thinking' column stores the preferred level for reference, but it's not written to agents.json.

    // Include subagents.allowAgents if set (sorted for stable output)
    if (Array.isArray(row.allowed_subagents) && row.allowed_subagents.length > 0) {
      entry.subagents = { allowAgents: [...row.allowed_subagents].sort() };
    }

    list.push(entry);
  }

  return list;
}

// ── Query ───────────────────────────────────────────────────────────────────

/**
 * Fetch agent rows from the database.
 */
export async function fetchAgentRows(client: pg.Client): Promise<AgentRow[]> {
  const result = await client.query<AgentRow>(AGENTS_QUERY);
  return result.rows;
}

// ── Write ───────────────────────────────────────────────────────────────────

/**
 * Write agents.json atomically (write to temp, then rename).
 * Accepts a bare array of agent list entries.
 */
export async function writeAgentsJsonAtomically(
  filePath: string,
  data: AgentListEntry[],
): Promise<void> {
  const dir = path.dirname(filePath);
  await fs.promises.mkdir(dir, { recursive: true });

  const tmpFile = path.join(
    dir,
    `${path.basename(filePath)}.${crypto.randomUUID()}.tmp`,
  );

  const content = JSON.stringify(data, null, 2) + "\n";

  await fs.promises.writeFile(tmpFile, content, { encoding: "utf-8" });
  await fs.promises.rename(tmpFile, filePath);
}

// ── Full sync ───────────────────────────────────────────────────────────────

/**
 * Perform a full sync: query DB → build JSON array → write file.
 * Returns true if the file was changed, false if identical.
 */
export async function syncAgentsConfig(
  client: pg.Client,
  outputPath: string,
): Promise<boolean> {
  const rows = await fetchAgentRows(client);
  const data = buildAgentsList(rows);
  const newContent = JSON.stringify(data, null, 2) + "\n";

  // Check if file already matches (avoid unnecessary writes / watcher triggers)
  try {
    const existing = await fs.promises.readFile(outputPath, "utf-8");
    if (existing === newContent) {
      return false;
    }
  } catch {
    // File doesn't exist yet — continue to write
  }

  await writeAgentsJsonAtomically(outputPath, data);
  return true;
}
