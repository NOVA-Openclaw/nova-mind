#!/usr/bin/env tsx
/**
 * TC-707-013: Cutover drift report.
 *
 * Read-only tool that:
 *   1. Generates the agents.json that would be produced from the live
 *      `get_agent_export_rows()` result.
 *   2. Reads the current inline `agents.entries` from the live OpenClaw config.
 *   3. Reports every field that differs for agents present in both, and lists
 *      agents that exist only in the generated DB roster.
 *
 * This tool does NOT write anything. It is intended to be run before switching
 * `agents.entries` to `{ "$include": "./agents.json" }` so the operator can
 * reconcile drift instead of silently cutting over.
 *
 * Run:
 *   cd cognition/focus/agent-config-sync
 *   npx tsx scripts/report-cutover-drift.ts
 *
 * Environment:
 *   OPENCLAW_DIR  — directory containing openclaw.json (default: ~/.openclaw)
 */

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { Client } from "pg";
import { buildAgentsList } from "../src/sync.js";
import type { AgentEntryConfig } from "../src/sync.js";

const OPENCLAW_DIR = process.env.OPENCLAW_DIR ?? path.join(os.homedir(), ".openclaw");
const OPENCLAW_CONFIG = path.join(OPENCLAW_DIR, "openclaw.json");

// ── Read DB config ──────────────────────────────────────────────────────────

async function loadDbConfig(): Promise<{
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
}> {
  const pgConfigPath = path.join(OPENCLAW_DIR, "postgres.json");
  if (fs.existsSync(pgConfigPath)) {
    const raw = JSON.parse(fs.readFileSync(pgConfigPath, "utf-8"));
    return {
      host: String(raw.host ?? "localhost"),
      port: Number(raw.port ?? 5432),
      database: String(raw.database ?? `${process.env.USER ?? "nova"}_memory`),
      user: String(raw.user ?? process.env.USER ?? "nova"),
      password: String(raw.password ?? ""),
    };
  }
  return {
    host: process.env.PGHOST ?? "localhost",
    port: Number(process.env.PGPORT ?? 5432),
    database: process.env.PGDATABASE ?? `${process.env.USER ?? "nova"}_memory`,
    user: process.env.PGUSER ?? process.env.USER ?? "nova",
    password: process.env.PGPASSWORD ?? "",
  };
}

// ── Read current inline agents.entries ──────────────────────────────────────

function loadInlineEntries(): Record<string, AgentEntryConfig> | null {
  if (!fs.existsSync(OPENCLAW_CONFIG)) {
    console.error(`OpenClaw config not found: ${OPENCLAW_CONFIG}`);
    return null;
  }
  const raw = JSON.parse(fs.readFileSync(OPENCLAW_CONFIG, "utf-8"));
  const entries = raw?.agents?.entries;
  if (entries == null) {
    console.error("No inline agents.entries found in openclaw.json");
    return null;
  }
  if (typeof entries === "object" && !Array.isArray(entries)) {
    // Skip if it's already an $include directive — nothing to diff against.
    if (Object.hasOwn(entries, "$include")) {
      console.error(
        "agents.entries is already an $include directive; no inline entries to diff against.",
      );
      return null;
    }
    return entries as Record<string, AgentEntryConfig>;
  }
  console.error("agents.entries is not a keyed object");
  return null;
}

// ── Diff helpers ────────────────────────────────────────────────────────────

function isScalar(value: unknown): boolean {
  return value === null || ["string", "number", "boolean"].includes(typeof value);
}

function jsonEqual(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

function* diffFields(
  agentId: string,
  generated: AgentEntryConfig,
  inline: AgentEntryConfig,
  prefix = "",
): Generator<string> {
  const keys = new Set([
    ...Object.keys(generated),
    ...Object.keys(inline),
  ]);
  for (const key of keys) {
    const path = prefix ? `${prefix}.${key}` : key;
    const g = (generated as Record<string, unknown>)[key];
    const i = (inline as Record<string, unknown>)[key];
    if (g === undefined && i !== undefined) {
      yield `${agentId}: generated missing ${path} (inline has ${JSON.stringify(i)})`;
      continue;
    }
    if (i === undefined && g !== undefined) {
      yield `${agentId}: inline missing ${path} (generated has ${JSON.stringify(g)})`;
      continue;
    }
    if (isScalar(g) || isScalar(i)) {
      if (!jsonEqual(g, i)) {
        yield `${agentId}: ${path} differs — generated=${JSON.stringify(g)} inline=${JSON.stringify(i)}`;
      }
      continue;
    }
    // Both objects — recurse.
    yield* diffFields(agentId, g as AgentEntryConfig, i as AgentEntryConfig, path);
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const inlineEntries = loadInlineEntries();
  if (inlineEntries == null) {
    process.exit(1);
  }

  const dbConfig = await loadDbConfig();
  const client = new Client(dbConfig);
  try {
    await client.connect();
    const result = await client.query<{
      name: string;
      model: string | null;
      fallback_models: string[] | null;
      thinking: string | null;
      instance_type: string;
      is_default: boolean | null;
      allowed_subagents: string[] | null;
      heartbeat_enabled: boolean | null;
      heartbeat_every: string | null;
      heartbeat_target: string | null;
      heartbeat_to: string | null;
    }>(`
      SELECT name, model, fallback_models, thinking, instance_type, is_default, allowed_subagents,
             heartbeat_enabled, heartbeat_every, heartbeat_target, heartbeat_to
      FROM get_agent_export_rows();
    `);
    const { entries: generatedEntries } = buildAgentsList(result.rows);

    const inlineIds = Object.keys(inlineEntries);
    const generatedIds = Object.keys(generatedEntries);
    const commonIds = inlineIds.filter((id) => generatedIds.includes(id));
    const dbOnlyIds = generatedIds.filter((id) => !inlineIds.includes(id));

    console.log("=== TC-707-013 Cutover Drift Report ===");
    console.log(`Inline agents.entries count: ${inlineIds.length}`);
    console.log(`Generated DB roster count:   ${generatedIds.length}`);
    console.log("");

    let driftCount = 0;
    for (const id of commonIds.sort((a, b) => a.localeCompare(b))) {
      const diffs = [...diffFields(id, generatedEntries[id]!, inlineEntries[id]!)];
      if (diffs.length > 0) {
        driftCount += diffs.length;
        for (const line of diffs) {
          console.log(line);
        }
      }
    }

    if (dbOnlyIds.length > 0) {
      console.log("");
      console.log(`New agents this cutover would ADD (${dbOnlyIds.length}):`);
      for (const id of dbOnlyIds.sort((a, b) => a.localeCompare(b))) {
        console.log(`  - ${id}: model=${JSON.stringify(generatedEntries[id]!.model)}`);
      }
    }

    console.log("");
    if (driftCount === 0 && dbOnlyIds.length === 0) {
      console.log("RESULT: no drift detected.");
      process.exit(0);
    }
    console.log(
      `RESULT: ${driftCount} field diff(s) across ${commonIds.length} shared agent(s); ${dbOnlyIds.length} DB-only agent(s). Review before enabling $include.`,
    );
    process.exit(2); // exit 2 signals drift exists without failing the tool contract
  } finally {
    await client.end();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
