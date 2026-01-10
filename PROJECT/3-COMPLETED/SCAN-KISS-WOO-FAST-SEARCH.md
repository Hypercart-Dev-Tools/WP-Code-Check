# WP Code Check Scan: KISS Woo Fast Search

**Created:** 2026-01-06
**Status:** ✅ Complete
**Plugin:** KISS - Faster Customer & Order Search v1.0.1

## Summary

Successfully created template, tested, and scanned the KISS Woo Fast Search plugin. The scan identified 4 critical/high-severity errors that need attention.

## Template Created

**File:** `dist/TEMPLATES/kiss-woo-fast-search.txt`

**Auto-detected metadata:**
- **Plugin Name:** KISS - Faster Customer & Order Search
- **Version:** 1.0.1
- **Author:** Vishal Kharche
- **Main File:** kiss-woo-fast-order-search.php
- **Path:** `/Users/noelsaw/Local Sites/bloomz-prod-08-15/app/public/wp-content/plugins/KISS-woo-fast-search`

## Scan Results

### Overview
- **Files Analyzed:** 4
- **Lines of Code:** 738
- **Total Errors:** 4
- **Total Warnings:** 0
- **Exit Code:** 1 (failed - errors found)

### Critical Issues Found

#### 1. Direct Database Queries Without Prepare (2 occurrences) ⚠️ CRITICAL
**File:** `includes/class-kiss-woo-search.php`
**Lines:** 126, 173

**Issue:** Using `$wpdb->get_var($query)` without `$wpdb->prepare()` - SQL injection risk

**Example:**
```php
// Line 126
$count = $wpdb->get_var( $query );

// Line 173
$count = $wpdb->get_var( $query );
```

**Fix Required:** Use `$wpdb->prepare()` to sanitize all SQL queries:
```php
$count = $wpdb->get_var( $wpdb->prepare( $query, $params ) );
```

#### 2. Direct Superglobal Manipulation ⚠️ HIGH
**File:** `kiss-woo-fast-order-search.php`
**Line:** 99

**Issue:** Direct access to `$_POST` superglobal

**Code:**
```php
$term = isset( $_POST['q'] ) ? sanitize_text_field( wp_unslash( $_POST['q'] ) ) : '';
```

**Note:** While this is sanitized, WordPress best practice is to use `filter_input()` or validate through a dedicated function.

#### 3. Admin Functions Without Capability Checks (2 occurrences) ⚠️ HIGH
**File:** `admin/class-kiss-woo-admin-page.php`
**Lines:** 39, 54

**Issue:** Admin hooks registered without capability checks

**Code:**
```php
// Line 39
add_action( 'admin_menu', array( $this, 'register_menu' ) );

// Line 54
add_submenu_page(
    $parent_slug,
    $page_title,
    $menu_title,
    // Missing capability check here
```

**Fix Required:** Add capability checks before executing admin functions:
```php
if ( ! current_user_can( 'manage_woocommerce' ) ) {
    return;
}
```

### Warnings

#### 4. Potential N+1 Query Pattern ⚠️ WARNING
**File:** `includes/class-kiss-woo-search.php`

**Issue:** File may contain N+1 query pattern (meta in loops)

**Recommendation:** Review loops that fetch metadata to ensure they're not causing performance issues.

## Positive Findings ✅

The plugin passed 26 other critical checks:
- ✅ No debug code in production
- ✅ No sensitive data in localStorage/sessionStorage
- ✅ No insecure deserialization
- ✅ AJAX handlers have nonce validation
- ✅ No unbounded queries (posts_per_page, get_users, etc.)
- ✅ No transients without expiration
- ✅ No HTTP requests without timeout
- ✅ No file_get_contents with external URLs

## Fixture Validation

**Status:** ✅ Passed
- **Fixtures Tested:** 8
- **Passed:** 8
- **Failed:** 0
- **Message:** Detection patterns verified against 8 test fixtures

## Files Analyzed

1. `kiss-woo-fast-order-search.php` (main plugin file)
2. `includes/class-kiss-woo-search.php` (search functionality)
3. `admin/class-kiss-woo-admin-page.php` (admin interface)
4. Additional support files

## Recommendations

### Priority 1: Fix SQL Injection Risks (CRITICAL)
1. Update `includes/class-kiss-woo-search.php` lines 126 and 173
2. Use `$wpdb->prepare()` for all database queries
3. Test thoroughly to ensure queries still work correctly

### Priority 2: Add Capability Checks (HIGH)
1. Add `current_user_can()` checks to admin functions
2. Verify user permissions before executing admin actions
3. Use appropriate capability: `manage_woocommerce` or `manage_options`

### Priority 3: Review N+1 Patterns (MEDIUM)
1. Audit loops that fetch metadata
2. Consider using `update_meta_cache()` for bulk operations
3. Profile performance with large datasets

## Report Location

**HTML Report:** `/Users/noelsaw/Documents/GH Repos/wp-code-check/dist/reports/2026-01-06-042013-UTC.html`

**JSON Log:** `/Users/noelsaw/Documents/GH Repos/wp-code-check/dist/logs/2026-01-06-042013-UTC.json`

## Next Steps

1. Share report with plugin developer (Vishal Kharche)
2. Prioritize fixing SQL injection vulnerabilities
3. Add capability checks to admin functions
4. Re-scan after fixes to verify issues resolved
5. Consider creating a baseline file to track progress

## Template Usage

To re-run this scan in the future:

```bash
cd /Users/noelsaw/Documents/GH\ Repos/wp-code-check/dist
./bin/run kiss-woo-fast-search --format json
```

Or with custom options:

```bash
./bin/run kiss-woo-fast-search --format json --max-errors 0
```

