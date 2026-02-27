#!/usr/bin/env ts-node
/**
 * Test script for issue #64: db-bootstrap-context hook fallback directory fix
 * 
 * This script verifies that the hook correctly uses event.context.workspaceDir
 * instead of the hardcoded ~/.openclaw/bootstrap-fallback/ directory.
 */

import { readFile, writeFile, mkdir, rm } from 'fs/promises';
import { join } from 'path';
import { tmpdir } from 'os';

// Define the types to match the hook
interface BootstrapFile {
  path: string;
  content: string;
}

interface BootstrapEvent {
  context: {
    agentId?: string;
    workspaceDir?: string;
    bootstrapFiles: BootstrapFile[];
  };
}

// Import the handler (we'll need to adjust the path)
const handlerPath = join(process.env.HOME || '', '.openclaw/hooks/db-bootstrap-context/handler.ts');

console.log('🧪 Testing Issue #64: db-bootstrap-context fallback directory fix\n');

async function runTests() {
  let passedTests = 0;
  let failedTests = 0;
  
  // Test TC-64-001: Fallback reads from event.context.workspaceDir
  console.log('📋 TC-64-001: Fallback reads from event.context.workspaceDir');
  try {
    const testWorkspace = join(tmpdir(), 'test-workspace-64-001');
    await mkdir(testWorkspace, { recursive: true });
    
    // Create test files
    await writeFile(join(testWorkspace, 'AGENTS.md'), '# Test AGENTS.md\nTest content');
    await writeFile(join(testWorkspace, 'SOUL.md'), '# Test SOUL.md\nTest content');
    
    // Import and test the handler
    const { default: handler } = await import(handlerPath);
    
    const event: BootstrapEvent = {
      context: {
        agentId: 'agent:test:main',
        workspaceDir: testWorkspace,
        bootstrapFiles: []
      }
    };
    
    await handler(event);
    
    // Check if files were loaded from workspace (not hardcoded dir)
    const hasWorkspaceFiles = event.context.bootstrapFiles.some(
      f => f.path.includes('AGENTS.md') || f.path.includes('SOUL.md')
    );
    
    // Clean up
    await rm(testWorkspace, { recursive: true });
    
    if (hasWorkspaceFiles) {
      console.log('✅ PASSED: Files loaded from workspace directory\n');
      passedTests++;
    } else {
      console.log('❌ FAILED: Files not loaded from workspace directory\n');
      failedTests++;
    }
  } catch (error) {
    console.log(`❌ FAILED: ${error}\n`);
    failedTests++;
  }
  
  // Test TC-64-006: Graceful handling when workspaceDir is undefined
  console.log('📋 TC-64-006: Graceful handling when workspaceDir is undefined');
  try {
    const { default: handler } = await import(handlerPath);
    
    const event: BootstrapEvent = {
      context: {
        agentId: 'agent:test:main',
        workspaceDir: undefined,
        bootstrapFiles: []
      }
    };
    
    await handler(event);
    
    // Should fall back to emergency context
    const hasEmergencyContext = event.context.bootstrapFiles.some(
      f => f.path.includes('emergency')
    );
    
    if (hasEmergencyContext) {
      console.log('✅ PASSED: Gracefully fell back to emergency context\n');
      passedTests++;
    } else {
      console.log('❌ FAILED: Did not fall back to emergency context\n');
      failedTests++;
    }
  } catch (error) {
    console.log(`❌ FAILED: ${error}\n`);
    failedTests++;
  }
  
  // Test TC-64-008: Graceful handling when workspaceDir path does not exist
  console.log('📋 TC-64-008: Graceful handling when workspaceDir path does not exist');
  try {
    const { default: handler } = await import(handlerPath);
    
    const event: BootstrapEvent = {
      context: {
        agentId: 'agent:test:main',
        workspaceDir: '/nonexistent/path/workspace',
        bootstrapFiles: []
      }
    };
    
    await handler(event);
    
    // Should fall back to emergency context
    const hasEmergencyContext = event.context.bootstrapFiles.some(
      f => f.path.includes('emergency')
    );
    
    if (hasEmergencyContext) {
      console.log('✅ PASSED: Gracefully handled nonexistent directory\n');
      passedTests++;
    } else {
      console.log('❌ FAILED: Did not handle nonexistent directory gracefully\n');
      failedTests++;
    }
  } catch (error) {
    console.log(`❌ FAILED: Hook crashed: ${error}\n`);
    failedTests++;
  }
  
  // Summary
  console.log('═'.repeat(60));
  console.log(`\n📊 Test Results:`);
  console.log(`   ✅ Passed: ${passedTests}`);
  console.log(`   ❌ Failed: ${failedTests}`);
  console.log(`   📈 Success Rate: ${((passedTests / (passedTests + failedTests)) * 100).toFixed(1)}%\n`);
  
  if (failedTests === 0) {
    console.log('🎉 All tests passed! Issue #64 is fixed.\n');
    process.exit(0);
  } else {
    console.log('⚠️  Some tests failed. Please review the changes.\n');
    process.exit(1);
  }
}

// Verify the handler file has been updated
async function verifyChanges() {
  console.log('🔍 Verifying changes to handler.ts...\n');
  
  try {
    const content = await readFile(handlerPath, 'utf-8');
    
    // Check that FALLBACK_DIR constant is removed
    if (content.includes('FALLBACK_DIR')) {
      console.log('❌ FALLBACK_DIR constant still exists in the code\n');
      return false;
    }
    console.log('✅ FALLBACK_DIR constant has been removed');
    
    // Check that loadFallbackFiles accepts workspaceDir parameter
    if (content.includes('loadFallbackFiles(workspaceDir:')) {
      console.log('✅ loadFallbackFiles now accepts workspaceDir parameter');
    } else {
      console.log('❌ loadFallbackFiles signature not updated\n');
      return false;
    }
    
    // Check that the function is called with event.context.workspaceDir
    if (content.includes('loadFallbackFiles(event.context.workspaceDir)')) {
      console.log('✅ loadFallbackFiles is called with event.context.workspaceDir');
    } else {
      console.log('❌ loadFallbackFiles call site not updated\n');
      return false;
    }
    
    // Check for graceful undefined handling
    if (content.includes('if (!workspaceDir)')) {
      console.log('✅ Graceful handling of undefined workspaceDir added');
    } else {
      console.log('❌ No undefined workspaceDir handling found\n');
      return false;
    }
    
    console.log('\n✨ All code changes verified!\n');
    return true;
  } catch (error) {
    console.log(`❌ Error reading handler file: ${error}\n`);
    return false;
  }
}

// Main execution
(async () => {
  const changesValid = await verifyChanges();
  
  if (!changesValid) {
    console.log('⚠️  Code changes verification failed. Skipping runtime tests.\n');
    process.exit(1);
  }
  
  console.log('═'.repeat(60));
  console.log('\n🚀 Running runtime tests...\n');
  
  await runTests();
})();
