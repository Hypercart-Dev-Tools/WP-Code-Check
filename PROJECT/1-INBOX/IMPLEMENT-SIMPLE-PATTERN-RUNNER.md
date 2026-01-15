# Implement Simple Pattern Runner

**Created:** 2026-01-15  
**Status:** Not Started  
**Priority:** HIGH  
**Blocks:** Phase 2 Pattern Migration (4 JSON patterns waiting)  
**Related:** `PROJECT/2-WORKING/PATTERN-MIGRATION-TO-JSON.md`

---

## Problem

The scanner currently has runners for `aggregated` and `clone_detection` pattern types, but **no runner for "simple" detection type patterns**. This blocks the migration of inline rules to JSON patterns.

**Current State:**
- 4 JSON patterns created: `unbounded-posts-per-page.json`, `unbounded-numberposts.json`, `nopaging-true.json`, `order-by-rand.json`
- Patterns load correctly but are never executed
- Inline code remains active as a workaround

**Impact:**
- Cannot complete Phase 2 of pattern migration
- JSON patterns exist but are unused (technical debt)
- Inline code duplication continues

---

## Acceptance Criteria

- [ ] Scanner detects and executes all patterns with `detection.type: "simple"` or `"direct"`
- [ ] Simple patterns produce identical results to inline `run_check` calls
- [ ] Fixture tests pass with no changes to finding counts
- [ ] Baseline suppression works for simple pattern findings
- [ ] Inline code for migrated rules can be safely removed

---

## Implementation Plan

### 1. Add Simple Pattern Runner Section

**Location:** `dist/bin/check-performance.sh` around line 2700-2800 (before aggregated patterns section)

**Code:**
```bash
# ============================================================================
# Simple Pattern Checks - JSON-Defined Rules
# ============================================================================

text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
text_echo "${BLUE}  SIMPLE PATTERN CHECKS${NC}"
text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
text_echo ""

# Find all simple/direct detection patterns
SIMPLE_PATTERNS=$(find "$REPO_ROOT/patterns" -name "*.json" -type f | while read -r pattern_file; do
  # Extract detection type from JSON
  detection_type=$(grep '"type"' "$pattern_file" | head -1 | sed 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  
  # Match both "simple" and "direct" (they're equivalent)
  if [ "$detection_type" = "simple" ] || [ "$detection_type" = "direct" ]; then
    echo "$pattern_file"
  fi
done)

if [ -z "$SIMPLE_PATTERNS" ]; then
  text_echo "${BLUE}No simple patterns found. Skipping.${NC}"
  text_echo ""
else
  debug_echo "Simple patterns found: $(echo "$SIMPLE_PATTERNS" | wc -l | tr -d ' ') patterns"
  
  # Process each simple pattern
  while IFS= read -r pattern_file; do
    [ -z "$pattern_file" ] && continue
    
    # Load pattern metadata
    if load_pattern "$pattern_file"; then
      # Determine error level based on severity
      error_level="ERROR"
      if [ "$pattern_severity" = "LOW" ] || [ "$pattern_severity" = "MEDIUM" ]; then
        error_level="WARNING"
      fi
      
      # Execute pattern using run_check
      run_check "$error_level" "$pattern_severity" "$pattern_title" "$pattern_id" \
        "-E $pattern_search"
    fi
  done <<< "$SIMPLE_PATTERNS"
fi

text_echo ""
```

### 2. Handle File Patterns

Simple patterns may specify `file_patterns` (e.g., `["*.php", "*.js"]`). The runner should respect these:

```bash
# Build file include args from pattern_file_patterns
include_args=""
if [ -n "$pattern_file_patterns" ]; then
  for ext in $pattern_file_patterns; do
    include_args="$include_args --include=$ext"
  done
fi

# Pass to run_check (may need to modify run_check to accept include args)
```

**Note:** Current `run_check` uses global `$EXCLUDE_ARGS` and `--include=*.php`. May need enhancement.

### 3. Remove Inline Code

After validation, remove these inline checks:

**File:** `dist/bin/check-performance.sh`

- **Lines 3850-3862:** `unbounded-posts-per-page`, `unbounded-numberposts`, `nopaging-true`
- **Lines 4854-4864:** `order-by-rand`

Search for: `TODO: Implement simple pattern runner`

### 4. Validation Steps

```bash
# 1. Run fixture tests before changes
./dist/tests/run-fixture-tests.sh > before.txt

# 2. Implement simple pattern runner

# 3. Run fixture tests after changes
./dist/tests/run-fixture-tests.sh > after.txt

# 4. Compare results
diff before.txt after.txt
# Expected: No differences in pass/fail counts

# 5. Test on real project
./dist/bin/check-performance.sh --paths /path/to/project --format json > before.json
# (after removing inline code)
./dist/bin/check-performance.sh --paths /path/to/project --format json > after.json
jq -S '.findings | sort_by(.rule_id, .file, .line)' before.json > before-sorted.json
jq -S '.findings | sort_by(.rule_id, .file, .line)' after.json > after-sorted.json
diff before-sorted.json after-sorted.json
# Expected: Identical findings
```

---

## Technical Notes

### Pattern Loader Variables

When `load_pattern()` is called, these variables are exported:
- `$pattern_id` - Rule ID (e.g., "unbounded-posts-per-page")
- `$pattern_enabled` - true/false
- `$pattern_detection_type` - "simple", "aggregated", etc.
- `$pattern_category` - "performance", "security", etc.
- `$pattern_severity` - "CRITICAL", "HIGH", "MEDIUM", "LOW"
- `$pattern_title` - Human-readable title
- `$pattern_search` - Regex pattern for grep
- `$pattern_file_patterns` - Space-separated file extensions (e.g., "*.php *.js")

### Existing Runners for Reference

- **Aggregated patterns:** Lines 5757-5801 in `check-performance.sh`
- **Clone detection:** Lines 5813-5850 in `check-performance.sh`

---

## Estimated Effort

- **Implementation:** 1-2 hours
- **Testing & Validation:** 1 hour
- **Documentation:** 30 minutes

**Total:** 2.5-3.5 hours

---

## Success Metrics

- [ ] All 4 JSON patterns execute successfully
- [ ] Fixture tests show 0 regressions
- [ ] Inline code removed from `check-performance.sh`
- [ ] CHANGELOG updated with migration completion
- [ ] `PATTERN-INVENTORY.md` updated (4 rules marked as fully migrated)

---

## Follow-Up Tasks

After implementation:
- Migrate remaining 7 T1 rules to JSON
- Implement runners for T2/T3 patterns (contextual, scripted)
- Complete Phase 2 of pattern migration

