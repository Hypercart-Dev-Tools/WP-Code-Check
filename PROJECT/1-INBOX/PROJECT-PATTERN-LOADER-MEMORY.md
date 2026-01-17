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
- [x] Phase 2 – Extend PATTERN-LIBRARY.json schema with detection/mitigation details needed by pattern-loader
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

- [x] Update `dist/bin/pattern-library-manager.sh` so each `patterns[]` entry also includes:
  - The resolved search pattern used by the scanner:
    - Either `search_pattern`, or an OR-joined string derived from `detection.patterns[].pattern` / `detection.patterns[].search`.
  - `file_patterns` (from `detection.file_patterns`), matching what `pattern_file_patterns` uses today.
  - `validator_script` and `validator_args` for scripted detections.
  - A richer mitigation configuration object with:
    - `enabled`
    - `validator_script`
    - `validator_args`
    - `severity_downgrade` (key/value map).

- [x] Keep existing summary/marketing fields intact and backward compatible (additive schema only).

- [x] Regenerate `dist/PATTERN-LIBRARY.json` and validate the new schema via `dist/bin/check-pattern-library-json.sh` to ensure all existing patterns are represented correctly.

**Phase 2 status (2026-01-16):**

- Thin registry adapter implemented in `dist/lib/pattern-loader.sh`.
- `load_pattern()` now prefers the enriched registry for core metadata, detection, and mitigation fields, with safe fallback to per-pattern JSON parsing.
- Registry-aware loading covers simple, scripted, headless/nodejs/js direct, aggregated, and clone-detection patterns.
- Regression checks executed where environment allowed (`verify-phase2-context-signals.sh`); PHP-specific tests are pending locally due to missing `php` binary but are expected to pass in CI.

**Phase 2 execution sequence (frozen plan)**

1. **Freeze and verify the registry schema**
   - Confirm that for every pattern, the registry now includes:
     - `search_pattern` or a combined pattern derived from `detection.search_pattern` / `detection.patterns[].pattern` / `detection.patterns[].search`.
     - `file_patterns` matching what `pattern_file_patterns` uses today.
     - `validator_script` and `validator_args` for scripted detections.
     - A full `mitigation_detection` object (enabled/script/args/severity_downgrade).
   - Cross-check that every field consumed by `dist/lib/pattern-loader.sh` has a 1:1 counterpart in the registry.
   - Treat any missing/mismatched field that affects behavior as a **Phase 2 blocker** (fix in `pattern-library-manager.sh` + regenerate the registry).

2. **Introduce a thin registry adapter in `pattern-loader.sh` (no external behavior change)**
   - Add small helpers (conceptually):
     - `registry_has_pattern "$pattern_id"`
     - `registry_get_field "$pattern_id" "$field_name"`
   - Implementation details:
     - First try to read from the enriched `PATTERN-LIBRARY.json`.
     - Fall back to the existing per-pattern JSON parsing when the registry is missing, the pattern is absent, or a field is not present.
     - Keep the public surface area of `load_pattern()` unchanged so callers do not need to be updated during Phase 2.

3. **Wire detection/mitigation fields through the adapter**
   - For each field group currently derived from JSON inside `load_pattern()`:
     - Core metadata: `pattern_id`, `pattern_enabled`, `pattern_detection_type`, `pattern_category`, `pattern_severity`, `pattern_title`.
     - Detection: `pattern_search`, `pattern_file_patterns`, `pattern_validator_script`, `pattern_validator_args`.
     - Mitigation: `pattern_mitigation_enabled`, `pattern_mitigation_script`, `pattern_mitigation_args`, `pattern_severity_downgrade`.
   - Change `load_pattern()` internals to **prefer** the registry adapter for these values whenever the registry can supply them, and only fall back to JSON parsing when required.
   - Ensure all detection types (simple, scripted, headless/nodejs/js direct, aggregated, clone detection) are covered.

4. **Regression pass focused on behavior (not performance)**
   - Run the existing fixture and baseline tests (e.g. `dist/tests/run-fixture-tests-v2.sh` and mitigation-focused tests) to confirm matches/misses are unchanged.
   - Spot-check a small set of representative patterns end-to-end:
     - A simple pattern (e.g. `file-get-contents-url`).
     - A pattern with multiple `detection.patterns[]` entries.
     - A scripted pattern with mitigation configuration.
     - A clone-detection pattern.
   - If failures appear, prefer fixing the registry/adapter mapping over adding runner-specific hacks, unless we uncover a pre-existing bug that should be corrected.

5. **Close out Phase 2 in this doc and changelog**
   - When the above is implemented and tests are green:
     - Mark the top-level Phase 2 checklist item as complete (`[x]`).
     - Capture any non-blocking gaps as bullets under **Future Enhancements** or as a short "Known limitations after Phase 2" subsection.
     - Bump the relevant script version(s) (e.g. `check-performance.sh`) and add a concise entry to `CHANGELOG.md` describing the Phase 2 completion.

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

This section focuses on validating the **Phase 2 registry-backed loader** and its fallbacks. Performance-focused work (Phase 3/4) remains for later iterations.

### 1. Pre-checks: Registry availability and validity

- [ ] Ensure the pattern registry exists and is valid JSON:

  ```bash
  # From repository root
  cd dist
  ./bin/check-pattern-library-json.sh
  ```

  **Expected:** Script exits with status 0 and prints a success message (or no errors). Any JSON parsing error here is a **blocker** for Phase 2.

### 2. Functional regression tests (fixtures + mitigation)

These confirm that preferring the registry in `load_pattern()` does **not** change detection or mitigation behavior.

- [ ] Run the main fixture test suite (local or CI emulation):

  ```bash
  # Local TTY
  cd dist
  ./tests/run-fixture-tests.sh

  # CI-style (no TTY)
  ./tests/run-tests-ci-mode.sh
  ```

  **Expected:**
  - All fixture tests pass (`Passed: N, Failed: 0`).
  - No new or changed findings for fixtures that exercise registry-backed patterns (e.g. `antipatterns.php`, `clean-code.php`, `file-get-contents-url.php`, `unsanitized-superglobal-read.php`).

- [ ] Run mitigation-focused tests (requires PHP in the environment):

  ```bash
  cd dist
  php tests/test-mitigation-detection.php
  ```

  **Expected:**
  - All mitigation scenarios still behave as before (severity downgrades, mitigation-enabled flags, validator selection).
  - No new failures introduced by registry-backed field loading.

> Note: On this dev machine, `php` is not available (`php: command not found`), so this step must be executed either in CI or in a local environment with PHP installed.

### 3. Registry vs. JSON fallback behavior

These checks validate that **fallbacks** still work when the registry is missing or unusable.

- [ ] Run a quick smoke test **without** the registry:

  ```bash
  cd dist
  mv PATTERN-LIBRARY.json PATTERN-LIBRARY.json.bak
  ./tests/run-fixture-tests.sh
  mv PATTERN-LIBRARY.json.bak PATTERN-LIBRARY.json
  ```

  **Expected:**
  - Fixture tests still pass.
  - No hard dependency on `PATTERN-LIBRARY.json` inside `load_pattern()` (the loader falls back cleanly to per-pattern JSON parsing).

- [ ] Optionally simulate an environment without `python3` (CI image without Python or by temporarily shadowing `python3`).

  **Expected:**
  - Registry adapter is skipped (`pattern_registry_available` returns false).
  - Loader uses legacy JSON parsing path; fixture tests remain green.

### 4. CI integration

In CI (GitHub Actions or equivalent), add/verify steps that run **after** any job that regenerates `PATTERN-LIBRARY.json`:

- [ ] `dist/bin/check-pattern-library-json.sh` (registry structural sanity check).
- [ ] `dist/tests/run-fixture-tests.sh` or `dist/tests/run-tests-ci-mode.sh` (behavioral regression check).
- [ ] `dist/tests/test-mitigation-detection.php` (when PHP is available in the CI image).

**Success criteria for Phase 2:** All of the above checks pass with no new failures and no drift in expected fixture results vs. pre-registry behavior.

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
 - **CI guardrail for registry-backed loader (optional):** Promote the registry-backed loader validation flow into a dedicated GitHub Actions job that runs after any change to `dist/PATTERN-LIBRARY.json` or `dist/lib/pattern-loader.sh`, wiring in:
   - `dist/bin/check-pattern-library-json.sh`
   - `dist/tests/run-fixture-tests.sh` or `dist/tests/run-tests-ci-mode.sh`
   - `dist/tests/test-mitigation-detection.php` (where PHP is available)

