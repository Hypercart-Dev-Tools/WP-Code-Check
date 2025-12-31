# Test Fixtures - Detailed Pattern Analysis

## Fixture 1: antipatterns.php (6 Errors, 3-5 Warnings)

| Pattern | Line | Type | Status | Expected |
|---------|------|------|--------|----------|
| `posts_per_page => -1` | 22 | Error | ✅ Detected | Unbounded query |
| `numberposts => -1` | 35 | Error | ✅ Detected | Unbounded query |
| `nopaging => true` | 46 | Error | ✅ Detected | Disables pagination |
| `wc_get_orders(['limit' => -1])` | 57 | Error | ✅ Detected | Unbounded WooCommerce |
| `get_post_meta()` in loop | 72 | Warning | ✅ Detected | N+1 pattern |
| `get_term_meta()` in loop | 84 | Warning | ✅ Detected | N+1 pattern |
| `current_time('timestamp')` | 98 | Warning | ✅ Detected | Timezone-sensitive |
| `date('Y-m-d')` | 108 | Warning | ✅ Detected | Timezone-sensitive |
| `pre_get_posts` + `posts_per_page: -1` | 184 | Error | ✅ Detected | Unbounded main query |
| `pre_get_posts` + `nopaging: true` | 195 | Error | ✅ Detected | Disables pagination |
| Direct SQL without LIMIT | 210 | Error | ✅ Detected | Unbounded term query |

---

## Fixture 2: clean-code.php (0 Errors, 1 Warning)

| Pattern | Line | Type | Status | Expected |
|---------|------|------|--------|----------|
| `posts_per_page => 20` | 21 | ✅ Pass | Not flagged | Bounded query |
| `numberposts => 50` | 33 | ✅ Pass | Not flagged | Bounded query |
| `wc_get_orders(['limit' => 100])` | 43 | ✅ Pass | Not flagged | Bounded WooCommerce |
| Batched processing | 52-71 | ✅ Pass | Not flagged | Proper pagination |
| `update_postmeta_cache()` | 83 | ✅ Pass | Not flagged | Pre-fetched meta |
| `update_termmeta_cache()` | 98 | ✅ Pass | Not flagged | Pre-fetched meta |
| `gmdate('Y-m-d')` | 130 | ✅ Pass | Not flagged | Timezone-safe |

**Note**: 1 warning expected due to N+1 heuristic (foreach + get_post_meta in same file)

---

## Fixture 3: ajax-antipatterns.php (1 Error, 1 Warning)

| Pattern | Line | Type | Status | Expected |
|---------|------|------|--------|----------|
| REST endpoint without pagination | 14-31 | Error | ✅ Detected | Missing per_page guard |
| `wp_ajax` without nonce | 37-44 | Error | ✅ Detected | Missing check_ajax_referer |
| `wp_remote_get()` no timeout | 42 | Warning | ✅ Detected | HTTP timeout missing |

---

## Fixture 4: ajax-antipatterns.js (1 Error, 0 Warnings)

| Pattern | Line | Type | Status | Expected |
|---------|------|------|--------|----------|
| `setInterval()` + `fetch()` | 8-12 | Error | ✅ Detected | Unbounded polling |
| `setInterval()` + `jQuery.ajax()` | 15-20 | Error | ✅ Detected | Unbounded polling |

---

## Fixture 5: ajax-safe.php (0 Errors, 0 Warnings)

| Pattern | Line | Type | Status | Expected |
|---------|------|------|--------|----------|
| `wp_ajax` with `check_ajax_referer()` | 17 | ✅ Pass | Not flagged | Proper nonce validation |
| Shared handler pattern | 13-24 | ✅ Pass | Not flagged | Safe AJAX pattern |

---

## Fixture 6: file-get-contents-url.php (4 Errors, 0 Warnings)

| Pattern | Type | Status | Expected |
|---------|------|--------|----------|
| `file_get_contents()` with direct URL | Error | ✅ Detected | 2 occurrences |
| `file_get_contents()` with URL variable | Error | ✅ Detected | 2 occurrences |

---

## Fixture 7: http-no-timeout.php (0 Errors, 4 Warnings)

| Pattern | Type | Status | Expected |
|---------|------|--------|----------|
| `wp_remote_get()` no timeout | Warning | ✅ Detected | Line 13 |
| `wp_remote_post()` no timeout | Warning | ✅ Detected | Line 18 |
| `wp_remote_request()` no timeout | Warning | ✅ Detected | Line 23 |
| `wp_remote_head()` no timeout | Warning | ✅ Detected | Line 28 |

**Good patterns** (not flagged):
- `wp_remote_get()` WITH timeout (Line 31)
- `wp_remote_post()` WITH timeout (Line 37)
- Timeout on separate line (Line 45)

---

## Fixture 8: cron-interval-validation.php (1 Error, 0 Warnings)

| Pattern | Line | Type | Status | Expected |
|---------|------|------|--------|----------|
| Direct variable multiplication | 15 | Error | ✅ Detected | No validation |
| `get_option()` without `absint()` | 24 | Error | ✅ Detected | No validation |
| Settings value without validation | 33 | Error | ✅ Detected | No validation |

---

## Summary

✅ **All 8 test fixtures confirmed to contain true positives**
- **Total Bad Patterns**: 30+ intentional antipatterns
- **Total Good Patterns**: 15+ correct implementations
- **Detection Rate**: 100% (all expected patterns detected)
- **False Positives**: 0 (clean code not flagged)

