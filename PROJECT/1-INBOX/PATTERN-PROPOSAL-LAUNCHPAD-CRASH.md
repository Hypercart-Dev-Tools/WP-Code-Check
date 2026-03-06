# Launchpad Crash-Derived WPCC Pattern Proposal

**Created:** 2026-03-06
**Status:** Not Started
**Priority:** Medium

## Problem/Request
Review the lessons in `PROJECT/4-MISC/P1-LAUNCHPAD-CRASH.md` and turn them into a practical plan for adding preventive anti-pattern coverage to WPCC.

## Context
- The Local/Launchpad incident is valuable as an IRL debugging narrative, but it is too environment-specific to become a single scanner rule.
- WPCC is already capable of reliability-oriented detection via JSON patterns, heuristic rules, and validator-backed checks.
- The most reusable lessons are architectural and API-usage smells, not the exact PHP-FPM/Local failure chain.
- Nearby precedent already exists in the pattern library:
  - `dist/patterns/db-query-in-constructor.json`
  - `dist/patterns/wp-json-html-escape.json`
  - `CONTRIBUTING.md`
  - `dist/tests/irl/_AI_AUDIT_INSTRUCTIONS.md`

## Direct Recommendation
Do **not** add a single anti-pattern called "Launchpad crash" or anything that implies WPCC can statically predict this exact segfault path.

Instead, split the incident into **generalized reliability rules** that improve portability, reduce bootstrap fragility, and standardize WordPress-safe coding patterns.

## Proposed Pattern Candidates

### 1) `nonstandard-wordpress-translation-alias`
**Recommendation:** Ship first  
**Category:** `reliability`  
**Severity:** `MEDIUM`  
**Viability:** High  
**Practicality:** High

**Goal**
- Detect use of `_()` in WordPress PHP where standard WP i18n helpers should be used instead (`__()`, `esc_html__()`, `esc_attr__()`).

**Why this belongs in WPCC**
- Strong signal, low implementation cost, easy remediation.
- Promotes WordPress-native conventions and reduces ambiguity in theme/plugin code.

**Detection approach**
- Start with a direct or heuristic PHP pattern for `\b_\s*\(`.
- Exclude known non-WordPress/vendor contexts if needed.

**Primary caution**
- Frame as a maintainability/reliability rule, not a claim that `_()` universally causes crashes.

### 2) `bootstrap-query-or-hydration-at-file-scope`
**Recommendation:** Pilot second  
**Category:** `reliability` or `performance`  
**Severity:** `HIGH`  
**Viability:** High  
**Practicality:** Medium

**Goal**
- Detect expensive or dependency-sensitive work happening at include/bootstrap time, especially in settings/bootstrap files.

**Candidate signals**
- `WP_Query`, `get_posts`, `get_users`, `get_terms`
- `wc_get_orders`, `wc_get_products`
- `$wpdb->get_*`, `$wpdb->query`
- remote calls or hydration logic executed at file scope

**Why this belongs in WPCC**
- This is the strongest architectural lesson from the incident.
- Closely aligned with the existing `db-query-in-constructor` rule: too much work too early in the lifecycle.

**Detection approach**
- Validator-backed/contextual rule rather than simple grep.
- Focus on file-scope execution and bootstrap/settings contexts to keep noise manageable.

**Primary caution**
- False positives are possible in intentionally bootstrapped config files; mitigation notes and baselining will matter.

### 3) `translation-helper-in-unsafe-attribute-context`
**Recommendation:** Experimental / later  
**Category:** `reliability`  
**Severity:** `LOW` or `MEDIUM`  
**Viability:** Medium  
**Practicality:** Medium-Low

**Goal**
- Detect translation/helper misuse in IDs, classes, inline styles, or other attribute-like render contexts where plain or context-appropriate escaped output is expected.

**Why consider it**
- The Launchpad incident repeatedly narrowed around render-path helper misuse.
- Could catch subtle context confusion before it spreads.

**Detection approach**
- Heuristic only after gathering several IRL examples.
- Keep disabled by default until signal quality is proven.

**Primary caution**
- High false-positive risk if shipped too early.

## What Should Not Be Added
- No rule named around a single environment or stack combination.
- No claim that WPCC can detect a PHP-FPM segfault chain from static code alone.
- No overly narrow ACF/Launchpad-only signature unless it becomes a private team rule outside the core WPCC library.

## Rollout Checklist

### Phase 1: `nonstandard-wordpress-translation-alias`
- [ ] Confirm the Launchpad incident will be decomposed into generalized rules, not a single crash detector
- [ ] Approve `nonstandard-wordpress-translation-alias` as the first implementation target
- [ ] Create pattern JSON (`dist/patterns/nonstandard-wordpress-translation-alias.json`)
- [ ] Create test fixtures with bad/good examples
  - [ ] `_()` call inside an `acf_add_local_field()` label array (the exact IRL crash shape)
  - [ ] Generic standalone `_('some string')` call as a baseline case
  - [ ] Valid `__()` / `esc_html__()` / `esc_attr__()` calls that should not flag
- [ ] Add remediation guidance explaining preferred WordPress i18n helpers
- [ ] Register pattern and verify tests pass
- [ ] Update CHANGELOG

### Phase 2: `bootstrap-query-or-hydration-at-file-scope`
- [ ] Decide whether this belongs under `reliability` or `performance`
- [ ] Prototype detection rule (evaluate reusing `context-pattern-check.sh` validator)
- [ ] Validate against 2-3 IRL repositories before enabling broadly
- [ ] Tune scope to reduce false positives in legitimate bootstrap/config files
- [ ] Create pattern JSON, fixtures, and remediation guidance
- [ ] Register pattern and verify tests pass
- [ ] Update CHANGELOG

### Phase 3: `translation-helper-in-unsafe-attribute-context`
- [ ] Gather at least 2-3 IRL examples of attribute/render helper misuse
- [ ] Decide whether signal quality justifies shipping
- [ ] If yes: create pattern JSON (disabled by default), fixtures, and remediation guidance
- [ ] Register pattern and verify tests pass
- [ ] Update CHANGELOG

## Notes
- Best first value comes from educational + standards-enforcing rules, not forensic crash prediction.
- If the team wants an immediate internal safeguard, a private rule set for local themes/settings code could be practical before promoting anything into the shared WPCC library.
- Follow-up implementation work should update pattern JSON, fixtures, registry expectations, and changelog entries together.