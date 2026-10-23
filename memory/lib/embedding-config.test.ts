/**
 * Tests for embedding-config shared loader.
 *
 * Issue: nova-mind #781
 */

import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, unlinkSync, mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { loadEmbeddingConfig } from "./embedding-config.ts";

describe("loadEmbeddingConfig", () => {
  let tmpDir: string;
  let previousOverride: string | undefined;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "embed-cfg-"));
    previousOverride = process.env.EMBEDDING_CONFIG_PATH_OVERRIDE;
  });

  afterEach(() => {
    if (previousOverride === undefined) {
      delete process.env.EMBEDDING_CONFIG_PATH_OVERRIDE;
    } else {
      process.env.EMBEDDING_CONFIG_PATH_OVERRIDE = previousOverride;
    }
  });

  it("reads model from valid config", () => {
    const path = join(tmpDir, "embedding-config.json");
    writeFileSync(
      path,
      JSON.stringify({
        provider: "ollama",
        model: "snowflake-arctic-embed2",
        base_url: "http://localhost:11434",
        dimensions: 1024,
      })
    );
    process.env.EMBEDDING_CONFIG_PATH_OVERRIDE = path;

    const cfg = loadEmbeddingConfig();
    assert.equal(cfg.model, "snowflake-arctic-embed2");
    assert.equal(cfg.base_url, "http://localhost:11434");
    assert.equal(cfg.dimensions, 1024);
  });

  it("errors when config is missing", () => {
    const path = join(tmpDir, "missing-embedding-config.json");
    process.env.EMBEDDING_CONFIG_PATH_OVERRIDE = path;

    assert.throws(() => loadEmbeddingConfig(), /Embedding config not found/);
  });

  it("errors when config JSON is invalid", () => {
    const path = join(tmpDir, "embedding-config.json");
    writeFileSync(path, "{not valid json");
    process.env.EMBEDDING_CONFIG_PATH_OVERRIDE = path;

    assert.throws(() => loadEmbeddingConfig(), /Invalid JSON/);
  });

  it("errors when required keys are missing", () => {
    const path = join(tmpDir, "embedding-config.json");
    writeFileSync(
      path,
      JSON.stringify({
        provider: "ollama",
        base_url: "http://localhost:11434",
        dimensions: 1024,
      })
    );
    process.env.EMBEDDING_CONFIG_PATH_OVERRIDE = path;

    assert.throws(
      () => loadEmbeddingConfig(),
      /must include provider, model, base_url, and dimensions/
    );
  });

  it("errors when dimensions is not a positive integer", () => {
    const path = join(tmpDir, "embedding-config.json");
    writeFileSync(
      path,
      JSON.stringify({
        provider: "ollama",
        model: "snowflake-arctic-embed2",
        base_url: "http://localhost:11434",
        dimensions: 0,
      })
    );
    process.env.EMBEDDING_CONFIG_PATH_OVERRIDE = path;

    assert.throws(
      () => loadEmbeddingConfig(),
      /must include provider, model, base_url, and dimensions/
    );
  });
});
