/**
 * Domain Identifier subsystem.
 *
 * Matches inbound messages to agent domains using two strategies:
 *   1. Keyword matching against agent_domains.keywords (TEXT[])
 *   2. Embedding similarity against memory_embeddings (source_type='agent_domain')
 *
 * Both scores are combined for final ranking.
 * Domain table data is cached for 5 minutes (DOMAIN_CACHE_TTL_MS).
 * Agent name is resolved via JOIN on agents table — never hardcoded.
 *
 * Issues: nova-mind #150
 */

import * as http from "http";
import { getPool } from "./shared/pg-pool.ts";

/**
 * Minimal client/pool shape used by loadDomains(). Keeps the plugin code free
 * of a hard pg.Pool dependency and makes unit testing straightforward.
 */
interface DomainPoolClient {
  query<RowType = unknown>(
    text: string,
    values?: unknown[]
  ): Promise<{ rows: RowType[] }>;
  release(): void;
}

interface DomainPool {
  connect(): Promise<DomainPoolClient>;
}

// ── Configuration ─────────────────────────────────────────────────────────────

const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || "http://localhost:11434";
const EMBEDDING_MODEL = "snowflake-arctic-embed2";
const EMBEDDING_DIMS = 1024;
const EMBEDDING_TIMEOUT_MS = 8000;
export const DOMAIN_CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes
const SIMILARITY_THRESHOLD = parseFloat(
  process.env.DOMAIN_SIMILARITY_THRESHOLD || "0.4"
);
const KEYWORD_SCORE_BOOST = 0.2; // Added to vector score when keyword also matches
const KEYWORD_BASE_SCORE = 0.5; // Base score for keyword-only matches (no vector)
const MAX_RESULTS = 3; // Return top N domains

// ── Types ─────────────────────────────────────────────────────────────────────

interface DomainRow {
  id: number;
  domainTopic: string;
  agentName: string;
  keywords: string[];
  notes: string;
}

export interface DomainMatch {
  domain: string;
  agent: string;
  similarity: number;
  matchedBy: "keyword" | "vector" | "both";
}

export interface DomainResult {
  domains: DomainMatch[];
  indicator?: "NO DOMAIN IDENTIFIED";
}

// ── Domain data cache ─────────────────────────────────────────────────────────

interface DomainCacheEntry {
  domains: DomainRow[];
  timestamp: number;
}

let domainCache: DomainCacheEntry | null = null;

// Caches for the agent_domains.keywords column probe.
// Only a successful probe result is cached (B1); a probe failure is transient
// and falls back to the canonical keywords-included query.
let keywordsColumnPresent: boolean | null = null;
let keywordsColumnProbePromise: Promise<boolean> | null = null;
let keywordsMissingWarningEmitted = false;

const KEYWORDS_MISSING_WARNING =
  "[turn-context] agent_domains.keywords missing — keyword matching disabled; apply nova-mind schema migration";

// Byte-identical to the pre-fix query (B3).
const DOMAIN_QUERY_WITH_KEYWORDS = `
      SELECT ad.id, ad.domain_topic, a.name AS agent_name, ad.keywords, ad.notes
      FROM agent_domains ad
      JOIN agents a ON ad.agent_id = a.id
      ORDER BY ad.domain_topic
    `;

const DOMAIN_QUERY_WITHOUT_KEYWORDS = `
      SELECT ad.id, ad.domain_topic, a.name AS agent_name, ad.notes
      FROM agent_domains ad
      JOIN agents a ON ad.agent_id = a.id
      ORDER BY ad.domain_topic
    `;

async function probeKeywordsColumn(client: DomainPoolClient): Promise<boolean> {
  const result = await client.query<{ column_name: string }>(
    `SELECT column_name
       FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND table_name = 'agent_domains'
        AND column_name = 'keywords'`
  );
  return result.rows.length > 0;
}

async function getKeywordsColumnPresent(client: DomainPoolClient): Promise<boolean> {
  if (keywordsColumnPresent !== null) {
    return keywordsColumnPresent;
  }
  if (!keywordsColumnProbePromise) {
    keywordsColumnProbePromise = probeKeywordsColumn(client)
      .then((present) => {
        keywordsColumnPresent = present;
        return present;
      })
      .catch((err) => {
        // B1: probe failures are not cached; next call will retry.
        keywordsColumnProbePromise = null;
        throw err;
      });
  }
  return keywordsColumnProbePromise;
}

export async function loadDomains(pool?: DomainPool): Promise<DomainRow[]> {
  const now = Date.now();
  if (domainCache && now - domainCache.timestamp < DOMAIN_CACHE_TTL_MS) {
    return domainCache.domains;
  }

  const client: DomainPoolClient = pool
    ? await pool.connect()
    : (await getPool().connect() as DomainPoolClient);
  try {
    let useKeywords = keywordsColumnPresent;

    if (useKeywords === null) {
      try {
        useKeywords = await getKeywordsColumnPresent(client);
      } catch {
        // B1: probe failure => assume column present and let the normal query
        // behave exactly as it did before this fix.
        useKeywords = true;
      }
    }

    let result;
    if (useKeywords) {
      result = await client.query<{
        id: number;
        domain_topic: string;
        agent_name: string;
        keywords: string[] | null;
        notes: string | null;
      }>(DOMAIN_QUERY_WITH_KEYWORDS);
    } else {
      if (!keywordsMissingWarningEmitted) {
        keywordsMissingWarningEmitted = true;
        console.warn(KEYWORDS_MISSING_WARNING);
      }
      result = await client.query<{
        id: number;
        domain_topic: string;
        agent_name: string;
        notes: string | null;
      }>(DOMAIN_QUERY_WITHOUT_KEYWORDS);
    }

    const domains: DomainRow[] = result.rows.map((row) => ({
      id: row.id,
      domainTopic: row.domain_topic,
      agentName: row.agent_name,
      keywords: useKeywords ? (row.keywords ?? []) : [],
      notes: row.notes ?? "",
    }));

    domainCache = { domains, timestamp: now };
    console.info(
      `[turn-context] domain-identifier: loaded ${domains.length} domains from DB`
    );
    return domains;
  } finally {
    client.release();
  }
}

/**
 * Reset caches and the warning-once guard. Intended for tests only.
 */
export function resetDomainIdentifierCache(): void {
  domainCache = null;
  keywordsColumnPresent = null;
  keywordsColumnProbePromise = null;
  keywordsMissingWarningEmitted = false;
}

// ── Embedding ─────────────────────────────────────────────────────────────────

function getEmbedding(text: string): Promise<number[]> {
  const body = JSON.stringify({ model: EMBEDDING_MODEL, prompt: text });

  return new Promise((resolve, reject) => {
    let req: http.ClientRequest;

    const timeout = setTimeout(() => {
      req?.destroy();
      reject(new Error(`Embedding timeout after ${EMBEDDING_TIMEOUT_MS}ms`));
    }, EMBEDDING_TIMEOUT_MS);

    try {
      const url = new URL(`${OLLAMA_BASE_URL}/api/embeddings`);
      const options: http.RequestOptions = {
        hostname: url.hostname,
        port: parseInt(url.port || "80", 10),
        path: url.pathname,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(body),
        },
      };

      req = http.request(options, (res) => {
        let data = "";
        res.on("data", (chunk: Buffer) => {
          data += chunk.toString();
        });
        res.on("end", () => {
          clearTimeout(timeout);
          try {
            const parsed = JSON.parse(data);
            const embedding: number[] = parsed.embedding;
            if (!Array.isArray(embedding) || embedding.length !== EMBEDDING_DIMS) {
              reject(
                new Error(
                  `Dimension mismatch: got ${embedding?.length ?? "undefined"}, expected ${EMBEDDING_DIMS}`
                )
              );
              return;
            }
            resolve(embedding);
          } catch (err) {
            reject(new Error(`Embedding parse error: ${err}`));
          }
        });
      });

      req.on("error", (err: Error) => {
        clearTimeout(timeout);
        reject(err);
      });

      req.write(body);
      req.end();
    } catch (err) {
      clearTimeout(timeout);
      reject(err);
    }
  });
}

// ── Keyword matching ──────────────────────────────────────────────────────────

/**
 * Check which domains have keywords present in the message.
 * Returns a Map<domainId, keywordScore>.
 */
export function matchKeywords(
  message: string,
  domains: DomainRow[]
): Map<number, number> {
  const lower = message.toLowerCase();
  const scores = new Map<number, number>();

  for (const domain of domains) {
    if (!domain.keywords.length) continue;

    let best = 0;
    for (const kw of domain.keywords) {
      if (lower.includes(kw.toLowerCase())) {
        // Longer keywords are more specific — give them higher weight
        const score = KEYWORD_BASE_SCORE + kw.length * 0.01;
        if (score > best) best = score;
      }
    }

    if (best > 0) {
      scores.set(domain.id, best);
    }
  }

  return scores;
}

// ── Vector similarity via PostgreSQL ─────────────────────────────────────────

/**
 * Use pgvector cosine distance to find domain embeddings similar to the query.
 * Returns Map<domainId, similarity>.
 */
async function matchVectorSimilarity(
  embedding: number[],
  domains: DomainRow[]
): Promise<Map<number, number>> {
  const scores = new Map<number, number>();

  const pool = getPool();
  const client = await pool.connect();
  try {
    const vectorStr = `[${embedding.join(",")}]`;
    const result = await client.query<{
      source_id: string;
      similarity: number;
    }>(
      `
      SELECT
        source_id,
        1 - (embedding <=> $1::vector) AS similarity
      FROM memory_embeddings
      WHERE source_type = 'agent_domain'
        AND 1 - (embedding <=> $1::vector) >= $2
      ORDER BY similarity DESC
      LIMIT 10
      `,
      [vectorStr, SIMILARITY_THRESHOLD]
    );

    for (const row of result.rows) {
      // source_id is the domain_topic string (set by seed-domain-embeddings.py),
      // not a numeric id — look up the DomainRow by topic name.
      const domain = domains.find((d) => d.domainTopic === row.source_id);
      if (domain) {
        scores.set(domain.id, row.similarity);
      }
    }
  } finally {
    client.release();
  }

  return scores;
}

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Identify the domain(s) most relevant to the given message.
 *
 * Combines keyword matching (fast, local) with embedding similarity (pgvector).
 * Returns the top 1-3 matches above the similarity threshold, or NO DOMAIN IDENTIFIED.
 *
 * The agent name is always resolved via agents JOIN — never hardcoded.
 *
 * @param message      The message to match against domains
 * @param hintKeywords Optional domain hints from the classifier
 */
export async function identifyDomain(
  message: string,
  hintKeywords?: string[]
): Promise<DomainResult> {
  if (!message.trim()) {
    return { domains: [], indicator: "NO DOMAIN IDENTIFIED" };
  }

  let domains: DomainRow[];
  try {
    domains = await loadDomains();
  } catch (err) {
    console.error(
      "[turn-context] domain-identifier DB error:",
      err instanceof Error ? err.message : String(err)
    );
    return { domains: [], indicator: "NO DOMAIN IDENTIFIED" };
  }

  // Step 1: Keyword matching (synchronous, fast)
  const keywordScores = matchKeywords(message, domains);

  // Apply classifier hints as additional keyword boost
  if (hintKeywords?.length) {
    const lower = message.toLowerCase();
    const lowerHints = hintKeywords.map((h) => h.toLowerCase());
    for (const domain of domains) {
      const topic = domain.domainTopic.toLowerCase();
      if (lowerHints.some((h) => topic.includes(h) || h.includes(topic) || lower.includes(h))) {
        const existing = keywordScores.get(domain.id) ?? 0;
        keywordScores.set(domain.id, Math.max(existing, SIMILARITY_THRESHOLD));
      }
    }
  }

  // Step 2: Embedding similarity (async, pgvector)
  let vectorScores = new Map<number, number>();
  try {
    const embedding = await getEmbedding(message);
    vectorScores = await matchVectorSimilarity(embedding, domains);
  } catch (err) {
    console.warn(
      "[turn-context] domain-identifier embedding error:",
      err instanceof Error ? err.message : String(err)
    );
    // Gracefully continue with keyword-only results
  }

  // Step 3: Combine keyword and vector scores
  const allIds = new Set([...keywordScores.keys(), ...vectorScores.keys()]);

  const candidates: Array<{
    domain: DomainRow;
    score: number;
    matchedBy: "keyword" | "vector" | "both";
  }> = [];

  for (const id of allIds) {
    const domain = domains.find((d) => d.id === id);
    if (!domain) continue;

    const kwScore = keywordScores.get(id) ?? 0;
    const vecScore = vectorScores.get(id) ?? 0;

    const hasKeyword = kwScore > 0;
    const hasVector = vecScore >= SIMILARITY_THRESHOLD;

    if (!hasKeyword && !hasVector) continue;

    let combinedScore: number;
    let matchedBy: "keyword" | "vector" | "both";

    if (hasKeyword && hasVector) {
      // Both: vector similarity + keyword boost (keywords confirm the match)
      combinedScore = vecScore + KEYWORD_SCORE_BOOST;
      matchedBy = "both";
    } else if (hasKeyword) {
      combinedScore = kwScore;
      matchedBy = "keyword";
    } else {
      combinedScore = vecScore;
      matchedBy = "vector";
    }

    candidates.push({ domain, score: combinedScore, matchedBy });
  }

  // Sort descending by score, take top N
  candidates.sort((a, b) => b.score - a.score);
  const top = candidates.slice(0, MAX_RESULTS);

  if (top.length === 0) {
    return { domains: [], indicator: "NO DOMAIN IDENTIFIED" };
  }

  const matches: DomainMatch[] = top.map(({ domain, score, matchedBy }) => ({
    domain: domain.domainTopic,
    agent: domain.agentName,
    similarity: Math.min(1.0, Math.round(score * 1000) / 1000),
    matchedBy,
  }));

  console.info(
    `[turn-context] domain=${matches[0].domain} similarity=${matches[0].similarity} matchedBy=${matches[0].matchedBy}`
  );

  return { domains: matches };
}

/**
 * Format domain match results as a human-readable string for prompt injection.
 *
 * @param result DomainResult from identifyDomain()
 * @returns Formatted string or null if no domain identified
 */
export function formatDomainContext(result: DomainResult): string | null {
  if (!result.domains.length || result.indicator === "NO DOMAIN IDENTIFIED") {
    return null;
  }

  const lines = result.domains.map((d) => {
    const pct = (d.similarity * 100).toFixed(0);
    return `🏷️ Domain: ${d.domain} → ${d.agent} (${d.matchedBy}, ${pct}%)`;
  });

  return lines.join("\n");
}
