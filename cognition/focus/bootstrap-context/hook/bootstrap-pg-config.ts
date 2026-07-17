/**
 * Bootstrap PostgreSQL config detection and validation.
 *
 * Supports the optional `bootstrap` section in ~/.openclaw/postgres.json
 * so an agent whose primary DB differs (e.g. newhart_memory) can still
 * load bootstrap context from nova_memory (nova-mind#488).
 */

import { readFileSync } from "fs";
import { join } from "path";

const VALID_BOOTSTRAP_KEYS = new Set([
  "host",
  "port",
  "database",
  "user",
  "password",
]);

export interface BootstrapOverrideStatus {
  /** True when postgres.json contains a structurally-valid `bootstrap` object. */
  configured: boolean;
  /** Keys present in the bootstrap object that are not valid PG fields. */
  unknownKeys: string[];
}

/**
 * Best-effort read of postgres.json to detect whether a bootstrap override
 * is configured and to collect unknown keys for warning purposes.
 *
 * Does not throw — any read/parse failure returns { configured: false } and
 * leaves full error handling to loadPgEnv().
 */
export function detectBootstrapOverride(homeDir: string): BootstrapOverrideStatus {
  const postgresJsonPath = join(homeDir, ".openclaw", "postgres.json");
  try {
    const raw = readFileSync(postgresJsonPath, "utf-8");
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { configured: false, unknownKeys: [] };
    }
    const section = (parsed as Record<string, unknown>).bootstrap;
    if (section === undefined || section === null) {
      return { configured: false, unknownKeys: [] };
    }
    if (typeof section !== "object" || Array.isArray(section)) {
      // loadPgEnv will warn about non-object section; we don't flag unknown keys here.
      return { configured: false, unknownKeys: [] };
    }
    const unknownKeys: string[] = [];
    for (const key of Object.keys(section as Record<string, unknown>)) {
      if (!VALID_BOOTSTRAP_KEYS.has(key)) {
        unknownKeys.push(key);
      }
    }
    return { configured: true, unknownKeys };
  } catch (e) {
    return { configured: false, unknownKeys: [] };
  }
}

/**
 * Warning emitted when pg-env.ts cannot be loaded. Distinct when a bootstrap
 * override was configured so operators can tell the override was ignored.
 */
export function pgEnvUnavailableWarning(
  bootstrapConfigured: boolean,
  error: Error,
): string {
  if (bootstrapConfigured) {
    return (
      `[bootstrap-context] pg-env.ts unavailable — bootstrap override cannot be applied, ` +
      `using hardcoded fallback: ${error.message}`
    );
  }
  return `[bootstrap-context] Could not load pg-env.ts: ${error.message}`;
}
