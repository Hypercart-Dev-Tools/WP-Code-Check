# Bug Report: get_terms() Detection - File Path with Spaces Issue

**Date:** 2026-01-02  
**Severity:** HIGH  
**Status:** CONFIRMED  
**Affects:** Scanner version 1.0.76

---

## Summary

The `get_terms()` detection pattern fails to correctly parse file paths containing spaces, resulting in:
1. **Line numbers showing as 0** in JSON output
2. **File paths being truncated** at the first space
3. **Incorrect findings** being reported

---

## Root Cause

**File:** `dist/bin/check-performance.sh`  
**Lines:** 2577-2591

### Problematic Code

```bash
TERMS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "get_terms[[:space:]]*(" "$PATHS" 2>/dev/null || true)
TERMS_UNBOUNDED=false
TERMS_FINDING_COUNT=0
if [ -n "$TERMS_FILES" ]; then
  for file in $TERMS_FILES; do  # ❌ BUG: Unquoted variable splits on spaces
    # Check if file has get_terms without 'number' or "number" nearby (within 5 lines)
    # Support both single and double quotes
    if ! grep -A5 "get_terms[[:space:]]*(" "$file" 2>/dev/null | grep -q -e "'number'" -e '"number"'; then
      # Apply baseline suppression per file
      if ! should_suppress_finding "get-terms-no-limit" "$file"; then
        text_echo "  $file: get_terms() may be missing 'number' parameter"
        # Get line number for JSON
        lineno=$(grep -n "get_terms[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        add_json_finding "get-terms-no-limit" "error" "$TERMS_SEVERITY" "$file" "${lineno:-0}" "get_terms() may be missing 'number' parameter" "get_terms("
        TERMS_UNBOUNDED=true
        ((TERMS_FINDING_COUNT++))
      fi
    fi
  done
fi
```

### The Problem

**Line 2577:** `for file in $TERMS_FILES; do`

When `$TERMS_FILES` is **not quoted**, bash splits the variable on whitespace (spaces, tabs, newlines). This causes file paths with spaces to be split into multiple tokens.

**Example:**

```bash
# Actual file path:
/Users/noelsaw/Local Sites/1-bloomzhemp-production-sync-07-24/app/public/wp-content/plugins/woocommerce-all-products-for-subscriptions/includes/admin/class-wcs-att-admin.php

# What bash sees (unquoted):
Token 1: /Users/noelsaw/Local
Token 2: Sites/1-bloomzhemp-production-sync-07-24/app/public/wp-content/plugins/woocommerce-all-products-for-subscriptions/includes/admin/class-wcs-att-admin.php
```

### Why Line Numbers Show as 0

When the loop processes `/Users/noelsaw/Local` (truncated path):
1. `grep -n "get_terms[[:space:]]*(" "$file"` fails (file doesn't exist)
2. `lineno` is empty
3. `${lineno:-0}` defaults to 0
4. JSON output shows `"line": 0`

---

## Evidence

### Scan Output (JSON)

```json
{
  "id": "get-terms-no-limit",
  "severity": "error",
  "impact": "CRITICAL",
  "file": "/Users/noelsaw/Local",
  "line": 0,
  "message": "get_terms() may be missing 'number' parameter",
  "code": "get_terms("
}
```

### Actual File Location

```bash
$ grep -rn "get_terms[[:space:]]*(" "/Users/noelsaw/Local Sites/1-bloomzhemp-production-sync-07-24/app/public/wp-content/plugins/woocommerce-all-products-for-subscriptions" | head -1

/Users/noelsaw/Local Sites/1-bloomzhemp-production-sync-07-24/app/public/wp-content/plugins/woocommerce-all-products-for-subscriptions/includes/admin/class-wcs-att-admin.php:259:		$category_terms   = get_terms( 'product_cat', array( 'hide_empty' => 0 ) );
```

**Correct line number:** 259  
**Reported line number:** 0

---

## Impact

### Severity: HIGH

1. **False Positives:** Truncated paths may not exist, causing grep to fail
2. **Missing Line Numbers:** All findings show line 0, making debugging difficult
3. **Incorrect File Paths:** JSON output contains invalid file paths
4. **User Confusion:** Developers can't locate the actual issue in their code

### Affected Patterns

This bug affects **any pattern** that uses a similar loop structure with unquoted variables:

**Confirmed Affected:**
- ✅ `get_terms()` detection (lines 2577-2591)

**Potentially Affected (need verification):**
- ⚠️ `get_users()` detection
- ⚠️ N+1 file-level detection
- ⚠️ Any other pattern using `for file in $FILES`

---

## Solution

### Fix: Quote the Variable

**Change line 2577 from:**
```bash
for file in $TERMS_FILES; do
```

**To:**
```bash
while IFS= read -r file; do
```

**And change the loop structure:**

```bash
if [ -n "$TERMS_FILES" ]; then
  echo "$TERMS_FILES" | while IFS= read -r file; do
    # Check if file has get_terms without 'number' or "number" nearby (within 5 lines)
    # Support both single and double quotes
    if ! grep -A5 "get_terms[[:space:]]*(" "$file" 2>/dev/null | grep -q -e "'number'" -e '"number"'; then
      # Apply baseline suppression per file
      if ! should_suppress_finding "get-terms-no-limit" "$file"; then
        text_echo "  $file: get_terms() may be missing 'number' parameter"
        # Get line number for JSON
        lineno=$(grep -n "get_terms[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        add_json_finding "get-terms-no-limit" "error" "$TERMS_SEVERITY" "$file" "${lineno:-0}" "get_terms() may be missing 'number' parameter" "get_terms("
        TERMS_UNBOUNDED=true
        ((TERMS_FINDING_COUNT++))
      fi
    fi
  done
fi
```

### Why This Works

- `while IFS= read -r file` reads one line at a time
- `IFS=` prevents trimming of leading/trailing whitespace
- `-r` prevents backslash interpretation
- `echo "$TERMS_FILES"` (quoted) preserves newlines
- Each file path is processed as a single unit, regardless of spaces

---

## Alternative Solution (Simpler)

Use `grep -rl` with `xargs` and proper null-byte separation:

```bash
grep -rlZ $EXCLUDE_ARGS --include="*.php" -e "get_terms[[:space:]]*(" "$PATHS" 2>/dev/null | while IFS= read -r -d '' file; do
  # ... rest of the logic
done
```

This uses:
- `-Z` flag to output null-terminated file names
- `read -d ''` to read null-terminated strings
- Handles spaces, newlines, and special characters correctly

---

## Testing

### Test Case 1: File Path with Spaces

**Setup:**
```bash
mkdir -p "/tmp/test path with spaces"
echo "<?php get_terms('category');" > "/tmp/test path with spaces/test.php"
```

**Expected:**
- File path: `/tmp/test path with spaces/test.php`
- Line number: 1
- Detection: Success

**Current Behavior:**
- File path: `/tmp/test` (truncated)
- Line number: 0
- Detection: Fails

### Test Case 2: File Path without Spaces

**Setup:**
```bash
mkdir -p "/tmp/testpath"
echo "<?php get_terms('category');" > "/tmp/testpath/test.php"
```

**Expected:**
- File path: `/tmp/testpath/test.php`
- Line number: 1
- Detection: Success

**Current Behavior:**
- File path: `/tmp/testpath/test.php`
- Line number: 1
- Detection: Success ✅

---

## Recommended Actions

### Immediate (High Priority)

1. **Fix `get_terms()` detection** (lines 2577-2591)
2. **Audit all similar patterns** in `check-performance.sh`
3. **Add test case** for file paths with spaces
4. **Update SAFEGUARDS.md** with this finding

### Medium Priority

5. **Review all `for file in $FILES` loops** in the codebase
6. **Standardize on `while IFS= read -r` pattern** for file iteration
7. **Add shellcheck** to CI/CD pipeline to catch these issues

### Low Priority

8. **Document best practices** for bash file iteration
9. **Create helper function** for safe file iteration
10. **Add automated tests** for edge cases (spaces, special chars, etc.)

---

## Related Issues

### Similar Patterns in Codebase

**Search for potential issues:**
```bash
grep -n "for file in \$" dist/bin/check-performance.sh
```

**Expected findings:**
- Line 2577: `get_terms()` detection ❌ (confirmed bug)
- Other patterns may exist

---

## References

### Bash Best Practices

1. **Always quote variables** when iterating over file paths
2. **Use `while IFS= read -r`** instead of `for file in $FILES`
3. **Use null-byte separation** (`-Z` and `read -d ''`) for maximum safety
4. **Test with edge cases:** spaces, newlines, special characters

### Related Documentation

- [SAFEGUARDS.md](../SAFEGUARDS.md) - Documents path quoting requirements
- [Bash Pitfalls](https://mywiki.wooledge.org/BashPitfalls) - Common bash mistakes

---

## Conclusion

This is a **high-severity bug** that affects the accuracy and usability of the scanner when scanning projects in directories with spaces (common on macOS with "Local Sites", "My Documents", etc.).

**Recommendation:** Fix immediately and include in next release (1.0.77).

---

**Bug Report Created:** 2026-01-02  
**Reporter:** AI Agent  
**Priority:** HIGH  
**Target Fix Version:** 1.0.77

