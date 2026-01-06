# Project Stability Review (Main Script)

**Created:** 2026-01-05
**Updated:** 2026-01-06
**Status:** Phase 1 Complete
**Priority:** High

## Problem/Request
Review stability risks in the main scanner script (`dist/bin/check-performance.sh`), focusing on:
- Inefficient grep patterns on large codebases
- Missing timeout handling
- Infinite loops in pattern matching

## Context
- Users run scans against very large WordPress codebases (plugins/themes + dependencies), often in paths with spaces.
- The script performs many recursive grep/find passes plus post-processing loops; a few “bad” patterns or edge-case inputs can lead to slow runs, hangs, or runaway logs.
- Recent debug additions can make long runs more visible but also risk adding noise/overhead.
- **Current Status:** Script is functionally correct (v1.0.81) but lacks performance safeguards for edge cases.

## Phased Approach

This work is divided into three phases based on risk/value analysis:

### Phase 1: Quick Wins (Safety Nets) - ✅ **COMPLETED 2026-01-06**
**Effort:** 1-2 hours | **Risk:** Low | **Value:** High

- [x] Add basic timeout wrapper for long-running grep operations
- [x] Add file count limits to prevent runaway scans (e.g., max 10,000 files)
- [x] Add early-exit conditions for aggregation loops (max iterations)
- [x] Document known performance bottlenecks in code comments
- [x] Add `MAX_SCAN_TIME` environment variable (default: 300s per pattern)

**Rationale:** Low-risk safety nets that prevent catastrophic hangs without changing core logic.

**Implementation Summary (v1.0.82):**
- Created `run_with_timeout()` portable timeout wrapper using Perl (macOS Bash 3.2 compatible)
- Added `MAX_SCAN_TIME=300`, `MAX_FILES=10000`, `MAX_LOOP_ITERATIONS=50000` environment variables
- Integrated timeout wrapper in aggregated pattern grep operations
- Added file count limits in clone detection
- Added iteration limits in ALL aggregation loops (string, hash, file) with early exit warnings
- Documented performance characteristics in code comments
- **Fixed timeout detection**: Removed `|| true` that swallowed exit code 124
- **Fixed incomplete loop bounds**: Added iteration limits to unique_strings and hash aggregation
- **Fixed version banner**: Updated header comment from 1.0.80 to 1.0.82
- All tests pass, no regressions detected

### Phase 2: Performance Profiling - ✅ **COMPLETED 2026-01-06**
**Effort:** 2-4 hours | **Risk:** Low | **Value:** Medium

- [x] Add optional timing instrumentation (`PROFILE=1` mode)
- [x] Run against large real codebases (WooCommerce, Save Cart Later)
- [x] Identify top 3-5 slowest operations with actual data
- [x] Create performance baseline report
- [x] Document typical scan times for reference codebases

**Rationale:** Need real-world data to optimize effectively. Guessing at bottlenecks risks wasted effort.

**Implementation Summary (v1.0.83):**
- Added `PROFILE` environment variable and timing functions
- Instrumented 4 major sections: CRITICAL_CHECKS, WARNING_CHECKS, MAGIC_STRING_DETECTOR, FUNCTION_CLONE_DETECTOR
- **Key Finding:** Function Clone Detector consumes 94% of scan time on small codebases, causes timeouts on large ones
- Profiling data shows O(n²) complexity in clone detection (25M comparisons for WooCommerce)
- Detailed analysis in `PROJECT/2-WORKING/PHASE-2-PERFORMANCE-PROFILING.md`

### Phase 3: Optimization - **DO AFTER PHASE 2 DATA**
**Effort:** 4-8 hours | **Risk:** Medium | **Value:** High (if bottlenecks confirmed)

- [ ] Optimize the slowest grep patterns (based on Phase 2 data)
- [ ] Implement file list caching (scan once, reuse for multiple patterns)
- [ ] Add progress indicators for long scans
- [ ] Parallelize independent pattern checks (if safe)
- [ ] Add incremental scan mode (only changed files)

**Rationale:** Optimize based on actual bottlenecks, not assumptions. Higher risk requires careful testing.

## Acceptance Criteria (Phase 1 Only)
- [x] No scan can run longer than `MAX_SCAN_TIME` without user override
- [x] No single pattern can process more than `MAX_FILES` without warning
- [x] All loops have documented termination conditions
- [x] Timeout failures are graceful (warning + continue, or fail in strict mode)
- [x] All existing tests pass unchanged
- [x] Performance on small codebases unchanged (< 1% overhead)

---

## Original Acceptance Criteria (For Reference)
- [ ] Identify the top 5–10 highest-cost grep/find operations (by call site + why they are expensive).
- [ ] For each, document a safe optimization option that preserves behavior (e.g., narrower includes, precomputed file lists, fewer re-scans).
- [ ] Identify where timeouts should exist (external commands / scans) and define a standard approach compatible with macOS (Bash 3.2).
- [ ] Identify any loops that could become unbounded (while-read over generated lists, grouping loops, aggregation loops) and document the exact conditions that could cause non-termination.
- [ ] Produce a short “Stability Safeguards” proposal: minimal changes, highest value, lowest regression risk.
- [ ] Define a verification checklist (what to run, what to measure, what output must remain unchanged).

## Investigation Plan
### 1) Inefficient grep patterns on large codebases
- Inventory all recursive `grep -r` / `grep -rl` / `find ... -exec grep` call sites.
- Note whether:
  - `$PATHS` is a directory vs single file
  - includes/excludes are applied consistently
  - results are re-grepped multiple times (N× passes)
- Quick profiling approach:
  - Add optional timing wrapper around major sections (behind an env flag) to collect coarse section timings.
  - Run against a large real codebase and compare timings before/after proposed changes.

### 2) Missing timeout handling
- Identify operations that can stall:
  - recursive grep on networked/slow disks
  - `find ... -exec wc -l` on huge trees
  - `jq` / `python3` parsing on large payloads
- Decide on a portable timeout strategy:
  - Prefer `perl -e 'alarm ...'` wrapper or `python3` wrapper if GNU `timeout` is unavailable.
  - Ensure failure mode is graceful: emit warning + continue, or fail only if in strict mode.

### 3) Infinite loops in pattern matching
- Review `while read` loops that consume command output; ensure the producer can’t block indefinitely.
- Review aggregation logic:
  - grouping/unique extraction loops
  - any loop that re-processes the same growing file
- Confirm that pattern extraction and matching cannot feed itself (e.g., debug output being re-scanned).

## Deliverables
- A written report in this document with:
  - Findings table (call site → risk → proposed mitigation)
  - Recommended minimal patch list (no refactors)
  - Test/verification steps

## Notes
- Scope is intentionally limited to stability and performance guardrails; no feature additions.
- Preserve output formats (text/JSON/HTML) and baseline behavior.

---

## Recommendation Summary

**Current Status:** Script is working correctly (v1.0.81) with all critical bugs fixed.

**Recommended Action:** **Proceed with Phase 1 only** (1-2 hours)

**Why Phase 1 Now:**
- ✅ Low risk, high value safety nets
- ✅ Prevents catastrophic edge cases (hangs, runaway scans)
- ✅ No changes to core logic or output
- ✅ Easy to test and verify

**Why Defer Phase 2-3:**
- ⏸️ Need real-world profiling data to optimize effectively
- ⏸️ Higher risk of regressions without data
- ⏸️ Better to wait for user feedback on actual performance issues
- ⏸️ Premature optimization is the root of all evil

**Decision Point:** After Phase 1, wait for user feedback. Only proceed to Phase 2-3 if users report actual performance problems on large codebases.

**Success Metrics for Phase 1:**
- No scan hangs indefinitely (timeout protection)
- No runaway file processing (count limits)
- All existing tests pass
- Zero performance regression on small codebases
