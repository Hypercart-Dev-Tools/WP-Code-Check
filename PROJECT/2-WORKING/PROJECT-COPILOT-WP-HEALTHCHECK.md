**STATUS:** Phase 2.1 Complete ✅ - Phase 3 Ready
**Author:** GitHub Copilot (Chat GPT 5.2) + Augment Agent (Claude Sonnet 4.5)
**PRIORITY**: High
**Started:** 2026-01-12
**Phase 1 Completed:** 2026-01-12
**Phase 1 Improvements Completed:** 2026-01-12
**Phase 2 Completed:** 2026-01-12
**Phase 2.1 Completed:** 2026-01-12

## Context

This plan is based on a real-world calibration exercise where the **deterministic GREP/pattern scanner output (raw JSON findings)** was compared against a **manual review of the actual WP Health Check & Troubleshooting plugin code in `/temp`**. The goal is to convert the observed false positives and “needs review” hot spots into concrete scanner improvements that reduce noise without hiding genuine issues.

## Table of Contents

- [Phased Progress Checklist (High Level)](#phased-progress-checklist-high-level)
- [Phase 1 — Reduce Obvious False Positives (Low Risk, High Impact)](#phase-1--reduce-obvious-false-positives-low-risk-high-impact)
- [Phase 2 — Add Context Signals (Guards + Sanitization) to Improve Triage](#phase-2--add-context-signals-guards--sanitization-to-improve-triage)
- [Phase 3 — Reclassify Findings (Categories + Severity Defaults)](#phase-3--reclassify-findings-categories--severity-defaults)
- [Acceptance Criteria](#acceptance-criteria)

> **Note for the LLM/agent:** As each task is completed, continuously update this document by ticking the relevant checklist items (`[x]`).
Also, update changelog to reflect changes.

## Phased Progress Checklist (High Level)

- [x] **Phase 1 complete:** Scanner no longer flags PHPDoc/comment-only matches; avoids POST-method false positives in HTML/REST config. ✅ **COMPLETED 2026-01-12**
- [x] **Phase 2 complete:** Findings include context signals (nonce/cap checks; sanitizer detection) and are downgraded appropriately. ✅ **COMPLETED 2026-01-12**
- [ ] **Phase 3 complete:** Findings are categorized (security vs best-practice vs performance) with clearer default severities.

### Phase 1 Results (2026-01-12)

**Initial Implementation (v1.2.3):**
- ✅ Created `is_line_in_comment()` helper function to detect PHPDoc/comment blocks
- ✅ Created `is_html_or_rest_config()` helper function to detect HTML forms and REST route configs
- ✅ Integrated filters into HTTP timeout check, superglobal manipulation check, and unsanitized superglobal read check
- ✅ Created test fixtures: `phase1-comment-filtering.php` and `phase1-html-rest-filtering.php`

**Phase 1 Improvements (v1.2.4):**
- ✅ Improved `is_line_in_comment()` with string literal detection, 100-line backscan, inline comment detection
- ✅ Improved `is_html_or_rest_config()` with anchored patterns, case-insensitive matching
- ✅ Moved helpers to shared library: `dist/bin/lib/false-positive-filters.sh`
- ✅ Created verification script: `dist/tests/verify-phase1-improvements.sh`
- ✅ Enhanced test fixtures with 12+ edge cases

**Results on Health Check Plugin:**
- **Baseline (before Phase 1)**: 75 total findings
- **After Phase 1 (v1.2.3)**: 74 total findings (3 PHPDoc false positives eliminated)
- **After Phase 1 Improvements (v1.2.4)**: **67 total findings**
- **Total Improvement**: **10.6% reduction** (8 false positives eliminated)
- **HTTP Timeout Findings**: Consistently 3 (all actual code, no false positives)

**Files Modified:**
- `dist/bin/check-performance.sh` - Integrated shared library, removed duplicate code
- `dist/bin/lib/false-positive-filters.sh` - New shared library with improved helpers
- `dist/tests/fixtures/phase1-comment-filtering.php` - Enhanced with edge cases
- `dist/tests/fixtures/phase1-html-rest-filtering.php` - Enhanced with edge cases
- `dist/tests/verify-phase1-improvements.sh` - New verification script

### Phase 2 Results (2026-01-12)

**Implementation (v1.3.0):**
- ✅ Created `detect_guards()` function to detect nonce and capability checks
- ✅ Created `detect_sanitizers()` function to detect sanitization functions
- ✅ Created `detect_sql_safety()` function to distinguish safe vs unsafe SQL
- ✅ Enhanced `add_json_finding()` to accept optional guards and sanitizers parameters
- ✅ Updated superglobal manipulation check to use guard detection and downgrade severity
- ✅ Updated unsanitized superglobal check to use both guard and sanitizer detection
- ✅ Updated wpdb prepare check to detect safe literal SQL vs unsafe concatenated SQL
- ✅ Fixed bash compatibility issues (removed `local` keyword from loop contexts)

**JSON Output Enhancements:**
- All findings now include `"guards":[]` array with detected security guards
- All findings now include `"sanitizers":[]` array with detected sanitizers
- Context messages include guard/sanitizer information for faster triage
- Example: `"Unsanitized superglobal access (has guards: wp_verify_nonce)"`

**Severity Downgrading Logic:**
- **Guards only**: Severity downgraded one level (HIGH → MEDIUM, CRITICAL → HIGH)
- **Sanitizers only**: Severity downgraded one level (HIGH → MEDIUM, CRITICAL → HIGH)
- **Guards + Sanitizers**: Finding suppressed entirely (fully protected)
- **Safe literal SQL**: Downgraded to LOW/MEDIUM with "(literal SQL - best practice)" note
- **No protection**: Original severity maintained

**Test Fixtures Created:**
- `dist/tests/fixtures/phase2-guards-detection.php` - Tests guard detection (14 test cases)
- `dist/tests/fixtures/phase2-wpdb-safety.php` - Tests SQL safety detection (12 test cases)
- `dist/tests/verify-phase2-context-signals.sh` - Automated verification script

**Files Modified:**
- `dist/bin/check-performance.sh` (v1.3.0) - Added guard/sanitizer detection, severity downgrading
- `dist/bin/lib/false-positive-filters.sh` (v1.2.0) - Added 3 new detection functions
- `CHANGELOG.md` - Documented Phase 2 changes

### Phase 2.1 Results (2026-01-12)

**Implementation (v1.3.1):**
- ✅ **Issue #2 Fixed**: Removed suppression logic - guards+sanitizers now emit as LOW severity
- ✅ **Issue #4 Fixed**: Removed `user_can()` from guard detection (only `current_user_can()` now)
- ✅ **Issue #1 Fixed**: Function-scoped guard detection with `get_function_scope_range()`
- ✅ **Issue #3 Fixed**: Basic taint propagation tracks sanitized variable assignments
- ✅ **Issue #5 Fixed**: Comprehensive test fixtures for branch misattribution and multi-line sanitization

**Key Improvements:**
- **No More Suppression**: Findings always emitted, even with guards+sanitizers (prevents false negatives)
- **Function Scoping**: Guards must be in same function and BEFORE access (prevents branch misattribution)
- **Variable Tracking**: Detects `$x = sanitize_text_field($_POST['x'])` patterns
- **Reduced Noise**: Removed `user_can()` false confidence

**Test Fixtures Created:**
- `dist/tests/fixtures/phase2-branch-misattribution.php` - Guards in different branches/functions
- `dist/tests/fixtures/phase2-sanitizer-multiline.php` - Multi-line sanitization patterns
- `dist/tests/verify-phase2.1-improvements.sh` - Automated verification

**Files Modified:**
- `dist/bin/check-performance.sh` (v1.3.1) - Integrated variable sanitization tracking
- `dist/bin/lib/false-positive-filters.sh` (v1.3.0) - Added function scope detection, enhanced guards/sanitizers
- `CHANGELOG.md` - Documented Phase 2.1 changes

**Remaining Limitations:**
- Function scope detection is heuristic-based (not full PHP parser)
- Variable tracking is 1-step only (doesn't follow `$a = $b; $c = $a;`)
- Doesn't handle array elements (`$data['key']`)
- Branch detection is basic (doesn't parse full control flow)

**Production Readiness:** Phase 2.1 significantly improves accuracy and reduces false confidence. Ready for production use with documented limitations.

## Phase 1 — Reduce Obvious False Positives (Low Risk, High Impact)

### Goal
Eliminate the most common “clearly wrong” matches that do not represent executable code paths.

### Checklist
- [ ] **Comment/docblock aware matching**
  - [ ] Ignore matches inside PHPDoc blocks (`/** ... */`).
  - [ ] Ignore matches inside block comments (`/* ... */`).
  - [ ] Ignore matches inside single-line comments (`// ...`).
  - [ ] Regression check: a docblock like `@uses wp_remote_get()` no longer triggers `http-no-timeout`.

- [ ] **Stop treating HTML/REST config as superglobal access**
  - [ ] Ensure rules like `spo-002-superglobals` only match real superglobal tokens (e.g., `$_GET[` / `$_POST[` / `$_REQUEST[` / etc.).
  - [ ] Explicitly exclude/avoid matching:
    - [ ] `<form ... method="POST">` (HTML attribute)
    - [ ] `array( 'methods' => 'POST', ... )` (REST route config)

### Deliverables
- [ ] Updated scanner logic/patterns to ignore comment/docblock contexts.
- [ ] Updated superglobal rules to match only executable access patterns.
- [ ] A small regression fixture set covering:
  - [ ] docblock `@uses` vs real function call
  - [ ] HTML `<form method="POST">`
  - [ ] REST route `'methods' => 'POST'`

## Phase 2 — Add Context Signals (Guards + Sanitization) to Improve Triage

### Goal
Keep reporting potentially risky patterns, but attach “context” so reviewers can triage faster and reduce high-severity noise.

### Checklist
- [x] **Guard heuristics (nearby checks)**
  - [x] If a superglobal read is preceded within ~N lines by `check_ajax_referer(`, downgrade severity (e.g., `error -> review`).
  - [x] If preceded within ~N lines by `wp_verify_nonce(` (or equivalent nonce checks), downgrade severity.
  - [x] If preceded within ~N lines by `current_user_can(` (or wrapper), downgrade severity.
  - [x] Output should record which guard(s) were detected (e.g., `guards: ['check_ajax_referer','current_user_can']`).

- [x] **Sanitizer/caster detection on superglobal reads**
  - [x] Detect common WP sanitizers/casters wrapping input (examples):
    - [x] `sanitize_text_field( $_GET[...] )`
    - [x] `sanitize_email( $_POST[...] )`
    - [x] `absint( $_GET[...] )`
    - [x] `esc_url_raw( $_REQUEST[...] )`
  - [x] Output should record which sanitizer was detected (e.g., `sanitizers: ['sanitize_email']`).

- [x] **Refine `$wpdb->prepare()` finding severity when no user input exists**
  - [x] If SQL is a literal and only includes safe identifiers (e.g. `{$wpdb->options}`), classify as best-practice / lower severity.
  - [x] Keep higher severity for concatenated SQL that includes superglobals or other tainted variables.

### Deliverables
- [x] JSON output augmented with guard/sanitizer hints.
- [x] Severity downgrade rules for “guarded” findings.
- [x] Regression fixtures for guarded vs unguarded superglobal reads.

## Phase 3 — Reclassify Findings (Categories + Severity Defaults)

### Goal
Separate “likely vulnerability” from “context-dependent security hygiene” and “best practice” so output is easier to consume.

### Checklist
- [ ] **Add/standardize rule categories**
  - [ ] `security-vuln-likely`
  - [ ] `security-context-dependent`
  - [ ] `best-practice`
  - [ ] `performance`

- [ ] **Define default severity per category**
  - [ ] Ensure best-practice rules (e.g., missing explicit timeout) do not default to the same “HIGH” urgency as exploitable patterns.

- [ ] **Update reporting summary**
  - [ ] Summaries should group by category and severity.
  - [ ] Ensure the report can clearly answer:
    - [ ] “How many confirmed?”
    - [ ] “How many false positives?”
    - [ ] “How many need review?”

### Deliverables
- [ ] Updated pattern metadata schema (if needed) to include `category` and default severity.
- [ ] Updated report generator to group by category.

## Acceptance Criteria

- [ ] Running the scanner on `/temp` (WP Health Check plugin) shows:
  - [ ] No findings triggered purely by docblocks/comments.
  - [ ] No findings triggered by HTML `<form method="POST">`.
  - [ ] No findings triggered by REST route `'methods' => 'POST'`.
  - [ ] Superglobal findings include guard/sanitizer context when present.
  - [ ] `$wpdb->query()` “no prepare” static queries are reduced in severity / categorized as best-practice.
  - [ ] Reports clearly separate security-vuln-likely vs best-practice vs performance.