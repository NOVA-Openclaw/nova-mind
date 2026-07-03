/**
 * pg-env.ts — Centralized PostgreSQL config loader for TypeScript/Node.js
 * with optional nested-section support.
 *
 * Resolution order: ENV vars → section → ~/.openclaw/postgres.json (flat keys) → defaults
 * Issue: nova-memory #94, nova-mind #330, nova-mind #320
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
  [key: string]: unknown;
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
 * PostgreSQL connection options interface that matches
 * the pg.Client constructor options.
 */
export interface PgConnectionConfig {
  host?: string;
  port?: number;
  database?: string;
  user?: string;
  password?: string;
}

/**
 * Load PostgreSQL config with resolution: ENV → section → config file → defaults.
 *
 * Returns connection config object suitable for pg.Client / pg.Pool constructor,
 * without modifying process.env to avoid pollution of the environment
 * for child processes and subagents.
 * Empty ENV strings are treated as unset.
 * Null values in JSON are treated as absent.
 * Malformed JSON is caught and warned about (falls through to defaults).
 *
 * If `section` is provided and the parsed config contains a valid object for that
 * key, section fields take precedence over top-level keys (ENV still wins).
 */
export function loadPgEnv(
  configPath?: string,
  section?: string
): PgConnectionConfig {
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

  // Resolve nested section if requested. A non-object section mirrors the
  // top-level object-type guard: warn and fall back to top-level keys.
  let sectionConfig: PgConfig | undefined;
  if (section) {
    const sectionValue = config[section];
    if (sectionValue && typeof sectionValue === "object" && !Array.isArray(sectionValue)) {
      sectionConfig = sectionValue as PgConfig;
    } else if (sectionValue !== undefined) {
      console.error(
        `WARNING: ${cfgPath}.${section} is not a JSON object, ignoring`
      );
    }
  }

  const result: PgConnectionConfig = {};

  for (const [jsonKey, envVar] of FIELD_MAP) {
    // 1. Check ENV (empty string = unset)
    const envVal = process.env[envVar];
    if (envVal) {
      if (jsonKey === "port") {
        const portNum = Number(envVal);
        if (!isNaN(portNum)) result[jsonKey] = portNum;
      } else {
        result[jsonKey] = envVal;
      }
      continue;
    }

    // 2. Check section config (null/undefined = absent, empty string = absent)
    if (sectionConfig) {
      const sectionVal = sectionConfig[jsonKey];
      if (sectionVal != null) {
        const strVal = String(sectionVal);
        if (strVal) {
          if (jsonKey === "port") {
            const portNum = Number(strVal);
            if (!isNaN(portNum)) result[jsonKey] = portNum;
          } else {
            result[jsonKey] = strVal;
          }
          continue;
        }
      }
    }

    // 3. Check top-level config file (null/undefined = absent, empty string = absent)
    const cfgVal = config[jsonKey];
    if (cfgVal != null) {
      const strVal = String(cfgVal);
      if (strVal) {
        if (jsonKey === "port") {
          const portNum = Number(strVal);
          if (!isNaN(portNum)) result[jsonKey] = portNum;
        } else {
          result[jsonKey] = strVal;
        }
        continue;
      }
    }

    // 4. Apply default
    const def = DEFAULTS[envVar];
    if (def !== undefined) {
      const defaultVal = typeof def === "function" ? def() : def;
      if (jsonKey === "port") {
        const portNum = Number(defaultVal);
        if (!isNaN(portNum)) result[jsonKey] = portNum;
      } else {
        result[jsonKey] = defaultVal;
      }
    }
  }

  return result;
}
