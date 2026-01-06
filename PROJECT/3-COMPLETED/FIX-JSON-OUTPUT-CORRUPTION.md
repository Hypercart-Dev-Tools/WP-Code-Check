# Fix: JSON Output Corruption (v1.0.88)

**Created:** 2026-01-06
**Completed:** 2026-01-06
**Status:** ✅ Complete
**Version:** v1.0.88
**Branch:** `feature/switch-html-generator-python-2026-01-06`
**Commit:** `ab11f57`

## Summary

Fixed a critical bash script bug that was prepending error messages to JSON log files, making them invalid and unparseable. The fix ensures clean JSON output that works seamlessly with the Python HTML generator.

## Problem

When running scans with `--format json`, the JSON log files were corrupted with error messages:

```
/Users/noelsaw/Documents/GH Repos/wp-code-check/dist/bin/check-performance.sh: line 1713: [: 0
0: integer expression expected
{
  "version": "1.0.87",
  ...
}
```

Additionally, the Python HTML generator output was being appended to the JSON file:

```json
}
Error: Invalid JSON in input file: Expecting value: line 1 column 1 (char 0)
Converting JSON to HTML...
  Input:  /Users/noelsaw/Documents/GH Repos/wp-code-check/dist/logs/2026-01-06-062131-UTC.json
  Output: /Users/noelsaw/Documents/GH Repos/wp-code-check/dist/reports/2026-01-06-062153-UTC.html
⚠ HTML report generation failed (Python converter error)
```

## Root Cause Analysis

### Issue 1: Duplicate Output in `match_count` (Line 1709)

**Original Code:**
```bash
local match_count=$(echo "$matches" | grep -c . || echo "0")
```

**Problem:**
- `grep -c .` returns "0" when there are no matches
- The `|| echo "0"` also executes, resulting in "0\n0" (two zeros on separate lines)
- This causes the integer comparison on line 1713 to fail: `[ "$match_count" -gt "$((MAX_FILES * 10))" ]`
- Bash error: `[: 0\n0: integer expression expected`

**Solution:**
```bash
# Count matches (grep -c returns 0 if no matches, so no need for || echo "0")
local match_count=$(echo "$matches" | grep -c . 2>/dev/null)
# Ensure match_count is a valid integer (default to 0 if empty/invalid)
match_count=${match_count:-0}
```

### Issue 2: Python Generator Output Captured in JSON (Line 4164)

**Original Code:**
```bash
if "$SCRIPT_DIR/json-to-html.py" "$LOG_FILE" "$HTML_REPORT" >&2; then
  echo "" >&2
  echo "📊 HTML Report: $HTML_REPORT" >&2
```

**Problem:**
- Line 616 redirects stderr to stdout: `exec 2>&1`
- This means `>&2` output is captured by the `tee` command on line 615
- Python generator output gets written to the JSON log file

**Solution:**
```bash
# IMPORTANT: Redirect to /dev/tty to prevent output from being captured in JSON log
if "$SCRIPT_DIR/json-to-html.py" "$LOG_FILE" "$HTML_REPORT" > /dev/tty 2>&1; then
  echo "" > /dev/tty
  echo "📊 HTML Report: $HTML_REPORT" > /dev/tty
```

## Changes Made

### File: `dist/bin/check-performance.sh`

**Line 1709-1711:** Fixed match count logic
```diff
- local match_count=$(echo "$matches" | grep -c . || echo "0")
+ # Count matches (grep -c returns 0 if no matches, so no need for || echo "0")
+ local match_count=$(echo "$matches" | grep -c . 2>/dev/null)
+ # Ensure match_count is a valid integer (default to 0 if empty/invalid)
+ match_count=${match_count:-0}
```

**Line 4164-4173:** Redirected Python generator to /dev/tty
```diff
- if "$SCRIPT_DIR/json-to-html.py" "$LOG_FILE" "$HTML_REPORT" >&2; then
-   echo "" >&2
-   echo "📊 HTML Report: $HTML_REPORT" >&2
+ # IMPORTANT: Redirect to /dev/tty to prevent output from being captured in JSON log
+ if "$SCRIPT_DIR/json-to-html.py" "$LOG_FILE" "$HTML_REPORT" > /dev/tty 2>&1; then
+   echo "" > /dev/tty
+   echo "📊 HTML Report: $HTML_REPORT" > /dev/tty
```

**Version Updates:**
- Line 4: `# Version: 1.0.88`
- Line 61: `SCRIPT_VERSION="1.0.88"`

### File: `CHANGELOG.md`

Added v1.0.88 entry documenting the fix with technical details.

## Testing

### Before Fix
```bash
$ head -3 dist/logs/2026-01-06-062131-UTC.json
/Users/noelsaw/Documents/GH Repos/wp-code-check/dist/bin/check-performance.sh: line 1713: [: 0
0: integer expression expected
{

$ python3 -m json.tool dist/logs/2026-01-06-062131-UTC.json
Error: Invalid JSON in input file: Expecting value: line 1 column 1 (char 0)
```

### After Fix
```bash
$ head -3 dist/logs/2026-01-06-062818-UTC.json
{
  "version": "1.0.88",
  "timestamp": "2026-01-06T06:28:21Z",

$ python3 -m json.tool dist/logs/2026-01-06-062818-UTC.json > /dev/null
✅ Valid JSON!

$ python3 dist/bin/json-to-html.py dist/logs/2026-01-06-062818-UTC.json dist/reports/test.html
Converting JSON to HTML...
  Input:  dist/logs/2026-01-06-062818-UTC.json
  Output: dist/reports/test.html
Processing project information...
Processing findings (12 total)...
Processing checks...
Processing DRY violations (0 total)...
Generating HTML report...

✓ HTML report generated successfully!
  Report: dist/reports/test.html
  Size: 34.2K
```

## Impact

### Before
- ❌ JSON logs were invalid and unparseable
- ❌ Python HTML generator failed with "Invalid JSON" error
- ❌ Manual cleanup required (extract lines 3-37 from JSON file)
- ❌ Error messages polluted JSON output

### After
- ✅ JSON logs are valid and parseable
- ✅ Python HTML generator works seamlessly
- ✅ No manual cleanup required
- ✅ Clean JSON output from start to finish

## Lessons Learned

1. **Bash Fallback Patterns:** Be careful with `|| echo "default"` when the command already returns a default value
2. **Output Redirection:** When using `exec 2>&1`, stderr is captured by stdout redirections - use `/dev/tty` for user-facing output
3. **Parameter Expansion:** Use `${var:-default}` for safety when dealing with potentially empty variables
4. **Testing:** Always validate JSON output with `python3 -m json.tool` or `jq` after making changes

## Related

- **Previous Issue:** Python HTML generator cherry-picked in v1.0.87
- **Related Commit:** `1a9b40b` - Added Python HTML generator
- **CHANGELOG:** v1.0.88 entry documents the fix
- **Branch:** `feature/switch-html-generator-python-2026-01-06`

