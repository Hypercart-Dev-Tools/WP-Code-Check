# Phase 3.4: Mitigation Detection Infrastructure

**Created:** 2026-01-15
**Completed:** 2026-01-15
**Status:** ✅ Complete
**Shipped In:** v1.3.17
**Related:** `PHASE-3.3-SIMPLE-T2-MIGRATION.md`, `PATTERN-MIGRATION-TO-JSON.md`

---

## Summary

Building infrastructure to support mitigation detection for JSON patterns. This enables patterns to detect mitigating factors (caching, pagination, guards) and automatically downgrade severity when mitigations are present.

---

## Goals

1. ✅ Create reusable mitigation validators
2. ✅ Extend JSON schema to support mitigation detection
3. ✅ Update pattern loader to extract mitigation config
4. ✅ Update scripted pattern runner to call mitigation validators
5. ✅ Support severity downgrading based on mitigations
6. ✅ Append mitigation info to finding messages
7. ⏳ Migrate remaining 11 T2 patterns that need mitigation detection

---

## Infrastructure Created

### 1. Mitigation Validators

#### `validators/mitigation-check.sh`
- **Purpose:** Generic mitigation detector for performance patterns
- **Detects:**
  - Caching (get_transient, wp_cache_get, update_meta_cache)
  - Pagination (LIMIT, per_page, posts_per_page, number)
  - Guards (if statements, early returns, capability checks)
  - Rate limiting (wp_schedule_event, transient throttling)
  - Hard caps (min/max functions, array_slice)
- **Usage:** `mitigation-check.sh <file> <line_number> [context_lines]`
- **Exit Codes:**
  - 0 = No mitigations found
  - 1 = Mitigations found (prints comma-separated list)
  - 2 = Error

#### `validators/security-guard-check.sh`
- **Purpose:** Security-specific guard detector
- **Detects:**
  - Nonce verification (wp_verify_nonce, check_admin_referer)
  - Capability checks (current_user_can, user_can)
  - Input sanitization (sanitize_*, wp_unslash)
  - Validation guards (early returns, wp_die)
  - CSRF protection (wp_nonce_field, wp_create_nonce)
- **Usage:** `security-guard-check.sh <file> <line_number> [context_lines]`
- **Exit Codes:** Same as mitigation-check.sh

---

### 2. JSON Schema Extension

Added `mitigation_detection` section to pattern JSON schema:

```json
{
  "mitigation_detection": {
    "enabled": true,
    "validator_script": "validators/mitigation-check.sh",
    "validator_args": ["20"],
    "severity_downgrade": {
      "CRITICAL": "HIGH",
      "HIGH": "MEDIUM",
      "MEDIUM": "LOW"
    }
  }
}
```

**Fields:**
- `enabled` (boolean): Enable/disable mitigation detection
- `validator_script` (string): Path to mitigation validator
- `validator_args` (array): Arguments to pass to validator
- `severity_downgrade` (object): Severity mapping when mitigations found

---

### 3. Pattern Loader Updates

**File:** `dist/lib/pattern-loader.sh`

**New Variables Extracted:**
- `pattern_mitigation_enabled` - true/false
- `pattern_mitigation_script` - Path to validator script
- `pattern_mitigation_args` - Space-separated args
- `pattern_severity_downgrade` - Semicolon-separated KEY=VALUE pairs

**Example Output:**
```bash
pattern_mitigation_enabled="true"
pattern_mitigation_script="validators/mitigation-check.sh"
pattern_mitigation_args="20"
pattern_severity_downgrade="CRITICAL=HIGH;HIGH=MEDIUM;MEDIUM=LOW"
```

---

### 4. Scripted Pattern Runner Updates

**File:** `dist/bin/check-performance.sh` (lines 5104-5140)

**Logic Flow:**
1. Run primary validator (confirms issue exists)
2. If issue confirmed, run mitigation validator
3. If mitigations found:
   - Parse severity downgrade map
   - Downgrade severity (CRITICAL → HIGH, etc.)
   - Append mitigation info to message
4. Add finding with adjusted severity and message

**Example Output:**
```
Before: "WP_Query/get_posts with -1 limit or nopaging" [CRITICAL]
After:  "WP_Query/get_posts with -1 limit or nopaging [Mitigated by: caching]" [HIGH]
```

---

## Testing

### Test File: `dist/tests/fixtures/mitigation-isolated-test.php`

**Test Cases:**
1. ✅ Unbounded query WITHOUT mitigation → CRITICAL
2. ✅ Unbounded query WITH caching → HIGH + "[Mitigated by: caching]"
3. ✅ Unbounded query WITH capability check → HIGH + "[Mitigated by: admin-only]"

**Results:**
```json
{
  "line": 12,
  "impact": "CRITICAL",
  "message": "WP_Query/get_posts with -1 limit or nopaging"
}
{
  "line": 51,
  "impact": "HIGH",
  "message": "WP_Query/get_posts with -1 limit or nopaging [Mitigated by: caching]"
}
{
  "line": 93,
  "impact": "HIGH",
  "message": "WP_Query/get_posts with -1 limit or nopaging [Mitigated by: admin-only]"
}
```

---

## Patterns Updated

### `wp-query-unbounded.json`
- **Version:** 1.0.0 → 2.0.0
- **Added:** Mitigation detection with 20-line context
- **Severity Downgrade:** CRITICAL → HIGH, HIGH → MEDIUM, MEDIUM → LOW
- **Status:** ✅ Tested and working

---

## Next Steps

### Remaining T2 Patterns to Migrate (11 patterns)

**With Mitigation Detection (6 patterns):**
1. `wc-unbounded-limit` - WooCommerce queries with limit => -1
2. `get-users-no-limit` - get_users() without number parameter
3. `get-terms-no-limit` - get_terms() without number parameter
4. `wc-get-orders-unbounded` - wc_get_orders() without limit
5. `wc-get-products-unbounded` - wc_get_products() without limit
6. ~~`wp-query-unbounded`~~ - ✅ Already migrated

**With Security Guard Detection (2 patterns):**
7. `superglobal-manipulation` - Direct $_GET/$_POST manipulation
8. `wpdb-unprepared-query` - $wpdb queries without prepare()

**With Complex Logic (3 patterns):**
9. `pre-get-posts-unbounded` - Requires 2-step detection
10. `query-limit-multiplier` - Has severity adjustment logic
11. `n1-meta-in-loop` - Complex context analysis

---

## Lessons Learned

1. **Context Window Size Matters** - 20 lines is a good default, but may need adjustment per pattern
2. **Function Scope Isolation** - Mitigation detector can pick up mitigations from nearby functions if context window is too large
3. **Test Isolation** - Need adequate spacing between test cases to prevent context bleeding
4. **Severity Downgrade Flexibility** - Map-based approach allows different downgrade strategies per pattern

---

## Files Modified

1. `dist/validators/mitigation-check.sh` - NEW
2. `dist/validators/security-guard-check.sh` - NEW
3. `dist/lib/pattern-loader.sh` - Updated (added mitigation extraction)
4. `dist/bin/check-performance.sh` - Updated (added mitigation detection logic)
5. `dist/patterns/wp-query-unbounded.json` - Updated (added mitigation detection)
6. `dist/tests/fixtures/mitigation-isolated-test.php` - NEW (test file)

---

## Metrics

- **New Validators:** 2
- **Patterns Updated:** 1
- **Patterns Ready to Migrate:** 11
- **Code Added:** ~200 lines
- **Test Coverage:** 3 test cases passing

---

## Status

**Current:** Infrastructure complete and tested ✅  
**Next:** Migrate remaining 11 T2 patterns using new infrastructure

