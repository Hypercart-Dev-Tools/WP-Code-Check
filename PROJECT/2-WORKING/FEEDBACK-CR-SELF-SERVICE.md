# WPCC Pattern Library — False Positive Review
**Source:** AI review of creditconnection2-self-service scan  
**Date:** 2026-03-23  
**Scan findings:** 99 total | **Estimated true positives after fixes:** ~40

---

## Action Items

### ✅ Fix Now — High Confidence, Low Effort

- [x] **FIX `php-shell-exec-functions.json` — `exec-call` pattern matches `curl_exec()`** ✅ *Fixed in commit 740ba08*  
  **Pattern:** `exec[[:space:]]*\(` has no word boundary → matches `curl_exec(`.  
  **Fix:** Change to `\bexec[[:space:]]*\(` in the `exec-call` sub-pattern.  
  **File:** `dist/patterns/php-shell-exec-functions.json`  
  **FPs eliminated:** 8 (all CRITICAL — all were `curl_exec($curl)` calls)

- [x] **`php-dynamic-include.json` — WP-CLI bootstrap scripts no longer flagged as LFI** ✅ *Resolved in follow-up commit*  
  **Finding:** `check-user-meta.php:13` and `test-alternate-registry-id.php:24` — `$path` is iterated from a hardcoded static array, never user-controlled.  
  **Attempted fix (740ba08 — insufficient):** Added `wp-load` to `exclude_patterns`, but the actual matched line is `require_once $path;` — it does not contain `wp-load`.  
  **Proper fix:** Added new `exclude_if_file_contains` capability to the simple pattern runner and `dist/bin/check-performance.sh`. When a matched file's content contains any string listed in the new `exclude_if_file_contains` JSON array, all matches in that file are suppressed. Added `"wp eval-file"` to `php-dynamic-include.json` under this key — both WP-CLI scripts have this string in their docblock comment.  
  **Files changed:** `dist/bin/check-performance.sh` (runner feature), `dist/patterns/php-dynamic-include.json` (new exclusion key)  
  **FPs eliminated:** 2 (both CRITICAL)

---

### ✅ Implemented After Investigation

- [x] **FIX `spo-002-superglobals` inline grep corruption** ✅ *Implemented in scanner*  
  **Scan log findings:** 31 total spo-002 findings. 16 are `CURLOPT_POST`/`CURLOPT_POSTFIELDS`, 2 are JS `type: 'POST'` strings, 4 are `$_SERVER` reads (SERVER not in the pattern alternation), 1 is the only legitimate finding (line 1014).  
  **Root cause confirmed:** The inline bash spo-002 grep (check-performance.sh ~line 3723) uses a **double-quoted string with `\\$_`**. In bash double-quotes, `\\` → `\` and then `$_` starts expansion of the bash `$_` special variable (last argument of the previous command). At runtime, `$_` contains the last argument from `text_echo "▸ Direct superglobal manipulation..."` — an ANSI-coloured string including `[HIGH]`. This corrupts the entire ERE pattern, causing it to match incorrectly in a non-deterministic way.  
  **The JSON pattern itself (`\$_(GET|POST...)`) is correct** — tested via `load_pattern` + direct grep, it does NOT match CURLOPT_POST. The bug is entirely in the inline bash code, not the JSON pattern file.  
  **Fix implemented:** Changed the inline grep at line 3723 from double-quoted to single-quoted string, which prevents `$_` expansion. This is a **scanner bug, not a pattern bug**. The JSON file did not need to change.  
  **File to fix:** `dist/bin/check-performance.sh` ~line 3723  
  **Verified impact:** `spo-002-superglobals` dropped from **31 → 3** findings in the follow-up scan. Remaining 3 are legitimate review cases: `$_POST['force_refresh']`, `unset($_GET['activate'])`, and `$_GET['view_errors']` conditional logic.

- [x] **FIX simple runner ignoring `exclude_patterns` / `exclude_files`** ✅ *Implemented in scanner*  
  **Scan log findings:** 30 `unsanitized-superglobal-read` findings. Confirmed FPs include: `class-cr-rest-api.php:90`, `class-cr-rest-api.php:98`, `class-cr-rest-api.php:843`, `class-cr-business-rest-api.php:103`, `class-cr-business-rest-api.php:138`, `class-cr-business-rest-api.php:857` — all are same-line ternary patterns like `isset($_GET['x']) ? sanitize_text_field($_GET['x']) : ''`.  
  **Root cause confirmed:** The simple pattern runner (`check-performance.sh` ~line 5970) runs `cached_grep -E "$pattern_search"` but **never applies `exclude_patterns` from the JSON definition**. The `exclude_patterns` array in `unsanitized-superglobal-read.json` (which includes `sanitize_`, `isset\(`, `esc_`, etc.) is loaded but silently ignored. The legacy inline checks manually pipe through `grep -v` to apply exclusions; the JSON-driven simple runner does not.  
  **This is NOT a multiline issue** — the flagged lines all have the sanitizer wrapper on the same line. The exclusion simply isn't being applied at all by the simple runner.  
  **Additional FPs from same root cause:** `clear-person-cache.php:34`, `setup-user-registry-id.php:23-24`, `set-account-type.php:26-27` — all properly guarded `$_POST` reads with nonce verification on the same line.  
  **Fix implemented:** The simple pattern runner now parses both `exclude_patterns` and `exclude_files` from the JSON pattern file and filters matches before JSON findings are added. This improves behavior across all JSON-defined `grep`/`simple` patterns, not just `unsanitized-superglobal-read`.  
  **File to fix:** `dist/bin/check-performance.sh` ~line 5970 (simple pattern runner grep call)  
  **Verified impact:** `unsanitized-superglobal-read` dropped from **30 → 19** findings in the follow-up scan. The remaining 19 are mostly other classes of reads that still require separate tuning, especially the dedicated `unsanitized-superglobal-isset-bypass` rule.

---

### 📋 Deferred — Investigate Further Before Implementing

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

| Fix | File to Edit | Effort | FPs Eliminated | Status |
|-----|-------------|--------|---------------|--------|
| `\b` word boundary on `exec-call` | `php-shell-exec-functions.json` | 1 line | 8 | ✅ Done (740ba08) |
| `exclude_if_file_contains` + `wp eval-file` | `check-performance.sh` + `php-dynamic-include.json` | Medium | 2 verified | ✅ Done |
| Single-quote inline spo-002 grep | `check-performance.sh` ~L3723 | 1 line | 28 verified | ✅ Done |
| Apply `exclude_patterns` in simple runner | `check-performance.sh` ~L5970 | Medium | 11 verified | ✅ Done |
| Admin-only hook whitelist | `check-performance.sh` | Medium | 1+ per scan | 📋 Deferred |
| N+1 loop containment tightening | `check-performance.sh` | Medium | 2+ per scan | 📋 Deferred |

**Latest measured totals:** 99 findings before scanner fixes → **88 findings after first round** → **86 findings after dynamic-include fix**.
