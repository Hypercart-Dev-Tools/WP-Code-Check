# Pattern Loading Verification: v1.x vs v2.x

**Date:** 2026-01-20  
**Status:** ✅ VERIFIED

---

## Finding: Pattern Loading is IDENTICAL

### Claim to Verify
> "v2.x loads all patterns into memory to scan files, while v1.x does not"

### Verification Result
❌ **CLAIM IS FALSE**

Both v1.x and v2.x load patterns **one-at-a-time**, NOT into memory.

---

## Evidence

### v1.x Pattern Loading (development branch)

**Discovery Phase:**
```bash
SIMPLE_PATTERNS=$(find "$REPO_ROOT/patterns" -name "*.json" -type f | while read -r pattern_file; do
  detection_type=$(grep '"detection_type"' "$pattern_file" | head -1 | sed 's/.*"detection_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ "$detection_type" = "simple" ]; then
    echo "$pattern_file"
  fi
done)
```

**Processing Phase:**
```bash
while IFS= read -r pattern_file; do
  [ -z "$pattern_file" ] && continue
  
  # Load ONE pattern at a time
  if load_pattern "$pattern_file"; then
    # Run grep scan
    matches=$(cached_grep $include_args -E "$pattern_search" || true)
    # Process matches
  fi
done <<< "$SIMPLE_PATTERNS"
```

### v2.x Pattern Loading (current workspace)

**Discovery Phase (with registry fallback):**
```bash
if SIMPLE_PATTERNS=$(get_patterns_from_registry "simple:direct" "php" "false"); then
  :
else
  # Fallback: Same as v1.x
  SIMPLE_PATTERNS=$(find "$REPO_ROOT/patterns" -maxdepth 1 -name "*.json" -type f 2>/dev/null | while read -r pattern_file; do
    # Extract detection type
    detection_info=$(python3 -S <<EOFPYTHON 2>/dev/null
import json
try:
  with open('$pattern_file', 'r') as f:
    data = json.load(f)
    root_type = data.get('detection_type', '') or ''
    sub_type = data.get('detection', {}).get('type', '') or ''
  print("%s %s" % (root_type, sub_type))
except Exception:
  pass
EOFPYTHON
)
    if [ "$detection_type" = "simple" ] || [ "$detection_type" = "grep" ]; then
      echo "$pattern_file"
    fi
  done)
fi
```

**Processing Phase (IDENTICAL to v1.x):**
```bash
while IFS= read -r pattern_file; do
  [ -z "$pattern_file" ] && continue
  
  # Load ONE pattern at a time
  if load_pattern "$pattern_file"; then
    # Run grep scan
    matches=$(cached_grep $include_args -E "$pattern_search" || true)
    # Process matches
  fi
done <<< "$SIMPLE_PATTERNS"
```

---

## Key Differences (Not Memory-Related)

| Aspect | v1.x | v2.x | Impact |
|--------|------|------|--------|
| **Discovery** | Filesystem scan every time | Registry lookup (faster) | v2 is faster, not smaller |
| **Fallback** | N/A | Falls back to filesystem | v2 is more resilient |
| **Memory** | One pattern at a time | One pattern at a time | ✅ IDENTICAL |

---

## What v2.x Registry Actually Does

The `PATTERN-LIBRARY.json` registry:
- ✅ Enables faster pattern discovery (no filesystem scan)
- ✅ Provides metadata for filtering/documentation
- ✅ Tracks pattern versions
- ❌ Does NOT load all patterns into memory
- ❌ Does NOT change memory usage

---

## Conclusion

**Both versions use identical memory models:**
- Patterns are discovered (either via registry or filesystem)
- Patterns are processed one-at-a-time in a loop
- Each pattern is loaded, scanned, then released
- No bulk loading into memory

**v2.x is better for:**
- Speed (registry lookup vs filesystem scan)
- Discoverability (metadata available)
- Documentation (statistics generated)
- NOT for memory usage (identical)

---

**Verified by:** Code review of both versions  
**Files examined:**
- v1.x: `git show development:dist/bin/check-performance.sh` (lines 4900-5100)
- v2.x: `dist/bin/check-performance.sh` (lines 5300-5410)

