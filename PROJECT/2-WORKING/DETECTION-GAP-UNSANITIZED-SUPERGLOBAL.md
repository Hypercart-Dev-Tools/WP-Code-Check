# Detection Gap: Unsanitized Superglobal Read

**Created:** 2026-01-29  
**Status:** In Progress  
**Priority:** HIGH  
**Assigned Version:** v2.2.3

## Problem Statement

WPCC reported **"Unsanitized superglobal read ($_GET/$_POST)" as PASSED** when the codebase contains raw `$_POST` usage without sanitization.

**User-Reported Cases:**
1. **Line 660**: `$keyword = $_POST['keyword'];` - No isset(), no sanitization
2. **Line 930**: `$selected_value = isset( $_GET['wholesale_sales_rep'] ) ? $_GET['wholesale_sales_rep'] : '';` - isset() present but no sanitization

**Scanned:** Universal Child Theme 2024 (~12K LOC)  
**WPCC Version:** 2.0.14

## Current Implementation Analysis

### Pattern JSON (`dist/patterns/unsanitized-superglobal-read.json`)
- **Detection type**: `"direct"`
- **Search pattern**: `\\$_(GET|POST|REQUEST)\\[`
- **Exclude patterns**: Includes `"isset\\("` and `"empty\\("` in the JSON

### Actual Implementation (`check-performance.sh` lines 3607-3648)

**Phase 1: Initial grep** (lines 3614-3623)
```bash
UNSANITIZED_MATCHES=$(cached_grep --include=*.php -E '\$_(GET|POST|REQUEST)\[' | \
  grep -v 'sanitize_' | \
  grep -v 'esc_' | \
  grep -v 'absint' | \
  grep -v 'intval' | \
  grep -v 'floatval' | \
  grep -v 'wc_clean' | \
  grep -v 'wp_unslash' | \
  grep -v '\$allowed_keys' | \
  grep -v '//.*\$_' || true)
```

**Phase 2: isset/empty filter** (lines 3628-3648)
```bash
# If isset/empty is present AND superglobal appears only once, skip it
if echo "$code" | grep -q 'isset\|empty'; then
  if [ "$superglobal_count" -eq 1 ]; then
    continue  # Skip - likely just existence check
  fi
fi
```

## Expected Behavior vs Actual

### Line 660: `$keyword = $_POST['keyword'];`

**Expected:**
- Initial grep: ✅ MATCH (has `$_POST[`)
- Sanitization filter: ✅ PASS (no sanitize_ functions)
- isset/empty filter: ✅ PASS (no isset/empty, so doesn't skip)
- **Result: SHOULD FLAG** ✅

**Actual (user reports):**
- **Result: NOT FLAGGED** ❌

### Line 930: `$selected_value = isset( $_GET['wholesale_sales_rep'] ) ? $_GET['wholesale_sales_rep'] : '';`

**Expected:**
- Initial grep: ✅ MATCH (has `$_GET[`)
- Sanitization filter: ✅ PASS (no sanitize_ functions)
- isset/empty filter: 
  - Has isset: YES
  - Superglobal count: 2 (appears twice in ternary)
  - Count > 1, so does NOT skip
- **Result: SHOULD FLAG** ✅

**Actual (user reports):**
- **Result: NOT FLAGGED** ❌

## Hypothesis: Why Are They Being Missed?

### Possible Causes

1. **Comment filter** (line 3662): Line might be in a comment block
2. **HTML/REST config filter** (line 3667): Line might match HTML form pattern
3. **Suppression rule** (line 3671): File might have suppression comment
4. **Pattern JSON exclude_patterns**: The JSON has `"isset\\("` which might be applied differently
5. **Bug in isset/empty logic**: Logic might not be working as expected

## Next Steps

- [ ] Get actual file path from user to examine line 660 in context
- [ ] Check if line is in comment block or has suppression
- [ ] Verify isset/empty filter logic with actual test cases
- [ ] Determine if pattern JSON exclude_patterns are overriding the script logic
- [ ] Create fix based on root cause

## Proposed Solution (Pending Root Cause)

### Option A: Fix grep logic
Update the isset/empty filter to properly handle ternary operators

### Option B: Create validator script
Similar to `wc-coupon-thankyou-context-validator.sh`, create context-aware validation

### Option C: Update pattern JSON
Remove `"isset\\("` and `"empty\\("` from exclude_patterns in JSON

## Test Fixtures Created

- `temp/test-unsanitized-assignment.php` - User-reported scenarios
- `temp/test-isset-filter.sh` - Logic testing script (needs debugging)

## Related Files

- `dist/patterns/unsanitized-superglobal-read.json`
- `dist/bin/check-performance.sh` (lines 3607-3750)

