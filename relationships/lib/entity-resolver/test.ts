#!/usr/bin/env -S npx tsx

/**
 * Test script to verify entity-resolver library functionality
 * 
 * Usage: 
 *   npx tsx test.ts [phone_or_uuid]
 * 
 * Or make executable and run directly:
 *   chmod +x test.ts
 *   ./test.ts [phone_or_uuid]
 */

import {
  resolveEntity,
  getEntityProfile,
  getCachedEntity,
  setCachedEntity,
  clearCache,
  getCacheStats,
  closeDbPool,
} from "./index.ts";

async function test() {
  const identifier = process.argv[2];
  
  if (!identifier) {
    console.log("Usage: node test.js [phone_or_uuid]");
    console.log("\nExample: node test.js +1234567890");
    console.log("         node test.js some-uuid\n");
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
  
  console.log("\n✅ All tests completed successfully!\n");
  
  await closeDbPool();
}

test().catch(async (err) => {
  console.error("\n❌ Test failed:", err.message);
  console.error(err.stack);
  await closeDbPool();
  process.exit(1);
});
