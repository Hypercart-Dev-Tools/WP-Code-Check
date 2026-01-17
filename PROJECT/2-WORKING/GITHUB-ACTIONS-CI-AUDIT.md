# GitHub Actions CI Test Fixture Failures - Audit Report

**Created:** 2026-01-10  
**Status:** Analysis Complete  
**Priority:** HIGH  
**Type:** Bug Investigation

## Problem Statement

GitHub Actions CI workflow test fixtures fail consistently. The only successful run was at:
https://github.com/Hypercart-Dev-Tools/WP-Code-Check/actions/runs/20622729422

## Root Cause Analysis

### Primary Issue: JSON Parsing Mismatch

The test runner script (`dist/tests/run-fixture-tests.sh`) has a **critical parsing bug**:

1. **What happens:**
   - Script runs `check-performance.sh` with `--no-log` flag
   - `check-performance.sh` outputs **JSON format** by default
   - Test script tries to parse JSON as **plain text** looking for lines like `Errors:   6`

2. **Evidence from test output:**
   ```bash
   [DEBUG] Raw output (last 20 lines):
       "summary": {
         "total_errors": 9,
         "total_warnings": 4,
   ```
   
   But the parsing logic does:
   ```bash
   actual_errors=$(echo "$clean_output" | grep -E "^[[:space:]]*Errors:" | grep -oE '[0-9]+' | head -1)
   actual_warnings=$(echo "$clean_output" | grep -E "^[[:space:]]*Warnings:" | grep -oE '[0-9]+' | head -1)
   ```
   
   This grep pattern **never matches** JSON output, so it defaults to `0`.

3. **Result:**
   - Expected: 6 errors, 3-5 warnings
   - Actual parsed: 0 errors, 0 warnings
   - **All tests fail** with parsing errors

### Secondary Issues

1. **HTML Report Generation Error**
   ```
   Error: Input file not found: 
   ⚠ HTML report generation failed (Python converter error)
   ```
   - The `json-to-html.py` converter is being called but failing
   - This is a side effect, not the main issue

2. **Pattern Library Regeneration on Every Test**
   - Each test run regenerates `PATTERN-LIBRARY.json` and `PATTERN-LIBRARY.md`
   - This adds unnecessary overhead to test execution
   - Not a failure, but inefficient

3. **Bash Version Warning**
   ```
   ⚠️  Warning: Bash 4+ required for full functionality. Using fallback mode.
   ```
   - macOS ships with Bash 3.2
   - GitHub Actions uses Ubuntu with Bash 4+
   - This creates environment inconsistency

## Why It Worked Once

The successful run likely occurred when:
- `check-performance.sh` **default format was `text`** instead of `json`
- The default was changed to `json` in line 113 of `check-performance.sh`
- The test script was never updated to handle this change
- Git history should show when `OUTPUT_FORMAT="json"` became the default

## Impact Assessment

- **Severity:** HIGH - All CI tests fail
- **Scope:** Affects all PR validation and automated testing
- **User Impact:** Developers cannot rely on CI for validation
- **False Positives:** Tests report failures even when detection works correctly

## Recommended Fixes

### Option 1: Force Text Output (Quick Fix)
Modify `run-fixture-tests.sh` line 126 to force text format:
```bash
"$BIN_DIR/check-performance.sh" --paths "$fixture_file" --no-log --format text > "$tmp_output" 2>&1 || true
```

### Option 2: Parse JSON Properly (Correct Fix)
Update the parsing logic to extract from JSON:
```bash
# Extract counts from JSON summary
actual_errors=$(echo "$clean_output" | grep -o '"total_errors":[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -1)
actual_warnings=$(echo "$clean_output" | grep -o '"total_warnings":[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -1)
```

### Option 3: Use jq for JSON Parsing (Best Practice)
```bash
actual_errors=$(echo "$clean_output" | jq -r '.summary.total_errors // 0')
actual_warnings=$(echo "$clean_output" | jq -r '.summary.total_warnings // 0')
```

## Files Affected

- `.github/workflows/ci.yml` - CI workflow configuration
- `dist/tests/run-fixture-tests.sh` - Test runner with parsing bug (lines 140-141)
- `dist/bin/check-performance.sh` - Scanner that outputs JSON by default

## Next Steps

1. ✅ **Immediate:** Document findings (this file)
2. ⏳ **Short-term:** Implement Option 2 or 3 to fix parsing
3. ⏳ **Medium-term:** Add format detection or explicit format flag
4. ⏳ **Long-term:** Consider separating JSON/text output modes more clearly

## Testing Plan

After fix implementation:
1. Run `dist/tests/run-fixture-tests.sh` locally
2. Verify all 8 fixture tests pass
3. Push to PR and verify GitHub Actions passes
4. Compare output with successful run from history

## Related Files

- `dist/tests/fixtures/antipatterns.php` - Test fixture (working correctly)
- `dist/tests/fixtures/clean-code.php` - Test fixture (working correctly)
- `dist/bin/json-to-html.py` - HTML converter (separate issue)

## Questions for User

1. Do you want Option 2 (grep-based) or Option 3 (jq-based) for the fix?
2. Should we add a `--format` flag to explicitly control output format?
3. Do you want to investigate the HTML converter error separately?

