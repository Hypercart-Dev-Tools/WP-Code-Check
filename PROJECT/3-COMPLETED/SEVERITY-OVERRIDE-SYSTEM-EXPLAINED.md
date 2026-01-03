# Severity Override System - How It Works

**Date:** 2026-01-01  
**Version:** 1.0.69  
**Question:** How do pattern JSON files work with the severity override system?

---

## 🎯 Quick Answer

**Pattern JSON files** and **severity override system** are **separate but complementary**:

1. **Pattern JSON files** (`dist/patterns/*.json`) define:
   - Detection logic (grep patterns, exclusions)
   - Test fixtures and expected violations
   - IRL examples and remediation guidance
   - **Factory default severity** (stored in `severity` field)

2. **Severity override system** (`dist/config/severity-levels.json`) allows:
   - **User customization** of severity levels per project
   - **Centralized configuration** for all 33 patterns
   - **Runtime override** via `--severity-config <path>` flag

3. **How they work together:**
   - Pattern JSON provides the **default severity**
   - Severity config file provides **user overrides**
   - Scanner uses `get_severity()` function to **merge both sources**

---

## 📊 Two-Tier Severity System

### Tier 1: Pattern JSON Files (Pattern Definitions)
**Location:** `dist/patterns/*.json`  
**Purpose:** Define pattern metadata and factory defaults  
**Scope:** Individual patterns (4 files currently)

**Example:** `dist/patterns/unsanitized-superglobal-read.json`
```json
{
  "id": "unsanitized-superglobal-read",
  "severity": "HIGH",  ← Factory default severity
  "category": "security",
  "detection": { ... },
  "test_fixture": { ... },
  "irl_examples": [ ... ]
}
```

### Tier 2: Severity Config File (User Overrides)
**Location:** `dist/config/severity-levels.json`  
**Purpose:** Centralized severity customization for all patterns  
**Scope:** All 33 patterns in one file

**Example:** `dist/config/severity-levels.json`
```json
{
  "severity_levels": {
    "unsanitized-superglobal-read": {
      "id": "unsanitized-superglobal-read",
      "level": "HIGH",  ← User can change this
      "factory_default": "HIGH",  ← Reference (don't change)
      "category": "security",
      "_comment": "Downgraded to MEDIUM for legacy code"
    }
  }
}
```

---

## 🔧 How the Scanner Resolves Severity

### The `get_severity()` Function

**Location:** `dist/bin/check-performance.sh` (line 362)

```bash
get_severity() {
  local rule_id="$1"
  local fallback="${2:-MEDIUM}"
  local severity=""

  # Step 1: Try custom config file (user override)
  if [ -n "$SEVERITY_CONFIG_FILE" ] && [ -f "$SEVERITY_CONFIG_FILE" ]; then
    severity=$(jq -r ".severity_levels[\"$rule_id\"].level // empty" "$SEVERITY_CONFIG_FILE")
  fi

  # Step 2: If not found, try factory defaults
  if [ -z "$severity" ] && [ -f "$REPO_ROOT/config/severity-levels.json" ]; then
    severity=$(jq -r ".severity_levels[\"$rule_id\"].level // empty" "$REPO_ROOT/config/severity-levels.json")
  fi

  # Step 3: If still not found, use fallback
  if [ -z "$severity" ]; then
    severity="$fallback"
  fi

  echo "$severity"
}
```

### Resolution Order (Priority)

1. **User custom config** (via `--severity-config <path>`)
2. **Factory defaults** (`dist/config/severity-levels.json`)
3. **Hardcoded fallback** (passed to `get_severity()`)

---

## 🔄 Integration Example

### Pattern JSON File
**File:** `dist/patterns/wpdb-query-no-prepare.json`
```json
{
  "id": "wpdb-query-no-prepare",
  "severity": "CRITICAL",  ← Factory default
  ...
}
```

### Severity Config File
**File:** `dist/config/severity-levels.json`
```json
{
  "severity_levels": {
    "wpdb-query-no-prepare": {
      "id": "wpdb-query-no-prepare",
      "level": "CRITICAL",  ← Can be overridden by user
      "factory_default": "CRITICAL",
      "category": "security"
    }
  }
}
```

### Scanner Usage
**File:** `dist/bin/check-performance.sh` (line 1648)
```bash
# Get severity (checks custom config, then factory defaults, then fallback)
WPDB_SEVERITY=$(get_severity "wpdb-query-no-prepare" "CRITICAL")

# Use the resolved severity
text_echo "${BLUE}▸ Direct database queries without \$wpdb->prepare() ${WPDB_COLOR}[$WPDB_SEVERITY]${NC}"
```

### User Override Example
**User creates:** `my-project-severity.json`
```json
{
  "severity_levels": {
    "wpdb-query-no-prepare": {
      "level": "HIGH",  ← Downgraded from CRITICAL
      "_reason": "Legacy codebase, fixing incrementally",
      "_ticket": "JIRA-1234"
    }
  }
}
```

**Run scanner with override:**
```bash
./dist/bin/check-performance.sh --severity-config my-project-severity.json
```

**Result:** Scanner uses `HIGH` instead of `CRITICAL` for this pattern.

---

## 📝 Current State (v1.0.69)

### Pattern JSON Files (4 total)
| Pattern ID | JSON File | Severity in JSON | Severity in Config |
|------------|-----------|------------------|-------------------|
| unsanitized-superglobal-isset-bypass | ✅ | HIGH | HIGH |
| unsanitized-superglobal-read | ✅ | HIGH | HIGH |
| wpdb-query-no-prepare | ✅ | CRITICAL | CRITICAL |
| get-users-no-limit | ✅ | CRITICAL | CRITICAL |

### Severity Config File
**File:** `dist/config/severity-levels.json`  
**Patterns:** All 33 patterns defined  
**Status:** ✅ Complete

### Scanner Integration
**Status:** ✅ All 33 patterns use `get_severity()`  
**Fallback:** Hardcoded severity as second parameter to `get_severity()`

---

## 🎯 Design Philosophy

### Why Two Systems?

**Pattern JSON Files:**
- **Purpose:** Pattern library for documentation and testing
- **Audience:** Developers, contributors, pattern authors
- **Content:** Detection logic, examples, remediation
- **Scope:** Individual patterns (modular)
- **Future:** Load detection logic from JSON (not yet implemented)

**Severity Config File:**
- **Purpose:** User customization for specific projects
- **Audience:** End users, DevOps teams
- **Content:** Severity levels only
- **Scope:** All patterns in one file (centralized)
- **Current:** Fully implemented and integrated

### Why Not Merge Them?

**Separation of Concerns:**
1. **Pattern definitions** (JSON files) = **What to detect**
2. **Severity config** (single file) = **How severe it is for your project**

**Benefits:**
- Users don't need to edit pattern JSON files
- Pattern JSON files can be version-controlled separately
- Severity overrides are project-specific (not pattern-specific)
- Easier to share patterns without sharing severity preferences

---

## 🚀 Future Enhancements

### Phase 1: Pattern Library (In Progress)
- ✅ Create pattern JSON files (4/33 done)
- ⏭️ Create remaining 29 pattern JSON files
- ⏭️ Load detection logic from JSON (not just metadata)

### Phase 2: Severity System (Complete)
- ✅ Centralized severity config file
- ✅ `get_severity()` function
- ✅ All 33 patterns use dynamic severity
- ✅ User override via `--severity-config`

### Phase 3: Integration (Future)
- ⏭️ Scanner loads patterns from JSON files
- ⏭️ Pattern JSON files become the source of truth
- ⏭️ Severity config file remains for user overrides
- ⏭️ Deprecate hardcoded patterns in scanner

---

## 📂 File Locations

**Pattern JSON Files:**
- `dist/patterns/unsanitized-superglobal-isset-bypass.json`
- `dist/patterns/unsanitized-superglobal-read.json`
- `dist/patterns/wpdb-query-no-prepare.json`
- `dist/patterns/get-users-no-limit.json`

**Severity Config:**
- `dist/config/severity-levels.json` (factory defaults)
- User creates custom file anywhere (e.g., `my-severity.json`)

**Scanner:**
- `dist/bin/check-performance.sh` (uses `get_severity()` function)

---

## 💡 TL;DR

**Q: Is the override set within each new JSON file?**

**A: No.** The pattern JSON files contain the **factory default severity**, but **user overrides** are set in a **separate centralized config file** (`dist/config/severity-levels.json` or custom file via `--severity-config`).

**How it works:**
1. Pattern JSON defines default: `"severity": "CRITICAL"`
2. Severity config allows override: `"level": "HIGH"`
3. Scanner uses `get_severity()` to merge: **User override wins**

**Why separate?**
- Pattern JSON = Pattern definition (what to detect)
- Severity config = User preference (how severe for your project)
- Separation of concerns = Easier to maintain and customize

