# Pattern Loader Memory Optimization

**Created:** 2026-01-15  
**Status:** In Progress  
**Priority:** Medium  
**Estimated Impact:** 6-12x faster pattern loading (600-1200ms → 50-100ms)

---

## Table of Contents

1. [Overview](#pattern-loader-memory-optimization)
2. [Phase Checklist](#phase-checklist)
3. [Problem Statement](#problem-statement)
4. [Proposed Solution](#proposed-solution)
5. [Implementation Plan](#implementation-plan)
6. [Registry vs Loader Field Mapping](#registry-vs-loader-field-mapping)
7. [Performance Expectations](#performance-expectations)
8. [Fallback Strategy](#fallback-strategy)
9. [Acceptance Criteria](#acceptance-criteria)
10. [Testing Plan](#testing-plan)
11. [Risks & Mitigations](#risks--mitigations)
12. [Future Enhancements](#future-enhancements)

---

## Phase Checklist

> Note for LLMs: Continuously update this checklist as work progresses (design, implementation, and testing) so humans can see high-level status without scrolling.

- [x] Phase 0 – Analyze current PATTERN-LIBRARY.json schema vs pattern-loader requirements
- [x] Phase 1 – Use PATTERN-LIBRARY.json for metadata + discovery (keep detection/mitigation loading as-is)
- [ ] Phase 2 – Extend PATTERN-LIBRARY.json schema with detection/mitigation details needed by pattern-loader
- [ ] Phase 3 – Implement in-memory pattern loader + Bash-friendly registry interface with robust fallbacks
- [ ] Phase 4 – Measure performance impact, validate fallbacks, and document results

---

## Problem Statement

The scanner currently loads and parses pattern JSON files multiple times during each scan:

1. **5 separate `find` operations** - Scanning the same directory tree for different pattern types
2. **52+ JSON files** opened and parsed multiple times (once for discovery, once for loading)
3. **52+ Python subprocesses** spawned for complex field extraction
4. **No caching** - Patterns re-parsed every time they're accessed

**Current overhead:** ~600-1200ms per scan just for pattern loading operations.

---

## Proposed Solution

Load all patterns into memory **once** at scan startup, then access pre-loaded data instead of re-parsing files.

### Approach: Leverage Existing PATTERN-LIBRARY.json

The `pattern-library-manager.sh` already generates `dist/PATTERN-LIBRARY.json` with complete **core metadata** after each scan. We can use this as a pre-computed pattern registry and extend it as needed.

**Benefits:**
- ✅ Already exists - no new data structure needed
- ✅ Pre-computed - all core metadata already extracted (id, enabled, category, severity, title, pattern_type, heuristic flag, mitigation flag, etc.)
- ✅ Extensible - detection/mitigation details can be added in a backward-compatible way
- ✅ Auto-updated - regenerated after each scan

---

## Implementation Plan

> Phase 0 (analysis) is captured in the **Registry vs Loader Field Mapping** section below and is already complete.

### Phase 1: Use PATTERN-LIBRARY.json for metadata and discovery

**Goal:** Reduce repeated `find`/`grep` work and duplicated metadata parsing, without changing how detection/mitigation details are loaded.

- Treat `dist/PATTERN-LIBRARY.json` as the single source of truth for:
  - Which patterns exist (`id`, `file`).
  - Which patterns are enabled/disabled.
  - Core metadata: category, severity, title, pattern_type, heuristic flag, mitigation flag.
- Implement registry-based discovery in `dist/bin/check-performance.sh` via `get_patterns_from_registry()`:
  - Reads `dist/PATTERN-LIBRARY.json` once per scan using Python.
  - Filters by `detection_type`, `pattern_type`, and `enabled` flag.
  - Maps each entry to the correct file path under `dist/patterns/` (including `headless/`, `nodejs/`, `js/`).
  - Returns pattern file lists for simple, scripted, direct, aggregated, and clone-detection runners.
- Keep `dist/lib/pattern-loader.sh` responsible for loading detection/mitigation details from individual JSON files on demand.

**Phase 1 status (2026-01-16):**

- Registry-based discovery is implemented and enabled by default when `dist/PATTERN-LIBRARY.json` and `python3` are available.
- All major runners (simple, scripted, headless/nodejs/js direct, aggregated, clone detection) now prefer the registry and fall back to legacy `find`-based discovery only when the registry is missing or unreadable.

### Phase 2: Extend PATTERN-LIBRARY.json schema with detection/mitigation details

**Goal:** Make the registry rich enough that it can eventually satisfy everything `pattern-loader.sh` needs, without re-opening each JSON file.

- Update `dist/bin/pattern-library-manager.sh` so each `patterns[]` entry also includes:
  - The resolved search pattern used by the scanner:
    - Either `search_pattern`, or an OR-joined string derived from `detection.patterns[].pattern`.
  - `file_patterns` (from `detection.file_patterns`), matching what `pattern_file_patterns` uses today.
  - `validator_script` and `validator_args` for scripted detections.
  - A richer `mitigation_detection` object with:
    - `enabled`
    - `validator_script`
    - `validator_args`
    - `severity_downgrade` (key/value map).
- Keep existing summary/marketing fields intact and backward compatible.
- Regenerate `dist/PATTERN-LIBRARY.json` and validate the new schema (e.g. via a small test harness) to ensure all existing patterns are represented correctly.

### Phase 3: Implement in-memory pattern loader

**Goal:** Load all pattern metadata + detection/mitigation details once per scan, then avoid per-pattern JSON parsing and extra Python subprocesses during the hot path.

- Introduce `dist/bin/lib/load-pattern-registry.py` to:
  - Read the enriched `dist/PATTERN-LIBRARY.json` (note: actual path is `dist/PATTERN-LIBRARY.json`, not repo root).
  - Build an in-memory registry (in Python) and export it in a Bash 3–compatible way, for example:
    - A temp file of `PATTERN_<ID>_<FIELD>=...` assignments that can be `source`d, **or**
    - A compact JSON cache that follow-up helpers can query in a single Python process.
- In `dist/bin/check-performance.sh`:
  - Add an early `PATTERN_REGISTRY_LOAD` section (after `REPO_ROOT`/`SCRIPT_DIR` are set) that:
    - Checks for `dist/PATTERN-LIBRARY.json`.
    - Invokes `load-pattern-registry.py` and records `PATTERN_REGISTRY_LOADED=true/false`.
    - Performs a robust staleness check (e.g. if any file under `patterns/` is newer than the registry, skip the registry and fall back to per-file parsing for that run).
- In `dist/lib/pattern-loader.sh`:
  - Update `load_pattern()` so that when `PATTERN_REGISTRY_LOADED=true`:
    - It pulls `pattern_id`, `pattern_enabled`, `pattern_category`, `pattern_severity`, `pattern_title`, `pattern_search`, `pattern_file_patterns`, validator fields, and mitigation fields from the pre-loaded registry.
    - It avoids re-opening the JSON file and avoids spawning additional Python subprocesses on the hot path.
  - When `PATTERN_REGISTRY_LOADED=false` or a pattern is missing from the registry, fall back to the existing JSON/Python-based parsing logic.
  - Ensure all Bash indirection is valid in Bash 3 (no associative arrays; use carefully constructed variable names or a small lookup helper instead).

### Phase 4: Measure, harden, and document

**Goal:** Confirm the performance wins and robustness, and make the behavior transparent to future maintainers.

- Use the existing profiling hooks (e.g. `PROFILE=1`) to measure:
  - Pattern discovery time before vs after Phase 1.
  - Pattern loading time before vs after Phase 3.
- Add smoke tests around failure modes:
  - Missing `dist/PATTERN-LIBRARY.json` (first run / registry generation failure).
  - Corrupt or partially-written registry.
  - Stale registry vs modified pattern JSONs.
- Update documentation:
  - Summarize the final registry schema and its relationship to individual pattern JSON files.
  - Cross-link with `PATTERN-LIBRARY-MANAGER-README.md` and this project doc.

---

## Registry vs Loader Field Mapping

This section captures the current state (as of 2026-01-16) of `dist/PATTERN-LIBRARY.json` vs what `dist/lib/pattern-loader.sh` actually needs at runtime.

### PATTERN-LIBRARY.json per-pattern fields (today)

Each entry under `"patterns"` currently includes:

- `id`
- `version`
- `enabled`
- `category`
- `severity`
- `title`
- `description`
- `detection_type`
- `pattern_type`
- `mitigation_detection` (boolean flag indicating presence of mitigation configuration)
- `heuristic` (boolean)
- `file` (basename of the pattern JSON file)

These make the registry an excellent source of truth for **metadata and discovery**, but they do **not** include the actual search patterns or detailed mitigation configuration.

### Fields used by pattern-loader.sh

`dist/lib/pattern-loader.sh` currently derives the following from each individual pattern JSON file:

- Core metadata:
  - `pattern_id` (from `id`)
  - `pattern_enabled` (from `enabled`)
  - `pattern_detection_type` (from `detection.type` or root `detection_type`)
  - `pattern_category` (from `category`)
  - `pattern_severity` (from `severity`)
  - `pattern_title` (from `title`)
- Detection details:
  - `pattern_search` – from `detection.search_pattern` **or** OR-joined from `detection.patterns[].pattern`.
  - `pattern_file_patterns` – from `detection.file_patterns[]`, defaulting to `"*.php"`.
  - `pattern_validator_script` and `pattern_validator_args` – from `detection.validator_script` / `detection.validator_args` when `pattern_detection_type="scripted"`.
- Mitigation details (from `mitigation_detection`):
  - `pattern_mitigation_enabled` (enabled flag)
  - `pattern_mitigation_script` (validator script)
  - `pattern_mitigation_args` (validator args)
  - `pattern_severity_downgrade` (encoded as `KEY=VALUE;KEY2=VALUE2...`).

### Gaps between registry and loader needs

Fields **not** present in `PATTERN-LIBRARY.json` today but required by `pattern-loader.sh` for full in-memory loading:

- `pattern_search` / combined search pattern (derived from `detection.search_pattern` or `detection.patterns[].pattern`).
- `file_patterns` (from `detection.file_patterns`).
- `validator_script` and `validator_args` for scripted detection types.
- Detailed `mitigation_detection` configuration (enabled/script/args/severity_downgrade), beyond the simple boolean flag.

### Implications for this project

- **Today:** `PATTERN-LIBRARY.json` is ready to be used as a **metadata + discovery cache** (Phase 1).
- **To reach full in-memory loading:** The registry must be extended to include the detection/mitigation details listed above (Phase 2), after which Phase 3 can safely move `load_pattern()` to rely primarily on the registry, with a fallback to direct JSON parsing.

---

## Performance Expectations

### Current Performance
- **Pattern discovery:** 5 × find + 52 × grep = ~150ms
- **Pattern loading:** 52 × (Python subprocess + grep/sed) = ~600-1000ms
- **Total overhead:** ~750-1150ms per scan

### Optimized Performance
- **Registry load:** 1 × Python parse + export = ~50ms
- **Pattern discovery:** Array lookup = ~1ms
- **Pattern loading:** Variable access = ~0.1ms per pattern
- **Total overhead:** ~55ms per scan

**Expected speedup:** 6-12x faster (especially noticeable on large codebases)

---

## Fallback Strategy

**If PATTERN-LIBRARY.json doesn't exist:**
- First scan after fresh clone
- Registry generation failed
- Patterns modified but registry not regenerated

**Solution:** Fall back to current approach (individual file parsing)

**Staleness detection:**
```bash
# Check if any pattern file is newer than registry
if [ "$PATTERN_REGISTRY_FILE" -ot "$REPO_ROOT/patterns" ]; then
  # Registry is stale - regenerate or use fallback
fi
```

---

## Acceptance Criteria

- [ ] Single Python script loads all patterns from PATTERN-LIBRARY.json
- [ ] Pattern metadata exported to Bash-friendly format (temp file or env vars)
- [ ] Scanner loads registry once at startup
- [ ] Pattern discovery uses pre-loaded data (no repeated find operations)
- [ ] `load_pattern()` uses pre-loaded data (no Python subprocesses)
- [ ] Fallback to current approach if registry missing
- [ ] Performance improvement measured and documented
- [ ] Bash 3 compatibility maintained
- [ ] No breaking changes to existing pattern format

---

## Testing Plan

1. **Baseline measurement:** Time current pattern loading with `PROFILE=1`
2. **Implementation:** Add registry loader and modify scanner
3. **Performance test:** Compare before/after with same codebase
4. **Fallback test:** Delete PATTERN-LIBRARY.json and verify graceful degradation
5. **Compatibility test:** Test on Bash 3 and Bash 4+ environments
6. **Large codebase test:** Measure improvement on WooCommerce or similar

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Stale registry | Incorrect pattern metadata | Check file timestamps, regenerate if stale |
| Registry corruption | Scan fails | Validate JSON before loading (e.g. `dist/bin/check-pattern-library-json.sh`), fallback on error |
| Memory usage | Bash variable limits | Use temp file instead of env vars if needed |
| Bash 3 compatibility | Breaks on older systems | Use simple key-value format, no associative arrays |

---

## Future Enhancements

- **Incremental updates:** Only reload changed patterns
- **Pattern versioning:** Detect version mismatches between registry and files
- **Parallel loading:** Load patterns in background while file list builds
- **Pattern caching:** Cache across multiple scans (with invalidation)

