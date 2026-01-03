#!/usr/bin/env bash
#
# Neochrome WP Toolkit - Fixture Validation Tests
# Version: 1.0.63
#
# Runs check-performance.sh against test fixtures and validates expected counts.
# This prevents regressions when modifying detection patterns.
#
# Usage:
#   ./tests/run-fixture-tests.sh
#
# Exit codes:
#   0 = All tests passed
#   1 = One or more tests failed
#

# Note: Do NOT use set -e here - we need to capture output from failing checks

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory (tests folder) and change to dist root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$(dirname "$SCRIPT_DIR")"

# Change to dist directory so we can use relative paths
# (check-performance.sh has issues with absolute paths containing spaces)
cd "$DIST_DIR"

BIN_DIR="./bin"
FIXTURES_DIR="./tests/fixtures"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================
# Expected Counts (update when adding new patterns/fixtures)
# ============================================================

# antipatterns.php - Should detect all intentional antipatterns
ANTIPATTERNS_EXPECTED_ERRORS=6
# Warning count differs between macOS (5) and Linux (3) due to grep/sed
# behavior with UTF-8 content. Accept range 3-5.
ANTIPATTERNS_EXPECTED_WARNINGS_MIN=3
ANTIPATTERNS_EXPECTED_WARNINGS_MAX=5

# clean-code.php - Should pass with minimal warnings
# Note: 1 warning expected due to N+1 heuristic (foreach + get_post_meta in same file)
CLEAN_CODE_EXPECTED_ERRORS=0
CLEAN_CODE_EXPECTED_WARNINGS_MIN=1
CLEAN_CODE_EXPECTED_WARNINGS_MAX=1

# ajax-antipatterns.php - REST/AJAX regressions
# Note: v1.0.46 added HTTP timeout check, which catches wp_remote_get without timeout
AJAX_PHP_EXPECTED_ERRORS=1
AJAX_PHP_EXPECTED_WARNINGS_MIN=1
AJAX_PHP_EXPECTED_WARNINGS_MAX=1

# ajax-antipatterns.js - Unbounded polling regressions
AJAX_JS_EXPECTED_ERRORS=1
AJAX_JS_EXPECTED_WARNINGS_MIN=0
AJAX_JS_EXPECTED_WARNINGS_MAX=0

# ajax-safe.php - Safe AJAX patterns (should not trigger errors)
AJAX_SAFE_EXPECTED_ERRORS=0
AJAX_SAFE_EXPECTED_WARNINGS_MIN=0
AJAX_SAFE_EXPECTED_WARNINGS_MAX=0

# file-get-contents-url.php - file_get_contents() with URLs (v1.0.46)
FILE_GET_CONTENTS_EXPECTED_ERRORS=4  # 2 direct URLs + 2 URL variables
FILE_GET_CONTENTS_EXPECTED_WARNINGS_MIN=0
FILE_GET_CONTENTS_EXPECTED_WARNINGS_MAX=0

# http-no-timeout.php - HTTP requests without timeout (v1.0.46)
HTTP_NO_TIMEOUT_EXPECTED_ERRORS=0
HTTP_NO_TIMEOUT_EXPECTED_WARNINGS_MIN=4  # 4 wp_remote_* calls without timeout
HTTP_NO_TIMEOUT_EXPECTED_WARNINGS_MAX=4

# cron-interval-validation.php - Unvalidated cron intervals (v1.0.47)
CRON_INTERVAL_EXPECTED_ERRORS=1  # 1 error with 3 findings (lines 15, 24, 33)
CRON_INTERVAL_EXPECTED_WARNINGS_MIN=0
CRON_INTERVAL_EXPECTED_WARNINGS_MAX=0

# ============================================================
# Helper Functions
# ============================================================

echo_header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

run_test() {
  local fixture_file="$1"
  local expected_errors="$2"
  local expected_warnings_min="$3"
  local expected_warnings_max="$4"
  local test_name="$(basename "$fixture_file")"

  TESTS_RUN=$((TESTS_RUN + 1))

  echo ""
  echo -e "${YELLOW}▸ Testing: $test_name${NC}"
  if [ "$expected_warnings_min" -eq "$expected_warnings_max" ]; then
    echo "  Expected: $expected_errors errors, $expected_warnings_min warnings"
  else
    echo "  Expected: $expected_errors errors, $expected_warnings_min-$expected_warnings_max warnings"
  fi

  # Run the check and capture output to temp file (more reliable than subshell)
  local tmp_output
  tmp_output=$(mktemp)

  # Debug: Show command being run
  echo -e "  ${BLUE}[DEBUG] Running: $BIN_DIR/check-performance.sh --paths \"$fixture_file\" --no-log${NC}"

  "$BIN_DIR/check-performance.sh" --paths "$fixture_file" --no-log > "$tmp_output" 2>&1 || true

  # Strip ANSI color codes for parsing (using perl for reliability)
  local clean_output
  clean_output=$(perl -pe 's/\e\[[0-9;]*m//g' < "$tmp_output")

  # Debug: Show last 20 lines of output (the summary section)
  echo -e "  ${BLUE}[DEBUG] Raw output (last 20 lines):${NC}"
  tail -20 "$tmp_output" | perl -pe 's/\e\[[0-9;]*m//g' | sed 's/^/    /'
  echo ""

  # Extract counts from summary (format: "  Errors:   6")
  local actual_errors
  local actual_warnings
  actual_errors=$(echo "$clean_output" | grep -E "^[[:space:]]*Errors:" | grep -oE '[0-9]+' | head -1)
  actual_warnings=$(echo "$clean_output" | grep -E "^[[:space:]]*Warnings:" | grep -oE '[0-9]+' | head -1)

  # Default to 0 if not found
  actual_errors=${actual_errors:-0}
  actual_warnings=${actual_warnings:-0}

  # Debug: Show parsed values
  echo -e "  ${BLUE}[DEBUG] Parsed errors: '$actual_errors', warnings: '$actual_warnings'${NC}"

  # Clean up temp file
  rm -f "$tmp_output"

  echo "  Actual:   $actual_errors errors, $actual_warnings warnings"

  # Validate errors exactly, warnings within range
  local errors_ok=false
  local warnings_ok=false

  [ "$actual_errors" -eq "$expected_errors" ] && errors_ok=true
  [ "$actual_warnings" -ge "$expected_warnings_min" ] && [ "$actual_warnings" -le "$expected_warnings_max" ] && warnings_ok=true

  if [ "$errors_ok" = true ] && [ "$warnings_ok" = true ]; then
    echo -e "  ${GREEN}✓ PASSED${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo -e "  ${RED}✗ FAILED${NC}"
    if [ "$errors_ok" = false ]; then
      echo -e "    ${RED}Errors: expected $expected_errors, got $actual_errors${NC}"
    fi
    if [ "$warnings_ok" = false ]; then
      echo -e "    ${RED}Warnings: expected $expected_warnings_min-$expected_warnings_max, got $actual_warnings${NC}"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

# ============================================================
# Main
# ============================================================

echo_header "Neochrome WP Toolkit - Fixture Validation"
echo "Testing detection patterns against known fixtures..."

# Debug: Show environment
echo ""
echo -e "${BLUE}[DEBUG] Environment:${NC}"
echo "  SCRIPT_DIR: $SCRIPT_DIR"
echo "  DIST_DIR:   $DIST_DIR"
echo "  PWD:        $(pwd)"
echo "  BIN_DIR:    $BIN_DIR"
echo "  FIXTURES:   $FIXTURES_DIR"
echo ""

# Debug: List files to confirm paths
echo -e "${BLUE}[DEBUG] Files present:${NC}"
ls -la "$FIXTURES_DIR/" 2>&1 || echo "  ERROR: Cannot list fixtures"
ls -la "$BIN_DIR/check-performance.sh" 2>&1 || echo "  ERROR: Cannot find check script"
echo ""

# Verify fixtures exist
if [ ! -f "$FIXTURES_DIR/antipatterns.php" ]; then
  echo -e "${RED}Error: antipatterns.php fixture not found${NC}"
  exit 1
fi

if [ ! -f "$FIXTURES_DIR/clean-code.php" ]; then
  echo -e "${RED}Error: clean-code.php fixture not found${NC}"
  exit 1
fi

# Verify new AJAX fixtures
if [ ! -f "$FIXTURES_DIR/ajax-antipatterns.php" ]; then
  echo -e "${RED}Error: ajax-antipatterns.php fixture not found${NC}"
  exit 1
fi

if [ ! -f "$FIXTURES_DIR/ajax-antipatterns.js" ]; then
  echo -e "${RED}Error: ajax-antipatterns.js fixture not found${NC}"
  exit 1
fi

	if [ ! -f "$FIXTURES_DIR/ajax-safe.php" ]; then
	  echo -e "${RED}Error: ajax-safe.php fixture not found${NC}"
	  exit 1
	fi

# Run tests (passing: errors, warnings_min, warnings_max)
	run_test "$FIXTURES_DIR/antipatterns.php" "$ANTIPATTERNS_EXPECTED_ERRORS" "$ANTIPATTERNS_EXPECTED_WARNINGS_MIN" "$ANTIPATTERNS_EXPECTED_WARNINGS_MAX" || true
	run_test "$FIXTURES_DIR/clean-code.php" "$CLEAN_CODE_EXPECTED_ERRORS" "$CLEAN_CODE_EXPECTED_WARNINGS_MIN" "$CLEAN_CODE_EXPECTED_WARNINGS_MAX" || true
	run_test "$FIXTURES_DIR/ajax-antipatterns.php" "$AJAX_PHP_EXPECTED_ERRORS" "$AJAX_PHP_EXPECTED_WARNINGS_MIN" "$AJAX_PHP_EXPECTED_WARNINGS_MAX" || true
	run_test "$FIXTURES_DIR/ajax-antipatterns.js" "$AJAX_JS_EXPECTED_ERRORS" "$AJAX_JS_EXPECTED_WARNINGS_MIN" "$AJAX_JS_EXPECTED_WARNINGS_MAX" || true
	run_test "$FIXTURES_DIR/ajax-safe.php" "$AJAX_SAFE_EXPECTED_ERRORS" "$AJAX_SAFE_EXPECTED_WARNINGS_MIN" "$AJAX_SAFE_EXPECTED_WARNINGS_MAX" || true

# ============================================================
# JSON Output Format Test
# ============================================================

echo ""
echo -e "${BLUE}▸ Testing: JSON output format${NC}"
((TESTS_RUN++))

# Run with JSON format and validate with shell parsing (no jq dependency)
JSON_OUTPUT=$("$BIN_DIR/check-performance.sh" --format json --paths "$FIXTURES_DIR/antipatterns.php" --no-log 2>&1)

# Check if output starts with {
if [[ "$JSON_OUTPUT" == "{"* ]]; then
  # Basic JSON structure validation
  if echo "$JSON_OUTPUT" | grep -q '"version"' && \
     echo "$JSON_OUTPUT" | grep -q '"summary"' && \
     echo "$JSON_OUTPUT" | grep -q '"findings"' && \
     echo "$JSON_OUTPUT" | grep -q '"checks"'; then
    # Validate error count in JSON matches expected
    JSON_ERRORS=$(echo "$JSON_OUTPUT" | grep -o '"total_errors":[[:space:]]*[0-9]*' | grep -o '[0-9]*')
    if [ "$JSON_ERRORS" = "$ANTIPATTERNS_EXPECTED_ERRORS" ]; then
      echo -e "  ${GREEN}✓ PASSED${NC} - JSON is valid and error count matches ($JSON_ERRORS)"
      ((TESTS_PASSED++))
    else
      echo -e "  ${RED}✗ FAILED${NC} - JSON error count mismatch (expected: $ANTIPATTERNS_EXPECTED_ERRORS, got: $JSON_ERRORS)"
      ((TESTS_FAILED++))
    fi
  else
    echo -e "  ${RED}✗ FAILED${NC} - JSON missing required fields (version, summary, findings, checks)"
    ((TESTS_FAILED++))
  fi
else
  echo -e "  ${RED}✗ FAILED${NC} - Output is not valid JSON (doesn't start with {)"
  echo "  Output preview: ${JSON_OUTPUT:0:100}..."
  ((TESTS_FAILED++))
fi

# ============================================================
# Baseline JSON Behavior Test
# ============================================================

echo ""
echo -e "${BLUE}▸ Testing: JSON baseline behavior${NC}"
((TESTS_RUN++))

BASELINE_FILE="$FIXTURES_DIR/.hcc-baseline"
JSON_BASELINE_OUTPUT=$("$BIN_DIR/check-performance.sh" --format json --paths "$FIXTURES_DIR/antipatterns.php" --baseline "$BASELINE_FILE" --no-log 2>&1)

if [[ "$JSON_BASELINE_OUTPUT" == "{"* ]]; then
  JSON_BASELINED=$(echo "$JSON_BASELINE_OUTPUT" | grep -o '"baselined":[[:space:]]*[0-9]*' | grep -o '[0-9]*')
  JSON_STALE=$(echo "$JSON_BASELINE_OUTPUT" | grep -o '"stale_baseline":[[:space:]]*[0-9]*' | grep -o '[0-9]*')

  JSON_BASELINED=${JSON_BASELINED:-0}
  JSON_STALE=${JSON_STALE:-0}

  if [ "$JSON_BASELINED" -gt 0 ] && [ "$JSON_STALE" -gt 0 ]; then
    echo -e "  ${GREEN}✓ PASSED${NC} - baseline applied (baselined=$JSON_BASELINED, stale_baseline=$JSON_STALE)"
    ((TESTS_PASSED++))
  else
    echo -e "  ${RED}✗ FAILED${NC} - baseline metrics not as expected (baselined=$JSON_BASELINED, stale_baseline=$JSON_STALE)"
    ((TESTS_FAILED++))
  fi
else
  echo -e "  ${RED}✗ FAILED${NC} - Baseline JSON output is not valid JSON (doesn't start with {)"
  echo "  Output preview: ${JSON_BASELINE_OUTPUT:0:100}..."
  ((TESTS_FAILED++))
fi

# Test 6: file-get-contents-url.php (v1.0.46)
echo_header "Test 6: file-get-contents-url.php"
run_test "$FIXTURES_DIR/file-get-contents-url.php" \
  "$FILE_GET_CONTENTS_EXPECTED_ERRORS" \
  "$FILE_GET_CONTENTS_EXPECTED_WARNINGS_MIN" \
  "$FILE_GET_CONTENTS_EXPECTED_WARNINGS_MAX"

# Test 7: http-no-timeout.php (v1.0.46)
echo_header "Test 7: http-no-timeout.php"
run_test "$FIXTURES_DIR/http-no-timeout.php" \
  "$HTTP_NO_TIMEOUT_EXPECTED_ERRORS" \
  "$HTTP_NO_TIMEOUT_EXPECTED_WARNINGS_MIN" \
  "$HTTP_NO_TIMEOUT_EXPECTED_WARNINGS_MAX"

# Test 8: cron-interval-validation.php (v1.0.47)
echo_header "Test 8: cron-interval-validation.php"
run_test "$FIXTURES_DIR/cron-interval-validation.php" \
  "$CRON_INTERVAL_EXPECTED_ERRORS" \
  "$CRON_INTERVAL_EXPECTED_WARNINGS_MIN" \
  "$CRON_INTERVAL_EXPECTED_WARNINGS_MAX"

# Summary
echo_header "Test Summary"
echo ""
echo -e "  Tests Run:    $TESTS_RUN"
echo -e "  ${GREEN}Passed:       $TESTS_PASSED${NC}"
echo -e "  ${RED}Failed:       $TESTS_FAILED${NC}"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo -e "${GREEN}✓ All fixture tests passed!${NC}"
  echo ""
  exit 0
else
  echo -e "${RED}✗ $TESTS_FAILED test(s) failed${NC}"
  echo ""
  echo "If you intentionally added/removed patterns, update the expected counts in:"
  echo "  $SCRIPT_DIR/run-fixture-tests.sh"
  echo ""
  exit 1
fi
