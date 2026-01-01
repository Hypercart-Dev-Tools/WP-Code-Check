# DRY Detection - Proof of Concept Summary

**Created:** 2026-01-01
**Status:** Planning Complete - Ready for Implementation
**Next Step:** Create test fixtures and aggregation script

---

## 📦 What Was Created

### 1. Planning Document
**File:** `PROJECT/1-INBOX/NEXT-FIND-DRY.md` (470 lines)

**Contents:**
- 3-phase pragmatic implementation plan
- Phase 1: Proof of Concept (2-3 patterns)
- Phase 2: Expansion (5-8 more patterns)
- Phase 3: Advanced (block fingerprinting, LLM integration)
- JSON pattern schema with aggregation fields
- Testing strategy and success metrics
- Go/No-Go decision criteria

### 2. Pattern JSON Files (3 files)

#### `dist/patterns/dry/duplicate-option-names.json`
- **Severity:** MEDIUM
- **Threshold:** 3+ files, 6+ occurrences
- **Detects:** `get_option()`, `update_option()`, `delete_option()` with hard-coded option names
- **Remediation:** Extract to constants file or class constants

#### `dist/patterns/dry/duplicate-transient-keys.json`
- **Severity:** MEDIUM
- **Threshold:** 3+ files, 4+ occurrences
- **Detects:** `get_transient()`, `set_transient()`, `delete_transient()` with hard-coded transient keys
- **Remediation:** Extract to constants file with CACHE_KEY_ prefix

#### `dist/patterns/dry/duplicate-capability-strings.json`
- **Severity:** LOW
- **Threshold:** 5+ files, 10+ occurrences
- **Detects:** `current_user_can()`, `user_can()` with hard-coded capability strings
- **Remediation:** Centralize custom capabilities with helper methods

### 3. Documentation
**File:** `dist/patterns/dry/README.md`

**Contents:**
- Overview of DRY patterns vs standard patterns
- How aggregation works
- Pattern schema documentation
- Best practices for when to centralize
- Refactoring strategies
- Roadmap for Phases 1-3

---

## 🎯 Phase 1 Proof of Concept - Next Steps

### What's Done ✅
- [x] Planning document created
- [x] 3 JSON pattern files created
- [x] Pattern schema designed with aggregation fields
- [x] Documentation written
- [x] Success criteria defined

### What's Needed ⏳

#### 1. Test Fixtures (3 files)
**Location:** `dist/tests/fixtures/dry/`

- `duplicate-options.php` - Simulate option names scattered across "files" (functions)
- `duplicate-transients.php` - Simulate transient keys scattered across "files"
- `duplicate-capabilities.php` - Simulate capability strings scattered across "files"

**Format:**
```php
<?php
/**
 * Test Fixture: Duplicate Option Names
 *
 * Simulates option names scattered across multiple files
 * (represented as functions to keep in one file for testing)
 */

// "File 1" - Admin settings
function admin_settings_page() {
    $api_key = get_option( 'my_plugin_api_key' ); // ❌ Duplicate
}

// "File 2" - API client
function api_client_init() {
    $api_key = get_option( 'my_plugin_api_key' ); // ❌ Duplicate
}

// Expected: 'my_plugin_api_key' appears in 2+ "files"
```

#### 2. Aggregation Script
**File:** `dist/bin/find-dry.sh`

**Requirements:**
- Load patterns from `dist/patterns/dry/*.json`
- Run grep with capture groups
- Group matches by captured value (option name, transient key, etc.)
- Count total matches and distinct files per group
- Filter by thresholds (`min_total_matches`, `min_distinct_files`)
- Output Markdown summary and JSON report

**Example Output:**
```
━━━ DRY VIOLATIONS ━━━

Option 'my_plugin_api_key' appears in 5 files (12 times)
  - admin/settings.php:45
  - includes/api-client.php:23
  - cron/sync.php:67
  - ajax/handlers.php:89
  - public/shortcodes.php:34

Transient 'user_data_cache' appears in 3 files (8 times)
  - includes/cache.php:12
  - ajax/user-search.php:34
  - cron/cleanup.php:56

━━━ SUMMARY ━━━
Total violations: 2
Total duplicated strings: 2
```

#### 3. Validation
- Run on test fixtures (should detect expected violations)
- Run on 1-2 real WordPress plugins (validate false positive rate)
- Measure scan time (should be < 5 seconds on 10k files)

#### 4. Go/No-Go Decision
**Criteria:**
- ✅ Patterns detect real duplication with < 10% false positives
- ✅ Team finds output actionable and useful
- ✅ Scan performance is acceptable
- ✅ At least 1 team member says "I would use this"

---

## 💡 Key Design Decisions

### 1. Why 2-3 Patterns for Phase 1?
**Answer:** Proof of concept should be minimal but meaningful. 2-3 patterns are enough to:
- Validate the aggregation approach
- Test false positive rate
- Measure performance
- Get team feedback
- Decide whether to continue

### 2. Why These 3 Patterns?
**Answer:** High signal, low noise, immediate value:
- **Option names:** Very common WordPress pattern, typos cause real bugs
- **Transient keys:** Cache invalidation bugs are hard to debug
- **Capability strings:** Security-adjacent, scattered checks are risky

### 3. Why External JSON Files?
**Answer:** Consistency with existing pattern infrastructure:
- Already have `dist/patterns/*.json` for performance/security
- Already have `dist/lib/pattern-loader.sh` for loading patterns
- JSON files are easier to maintain than embedded bash patterns
- Enables future tooling (pattern editor, pattern marketplace)

### 4. Why Grep-First (Not AST)?
**Answer:** Pragmatic approach from FIND-DRY.md:
- Grep is fast (< 5 seconds on large codebases)
- No dependencies (pure bash)
- Good enough for string literal duplication
- Can add AST later if needed (Phase 3)

---

## 📊 Expected Outcomes

### If Successful (GO)
- **Immediate value:** Developers find and fix real duplication
- **Confidence:** Team wants more patterns (Phase 2)
- **Validation:** Approach works, false positives are manageable
- **Next step:** Expand to 8-10 patterns, integrate with main scanner

### If Unsuccessful (NO-GO)
- **Too noisy:** False positive rate > 25%
- **Not useful:** Team doesn't find violations actionable
- **Too slow:** Scan takes > 10 seconds on typical codebase
- **Next step:** Revisit approach or abandon DRY detection

---

## 🚀 Implementation Timeline (Estimated)

### Day 1: Test Fixtures
- Create 3 test fixture files
- Ensure they demonstrate expected violations
- Document expected output

### Day 2: Aggregation Script
- Create `dist/bin/find-dry.sh`
- Implement pattern loading
- Implement grep + grouping logic
- Implement threshold filtering
- Implement Markdown output

### Day 3: Validation
- Run on test fixtures (verify detection)
- Run on 2-3 real WordPress plugins
- Measure false positive rate
- Measure scan performance
- Document findings

### Day 4: Team Review
- Present findings to team
- Demonstrate on real codebase
- Collect feedback
- Make Go/No-Go decision

---

## 📁 File Structure (Current State)

```
dist/
├── patterns/
│   ├── dry/                                    # NEW
│   │   ├── README.md                          # ✅ Created
│   │   ├── duplicate-option-names.json        # ✅ Created
│   │   ├── duplicate-transient-keys.json      # ✅ Created
│   │   └── duplicate-capability-strings.json  # ✅ Created
│   ├── get-users-no-limit.json                # Existing
│   ├── wpdb-query-no-prepare.json             # Existing
│   └── ...
├── bin/
│   ├── find-dry.sh                            # ⏳ TODO
│   └── check-performance.sh                   # Existing
├── lib/
│   ├── dry-aggregator.sh                      # ⏳ TODO (optional)
│   └── pattern-loader.sh                      # Existing
└── tests/
    └── fixtures/
        └── dry/                                # ⏳ TODO
            ├── duplicate-options.php
            ├── duplicate-transients.php
            └── duplicate-capabilities.php

PROJECT/
└── 1-INBOX/
    ├── NEXT-FIND-DRY.md                       # ✅ Created
    ├── DRY-POC-SUMMARY.md                     # ✅ Created (this file)
    └── FIND-DRY.md                            # Existing (reference)
```

---

## ❓ Questions to Answer During Implementation

1. **Threshold tuning:** Are 3 files / 6 occurrences the right thresholds?
2. **Allowlist scope:** Should we exclude more WordPress core strings?
3. **Integration:** Separate script or integrate into `check-performance.sh`?
4. **Output format:** Markdown only, or also JSON/HTML?
5. **Baseline support:** Should DRY violations support baseline suppression?

---

## 🎓 Lessons from FIND-DRY.md

### What We Adopted ✅
- Grep-first approach (fast, simple, no dependencies)
- JSON pattern files (maintainable, extensible)
- Aggregation thresholds (reduce noise)
- Phased rollout (validate before expanding)
- Deterministic evidence (LLM is optional)

### What We Adapted 🔧
- WordPress-specific patterns (options, transients, capabilities)
- Existing pattern infrastructure (reuse `dist/patterns/`)
- Severity levels (align with CRITICAL/HIGH/MEDIUM/LOW)
- Reporting format (integrate with existing JSON/HTML reports)

### What We Deferred ⏸️
- AST analysis (Phase 3 or later)
- Automatic refactoring (too risky for Phase 1)
- Import graph analysis (not critical for WordPress)
- N-gram similarity (Phase 3 if needed)

---

**Status:** Ready for implementation. Next step: Create test fixtures and aggregation script.

**Decision Point:** After Phase 1 validation, decide Go/No-Go for Phase 2 expansion.