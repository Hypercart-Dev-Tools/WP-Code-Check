# Phase 3: Clone Detection Optimization

**Created:** 2026-01-06
**Status:** In Progress
**Assigned Version:** 1.0.84

## Summary

Implemented Priority 1 optimizations for clone detection based on Phase 2 profiling data. Clone detection was identified as the primary bottleneck (94% of scan time), causing complete failure on large codebases like WooCommerce.

## Changes Implemented

### 1. MAX_CLONE_FILES Limit ✅ COMPLETE

**File:** `dist/bin/check-performance.sh`

- Added `MAX_CLONE_FILES` environment variable (default: 100 files)
- Separated from `MAX_FILES` to allow independent control
- Shows warning when file count exceeds limit
- Shows progress warning at 80% threshold (>80 files)

**Code Changes:**
```bash
# Line 88-90: Configuration
MAX_CLONE_FILES="${MAX_CLONE_FILES:-100}"  # 100 files default (prevents timeouts)

# Line 1817-1827: File count check with warnings
if [ "$MAX_CLONE_FILES" -gt 0 ] && [ "$file_count" -gt "$MAX_CLONE_FILES" ]; then
  text_echo "  ${YELLOW}⚠ File count ($file_count) exceeds clone detection limit ($MAX_CLONE_FILES)${NC}"
  text_echo "  ${YELLOW}  Skipping clone detection to prevent timeout. Set MAX_CLONE_FILES=0 to disable limit.${NC}"
  rm -f "$temp_functions" "$temp_hashes"
  return 1
fi

# Show warning if approaching limit
if [ "$MAX_CLONE_FILES" -gt 0 ] && [ "$file_count" -gt $((MAX_CLONE_FILES * 80 / 100)) ]; then
  text_echo "  ${YELLOW}⚠ Processing $file_count files (limit: $MAX_CLONE_FILES) - this may take a while...${NC}"
fi
```

### 2. --skip-clone-detection Flag ✅ COMPLETE

**File:** `dist/bin/check-performance.sh`

- Added `SKIP_CLONE_DETECTION` variable (default: false)
- Added `--skip-clone-detection` command-line flag
- Updated help text to document the flag
- Added conditional logic to skip clone detection section when flag is set

**Code Changes:**
```bash
# Line 72: Configuration
SKIP_CLONE_DETECTION=false  # Skip clone detection for faster scans

# Line 25: Help text
#   --skip-clone-detection   Skip function clone detection (faster scans)

# Line 268-271: Argument parsing
--skip-clone-detection)
  SKIP_CLONE_DETECTION=true
  shift
  ;;

# Line 3981-3987: Skip logic
if [ "$SKIP_CLONE_DETECTION" = "true" ]; then
  text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  text_echo "${BLUE}  FUNCTION CLONE DETECTOR${NC}"
  text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  text_echo ""
  text_echo "${YELLOW}  ○ Skipped (use --enable-clone-detection to run)${NC}"
  text_echo ""
fi
```

### 3. Version Update ✅ COMPLETE

- Updated version from 1.0.83 to 1.0.84
- Updated CHANGELOG.md with Phase 3 changes

## Testing Status

### Manual Testing Required

Due to terminal/environment issues during automated testing, manual verification is needed:

**Test 1: Small Codebase (Save Cart Later - 8 files)**
```bash
cd dist
PROFILE=1 bash bin/check-performance.sh --paths /Users/noelsaw/Downloads/save-cart-later --skip-clone-detection
```
**Expected:** Clone detection section shows "Skipped" message, scan completes in ~6 seconds (vs 114s with clone detection)

**Test 2: Large Codebase (WooCommerce - ~500 files)**
```bash
cd dist
PROFILE=1 bash bin/check-performance.sh --paths /path/to/woocommerce --skip-clone-detection
```
**Expected:** Scan completes successfully without timeout (previously failed after 10+ minutes)

**Test 3: File Limit Warning**
```bash
cd dist
MAX_CLONE_FILES=5 bash bin/check-performance.sh --paths /Users/noelsaw/Downloads/save-cart-later
```
**Expected:** Shows warning that file count (8) exceeds limit (5), skips clone detection

**Test 4: Approaching Limit Warning**
```bash
cd dist
MAX_CLONE_FILES=10 bash bin/check-performance.sh --paths /Users/noelsaw/Downloads/save-cart-later
```
**Expected:** Shows warning that processing 8 files (limit: 10), then proceeds with clone detection

## Expected Performance Impact

| Scenario | Before | After (--skip-clone-detection) | Improvement |
|----------|--------|-------------------------------|-------------|
| Save Cart Later (8 files) | 114s | ~6s | 95% faster |
| WooCommerce (~500 files) | TIMEOUT (>600s) | ~30s | Completes successfully |
| Medium Plugin (50 files) | ~300s | ~10s | 97% faster |

## Next Steps

### Remaining Priority 1 Tasks

- [ ] Test optimizations on Save Cart Later (manual testing required)
- [ ] Test optimizations on WooCommerce (manual testing required)
- [ ] Consider making clone detection opt-in by default (--enable-clone-detection flag)

### Priority 2 Tasks (Future)

- [ ] Add progress indicators ("Processing file X of Y...")
- [ ] Display elapsed time every 10 seconds for long operations
- [ ] Show which section is currently running
- [ ] Add spinner/progress bar for better UX

### Priority 3 Tasks (Future)

- [ ] Implement file list caching (scan once, reuse for multiple patterns)
- [ ] Cache function signatures instead of re-extracting
- [ ] Add early exit if no duplicates found in first N files
- [ ] Parallelize independent pattern checks (if safe)
- [ ] Add incremental scan mode (only changed files)

## Files Modified

1. `dist/bin/check-performance.sh` - Added MAX_CLONE_FILES limit and --skip-clone-detection flag
2. `CHANGELOG.md` - Added v1.0.84 entry
3. `PROJECT/1-INBOX/PROJECT-STABILITY.md` - Updated Phase 3 section with detailed tasks

## Notes

- Clone detection has O(n²) complexity, making it impractical for large codebases
- Default limit of 100 files is conservative but prevents most timeout scenarios
- Users can override with `MAX_CLONE_FILES=0` to disable limit entirely
- The --skip-clone-detection flag provides immediate relief for large codebase scans
- Future work should consider making clone detection opt-in rather than opt-out

