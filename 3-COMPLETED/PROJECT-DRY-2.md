# PROJECT-DRY-2 — DRY Opportunities for `check-performance.sh`
**Date:** 2026-06-13  
**Scope:** Bash performance/security scanner (`dist/bin/check-performance.sh`)  
**Goal:** Highlight consolidation targets so the toolkit keeps a single source of truth for shared behaviors without touching runtime logic yet.

## UPDATE - Desion made to defer most of these and tackle these only instead: 

Phase 1: Critical Bug Fix (30 minutes) - DO NOW
✅ Fix version drift (Target #2 - partial)
Define SCRIPT_VERSION="1.0.59" constant
Replace 4 hardcoded version strings
Test: Verify version appears correctly in logs/JSON
Phase 2: Quick Cleanup (15 minutes) - DO NEXT

STATUS: COMPLETED


✅ Remove duplicate timestamp function (Target #4)
Delete get_local_timestamp()
Use timestamp_iso8601() from common-helpers
Test: Verify timestamps still work

STATUS: COMPLETED


---

## 🎯 Summary
- The performance/security scanner has grown a large collection of inline helpers and bespoke check blocks. Several of them duplicate responsibilities that already live (or could live) in `dist/bin/lib/*.sh`.
- Consolidating JSON/reporting helpers, project metadata detection, and the bespoke grep/formatting loops will reduce maintenance risk and align the script with the project’s DRY/SOT expectations.

---

## 🔁 Consolidation Targets

### 1) JSON + Reporting Utilities
**Severity:** 🟡 MEDIUM
**Priority:** 🔵 HIGH
**Effort:** ⚡ MEDIUM (4-6 hours)

**Issue:**
Functions such as `json_escape()`, `add_json_finding()`, `add_json_check()`, `output_json()`, and `generate_html_report()` are defined directly in the script even though `dist/bin/lib/json-helpers.sh` already exists as a shared JSON surface. Keeping these inline makes it easy for future scripts to re-implement similar logic inconsistently.

**Impact:**
- 🔴 **Maintenance Risk:** Any bug fix in JSON escaping must be duplicated across scripts
- 🟡 **Inconsistency:** Future scripts may implement different JSON formatting
- 🟢 **Testing:** Harder to unit test JSON generation in isolation

**Recommendation:**
Move all JSON construction/escaping and HTML report generation into `dist/bin/lib/json-helpers.sh` (or a new `report-helpers.sh`) and source it from the main script. Keep only minimal wiring in `check-performance.sh`.

**Functions to Extract:**
- `json_escape()` - 9 lines
- `url_encode()` - 4 lines
- `add_json_finding()` - 67 lines
- `add_json_check()` - 12 lines
- `output_json()` - 68 lines
- `generate_html_report()` - ~100 lines

**Total Lines to Move:** ~260 lines → `dist/bin/lib/report-helpers.sh`

---

### 2) Project Metadata + Version SOT
**Severity:** 🔴 HIGH
**Priority:** 🔴 CRITICAL
**Effort:** ⚡ LOW (2-3 hours)

**Issue:**
The script recomputes project info multiple times (log header, JSON output) via `detect_project_info()` plus repeated `grep` parsing. Version text is also duplicated with mismatched values (header shows 1.0.59 but could drift from JSON output).

**Impact:**
- 🔴 **Version Drift:** Multiple version strings can get out of sync (critical for auditing)
- 🔴 **Performance:** Redundant file scanning and grep operations
- 🟡 **Maintenance:** Changes to metadata detection must be made in multiple places

**Recommendation:**
Extract project metadata helpers (`detect_project_info()`, `count_analyzed_files()`, `count_lines_of_code()`, `get_local_timestamp()`) into a dedicated helper file and return structured data once per run. Define a single `SCRIPT_VERSION` variable and reuse it in the banner, logs, and JSON payload to avoid drift.

**Functions to Extract:**
- `detect_project_info()` - ~100 lines (complex WordPress header parsing)
- `count_analyzed_files()` - 3 lines
- `count_lines_of_code()` - 19 lines
- `get_local_timestamp()` - 3 lines

**Version Consolidation:**
- Create `SCRIPT_VERSION="1.0.59"` constant at top of script
- Remove hardcoded version from line 4 header comment
- Reuse `$SCRIPT_VERSION` in banner, logs, and JSON output

**Total Lines to Move:** ~125 lines → `dist/bin/lib/project-helpers.sh`

---

### 3) Shared Check Runner for Contextual Grep Blocks
**Severity:** 🟡 MEDIUM
**Priority:** 🟡 MEDIUM
**Effort:** ⚡⚡ HIGH (8-12 hours)

**Issue:**
After `run_check()` there are several bespoke blocks (admin capability checks, AJAX polling, REST pagination, etc.) that repeat the same pattern: `grep`, guard numeric line numbers, apply baseline suppression, build JSON findings, and manage per-check counters. Each block re-implements nearly identical loops and string parsing.

**Impact:**
- 🟡 **Code Duplication:** ~200+ lines of duplicated grep/baseline/counter logic
- 🟡 **Bug Risk:** Fixes to baseline suppression must be applied to 6+ locations
- 🟢 **Extensibility:** Adding new contextual checks requires copying entire pattern

**Recommendation:**
Extend `run_check()` (or add `run_context_check()`) to accept a callback/validator for contextual rules. Centralize baseline suppression, grouping, and JSON/check counter updates so individual rules only provide: patterns, optional context window, and the pass/fail message. This will collapse the duplicated state machines across those sections.

**Affected Check Blocks:**
1. Admin capability checks (lines ~1400-1500)
2. AJAX polling detection (lines ~1500-1600)
3. REST API pagination (lines ~1600-1700)
4. Transient expiration checks (lines ~1700-1800)
5. Direct database queries (lines ~1800-1900)
6. Unescaped output (lines ~1900-2000)

**Refactor Strategy:**
- Create `run_context_check()` function that accepts:
  - Check name, severity, impact
  - Grep pattern(s)
  - Context validator callback (optional)
  - Message template
- Centralize baseline suppression logic
- Centralize JSON finding generation
- Centralize counter management

**Total Lines to Consolidate:** ~600 lines → ~150 lines (75% reduction)

---

### 4) Path + Timestamp Handling
**Severity:** 🟢 LOW
**Priority:** 🟢 LOW
**Effort:** ⚡ TRIVIAL (30 minutes)

**Issue:**
`SCRIPT_DIR`/`PLUGIN_DIR` are computed twice, and timestamp helpers live inline despite similar helpers already existing in `dist/bin/lib/common-helpers.sh`.

**Impact:**
- 🟢 **Minor Duplication:** Only ~10 lines duplicated
- 🟢 **Low Risk:** Path computation is stable and rarely changes
- 🟢 **Consistency:** Should use shared helpers for uniformity

**Recommendation:**
Reuse the sourced helper values for directories and timestamps instead of reassigning them mid-file, ensuring a single place to update path or clock logic.

**Current State:**
- `get_local_timestamp()` defined inline (3 lines) - duplicates functionality
- `timestamp_iso8601()` already exists in `common-helpers.sh` ✅
- `timestamp_filename()` already exists in `common-helpers.sh` ✅

**Action:**
- Remove `get_local_timestamp()` function
- Replace calls with `timestamp_iso8601()` or `timestamp_filename()` from common-helpers
- Verify no duplicate `SCRIPT_DIR` assignments

**Total Lines to Remove:** ~10 lines

---

## 📊 Summary Matrix

| Target | Severity | Priority | Effort | Lines Saved | Risk |
|--------|----------|----------|--------|-------------|------|
| **1. JSON + Reporting** | 🟡 MEDIUM | 🔵 HIGH | ⚡ MEDIUM (4-6h) | ~260 lines | Low - Well-isolated functions |
| **2. Project Metadata** | 🔴 HIGH | 🔴 CRITICAL | ⚡ LOW (2-3h) | ~125 lines | Low - Pure data extraction |
| **3. Context Check Runner** | 🟡 MEDIUM | 🟡 MEDIUM | ⚡⚡ HIGH (8-12h) | ~450 lines | Medium - Complex refactor |
| **4. Path/Timestamp** | 🟢 LOW | 🟢 LOW | ⚡ TRIVIAL (30m) | ~10 lines | Very Low - Simple cleanup |

**Total Potential Reduction:** ~845 lines (34% of 2,448-line script)

---

## 🎯 Recommended Implementation Order

### Phase 1: Quick Wins (3-4 hours)
1. ✅ **Target #4** - Path/Timestamp cleanup (30 min)
2. ✅ **Target #2** - Project Metadata + Version SOT (2-3 hours)

**Rationale:** Low risk, high impact on version drift bug, immediate value

### Phase 2: Core Infrastructure (4-6 hours)
3. ✅ **Target #1** - JSON + Reporting utilities (4-6 hours)

**Rationale:** Enables future scripts to reuse JSON generation, prevents inconsistency

### Phase 3: Advanced Refactor (8-12 hours)
4. ✅ **Target #3** - Context Check Runner (8-12 hours)

**Rationale:** Highest complexity, but biggest code reduction. Do last when other helpers are stable.

---

## ✅ Next Steps (Implementation Checklist)

### Pre-Implementation
- [ ] Create feature branch: `feature/dry-phase2-check-performance`
- [ ] Backup current test baseline: `cp dist/tests/fixtures/.hcc-baseline .hcc-baseline.backup`
- [ ] Run full test suite to establish baseline: `dist/tests/run-fixture-tests.sh`

### Phase 1: Quick Wins
- [ ] **Target #4:** Remove `get_local_timestamp()`, use `common-helpers.sh` functions
- [ ] **Target #2:** Create `dist/bin/lib/project-helpers.sh`
  - [ ] Move `detect_project_info()`, `count_analyzed_files()`, `count_lines_of_code()`
  - [ ] Define `SCRIPT_VERSION` constant
  - [ ] Update all version references to use `$SCRIPT_VERSION`
- [ ] Run tests: `dist/tests/run-fixture-tests.sh` (verify no regressions)

### Phase 2: Core Infrastructure
- [ ] **Target #1:** Create `dist/bin/lib/report-helpers.sh`
  - [ ] Move `json_escape()`, `url_encode()`
  - [ ] Move `add_json_finding()`, `add_json_check()`
  - [ ] Move `output_json()`, `generate_html_report()`
  - [ ] Source in `check-performance.sh`
- [ ] Run tests: `dist/tests/run-fixture-tests.sh` (verify JSON output parity)
- [ ] Test JSON output: `./dist/bin/check-performance.sh --paths dist/tests/fixtures/antipatterns.php --format json`

### Phase 3: Advanced Refactor
- [ ] **Target #3:** Create `run_context_check()` function
  - [ ] Design callback interface for context validators
  - [ ] Centralize baseline suppression logic
  - [ ] Centralize JSON finding generation
  - [ ] Refactor admin capability checks to use new runner
  - [ ] Refactor AJAX polling checks to use new runner
  - [ ] Refactor REST pagination checks to use new runner
  - [ ] Refactor remaining contextual checks
- [ ] Run tests: `dist/tests/run-fixture-tests.sh` (verify all checks still work)
- [ ] Compare output: `diff <(old_output) <(new_output)` (should be identical)

### Post-Implementation
- [ ] Update `CHANGELOG.md` with DRY Phase 2 completion
- [ ] Update version to 1.0.60
- [ ] Run full test suite against real projects (Save Cart Later, etc.)
- [ ] Document new helper functions with PHPDoc-style comments
- [ ] Update `PROJECT-DRY-2.md` status to COMPLETE
- [ ] Create `PROJECT-DRY-3.md` for next iteration (if needed)

---

## 🚨 Risk Mitigation

**Testing Strategy:**
1. **Baseline Comparison:** Generate JSON output before/after each phase, compare with `diff`
2. **Fixture Tests:** Run `dist/tests/run-fixture-tests.sh` after each change
3. **Real-World Testing:** Test against known projects (Save Cart Later) before merging
4. **Rollback Plan:** Keep feature branch until all tests pass

**Known Risks:**
- 🟡 **JSON Output Changes:** Any whitespace/formatting changes will break downstream tools
  - **Mitigation:** Use `jq` to normalize JSON before comparison
- 🟡 **Baseline Suppression Logic:** Complex state machine, easy to break
  - **Mitigation:** Add unit tests for baseline matching before refactoring
- 🟢 **Version Drift:** Low risk, easy to verify with grep

---

**Status:** 📋 READY FOR IMPLEMENTATION
**Estimated Total Effort:** 15-21 hours
**Expected Code Reduction:** 34% (845 lines)
**Next Action:** Create feature branch and start Phase 1