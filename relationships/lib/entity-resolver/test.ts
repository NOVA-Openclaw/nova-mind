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
  const testEntityIds = [99001, 99002, 99003, 99004, 99005];

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

test().catch(async (err) => {
  console.error("\n❌ Test failed:", err.message);
  console.error(err.stack);
  await closeDbPool();
  process.exit(1);
});
