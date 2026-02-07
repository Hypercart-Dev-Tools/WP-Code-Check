#!/usr/bin/env bash
#
# Regression Suite for P1-2026-02-06 Fix Audit
# - wc-coupon-in-thankyou validator integration in main scanner flow
# - cached_grep one-file path-with-spaces handling
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCANNER="$REPO_ROOT/dist/bin/check-performance.sh"
VALIDATOR_TEST="$REPO_ROOT/dist/bin/test-wc-coupon-validator.sh"
TMP_ROOT="/tmp/wpcc-fix-audit-$$"
PASSED=0
FAILED=0

cleanup() {
  rm -rf "$TMP_ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$TMP_ROOT"

pass() {
  echo "PASS: $1"
  ((PASSED++)) || true
}

fail() {
  echo "FAIL: $1"
  ((FAILED++)) || true
}

run_scan() {
  local scan_path="$1"
  local out_json="$2"
  "$SCANNER" --paths "$scan_path" --format json --no-log > "$out_json" 2>/dev/null || true
}

check_status_is() {
  local out_json="$1"
  local check_name="$2"
  local expected_status="$3"
  python3 - "$out_json" "$check_name" "$expected_status" <<'PY'
import json
import sys

path, name, expected = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
checks = [c for c in data.get("checks", []) if c.get("name") == name]
ok = any(c.get("status") == expected for c in checks)
sys.exit(0 if ok else 1)
PY
}

finding_count_eq() {
  local out_json="$1"
  local finding_id="$2"
  local expected="$3"
  python3 - "$out_json" "$finding_id" "$expected" <<'PY'
import json
import sys

path, finding_id, expected = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
count = sum(1 for x in data.get("findings", []) if x.get("id") == finding_id)
sys.exit(0 if count == expected else 1)
PY
}

finding_count_gte() {
  local out_json="$1"
  local finding_id="$2"
  local minimum="$3"
  python3 - "$out_json" "$finding_id" "$minimum" <<'PY'
import json
import sys

path, finding_id, minimum = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
count = sum(1 for x in data.get("findings", []) if x.get("id") == finding_id)
sys.exit(0 if count >= minimum else 1)
PY
}

echo "============================================================"
echo "P1 Fix Audit Regression Suite"
echo "============================================================"

if bash "$VALIDATOR_TEST" >/dev/null 2>&1; then
  pass "Validator unit suite"
else
  fail "Validator unit suite"
fi

# Test 1: Checkout hook should not be flagged by full scanner.
CHECKOUT_DIR="$TMP_ROOT/checkout"
mkdir -p "$CHECKOUT_DIR"
cp "$REPO_ROOT/dist/bin/fixtures/wc-coupon-thankyou-false-positive-checkout-hook.php" "$CHECKOUT_DIR/functions.php"
CHECKOUT_JSON="$TMP_ROOT/checkout.json"
run_scan "$CHECKOUT_DIR" "$CHECKOUT_JSON"

if check_status_is "$CHECKOUT_JSON" "WooCommerce coupon logic in thank-you context" "passed" && \
   finding_count_eq "$CHECKOUT_JSON" "wc-coupon-in-thankyou" 0; then
  pass "Checkout hook false positive suppressed in scanner flow"
else
  fail "Checkout hook false positive suppressed in scanner flow"
fi

# Test 2: Commented hook should not be flagged by full scanner.
COMMENTED_DIR="$TMP_ROOT/commented"
mkdir -p "$COMMENTED_DIR"
cp "$REPO_ROOT/dist/bin/fixtures/wc-coupon-thankyou-false-positive-commented-hook.php" "$COMMENTED_DIR/functions.php"
COMMENTED_JSON="$TMP_ROOT/commented.json"
run_scan "$COMMENTED_DIR" "$COMMENTED_JSON"

if check_status_is "$COMMENTED_JSON" "WooCommerce coupon logic in thank-you context" "passed" && \
   finding_count_eq "$COMMENTED_JSON" "wc-coupon-in-thankyou" 0; then
  pass "Commented hook false positive suppressed in scanner flow"
else
  fail "Commented hook false positive suppressed in scanner flow"
fi

# Test 3: True thank-you hook should still be flagged.
TRUE_DIR="$TMP_ROOT/true-positive"
mkdir -p "$TRUE_DIR"
cp "$REPO_ROOT/dist/bin/fixtures/wc-coupon-thankyou-true-positive.php" "$TRUE_DIR/functions.php"
TRUE_JSON="$TMP_ROOT/true-positive.json"
run_scan "$TRUE_DIR" "$TRUE_JSON"

if check_status_is "$TRUE_JSON" "WooCommerce coupon logic in thank-you context" "failed" && \
   finding_count_gte "$TRUE_JSON" "wc-coupon-in-thankyou" 1; then
  pass "Thank-you true positive retained in scanner flow"
else
  fail "Thank-you true positive retained in scanner flow"
fi

# Test 4: One-file path-with-spaces should detect unsanitized superglobal read.
SPACE_ONE_DIR="$TMP_ROOT/space one"
mkdir -p "$SPACE_ONE_DIR"
cat > "$SPACE_ONE_DIR/functions.php" <<'PHP'
<?php
add_action('wp_ajax_test_action', function() {
    $keyword = $_POST['keyword'];
    echo $keyword;
});
PHP
SPACE_ONE_JSON="$TMP_ROOT/space-one.json"
run_scan "$SPACE_ONE_DIR" "$SPACE_ONE_JSON"

if check_status_is "$SPACE_ONE_JSON" 'Unsanitized superglobal read ($_GET/$_POST)' "failed" && \
   finding_count_gte "$SPACE_ONE_JSON" "unsanitized-superglobal-read" 1; then
  pass "One-file path-with-spaces unsanitized detection"
else
  fail "One-file path-with-spaces unsanitized detection"
fi

# Test 5: Multi-file path-with-spaces should also detect.
SPACE_TWO_DIR="$TMP_ROOT/space two"
mkdir -p "$SPACE_TWO_DIR"
cat > "$SPACE_TWO_DIR/functions.php" <<'PHP'
<?php
add_action('wp_ajax_test_action', function() {
    $keyword = $_POST['keyword'];
    echo $keyword;
});
PHP
cat > "$SPACE_TWO_DIR/other.php" <<'PHP'
<?php
function noop() { return true; }
PHP
SPACE_TWO_JSON="$TMP_ROOT/space-two.json"
run_scan "$SPACE_TWO_DIR" "$SPACE_TWO_JSON"

if check_status_is "$SPACE_TWO_JSON" 'Unsanitized superglobal read ($_GET/$_POST)' "failed" && \
   finding_count_gte "$SPACE_TWO_JSON" "unsanitized-superglobal-read" 1; then
  pass "Multi-file path-with-spaces unsanitized detection"
else
  fail "Multi-file path-with-spaces unsanitized detection"
fi

echo "============================================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "============================================================"

if [ "$FAILED" -eq 0 ]; then
  exit 0
fi

exit 1
