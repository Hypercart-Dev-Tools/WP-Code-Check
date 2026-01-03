# Test Fixtures Verification Report

## Overview
This document confirms that all test fixtures in the WP Code Check project contain **true positives** (intentional bad patterns) and **true negatives** (correct patterns).

---

## Test Fixtures Summary

### 1. **antipatterns.php** ✅
**Expected Results**: 6 Errors, 3-5 Warnings

**Bad Patterns Detected**:
- ✅ `posts_per_page => -1` (Line 22) - Unbounded query
- ✅ `numberposts => -1` (Line 35) - Unbounded query
- ✅ `nopaging => true` (Line 46) - Disables pagination
- ✅ `wc_get_orders(['limit' => -1])` (Line 57) - Unbounded WooCommerce query
- ✅ `get_post_meta()` in loop (Line 72) - N+1 query pattern
- ✅ `get_term_meta()` in loop (Line 84) - N+1 query pattern
- ✅ `current_time('timestamp')` (Line 98) - Timezone-sensitive pattern
- ✅ `date()` function (Line 108) - Timezone-sensitive pattern
- ✅ `pre_get_posts` with `posts_per_page => -1` (Line 184) - Unbounded main query
- ✅ `pre_get_posts` with `nopaging => true` (Line 195) - Disables pagination
- ✅ Direct SQL without LIMIT (Line 210) - Unbounded term query

---

### 2. **clean-code.php** ✅
**Expected Results**: 0 Errors, 1 Warning (N+1 heuristic)

**Good Patterns**:
- ✅ `posts_per_page => 20` (Line 21) - Bounded query
- ✅ `numberposts => 50` (Line 33) - Bounded query
- ✅ `wc_get_orders(['limit' => 100])` (Line 43) - Bounded WooCommerce query
- ✅ Batched processing with pagination (Lines 52-71)
- ✅ Pre-fetched meta with `update_postmeta_cache()` (Line 83)
- ✅ Pre-fetched term meta with `update_termmeta_cache()` (Line 98)
- ✅ Timezone-safe patterns with `gmdate()` (Line 130)

---

### 3. **ajax-antipatterns.php** ✅
**Expected Results**: 1 Error, 1 Warning

**Bad Patterns**:
- ✅ REST endpoint without pagination guard (Lines 14-31)
- ✅ `wp_ajax` handler without nonce validation (Lines 37-44)
- ✅ `wp_remote_get()` without timeout (Line 42) - HTTP timeout warning

---

### 4. **ajax-antipatterns.js** ✅
**Expected Results**: 1 Error, 0 Warnings

**Bad Patterns**:
- ✅ `setInterval()` with `fetch()` (Lines 8-12) - Unbounded polling
- ✅ `setInterval()` with `jQuery.ajax()` (Lines 15-20) - Unbounded polling

---

### 5. **ajax-safe.php** ✅
**Expected Results**: 0 Errors, 0 Warnings

**Good Patterns**:
- ✅ `wp_ajax` handler with `check_ajax_referer()` (Line 53)
- ✅ Proper nonce validation (Line 17)

---

### 6. **file-get-contents-url.php** ✅
**Expected Results**: 4 Errors, 0 Warnings

**Bad Patterns**:
- ✅ `file_get_contents()` with direct URL (2 occurrences)
- ✅ `file_get_contents()` with URL variable (2 occurrences)

---

### 7. **http-no-timeout.php** ✅
**Expected Results**: 0 Errors, 4 Warnings

**Bad Patterns**:
- ✅ `wp_remote_get()` without timeout (Line 13)
- ✅ `wp_remote_post()` without timeout (Line 18)
- ✅ `wp_remote_request()` without timeout (Line 23)
- ✅ `wp_remote_head()` without timeout (Line 28)

**Good Patterns**:
- ✅ `wp_remote_get()` with timeout (Line 31)
- ✅ `wp_remote_post()` with timeout (Line 37)
- ✅ Timeout on separate line (Line 45)

---

### 8. **cron-interval-validation.php** ✅
**Expected Results**: 1 Error, 0 Warnings

**Bad Patterns**:
- ✅ Direct variable multiplication without validation (Line 15)
- ✅ `get_option()` without `absint()` (Line 24)
- ✅ Settings value without validation (Line 33)

---

## Conclusion

✅ **All test fixtures are confirmed to contain true positives and true negatives.**

The test suite validates that the scanner:
1. **Correctly detects** intentional bad patterns (antipatterns)
2. **Correctly ignores** safe patterns (clean code)
3. **Maintains regression prevention** for AJAX, REST, and HTTP patterns
4. **Provides accurate error/warning counts** for each fixture

**Test Status**: Ready for validation

