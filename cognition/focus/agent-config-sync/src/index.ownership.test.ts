/**
 * Unit tests for ownership-mode resolution (nova-mind#819 round 4).
 *
 * TC-819-U-06: resolveOwnershipMode picks explicit when agents.ownership="explicit"
 * TC-819-U-07: running gateway version >= 2026.11.0 selects explicit
 * TC-819-U-08: running gateway version < 2026.11.0 selects legacy
 * TC-819-U-09: unknown running version with no explicit ownership logs warning and stays legacy
 * TC-819-U-10: unknown running version with agents.ownership="explicit" stays explicit
 * TC-819-U-11: beta/prerelease version strings are tolerated
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  resolveOwnershipMode,
  parseOpenClawVersion,
  isOpenClawVersionAtLeast,
} from "../index.js";
import type { OwnershipMode } from "./sync.js";

function makeLogger(): {
  warnings: string[];
  infos: string[];
  errors: string[];
  log: ReturnType<typeof makeMockLogger>;
} {
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
): {
  warn: (msg: string) => void;
  info: (msg: string) => void;
  error: (msg: string) => void;
} {
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
        meta: { lastTouchedVersion: "2026.9.6" },
      },
      "2026.9.6",
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });

  it("returns explicit even when version is unknown", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      {
        agents: { ownership: "explicit" },
      },
      undefined,
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });
});

// ── TC-819-U-07: running gateway version >= 2026.11.0 selects explicit ──────

describe("TC-819-U-07: gateway version >= 2026.11.0 selects explicit", () => {
  it("2026.11.0 → explicit", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode({}, "2026.11.0", log);
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });

  it("2026.11.3 → explicit", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      { meta: { lastTouchedVersion: "2026.9.6" } },
      "2026.11.3",
      log,
    );
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });

  it("2026.12.0 → explicit", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode({}, "2026.12.0", log);
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });

  it("2027.1.1 → explicit", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode({}, "2027.1.1", log);
    assert.strictEqual(mode, "explicit");
    assert.strictEqual(warnings.length, 0);
  });
});

// ── TC-819-U-08: running gateway version < 2026.11.0 selects legacy ─────────

describe("TC-819-U-08: gateway version < 2026.11.0 selects legacy", () => {
  it("2026.9.6 with no explicit ownership → legacy", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      { meta: { lastTouchedVersion: "2026.11.3" } },
      "2026.9.6",
      log,
    );
    assert.strictEqual(mode, "legacy");
    assert.strictEqual(warnings.length, 0);
  });

  it("2026.10.99 → legacy", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode({}, "2026.10.99", log);
    assert.strictEqual(mode, "legacy");
    assert.strictEqual(warnings.length, 0);
  });

  it("legacy configs with 11.3-looking surfaces still use legacy when version says 9.x", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      {
        agents: {
          defaults: {
            systemAgent: { agentId: "newhart" },
          },
        },
        bindings: [{ agentId: "newhart", match: { channel: "discord", accountId: "default" } }],
        "$include": "./agents-explicit.json",
      },
      "2026.9.6",
      log,
    );
    assert.strictEqual(mode, "legacy");
    assert.strictEqual(warnings.length, 0);
  });
});

// ── TC-819-U-09: unknown version behaviour ──────────────────────────────────

describe("TC-819-U-09: unknown running version", () => {
  it("unknown version with no explicit ownership → legacy and warning", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode({}, undefined, log);
    assert.strictEqual(mode, "legacy");
    assert.strictEqual(warnings.length, 1);
    assert.ok(warnings[0]?.includes("Could not determine running gateway version"));
  });

  it("unparseable running version is treated as unknown → legacy and warning", () => {
    const { log, warnings } = makeLogger();
    const mode = resolveOwnershipMode(
      { meta: { lastTouchedVersion: "not-a-version" } },
      "not-a-version",
      log,
    );
    assert.strictEqual(mode, "legacy");
    assert.strictEqual(warnings.length, 1);
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

  it("2026.11.0-beta.1 still satisfies >= 2026.11.0", () => {
    assert.strictEqual(isOpenClawVersionAtLeast("2026.11.0-beta.1", 2026, 11, 0), true);
  });
});
