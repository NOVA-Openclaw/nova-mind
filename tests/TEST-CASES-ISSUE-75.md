# Test Cases: Issue #75 - Test Script Tracking Pass/Fail

**Issue:** nova-memory#75  
**Bug:** Test script reports "All passed" despite failures  
**File:** tests/test-issue-70.sh  
**Date:** 2026-02-13

---

## Problem

The test script `test-issue-70.sh` has functions to print test results (`print_pass` and `print_fail`) but does not:
1. Track the number of tests that pass vs fail
2. Exit with non-zero status when tests fail
3. Provide accurate summary of results

This means the script will always report success even when tests fail.

---

## Test Case 1: Track Pass/Fail Counts

**ID:** TC-75-001  
**Priority:** Critical

**Given:** 
- Test script runs multiple test cases
- Some tests pass, some tests fail

**When:** 
- Script completes execution

**Then:**
- Pass count accurately reflects number of passing tests
- Fail count accurately reflects number of failing tests
- Summary displays correct totals

**Example:**
```
========================================
Test Results Summary
========================================
Total tests: 10
Passed: 7
Failed: 3
```

---

## Test Case 2: Exit Code on Failure

**ID:** TC-75-002  
**Priority:** Critical

**Given:**
- Test script runs with at least one test failure

**When:**
- Script completes

**Then:**
- Exit code is non-zero (typically 1)
- CI/CD systems can detect the failure
- "All tests passed!" message is NOT displayed

---

## Test Case 3: Exit Code on Success

**ID:** TC-75-003  
**Priority:** High

**Given:**
- Test script runs with all tests passing

**When:**
- Script completes

**Then:**
- Exit code is 0
- Success message is displayed
- Summary shows all tests passed

---

## Test Case 4: Individual Test Failures Reported

**ID:** TC-75-004  
**Priority:** High

**Given:**
- Multiple tests run
- Test #3 fails

**When:**
- Script continues to run remaining tests

**Then:**
- Test #3 failure is clearly displayed with red ✗
- Subsequent tests continue to run
- Final summary includes count of which tests failed

---

## Implementation Requirements

### Variables to Track
```bash
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
```

### Modified print_pass Function
```bash
function print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}
```

### Modified print_fail Function
```bash
function print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}
```

### End of Script
```bash
echo ""
echo "=========================================="
echo "Test Results Summary"
echo "=========================================="
echo "Total tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}✗ TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    exit 0
fi
```

---

## Acceptance Criteria

- [ ] Pass/fail counts are accurately tracked
- [ ] Summary matches actual test results
- [ ] Exit code is non-zero when any test fails
- [ ] Exit code is zero only when all tests pass
- [ ] Individual test failures are clearly visible
- [ ] Script can be used in CI/CD pipelines reliably
