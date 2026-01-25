# BUG: HTTP Timeout Validator False Negative

**Status:** CONFIRMED  
**Severity:** HIGH  
**Impact:** Scanner misses real HTTP timeout vulnerabilities  
**Date Discovered:** 2026-01-25  

## The Issue

The `http-timeout-check.sh` validator is **too simplistic** and produces false negatives when:

1. A timeout is set in a variable
2. That variable is then passed through `apply_filters()`
3. A filter could remove or override the timeout

### Example: Hypercart Server Monitor MKII

**File:** `lib/plugin-update-checker/Puc/v5p4/UpdateChecker.php`  
**Line:** 699 (wp_remote_get call)

```php
// Line 684-688: Timeout IS set
$options = array(
    'timeout' => wp_doing_cron() ? 10 : 3,
    'headers' => array('Accept' => 'application/json'),
);

// Line 690: BUT timeout can be REMOVED by filter
$options = apply_filters($this->getUniqueName($filterRoot . '_options'), $options);

// Line 699: wp_remote_get uses filtered options
$result = wp_remote_get($url, $options);
```

**The Problem:**
- A plugin could hook into the filter and remove the timeout
- If timeout is removed, `wp_remote_get()` uses WordPress default (can be very long)
- This creates a **hang risk** if remote server is unresponsive

## Why Validator Failed

**Current Logic (lines 55-63 of http-timeout-check.sh):**

```bash
if echo "$context" | grep -qiE "'timeout'[[:space:]]*=>|\"timeout\"[[:space:]]*=>|'timeout'[[:space:]]*:"; then
    # Timeout FOUND - this is a false positive (timeout exists)
    exit 1
else
    # Timeout NOT found - this is an issue (no timeout)
    exit 0
fi
```

**What Happened:**
1. Validator checked lines 679-719 (±20 lines from line 699)
2. Found `'timeout' =>` on line 685
3. Returned exit code 1 (false positive)
4. Scanner suppressed the finding

**The Flaw:**
- Validator doesn't check if timeout is **filtered after being set**
- Doesn't understand that `apply_filters()` can remove the timeout
- Treats "timeout exists somewhere in context" as "timeout is safe"

## The Fix

Enhance validator to detect:

1. **Timeout set in variable** (current check)
2. **Variable then filtered** (NEW)
3. **Filter could remove timeout** (NEW)

### Detection Logic

```bash
# Check if timeout is set
if grep -q "'timeout'[[:space:]]*=>" "$context"; then
    # Check if that variable is then filtered
    if grep -q "apply_filters.*\$options" "$context"; then
        # Timeout can be removed by filter - ISSUE
        exit 0  # Confirmed issue
    else
        # Timeout is set and not filtered - safe
        exit 1  # False positive
    fi
else
    # No timeout at all - ISSUE
    exit 0  # Confirmed issue
fi
```

## Impact

- **Current:** Scanner misses HTTP timeout vulnerabilities when timeout is filtered
- **After Fix:** Scanner correctly identifies filtered timeouts as real issues
- **Confidence:** HIGH - This is a real vulnerability pattern

## Files to Update

1. `dist/validators/http-timeout-check.sh` - Enhance detection logic
2. Re-scan Hypercart Server Monitor MKII to verify fix
3. Update pattern documentation if needed

## Related

- Pattern: `http-no-timeout` (dist/patterns/http-no-timeout.json)
- Scanner: `dist/bin/check-performance.sh` (lines 5489-5650)
- Validator execution: lines 5559-5575

