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
  /** The database value from the bootstrap section, if any. */
  database?: string;
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
    const sectionRecord = section as Record<string, unknown>;
    const unknownKeys: string[] = [];
    for (const key of Object.keys(sectionRecord)) {
      if (!VALID_BOOTSTRAP_KEYS.has(key)) {
        unknownKeys.push(key);
      }
    }
    const database = sectionRecord.database;
    return {
      configured: true,
      unknownKeys,
      database: typeof database === "string" && database ? database : undefined,
    };
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

/**
 * Deprecation warning for the postgres.json `bootstrap` database override.
 *
 * The bootstrap section was introduced in #330/#488 to let split agents query
 * another peer's DB, but that is now the wrong default. Each agent must use
 * its own `<user>_memory` DB. If the override still points elsewhere, emit a
 * loud warning so operators can remove it.
 *
 * Issue: nova-mind #775
 */
export function bootstrapForeignDbWarning(
  configuredDatabase: string | undefined,
  ownDb: string,
): string | undefined {
  if (!configuredDatabase || configuredDatabase === ownDb) {
    return undefined;
  }
  return (
    `[bootstrap-context] DEPRECATED: postgres.json bootstrap override targets ` +
    `foreign database '${configuredDatabase}' instead of this agent's own DB ` +
    `'${ownDb}'. Remove the bootstrap section or set its database to '${ownDb}'. ` +
    `See nova-mind #775.`
  );
}
