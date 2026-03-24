# Magic Strings Detector - Observability Enhancement

**Created:** 2026-03-24
**Started:** 2026-03-24
**Status:** In Progress
**Priority:** Medium
**Assigned Version:** 2.2.8
**Selected Path:** B (Timing + Quality + State)
**Effort Remaining:** 2-3 hours
**Impact:** High

---

## Decision

Path B is the selected implementation path.

Before adding observability metrics, a technical spike was completed to remove a blocking defect in the magic-strings execution path.

---

## Technical Spike

**Status:** Completed
**Completed:** 2026-03-24

### Goal

Determine why Magic String Detector appeared to hang on a small plugin and fix the blocker before layering new metrics on top.

### Root Cause

- The pattern registry was in a stale state, so `load_pattern()` fell back to per-pattern Python parsing in `dist/lib/pattern-loader.sh`.
- Those fallback parsers used indented heredoc terminators with non-tab-stripping heredocs, which broke pattern extraction in the stale-registry path.
- For simple JSON-defined rules, that could leave `pattern_search` empty and make the scanner behave like it was stuck at the start of Magic String Detector.

### Patch

- Fixed the fallback Python heredocs in `dist/lib/pattern-loader.sh` so tab-indented terminators close correctly.
- Added a guard in `dist/bin/check-performance.sh` to skip simple rules with empty search patterns and emit an explicit warning.

### Verification

Command used:

```bash
WPCC_REGISTRY_DEBUG=1 PROFILE=1 DEBUG_TRACE=1 \
./dist/bin/check-performance.sh \
  --paths '/Users/noelsaw/Documents/GH Repos/creditconnection2-self-service' \
  --format text \
  --verbose \
  --ai-triage \
  --ai-verbose
```

Observed result:

- Scan completed through `Magic String Detector` and `Function Clone Detector`.
- Verification run completed in 35s.
- Profile output reported:
  - `MAGIC_STRING_DETECTOR`: 21311ms
  - `CRITICAL_CHECKS`: 9427ms
  - `FUNCTION_CLONE_DETECTOR`: 3967ms
  - `WARNING_CHECKS`: 1186ms
- Registry debug reported `state=stale`, `hits=0`, `misses=42`, and the scanner regenerated the registry at the end of the run.

### Notes

- The spike removed the blocker but did not add new observability metrics yet.
- The run also exposed unrelated issues outside this spike:
  - Missing validator script for `wp-template-tags-in-loops`
  - Baseline noise from unrelated historical paths

---

## Why Path B Still Makes Sense

- The scan now completes, so timing and quality metrics will describe real detector behavior instead of a broken fallback path.
- The verification run shows `MAGIC_STRING_DETECTOR` is still the dominant phase in this workload, so extra observability remains high value.
- Path B is still the best balance of implementation time and debugging value.

---

## Current State

**Now unblocked, but still lacking visibility:**
- Yes: detector runs to completion after the technical spike
- Yes: basic progress indicators (every 10 seconds)
- Yes: timeout protection and iteration limits
- Yes: profiling framework already exists and is usable
- No: phase timing per aggregated pattern in normal output
- No: quality metrics showing raw -> unique -> violations
- No: explicit phase/state tracking inside aggregated pattern processing
- No: JSON output for magic-string metrics

---

## Path B Scope

### 1. Timing Metrics

Track duration of the three aggregated-pattern phases:

- GREP
- EXTRACT
- AGGREGATE

### 2. Quality Metrics

Track:

- raw matches
- extracted strings
- unique strings
- filtered strings
- final violations

### 3. State Tracking

Add lightweight phase tracking for debugging:

- IDLE
- GREP
- EXTRACT
- AGGREGATE
- COMPLETE

### 4. Output Integration

Expose metrics in:

- terminal output when `--verbose` or profiling is enabled
- JSON output for downstream reporting

### 5. Testing and Docs

- verify no meaningful performance regression
- update changelog
- update plan status and results

---

## Technical Details

**Main file:** `dist/bin/check-performance.sh`
**Main function:** `process_aggregated_pattern()`

**Primary phases:**
1. GREP
2. EXTRACT
3. AGGREGATE

**Metrics to add:**

```text
Timing: MAGIC_GREP_TIME, MAGIC_EXTRACT_TIME, MAGIC_AGGREGATE_TIME (ms)
Counts: raw_matches, extracted_strings, unique_strings, violations, filtered_strings
Quality: extraction_rate (%), strings_below_min_files, strings_below_min_matches
State: current_phase
```

**JSON output target:**

```json
"magic_string_metrics": {
  "patterns_processed": 4,
  "total_raw_matches": 1250,
  "total_unique_strings": 45,
  "total_violations": 8,
  "timing_ms": {"grep": 245, "extract": 1820, "aggregate": 340}
}
```

---

## Implementation Checklist

### Completed Spike Work

- [x] Reproduce the stall on `creditconnection2-self-service`
- [x] Identify the stale-registry fallback defect
- [x] Patch the fallback loader
- [x] Add empty-search guardrails
- [x] Re-run scan and verify Magic String Detector completes

### Path B Remaining Work

- [ ] Add timing variables at `process_aggregated_pattern()` start
- [ ] Capture GREP, EXTRACT, and AGGREGATE elapsed times
- [ ] Track extracted-string count during capture
- [ ] Track filtered-string reasons before violation output
- [ ] Add lightweight phase/state tracking for debug output
- [ ] Output metrics in verbose/profile mode
- [ ] Add metrics to JSON output
- [ ] Test with `--verbose` and `--format json`
- [ ] Verify less than 1% performance overhead on representative scan set
- [ ] Update changelog with Path B implementation details

---

## Success Criteria

- [x] Technical spike completed and blocker removed
- [ ] Phase timing visible in verbose output
- [ ] Quality metrics shown as raw -> unique -> violations
- [ ] State transitions logged in debug mode
- [ ] Metrics present in JSON output
- [ ] No meaningful performance regression
- [ ] Works with existing flags

---

## Next Steps

1. Implement Path B metrics inside `process_aggregated_pattern()`.
2. Surface the metrics in text and JSON output.
3. Re-run the same plugin path plus one larger regression target to check overhead.