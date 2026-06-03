/**
 * Agent Config Sync — core logic
 *
 * Queries the `agents` table and builds the agents.json config as a bare JSON
 * array of non-peer agents. Writes atomically (tmp + rename) to prevent
 * partial reads.
 *
 * Also syncs HEARTBEAT.md files from `agent_bootstrap_context` to the correct
 * workspace directories for each agent.
 */

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import type pg from "pg";

// ── Types ───────────────────────────────────────────────────────────────────

export type HeartbeatRow = {
  agent_name: string;
  content: string;
};

export type AgentRow = {
  name: string;
  model: string;
  fallback_models: string[] | null;
  thinking: string | null;
  instance_type: string;
  is_default: boolean | null;
  allowed_subagents: string[] | null;
  // #262 — Per-agent heartbeat config (optional: present once DB migration applied)
  heartbeat_enabled?: boolean | null;
  heartbeat_every?: string | null;
  heartbeat_target?: string | null;
  heartbeat_to?: string | null;
};

type HeartbeatConfig = { every?: string; target?: string; to?: string };

type AgentListEntry = {
  id: string;
  default?: true;
  model: string | { primary: string; fallbacks: string[] };
  subagents?: { allowAgents: string[] };
  heartbeat?: HeartbeatConfig;
};

// ── SQL ─────────────────────────────────────────────────────────────────────

// Queries get_agent_export_rows(), which scopes results to the connecting role
// (session_user) and subagents owning that role via `parent_agents` array overlap.
// The function lives in nova-mind/database/schema.sql and is owned by newhart.
const AGENTS_QUERY = `
  SELECT name, model, fallback_models, thinking, instance_type, is_default, allowed_subagents,
         heartbeat_enabled, heartbeat_every, heartbeat_target, heartbeat_to
  FROM get_agent_export_rows();
`;

// Queries HEARTBEAT records for all agents that have agent-scoped entries.
const HEARTBEAT_QUERY = `
  SELECT agent_name, content
  FROM agent_bootstrap_context
  WHERE file_key = 'HEARTBEAT'
    AND agent_name IS NOT NULL
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

    // #262/#273 — Per-agent heartbeat config
    // OpenClaw schema requires heartbeat to be an object, not a boolean.
    // heartbeat_enabled = true  → emit heartbeat object with non-NULL sub-fields only
    // heartbeat_enabled = false | NULL → omit key (inherits agents.defaults.heartbeat)
    if (row.heartbeat_enabled === true && row.heartbeat_every) {
      const hb: HeartbeatConfig = { every: row.heartbeat_every };
      if (row.heartbeat_target) hb.target = row.heartbeat_target;
      if (row.heartbeat_to) hb.to = row.heartbeat_to;
      entry.heartbeat = hb;
    }

    list.push(entry);
  }

  // Sort by agent name (id) for stable, deterministic output
  return list.sort((a, b) => a.id.localeCompare(b.id));
}

// ── Query ───────────────────────────────────────────────────────────────────

/**
 * Fetch agent rows from the database.
 */
export async function fetchAgentRows(client: pg.Client): Promise<AgentRow[]> {
  const result = await client.query<AgentRow>(AGENTS_QUERY);
  return result.rows;
}

/**
 * Fetch HEARTBEAT records for all agents from agent_bootstrap_context.
 */
export async function fetchHeartbeatRecords(
  client: pg.Client,
): Promise<HeartbeatRow[]> {
  const result = await client.query<HeartbeatRow>(HEARTBEAT_QUERY);
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

// ── Heartbeat sync ─────────────────────────────────────────────────────────

/**
 * Sync HEARTBEAT.md files for all agents from agent_bootstrap_context.
 *
 * Workspace routing:
 *   - defaultAgentName → <stateDir>/workspace/HEARTBEAT.md
 *   - all others       → <stateDir>/workspace-<agent_name>/HEARTBEAT.md
 *
 * Uses atomic writes (tmp + rename). Skips write when content is unchanged.
 * Creates workspace directory if it does not exist.
 *
 * Returns a list of agent names whose HEARTBEAT.md files were updated.
 */
export async function syncHeartbeatFiles(
  client: pg.Client,
  stateDir: string,
  defaultAgentName: string,
): Promise<string[]> {
  const rows = await fetchHeartbeatRecords(client);
  const updated: string[] = [];

  for (const row of rows) {
    const wsDir =
      row.agent_name === defaultAgentName
        ? path.join(stateDir, "workspace")
        : path.join(stateDir, `workspace-${row.agent_name}`);

    const filePath = path.join(wsDir, "HEARTBEAT.md");
    const newContent = row.content;

    // Skip write if content is NULL — preserve existing file
    if (newContent == null) continue;

    // Skip write if content unchanged
    try {
      const existing = await fs.promises.readFile(filePath, "utf-8");
      if (existing === newContent) continue;
    } catch {
      // File doesn't exist yet — continue to write
    }

    // Create workspace directory if needed
    await fs.promises.mkdir(wsDir, { recursive: true });

    // Atomic write: tmp file + rename
    const tmpFile = path.join(
      wsDir,
      `HEARTBEAT.md.${crypto.randomUUID()}.tmp`,
    );
    await fs.promises.writeFile(tmpFile, newContent, { encoding: "utf-8" });
    await fs.promises.rename(tmpFile, filePath);

    updated.push(row.agent_name);
  }

  return updated;
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
