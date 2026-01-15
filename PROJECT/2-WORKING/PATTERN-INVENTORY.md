# Pattern Migration Inventory

**Created:** 2026-01-15  
**Status:** In Progress  
**Purpose:** Complete inventory of all inline rules in `check-performance.sh` for migration to JSON

---

## Overview

This document catalogs **all inline pattern rules** currently hardcoded in `check-performance.sh`. Each rule is classified by complexity tier to guide migration strategy.

### Complexity Tiers

- **T1 (Tier 1)** - Simple grep patterns → Direct JSON migration (1-5 min each)
- **T2 (Tier 2)** - Multi-step checks with context → JSON + helper functions (10-20 min each)
- **T3 (Tier 3)** - Complex logic with loops/aggregation → JSON + validator script (30-60 min each)
- **T4 (Tier 4)** - Highly complex state machines → Defer or redesign (2-4 hours each)

### Migration Priority

- **P1 (High)** - Security, SPO, KISS violations - migrate first
- **P2 (Medium)** - Performance, N+1 patterns - migrate second
- **P3 (Low)** - Heuristics, warnings - migrate last

---

## 🚧 BLOCKERS - MUST RESOLVE BEFORE PHASE 2 COMPLETE

### Simple Pattern Runner Not Implemented

**Status:** BLOCKED
**Impact:** 4 JSON patterns created but not active
**Affected Rules:** #18, #19, #20, #35 (unbounded-posts-per-page, unbounded-numberposts, nopaging-true, order-by-rand)

**Problem:**
- JSON pattern files exist and load correctly
- Scanner has no runner for `detection.type: "simple"` patterns
- Inline code remains active as workaround

**Solution Required:**
- Implement simple pattern runner in `check-performance.sh` (see lines 5757-5850 for reference)
- Estimated effort: 2-3 hours
- See: `PROJECT/1-INBOX/IMPLEMENT-SIMPLE-PATTERN-RUNNER.md`

**Tracking:**
- Inline code markers: Search for "TODO: Implement simple pattern runner" in `check-performance.sh`
- Lines 3850-3862, 4854-4864

---

## Inventory Table

| # | Rule ID | Title | Lines | Tier | Priority | Category | Status | Notes |
|---|---------|-------|-------|------|----------|----------|--------|-------|
| 1 | `spo-001-debug-code` | Debug code in production | 2795-2810 | T1 | P1 | SPO/Security | ✅ JSON | Already migrated |
| 2 | `hcc-001-localstorage-exposure` | Sensitive data in localStorage | 2815-2828 | T1 | P1 | Security | ✅ JSON | Already migrated |
| 3 | `hcc-002-client-serialization` | Serialization to client storage | 2833-2841 | T1 | P1 | Security | ✅ JSON | Already migrated |
| 4 | `hcc-008-unsafe-regexp` | User input in RegExp | 2846-2848 | T1 | P1 | Security | ✅ JSON | Already migrated |
| 5 | `superglobal-manipulation` | Direct superglobal manipulation | 2856-2952 | T2 | P1 | Security | ⏳ Inline | Multi-step with comment filtering |
| 6 | `unsanitized-superglobal-isset-bypass` | Unsanitized superglobal read | 2957-3122 | T3 | P1 | Security | ⏳ Inline | Complex isset/empty bypass detection |
| 7 | `php-eval-injection` | Dangerous eval() usage | 3127-3128 | T1 | P1 | Security | ✅ JSON | Already migrated |
| 8 | `php-dynamic-include` | Dynamic include/require | 3131-3133 | T1 | P1 | Security | ✅ JSON | Already migrated |
| 9 | `php-shell-exec-functions` | Shell command execution | 3136-3140 | T1 | P1 | Security | ✅ JSON | Already migrated |
| 10 | `spo-003-insecure-deserialization` | Insecure deserialization | 3143-3152 | T1 | P1 | SPO/Security | ✅ JSON | Already migrated |
| 11 | `php-hardcoded-credentials` | Hardcoded credentials | 3156-3177 | T1 | P1 | Security | ✅ JSON | Already migrated |
| 12 | `wpdb-unprepared-query` | Direct DB queries without prepare | 3181-3297 | T2 | P1 | Security | ⏳ Inline | Multi-step with prepare check |
| 13 | `admin-cap-missing` | Admin functions without caps | 3301-3430 | T3 | P1 | Security | ⏳ Inline | Complex callback analysis |
| 14 | `ajax-polling-unbounded` | Unbounded AJAX polling | 3434-3493 | T2 | P2 | Performance | ⏳ Inline | setInterval + fetch detection |
| 15 | `hcc-005-expensive-polling` | Expensive WP functions in polling | 3497-3558 | T2 | P2 | Performance | ⏳ Inline | Context-aware polling check |
| 16 | `rest-no-pagination` | REST endpoints without pagination | 3562-3620 | T2 | P2 | Performance | ⏳ Inline | register_rest_route analysis |
| 17 | `ajax-nonce-missing` | wp_ajax handlers without nonce | 3624-3846 | T3 | P1 | Security | ⏳ Inline | Complex callback + nonce detection |
| 18 | `unbounded-posts-per-page` | Unbounded posts_per_page | 3850-3862 | T1 | P2 | Performance | ⏳ JSON (blocked) | JSON exists, needs runner |
| 19 | `unbounded-numberposts` | Unbounded numberposts | 3850-3862 | T1 | P2 | Performance | ⏳ JSON (blocked) | JSON exists, needs runner |
| 20 | `nopaging-true` | nopaging => true | 3850-3862 | T1 | P2 | Performance | ⏳ JSON (blocked) | JSON exists, needs runner |
| 21 | `wc-unbounded-limit` | Unbounded WC limit=-1 | 3863-3935 | T2 | P2 | Performance | ⏳ Inline | Mitigation detection |
| 22 | `wcs-no-limit` | WC Subscriptions without limits | 3939-4000 | T2 | P2 | Performance | ⏳ Inline | wcs_get_subscriptions check |
| 23 | `get-users-no-limit` | get_users without number | 4004-4085 | T2 | P2 | Performance | ⏳ Inline | Context window check |
| 24 | `get-terms-no-limit` | get_terms without number | 4089-4143 | T2 | P2 | Performance | ⏳ Inline | Context window check |
| 25 | `pre-get-posts-unbounded` | pre_get_posts forcing unbounded | 4147-4183 | T2 | P2 | Performance | ⏳ Inline | Hook + set() detection |
| 26 | `unbounded-sql-terms` | Unbounded SQL on terms tables | 4189-4242 | T2 | P2 | Performance | ⏳ Inline | LIMIT check on SQL |
| 27 | `wc-get-orders-unbounded` | Unbounded wc_get_orders() | 4246-4299 | T2 | P2 | Performance | ⏳ Inline | Context window check |
| 28 | `wc-get-products-unbounded` | Unbounded wc_get_products() | 4303-4353 | T2 | P2 | Performance | ⏳ Inline | Context window check |
| 29 | `wp-query-unbounded` | Unbounded WP_Query/get_posts | 4357-4420 | T2 | P2 | Performance | ⏳ Inline | Context window check |
| 30 | `wp-user-query-no-cache` | WP_User_Query without meta cache | 4424-4492 | T2 | P2 | Performance | ⏳ Inline | cache_results check |
| 31 | `query-limit-multiplier` | Query limit multipliers (count*N) | 4496-4563 | T2 | P2 | Performance | ⏳ Inline | Heuristic pattern |
| 32 | `array-merge-in-loop` | array_merge() inside loops | 4567-4628 | T2 | P3 | Performance | ⏳ Inline | Heuristic pattern |
| 33 | `cron-interval-unvalidated` | Unvalidated cron intervals | 4632-4768 | T3 | P2 | KISS | ⏳ Inline | Complex interval validation |
| 34 | `timezone-sensitive-patterns` | Timezone patterns (current_time) | 4772-4847 | T2 | P3 | KISS | ⏳ Inline | current_time/date detection |
| 35 | `order-by-rand` | Randomized ordering (RAND) | 4854-4864 | T1 | P2 | Performance | ⏳ JSON (blocked) | JSON exists, needs runner |
| 36 | `like-leading-wildcard` | LIKE with leading wildcards | 4859-4959 | T2 | P2 | Performance | ⏳ Inline | Meta_query LIKE detection |
| 37 | `n1-meta-in-loop` | N+1 patterns (meta in loops) | 4963-5016 | T2 | P2 | Performance | ⏳ Inline | Loop + meta detection |
| 38 | `wc-n1-in-loop` | WC N+1 patterns (WC in loops) | 5020-5113 | T3 | P2 | Performance | ⏳ Inline | Complex WC context detection |
| 39 | `wc-coupon-thankyou` | WC coupon logic in thank-you | 5117-5185 | T3 | P3 | Performance | ⏳ Inline | Multi-step context detection |
| 40 | `wc-smart-coupons-perf` | Smart Coupons performance | 5189-5264 | T3 | P3 | Performance | ⏳ Inline | Plugin-specific detection |
| 41 | `json-html-escape-url` | HTML-escaping in JSON URLs | 5268-5320 | T3 | P3 | KISS | ⏳ Inline | Heuristic JSON detection |
| 42 | `transient-no-expiration` | Transients without expiration | 5324-5369 | T2 | P2 | Performance | ⏳ Inline | set_transient check |
| 43 | `script-version-time` | Script versioning with time() | 5373-5410 | T2 | P3 | Performance | ⏳ Inline | wp_enqueue + time() |
| 44 | `file-get-contents-url` | file_get_contents() with URLs | 5414-5479 | T1 | P2 | Performance | ⏳ Inline | Simple grep |
| 45 | `http-no-timeout` | HTTP requests without timeout | 5483-5575 | T2 | P2 | Performance | ⏳ Inline | wp_remote_* context check |
| 46 | `php-short-tags` | Disallowed PHP short tags | 5579-5651 | T2 | P3 | KISS | ⏳ Inline | <?= and <? detection |

---

## Summary Statistics

### By Tier
- **T1 (Simple):** 11 rules (24%)
- **T2 (Moderate):** 24 rules (52%)
- **T3 (Complex):** 11 rules (24%)
- **T4 (Very Complex):** 0 rules (0%)

**Total:** 46 inline rules

### By Priority
- **P1 (High - Security/SPO):** 13 rules (28%)
- **P2 (Medium - Performance):** 26 rules (57%)
- **P3 (Low - Heuristics):** 7 rules (15%)

### By Status
- **✅ Fully Migrated to JSON:** 7 rules (15%) - Active and working
- **⏳ JSON Created (Blocked):** 4 rules (9%) - Waiting for simple pattern runner
- **⏳ Needs Migration:** 35 rules (76%) - Still inline code

### Migration Effort Estimate

Based on tier complexity:
- **T1 rules:** 11 total, 4 migrated, 7 remaining × 5 min = ~35 minutes
- **T2 rules:** 24 rules × 15 min = ~6 hours
- **T3 rules:** 11 rules × 45 min = ~8 hours

**Total estimated effort remaining:** ~14 hours (1.75 work days)
**Progress:** 4 of 46 rules migrated in Phase 2 (9%)

---

## Phase 2 High-Priority Targets (P1)

These rules should be migrated first:

### Security Rules (6 rules)
1. ✅ `spo-001-debug-code` - Already JSON
2. ✅ `hcc-001-localstorage-exposure` - Already JSON
3. ✅ `hcc-002-client-serialization` - Already JSON
4. ✅ `hcc-008-unsafe-regexp` - Already JSON
5. ⏳ `superglobal-manipulation` - **T2, needs migration**
6. ⏳ `unsanitized-superglobal-isset-bypass` - **T3, needs migration**
7. ✅ `php-eval-injection` - Already JSON
8. ✅ `php-dynamic-include` - Already JSON
9. ✅ `php-shell-exec-functions` - Already JSON
10. ✅ `spo-003-insecure-deserialization` - Already JSON
11. ✅ `php-hardcoded-credentials` - Already JSON
12. ⏳ `wpdb-unprepared-query` - **T2, needs migration**
13. ⏳ `admin-cap-missing` - **T3, needs migration**
14. ⏳ `ajax-nonce-missing` - **T3, needs migration**

**P1 Migration Status:** 7/14 complete (50%)

---

## Next Steps

1. ✅ Complete Phase 0 inventory (this document)
2. ⏳ Migrate P1 security rules (7 remaining)
3. ⏳ Migrate P2 performance rules (26 rules)
4. ⏳ Migrate P3 heuristic rules (7 rules)
5. ⏳ Remove inline code after JSON migration
6. ⏳ Update tests to reference JSON patterns

