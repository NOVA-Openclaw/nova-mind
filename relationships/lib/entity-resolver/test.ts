#!/usr/bin/env -S npx tsx

/**
 * Test script to verify entity-resolver library functionality
 *
 * Usage:
 *   npx tsx test.ts [phone_or_uuid]
 *   npx tsx test.ts --irc-tests
 *
 * Or make executable and run directly:
 *   chmod +x test.ts
 *   ./test.ts [phone_or_uuid]
 *   ./test.ts --irc-tests
 */

import * as os from "os";
import { join } from "path";
import pg from "pg";
import assert from "node:assert/strict";

import {
  resolveEntity,
  resolveEntityByIdentifiers,
  getEntityProfile,
  getCachedEntity,
  setCachedEntity,
  clearCache,
  getCacheStats,
  closeDbPool,
} from "./index.ts";

const { Client } = pg;

async function loadPgConfig() {
  const pgEnvPath = join(process.env.HOME || os.homedir(), ".openclaw", "lib", "pg-env.ts");
  try {
    const { loadPgEnv } = await import(pgEnvPath);
    return loadPgEnv();
  } catch (e) {
    console.warn('[entity-resolver/test] Could not load pg-env.ts:', (e as Error).message);
    return {};
  }
}

async function getDbClient() {
  const cfg = await loadPgConfig();
  const client = new Client({
    host: cfg.host || "localhost",
    port: cfg.port || 5432,
    database: cfg.database || `${os.userInfo().username.replace(/-/g, "_")}_memory`,
    user: cfg.user || os.userInfo().username,
    password: cfg.password,
  });
  await client.connect();
  return client;
}

async function test() {
  const identifier = process.argv[2];

  if (!identifier) {
    console.log("Usage: node test.js [phone_or_uuid]");
    console.log("       node test.js --irc-tests");
    console.log("\nExample: node test.js +1234567890");
    console.log("         node test.js some-uuid\n");
    return;
  }

  if (identifier === "--irc-tests") {
    await runIrcTests();
    return;
  }

  if (identifier === "--relationship-stats-tests") {
    await runRelationshipStatsTests();
    return;
  }

  console.log(`\n🔍 Testing entity resolution for: ${identifier}\n`);

  // Test 1: Resolve entity
  console.log("--- Test 1: Resolve Entity ---");
  const entity = await resolveEntity({ uuid: identifier, phone: identifier });

  if (!entity) {
    console.log("❌ No entity found for identifier:", identifier);
    await closeDbPool();
    return;
  }

  console.log("✅ Entity found:");
  console.log(`  ID: ${entity.id}`);
  console.log(`  Name: ${entity.name}`);
  console.log(`  Full Name: ${entity.fullName || "N/A"}`);
  console.log(`  Type: ${entity.type}`);

  // Test 2: Load entity profile
  console.log("\n--- Test 2: Load Entity Profile ---");
  const profile = await getEntityProfile(entity.id);

  if (Object.keys(profile).length === 0) {
    console.log("  No profile facts found");
  } else {
    console.log("  Profile facts:");
    for (const [key, value] of Object.entries(profile)) {
      console.log(`    • ${key}: ${value}`);
    }
  }

  // Test 3: Caching
  console.log("\n--- Test 3: Session-Aware Caching ---");
  const sessionId = "test-session-123";

  // Clear any existing cache
  clearCache();
  console.log("✅ Cache cleared");

  // Test cache miss
  let cached = getCachedEntity(sessionId);
  console.log(`  Cache miss (expected): ${cached === null ? "✅" : "❌"}`);

  // Set cache
  setCachedEntity(sessionId, entity);
  console.log("✅ Entity cached for session:", sessionId);

  // Test cache hit
  cached = getCachedEntity(sessionId);
  console.log(`  Cache hit: ${cached !== null ? "✅" : "❌"}`);
  console.log(`  Cached entity: ${cached?.name} (ID: ${cached?.id})`);

  // Test cache stats
  const stats = getCacheStats();
  console.log(`  Cache stats: ${stats.size} session(s) cached`);
  console.log(`  Sessions: ${stats.sessions.join(", ")}`);

  // Test clearing specific session
  clearCache(sessionId);
  cached = getCachedEntity(sessionId);
  console.log(`  After clear: ${cached === null ? "✅" : "❌"}`);

  // Test 4: Multiple identifier types
  console.log("\n--- Test 4: Multiple Identifier Resolution ---");

  // Try with phone
  const byPhone = await resolveEntity({ phone: identifier });
  console.log(`  By phone: ${byPhone ? "✅ Found" : "❌ Not found"}`);

  // Try with UUID
  const byUuid = await resolveEntity({ uuid: identifier });
  console.log(`  By UUID: ${byUuid ? "✅ Found" : "❌ Not found"}`);

  // Try with multiple identifiers at once
  const byMultiple = await resolveEntity({ phone: identifier, uuid: identifier });
  console.log(`  By multiple: ${byMultiple ? "✅ Found" : "❌ Not found"}`);

  // Test 5: IRC identifier support (nova-mind#522)
  console.log("\n--- Test 5: IRC identifier support ---");
  const ircEntity = await resolveEntity({ ircUsername: identifier });
  console.log(`  By ircUsername: ${ircEntity ? `✅ Found (id=${ircEntity.id})` : "❌ Not found"}`);

  console.log("\n✅ All tests completed successfully!\n");

  await closeDbPool();
}

/**
 * TC-522: IRC identifier support tests for the entity-resolver library.
 *
 * These tests hit the live database configured by ~/.openclaw/postgres.json.
 * They create temporary test entities/facts in a high id range and clean them
 * up on completion. Intended for staging; never run against production without
 * review.
 */
async function runIrcTests() {
  const client = await getDbClient();
  const testEntityIds = [99001, 99002, 99003, 99004, 99005, 99006, 99007];

  async function seed() {
    // Clean any stale test rows from a previous aborted run
    await cleanup();

    // TC-522-003 / TC-522-004 / TC-522-006
    await client.query(
      `INSERT INTO entities (id, name, type) VALUES ($1, 'IRC Test Entity', 'person')`,
      [testEntityIds[0]]
    );
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value) VALUES ($1, 'irc_username', 'late.sh/druidian')`,
      [testEntityIds[0]]
    );

    // TC-522-008: multiple irc_username facts per entity
    await client.query(
      `INSERT INTO entities (id, name, type) VALUES ($1, 'IRC Multi-Network Entity', 'person')`,
      [testEntityIds[1]]
    );
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value) VALUES ($1, 'irc_username', 'late.sh/druidian2'), ($1, 'irc_username', 'libera.chat/druidian2')`,
      [testEntityIds[1]]
    );

    // TC-522-009: conflict — two entities share the same composite value
    await client.query(
      `INSERT INTO entities (id, name, type) VALUES ($1, 'IRC Conflict A', 'person'), ($2, 'IRC Conflict B', 'person')`,
      [testEntityIds[2], testEntityIds[3]]
    );
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value) VALUES ($1, 'irc_username', 'late.sh/dupe'), ($2, 'irc_username', 'late.sh/dupe')`,
      [testEntityIds[2], testEntityIds[3]]
    );

    // TC-522-011: nick with special chars
    await client.query(
      `INSERT INTO entities (id, name, type) VALUES ($1, 'IRC Special Entity', 'person')`,
      [testEntityIds[4]]
    );
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value) VALUES ($1, 'irc_username', 'late.sh/dru-idian[bot]')`,
      [testEntityIds[4]]
    );

    // TC-522-013: combined non-IRC identifier conflict detection regression
    await client.query(
      `INSERT INTO entities (id, name, type) VALUES ($1, 'Discord Entity', 'person'), ($2, 'Telegram Entity', 'person')`,
      [testEntityIds[5], testEntityIds[6]]
    );
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value) VALUES ($1, 'discord_id', 'combined-discord-013'), ($2, 'telegram_id', 'combined-telegram-013')`,
      [testEntityIds[5], testEntityIds[6]]
    );
  }

  async function cleanup() {
    await client.query(`DELETE FROM entity_facts WHERE entity_id = ANY($1)`, [testEntityIds]);
    await client.query(`DELETE FROM entities WHERE id = ANY($1)`, [testEntityIds]);
  }

  let passed = 0;
  let failed = 0;

  function check(name: string, condition: boolean, details?: string) {
    if (condition) {
      console.log(`✅ ${name}`);
      passed++;
    } else {
      console.log(`❌ ${name}${details ? ` — ${details}` : ""}`);
      failed++;
    }
  }

  try {
    await seed();

    console.log("\n🔍 TC-522 entity-resolver library tests\n");

    // TC-522-003: happy path — composite match resolves entity
    const e003 = await resolveEntity({ ircUsername: "late.sh/druidian" });
    check("TC-522-003: resolveEntity happy path", e003?.id === testEntityIds[0]);

    // TC-522-004: happy path — multi-entity resolver variant
    const r004 = await resolveEntityByIdentifiers({ ircUsername: "late.sh/druidian" });
    check(
      "TC-522-004: resolveEntityByIdentifiers happy path",
      r004 != null && r004.ok === true && r004.entity.id === testEntityIds[0]
    );

    // TC-522-005: negative — same nick, different network, no match
    const e005 = await resolveEntity({ ircUsername: "libera.chat/druidian" });
    check("TC-522-005: different network returns null", e005 === null);

    // TC-522-006: negative — unknown nick, no match
    const e006 = await resolveEntity({ ircUsername: "late.sh/nobodyknown" });
    check("TC-522-006: unknown nick returns null", e006 === null);

    // TC-522-007: negative — lookalike nick, no fuzzy/prefix match
    const e007 = await resolveEntity({ ircUsername: "late.sh/druidian_" });
    check("TC-522-007: lookalike nick returns null", e007 === null);

    // TC-522-008: multiple irc_username facts per entity
    const e008a = await resolveEntity({ ircUsername: "late.sh/druidian2" });
    const e008b = await resolveEntity({ ircUsername: "libera.chat/druidian2" });
    check(
      "TC-522-008: multiple irc_username facts per entity",
      e008a?.id === testEntityIds[1] && e008b?.id === testEntityIds[1]
    );

    // TC-522-009: conflict detection
    const r009 = await resolveEntityByIdentifiers({ ircUsername: "late.sh/dupe" });
    check(
      "TC-522-009: conflict detected for shared composite value",
      r009 != null && r009.ok === false && r009.conflict === true
    );

    // TC-522-010: case normalization is caller responsibility (exact match)
    const e010 = await resolveEntity({ ircUsername: "late.sh/druidian" });
    check("TC-522-010: exact lowercased match resolves", e010?.id === testEntityIds[0]);

    // TC-522-011: nick with IRC-legal special chars
    const e011 = await resolveEntity({ ircUsername: "late.sh/dru-idian[bot]" });
    check("TC-522-011: special chars resolve exactly", e011?.id === testEntityIds[4]);

    // TC-522-031: legacy mixed-case row does NOT match lowercased lookup
    await client.query(
      `UPDATE entity_facts SET value = 'late.sh/Druidian' WHERE entity_id = $1 AND key = 'irc_username'`,
      [testEntityIds[0]]
    );
    const e031 = await resolveEntity({ ircUsername: "late.sh/druidian" });
    check(
      "TC-522-031: legacy mixed-case row invisible to lowercased lookup (migration required)",
      e031 === null
    );
    // Restore lowercased value for idempotency
    await client.query(
      `UPDATE entity_facts SET value = 'late.sh/druidian' WHERE entity_id = $1 AND key = 'irc_username'`,
      [testEntityIds[0]]
    );

    // TC-522-012: regression — non-IRC identifiers still work
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value) VALUES ($1, 'discord_id', '123456789')`,
      [testEntityIds[0]]
    );
    const e012 = await resolveEntity({ discordId: "123456789" });
    check("TC-522-012: discord_id regression", e012?.id === testEntityIds[0]);
    await client.query(
      `DELETE FROM entity_facts WHERE entity_id = $1 AND key = 'discord_id'`,
      [testEntityIds[0]]
    );

    // TC-522-013: regression — combined non-IRC identifier conflict detection unaffected
    const r013 = await resolveEntityByIdentifiers({
      discordId: "combined-discord-013",
      telegramId: "combined-telegram-013",
    });
    check(
      "TC-522-013: combined non-IRC identifier conflict detection unaffected",
      r013 != null && r013.ok === false && r013.conflict === true && r013.entities?.length === 2
    );

    console.log(`\n${passed} passed, ${failed} failed\n`);
    if (failed > 0) {
      process.exitCode = 1;
    }
  } catch (err) {
    console.error("\n❌ IRC tests failed:", err instanceof Error ? err.message : String(err));
    console.error((err as Error).stack);
    process.exitCode = 1;
  } finally {
    await cleanup();
    await client.end();
    await closeDbPool();
  }
}

/**
 * RS-0xx: Relationship stats integration tests for nova-mind#543.
 *
 * These tests hit the live database (intended for nova-staging) and seed
 * disposable rows in entities, entity_facts, channel_sessions, and
 * channel_transcripts. IDs are chosen in the 99101–99110 range to avoid
 * collision with the IRC tests (99001–99007).
 */
async function runRelationshipStatsTests() {
  const client = await getDbClient();
  const testEntityIds = [99101, 99102, 99103];
  const testSessionIds: number[] = [];

  async function cleanup() {
    await client.query(
      `DELETE FROM channel_transcripts WHERE session_id = ANY($1)`,
      [testSessionIds]
    );
    await client.query(
      `DELETE FROM channel_sessions WHERE id = ANY($1)`,
      [testSessionIds]
    );
    await client.query(`DELETE FROM entity_facts WHERE entity_id = ANY($1)`, [testEntityIds]);
    await client.query(`DELETE FROM entities WHERE id = ANY($1)`, [testEntityIds]);
  }

  async function seed() {
    // Clean any stale test rows from a previous aborted run
    await cleanup();

    // RS-003/RS-044 rich entity: mixed visibility facts + transcript
    await client.query(
      `INSERT INTO entities (
         id, name, full_name, type, pronouns, trust_level, last_seen, created_at
       ) VALUES ($1, 'Tabatha', 'Tabatha Janell Wilson', 'person', 'she/her', 'friend',
                 '2026-07-27 08:00:00'::timestamp, '2026-01-30'::timestamp)`,
      [testEntityIds[0]]
    );
    // 19 public + 15 trusted + 13 private + 1 timezone = 48 facts (unfiltered count test)
    const visibilityFacts: Array<{ key: string; value: string; visibility: string; privacy_scope: number[] | null }> = [];
    for (let i = 0; i < 19; i++) {
      visibilityFacts.push({ key: `public_fact_${i}`, value: `v${i}`, visibility: "public", privacy_scope: null });
    }
    for (let i = 0; i < 15; i++) {
      visibilityFacts.push({ key: `trusted_fact_${i}`, value: `v${i}`, visibility: "trusted", privacy_scope: null });
    }
    for (let i = 0; i < 13; i++) {
      visibilityFacts.push({ key: `private_fact_${i}`, value: `v${i}`, visibility: "private", privacy_scope: null });
    }
    // Bulk insert
    const valuesSql = visibilityFacts
      .map((_, idx) => `($1, $${idx * 4 + 2}, $${idx * 4 + 3}, $${idx * 4 + 4}, $${idx * 4 + 5})`)
      .join(",");
    const params = [testEntityIds[0], ...visibilityFacts.flatMap((f) => [f.key, f.value, f.visibility, f.privacy_scope])];
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value, visibility, privacy_scope) VALUES ${valuesSql}`,
      params
    );
    // Allowlist fact for RS-004 regression
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value) VALUES ($1, 'timezone', 'America/Chicago')`,
      [testEntityIds[0]]
    );

    // Create a channel session + transcript for last-message lookup
    const sessionRes = await client.query(
      `INSERT INTO channel_sessions (provider, external_chat_id, chat_type)
       VALUES ('discord', '1513392492651872306', 'direct')
       RETURNING id`
    );
    const sessionId = sessionRes.rows[0].id;
    testSessionIds.push(sessionId);
    await client.query(
      `INSERT INTO channel_transcripts (
         session_id, external_message_id, timestamp, sender_entity_id, content
       ) VALUES ($1, 'msg-001', '2026-07-27 02:11:00+00', $2, 'hello')`,
      [sessionId, testEntityIds[0]]
    );
    // Older transcript — should not be returned
    await client.query(
      `INSERT INTO channel_transcripts (
         session_id, external_message_id, timestamp, sender_entity_id, content
       ) VALUES ($1, 'msg-002', '2026-07-26 10:00:00+00', $2, 'earlier')`,
      [sessionId, testEntityIds[0]]
    );

    // RS-014 degenerate entity: zero facts, no transcripts
    await client.query(
      `INSERT INTO entities (id, name, type, trust_level, created_at)
       VALUES ($1, 'Brand New User', 'person', 'unknown', '2026-07-28'::timestamp)`,
      [testEntityIds[1]]
    );

    // RS-015 entity: last_seen populated but no transcripts
    await client.query(
      `INSERT INTO entities (id, name, type, last_seen, created_at)
       VALUES ($1, 'No Transcript User', 'person', '2026-07-26 08:00:00'::timestamp, '2026-07-01'::timestamp)`,
      [testEntityIds[2]]
    );
  }

  let passed = 0;
  let failed = 0;

  function check(name: string, condition: boolean, details?: string) {
    if (condition) {
      console.log(`✅ ${name}`);
      passed++;
    } else {
      console.log(`❌ ${name}${details ? ` — ${details}` : ""}`);
      failed++;
    }
  }

  try {
    await seed();
    console.log("\n🔍 RS-0xx relationship stats integration tests\n");

    // RS-003 / RS-044: rich profile with unfiltered count
    const profile = await getEntityProfile(testEntityIds[0]);
    check(
      "RS-003/RS-044: fact count is unfiltered (48) and allowlist facts present",
      profile.stats.factCount === 48 && profile.facts.timezone === "America/Chicago"
    );
    check(
      "RS-003: last message timestamp + two-part ref",
      profile.stats.lastMessage != null &&
        profile.stats.lastMessage.timestamp === "2026-07-27 02:11 UTC" &&
        profile.stats.lastMessage.ref === "discord:1513392492651872306"
    );

    // RS-002 / RS-001: pronouns and trust_level fetched in identifier query
    const r002 = await resolveEntityByIdentifiers({ discordId: "1513392492651872306" });
    // The seeded entity has no discord_id fact, so this will not resolve by discordId.
    // Instead resolve by the explicit entity id fact we add here:
    await client.query(
      `INSERT INTO entity_facts (entity_id, key, value) VALUES ($1, 'discord_id', 'rs543-tabatha')`,
      [testEntityIds[0]]
    );
    const r002b = await resolveEntityByIdentifiers({ discordId: "rs543-tabatha" });
    check(
      "RS-001/RS-002: pronouns and trust_level resolved with identifier query",
      r002b != null &&
        r002b.ok === true &&
        r002b.entity.pronouns === "she/her" &&
        r002b.entity.trustLevel === "friend" &&
        r002b.entity.createdAt === "2026-01-30"
    );

    // RS-014: degenerate entity
    const profileNew = await getEntityProfile(testEntityIds[1]);
    check(
      "RS-014: zero facts + no transcripts → empty profile, zero count",
      profileNew.stats.factCount === 0 && profileNew.stats.lastMessage === null && Object.keys(profileNew.facts).length === 0
    );

    // RS-015: last_seen fallback scenario (no transcripts but last_seen set)
    const profileFallback = await getEntityProfile(testEntityIds[2]);
    check(
      "RS-015: no transcripts → lastMessage null (last_seen is an entity field, not a profile stat)",
      profileFallback.stats.factCount === 0 && profileFallback.stats.lastMessage === null
    );

    // RS-050: simple timing check (informational, generous ceiling)
    const start = process.hrtime.bigint();
    await getEntityProfile(testEntityIds[0]);
    const elapsedMs = Number(process.hrtime.bigint() - start) / 1_000_000;
    check(
      `RS-050: aggregate query completes within budget (${elapsedMs.toFixed(2)}ms)`,
      elapsedMs < 200,
      `took ${elapsedMs.toFixed(2)}ms`
    );

    // RS-051: EXPLAIN confirms index usage
    const explainResult = await client.query(
      `EXPLAIN (FORMAT JSON)
       SELECT
         fc.count AS fact_count,
         to_char(lm.timestamp AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"') AS last_message_time,
         lm.provider AS last_message_provider,
         lm.external_chat_id AS last_message_external_chat_id,
         facts.facts_json
       FROM (SELECT COUNT(*) AS count FROM entity_facts WHERE entity_id = $1) fc
       LEFT JOIN LATERAL (
         SELECT ct.timestamp, cs.provider, cs.external_chat_id
         FROM channel_transcripts ct
         JOIN channel_sessions cs ON ct.session_id = cs.id
         WHERE ct.sender_entity_id = $1
         ORDER BY ct.timestamp DESC
         LIMIT 1
       ) lm ON true
       LEFT JOIN LATERAL (
         SELECT COALESCE(
           jsonb_agg(jsonb_build_object('key', sub.key, 'value', sub.value)),
           '[]'::jsonb
         ) AS facts_json
         FROM (
           SELECT key, value
           FROM entity_facts
           WHERE entity_id = $1 AND key = ANY($2)
           LIMIT 20
         ) sub
       ) facts ON true`,
      [testEntityIds[0], ["timezone"]]
    );
    const planText = JSON.stringify(explainResult.rows[0]["QUERY PLAN"]);
    const hasSeqScanEntityFacts = planText.includes('"Node Type": "Seq Scan"') && planText.includes("entity_facts");
    const hasSeqScanTranscripts = planText.includes('"Node Type": "Seq Scan"') && planText.includes("channel_transcripts");
    check(
      "RS-051: EXPLAIN shows no seq scan on entity_facts or channel_transcripts",
      !hasSeqScanEntityFacts && !hasSeqScanTranscripts,
      planText
    );

    console.log(`\n${passed} passed, ${failed} failed\n`);
    if (failed > 0) {
      process.exitCode = 1;
    }
  } catch (err) {
    console.error("\n❌ Relationship stats tests failed:", err instanceof Error ? err.message : String(err));
    console.error((err as Error).stack);
    process.exitCode = 1;
  } finally {
    await cleanup();
    await client.end();
    await closeDbPool();
  }
}

test().catch(async (err) => {
  console.error("\n❌ Test failed:", err.message);
  console.error(err.stack);
  await closeDbPool();
  process.exit(1);
});
