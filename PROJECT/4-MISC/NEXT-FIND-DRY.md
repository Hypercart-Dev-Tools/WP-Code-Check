# WP Code Check - Magic String Detector ("DRY") (Pragmatic 3-Phase Plan)

**Created:** 2026-01-01
**Status:** Planning
**Goal:** Detect WordPress-specific magic strings (DRY violations) using grep-based pattern matching with JSON pattern files

---

## 🎯 Executive Summary

This plan adapts the grep-first Magic String Detector ("DRY") approach from `FIND-DRY.md` to the **WP Code Check** codebase. We'll leverage the existing pattern infrastructure (`dist/patterns/*.json`) and grep engine to find high-impact magic strings (duplicated literals) in WordPress codebases.

**Key Decision:** Start with **2-3 patterns** in Phase 1 as proof-of-concept to validate the approach before expanding.

---

## 📊 Current State Analysis

### What We Have
- ✅ **Existing pattern infrastructure** (`dist/patterns/` with 4 JSON patterns)
- ✅ **Pattern loader library** (`dist/lib/pattern-loader.sh`)
- ✅ **Grep-based detection engine** (`dist/bin/check-performance.sh`)
- ✅ **Test fixture system** (`dist/tests/fixtures/`)
- ✅ **JSON/HTML reporting** (already generates reports)
- ✅ **Baseline suppression** (for managing technical debt)

### What We Need
- ❌ **Magic String Detector patterns** (option names, transient keys, meta keys, capability strings)
- ❌ **Aggregation logic** (count occurrences across files, group by match)
- ❌ **Threshold-based reporting** (only report if seen in N+ files)
- ❌ **Magic String Detector test fixtures** (demonstrate duplication patterns)

---

## 🚀 Phase 1: Proof of Concept (2-3 Patterns)

**Goal:** Validate the approach with high-signal, low-noise patterns that demonstrate immediate value.

**Timeline:** 1-2 days  
**Success Criteria:** Patterns detect real duplication in test fixtures and IRL examples with <10% false positives

### Selected Patterns (Pick 2-3)

#### Pattern 1: **Duplicate Option Names** (HIGHEST PRIORITY)
- **Why:** Option names scattered across files are a major WordPress DRY violation
- **Detection:** `get_option\(['"]([a-z0-9_]+)['"]\)` with aggregation
- **Threshold:** Report if same option name appears in 3+ files
- **Severity:** MEDIUM
- **Category:** duplication
- **Example:**
  ```php
  // ❌ BAD: Scattered across 5 files
  get_option( 'my_plugin_api_key' );
  update_option( 'my_plugin_api_key', $key );
  
  // ✅ GOOD: Centralized constants
  define( 'MY_PLUGIN_OPTION_API_KEY', 'my_plugin_api_key' );
  get_option( MY_PLUGIN_OPTION_API_KEY );
  ```

#### Pattern 2: **Duplicate Transient Keys** (HIGH PRIORITY)
- **Why:** Transient keys are often copy-pasted, leading to cache invalidation bugs
- **Detection:** `(get|set|delete)_transient\(['"]([a-z0-9_]+)['"]\)` with aggregation
- **Threshold:** Report if same transient key appears in 3+ files
- **Severity:** MEDIUM
- **Category:** duplication
- **Example:**
  ```php
  // ❌ BAD: Same key in multiple files
  set_transient( 'user_data_cache', $data, HOUR_IN_SECONDS );
  get_transient( 'user_data_cache' );
  
  // ✅ GOOD: Centralized constants
  define( 'CACHE_KEY_USER_DATA', 'user_data_cache' );
  set_transient( CACHE_KEY_USER_DATA, $data, HOUR_IN_SECONDS );
  ```

#### Pattern 3: **Duplicate Capability Strings** (MEDIUM PRIORITY)
- **Why:** Capability strings scattered across files make permission changes risky
- **Detection:** `current_user_can\(['"]([a-z0-9_]+)['"]\)` with aggregation
- **Threshold:** Report if same capability appears in 5+ files
- **Severity:** LOW
- **Category:** duplication
- **Example:**
  ```php
  // ❌ BAD: Scattered across 8 files
  if ( ! current_user_can( 'manage_options' ) ) { return; }
  
  // ✅ GOOD: Centralized capability checks
  if ( ! MyPlugin\Security::can_manage_settings() ) { return; }
  ```

### Deliverables
1. **3 JSON pattern files** in `dist/patterns/dry/`
   - `duplicate-option-names.json`
   - `duplicate-transient-keys.json`
   - `duplicate-capability-strings.json`

2. **Aggregation script** (`dist/bin/find-dry.sh`)
   - Loads patterns from `dist/patterns/dry/`
   - Runs grep, groups by match, counts occurrences
   - Reports only matches exceeding thresholds
   - Outputs Markdown summary + JSON report

3. **Test fixtures** (`dist/tests/fixtures/dry/`)
   - `duplicate-options.php` (10+ files with same option names)
   - `duplicate-transients.php` (5+ files with same transient keys)
   - `duplicate-capabilities.php` (8+ files with same capability strings)

4. **Documentation**
   - Update `dist/README.md` with DRY detection section
   - Add `dist/patterns/dry/README.md` explaining pattern format

### Phase 1 Exit Criteria
- [ ] All 3 patterns detect violations in test fixtures
- [ ] Patterns detect real duplication in at least 1 IRL WordPress plugin
- [ ] False positive rate < 10% (manually verified on 2-3 real plugins)
- [ ] Aggregation script runs in < 5 seconds on 10k file codebase
- [ ] Team agrees: "This is useful, let's continue"

---

## 🔧 Phase 2: Expand Pattern Library (5-8 More Patterns)

**Goal:** Add more WordPress-specific Magic String Detector patterns based on Phase 1 learnings.

**Timeline:** 3-5 days  
**Prerequisites:** Phase 1 complete and validated

### Additional Patterns (Select 5-8)

1. **Duplicate Meta Keys** (`get_post_meta`, `update_post_meta`)
2. **Duplicate Nonce Action Strings** (`wp_create_nonce`, `wp_verify_nonce`)
3. **Duplicate AJAX Action Names** (`wp_ajax_*` hooks)
4. **Duplicate REST Route Paths** (`register_rest_route`)
5. **Duplicate SQL Table Names** (custom table references)
6. **Duplicate Error Messages** (repeated error strings)
7. **Duplicate Hook Names** (`do_action`, `apply_filters` with string literals)
8. **Duplicate Shortcode Names** (`add_shortcode` with string literals)

### Enhancements
- **Churn-aware prioritization:** Rank duplicates in frequently-changed files higher
- **Cross-file clustering:** Group files sharing the same duplicated strings
- **Baseline integration:** Allow suppressing known duplicates in legacy code
- **HTML report section:** Add "Magic String Violations" section to existing HTML reports

### Phase 2 Exit Criteria
- [ ] 8-10 total Magic String Detector patterns enabled
- [ ] Patterns integrated into main `check-performance.sh` workflow
- [ ] Magic String violations appear in HTML reports
- [ ] CI/CD integration (warn-only mode)
- [ ] Documentation complete with remediation examples

---

## 🎓 Phase 3: Advanced Detection & Remediation Guidance

**Goal:** Add lightweight structure analysis and LLM-powered refactoring suggestions.

**Timeline:** 5-7 days
**Prerequisites:** Phase 2 complete, patterns stable in production

### Enhancements

#### 3.1 Lightweight Structure Analysis (No AST)
- **Normalized block fingerprinting:** Detect similar code blocks (retry loops, auth checks)
- **N-gram similarity:** Find near-duplicate functions with minor variations
- **Import graph extraction:** Detect circular dependencies via regex

#### 3.2 LLM Integration (Optional)
- **Input:** Top 5 DRY violations (by file count × churn rate)
- **Output:** Refactoring plan with:
  - Risk assessment (drift potential, security impact)
  - Extraction target (helper class, constants file)
  - Migration steps (create helper → update callers → test)
  - Test recommendations

#### 3.3 Remediation Automation (Future)
- **Generate constants file:** Auto-create `includes/constants.php` with extracted strings
- **Generate helper class:** Scaffold helper class for repeated logic
- **Find-and-replace script:** Generate sed/awk commands for mechanical refactors

### Phase 3 Exit Criteria
- [ ] Block fingerprinting detects scattered retry/auth logic
- [ ] LLM generates actionable refactoring plans for top violations
- [ ] Team successfully refactors 2-3 real duplications using tool guidance
- [ ] Documentation includes case studies of successful refactors

---

## 📋 Implementation Details

### JSON Pattern Schema (Magic String Detector Extensions)

Based on existing `dist/patterns/*.json` format, add aggregation fields:

```json
{
  "id": "duplicate-option-names",
  "version": "1.0.0",
  "enabled": true,
  "category": "duplication",
  "severity": "MEDIUM",
  "title": "Duplicate option names across files",
  "description": "Detects get_option/update_option calls with hard-coded option names appearing in multiple files.",
  "rationale": "Hard-coded option names scattered across files make refactoring risky and lead to typos/bugs.",

  "detection": {
    "type": "grep",
    "file_patterns": ["*.php"],
    "search_pattern": "(get_option|update_option|delete_option)\\(['\"]([a-z0-9_]+)['\"]",
    "capture_group": 2,
    "exclude_patterns": [
      "//.*option",
      "define\\("
    ]
  },

  "aggregation": {
    "enabled": true,
    "group_by": "capture_group",
    "min_total_matches": 6,
    "min_distinct_files": 3,
    "top_k_groups": 10,
    "report_format": "Option '{match}' appears in {file_count} files ({total_count} times)"
  },

  "remediation": {
    "summary": "Extract option names to a constants file or class constants.",
    "examples": [
      {
        "bad": "get_option( 'my_plugin_api_key' );",
        "good": "define( 'MY_PLUGIN_OPTION_API_KEY', 'my_plugin_api_key' );\nget_option( MY_PLUGIN_OPTION_API_KEY );",
        "note": "Centralize in includes/constants.php"
      }
    ]
  },

  "test_fixture": {
    "path": "dist/tests/fixtures/dry/duplicate-options.php",
    "expected_violations": 3,
    "expected_groups": ["my_plugin_api_key", "my_plugin_cache_ttl", "my_plugin_debug_mode"]
  }
}
```

### Aggregation Script Architecture

**File:** `dist/bin/find-dry.sh`

**Workflow:**
1. Load all enabled patterns from `dist/patterns/dry/*.json`
2. For each pattern:
   - Run grep with search pattern
   - Extract capture groups (option names, transient keys, etc.)
   - Group matches by capture group value
   - Count total matches and distinct files per group
   - Filter by thresholds (`min_total_matches`, `min_distinct_files`)
3. Generate reports:
   - **Markdown:** Human-readable summary with top violations
   - **JSON:** Machine-readable with file/line evidence
   - **HTML:** Integrate into existing report template

**Key Functions:**
```bash
# Load pattern and extract aggregation config
load_dry_pattern() { ... }

# Run grep and group by capture group
aggregate_matches() { ... }

# Filter by thresholds
apply_thresholds() { ... }

# Generate Markdown summary
output_markdown_summary() { ... }

# Generate JSON report
output_json_report() { ... }
```

---

## 🧪 Testing Strategy

### Test Fixtures (Phase 1)

**File:** `dist/tests/fixtures/dry/duplicate-options.php` (Magic String Detector fixtures)

```php
<?php
/**
 * Test Fixture: Duplicate Option Names
 *
 * Simulates a plugin with option names scattered across multiple "files"
 * (represented as functions to keep in one file for testing)
 */

// File 1: Admin settings page
function admin_settings_page() {
    $api_key = get_option( 'my_plugin_api_key' ); // ❌ Duplicate
    $debug = get_option( 'my_plugin_debug_mode' ); // ❌ Duplicate
}

// File 2: API client
function api_client_init() {
    $api_key = get_option( 'my_plugin_api_key' ); // ❌ Duplicate
}

// File 3: Cron job
function cron_sync_data() {
    $api_key = get_option( 'my_plugin_api_key' ); // ❌ Duplicate
    $ttl = get_option( 'my_plugin_cache_ttl' ); // ❌ Duplicate
}

// File 4: AJAX handler
function ajax_get_settings() {
    $debug = get_option( 'my_plugin_debug_mode' ); // ❌ Duplicate
    $ttl = get_option( 'my_plugin_cache_ttl' ); // ❌ Duplicate
}

// Expected violations:
// - 'my_plugin_api_key' appears in 3 files (admin, api, cron)
// - 'my_plugin_debug_mode' appears in 2 files (admin, ajax)
// - 'my_plugin_cache_ttl' appears in 2 files (cron, ajax)
```

### Validation Tests

```bash
# Run Magic String Detector on test fixture
./dist/bin/find-dry.sh --paths dist/tests/fixtures/dry/

# Expected output:
# ━━━ MAGIC STRING VIOLATIONS ━━━
#
# Option name 'my_plugin_api_key' appears in 3 files (3 times)
#   - dist/tests/fixtures/dry/duplicate-options.php:7
#   - dist/tests/fixtures/dry/duplicate-options.php:13
#   - dist/tests/fixtures/dry/duplicate-options.php:18
#
# Remediation: Extract to constants file
```

---

## 📊 Success Metrics

### Phase 1 (Proof of Concept)
- **Patterns created:** 2-3
- **Test fixtures:** 2-3
- **False positive rate:** < 10%
- **Scan time:** < 5 seconds on 10k files
- **Team decision:** Go/No-Go for Phase 2

### Phase 2 (Expansion)
- **Total patterns:** 8-10
- **CI/CD integration:** Warn-only mode
- **HTML report integration:** DRY section added
- **Real-world validation:** Tested on 5+ WordPress plugins

### Phase 3 (Advanced)
- **Block fingerprinting:** Detects scattered logic patterns
- **LLM integration:** Generates refactoring plans
- **Successful refactors:** 2-3 real duplications eliminated
- **Documentation:** Case studies published

---

## 🚦 Decision Points

### After Phase 1: Go/No-Go Decision

**GO if:**
- ✅ Patterns detect real magic strings with < 10% false positives
- ✅ Team finds output actionable and useful
- ✅ Scan performance is acceptable (< 5 sec on typical codebase)
- ✅ At least 1 team member says "I would use this"

**NO-GO if:**
- ❌ False positive rate > 25%
- ❌ Patterns miss obvious magic strings (high false negatives)
- ❌ Output is too noisy or not actionable
- ❌ Team consensus: "This doesn't add value"

### After Phase 2: Expand or Stabilize?

**EXPAND to Phase 3 if:**
- ✅ Pattern library is stable and useful
- ✅ Team wants LLM-powered refactoring guidance
- ✅ Block fingerprinting would catch issues patterns miss

**STABILIZE (skip Phase 3) if:**
- ✅ Current patterns are sufficient
- ❌ Team doesn't need advanced features
- ❌ ROI on Phase 3 is unclear

---

## 📁 File Structure

```
dist/
├── bin/
│   ├── find-dry.sh              # NEW: Magic String Detector script
│   └── check-performance.sh     # UPDATED: Integrate Magic String checks
├── lib/
│   └── dry-aggregator.sh        # NEW: Aggregation logic library
├── patterns/
│   └── dry/                     # NEW: Magic String Detector patterns
│       ├── README.md
│       ├── duplicate-option-names.json
│       ├── duplicate-transient-keys.json
│       └── duplicate-capability-strings.json
├── tests/
│   └── fixtures/
│       └── dry/                 # NEW: Magic String Detector test fixtures
│           ├── duplicate-options.php
│           ├── duplicate-transients.php
│           └── duplicate-capabilities.php
└── reports/                     # EXISTING: Add DRY section to HTML
```

---

## 🎯 Next Steps

### Immediate (Phase 1 Kickoff)

1. **Create pattern files** (2-3 JSON files in `dist/patterns/dry/`)
2. **Create test fixtures** (2-3 PHP files demonstrating duplication)
3. **Build aggregation script** (`dist/bin/find-dry.sh`)
4. **Validate on test fixtures** (ensure patterns work)
5. **Test on 1-2 real WordPress plugins** (validate false positive rate)
6. **Team review:** Go/No-Go decision

### Questions to Answer in Phase 1

- **Q1:** What threshold values work best? (3 files? 5 files? 10 occurrences?)
- **Q2:** Should we report ALL duplicates or only top-K?
- **Q3:** How do we handle WordPress core functions (e.g., everyone uses `get_option('siteurl')`)?
- **Q4:** Should Magic String checks be separate or integrated into `check-performance.sh`?
- **Q5:** Do we need allowlists for common patterns (e.g., `current_user_can('manage_options')`)?

---

## 💡 Key Insights from FIND-DRY.md

### What We're Adopting
✅ **Grep-first approach** - Start simple, add complexity later
✅ **JSON pattern files** - Already have infrastructure
✅ **Aggregation thresholds** - Reduce noise
✅ **Phased rollout** - Validate before expanding
✅ **Deterministic evidence** - LLM is optional, not required
✅ **"Magic String" terminology** - Clearer than "DRY violation"

### What We're Deferring
⏸️ **AST analysis** - Phase 3 or later
⏸️ **Automatic refactoring** - Too risky for Phase 1
⏸️ **Import graph analysis** - Not critical for WordPress
⏸️ **N-gram similarity** - Phase 3 if needed

### What We're Adapting
🔧 **Pattern categories** - WordPress-specific (options, transients, meta keys)
🔧 **Severity levels** - Align with existing CRITICAL/HIGH/MEDIUM/LOW
🔧 **Reporting format** - Integrate with existing JSON/HTML reports
🔧 **CI/CD integration** - Use existing GitHub Actions workflows

---

**End of Document**


