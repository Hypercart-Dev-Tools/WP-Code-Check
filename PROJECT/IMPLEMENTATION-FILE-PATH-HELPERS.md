# Implementation: Centralized File Path Helper Functions

**Date:** 2026-01-02  
**Priority:** HIGH  
**Target Version:** 1.0.77  
**Estimated Effort:** 2-3 hours

---

## Summary

Centralize all file path handling into reusable helper functions in `dist/bin/lib/common-helpers.sh` to solve:

1. ✅ **File paths with spaces** breaking loops
2. ✅ **URL encoding** for `file://` links in HTML reports
3. ✅ **HTML escaping** for display text
4. ✅ **Consistent handling** across all patterns

---

## Current Issues

### Issue 1: Unquoted Variables in Loops (4 occurrences)

**Problem:** `for file in $FILES` splits on spaces

**Affected Lines:**
- Line 2374: AJAX handlers
- Line 2577: get_terms()
- Line 2618: pre_get_posts
- Line 2720: Cron interval

**Example:**
```bash
# Current (broken):
for file in $AJAX_FILES; do
  # Splits "/Users/noelsaw/Local Sites/..." into multiple tokens
done
```

---

### Issue 2: Inconsistent URL Encoding

**Problem:** `url_encode()` exists but not used consistently

**Current Implementation (line 221-227):**
```bash
# URL-encode a string for file:// links
url_encode() {
  local str="$1"
  # Use jq's @uri filter for robust RFC 3986 encoding
  str=$(printf '%s' "$str" | jq -sRr @uri)
  printf '%s' "$str"
}
```

**Used in:**
- Line 779: Paths link encoding
- Line 789: JSON log path encoding
- Line 875: Finding file path encoding (via jq)

---

### Issue 3: Inconsistent HTML Escaping

**Problem:** HTML escaping done inline with sed

**Current Implementation (line 783):**
```bash
local escaped_abs_path=$(echo "$abs_path" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
```

**Used in:**
- Line 783: Paths display text
- Line 790: JSON log display text
- Line 876: Code snippet escaping (via jq)

---

## Solution: Centralized Helper Functions

### File: `dist/bin/lib/common-helpers.sh`

Add the following helper functions:

```bash
# ============================================================
# FILE PATH HANDLING HELPERS
# ============================================================

# Safely iterate over newline-separated file paths (handles spaces)
# Usage: safe_file_iterator "$FILES_LIST" | while IFS= read -r file; do ... done
# Returns: Stream of file paths, one per line
safe_file_iterator() {
  local files="$1"
  if [ -n "$files" ]; then
    printf '%s\n' "$files"
  fi
}

# URL-encode a file path for file:// links (RFC 3986)
# Usage: url_encode_path "/path/with spaces/file.php"
# Returns: /path/with%20spaces/file.php
url_encode_path() {
  local path="$1"
  # Use jq's @uri filter for robust RFC 3986 encoding
  printf '%s' "$path" | jq -sRr @uri
}

# HTML-escape a string for safe display in HTML
# Usage: html_escape_string "Code with <tags> & \"quotes\""
# Returns: Code with &lt;tags&gt; &amp; &quot;quotes&quot;
html_escape_string() {
  local str="$1"
  # Escape HTML special characters
  str="${str//&/&amp;}"   # Must be first to avoid double-escaping
  str="${str//</&lt;}"
  str="${str//>/&gt;}"
  str="${str//\"/&quot;}"
  str="${str//\'/&#39;}"
  printf '%s' "$str"
}

# Create a clickable file:// link for HTML reports
# Usage: create_file_link "/path/to/file.php" "Optional Display Text"
# Returns: <a href="file:///path/to/file.php">Display Text</a>
create_file_link() {
  local file_path="$1"
  local display_text="${2:-$file_path}"  # Use file path as display if not provided
  
  local encoded_path=$(url_encode_path "$file_path")
  local escaped_text=$(html_escape_string "$display_text")
  
  printf '<a href="file://%s" style="color: #667eea; text-decoration: none;" title="Click to open file">%s</a>' \
    "$encoded_path" "$escaped_text"
}

# Create a clickable directory link for HTML reports
# Usage: create_directory_link "/path/to/directory" "Optional Display Text"
# Returns: <a href="file:///path/to/directory">Display Text</a>
create_directory_link() {
  local dir_path="$1"
  local display_text="${2:-$dir_path}"
  
  local encoded_path=$(url_encode_path "$dir_path")
  local escaped_text=$(html_escape_string "$display_text")
  
  printf '<a href="file://%s" style="color: #fff; text-decoration: underline;" title="Click to open directory">%s</a>' \
    "$encoded_path" "$escaped_text"
}

# Validate that a file path exists and is readable
# Usage: if validate_file_path "$file"; then ... fi
# Returns: 0 if valid, 1 if invalid
validate_file_path() {
  local file_path="$1"
  
  if [ -z "$file_path" ]; then
    return 1  # Empty path
  fi
  
  if [ ! -e "$file_path" ]; then
    return 1  # Path doesn't exist
  fi
  
  if [ ! -r "$file_path" ]; then
    return 1  # Path not readable
  fi
  
  return 0  # Valid
}
```

---

## Implementation Plan

### Step 1: Add Helper Functions to common-helpers.sh

**File:** `dist/bin/lib/common-helpers.sh`  
**Action:** Append the helper functions above

---

### Step 2: Fix File Iteration Loops (4 patterns)

#### Pattern 1: AJAX Handlers (Line 2374)

**Before:**
```bash
AJAX_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "wp_ajax" "$PATHS" 2>/dev/null || true)
if [ -n "$AJAX_FILES" ]; then
  for file in $AJAX_FILES; do
    # ... processing logic
  done
fi
```

**After:**
```bash
AJAX_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "wp_ajax" "$PATHS" 2>/dev/null || true)
if [ -n "$AJAX_FILES" ]; then
  safe_file_iterator "$AJAX_FILES" | while IFS= read -r file; do
    # ... processing logic
  done
fi
```

---

#### Pattern 2: get_terms() (Line 2577)

**Before:**
```bash
if [ -n "$TERMS_FILES" ]; then
  for file in $TERMS_FILES; do
    # ... processing logic
  done
fi
```

**After:**
```bash
if [ -n "$TERMS_FILES" ]; then
  safe_file_iterator "$TERMS_FILES" | while IFS= read -r file; do
    # ... processing logic
  done
fi
```

---

#### Pattern 3: pre_get_posts (Line 2618)

**Before:**
```bash
if [ -n "$PRE_GET_POSTS_FILES" ]; then
  for file in $PRE_GET_POSTS_FILES; do
    # ... processing logic
  done
fi
```

**After:**
```bash
if [ -n "$PRE_GET_POSTS_FILES" ]; then
  safe_file_iterator "$PRE_GET_POSTS_FILES" | while IFS= read -r file; do
    # ... processing logic
  done
fi
```

---

#### Pattern 4: Cron Interval (Line 2720)

**Before:**
```bash
if [ -n "$CRON_FILES" ]; then
  for file in $CRON_FILES; do
    # ... processing logic
  done
fi
```

**After:**
```bash
if [ -n "$CRON_FILES" ]; then
  safe_file_iterator "$CRON_FILES" | while IFS= read -r file; do
    # ... processing logic
  done
fi
```

---

### Step 3: Refactor HTML Report Generation

#### Replace Inline URL Encoding (Line 779)

**Before:**
```bash
local encoded_path=$(url_encode "$abs_path")
```

**After:**
```bash
local encoded_path=$(url_encode_path "$abs_path")
```

---

#### Replace Inline HTML Escaping (Line 783)

**Before:**
```bash
local escaped_abs_path=$(echo "$abs_path" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
paths_link="<a href=\"file://$encoded_path\" style=\"color: #fff; text-decoration: underline;\" title=\"Click to open directory\">$escaped_abs_path</a>"
```

**After:**
```bash
paths_link=$(create_directory_link "$abs_path")
```

---

#### Replace JSON Log Link (Line 789-791)

**Before:**
```bash
local encoded_log_path=$(url_encode "$log_file_path")
local escaped_log_path=$(echo "$log_file_path" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
json_log_link="<div style=\"margin-top: 8px;\">JSON Log: <a href=\"file://$encoded_log_path\" style=\"color: #fff; text-decoration: underline;\" title=\"Click to open JSON log file\">$escaped_log_path</a> <button class=\"copy-btn\" onclick=\"copyLogPath()\" title=\"Copy JSON log path to clipboard\">📋 Copy Path</button></div>"
```

**After:**
```bash
local log_link=$(create_file_link "$log_file_path")
json_log_link="<div style=\"margin-top: 8px;\">JSON Log: $log_link <button class=\"copy-btn\" onclick=\"copyLogPath()\" title=\"Copy JSON log path to clipboard\">📋 Copy Path</button></div>"
```

---

### Step 4: Remove Old url_encode() Function

**File:** `dist/bin/check-performance.sh`
**Lines:** 221-227

**Action:** Remove the old `url_encode()` function since it's now in `common-helpers.sh` as `url_encode_path()`

**Before:**
```bash
# URL-encode a string for file:// links
url_encode() {
  local str="$1"
  # Use jq's @uri filter for robust RFC 3986 encoding
  str=$(printf '%s' "$str" | jq -sRr @uri)
  printf '%s' "$str"
}
```

**After:** (Delete these lines)

---

## Benefits

### 1. DRY Principle ✅

- **Single Source of Truth** for file path handling
- **No code duplication** across patterns
- **Easier maintenance** - fix once, works everywhere

### 2. Consistency ✅

- **All patterns use same logic** for file iteration
- **All HTML links use same encoding** method
- **All display text uses same escaping** method

### 3. Testability ✅

- **Helper functions can be unit tested** independently
- **Easier to verify edge cases** (spaces, special chars, etc.)
- **Clear function contracts** with documented inputs/outputs

### 4. Readability ✅

- **Self-documenting code** with descriptive function names
- **Less inline complexity** in main script
- **Easier for new contributors** to understand

### 5. Extensibility ✅

- **Easy to add new helpers** as needs arise
- **Centralized location** for all path-related logic
- **Can add validation, logging, etc.** in one place

---

## Testing Plan

### Test Case 1: File Paths with Spaces

**Setup:**
```bash
mkdir -p "/tmp/test path with spaces"
cat > "/tmp/test path with spaces/test.php" << 'EOF'
<?php
$terms = get_terms('category');
add_action('wp_ajax_test', 'test_ajax');
EOF
```

**Test:**
```bash
./bin/check-performance.sh --paths "/tmp/test path with spaces" --format json
```

**Expected:**
- ✅ All patterns detect issues correctly
- ✅ Line numbers are accurate (not 0)
- ✅ File paths are complete (not truncated)
- ✅ HTML links work when clicked

---

### Test Case 2: Special Characters in Paths

**Setup:**
```bash
mkdir -p "/tmp/test&path<with>special\"chars"
cat > "/tmp/test&path<with>special\"chars/test.php" << 'EOF'
<?php
$terms = get_terms('category');
EOF
```

**Test:**
```bash
./bin/check-performance.sh --paths "/tmp/test&path<with>special\"chars" --format json
```

**Expected:**
- ✅ HTML escaping prevents broken markup
- ✅ URL encoding creates valid file:// links
- ✅ No JavaScript errors in HTML report

---

### Test Case 3: Unicode Characters in Paths

**Setup:**
```bash
mkdir -p "/tmp/test-日本語-path"
cat > "/tmp/test-日本語-path/test.php" << 'EOF'
<?php
$terms = get_terms('category');
EOF
```

**Test:**
```bash
./bin/check-performance.sh --paths "/tmp/test-日本語-path" --format json
```

**Expected:**
- ✅ Unicode characters preserved in display
- ✅ URL encoding handles Unicode correctly
- ✅ Links work in browser

---

### Test Case 4: Regression Test (Normal Paths)

**Setup:**
```bash
mkdir -p "/tmp/normalpath"
cat > "/tmp/normalpath/test.php" << 'EOF'
<?php
$terms = get_terms('category');
EOF
```

**Test:**
```bash
./bin/check-performance.sh --paths "/tmp/normalpath" --format json
```

**Expected:**
- ✅ All existing functionality works
- ✅ No performance degradation
- ✅ Output identical to previous version

---

## Files to Modify

| File | Lines | Action | Priority |
|------|-------|--------|----------|
| `dist/bin/lib/common-helpers.sh` | End of file | Add helper functions | HIGH |
| `dist/bin/check-performance.sh` | 221-227 | Remove old url_encode() | HIGH |
| `dist/bin/check-performance.sh` | 2374 | Fix AJAX loop | HIGH |
| `dist/bin/check-performance.sh` | 2577 | Fix get_terms loop | HIGH |
| `dist/bin/check-performance.sh` | 2618 | Fix pre_get_posts loop | HIGH |
| `dist/bin/check-performance.sh` | 2720 | Fix cron loop | HIGH |
| `dist/bin/check-performance.sh` | 779 | Use url_encode_path() | MEDIUM |
| `dist/bin/check-performance.sh` | 783-784 | Use create_directory_link() | MEDIUM |
| `dist/bin/check-performance.sh` | 789-791 | Use create_file_link() | MEDIUM |
| `CHANGELOG.md` | Top | Add version 1.0.77 entry | HIGH |

---

## Checklist

### Phase 1: Add Helper Functions
- [ ] Add helper functions to `common-helpers.sh`
- [ ] Test helper functions independently
- [ ] Verify jq dependency is available

### Phase 2: Fix File Iteration Loops
- [ ] Fix line 2374 (AJAX handlers)
- [ ] Fix line 2577 (get_terms)
- [ ] Fix line 2618 (pre_get_posts)
- [ ] Fix line 2720 (cron interval)
- [ ] Test with file paths containing spaces

### Phase 3: Refactor HTML Generation
- [ ] Remove old url_encode() function (lines 221-227)
- [ ] Replace line 779 with url_encode_path()
- [ ] Replace lines 783-784 with create_directory_link()
- [ ] Replace lines 789-791 with create_file_link()
- [ ] Test HTML report generation

### Phase 4: Testing
- [ ] Test Case 1: Paths with spaces
- [ ] Test Case 2: Special characters
- [ ] Test Case 3: Unicode characters
- [ ] Test Case 4: Regression test (normal paths)
- [ ] Verify HTML links work in browser
- [ ] Verify JSON output is valid

### Phase 5: Documentation
- [ ] Update CHANGELOG.md (version 1.0.77)
- [ ] Update version number in check-performance.sh
- [ ] Update SAFEGUARDS.md with new helpers
- [ ] Document helper functions in common-helpers.sh

---

## Migration Notes

### Backward Compatibility

✅ **Fully backward compatible** - no breaking changes

- Helper functions are additive (don't remove existing functionality)
- File iteration changes are internal (no API changes)
- HTML output format remains the same
- JSON output format remains the same

### Performance Impact

✅ **Negligible performance impact**

- `safe_file_iterator()` uses `printf` (built-in, fast)
- `url_encode_path()` uses existing jq dependency
- `html_escape_string()` uses bash string substitution (fast)
- No additional external dependencies

### Dependencies

✅ **No new dependencies**

- `jq` already required for JSON processing
- All other functions use bash built-ins
- No additional packages needed

---

## Example Usage

### Before (Inline, Error-Prone)

```bash
# File iteration (broken with spaces)
for file in $FILES; do
  echo "$file"
done

# URL encoding (duplicated)
encoded=$(printf '%s' "$path" | jq -sRr @uri)

# HTML escaping (duplicated)
escaped=$(echo "$text" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

# Creating links (complex, duplicated)
link="<a href=\"file://$encoded\">$escaped</a>"
```

### After (Centralized, Robust)

```bash
# File iteration (handles spaces)
safe_file_iterator "$FILES" | while IFS= read -r file; do
  echo "$file"
done

# URL encoding (centralized)
encoded=$(url_encode_path "$path")

# HTML escaping (centralized)
escaped=$(html_escape_string "$text")

# Creating links (simple, consistent)
link=$(create_file_link "$path" "$display_text")
```

---

## Success Criteria

### Must Have ✅

- [ ] All 4 file iteration loops fixed
- [ ] File paths with spaces handled correctly
- [ ] Line numbers reported accurately (not 0)
- [ ] HTML links work in all browsers
- [ ] All tests pass

### Should Have ✅

- [ ] Old url_encode() removed (no duplication)
- [ ] HTML generation uses helper functions
- [ ] Code is more readable and maintainable
- [ ] Documentation updated

### Nice to Have ✅

- [ ] Additional helper functions for future use
- [ ] Unit tests for helper functions
- [ ] Performance benchmarks

---

## Estimated Timeline

| Phase | Estimated Time | Priority |
|-------|----------------|----------|
| **Phase 1:** Add helpers | 30 minutes | HIGH |
| **Phase 2:** Fix loops | 45 minutes | HIGH |
| **Phase 3:** Refactor HTML | 30 minutes | MEDIUM |
| **Phase 4:** Testing | 45 minutes | HIGH |
| **Phase 5:** Documentation | 30 minutes | MEDIUM |
| **Total** | **3 hours** | - |

---

**Implementation Guide Created:** 2026-01-02
**Ready for Development:** Yes
**Estimated Effort:** 2-3 hours
**Target Version:** 1.0.77
