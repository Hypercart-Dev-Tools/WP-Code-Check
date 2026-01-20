# New Pattern Detection Opportunities

**Date:** 2026-01-01  
**Source:** Manual analysis of WooCommerce All Products for Subscriptions v6.0.6  
**Status:** Proposed

---

## Executive Summary

Based on manual code review of a 14K+ LOC WooCommerce plugin, I identified **8 new patterns** that could be added to the automated detection library. These patterns caught real issues that the current 29 checks missed.

**Impact:** Adding these patterns would increase detection coverage from **29 to 37 checks** (+28% coverage).

---

## 🆕 NEW PATTERNS (Can be added immediately)

### 1. **Unsanitized `$_GET` Usage** ⭐ HIGH PRIORITY — STATUS: ✅ COMPLETE

**Current Status:** Partially detected  
**Gap:** Current check only detects *assignment* to superglobals, not *reading* without sanitization

**Current Detection:**
```bash
# Only catches: $_GET['foo'] = 'bar' (assignment)
"-E \\$_(GET|POST|REQUEST)\\[[^]]*\\][[:space:]]*="
```

**Proposed Enhancement:**
```bash
# NEW: Catch direct usage without sanitization wrapper
"-E \\$_(GET|POST)\\[[^]]+\\]" | grep -v "sanitize_\|wc_clean\|absint\|intval\|esc_\|isset\|empty"
```

**Example Caught:**
```php
// ❌ BAD - Would be detected
if ( $_GET['tab'] === 'subscriptions' ) {

// ✅ GOOD - Would pass
if ( isset( $_GET['tab'] ) && sanitize_key( $_GET['tab'] ) === 'subscriptions' ) {
```

**Severity:** HIGH  
**Category:** security  
**Rule ID:** `unsanitized-superglobal-read`

**Notes:** Add generous allowlist to reduce false positives (`sanitize_*`, `esc_*`, `absint`, `intval`, `wc_clean`, `wp_unslash`, `isset`, `empty`, `$allowed_keys`).

---

### 2. **Missing Capability Checks in Admin Functions** ⭐ HIGH PRIORITY — STATUS: ✅ ENHANCED (v1.0.65)

**Current Status:** ✅ COMPLETE
**Enhancement:** Now detects `add_menu_page`, `add_submenu_page`, `add_options_page`, `add_management_page` in addition to AJAX handlers

**Proposed Pattern:**
```bash
# Detect admin menu callbacks without capability checks
grep -A20 "add_menu_page\|add_submenu_page" | grep -v "current_user_can\|is_admin"
```

**Example Caught:**
```php
// ❌ BAD - Admin function without capability check
function handle_admin_action() {
    // Missing: if ( ! current_user_can( 'manage_options' ) ) { return; }
    update_option( 'setting', $_POST['value'] );
}
```

**Severity:** HIGH  
**Category:** security  
**Rule ID:** `admin-function-no-capability`

**Notes:** Scope to admin menu callbacks and admin init/menu hooks; ensure `current_user_can`/`user_can` present in same function; ignore comments/strings.

---

### 3. **Complex Conditionals (Cyclomatic Complexity)** ⭐ MEDIUM PRIORITY — STATUS: NOT STARTED

**Current Status:** Not detected  
**Gap:** No check for maintainability/code complexity

**Proposed Pattern:**
```bash
# Detect if statements with 4+ conditions
grep -E "if[[:space:]]*\\(.*&&.*&&.*&&"
```

**Example Caught:**
```php
// ❌ BAD - 4+ conditions (hard to test/maintain)
if ( $a && $b && $c && $d ) {
```

**Severity:** MEDIUM (could be LOW)  
**Category:** maintainability  
**Rule ID:** `complex-conditional`

**Notes:** Risk of noise; make threshold configurable (start at 4+ conditions), restrict to PHP files, ignore comments.

---

### 4. **No Caching for Expensive Operations** ⭐ MEDIUM PRIORITY — STATUS: NOT STARTED

**Current Status:** Not detected  
**Gap:** No check for missing caching patterns

**Proposed Pattern:**
```bash
# Detect expensive operations without nearby caching
# Look for WP_Query, get_posts, wc_get_orders without get_transient in same function
```

**Example Caught:**
```php
// ❌ BAD - Expensive query without caching
function get_subscription_schemes( $product_id ) {
    $query = new WP_Query( array( /* complex query */ ) );
    // Missing: transient check
}
```

**Severity:** MEDIUM  
**Category:** performance  
**Rule ID:** `missing-cache-expensive-operation`

**Notes:** Hard with grep; consider gating as experimental or defer until function-level/AST analysis exists.

**Note:** This is complex to detect reliably with grep. May need function-level analysis.

---

### 5. **Subscription/Order Queries Without Limits** ⭐ MEDIUM PRIORITY — STATUS: ✅ COMPLETE (v1.0.65)

**Current Status:** ✅ COMPLETE
**Implementation:** WooCommerce Subscriptions functions now detected (`wcs_get_subscriptions*` without 'limit' parameter)

**Proposed Pattern:**
```bash
# Detect wcs_get_subscriptions without 'limit' parameter
grep -E "wcs_get_subscriptions\\(" | grep -v "'limit'"
```

**Example Caught:**
```php
// ❌ BAD - No limit specified
$subscriptions = wcs_get_subscriptions_for_order( $order_id );

// ✅ GOOD
$subscriptions = wcs_get_subscriptions_for_order( $order_id, array( 'limit' => 100 ) );
```

**Severity:** MEDIUM  
**Category:** performance  
**Rule ID:** `wcs-get-subscriptions-no-limit`

---

### 7. **Nested Loops (Performance Risk)** ⭐ LOW PRIORITY — STATUS: NOT STARTED

**Current Status:** Not detected
**Gap:** No check for nested loop patterns that multiply complexity

**Proposed Pattern:**
```bash
# Detect nested foreach loops (potential O(n²) complexity)
grep -A10 "foreach" | grep "foreach"
```

**Example Caught:**
```php
// ❌ BAD - Nested loops can be O(n²)
foreach ( $cart_items as $item ) {
    foreach ( $subscription_schemes as $scheme ) {
        // Potential performance issue with large datasets
    }
}
```

**Severity:** LOW
**Category:** performance
**Rule ID:** `nested-loops`

**Notes:** Potentially noisy; limit to PHP, maybe skip small functions or allowlist obvious small loops.

**Note:** This is a code smell, not always a bug. Many nested loops are necessary.

---

### 8. **Direct Database Queries Without $wpdb->prepare()** ⭐ CRITICAL PRIORITY — STATUS: ✅ COMPLETE

**Current Status:** Not detected
**Gap:** No check for SQL injection via unprepared queries

**Proposed Pattern:**
```bash
# Detect $wpdb->query without $wpdb->prepare
grep -E "\\$wpdb->(query|get_)" | grep -v "prepare"
```

**Example Caught:**
```php
// ❌ CRITICAL - SQL injection risk
$wpdb->query( "DELETE FROM {$wpdb->posts} WHERE ID = {$_GET['id']}" );

// ✅ GOOD
$wpdb->query( $wpdb->prepare( "DELETE FROM {$wpdb->posts} WHERE ID = %d", $_GET['id'] ) );
```

**Severity:** CRITICAL
**Category:** security
**Rule ID:** `wpdb-query-no-prepare`

**Notes:** Exclude lines already containing `$wpdb->prepare(`; include `get_var/get_row/get_results` raw SQL.

---

## 📊 PATTERN ENHANCEMENT OPPORTUNITIES (Improve existing checks)

### 9. **Enhance: Direct Superglobal Manipulation** — STATUS: NOT STARTED

**Current Check:** `spo-002-superglobals` (HIGH)
**Current Pattern:** Only detects *assignment* to superglobals
**Enhancement:** Also detect *reading* without sanitization

**Before:**
```bash
"-E \\$_(GET|POST|REQUEST)\\[[^]]*\\][[:space:]]*="
```

**After:**
```bash
# Add new pattern to existing check
"-E \\$_(GET|POST|REQUEST)\\[[^]]+\\]" | grep -v "sanitize_\|wc_clean\|absint\|isset\|empty"
```

**Impact:** Would catch 10+ additional instances in the analyzed plugin

---

### 10. **Enhance: N+1 Pattern Detection** — STATUS: ✅ COMPLETE (v1.0.66)

**Current Check:** `n-plus-one-pattern` (MEDIUM) - General N+1 detection
**New Check:** `wc-n-plus-one-pattern` (HIGH) - WooCommerce-specific N+1 detection
**Enhancement:** Created dedicated WooCommerce N+1 check that detects WC functions in loops

**Implementation:**
```bash
# New dedicated check: wc-n-plus-one-pattern
# Detects loops over WC orders/products, then checks loop body for:
# - wc_get_order()
# - wc_get_product()
# - get_post_meta()
# - get_user_meta()
# - ->get_meta()
```

**Impact:** ✅ Successfully catches WooCommerce-specific N+1 patterns (7 violations detected in test fixture)

---

## 📋 IMPLEMENTATION PRIORITY MATRIX

| # | Pattern | Severity | Ease | Impact | Priority |
|---|---------|----------|------|--------|----------|
| 8 | **wpdb without prepare** | CRITICAL | Easy | High | 🔥 **P0** |
| 1 | **Unsanitized $_GET read** | HIGH | Medium | High | 🔥 **P0** |
| 2 | **Admin no capability** | HIGH | Medium | Medium | ⚡ **P1** |
| 5 | **WCS queries no limit** | MEDIUM | Easy | Medium | ⚡ **P1** |
| 9 | **Enhance superglobal** | HIGH | Easy | High | ⚡ **P1** |
| 10 | **Enhance N+1 detection** | MEDIUM | Easy | Medium | ⚡ **P1** |
| 6 | **Error suppression** | LOW | Easy | Low | 📝 **P2** |
| 3 | **Complex conditionals** | MEDIUM | Easy | Low | 📝 **P2** |
| 7 | **Nested loops** | LOW | Medium | Low | 📝 **P3** |
| 4 | **Missing caching** | MEDIUM | Hard | Medium | 📝 **P3** |

---

## 🎯 RECOMMENDED IMPLEMENTATION PLAN

### Phase 1: Quick Wins (1-2 hours)
- ✅ Pattern #8: wpdb without prepare (CRITICAL)
- ✅ Pattern #1: Unsanitized $_GET read (HIGH)
- ✅ Pattern #6: Error suppression (LOW but easy)
- ✅ Enhancement #9: Improve superglobal detection

**Deliverable:** 4 new/enhanced checks, +CRITICAL security coverage

### Phase 2: WooCommerce-Specific (2-3 hours) — ✅ COMPLETE (v1.0.66)
- ✅ Pattern #5: WCS queries without limits (v1.0.65)
- ✅ Enhancement #10: WooCommerce N+1 patterns (v1.0.66)
- ✅ Pattern #2: Admin capability checks (v1.0.65)

**Deliverable:** ✅ COMPLETE - 3 new checks, better WooCommerce coverage

### Phase 3: Code Quality (3-4 hours)
- ✅ Pattern #3: Complex conditionals
- ✅ Pattern #7: Nested loops
- ⚠️ Pattern #4: Missing caching (requires more research)

**Deliverable:** 2-3 new checks, maintainability focus

---

## 📈 EXPECTED IMPACT

**Current State:**
- 29 checks
- Caught 0 issues in WCS plugin (all automated checks passed)

**After Phase 1:**
- 33 checks (+4)
- Would catch ~15-20 issues in WCS plugin (unsanitized $_GET, potential SQL injection)

**After Phase 2:**
- 36 checks (+7)
- Would catch ~25-30 issues (WooCommerce-specific patterns)

**After Phase 3:**
- 37-38 checks (+8-9)
- Would catch ~30-35 issues (including code quality)

---

## 🔍 VALIDATION STRATEGY

For each new pattern:

1. **Create test fixture** in `dist/tests/fixtures/`
2. **Add expected count** to fixture validation
3. **Test against real plugins:**
   - WooCommerce All Products for Subscriptions (baseline)
   - WooCommerce core
   - Popular free plugins from wordpress.org

4. **Measure false positive rate:**
   - Target: <5% false positives
   - If higher, refine pattern or add exclusions

---

## 💡 NOTES & CONSIDERATIONS

### Why These Patterns Matter

1. **Security Patterns (#1, #2, #8):** Prevent real vulnerabilities
2. **Performance Patterns (#5, #10):** Prevent site crashes under load
3. **Maintainability Patterns (#3, #6, #7):** Reduce technical debt

### Challenges

- **Pattern #4 (Missing caching):** Hard to detect reliably with grep
  - May need function-level analysis
  - Consider as future enhancement with AST parsing

- **Pattern #3 (Complex conditionals):** Subjective threshold
  - Start with 4+ conditions
  - Make configurable via severity config

### False Positive Mitigation

- Use negative lookahead patterns (grep -v)
- Exclude common safe patterns (isset, empty, sanitize_*)
- Allow users to suppress via baseline files

---

## 🚀 NEXT STEPS

1. **Review this document** with team
2. **Prioritize patterns** based on project needs
3. **Implement Phase 1** (quick wins)
4. **Test against real codebases**
5. **Iterate based on feedback**

---

**Author:** AI Agent (Augment)
**Reviewed by:** [Pending]
**Approved by:** [Pending]
### 6. **Error Suppression with @ Operator** ⭐ LOW PRIORITY — STATUS: NOT STARTED

**Current Status:** Not detected  
**Gap:** No check for error suppression antipattern

**Proposed Pattern:**
```bash
# Detect @ operator (error suppression)
grep -E "@\\$_|@get_|@wc_|@file_|@fopen|@json_decode"
```

**Example Caught:**
```php
// ❌ BAD - Suppressing errors hides bugs
$data = @json_decode( $response );
```

**Severity:** LOW  
**Category:** maintainability  
**Rule ID:** `error-suppression`

**Notes:** Avoid matching comments/strings; watch for vendor/library code to limit false positives.

---


