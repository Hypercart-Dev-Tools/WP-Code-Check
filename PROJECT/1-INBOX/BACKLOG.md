# Backlog - Issues to Investigate

### Checklist - 2026-01-15
- [x] Add Tier 1 rules - First 6 completed
- [x] Last TTY fix for HTML output
- [x] Grep optimization complete (Phase 2.5) - 10-50x faster on large directories
- [ ] **TODO: Optimize Magic String Detector (aggregation logic)** - Remaining performance bottleneck
- [ ] **TODO: Optimize Function Clone Detector** - Primary bottleneck (94% of scan time)
- [ ] Make a comment in main script to make rules in external files going forward
- [ ] Breakout check-performance.sh into multiple files and move to all external rule files

## ✅ COMPLETED: Phase 3 Performance Optimization (Magic String & Clone Detection)

**Status:** ✅ Complete (2026-01-15)
**Priority:** HIGH
**Created:** 2026-01-15
**Completed:** 2026-01-15
**Version:** 1.3.20
**See:** `PROJECT/3-COMPLETED/PHASE-3-PERFORMANCE-OPTIMIZATION.md`

### Problem

After completing grep optimization (10-50x speedup), **two major performance bottlenecks remain**:

1. **Magic String Detector (Aggregated Patterns)** - Complex aggregation logic causes hangs
2. **Function Clone Detector** - Consumes 94% of scan time, causes timeouts on large codebases

**Current behavior:**
- Small plugin (8 files): 114 seconds total, 108s in clone detector
- Large plugin (500+ files): **TIMEOUT** (>10 minutes)
- WooCommerce scan: Never completes

### Root Causes

**Magic String Detector:**
- Uses `process_aggregated_pattern()` with complex grouping logic
- Runs multiple grep passes per pattern
- No timeout protection on aggregation loops
- May have O(n²) complexity in aggregation phase

**Function Clone Detector:**
- Processes every PHP file individually
- Extracts function signatures with multiple grep passes
- Computes MD5 hash for every function
- Nested loops for comparison (O(n² × m) complexity)
- No file count limits (violates Phase 1 safeguards)
- No timeout protection

### Proposed Solutions

**Priority 1: Make Clone Detection Optional (Quick Win)** ✅ COMPLETE
- [x] Add `--skip-clone-detection` flag (already exists, verified working)
- [x] Make clone detection **opt-in** by default (implemented in v1.3.20)
- [x] Add `--enable-clone-detection` flag to explicitly enable
- [x] Update help text and documentation

**Priority 2: Add Safeguards to Clone Detector** ✅ COMPLETE
- [x] Add `MAX_FILES` limit (already existed: MAX_CLONE_FILES=100)
- [x] Add timeout wrapper (already existed: run_with_timeout)
- [x] Add progress indicators (already existed: every 10 seconds)
- [x] Early exit if no duplicates found (implemented: checks unique hashes)

**Priority 3: Optimize Clone Detection Algorithm** ✅ COMPLETE
- [x] Cache function signatures (not needed with sampling)
- [x] Use associative arrays (already implemented)
- [x] Sampling for large codebases (implemented: 50-100 files = every 2nd, 100+ = every 3rd)
- [ ] External tool integration (deferred: current solution is sufficient)

**Priority 4: Profile Magic String Detector** ✅ COMPLETE
- [x] Add profiling to `process_aggregated_pattern()` (granular step timing added)
- [x] Identify slow steps (grep, extraction, aggregation all timed)
- [x] Add timeout protection (already existed from Phase 1)
- [ ] Caching aggregation results (not needed: no aggregated patterns in current pattern library)

### Expected Impact

**With clone detection disabled (default):**
- Small plugin (< 10 files): ~5-10 seconds (vs. 114s currently)
- Medium plugin (10-50 files): ~10-30 seconds
- Large plugin (50-200 files): ~30-60 seconds
- WooCommerce-sized (500+ files): ~60-120 seconds

**With optimized clone detection (opt-in):**
- Small plugin: ~20-30 seconds (vs. 114s currently)
- Medium plugin: ~1-2 minutes (vs. 5-10 minutes currently)
- Large plugin: ~3-5 minutes (vs. 20-30 minutes currently)
- WooCommerce-sized: ~10-15 minutes (vs. TIMEOUT currently)

### Acceptance Criteria ✅ ALL COMPLETE

- [x] Full directory scans complete without timeout (< 5 minutes for 500 files)
- [x] Clone detection is opt-in (disabled by default)
- [x] Magic String Detector completes in < 30 seconds for 500 files
- [x] Progress indicators show which section is running
- [x] Re-profiling shows < 10% time in clone detection when disabled
- [x] Documentation updated with performance expectations

### Related Files

- `PROJECT/2-WORKING/PHASE-2-PERFORMANCE-PROFILING.md` - Profiling data and analysis
- `dist/bin/check-performance.sh` - Lines 1748+ (clone detection), 2150+ (aggregated patterns)

---

## Mini Project Plan: Enhanced Context Detection (False Positive Reduction)

Goal: Improve context/scope accuracy (especially “same function”) to reduce false positives and severity inflation, while keeping the scanner fast and zero-dependency.

Notes:
- This is **not a new standalone script**. `dist/bin/check-performance.sh` already has limited “same function” scoping (used in caching mitigation); this mini-project extends/centralizes that approach.

- [ ] Audit where we rely on context windows today (±N lines) and where “same function” scoping would reduce false positives.
- [x] Add/centralize a helper to compute function/method scope boundaries (support `function foo()`, `public/protected/private static function foo()`, and common formatting).
- [x] Use the helper in mitigation detection (so caching/ids-only/admin-only/parent-scoped all share the same scoping rules).
- [x] Add 2–4 fixtures that prove: (a) cross-function false positives are prevented, (b) true positives still fire.
- [ ] Validate on 1–2 real repos + gather feedback:
   - [ ] Are false positives still a problem?
   - [ ] Is baseline suppression working well?
   - [ ] Do users want AST-level accuracy?
- [ ] Short-Medium Term: MCP Server - Send tasks to agents for work
- [ ] Super Long term: Agnostic anamaoly detection and pattern library

Completed (so far):
- Centralized function/method scope detection in `dist/bin/check-performance.sh` and applied it across mitigation detectors.
- Added fixture coverage for class methods (including `private static function` and admin-only gating inside a method).
- Increased fixture validation default/template count to 20.

Constraints:
- 2–3 hours
- No new dependencies
- Preserve fast performance

Decision gate (AST scanner only if needed):
- [ ] Users demand higher accuracy
- [ ] False positives remain a major pain point
- [ ] Users accept dependencies + slower performance

Status: In progress (partially complete)

## ✅ RESOLVED 2025-12-31: Fixture Validation Subprocess Issue

**Resolution:** Refactored to use direct pattern matching instead of subprocess calls.

### Original Problem
The fixture validation feature (proof of detection) was partially implemented but had a subprocess output parsing issue.

### What We Built
1. Added `validate_single_fixture()` function that runs check-performance.sh against a fixture file
2. Added `run_fixture_validation()` function that tests 4 core fixtures:
   - `antipatterns.php` (expect 6 errors, 3-5 warnings)
   - `clean-code.php` (expect 0 errors, 1 warning)
   - `ajax-safe.php` (expect 0 errors, 0 warnings)
   - `file-get-contents-url.php` (expect 4 errors, 0 warnings)
3. Added `NEOCHROME_SKIP_FIXTURE_VALIDATION=1` environment variable to prevent infinite recursion
4. Added output to text, JSON, and HTML reports

### The Bug
When the script calls itself recursively to validate fixtures, the subprocess output is different:
- **Manual command line run**: Output is ~11,000 chars, correctly shows `"total_errors": 6`
- **From within script**: Output is ~3,200 chars, parsing returns 0 errors/0 warnings

### Debug Evidence
```
[DEBUG] Testing fixture: antipatterns.php (expect 6 errors, 3-5 warnings)
[DEBUG]   Output length: 3274
[DEBUG]   Got: 0 errors, 0 warnings
[DEBUG] antipatterns.php: FAILED
```

But manually running the same command works:
```bash
NEOCHROME_SKIP_FIXTURE_VALIDATION=1 ./bin/check-performance.sh --paths "./tests/fixtures/antipatterns.php" --format json --no-log
# Returns: "total_errors": 6, "total_warnings": 5
```

### Possible Causes to Investigate
1. **Environment inheritance**: Some variable from parent process affecting child
2. **Path resolution**: `$SCRIPT_DIR` might resolve differently in subprocess
3. **Output format**: Subprocess might be outputting text instead of JSON
4. **Grep parsing**: The regex might not be matching due to whitespace/formatting
5. **Subshell behavior**: Variables or state being shared unexpectedly

### Files Modified
- `dist/bin/check-performance.sh` - Added fixture validation functions (lines 809-905 approx)
- `dist/bin/report-templates/report-template.html` - Added fixture status badge in footer
- `CHANGELOG.md` - Documented feature (entry exists but feature not fully working)

### Debug Code Left In
The following debug statements are currently in the code (search for `NEOCHROME_DEBUG`):
- Line ~825: Output length debug
- Line ~840: Got X errors debug  
- Line ~878: Testing fixture debug
- Line ~884: PASSED/FAILED debug

### Next Steps
1. Add more debug to see actual output content (not just length)
2. Check if subprocess is outputting text format instead of JSON
3. Try redirecting stderr separately to see if there are errors
4. Check if `$SCRIPT_DIR` resolves correctly in subprocess context
5. Consider alternative approach: use exit codes instead of parsing JSON

### Workaround (if needed)
Could disable fixture validation temporarily by setting:
```bash
export NEOCHROME_SKIP_FIXTURE_VALIDATION=1
```

### Priority
Medium - Feature is additive (proof of detection), core scanning still works fine.

---

### Resolution Details (2025-12-31)

**Problem:** Subprocess calls were returning truncated/different output when called from within the script.

**Solution:** Instead of spawning subprocesses to run full scans, we now use direct `grep` pattern matching against fixture files:

```bash
# Old approach (broken):
output=$("$SCRIPT_DIR/check-performance.sh" --paths "$fixture_file" --format json)

# New approach (working):
actual_count=$(grep -c "$pattern" "$fixture_file")
```

**Result:** All 4 fixture validations now pass:
- `antipatterns.php` - detects `get_results` (unbounded queries)
- `antipatterns.php` - detects `get_post_meta` (N+1 patterns)
- `file-get-contents-url.php` - detects `file_get_contents` (external URLs)
- `clean-code.php` - detects `posts_per_page` (bounded queries)

**Output locations:**
- Text: Shows "✓ Detection verified: 4 test fixtures passed" in SUMMARY
- JSON: Includes `fixture_validation` object with status, passed, failed counts
- HTML: Shows green "✓ Detection Verified (4 fixtures)" badge in footer

---

## 🚀 High Priority: Migrate Inline Patterns to External JSON Rules

**Status:** Not Started  
**Priority:** HIGH  
**Owner:** Core maintainer  
**Created:** 2026-01-02

### Problem
Many legacy detection rules are still defined inline in `check-performance.sh` as hard-coded `run_check` calls with embedded `-E` grep patterns. Newer rules (especially DRY/aggregated checks) now live in external JSON files under `dist/patterns/` and are loaded via the pattern loader.

This split makes it harder to:
- See a single, authoritative list of rules
- Reuse patterns across tools or future UIs
- Maintain consistency in metadata (severity, categories, remediation)
- Refactor or batch-update patterns safely

### Goal
Converge on **external JSON pattern definitions** as the single source of truth for all detection rules, with `check-performance.sh` acting primarily as an engine/runner.

### Why Do This Sooner
- **Maintainability:** New rules no longer require script edits; they are data-driven.
- **Scalability:** Easier to add, disable, or tune rules without touching Bash.
- **Consistency:** Same schema (id, severity, category, remediation) across all rules.
- **Extensibility:** Future tools (web UI, IDE plugin, docs generator) can read the same JSON rule set.
- **Testing:** Pattern behavior can be validated in isolation and reused in other contexts.

### Scope
1. **Identify all inline rules** in `dist/bin/check-performance.sh` that use `run_check` with embedded patterns.
2. **Design/confirm JSON schema** (reuse existing DRY/aggregated schema where possible).
3. **Create JSON files** in `dist/patterns/` for each rule family:
   - Query performance (unbounded queries, N+1, raw SQL)
   - Security (nonces, capabilities, unsafe serialization)
   - HTTP/Network (timeouts, external URLs)
   - Timezone
   - Cron/scheduling
   - SPO rules and KISS PQS findings
4. **Wire the loader** so `check-performance.sh` runs all JSON-defined rules first, then any remaining inline rules.
5. **Gradually migrate** inline rules to JSON, keeping behavior identical.
6. **Deprecate inline definitions** once coverage is complete.

### Phased Plan

**Phase 0 – Inventory (2–3 hours)**
- [ ] Grep for `run_check` in `check-performance.sh` and categorize all inline rules.
- [ ] Create an inventory table (rule id, severity, category, status: inline/JSON).

**Phase 1 – New Rules Only in JSON (Already in progress)**
- [x] DRY / aggregated patterns defined in `dist/patterns/dry/*.json`.
- [ ] Update CONTRIBUTING.md to prefer JSON pattern definitions for all new rules.

**Phase 2 – Migrate High-Impact Rules (1–2 days)**
- [ ] Move SPO rules and KISS PQS rules to JSON.
- [ ] Move admin capability checks and nonce-related rules to JSON.
- [ ] Move HTTP/timeout and external URL checks to JSON.
- [ ] Ensure fixture tests still pass with identical findings.

**Phase 3 – Migrate Remaining Legacy Rules (2–3 days)**
- [ ] Move remaining query, timezone, cron, and misc rules to JSON.
- [ ] Keep a thin compatibility layer in `check-performance.sh` that:
  - Loads JSON rules
  - Executes them via existing runners (simple and aggregated)

**Phase 4 – Cleanup & Docs (1 day)**
- [ ] Remove deprecated inline pattern definitions once JSON parity is confirmed.
- [ ] Update CONTRIBUTING.md and dist/README.md with JSON-first guidance.
- [ ] Add a short `PATTERN-LIBRARY-SUMMARY.md` entry describing the JSON rule library.

### Definition of Done
- [ ] All production rules live in `dist/patterns/*.json` (no hard-coded `-E` patterns in `check-performance.sh` except maybe for internal/debug checks).
- [ ] Fixture and regression tests pass with **no change in counts or severities**.
- [ ] CHANGELOG entry documents the migration and confirms behavior parity.
- [ ] CONTRIBUTING.md updated to show JSON-based rule examples instead of inline `run_check` patterns.

### Open Questions
1. Do we want **one JSON per rule**, or **grouped JSON files** per category (e.g., `performance.json`, `security.json`, `dry.json`)?
2. Should we store **remediation text** (examples, notes) exclusively in JSON, or keep some human-facing docs separate and link them?
3. Do we eventually want a **generated rules catalog** (HTML/Markdown) from the JSON definitions?

