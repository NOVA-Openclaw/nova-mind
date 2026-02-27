#!/usr/bin/env -S npx tsx

/**
 * Verification script to ensure the refactored handler can import and use the entity-resolver library
 */

import {
  resolveEntity,
  getEntityProfile,
  getCachedEntity,
  setCachedEntity,
  closeDbPool,
} from "../../../nova-relationships/lib/entity-resolver/index.ts";

async function verify() {
  console.log("\n✅ Successfully imported entity-resolver library from hook!\n");
  
  console.log("Available functions:");
  console.log("  - resolveEntity:", typeof resolveEntity);
  console.log("  - getEntityProfile:", typeof getEntityProfile);
  console.log("  - getCachedEntity:", typeof getCachedEntity);
  console.log("  - setCachedEntity:", typeof setCachedEntity);
  console.log("  - closeDbPool:", typeof closeDbPool);
  
  // Try a simple resolution test
  console.log("\n--- Testing entity resolution ---");
  const entity = await resolveEntity({ phone: "(512) 692-7184" });
  
  if (entity) {
    console.log(`✅ Resolved entity: ${entity.name} (ID: ${entity.id})`);
    
    // Try caching
    const sessionId = "verify-session";
    setCachedEntity(sessionId, entity);
    const cached = getCachedEntity(sessionId);
    
    if (cached && cached.id === entity.id) {
      console.log("✅ Caching works correctly");
    } else {
      console.log("❌ Caching failed");
    }
    
    // Try loading profile
    const profile = await getEntityProfile(entity.id);
    console.log(`✅ Profile loaded: ${Object.keys(profile).length} facts`);
  } else {
    console.log("⚠️  No entity found (database may be empty)");
  }
  
  console.log("\n✅ Hook refactoring verification complete!\n");
  
  await closeDbPool();
}

verify().catch(async (err) => {
  console.error("\n❌ Verification failed:", err.message);
  console.error(err.stack);
  await closeDbPool();
  process.exit(1);
});
