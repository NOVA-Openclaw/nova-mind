import { describe, it, expect } from "vitest";
import { readFileSync } from "fs";
import { join } from "path";

/**
 * Regression tests for the memory-extract legacy hook contract.
 *
 * SE #1231 P0: commit 5ee6938 (#716) accidentally rewrote the hook to the
 * plugin-SDK shape (export default register(api), HOOK.md events=[]).  The
 * legacy hook loader rejects it because HOOK.md has no static events and the
 * default export is not an async handler.  These tests catch that regression
 * at desk-QA time without needing a running gateway.
 */

const HOOK_DIR = join(__dirname, "../../../hooks/memory-extract");
const HANDLER_PATH = join(HOOK_DIR, "handler.ts");
const HOOK_MD_PATH = join(HOOK_DIR, "HOOK.md");

function parseHookMetadata(md: string): { events?: string[]; [key: string]: unknown } {
  const frontMatter = md.match(/^---\n([\s\S]*?)\n---/);
  if (!frontMatter) throw new Error("HOOK.md has no front matter");
  const metadataLine = frontMatter[1]
    .split("\n")
    .find((line) => line.startsWith("metadata:"));
  if (!metadataLine) throw new Error("HOOK.md front matter has no metadata line");
  const json = metadataLine.replace(/^metadata:\s*/, "");
  const parsed = JSON.parse(json);
  return parsed?.openclaw ?? {};
}

describe("memory-extract legacy hook contract", () => {
  it("HOOK.md declares the legacy message:received event", () => {
    const md = readFileSync(HOOK_MD_PATH, "utf8");
    const meta = parseHookMetadata(md);
    expect(Array.isArray(meta.events)).toBe(true);
    expect(meta.events).not.toHaveLength(0);
    expect(meta.events).toContain("message:received");
  });

  it("handler.ts default-exports a legacy async handler, not register()", async () => {
    const mod = await import("../../../hooks/memory-extract/handler.ts");
    expect(mod).toHaveProperty("default");
    expect(typeof mod.default).toBe("function");
    // Legacy handler shape: one argument (the event), async.
    expect(mod.default.length).toBe(1);
    // Ensure the #716 plugin register() shape is gone.
    expect(mod.default.name).not.toBe("register");
    expect("register" in mod).toBe(false);
  });

  it("handler.ts source does not export a plugin register() shape", () => {
    const source = readFileSync(HANDLER_PATH, "utf8");
    // Reject plugin SDK register default export or named register export.
    expect(source).not.toMatch(/export\s+default\s+function\s+register\b/);
    expect(source).not.toMatch(/export\s+(async\s+)?function\s+register\b/);
    expect(source).not.toMatch(/export\s*\{\s*register\s*\}/);
    // Legacy default export should be an async handler.
    expect(source).toMatch(/export\s+default\s+async\s+function\s+handler\s*\(/);
  });
});
