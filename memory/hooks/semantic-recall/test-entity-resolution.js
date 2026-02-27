#!/usr/bin/env node

/**
 * Test script to verify entity resolution functionality
 * Usage: node test-entity-resolution.js [phone_or_uuid]
 */

import pg from "pg";

const { Pool } = pg;

const pool = new Pool({
  host: process.env.PGHOST || "localhost",
  database: process.env.PGDATABASE || "nova_memory",
  user: process.env.PGUSER || "nova",
  password: process.env.PGPASSWORD,
  max: 5,
});

async function resolveEntity(identifier) {
  try {
    const result = await pool.query(
      `SELECT e.id, e.name, e.full_name 
       FROM entities e 
       JOIN entity_facts ef ON e.id = ef.entity_id 
       WHERE (ef.key = 'phone' AND ef.value = $1)
          OR (ef.key = 'signal_uuid' AND ef.value = $1)
       LIMIT 1`,
      [identifier]
    );

    if (result.rows.length > 0) {
      return result.rows[0];
    }
    
    return null;
  } catch (err) {
    console.error("Entity resolution error:", err.message);
    return null;
  }
}

async function loadEntityFacts(entityId) {
  try {
    const result = await pool.query(
      `SELECT key, value FROM entity_facts 
       WHERE entity_id = $1 
       AND key IN ('timezone', 'current_timezone', 'communication_style', 'expertise', 'preferences')
       LIMIT 10`,
      [entityId]
    );

    return result.rows;
  } catch (err) {
    console.error("Entity facts loading error:", err.message);
    return [];
  }
}

async function test() {
  const identifier = process.argv[2];
  
  if (!identifier) {
    console.log("Usage: node test-entity-resolution.js [phone_or_uuid]");
    console.log("\nTesting with a sample query to list available entity identifiers...\n");
    
    // List some example identifiers
    const examples = await pool.query(
      `SELECT DISTINCT key, value FROM entity_facts 
       WHERE key IN ('phone', 'signal_uuid') 
       LIMIT 5`
    );
    
    console.log("Example identifiers in database:");
    examples.rows.forEach(row => {
      console.log(`  ${row.key}: ${row.value}`);
    });
    
    await pool.end();
    return;
  }
  
  console.log(`Testing entity resolution for: ${identifier}\n`);
  
  const entity = await resolveEntity(identifier);
  
  if (!entity) {
    console.log("❌ No entity found for identifier:", identifier);
    await pool.end();
    return;
  }
  
  console.log("✅ Entity found:");
  console.log(`  ID: ${entity.id}`);
  console.log(`  Name: ${entity.name}`);
  console.log(`  Full Name: ${entity.full_name || "N/A"}`);
  
  console.log("\nLoading entity facts...\n");
  
  const facts = await loadEntityFacts(entity.id);
  
  if (facts.length === 0) {
    console.log("  No relevant facts found");
  } else {
    console.log("  Facts:");
    facts.forEach(fact => {
      console.log(`    • ${fact.key}: ${fact.value}`);
    });
  }
  
  await pool.end();
}

test().catch(err => {
  console.error("Test failed:", err);
  process.exit(1);
});
