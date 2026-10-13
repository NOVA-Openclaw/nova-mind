import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { runSemanticRecall } from "../src/semantic-recall.ts";

/**
 * Tests for semantic-recall formatting boundaries (#697 / #361).
 *
 * These tests mock the proactive-recall.py subprocess so the suite runs
 * without Python dependencies while still exercising the formatting path.
 *
 * Fixture-value derivations:
 * - 0.7 is HIGH_CONFIDENCE_THRESHOLD (semantic-recall.ts default).
 * - 0.699999 and 0.700001 are the boundary probes required by TC-697-006 to
 *   distinguish >= from >.
 * - "memory" is a generic source string returned by proactive-recall.py.
 */

vi.mock("child_process", () => ({
  spawn: vi.fn(),
}));

import { spawn } from "child_process";

describe("runSemanticRecall boundary formatting (#697-006)", () => {
  beforeEach(() => {
    vi.mocked(spawn).mockReset();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function mockSpawn(stdoutData: string, exitCode = 0) {
    vi.mocked(spawn).mockImplementation(() => {
      const handlers: Record<string, ((...args: unknown[]) => void)[]> = {};
      const child = {
        stdout: {
          on: (event: string, cb: (chunk: Buffer) => void) => {
            if (event === "data") {
              setImmediate(() => cb(Buffer.from(stdoutData)));
            }
          },
        },
        stderr: { on: () => {} },
        stdin: { write: () => {}, end: () => {} },
        on: (event: string, cb: (code: number) => void) => {
          if (event === "close") {
            setImmediate(() => cb(exitCode));
          }
        },
      } as any;
      return child;
    });
  }

  it("TC-697-006: similarity exactly 0.7 renders high-confidence indicator", async () => {
    mockSpawn(
      JSON.stringify({
        memories: [{ source: "memory", content: "exact boundary", similarity: 0.7 }],
      })
    );

    const result = await runSemanticRecall({ content: "test" });

    expect(result).toContain("🎯");
    expect(result).not.toContain("📝");
  });

  it("TC-697-006: similarity 0.700001 renders high-confidence indicator", async () => {
    mockSpawn(
      JSON.stringify({
        memories: [{ source: "memory", content: "just above", similarity: 0.700001 }],
      })
    );

    const result = await runSemanticRecall({ content: "test" });

    expect(result).toContain("🎯");
  });

  it("TC-697-006: similarity 0.699999 renders regular indicator", async () => {
    mockSpawn(
      JSON.stringify({
        memories: [{ source: "memory", content: "just below", similarity: 0.699999 }],
      })
    );

    const result = await runSemanticRecall({ content: "test" });

    expect(result).toContain("📝");
    expect(result).not.toContain("🎯");
  });
});
