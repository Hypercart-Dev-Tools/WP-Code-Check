# Fix: File Path with Spaces Bug - All Affected Patterns

**Date:** 2026-01-02  
**Priority:** HIGH  
**Target Version:** 1.0.77  
**Estimated Effort:** 1-2 hours

---

## Summary

**4 patterns** in `check-performance.sh` use unquoted `for file in $FILES` loops, causing failures when file paths contain spaces.

---

## Affected Patterns

| Line | Pattern | Severity | Status |
|------|---------|----------|--------|
| 2374 | AJAX handlers without nonce | HIGH | ❌ Needs fix |
| 2577 | get_terms() without limit | CRITICAL | ❌ Needs fix |
| 2618 | pre_get_posts unbounded | CRITICAL | ❌ Needs fix |
| 2720 | Cron interval validation | HIGH | ❌ Needs fix |

---

## Fix Strategy

### Option 1: while IFS= read -r (Recommended)

**Pros:**
- ✅ Handles spaces, newlines, special characters
- ✅ Standard bash best practice
- ✅ Easy to understand and maintain

**Cons:**
- ⚠️ Slightly more verbose than `for` loop

### Option 2: Use grep -Z with null-byte separation

**Pros:**
- ✅ Maximum safety (handles all edge cases)
- ✅ Industry standard for file iteration

**Cons:**
- ⚠️ Requires `-Z` flag support in grep
- ⚠️ More complex syntax

**Recommendation:** Use Option 1 for consistency and readability.

---

## Implementation

### Pattern 1: AJAX Handlers (Line 2374)

**Current Code:**
```bash
AJAX_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "wp_ajax" "$PATHS" 2>/dev/null || true)
if [ -n "$AJAX_FILES" ]; then
  for file in $AJAX_FILES; do
    hook_count=$(grep -E "wp_ajax" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')
    nonce_count=$(grep -E "check_ajax_referer[[:space:]]*\\(|wp_verify_nonce[[:space:]]*\\(" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')
    # ... rest of logic
  done
fi
```

**Fixed Code:**
```bash
AJAX_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "wp_ajax" "$PATHS" 2>/dev/null || true)
if [ -n "$AJAX_FILES" ]; then
  echo "$AJAX_FILES" | while IFS= read -r file; do
    hook_count=$(grep -E "wp_ajax" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')
    nonce_count=$(grep -E "check_ajax_referer[[:space:]]*\\(|wp_verify_nonce[[:space:]]*\\(" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')
    # ... rest of logic
  done
fi
```

---

### Pattern 2: get_terms() (Line 2577)

**Current Code:**
```bash
TERMS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "get_terms[[:space:]]*(" "$PATHS" 2>/dev/null || true)
TERMS_UNBOUNDED=false
TERMS_FINDING_COUNT=0
if [ -n "$TERMS_FILES" ]; then
  for file in $TERMS_FILES; do
    if ! grep -A5 "get_terms[[:space:]]*(" "$file" 2>/dev/null | grep -q -e "'number'" -e '"number"'; then
      if ! should_suppress_finding "get-terms-no-limit" "$file"; then
        text_echo "  $file: get_terms() may be missing 'number' parameter"
        lineno=$(grep -n "get_terms[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        add_json_finding "get-terms-no-limit" "error" "$TERMS_SEVERITY" "$file" "${lineno:-0}" "get_terms() may be missing 'number' parameter" "get_terms("
        TERMS_UNBOUNDED=true
        ((TERMS_FINDING_COUNT++))
      fi
    fi
  done
fi
```

**Fixed Code:**
```bash
TERMS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "get_terms[[:space:]]*(" "$PATHS" 2>/dev/null || true)
TERMS_UNBOUNDED=false
TERMS_FINDING_COUNT=0
if [ -n "$TERMS_FILES" ]; then
  echo "$TERMS_FILES" | while IFS= read -r file; do
    if ! grep -A5 "get_terms[[:space:]]*(" "$file" 2>/dev/null | grep -q -e "'number'" -e '"number"'; then
      if ! should_suppress_finding "get-terms-no-limit" "$file"; then
        text_echo "  $file: get_terms() may be missing 'number' parameter"
        lineno=$(grep -n "get_terms[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        add_json_finding "get-terms-no-limit" "error" "$TERMS_SEVERITY" "$file" "${lineno:-0}" "get_terms() may be missing 'number' parameter" "get_terms("
        TERMS_UNBOUNDED=true
        ((TERMS_FINDING_COUNT++))
      fi
    fi
  done
fi
```

---

### Pattern 3: pre_get_posts (Line 2618)

**Current Code:**
```bash
PRE_GET_POSTS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "add_action.*pre_get_posts\|add_filter.*pre_get_posts" "$PATHS" 2>/dev/null || true)
if [ -n "$PRE_GET_POSTS_FILES" ]; then
  for file in $PRE_GET_POSTS_FILES; do
    if grep -q "set[[:space:]]*([[:space:]]*['\"]posts_per_page['\"][[:space:]]*,[[:space:]]*-1" "$file" 2>/dev/null || \
       grep -q "set[[:space:]]*([[:space:]]*['\"]nopaging['\"][[:space:]]*,[[:space:]]*true" "$file" 2>/dev/null; then
      # ... rest of logic
    fi
  done
fi
```

**Fixed Code:**
```bash
PRE_GET_POSTS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "add_action.*pre_get_posts\|add_filter.*pre_get_posts" "$PATHS" 2>/dev/null || true)
if [ -n "$PRE_GET_POSTS_FILES" ]; then
  echo "$PRE_GET_POSTS_FILES" | while IFS= read -r file; do
    if grep -q "set[[:space:]]*([[:space:]]*['\"]posts_per_page['\"][[:space:]]*,[[:space:]]*-1" "$file" 2>/dev/null || \
       grep -q "set[[:space:]]*([[:space:]]*['\"]nopaging['\"][[:space:]]*,[[:space:]]*true" "$file" 2>/dev/null; then
      # ... rest of logic
    fi
  done
fi
```

---

### Pattern 4: Cron Interval (Line 2720)

**Current Code:**
```bash
CRON_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "wp_schedule_event\|wp_schedule_single_event\|cron_schedules" "$PATHS" 2>/dev/null || true)
if [ -n "$CRON_FILES" ]; then
  for file in $CRON_FILES; do
    # Look for 'interval' => $variable * 60 or $variable * MINUTE_IN_SECONDS patterns
    # ... rest of logic
  done
fi
```

**Fixed Code:**
```bash
CRON_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "wp_schedule_event\|wp_schedule_single_event\|cron_schedules" "$PATHS" 2>/dev/null || true)
if [ -n "$CRON_FILES" ]; then
  echo "$CRON_FILES" | while IFS= read -r file; do
    # Look for 'interval' => $variable * 60 or $variable * MINUTE_IN_SECONDS patterns
    # ... rest of logic
  done
fi
```

---

## Testing Plan

### Test Case 1: File Path with Spaces

**Setup:**
```bash
mkdir -p "/tmp/test path with spaces"
cat > "/tmp/test path with spaces/test.php" << 'EOF'
<?php
// Test get_terms without number
$terms = get_terms('category');

// Test AJAX without nonce
add_action('wp_ajax_test', 'test_ajax');

// Test pre_get_posts unbounded
add_action('pre_get_posts', function($query) {
    $query->set('posts_per_page', -1);
});

// Test cron interval
wp_schedule_event(time(), 'custom_interval', 'my_hook');
EOF
```

**Run Scanner:**
```bash
./bin/check-performance.sh --paths "/tmp/test path with spaces" --format json
```

**Expected Results:**
- ✅ All 4 patterns detected
- ✅ Correct file path in JSON output
- ✅ Correct line numbers (not 0)
- ✅ No truncated paths

---

## Files to Modify

| File | Lines to Change | Description |
|------|-----------------|-------------|
| `dist/bin/check-performance.sh` | 2374 | Fix AJAX loop |
| `dist/bin/check-performance.sh` | 2577 | Fix get_terms loop |
| `dist/bin/check-performance.sh` | 2618 | Fix pre_get_posts loop |
| `dist/bin/check-performance.sh` | 2720 | Fix cron interval loop |

---

## Checklist

- [ ] Fix line 2374 (AJAX handlers)
- [ ] Fix line 2577 (get_terms)
- [ ] Fix line 2618 (pre_get_posts)
- [ ] Fix line 2720 (cron interval)
- [ ] Test with file paths containing spaces
- [ ] Test with file paths without spaces (regression test)
- [ ] Update CHANGELOG.md (version 1.0.77)
- [ ] Update version number in check-performance.sh
- [ ] Run full test suite
- [ ] Document fix in SAFEGUARDS.md

---

**Fix Document Created:** 2026-01-02  
**Ready for Implementation:** Yes  
**Estimated Time:** 1-2 hours

