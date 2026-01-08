# WooCommerce Coupon-in-Thank-You Pattern Implementation

**Created:** 2026-01-08  
**Status:** ✅ Completed  
**Shipped In:** v1.1.0  
**Pattern ID:** `wc-coupon-in-thankyou`

---

## 📋 Summary

Successfully created a new detection pattern for identifying coupon logic running in WooCommerce thank-you/order-received contexts. This is a reliability anti-pattern where coupon operations (apply/remove/validate) are performed after the order is already complete, which can cause data inconsistencies and unexpected side effects.

---

## 🎯 What Was Built

### 1. Pattern Definition
**File:** `dist/patterns/wc-coupon-in-thankyou.json`

- **Category:** Reliability
- **Severity:** HIGH
- **Detection Type:** Multi-step grep (heuristic)
- **Pattern Type:** PHP/WooCommerce

**Detection Strategy:**
1. **Step 1:** Find files with thank-you/order-received context markers
   - Hooks: `woocommerce_thankyou`, `*_woocommerce_thankyou`, `woocommerce_thankyou_*`
   - Conditionals: `is_order_received_page()`, `is_wc_endpoint_url('order-received')`
   - Templates: `woocommerce/checkout/thankyou.php`, `order-received.php`

2. **Step 2:** Search those files for coupon operations
   - `apply_coupon()`, `remove_coupon()`, `has_coupon()`
   - `new WC_Coupon()`, `wc_get_coupon()`
   - `get_used_coupons()`, `get_coupon_codes()`
   - Coupon validity filters and action hooks

**Metadata Included:**
- ✅ Full rationale and description
- ✅ Remediation examples (bad vs. good code)
- ✅ Appropriate hooks for coupon logic
- ✅ False positive scenarios documented
- ✅ References to WooCommerce documentation

---

### 2. Standalone Detection Script
**File:** `dist/bin/detect-wc-coupon-in-thankyou.sh`

**Features:**
- ✅ User-friendly output with progress indicators
- ✅ Automatic ripgrep detection with grep fallback
- ✅ Colored output and clear remediation guidance
- ✅ Exit codes (0 = clean, 1 = issues found)
- ✅ Excludes vendor, node_modules, tests automatically

**Usage:**
```bash
bash dist/bin/detect-wc-coupon-in-thankyou.sh [path]
```

---

### 3. Minimal Copy-Paste Snippet
**File:** `dist/bin/wc-coupon-thankyou-snippet.sh`

**Features:**
- ✅ Minimal, CI-ready bash script
- ✅ Direct copy-paste into CI pipelines
- ✅ Ripgrep-based with commented grep fallback
- ✅ No dependencies on project structure
- ✅ Clean output suitable for parsing

**Usage:**
```bash
bash wc-coupon-thankyou-snippet.sh
```

---

## 📊 Pattern Library Integration

**Status:** ✅ Auto-registered via pattern-library-manager.sh

**Updated Files:**
- `dist/PATTERN-LIBRARY.json` - Canonical registry (now 27 patterns)
- `dist/PATTERN-LIBRARY.md` - Human-readable documentation

**Pattern Counts:**
- **Total Patterns:** 27 (was 26)
- **PHP Patterns:** 16 (was 15)
- **HIGH Severity:** 9 (was 8)
- **Reliability Category:** 4 (was 3)

---

## 🔧 Technical Details

### Context Markers (Step 1)

**Hooks:**
```regex
(add_action|do_action|apply_filters|add_filter)\([[:space:]]*['"]([a-z_]*woocommerce_thankyou[a-z_]*)['"]
```

**Conditionals:**
```regex
is_order_received_page\(
is_wc_endpoint_url\([[:space:]]*['"]order-received['"]
```

**Templates:**
```regex
woocommerce/checkout/(thankyou|order-received)\.php
```

### Coupon Operations (Step 2)

**Method Calls:**
```regex
->apply_coupon\(
->remove_coupon\(
->has_coupon\(
->get_used_coupons\(
->get_coupon_codes\(
```

**Object Instantiation:**
```regex
new[[:space:]]+WC_Coupon\(
wc_get_coupon\(
```

**Filters/Actions:**
```regex
(add_filter|apply_filters)\([[:space:]]*['"]woocommerce_coupon_is_valid
(add_action|do_action)\([[:space:]]*['"]woocommerce_(applied|removed)_coupon
```

---

## 📝 Remediation Guidance

### ❌ Bad (Anti-Pattern)
```php
add_action('woocommerce_thankyou', function($order_id) {
  $order = wc_get_order($order_id);
  $order->apply_coupon('THANKYOU10'); // ❌ Applying coupon after order complete
});
```

### ✅ Good (Correct Approach)
```php
add_action('woocommerce_checkout_order_processed', function($order_id) {
  $order = wc_get_order($order_id);
  // Apply coupon logic during checkout, before order completion
});
```

### Appropriate Hooks
- `woocommerce_before_calculate_totals` - Dynamic coupon application based on cart
- `woocommerce_checkout_order_processed` - Post-checkout logic before thank-you page
- `woocommerce_add_to_cart` - Cart-level coupon logic
- `woocommerce_applied_coupon` - React to coupon application (not initiate on thank-you)

---

## ⚠️ False Positive Scenarios

The pattern may flag these acceptable use cases (manual review recommended):

1. **Read-Only Display:** Showing used coupons for order confirmation
2. **Marketing Messages:** Displaying "next order" coupon code (not applying it)
3. **Analytics/Logging:** Referencing coupon data without modification

---

## 📦 Files Modified

### Created
- ✅ `dist/patterns/wc-coupon-in-thankyou.json` (129 lines)
- ✅ `dist/bin/detect-wc-coupon-in-thankyou.sh` (193 lines)
- ✅ `dist/bin/wc-coupon-thankyou-snippet.sh` (90 lines)

### Updated
- ✅ `dist/bin/check-performance.sh` - Version bumped to 1.1.0
- ✅ `CHANGELOG.md` - Added v1.1.0 entry with full details
- ✅ `dist/PATTERN-LIBRARY.json` - Auto-updated with new pattern
- ✅ `dist/PATTERN-LIBRARY.md` - Auto-updated documentation

---

## ✅ Testing

**Pattern Validation:**
```bash
✅ JSON syntax validated (python3 -m json.tool)
✅ Pattern library manager executed successfully
✅ Pattern registered in canonical registry
✅ Standalone script executable permissions set
✅ Snippet script tested (gracefully handles missing ripgrep)
```

**Integration Status:**
- ✅ Pattern appears in PATTERN-LIBRARY.json
- ✅ Pattern appears in PATTERN-LIBRARY.md
- ✅ Version numbers updated consistently
- ✅ CHANGELOG entry complete

---

## 🎓 Lessons Learned

1. **Two-Step Detection Works Well:** Filtering by context first (step 1) then searching for operations (step 2) reduces false positives significantly
2. **Heuristic Pattern:** This is intentionally a heuristic pattern - some false positives expected for read-only display logic
3. **Comprehensive Metadata:** Including remediation examples and false positive scenarios helps users understand the pattern
4. **Multiple Delivery Formats:** Providing both a full-featured script and a minimal snippet serves different use cases

---

## 📚 References

- [WooCommerce Hooks Documentation](https://woocommerce.com/document/introduction-to-hooks-actions-and-filters/)
- [WooCommerce Code Reference](https://woocommerce.github.io/code-reference/hooks/hooks.html)
- [Checkout Flow and Events](https://developer.woocommerce.com/docs/cart-and-checkout-blocks/checkout-flow-and-events/)

---

**Completion Date:** 2026-01-08  
**Total Development Time:** ~30 minutes  
**Lines of Code Added:** ~412 lines (pattern + scripts + docs)

