# HCC Security & Performance Rules
## High-Confidence Check Rules for Neochrome WP Toolkit

**Status:** ✅ **COMPLETED** - HCC-001 and HCC-002 (CRITICAL rules) implemented and tested
**Generated:** 2025-12-31
**Implemented:** 2025-12-31
**Based on:** AUDIT-2025-12-31.md findings
**Tool:** check-performance.sh grep-based pattern detection

---

## Overview

This document defines new grep-based rules that could have caught the security and performance issues identified in the 2025-12-31 audit. These rules are designed to be added to the `check-performance.sh` script to prevent similar issues in future code.

---

## Rule Categories

### 1. Client-Side Data Exposure (CRITICAL)

#### Rule: HCC-001 - Sensitive Data in localStorage/sessionStorage
**Status:** ✅ **IMPLEMENTED** (2025-12-31)
**Audit Finding:** Issue #1 - Cached plugin inventory exposed to front-end visitors
**Impact:** CRITICAL
**Can Be Caught:** ✅ YES
**Location:** Lines 1430-1443 in dist/bin/check-performance.sh

**Pattern:**
```bash
run_check "ERROR" "CRITICAL" "Sensitive data stored in localStorage/sessionStorage" "hcc-001-localstorage-exposure" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*plugin" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*cache" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*user" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*admin" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*plugin" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*cache" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*user" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*admin"
```

**Rationale:**
Detects when sensitive plugin/user/admin data is being stored in browser storage that is accessible to front-end scripts. This would have caught the `pqs_plugin_cache` localStorage usage.

**Recommendation:**
Flag any localStorage/sessionStorage usage containing keywords: plugin, cache, user, admin, settings, version, activation, capability.

STATUS: COMPLETED

---

#### Rule: HCC-002 - Serialization of Sensitive Objects to Client Storage
**Status:** ✅ **IMPLEMENTED** (2025-12-31)
**Audit Finding:** Issue #1 - Plugin inventory serialized to localStorage
**Impact:** CRITICAL
**Can Be Caught:** ✅ YES
**Location:** Lines 1445-1451 in dist/bin/check-performance.sh

**Pattern:**
```bash
run_check "ERROR" "CRITICAL" "Serialization of sensitive data to client storage" "hcc-002-client-serialization" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*JSON\\.stringify" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*JSON\\.stringify" \
  "-E localStorage\\[[^]]*\\][[:space:]]*=[[:space:]]*JSON\\.stringify"
```

**Rationale:**
Detects when objects are being serialized (JSON.stringify) and stored in browser storage, which often contains sensitive metadata.

**Recommendation:**
Review all client-side serialization to ensure no sensitive data (versions, activation states, settings URLs) is exposed.

STATUS: COMPLETED

---

### 2. Cache Invalidation & Persistence (HIGH)

#### Rule: HCC-003 - Missing Cache Invalidation on Logout
**Audit Finding:** Issue #2 - Sensitive plugin state persists indefinitely
**Impact:** HIGH
**Can Be Caught:** ⚠️ PARTIAL

**Pattern:**
```bash
# Check for logout hooks without cache clearing
text_echo "${BLUE}▸ Logout handlers without cache invalidation ${RED}[HIGH]${NC}"
LOGOUT_CACHE_MISSING=false
LOGOUT_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" --include="*.js" -E "wp_logout|logout|signout" $PATHS 2>/dev/null || true)
if [ -n "$LOGOUT_FILES" ]; then
  for file in $LOGOUT_FILES; do
    logout_count=$(grep -E "wp_logout|logout|signout" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')
    cache_clear_count=$(grep -E "localStorage\\.clear|sessionStorage\\.clear|removeItem|delete_transient|wp_cache_delete" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')

    if [ "$logout_count" -gt 0 ] && [ "$cache_clear_count" -eq 0 ]; then
      # Flag as missing cache invalidation
      LOGOUT_CACHE_MISSING=true
    fi
  done
fi
```

**Rationale:**
Detects logout/signout handlers that don't clear cached data. This is a heuristic check that would flag files with logout logic but no cache clearing.

**Limitation:**
Cannot definitively prove cache invalidation is missing (cache clearing might be in a different file), but raises awareness.

---

#### Rule: HCC-004 - localStorage Without TTL/Expiry Check
**Audit Finding:** Issue #2 - Cache never expires until code executes
**Impact:** HIGH
**Can Be Caught:** ⚠️ PARTIAL

**Pattern:**
```bash
run_check "WARNING" "HIGH" "localStorage usage without expiry/TTL validation" "hcc-004-no-cache-ttl" \
  "-E localStorage\\.getItem[[:space:]]*\\([^)]*\\)[[:space:]]*(?!.*timestamp|expir|ttl|age)"
```

**Rationale:**
Flags localStorage reads that don't appear to check timestamps or expiry. This is a heuristic that would catch simple cases.

**Limitation:**
Regex cannot reliably detect if expiry logic exists elsewhere in the code flow. Requires manual review.

---

### 3. Performance - Unbounded Polling (HIGH)

#### Rule: HCC-005 - Expensive Server Calls in Polling Loops
**Status:** ✅ **IMPLEMENTED** (2025-12-31)
**Audit Finding:** Issue #3 - get_plugins() called every 30s
**Impact:** HIGH
**Can Be Caught:** ✅ YES (Enhanced)
**Location:** Lines 1612-1668 in dist/bin/check-performance.sh

**Pattern:**
```bash
# Enhance existing AJAX polling check to detect expensive WP functions
text_echo "${BLUE}▸ Expensive WP functions in polling intervals ${RED}[HIGH]${NC}"
EXPENSIVE_POLLING=false
POLLING_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.js" --include="*.php" -E "setInterval[[:space:]]*\\(" $PATHS 2>/dev/null || true)
if [ -n "$POLLING_MATCHES" ]; then
  while IFS= read -r match; do
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)

    # Check for expensive WP functions in context
    start_line=$lineno
    end_line=$((lineno + 20))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null)

    if echo "$context" | grep -qE "get_plugins\\(|get_themes\\(|get_posts\\(|WP_Query|get_users\\("; then
      EXPENSIVE_POLLING=true
      # Flag this finding
    fi
  done <<< "$POLLING_MATCHES"
fi
```

**Rationale:**
Extends the existing AJAX polling check to specifically detect expensive WordPress functions (get_plugins, get_themes, WP_Query, get_users) being called in polling intervals.

**Recommendation:**
Flag any setInterval that calls: get_plugins(), get_themes(), get_posts(), new WP_Query(), get_users(), or filesystem operations.

**Implementation Notes:**
- Scans both `.js` and `.php` files (PHP files may contain inline `<script>` tags)
- Searches for `setInterval()` calls, then checks 20 lines of context for expensive functions
- Detects: `get_plugins()`, `get_themes()`, `get_posts()`, `WP_Query`, `get_users()`, `wp_get_recent_posts()`, `get_categories()`, `get_terms()`
- Works even when expensive functions are mentioned in comments (helps catch documentation of backend calls)
- Separate from the basic AJAX polling check - focuses specifically on expensive operations

---

#### Rule: HCC-006 - Polling Without Visibility/Idle Detection
**Audit Finding:** Issue #3 - No visibility check to pause polling
**Impact:** MEDIUM
**Can Be Caught:** ⚠️ PARTIAL

**Pattern:**
```bash
run_check "WARNING" "MEDIUM" "setInterval without Page Visibility API check" "hcc-006-no-visibility-check" \
  "-E setInterval[[:space:]]*\\(" \
  --exclude-pattern "document\\.hidden|visibilityState|pageVisibility"
```

**Rationale:**
Flags setInterval usage that doesn't appear to use the Page Visibility API to pause when tab is hidden.

**Limitation:**
Negative pattern matching is imperfect; requires manual review to confirm visibility checks are truly missing.

---

### 4. Undefined Variables & Configuration Errors (HIGH)

#### Rule: HCC-007 - Reference to Undefined Configuration Objects
**Audit Finding:** Issue #4 - highlightSettings undefined, only pluginSettings exists
**Impact:** HIGH
**Can Be Caught:** ❌ NO (Requires Static Analysis)

**Pattern:**
```bash
# This cannot be reliably caught with grep alone
# Requires JavaScript static analysis or linting (ESLint, TypeScript)
```

**Rationale:**
Grep cannot track variable scope or detect undefined references. This requires:
- ESLint with `no-undef` rule
- TypeScript type checking
- JSHint/JSLint

**Recommendation:**
Add ESLint to the build pipeline with strict rules:
```json
{
  "rules": {
    "no-undef": "error",
    "no-unused-vars": "warn"
  }
}
```

**Alternative Heuristic (Low Confidence):**
```bash
# Flag common typo patterns in settings access
run_check "WARNING" "MEDIUM" "Potential undefined settings object access" "hcc-007-undefined-settings" \
  "-E highlightSettings\\." \
  "-E pluginSetting\\." \
  "-E userSettings\\." \
  "-E configSettings\\."
```

This would catch the specific `highlightSettings` typo but is not a general solution.

---

### 5. Unsafe RegExp Construction (MEDIUM)

#### Rule: HCC-008 - User Input in RegExp Without Escaping
**Status:** ✅ **IMPLEMENTED** (2025-12-31)
**Audit Finding:** Issue #5 - new RegExp('\\b' + lowerQuery + '\\b', 'i') with raw input
**Impact:** MEDIUM
**Can Be Caught:** ✅ YES
**Location:** Lines 1465-1474 in dist/bin/check-performance.sh

**Pattern:**
```bash
run_check "ERROR" "MEDIUM" "User input in RegExp constructor without escaping" "hcc-008-unsafe-regexp" \
  "-E new[[:space:]]+RegExp[[:space:]]*\\([^)]*\\+[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*" \
  "-E RegExp[[:space:]]*\\([^)]*\\$\\{[^}]*\\}"
```

**Rationale:**
Detects RegExp constructors that concatenate variables (likely user input) without escaping. Catches patterns like:
- `new RegExp('\\b' + query + '\\b')`
- `new RegExp(\`pattern${userInput}\`)`

**Recommendation:**
Flag all dynamic RegExp construction and require escaping via a helper function.

**Implementation Notes:**
- Scans `.js`, `.jsx`, `.ts`, `.tsx`, and `.php` files
- Uses single `-E` pattern with alternation (`|`) for BSD grep compatibility
- Pattern 1: Detects string concatenation with `+` operator: `RegExp(...) + `
- Pattern 2: Detects template literals with variables: `RegExp...${`
- Catches both `new RegExp()` and `RegExp()` (without `new`)
- **Known Limitation:** Cannot detect if variables have been properly escaped (e.g., `query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')`)
- **Expected False Positives:** Properly escaped variables will still be flagged (developers must manually verify escaping)

---

## Implementation Priority

### Immediate (Can Add to check-performance.sh Today)

1. ✅ **HCC-001** - localStorage sensitive data detection
2. ✅ **HCC-002** - Client-side serialization detection
3. ✅ **HCC-005** - Expensive functions in polling (enhance existing rule)
4. ✅ **HCC-008** - Unsafe RegExp construction

### Medium-Term (Requires Enhanced Scripting)

5. ⚠️ **HCC-003** - Logout cache invalidation (heuristic check)
6. ⚠️ **HCC-004** - localStorage TTL validation (heuristic check)
7. ⚠️ **HCC-006** - Visibility API detection (negative pattern)

### Long-Term (Requires Additional Tools)

8. ❌ **HCC-007** - Undefined variables (requires ESLint/TypeScript)

---

## Recommended Script Additions

Add these checks to `check-performance.sh` after line 1260 (after existing debug code check):

```bash
# ============================================================================
# HCC RULES - High-Confidence Checks from 2025-12-31 Audit
# ============================================================================

text_echo "${RED}━━━ HCC SECURITY CHECKS (Client-Side Data Exposure) ━━━${NC}"
text_echo ""

# HCC-001: Sensitive data in localStorage/sessionStorage
OVERRIDE_GREP_INCLUDE="--include=*.js --include=*.jsx --include=*.ts --include=*.tsx"
run_check "ERROR" "CRITICAL" "Sensitive data in localStorage/sessionStorage" "hcc-001-localstorage-exposure" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*plugin" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*cache" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*user" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*admin" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*plugin"
unset OVERRIDE_GREP_INCLUDE

# HCC-002: Serialization to client storage
OVERRIDE_GREP_INCLUDE="--include=*.js --include=*.jsx --include=*.ts --include=*.tsx"
run_check "ERROR" "CRITICAL" "Serialization of objects to client storage" "hcc-002-client-serialization" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*JSON\\.stringify" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*JSON\\.stringify"
unset OVERRIDE_GREP_INCLUDE

# HCC-008: Unsafe RegExp construction
OVERRIDE_GREP_INCLUDE="--include=*.js --include=*.jsx --include=*.ts --include=*.tsx --include=*.php"
run_check "ERROR" "MEDIUM" "User input in RegExp without escaping" "hcc-008-unsafe-regexp" \
  "-E new[[:space:]]+RegExp[[:space:]]*\\([^)]*\\+" \
  "-E RegExp[[:space:]]*\\([^)]*\\$\\{"
unset OVERRIDE_GREP_INCLUDE

text_echo ""
```

---

## Summary

**Total Rules Defined:** 8
**Immediately Implementable:** 4 (HCC-001, 002, 005, 008)
**Heuristic/Partial:** 3 (HCC-003, 004, 006)
**Requires Additional Tools:** 1 (HCC-007)

**Audit Coverage:**
- ✅ Issue #1 (localStorage exposure): **Fully covered** by HCC-001, HCC-002
- ⚠️ Issue #2 (Cache persistence): **Partially covered** by HCC-003, HCC-004
- ✅ Issue #3 (Polling performance): **Fully covered** by HCC-005 (enhanced existing rule)
- ❌ Issue #4 (Undefined config): **Not covered** by grep (requires ESLint)
- ✅ Issue #5 (Unsafe RegExp): **Fully covered** by HCC-008

**Overall Audit Detection Rate:** 60% fully covered, 20% partially covered, 20% requires additional tooling

---

## Next Steps

1. **Immediate:** Add HCC-001, HCC-002, HCC-008 to check-performance.sh
2. **Week 1:** Enhance existing AJAX polling check with HCC-005 patterns
3. **Week 2:** Implement heuristic checks HCC-003, HCC-004, HCC-006
4. **Month 1:** Integrate ESLint into CI/CD pipeline for HCC-007
5. **Ongoing:** Run checks on all new code before merge

---

**Document Version:** 1.0
**Last Updated:** 2025-12-31
**Maintainer:** Development Team
