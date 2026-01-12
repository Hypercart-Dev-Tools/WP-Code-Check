# Phase 2 Quality Improvements (Critical)

**Created:** 2026-01-12
**Status:** Not Started
**Priority:** CRITICAL
**Blocks:** Phase 2 production deployment

## Context

Phase 2 implementation (v1.3.0) added guard and sanitizer detection with severity downgrading. However, the current implementation has **5 critical quality issues** that create false confidence and potential false negatives. These must be addressed before Phase 2 can be considered production-safe.

## Top 5 Critical Issues

### 1. Guard Misattribution (False Confidence)

**Problem:** `detect_guards()` is window-based and token-based. It doesn't prove the guard actually protects the specific read.

**Examples of False Positives:**
- Guard in different branch: `if ($condition) { wp_verify_nonce(...); } else { $x = $_POST['x']; }`
- Guard in different callback: Guard in one AJAX handler, read in another
- Guard checking different nonce/value: `wp_verify_nonce($_POST['nonce1'], ...)` but reading `$_POST['data']`
- Guard present but bypassable: Guard after the read, or in unreachable code

**Solution:**
- Scope guards to same function block using `get_function_scope_range()`
- Require guard BEFORE access in same block
- Detect common guard patterns: `if ( ! wp_verify_nonce(...) ) return;` or `wp_die()`
- Don't count guards in different branches or after the access

**Acceptance Criteria:**
- [ ] Guards scoped to same function using `get_function_scope_range()`
- [ ] Guards must appear BEFORE the superglobal access
- [ ] Guards in different branches not counted
- [ ] Guards after access not counted
- [ ] Test fixtures cover branch misattribution cases

---

### 2. Suppression Too Aggressive (False Negatives)

**Problem:** Current logic suppresses findings when "guards + sanitizers" are detected. Given heuristic limitations, this risks false negatives.

**Current Code:**
```bash
# PHASE 2: Skip if BOTH guards AND sanitizers are present (fully protected)
if [ -n "$guards" ] && [ -n "$sanitizers" ]; then
  # Fully protected: has nonce/capability check AND sanitization
  continue  # ← TOO AGGRESSIVE
fi
```

**Solution:**
- **Never suppress** - always emit a finding
- Mark as LOW/INFO severity when guards + sanitizers detected
- Add `"confidence": "low"` or `"status": "guarded"` to JSON
- Let reviewers decide if it's truly safe
- Gather corpus evidence before enabling suppression

**Acceptance Criteria:**
- [ ] Remove suppression logic (no `continue` for guards + sanitizers)
- [ ] Downgrade to LOW/INFO severity instead
- [ ] Add confidence/status field to JSON output
- [ ] Document that suppression requires corpus validation
- [ ] Test fixtures verify findings are still emitted

---

### 3. Single-Line Sanitizer Detection (Misses Safe Flows)

**Problem:** `detect_sanitizers()` only recognizes wrappers on the same line as the superglobal read. Misses common safe patterns.

**Missed Patterns:**
```php
// Pattern 1: Variable assignment
$x = sanitize_text_field($_GET['x']);
// ... later in function ...
echo $x;  // ← Scanner flags this as unsanitized

// Pattern 2: Multi-line sanitization
$data = $_POST['data'];
$data = sanitize_text_field($data);
use_data($data);  // ← Scanner doesn't know $data is sanitized
```

**Solution:**
- Implement basic taint propagation within function scope
- Track variable assignments: `$var = sanitize_*($_GET[...])`
- Mark variable as "sanitized" for rest of function
- Even 1-step variable assignment helps significantly
- Use `get_function_scope_range()` to limit scope

**Acceptance Criteria:**
- [ ] Detect sanitization in variable assignment: `$x = sanitize_text_field($_GET['x'])`
- [ ] Track sanitized variables within function scope
- [ ] Don't flag later uses of sanitized variables
- [ ] Test fixtures cover multi-line sanitization patterns
- [ ] Document limitations (only 1-step tracking, function-scoped)

---

### 4. `user_can()` Detection Too Noisy

**Problem:** Detecting `user_can()` in the prior window overcounts "guards" because it's broader and more variable than `current_user_can()`.

**Issues:**
- `user_can($user_id, 'cap')` requires user ID parameter - may not be current user
- Often used for checking OTHER users' capabilities, not access control
- Not always used in conditional guard context
- May just be present in code, not actually guarding the access

**Solution:**
- Tighten detection pattern for `user_can()`
- Require it to be used in conditional guard context: `if ( ! user_can(...) )`
- Consider removing `user_can()` from guard detection entirely
- Focus on `current_user_can()` which is more reliable
- Document why `user_can()` is excluded or limited

**Acceptance Criteria:**
- [ ] Tighten `user_can()` detection to require conditional context
- [ ] OR remove `user_can()` from guard detection
- [ ] Document decision and rationale
- [ ] Test fixtures cover `user_can()` edge cases
- [ ] Verify no false confidence from `user_can()` presence

---

### 5. Fixtures Don't Cover Branch Misattribution

**Problem:** Current fixture coverage is good for distance/order, but doesn't test branch misattribution.

**Missing Test Cases:**
```php
// Guard in different branch
if ($condition) {
    wp_verify_nonce($_POST['nonce'], 'action');
} else {
    $x = $_POST['x'];  // ← Should NOT be marked as guarded
}

// Guard in different function
function check_nonce() {
    wp_verify_nonce($_POST['nonce'], 'action');
}
function process_data() {
    $x = $_POST['x'];  // ← Should NOT be marked as guarded
}

// Guard checking different parameter
wp_verify_nonce($_POST['nonce1'], 'action1');
$data = $_POST['data2'];  // ← Different parameter, not protected

// Guard after access (already covered but needs emphasis)
$x = $_POST['x'];
wp_verify_nonce($_POST['nonce'], 'action');  // ← Too late
```

**Solution:**
- Add comprehensive branch misattribution fixtures
- Test guards in different if/else branches
- Test guards in different functions
- Test guards checking different parameters
- Test guards in unreachable code

**Acceptance Criteria:**
- [ ] Fixture: Guard in different if/else branch
- [ ] Fixture: Guard in different function
- [ ] Fixture: Guard checking different nonce parameter
- [ ] Fixture: Guard in unreachable code (after return)
- [ ] Verification script tests all branch cases
- [ ] Document expected behavior for each case

---

## Implementation Plan

### Phase 2.1: Fix Critical Issues (High Priority)
1. **Issue #2 (Suppression)** - Easiest to fix, highest risk
   - Remove suppression logic
   - Change to LOW/INFO severity
   - Add confidence field
2. **Issue #4 (user_can)** - Quick win
   - Tighten or remove `user_can()` detection
3. **Issue #5 (Fixtures)** - Foundation for testing
   - Add branch misattribution test cases

### Phase 2.2: Improve Accuracy (Medium Priority)
4. **Issue #1 (Guard Scoping)** - More complex
   - Scope guards to function
   - Require guard before access
   - Detect guard patterns
5. **Issue #3 (Taint Propagation)** - Most complex
   - Track variable assignments
   - 1-step taint propagation

### Phase 2.3: Validation (Before Production)
- Run against Health Check plugin
- Run against WooCommerce
- Compare before/after metrics
- Document false positive/negative rates
- Get user feedback on confidence levels

---

## Success Criteria

Before Phase 2 can be considered production-safe:
- [ ] All 5 critical issues addressed
- [ ] Comprehensive test fixtures cover all edge cases
- [ ] Verification script passes all tests
- [ ] No suppression without corpus validation
- [ ] Guard detection scoped to function
- [ ] Sanitizer detection handles variable assignments
- [ ] Documentation updated with limitations
- [ ] Real-world validation on 3+ plugins

---

## Notes

These improvements are **blocking** for Phase 2 production deployment. The current implementation provides value (context signals in JSON), but the severity downgrading and suppression logic needs refinement to avoid false confidence.

**Recommendation:** Ship Phase 2 with guard/sanitizer detection in JSON output, but **disable automatic severity downgrading** until these issues are resolved. Let users see the context signals and make their own decisions.

