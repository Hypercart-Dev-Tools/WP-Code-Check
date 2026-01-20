# Phase 3.3 Discovery Notes - T2 Pattern Migration Complexity

**Created:** 2026-01-15  
**Status:** Discovery Phase  
**Related:** `PATTERN-MIGRATION-TO-JSON.md`, `PATTERN-INVENTORY.md`

---

## Summary

During Phase 3.3 (migrating remaining 19 T2 patterns), we discovered that many T2 patterns use advanced features that are not yet supported in the JSON pattern infrastructure. This document catalogs these features and proposes solutions.

---

## Discovery: Advanced Features in T2 Patterns

### 1. Mitigation Detection (`get_adjusted_severity`)

**What it does:**
- Analyzes code context to detect mitigating factors (caching, pagination, guards)
- Adjusts severity based on mitigations found
- Appends mitigation info to finding messages

**Example from `wc-unbounded-limit` (lines 3877-3891):**
```bash
# Get adjusted severity based on mitigating factors
mitigation_result=$(get_adjusted_severity "$file" "$lineno" "$WC_UNBOUNDED_SEVERITY")
adjusted_severity=$(echo "$mitigation_result" | cut -d'|' -f1)
mitigations=$(echo "$mitigation_result" | cut -d'|' -f2)

# Build message with mitigation info
message="Unbounded WooCommerce query (limit => -1)"
if [ -n "$mitigations" ]; then
  message="$message [Mitigated by: $mitigations]"
fi
```

**Patterns using this feature:**
- `wc-unbounded-limit` (Rule #21)
- `get-users-no-limit` (Rule #23)
- `get-terms-no-limit` (Rule #24)
- `wc-get-orders-unbounded` (Rule #27)
- `wc-get-products-unbounded` (Rule #28)
- `wp-query-unbounded` (Rule #29)

**Impact:** 6 of 19 T2 patterns (32%)

---

### 2. Security Guard Detection (`detect_guards`)

**What it does:**
- Checks for nonce verification and capability checks in surrounding context
- Downgrades severity if guards are present
- Used for security patterns to reduce false positives

**Example from `superglobal-manipulation` (lines 2887-2906):**
```bash
# Detect security guards (nonce checks, capability checks)
guards=$(detect_guards "$file" "$lineno" 20)

# Downgrade severity if guards are present
adjusted_severity="$SUPERGLOBAL_SEVERITY"
if [ -n "$guards" ]; then
  case "$SUPERGLOBAL_SEVERITY" in
    CRITICAL) adjusted_severity="HIGH" ;;
    HIGH)     adjusted_severity="MEDIUM" ;;
    MEDIUM)   adjusted_severity="LOW" ;;
  esac
fi
```

**Patterns using this feature:**
- `superglobal-manipulation` (Rule #5)
- `wpdb-unprepared-query` (Rule #12) - uses `detect_sql_safety` variant

**Impact:** 2 of 19 T2 patterns (11%)

---

### 3. Complex Context Analysis

**What it does:**
- Multi-step validation with nested checks
- Variable tracking across lines
- Function scope detection

**Example from `wpdb-unprepared-query` (lines 3211-3235):**
```bash
# Extract variable name from $wpdb->get_*( $var )
var_name=$(echo "$code" | sed -n 's/.*\$wpdb->[a-z_]*[[:space:]]*([[:space:]]*\(\$[a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p')

if [ -n "$var_name" ]; then
  range=$(get_function_scope_range "$file" "$lineno" 30)
  function_start=${range%%:*}
  
  # Check if variable was assigned from $wpdb->prepare() within previous 20 lines
  start_line=$((lineno - 20))
  [ "$start_line" -lt "$function_start" ] && start_line="$function_start"
  context=$(sed -n "${start_line},${lineno}p" "$file" 2>/dev/null || true)
  
  # Check for pattern: $var = $wpdb->prepare(...)
  if echo "$context" | grep -qE "${var_escaped}[[:space:]]*=[[:space:]]*\\\$wpdb->prepare"; then
    continue  # Variable was prepared - skip
  fi
fi
```

**Patterns using this feature:**
- `wpdb-unprepared-query` (Rule #12)
- `n1-meta-in-loop` (Rule #37)

**Impact:** 2 of 19 T2 patterns (11%)

---

## Infrastructure Gaps

### Gap 1: No Mitigation Detection in JSON Patterns

**Current state:**
- JSON patterns can only report fixed severity
- No way to adjust severity based on context
- No way to append mitigation info to messages

**Needed:**
- Add `mitigation_detection` section to JSON schema
- Create reusable mitigation validators
- Update scripted pattern runner to call mitigation validators
- Support severity adjustment in JSON findings

**Proposed JSON schema extension:**
```json
{
  "detection": {
    "type": "scripted",
    "search_pattern": "...",
    "validator_script": "..."
  },
  "mitigation_detection": {
    "enabled": true,
    "validator_script": "validators/mitigation-check.sh",
    "severity_adjustment": {
      "CRITICAL": "HIGH",
      "HIGH": "MEDIUM",
      "MEDIUM": "LOW"
    },
    "append_to_message": true
  }
}
```

---

### Gap 2: No Guard Detection in JSON Patterns

**Current state:**
- No support for security guard detection
- No way to check for nonces/capabilities in context

**Needed:**
- Create `validators/security-guard-check.sh`
- Add guard detection to JSON schema
- Integrate with mitigation detection framework

---

### Gap 3: Limited Validator Capabilities

**Current state:**
- Validators can only return 0/1/2 (issue/false-positive/needs-review)
- No way to return structured data (e.g., mitigation details)
- No way to adjust severity from validator

**Needed:**
- Enhanced validator protocol with JSON output
- Support for validators returning metadata
- Backward compatibility with simple exit codes

---

## Completed Work (Phase 3.3 So Far)

### ✅ Added `validator_args` Support

**Files modified:**
1. `dist/lib/pattern-loader.sh` - Extract `validator_args` from JSON
2. `dist/bin/check-performance.sh` - Pass args to validator scripts

**Benefit:** Validators can now be parameterized (e.g., parameter name, context lines)

**Example:**
```json
{
  "detection": {
    "validator_script": "validators/parameter-presence-check.sh",
    "validator_args": ["number", "10"]
  }
}
```

### ✅ Created Reusable Validator: `parameter-presence-check.sh`

**Purpose:** Check if a parameter exists in context window  
**Usage:** `parameter-presence-check.sh <file> <line> <param_name> [context_lines]`  
**Exit codes:**
- 0 = Parameter NOT found (issue)
- 1 = Parameter found (false positive)
- 2 = Error

**Can be reused for:**
- `get-users-no-limit` (check for 'number')
- `get-terms-no-limit` (check for 'number')
- `wp-user-query-no-cache` (check for 'cache_results')
- Any pattern that checks for parameter presence

---

## Recommended Next Steps

### Option A: Complete Infrastructure First (Recommended)

1. **Implement mitigation detection framework** (~4 hours)
   - Add JSON schema support
   - Create `validators/mitigation-check.sh`
   - Update scripted pattern runner
   - Test with 1-2 patterns

2. **Migrate patterns with mitigation detection** (~3 hours)
   - 6 patterns use `get_adjusted_severity`
   - Can reuse mitigation validator

3. **Migrate remaining simple T2 patterns** (~2 hours)
   - 11 patterns without advanced features
   - Use existing validators

**Total effort:** ~9 hours (1-2 days)

### Option B: Migrate Simple Patterns First

1. **Identify truly simple T2 patterns** (no mitigation, no guards)
2. **Migrate those first** (~2 hours for ~5-7 patterns)
3. **Defer complex patterns** to Phase 4

**Total effort:** ~2 hours (quick wins)

---

## Pattern Categorization by Complexity

### Simple T2 (can migrate now with existing infrastructure):
- `ajax-polling-unbounded` (Rule #14) - simple grep
- `hcc-005-expensive-polling` (Rule #15) - context check
- `rest-no-pagination` (Rule #16) - grep + context
- `wcs-no-limit` (Rule #22) - simple grep
- `pre-get-posts-unbounded` (Rule #25) - hook detection
- `unbounded-sql-terms` (Rule #26) - LIMIT check
- `query-limit-multiplier` (Rule #31) - heuristic pattern
- `like-leading-wildcard` (Rule #36) - LIKE pattern
- `http-no-timeout` (Rule #45) - context check

**Count:** 9 patterns (~47%)

### T2 with Mitigation Detection (need infrastructure):
- `wc-unbounded-limit` (Rule #21)
- `get-users-no-limit` (Rule #23)
- `get-terms-no-limit` (Rule #24)
- `wc-get-orders-unbounded` (Rule #27)
- `wc-get-products-unbounded` (Rule #28)
- `wp-query-unbounded` (Rule #29)

**Count:** 6 patterns (~32%)

### T2 with Guard Detection (need infrastructure):
- `superglobal-manipulation` (Rule #5)
- `wpdb-unprepared-query` (Rule #12)

**Count:** 2 patterns (~11%)

### T2 with Complex Analysis (may need custom validators):
- `wp-user-query-no-cache` (Rule #30) - cache_results check
- `n1-meta-in-loop` (Rule #37) - loop + meta detection

**Count:** 2 patterns (~11%)

---

## Conclusion

**Phase 3.3 is more complex than initially estimated** due to advanced features in T2 patterns. We have two viable paths forward:

1. **Build infrastructure** to support all features → migrate all 19 patterns
2. **Migrate simple patterns** now → defer complex ones to Phase 4

**Recommendation:** Option B (migrate 9 simple patterns now) for quick progress, then build infrastructure for remaining 10 patterns.


