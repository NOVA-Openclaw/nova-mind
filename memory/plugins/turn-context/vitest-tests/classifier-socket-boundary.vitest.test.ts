import { describe, it, expect, beforeEach, afterEach } from "vitest";
import * as http from "http";
import type { Socket } from "net";
import { classifyMessage, getOllamaTimeoutMs } from "../src/classifier.ts";

/**
 * Tests for #361 warm-path latency and socket cleanup, plus #697 boundary
 * behavior not covered by the failure-reason suite.
 *
 * Fixture-value derivations:
 * - "perhaps tomorrow" is the same ambiguous content used in
 *   classifier-failures.vitest.test.ts; it fails rule-based classification and
 *   reaches the Ollama fallback.
 * - 50ms is the reduced OLLAMA_TIMEOUT_MS used only in these tests to avoid a
 *   40-second socket-leak probe; production remains at 2000ms.
 * - N=20 consecutive timeouts is the minimum count required by TC-361-003.
 */

describe("getOllamaTimeoutMs fallback", () => {
  let originalTimeout: string | undefined;

  beforeEach(() => {
    originalTimeout = process.env.OLLAMA_TIMEOUT_MS;
  });

  afterEach(() => {
    if (originalTimeout === undefined) {
      delete process.env.OLLAMA_TIMEOUT_MS;
    } else {
      process.env.OLLAMA_TIMEOUT_MS = originalTimeout;
    }
  });

  it.each([
    { value: "", expected: 2000, label: "empty string" },
    { value: "not-a-number", expected: 2000, label: "NaN" },
    { value: "0", expected: 2000, label: "zero" },
    { value: "-100", expected: 2000, label: "negative" },
    { value: "50", expected: 50, label: "valid positive" },
  ])("returns $expected for $label", ({ value, expected }) => {
    process.env.OLLAMA_TIMEOUT_MS = value;
    expect(getOllamaTimeoutMs()).toBe(expected);
  });
});

describe("classifier warm path and socket cleanup (#361)", () => {
  let originalBaseUrl: string | undefined;
  let originalTimeout: string | undefined;
  let server: http.Server | undefined;

  beforeEach(() => {
    originalBaseUrl = process.env.OLLAMA_BASE_URL;
    originalTimeout = process.env.OLLAMA_TIMEOUT_MS;
    process.env.OLLAMA_TIMEOUT_MS = "50";
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
    if (originalTimeout === undefined) {
      delete process.env.OLLAMA_TIMEOUT_MS;
    } else {
      process.env.OLLAMA_TIMEOUT_MS = originalTimeout;
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

  // Ambiguous content that reaches the Ollama fallback.
  const ambiguousContent = "perhaps tomorrow";

  it("TC-361-002: warm model responds quickly without adding a 2000ms latency tax", async () => {
    const port = await startServer((_, res) => {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          response: JSON.stringify({ type: "info_request", domainHints: ["x"] }),
        })
      );
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;

    const start = Date.now();
    const result = await classifyMessage(ambiguousContent);
    const elapsed = Date.now() - start;

    expect(result).toEqual({ type: "info_request", domainHints: ["x"], method: "ollama" });
    // A warm local HTTP round-trip must finish well under the 2000ms timeout;
    // 500ms leaves generous headroom for scheduler jitter on a shared host.
    expect(elapsed).toBeLessThan(500);
  });

  it("TC-361-003: timed-out request sockets are destroyed, not leaked", async () => {
    const sockets = new Set<Socket>();
    const server2 = http.createServer(() => {
      // Never respond.
    });
    server2.on("connection", (socket: Socket) => {
      sockets.add(socket);
      socket.on("close", () => sockets.delete(socket));
    });

    const port = await new Promise<number>((resolve) => {
      server2.listen(0, "127.0.0.1", () => {
        const addr = server2.address();
        resolve(typeof addr === "object" && addr ? addr.port : 0);
      });
    });
    process.env.OLLAMA_BASE_URL = `http://127.0.0.1:${port}`;

    const N = 20;
    for (let i = 0; i < N; i++) {
      await classifyMessage(ambiguousContent);
    }

    // Give the event loop a tick for the close events to fire after req.destroy().
    await new Promise((r) => setTimeout(r, 100));

    // Every client socket created by the classifier timeout path must have been
    // closed; otherwise we have a leak.
    expect(sockets.size).toBe(0);

    await new Promise<void>((resolve) => server2.close(() => resolve()));
  }, 5000);
});
