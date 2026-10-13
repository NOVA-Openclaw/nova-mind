import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as http from "http";
import { classifyMessage } from "../src/classifier.ts";

/**
 * Unit tests for #697 / #361 classifier failure logging.
 *
 * The four failure classes (model_not_found, timeout, connection_refused,
 * parse_error) must each emit a distinct, greppable reason token while still
 * returning a safe default classification.
 *
 * Fixture-value derivations:
 * - "perhaps tomorrow" is intentionally ambiguous: no question mark, no
 *   interrogative, no action verb, not a greeting/acknowledgment/command, so
 *   classifyByRules returns null and the Ollama fallback runs.
 * - 404/200 are the HTTP status codes exercised by TC-697-001/003/004.
 * - reason tokens model_not_found/timeout/connection_refused/parse_error are
 *   the exact values required by TC-697-001..004 and TC-361-004.
 * - The 2000ms timeout value comes from classifier.ts OLLAMA_TIMEOUT_MS.
 */

describe("classifyMessage failure reasons (#697 / #361)", () => {
  let originalBaseUrl: string | undefined;
  let server: http.Server | undefined;

  beforeEach(() => {
    originalBaseUrl = process.env.OLLAMA_BASE_URL;
  });

  afterEach(async () => {
    if (server) {
      await new Promise<void>((resolve, reject) => {
        server!.close((err) => (err ? reject(err) : resolve()));
      });
      server = undefined;
    }
    if (originalBaseUrl === undefined) {
      delete process.env.OLLAMA_BASE_URL;
    } else {
      process.env.OLLAMA_BASE_URL = originalBaseUrl;
    }
  });

  function startServer(handler: (req: http.IncomingMessage, res: http.ServerResponse) => void): Promise<number> {
    return new Promise((resolve) => {
      server = http.createServer(handler);
      server.listen(0, "127.0.0.1", () => {
        const addr = server!.address();
        const port = typeof addr === "object" && addr ? addr.port : 0;
        resolve(port);
      });
    });
  }

  async function captureWarning(fn: () => Promise<unknown>): Promise<{ warnings: string[]; result: unknown }> {
    const warnings: string[] = [];
    const originalWarn = console.warn;
    console.warn = (...args: unknown[]) => {
      warnings.push(args.map((a) => (typeof a === "string" ? a : JSON.stringify(a))).join(" "));
    };
    try {
      const result = await fn();
      return { warnings, result };
    } finally {
      console.warn = originalWarn;
    }
  }

  // Ambiguous content that fails rule-based classification and triggers Ollama fallback.
  const ambiguousContent = "perhaps tomorrow";

  it("TC-697-001: model not installed (404) logs reason=model_not_found and defaults to conversation", async () => {
    const port = await startServer((_, res) => {
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "model 'phi4-mini:latest' not found, try pulling it first" }));
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;

    const { warnings, result } = await captureWarning(() => classifyMessage(ambiguousContent));

    expect(result).toEqual({ type: "conversation", method: "default" });
    expect(warnings.some((w) => w.includes("reason=model_not_found"))).toBe(true);
  });

  it("TC-697-002: Ollama unreachable logs reason=connection_refused and defaults to conversation", async () => {
    // Find an unused port; connection should be refused.
    const probe = http.createServer();
    const port = await new Promise<number>((resolve) => probe.listen(0, "127.0.0.1", () => {
      const addr = probe.address();
      resolve(typeof addr === "object" && addr ? addr.port : 0);
    }));
    await new Promise<void>((resolve) => probe.close(() => resolve()));

    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;

    const { warnings, result } = await captureWarning(() => classifyMessage(ambiguousContent));

    expect(result).toEqual({ type: "conversation", method: "default" });
    expect(warnings.some((w) => w.includes("reason=connection_refused"))).toBe(true);
  });

  it("TC-697-003: garbage non-JSON 200 body logs reason=parse_error and defaults to conversation", async () => {
    const port = await startServer((_, res) => {
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end("not json at all");
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;

    const { warnings, result } = await captureWarning(() => classifyMessage(ambiguousContent));

    expect(result).toEqual({ type: "conversation", method: "default" });
    expect(warnings.some((w) => w.includes("reason=parse_error"))).toBe(true);
  });

  it("TC-697-004: valid outer JSON with prose inner response logs reason=parse_error", async () => {
    const port = await startServer((_, res) => {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ response: "I cannot classify this." }));
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;

    const { warnings, result } = await captureWarning(() => classifyMessage(ambiguousContent));

    expect(result).toEqual({ type: "conversation", method: "default" });
    expect(warnings.some((w) => w.includes("reason=parse_error"))).toBe(true);
  });

  it("TC-361-001: cold-load timeout destroys socket and logs reason=timeout", async () => {
    const port = await startServer(() => {
      // Never respond — trigger the 2000ms timeout and req.destroy().
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;

    const { warnings, result } = await captureWarning(() => classifyMessage(ambiguousContent));

    expect(result).toEqual({ type: "conversation", method: "default" });
    expect(warnings.some((w) => w.includes("reason=timeout"))).toBe(true);
  }, 5000);

  it("TC-361-004: all four failure reasons are pairwise distinct", async () => {
    const reasons: string[] = [];

    // 404 -> model_not_found
    let port = await startServer((_, res) => {
      res.writeHead(404, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "model not found" }));
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;
    delete process.env.OLLAMA_TIMEOUT_MS;
    let captured = await captureWarning(() => classifyMessage(ambiguousContent));
    reasons.push(captured.warnings.find((w) => w.includes("reason="))!);
    await new Promise<void>((resolve) => server!.close(() => resolve()));
    server = undefined;

    // garbage -> parse_error
    port = await startServer((_, res) => {
      res.writeHead(200);
      res.end("garbage");
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;
    delete process.env.OLLAMA_TIMEOUT_MS;
    captured = await captureWarning(() => classifyMessage(ambiguousContent));
    reasons.push(captured.warnings.find((w) => w.includes("reason="))!);
    await new Promise<void>((resolve) => server!.close(() => resolve()));
    server = undefined;

    // refused -> connection_refused
    const probe = http.createServer();
    port = await new Promise<number>((resolve) => probe.listen(0, "127.0.0.1", () => {
      const addr = probe.address();
      resolve(typeof addr === "object" && addr ? addr.port : 0);
    }));
    await new Promise<void>((resolve) => probe.close(() => resolve()));
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;
    delete process.env.OLLAMA_TIMEOUT_MS;
    captured = await captureWarning(() => classifyMessage(ambiguousContent));
    reasons.push(captured.warnings.find((w) => w.includes("reason="))!);

    // hang -> timeout (use a short timeout so the four-reason probe stays fast)
    port = await startServer(() => {
      // Never respond.
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;
    process.env.OLLAMA_TIMEOUT_MS = "50";
    captured = await captureWarning(() => classifyMessage(ambiguousContent));
    reasons.push(captured.warnings.find((w) => w.includes("reason="))!);
    await new Promise<void>((resolve) => server!.close(() => resolve()));
    server = undefined;

    const distinctReasons = new Set(
      reasons.map((r) => {
        const match = r.match(/reason=([a-z_]+)/);
        return match ? match[1] : "";
      })
    );
    expect(distinctReasons.size).toBe(4);
    expect(distinctReasons).toContain("model_not_found");
    expect(distinctReasons).toContain("parse_error");
    expect(distinctReasons).toContain("connection_refused");
    expect(distinctReasons).toContain("timeout");
  }, 10000);

  it("TC-697-005: invalid type enum value falls back to conversation with method=ollama", async () => {
    const port = await startServer((_, res) => {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ response: JSON.stringify({ type: "urgent_escalation", domainHints: ["x"] }) }));
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;

    const { result } = await captureWarning(() => classifyMessage(ambiguousContent));

    expect(result).toEqual({ type: "conversation", domainHints: ["x"], method: "ollama" });
  });
});
