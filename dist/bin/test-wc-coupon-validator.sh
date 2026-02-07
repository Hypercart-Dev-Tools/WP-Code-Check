#!/usr/bin/env bash
#
# Test Suite for WC Coupon Thank-You Context Validator
#

set -uo pipefail  # Removed -e so tests can fail without exiting script

VALIDATOR="dist/bin/validators/wc-coupon-thankyou-context-validator.sh"
PASSED=0
FAILED=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WC Coupon Thank-You Context Validator - Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Test 1: False Positive - Checkout Hook
echo "Test 1: False Positive - Checkout Hook (woocommerce_checkout_order_processed)"
$VALIDATOR dist/bin/fixtures/wc-coupon-thankyou-false-positive-checkout-hook.php 13
EXIT_CODE=$?
if [ $EXIT_CODE -eq 1 ]; then
  echo "✅ PASS: Correctly identified as false positive"
  ((PASSED++))
elif [ $EXIT_CODE -eq 0 ]; then
  echo "❌ FAIL: Incorrectly flagged as issue"
  ((FAILED++))
else
  echo "⚠️  REVIEW: Needs manual review (exit code $EXIT_CODE)"
  ((FAILED++))
fi
echo ""

# Test 2: False Positive - Commented Hook
echo "Test 2: False Positive - Commented Out Hook (dead code)"
$VALIDATOR dist/bin/fixtures/wc-coupon-thankyou-false-positive-commented-hook.php 15
EXIT_CODE=$?
if [ $EXIT_CODE -eq 1 ]; then
  echo "✅ PASS: Correctly identified as false positive (dead code)"
  ((PASSED++))
elif [ $EXIT_CODE -eq 0 ]; then
  echo "❌ FAIL: Incorrectly flagged dead code as issue"
  ((FAILED++))
else
  echo "⚠️  REVIEW: Needs manual review (exit code $EXIT_CODE)"
  ((FAILED++))
fi
echo ""

# Test 3: True Positive - Thank-You Hook
echo "Test 3: True Positive - Thank-You Hook (woocommerce_thankyou)"
$VALIDATOR dist/bin/fixtures/wc-coupon-thankyou-true-positive.php 14
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ PASS: Correctly identified as issue"
  ((PASSED++))
elif [ $EXIT_CODE -eq 1 ]; then
  echo "❌ FAIL: Incorrectly marked as false positive"
  ((FAILED++))
else
  echo "⚠️  REVIEW: Needs manual review (exit code $EXIT_CODE)"
  ((FAILED++))
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Results: $PASSED passed, $FAILED failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAILED -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi

