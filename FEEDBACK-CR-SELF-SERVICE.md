# WPCC Pattern Library — False Positive Review
**Source:** AI review of creditconnection2-self-service scan  
**Date:** 2026-03-23  
**Scan findings:** 99 total | **Estimated true positives after fixes:** ~40

---

## Action Items

### ✅ Fix Now — High Confidence, Low Effort

- [ ] **FIX `php-shell-exec-functions.json` — `exec-call` pattern matches `curl_exec()`**  
  **Pattern:** `exec[[:space:]]*\(` has no word boundary → matches `curl_exec(`.  
  **Fix:** Change to `\bexec[[:space:]]*\(` in the `exec-call` sub-pattern.  
  **File:** `dist/patterns/php-shell-exec-functions.json`  
  **FPs eliminated:** 8 (all CRITICAL — all were `curl_exec($curl)` calls)

- [ ] **FIX `php-dynamic-include.json` — WP-CLI bootstrap scripts flagged as LFI**  
  **Finding:** `check-user-meta.php:13` and `test-alternate-registry-id.php:24` — `$path` is iterated from a hardcoded static array, never user-controlled.  
  **Fix:** Add `*-user-meta.php`, `*-registry-id.php`, or more broadly `*/scripts/*` / `*/cli/*` to `exclude_files` in the pattern.  
  **File:** `dist/patterns/php-dynamic-include.json`  
  **FPs eliminated:** 2 (both CRITICAL)

---

### 🔍 Investigate Before Acting — Diagnosis Uncertain

- [ ] **INVESTIGATE "Direct superglobal manipulation" (~17 findings on `CURLOPT_POST`)**  
  **Reviewer claim:** `curl_setopt($curl, CURLOPT_POST, true)` is matched as superglobal manipulation.  
  **Our assessment:** The `spo-002-superglobals` pattern requires `$_` prefix in all branches — `CURLOPT_POST` cannot match it.  
  **Action:** Re-examine the actual line numbers in the scan log for these 17 findings. Determine which rule is actually firing and why. Do NOT apply the reviewer's suggested fix (`$_` anchoring) — it's already implemented.  
  **File:** `dist/patterns/spo-002-superglobal-manipulation.json` (likely not the culprit)

- [ ] **INVESTIGATE "Sanitized reads flagged as unsanitized" for `sanitize_text_field($_GET[...])`**  
  **Finding:** `class-cr-rest-api.php` and `class-cr-business-rest-api.php` — `sanitize_text_field($_GET['registry_id'])` being flagged.  
  **Our assessment:** `sanitize_` is already in `exclude_patterns` for `unsanitized-superglobal-read`. This is likely a **multiline case** — `$_GET` on its own line while the sanitizer wraps on another.  
  **Action:** Confirm by inspecting actual flagged lines. If multiline, document as a known structural limitation (grep is line-scoped; lookbehinds won't help here). If same-line, there's a bug in the exclude logic.  
  **File:** `dist/patterns/unsanitized-superglobal-read.json`

---

### 📋 Deferred — Valid Issues, Structural Effort Required

- [ ] **DEFERRED: Add admin-only hook whitelist for capability check false positives**  
  **Finding:** `credit-registry-forms.php:48` — `add_action('admin_notices', ...)` flagged for missing capability check. `admin_notices` only fires for authenticated admin users.  
  **Reviewer recommendation:** Whitelist inherently-admin-only hooks (`admin_notices`, `admin_init`, `admin_menu`, etc.)  
  **Our assessment:** Correct diagnosis. Not fixable with regex alone — requires a hook whitelist in the scanner logic. Downgrade severity to INFO as interim.  
  **Effort:** Low–Medium | **FPs eliminated:** 1 per occurrence

- [ ] **DEFERRED: Strengthen N+1 loop detection to verify lexical containment**  
  **Finding 1:** `check-user-meta.php:23` — `get_user_meta()` called sequentially for a single user, not inside a user loop.  
  **Finding 2:** `class-cr-business-rest-api.php:245` — single `get_user_meta()` re-read after processing.  
  **Reviewer recommendation:** Confirm the meta call is lexically inside a loop body (`{...}`), not just nearby by line count.  
  **Our assessment:** The scanner has `is_iterating_over_multiple_objects()` heuristics. These may be gaps in that logic. Review and tighten the "loop containment" check.  
  **Effort:** Medium | **FPs eliminated:** 2

---

### ✔️ No Action Required — Already Handled or Misdiagnosed

- [x] **SKIP — `isset()` exclusion for superglobal reads**  
  `isset\(` is already in `exclude_patterns` for `unsanitized-superglobal-read.json`. Reviewer's suggestion is already implemented.

- [x] **SKIP — `$_` prefix anchoring for superglobal manipulation**  
  All three sub-patterns in `spo-002-superglobals` already require `$_` prefix. The reviewer's suggested fix is already in place.

- [x] **SKIP — Sanitizer negative-lookbehind regex for `unsanitized-superglobal-read`**  
  The `exclude_patterns` list already handles same-line sanitizer wrapping. The multiline case is a structural grep limitation, not addressable by the proposed regex.

---

## Valid Issues Found (Not FPs — Tracker for Plugin Owner)

| # | File | Line | Issue | Risk |
|---|------|------|-------|------|
| 6 | `admin-test-page.php` | 191 | `$_GET['view_file']` used without `sanitize_file_name()`; `strpos($view_file, '..')` bypass-able via encoding | HIGH |
| 7 | `admin-test-page.php` | 145 | `$_GET['view_dir']` displayed with `esc_html()` before `sanitize_file_name()` on line 147 — safe but misordered | LOW (confusing) |
| 8 | `api-functions.php` | 1014 | `$_POST['force_refresh']` in AJAX handler — strict `=== 'true'` comparison limits injection, but verify nonce upstream | LOW–MEDIUM |

---

## Impact Summary

| Fix | File to Edit | Effort | FPs Eliminated |
|-----|-------------|--------|---------------|
| `\b` word boundary on `exec-call` | `php-shell-exec-functions.json` | 1 line | 8 |
| Add WP-CLI scripts to `exclude_files` | `php-dynamic-include.json` | 2 lines | 2 |
| Investigate superglobal 17-finding cluster | Scan log + `spo-002` | Investigation | Up to ~17 |
| Investigate multiline sanitizer FPs | Scan log + `unsanitized-superglobal-read` | Investigation | Up to ~20 |
| Admin-only hook whitelist | `check-performance.sh` | Medium | 1+ per scan |
| N+1 loop containment tightening | `check-performance.sh` | Medium | 2+ per scan |
