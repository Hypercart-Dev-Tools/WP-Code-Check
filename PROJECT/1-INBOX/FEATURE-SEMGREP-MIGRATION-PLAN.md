# Semgrep Migration and Search Backend Stabilization

**Created:** 2026-02-10
**Status:** Phase 0a Complete
**Priority:** High
**Last Updated:** 2026-03-23

## Problem/Request
Intermittent scan stalls still matter on very large repositories and the scanner still mixes multiple search paths. The highest-risk problems are no longer unguarded hangs in the active path; they are now a maintainability split between `cached_grep()`-based scans, timeout-wrapped raw recursive file discovery, and helper-level `xargs` or raw `grep -r` fallback behavior.

## Context
- Scanner entrypoint: `dist/bin/check-performance.sh`
- Current architecture already has useful safeguards:
  - `MAX_SCAN_TIME`
  - `run_with_timeout()`
  - `cached_grep()`
  - `.wpcignore` support
  - `--skip-magic-strings`
- Active scan path still contains timeout-wrapped raw recursive file-discovery calls:
   - `dist/bin/check-performance.sh:4372` - `AJAX_FILES`
   - `dist/bin/check-performance.sh:4773` - `TERMS_FILES`
   - `dist/bin/check-performance.sh:5180` - `CRON_FILES`
   - `dist/bin/check-performance.sh:5427` - `N1_FILES`
   - `dist/bin/check-performance.sh:5619` - `THANKYOU_CONTEXT_FILES`
   - `dist/bin/check-performance.sh:5710` - `SMART_COUPONS_FILES`
   - `dist/bin/check-performance.sh:5722` - `PERF_RISK_FILES`
   - `dist/bin/check-performance.sh:5789` - `JSON_RESPONSE_FILES`
- Helper-level raw search behavior still exists and is part of the maintenance burden:
   - `dist/bin/check-performance.sh:3378` - aggregated pattern `xargs grep`
   - `dist/bin/check-performance.sh:3381` - aggregated pattern raw `grep -rHn` fallback
   - `dist/bin/check-performance.sh:3576` - `fast_grep()` `xargs grep`
   - `dist/bin/check-performance.sh:3579` - `fast_grep()` raw `grep -rHn` fallback
   - `dist/bin/check-performance.sh:3634` - `cached_grep()` raw `grep -rHn` fallback

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
**Status:** ✅ Phase 0a Complete | Phase 0b Deferred

**Scope**
- Keep Bash + current pattern system.
- Patch unstable search call sites and observability gaps.

**Tasks**
1. ~~Replace known raw recursive/xargs hotspots with safer cached/wrapped calls.~~ → Refined: xargs calls at lines 2617/3222 are intentionally using pre-cached file lists inside already-protected paths — not actual hotspots. The real issue was 8 unprotected `grep -rl` file-discovery calls.
2. Standardize null-delimited file handling for all multi-file grep execution. → Deferred (existing `cached_grep` already uses `tr '\n' '\0' | xargs -0`; the 8 patched calls are file-discovery, not line-matching)
3. ✅ **Ensure every expensive check uses timeout guards.** — Complete (2026-02-09). The active file-discovery calls remain raw `grep -r*`, but they are wrapped with `run_with_timeout "$MAX_SCAN_TIME"`:
   - `AJAX_FILES` (line ~4372)
   - `TERMS_FILES` (line ~4773)
   - `CRON_FILES` (line ~5180)
   - `N1_FILES` (line ~5427, pipeline — timeout wraps the recursive grep stage)
   - `THANKYOU_CONTEXT_FILES` (line ~5619)
   - `SMART_COUPONS_FILES` (line ~5710)
   - `PERF_RISK_FILES` (line ~5722)
   - `JSON_RESPONSE_FILES` (line ~5789)
4. Add heartbeat logs every 10 seconds for long loops. → Deferred to Phase 0b
5. Add top-N slow checks summary at end of scan. → Deferred to Phase 0b
6. Improve docs for `.wpcignore`, `--skip-magic-strings`, and `MAX_SCAN_TIME`. → Deferred to Phase 0b

**Deliverables**
- ✅ Stability patch in `dist/bin/check-performance.sh`
- Short troubleshooting section in docs → Deferred to Phase 0b
- Baseline performance snapshot (before/after) → Deferred to Phase 0b

**Exit Criteria**
- [x] No unguarded raw `grep -r*` in active scan path; however, active scan still contains timeout-wrapped raw file-discovery calls and helper internals still retain raw `grep -r` / `xargs grep` fallback behavior
- [ ] Small-project scans complete reliably in repeated runs → Needs verification testing
- [ ] Users can identify long-running checks from logs → Deferred to Phase 0b

**Implementation Notes (2026-02-09):**
- The xargs calls at lines 2617 and 3222 were originally listed as hotspots but are inside already-protected paths (pre-cached file list + `run_with_timeout`). Removed from scope.
- Timeout behavior: on timeout, check returns empty result, reports "passed," scan continues. Silent degradation chosen over hang. Per-check timeout warnings remain deferred and are now tracked in `4X4.md` instead of `BACKLOG.md`.
- No new functions or abstractions introduced — reuses existing `run_with_timeout` infrastructure.

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

**Candidate Rules (reprioritized for current false-positive pressure)**
1. `unsanitized-superglobal-read`
2. `unsanitized-superglobal-isset-bypass`
3. `wpdb-query-no-prepare`
4. `file-get-contents-url`
5. `wp-json-html-escape`
6. `php-hardcoded-credentials`
7. `php-eval-injection`
8. `spo-002-superglobal-manipulation` - lower urgency after the inline grep quoting fix
9. `php-dynamic-include` - lower urgency after the WP-CLI bootstrap false-positive fix
10. `php-shell-exec-functions` - lower urgency after the `curl_exec()` word-boundary fix

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
- [x] Four-phase plan approved for execution order
- [x] Phase 0 task list accepted as immediate next sprint
- [x] Phase 0a (timeout guards) implemented and merged
- [ ] Phase 0b (observability) completed
- [ ] Success metrics and promotion gates agreed before Phase 2 rollout

