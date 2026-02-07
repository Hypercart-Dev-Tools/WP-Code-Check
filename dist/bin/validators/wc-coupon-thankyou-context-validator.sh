#!/usr/bin/env bash
#
# WooCommerce Coupon Thank-You Context Validator
# Version: 2.0.0
#
# Validates that coupon operations are actually in thank-you/order-received context,
# not just in the same file as thank-you hooks.
#
# Usage: wc-coupon-thankyou-context-validator.sh <file> <line_number>
#
# Exit codes:
#   0 = Confirmed issue (coupon operation in thank-you context)
#   1 = False positive (coupon operation in different context or dead code)
#   2 = Needs manual review
#
# Validation logic:
#   1. Check if the hook registration is commented out (dead code)
#   2. Find the function containing the flagged line
#   3. Search backwards for the hook registration (add_action/add_filter)
#   4. Verify the hook is actually a thank-you hook, not checkout/cart hook

set -euo pipefail

FILE="$1"
LINE_NUMBER="$2"

# Validate inputs
if [ ! -f "$FILE" ]; then
  echo "ERROR: File not found: $FILE" >&2
  exit 2
fi

if ! [[ "$LINE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Invalid line number: $LINE_NUMBER" >&2
  exit 2
fi

# Get total lines in file
TOTAL_LINES=$(wc -l < "$FILE" | tr -d ' ')

# Step 1: Find the function containing this line
# Extract context around the line and search for function declaration
SEARCH_START=$((LINE_NUMBER - 100))
[ "$SEARCH_START" -lt 1 ] && SEARCH_START=1

# Get context and find function declaration
CONTEXT=$(sed -n "${SEARCH_START},${LINE_NUMBER}p" "$FILE" 2>/dev/null || true)

# Find the last function declaration before our line
FUNCTION_LINE=$(echo "$CONTEXT" | grep -nE '^\s*(public|private|protected)?\s*function\s+[a-zA-Z_]' | tail -1 || echo "")

if [ -z "$FUNCTION_LINE" ]; then
  # No function found - might be in global scope or anonymous function
  # Check for anonymous function in add_action/add_filter
  FUNCTION_LINE=$(echo "$CONTEXT" | grep -nE '(add_action|add_filter)\s*\([^)]*function\s*\(' | tail -1 || echo "")
fi

# Extract function name if possible
FUNCTION_NAME=""
if [ -n "$FUNCTION_LINE" ]; then
  FUNCTION_NAME=$(echo "$FUNCTION_LINE" | grep -oE 'function\s+([a-zA-Z_][a-zA-Z0-9_]*)' | awk '{print $2}' || echo "")
fi

# Step 2: Search for hook registration
# Look for add_action or add_filter that references this function
HOOK_LINE=""
HOOK_NAME=""

if [ -n "$FUNCTION_NAME" ]; then
  # Search the entire file for hook registration (more reliable than searching backwards)
  # Look for add_action/add_filter with this function name
  HOOK_LINE=$(grep -nE "(add_action|add_filter)\s*\([^)]*['\"]([a-z_]+)['\"][^)]*['\"]?${FUNCTION_NAME}['\"]?" "$FILE" | head -1 || true)

  if [ -n "$HOOK_LINE" ]; then
    # Extract the hook name from the matched line
    HOOK_NAME=$(echo "$HOOK_LINE" | grep -oE "['\"]([a-z_]+)['\"]" | head -1 | tr -d "'" | tr -d '"' || true)
  fi
fi

# Step 3: Check if hook registration is commented out (dead code)
if [ -n "$HOOK_LINE" ]; then
  # Get the actual line content
  HOOK_LINE_CONTENT=$(echo "$HOOK_LINE" | cut -d: -f2-)
  
  # Check if line starts with // or is inside /* */
  if echo "$HOOK_LINE_CONTENT" | grep -qE '^\s*(//|/\*)'; then
    # Hook is commented out - this is dead code
    exit 1
  fi
fi

# Step 4: Validate hook context
# Define problematic hooks (thank-you/order-received context)
PROBLEMATIC_HOOKS=(
  "woocommerce_thankyou"
  "woocommerce_order_received"
  "woocommerce_thankyou_"  # Catches woocommerce_thankyou_{payment_method}
)

# Define safe hooks (checkout/cart context)
SAFE_HOOKS=(
  "woocommerce_checkout_order_processed"
  "woocommerce_checkout_create_order"
  "woocommerce_new_order"
  "woocommerce_before_calculate_totals"
  "woocommerce_add_to_cart"
  "woocommerce_applied_coupon"
  "woocommerce_removed_coupon"
  "woocommerce_cart_calculate_fees"
)

# Check if hook is in safe list
for safe_hook in "${SAFE_HOOKS[@]}"; do
  if [[ "$HOOK_NAME" == *"$safe_hook"* ]]; then
    # This is a safe hook - false positive
    exit 1
  fi
done

# Check if hook is in problematic list
for problem_hook in "${PROBLEMATIC_HOOKS[@]}"; do
  if [[ "$HOOK_NAME" == *"$problem_hook"* ]]; then
    # Confirmed issue - coupon operation in thank-you context
    exit 0
  fi
done

# If we couldn't determine the hook context, needs manual review
exit 2

