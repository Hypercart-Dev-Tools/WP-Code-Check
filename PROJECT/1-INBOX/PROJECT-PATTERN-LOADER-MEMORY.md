# Pattern Loader Memory Optimization

**Created:** 2026-01-15  
**Status:** Not Started  
**Priority:** Medium  
**Estimated Impact:** 6-12x faster pattern loading (600-1200ms → 50-100ms)

---

## Problem Statement

The scanner currently loads and parses pattern JSON files multiple times during each scan:

1. **5 separate `find` operations** - Scanning the same directory tree for different pattern types
2. **52+ JSON files** opened and parsed multiple times (once for discovery, once for loading)
3. **52+ Python subprocesses** spawned for complex field extraction
4. **No caching** - Patterns re-parsed every time they're accessed

**Current overhead:** ~600-1200ms per scan just for pattern loading operations.

---

## Proposed Solution

Load all patterns into memory **once** at scan startup, then access pre-loaded data instead of re-parsing files.

### Approach: Leverage Existing PATTERN-LIBRARY.json

The `pattern-library-manager.sh` already generates `dist/PATTERN-LIBRARY.json` with complete pattern metadata after each scan. We can use this as a pre-computed pattern registry.

**Benefits:**
- ✅ Already exists - no new data structure needed
- ✅ Pre-computed - all metadata already extracted
- ✅ Complete - includes all fields (id, severity, search_pattern, file_patterns, etc.)
- ✅ Auto-updated - regenerated after each scan

---

## Implementation Plan

### Phase 1: Create Pattern Registry Loader (Python)

**File:** `dist/bin/lib/load-pattern-registry.py`

**Functionality:**
- Read `dist/PATTERN-LIBRARY.json`
- Parse all pattern metadata
- Export to Bash-friendly format (temp file with key-value pairs)
- Support fallback to individual file parsing if registry missing

**Output format options:**
1. **Temp file with sourcing:** `PATTERN_<ID>_<FIELD>=value` (Bash 3 compatible)
2. **JSON temp file:** Single file with all patterns, parsed once with jq/Python
3. **Associative arrays:** For Bash 4+ environments

### Phase 2: Modify Scanner Startup

**Location:** `dist/bin/check-performance.sh` (before pattern discovery)

**Changes:**
```bash
# Early in script (after REPO_ROOT is set)
section_start "PATTERN_REGISTRY_LOAD"

# Check if pre-generated registry exists
if [ -f "$REPO_ROOT/PATTERN-LIBRARY.json" ]; then
  # Load all patterns into memory
  PATTERN_REGISTRY_FILE=$(mktemp)
  python3 "$SCRIPT_DIR/lib/load-pattern-registry.py" \
    "$REPO_ROOT/PATTERN-LIBRARY.json" \
    "$PATTERN_REGISTRY_FILE"
  
  # Source the registry (Bash 3 compatible)
  source "$PATTERN_REGISTRY_FILE"
  PATTERN_REGISTRY_LOADED=true
else
  # First run or registry missing - use fallback
  PATTERN_REGISTRY_LOADED=false
fi

section_end
```

### Phase 3: Replace Pattern Discovery Loops

**Current (5 separate find operations):**
```bash
SIMPLE_PATTERNS=$(find "$REPO_ROOT/patterns" -maxdepth 1 -name "*.json" | while read -r pattern_file; do
  detection_type=$(python3 <<EOFPYTHON ...)
  if [ "$detection_type" = "simple" ]; then echo "$pattern_file"; fi
done)
```

**Optimized (single registry lookup):**
```bash
if [ "$PATTERN_REGISTRY_LOADED" = "true" ]; then
  # Get patterns from pre-loaded registry
  SIMPLE_PATTERNS=$(get_patterns_by_type "simple")
else
  # Fallback to current approach
  SIMPLE_PATTERNS=$(find "$REPO_ROOT/patterns" ...)
fi
```

### Phase 4: Optimize load_pattern() Function

**Location:** `dist/lib/pattern-loader.sh`

**Changes:**
```bash
load_pattern() {
  local pattern_file="$1"
  local pattern_id=$(basename "$pattern_file" .json)
  
  if [ "$PATTERN_REGISTRY_LOADED" = "true" ]; then
    # Load from pre-parsed registry (no file I/O, no Python subprocess)
    pattern_id="${PATTERN_${pattern_id}_ID}"
    pattern_enabled="${PATTERN_${pattern_id}_ENABLED}"
    pattern_severity="${PATTERN_${pattern_id}_SEVERITY}"
    # ... etc
    return 0
  else
    # Fallback to current file parsing
    # ... existing code
  fi
}
```

---

## Performance Expectations

### Current Performance
- **Pattern discovery:** 5 × find + 52 × grep = ~150ms
- **Pattern loading:** 52 × (Python subprocess + grep/sed) = ~600-1000ms
- **Total overhead:** ~750-1150ms per scan

### Optimized Performance
- **Registry load:** 1 × Python parse + export = ~50ms
- **Pattern discovery:** Array lookup = ~1ms
- **Pattern loading:** Variable access = ~0.1ms per pattern
- **Total overhead:** ~55ms per scan

**Expected speedup:** 6-12x faster (especially noticeable on large codebases)

---

## Fallback Strategy

**If PATTERN-LIBRARY.json doesn't exist:**
- First scan after fresh clone
- Registry generation failed
- Patterns modified but registry not regenerated

**Solution:** Fall back to current approach (individual file parsing)

**Staleness detection:**
```bash
# Check if any pattern file is newer than registry
if [ "$PATTERN_REGISTRY_FILE" -ot "$REPO_ROOT/patterns" ]; then
  # Registry is stale - regenerate or use fallback
fi
```

---

## Acceptance Criteria

- [ ] Single Python script loads all patterns from PATTERN-LIBRARY.json
- [ ] Pattern metadata exported to Bash-friendly format (temp file or env vars)
- [ ] Scanner loads registry once at startup
- [ ] Pattern discovery uses pre-loaded data (no repeated find operations)
- [ ] `load_pattern()` uses pre-loaded data (no Python subprocesses)
- [ ] Fallback to current approach if registry missing
- [ ] Performance improvement measured and documented
- [ ] Bash 3 compatibility maintained
- [ ] No breaking changes to existing pattern format

---

## Testing Plan

1. **Baseline measurement:** Time current pattern loading with `PROFILE=1`
2. **Implementation:** Add registry loader and modify scanner
3. **Performance test:** Compare before/after with same codebase
4. **Fallback test:** Delete PATTERN-LIBRARY.json and verify graceful degradation
5. **Compatibility test:** Test on Bash 3 and Bash 4+ environments
6. **Large codebase test:** Measure improvement on WooCommerce or similar

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Stale registry | Incorrect pattern metadata | Check file timestamps, regenerate if stale |
| Registry corruption | Scan fails | Validate JSON before loading, fallback on error |
| Memory usage | Bash variable limits | Use temp file instead of env vars if needed |
| Bash 3 compatibility | Breaks on older systems | Use simple key-value format, no associative arrays |

---

## Future Enhancements

- **Incremental updates:** Only reload changed patterns
- **Pattern versioning:** Detect version mismatches between registry and files
- **Parallel loading:** Load patterns in background while file list builds
- **Pattern caching:** Cache across multiple scans (with invalidation)

