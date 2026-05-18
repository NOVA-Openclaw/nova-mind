#!/bin/bash
# Test script for Issue #22: OPENCLAW_WORKSPACE environment variable support

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_ALIASES="$SCRIPT_DIR/../scripts/shell-aliases.sh"
TEST_RESULTS=()
PASSED=0
FAILED=0

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "Testing Issue #22: OPENCLAW_WORKSPACE"
echo "========================================"
echo ""

# Helper function to test sourcing the script
test_source() {
  local test_name="$1"
  local setup_cmd="$2"
  local expected_workspace="$3"
  
  echo "Testing: $test_name"
  
  # Run in subshell to avoid polluting current environment
  (
    eval "$setup_cmd"
    source "$SHELL_ALIASES"
    
    # Check if OPENCLAW_WORKSPACE is set correctly
    if [ "$OPENCLAW_WORKSPACE" == "$expected_workspace" ]; then
      echo -e "${GREEN}✓ PASS${NC}: OPENCLAW_WORKSPACE='$OPENCLAW_WORKSPACE'"
      exit 0
    else
      echo -e "${RED}✗ FAIL${NC}: Expected '$expected_workspace', got '$OPENCLAW_WORKSPACE'"
      exit 1
    fi
  )
  
  if [ $? -eq 0 ]; then
    ((PASSED++))
  else
    ((FAILED++))
  fi
  echo ""
}

# Test 1: Default Workspace
test_source \
  "Test 1: Default Workspace" \
  "unset OPENCLAW_WORKSPACE" \
  "$HOME/workspace"

# Test 2: Custom Workspace
test_source \
  "Test 2: Custom Workspace" \
  "export OPENCLAW_WORKSPACE='/tmp/my_workspace'" \
  "/tmp/my_workspace"

# Test 3: Workspace with Spaces
test_source \
  "Test 3: Workspace with Spaces" \
  "export OPENCLAW_WORKSPACE='/tmp/my workspace'" \
  "/tmp/my workspace"

# Test 4: Invalid Workspace (non-existent directory)
# For this test, we just verify the variable is set - the script doesn't validate existence
test_source \
  "Test 4: Invalid Workspace" \
  "export OPENCLAW_WORKSPACE='/tmp/nonexistent_dir_12345'" \
  "/tmp/nonexistent_dir_12345"

# Test 5: Empty Workspace
# Empty string should fall back to default
test_source \
  "Test 5: Empty Workspace" \
  "export OPENCLAW_WORKSPACE=''" \
  "$HOME/workspace"

# Test 6: Subsequent sourcing with different values
echo "Testing: Test 6: Subsequent Sourcing"
(
  export OPENCLAW_WORKSPACE="/tmp/workspace1"
  source "$SHELL_ALIASES"
  FIRST_VALUE="$OPENCLAW_WORKSPACE"
  
  export OPENCLAW_WORKSPACE="/tmp/workspace2"
  source "$SHELL_ALIASES"
  SECOND_VALUE="$OPENCLAW_WORKSPACE"
  
  if [ "$FIRST_VALUE" == "/tmp/workspace1" ] && [ "$SECOND_VALUE" == "/tmp/workspace2" ]; then
    echo -e "${GREEN}✓ PASS${NC}: Workspace updated from '$FIRST_VALUE' to '$SECOND_VALUE'"
    exit 0
  else
    echo -e "${RED}✗ FAIL${NC}: Expected workspace to change from '/tmp/workspace1' to '/tmp/workspace2'"
    echo "  First: $FIRST_VALUE"
    echo "  Second: $SECOND_VALUE"
    exit 1
  fi
)

if [ $? -eq 0 ]; then
  ((PASSED++))
else
  ((FAILED++))
fi
echo ""

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Total Tests: $((PASSED + FAILED))"
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
  echo -e "${RED}Failed: $FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
