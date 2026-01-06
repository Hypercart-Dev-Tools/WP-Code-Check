# Phase 2: Node.js Pattern Analysis

**Created:** 2026-01-06
**Status:** In Progress
**Branch:** `feature/nodejs-headless-patterns-2026-01-06`

## Analysis of Old Branch Implementation

### Key Findings from `origin/rules/nodejs-wp-headless-phase-2`

#### 1. File Type Detection

**Old approach:**
```bash
# Line 1592: Find source files
source_files=$(find "$PATHS" \( -name "*.php" -o -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" \) -type f 2>/dev/null | grep -v '/vendor/' | grep -v '/node_modules/' | grep -v '\.min\.js$' | grep -v 'bundle' || true)

# Line 1612: Detect file type
case "$file" in
  *.js|*.jsx|*.ts|*.tsx) is_js=true ;;
  *.php) is_php=true ;;
esac
```

**Exclusions:**
- `/vendor/` - PHP dependencies
- `/node_modules/` - JavaScript dependencies
- `*.min.js` - Minified files
- `bundle` - Bundled files

#### 2. Pattern Loading with File Type Override

**Old approach:**
```bash
# Set file type filter before run_check
OVERRIDE_GREP_INCLUDE="--include=*.js --include=*.jsx --include=*.ts --include=*.tsx"

# Run the check
run_check "ERROR" "$(get_severity "hcc-001-localstorage-exposure" "CRITICAL")" \
  "Sensitive data in localStorage/sessionStorage" "hcc-001-localstorage-exposure" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*plugin" \
  ...

# Clear the override
unset OVERRIDE_GREP_INCLUDE
```

**Pattern:**
1. Set `OVERRIDE_GREP_INCLUDE` with file extensions
2. Call `run_check` (which uses the override)
3. Unset `OVERRIDE_GREP_INCLUDE`

#### 3. JSON Pattern Structure

**Key fields:**
```json
{
  "id": "headless-api-key-exposure",
  "detection": {
    "type": "grep",
    "file_patterns": ["*.js", "*.jsx", "*.ts", "*.tsx"],
    "patterns": [
      {
        "id": "hardcoded-api-key",
        "pattern": "(API_KEY|SECRET|TOKEN)...",
        "description": "..."
      }
    ],
    "exclude_patterns": ["//.*SECRET", ...],
    "exclude_files": ["*/node_modules/*", ...]
  }
}
```

**Important:** The `file_patterns` array specifies which file types to scan.

---

## New Implementation Plan

### Approach: Extend Existing `load_pattern()` Function

Instead of creating a separate `load_javascript_pattern()` function, we'll extend the existing `load_pattern()` function to handle JavaScript/TypeScript files.

### Changes Needed

#### 1. Update `load_pattern()` to Read `file_patterns` from JSON

**Current behavior:**
- Hardcoded to scan `*.php` files only
- Uses `--include="*.php"` in grep commands

**New behavior:**
- Read `file_patterns` array from JSON
- Build `--include` flags dynamically
- Default to `*.php` if `file_patterns` is missing (backward compatibility)

**Implementation:**
```bash
# In load_pattern() function
local file_patterns=$(jq -r '.detection.file_patterns[]? // empty' "$pattern_file" 2>/dev/null)

if [ -n "$file_patterns" ]; then
  # Build OVERRIDE_GREP_INCLUDE from file_patterns
  OVERRIDE_GREP_INCLUDE=""
  while IFS= read -r ext; do
    OVERRIDE_GREP_INCLUDE="$OVERRIDE_GREP_INCLUDE --include=$ext"
  done <<< "$file_patterns"
else
  # Default to PHP for backward compatibility
  OVERRIDE_GREP_INCLUDE="--include=*.php"
fi
```

#### 2. Update Pattern Discovery to Include New Directories

**Current:**
```bash
AGGREGATED_PATTERNS=$(find "$REPO_ROOT/patterns" -name "*.json" -type f | while read -r pattern_file; do
  # Only processes patterns in dist/patterns/*.json
done)
```

**New:**
```bash
AGGREGATED_PATTERNS=$(find "$REPO_ROOT/patterns" -name "*.json" -type f | while read -r pattern_file; do
  # Now also processes:
  # - dist/patterns/headless/*.json
  # - dist/patterns/nodejs/*.json
  # - dist/patterns/js/*.json
done)
```

**No changes needed!** The `find` command already searches recursively.

#### 3. Update Exclusions for JavaScript Files

**Add to existing exclusions:**
```bash
EXCLUDE_ARGS="--exclude-dir=vendor --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.next --exclude-dir=dist --exclude=*.min.js --exclude=*bundle*.js"
```

**New exclusions:**
- `node_modules/` - JavaScript dependencies
- `.next/` - Next.js build output
- `dist/` - Build output
- `*.min.js` - Minified files
- `*bundle*.js` - Bundled files

#### 4. Handle `exclude_files` from JSON

**Current:** Not implemented
**New:** Read `exclude_files` from JSON and apply to grep

```bash
# In load_pattern() function
local exclude_files=$(jq -r '.detection.exclude_files[]? // empty' "$pattern_file" 2>/dev/null)

if [ -n "$exclude_files" ]; then
  while IFS= read -r exclude_pattern; do
    # Convert glob pattern to grep exclude
    # */node_modules/* -> --exclude-dir=node_modules
    # *test* -> --exclude=*test*
  done <<< "$exclude_files"
fi
```

---

## Implementation Steps

### Step 1: Update Exclusions (5 min)
- Add JavaScript-specific exclusions to `EXCLUDE_ARGS`
- Test that existing PHP patterns still work

### Step 2: Extend `load_pattern()` to Read `file_patterns` (30 min)
- Add `file_patterns` parsing from JSON
- Build `OVERRIDE_GREP_INCLUDE` dynamically
- Maintain backward compatibility with PHP-only patterns

### Step 3: Test with One Pattern (15 min)
- Test `headless/api-key-exposure.json` on a sample JS file
- Verify pattern detection works
- Check that PHP patterns are unaffected

### Step 4: Add `exclude_files` Support (20 min)
- Parse `exclude_files` from JSON
- Convert glob patterns to grep exclude flags
- Test with patterns that have exclusions

### Step 5: Full Testing (30 min)
- Test all 11 JavaScript/Node.js patterns
- Verify test fixtures pass
- Run full scan on mixed PHP/JS project
- Ensure no regressions in PHP pattern detection

---

## Risk Mitigation

### Backward Compatibility
- ✅ Default to `*.php` if `file_patterns` is missing
- ✅ Existing PHP patterns don't have `file_patterns` field
- ✅ No changes to existing pattern JSON files needed

### Performance
- ✅ Use Phase 1 safeguards (timeout, file limits)
- ✅ Exclude `node_modules/` and build directories
- ✅ Skip minified and bundled files

### Testing
- ✅ Test one pattern at a time
- ✅ Verify fixtures before full integration
- ✅ Run existing PHP tests to ensure no regressions

---

## Next Steps

1. Update `EXCLUDE_ARGS` with JavaScript exclusions
2. Extend `load_pattern()` to read `file_patterns`
3. Test with `api-key-exposure.json` pattern
4. Add `exclude_files` support
5. Full testing and validation
6. Update version and CHANGELOG

