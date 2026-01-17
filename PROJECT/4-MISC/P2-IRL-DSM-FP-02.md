# IRL: Direct Superglobal Manipulation (DSM) False Positives - Post Memory Loader Project Version

**Created:** 2026-01-17  
**Status:** Not Started   
**Priority:** P2  
**Rule:** `spo-002-superglobals` (Direct superglobal manipulation)

## Table of Contents

1. Project Summary
2. Phased Checklist (Track Progress Here)
3. Problem Statement
4. Current Behavior (Quick Scanner)
5. Observed False Positive Patterns
6. Goals and Success Metrics
7. Plan of Record
8. Implementation Details
9. Risks and Mitigations
10. Decision Points

## Project Summary

Reduce DSM false positives by ~5–20% while keeping the rule loud on genuine risk. The win is lowering scan failures and manual triage caused by guarded/sanitized patterns, without weakening security. This is realistic without a full AST: do a severity split in the quick scanner first, then optionally use the Golden Rules Analyzer (GRA) as a second-pass filter for edge cases.

## Phased Checklist (Track Progress Here)

Note for LLM: Always mark checklist items as progress is made.

- [ ] Phase 1: Define policy and heuristics (guarded vs unguarded DSM)
- [ ] Phase 2: Implement quick scanner refinements
- [ ] Phase 3: Benchmark results on representative plugins
- [ ] Phase 4: Prototype GRA SuperglobalsRule (optional)
- [ ] Phase 5: Decide on integration strategy and rollout

## Problem Statement

Real-world scans (e.g., Gravity Forms, WooCommerce add-ons) show the `spo-002-superglobals` rule is directionally correct but still produces roughly 5–20% false positives:

- Lines are flagged even when nonce checks and sanitization are present.
- Some flags are on bridge code or legacy patterns that are effectively acceptable risk.
- A few flags are contextually safe (e.g., admin-only, guarded, sanitized), but still fail the check.

We want to avoid turning DSM into a purely informational rule; it should still fail when:

- Superglobals are written or modified without guards, or
- Flow makes it difficult to reason about data provenance.

## Current Behavior (Quick Scanner)

The quick scanner implements DSM in `dist/bin/check-performance.sh` roughly as:

- Grep for superglobal writes/manipulation:
  - `unset($_GET/$_POST/$_REQUEST/$_COOKIE['...'])`
  - `$_GET/$_POST/$_REQUEST = ...`
  - `$_GET/$_POST/$_REQUEST/$_COOKIE['...'] = ...`
- Skip obvious comment lines and patterns that look like HTML/REST config.
- Look for security guards near the match using `detect_guards()`.
  - Examples: `check_admin_referer`, `wp_verify_nonce`, capability checks.
- Honor `should_suppress_finding` for per-file/project ignores.
- Record `guards` in the JSON finding and downgrade severity when guards exist, but still:
  - Mark the check as failed when any DSM instance is found.
  - Emit findings as `error` severity in JSON (with adjusted impact).

This keeps DSM highly visible but means guarded + sanitized DSM still contributes to failures and manual triage load.

## Observed False Positive Patterns

From real plugin scans (e.g., Gravity Forms, Hypercart Server Monitor MKII):

1. Nonce + capability guarded form handlers
   - Typical pattern:
     - `check_admin_referer()` and sometimes `current_user_can()` before touching `$_POST`.
     - Immediate sanitization via `absint`, `sanitize_text_field`, `sanitize_email`, `sanitize_key`, etc.
   - These are expected WordPress form-handling patterns.

2. Bridge or transport code
   - Code that moves values between `$_POST`, `$_REQUEST`, or internal arrays to satisfy older APIs.
   - Risk is lower when values are already sanitized or re-validated at the actual sink.

3. Project-specific wrappers
   - Helpers like `rgpost()`, `rgget()`, or framework-specific accessors that centralize sanitization.
   - DSM flags assignments around these wrappers even when the overall pattern is considered safe by project conventions.

4. Admin-only flows
   - DSM in code that only runs on `is_admin()` routes with additional capability checks.
   - Still worth surfacing but should not carry the same severity as public endpoint manipulations.

5. JS/AJAX requests inside PHP views
   - Patterns like jQuery `$.ajax({ type: 'POST', data: { action: '...' } })` embedded in PHP admin views.
   - These are front-end request descriptors (JavaScript), not PHP superglobal writes, but can currently be misclassified as DSM.
   - Concrete example: Hypercart Server Monitor MKII admin tabs (`tab-manual-test.php`, `tab-email.php`, `tab-debug.php`) where `type: 'POST'` lines are flagged by `spo-002-superglobals`.

## Goals and Success Metrics

- Reduce DSM false positives by ~5–20% without reducing detection of unguarded writes.
- Decrease scan failures caused by guarded/sanitized patterns.
- Preserve visibility by keeping guarded DSM findings in output (lower severity).

## Plan of Record

Primary path (recommended):

1. Refine heuristics in the quick scanner (no AST) to split severity and failure criteria.
2. Benchmark the impact on a small, representative plugin set.
3. If still noisy, add an optional GRA SuperglobalsRule for second-pass filtering.

## Implementation Details

### Phase 1: Define Policy and Heuristics

- Split DSM into two categories at the check level:
  - Unguarded DSM: fails the check.
  - Guarded DSM: recorded as warning/info, does not fail the check.
- Add sanitizer detection for writes:
  - If a context window contains both guard and sanitizer, downgrade further.
- Strengthen non-PHP filtering (make JS/AJAX-in-PHP a first-class case):
  - Tighten `is_html_or_rest_config` (or equivalent helper) so DSM ignores JS snippets and REST config lines entirely.
  - Explicitly treat jQuery/JS AJAX blocks inside PHP views (e.g., `$.ajax({ type: 'POST', data: { action: 'hsm_*' } })`) as **out of scope for DSM**; they should instead be handled by JS-facing rules.
- Add project-level allowlist pattern:
  - Allow per-project suppression of known bridge code, e.g., `spo-002-superglobals-bridge`.

### Phase 2: Implement Quick Scanner Refinements

- Update `detect_guards()` and add `detect_sanitizers()`.
- Adjust DSM check failure logic to trigger only on unguarded DSM.
- Update JSON output to include `guarded`, `sanitized`, and `severity` fields as appropriate.

### Phase 3: Benchmark Results

- Use 3 to 5 representative plugins (e.g., Gravity Forms, WooCommerce extensions, Hypercart Server Monitor MKII).
- Measure:
  - DSM finding counts before vs after changes.
  - Share of findings now classified as guarded/sanitized.
  - Any missed unguarded DSM instances.
  - Specific regression: Hypercart Server Monitor MKII should report **zero** DSM findings originating from JS admin views once non-PHP filtering is in place.

### Phase 4 (Optional): GRA SuperglobalsRule

- Add `SuperglobalsRule` to `dist/bin/experimental/golden-rules-analyzer.php`.
- Classify occurrences as error, warning, info based on guards and sanitizers.
- Add CLI option `--rule=superglobals` and JSON output for integration.

### Phase 5: Integration and Rollout

- Decide whether GRA integration is:
  - Default for DSM, or
  - Opt-in via `--enable-golden-rules-dsm` or project config.
- Document the policy in README or scanner docs if needed.

## Risks and Mitigations

- Risk: Guard detection misses edge cases and allows risky writes.
  - Mitigation: Keep unguarded detection strict; do not suppress without explicit guard + sanitizer.
- Risk: Added heuristics become inconsistent across projects.
  - Mitigation: Use project-level allowlists and document how to configure them.
- Risk: GRA integration increases runtime cost.
  - Mitigation: Make it opt-in or only run when DSM hits exist.

## Decision Points

- After Phase 3: If FP reduction is at least 5–10% and unguarded detection remains strong, ship Option A.
- After Phase 4: If GRA meaningfully reduces noise without performance issues, consider optional integration.
