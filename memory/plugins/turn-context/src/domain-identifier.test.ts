import { beforeEach, afterEach, describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  loadDomains,
  matchKeywords,
  resetDomainIdentifierCache,
  DOMAIN_CACHE_TTL_MS,
} from "./domain-identifier.ts";

// Original hard-coded query from the pre-fix implementation (DK-004).
const EXPECTED_QUERY_WITH_KEYWORDS = `
      SELECT ad.id, ad.domain_topic, a.name AS agent_name, ad.keywords, ad.notes
      FROM agent_domains ad
      JOIN agents a ON ad.agent_id = a.id
      ORDER BY ad.domain_topic
    `;

const EXPECTED_QUERY_WITHOUT_KEYWORDS = `
      SELECT ad.id, ad.domain_topic, a.name AS agent_name, ad.notes
      FROM agent_domains ad
      JOIN agents a ON ad.agent_id = a.id
      ORDER BY ad.domain_topic
    `;

interface FakeClient {
  query: <RowType>(text: string, values?: unknown[]) => Promise<{ rows: RowType[] }>;
  release: () => void;
  queryCalls: Array<{ text: string; values?: unknown[] }>;
  releaseCount: number;
}

interface FakeClientOptions {
  probeRows?: unknown[];
  probeError?: Error;
  mainRows?: unknown[];
  mainError?: Error;
}

function createFakeClient(options: FakeClientOptions): FakeClient {
  const queryCalls: Array<{ text: string; values?: unknown[] }> = [];
  let releaseCount = 0;
  return {
    query: async <RowType>(text: string, values?: unknown[]) => {
      queryCalls.push({ text, values });
      if (/information_schema\.columns/.test(text)) {
        if (options.probeError) throw options.probeError;
        return { rows: (options.probeRows ?? []) as RowType[] };
      }
      if (options.mainError) throw options.mainError;
      return { rows: (options.mainRows ?? []) as RowType[] };
    },
    release: () => {
      releaseCount += 1;
    },
    get queryCalls() {
      return queryCalls;
    },
    get releaseCount() {
      return releaseCount;
    },
  };
}

function createFakePool(...clientFactories: Array<() => FakeClient>) {
  let index = 0;
  return {
    connect: async () => {
      const factory = clientFactories[index] ?? clientFactories[clientFactories.length - 1];
      index += 1;
      return factory();
    },
  };
}

let originalWarn: typeof console.warn;
let warnings: string[];
let originalNow: typeof Date.now;

beforeEach(() => {
  resetDomainIdentifierCache();
  warnings = [];
  originalWarn = console.warn;
  console.warn = (...args: unknown[]) => {
    warnings.push(args.map(String).join(" "));
  };
  originalNow = Date.now;
});

afterEach(() => {
  console.warn = originalWarn;
  Date.now = originalNow;
});

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim();
}

describe("loadDomains() — column-present path (healthy schema)", () => {
  it("DK-001 — returns non-empty keywords arrays on canonical schema", async () => {
    const client = createFakeClient({
      probeRows: [{ column_name: "keywords" }],
      mainRows: [
        { id: 1, domain_topic: "coding", agent_name: "coder", keywords: ["code", "typescript"], notes: "notes" },
      ],
    });
    const domains = await loadDomains(createFakePool(() => client));

    assert.equal(domains.length, 1);
    assert.deepEqual(domains[0].keywords, ["code", "typescript"]);
  });

  it("DK-002 — column-detection query runs once before the main query on cold cache", async () => {
    const client = createFakeClient({
      probeRows: [{ column_name: "keywords" }],
      mainRows: [{ id: 1, domain_topic: "coding", agent_name: "coder", keywords: ["code"], notes: null }],
    });
    await loadDomains(createFakePool(() => client));

    assert.equal(client.queryCalls.length, 2);
    assert.match(client.queryCalls[0].text, /information_schema\.columns/);
    assert.equal(normalizeSql(client.queryCalls[1].text), normalizeSql(EXPECTED_QUERY_WITH_KEYWORDS));
  });

  it("DK-003 — column-detection result is cached and not re-queried on subsequent calls", async () => {
    const client = createFakeClient({
      probeRows: [{ column_name: "keywords" }],
      mainRows: [{ id: 1, domain_topic: "coding", agent_name: "coder", keywords: ["code"], notes: null }],
    });
    await loadDomains(createFakePool(() => client));
    await loadDomains(createFakePool(() => client));

    // Second call hits the 5-minute domain cache, so only the first probe + main run.
    assert.equal(client.queryCalls.length, 2);
  });

  it("DK-004 — canonical-path query matches pre-fix baseline", async () => {
    const client = createFakeClient({
      probeRows: [{ column_name: "keywords" }],
      mainRows: [{ id: 1, domain_topic: "coding", agent_name: "coder", keywords: ["code"], notes: null }],
    });
    await loadDomains(createFakePool(() => client));

    const mainQuery = client.queryCalls.find((c) => !/information_schema\.columns/.test(c.text));
    assert.ok(mainQuery);
    assert.equal(normalizeSql(mainQuery!.text), normalizeSql(EXPECTED_QUERY_WITH_KEYWORDS));
  });
});

describe("loadDomains() — column-missing fallback path (drifted schema)", () => {
  it("DK-005 — does not throw when the keywords column is absent", async () => {
    const client = createFakeClient({
      probeRows: [],
      mainRows: [{ id: 2, domain_topic: "infra", agent_name: "graybeard", notes: "ops" }],
    });
    await assert.doesNotReject(loadDomains(createFakePool(() => client)));
  });

  it("DK-006 — fallback query omits ad.keywords from SELECT list", async () => {
    const client = createFakeClient({
      probeRows: [],
      mainRows: [{ id: 2, domain_topic: "infra", agent_name: "graybeard", notes: "ops" }],
    });
    await loadDomains(createFakePool(() => client));

    const mainQuery = client.queryCalls.find((c) => !/information_schema\.columns/.test(c.text));
    assert.ok(mainQuery);
    assert.doesNotMatch(mainQuery!.text, /ad\.keywords/);
    assert.equal(normalizeSql(mainQuery!.text), normalizeSql(EXPECTED_QUERY_WITHOUT_KEYWORDS));
  });

  it("DK-007 — keywords is [] for every row on fallback path", async () => {
    const client = createFakeClient({
      probeRows: [],
      mainRows: [
        { id: 2, domain_topic: "infra", agent_name: "graybeard", notes: "ops" },
        { id: 3, domain_topic: "docs", agent_name: "scribe", notes: "write" },
      ],
    });
    const domains = await loadDomains(createFakePool(() => client));

    assert.equal(domains.length, 2);
    for (const d of domains) {
      assert.ok(Array.isArray(d.keywords));
      assert.equal(d.keywords.length, 0);
    }
  });

  it("DK-008 — non-keywords fields map through unchanged on fallback", async () => {
    const client = createFakeClient({
      probeRows: [],
      mainRows: [{ id: 7, domain_topic: "test", agent_name: "gem", notes: "cases" }],
    });
    const domains = await loadDomains(createFakePool(() => client));

    assert.equal(domains[0].id, 7);
    assert.equal(domains[0].domainTopic, "test");
    assert.equal(domains[0].agentName, "gem");
    assert.equal(domains[0].notes, "cases");
  });
});

describe("matchKeywords() — downstream consumer", () => {
  it("DK-009 — empty-keyword domains produce an empty score map", () => {
    const domains = [
      { id: 1, domainTopic: "sql", agentName: "a", keywords: [] as string[], notes: "" },
      { id: 2, domainTopic: "code", agentName: "b", keywords: [] as string[], notes: "" },
    ];
    const scores = matchKeywords("some sql keyword text", domains);
    assert.equal(scores.size, 0);
  });
});

describe("warning — exactly once per process lifetime", () => {
  it("DK-010 — logs exactly one warning on first fallback trigger", async () => {
    const client = createFakeClient({
      probeRows: [],
      mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }],
    });
    await loadDomains(createFakePool(() => client));

    assert.equal(warnings.length, 1);
    assert.match(warnings[0], /agent_domains\.keywords/);
    assert.match(warnings[0], /apply nova-mind schema migration/);
  });

  it("DK-011 — warning is not repeated on second call within cache TTL", async () => {
    const client = createFakeClient({
      probeRows: [],
      mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }],
    });
    await loadDomains(createFakePool(() => client));
    await loadDomains(createFakePool(() => client));

    assert.equal(warnings.length, 1);
  });

  it("DK-012 — warning is not repeated after domain-cache TTL expiry", async () => {
    const clients = [
      createFakeClient({ probeRows: [], mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }] }),
      createFakeClient({ probeRows: [], mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }] }),
    ];
    Date.now = () => 1000;
    await loadDomains(createFakePool(() => clients[0]));

    Date.now = () => 1000 + DOMAIN_CACHE_TTL_MS + 1;
    await loadDomains(createFakePool(() => clients[1]));

    assert.equal(warnings.length, 1);
  });

  it("DK-013 — column-presence cache survives domain-cache TTL expiry", async () => {
    const clients = [
      createFakeClient({ probeRows: [], mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }] }),
      createFakeClient({ probeRows: [], mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }] }),
    ];
    Date.now = () => 2000;
    await loadDomains(createFakePool(() => clients[0]));

    Date.now = () => 2000 + DOMAIN_CACHE_TTL_MS + 1;
    await loadDomains(createFakePool(() => clients[1]));

    const probeCalls0 = clients[0].queryCalls.filter((c) => /information_schema\.columns/.test(c.text));
    const probeCalls1 = clients[1].queryCalls.filter((c) => /information_schema\.columns/.test(c.text));
    assert.equal(probeCalls0.length + probeCalls1.length, 1);
  });
});

describe("error paths", () => {
  it("DK-014 — probe query failure falls back to assume-present and does not crash", async () => {
    const client = createFakeClient({
      probeError: new Error("probe failed"),
      mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", keywords: ["k"], notes: null }],
    });
    const domains = await loadDomains(createFakePool(() => client));

    assert.equal(domains.length, 1);
    assert.deepEqual(domains[0].keywords, ["k"]);
  });

  it("DK-015 — fallback main query failure is propagated, not swallowed", async () => {
    const client = createFakeClient({
      probeRows: [],
      mainError: new Error("fallback select failed"),
    });
    await assert.rejects(loadDomains(createFakePool(() => client)), /fallback select failed/);
  });

  it("DK-016 — client.release() called in finally on fallback success and failure", async () => {
    const successClient = createFakeClient({
      probeRows: [],
      mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }],
    });
    await loadDomains(createFakePool(() => successClient));
    assert.equal(successClient.releaseCount, 1);

    const failClient = createFakeClient({
      probeRows: [],
      mainError: new Error("boom"),
    });
    // Clear the domain-data cache so the failure path actually runs a query.
    resetDomainIdentifierCache();
    await assert.rejects(loadDomains(createFakePool(() => failClient)));
    assert.equal(failClient.releaseCount, 1);
  });

  it("DK-017 — malformed probe result is treated as column present", async () => {
    const client = createFakeClient({
      probeRows: [{ column_name: "keywords" }, { column_name: "keywords" }],
      mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", keywords: ["k"], notes: null }],
    });
    const domains = await loadDomains(createFakePool(() => client));

    assert.equal(domains[0].keywords.length, 1);
    const mainQuery = client.queryCalls.find((c) => !/information_schema\.columns/.test(c.text));
    assert.ok(mainQuery);
    assert.match(mainQuery!.text, /ad\.keywords/);
  });

  it("DK-018 — concurrent first calls do not issue duplicate probe queries or warnings", async () => {
    const clients = [
      createFakeClient({ probeRows: [], mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }] }),
      createFakeClient({ probeRows: [], mainRows: [{ id: 1, domain_topic: "x", agent_name: "a", notes: null }] }),
    ];
    const pool = createFakePool(() => clients[clients.length - 1]);
    // Ensure two distinct clients are handed out.
    let call = 0;
    const poolTwoClients = {
      connect: async () => {
        const c = clients[call];
        call += 1;
        return c;
      },
    };

    const [a, b] = await Promise.all([
      loadDomains(poolTwoClients),
      loadDomains(poolTwoClients),
    ]);

    assert.equal(a.length, 1);
    assert.equal(b.length, 1);

    const probeCalls = clients.flatMap((c) => c.queryCalls.filter((q) => /information_schema\.columns/.test(q.text)));
    assert.ok(probeCalls.length <= 1, `expected at most 1 probe query, got ${probeCalls.length}`);
    assert.equal(warnings.length, 1);
  });
});
