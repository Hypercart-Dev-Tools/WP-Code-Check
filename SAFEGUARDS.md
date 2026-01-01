# WP Code Check - Critical Safeguards

**Last Updated:** 2026-01-01 (v1.0.67)

This document contains critical implementation details that MUST NOT be changed without careful consideration. These safeguards prevent catastrophic failures that can silently break the scanner.

---

## 🚨 CRITICAL: Path Variable Quoting

### Rule
**ALL instances of `$PATHS` in grep commands MUST be quoted as `"$PATHS"`**

### Why This Matters
When `$PATHS` contains spaces (e.g., `/Users/name/Local Sites/project/`), an unquoted variable causes the shell to split it into multiple arguments, breaking grep searches completely.

### Impact of Violation
- **Severity:** CRITICAL
- **Symptom:** Scanner reports 0 issues for projects in paths with spaces
- **Detection:** Silent failure - no error messages, just incorrect results
- **Affected:** ALL pattern-based checks (16 grep commands)

### Example
```bash
# ❌ WRONG - breaks with spaces in path
grep -rHn --include="*.php" -E 'pattern' $PATHS

# ✅ CORRECT - works with all paths
grep -rHn --include="*.php" -E 'pattern' "$PATHS"
```

### Affected Lines (as of v1.0.67)
All grep commands in `dist/bin/check-performance.sh`:
- Line 1373: Dynamic pattern engine
- Line 1541: Unsanitized superglobal read
- Line 1647: Direct database queries
- Line 1719: Admin functions without capability checks
- Line 1798: AJAX polling (setInterval)
- Line 1862: Expensive polling (HCC-005)
- Line 1926: REST endpoints
- Line 1987: wp_ajax handlers
- Line 2057: WooCommerce Subscriptions queries
- Line 2122: get_users without limit
- Line 2188: get_terms without limit
- Line 2228: pre_get_posts unbounded
- Line 2272: Unbounded SQL on wp_terms
- Line 2627: N+1 patterns (meta in loops)
- Line 2676: WooCommerce N+1 patterns
- Line 2759: Transients without expiration

### Verification
Each affected line has an inline comment:
```bash
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
```

### Testing
To verify this safeguard:
1. Create a test project in a path with spaces: `/tmp/test path/plugin/`
2. Run scanner: `./dist/bin/check-performance.sh --paths "/tmp/test path/plugin/"`
3. Verify issues are detected (should NOT report 0 issues if violations exist)

---

## 🔒 Pattern Enhancement: isset() Bypass Detection

### Rule
**The `unsanitized-superglobal-read` pattern MUST count superglobal occurrences per line**

### Logic
```bash
# Count how many times $_GET/$_POST/$_REQUEST appears on the line
superglobal_count=$(echo "$code" | grep -o '\$_\(GET\|POST\|REQUEST\)\[' | wc -l)

# If isset/empty is present AND superglobal appears only once, skip it
if echo "$code" | grep -q 'isset\|empty'; then
  if [ "$superglobal_count" -eq 1 ]; then
    continue  # This is just an existence check
  fi
fi

# Otherwise, report it (isset + direct usage on same line)
echo "$line"
```

### Why This Matters
- **1 occurrence with isset/empty:** Safe existence check
  - Example: `if ( isset( $_GET['tab'] ) ) {` ✅
- **2+ occurrences:** isset check + direct usage (VIOLATION)
  - Example: `isset( $_GET['tab'] ) && $_GET['tab'] === 'subscriptions'` ❌

### Impact of Violation
If this logic is removed or simplified:
- **False Negatives:** Real security vulnerabilities will be missed
- **False Positives:** Valid existence checks will be flagged

### Location
`dist/bin/check-performance.sh` lines 1552-1572

---

## 📋 Version Increment Checklist

When making changes to the scanner, ALWAYS:

1. ✅ Increment version number in `dist/bin/check-performance.sh` (line 4)
2. ✅ Update `CHANGELOG.md` with:
   - Version number
   - Date (YYYY-MM-DD)
   - Category: Added/Changed/Fixed/Removed
   - Detailed description of changes
   - Impact assessment
   - Files changed with line numbers
3. ✅ Run test fixtures to verify no regressions:
   ```bash
   ./dist/bin/check-performance.sh --paths "dist/tests/fixtures/"
   ```
4. ✅ Test with real-world plugin in path with spaces
5. ✅ Update this SAFEGUARDS.md if critical logic changes

---

## 🧪 Critical Test Cases

### Test Case 1: Path with Spaces
**Purpose:** Verify grep commands work with spaces in paths

```bash
# Create test directory with spaces
mkdir -p "/tmp/test path/plugin"
cp dist/tests/fixtures/unsanitized-superglobal-isset-bypass.php "/tmp/test path/plugin/"

# Run scanner
./dist/bin/check-performance.sh --paths "/tmp/test path/plugin/"

# Expected: Should detect 2 errors (not 0)
```

### Test Case 2: isset() Bypass Pattern
**Purpose:** Verify isset + direct usage is caught

```bash
# Run test fixture
./dist/bin/check-performance.sh --paths "dist/tests/fixtures/unsanitized-superglobal-isset-bypass.php"

# Expected: Should detect 2 errors
# - Line 11: isset( $_GET['action'] ) && $_GET['action'] === 'delete'
# - Line 15: ! empty( $_POST['data'] ) && process_data( $_POST['data'] )
```

---

## 🔍 Debugging Silent Failures

If the scanner reports 0 issues when violations clearly exist:

1. **Check path quoting:**
   ```bash
   # Add debug output before grep
   echo "DEBUG: PATHS='$PATHS'"
   echo "DEBUG: PATHS contains spaces: $(echo "$PATHS" | grep -q ' ' && echo YES || echo NO)"
   ```

2. **Verify grep is finding files:**
   ```bash
   # Test grep directly
   grep -rHn --include="*.php" -E '\$_(GET|POST|REQUEST)\[' "$PATHS" | wc -l
   ```

3. **Check if filters are too aggressive:**
   ```bash
   # Count matches at each filter stage
   echo "After initial grep: $(MATCHES | wc -l)"
   echo "After sanitize_ filter: $(MATCHES | grep -v 'sanitize_' | wc -l)"
   # etc.
   ```

---

## 📝 Change History

| Version | Date | Change | Reason |
|---------|------|--------|--------|
| 1.0.67 | 2026-01-01 | Added path quoting safeguards | Fixed critical bug with spaces in paths |
| 1.0.67 | 2026-01-01 | Created SAFEGUARDS.md | Prevent future regressions |

---

**⚠️ WARNING:** Violating these safeguards can cause silent failures that are extremely difficult to debug. Always consult this document before modifying core scanner logic.

