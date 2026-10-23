/**
 * Shared embedding-config loader for TypeScript plugins.
 *
 * Reads nova-mind's embedding-config.json (provider, model, base_url, dimensions)
 * from ~/.openclaw/scripts/embedding-config.json. Missing or invalid config is a
 * loud failure; there is no silent default model.
 *
 * Reuses the convention from memory-extract: config lives in ~/.openclaw/scripts/
 * and the path may be overridden via EMBEDDING_CONFIG_PATH_OVERRIDE.
 *
 * Issue: nova-mind #781
 */

import { existsSync, readFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";

export interface EmbeddingConfig {
  provider: string;
  model: string;
  base_url: string;
  dimensions: number;
}

const DEFAULT_EMBEDDING_CONFIG_PATH = join(
  homedir(),
  ".openclaw",
  "scripts",
  "embedding-config.json"
);

function isEmbeddingConfig(value: unknown): value is EmbeddingConfig {
  if (typeof value !== "object" || value === null) {
    return false;
  }
  const cfg = value as EmbeddingConfig;
  return (
    typeof cfg.provider === "string" &&
    typeof cfg.model === "string" &&
    typeof cfg.base_url === "string" &&
    typeof cfg.dimensions === "number" &&
    Number.isInteger(cfg.dimensions) &&
    cfg.dimensions > 0
  );
}

export function loadEmbeddingConfig(
  overridePath?: string
): EmbeddingConfig {
  const configPath =
    overridePath ||
    process.env.EMBEDDING_CONFIG_PATH_OVERRIDE ||
    DEFAULT_EMBEDDING_CONFIG_PATH;

  if (!existsSync(configPath)) {
    throw new Error(`Embedding config not found: ${configPath}`);
  }

  let raw: string;
  try {
    raw = readFileSync(configPath, "utf8");
  } catch (err) {
    throw new Error(
      `Cannot read embedding config ${configPath}: ${(err as Error).message}`
    );
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    throw new Error(
      `Invalid JSON in embedding config ${configPath}: ${(err as Error).message}`
    );
  }

  if (!isEmbeddingConfig(parsed)) {
    throw new Error(
      `Embedding config ${configPath} must include provider, model, base_url, and dimensions`
    );
  }

  return parsed;
}
