/**
 * Unit tests for bootstrap-context hook handler internals.
 *
 * Covers the two cheap gaps flagged in QA desk review for nova-mind#488:
 *   TC-19: synchronous getPool() constructor throw is caught in loadFromDatabase()
 *   TC-02: pg-env.ts import failure with no override keeps the hardcoded fallback config
 *
 * Run: npx tsx --test cognition/focus/bootstrap-context/hook/handler.test.ts
 */

import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const FALLBACK_CONFIG = {
  host: "localhost",
  port: 5432,
  database: "nova_memory",
  user: os.userInfo().username,
};

function makeTempHome(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "bootstrap-handler-test-"));
}

describe("TC-19: loadFromDatabase catches synchronous getPool() throw", { concurrency: false }, () => {
  it("returns { ok: false, files: [] } when the Pool constructor throws", async () => {
    const { __testing } = await import("./handler.js?tc=19");

    __testing.setPoolConstructor(
      class {
        constructor() {
          throw new Error("synchronous pool death");
        }
      } as unknown as new (...args: any[]) => any,
    );

    const result = await __testing.loadFromDatabase("scout");
    assert.deepStrictEqual(result, { ok: false, files: [] });
  });
});

describe("TC-02: pg-env.ts unavailable with no override uses hardcoded fallback", { concurrency: false }, () => {
  let tmpHome: string;
  let originalHome: string | undefined;

  before(() => {
    originalHome = process.env.HOME;
    tmpHome = makeTempHome();
    process.env.HOME = tmpHome;
  });

  after(() => {
    if (originalHome === undefined) {
      delete process.env.HOME;
    } else {
      process.env.HOME = originalHome;
    }
    fs.rmSync(tmpHome, { recursive: true, force: true });
  });

  it("keeps the literal fallback pgConfig when pg-env.ts cannot be loaded", async () => {
    const { __testing } = await import("./handler.js?tc=02");
    assert.deepStrictEqual(__testing.getPgConfig(), FALLBACK_CONFIG);
  });
});
