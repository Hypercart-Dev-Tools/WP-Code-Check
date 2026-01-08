# HOWTO: WooCommerce Coupon Performance Detection

> **Version:** 1.1.1  
> **Last Updated:** 2026-01-08

This guide covers detecting and fixing WooCommerce coupon-related performance issues, particularly on thank-you/order-received pages.

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Pattern Overview](#pattern-overview)
3. [Common Issues](#common-issues)
4. [Detection Scripts](#detection-scripts)
5. [Remediation Guide](#remediation-guide)
6. [Performance Optimization](#performance-optimization)

---

## Quick Start

### Scan for Coupon Performance Issues

```bash
# Scan for custom coupon logic in thank-you context
./dist/bin/detect-wc-coupon-in-thankyou.sh /path/to/wp-content

# Scan for Smart Coupons plugin performance issues
./dist/bin/detect-wc-smart-coupons-perf.sh /path/to/wp-content

# Run both checks
./dist/bin/detect-wc-coupon-in-thankyou.sh /path/to/wp-content
./dist/bin/detect-wc-smart-coupons-perf.sh /path/to/wp-content
```

---

## Pattern Overview

### Pattern 1: `wc-coupon-in-thankyou`

**What it detects:** Custom coupon logic in theme/plugin code running on thank-you page

**Severity:** HIGH (Reliability)

**Detects:**
- `apply_coupon()`, `remove_coupon()`, `has_coupon()` calls
- `new WC_Coupon()`, `wc_get_coupon()` instantiation
- `wc_get_coupon_id_by_code()` lookups
- `get_used_coupons()`, `get_coupon_codes()` retrieval
- Coupon validity filters in post-purchase context

**Why it's a problem:**
- Order is already complete - coupon changes cause data inconsistencies
- Logic should run during cart/checkout, not after payment
- Can cause unexpected side effects on completed orders

### Pattern 2: `wc-smart-coupons-thankyou-perf`

**What it detects:** WooCommerce Smart Coupons plugin with potential performance issues

**Severity:** HIGH (Performance)

**Detects:**
- Smart Coupons plugin presence
- `wc_get_coupon_id_by_code()` calls (triggers slow query)
- Thank-you page hooks in Smart Coupons code

**Why it's a problem:**
- Triggers `LOWER(post_title)` query that scans 300k+ rows
- Causes 15-30 second page load times
- Cannot use database indexes due to LOWER() function
- Blocks page rendering, looks like payment failed to customers

---

## Common Issues

### Issue 1: Custom Coupon Logic on Thank-You Page

**Symptom:** Coupon operations in theme's `thankyou.php` or hooked to `woocommerce_thankyou`

**Example (BAD):**
```php
add_action('woocommerce_thankyou', function($order_id) {
  $order = wc_get_order($order_id);
  $order->apply_coupon('THANKYOU10'); // ❌ Too late!
});
```

**Fix:** Move to checkout hook
```php
add_action('woocommerce_checkout_order_processed', function($order_id) {
  $order = wc_get_order($order_id);
  // Apply coupon logic during checkout, before order completion
});
```

**Detected by:** `wc-coupon-in-thankyou` pattern

---

### Issue 2: Smart Coupons Slow Database Queries

**Symptom:** Thank-you page takes 15-30 seconds to load

**Root Cause:**
```sql
SELECT ID FROM wp_posts 
WHERE LOWER(post_title) = LOWER('COUPONCODE') 
AND post_type = 'shop_coupon' 
AND post_status = 'publish'
ORDER BY post_date DESC
```

**Fix 1: Add Database Index (Immediate)**
```sql
ALTER TABLE wp_posts 
ADD INDEX idx_coupon_lookup (post_title(50), post_type, post_status);
```

**Expected improvement:** 15-30s → <100ms

**Fix 2: Implement Caching**
```php
function get_cached_coupon_id($code) {
  $cache_key = 'coupon_id_' . md5($code);
  $coupon_id = get_transient($cache_key);
  
  if (false === $coupon_id) {
    $coupon_id = wc_get_coupon_id_by_code($code);
    set_transient($cache_key, $coupon_id, 15 * MINUTE_IN_SECONDS);
  }
  
  return $coupon_id;
}
```

**Detected by:** `wc-smart-coupons-thankyou-perf` pattern

---

### Issue 3: Theme Code Calling `wc_get_coupon_id_by_code()`

**Symptom:** Custom theme code looks up coupons by code on thank-you page

**Example (BAD):**
```php
// In thankyou.php template
$coupon_id = wc_get_coupon_id_by_code('WELCOME'); // ❌ Slow query
$coupon = new WC_Coupon($coupon_id);
echo $coupon->get_amount();
```

**Fix:** Cache the lookup or use coupon ID directly
```php
// Store coupon ID in theme options/constants
define('WELCOME_COUPON_ID', 12345);
$coupon = new WC_Coupon(WELCOME_COUPON_ID); // ✅ Fast
echo $coupon->get_amount();
```

**Detected by:** Both patterns (`wc-coupon-in-thankyou` + `wc-smart-coupons-thankyou-perf`)

---

## Detection Scripts

### Script 1: `detect-wc-coupon-in-thankyou.sh`

**Purpose:** Find custom coupon logic in thank-you context

**Usage:**
```bash
bash dist/bin/detect-wc-coupon-in-thankyou.sh /path/to/scan
```

**Exit Codes:**
- `0` - No issues found
- `1` - Coupon logic detected in thank-you context

**Output Example:**
```
🔍 WooCommerce Coupon-in-Thank-You Detector
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Step 1: Finding files with thank-you/order-received context...
✓ Found 3 file(s) with thank-you/order-received context.

# Step 2: Searching for coupon operations in those files...

functions.php:996:	$coupons = $order->get_coupon_codes();
functions.php:1000:	$coupon = new WC_Coupon($coupon_code);

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  Issues detected - coupon logic found in thank-you/order-received context

📋 Remediation:
   Move coupon operations to appropriate cart/checkout hooks:
   - woocommerce_before_calculate_totals
   - woocommerce_checkout_order_processed
   - woocommerce_add_to_cart
```

---

### Script 2: `detect-wc-smart-coupons-perf.sh`

**Purpose:** Detect Smart Coupons plugin and performance risks

**Usage:**
```bash
bash dist/bin/detect-wc-smart-coupons-perf.sh /path/to/scan
```

**Exit Codes:**
- `0` - No issues or medium risk
- `1` - High risk detected

**Output Example:**
```
🔍 WooCommerce Smart Coupons Performance Detector
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Step 1: Detecting WooCommerce Smart Coupons plugin...
⚠️  Found WooCommerce Smart Coupons plugin (2 file(s))

# Step 2: Checking for thank-you page hooks and coupon lookups...

class-wc-smart-coupons.php:554:	$coupon_id = wc_get_coupon_id_by_code( $coupon_code );

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  HIGH RISK: Smart Coupons uses thank-you hooks or coupon lookups

📊 Performance Impact:
   • Typical delay: 15-30 seconds per thank-you page load
   • Cause: LOWER(post_title) query scans entire wp_posts table
   • Affected: Thank-you page, order received page

🔧 Immediate Fix (Database Index):
   Run this SQL query to add an optimized index:

   ALTER TABLE wp_posts ADD INDEX idx_coupon_lookup (post_title(50), post_type, post_status);

   Expected improvement: 15-30s → <100ms
```

---

## Remediation Guide

### Step 1: Identify the Issue

Run both detection scripts to understand what's causing the problem:

```bash
# Check for custom code issues
./dist/bin/detect-wc-coupon-in-thankyou.sh /path/to/wp-content/themes

# Check for Smart Coupons issues
./dist/bin/detect-wc-smart-coupons-perf.sh /path/to/wp-content/plugins
```

### Step 2: Apply Immediate Fixes

**For Smart Coupons Performance:**
```sql
-- Add database index (run in phpMyAdmin or WP-CLI)
ALTER TABLE wp_posts 
ADD INDEX idx_coupon_lookup (post_title(50), post_type, post_status);
```

**Verify index was created:**
```sql
SHOW INDEX FROM wp_posts WHERE Key_name = 'idx_coupon_lookup';
```

### Step 3: Move Custom Coupon Logic

**Find the problematic code** (from detection script output)

**Move to appropriate hook:**
- Cart operations → `woocommerce_before_calculate_totals`
- Checkout logic → `woocommerce_checkout_order_processed`
- Post-order actions → `woocommerce_order_status_changed`

### Step 4: Verify Performance

**Install Query Monitor:**
```bash
wp plugin install query-monitor --activate
```

**Check thank-you page:**
1. Complete a test order
2. View thank-you page
3. Check Query Monitor for slow queries
4. Verify `idx_coupon_lookup` index is being used

---

## Performance Optimization

### Database Index Details

**Index SQL:**
```sql
ALTER TABLE wp_posts 
ADD INDEX idx_coupon_lookup (post_title(50), post_type, post_status);
```

**Why this works:**
- `post_title(50)` - Prefix index on first 50 characters (balances size vs performance)
- `post_type` - Filters to `shop_coupon` posts only
- `post_status` - Filters to `publish` status

**Verification:**
```sql
EXPLAIN SELECT ID FROM wp_posts 
WHERE post_title = 'TESTCODE' 
AND post_type = 'shop_coupon' 
AND post_status = 'publish';
```

Should show: `Using index` or `Using where; Using index`

### Caching Strategy

**Transient caching (15-minute TTL):**
```php
function get_cached_coupon_id($code) {
  $cache_key = 'coupon_id_' . md5(strtolower($code));
  $coupon_id = get_transient($cache_key);
  
  if (false === $coupon_id) {
    $coupon_id = wc_get_coupon_id_by_code($code);
    if ($coupon_id) {
      set_transient($cache_key, $coupon_id, 15 * MINUTE_IN_SECONDS);
    }
  }
  
  return $coupon_id;
}
```

**Object caching (Redis/Memcached):**
```php
// Requires Redis/Memcached object cache plugin
function get_cached_coupon_id($code) {
  $cache_key = 'coupon_id_' . md5(strtolower($code));
  $coupon_id = wp_cache_get($cache_key, 'coupons');
  
  if (false === $coupon_id) {
    $coupon_id = wc_get_coupon_id_by_code($code);
    if ($coupon_id) {
      wp_cache_set($cache_key, $coupon_id, 'coupons', 900); // 15 min
    }
  }
  
  return $coupon_id;
}
```

---

## Related Documentation

- [dist/patterns/wc-coupon-in-thankyou.json](patterns/wc-coupon-in-thankyou.json) - Custom coupon logic pattern
- [dist/patterns/wc-smart-coupons-thankyou-perf.json](patterns/wc-smart-coupons-thankyou-perf.json) - Smart Coupons performance pattern
- [WooCommerce Hooks Reference](https://woocommerce.github.io/code-reference/hooks/hooks.html)
- [Query Monitor Plugin](https://wordpress.org/plugins/query-monitor/)

---

## Changelog

### 1.1.1 (2026-01-08)
- Added Smart Coupons performance pattern
- Enhanced coupon-in-thankyou pattern to detect `wc_get_coupon_id_by_code()`
- Created comprehensive HOWTO guide

### 1.1.0 (2026-01-08)
- Initial release of `wc-coupon-in-thankyou` pattern

---

**Last Updated:** 2026-01-08  
**Patterns:** 2 (wc-coupon-in-thankyou, wc-smart-coupons-thankyou-perf)  
**Scripts:** 2 (detect-wc-coupon-in-thankyou.sh, detect-wc-smart-coupons-perf.sh)

