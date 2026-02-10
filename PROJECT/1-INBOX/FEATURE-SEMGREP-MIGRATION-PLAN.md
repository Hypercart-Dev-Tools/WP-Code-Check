# Semgrep Migration and Search Backend Stabilization

**Created:** 2026-02-10
**Status:** Not Started
**Priority:** High

## Problem/Request
Intermittent scan stalls occur on very large repositories (expected risk) and sometimes on smaller projects (unexpected). The current scanner mixes cached and uncached recursive search paths, with several raw `grep -r*` and `xargs grep` call sites that can still cause unstable runtime behavior.

## Context
- Scanner entrypoint: `dist/bin/check-performance.sh`
- Current architecture already has useful safeguards:
  - `MAX_SCAN_TIME`
  - `run_with_timeout()`
  - `cached_grep()`
  - `.wpcignore` support
  - `--skip-magic-strings`
- Remaining high-risk hotspots still use raw recursive grep or raw xargs patterns:
  - `dist/bin/check-performance.sh:2617`
  - `dist/bin/check-performance.sh:3222`
  - `dist/bin/check-performance.sh:4216`
  - `dist/bin/check-performance.sh:4617`
  - `dist/bin/check-performance.sh:5024`
  - `dist/bin/check-performance.sh:5271`
  - `dist/bin/check-performance.sh:5463`
  - `dist/bin/check-performance.sh:5554`
  - `dist/bin/check-performance.sh:5633`

## Direct Answer: Improvements Possible on Raw Recursive/Xargs Paths
Yes. The most impactful improvements are:
- Replace raw `grep -r*` call sites with one wrapper that enforces timeout, exclusion handling, and consistent output parsing.
- Remove `cat file | xargs grep` patterns in favor of null-delimited input (`tr '\n' '\0' | xargs -0`) or direct file iteration.
- Add per-check elapsed-time logging and heartbeat progress output for long-running loops.
- Precompute extension-specific file lists once (PHP/JS/TS) and reuse them across checks.
- Add a global fail-safe per phase so a single problematic check degrades gracefully instead of appearing hung.

## 4-Phase Plan

### Phase 0: Quick Wins (Current System, Low-Medium Effort)
**Goal:** Reduce hangs quickly without changing core detection architecture.

**Scope**
- Keep Bash + current pattern system.
- Patch unstable search call sites and observability gaps.

**Tasks**
1. Replace known raw recursive/xargs hotspots with safer cached/wrapped calls.
2. Standardize null-delimited file handling for all multi-file grep execution.
3. Ensure every expensive check uses timeout guards.
4. Add heartbeat logs every 10 seconds for long loops.
5. Add top-N slow checks summary at end of scan.
6. Improve docs for `.wpcignore`, `--skip-magic-strings`, and `MAX_SCAN_TIME`.

**Deliverables**
- Stability patch in `dist/bin/check-performance.sh`
- Short troubleshooting section in docs
- Baseline performance snapshot (before/after)

**Exit Criteria**
- [ ] No unguarded raw `grep -r*` or unsafe `xargs grep` in active scan path
- [ ] Small-project scans complete reliably in repeated runs
- [ ] Users can identify long-running checks from logs

### Phase 1: Unified Search Backend Wrapper
**Goal:** Normalize all search operations behind one backend wrapper with safe defaults.

**Scope**
- Introduce a single search API layer in shell helper(s).
- Keep default backend regex-based and behavior-compatible.

**Tasks**
1. Create wrapper functions for:
   - file discovery
   - line match search
   - context extraction
2. Enforce shared behavior:
   - timeout
   - exclusion rules
   - null-safe file handling
   - consistent `file:line:code` formatting
3. Route all checks through wrapper API.
4. Add regression fixtures for output parity.

**Deliverables**
- Unified wrapper module
- Refactored scanner call sites
- Regression report proving parity vs current output

**Exit Criteria**
- [ ] All checks call wrapper functions, not raw search commands
- [ ] Timeout/exclusion behavior is consistent across checks
- [ ] Fixture suite passes with no critical regressions

### Phase 2: Optional Semgrep Backend Pilot (5-10 Noisy Rules)
**Goal:** Validate Semgrep on targeted noisy rules without destabilizing the scanner.

**Scope**
- Semgrep is optional via feature flag.
- Pilot only direct/noisy rule subset.

**Candidate Rules (initial)**
1. `unsanitized-superglobal-read`
2. `spo-002-superglobal-manipulation`
3. `wpdb-query-no-prepare`
4. `php-eval-injection`
5. `php-dynamic-include`
6. `php-shell-exec-functions`
7. `php-hardcoded-credentials`
8. `unsanitized-superglobal-isset-bypass`
9. `file-get-contents-url`
10. `wp-json-html-escape` (evaluate feasibility)

**Tasks**
1. Implement `--search-backend semgrep` toggle (default remains current backend).
2. Author Semgrep rules for pilot set.
3. Build comparison harness using fixtures and IRL samples:
   - precision proxy (false-positive rate)
   - recall proxy (findings retained)
   - runtime comparison
4. Generate a per-rule scorecard.

**Deliverables**
- Optional Semgrep integration path
- Pilot Semgrep rule pack
- Benchmark report with recommendation per rule

**Exit Criteria**
- [ ] Pilot runs end-to-end in CI/local test flow
- [ ] Scorecard exists for each pilot rule
- [ ] Clear go/no-go decision per rule

### Phase 3: Production Promotion Strategy
**Goal:** Promote only Semgrep rules that beat current implementation, keep Bash where it is stronger.

**Scope**
- Keep Bash for aggregated, clone-detection, and workflow/context-heavy checks.
- Promote Semgrep selectively for proven direct pattern checks.

**Tasks**
1. Define promotion gates (accuracy and runtime thresholds).
2. Migrate winning pilot rules to Semgrep default path.
3. Keep fallback to Bash backend per rule.
4. Update docs and changelog with backend matrix and troubleshooting.

**Deliverables**
- Hybrid production scanner (Semgrep + Bash)
- Rule ownership matrix (Semgrep-managed vs Bash-managed)
- Rollback plan and fallback toggles

**Exit Criteria**
- [ ] Promoted rules meet agreed quality/performance gates
- [ ] No regression in fixture and smoke suites
- [ ] Clear operational fallback documented

## Success Metrics
- [ ] 95th percentile scan time reduced on medium repositories
- [ ] Fewer reports of "apparent hangs" on small repositories
- [ ] Equal or lower false-positive rate on migrated rules
- [ ] Zero loss of coverage for aggregated/scripted checks

## Risks
- Semgrep dependency and install friction for some users
- Rule drift between Bash and Semgrep implementations
- Initial parity gaps on WordPress-specific edge cases

## Mitigations
- Keep Semgrep optional until scorecards validate migration
- Maintain per-rule fallback to Bash
- Use fixture + IRL validation for every migration decision

## Acceptance Criteria
- [ ] Four-phase plan approved for execution order
- [ ] Phase 0 task list accepted as immediate next sprint
- [ ] Success metrics and promotion gates agreed before Phase 2 rollout

