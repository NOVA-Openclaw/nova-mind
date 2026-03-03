/**
 * pg-env.ts — Centralized PostgreSQL config loader for TypeScript/Node.js.
 *
 * Resolution order: ENV vars → ~/.openclaw/postgres.json → defaults
 * Issue: nova-memory #94
 */

import { readFileSync } from "fs";
import { homedir, userInfo } from "os";
import { join } from "path";

interface PgConfig {
  host?: string | null;
  port?: string | number | null;
  database?: string | null;
  user?: string | null;
  password?: string | null;
}

const FIELD_MAP: Array<[keyof PgConfig, string]> = [
  ["host", "PGHOST"],
  ["port", "PGPORT"],
  ["database", "PGDATABASE"],
  ["user", "PGUSER"],
  ["password", "PGPASSWORD"],
];

const DEFAULTS: Record<string, string | (() => string)> = {
  PGHOST: "localhost",
  PGPORT: "5432",
  PGUSER: () => userInfo().username,
};

/**
 * Load PostgreSQL env vars with resolution: ENV → config file → defaults.
 *
 * Sets process.env for each PG* var and returns the resulting record.
 * Empty ENV strings are treated as unset.
 * Null values in JSON are treated as absent.
 * Malformed JSON is caught and warned about (falls through to defaults).
 */
export function loadPgEnv(
  configPath?: string
): Record<string, string> {
  const cfgPath =
    configPath ?? join(homedir(), ".openclaw", "postgres.json");

  // Try to read config file
  let config: PgConfig = {};
  try {
    const raw = readFileSync(cfgPath, "utf-8");
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      config = parsed as PgConfig;
    } else {
      console.error(
        `WARNING: ${cfgPath} is not a JSON object, ignoring`
      );
    }
  } catch (e: unknown) {
    if (e && typeof e === "object" && "code" in e && (e as { code: string }).code === "ENOENT") {
      // File not found — fine, use defaults
    } else {
      console.error(
        `WARNING: Failed to read ${cfgPath}: ${e}, falling through to defaults`
      );
    }
  }

  const result: Record<string, string> = {};

  for (const [jsonKey, envVar] of FIELD_MAP) {
    // 1. Check ENV (empty string = unset)
    const envVal = process.env[envVar];
    if (envVal) {
      result[envVar] = envVal;
      continue;
    }

    // 2. Check config file (null/undefined = absent, empty string = absent)
    const cfgVal = config[jsonKey];
    if (cfgVal != null) {
      const strVal = String(cfgVal);
      if (strVal) {
        result[envVar] = strVal;
        process.env[envVar] = strVal;
        continue;
      }
    }

    // 3. Apply default
    const def = DEFAULTS[envVar];
    if (def !== undefined) {
      const defaultVal = typeof def === "function" ? def() : def;
      result[envVar] = defaultVal;
      process.env[envVar] = defaultVal;
    }
  }

  return result;
}
