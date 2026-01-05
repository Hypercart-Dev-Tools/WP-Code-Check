# Pattern Library - JSON Files Summary

**Date:** 2026-01-01  
**Version:** 1.0.69  
**Status:** ✅ 4 Pattern JSON Files Created

---

## 📚 Pattern Library Overview

The pattern library separates pattern definitions from scanner logic, enabling:
- **Modularity** - Each pattern is self-contained
- **Versioning** - Track pattern evolution over time
- **Community Contributions** - Easy to add new patterns
- **Testing** - Link patterns to test fixtures
- **Documentation** - Remediation examples and references
- **IRL Examples** - Real-world code from production plugins

---

## 📁 Pattern JSON Files (4 Total)

### 1. unsanitized-superglobal-isset-bypass.json
**ID:** `unsanitized-superglobal-isset-bypass`  
**Severity:** HIGH  
**Category:** Security  
**Added:** v1.0.67

**Description:**  
Detects `$_GET/$_POST/$_REQUEST` used directly after `isset/empty` check on same line without sanitization.

**Detection Logic:**
- Search: `\$_(GET|POST|REQUEST)\[`
- Exclude: `sanitize_`, `esc_`, `absint`, `intval`, `wc_clean`, `wp_unslash`, comments
- Post-process: Count occurrences per line - report if 2+ (isset + usage)

**Test Fixture:**
- Path: `dist/tests/fixtures/unsanitized-superglobal-isset-bypass.php`
- Expected violations: 5
- Expected valid: 6

**IRL Examples:** 3
- WooCommerce All Products for Subscriptions v6.0.6 (line 451)
- KISS Woo Coupon Debugger v2.1.0 (lines 434, 472)

---

### 2. unsanitized-superglobal-read.json ⭐ NEW
**ID:** `unsanitized-superglobal-read`  
**Severity:** HIGH  
**Category:** Security  
**Added:** v1.0.69

**Description:**  
Direct access to `$_GET/$_POST/$_REQUEST` without sanitization functions. Broader than isset-bypass - catches ANY unsanitized access.

**Detection Logic:**
- Search: `\$_(GET|POST|REQUEST)\[`
- Exclude: `sanitize_`, `esc_`, `absint`, `intval`, `wc_clean`, `wp_unslash`, `isset(`, `empty(`, `in_array(`, comments
- Post-process: None (catches all direct reads)

**Test Fixture:**
- Path: `dist/tests/fixtures/unsanitized-superglobal-read.php`
- Expected violations: 8
- Expected valid: 13

**IRL Examples:** 3
- WP Activity Log v5.5.4 (lines 1261, 343, 358)
- Type juggling vulnerability in plugin visibility control
- Unsanitized array access in bulk plugin updates

**Remediation:**
```php
// Bad
if ( $_GET['tab'] === 'subscriptions' ) {

// Good
if ( isset( $_GET['tab'] ) && sanitize_key( $_GET['tab'] ) === 'subscriptions' ) {
```

---

### 3. wpdb-query-no-prepare.json ⭐ NEW
**ID:** `wpdb-query-no-prepare`  
**Severity:** CRITICAL  
**Category:** Security  
**Added:** v1.0.69

**Description:**  
Detects `$wpdb->query()`, `get_var()`, `get_row()`, `get_results()`, or `get_col()` called without `$wpdb->prepare()` wrapper - SQL injection risk.

**Detection Logic:**
- Search: `\$wpdb->(query|get_var|get_row|get_results|get_col)\(`
- Exclude: `\$wpdb->prepare\(`, comments, `phpcs:ignore`
- Post-process: Check if `prepare()` appears on same or previous line

**Test Fixture:**
- Path: `dist/tests/fixtures/wpdb-no-prepare.php`
- Expected violations: 7
- Expected valid: 7

**IRL Examples:** 1
- WP Activity Log v5.5.4 (line 226/151 original)
- Migration function with hardcoded LIKE query
- Low immediate risk but violates WordPress Coding Standards

**Remediation:**
```php
// Bad
$wpdb->get_results( "SELECT option_name FROM $wpdb->options WHERE option_name LIKE 'prefix_%'" );

// Good
$wpdb->get_results(
    $wpdb->prepare(
        "SELECT option_name FROM {$wpdb->options} WHERE option_name LIKE %s",
        $wpdb->esc_like( 'prefix_' ) . '%'
    )
);
```

**Special Cases:**
- LIKE queries: Use `$wpdb->esc_like()` to escape wildcards
- IN clauses: Use `array_fill()` to create placeholders
- Static queries: Technically safe but still flagged (use `phpcs:ignore` with justification)

---

### 4. get-users-no-limit.json ⭐ NEW
**ID:** `get-users-no-limit`  
**Severity:** CRITICAL  
**Category:** Performance  
**Added:** v1.0.69

**Description:**  
Detects `get_users()` calls without the `'number'` parameter, which can fetch ALL users and cause memory exhaustion on large sites.

**Detection Logic:**
- Search: `get_users\(`
- Exclude: `'number'\s*=>`, `"number"\s*=>`, comments
- Post-process: Check if `'number'` parameter appears within 5 lines

**Test Fixture:**
- Path: None yet (TODO: Create comprehensive fixture)
- Expected violations: TBD
- Expected valid: TBD

**IRL Examples:** 2
- WP Activity Log v5.5.4 (lines 230, 444)
- AJAX user search without limits
- Pre-loading users when count below threshold (still unbounded)

**Performance Impact:**
| Site Size | Users | Impact | Recommendation |
|-----------|-------|--------|----------------|
| Small | < 1,000 | Low | Still add limits for future-proofing |
| Medium | 1,000 - 10,000 | Medium | MUST add limits - risk of timeouts |
| Large | 10,000+ | CRITICAL | MUST add limits + pagination + caching |
| Enterprise | 50,000+ | SEVERE | Guaranteed crashes without limits |

**Remediation:**
```php
// Bad
$users = get_users();

// Good
$users = get_users( array( 'number' => 100 ) );

// Better (with pagination)
$users = get_users( array(
    'number' => 50,
    'paged' => $page,
    'search' => '*' . $search . '*'
) );
```

**Alternatives:**
- Direct `$wpdb` queries with LIMIT
- `WP_User_Query` with `'fields'` parameter (reduces memory)
- Autocomplete with minimum character requirement (3+ chars)

---

## 📊 Pattern Statistics

| Pattern | Severity | Category | Fixtures | IRL Examples | Status |
|---------|----------|----------|----------|--------------|--------|
| unsanitized-superglobal-isset-bypass | HIGH | Security | ✅ | 3 | ✅ Complete |
| unsanitized-superglobal-read | HIGH | Security | ✅ | 3 | ✅ Complete |
| wpdb-query-no-prepare | CRITICAL | Security | ✅ | 1 | ✅ Complete |
| get-users-no-limit | CRITICAL | Performance | ❌ | 2 | ⚠️ Needs fixture |

**Total:** 4 patterns, 9 IRL examples, 3 test fixtures

---

## 🎯 Next Steps

### Immediate
1. ✅ **Pattern JSON Files Created** - All 3 new patterns documented
2. ⏭️ **Create get-users Fixture** - Add `dist/tests/fixtures/get-users-no-limit.php`
3. ⏭️ **Integrate Patterns into Scanner** - Load from JSON instead of hardcoded logic

### Future
- Create JSON files for remaining 29 patterns (33 total - 4 done = 29 remaining)
- Add more IRL examples from WP Activity Log (57 additional violations available)
- Community pattern submissions via GitHub
- Pattern versioning and deprecation strategy

---

## 📂 File Locations

**Pattern JSON Files:**
- `dist/patterns/unsanitized-superglobal-isset-bypass.json`
- `dist/patterns/unsanitized-superglobal-read.json`
- `dist/patterns/wpdb-query-no-prepare.json`
- `dist/patterns/get-users-no-limit.json`

**Test Fixtures:**
- `dist/tests/fixtures/unsanitized-superglobal-isset-bypass.php`
- `dist/tests/fixtures/unsanitized-superglobal-read.php`
- `dist/tests/fixtures/wpdb-no-prepare.php`

**IRL Examples:**
- `dist/tests/irl/woocommerce-all-products-for-subscriptions/`
- `dist/tests/irl/kiss-woo-coupon-debugger/`
- `dist/tests/irl/wp-security-audit-log/`

---

**Pattern library is growing!** 🎉  
4 patterns documented, 29 more to go.

