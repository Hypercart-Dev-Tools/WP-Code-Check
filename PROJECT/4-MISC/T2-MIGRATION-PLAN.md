# T2 Rules Migration Plan

**Created:** 2026-01-15  
**Status:** In Progress

## Overview

This document categorizes the 24 remaining T2 rules by migration complexity and defines the migration strategy for each group.

---

## Category 1: Simple Patterns (Can use existing Simple Pattern Runner)

These rules can be migrated using the existing simple pattern runner with minimal changes:

### 1.1 Direct Grep Patterns (5 rules)

| # | Rule ID | Title | Lines | Complexity | Notes |
|---|---------|-------|-------|------------|-------|
| 46 | `php-short-tags` | Disallowed PHP short tags | 5508-5574 | Low | Two patterns: `<?=` and `<? ` |
| 34 | `timezone-sensitive-patterns` | Timezone patterns | 4772-4847 | Low | Detects `current_time`, `date()` usage |
| 42 | `transient-no-expiration` | Transients without expiration | 5324-5369 | Low | Detects `set_transient` with 0 expiration |
| 43 | `script-version-time` | Script versioning with time() | 5373-5410 | Low | Detects `wp_enqueue_*` with `time()` |
| 32 | `array-merge-in-loop` | array_merge() in loops | 4567-4628 | Medium | Heuristic: array_merge near loop keywords |

**Estimated effort:** 5 × 15 min = 1.25 hours

---

## Category 2: Context-Aware Patterns (Need scripted validators)

These rules require checking context (e.g., presence of mitigation code, function scope):

### 2.1 Mitigation Detection (10 rules)

| # | Rule ID | Title | Lines | Complexity | Notes |
|---|---------|-------|-------|------------|-------|
| 21 | `wc-unbounded-limit` | Unbounded WC limit=-1 | 3863-3935 | Medium | Check for `LIMIT` in same function |
| 23 | `get-users-no-limit` | get_users without number | 4004-4085 | Medium | Check for `number` param |
| 24 | `get-terms-no-limit` | get_terms without number | 4089-4143 | Medium | Check for `number` param |
| 27 | `wc-get-orders-unbounded` | Unbounded wc_get_orders() | 4246-4299 | Medium | Check for `limit` param |
| 28 | `wc-get-products-unbounded` | Unbounded wc_get_products() | 4303-4353 | Medium | Check for `limit` param |
| 29 | `wp-query-unbounded` | Unbounded WP_Query/get_posts | 4357-4420 | Medium | Check for pagination params |
| 30 | `wp-user-query-no-cache` | WP_User_Query without cache | 4424-4492 | Medium | Check for `cache_results` |
| 26 | `unbounded-sql-terms` | Unbounded SQL on terms | 4189-4242 | Medium | Check for `LIMIT` in SQL |
| 22 | `wcs-no-limit` | WC Subscriptions no limits | 3939-4000 | Medium | Check for `number` param |
| 31 | `query-limit-multiplier` | Query limit multipliers | 4496-4563 | Medium | Heuristic: count*N patterns |

**Estimated effort:** 10 × 20 min = 3.33 hours

### 2.2 Multi-Step Detection (4 rules)

| # | Rule ID | Title | Lines | Complexity | Notes |
|---|---------|-------|-------|------------|-------|
| 5 | `superglobal-manipulation` | Direct superglobal manipulation | 2856-2952 | High | Filter out comments, check assignment |
| 12 | `wpdb-unprepared-query` | DB queries without prepare | 3181-3297 | High | Check for `$wpdb->prepare()` usage |
| 25 | `pre-get-posts-unbounded` | pre_get_posts forcing unbounded | 4147-4183 | Medium | Hook + set() detection |
| 36 | `like-leading-wildcard` | LIKE with leading wildcards | 4859-4959 | Medium | Meta_query LIKE detection |

**Estimated effort:** 4 × 25 min = 1.67 hours

### 2.3 JavaScript/AJAX Patterns (3 rules)

| # | Rule ID | Title | Lines | Complexity | Notes |
|---|---------|-------|-------|------------|-------|
| 14 | `ajax-polling-unbounded` | Unbounded AJAX polling | 3434-3493 | Medium | setInterval + fetch detection |
| 15 | `hcc-005-expensive-polling` | Expensive WP in polling | 3497-3558 | Medium | Context-aware polling check |
| 16 | `rest-no-pagination` | REST without pagination | 3562-3620 | Medium | register_rest_route analysis |

**Estimated effort:** 3 × 20 min = 1 hour

### 2.4 Loop Detection (2 rules)

| # | Rule ID | Title | Lines | Complexity | Notes |
|---|---------|-------|-------|------------|-------|
| 37 | `n1-meta-in-loop` | N+1 meta in loops | 4963-5016 | Medium | Loop + meta detection |
| 45 | `http-no-timeout` | HTTP without timeout | 5483-5575 | Medium | wp_remote_* context check |

**Estimated effort:** 2 × 20 min = 0.67 hours

---

## Migration Strategy

### Phase 3.1: Simple Patterns (Category 1)
1. Start with `php-short-tags` (simplest, two patterns)
2. Migrate `timezone-sensitive-patterns`
3. Migrate `transient-no-expiration`
4. Migrate `script-version-time`
5. Migrate `array-merge-in-loop`

**Estimated: 1.25 hours**

### Phase 3.2: Scripted Validators (Category 2)
1. Create validator framework for context-aware checks
2. Migrate mitigation detection rules (10 rules)
3. Migrate multi-step detection rules (4 rules)
4. Migrate JavaScript/AJAX patterns (3 rules)
5. Migrate loop detection rules (2 rules)

**Estimated: 6.67 hours**

---

## Total Effort Estimate

- **Category 1 (Simple):** 1.25 hours
- **Category 2 (Context-aware):** 6.67 hours
- **Total:** ~8 hours (vs original estimate of 5.25 hours)

**Note:** Original estimate was too optimistic. T2 rules are more complex than initially assessed.

---

## Next Steps

1. ✅ Complete this categorization
2. ⏳ Start with Phase 3.1 (simple patterns)
3. ⏳ Design validator framework for Phase 3.2
4. ⏳ Implement and test each migration

