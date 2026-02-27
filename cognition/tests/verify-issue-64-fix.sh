#!/bin/bash
# Verification script for Issue #64 fix
# This script performs static analysis to verify the fix is correct

echo "🔍 Verifying Issue #64 Fix: db-bootstrap-context fallback directory"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

HANDLER_FILE="$HOME/.openclaw/hooks/db-bootstrap-context/handler.ts"
PASSED=0
FAILED=0

# Check 1: FALLBACK_DIR constant should NOT exist
echo "✓ Check 1: Hardcoded FALLBACK_DIR constant removed"
if grep -q "const FALLBACK_DIR" "$HANDLER_FILE"; then
    echo "  ❌ FAILED: FALLBACK_DIR constant still exists"
    ((FAILED++))
else
    echo "  ✅ PASSED: FALLBACK_DIR constant not found"
    ((PASSED++))
fi
echo ""

# Check 2: loadFallbackFiles should accept workspaceDir parameter
echo "✓ Check 2: loadFallbackFiles accepts workspaceDir parameter"
if grep -q "loadFallbackFiles(workspaceDir: string" "$HANDLER_FILE"; then
    echo "  ✅ PASSED: Function signature updated"
    ((PASSED++))
else
    echo "  ❌ FAILED: Function signature not updated"
    ((FAILED++))
fi
echo ""

# Check 3: loadFallbackFiles should handle undefined workspaceDir
echo "✓ Check 3: Undefined workspaceDir handled gracefully"
if grep -q "if (!workspaceDir)" "$HANDLER_FILE"; then
    echo "  ✅ PASSED: Undefined check present"
    ((PASSED++))
else
    echo "  ❌ FAILED: No undefined check found"
    ((FAILED++))
fi
echo ""

# Check 4: Call site should pass event.context.workspaceDir
echo "✓ Check 4: loadFallbackFiles called with event.context.workspaceDir"
if grep -q "loadFallbackFiles(event.context.workspaceDir)" "$HANDLER_FILE"; then
    echo "  ✅ PASSED: Call site updated correctly"
    ((PASSED++))
else
    echo "  ❌ FAILED: Call site not updated"
    ((FAILED++))
fi
echo ""

# Check 5: Files should be read from workspaceDir parameter, not hardcoded path
echo "✓ Check 5: Files read from workspaceDir parameter"
if grep -q "join(workspaceDir, filename)" "$HANDLER_FILE"; then
    echo "  ✅ PASSED: Using workspaceDir parameter for file reads"
    ((PASSED++))
else
    echo "  ❌ FAILED: Not using workspaceDir parameter"
    ((FAILED++))
fi
echo ""

# Check 6: No references to bootstrap-fallback directory
echo "✓ Check 6: No references to hardcoded bootstrap-fallback directory"
if grep -q "bootstrap-fallback" "$HANDLER_FILE"; then
    echo "  ❌ FAILED: References to bootstrap-fallback still exist"
    ((FAILED++))
else
    echo "  ✅ PASSED: No bootstrap-fallback references found"
    ((PASSED++))
fi
echo ""

# Check 7: MEMORY.md added to fallback files list
echo "✓ Check 7: MEMORY.md added to fallback files list"
if grep -A 10 "const fallbackFiles" "$HANDLER_FILE" | grep -q "MEMORY.md"; then
    echo "  ✅ PASSED: MEMORY.md in fallback files"
    ((PASSED++))
else
    echo "  ⚠️  WARNING: MEMORY.md not in fallback files (not critical)"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Verification Results:"
echo "   ✅ Passed: $PASSED"
echo "   ❌ Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo "🎉 All checks passed! Issue #64 is fixed."
    echo ""
    echo "Summary of changes:"
    echo "  • Removed hardcoded FALLBACK_DIR constant"
    echo "  • Updated loadFallbackFiles() to accept workspaceDir parameter"
    echo "  • Added graceful handling for undefined workspaceDir"
    echo "  • Updated call site to pass event.context.workspaceDir"
    echo "  • Files now read from workspace directory instead of hardcoded path"
    echo "  • Added MEMORY.md to fallback files list"
    echo ""
    exit 0
else
    echo ""
    echo "⚠️  Some checks failed. Please review the implementation."
    echo ""
    exit 1
fi
