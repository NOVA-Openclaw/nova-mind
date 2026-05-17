#!/bin/bash
# Test script for Issue #26: Git workflow enforcement
# This script validates all test cases defined in TEST-CASES-ISSUE-26.md

# Don't use set -e because we're testing for failures
set +e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test repo setup
TEST_REPO_DIR="/tmp/nova-test-repo-$$"
ORIGINAL_DIR="$(pwd)"

# Logging
log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

log_test() {
  echo -e "\n${YELLOW}━━━ TEST: $1 ━━━${NC}"
}

# Test result tracking
pass_test() {
  ((PASSED_TESTS++))
  log_success "$1"
}

fail_test() {
  ((FAILED_TESTS++))
  log_error "$1"
}

start_test() {
  ((TOTAL_TESTS++))
  log_test "$1"
}

# Setup test repository
setup_test_repo() {
  log_info "Setting up test repository..."
  
  # Remove old test repo if exists
  rm -rf "$TEST_REPO_DIR"
  
  # Create fresh test repo
  mkdir -p "$TEST_REPO_DIR"
  cd "$TEST_REPO_DIR"
  
  git init
  git config user.name "Test User"
  git config user.email "test@example.com"
  
  # Copy the pre-push hook
  cp "$ORIGINAL_DIR/.git/hooks/pre-push" .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  
  # Create initial commit on main
  echo "# Test Repo" > README.md
  git add README.md
  git commit -m "Initial commit"
  
  # Create a fake remote
  git remote add origin "https://github.com/test/test-repo.git"
  
  log_success "Test repository created at $TEST_REPO_DIR"
}

# Cleanup
cleanup() {
  cd "$ORIGINAL_DIR"
  rm -rf "$TEST_REPO_DIR"
  log_info "Cleaned up test repository"
}

# Test helper: attempt push and capture result
test_push() {
  local branch="$1"
  local agent_id="$2"
  local expected_result="$3" # "pass" or "fail"
  
  # Set agent ID
  if [[ -n "$agent_id" ]]; then
    export CLAWDBOT_AGENT_ID="$agent_id"
  else
    unset CLAWDBOT_AGENT_ID
  fi
  
  # Create and checkout branch if not exists
  if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
    git checkout -b "$branch" 2>/dev/null || git checkout "$branch"
    echo "Test content for $branch" >> test-file.txt
    git add test-file.txt
    git commit -m "Test commit on $branch" >/dev/null 2>&1 || true
  else
    git checkout "$branch" 2>/dev/null
  fi
  
  # Attempt push (dry-run to avoid actual remote push)
  local output
  local exit_code
  
  # Use pre-push hook directly since we don't have a real remote
  output=$(echo "refs/heads/$branch $(git rev-parse HEAD) refs/heads/$branch 0000000000000000000000000000000000000000" | .git/hooks/pre-push 2>&1)
  exit_code=$?
  
  # Check result
  if [[ "$expected_result" == "pass" ]]; then
    if [[ $exit_code -eq 0 ]]; then
      return 0
    else
      echo "Expected push to pass but it failed:"
      echo "$output"
      return 1
    fi
  else
    if [[ $exit_code -ne 0 ]]; then
      return 0
    else
      echo "Expected push to fail but it passed"
      return 1
    fi
  fi
}

# Test helper: test gh pr merge
test_gh_merge() {
  local agent_id="$1"
  local expected_result="$2" # "pass" or "fail"
  
  # Source the shell aliases
  source "$ORIGINAL_DIR/scripts/shell-aliases.sh"
  
  # Set agent ID
  if [[ -n "$agent_id" ]]; then
    export CLAWDBOT_AGENT_ID="$agent_id"
  else
    unset CLAWDBOT_AGENT_ID
  fi
  
  # Mock the gh command to avoid actual API calls
  # Create a temporary gh wrapper that just returns success
  local temp_gh="/tmp/gh-mock-$$"
  cat > "$temp_gh" << 'EOF'
#!/bin/bash
# Mock gh command for testing
exit 0
EOF
  chmod +x "$temp_gh"
  
  # Test gh pr merge with mocked command
  local output
  local exit_code
  
  # Temporarily override command
  command() {
    if [[ "$1" == "gh" ]]; then
      "$temp_gh" "${@:2}"
    else
      builtin command "$@"
    fi
  }
  export -f command
  
  output=$(gh pr merge 123 2>&1)
  exit_code=$?
  
  rm -f "$temp_gh"
  unset -f command
  
  # Check result
  if [[ "$expected_result" == "pass" ]]; then
    if [[ $exit_code -eq 0 ]]; then
      return 0
    else
      echo "Expected merge to pass but it failed:"
      echo "$output"
      return 1
    fi
  else
    if [[ $exit_code -ne 0 ]]; then
      return 0
    else
      echo "Expected merge to fail but it passed"
      return 1
    fi
  fi
}

# Run all tests
run_tests() {
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  NOVA Git Workflow Enforcement - Test Suite${NC}"
  echo -e "${BLUE}  Issue #26${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  
  setup_test_repo
  
  # TC-26-01: Coder can push feature branches
  start_test "TC-26-01: Coder can push feature branches"
  if test_push "feature/test-branch" "claude-code" "pass"; then
    pass_test "Coder (claude-code) successfully pushed to feature branch"
  else
    fail_test "Coder (claude-code) failed to push to feature branch"
  fi
  
  # TC-26-02: Gidget can push feature branches
  start_test "TC-26-02: Gidget can push feature branches"
  if test_push "feature/gidget-test" "git-agent" "pass"; then
    pass_test "Gidget (git-agent) successfully pushed to feature branch"
  else
    fail_test "Gidget (git-agent) failed to push to feature branch"
  fi
  
  # TC-26-03: NOVA main blocked from pushing
  start_test "TC-26-03: NOVA main blocked from pushing"
  if test_push "feature/nova-test" "" "fail"; then
    pass_test "NOVA main correctly blocked from pushing"
  else
    fail_test "NOVA main was not blocked from pushing"
  fi
  
  # TC-26-04: Newhart can push (requires changing USER)
  start_test "TC-26-04: Newhart can push"
  export USER="newhart"
  if test_push "feature/newhart-test" "" "pass"; then
    pass_test "User 'newhart' successfully pushed to feature branch"
  else
    fail_test "User 'newhart' failed to push to feature branch"
  fi
  export USER="$(whoami)" # Reset
  
  # TC-26-05: Block push to main (Coder)
  start_test "TC-26-05: Block push to main (Coder)"
  git checkout main 2>/dev/null
  echo "Changes" >> README.md
  git add README.md
  git commit -m "Test commit on main" >/dev/null 2>&1 || true
  if test_push "main" "claude-code" "fail"; then
    pass_test "Coder correctly blocked from pushing to main"
  else
    fail_test "Coder was not blocked from pushing to main"
  fi
  
  # TC-26-06: Block push to main (Gidget)
  start_test "TC-26-06: Block push to main (Gidget)"
  if test_push "main" "git-agent" "fail"; then
    pass_test "Gidget correctly blocked from pushing to main"
  else
    fail_test "Gidget was not blocked from pushing to main"
  fi
  
  # TC-26-07: Block push to master
  start_test "TC-26-07: Block push to master"
  git checkout -b master 2>/dev/null || git checkout master
  echo "Changes" >> README.md
  git add README.md
  git commit -m "Test commit on master" >/dev/null 2>&1 || true
  if test_push "master" "claude-code" "fail"; then
    pass_test "Push to master correctly blocked"
  else
    fail_test "Push to master was not blocked"
  fi
  
  # TC-26-08: Gidget can merge PRs
  start_test "TC-26-08: Gidget can merge PRs"
  cd "$ORIGINAL_DIR"
  if test_gh_merge "git-agent" "pass"; then
    pass_test "Gidget (git-agent) can merge PRs"
  else
    fail_test "Gidget (git-agent) cannot merge PRs"
  fi
  
  # TC-26-09: Coder blocked from merging PRs
  start_test "TC-26-09: Coder blocked from merging PRs"
  if test_gh_merge "claude-code" "fail"; then
    pass_test "Coder (claude-code) correctly blocked from merging PRs"
  else
    fail_test "Coder (claude-code) was not blocked from merging PRs"
  fi
  
  # TC-26-10: NOVA main blocked from merging PRs
  start_test "TC-26-10: NOVA main blocked from merging PRs"
  if test_gh_merge "" "fail"; then
    pass_test "NOVA main correctly blocked from merging PRs"
  else
    fail_test "NOVA main was not blocked from merging PRs"
  fi
  
  cleanup
  
  # Print summary
  echo -e "\n${BLUE}═══════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  Test Summary${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
  echo -e "Total tests:  $TOTAL_TESTS"
  echo -e "${GREEN}Passed:       $PASSED_TESTS${NC}"
  if [[ $FAILED_TESTS -gt 0 ]]; then
    echo -e "${RED}Failed:       $FAILED_TESTS${NC}"
    echo -e "\n${RED}❌ Some tests failed${NC}"
    exit 1
  else
    echo -e "\n${GREEN}✅ All tests passed!${NC}"
    exit 0
  fi
}

# Main execution
trap cleanup EXIT
run_tests
