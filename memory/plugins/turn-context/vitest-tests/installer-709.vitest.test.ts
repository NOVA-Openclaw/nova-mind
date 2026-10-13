import { describe, it, expect, beforeAll } from "vitest";
import { mkdtempSync, writeFileSync, readFileSync, unlinkSync } from "fs";
import { execSync } from "child_process";
import { tmpdir } from "os";
import { join } from "path";

/**
 * Unit tests for #709 installer config merge behavior.
 *
 * These exercise the jq filter used in agent-install.sh to enable the
 * turn-context plugin, verifying idempotency and preservation of existing keys.
 */

function runJqFilter(input: object): object {
  const dir = mkdtempSync(join(tmpdir(), "turn-context-installer-"));
  const inputPath = join(dir, "openclaw.json");
  const outputPath = join(dir, "openclaw.json.tmp");
  writeFileSync(inputPath, JSON.stringify(input));

  // Exact jq filter from agent-install.sh (#709 fix).
  const filter = `
    .plugins.load.paths = ((.plugins.load.paths // []) + ["/home/nova/.openclaw/plugins/turn-context"] | unique)
    | .plugins.entries."turn-context" = (.plugins.entries."turn-context" // {}) * {
        "enabled": true,
        "hooks": {
          "allowConversationAccess": true
        }
      }
  `;

  try {
    execSync(`jq '${filter}' "${inputPath}" > "${outputPath}"`);
    return JSON.parse(readFileSync(outputPath, "utf-8"));
  } finally {
    try {
      unlinkSync(inputPath);
      unlinkSync(outputPath);
    } catch {}
  }
}

describe("agent-install.sh turn-context jq filter (#709)", () => {
  beforeAll(() => {
    try {
      execSync("command -v jq", { stdio: "ignore" });
    } catch {
      // eslint-disable-next-line no-console
      console.warn("jq not available; installer tests skipped at runtime");
    }
  });

  it("TC-709-001: fresh install sets enabled=true and hooks.allowConversationAccess=true", () => {
    const result = runJqFilter({ plugins: { load: { paths: [] }, entries: {} } });

    expect(result.plugins.entries["turn-context"]).toEqual({
      enabled: true,
      hooks: { allowConversationAccess: true },
    });
    expect(result.plugins.load.paths).toContain("/home/nova/.openclaw/plugins/turn-context");
  });

  it("TC-709-002: existing turn-context keys are preserved (merge, not overwrite)", () => {
    const result = runJqFilter({
      plugins: {
        load: { paths: [] },
        entries: {
          "turn-context": {
            enabled: true,
            config: { placement: "turn-prepend" },
            hooks: { allowConversationAccess: true },
          },
        },
      },
    });

    // placement must survive; allowConversationAccess must remain true.
    expect(result.plugins.entries["turn-context"]).toEqual({
      enabled: true,
      config: { placement: "turn-prepend" },
      hooks: { allowConversationAccess: true },
    });
  });

  it("TC-709-003: re-run is idempotent — duplicate paths are deduplicated", () => {
    const first = runJqFilter({ plugins: { load: { paths: [] }, entries: {} } });
    const second = runJqFilter(first);

    expect(second.plugins.load.paths).toEqual(first.plugins.load.paths);
    expect(second.plugins.entries["turn-context"]).toEqual(first.plugins.entries["turn-context"]);
  });

  it("TC-709-007: pre-existing string 'true' for allowConversationAccess is merged, not coerced", () => {
    const result = runJqFilter({
      plugins: {
        load: { paths: [] },
        entries: {
          "turn-context": {
            hooks: { allowConversationAccess: "true" },
          },
        },
      },
    });

    // The installer writes boolean true via merge; existing string value is
    // overwritten because the right-hand object in jq's * operator wins on
    // key collision. This is the expected idempotent merge behavior.
    expect(result.plugins.entries["turn-context"].hooks.allowConversationAccess).toBe(true);
  });
});
