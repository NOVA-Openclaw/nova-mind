/**
 * Unit tests for ownership-mode resolution (nova-mind#819 round 3).
 *
 * TC-819-U-06: resolveOwnershipMode picks explicit when agents.ownership="explicit"
 * TC-819-U-07: explicit-owner surfaces without ownership="explicit" → explicit + warn
 * TC-819-U-08: gateway version >= 2026.11.3 → explicit
 * TC-819-U-09: 9.6 config with no explicit surfaces → legacy
 * TC-819-U-10: beta/prerelease version strings are tolerated
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  resolveOwnershipMode,
  parseOpenClawVersion,
  isOpenClawVersionAtLeast,
  hasExplicitOwnerSurfaces,
} from "../index.js";
import type { OwnershipMode } from "./sync.js";

function makeLogger(): { warnings: string[]; infos: string[]; errors: string[]; log: ReturnType<typeof makeMockLogger> } {
  const warnings: string[] = [];
  const infos: string[] = [];
  const errors: string[] = [];
  const log = makeMockLogger(warnings, infos, errors);
  return { warnings, infos, errors, log };
}

function makeMockLogger(
  warnings: string[],
  infos: string[],
  errors: string[],
): { warn: (msg: string) => void; info: (msg: string) => void; error: (msg: string) => void } {
  return {
    warn: (msg: string) => warnings.push(msg),
    info: (msg: string) => infos.push(msg),
    error: (msg: string) => errors.push(msg),
  };
}

// ── TC-819-U-06: explicit ownership wins ────────────────────────────────────

describe("TC-819-U-06: resolveOwnershipMode when agents.ownership='explicit'", () => {
  it("returns explicit regardless of version or surfaces", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      {
        agents: { ownership: "explicit" },
        meta: { lastTouchedVersion: "2026.9.4" },
      },
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });
});

// ── TC-819-U-07: explicit-owner surfaces guard ──────────────────────────────

describe("TC-819-U-07: explicit-owner surfaces without ownership='explicit'", () => {
  it("systemAgent.agentId forces explicit mode and logs a warning", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      {
        agents: {
          defaults: {
            systemAgent: { agentId: "newhart" },
          },
        },
      },
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 1);
    assert.ok(warnings[0]?.includes("explicit-owner surfaces"));
  });

  it("root bindings[] forces explicit mode and logs a warning", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      {
        bindings: [{ agentId: "newhart", match: { channel: "discord", accountId: "default" } }],
      },
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 1);
  });

  it("root $include of agents-explicit.json forces explicit mode and logs a warning", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      {
        "$include": "./agents-explicit.json",
      },
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 1);
  });

  it("array $include containing agents-explicit.json forces explicit mode", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      {
        "$include": ["./base.json", "./agents-explicit.json"],
      },
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 1);
  });

  it("hasExplicitOwnerSurfaces returns false for unrelated $include", () => {
    assert.strictEqual(
      hasExplicitOwnerSurfaces({ "$include": "./something-else.json" }),
      false,
    );
  });

  it("hasExplicitOwnerSurfaces returns false when surfaces are absent", () => {
    assert.strictEqual(
      hasExplicitOwnerSurfaces({ agents: { entries: { $include: "./agents.json" } } }),
      false,
    );
  });
});

// ── TC-819-U-08: gateway version detection ──────────────────────────────────

describe("TC-819-U-08: gateway version >= 2026.11.3 selects explicit", () => {
  it("2026.11.3 → explicit", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      { meta: { lastTouchedVersion: "2026.11.3" } },
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });

  it("2026.12.0 → explicit", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      { meta: { lastTouchedVersion: "2026.12.0" } },
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });

  it("2027.1.1 → explicit", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      { meta: { lastTouchedVersion: "2027.1.1" } },
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });
});

// ── TC-819-U-09: 9.6 behavior preserved ─────────────────────────────────────

describe("TC-819-U-09: 9.6 configs with no explicit surfaces stay legacy", () => {
  it("2026.9.6 with no surfaces → legacy", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      { meta: { lastTouchedVersion: "2026.9.6" } },
      log,
    );
    assert.strictEqual(mode, "legacy");
    assert.strictEqual(warnings.length, 0);
  });

  it("missing version with no surfaces → legacy", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode({}, log);
    assert.strictEqual(mode, "legacy");
    assert.strictEqual(warnings.length, 0);
  });

  it("unparseable version with no surfaces → legacy", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      { meta: { lastTouchedVersion: "not-a-version" } },
      log,
    );
    assert.strictEqual(mode, "legacy");
    assert.strictEqual(warnings.length, 0);
  });
});

// ── TC-819-U-10: version parsing edge cases ─────────────────────────────────

describe("TC-819-U-10: version parsing tolerates prerelease suffixes", () => {
  it("parseOpenClawVersion strips -beta suffix", () => {
    assert.deepStrictEqual(parseOpenClawVersion("2026.11.3-beta.1"), [2026, 11, 3]);
  });

  it("parseOpenClawVersion returns null for garbage", () => {
    assert.strictEqual(parseOpenClawVersion(""), null);
    assert.strictEqual(parseOpenClawVersion("v1.2.3"), null);
    assert.strictEqual(parseOpenClawVersion("2026.11"), null);
  });

  it("isOpenClawVersionAtLeast handles equality", () => {
    assert.strictEqual(isOpenClawVersionAtLeast("2026.11.3", 2026, 11, 3), true);
    assert.strictEqual(isOpenClawVersionAtLeast("2026.11.2", 2026, 11, 3), false);
    assert.strictEqual(isOpenClawVersionAtLeast("2026.10.99", 2026, 11, 3), false);
    assert.strictEqual(isOpenClawVersionAtLeast("2025.99.99", 2026, 11, 3), false);
  });
});
